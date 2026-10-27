#!/usr/bin/env bash
# a64exectest —— 自举 aarch64 的 **ELF 加载器**验证：运行内核之外的程序
#
# 判据分八层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出两个 ELF            抓"根本没产出"
#   ② 用户 ELF **不在**内核镜像里         抓"其实链接进了内核，加载是演的"
#   ③ 用户 ELF 头部字段（独立用 python 读） 抓"链接器 --base 没生效"
#   ④ 端到端裸机执行：逐行输出             抓"加载了但跑错"
#   ⑤ 模拟器诊断计数 svc / eret           抓"走了别的路径、碰巧也对"
#   ⑥ 篡改用户 ELF 的一个字节 → 输出随之变  抓"其实没从文件读"
#   ⑦ 八个负例必须给出**八个不同的错误码**  抓"校验被跳过 / 统一返回 -1"
#   ⑧ 不给 initrd 必须报错                抓"内核自己内嵌了一份用户程序"
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64exectest
rm -rf $W && mkdir -p $W
PASS=0; FAILN=0; SKIP=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAILN=$((FAILN+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi; }

# ── 编译汇编器与链接器 ──
cp lib/*.mo $W/
cp examples/a64as.mo $W/test.mo
cd $W && rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "汇编器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64as.elf
cp $ROOT/examples/a64ld.mo $W/test.mo
rm -f out.elf && $ROOT/bin/moc > /dev/null 2>&1
chk "链接器编译" "$([ -f out.elf ] && echo yes || echo no)" "yes"
cp out.elf $W/a64ld.elf

# ── ① 两个镜像 ──
./a64as.elf -r $ROOT/tools/a64exec/main.s $W/main.o > $W/as1.log 2>&1
./a64ld.elf $W/kern.elf $W/main.o > $W/ld1.log 2>&1
chk "内核链接" "$([ -f $W/kern.elf ] && echo yes || echo no)" "yes"
./a64as.elf -r $ROOT/tools/a64exec/user.s $W/user.o > $W/as2.log 2>&1
# 用户程序链接到 0x40200000（用户区）；内核默认 0x40000000
./a64ld.elf --base 1075838976 $W/user.elf $W/user.o > $W/ld2.log 2>&1
chk "用户链接" "$([ -f $W/user.elf ] && echo yes || echo no)" "yes"

# ── ② 用户程序不在内核镜像里 ──
python3 - "$W" <<'PY'
import sys, os
w = sys.argv[1]
k = open(os.path.join(w, "kern.elf"), "rb").read()
u = open(os.path.join(w, "user.elf"), "rb").read()
bad = []
if b"U1\n\x00" in k:
    bad.append("内核镜像里出现了用户字符串")
# 用户 text 的第一个 4 字节指令字若在内核里出现，说明是同一份代码
uw = u[120:124]
if uw in k:
    bad.append("用户首条指令出现在内核里")
open(os.path.join(w, "indep.txt"), "w").write("\n".join(bad))
PY
chk "用户程序独立于内核" "$(cat $W/indep.txt | tr -d '\n')" ""

# ── ③ 头部字段（不读链接器日志，独立解析）──
python3 - "$W" <<'PY'
import sys, os, struct
w = sys.argv[1]
e = open(os.path.join(w, "user.elf"), "rb").read()
def h16(o): return struct.unpack_from("<H", e, o)[0]
def h64(o): return struct.unpack_from("<Q", e, o)[0]
f = []
f.append("entry=%s" % hex(h64(24)))
f.append("type=%d" % h16(16))
f.append("machine=%d" % h16(18))
off = h64(32)
pt, fl = struct.unpack_from("<II", e, off)
o, v, p, fs, ms, al = struct.unpack_from("<QQQQQQ", e, off + 8)
f.append("ptype=%d" % pt)
f.append("vaddr=%s" % hex(v))
f.append("memsz_gt_filesz=%d" % (1 if ms > fs else 0))
open(os.path.join(w, "hdr.txt"), "w").write("\n".join(f))
PY
chk "用户 entry 在用户区" "$(grep '^entry=' $W/hdr.txt)" "entry=0x40200000"
chk "用户 e_type=ET_EXEC" "$(grep '^type=' $W/hdr.txt)" "type=2"
chk "用户 e_machine=aarch64" "$(grep '^machine=' $W/hdr.txt)" "machine=183"
chk "用户程序头是 PT_LOAD" "$(grep '^ptype=' $W/hdr.txt)" "ptype=1"
chk "用户 p_vaddr 在用户区" "$(grep '^vaddr=' $W/hdr.txt)" "vaddr=0x40200000"
chk "bss 存在（memsz>filesz）" "$(grep '^memsz_gt_filesz=' $W/hdr.txt)" "memsz_gt_filesz=1"

run() {  # run <outfile> [initrd] —— 返回 0 表示模拟器跑起来了
    local ird="$2"
    python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 \
        --initrd "$ird" --steps 3000000 > "$1" 2> "$1.err"
}

# ── ④ 端到端输出 ──
run $W/out.txt $W/user.elf@0x40410000
chk "启动横幅" "$(grep -c '^MO-EXEC$' $W/out.txt)" "1"
chk "用户字符串" "$(grep -c '^U1$' $W/out.txt)" "1"
chk "用户算出 5050" "$(grep -c '^5050$' $W/out.txt)" "1"
chk "bss 已清零" "$(grep -c '^0$' $W/out.txt)" "1"
chk "用户读内核被拦" "$(grep -c '^PF2$' $W/out.txt)" "1"
chk "用户正常收尾" "$(grep -c '^D$' $W/out.txt)" "1"
chk "退出码 7" "$(grep -c '^EXIT 7$' $W/out.txt)" "1"
chk "内核未被污染" "$(grep -c '^V OK$' $W/out.txt)" "1"

# ── ⑤ 模拟器诊断计数 ──
# 6 次 svc = 3 次 write + 2 次 putdec + 1 次 exit
# 7 次 eret = 6 次 svc 返回 + 1 次 abort 返回
chk "svc 次数" "$(grep -o 'svc=[0-9]*' $W/out.txt.err)" "svc=6"
chk "eret 次数" "$(grep -o 'eret=[0-9]*' $W/out.txt.err | tail -1)" "eret=7"

# ── ⑥ 篡改用户 ELF → 输出随之变 ──
python3 - "$W" <<'PY'
import sys, os, struct
w = sys.argv[1]
e = bytearray(open(os.path.join(w, "user.elf"), "rb").read())
i = e.find(b"U1\n\x00")
assert i > 0, "找不到用户字符串"
open(os.path.join(w, "stroff.txt"), "w").write(str(i))
# (a) 改字符串首字节
a = bytearray(e); a[i] = ord('V')
open(os.path.join(w, "user_str.elf"), "wb").write(bytes(a))
# (b) 改入口：跳过前 5 条指令（ldaddr 4 条 + bl uputs），直接从求和开始
b = bytearray(e)
struct.pack_into("<Q", b, 24, 0x40200014)
open(os.path.join(w, "user_entry.elf"), "wb").write(bytes(b))
PY
run $W/out_str.txt $W/user_str.elf@0x40410000
chk "改字符串后输出随之变" "$(grep -c '^V1$' $W/out_str.txt)" "1"
chk "改字符串后不再有原串" "$(grep -c '^U1$' $W/out_str.txt)" "0"
run $W/out_entry.txt $W/user_entry.elf@0x40410000
chk "改入口后跳过首条输出" "$(grep -c '^U1$' $W/out_entry.txt)" "0"
chk "改入口后仍算出 5050" "$(grep -c '^5050$' $W/out_entry.txt)" "1"

# ── ⑦ 八个负例，八个不同的码 ──
python3 - "$W" <<'PY'
import sys, os, struct
w = sys.argv[1]
e = bytearray(open(os.path.join(w, "user.elf"), "rb").read())
def wname(n, b):
    open(os.path.join(w, "bad_%s.elf" % n), "wb").write(bytes(b))
a = bytearray(e); a[0] = 0x00;                       wname("magic", a)
a = bytearray(e); struct.pack_into("<H", a, 16, 1);  wname("type", a)
a = bytearray(e); struct.pack_into("<H", a, 18, 62); wname("mach", a)
a = bytearray(e); struct.pack_into("<H", a, 54, 64); wname("phes", a)
a = bytearray(e); struct.pack_into("<H", a, 56, 0);  wname("phnum", a)
a = bytearray(e); struct.pack_into("<Q", a, 24, 0x40000000); wname("entry", a)
a = bytearray(e)
off = struct.unpack_from("<Q", a, 32)[0]
struct.pack_into("<Q", a, off + 40, 0x1000000);      wname("seg", a)
a = bytearray(e)
struct.pack_into("<I", a, off, 0);                   wname("noload", a)
PY
for c in 1:magic 2:type 3:mach 4:phes 5:phnum 6:entry 7:seg 8:noload; do
    n=${c%%:*}; t=${c##*:}
    run $W/bad_$t.txt $W/bad_$t.elf@0x40410000
    chk "负例 $t 报 E-$n" "$(grep -c "^E-$n\$" $W/bad_$t.txt)" "1"
    chk "负例 $t 没有运行用户" "$(grep -c '^U1$' $W/bad_$t.txt)" "0"
done

# ── ⑧ 不给 initrd：内核读到全 0 的内存，必须报"没有镜像" ──
# 这条是反向判据：若内核镜像里内嵌了一份用户程序，不给 initrd 也会照样跑通。
python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1     --steps 3000000 > $W/out_no.txt 2> $W/out_no.txt.err
chk "无 initrd 时报错" "$(grep -c '^E-1$' $W/out_no.txt)" "1"
chk "无 initrd 时不运行用户" "$(grep -c '^U1$' $W/out_no.txt)" "0"

echo "a64exectest: $PASS 通过 / $FAILN 失败 / $SKIP 跳过"
if [ "$FAILN" != "0" ]; then exit 1; fi
exit 0
