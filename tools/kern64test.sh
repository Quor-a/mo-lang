#!/bin/bash
# kern64test.sh —— ARM64 裸机内核的端到端验证
#
# 判据不是"能编译"，而是"在模拟的裸硬件上真跑出正确结果"：
#   - 产物必须是 aarch64 ELF（不是 x86 内核换了个名字）
#   - 前导必须是 UART MMIO 版（落到 VGA 版会往错误地址写，静默）
#   - 模拟器里必须真打印出横幅、自检结果、停机标记
#   - 自检的三项数值必须逐一精确（55 / 5050 / 6765）
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
ELF=/tmp/mokern64.elf
C=/tmp/mokern64/kernel.c
pass=0
fail=0

ck() { # 名称 得到 想要
    if [ "$2" = "$3" ]; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi
}
ckhas() { # 名称 文本 子串
    if echo "$2" | grep -q "$3"; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (缺少 '$3')"; fi
}
ckhasnot() { # 名称 文本 子串
    if echo "$2" | grep -q "$3"; then fail=$((fail+1)); echo "✗ $1 (不该出现 '$3')";
    else pass=$((pass+1)); fi
}

rm -f "$ELF"
bash tools/kernel64.sh examples/kernel64.mo "$ELF" >/tmp/k64build.log 2>&1
rc=$?
ck "内核构建" "$rc" 0
[ -f "$ELF" ] || { echo "kern64test: 没有产物，无法继续"; exit 1; }

# 1) 机器类型必须是 AArch64（EM_AARCH64 = 183）
M=$(python3 -c "import struct;print(struct.unpack_from('<H',open('$ELF','rb').read(),18)[0])")
ck "ELF 机器类型 AArch64" "$M" 183

# 2) 前导必须是 ARM64 版：拿成 x86 的 VGA 版照样编得出来、跑起来无声无息
ckhas "前导含 UART MMIO" "$(cat "$C")" "uart_print"
ckhasnot "未落到 x86 VGA" "$(cat "$C")" "0xB8000"

# 3) 真正执行
OUT=$(python3 tools/kern64run.py "$ELF" 2>/dev/null)

ckhas "启动横幅" "$OUT" "MO-KERN64 BOOT"
ckhas "控制台声明" "$OUT" "mmio-uart@0x09000000"
ckhas "无宿主声明" "$OUT" "no libc / no syscall / no host os"
ckhas "fib(10)=55" "$OUT" "got=55 want=55"
ckhas "sum(1..100)=5050" "$OUT" "got=5050 want=5050"
ckhas "fib(20)=6765" "$OUT" "got=6765 want=6765"
ckhas "自检全过" "$OUT" "selftest passed: 3/3"
ckhas "停机标记" "$OUT" "MO-KERN64 HALT"
ckhasnot "没有 FAIL" "$OUT" "FAIL"

echo "kern64test: $pass 通过 / $fail 失败"
[ "$fail" = 0 ] || exit 1
exit 0
