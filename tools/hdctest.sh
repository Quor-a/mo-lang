#!/bin/bash
# hdctest —— 单独跑 HDC 测试（make test 已覆盖，这里便于调试）
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W=/tmp/hdct
rm -rf "$W" && mkdir -p "$W" && cp "$HERE"/lib/*.mo "$W/"
cp "$HERE/tests/123_hdc.mo" "$W/test.mo"
( cd "$W" && "$HERE/bin/moc" test.mo out.elf ) >/dev/null 2>&1 || { echo "编译失败"; exit 1; }
chmod +x "$W/out.elf"
( cd "$W" && ./out.elf )
