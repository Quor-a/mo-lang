#!/usr/bin/env python3
# mols.py —— 墨语言的 Language Server
#
# 之前 tools/editor/ 只有 TextMate 语法高亮，**没有语义能力**：
# 不能跳转定义、不能悬停看签名、报错要切到终端看。
#
# 这个服务器提供三块能力：
#
#   1. **诊断**（最有价值）—— 调用真正的 moc 编译当前文件，
#      把 `file:line:col: error: ...` 解析成编辑器内联的红波浪线。
#      它不依赖任何调试信息，只要解析编译器的错误输出格式。
#   2. **索引** —— 扫 .mo 源码提取符号定义位置，供跳转/悬停/大纲使用。
#   3. **语义高亮** —— 区分「函数 / 类型 / 变量 / 关键字」，
#      比正则高亮准（不会把注释里的 fn 当成关键字）。
#
# 通信：LSP 的 JSON-RPC over stdio。只用标准库。
#
# ⚠️ 已知限制（都写在这里，不做假装支持）：
#   - 诊断是**整文件编译**，不做增量；大文件每次改动会重编一次
#   - 索引基于正则，**不做作用域消解**：两个函数里的同名局部变量
#     会被当成同一个符号（跳转时给出多个候选，按行号取最近的一个）
#   - 没有自动补全（completion）—— 需要类型推导，1.x 不做

import json
import os
import re
import subprocess
import sys
import tempfile
import shutil

# ---------------------------------------------------------------- 常量

KEYWORDS = {
    "fn", "return", "let", "var", "struct", "class", "enum",
    "import", "if", "else", "while", "break", "continue", "for",
    "true", "false",
}
TYPES = {"i64", "byte", "ptr", "bool", "f64"}
BUILTINS = {
    "load8", "load16", "load32", "load64", "store8", "store16",
    "store32", "store64", "syscall", "argc", "argv", "sizeof",
    "alignof", "print", "print_i64", "strlen", "streq",
}

# LSP 语义 token 类型（顺序必须与 legend 一致）
TOKEN_TYPES = [
    "keyword",     # 0
    "function",    # 1
    "type",        # 2
    "variable",    # 3
    "number",      # 4
    "string",      # 5
    "comment",     # 6
    "operator",    # 7
    "enumMember",  # 8
    "class",       # 9
    "struct",      # 10
]
TOKEN_MODS = ["declaration", "definition", "readonly"]

# ---------------------------------------------------------------- 索引


class Sym:
    """一个符号定义。"""

    def __init__(self, name, kind, line, col, detail, uri, endline=None):
        self.name = name
        self.kind = kind      # function / variable / struct / class / enum / enumMember
        self.line = line      # 0-based
        self.col = col        # 0-based
        self.detail = detail  # 签名或类型，用于 hover
        self.uri = uri
        self.endline = endline or line

    def kind_id(self):
        return {
            "function": 1, "class": 2, "struct": 3, "enum": 4,
            "enumMember": 5, "variable": 6,
        }.get(self.kind, 6)


def strip_comment(line):
    """去掉行注释。**不能**简单找第一个 # —— 字符串里的 # 要保留。"""
    out = []
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if c == "#" and not in_str:
            break
        out.append(c)
        i += 1
    return "".join(out)


