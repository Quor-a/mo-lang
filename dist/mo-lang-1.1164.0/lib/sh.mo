# sh —— 对标 shell 的能力（用墨语言自己写的）
#
# 一个 shell 的本质是这四件事，本库逐个实现：
#   1. 词法切分（含引号、转义）
#   2. 通配符展开（glob / fnmatch）
#   3. 进程控制（fork + execve + wait）
#   4. 通道与重定向（pipe + dup2）
#
# 全部是系统调用，不依赖 libc，所以编成 freestanding 也能用。
#
# 没做（诚实列出）：
#   - 环境变量表：墨语言不暴露 environ，这里用**自建 envp** 代替
#   - 作业控制（fg/bg/Ctrl-Z）：需要终端会话与信号组，留待后面
#   - 命令替换 $(...)、函数、别名：shell 语言层，不在本库范围
import "str.mo";
import "io.mo";
import "err.mo";
import "heap.mo";
import "mem.mo";
import "dir.mo";

# ---------------------------------------------------------------- 常量
var SH_PATH: [512] byte = 0;      # 可执行文件搜索路径

# capture 的输出缓冲
var SH_OUT: i64 = 0;
var SH_OUTN: i64 = 0;
var SH_CAPMAX: i64 = 262144;      # 单次捕获上限，防止无限增长

# ---------------------------------------------------------------- 进程

fn sh_fork() -> i64 { return syscall(57, 0, 0, 0, 0, 0, 0); }

# execve 自己发系统调用，不去 import pty.mo ——
# pty 需要 /dev/ptmx，把它拖进来会让纯 shell 场景多一份无关依赖。
fn sh_execve(path: i64, argv: i64, envp: i64) -> i64 {
    return syscall(59, path, argv, envp, 0, 0, 0);
}

