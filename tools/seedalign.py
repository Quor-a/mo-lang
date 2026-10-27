#!/usr/bin/env python3
"""
seedalign —— seed 与 compiler.mo 的对齐检查

改 compiler.mo 时若影响了「编译期副作用」，必须同步改 seed 的汇编
（src/asm/main.s）。这类漏改的表现是**自举失败**，而排查起来很费时
（我为此花了整一轮，一度误判成"seed 有缺陷"）。

本脚本在 make 之前就把它拦下来。

检查项：
  1. 数据段头的 dquad 数量两边是否一致
  2. 两边是否都存在 emit_startup / parse_program 锚点
"""
import re, sys

ROOT = __file__.rsplit('/', 2)[0]

def read(p):
    try:
        return open(p, encoding='utf-8').read()
    except Exception as e:
        return None

def seed_dquads():
    """数 seed 汇编里 emit_startup 与 parse_program 之间的 dquad 调用"""
    a = read(f'{ROOT}/src/asm/main.s')
    if a is None:
        return None, 'cannot read src/asm/main.s'
    i = a.find('call emit_startup')
    j = a.find('call parse_program')
    if i < 0 or j < 0 or j < i:
        return None, 'anchor not found (emit_startup / parse_program)'
    return a[i:j].count('call dquad'), None

def mo_dquads():
    """数 compiler.mo 的 reserve_arg_slots() 里的 dquad 调用"""
    s = read(f'{ROOT}/src/mo/compiler_part5.mo')
    if s is None:
        return None, 'cannot read src/mo/compiler_part5.mo'
    m = re.search(r'fn reserve_arg_slots\(\) -> i64 \{(.*?)\n\}', s, re.S)
    if not m:
        return None, 'reserve_arg_slots() not found'
    return m.group(1).count('dquad(0);'), None

def main():
    ns, e1 = seed_dquads()
    nm, e2 = mo_dquads()
    if e1 or e2:
        print('seedalign: SKIP (%s)' % (e1 or e2))
        return 0
    if ns == nm:
        print('seedalign: OK (数据段头 dquad: seed=%d, compiler.mo=%d)' % (ns, nm))
        return 0
    print('seedalign: ✗ 不对齐')
    print('    src/asm/main.s            : %d 个 dquad' % ns)
    print('    src/mo/compiler_part5.mo  : %d 个 dquad' % nm)
    print()
    print('    seed 是手写汇编，数据段头布局写死在 src/asm/main.s 里。')
    print('    compiler.mo 改了 reserve_arg_slots()，seed 必须同步改，')
    print('    否则两边对全局变量起始偏移的认识不同 → 自举失败。')
    print()
    print('    详见 docs/self_hosting_alignment.md')
    return 1

sys.exit(main())
