#!/bin/bash
# pkgv2mut —— 证明 pkgv2test 的判据**真的会响**（变异验证）
#
#   make pkgv2mut
#
# 为什么必须做这一步
# ------------------
# 本项目反复栽在"验证机制自身静默失效"上：测试恒绿，但一条都没验到。
# 所以每个新测试都要配一组"把实现改回缺陷状态"的变异，确认判据会变红。
# 下面是六个变异，每一个都对应一条"看起来装上了、其实没有"的失败形态。
#
# 变异都在 examples/pkgv2.mo 上（不动编译器），所以不需要重建 bin/mo2x；
# 但 android_native.sh 每次都会重新生成产物，中间文件必须清掉。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build

PKG=examples/pkgv2.mo
cp -f "$PKG" build/pkgv2mut.bak

restore() {
    cp -f build/pkgv2mut.bak "$PKG"
    # 清掉上一次的产物：若留着，构建脚本可能因为时间戳相同而跳过重建，
    # 于是测的是**上一个变异**的二进制（v1.135 记过）。
    rm -f /tmp/pkgv2_arm64 /tmp/pkgv2_x86
    rm -rf /tmp/mo_pkgs_v2
}
trap restore EXIT INT TERM

# 应用一次替换（Python 精确子串，不用 sed 正则 —— 正则的空格/转义差异
# 会让"手工验证能匹配、脚本里却恒判未生效"）
apply() {   # apply <文件> <旧> <新> <变异名> [all]
    python3 - "$1" "$2" "$3" "$4" "${5:-one}" <<'PYEOF'
import sys
path, old, new, name, mode = sys.argv[1:6]
s = open(path).read()
c = s.count(old)
if c == 0:
    sys.stderr.write("锚点未找到：%s\n" % name)
    sys.exit(1)
if c != 1 and mode != "all":
    sys.stderr.write("锚点不唯一(%d 处)：%s\n" % (c, name))
    sys.exit(1)
open(path, 'w').write(s.replace(old, new))
print("   已注入 %s（%d 处）" % (name, c))
PYEOF
}

echo "=== pkgv2 变异验证 ==="

# ---- 基线 ----
restore
if bash tools/pkgv2test.sh >/tmp/pkgv2mut_base.log 2>&1; then
    echo "  ✓ 基线通过（$(tail -1 /tmp/pkgv2mut_base.log)）"
else
    echo "  ✗ 基线就没通过 —— 后面的变异全部无意义"
    tail -20 /tmp/pkgv2mut_base.log
    exit 1
fi

CAP=0
TOT=0

run_mut() {   # run_mut <名> <文件> <旧> <新> [all]
    TOT=$((TOT + 1))
    restore
    if ! apply "$2" "$3" "$4" "$1" "${5:-one}"; then
        echo "  ✗ $1 无法注入"
        return
    fi
    if bash tools/pkgv2test.sh >/tmp/pkgv2mut_$1.log 2>&1; then
        echo "  ✗ $1 未被捕获（测试仍然全绿 = 判据没验到它）"
    else
        echo "  ✓ $1 被捕获（$(grep -c '✗' /tmp/pkgv2mut_$1.log) 项变红）"
        CAP=$((CAP + 1))
    fi
}

# M1：降级保护失效 —— 2.0.0 → 1.5.0 被静默接受，版本回退、CODE 也回退
run_mut M1 "$PKG" \
    "    if vcmp(ver, &OV) <= 0 { return -1; }      # 降级 / 同版本：拒绝" \
    "    if 0 == 1 { return -1; }"

# M2：upgrade 只改清单、不重写 CODE —— 版本号变成 2.0.0，跑出来仍是 42
run_mut M2 "$PKG" \
    "    if write_file_bytes(&P, &CB, CBN) != CBN { return -2; }" \
    "    if 1 == 1 { }"

# M3：校验和退化成"只看长度" —— 篡改前后字节码长度相同，于是验不出来
run_mut M3 "$PKG" \
    "        h = h + load8(p + i);" \
    "        h = h + 0;"

# M4：环检测失效（访问中就直接返回）—— 循环依赖被静默接受，顺序表还少一项
run_mut M4 "$PKG" \
    "    if MARK[i] == 1 { CY = 1; return -2; }" \
    "    if MARK[i] == 1 { return 0; }"

# M5：顺序表被倒着填 —— 拓扑序变成 app libB libC（依赖还没装就先装自己）
run_mut M5 "$PKG" \
    "    ORD[ON] = i;
    ON = ON + 1;" \
    "    ORD[7 - ON] = i;
    ON = ON + 1;"

# M6：依赖缺失时静默跳过 —— 装一个依赖不存在的包，返回"成功"
run_mut M6 "$PKG" \
    "                    if di < 0 { return -3; }   # 依赖缺失：明确报错，不静默跳过" \
    "                    if di < 0 { di = 0; }"

# ---- 打包分发（v1.158）----
#
# 这四个变异对应"包被传输"时四种不同的坏法。它们的共同点是：
# 包管理器都能"装上"，但装上去的东西是错的。分开的意义在于
# 调用方要做的事完全不同——重传 / 拒收 / 换渠道 / 报太大。

# M7：不核对长度字段与实际 hex 长度 —— 传输被截断的包被当成完整包装上
run_mut M7 "$PKG" \
    "    if slen(&HH) != len * 2 { return -5; }" \
    "    if 0 == 1 { return -5; }"

# M8：不比校验和 —— 被篡改的包照样装成功
run_mut M8 "$PKG" \
    "    if fnv1a(&UBUF, UBN) != ck { return -6; }" \
    "    if 0 == 1 { return -6; }"

# M9：容量检查挪到长度检查之后 —— 超大包被报成"被截断"，调用方会无限重传
run_mut M9 "$PKG" \
    "    if len > 64 { return -7; }
    if len < 0 { return -7; }
    # 长度字段必须与实际 hex 长度逐字符相符
    if slen(&HH) != len * 2 { return -5; }" \
    "    # 长度字段必须与实际 hex 长度逐字符相符
    if slen(&HH) != len * 2 { return -5; }
    if len > 64 { return -7; }
    if len < 0 { return -7; }"

# M10：非法 hex 不再报错 —— 格式坏的包被当成内容坏，还可能直接装上去
run_mut M10 "$PKG" \
    "    if c >= 97 {
        if c <= 102 { return c - 97 + 10; }
    }
    return -1;
}" \
    "    if c >= 97 {
        if c <= 102 { return c - 97 + 10; }
    }
    return 0;
}"

# M11：打包时每字节只写高位 4 bit —— 包在生成阶段就已经是残缺的，
#      但 unpack 会因为长度对不上而拒收（若不拒收，就是静默装上半个包）
run_mut M11 "$PKG" \
    "        store8(dst + o, hexch(hi));
        store8(dst + o + 1, hexch(c - hi * 16));
        o = o + 2;" \
    "        store8(dst + o, hexch(hi));
        o = o + 1;"

restore
echo
echo "捕获 $CAP / $TOT 个变异"
[ "$CAP" -eq "$TOT" ] || exit 1
exit 0