def index_source(text, uri):
    """扫一遍源码，提取所有符号定义。"""
    syms = []
    lines = text.split("\n")

    # ---- import：记住，用于跨文件跳转 ----
    imports = []
    for ln, raw in enumerate(lines):
        m = re.search(r'import\s+"([^"]+)"', strip_comment(raw))
        if m:
            imports.append((m.group(1), ln))

    # ---- enum（先扫，因为 enum 成员要归属）----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        m = re.match(r"\s*enum\s+([A-Za-z_][A-Za-z_0-9]*)\s*\{", code)
        if m:
            syms.append(Sym(m.group(1), "enum", ln, m.start(1),
                            "enum " + m.group(1), uri))
            # 成员：**可能就写在这一行**（enum C { A = 1; B = 2; }），
            # 所以从声明行本身开始扫，而不是 ln+1。
            # 第一版从下一行开始，于是单行写法的所有成员都丢了 ——
            # 表现为大纲里只有 enum 名、没有成员，且不报错。
            k = ln
            auto = 0
            while k < len(lines):
                c2 = strip_comment(lines[k])
                body = c2[c2.find("{") + 1:] if k == ln else c2
                if "}" in body:
                    body = body[:body.find("}")]
                    if k > ln:
                        break
                for mm in re.finditer(
                        r"([A-Za-z_][A-Za-z_0-9]*)\s*(?:=\s*(-?\d+))?\s*;", body):
                    val = mm.group(2) if mm.group(2) else str(auto)
                    off = (c2.find("{") + 1 if k == ln else 0) + mm.start(1)
                    syms.append(Sym(mm.group(1), "enumMember", k, off,
                                    "%s.%s = %s" % (m.group(1), mm.group(1), val),
                                    uri))
                    auto = int(val) + 1 if mm.group(2) else auto + 1
                if k > ln and "}" in c2:
                    break
                if k == ln and "}" in c2:
                    break
                k += 1

    # ---- struct / class ----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        for kw, kind in (("struct", "struct"), ("class", "class")):
            m = re.match(r"\s*%s\s+([A-Za-z_][A-Za-z_0-9]*)" % kw, code)
            if m:
                syms.append(Sym(m.group(1), kind, ln, m.start(1),
                                "%s %s" % (kw, m.group(1)), uri))
                # 字段同样可能写在同一行（struct P { x: i64; y: i64; }）
                k = ln
                while k < len(lines):
                    c2 = strip_comment(lines[k])
                    body = c2[c2.find("{") + 1:] if k == ln else c2
                    if "}" in body:
                        body = body[:body.find("}")]
                    for fm in re.finditer(
                            r"([A-Za-z_][A-Za-z_0-9]*)\s*:\s*([A-Za-z_][A-Za-z_0-9]*)\s*;", body):
                        off = (c2.find("{") + 1 if k == ln else 0) + fm.start(1)
                        syms.append(Sym(fm.group(1), "variable", k, off,
                                        "%s: %s" % (fm.group(1), fm.group(2)), uri))
                    if "}" in c2:
                        break
                    k += 1

    # ---- 函数（含方法：ClassName_method）----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        m = re.match(r"\s*fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(([^)]*)\)\s*->\s*([A-Za-z_][A-Za-z_0-9]*)", code)
        if m:
            syms.append(Sym(m.group(1), "function", ln, m.start(1),
                            "fn %s(%s) -> %s" % (m.group(1), m.group(2).strip(),
                                                 m.group(3)),
                            uri))
            continue
        m = re.match(r"\s*fn\s+([A-Za-z_][A-Za-z_0-9]*)\s*\(([^)]*)\)", code)
        if m:
            syms.append(Sym(m.group(1), "function", ln, m.start(1),
                            "fn %s(%s)" % (m.group(1), m.group(2).strip()), uri))

    # ---- 全局 var ----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        m = re.match(r"\s*var\s+([A-Za-z_][A-Za-z_0-9]*)\s*:\s*([^=;]+)", code)
        if m:
            syms.append(Sym(m.group(1), "variable", ln, m.start(1),
                            "var %s: %s" % (m.group(1), m.group(2).strip()), uri))

    # ---- 局部变量 let ----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        m = re.match(r"\s*let\s+([A-Za-z_][A-Za-z_0-9]*)\s*:\s*([^=;]+)", code)
        if m:
            syms.append(Sym(m.group(1), "variable", ln, m.start(1),
                            "let %s: %s" % (m.group(1), m.group(2).strip()), uri))

    # ---- 函数参数 ----
    for ln, raw in enumerate(lines):
        code = strip_comment(raw)
        if not re.match(r"\s*fn\s", code):
            continue
        m = re.search(r"\(([^)]*)\)", code)
        if not m:
            continue
        for pm in re.finditer(r"([A-Za-z_][A-Za-z_0-9]*)\s*:\s*([A-Za-z_][A-Za-z_0-9]*)",
                              m.group(1)):
            syms.append(Sym(pm.group(1), "variable", ln,
                            code.find(m.group(1)) + m.start(1) + pm.start(1),
                            "%s: %s" % (pm.group(1), pm.group(2)), uri))

    return syms, imports


