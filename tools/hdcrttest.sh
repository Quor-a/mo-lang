#!/bin/bash
# hdcrttest —— 单独跑 HDC retrain 测试（make test 已覆盖，这里便于调试）
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/hdcrtt
rm -rf "$W" && mkdir -p "$W" && cp "$HERE"/lib/*.mo "$W/"
cp "$HERE/tests/124_hdcrt.mo" "$W/test.mo"
( cd "$W" && "$HERE/bin/moc" test.mo out.elf ) >/dev/null 2>&1 || { echo "编译失败"; exit 1; }
chmod +x "$W/out.elf"
( cd "$W" && ./out.elf )
