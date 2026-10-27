# mosh.mo —— 用墨语言写的 shell
#
#   ./bin/moc examples/mosh.mo /tmp/mosh.elf && /tmp/mosh.elf
#
# 支持：外部命令、管道 a|b、重定向 > >>、内建 cd/pwd/echo/help/exit/env/which、
#       $? 上一条退出码、引号与转义、* 与 ? 通配符。
#
# 它证明墨语言能写"系统软件"而不只是"应用程序"：
# 全部能力来自 fork/execve/wait/pipe/dup2 五个系统调用，没有 libc。
import "sh.mo";
import "io.mo";
import "str.mo";
import "dir.mo";

var LAST: i64 = 0;
var LINE: [1024] byte = 0;
var TOKS: [64] i64 = 0;
var OUT: [262144] byte = 0;

# 打印上一条命令的退出码
fn show_status() -> i64 {
    print("exit=");
    print_i64(LAST);
    print_nl();
    return 0;
}

# 内建命令：返回 1 表示已处理，0 表示交给外部程序
fn builtin(n: i64) -> i64 {
    let a0: i64 = TOKS[0];
    if streq(a0, "exit") == 1 {
        if n > 1 { print("bye\n"); }
        sh_exit(0);
        return 1;
    }
    if streq(a0, "help") == 1 {
        print("mosh -- a shell written in the Mo language\n");
        print("  builtins: help exit cd pwd echo env which status\n");
        print("  syntax  : cmd args | cmd > file >> file\n");
        print("  glob    : * and ? are expanded\n");
        return 1;
    }
    if streq(a0, "cd") == 1 {
        if n > 1 {
            if sh_chdir(TOKS[1]) < 0 { print("cd: failed\n"); LAST = 1; return 1; }
        } else {
            sh_chdir("/");
        }
        LAST = 0;
        return 1;
    }
    if streq(a0, "pwd") == 1 {
        let c: i64 = sh_getcwd();
        print(c);
        print_nl();
        LAST = 0;
        return 1;
    }
    if streq(a0, "echo") == 1 {
        let i: i64 = 1;
        while i < n {
            print(TOKS[i]);
            if i + 1 < n { print(" "); }
            i = i + 1;
        }
        print_nl();
        LAST = 0;
        return 1;
    }
    if streq(a0, "env") == 1 {
        let i: i64 = 0;
        while i < SH_NENV {
            print(SH_ENV[i]);
            print_nl();
            i = i + 1;
        }
        LAST = 0;
        return 1;
    }
    if streq(a0, "which") == 1 {
        if n > 1 {
            let w: i64 = sh_which(TOKS[1]);
            if w == 0 { print("not found: "); print(TOKS[1]); print_nl(); LAST = 1; }
            else { print(w); print_nl(); LAST = 0; }
        }
        return 1;
    }
    if streq(a0, "status") == 1 { show_status(); return 1; }
    return 0;
}

# 按 * / ? 展开**最后一个**参数（够演示 glob 的实际用法）
fn try_glob(n: i64) -> i64 {
    let pat: i64 = TOKS[n - 1];
    if n < 1 { return n; }
    let has: i64 = 0;
    let i: i64 = 0;
    while load8(pat + i) != 0 {
        if load8(pat + i) == 42 { has = 1; }
        if load8(pat + i) == 63 { has = 1; }
        i = i + 1;
    }
    if has == 0 { return n; }
    # dir.mo 是迭代式 API：dir_open → dir_next(name, ty) → dir_close，
    # 状态在库内部，没有句柄概念。
    let r0: i64 = dir_open(".");
    if r0 < 0 { return n; }
    let nm: [256] byte = 0;
    let tyv: [1] i64 = 0;
    let cnt: i64 = 0;
    while dir_next(&nm, &tyv) == 1 {
        if fnmatch(pat, &nm) == 1 {
            if cnt == 0 { store64(&TOKS + (n - 1) * 8, str_dup(&nm)); }
            else {
                if n < 63 {
                    store64(&TOKS + n * 8, str_dup(&nm));
                    n = n + 1;
                }
            }
            cnt = cnt + 1;
        }
    }
    dir_close();
    if cnt == 0 { print("no match: "); print(pat); print_nl(); }
    return n;
}

fn main() -> i64 {
    # 必须先 heap_init()：str_dup / dir_list 走的都是 mem.mo 的 bump 分配器，
    # 而 hp 初值是 0 —— 不初始化就 alloc 会返回地址 0，一写就段错误。
    # 这类"忘了初始化"的错误在墨语言里没有运行时提示，只能靠记住。
    heap_init();
    SH_OUT = &OUT;
    sh_setenv("PATH=/usr/local/bin:/usr/bin:/bin");
    sh_setenv("HOME=/root");
    sh_setenv("SHELL=mosh");

    print("mosh -- Mo shell. 'help' for commands, 'exit' to quit.\n");

    while 1 {
        print("mo$ ");
        # 读一行
        let i: i64 = 0;
        while 1 {
            let one: [1] byte = 0;
            let r: i64 = syscall(0, 0, &one, 1, 0, 0, 0);
            if r <= 0 {
                print("\n");
                sh_exit(0);
            }
            let c: i64 = load8(&one);
            if c == 10 { break; }
            if i < 1020 {
                store8(&LINE + i, c);
                i = i + 1;
            }
        }
        store8(&LINE + i, 0);

        let n: i64 = sh_split(&LINE, &TOKS);
        if n == 0 { continue; }

        # 管道：只看一层 a | b
        let p: i64 = 0 - 1;
        i = 0;
        while i < n {
            if streq(TOKS[i], "|") == 1 { p = i; }
            i = i + 1;
        }
        if p > 0 {
            store64(&TOKS + p * 8, 0);
            let b: i64 = &TOKS;
            let a2: i64 = &TOKS + (p + 1) * 8;
            LAST = sh_pipe_exec(b, a2);
            print(SH_OUT);
            continue;
        }

        # 重定向：> 与 >>
        let red: i64 = 0 - 1;
        let app: i64 = 0;
        i = 0;
        while i < n {
            if streq(TOKS[i], ">") == 1 { red = i; app = 0; }
            if streq(TOKS[i], ">>") == 1 { red = i; app = 1; }
            i = i + 1;
        }
        if red >= 0 {
            let path: i64 = TOKS[red + 1];
            store64(&TOKS + red * 8, 0);
            LAST = sh_redirect_out(&TOKS, path, app);
            continue;
        }

        if builtin(n) == 1 { continue; }

        n = try_glob(n);
        LAST = sh_run(&TOKS);
        if LAST == 127 { print("mosh: command not found\n"); }
        else { if LAST == 126 { print("mosh: cannot exec\n"); } }
    }
    return 0;
}
