#!/usr/bin/env python3
"""unitest 的参照端：用 unicodedata 独立算一遍期望，与 unidump 的输出比对。

期望语义必须与 lib/uni.mo 完全一致：
  - 类别：UAX #44 细类映射到 uni.mo 的 23 个粗类
  - 大小写：str.upper()/str.lower() 长度为一 → 取该码点；
            长度大于一（一个码点变多个码点）→ 返回原码点并置 SPEC=1
"""

import sys
import unicodedata as ud

COARSE = {'Cn': 0, 'Cc': 19, 'Cf': 20, 'Cs': 21, 'Co': 22,
          'Lu': 1, 'Ll': 2, 'Lt': 3, 'Lm': 4, 'Lo': 5,
          'Mn': 6, 'Mc': 6, 'Me': 6,
          'Nd': 7, 'Nl': 8, 'No': 8,
          'Pc': 9, 'Pd': 10, 'Ps': 11, 'Pi': 11, 'Pe': 12, 'Pf': 12, 'Po': 13,
          'Sm': 14, 'Sc': 15, 'Sk': 16, 'So': 17,
          'Zs': 18, 'Zl': 18, 'Zp': 18}


def simp(cp, fn):
    s = fn(chr(cp))
    if len(s) == 1:
        return ord(s), 0
    return cp, 1


def main():
    path = sys.argv[1]
    n = 0
    bad = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 6:
                continue
            cp, cat, up, sup, lo, slo = (int(x) for x in parts)
            n += 1
            want_cat = COARSE[ud.category(chr(cp))]
            want_up, want_sup = simp(cp, str.upper)
            want_lo, want_slo = simp(cp, str.lower)
            if (cat, up, sup, lo, slo) != (want_cat, want_up, want_sup,
                                           want_lo, want_slo):
                bad.append((cp, (cat, up, sup, lo, slo),
                            (want_cat, want_up, want_sup, want_lo, want_slo)))
    print('  unicode %s  比对码点数 %d' % (ud.unidata_version, n))
    if not bad:
        print('  unitest: 全部一致')
        return 0
    print('  unitest: 不一致 %d 处（前 10）' % len(bad))
    for cp, got, want in bad[:10]:
        print('    U+%04X  got=%s want=%s' % (cp, got, want))
    return 1


if __name__ == '__main__':
    sys.exit(main())
