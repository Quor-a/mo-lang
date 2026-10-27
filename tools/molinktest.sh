#!/bin/bash
# molinktest —— 墨语言自写的静态链接器与 GNU ld 的等价性测试
#
# 为什么必须和 ld 对比：
#   链接错误最常见的表现不是"报错"，而是"程序照常跑、值却是错的"
#   （全局地址搬错位置、重定位差 4 字节、段越界……）。
#   只测"链接出来的程序能跑"根本测不出这些。
#   所以这里对同一批 .o，分别用
#       bin/molink        （墨语言自己写的，不调 ld、不调 as）
#       tools/molink.sh   （走 GNU ld + mocrt.s）
#   链接并运行，逐字节比对 stdout 与退出码。
#
# 这不是"能跑就行"的测试：任何一处不一致都直接失败。

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MO=$(cd "$HERE/.." && pwd)
cd "$MO"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# 需要 stdin 或会长时间运行的不放进来
CASES="bubble_sort calc sort freq grep plot bignum mclass"

if [ ! -x bin/molink ]; then
    echo "构建 bin/molink ..."
    ./bin/moc tools/molink.mo -nostdlib bin/molink || { echo "❌ bin/molink 构建失败"; exit 1; }
fi

for c in $CASES; do
    src="examples/$c.mo"
    [ -f "$src" ] || continue

    # 1) 编译成 .o
    if ! ./bin/moc "$src" -nostdlib -c "$TMP/$c.o" > "$TMP/$c.cc" 2>&1; then
        echo "  [skip] $c：编译失败"
        continue
    fi

    # 2) 墨语言自链接
    if ! ./bin/molink "$TMP/$c.o" -o "$TMP/$c.self" > "$TMP/$c.sl" 2>&1; then
        echo "❌ $c：自链接失败"
        cat "$TMP/$c.sl"
        FAIL=$((FAIL + 1))
        continue
    fi

    # 3) GNU ld 链接
    if ! bash tools/molink.sh "$TMP/$c.o" -o "$TMP/$c.ld" -nostdlib > "$TMP/$c.ll" 2>&1; then
        echo "  [skip] $c：ld 链接失败"
        continue
    fi

    # 4) 分别运行（限时，避免死循环卡住）
    timeout 10 "$TMP/$c.self" > "$TMP/$c.s.out" 2>&1 < /dev/null
    SRC_RC=$?
    timeout 10 "$TMP/$c.ld" > "$TMP/$c.l.out" 2>&1 < /dev/null
    LD_RC=$?

    if [ "$SRC_RC" != "$LD_RC" ]; then
        echo "❌ $c：退出码不一致  自链接=$SRC_RC  ld=$LD_RC"
        FAIL=$((FAIL + 1))
        continue
    fi
    if ! diff -q "$TMP/$c.s.out" "$TMP/$c.l.out" > /dev/null; then
        echo "❌ $c：输出不一致"
        diff "$TMP/$c.s.out" "$TMP/$c.l.out" | head -5
        FAIL=$((FAIL + 1))
        continue
    fi

    echo "  ✓ $c  退出码=$SRC_RC  输出 $(wc -c < "$TMP/$c.s.out") 字节"
    PASS=$((PASS + 1))
done

# ---- 变异验证：证明上面的比对真的有区分力 ----
# 把 .data 的基址改成一个错的地址（0x20000000），重新编译链接器，
# 再链接同一个 .o —— 如果跑出来的结果还和原来一模一样，
# 说明前面的"输出一致"根本没在检验任何东西。
echo ""
echo "变异验证：把 .data 基址改错，结果必须与原版不同"
sed 's/var DATA_ADDR: i64 = 268435456;/var DATA_ADDR: i64 = 536870912;/' \
    tools/molink.mo > "$TMP/molink_bad.mo"
./bin/moc "$TMP/molink_bad.mo" -nostdlib "$TMP/molink_bad" > /dev/null 2>&1
if [ ! -x "$TMP/molink_bad" ]; then
    echo "  ⚠ 变异版编译失败，无法做变异验证"
else
    ./bin/moc examples/mclass.mo -nostdlib -c "$TMP/mclass.o" > /dev/null 2>&1
    ./bin/molink "$TMP/mclass.o" -o "$TMP/mclass.ok" > /dev/null 2>&1
    "$TMP/molink_bad" "$TMP/mclass.o" -o "$TMP/mclass.bad" > /dev/null 2>&1
    timeout 5 "$TMP/mclass.ok" > "$TMP/mclass.ok.out" 2>&1 < /dev/null
    OK_RC=$?
    timeout 5 "$TMP/mclass.bad" > "$TMP/mclass.bad.out" 2>&1 < /dev/null
    BAD_RC=$?
    SAME=0
    if [ "$OK_RC" = "$BAD_RC" ]; then
        if diff -q "$TMP/mclass.ok.out" "$TMP/mclass.bad.out" > /dev/null; then SAME=1; fi
    fi
    if [ "$SAME" = "1" ]; then
        echo "❌ 变异版与原版结果完全相同 —— 前面的比对没有区分力"
        FAIL=$((FAIL + 1))
    else
        echo "  ✓ 变异版表现不同（原版退出码 $OK_RC / 变异版 $BAD_RC），比对有效"
        PASS=$((PASS + 1))
    fi
fi

echo ""
echo "molinktest: $PASS 项通过，$FAIL 项失败"
if [ "$FAIL" != "0" ]; then exit 1; fi
exit 0
