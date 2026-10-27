#!/bin/bash
# rootfstest —— 证明 rootfs 打包与检查器都有效
#   bash tools/rootfstest.sh
#
# 分两段：
#   A. 打包出的 rootfs 六层判据全过
#   B. 四类真机踩过的破坏，检查器**必须**变红（否则检查器是空转的）
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
R=/tmp/mo_rootfs_t1
pass=0; fail=0
ck(){ if [ "$2" = "$3" ]; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1（got $2 want $3）"; fail=$((fail+1)); fi; }

echo "=== A. 打包出的 rootfs ==="
bash "$ROOT/tools/mkrootfs.sh" "$R" >/dev/null 2>&1
bash "$ROOT/tools/rootfscheck.sh" "$R" >/dev/null 2>&1
ck "A1 新打包的 rootfs 检查全过" "$?" "0"
[ -d "$R/work" ]; ck "A2 work/ 被建出来" "$?" "0"
[ "$(stat -c '%a' "$R")" = "755" ]; ck "A3 顶层权限 755（不是 700）" "$?" "0"

echo "=== B. 四类真机破坏，检查器必须变红 ==="
# B1: 删掉 work/ —— proot 报 can't chdir to '/work'
cp -r "$R" /tmp/mo_rootfs_b1; rm -rf /tmp/mo_rootfs_b1/work
bash "$ROOT/tools/rootfscheck.sh" /tmp/mo_rootfs_b1 >/dev/null 2>&1
ck "B1 删 work/ 被抓到" "$([ $? -ne 0 ] && echo yes)" "yes"

# B2: 顶层权限改成 700 —— tracee 降权后进不去
cp -r "$R" /tmp/mo_rootfs_b2; chmod 700 /tmp/mo_rootfs_b2
bash "$ROOT/tools/rootfscheck.sh" /tmp/mo_rootfs_b2 >/dev/null 2>&1
ck "B2 顶层 700 被抓到" "$([ $? -ne 0 ] && echo yes)" "yes"

# B3: 删掉 moc —— proot 报 No such file
cp -r "$R" /tmp/mo_rootfs_b3; rm -f /tmp/mo_rootfs_b3/bin/moc
bash "$ROOT/tools/rootfscheck.sh" /tmp/mo_rootfs_b3 >/dev/null 2>&1
ck "B3 删 moc 被抓到" "$([ $? -ne 0 ] && echo yes)" "yes"

# B4: 动态链接的翻译器不带 loader —— execve 报 ENOENT
cp -r "$R" /tmp/mo_rootfs_b4
cp /bin/ls /tmp/mo_rootfs_b4/box64 2>/dev/null || cp "$(command -v python3)" /tmp/mo_rootfs_b4/box64
bash "$ROOT/tools/rootfscheck.sh" /tmp/mo_rootfs_b4 2>/dev/null | grep -q "FAIL.*\[4\]"
ck "B4 翻译器缺 loader 被抓到" "$?" "0"

echo "rootfstest: $pass 通过 / $fail 失败"
[ "$fail" -eq 0 ]