class Workspace:
    def __init__(self, root):
        self.root = root
        self.docs = {}     # uri -> text
        self.syms = {}     # uri -> [Sym]
        self.imports = {}  # uri -> [(lib, line)]

    def reindex(self, uri, text):
        self.docs[uri] = text
        s, im = index_source(text, uri)
        self.syms[uri] = s
        self.imports[uri] = im

    def all_syms(self, uri):
        """当前文件 + 它 import 的库（用于跨文件跳转）。"""
        out = list(self.syms.get(uri, []))
        seen = {uri}
        for lib, _ in self.imports.get(uri, []):
            lu = self.lib_uri(lib)
            if lu and lu not in seen and os.path.exists(self.uri_path(lu)):
                seen.add(lu)
                try:
                    t = open(self.uri_path(lu), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                if lu not in self.syms:
                    s, _ = index_source(t, lu)
                    self.syms[lu] = s
                out.extend(self.syms[lu])
        return out

    def lib_uri(self, lib):
        """import "io.mo" → 找得到的文件 uri。"""
        cands = [
            os.path.join(self.root, "lib", lib),
            os.path.join(self.root, lib),
            os.path.join(os.path.dirname(os.path.dirname(
                os.path.abspath(__file__))), "lib", lib),
        ]
        for c in cands:
            if os.path.exists(c):
                return "file://" + os.path.abspath(c)
        return None

    @staticmethod
    def uri_path(uri):
        return uri[len("file://"):] if uri.startswith("file://") else uri


# ---------------------------------------------------------------- 诊断


DIAG_RE = re.compile(r"^(.+?):(\d+):(\d+):\s*(error|warning):\s*(.*)$")


def run_diagnostics(ws, uri):
    """调用真 moc 编译，把错误变成 LSP Diagnostic。"""
    path = ws.uri_path(uri)
    if not os.path.exists(path):
        return []

    moc = os.path.join(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), "bin", "moc")
    if not os.path.exists(moc):
        return []

    # 🔴 moc 的 import 解析依赖 **cwd**：import "io.mo" 会找 ./lib/io.mo。
    #    所以不能直接编译原文件（原目录可能没有 lib/），
    #    必须建临时目录、放进源码、并链上 lib/，再在**那个目录**里跑。
    tmp = tempfile.mkdtemp(prefix="mols-")
    try:
        # 🔴 moc **默认读 test.mo**（inpath 硬编码为 "test.mo"），
        #    不接受"当前目录唯一的 .mo"这种推断。
        #    第一版用 os.path.basename(path)（用户文件叫 t.mo），
        #    moc 直接输出 "cannot open input" —— 于是**任何文件**
        #    的诊断都是 0 条，看起来像"诊断功能没生效"，
        #    实际是输入文件名不匹配。
        src = os.path.join(tmp, "test.mo")
        shutil.copyfile(path, src)
        libsrc = os.path.join(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))), "lib")
        if os.path.isdir(libsrc):
            os.symlink(libsrc, os.path.join(tmp, "lib"))
        try:
            p = subprocess.run([moc], cwd=tmp, capture_output=True,
                               timeout=30)
        except subprocess.TimeoutExpired:
            return []
        out = (p.stdout.decode("utf-8", "replace") +
               p.stderr.decode("utf-8", "replace"))
        # "cannot open input" 说明 moc 根本没读到文件 —— 这是**工具**
        # 的问题，不是用户代码的问题，必须区分开，否则会被当成
        # "编译通过"而静默掉。
        if "cannot open input" in out:
            return [{
                "range": {"start": {"line": 0, "character": 0},
                          "end": {"line": 0, "character": 1}},
                "severity": 2,
                "source": "mols",
                "message": "mols: 无法让 moc 打开输入文件（这是工具问题，非代码错误）",
            }]
        diags = []
        for line in out.split("\n"):
            m = DIAG_RE.match(line.strip())
            if not m:
                continue
            diags.append({
                "range": {
                    "start": {"line": int(m.group(2)) - 1,
                              "character": max(0, int(m.group(3)) - 1)},
                    "end": {"line": int(m.group(2)) - 1,
                            "character": max(0, int(m.group(3)))},
                },
                "severity": 1 if m.group(4) == "error" else 2,
                "source": "mo",
                "message": m.group(5),
            })
        return diags
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 语义 token


