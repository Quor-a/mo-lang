# lsptest.mo —— 墨语言写的 LSP 测试驱动（客户端）
#
# 为什么必须换成墨语言实现：
#   「自包含生态」要求连"测试驱动"也不借别人的手。此前 tools/lsptest.py
#   是 Python 写的 —— 服务器 mols 已经是墨语言写的，驱动却还是 Python。
#
# 它做什么：
#   spawn 起 bin/mols（墨语言服务器），用管道说 LSP 协议，
#   跑与 lsptest.py **同一套** 27 项断言，逐项比对具体行号/字符串/数量。
#
# 与 lsptest.py 的关系：
#   Python 版保留为**独立实现**做交叉验证。两个客户端、同一个服务器，
#   各自独立得出一致结论，才谈得上"等价"。
#
# ⚠️ 已知限制（不假装支持）：
#   - 只校验字段的子串/首个匹配，不做完整 JSON 树遍历
#   - semanticTokens 只数 data 元素个数，不校验每个 token 的类型
import "str.mo";
import "io.mo";
import "fs.mo";
import "json.mo";

# ============================================================ 缓冲

var PASS: i64 = 0;
var FAIL: i64 = 0;

var SRVP: [512] byte = 0;      # 服务器可执行文件路径
var ROOTP: [512] byte = 0;     # 项目根目录（同步传给服务器 + chdir）
var TMPD: [512] byte = 0;      # 临时目录
var URI_PATH: [512] byte = 0;  # 临时文件真实路径
var URI: [640] byte = 0;       # file:// + URI_PATH

var SRCTXT: [8192] byte = 0;   # 合法源码
var BADTXT: [1024] byte = 0;   # 故意写错的源码

var PIN: [2] i64 = 0;          # [0]=child 读(我们不管) [1]=我们写(child stdin)
var POUT: [2] i64 = 0;         # [0]=我们读(child stdout) [1]=child 写
var CHILD: i64 = 0;

var OUT: [65536] byte = 0;
var OUTN: i64 = 0;
var HDR: [64] byte = 0;
var TB: [64] byte = 0;
var RB: [65536] byte = 0;
var RBN: i64 = 0;
var RESP: [65536] byte = 0;
var DIAGS: [65536] byte = 0;
var VBUF: [8192] byte = 0;
var UBUF: [512] byte = 0;
var MBUF: [1024] byte = 0;

# ============================================================ 输出（构造请求体）

fn o_reset() -> i64 {
    OUTN = 0;
    return 0;
}

fn o_c(c: i64) -> i64 {
    store8(&OUT + OUTN, c);
    OUTN = OUTN + 1;
    return 0;
}

fn o_str(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        store8(&OUT + OUTN, c);
        OUTN = OUTN + 1;
        i = i + 1;
        c = load8(s + i);
    }
    return 0;
}

fn o_int(v: i64) -> i64 {
    let n: i64 = utoa(v, &TB, 10);
    return o_str(&TB);
}

fn o_esc_c(c: i64) -> i64 {
    if c == 34 { o_c(92); o_c(34); return 0; }
    if c == 92 { o_c(92); o_c(92); return 0; }
    if c == 10 { o_c(92); o_c(110); return 0; }
    if c == 9  { o_c(92); o_c(116); return 0; }
    if c == 13 { o_c(92); o_c(114); return 0; }
    o_c(c);
    return 0;
}

fn o_esc(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        o_esc_c(c);
        i = i + 1;
        c = load8(s + i);
    }
    return 0;
}

fn w_frame() -> i64 {
    strcpy(&HDR, "Content-Length: ");
    strcat_i64(&HDR, OUTN);
    strcat(&HDR, "\r\n\r\n");
    let l: i64 = strlen(&HDR);
    syscall(1, PIN[1], &HDR, l, 0, 0, 0);
    syscall(1, PIN[1], &OUT, OUTN, 0, 0, 0);
    return 0;
}

# ============================================================ 子进程

