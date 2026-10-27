#!/bin/bash
# pkgclosuretest —— 依赖闭包/依赖树的递归正确性（端到端）
#
# 背景：pkg_dep_names 把结果写进**全局** PKG_NAMES，而 pkg_closure 与
# pkg_tree_visit 是递归的。内层一调用就把外层还没遍历到的名字覆盖掉。
# 触发条件很窄（外层 >=2 个依赖、内层覆盖到外层未遍历的下标），
# 所以链状依赖（app->b->c，每层一个）**碰巧不会暴露** —— 现有
# mopkgmo_test.sh 用的正是链状，一直全绿。
#
# 这里刻意构造分叉：app -> {b, d}，b -> {c1, c2}。
# 缺陷下 i=1 读到的是内层留下的 "c2"，于是 d 丢失、c2 出现两次。
#
# 同一程序里 BFS 版的 fetch 是对的（.deps 四个包齐全），
# 于是「.deps 齐全但 tree 缺 d」本身就是最硬的对照证据。
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); BUILD=$(mktemp -d); FAIL=0
trap 'rm -rf "$W" "$BUILD"' EXIT
pass(){ echo "  ✓ $1"; }; fail(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

cp "$ROOT"/lib/*.mo "$BUILD"/; cp "$ROOT/tools/mopkgcli.mo" "$BUILD/test.mo"
( cd "$BUILD" && "$ROOT/bin/moc" test.mo mopkg.elf >/dev/null 2>&1 ) || { echo "✗ 编译失败"; exit 1; }
M="$BUILD/mopkg.elf"
mk(){ mkdir -p "$1"; ( cd "$1" && git init -q -b main && printf '%s' "$2" > mo.toml && git add -A && git -c user.email=a@b -c user.name=t commit -qm i ) >/dev/null 2>&1; }
dep(){ printf '%s = { git = "%s", ref = "main", version = "^1.0.0" }\n' "$1" "$2"; }

mk "$W/c1" '[package]
name = "c1"
version = "1.0.0"
'
mk "$W/c2" '[package]
name = "c2"
version = "1.0.0"
'
mk "$W/d" '[package]
name = "d"
version = "1.0.0"
'
mk "$W/b" "[package]
name = \"b\"
version = \"2.0.0\"

[dependencies]
$(dep c1 "$W/c1")
$(dep c2 "$W/c2")
"
mkdir -p "$W/app"
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\n%s\n%s\n' \
  "$(dep b "$W/b")" "$(dep d "$W/d")" > "$W/app/mo.toml"
cd "$W/app"
$M fetch >/dev/null 2>&1

# 0) 非空转守卫：确认这条用例真的建出了分叉依赖，否则下面的"齐全"毫无意义
if [ -d .deps/b ] && [ -d .deps/c1 ] && [ -d .deps/c2 ] && [ -d .deps/d ]; then
  pass "构造成功：.deps 四个包齐全（BFS 的 fetch 正确）"
else
  fail "用例没建起来，.deps=$(ls .deps 2>/dev/null | tr '\n' ' ')"; exit 1
fi

T=$($M tree 2>&1)
for n in b c1 c2 d; do
  if echo "$T" | grep -q "\b$n\b"; then pass "tree 含 $n"; else fail "tree 缺 $n"; fi
done
# 每个名字恰好一次 —— 只查"含不含"会把"c2 出现两次、d 丢失"判成通过
for n in b c1 c2 d; do
  c=$(echo "$T" | grep -c "^ *$n\b")
  if [ "$c" = 1 ]; then pass "$n 恰好出现 1 次"; else fail "$n 出现 $c 次（应为 1）"; fi
done
echo
[ "$FAIL" -eq 0 ] && echo "pkgclosuretest: 全部通过" || echo "pkgclosuretest: 失败 $FAIL 项"
exit $FAIL
