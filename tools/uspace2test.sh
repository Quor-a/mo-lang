#!/bin/bash
# uspace2test —— 「完整用户空间」端到端验证
#
#   make uspace2test
#
# 两端对照，同一份源码、同一组判据：
#   A 端  ARM64  ：Unicorn 模拟 ARM64 CPU + 自制 Linux syscall 表（内存文件系统）
#   B 端  x86-64 ：本机**真跑**（cfs-x86_64 静态 ELF，操作真文件系统 /mo）
#
# 为什么必须两端：只跑 ARM64，判据由模拟器自己实现的 syscall 语义给出，
# 可能与真内核不一致；只跑 x86-64，验证不到 *at 号适配（x86 不需要）。
# 两端给**同一组数字**，才说明「适配对了」而不是「模拟器迁就了实现」。
#
# 与 uspacetest（v1.161 最小用户空间）的区别
# ------------------------------------------
# 最小版只验「建根 → 写脚本 → 读回 → 装包 → 执行」。这一版要验六件事：
#   层次化 VFS · 完整 shell · 依赖拓扑与环检测 · 签名（不是校验和）·
#   序列化往返 · 跨运行恢复
# 其中两条最关键：
#   · deps app 必须是 liba → libb → app（后序）
#     —— 声明顺序是 app,libb,liba，两者**逐位不同**，所以这条能区分
#   · 序列化往返后 files/pkgs/envs 必须**与往返前相等**，且 run 结果相同
#     —— 只验「load 之后能跑」的话，load 读的是没清干净的残留也照样通过
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

echo "uspace2:"

# ---------------- A 端：ARM64（模拟器） ----------------
# 🔴 必须先删产物：构建失败时旧 ELF 会残留，然后"执行"跑的是上一个版本
# —— 判据全绿，等于什么都没验（v1.153 记过「源码干净 ≠ 产物干净」）。
ELF=/tmp/mo_uspace2.arm64
rm -f $ELF
bash tools/android_native.sh examples/uspace2.mo $ELF >/dev/null 2>&1
BA=$?
chk $BA "ARM64 构建（cfs-aarch64）"

if [ $BA -ne 0 ]; then
  echo "  ✗ ARM64 构建失败，跳过执行（不跑残留的旧产物）"; fail=$((fail+1))
else
  S=$(python3 $ROOT/tools/armrun.py $ELF --dumpfs 2>/dev/null)
  echo "$S" | grep -q "\[sip vectors bad\] = 0"; chk $? "  ARM64: SipHash 官方向量全对"
  echo "$S" | grep -q "\[nodes\] = 4";              chk $? "  ARM64: VFS 4 个节点"
  echo "$S" | grep -q "\[write motd\] = 14";        chk $? "  ARM64: 写文件 14 字节"
  echo "$S" | grep -q "\[motd\] = MO-USERSPACE-2";  chk $? "  ARM64: 内容逐字节正确"
  echo "$S" | grep -q "\[pwd\] = /mo/bin";          chk $? "  ARM64: cd/pwd 路径正确（无双斜杠）"
  echo "$S" | grep -q "\[env count\] = 1";          chk $? "  ARM64: 环境变量已设置"
  echo "$S" | grep -q "^root$";                     chk $? "  ARM64: \$VAR 展开生效"
  echo "$S" | grep -q "\[deps app\] = 3";           chk $? "  ARM64: 拓扑序 3 个包"
  # 后序 liba → libb → app。声明顺序是 app,libb,liba，两者逐位不同
  # 断言整个顺序串，而不是逐行 grep：后者检查不了先后（M1 变异实测漏过）
  echo "$S" | grep -q "\[order\] = liba,libb,app"; chk $? "  ARM64: 拓扑序 liba,libb,app"
  echo "$S" | grep -q "\[run liba\] = 6";           chk $? "  ARM64: 依赖包可执行（2*3）"
  echo "$S" | grep -q "\[run app\] = 42";           chk $? "  ARM64: 主包执行 = 42"
  echo "$S" | grep -q "\[tampered\] = -12";         chk $? "  ARM64: 篡改代码 → 签名不符 -12"
  echo "$S" | grep -q "\[run app2\] = 45";          chk $? "  ARM64: 升级后 = 45（不是 42）"
  echo "$S" | grep -q "\[downgrade\] = -8";         chk $? "  ARM64: 降级被拒"
  echo "$S" | grep -q "\[still run\] = 45";         chk $? "  ARM64: 降级被拒后版本未变"
  echo "$S" | grep -q "\[cycle\] = -2";             chk $? "  ARM64: 依赖环被检出"
  echo "$S" | grep -q "\[unpack\] = 2";             chk $? "  ARM64: pack/unpack 往返成功"
  echo "$S" | grep -q "\[after clear files\] = 0";  chk $? "  ARM64: 清空后 0 个文件"
  echo "$S" | grep -q "\[after clear pkgs\] = 0";   chk $? "  ARM64: 清空后 0 个包"
  echo "$S" | grep -q "\[restored files\] = 5";     chk $? "  ARM64: 重建后 5 个文件"
  echo "$S" | grep -q "\[restored pkgs\] = 3";      chk $? "  ARM64: 重建后 3 个包"
  echo "$S" | grep -q "\[restored envs\] = 1";      chk $? "  ARM64: 重建后 1 个环境变量"
  echo "$S" | grep -q "\[files match\] = 1";        chk $? "  ARM64: 往返前后文件数相等"
  echo "$S" | grep -q "\[pkgs match\] = 1";         chk $? "  ARM64: 往返前后包数相等"
  echo "$S" | grep -q "\[run app after\] = 45";     chk $? "  ARM64: 重建后仍可执行"
  echo "$S" | grep -q "^hello$";                    chk $? "  ARM64: 分号前段执行"
  echo "$S" | grep -q "^world$";                    chk $? "  ARM64: 分号后段执行"
  echo "$S" | grep -q "^? nosuchcmd$";              chk $? "  ARM64: 未知命令响亮报错"
  echo "$S" | grep -q "\[cmds run\] = 9";           chk $? "  ARM64: 脚本 9 条语句"
  echo "$S" | grep -q "\[unknown cmds\] = 1";       chk $? "  ARM64: 未知命令计数 1"
  echo "$S" | grep -q "\[rm non-empty\] = -11";     chk $? "  ARM64: 非空目录拒绝删除"
  echo "$S" | grep -q "\[rm again\] = -1";          chk $? "  ARM64: 已删文件再删 → -1"
  # 所有 *at 调用的 dfd 都必须是 AT_FDCWD(-100)，否则说明参数重排错了
  BAD=$(echo "$S" | grep -c "dfd=")
  GOOD=$(echo "$S" | grep -c "dfd=-100")
  [ "$BAD" = "$GOOD" ] && [ "$BAD" -gt 0 ]
  chk $? "  ARM64: 全部 *at 调用 dfd = AT_FDCWD"