def semantic_tokens(text):
    """产出 LSP 语义 token（相对编码的 5 元组扁平数组）。"""
    data = []
    prev_line = 0
    prev_char = 0
    lines = text.split("\n")

    def push(ln, ch, length, typ, _mods=0):
        nonlocal prev_line, prev_char
        # 🔴 不能写 `data += [...]` —— 那是对 data 的赋值，
        #    Python 会把它当成 push 的**局部变量**，读时未绑定
        #    （UnboundLocalError）。用 extend 才是"改外层对象"。
        data.extend([ln - prev_line,
                     ch - prev_char if ln == prev_line else ch,
                     length, typ, 0])
        prev_line, prev_char = ln, ch

    known = set()
    lines_all = text.split("\n")
    for raw in lines_all:
        for m in re.finditer(r"\bfn\s+([A-Za-z_][A-Za-z_0-9]*)", strip_comment(raw)):
            known.add(m.group(1))
        for m in re.finditer(r"\bvar\s+([A-Za-z_][A-Za-z_0-9]*)", strip_comment(raw)):
            known.add(m.group(1))
        for m in re.finditer(r"\benum\s+([A-Za-z_][A-Za-z_0-9]*)", strip_comment(raw)):
            known.add(m.group(1))
        for m in re.finditer(r"\b(?:struct|class)\s+([A-Za-z_][A-Za-z_0-9]*)", strip_comment(raw)):
            known.add(m.group(1))

    for ln, raw in enumerate(lines):
        # 注释整行
        s = raw.lstrip()
        if s.startswith("#"):
            push(ln, len(raw) - len(s), len(s), 6)
            continue
        code = strip_comment(raw)
        # 字符串
        for m in re.finditer(r'"(?:\\.|[^"\\])*"', code):
            push(ln, m.start(), len(m.group(0)), 5)
        # 数字
        for m in re.finditer(r"\b\d+\b", code):
            push(ln, m.start(), len(m.group(0)), 4)
        # 关键字
        for m in re.finditer(r"\b[A-Za-z_][A-Za-z_0-9]*\b", code):
            w = m.group(0)
            if w in KEYWORDS:
                push(ln, m.start(), len(w), 0)
            elif w in TYPES:
                push(ln, m.start(), len(w), 2)
            elif w in BUILTINS:
                push(ln, m.start(), len(w), 1)
            elif w in known:
                push(ln, m.start(), len(w), 1)
        # 运算符
        for m in re.finditer(r"[-+*/%=!<>&|^~]+", code):
            push(ln, m.start(), len(m.group(0)), 7)

    return data


# ---------------------------------------------------------------- LSP 主循环


def word_at(text, line, char):
    lines = text.split("\n")
    if line >= len(lines):
        return None, 0, 0
    s = lines[line]
    if char > len(s):
        char = len(s)
    lo = char
    while lo > 0 and (s[lo - 1].isalnum() or s[lo - 1] == "_"):
        lo -= 1
    hi = char
    while hi < len(s) and (s[hi].isalnum() or s[hi] == "_"):
        hi += 1
    w = s[lo:hi]
    return (w if w else None), lo, hi


