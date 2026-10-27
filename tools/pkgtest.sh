#!/bin/bash
# pkgtest —— 用**本地 git 仓库**验证包管理器（不需要网络）
#
# 为什么用真 git 而不是 mock：包管理器的正确性几乎全在
# "clone 到哪、锁了哪个 commit、检出是否一致"这些地方上，
# mock 掉 git 就等于没测。
set +e
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOPKG="$HERE/tools/mopkg.sh"
W=/tmp/mopkgtest
rm -rf $W && mkdir -p $W
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkpkg() {  # mkpkg <名字> <版本> <依赖声明行...>
  local n=$1 v=$2; shift 2
  mkdir -p $W/repos/$n && cd $W/repos/$n
  git init -q -b main . 2>/dev/null
  { echo '[package]'; echo "name = \"$n\""; echo "version = \"$v\""; echo;
    echo '[dependencies]'; for l in "$@"; do echo "$l"; done; } > mo.toml
  echo "fn ${n}_v() -> i64 { return 1; }" > lib.mo
  git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
  cd $W
}

# ---- 三个包：app 依赖 b，b 依赖 c ----
mkpkg c 1.0.0
mkpkg b 2.1.0 "c = { git = \"file://$W/repos/c\", ref = \"main\", version = \"^1.0.0\" }"
mkdir -p $W/app && cd $W/app
bash $MOPKG init app >/dev/null 2>&1
cat > mo.toml <<TOML
[package]
name = "app"
version = "0.1.0"

[dependencies]
b = { git = "file://$W/repos/b", ref = "main", version = "^2.0.0" }
TOML

bash $MOPKG fetch >/dev/null 2>&1
ck "$?" "0" "fetch 递归拉取依赖"
[ -d deps/b ] && ck "1" "1" "b 已安装" || ck "0" "1" "b 已安装"
[ -d deps/c ] && ck "1" "1" "c 被递归安装" || ck "0" "1" "c 被递归安装"

# 锁文件
ck "$(grep -c '^\[\[package\]\]' mo.lock)" "2" "mo.lock 记录 2 个包"
[ -n "$(grep '^name = "c"' mo.lock)" ] && ck 1 1 "锁里含 c"
c1=$(awk '/^name = "c"/{f=1} f&&/^commit = /{print; exit}' mo.lock)
ck "$(bash $MOPKG verify >/dev/null 2>&1; echo $?)" "0" "verify 通过"

# 依赖树
T=$(bash $MOPKG tree 2>/dev/null)
echo "$T" | grep -q "b 2.1.0" && ck 1 1 "tree 显示 b 2.1.0"
echo "$T" | grep -q "c 1.0.0" && ck 1 1 "tree 显示 c（间接依赖）"

# ---- 版本约束不满足要报错 ----
cat > mo.toml <<TOML
[package]
name = "app"
version = "0.1.0"

[dependencies]
b = { git = "file://$W/repos/b", ref = "main", version = ">=9.0.0" }
TOML
ck "$(bash $MOPKG verify >/dev/null 2>&1; echo $?)" "1" "版本不满足约束 → verify 失败"

# ---- 锁与实际不一致（手动改动 HEAD）要报"不可复现" ----
cat > mo.toml <<TOML
[package]
name = "app"
version = "0.1.0"

[dependencies]
b = { git = "file://$W/repos/b", ref = "main", version = "^2.0.0" }
TOML
(cd deps/b && git checkout -q HEAD~0 2>/dev/null; git commit -q --allow-empty -m x 2>/dev/null)
ck "$(bash $MOPKG verify >/dev/null 2>&1; echo $?)" "1" "锁记录 ≠ 实际 HEAD → 报不可复现"

# ---- 未安装的依赖要报错 ----
rm -rf deps/c
cat > mo.toml <<TOML
[package]
name = "app"
version = "0.1.0"

[dependencies]
b = { git = "file://$W/repos/b", ref = "main" }
c = { git = "file://$W/repos/c", ref = "main" }
TOML
ck "$(bash $MOPKG verify 2>&1 | grep -c '未安装')" "1" "依赖缺失 → verify 报未安装"

# ---- 循环依赖检测 ----
mkdir -p $W/cyc && cd $W/cyc
mkpkg p 1.0.0 "q = { git = \"file://$W/repos/q\" }" 2>/dev/null
mkpkg q 1.0.0 "p = { git = \"file://$W/repos/p\" }" 2>/dev/null
cat > mo.toml <<TOML
[package]
name = "cyc"
version = "0.1.0"

[dependencies]
p = { git = "file://$W/repos/p" }
TOML
bash $MOPKG fetch >/dev/null 2>&1
CT=$(bash $MOPKG tree 2>/dev/null)
echo "$CT" | grep -q "循环依赖" && ck 1 1 "循环依赖被检出（p→q→p）"

# ---- 版本约束单元（借 shell 函数） ----
sed -n "/^# ============================ 版本/,/^# ============================ 锁文件/p" $MOPKG > /tmp/pkgvfns.sh
V=$(bash -c '. /tmp/pkgvfns.sh
r=""; 
ver_match 1.9.9 "^1.0.0" && r="${r}1";
ver_match 2.0.0 "^1.0.0" || r="${r}2";
ver_match 1.2.9 "~1.2.0" && r="${r}3";
ver_match 1.3.0 "~1.2.0" || r="${r}4";
ver_match 0.9.0 ">=1.0.0" || r="${r}5";
ver_match 1.0.1 "=1.0.0" || r="${r}6";
echo $r')
ck "$V" "123456" "版本约束语义（^ ~ >= =）"

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ]
