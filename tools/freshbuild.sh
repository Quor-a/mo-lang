#!/bin/bash
# 全新环境可构建性验证：只带源码，不带任何构建产物
#
# 为什么需要它：bin/ 与 build/ 只装构建产物，git 不跟踪空目录。
# 开发者本机永远有 bin/，所以"从零 checkout 出来 make 直接失败"这类缺陷
# 在本机永远发现不了 —— 而且 ld 的报错是 "cannot open output file"，
# 落在链接器上而不是"目录缺失"，很迷惑。这里在临时目录里模拟全新环境。
#
# 三条断言：
#   1. 临时目录确实没有 bin/（否则这条测试就是空转）
#   2. make boot 在全新环境下成功
#   3. 全新构建出的 bin/moc 与源目录的逐字节一致（可复现构建）
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
pass(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

REF=bin/moc
if [ ! -f "$REF" ]; then
  echo "freshbuild: 需要 bin/moc 作为参照，先跑 make 构建"; exit 1
fi
REFMD5=$(md5sum "$REF" | cut -d' ' -f1)

WORK=/tmp/mofresh
rm -rf "$WORK" && mkdir -p "$WORK"
for d in src tools tests lib examples docs; do
  [ -d "$d" ] && cp -r "$d" "$WORK/"
done
for f in Makefile build.sh verify_bootstrap.sh VERSION CHANGELOG.md mo.toml; do
  [ -f "$f" ] && cp "$f" "$WORK/"
done

if [ -e "$WORK/bin" ]; then
  fail "临时目录不该有 bin/，这条测试会空转"
else
  pass "临时目录确实没有 bin/"
fi

if ( cd "$WORK" && make boot >/tmp/mofresh.log 2>&1 ); then
  pass "全新环境 make boot 成功"
else
  fail "全新环境 make boot 失败："
  tail -20 /tmp/mofresh.log | sed 's/^/      /'
fi

if [ -f "$WORK/bin/moc" ]; then
  NEWMD5=$(md5sum "$WORK/bin/moc" | cut -d' ' -f1)
  if [ "$NEWMD5" = "$REFMD5" ]; then
    pass "全新构建产物与 bin/moc 逐字节一致（$NEWMD5）"
  else
    fail "产物不一致：新=$NEWMD5 参照=$REFMD5"
  fi
else
  fail "未产出 bin/moc"
fi

echo "freshbuild: 通过 $PASS / $((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