class Server:
    def __init__(self, root):
        self.ws = Workspace(root)
        self.root = root

    def handle(self, msg):
        m = msg.get("method")
        p = msg.get("params") or {}
        mid = msg.get("id")

        if m == "initialize":
            return mid, {
                "capabilities": {
                    "textDocumentSync": 1,
                    "definitionProvider": True,
                    "hoverProvider": True,
                    "documentSymbolProvider": True,
                    "referencesProvider": True,
                    "semanticTokensProvider": {
                        "legend": {
                            "tokenTypes": TOKEN_TYPES,
                            "tokenModifiers": TOKEN_MODS,
                        },
                        "full": True,
                    },
                },
                "serverInfo": {"name": "mols", "version": "0.1"},
            }

        if m == "initialized" or m == "shutdown":
            return mid, None
        if m == "exit":
            sys.exit(0)

        if m == "textDocument/didOpen":
            uri = p["textDocument"]["uri"]
            self.ws.reindex(uri, p["textDocument"]["text"])
            self.send_notification("textDocument/publishDiagnostics",
                                   {"uri": uri,
                                    "diagnostics": run_diagnostics(self.ws, uri)})
            return None, None

        if m == "textDocument/didChange":
            uri = p["textDocument"]["uri"]
            text = p["contentChanges"][-1]["text"]
            self.ws.reindex(uri, text)
            self.send_notification("textDocument/publishDiagnostics",
                                   {"uri": uri,
                                    "diagnostics": run_diagnostics(self.ws, uri)})
            return None, None

        if m == "textDocument/definition":
            uri = p["textDocument"]["uri"]
            text = self.ws.docs.get(uri, "")
            w, _, _ = word_at(text, p["position"]["line"], p["position"]["character"])
            if not w:
                return mid, []
            out = []
            for s in self.ws.all_syms(uri):
                if s.name == w:
                    out.append({
                        "uri": s.uri,
                        "range": {
                            "start": {"line": s.line, "character": s.col},
                            "end": {"line": s.line, "character": s.col + len(s.name)},
                        },
                    })
            return mid, out

        if m == "textDocument/hover":
            uri = p["textDocument"]["uri"]
            text = self.ws.docs.get(uri, "")
            w, _, _ = word_at(text, p["position"]["line"], p["position"]["character"])
            if not w:
                return mid, None
            for s in self.ws.all_syms(uri):
                if s.name == w:
                    return mid, {
                        "contents": {
                            "kind": "markdown",
                            "value": "```mo\n%s\n```\n\n%s (%s)" % (s.detail, s.kind, os.path.basename(s.uri)),
                        }
                    }
            return mid, None

        if m == "textDocument/documentSymbol":
            uri = p["textDocument"]["uri"]
            out = []
            for s in self.ws.syms.get(uri, []):
                out.append({
                    "name": s.name,
                    "kind": s.kind_id(),
                    "detail": s.detail,
                    "range": {"start": {"line": s.line, "character": 0},
                              "end": {"line": s.line, "character": 0}},
                    "selectionRange": {
                        "start": {"line": s.line, "character": s.col},
                        "end": {"line": s.line, "character": s.col + len(s.name)},
                    },
                })
            return mid, out

        if m == "textDocument/references":
            uri = p["textDocument"]["uri"]
            text = self.ws.docs.get(uri, "")
            w, _, _ = word_at(text, p["position"]["line"], p["position"]["character"])
            if not w:
                return mid, []
            out = []
            for ln, raw in enumerate(text.split("\n")):
                for mm in re.finditer(r"\b%s\b" % re.escape(w), strip_comment(raw)):
                    out.append({"uri": uri, "range": {
                        "start": {"line": ln, "character": mm.start()},
                        "end": {"line": ln, "character": mm.start() + len(w)}}})
            return mid, out

        if m == "textDocument/semanticTokens/full":
            uri = p["textDocument"]["uri"]
            return mid, {"data": semantic_tokens(self.ws.docs.get(uri, ""))}

        return mid, None

    def send_notification(self, method, params):
        send({"jsonrpc": "2.0", "method": method, "params": params})


def send(msg):
    b = json.dumps(msg).encode("utf-8")
    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(b))
    sys.stdout.buffer.write(b)
    sys.stdout.buffer.flush()


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    srv = Server(root)
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            break
        line = line.decode("utf-8", "replace").strip()
        if not line.lower().startswith("content-length:"):
            continue
        n = int(line.split(":")[1].strip())
        sys.stdin.buffer.readline()          # 空行
        body = sys.stdin.buffer.read(n)
        try:
            msg = json.loads(body.decode("utf-8"))
        except ValueError:
            continue
        mid, result = srv.handle(msg)
        if mid is not None:
            send({"jsonrpc": "2.0", "id": mid, "result": result})


if __name__ == "__main__":
    main()
