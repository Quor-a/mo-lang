#!/usr/bin/env python3
"""codesize —— 墨语言产物代码段体积与冗余模式度量

为什么单做：
    项目目标之一是"代码体积还有 30%+ 压缩空间"。但**没有度量就没有优化** ——
    拍脑袋说"这里能省"很容易省了个寂寞。这个脚本给出基线与各冗余模式的
    实际占比，让每一点优化都可量化、可回归。

用法：
    python3 tools/codesize.py <elf>          # 报告
    python3 tools/codesize.py <elf> --json   # 机器可读

⚠️ 墨语言生成的 ELF 有两个 PT_LOAD：
    ph0 = 代码段（vaddr 0x400000），ph1 = 数据段（vaddr 0x10000000）
    只统计代码段，否则会把数据段字节当成指令，模式统计全是假的。
"""
import struct, sys, json

def read_code(path):
    d = open(path, 'rb').read()
    e_phoff = struct.unpack('<Q', d[0x20:0x28])[0]
    e_phentsize = struct.unpack('<H', d[0x36:0x38])[0]
    e_phnum = struct.unpack('<H', d[0x38:0x3a])[0]
    total = 0
    blobs = []
    for i in range(e_phnum):
        o = e_phoff + i * e_phentsize
        typ = struct.unpack('<I', d[o:o+4])[0]
        off = struct.unpack('<Q', d[o+0x08:o+0x10])[0]
        vaddr = struct.unpack('<Q', d[o+0x10:o+0x18])[0]
        filesz = struct.unpack('<Q', d[o+0x20:o+0x28])[0]
        if typ == 1 and vaddr == 0x400000:      # 只取代码段
            blobs.append(d[off:off+filesz])
            total += filesz
    return b''.join(blobs), total, len(d)

# 冗余模式：(名字, 字节, 可省字节数)
# 只列**确认安全可删**的：等长替换没有体积收益，跨基本块的要先证明可达。
PATS = [
    ("push rbx / pop rbx（保存后未使用）", b'\x53\x5b', 2),
    ("push rax / pop rax",                 b'\x50\x58', 2),
    ("mov rsi,rax / mov rax,rsi",          b'\x48\x89\xc6\x48\x89\xf0', 3),
    ("mov rbx,rax / mov rax,rbx",          b'\x48\x89\xc3\x48\x89\xd8', 3),
    ("mov rax,rax",                        b'\x48\x89\xc0', 3),
    ("jmp 到下一条指令（跳过 0 字节）",      b'\xeb\x00', 2),
]

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 1
    path = sys.argv[1]
    code, csize, fsize = read_code(path)
    if csize == 0:
        print(f"{path}: 未找到代码段（vaddr 0x400000）"); return 1
    rows = []
    saved = 0
    for name, pat, sbytes in PATS:
        n = code.count(pat)
        if n:
            rows.append((name, n, n * sbytes))
            saved += n * sbytes
    if '--json' in sys.argv:
        print(json.dumps({"file": path, "code": csize, "whole": fsize,
                          "saved": saved, "pct": round(saved * 100.0 / csize, 2),
                          "pats": [{"n": a, "c": b, "s": c} for a, b, c in rows]}))
        return 0
    print(f"{path}")
    print(f"  代码段 : {csize} 字节（整个文件 {fsize}）")
    for name, n, s in rows:
        print(f"    {name}: {n} 处，省 {s} 字节")
    print(f"  可省   : {saved} 字节（{saved * 100.0 / csize:.2f}%）")
    return 0

if __name__ == '__main__':
    sys.exit(main())
