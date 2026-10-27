#!/usr/bin/env bash
# mokern64 —— **自举内核跑在 ARM64 上**，再产出 ARM64 裸机内核
#
# 闭环（四段，每一段都是下一段的输入）：
#
#   examples/mokern.mo ──mo2x cfs-aarch64 + zig──> ARM64 静态 ELF（内核生成器）
#                                                     │ 跑在 Unicorn 模拟的 ARM64 CPU
#                                                     ↓ 写文件
#                                              kern.arm.elf（3414 字节）
#                                                     ↓ kern64run.py（裸硬件：无 Linux/libc/安卓）
#                                    MO-KERN / U OK / PF2 / DONE
#
# 与 mokerntest.sh 的差别：mokerntest 只证明"墨语言能造内核"（生成器跑在 x86-64）。
# 本脚本证明的是**这条能力在目标架构上也成立** —— 生成器自己是 ARM64 程序，
# 造出来的也是 ARM64 内核。
#
# 判据为什么这么定：
#   ① 「两端产物 md5 相同」只能证明交叉后端**没算错**，证明不了算得对 ——
#      源码里一条编码写坏，两端会**一起**写坏，md5 照样相同。所以必须再有
#      ⑤：把 ARM64 端的产物拿去裸机跑，输出逐行比对。
#   ② ⑤ 之外还要有 ⑥：关掉 MMU 后 PF2 必须消失 —— 否则"隔离生效"可能只是
#      程序自己的功劳（比如用户程序压根没去读那块内存）。
#   ③ ③ 是防"静默空转"：--extract 写错路径时 ARM64 端照样退出码 0，
#      只是没有产物；这里显式断言"两边都真产出了非空文件"。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
# 🔴 bin/mo2x **不在 make boot 链上**。开发目录里早就编好了看不出来，
# 全新环境解包后 bin/ 是空的，第一项判据就会挂成"交叉编译失败"（v1.154）。
# 反过来，若 bin/ 里已经有能用的 mo2x 就不要重建 —— 重建会撞上编译器容量
# 缺陷（tools/mo2x.mo 编不出来，报 no main function），那是另一回事，
# 见 docs/mokern64.md「已知限制」。
if [ ! -x bin/mo2x ]; then
    echo "bin/mo2x 不存在，尝试构建…"
    echo "（若失败于 'no main function'，是编译器容量缺陷，见 docs/mokern64.md）"
    make mo2x > /dev/null 2>&1
fi

W=/tmp/mokern64w
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1"; echo "    得到: $2"; echo "    想要: $3"; fi; }

echo "mokern64:"

# ── ① 交叉编译：墨语言 → ARM64 静态 ELF（生成器自己变成手机架构程序）──
# 🔴 先删产物：构建失败时旧 ELF 残留，后面的"执行"跑的是上一版 —— 判据全绿，
# 等于没验（v1.153「源码干净 ≠ 产物干净」）。
GEN=$W/mokern.arm64
rm -f $GEN
bash tools/android_native.sh examples/mokern.mo $GEN > $W/build.log 2>&1
chk "ARM64 构建（cfs-aarch64）" "$([ -f $GEN ] && echo yes || echo no)" "yes"
[ -f $GEN ] || { echo "  构建失败："; cat $W/build.log; echo "$PASS 通过 / $FAILN 失败"; exit 1; }
chk "生成器 e_machine = AArch64(183)" "$(python3 -c "
import struct
d=open('$GEN','rb').read(); print(struct.unpack_from('<H',d,18)[0])")" "183"
chk "生成器静态链接（无 .interp）" "$(python3 -c "
d=open('$GEN','rb').read(); print('yes' if b'.interp' not in d[:4096] else 'no')")" "yes"

