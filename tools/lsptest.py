#!/usr/bin/env python3
# lsptest —— 真跑一遍 LSP 会话，逐项校验响应
#
# ⚠️ 不能只测"服务器能启动"。LSP 的价值在于返回**正确的位置和内容**，
#    所以这里每一项都断言具体的行号/字符串/数量，
#    而不是"有返回就算过"。

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOLS = os.environ.get("MOLS") or os.path.join(HERE, "mols.py")
# Python 版用解释器启动；墨语言版是编译好的可执行文件，直接跑
RUN = [sys.executable, MOLS] if MOLS.endswith(".py") else [MOLS]

PASS = 0
FAIL = 0


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
        print("  ✓ %s" % name)
    else:
        FAIL += 1
        print("  ✗ %s: got %r, want %r" % (name, got, want))


def check_true(name, cond, info=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  ✓ %s" % name)
    else:
        FAIL += 1
        print("  ✗ %s %s" % (name, info))


class Client:
    def __init__(self, root):
        self.p = subprocess.Popen(
            RUN + [root],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, cwd=root)
        self.id = 0

    def send(self, method, params=None, notify=False):
        self.id += 1
        msg = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if not notify:
            msg["id"] = self.id
        b = json.dumps(msg).encode()
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
        self.p.stdin.flush()
        if notify:
            return None
        return self.read_for(self.id)

    def read_frame(self):
        """读一帧（可能是对请求的响应，也可能是服务器主动的通知）。"""
        while True:
            line = self.p.stdout.readline()
            if not line:
                return None
            if not line.lower().startswith(b"content-length:"):
                continue
            n = int(line.split(b":")[1].strip())
            self.p.stdout.readline()
            return json.loads(self.p.stdout.read(n).decode())

    def read_for(self, want_id):
        """读帧，跳过中间的通知（publishDiagnostics）。"""
        diags = []
        while True:
            msg = self.read_frame()
            if msg is None:
                return None, diags
            if msg.get("method") == "textDocument/publishDiagnostics":
                diags.append(msg["params"])
                continue
            if msg.get("id") == want_id:
                return msg.get("result"), diags

    # 🔴 didOpen / didChange 是**通知**，服务器不会回 id 响应。
    #    第一版用发请求的路径等响应，于是 read_for 永久阻塞 ——
    #    表现为测试挂死到被杀，而不是报错，很难想到是协议方向搞错。
    def notify_and_diag(self, method, params):
        self.send(method, params, notify=True)
        msg = self.read_frame()
        if msg and msg.get("method") == "textDocument/publishDiagnostics":
            return msg["params"].get("diagnostics", [])
        return []

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        self.p.terminate()


SRC = '''import "io.mo";

enum Color { RED = 1; GREEN = 2; BLUE = 3; }

struct Point { x: i64; y: i64; }

var GCOUNT: i64 = 0;

fn add(a: i64, b: i64) -> i64 {
    return a + b;
}

fn main() -> i64 {
    let v: i64 = add(1, 2);
    GCOUNT = v;
    print("done\\n");
    return 0;
}
'''


def main():
    tmp = tempfile.mkdtemp(prefix="lsptest-")
    path = os.path.join(tmp, "t.mo")
    open(path, "w").write(SRC)
    uri = "file://" + path

    c = Client(ROOT)

    print("== initialize ==")
    r, _ = c.send("initialize", {"rootUri": "file://" + ROOT})
    check_true("返回 capabilities", bool(r and "capabilities" in r))
    caps = r["capabilities"]
    check("definitionProvider", caps.get("definitionProvider"), True)
    check("hoverProvider", caps.get("hoverProvider"), True)
    check("documentSymbolProvider", caps.get("documentSymbolProvider"), True)
    check_true("有 semanticTokens legend",
               "tokenTypes" in caps.get("semanticTokensProvider", {}).get("legend", {}))

    print("== didOpen —— 诊断 ==")
    ds = c.notify_and_diag("textDocument/didOpen",
                           {"textDocument": {"uri": uri, "text": SRC}})
    # 这份源码是合法的，应当没有 error 级诊断
    errs = [d for d in ds if d["severity"] == 1]
    check("合法源码无 error 诊断", len(errs), 0)

    print("== documentSymbol —— 大纲 ==")
    r, _ = c.send("textDocument/documentSymbol", {"textDocument": {"uri": uri}})
    names = sorted(set(s["name"] for s in r))
    for n in ["add", "main", "Color", "RED", "Point", "GCOUNT", "x", "v"]:
        check_true("大纲含 %s" % n, n in names, str(names))

    print("== definition —— 跳转定义 ==")
    # `add(1, 2)` 在第 13 行（0-based）
    r, _ = c.send("textDocument/definition",
                  {"textDocument": {"uri": uri},
                   "position": {"line": 13, "character": 18}})
    check_true("add 有定义", bool(r), str(r))
    if r:
        check("add 定义行号", r[0]["range"]["start"]["line"], 8)

    # Point 在第 4 行
    r, _ = c.send("textDocument/definition",
                  {"textDocument": {"uri": uri},
                   "position": {"line": 4, "character": 8}})
    check_true("Point 有定义", bool(r))
    if r:
        check("Point 定义行号", r[0]["range"]["start"]["line"], 4)

    print("== hover —— 悬停 ==")
    r, _ = c.send("textDocument/hover",
                  {"textDocument": {"uri": uri},
                   "position": {"line": 13, "character": 18}})
    check_true("hover 有内容", bool(r))
    if r:
        val = r["contents"]["value"]
        check_true("hover 显示签名", "fn add(a: i64, b: i64) -> i64" in val, val)

    print("== references —— 查找引用 ==")
    r, _ = c.send("textDocument/references",
                  {"textDocument": {"uri": uri},
                   "position": {"line": 13, "character": 18}})
    check_true("add 引用 >= 1 处", len(r) >= 1, str(r))

    print("== 语义高亮 ==")
    r, _ = c.send("textDocument/semanticTokens/full", {"textDocument": {"uri": uri}})
    check_true("token 数据非空", len(r["data"]) > 0)
    check("token 数据是 5 的倍数", len(r["data"]) % 5, 0)

    print("== 跨文件跳转（import 的库）==")
    r, _ = c.send("textDocument/definition",
                  {"textDocument": {"uri": uri},
                   "position": {"line": 15, "character": 5}})
    check_true("print 能跳到 io.mo", bool(r) and r[0]["uri"].endswith("io.mo"),
               str(r) if r else "无结果")

    print("== 错误诊断（真的写错）==")
    # 🔴 用 nosuchfunc 而不是 `print_i64("x")` —— 后者**不报错**。
    #    墨语言是弱类型：字符串字面量就是个地址，当 i64 传完全合法。
    #    第一版用它当"错误用例"，结果诊断数为 0，看起来像诊断功能坏了，
    #    其实是**用例本身没错**。
    BAD = 'import "io.mo";\nfn main() -> i64 {\n    nosuchfunc(1);\n    return 0;\n}\n'
    open(path, "w").write(BAD)
    ds = c.notify_and_diag("textDocument/didChange",
                           {"textDocument": {"uri": uri},
                            "contentChanges": [{"text": BAD}]})
    check_true("发现编译错误", len(ds) >= 1, str(ds))
    if ds:
        check("错误行号（0-based）", ds[0]["range"]["start"]["line"], 2)
        check_true("错误有消息", len(ds[0]["message"]) > 0, ds[0]["message"])

    c.close()
    print("\n通过 %d / 失败 %d" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
