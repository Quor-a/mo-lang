#!/usr/bin/env bash
# a64pkgtest —— 自举 aarch64 的 **包管理与执行环境**验证
#
# 与 a64exec 的差别：initrd 里放的不是赤裸 ELF，而是**包** —— 一串可打印
# 字节 `MOPK1|<name>|<ver>|<len>|<hex>|<sum>`。内核解开它、算校验和、对不上
# 就拒绝执行，对上了才把 payload（用户 ELF）加载运行。
#
# 判据分八层，缺一层就漏掉不同类别的缺陷：
#   ① 汇编 + 链接产出两个 ELF             抓"根本没产出"
#   ② 用户 ELF **不在**内核镜像里          抓"其实链接进了内核，装包是演的"
#   ③ 用户 ELF 头部字段（独立用 python 读） 抓"链接器 --base 没生效"
#   ④ 端到端：逐行输出 + PK n= 等于文件长度 抓"解包长度错 / 加载了但跑错"
#   ⑤ 模拟器诊断计数 svc / eret            抓"走了别的路径、碰巧也对"
#   ⑥ 篡改包 → 六个**不同**的错误码        抓"校验被跳过 / 统一返回 -1"
#   ⑦ 改 payload 内容并同步改 sum → 输出随之变 抓"其实没从包里读"
#   ⑧ 不给 initrd 必须报错                 抓"内核自己内嵌了一份用户程序"
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/a64pkgtest
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
./a64as.elf -r $ROOT/tools/a64pkg/main.s $W/main.o > $W/as1.log 2>&1
./a64ld.elf $W/kern.elf $W/main.o > $W/ld1.log 2>&1
chk "内核链接" "$([ -f $W/kern.elf ] && echo yes || echo no)" "yes"
./a64as.elf -r $ROOT/tools/a64pkg/user.s $W/user.o > $W/as2.log 2>&1
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
if u[120:124] in k:
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
f = ["entry=%s" % hex(h64(24)), "type=%d" % h16(16), "machine=%d" % h16(18),
     "size=%d" % len(e)]
off = h64(32)
pt, fl = struct.unpack_from("<II", e, off)
o, v, p, fs, ms, al = struct.unpack_from("<QQQQQQ", e, off + 8)
f += ["ptype=%d" % pt, "vaddr=%s" % hex(v), "memsz_gt_filesz=%d" % (1 if ms > fs else 0)]
open(os.path.join(w, "hdr.txt"), "w").write("\n".join(f))
PY
chk "用户 entry 在用户区" "$(grep '^entry=' $W/hdr.txt)" "entry=0x40200000"
chk "用户 e_type=ET_EXEC" "$(grep '^type=' $W/hdr.txt)" "type=2"
chk "用户 e_machine=aarch64" "$(grep '^machine=' $W/hdr.txt)" "machine=183"
chk "用户程序头是 PT_LOAD" "$(grep '^ptype=' $W/hdr.txt)" "ptype=1"
chk "用户 p_vaddr 在用户区" "$(grep '^vaddr=' $W/hdr.txt)" "vaddr=0x40200000"
chk "bss 存在（memsz>filesz）" "$(grep '^memsz_gt_filesz=' $W/hdr.txt)" "memsz_gt_filesz=1"

# ── 打包：由 python **独立**实现，不读内核日志 ──
# 内核能跑通本身就证明它的 FNV-1a 与这里的算法一致；判据不照抄内核输出。
python3 - "$W" <<'PY'
import sys, os
w = sys.argv[1]
def fnv(b):
    h = 2166136261
    for x in b:
        h ^= x
        h = (h * 16777619) & 0xFFFFFFFF
    return h
p = open(os.path.join(w, "user.elf"), "rb").read()
pkg = "MOPK1|app|1|%d|%s|%d" % (len(p), p.hex(), fnv(p))
open(os.path.join(w, "pkg.txt"), "w").write(pkg)
open(os.path.join(w, "size.txt"), "w").write(str(len(p)))
PY
USZ=$(cat $W/size.txt)

run() {  # run <outfile> <initrd 参数...>
    local out="$1"; shift
    python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 \
        "$@" --steps 3000000 > "$out" 2> "$out.err"
}

# ── ④ 端到端 ──
run $W/out.txt --initrd $W/pkg.txt@0x40410000
chk "启动横幅" "$(grep -c '^MO-PKG$' $W/out.txt)" "1"
chk "解包长度等于文件大小" "$(grep -c "^PK n=$USZ\$" $W/out.txt)" "1"
chk "用户字符串" "$(grep -c '^U1$' $W/out.txt)" "1"
chk "用户算出 5050" "$(grep -c '^5050$' $W/out.txt)" "2"
# 两个 0：create 返回的 id、以及 bss（内核加载前把用户区污染成 0xA5A5A5A5，
# 不清零这里会是 2779163050）。两者都是 0，所以按**个数**断言。
chk "id 与 bss 都是 0" "$(grep -c '^0$' $W/out.txt)" "2"
chk "写入 8 字节" "$(grep -c '^8$' $W/out.txt)" "2"
chk "文件数 1" "$(grep -c '^1$' $W/out.txt)" "1"
chk "用户读文件内容区被拦" "$(grep -c '^PF2$' $W/out.txt)" "1"
chk "用户正常收尾" "$(grep -c '^D$' $W/out.txt)" "1"
chk "退出码 7" "$(grep -c '^EXIT 7$' $W/out.txt)" "1"
chk "内核未被污染" "$(grep -c '^V OK$' $W/out.txt)" "1"

