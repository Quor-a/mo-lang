#!/bin/bash
# pkgv2test —— 包管理器的**升级 / 依赖 / 校验**在安卓（ARM64）与 x86-64 两端验证
#
#   make pkgv2test
#
# 验什么
# ------
# examples/pkgv2.mo 在 v1.155 的 pkgmgr（装/列/查/执行/卸）之上补了三件事：
#   · 版本比较与升级：1.0.0 → 2.0.0 允许；2.0.0 → 1.5.0 **必须被拒绝**
#   · 依赖解析：app → libB → libC，拓扑序必须是 **libC libB app**（后序）
#   · 完整性校验：CODE 被改写而清单没动时，verify 必须失败
#
# 为什么两端都跑
# --------------
# 这类"文件 IO + 号表翻译"的缺陷**只在一端暴露**：v1.155 的 getdents64
# 就是 x86 上恰好正确、ARM64 上发成了 add_key。只跑一端等于没验证翻译表。
#
# 判据为什么这样写
# ----------------
#   · 升级后 run 从 42 变 45：只改版本号而 CODE 没换的话，这里仍是 42
#   · 降级被拒后 run 仍是 45：若降级被静默接受，这里会变回 42
#   · 拓扑序按整行比对：只查"包含 app"分不清后序与前序
#   · 篡改后 verify 必须是 0：一个恒返回 1 的 verify 在这里就露馅
#   · 环/缺失依赖必须返回 -2：若只是"跳过访问中的节点"，会返回 0 且顺序少一个

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PASS=0
FAIL=0

ck() {   # ck <描述> <实际> <期望>
    if [ "$2" = "$3" ]; then
        echo "  ✓ $1 ($2)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $1 (得到 '$2' 想要 '$3')"
        FAIL=$((FAIL + 1))
    fi
}

# 行形如 "[4] run 2.0.0     out=45" → 取最后一个 '=' 之后的内容
val() { echo "$1" | grep -F "$2" | head -1 | sed 's/.*=//' | tr -d ' \r'; }

# 整行比对（去首尾空白）—— 用于拓扑序这种"内容里有空格"的行
line() { echo "$1" | grep -F "$2" | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

run_one() {
    local tag=$1 arch=$2 sim=$3
    local out rc

    rm -rf /tmp/mo_pkgs_v2          # 真机端会真建目录；不清理第二次必 EEXIST
    local bin=/tmp/pkgv2_$tag
    rm -f "$bin"
    if ! ARCH=$arch bash tools/android_native.sh examples/pkgv2.mo "$bin" \
            >/tmp/pkgv2_build_$tag.log 2>&1; then
        echo "  ✗ $tag 构建失败"
        tail -3 /tmp/pkgv2_build_$tag.log
        FAIL=$((FAIL + 2))
        return
    fi

    if [ "$sim" = "yes" ]; then
        out=$(python3 tools/armrun.py "$bin" 2>&1)
        rc=$?
    else
        out=$("$bin" 2>&1)
        rc=$?
    fi

    echo "[$tag] 退出码=$rc"
    ck "$tag 退出码"        "$rc" "0"
    ck "$tag pkg ok"        "$(val "$out" 'pkg ok = ')"         "1"
    ck "$tag 装 libC"       "$(val "$out" '[1] install libC')"  "0"
    ck "$tag 装 libB"       "$(val "$out" '[1] install libB')"  "1"
    ck "$tag 装 app"        "$(val "$out" '[1] install app')"   "2"
    ck "$tag 依赖个数"      "$(val "$out" '[2] topo n')"        "3"
    ck "$tag 拓扑序(后序)"  "$(line "$out" '[2] topo order')"   "[2] topo order    =libC libB app"
    ck "$tag 未篡改校验"    "$(val "$out" '[3] verify app')"    "1"
    ck "$tag 升级前 run"    "$(val "$out" '[4] run 1.0.0')"     "42"
    ck "$tag 升级 ret"      "$(val "$out" '[4] upgrade ret')"   "0"
    ck "$tag 升级后版本"    "$(val "$out" '[4] ver after')"     "2.0.0"
    ck "$tag 升级后 run"    "$(val "$out" '[4] run 2.0.0')"     "45"
    ck "$tag 升级后校验"    "$(val "$out" '[4] verify after')"  "1"
    ck "$tag 降级被拒"      "$(val "$out" '[5] downgrade ret')" "-1"
    ck "$tag 降级后版本"    "$(val "$out" '[5] ver after')"     "2.0.0"
    ck "$tag 降级后 run"    "$(val "$out" '[5] run after')"     "45"
    ck "$tag 篡改后校验"    "$(val "$out" '[6] tamper verify')" "0"
    ck "$tag 环检测"        "$(val "$out" '[7] cycle ret')"     "-2"
    ck "$tag 环标志"        "$(val "$out" '[7] cycle flag')"    "1"
    ck "$tag 缺失依赖"      "$(val "$out" '[8] missing ret')"   "-2"
    # VM 边界：损坏 / 恶意的包必须响亮失败。
    # 未修复时这五项**全部返回 0**（静默），连栈上溢把 VM_OUT 写坏都不出声。
    ck "$tag 合法包"        "$(line "$out" '[9a] legal')"       "[9a] legal     ret=0 out=42"
    ck "$tag ADD 下溢"      "$(val "$out" '[9b] underflow')"    "-2"
    ck "$tag PRINT 下溢"    "$(val "$out" '[9c] print uf')"     "-2"
    ck "$tag 立即数截断"    "$(val "$out" '[9d] trunc')"        "-4"
    ck "$tag 栈上溢"        "$(val "$out" '[9e] overflow')"     "-3"
    ck "$tag VM 边界总"     "$(val "$out" '[9] vmguard')"       "1"
    # 打包分发：包在没有 git / 仓库的环境里能不能传出去、装回来
    # · 删掉 CODE 后 run 必须是 -1，解包后必须回到 42：
    #   否则"解包成功"可能只是改了内存里的注册表，文件压根没写回
    # · 篡改/截断/非法字符/超大 各自有码：统一成 -1 就分不清重传与拒收
    ck "$tag 装 dist"       "$(val "$out" '[10] install dist')" "6"
    ck "$tag 打包"          "$(val "$out" '[10] pack ret')"     "0"
    ck "$tag 可传输流"      "$(line "$out" '[10] stream')" \
        "[10] stream       =MOPK1|dist|1.0.0||0000000d|01060000000107000000040300|cb7a9049"
    ck "$tag 删后 run"      "$(val "$out" '[10] run deleted')"  "-1"
    ck "$tag 解包"          "$(val "$out" '[10] unpack ret')"   "6"
    ck "$tag 解包后 run"    "$(val "$out" '[10] run restored')" "42"
    ck "$tag 篡改"          "$(val "$out" '[10] tamper ret')"   "-6"
    ck "$tag 截断"          "$(val "$out" '[10] trunc ret')"    "-5"
    ck "$tag 非法 hex"      "$(val "$out" '[10] badhex ret')"   "-8"
    ck "$tag 超出容量"      "$(val "$out" '[10] toobig ret')"   "-7"
}

echo "=== 包管理器 v2：升级 / 依赖 / 校验（ARM64 模拟器 / x86-64 真机）==="
run_one arm64 aarch64 yes
run_one x86   x86_64  no

echo
echo "通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
