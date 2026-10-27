#!/usr/bin/env bash
# mokern64mut —— 证明 tools/mokern64.sh 真的能抓到缺陷
#
# 每个变异都是"改一行看起来无害的代码"，测试必须变红。改了代码却测不出
# 变化，往往不是代码对，而是判据瞎。
#
# M6 是这一轮专门加的：它让**两端产物一起错**，md5 照样相同 —— 如果
# "两端一致"就是全部判据，M6 会被判成通过。专门盯它的那一项（单独校验
# ARM64 端产物的 e_machine）必须红，否则那一层就是摆设。
#
# 🔴 顺序是硬的：先还原源码，**再**跑测试。v1.177 在这里栽过 —— 顺序写反
# 时二进制里留着上一个变异的坏后端，此后每个变异都在污染态上跑，"被捕获"
# 只是撞上前面的残留，脚本却给出漂亮分数。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=examples/mokern.mo
BAK=/tmp/mokern64.mo.bak
cp $SRC $BAK
CAP=0; MISS=0

apply() { python3 - "$1" "$2" <<'PY'
import sys
p='examples/mokern.mo'
s=open(p).read()
old,new=sys.argv[1],sys.argv[2]
if old not in s:
    print("ANCHOR MISSING: "+old); sys.exit(3)
open(p,'w').write(s.replace(old,new,1))
PY
}

run() {
    local name=$1
    local out
    out=$(bash tools/mokern64.sh 2>&1 | tail -1)
    cp $BAK $SRC
    # 🔴 判据字符串必须与被测脚本的输出格式**逐字**对上。
    # 这里沿用了 mokerntest 的 "失败 0 项"，而 mokern64.sh 输出的是
    # "19 通过 / 0 失败" —— 两边对不上，于是**所有变异都被判成"被捕获"**，
    # 连 M5 这种实测 19 通过 / 0 失败（测试全过＝真没抓到）的也报 ✓。
    # 又是一例"验证机制假装验证并给出漂亮分数"。
    # 也不能只 grep "0 失败"："10 失败" 里同样含 "0 失败"（v1.164 记过）。
    if echo "$out" | grep -qE '/ 0 失败$'; then
        echo "✗ $name 未被捕获：$out"
        MISS=$((MISS+1))
    else
        echo "✓ $name 被捕获：$out"
        CAP=$((CAP+1))
    fi
}

# M1：data abort 的返回地址不 +4 → 出错指令原地重来 → 死循环，永远到不了 DONE
apply 'addi(0, 0, 4);                 # 返回地址 +4' \
      'addi(0, 0, 0);                 # 返回地址 +4'
run "M1 abort 返回地址不 +4"

# M2：内核私有块的 AP 从 00 改成 01 → 越权不再被拦，PF2 消失
apply 'ld64(9, 1025, 0, 16448, 64);' \
      'ld64(9, 1089, 0, 16448, 64);'
run "M2 内核私有块 AP=00→01"

# M3：_start 里不设 elr_el1 → eret 跳到 0，用户任务根本不起来
apply '    msr_(49665, 0);                # msr elr_el1, x0' \
      '    movz_(0, 0, 0);                # msr elr_el1, x0'
run "M3 不设 elr_el1"

# M4：UART 地址装错半字 → 字符写进 0x0900 而不是 0x09000000，一行都打不出
apply '    ldaddr(25, 2304);              # 0x09000000' \
      '    movz_(25, 2304, 0);            # 0x09000000'
run "M4 UART 地址装错半字"

# M5：不建内核私有块 → EL0 访问变成转换错误而不是权限错误，PF2 不该出现
apply '    strx(9, 14, 16);' \
      '    movz_(9, 0, 0);'
run "M5 不建内核私有块描述符"

# M6：EM_AARCH64(183) 写成 EM_X86_64(62) → **两端产物一起错**，md5 仍相同。
# 只能被"单独校验 ARM64 端产物 e_machine"和裸机加载器抓到。
apply '    st16(18, 183);                 # EM_AARCH64' \
      '    st16(18, 62);                  # EM_AARCH64'
run "M6 e_machine 写成 x86-64"

# M7：跳过写回（但仍 close）→ 程序退出码 0、统计打印正常，产物却是 0 字节。
# 盯它的是"ARM64 端执行（产物非空）"与"产物非空（> 1024 字节）"。
apply '    let w: i64 = syscall(1, fd, &OUT, total, 0, 0, 0);' \
      '    let w: i64 = total;'
run "M7 跳过写回但仍报成功"

cp $BAK $SRC
echo "捕获 $CAP 个，未捕获 $MISS 个"
exit $((MISS > 0))
