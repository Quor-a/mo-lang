#!/bin/bash
# molink —— 把 -c 产出的 .o 与 libc 链接成可执行文件
#
# 为什么要固定 section 地址：
#   编译器代码里嵌的是**绝对地址**（movabs rax, 0x10000000+off），
#   而 .o 里 .data 的地址是 0。所以链接时必须把 .data 放回
#   0x10000000，否则全局变量全部错位 —— 而且不报错，只是读到垃圾。
#
#   .text **不能**固定：ld 会把 .interp / .dynsym / .plt 等放在
#   0x400000 之后，强行把 .text 钉在 0x4000b0 会与之重叠，
#   ld 报 "overlaps section .text"，或者静默生成错文件后一跑就段错误。
#   内部调用用的是 rel32，在同一 section 内平移不变，所以 .text
#   放到哪儿都行。
set -e
OBJ=""
OUT=""
LINK_LIBC=1
if [ "$1" = "-shared" ] || echo "$@" | grep -q -- "-shared"; then
  MODE=so
fi
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -shared) shift ;;          # 不能落进 *) 否则会把 OBJ 覆盖成 "-shared"
        -nostdlib) LINK_LIBC=0; shift ;;
        *) OBJ="$1"; shift ;;
    esac
done
if [ "$MODE" = "so" ]; then
  : "${OUT:=libmo.so}"
  ld -shared -o "$OUT" "$OBJ"
  echo "linked: $OUT"
  exit 0
fi
if [ -z "$OBJ" ]; then echo "usage: molink.sh prog.o -o prog"; exit 1; fi
if [ -z "$OUT" ]; then OUT="${OBJ%.o}"; fi

DYNLINK=$(ls /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 2>/dev/null | head -1)

# libatomic：CAS / atomic load / store 的符号（lib/lf.mo 用）。
#   ld 的默认搜索路径里通常没有它（-latomic 会报 cannot find），
#   而 gcc 有 —— 所以借 gcc 问出真实路径再直接塞给 ld。
ATOMIC=""
if command -v gcc >/dev/null 2>&1; then
    A=$(gcc -print-file-name=libatomic.so 2>/dev/null)
    if [ -n "$A" ] && [ -f "$A" ] && [ "${A#libatomic.so}" != "$A" ]; then :; fi
    if [ -n "$A" ] && [ -f "$A" ] && [ "$A" != "libatomic.so" ]; then
        ATOMIC="$A"
    else
        A=$(gcc -print-file-name=libatomic.so.1 2>/dev/null)
        if [ -n "$A" ] && [ -f "$A" ] && [ "$A" != "libatomic.so.1" ]; then ATOMIC="$A"; fi
    fi
fi

if [ "$LINK_LIBC" = "1" ]; then
    ld --section-start=.data=0x10000000 \
       -e _start -o "$OUT" "$OBJ" -lc -lpthread ${ATOMIC:+"$ATOMIC"} \
       --dynamic-linker="$DYNLINK"
else
    HERE=$(cd "$(dirname "$0")" && pwd)
    RT=$(mktemp -d)/mocrt.o
    as -o "$RT" "$HERE/mocrt.s"
    ld --section-start=.data=0x10000000 \
       -e _start -o "$OUT" "$OBJ" "$RT"
fi
chmod +x "$OUT"
echo "linked: $OUT"
