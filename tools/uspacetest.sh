#!/bin/bash
# uspacetest —— 「最小用户空间」端到端验证
#
#   make uspacetest
#
# 两端对照，同一份源码、同一组判据：
#   A 端  ARM64  ：Unicorn 模拟 ARM64 CPU + 自制 Linux syscall 表（内存文件系统）
#   B 端  x86-64 ：本机**真跑**（cfs-x86_64 静态 ELF，操作真文件系统 /mo）
#
# 为什么必须两端：只跑 ARM64 端，判据是模拟器自己实现的 syscall 语义，
# 可能与真内核不一致；只跑 x86-64 端，验证不到 *at 号适配（x86 不需要）。
# 两端给**同一组数字**，才说明「适配对了」而不是「模拟器迁就了实现」。
#
# 本测试要证明的不是「程序能跑」，而是「用户空间能自我维持」：
#   建根 → 写启动脚本 → 读回来 → 逐行解释 → 装包 → 执行 → 卸包。
# 其中「读回来并逐字节比对」是关键：若直接执行内存里的字符串，
# 「能在目标机上持久化状态」这条就没人验。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

echo "uspace:"

# ---------------- A 端：ARM64（模拟器） ----------------
# 🔴 必须先删产物：构建失败时**旧 ELF 会残留**，然后"执行"跑的是上一个版本
# —— 判据全绿，等于什么都没验（v1.153 记过「源码干净 ≠ 产物干净」）。
ELF=/tmp/mo_uspace.arm64
rm -f $ELF
bash tools/android_native.sh examples/uspace.mo $ELF >/dev/null 2>&1
BA=$?
chk $BA "ARM64 构建（cfs-aarch64）"

if [ $BA -ne 0 ]; then
  echo "  ✗ ARM64 构建失败，跳过执行（不跑残留的旧产物）"; fail=$((fail+1))
else
  S=$(python3 $ROOT/tools/armrun.py $ELF --dumpfs 2>/dev/null)
  echo "$S" | grep -q "\[1\] mkdir /mo     ret=0";  chk $? "  ARM64: 建根成功"
  echo "$S" | grep -q "\[2\] write rc      bytes=113"; chk $? "  ARM64: 写脚本 113 字节"
  echo "$S" | grep -q "\[3\] read rc       bytes=113"; chk $? "  ARM64: 读回 113 字节"
  echo "$S" | grep -q "\[3\] rc identical  =1"; chk $? "  ARM64: 读回逐字节相同"
  echo "$S" | grep -q "^boot$";                   chk $? "  ARM64: 脚本 echo 生效"
  echo "$S" | grep -q "^MO-USERSPACE$";           chk $? "  ARM64: cat 读到文件内容"
  echo "$S" | grep -q "^done$";                   chk $? "  ARM64: 脚本末行也执行了"
  echo "$S" | grep -q "\[4\] cmds run      =6";   chk $? "  ARM64: 6 条命令全部执行"
  echo "$S" | grep -q "\[5\] run demo      out=42"; chk $? "  ARM64: 装包后执行 = 42"
  echo "$S" | grep -q "\[6\] tamper run    ret=-6"; chk $? "  ARM64: 篡改后拒绝执行"
  echo "$S" | grep -q "\[7\] pkgs before   =1";   chk $? "  ARM64: 卸载前有 1 个包"
  echo "$S" | grep -q "\[7\] pkgs after    =0";   chk $? "  ARM64: 卸载后 0 个包"
  echo "$S" | grep -q "\[7\] find removed  =-1";  chk $? "  ARM64: 卸载后查不到"
  # 所有 *at 调用的 dfd 都必须是 AT_FDCWD(-100)，否则说明参数重排错了
  BAD=$(echo "$S" | grep -c "dfd=" )
  GOOD=$(echo "$S" | grep -c "dfd=-100")
  [ "$BAD" = "$GOOD" ] && [ "$BAD" -gt 0 ]
  chk $? "  ARM64: 全部 *at 调用 dfd = AT_FDCWD"
fi

# ---------------- B 端：x86-64（真文件系统） ----------------
# 源码里路径写死 /mo，所以本机跑会在**真**根目录建 /mo —— 这正是要验的：
# 不是模拟器内存 FS 的语义，而是真内核的行为。跑完清掉。
EXE=/tmp/mo_uspace.x86
rm -f $EXE
rm -rf /mo
ARCH=x86_64 bash tools/android_native.sh examples/uspace.mo $EXE >/dev/null 2>&1
BB=$?
chk $BB "x86-64 构建（cfs-x86_64）"

if [ $BB -ne 0 ]; then
  echo "  ✗ x86-64 构建失败"; fail=$((fail+1))
else
  T=$(timeout 60 $EXE 2>&1)
  RC=$?
  chk $RC "x86-64: 真机退出码 0"
  echo "$T" | grep -q "\[1\] mkdir /mo     ret=0";  chk $? "  x86-64: 建根成功"
  echo "$T" | grep -q "\[2\] write rc      bytes=113"; chk $? "  x86-64: 写脚本 113 字节"
  echo "$T" | grep -q "\[3\] rc identical  =1";     chk $? "  x86-64: 读回逐字节相同"
  echo "$T" | grep -q "\[4\] cmds run      =6";     chk $? "  x86-64: 6 条命令全部执行"
  echo "$T" | grep -q "\[5\] run demo      out=42"; chk $? "  x86-64: 装包后执行 = 42"
  echo "$T" | grep -q "\[6\] tamper run    ret=-6"; chk $? "  x86-64: 篡改后拒绝执行"
  echo "$T" | grep -q "\[7\] pkgs after    =0";     chk $? "  x86-64: 卸载后 0 个包"
  # 真文件系统上必须真的留下 hi.txt（脚本里的 write 命令生效），
  # 且 init.rc 已被删掉（程序收尾 fdel）—— 证明读写与删除都作用在真磁盘上
  [ -f /mo/hi.txt ]
  chk $? "  x86-64: 真磁盘上留下 hi.txt"
  [ ! -f /mo/init.rc ]
  chk $? "  x86-64: 真磁盘上 init.rc 已删除"
  rm -rf /mo
fi

echo "uspacetest: fail=$fail"
exit $fail
