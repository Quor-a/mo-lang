#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
nscheck —— 模块命名空间缺失下的「歧义调用」静态检查

背景（实测得出的绑定语义，不是猜的）
------------------------------------
墨语言没有模块命名空间，所有 `import` 进来的文件共享同一张符号表。
用 A.mo / B.mo 各自定义 `fn helper()`（返回 111 / 222）实测：

  t1  import A; import B;  calla() callb()  -> 111 222
  t2  import B; import A;  calla() callb()  -> 111 222
      ⇒ 文件内部调用自己定义的函数，恒正确，与 import 顺序无关

  t3  import A; import B;  main 直接 helper()  -> 222（B 的）
  t4  import B; import A;  main 直接 helper()  -> 111（A 的）
      ⇒ 调用点所在文件自己没定义时，绑定**最后被处理的那个**文件的定义
        —— 不报错、不崩溃，改一行 import 顺序就换了一个实现

  m1  A 调用自己没定义的 helper，B 定义了  -> error: undefined symbol
      ⇒ 「静默蹭用别的库的函数」不会发生，未定义会直接报错

所以真正的风险面比最初设想的窄，但更实在：
**调用点所在文件没有自己的定义，而闭包里有 ≥2 个不同实现。**
本工具只报这一种（AMBIGUOUS CALL）。

判据
----
1. 从主文件出发，递归收集 import 闭包
2. 每个文件取顶层 `fn NAME(` 定义，函数体去空白去注释后取摘要
3. 收集每个文件的调用点（排除关键字、排除 `x.y(` 成员调用）
4. 调用点不在本文件定义、且闭包内可见定义 ≥2 个且摘要不同 → 报

`--lib` 是另一种模式：把 lib/ 当一个大程序，列「同名且实现不同」清单，
供人工审阅（其中含无害项，如 cstd/net 的 exit 实现等价），不计入失败。

用法
----
  python3 tools/nscheck.py <main.mo> ...      检查若干程序
  python3 tools/nscheck.py --all               检查 examples/ 与 tests/ 下全部
  python3 tools/nscheck.py --lib               列 lib/ 内同名不同实现的清单

退出码：0 = 无歧义调用，1 = 有歧义调用，2 = 用法或 IO 错误
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")

# import "xxx.mo" 或 import 'xxx.mo'
RE_IMP = re.compile(r'import\s+"([^"]+)"')
RE_FN = re.compile(r'^fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(', re.M)
RE_COMMENT = re.compile(r'#.*$')
# 调用点：名字前面不能是点号或字母数字（排除成员调用 x.y( 与 _h0( 之类误连）
RE_CALL = re.compile(r'(?<![.\w])([A-Za-z_][A-Za-z_0-9]*)\s*\(')

KEYWORDS = set("""
if else while for return fn let var struct enum import break continue
syscall and or not
""".split())


# ---- 缓存 ---------------------------------------------------------------
# 没有缓存时 --lib 要跑 21 秒（real），其中绝大部分耗在对同一批文件反复
# stat / 反复读盘上：56 个入口各做一次 closure，而它们 import 的都是同样
# 那几个 lib。缓存后降到 1 秒以内，--all（上百个程序）才跑得完。
_OPEN_CACHE = {}
_TEXT_CACHE = {}
_FN_CACHE = {}


def try_open(path, cwd):
    """复刻编译器 try_open 的搜索顺序：原样 / lib/<base> / ../lib/<base>"""
    key = (path, cwd)
    if key in _OPEN_CACHE:
        return _OPEN_CACHE[key]
    res = None
    # 先按「引用文件所在目录」解析，再回退到编译器那两条 lib 路径。
    # 编译器用的是进程 cwd（run.sh 会 cd 到 /tmp/mot 再编译），而本工具
    # 从仓库根跑 —— 只认进程 cwd 的话，tests/*/main.mo 里 import "ambA.mo"
    # 这种同目录裸名会被判为打不开，闭包少收文件，检查静默少报。
    cand = os.path.normpath(os.path.join(cwd, path))
    if os.path.isfile(cand):
        res = os.path.abspath(cand)
    else:
        base = os.path.basename(path)
        for rel in (os.path.join("lib", base),
                    os.path.join("..", "lib", base)):
            cand = os.path.normpath(os.path.join(cwd, rel))
            if os.path.isfile(cand):
                res = os.path.abspath(cand)
                break
    _OPEN_CACHE[key] = res
    return res


