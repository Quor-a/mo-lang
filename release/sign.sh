#!/bin/bash
# sign.sh —— 用 SSH 签名密钥对文件生成 .sig（ssh-keygen -Y sign）
# 用法: bash release/sign.sh <文件...>
# 产物: <每个文件>.sig（SSH SIG 格式， armored）
# 公钥: release/SIGNING_KEY.pub（已入库）；私钥 $HOME/.ssh/mo-release-signing-key（不入库）
# 注意: ssh-keygen 自己写 <file>.sig，且已存在时会交互询问 —— 先删旧文件，
#       stdout 重定向会把 "Overwrite (y/n)?" 提示抓进 .sig（实证坑）。
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="$HOME/.ssh/mo-release-signing-key"
NS="mo-release"
if [ ! -f "$KEY" ]; then
    echo "缺少签名私钥 $KEY（不应入库）。" >&2
    exit 1
fi
for f in "$@"; do
    [ -f "$f" ] || { echo "不存在: $f" >&2; exit 1; }
    rm -f "$f.sig"
    ssh-keygen -Y sign -f "$KEY" -n "$NS" "$f" >/dev/null 2>&1
    [ -s "$f.sig" ] || { echo "签名失败: $f" >&2; exit 1; }
    echo "已签: $f -> $f.sig"
done