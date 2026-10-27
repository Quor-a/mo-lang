#!/usr/bin/env python3
"""检查 rootfs 里的用户态翻译器是否自包含。

退出码：
  0 = 静态链接（不需要任何外部文件）
  1 = 动态链接但 loader 与依赖库在 rootfs 里齐备
  4 = 需要 loader 但 rootfs 里没有
  5 = 依赖库缺失
  6 = 不是 ELF / 不存在
真机实测（2026-10-24）：box64 是 aarch64 PIE，rootfs 里既没有
ld-linux 也没有 lib/，execve 直接 ENOENT（文件明明在）—— 就是 4。
"""
import struct, os, sys, subprocess

def interp(exe):
    d = open(exe, 'rb').read()
    if d[:4] != b'\x7fELF':
        return None, None
    phoff, = struct.unpack_from('<Q', d, 0x20)
    phes, phn = struct.unpack_from('<HH', d, 0x36)
    for i in range(phn):
        off = phoff + i * phes
        if struct.unpack_from('<I', d, off)[0] == 3:      # PT_INTERP
            po, = struct.unpack_from('<Q', d, off + 8)
            pf, = struct.unpack_from('<Q', d, off + 32)
            return d[po:po + pf].rstrip(b'\x00').decode(), d
    return "", d

def main():
    root, exe = sys.argv[1], sys.argv[1] + "/box64"
    if not os.path.exists(exe):
        print("no-translator"); return 0
    need, d = interp(exe)
    if need is None:
        print("not-elf"); return 6
    if need == "":
        print("static"); return 0
    if not os.path.exists(root + need):
        print("missing-loader", need); return 4
    miss = []
    out = subprocess.run(["ldd", exe], capture_output=True, text=True).stdout
    for ln in out.splitlines():
        if "=>" not in ln:
            continue
        p = ln.split("=>", 1)[1].strip().split(" (")[0].strip()
        if p.startswith("/") and not os.path.exists(root + p):
            miss.append(p)
    if miss:
        print("missing-lib", miss); return 5
    print("dynamic-ok loader=%s" % need); return 1

sys.exit(main())
