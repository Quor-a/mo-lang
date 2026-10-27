#!/bin/bash
# mkrootfs —— 生成可 proot 运行的墨语言 rootfs（自包含、开箱即用）
#
#   bash tools/mkrootfs.sh [OUT]          # 默认 /tmp/mo_rootfs
#
# 为什么需要它：proot 起容器时，翻译器、工作目录、目录权限这三样
# 任何一样不对，症状都是"墨语言工具链跑不起来"，而报错指向别处：
#
#   1. 翻译器（box64/qemu）若是**动态链接**的，rootfs 里必须带上它的
#      loader 与全部依赖库，否则 execve 返回 ENOENT（"文件不存在"），
#      而文件明明就在那 —— 真机实测 2026-10-24：box64 是 aarch64 PIE，
#      rootfs 里没有 ld-linux 也没有 lib/，于是必然 ENOENT。
#      这里做的是：动态链接就**解析 ldd 并把依赖全部复制进去**，
#      解析不出来就报错退出，不做"大概能跑"的猜测。
#   2. proot 会 chdir 到工作目录（常见是 /work）。目录不存在时
#      报 can't chdir to '/work' —— 与工具链毫无关系。
#   3. rootfs 顶层若为 700，proot 的 tracee 以 app uid 运行时进不去，
#      报的是 Permission denied，同样指向不到权限本身。
#
# 所以本脚本**显式**建 work/、显式 chmod 755，并对翻译器做自包含校验。
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-/tmp/mo_rootfs}
HOST=$(uname -m)

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/work" "$OUT/etc" "$OUT/boot" "$OUT/tmp"

# ---------- 1. 工具链 ----------
for t in moc mo2x molink mols modb dwmo mo2c; do
    [ -x "$ROOT/bin/$t" ] && cp "$ROOT/bin/$t" "$OUT/bin/" || true
done
[ -f "$OUT/bin/moc" ] || { echo "mkrootfs: 缺少 bin/moc，先 make"; exit 1; }

# ---------- 2. 标准库 ----------
cp "$ROOT"/lib/*.mo "$OUT/lib/" 2>/dev/null || true
[ -f "$OUT/lib/io.mo" ] || { echo "mkrootfs: 缺少 lib/io.mo"; exit 1; }

# ---------- 3. 翻译器：宿主架构 != 目标架构时才需要 ----------
# 墨语言的工具链本机编出来是 x86_64 静态 ELF；在 arm64 设备上要跑它
# 必须有个用户态翻译器。策略：
#   静态 qemu-x86_64-static  >  动态 qemu  >  box64（必须补依赖）
XLATE=""
for c in qemu-x86_64-static qemu-x86_64 box64; do
    command -v "$c" >/dev/null 2>&1 && { XLATE=$(command -v "$c"); break; }
done
if [ "$HOST" = "x86_64" ] || [ "$HOST" = "amd64" ]; then
    echo "mkrootfs: 宿主 $HOST，工具链可直接执行，不需要翻译器"
else
    [ -n "$XLATE" ] || { echo "mkrootfs: 宿主 $HOST 需要翻译器（qemu-x86_64-static / box64），未找到"; exit 1; }
    cp "$XLATE" "$OUT/box64"
    chmod 755 "$OUT/box64"
    # 自包含校验：读 ELF 头看有没有 .interp（= 是否需要 loader）
    python3 - "$OUT/box64" "$OUT" <<'PY'
import struct, sys, os, subprocess, shutil
exe, root = sys.argv[1], sys.argv[2]
d = open(exe,'rb').read()
assert d[:4] == b'\x7fELF', "翻译器不是 ELF"
# 遍历程序头找 PT_INTERP(3)
e_phoff, = struct.unpack_from('<Q', d, 0x20)
e_phentsize, e_phnum = struct.unpack_from('<HH', d, 0x36)
need = None
for i in range(e_phnum):
    off = e_phoff + i*e_phentsize
    p_type, = struct.unpack_from('<I', d, off)
    if p_type == 3:
        p_offset, = struct.unpack_from('<Q', d, off+8)
        p_filesz, = struct.unpack_from('<Q', d, off+32)
        need = d[p_offset:p_offset+p_filesz].rstrip(b'\x00').decode()
        break
if need is None:
    print("  翻译器静态链接，自包含 ✓")
    sys.exit(0)
print("  翻译器需要 loader:", need)
os.makedirs(root+"/lib", exist_ok=True)
# 复制 loader
src = need if os.path.exists(need) else None
if src is None:
    for base in ("/lib", "/usr/lib", "/lib64", "/usr/lib64"):
        c = base + "/" + os.path.basename(need)
        if os.path.exists(c): src = c; break
if src is None:
    print("  ✗ 找不到 loader", need); print("    （这正是 execve 报 ENOENT 的根因）")
    sys.exit(1)
shutil.copy2(src, root + need); os.chmod(root+need, 0o755)
print("  loader ✓", need)
# 复制依赖库
out = subprocess.run(["ldd", exe], capture_output=True, text=True).stdout
n = 0
for ln in out.splitlines():
    ln = ln.strip()
    if "=>" not in ln: continue
    right = ln.split("=>",1)[1].strip()
    path = right.split(" (")[0].strip()
    if not path.startswith("/"): continue
    if not os.path.exists(path):
        print("  ✗ 依赖缺失:", path); sys.exit(1)
    dst = root + path
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(path, dst); os.chmod(dst, 0o755); n += 1
print("  依赖库 ✓", n, "个")
PY
    [ $? -eq 0 ] || { echo "mkrootfs: 翻译器自包含校验失败"; exit 1; }
fi

# ---------- 4. 元数据 ----------
cat > "$OUT/etc/motd" <<M
墨语言 rootfs（proot 运行环境）
宿主架构: $HOST
生成时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
M
cat > "$OUT/etc/uspace.conf" <<M
work=/work
bin=/bin
lib=/lib
M
printf 'molang-rootfs %s\n' "$(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)" > "$OUT/VERSION"

# ---------- 5. 权限：proot tracee 常被降权，700 会让它进不去 ----------
chmod -R a+rX "$OUT"
chmod 755 "$OUT" "$OUT/bin" "$OUT/lib" "$OUT/work" "$OUT/etc" "$OUT/tmp" "$OUT/boot"

echo "mkrootfs: $OUT"
echo "  bin/  : $(ls "$OUT/bin" | tr '\n' ' ')"
echo "  lib/  : $(ls "$OUT/lib" | wc -l) 个 .mo"
echo "  work/ : $([ -d "$OUT/work" ] && echo 存在 || echo 缺失)"
