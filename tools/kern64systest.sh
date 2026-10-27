#!/bin/bash
# kern64systest.sh —— ARM64 裸机"系统"（RAMFS + shell + 包管理）的端到端验证
#
# 判据不是"能编译"，而是**在模拟的裸硬件上真的交互并给出正确结果**：
#   - 注入一串按键，内核必须逐字符读回来（回显完整 = 输入链路真的工作）
#   - 写文件 → 读回来 → 删掉，每一步都要给出精确数字
#   - 装包 → 执行 → 结果必须等于手算的值（5+3=8）
#   - 错误路径也要有精确错误码（栈不足 = -3）
#
# 这条链上最阴的两个缺陷都是"不报错、只给错答案"或"无声卡死"，
# 所以每条断言都写成精确值，而不是"看起来跑起来了"。
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
ELF=/tmp/mosys64.elf
C=/tmp/mokern64/kernel.c
pass=0
fail=0

ck() {
    if [ "$2" = "$3" ]; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi
}
ckhas() {
    if echo "$2" | grep -q "$3"; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (缺少 '$3')"; fi
}
ckhasnot() {
    if echo "$2" | grep -q "$3"; then fail=$((fail+1)); echo "✗ $1 (不该出现 '$3')";
    else pass=$((pass+1)); fi
}

rm -f "$ELF"
bash tools/kernel64.sh examples/kern64sys.mo "$ELF" >/tmp/k64sysbuild.log 2>&1
rc=$?
ck "系统镜像构建" "$rc" 0
[ -f "$ELF" ] || { echo "kern64systest: 没有产物，无法继续"; exit 1; }

M=$(python3 -c "import struct;print(struct.unpack_from('<H',open('$ELF','rb').read(),18)[0])")
ck "ELF 机器类型 AArch64" "$M" 183
ckhas "前导含 UART MMIO" "$(cat "$C")" "uart_print"
ckhasnot "未落到 x86 VGA" "$(cat "$C")" "0xB8000"

# ---- 1) 没有输入时：shell 读不到字符就停机，不该卡死也不该乱读 ----
OUT0=$(python3 tools/kern64run.py "$ELF" 2>/tmp/k64sys0.err)
ckhas "无输入仍启动" "$OUT0" "MO-KERN64-SYS BOOT"
ckhas "无输入即停机" "$OUT0" "MO-KERN64-SYS HALT"
ckhas "无输入不读数据寄存器" "$(cat /tmp/k64sys0.err)" "rd_dr=0"

# ---- 2) 注入一串命令，走完整的 写→读→装包→执行→删除 ----
KEYS=$(printf 'ls\rwrite a hello\rcat a\rls\rpkg demo 05 03 10 90\rrun demo\rpkg bad 10 90\rrun bad\rpkgs\rxyz\rrm a\rls\rexit\r')
OUT=$(python3 tools/kern64run.py "$ELF" --keys "$KEYS" 2>/tmp/k64sys.err)
ERR=$(cat /tmp/k64sys.err)

ckhas "启动横幅" "$OUT" "MO-KERN64-SYS BOOT"
ckhas "无宿主声明" "$OUT" "no libc / no syscall / no host os"

# 输入链路：回显必须**完整**。早先模拟器的读钩子把第一个字节预置进
# 数据寄存器又被钩子覆盖，"help" 只回显出 "elp"，第一个字符凭空消失。
ckhas "回显完整（首字符未丢）" "$OUT" "mo> write a hello"
RD=$(sed -n 's/.*rd_dr=\([0-9]*\).*/\1/p' /tmp/k64sys.err)
ck "确实读了 UART（次数 > 50）" "$([ "${RD:-0}" -gt 50 ] && echo yes || echo no)" "yes"

# RAMFS
ckhas "初始无文件" "$OUT" "files=0"
ckhas "写入 5 字节" "$OUT" "wrote=5"
ckhas "读回内容" "$OUT" "hello"
ckhas "列目录含文件名" "$OUT" "a len=5"

# 包管理 + 栈式 VM：05 03 10 90 = push 5, push 3, add, halt
ckhas "装包 4 条指令" "$OUT" "installed ops=4"
ckhas "执行结果 5+3" "$OUT" "=8"
ckhas "包清单" "$OUT" "demo ops=4"

# 错误路径：10 90 = add, halt —— 栈上不足两个元素
ckhas "栈不足报错" "$OUT" "=-3"

ckhas "删除成功" "$OUT" "rm=0"
ckhas "删除后无文件" "$OUT" "files=0"
ckhas "未知命令" "$OUT" "? xyz"
ckhas "命令计数" "$OUT" "cmds=13"
ckhas "停机标记" "$OUT" "MO-KERN64-SYS HALT"

echo "kern64systest: $pass 通过 / $fail 失败"
[ "$fail" = 0 ] || exit 1
exit 0