fn spawn() -> i64 {
    let raw: [8] byte = 0;
    let v: i64 = 0;
    let r: i64 = syscall(22, &raw, 0, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    v = load64(&raw);
    store64(&PIN, v & 4294967295);
    store64(&PIN + 8, (v / 4294967296) & 4294967295);
    r = syscall(22, &raw, 0, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    v = load64(&raw);
    store64(&POUT, v & 4294967295);
    store64(&POUT + 8, (v / 4294967296) & 4294967295);
    let ch: i64 = syscall(57, 0, 0, 0, 0, 0, 0);
    if ch == 0 {
        syscall(3, PIN[1], 0, 0, 0, 0, 0);
        syscall(3, POUT[0], 0, 0, 0, 0, 0);
        syscall(33, PIN[0], 0, 0, 0, 0, 0);
        syscall(33, POUT[1], 1, 0, 0, 0, 0);
        syscall(3, PIN[0], 0, 0, 0, 0, 0);
        syscall(3, POUT[1], 0, 0, 0, 0, 0);
        syscall(80, &ROOTP, 0, 0, 0, 0, 0);
        let av: [3] i64 = 0;
        store64(&av, &SRVP);
        store64(&av + 8, &ROOTP);
        store64(&av + 16, 0);
        syscall(59, &SRVP, &av, 0, 0, 0, 0);
        syscall(60, 127, 0, 0, 0, 0, 0);
    }
    syscall(3, PIN[0], 0, 0, 0, 0, 0);
    syscall(3, POUT[1], 0, 0, 0, 0, 0);
    CHILD = ch;
    return 0;
}

# ============================================================ 读帧

fn atoi_after(s: i64) -> i64 {
    let i: i64 = 0;
    let c: i64 = load8(s);
    while c != 0 {
        if c == 58 { i = i + 1; break; }
        i = i + 1;
        c = load8(s + i);
    }
    while load8(s + i) == 32 { i = i + 1; }
    let v: i64 = 0;
    c = load8(s + i);
    while c != 0 {
        if is_digit(c) == 0 { break; }
        v = v * 10 + (c - 48);
        i = i + 1;
        c = load8(s + i);
    }
    return v;
}

fn pump() -> i64 {
    let n: i64 = syscall(0, POUT[0], &RB + RBN, 32768, 0, 0, 0);
    if n <= 0 { return 0 - 1; }
    RBN = RBN + n;
    return n;
}

fn take_msg() -> i64 {
    let p: i64 = strstr(&RB, "Content-Length:");
    if p < 0 { return 0; }
    let q: i64 = strstr(&RB + p, "\r\n\r\n");
    if q < 0 { return 0; }
    let bs: i64 = p + q + 4;
    let n: i64 = atoi_after(&RB + p);
    if RBN - bs < n { return 0; }
    memcpy(&RESP, &RB + bs, n);
    store8(&RESP + n, 0);
    let used: i64 = bs + n;
    memcpy(&RB, &RB + used, RBN - used);
    RBN = RBN - used;
    return 1;
}

fn read_msg() -> i64 {
    while 1 {
        if take_msg() == 1 { return 1; }
        if pump() < 0 { return 0; }
    }
    return 0;
}

fn wait_resp(want: i64) -> i64 {
    while 1 {
        if read_msg() == 0 { return 0; }
        if strstr(&RESP, "publishDiagnostics") >= 0 {
            strcpy(&DIAGS, &RESP);
            continue;
        }
        let id: i64 = json_int(&RESP, "id");
        if id == want { return 1; }
    }
    return 0;
}

fn notify_and_diag() -> i64 {
    if read_msg() == 0 { strcpy(&DIAGS, ""); return 0; }
    if strstr(&RESP, "publishDiagnostics") >= 0 {
        strcpy(&DIAGS, &RESP);
        return 1;
    }
    strcpy(&DIAGS, "");
    return 0;
}

# ============================================================ 发请求

fn send_init() -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://");
    o_esc(&ROOTP);
    o_str("\"}}");
    w_frame();
    return wait_resp(1);
}

fn send_didOpen() -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\",\"languageId\":\"mo\",\"version\":1,\"text\":\"");
    o_esc(&SRCTXT);
    o_str("\"}}}");
    w_frame();
    return notify_and_diag();
}

fn send_docSym(id: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"}}}");
    w_frame();
    return wait_resp(id);
}

fn send_def(id: i64, line: i64, col: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"},\"position\":{\"line\":");
    o_int(line);
    o_str(",\"character\":");
    o_int(col);
    o_str("}}}");
    w_frame();
    return wait_resp(id);
}

fn send_hover(id: i64, line: i64, col: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"},\"position\":{\"line\":");
    o_int(line);
    o_str(",\"character\":");
    o_int(col);
    o_str("}}}");
    w_frame();
    return wait_resp(id);
}

fn send_refs(id: i64, line: i64, col: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"},\"position\":{\"line\":");
    o_int(line);
    o_str(",\"character\":");
    o_int(col);
    o_str("},\"context\":{\"includeDeclaration\":true}}");
    w_frame();
    return wait_resp(id);
}

