#!/bin/bash
# pkgarmtest —— **包管理在安卓上运行**的最小地基：端到端验证
#
# 两端对照，同一份源码、同一组判据：
#   A 端  ARM64  ：Unicorn 模拟 ARM64 CPU + 自制 Linux syscall 表（内存文件系统）
#   B 端  x86-64 ：本机真跑（cfs-x86_64 静态 ELF，操作**真**文件系统）
#
# 为什么需要这个例子：lib/mopkg.mo 走的是 fork+execve+pipe+wait4（sh_capture）
# 并且依赖 git，这套调用在 freestanding 的 cfs-aarch64 上**根本不存在** ——
# 编都编不过。本例证明包管理真正需要的只有五个 *at 调用，纯 syscall 即可，
# 不需要 fork / exec / git / libc。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

echo "pkgarm:"

# ---------------- A 端：ARM64（模拟器） ----------------
# 🔴 必须先删产物：构建失败时旧 ELF 会残留，然后"执行"跑的是上一个版本 ——
# 判据全绿，等于什么都没验（v1.153「源码干净 ≠ 产物干净」的另一半）。
ELF=/tmp/mo_pkgarm.arm64
rm -f $ELF
bash tools/android_native.sh examples/pkgarm.mo $ELF >/dev/null 2>&1
BA=$?
chk $BA "ARM64 构建（cfs-aarch64）"

bash $ROOT/tools/pyreq.sh unicorn >/dev/null 2>&1
HAVE=$?
if [ $BA -ne 0 ]; then
  echo "  ✗ ARM64 构建失败，跳过执行（不跑残留的旧产物）"; fail=$((fail+1))
elif [ $HAVE -ne 0 ]; then
  echo "  ⚠ 跳过 ARM64 执行（缺少 unicorn，见 tools/pyreq.sh）"
else
  S=$(python3 $ROOT/tools/armrun.py $ELF --dumpfs 2>/dev/null)
  echo "$S" | grep -q "mkdir ret   = 0";    chk $? "  ARM64: mkdirat 建包目录"
  echo "$S" | grep -q "write bytes = 10";   chk $? "  ARM64: 写清单 10 字节"
  echo "$S" | grep -q "read bytes  = 10";   chk $? "  ARM64: 读回 10 字节"
  echo "$S" | grep -q "read back   : MO-PKG-OK"; chk $? "  ARM64: 读回内容原样"
  echo "$S" | grep -q "stat ret    = 0";    chk $? "  ARM64: newfstatat 查询命中"
  echo "$S" | grep -q "unlink ret  = 0";    chk $? "  ARM64: unlinkat 删除"
  echo "$S" | grep -q "pkg ok      = 1";    chk $? "  ARM64: 汇总通过"

  # 五个 *at 调用（mkdir/open W/open R/stat/unlink）首参都必须是 AT_FDCWD(-100)。
  # 关键在 N_ALL == N_100：少插一个 -100 时，剩下的仍全是 -100，
  # 只看"有 -100"会漏判。此前 unlinkat/newfstatat 根本不记日志 ——
  # 那正是"重排漏了一个"藏得住的地方，本轮一并补上。
  N_ALL=$(echo "$S" | grep -c "dfd=")
  N_100=$(echo "$S" | grep -c "dfd=-100")
  [ "$N_ALL" = "5" ]
  chk $? "  ARM64: *at 调用共 5 次（mkdir+open×2+stat+unlink）"
  [ "$N_ALL" = "$N_100" ]
  chk $? "  ARM64: 全部首参为 AT_FDCWD(-100)，无遗漏"
fi

# ---------------- B 端：x86-64（真机、真文件系统） ----------------
X86=/tmp/mo_pkgarm_x86
rm -f $X86; rm -rf /tmp/mo_pkg_demo
ARCH=x86_64 bash tools/android_native.sh examples/pkgarm.mo $X86 >/dev/null 2>&1
BB=$?
chk $BB "x86-64 构建（cfs-x86_64）"

if [ $BB -ne 0 ] || [ ! -x $X86 ]; then
  echo "  ✗ x86-64 产物不可用，跳过执行（不跑残留的旧产物）"; fail=$((fail+1))
else
  T=$($X86 2>&1); RC=$?
  echo "$T" | grep -q "mkdir ret   = 0";    chk $? "  x86-64: mkdir 建包目录"
  echo "$T" | grep -q "write bytes = 10";   chk $? "  x86-64: 写清单 10 字节"
  echo "$T" | grep -q "read bytes  = 10";   chk $? "  x86-64: 读回 10 字节"
  echo "$T" | grep -q "read back   : MO-PKG-OK"; chk $? "  x86-64: 读回内容原样"
  echo "$T" | grep -q "stat ret    = 0";    chk $? "  x86-64: stat 查询命中"
  echo "$T" | grep -q "unlink ret  = 0";    chk $? "  x86-64: unlink 删除"
  echo "$T" | grep -q "pkg ok      = 1";    chk $? "  x86-64: 汇总通过"
  [ $RC = 0 ]
  chk $? "  x86-64: 退出码 0"
  # 真机才能说的两件事：目录真建出来了、unlink 后文件真没了
  [ -d /tmp/mo_pkg_demo ]
  chk $? "  真机: 包目录确实存在"
  [ ! -f /tmp/mo_pkg_demo/MANIFEST ]
  chk $? "  真机: 清单已删除"
  rmdir /tmp/mo_pkg_demo 2>/dev/null
fi

if [ $fail -eq 0 ]; then
  echo "pkgarm: OK（ARM64 与 x86-64 两端包管理地基一致）"
else
  echo "pkgarm: $fail 项未通过"; exit 1
fi
