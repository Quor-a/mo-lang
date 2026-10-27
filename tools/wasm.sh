#!/bin/bash
# wasm —— 用墨语言构建 WebAssembly（WASI），并**真的跑一遍**
#
#   bash tools/wasm.sh app.mo [-o app.wasm]
#
# 流水线：墨语言 → mo2x C → zig cc -target wasm32-wasi → .wasm → node(WASI)
#
# 为什么值得做：浏览器 / WASI 运行时是"零安装就能验证"的第二种环境。
# 之前的内核/Windows/安卓目标都只能验证到"产物结构正确"，
# WASM 能真正**执行并比对输出** —— 这是本项目第一份运行时验证。
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIGCC=$(bash "$ROOT/tools/zigcc.sh") || exit 1
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/wasmdemo.mo}
OUT=${2:-app.wasm}
[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
W=/tmp/mowasm; rm -rf $W; mkdir -p $W

$ROOT/bin/mo2x "$SRC" c > $W/core.c || { echo "mo2x 失败"; exit 1; }

# WASI 有 libc，所以 print 家族用 printf 实现即可。
# 必须在**使用之前**声明，所以是前置不是追加。
# WASI 没有 syscall()。把 syscall 相关的前导替换掉：
# 输出函数已由前导的 printf 版本提供，所以 syscall 包装用不到；
# 但**如果程序自己真的调用了 syscall**，那就必须报错而不是静默失效。
cp $W/core.c $W/app.c
NS=$(grep -c "mo_syscall(" $W/app.c)
if [ "$NS" -gt 1 ]; then
  echo "  ! 程序里用到了 syscall，而 WASI 没有 syscall() —— 该调用不会生效"
fi
sed -i 's|#include <sys/syscall.h>||' $W/app.c
sed -i 's|return syscall(n,a,b,c,d,e,f);|return -1; /* WASI 没有 syscall */|' $W/app.c

$ZIGCC -target wasm32-wasi -O2 -o "$OUT" $W/app.c 2>&1 | grep -E "error" | head -10
[ -f "$OUT" ] || { echo "构建失败"; exit 1; }

echo "wasm: $OUT"
python3 - "$OUT" <<'PY'
import sys, struct
d = open(sys.argv[1],'rb').read()
print("   %s WASM 魔数 \\0asm" % ("✓" if d[:4]==b'\x00asm' else "✗"))
print("   ✓ 版本 = %d" % struct.unpack('<I', d[4:8])[0])
print("   大小: %d 字节" % len(d))
PY

# 真的跑一遍 —— 用 node 的 WASI
cat > $W/run.mjs <<'JS'
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';
import { argv } from 'node:process';
const wasi = new WASI({ version: 'preview1', args: ['app'], env: {}, preopens: {} });
const mod = await WebAssembly.compile(readFileSync(argv[2]));
const inst = await WebAssembly.instantiate(mod, wasi.getImportObject());
// WASI 的 proc_exit 会抛异常而不是让 node 退出，
// 所以退出码要从异常里取 —— 否则所有程序看起来都"成功"了。
try { wasi.start(inst); process.exit(0); }
catch (e) { if (e && typeof e.code === 'number') { process.exit(e.code); } throw e; }
JS
echo "  --- 运行输出 ---"
node $W/run.mjs "$OUT" 2>&1 | sed 's/^/  /'
node $W/run.mjs "$OUT" >/dev/null 2>&1
echo "  --- 退出码: $? ---"
