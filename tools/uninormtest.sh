#!/usr/bin/env bash
# uninormtest —— uninorm.mo 与 Python unicodedata 的**全量独立参照**比对
#
# 为什么需要它：tests/146_uninorm.mo 里的断言是挑出来的十几个具体值，
# 值对了不代表区间表没错位、排序没漏段。这里把覆盖段内约 1.2 万个
# 码点、外加 540 条多记号序列的 NFD/NFC 全部打出来，由 Python 用
# unicodedata 独立算一遍期望，逐行比对。
#
# 期望由 Python 现算，不落在仓库里 —— 换一台机器、换一个 Unicode 版本
# 都能重算，不会出现「期望文件陈旧但仍全绿」。

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MOC="$HERE/bin/moc"
TMP=/tmp/mot_uninorm

rm -rf "$TMP" && mkdir -p "$TMP"
cp "$HERE"/lib/*.mo "$TMP"/ 2>/dev/null
cp "$HERE"/tools/uninormdump.mo "$TMP"/test.mo

( cd "$TMP" && "$MOC" ) >/dev/null 2>&1
if [ ! -f "$TMP/out.elf" ]; then
    echo "uninormtest: 编译失败"
    exit 1
fi
chmod +x "$TMP/out.elf"
( cd "$TMP" && timeout 120 ./out.elf ) > "$TMP/got.txt"
rc=$?
if [ $rc -ne 0 ]; then
    echo "uninormtest: uninormdump 退出码 $rc"
    exit 1
fi

python3 "$HERE/tools/uninormref.py" "$TMP/got.txt"