def read_text(rp):
    """带缓存地读文件；读不到的返回 None（IO 错误不该让整个检查崩掉）"""
    if rp in _TEXT_CACHE:
        return _TEXT_CACHE[rp]
    try:
        with open(rp, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except (IOError, OSError):
        text = None
    _TEXT_CACHE[rp] = text
    return text


def fn_map(rp):
    """带缓存的 top_level_fns"""
    if rp not in _FN_CACHE:
        text = read_text(rp)
        _FN_CACHE[rp] = top_level_fns(text) if text is not None else {}
    return _FN_CACHE[rp]


def strip_ws(body):
    """去掉注释与所有空白，用于比较实现是否等价"""
    out = []
    for line in body.split("\n"):
        line = RE_COMMENT.sub("", line).strip()
        if line:
            out.append(line)
    return re.sub(r"\s+", "", "".join(out))


def top_level_fns(text):
    """提取顶层 fn 定义 -> {name: 规范化函数体}。

    用花括号配平确定函数体边界；只认顶格（列 0）的 fn，避免把嵌套函数算进来。
    """
    # 先去掉行注释，再做花括号配平 —— 否则注释里的 { } 会让边界算错。
    clean = "\n".join(RE_COMMENT.sub("", l) for l in text.split("\n"))
    res = {}
    n = len(clean)
    for m in RE_FN.finditer(clean):
        j = clean.find("{", m.end())
        if j < 0:
            continue
        depth = 0
        k = j
        while k < n:
            c = clean[k]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        res.setdefault(m.group(1), strip_ws(clean[j:k + 1]))
    return res


def closure(main_path, seen=None, files=None):
    """递归收集 import 闭包，返回 [(realpath, cwd)]"""
    if seen is None:
        seen = set()
    if files is None:
        files = []
    rp = os.path.abspath(main_path)
    if rp in seen:
        return files
    seen.add(rp)
    text = read_text(rp)
    if text is None:
        return files
    cwd = os.path.dirname(rp)
    files.append((rp, cwd))
    for name in RE_IMP.findall(text):
        cand = try_open(name, cwd)
        if cand:
            closure(cand, seen, files)
    return files


def conflicts(files):
    """返回 [(name, fileA, fileB)]：同名且实现不同"""
    # 去重：--lib 模式下每个库都当入口跑一次 closure，同一个文件会被收
    # 进 files 多次；不去重的话同一个冲突会重复报好几遍。
    seen = set()
    uniq = []
    for item in files:
        if item[0] in seen:
            continue
        seen.add(item[0])
        uniq.append(item)
    files = uniq
    owner = {}          # name -> (norm_body, path)
    out = []
    pairs = set()       # 同一对文件可能有多处同名，只报一次
    for rp, cwd in files:
        for name, body in fn_map(rp).items():
            if name in owner:
                ob, op = owner[name]
                key = (name, op, rp)
                if ob != body and op != rp and key not in pairs:
                    pairs.add(key)
                    out.append((name, op, rp))
            else:
                owner[name] = (body, rp)
    return out


def short(p):
    try:
        return os.path.relpath(p, ROOT)
    except ValueError:
        return p


def call_sites(text):
    """取该文件里的函数调用点名字集合。

    排除三类误抓：
      * 关键字：`if (` `while (` `return (` 都不是调用
      * 成员调用 `Rect.area(`：名字前有点号，不是顶层函数
      * 定义行 `fn NAME(`：由调用方用 own 集合排除
    """
    clean = "\n".join(RE_COMMENT.sub("", l) for l in text.split("\n"))
    out = set()
    for m in RE_CALL.finditer(clean):
        nm = m.group(1)
        if nm in KEYWORDS:
            continue
        out.add(nm)
    return out


def ambiguous_calls(files):
    """返回 [(name, callfile, [定义文件路径...])]：歧义调用"""
    # 去重（--lib / 多入口时同一文件会被收集多次）
    seen = set()
    uniq = []
    for item in files:
        if item[0] in seen:
            continue
        seen.add(item[0])
        uniq.append(item)
    files = uniq

    defines = {}        # name -> [(body, path)]
    for rp, _ in files:
        for name, body in fn_map(rp).items():
            defines.setdefault(name, []).append((body, rp))

    out = []
    for rp, _ in files:
        text = read_text(rp)
        if text is None:
            continue
        own = set(fn_map(rp).keys())
        for nm in sorted(call_sites(text)):
            if nm in own:
                continue            # 本文件自己定义了 → 恒绑自己的，无歧义
            cands = defines.get(nm)
            if not cands:
                continue            # 没人定义 → 编译器会报 undefined，不归本工具
            if len(set(b for b, _ in cands)) < 2:
                continue            # 多个文件定义但实现一致 → 无差别
            out.append((nm, rp, [p for _, p in cands]))
    return out


def check_one(main_path):
    files = closure(main_path)
    ambs = ambiguous_calls(files)
    return ambs, len(set(f[0] for f in files))


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    targets = []
    if argv[1] == "--all":
        for d in ("examples", "tests"):
            dd = os.path.join(ROOT, d)
            if os.path.isdir(dd):
                for fn in sorted(os.listdir(dd)):
                    if fn.endswith(".mo"):
                        targets.append(os.path.join(dd, fn))
    elif argv[1] == "--lib":
        for fn in sorted(os.listdir(LIB)):
            if fn.endswith(".mo"):
                targets.append(os.path.join(LIB, fn))
    else:
        targets = argv[1:]

    # --lib 模式：把所有库当成同一个程序来检查（它们两两之间是否冲突）
    if argv[1] == "--lib":
        files = []
        for t in targets:
            files.extend(closure(t))
        cs = conflicts(files)
        print("lib 文件数: %d" % len(set(f[0] for f in files)))
        if not cs:
            print("跨文件同名且实现不同: 0  -> 无冲突")
            return 0
        print("跨文件同名且实现不同: %d" % len(cs))
        for name, a, b in cs:
            print("  %s: %s <-> %s" % (name, short(a), short(b)))
        # --lib 是**清单模式**，恒返回 0：这里含无害项（如 cstd/net 的 exit
        # 两个实现都是 syscall(60)，只在 return 值上差一点，而 exit 不返回），
        # 让它参与成败判定只会制造必须手工豁免的噪声。
        return 0

    bad = 0
    nprog = 0
    for t in targets:
        ambs, nf = check_one(t)
        nprog += 1
        if ambs:
            bad += 1
            print("歧义调用 %s (%d 文件):" % (short(t), nf))
            for name, cf, paths in ambs:
                print("  %s() 在 %s 调用，可见定义有 %d 处且实现不同: %s"
                      % (name, short(cf), len(paths),
                         " ".join(short(p) for p in paths)))
    print("检查程序数: %d，有歧义调用: %d" % (nprog, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
