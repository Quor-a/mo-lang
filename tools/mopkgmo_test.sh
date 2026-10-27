#!/bin/bash
# mopkgmo_test —— 验证「墨语言写的包管理器」端到端可用
#
# 为什么单独立一个测试而不复用 pkgtest.sh：
#   pkgtest.sh 测的是 shell 版 mopkg.sh。这里测的是 lib/mopkg.mo +
#   tools/mopkgcli.mo 编出来的可执行文件 —— 两者是不同实现，
#   必须各自验证，不能因为 shell 版过了就认为墨语言版也对。
#
# 重点验证三件 shell 版有、而 mo 版原本缺失的东西：
#   1. 递归拉取间接依赖
#   2. 检出指定 ref（否则锁里的 commit 与实际内容不符）
#   3. 写出 mo.lock

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MOC="$ROOT/bin/moc"
WORK=$(mktemp -d)
FAIL=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "mopkgmo: 编译墨语言版包管理器"

# ---- 编译 ----
BUILD=$(mktemp -d)
cp "$ROOT"/lib/*.mo "$BUILD"/
cp "$ROOT/tools/mopkgcli.mo" "$BUILD/test.mo"
( cd "$BUILD" && "$MOC" test.mo mopkg.elf ) || { echo "✗ 编译失败"; exit 1; }
MPKG="$BUILD/mopkg.elf"
pass "编译"

# ---- 造三个本地 git 仓库：app -> b -> c ----
mk_repo() {
  local d="$1" n="$2" v="$3" extra="$4"
  mkdir -p "$d"
  ( cd "$d" && git init -q -b main && \
    printf '[package]\nname = "%s"\nversion = "%s"\n\n%s\n' "$n" "$v" "$extra" > mo.toml && \
    git add -A && git -c user.email=a@b -c user.name=t commit -qm init )
}
mk_repo "$WORK/repo_c" c 1.0.0 ""
mk_repo "$WORK/repo_b" b 2.1.0 "[dependencies]
c = { git = \"$WORK/repo_c\", ref = \"main\", version = \"^1.0.0\" }"
mkdir -p "$WORK/app"
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nb = { git = "%s", ref = "main", version = "^2.0.0" }\n' \
  "$WORK/repo_b" > "$WORK/app/mo.toml"

cd "$WORK/app"

# ---- 1. fetch 递归 ----
OUT=$("$MPKG" fetch 2>&1)
if [ -d .deps/b ] && [ -d .deps/c ]; then
  pass "fetch 递归拉到间接依赖 c"
else
  fail "fetch 未递归（.deps 里应有 b 和 c，实际: $(ls .deps 2>/dev/null | tr '\n' ' ')）"
fi

# ---- 2. 检出 ref ----
BR=$(git -C .deps/b branch --show-current 2>/dev/null)
if [ "$BR" = "main" ]; then
  pass "检出指定 ref (main)"
else
  fail "检出失败，.deps/b 当前分支=$BR"
fi

# ---- 3. mo.lock ----
if [ -f mo.lock ]; then
  pass "生成 mo.lock"
else
  fail "未生成 mo.lock"
fi
if grep -q 'name = "b"' mo.lock && grep -q 'name = "c"' mo.lock; then
  pass "mo.lock 含 b 与 c"
else
  fail "mo.lock 缺少间接依赖记录"
fi
# commit 必须是 40 位十六进制，空值说明 git 没跑通
CB=$(grep -A5 'name = "b"' mo.lock | grep '^commit' | sed 's/.*"\(.*\)"/\1/')
case "$CB" in
  ????????????????????????????????????????)
    if printf '%s' "$CB" | grep -qE '^[0-9a-f]{40}$'; then
      pass "mo.lock 记录了真实 commit ($CB)"
    else
      fail "commit 不是十六进制: $CB"
    fi ;;
  *) fail "commit 为空或长度不对: [$CB]" ;;
esac
# version 必须干净 —— 曾因 pkg_skip 返回下标被当成地址，取成 'ersion = "2.1.0"'
VB=$(grep -A5 'name = "b"' mo.lock | grep '^version' | sed 's/.*"\(.*\)"/\1/')
if [ "$VB" = "2.1.0" ]; then
  pass "mo.lock 版本解析干净 ($VB)"
else
  fail "版本解析错误: [$VB]（正确应为 2.1.0）"
fi

# ---- 4. tree 含间接依赖 ----
if "$MPKG" tree 2>&1 | grep -q 'c'; then
  pass "tree 显示间接依赖 c"
else
  fail "tree 未显示间接依赖"
fi

# ---- 5. verify 通过 ----
if "$MPKG" verify 2>&1 | grep -q '✓'; then
  pass "verify 通过"
else
  fail "verify 未通过"
fi

# ---- 6. 变异：约束不满足时应报错 ----
# 这条用来证明 verify 不是无条件通过
sed -i 's/\^2\.0\.0/^9.0.0/' mo.toml
"$MPKG" fetch >/dev/null 2>&1
if "$MPKG" verify 2>&1 | grep -q '✗'; then
  pass "版本约束不满足时 verify 报错（非空转）"
else
  fail "约束改成 ^9.0.0 后 verify 仍通过 —— 说明没真的检查"
fi
sed -i 's/\^9\.0\.0/^2.0.0/' mo.toml

echo
if [ "$FAIL" -eq 0 ]; then
  echo "mopkgmo: 全部通过"
else
  echo "mopkgmo: 失败 $FAIL 项"
fi
rm -rf "$WORK" "$BUILD"
exit $FAIL
