#!/usr/bin/env python3
"""uninormref —— 用 Python unicodedata 独立算期望，逐行比对 uninorm 输出。

期望现算，不落在仓库里。"""
import sys, unicodedata

# 与 lib/uninorm.mo 文档声明的覆盖段一致
COV = [(0x0000,0x017F),(0x0300,0x036F),(0x0384,0x03FF),
       (0x1E00,0x1EFF),(0x1100,0x11FF),(0xAC00,0xD7A3)]

def in_cov(cp):
    for lo, hi in COV:
        if lo <= cp <= hi:
            return True
    return False

def supported(src):
    """递归分解的**每一层中间码点**都必须落在覆盖段内。

    不满足就整条排除：例如 U+1E1C 的分解链是 1E1C -> 0228 + 0306，
    而 0228 -> 0045 + 0327；0228 不在覆盖段内，于是实现只能原样输出
    0228 0306，而 Python 给的是完整 NFD 0045 0327 0306。
    这是**覆盖范围**的诚实限制，不是实现错 —— 但必须显式排除并报数，
    不能让它混在"不一致"里，也不能靠放宽判据蒙过去。"""
    stack = list(src)
    while stack:
        ch = stack.pop()
        if not in_cov(ord(ch)):
            return False
        d = unicodedata.decomposition(ch)
        if d and not d.startswith("<"):
            for part in d.split():
                stack.append(chr(int(part, 16)))
    return True

def main():
    path = sys.argv[1]
    print("python unicodedata", unicodedata.unidata_version)
    nfd_bad = nfc_bad = nfd_n = nfc_n = skip = 0
    first = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            tag = p[0]
            nin = int(p[1])
            ins = [int(x) for x in p[2:2+nin]]
            idx = 2 + nin
            nout = int(p[idx])
            outs = [int(x) for x in p[idx+1:idx+1+nout]]
            src = "".join(chr(c) for c in ins)
            if not supported(src):
                skip += 1
                continue
            if tag == "0":
                want = [ord(c) for c in unicodedata.normalize("NFD", src)]
                nfd_n += 1
                if want != outs:
                    nfd_bad += 1
                    if len(first) < 8:
                        first.append(("NFD", [hex(x) for x in ins],
                                      [hex(x) for x in outs], [hex(x) for x in want]))
            else:
                want = [ord(c) for c in unicodedata.normalize("NFC", src)]
                # NFC 还要看**组合结果**落在哪：0041 0308 0304 的 NFC 是
                # U+01DE（A-diaeresis-macron），0045 0300 0327 的 NFC 是
                # U+0228（E-cedilla）—— 两者都在覆盖段外，组合表里根本
                # 没有这个条目，实现做不出来。这类必须排除并报数，
                # 不能算进"不一致"，也不能靠放宽判据蒙过去。
                if not all(in_cov(x) for x in want):
                    skip += 1
                    continue
                nfc_n += 1
                if want != outs:
                    nfc_bad += 1
                    if len(first) < 8:
                        first.append(("NFC", [hex(x) for x in ins],
                                      [hex(x) for x in outs], [hex(x) for x in want]))
    print("NFD 比对 %d 条，不一致 %d" % (nfd_n, nfd_bad))
    print("NFC 比对 %d 条，不一致 %d" % (nfc_n, nfc_bad))
    print("因递归分解路径或 NFC 组合结果超出覆盖段而排除 %d 条（U+0228 / U+01A0 / U+01DE 等不在表内）" % skip)
    for kind, ins, got, want in first:
        print("  %s in=%s got=%s want=%s" % (kind, ins, got, want))
    ok = (nfd_bad == 0 and nfc_bad == 0 and nfd_n > 10000 and nfc_n > 10000)
    print("OK" if ok else "MISMATCH")
    return 0 if ok else 1

sys.exit(main())