fi

# ---------------- B 端：x86-64（真文件系统） ----------------
EXE=/tmp/mo_uspace2.x86
rm -f $EXE
rm -rf /mo
ARCH=x86_64 bash tools/android_native.sh examples/uspace2.mo $EXE >/dev/null 2>&1
BB=$?
chk $BB "x86-64 构建（cfs-x86_64）"

if [ $BB -ne 0 ]; then
  echo "  ✗ x86-64 构建失败"; fail=$((fail+1))
else
  T=$(timeout 120 $EXE 2>&1)
  RC=$?
  chk $RC "x86-64: 首次运行退出码 0"
  echo "$T" | grep -q "\[mode\] init";              chk $? "  x86-64: 首次为 init 模式"
  echo "$T" | grep -q "\[nodes\] = 4";              chk $? "  x86-64: VFS 4 个节点"
  echo "$T" | grep -q "\[pwd\] = /mo/bin";          chk $? "  x86-64: cd/pwd 路径正确"
  echo "$T" | grep -q "\[order\] = liba,libb,app"; chk $? "  x86-64: 拓扑序 liba,libb,app"
  echo "$T" | grep -q "\[run app\] = 42";           chk $? "  x86-64: 主包执行 = 42"
  echo "$T" | grep -q "\[tampered\] = -12";         chk $? "  x86-64: 篡改 → 签名不符"
  echo "$T" | grep -q "\[run app2\] = 45";          chk $? "  x86-64: 升级后 = 45"
  echo "$T" | grep -q "\[cycle\] = -2";             chk $? "  x86-64: 依赖环被检出"
  echo "$T" | grep -q "\[files match\] = 1";        chk $? "  x86-64: 往返前后文件数相等"
  echo "$T" | grep -q "\[run app after\] = 45";     chk $? "  x86-64: 重建后仍可执行"
  echo "$T" | grep -q "\[unknown cmds\] = 1";       chk $? "  x86-64: 未知命令计数 1"

  # ---------- 跨运行：第二次启动必须自动进入 restore ----------
  # 这是「用户空间」与「一次性的 demo」的分界线。ARM64 端每次运行是新的
  # 内存 FS，所以这条只能在真磁盘上验 —— 两端能力不同，如实分开断言。
  [ -f /mo/state.db ]
  chk $? "  x86-64: 真磁盘留下 state.db"
  U=$(timeout 120 $EXE 2>&1)
  echo "$U" | grep -q "\[mode\] restore";           chk $? "  x86-64: 第二次自动进入 restore"
  echo "$U" | grep -q "\[files\] = 5";              chk $? "  x86-64: 恢复 5 个文件"
  echo "$U" | grep -q "\[pkgs\] = 3";               chk $? "  x86-64: 恢复 3 个包"
  echo "$U" | grep -q "\[envs\] = 1";               chk $? "  x86-64: 恢复 1 个环境变量"
  echo "$U" | grep -q "\[motd\] = MO-USERSPACE-2";  chk $? "  x86-64: 恢复后文件内容一致"
  echo "$U" | grep -q "\[run app\] = 45";           chk $? "  x86-64: 恢复后仍可执行 = 45"
  rm -rf /mo
fi

echo "uspace2test: fail=$fail"
exit $fail
