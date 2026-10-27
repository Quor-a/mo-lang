#!/usr/bin/env python3
"""按指令统计代码段体积构成 —— 让"往哪优化"有数据，而不是凭直觉。

用法：python3 tools/codecompose.py <elf>
"""
import subprocess, re, sys, os

def text_bytes(path):
    out = subprocess.run(['readelf', '-lW', path], capture_output=True, text=True).stdout
    m = re.search(r'LOAD\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+0x([0-9a-f]+)\s+R E', out)
    if not m:
        raise SystemExit('找不到可执行 LOAD 段')
    off, sz = int(m.group(1), 16), int(m.group(5), 16)
    return open(path, 'rb').read()[off:off + sz]

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'bin/moc'
    binf = '/tmp/_cc.bin'
    open(binf, 'wb').write(text_bytes(path))
    dis = subprocess.run(['objdump', '-D', '-b', 'binary', '-m', 'i386:x86-64', binf],
                         capture_output=True, text=True).stdout
    tot, cnt = {}, {}
    for ln in dis.splitlines():
        m = re.match(r'\s+[0-9a-f]+:\t((?:[0-9a-f]{2} )+)\s*\t?(.*)', ln)
        if not m:
            continue
        bs = [x for x in m.group(1).split() if re.fullmatch('[0-9a-f]{2}', x)]
        ins = m.group(2).strip()
        if not ins:
            continue
        op = ins.split()[0]
        tot[op] = tot.get(op, 0) + len(bs)
        cnt[op] = cnt.get(op, 0) + 1
    T = sum(tot.values())
    N = sum(cnt.values())
    print(f'代码段 {T} 字节 / {N} 条指令 ({path})')
    print(f'{"指令":<10}{"字节":>9}{"占比":>8}{"条数":>8}{"均长":>7}')
    for op, v in sorted(tot.items(), key=lambda x: -x[1])[:15]:
        print(f'{op:<10}{v:>9}{100*v/T:>7.1f}%{cnt[op]:>8}{v/cnt[op]:>7.2f}')
    # 关键比值：push/pop 的编码极短，这是判断"寄存器分配是否省体积"的依据
    pp = tot.get('push', 0) + tot.get('pop', 0)
    print(f'\npush+pop 合计 {pp} 字节 ({100*pp/T:.1f}%)，均长 '
          f'{(tot.get("push",0)+tot.get("pop",0))/(cnt.get("push",1)+cnt.get("pop",1)):.2f}')
    print('若换成寄存器传送(mov, 3 字节)，体积是增还是减，取决于这个均长。')

if __name__ == '__main__':
    main()