fn send_sem(id: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"id\":");
    o_int(id);
    o_str(",\"method\":\"textDocument/semanticTokens/full\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"}}}");
    w_frame();
    return wait_resp(id);
}

fn send_didChange(txt: i64) -> i64 {
    o_reset();
    o_str("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"");
    o_esc(&URI);
    o_str("\"},\"contentChanges\":[{\"text\":\"");
    o_esc(txt);
    o_str("\"}]}}");
    w_frame();
    return notify_and_diag();
}

# ============================================================ 断言

fn check(name: i64, got: i64, want: i64) -> i64 {
    if got == want {
        PASS = PASS + 1;
        print("  ✓ ");
        print(name);
        print("\n");
    } else {
        FAIL = FAIL + 1;
        print("  ✗ ");
        print(name);
        print(": got ");
        print_i64(got);
        print(", want ");
        print_i64(want);
        print("\n");
    }
    return 0;
}

fn check_true(name: i64, cond: i64, info: i64) -> i64 {
    if cond == 1 {
        PASS = PASS + 1;
        print("  ✓ ");
        print(name);
        print("\n");
    } else {
        FAIL = FAIL + 1;
        print("  ✗ ");
        print(name);
        print(" ");
        print(info);
        print("\n");
    }
    return 0;
}

fn count_sub(s: i64, sub: i64) -> i64 {
    let n: i64 = 0;
    let p: i64 = 0;
    while 1 {
        p = strstr(s + p, sub);
        if p < 0 { break; }
        n = n + 1;
        p = p + strlen(sub);
    }
    return n;
}

fn count_data() -> i64 {
    let p: i64 = strstr(&RESP, "\"data\":[");
    if p < 0 { return 0; }
    p = p + 8;
    let c: i64 = load8(&RESP + p);
    if c == 93 { return 0; }
    let n: i64 = 1;
    while c != 93 {
        if c == 44 { n = n + 1; }
        p = p + 1;
        c = load8(&RESP + p);
        if c == 0 { break; }
    }
    return n;
}

# ============================================================ 源码

fn build_src() -> i64 {
    strcpy(&SRCTXT, "import \"io.mo\";\n\nenum Color { RED = 1; GREEN = 2; BLUE = 3; }\n\nstruct Point { x: i64; y: i64; }\n\nvar GCOUNT: i64 = 0;\n\nfn add(a: i64, b: i64) -> i64 {\n    return a + b;\n}\n\nfn main() -> i64 {\n    let v: i64 = add(1, 2);\n    GCOUNT = v;\n    print(\"done\\n\");\n    return 0;\n}\n");
    strcpy(&BADTXT, "import \"io.mo\";\nfn main() -> i64 {\n    nosuchfunc(1);\n    return 0;\n}\n");
    return 0;
}

fn mk_tmp() -> i64 {
    let pid: i64 = syscall(39, 0, 0, 0, 0, 0, 0);
    strcpy(&TMPD, "/tmp/lsptest-");
    strcat_i64(&TMPD, pid);
    syscall(83, &TMPD, 493, 0, 0, 0);
    strcpy(&URI_PATH, &TMPD);
    strcat(&URI_PATH, "/t.mo");
    strcpy(&URI, "file://");
    strcat(&URI, &URI_PATH);
    return 0;
}

fn write_tmp(txt: i64) -> i64 {
    let fd: i64 = fopen(&URI_PATH, 577, 420);
    if fd < 0 { return 0 - 1; }
    fwrite(fd, txt, strlen(txt));
    fclose(fd);
    return 0;
}

# ============================================================ main

fn main() -> i64 {
    if argc() > 2 {
        strcpy(&SRVP, argv(1));
        strcpy(&ROOTP, argv(2));
    } else {
        strcpy(&SRVP, "bin/mols");
        strcpy(&ROOTP, ".");
    }
    build_src();
    mk_tmp();
    write_tmp(&SRCTXT);
    if spawn() < 0 {
        print("✗ spawn 服务器失败\n");
        return 1;
    }

    print("== initialize ==\n");
    if send_init() == 0 { print("✗ initialize 无响应\n"); return 1; }
    check_true("返回 capabilities", strstr(&RESP, "capabilities") >= 0, &RESP);
    check_true("definitionProvider", json_true(&RESP, "definitionProvider") == 1, &RESP);
    check_true("hoverProvider", json_true(&RESP, "hoverProvider") == 1, &RESP);
    check_true("documentSymbolProvider", json_true(&RESP, "documentSymbolProvider") == 1, &RESP);
    check_true("有 semanticTokens legend", strstr(&RESP, "tokenTypes") >= 0, &RESP);

    print("== didOpen —— 诊断 ==\n");
    send_didOpen();
    check("合法源码无 error 诊断", count_sub(&DIAGS, "\"severity\":1"), 0);

    print("== documentSymbol —— 大纲 ==\n");
    if send_docSym(2) == 0 { print("✗ documentSymbol 无响应\n"); return 1; }
    check_true("大纲含 add", strstr(&RESP, "\"name\":\"add\"") >= 0, &RESP);
    check_true("大纲含 main", strstr(&RESP, "\"name\":\"main\"") >= 0, &RESP);
    check_true("大纲含 Color", strstr(&RESP, "\"name\":\"Color\"") >= 0, &RESP);
    check_true("大纲含 RED", strstr(&RESP, "\"name\":\"RED\"") >= 0, &RESP);
    check_true("大纲含 Point", strstr(&RESP, "\"name\":\"Point\"") >= 0, &RESP);
    check_true("大纲含 GCOUNT", strstr(&RESP, "\"name\":\"GCOUNT\"") >= 0, &RESP);
    check_true("大纲含 x", strstr(&RESP, "\"name\":\"x\"") >= 0, &RESP);
    check_true("大纲含 v", strstr(&RESP, "\"name\":\"v\"") >= 0, &RESP);

    print("== definition —— 跳转定义 ==\n");
    if send_def(3, 13, 18) == 0 { print("✗ definition(add) 无响应\n"); return 1; }
    check_true("add 有定义", strstr(&RESP, "uri") >= 0, &RESP);
    check("add 定义行号", json_int(&RESP, "line"), 8);
    if send_def(4, 4, 8) == 0 { print("✗ definition(Point) 无响应\n"); return 1; }
    check_true("Point 有定义", strstr(&RESP, "uri") >= 0, &RESP);
    check("Point 定义行号", json_int(&RESP, "line"), 4);

    print("== hover —— 悬停 ==\n");
    if send_hover(5, 13, 18) == 0 { print("✗ hover 无响应\n"); return 1; }
    check_true("hover 有内容", strstr(&RESP, "contents") >= 0, &RESP);
    if json_str(&RESP, "value", &VBUF) == 1 {
        check_true("hover 显示签名", strstr(&VBUF, "fn add(a: i64, b: i64) -> i64") >= 0, &VBUF);
    } else {
        check_true("hover 显示签名", 0, &RESP);
    }

    print("== references —— 查找引用 ==\n");
    if send_refs(6, 13, 18) == 0 { print("✗ references 无响应\n"); return 1; }
    check_true("add 引用 >= 1 处", strstr(&RESP, "uri") >= 0, &RESP);

    print("== 语义高亮 ==\n");
    if send_sem(7) == 0 { print("✗ semanticTokens 无响应\n"); return 1; }
    let nd: i64 = count_data();
    check_true("token 数据非空", nd > 0, &RESP);
    check("token 数据是 5 的倍数", nd - (nd / 5) * 5, 0);

    print("== 跨文件跳转（import 的库）==\n");
    if send_def(8, 15, 5) == 0 { print("✗ definition(print) 无响应\n"); return 1; }
    if json_str(&RESP, "uri", &UBUF) == 1 {
        check_true("print 能跳到 io.mo", str_ends_with(&UBUF, "io.mo") == 1, &UBUF);
    } else {
        check_true("print 能跳到 io.mo", 0, &RESP);
    }

    print("== 错误诊断（真的写错）==\n");
    write_tmp(&BADTXT);
    send_didChange(&BADTXT);
    check_true("发现编译错误", count_sub(&DIAGS, "\"range\"") >= 1, &DIAGS);
    check("错误行号（0-based）", json_int(&DIAGS, "line"), 2);
    if json_str(&DIAGS, "message", &MBUF) == 1 {
        check_true("错误有消息", strlen(&MBUF) > 0, &MBUF);
    } else {
        check_true("错误有消息", 0, &DIAGS);
    }

    syscall(3, PIN[1], 0, 0, 0, 0, 0);
    syscall(61, CHILD, &TB, 0, 0, 0, 0);

    print("\n通过 ");
    print_i64(PASS);
    print(" / 失败 ");
    print_i64(FAIL);
    print("\n");
    if FAIL > 0 { return 1; }
    return 0;
}
