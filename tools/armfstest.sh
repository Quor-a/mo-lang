#!/bin/bash
# armfstest —— 安卓原生 **文件 IO** 端到端验证
#
# 两端对照，同一份源码、同一组判据：
#   A 端  ARM64  ：Unicorn 模拟 ARM64 CPU + 自制 Linux syscall 表（内存文件系统）
#   B 端  x86-64 ：本机真跑（cfs-x86_64 静态 ELF，操作**真**文件系统）
#
# 为什么要两端：只跑 ARM64 端，判据是模拟器自己实现的 syscall 语义，
# 可能与真内核不一致；只跑 x86-64 端，验证不到 *at 号适配（x86 不需要）。
# 两端给同一组数字，才说明「适配对了」而不是「模拟器迁就了实现」。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

echo "armfs:"

# ---------------- A 端：ARM64（模拟器） ----------------
# 🔴 必须先删产物：构建失败时**旧 ELF 会残留**，然后"执行"跑的是上一个
# 版本 —— 判据全绿，等于什么都没验（v1.153 记过「源码干净 ≠ 产物干净」，
# 这里是同一个坑的另一半）。构建失败就跳过执行并直接判失败。
ELF=/tmp/mo_armfs.arm64
rm -f $ELF
bash tools/android_native.sh examples/armfs.mo $ELF >/dev/null 2>&1
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
  echo "$S" | grep -q "write bytes = 9"
  chk $? "  ARM64: write 返回 9"
  echo "$S" | grep -q "read bytes  = 9"
  chk $? "  ARM64: read 返回 9"
  echo "$S" | grep -q "read back   : MO-FS-OK"
  chk $? "  ARM64: 读回内容原样写回 stdout"
  echo "$S" | grep -q "content ok  = 1"
  chk $? "  ARM64: 长度与预期一致"
  echo "$S" | grep -q "mkdir ret   = 0"
  chk $? "  ARM64: mkdir 成功"
  echo "$S" | grep -q "unlink ret  = 0"
  chk $? "  ARM64: unlink 成功"

  # *at 参数重排是否真的对：四次（open W / open R / mkdir / unlink）首参都必须是
  # AT_FDCWD(-100)，且**不能有任何**其它 dfd —— 后者才是防止「重排漏了一个」
  # 的关键（少插一个 -100 时，剩下的仍全是 -100，只看"有 -100"会漏判）。
  N_ALL=$(echo "$S" | grep -c "dfd=")
  N_100=$(echo "$S" | grep -c "dfd=-100")
  [ "$N_ALL" = "4" ]
  chk $? "  ARM64: *at 调用共 4 次（open×2 + mkdir + unlink）"
  [ "$N_ALL" = "$N_100" ]
  chk $? "  ARM64: 全部首参为 AT_FDCWD(-100)，无遗漏"
fi

# ---------------- B 端：x86-64（真机、真文件系统） ----------------
X86=/tmp/mo_armfs_x86
rm -f $X86 /tmp/mo_armfs.txt; rmdir /tmp/mo_armfs_dir 2>/dev/null
ARCH=x86_64 bash tools/android_native.sh examples/armfs.mo $X86 >/dev/null 2>&1
BB=$?
chk $BB "x86-64 构建（cfs-x86_64）"

if [ $BB -ne 0 ] || [ ! -x $X86 ]; then
  echo "  ✗ x86-64 产物不可用，跳过执行（不跑残留的旧产物）"; fail=$((fail+1))
elif [ -x $X86 ]; then
  T=$($X86 2>&1); RC=$?
  echo "$T" | grep -q "write bytes = 9"
  chk $? "  x86-64: write 返回 9"
  echo "$T" | grep -q "read bytes  = 9"
  chk $? "  x86-64: read 返回 9"
  echo "$T" | grep -q "read back   : MO-FS-OK"
  chk $? "  x86-64: 读回内容原样写回 stdout"
  echo "$T" | grep -q "content ok  = 1"
  chk $? "  x86-64: 长度与预期一致"
  echo "$T" | grep -q "mkdir ret   = 0"
  chk $? "  x86-64: mkdir 成功"
  echo "$T" | grep -q "unlink ret  = 0"
  chk $? "  x86-64: unlink 成功"
  [ $RC = 0 ]
  chk $? "  x86-64: 退出码 0"
  # 真机上顺带确认：目录真的建出来了（模拟器只能说"调用返回 0"）
  [ -d /tmp/mo_armfs_dir ]
  chk $? "  真机: /tmp/mo_armfs_dir 确实存在"
  [ ! -f /tmp/mo_armfs.txt ]
  chk $? "  真机: unlink 后文件确实没了"
  rmdir /tmp/mo_armfs_dir 2>/dev/null
else
  echo "  ✗ x86-64 产物不可执行"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then
  echo "armfs: OK（ARM64 与 x86-64 两端文件 IO 结果一致）"
else
  echo "armfs: $fail 项未通过"; exit 1
fi
