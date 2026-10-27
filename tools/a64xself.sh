#!/usr/bin/env bash
# a64xself —— 墨语言写的 AArch64 汇编器，**跑在 ARM64 上**再产出 AArch64 系统
#
# 闭环：
#   examples/a64as.mo ──mo2x cfs-aarch64──> ARM64 静态 ELF（汇编器）
#                                              │ 运行在 Unicorn 模拟的 ARM64 CPU
#   tools/a64sys.s    ─────────────────────────┘
#                                              ↓
#                                          sys64.arm.elf
#                                              ↓ kern64run.py（裸机：无 Linux/libc）
#                                     MO-A64 BOOT / SUM=5050 OK / FIB=55 OK ...
#
# 判据为什么这么定：
#   ① 「ARM64 产物 == x86 产物」只能证明**交叉后端没算错**，证明不了算得对
#      —— 把源码里一条指令编码改坏，两端会**一起**改坏，md5 照样相同。
#      所以必须再有 ②：把 ARM64 产物拿去裸机跑，输出逐行比对。
#   ② 之外还要有 ③：ARM64 端必须**真的读了文件**（--preload 缺了就静默变成
#      空输入，程序照样可能"成功"）。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
# 🔴 bin/mo2x **不在 make boot 链上**。开发目录里它早就编好了看不出来，
# 全新环境解包后 bin/ 是空的，android_native.sh 直接报
# "bin/mo2x: No such file or directory" —— 而 a64xself 的判据第一条就
# 挂在这里，看上去像"交叉编译失败"。v1.154「$(MO2X) 从未定义」的同类。
[ -x bin/mo2x ] || make mo2x > /dev/null 2>&1
W=/tmp/a64xself
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1"; echo "    得到: $2"; echo "    想要: $3"; fi; }

echo "a64xself:"

# ── ① 构建：墨语言 → ARM64 静态 ELF（无 libc）──
# 🔴 先删产物：构建失败时旧 ELF 会残留，然后"执行"跑的是上一版
# —— 判据全绿，等于什么都没验（v1.153「源码干净 ≠ 产物干净」）。
ARM_ELF=$W/a64as.arm64
rm -f $ARM_ELF
bash tools/android_native.sh examples/a64as.mo $ARM_ELF > $W/build.log 2>&1
chk "ARM64 构建（cfs-aarch64）" "$([ -f $ARM_ELF ] && echo yes || echo no)" "yes"
[ -f $ARM_ELF ] || { echo "  构建失败："; cat $W/build.log; echo "$PASS 通过 / $FAILN 失败"; exit 1; }
chk "e_machine = AArch64(183)" "$(python3 -c "
import struct
d=open('$ARM_ELF','rb').read(); print(struct.unpack_from('<H',d,18)[0])")" "183"

# ── ② x86-64 参照端：同一份源码，本机真跑 ──
X86=$W/x86; mkdir -p $X86
cp lib/*.mo $X86/ && cp examples/a64as.mo $X86/test.mo
( cd $X86 && $ROOT/bin/moc > /dev/null 2>&1 )
chk "x86 端编译" "$([ -f $X86/out.elf ] && echo yes || echo no)" "yes"
[ -f $X86/out.elf ] || { echo "$PASS 通过 / $FAILN 失败"; exit 1; }
( cd $X86 && ./out.elf $ROOT/tools/a64sys.s $W/sys64.x86.elf > $W/as.x86.log 2>&1 )
chk "x86 端汇编退出码" "$?" "0"
chk "x86 端产出非空" "$([ -s $W/sys64.x86.elf ] && echo yes || echo no)" "yes"

# ── ③ ARM64 端：在模拟的 ARM64 CPU 上跑同一个汇编器 ──
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 600 python3 $ROOT/tools/armrun.py $ARM_ELF /in.s /out.elf \
    --preload /in.s=$ROOT/tools/a64sys.s \
    --extract /out.elf=$W/sys64.arm.elf > $W/run.log 2>&1
chk "ARM64 端执行" "$([ -s $W/sys64.arm.elf ] && echo yes || echo no)" "yes"

# 两端 stdout 必须一致（"114 insns, 4163 data bytes, 23 labels"）
X86LOG=$(grep -a "insns" $W/as.x86.log)
ARMLOG=$(grep -a "insns" $W/run.log)
chk "两端统计输出一致" "$ARMLOG" "$X86LOG"
# 非空转守卫：上面若两边都是空串会"相等"，这里确保真有内容
chk "统计输出非空" "$([ -n "$X86LOG" ] && echo yes || echo no)" "yes"

# ── ④ 两端产物逐字节相同 ──
if [ -s $W/sys64.arm.elf ] && [ -s $W/sys64.x86.elf ]; then
  A=$(md5sum < $W/sys64.x86.elf | cut -d' ' -f1)
  B=$(md5sum < $W/sys64.arm.elf | cut -d' ' -f1)
  chk "两端产物 md5 相同" "$B" "$A"
  chk "产物大小" "$(stat -c %s $W/sys64.arm.elf)" "$(stat -c %s $W/sys64.x86.elf)"
  # 🔴 单独校验 ARM64 端产物的 e_machine。
  # 两端同源，源码里写错 e_machine 会让两端**一起**错、md5 照样相同 ——
  # 这一层专门盯住它（它不依赖模拟器，比对的是产物本身的字节）。
  chk "ARM64 产物 e_machine = 183" "$(python3 -c "
import struct
d=open('$W/sys64.arm.elf','rb').read(); print(struct.unpack_from('<H',d,18)[0])")" "183"
else
  FAILN=$((FAILN+2)); echo "✗ 至少一端没有产物，跳过 md5 比对"
fi

# ── ⑤ ARM64 端产出的系统，在**裸机**上真跑（无 Linux/libc）──
# 这一层才是"算得对"的证据：只比 md5 的话，两端一起错也照样相同。
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 300 python3 $ROOT/tools/kern64run.py $W/sys64.arm.elf --steps 100000 > $W/bare.log 2>&1
BARE=$(grep -v "^---" $W/bare.log | grep -v '^$')
chk "ARM64 产物在裸机上跑出正确输出" "$BARE" "MO-A64 BOOT
SUM=5050 OK
FIB=55 OK
MEM OK
IMM OK"

# ── ⑥ 负例：坏输入，ARM64 端必须报错而不是静默产出 ──
printf '.text\n_start:\n\tcmp x0, #5050\n\tret\n' > $W/bad.s
rm -f $W/bad.arm.elf
PYTHONPATH=${MO_PYLIBS:-/data/workspace/pylibs} \
timeout 300 python3 $ROOT/tools/armrun.py $ARM_ELF /in.s /bad.elf \
    --preload /in.s=$W/bad.s > $W/bad.log 2>&1
chk "负例：越界立即数被拒绝（无产物）" "$([ -s $W/bad.arm.elf ] && echo yes || echo no)" "no"
grep -aq "out of range" $W/bad.log
chk "负例：报错信息含 out of range" "$?" "0"

echo "$PASS 通过 / $FAILN 失败"
[ $FAILN -eq 0 ]
