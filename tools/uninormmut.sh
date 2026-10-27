#!/usr/bin/env bash
# uninormmut —— lib/uninorm.mo 的变异验证
#
# 证明 tests/146_uninorm.mo 的 19 项断言**非空转**。
# 其中 M1、M2 是**本轮真实存在过的两个缺陷**（被这个新写的测试抓出来的），
# 不是凭空设计的：
#   M1 un_reorder 拿循环变量 k 当退出标志 → 插入位置永远落到段首，
#      U+1E14 的 NFD 从 0045 0304 0300 变成 0045 0300 0300（0304 被覆盖）
#   M2 ccc==0 分支不尝试 Hangul 组合 → Hangul 音节**分解对、重组失败**，
#      U+AC00 的 NFC 仍是 1100 1161
#
# 还原机制同 tools/acmut.sh：备份在 build/、trap 还原、开工前自愈、
# 写入后立即读回校验（沙盒有写入可见性延迟，本轮在 acmut 上栽过）。
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/lib/uninorm.mo"
BAK="$HERE/build/uninormmut.bak"
MOC="$HERE/bin/moc"
PY="$HERE/build/uninormmut_pairs.py"
mkdir -p "$HERE/build"

cat > "$PY" <<'PYEOF'
import sys
P = [
 ("M1 排序：拿循环变量 k 当退出标志(本轮真缺陷)",
  "                    let ins: i64 = i + 1;\n                    while k >= i + 1 {\n                        ck = UN_D1[k];\n                        if un_ccc(ck) <= un_ccc(cj) {\n                            ins = k + 1;\n                            k = i;\n                        }\n                        if k >= i + 1 {\n                            UN_D1[k + 1] = ck;\n                            k = k - 1;\n                            ins = k + 1;\n                        }\n                    }\n                    UN_D1[ins] = cj;",
  "                    let go: i64 = 1;\n                    while k >= i + 1 {\n                        if go == 1 {\n                            ck = UN_D1[k];\n                            if un_ccc(ck) > un_ccc(cj) {\n                                UN_D1[k + 1] = ck;\n                                k = k - 1;\n                            }\n                            if un_ccc(ck) <= un_ccc(cj) { go = 0; }\n                        }\n                        if go == 0 { k = i; }\n                    }\n                    UN_D1[k + 1] = cj;"),
 ("M2 ccc==0 分支不尝试 Hangul 组合(本轮真缺陷)",
  "            let hv: i64 = 0 - 1;\n            if last >= 0 { hv = un_hangul_pair(UN_OUT[last], c); }\n            if hv >= 0 {\n                UN_OUT[last] = hv;\n            }\n            if hv < 0 {",
  "            let hv: i64 = 0 - 1;\n            if hv >= 0 {\n                UN_OUT[last] = hv;\n            }\n            if hv < 0 {"),
 ("M3 递归分解只做一级",
  "                    if dep >= 1 { UN_NREC = UN_NREC + 1; }",
  "                    if dep >= 1 { UN_NREC = UN_NREC + 1; }\n                    if dep >= 1 { d = 0 - 1; }"),
 ("M4 排序判据用 < 而非 <=(不稳定)",
  "                        if un_ccc(ck) <= un_ccc(cj) {\n                            ins = k + 1;\n                            k = i;\n                        }",
  "                        if un_ccc(ck) < un_ccc(cj) {\n                            ins = k + 1;\n                            k = i;\n                        }"),
 ("M5 输出集合里丢掉未组合的记号",
  "            if hv < 0 {\n                UN_OUT[o] = c;\n                last = o;\n                o = o + 1;\n            }",
  "            if hv < 0 {\n                UN_OUT[o] = c;\n                o = o + 1;\n            }"),
]
mode = sys.argv[1]
path = sys.argv[2]
s = open(path).read()
if mode == "heal":
    n = 0
    for name, good, bad in P:
        if bad in s:
            s = s.replace(bad, good); n += 1
    if n:
        open(path, "w").write(s)
    print("HEALED %d" % n)
elif mode == "count":
    print(len(P))
elif mode == "names":
    for i, p in enumerate(P):
        print("%d\t%s" % (i, p[0]))
elif mode == "apply":
    idx = int(sys.argv[3])
    name, good, bad = P[idx]
    if good not in s:
        print("ANCHOR-MISS"); sys.exit(3)
    open(path, "w").write(s.replace(good, bad, 1))
    reread = open(path).read()
    if bad not in reread:
        print("WRITE-INVISIBLE"); sys.exit(4)
    print("OK")
elif mode == "check":
    left = sum(1 for _, _, bad in P if bad in s)
    print("LEFT %d" % left)
    sys.exit(1 if left else 0)
PYEOF

restore() { [ -f "$BAK" ] && cp "$BAK" "$SRC"; return 0; }
trap restore EXIT INT TERM

run_test() {
    local dir="$HERE/build/uninormmut_run"
    rm -rf "$dir" && mkdir -p "$dir"
    cp "$HERE"/lib/*.mo "$dir/" 2>/dev/null
    cp "$HERE/tests/146_uninorm.mo" "$dir/test.mo"
    ( cd "$dir" && timeout 60 "$MOC" test.mo out.elf ) >/dev/null 2>&1
    if [ ! -f "$dir/out.elf" ]; then echo "COMPILE-FAIL"; return 2; fi
    ( cd "$dir" && timeout 30 ./out.elf ) 2>&1 | tail -1
    return ${PIPESTATUS[0]}
}

echo "=== uninormmut ==="
python3 "$PY" heal "$SRC"
cp "$SRC" "$BAK"

echo -n "基线（必须全过）: "
out=$(run_test); rc=$?
echo "$out (rc=$rc)"
if [ "$rc" != "0" ]; then echo "❌ 基线就没过，变异结果无意义"; exit 1; fi

N=$(python3 "$PY" count "$SRC")
all=1
i=0
while [ "$i" -lt "$N" ]; do
    name=$(python3 "$PY" names "$SRC" | awk -F'\t' -v k="$i" '$1==k{print $2}')
    r=$(python3 "$PY" apply "$SRC" "$i")
    sync
    if [ "$r" != "OK" ]; then
        echo "⚠ $name 变异未生效（$r）"; all=0
    else
        out=$(run_test); rc=$?
        if [ "$rc" != "0" ]; then echo "✓ $name 变异被捕获 -> $out (rc=$rc)"
        else echo "✗ $name 未被捕获 -> $out (rc=$rc)"; all=0; fi
    fi
    restore
    i=$((i+1))
done

python3 "$PY" check "$SRC" || all=0
[ -f "$BAK" ] || { echo "❌ 备份缺失"; all=0; }
if [ "$all" = "1" ]; then echo "=== 全部变异被捕获 ==="; else echo "=== 有变异未被捕获 ==="; fi
[ "$all" = "1" ]