# wait4(61)：返回 0..255 的退出码；被信号杀死时返回 128+signo（与 shell 一致）
var SH_ST: i64 = 0;
fn sh_wait(pid: i64) -> i64 {
    let r: i64 = syscall(61, pid, &SH_ST, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    if (SH_ST & 127) == 0 { return (SH_ST >> 8) & 255; }
    return 128 + (SH_ST & 127);
}

fn sh_exit(code: i64) -> i64 {
    syscall(60, code, 0, 0, 0, 0, 0);
    return 0;
}

# pipe(22)：out[0]=读端 out[1]=写端
#
# **这里有个真实的坑**：pipe(2) 写入的是**两个 int（4 字节）**，
# 不是两个 long。直接按 i64 读会把两个 fd 挤进同一个 8 字节槽 ——
# 实测读出 fds[0]=0x0000000400000003(=17179869187)、fds[1]=0，
# 于是 dup2 收到一堆无效 fd，报 "Bad file descriptor"。
# 所以必须按 32 位拆开。
fn sh_pipe(out: i64) -> i64 {
    let raw: [8] byte = 0;
    let r: i64 = syscall(22, &raw, 0, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    let v: i64 = load64(&raw);
    store64(out, v & 4294967295);
    store64(out + 8, (v / 4294967296) & 4294967295);
    return 0;
}
fn sh_dup2(old: i64, new: i64) -> i64 { return syscall(33, old, new, 0, 0, 0, 0); }
fn sh_close(fd: i64) -> i64 { return syscall(3, fd, 0, 0, 0, 0, 0); }

fn sh_chdir(p: i64) -> i64 { return syscall(80, p, 0, 0, 0, 0, 0); }
var SH_CWD: [4096] byte = 0;
fn sh_getcwd() -> i64 {
    let n: i64 = syscall(79, &SH_CWD, 4096, 0, 0, 0, 0);
    return &SH_CWD;
}

# ---------------------------------------------------------------- 环境
#
# 墨语言没有 environ，所以自建一张 envp 表。
# sh_setenv 只做"追加或替换"，够 shell 用。
var SH_ENV: [64] i64 = 0;
var SH_NENV: i64 = 0;

fn sh_envp() -> i64 { return &SH_ENV; }

fn sh_setenv(kv: i64) -> i64 {
    let i: i64 = 0;
    while i < SH_NENV {
        if streq(SH_ENV[i], kv) == 1 { return 0; }
        i = i + 1;
    }
    if SH_NENV < 63 {
        let d: i64 = str_dup(kv);
        store64(&SH_ENV + SH_NENV * 8, d);
        SH_NENV = SH_NENV + 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 查找

var SH_BIN: [4096] byte = 0;
var SH_SEG: [512] byte = 0;     # PATH 段拼接缓冲 —— 必须是全局的

# 在 PATH 里找可执行文件。命中返回堆上的完整路径，否则 0。
#
# 曾经这里在 while 循环内部写 `let seg: [512] byte = 0;`，结果
# sh_which("git") 恒返回 0（找不到任何 PATH 第二段的命令），而
# 手工在循环外拼同样的字符串却正确。症状是 "command not found"，
# 很容易误判成 PATH 环境没传进来 —— 实际是循环内声明的局部数组
# 不按预期工作。数组一律用全局缓冲。
fn sh_which(name: i64) -> i64 {
    # str_dup 走 mem.mo 的 bump 分配器，而未初始化的 alloc 会把 brk
    # 设成 4096 —— 低于真实数据段末尾，等于把数据段截掉：第一次调用
    # 返回 0（看着像"命令不存在"），第二次就段错误。所以这里必须保证
    # 堆已就绪，不能假设调用方初始化过。
    if heap_ready() == 0 { heap_init(); }
    if load8(name) == 47 {                 # 含 '/' 就按路径直接用
        if load8(SH_BIN) == 0 { return str_dup(name); }
        return str_dup(name);
    }
    if load8(&SH_PATH) == 0 { strcpy(&SH_PATH, "/usr/local/bin:/usr/bin:/bin"); }
    let p: i64 = &SH_PATH;
    let i: i64 = 0;
    let start: i64 = 0;
    while 1 {
        let c: i64 = load8(p + i);
        if c == 0 { break; }
        if c == 58 {                       # ':'
            let k: i64 = 0;
            while start + k < i {
                store8(&SH_SEG + k, load8(p + start + k));
                k = k + 1;
            }
            store8(&SH_SEG + k, 0);
            strcat(&SH_SEG, "/");
            strcat(&SH_SEG, name);
            if sh_is_exec(&SH_SEG) == 1 { return str_dup(&SH_SEG); }
            start = i + 1;
        }
        i = i + 1;
    }
    # 最后一段
    let m: i64 = 0;
    while load8(p + start + m) != 0 {
        store8(&SH_SEG + m, load8(p + start + m));
        m = m + 1;
    }
    store8(&SH_SEG + m, 0);
    strcat(&SH_SEG, "/");
    strcat(&SH_SEG, name);
    if sh_is_exec(&SH_SEG) == 1 { return str_dup(&SH_SEG); }
    return 0;
}

# 用 access(21, X_OK=1) 判断可执行
fn sh_is_exec(p: i64) -> i64 {
    let r: i64 = syscall(21, p, 1, 0, 0, 0);
    if r == 0 { return 1; }
    return 0;
}

# ---------------------------------------------------------------- 词法切分
#
# 支持：空格分隔、单引号与双引号（引号内空格不分词）、反斜杠转义。
# 结果写进 toks（i64 指针数组），返回 token 个数。
fn sh_split(line: i64, toks: i64) -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let buf: [1024] byte = 0;
    while load8(line + i) != 0 {
        let c: i64 = load8(line + i);
        if c == 32 { i = i + 1; }
        else {
            if c == 9 { i = i + 1; }
            else {
                let j: i64 = 0;
                while load8(line + i) != 0 {
                    let d: i64 = load8(line + i);
                    if d == 32 { break; }
                    if d == 9 { break; }
                    if d == 34 {                      # 双引号
                        i = i + 1;
                        while load8(line + i) != 34 {
                            if load8(line + i) == 0 { break; }
                            store8(&buf + j, load8(line + i));
                            j = j + 1;
                            i = i + 1;
                        }
                        i = i + 1;
                    } else {
                        if d == 39 {                  # 单引号
                            i = i + 1;
                            while load8(line + i) != 39 {
                                if load8(line + i) == 0 { break; }
                                store8(&buf + j, load8(line + i));
                                j = j + 1;
                                i = i + 1;
                            }
                            i = i + 1;
                        } else {
                            if d == 92 {              # 反斜杠
                                i = i + 1;
                                store8(&buf + j, load8(line + i));
                                j = j + 1;
                                i = i + 1;
                            } else {
                                store8(&buf + j, d);
                                j = j + 1;
                                i = i + 1;
                            }
                        }
                    }
                }
                store8(&buf + j, 0);
                if n < 63 {
                    let d2: i64 = str_dup(&buf);
                    store64(toks + n * 8, d2);
                    n = n + 1;
                }
            }
        }
    }
    store64(toks + n * 8, 0);
    return n;
}

# ---------------------------------------------------------------- 通配符

# fnmatch：支持 * 与 ?，其它字符要求完全相等
fn fnmatch(pat: i64, s: i64) -> i64 {
    let pi: i64 = 0;
    let si: i64 = 0;
    let star: i64 = 0 - 1;
    let ss: i64 = 0;
    while load8(s + si) != 0 {
        let pc: i64 = load8(pat + pi);
        if pc == 42 {
            star = pi;
            ss = si;
            pi = pi + 1;
        } else {
            if pc == load8(s + si) { pi = pi + 1; si = si + 1; }
            else {
                if pc == 63 { pi = pi + 1; si = si + 1; }
                else {
                    if star >= 0 {
                        pi = star + 1;
                        ss = ss + 1;
                        si = ss;
                    } else {
                        return 0;
                    }
                }
            }
        }
    }
    while load8(pat + pi) == 42 { pi = pi + 1; }
    if load8(pat + pi) == 0 { return 1; }
    return 0;
}

# ---------------------------------------------------------------- 执行

# 执行 argv（以 0 结尾的指针数组）。只在子进程里调用；失败就 _exit。
fn sh_execvp(argv: i64) -> i64 {
    let name: i64 = load64(argv);
    let full: i64 = sh_which(name);
    if full == 0 {
        print("mo: command not found: ");
        print(name);
        print_nl();
        sh_exit(127);
    }
    # 注意：墨语言不支持函数调用嵌套在实参里（f(g(x)) 会解析错），
    # 必须先把结果取到变量。这是原生后端就有的限制。
    let env: i64 = sh_envp();
    let r: i64 = sh_execve(full, argv, env);
    # 到了这里说明 execve 失败
    print("mo: cannot exec: ");
    print(name);
    print_nl();
    sh_exit(126);
    return 0;
}

# 跑一条命令并**捕获**其 stdout。输出进 SH_OUT，返回退出码。
fn sh_capture(argv: i64) -> i64 {
    let fds: [2] i64 = 0;
    if sh_pipe(&fds) < 0 { err_set(E_IO, "pipe failed", "sh_capture"); return 0 - 1; }
    let pid: i64 = sh_fork();
    if pid == 0 {
        sh_close(fds[0]);
        sh_dup2(fds[1], 1);
        sh_close(fds[1]);
        sh_execvp(argv);
        sh_exit(127);
    }
    sh_close(fds[1]);
    SH_OUTN = 0;
    let buf: [4096] byte = 0;
    while 1 {
        let n: i64 = syscall(0, fds[0], &buf, 4096, 0, 0, 0);
        if n <= 0 { break; }
        if SH_OUTN + n < SH_CAPMAX {
            memcpy(SH_OUT + SH_OUTN, &buf, n);
            SH_OUTN = SH_OUTN + n;
        }
    }
    store8(SH_OUT + SH_OUTN, 0);
    sh_close(fds[0]);
    let rc: i64 = sh_wait(pid);
    return rc;
}

# 两级管道：a | b。b 的输出进 SH_OUT。
fn sh_pipe_exec(a: i64, b: i64) -> i64 {
    let fds: [2] i64 = 0;
    if sh_pipe(&fds) < 0 { err_set(E_IO, "pipe failed", "sh_pipe_exec"); return 0 - 1; }
    let p1: i64 = sh_fork();
    if p1 == 0 {
        sh_close(fds[0]);
        sh_dup2(fds[1], 1);
        sh_close(fds[1]);
        sh_execvp(a);
        sh_exit(127);
    }
    let fds2: [2] i64 = 0;
    if sh_pipe(&fds2) < 0 { return 0 - 1; }
    let p2: i64 = sh_fork();
    if p2 == 0 {
        sh_close(fds[1]);
        sh_dup2(fds[0], 0);
        sh_close(fds[0]);
        sh_close(fds2[0]);
        sh_dup2(fds2[1], 1);
        sh_close(fds2[1]);
        sh_execvp(b);
        sh_exit(127);
    }
    sh_close(fds[0]);
    sh_close(fds[1]);
    sh_close(fds2[1]);
    SH_OUTN = 0;
    let buf: [4096] byte = 0;
    while 1 {
        let n: i64 = syscall(0, fds2[0], &buf, 4096, 0, 0, 0);
        if n <= 0 { break; }
        if SH_OUTN + n < SH_CAPMAX {
            memcpy(SH_OUT + SH_OUTN, &buf, n);
            SH_OUTN = SH_OUTN + n;
        }
    }
    store8(SH_OUT + SH_OUTN, 0);
    sh_close(fds2[0]);
    let ra: i64 = sh_wait(p1);
    let rb: i64 = sh_wait(p2);
    return rb;
}

# 前台执行一条命令（不捕获，直接输出到终端）。返回退出码。
fn sh_run(argv: i64) -> i64 {
    let pid: i64 = sh_fork();
    if pid == 0 {
        sh_execvp(argv);
        sh_exit(127);
    }
    return sh_wait(pid);
}

# 重定向执行：把 stdout 写到文件（mode 0=截断 1=追加）
fn sh_redirect_out(argv: i64, path: i64, append: i64) -> i64 {
    # 🔴 v1.115 修掉的一个真 bug：覆盖模式原来是 65（O_WRONLY|O_CREAT），
    #    **缺 O_TRUNC(512)** —— `>` 打开文件时不会截断，只在开头覆盖写入。
    #    于是往一个已经存在且更长的文件里重定向时，尾部旧内容会残留：
    #        echo hi > f   （f 原本 98 字节）→ 得到 "hi\n" + 95 字节旧内容
    #    这与 shell 的 `>` 语义不符，而且**只在文件已存在时才发作**——
    #    第一次跑测试（文件不存在）永远通过，第二次起才失败。
    #    它藏了很久，靠的是测试套件自己的空转（test_done 返回值被丢弃）。
    let flags: i64 = 577;                # O_WRONLY|O_CREAT|O_TRUNC
    if append == 1 { flags = 1089; }     # |O_APPEND（追加不能截断）
    let pid: i64 = sh_fork();
    if pid == 0 {
        let fd: i64 = syscall(2, path, flags, 420, 0, 0);
        if fd < 0 { print("mo: cannot open for writing\n"); sh_exit(1); }
        sh_dup2(fd, 1);
        sh_close(fd);
        sh_execvp(argv);
        sh_exit(127);
    }
    return sh_wait(pid);
}

# 读取整个文件到 SH_OUT（供 shell 的 < 使用）
fn sh_slurp(path: i64) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0);
    if fd < 0 { err_set(E_FOUND, "cannot open", "sh_slurp"); return 0 - 1; }
    SH_OUTN = 0;
    let buf: [4096] byte = 0;
    while 1 {
        let n: i64 = syscall(0, fd, &buf, 4096, 0, 0, 0);
        if n <= 0 { break; }
        if SH_OUTN + n < SH_CAPMAX {
            memcpy(SH_OUT + SH_OUTN, &buf, n);
            SH_OUTN = SH_OUTN + n;
        }
    }
    store8(SH_OUT + SH_OUTN, 0);
    sh_close(fd);
    return SH_OUTN;
}