# ── ② 参照端：同一份源码在 x86-64 上真跑 ──
X86=$W/x86; mkdir -p $X86
cp lib/*.mo $X86/ && cp examples/mokern.mo $X86/test.mo
( cd $X86 && $ROOT/bin/moc > /dev/null 2>&1 )
chk "x86 端编译" "$([ -f $X86/out.elf ] && echo yes || echo no)" "yes"
[ -f $X86/out.elf ] || { echo "$PASS 通过 / $FAILN 失败"; exit 1; }
( cd $X86 && ./out.elf $W/kern.x86.elf > $W/gen.x86.log 2>&1 )
chk "x86 端退出码" "$?" "0"

# ── ③ ARM64 端：在模拟的 ARM64 CPU 上跑同一个生成器 ──
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 900 python3 $ROOT/tools/armrun.py $GEN /out.elf \
    --extract /out.elf=$W/kern.arm.elf > $W/gen.arm.log 2>&1
chk "ARM64 端执行" "$([ -s $W/kern.arm.elf ] && echo yes || echo no)" "yes"
grep -qi "UC_ERR\|Traceback" $W/gen.arm.log && {
    echo "✗ ARM64 端执行报错"; tail -5 $W/gen.arm.log; FAILN=$((FAILN+1)); }

# 两端 stdout 必须一致（"mokern: 817 insns, 26 data bytes"）
X86LOG=$(grep -a "insns" $W/gen.x86.log)
ARMLOG=$(grep -a "insns" $W/gen.arm.log)
chk "两端统计输出一致" "$ARMLOG" "$X86LOG"
# 非空转守卫：两边都是空串也会"相等"
chk "统计输出非空" "$([ -n "$X86LOG" ] && echo yes || echo no)" "yes"

# ── ④ 两端产物逐字节相同 ──
if [ -s $W/kern.arm.elf ] && [ -s $W/kern.x86.elf ]; then
  chk "两端产物 md5 相同" \
      "$(md5sum < $W/kern.arm.elf | cut -d' ' -f1)" \
      "$(md5sum < $W/kern.x86.elf | cut -d' ' -f1)"
  # 🔴 单独校验 ARM64 端产物的 e_machine：两端同源，源码里写错 e_machine
  # 会让两端**一起**错、md5 照样相同。这一层比对的是产物自身的字节，
  # 不依赖模拟器。
  chk "ARM64 产物 e_machine = 183" "$(python3 -c "
import struct
d=open('$W/kern.arm.elf','rb').read(); print(struct.unpack_from('<H',d,18)[0])")" "183"
  chk "产物非空（> 1024 字节）" \
      "$([ $(stat -c %s $W/kern.arm.elf) -gt 1024 ] && echo yes || echo no)" "yes"

  # 🔴 ④b 静态解析 ARM64 产物里的三条页表描述符，断言 AP 依次 01/01/00。
  # 这一层是执行层的补充，不是替代：M5（不建内核私有块描述符）让
  # EL0 访问变成**转换错误**，而内核的 abort 处理不区分两者，照样打印
  # PF2 —— 裸机输出逐字不变，19 项全过。**执行层对 M5 完全失明**，
  # 只有静态解析能抓到（它比对的是镜像自身的字节，不是它跑出什么）。
  # 顺带 M2（AP=00 改成 01）在这里也直接现形，不必等执行。
  AP=$(python3 - "$W/kern.arm.elf" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
n=struct.unpack_from('<Q',d,96)[0]
code=d[120:120+n]
vals={}; cur=0
for i in range(len(code)//4):
    w=struct.unpack_from('<I',code,i*4)[0]
    if (w & 0xFF800000) == 0xD2800000 and (w & 31) == 9:      # movz x9, #imm16
        cur = (w>>5) & 0xFFFF
    elif (w & 0xFF800000) == 0xF2800000 and (w & 31) == 9:    # movk x9, #imm16, lsl #hw
        hw=(w>>21)&3; cur |= ((w>>5)&0xFFFF) << (16*hw)
    elif (w & 0xFFC00000) == 0xF9000000:                       # str xN, [xM, #off]
        rn=(w>>5)&31; rt=w&31; off=((w>>10)&0xFFF)*8
        if rn==14 and rt==9: vals[off]=cur
aps=[(vals[o]>>6)&3 if o in vals else -1 for o in (0,8,16)]
print(" ".join(str(x) for x in aps), "n=%d"%len(vals))
PY
)
  chk "三条页表描述符的 AP 依次 01/01/00" "${AP% *}" "1 1 0"
  chk "页表 block 描述符条数 = 3" "$(echo "$AP" | grep -o 'n=[0-9]*' | cut -d= -f2)" "3"
else
  FAILN=$((FAILN+3)); echo "✗ 至少一端没有产物，跳过产物比对"
fi

# ── ⑤ ARM64 端造出的内核，在**裸硬件**上真启动（无 Linux / libc / 安卓）──
# 这一层才是"算得对"的证据：只比 md5 的话，两端一起错也照样相同。
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 300 python3 $ROOT/tools/kern64run.py $W/kern.arm.elf --mmu 1 --exc 1 > $W/on.txt 2>&1
ON=$(grep -v "^---\|^$" $W/on.txt)
chk "ARM64 产物在裸机上启动" "$ON" "$(printf 'MO-KERN\nU OK\nPF2\nDONE')"

# 内核状态必须是内核自己设的，而不是模拟器给的默认值
chk "内核栈 = 内核自己设的 sp_el1" \
    "$(grep -o 'ksp=0x[0-9a-f]*' $W/on.txt | head -1)" "ksp=0x40401000"
chk "用户栈 = 内核自己设的 sp_el0" \
    "$(grep -o 'usp=0x[0-9a-f]*' $W/on.txt | head -1)" "usp=0x40010000"
chk "svc 次数（write + exit）" \
    "$(grep -o 'svc=[0-9]*' $W/on.txt | head -1)" "svc=2"
chk "eret 次数（下 EL0 + 两次返回）" \
    "$(grep -o 'eret=[0-9]*' $W/on.txt | head -1)" "eret=3"

# ── ⑥ 反向：关掉 MMU，页表隔离必须失效 ──
# 没有这条，"PF2 出现"可能只是用户程序碰巧读到坏数据，而不是被页表拦下。
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 300 python3 $ROOT/tools/kern64run.py $W/kern.arm.elf --mmu 0 --exc 1 > $W/off.txt 2>&1
chk "关 MMU 后不应有 PF2" "$(grep -c '^PF2$' $W/off.txt)" "0"
chk "关 MMU 后仍有 U OK"  "$(grep -c '^U OK$' $W/off.txt)" "1"

# ── ⑦ 负例：不给输出文件名，ARM64 端必须报错退出而不是静默"成功" ──
rm -f $W/none.elf
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 300 python3 $ROOT/tools/armrun.py $GEN \
    --extract /out.elf=$W/none.elf > $W/none.log 2>&1
chk "负例：缺参数时不产出" "$([ -s $W/none.elf ] && echo yes || echo no)" "no"

echo "$PASS 通过 / $FAILN 失败"
[ $FAILN -eq 0 ]
