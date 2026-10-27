#!/usr/bin/env python3
# unused —— 「写了但从未读」的局部变量检查
#
# 为什么单独做这个检查：
#   一个变量被赋值却从没被读过，通常只有两种可能 —— 死代码，或者
#   **本该用它却忘了用**。后者往往意味着一条判断、一次校验被漏掉，
#   而不报错、不崩溃，只是结果悄悄不对。
#   v1.151 就是靠它翻出 mopkg.mo 里 `np = PKG_NN` 这半截修复：
#   存了递归前的状态却没人读，指向的正是一个真缺陷（递归重写全局
#   PKG_NAMES，实测树里 d 被 c2 顶掉）。那段缺陷作者自己写过注释、
#   知道存在，但因为没人读它，也就没人被它拦住。
#
# 判据（刻意收紧，避免噪声淹没）：
#   只报「至少写过一次、且一次都没被读过」的**局部**变量（let 声明）。
#   不算：全局变量（本来就是给别的模块用的）、形参、数组下标写
#   （`buf[0]=7` 读的是 buf 的地址，算用过）、取址（`&p`）。
#
#   python3 tools/unused.py --lib     扫 lib/
#   python3 tools/unused.py --all     扫 lib/ examples/ tests/
#   python3 tools/unused.py <文件>...  指定文件
import sys, re, glob, os

TOK = re.compile(r'->|==|!=|<=|>=|&&|\|\||[A-Za-z_][A-Za-z0-9_]*|\S')

def strip(src):
    """去掉行注释与字符串/字符字面量 —— 否则注释里提到变量名会被当成一次读。"""
    out = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c == '#':
            while i < n and src[i] != '\n': i += 1
            continue
        if c in '"\'':
            q = c; i += 1
            while i < n and src[i] != q:
                if src[i] == '\\': i += 1
                i += 1
            i += 1; out.append('""'); continue
        out.append(c); i += 1
    return ''.join(out)

def scan(path):
    raw = open(path, encoding='utf-8', errors='replace').read()
    # 豁免行必须在**原始**源码上找：strip() 会把注释整个剥掉，
    # 在剥完之后再看 `unused: ok` 永远找不着。换行符是保留的，行号一致。
    exempt = {i+1 for i, l in enumerate(raw.split('\n')) if 'unused: ok' in l}
    src = strip(raw)
    hits = []
    for m in re.finditer(r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', src):
        fname = m.group(1)
        i = m.end() - 1; depth = 0
        while i < len(src):                       # 跳过形参表
            if src[i] == '(': depth += 1
            elif src[i] == ')': depth -= 1
            elif src[i] == '{' and depth == 0: break
            i += 1
        if i >= len(src): continue
        bst = i; depth = 0; j = i
        while j < len(src):                       # 找到函数体末尾
            if src[j] == '{': depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0: break
            j += 1
        body = src[bst:j+1]
        off = src[:bst].count('\n')
        params = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', src[m.end():bst]))
        for dm in re.finditer(r'\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=;]*)?=', body):
            name = dm.group(1)
            if name in params: continue
            # 豁免：`# unused: ok` 写在声明行，表示"刻意赋值却不用"
            ln0 = body.rfind('\n', 0, dm.start()) + 1
            ln1 = body.find('\n', dm.start())
            if 'unused: ok' in body[ln0: ln1 if ln1 > 0 else len(body)]: continue
            toks = TOK.findall(body)
            w = r = 0
            for k, t in enumerate(toks):
                if t != name: continue
                if k > 0 and toks[k-1] == '.':  continue   # 成员名，不是这个变量
                if k > 0 and toks[k-1] == 'let': continue   # 声明处本身不算读
                if k+1 < len(toks) and toks[k+1] == '=': w += 1
                else: r += 1
            if w > 0 and r == 0:
                hits.append((path, off + body[:dm.start()].count('\n') + 1, fname, name, w))
    return hits

def main():
    a = sys.argv[1:]
    if not a or a[0] == '--all':
        files = sorted(glob.glob('lib/*.mo') + glob.glob('examples/*.mo')
                       + glob.glob('tests/*.mo') + glob.glob('tests/*/main.mo'))
    elif a[0] == '--lib':
        files = sorted(glob.glob('lib/*.mo'))
    else:
        files = a
    tot = 0
    for f in files:
        for path, ln, fn_, nm, w in scan(f):
            print(f"{path}:{ln}  fn {fn_}  变量 '{nm}' 写了 {w} 次、从未读过")
            tot += 1
    print(f"扫描 {len(files)} 个文件，命中 {tot}")
    return 1 if tot else 0

if __name__ == '__main__':
    sys.exit(main())
