#!/usr/bin/env bash
# unitest —— uni.mo 与 Python unicodedata 的**全量独立参照**比对
#
# 为什么需要它：tests/145_uni.mo 里的断言是挑出来的几十个具体值，
# 值对了不代表区间表没错位。这里让 unidump 把覆盖段内 23440 个码点的
# 分类与大小写全部打印出来，由 Python 用 unicodedata 独立算一遍期望，
# 逐行比对。
#
# 期望由 Python 现算，不落在仓库里 —— 换一台机器、换一个 Unicode 版本
# 都能重算，不会出现「期望文件陈旧但仍全绿」。

set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MOC="$HERE/bin/moc"
TMP=/tmp/mot_uni

rm -rf "$TMP" && mkdir -p "$TMP"
cp "$HERE"/lib/*.mo "$TMP"/ 2>/dev/null
cp "$HERE"/tools/unidump.mo "$TMP"/test.mo

( cd "$TMP" && "$MOC" ) >/dev/null 2>&1
if [ ! -f "$TMP/out.elf" ]; then
    echo "unitest: 编译失败"
    exit 1
fi
chmod +x "$TMP/out.elf"
( cd "$TMP" && ./out.elf ) > "$TMP/got.txt"
rc=$?
if [ $rc -ne 0 ]; then
    echo "unitest: unidump 退出码 $rc"
    exit 1
fi

python3 "$HERE/tools/uniref.py" "$TMP/got.txt"