# ── ⑤ 模拟器诊断计数 ──
# 14 次 svc = 2 次 write + 7 次 putdec + 1 create + 1 write-file + 1 read-file
#            + 1 count + 1 exit
# 15 次 eret = 14 次 svc 返回 + 1 次 abort 返回
chk "svc 次数" "$(grep -o 'svc=[0-9]*' $W/out.txt.err)" "svc=14"
chk "eret 次数" "$(grep -o 'eret=[0-9]*' $W/out.txt.err | tail -1)" "eret=15"

# ── ⑥ 六个负例，六个不同的码 ──
python3 - "$W" <<'PY'
import sys, os
w = sys.argv[1]
def fnv(b):
    h = 2166136261
    for x in b:
        h ^= x
        h = (h * 16777619) & 0xFFFFFFFF
    return h
p = open(os.path.join(w, "user.elf"), "rb").read()
hx = p.hex()
def save(n, s): open(os.path.join(w, "bad_%s.txt" % n), "w").write(s)
# -1 magic
save("magic", "MOPK2|app|1|%d|%s|%d" % (len(p), hx, fnv(p)))
# -2 段数不对（少一个 |ver|）
save("nseg", "MOPK1|app|%d|%s|%d" % (len(p), hx, fnv(p)))
# -3 hex 长度与 len 不符（砍掉最后两个 hex 字符）
save("hlen", "MOPK1|app|1|%d|%s|%d" % (len(p), hx[:-2], fnv(p)))
# -4 非法 hex 字符
save("hexchar", "MOPK1|app|1|%d|%s|%d" % (len(p), "zz" + hx[2:], fnv(b"\x00"*0) ))
# -5 校验和不符（改 payload 但沿用旧 sum）
q = bytearray(p); q[0] = 0x00
save("sum", "MOPK1|app|1|%d|%s|%d" % (len(q), bytes(q).hex(), fnv(p)))
# -6 payload 超出容量（2000 > 1024）
big = b"\x00" * 2000
save("big", "MOPK1|app|1|%d|%s|%d" % (len(big), big.hex(), fnv(big)))
PY
for c in 1:magic 2:nseg 3:hlen 4:hexchar 5:sum 6:big; do
    n=${c%%:*}; t=${c##*:}
    run $W/bad_$t.out --initrd $W/bad_$t.txt@0x40410000
    chk "负例 $t 报 BAD $n" "$(grep -c "^BAD $n\$" $W/bad_$t.out)" "1"
    chk "负例 $t 没有运行用户" "$(grep -c '^U1$' $W/bad_$t.out)" "0"
done

# ── ⑦ 改 payload 内容并同步改 sum → 输出随之变 ──
python3 - "$W" <<'PY'
import sys, os
w = sys.argv[1]
def fnv(b):
    h = 2166136261
    for x in b:
        h ^= x
        h = (h * 16777619) & 0xFFFFFFFF
    return h
p = bytearray(open(os.path.join(w, "user.elf"), "rb").read())
i = p.find(b"U1\n\x00")
assert i > 0, "找不到用户字符串"
p[i] = ord('V')
open(os.path.join(w, "str.txt"), "w").write(
    "MOPK1|app|1|%d|%s|%d" % (len(p), bytes(p).hex(), fnv(bytes(p))))
PY
run $W/out_str.txt --initrd $W/str.txt@0x40410000
chk "改 payload 后输出随之变" "$(grep -c '^V1$' $W/out_str.txt)" "1"
chk "改 payload 后不再有原串" "$(grep -c '^U1$' $W/out_str.txt)" "0"
chk "改 payload 后仍能算 5050" "$(grep -c '^5050$' $W/out_str.txt)" "2"

# ── ⑧ 不给 initrd ──
python3 $ROOT/tools/kern64run.py $W/kern.elf --mmu 1 --exc 1 \
    --steps 3000000 > $W/out_no.txt 2> $W/out_no.txt.err
chk "无 initrd 时报错" "$(grep -c '^BAD 1$' $W/out_no.txt)" "1"
chk "无 initrd 时不运行用户" "$(grep -c '^U1$' $W/out_no.txt)" "0"

echo "a64pkgtest: $PASS 通过 / $FAILN 失败 / $SKIP 跳过"
if [ "$FAILN" != "0" ]; then exit 1; fi
exit 0
