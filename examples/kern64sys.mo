# kern64sys.mo —— ARM64 裸机上的最小独立系统
#
#   bash tools/kernel64.sh examples/kern64sys.mo /tmp/mosys64.elf
#   python3 tools/kern64run.py /tmp/mosys64.elf --keys 'help\rls\r'
#
# 与 examples/kernel64.mo 的关系：那是**内核**（开机、自检、停机），
# 这是**系统**（内核起来之后能干什么）。三件套：
#
#   1. RAMFS   —— 内存文件系统。裸机没有磁盘也没有 OS，包管理要持久化
#                 状态，只能自己提供一个（v1.161 的 uspace 靠 Linux 的
#                 *at 系统调用，这里一个 syscall 都没有）。
#   2. shell   —— 通过 UART 读命令。ARM64 没有 I/O 端口，键盘只能走
#                 同一块 PL011 的 MMIO 轮询读。
#   3. pkg     —— 装包、执行、卸包。包是一串栈式 VM 指令，装进来就能跑。
#
# 输入是非阻塞的 uart_trygetc：模拟器只能注入有限按键，内核读到 -1
# 就认为输入耗尽并停机。真机上这里会换成阻塞读。

# mo-target: kern-aarch64   # 非原生后端，projcheck 跳过原生编译

var FSN: i64 = 0;
var FSNAME: [128] byte = 0;      # 8 个文件 × 16 字节名字
var FSDATA: [512] byte = 0;      # 8 个文件 × 64 字节内容
var FSLEN: [8] i64 = 0;
var FSUSE: [8] i64 = 0;

var PKGN: i64 = 0;
var PKGNAME: [64] byte = 0;      # 4 个包 × 16 字节名字
var PKGCODE: [64] i64 = 0;       # 4 个包 × 16 条指令
var PKGLEN: [4] i64 = 0;

var LINE: [128] byte = 0;
var CUR: i64 = 0;
var TPOS: i64 = 0;
var TOK: [16] byte = 0;
var NAMEBUF: [16] byte = 0;
var ONE: [2] byte = 0;
var STACK: [64] i64 = 0;
var NCMD: i64 = 0;

# 指令编码：每条两位十进制数，十位=操作码，个位=立即数
#   0n = PUSH n    1n = ADD    2n = SUB    3n = MUL    9n = HALT
# 例：05 03 10 90  →  push 5, push 3, add, halt  →  8

# 注意：墨语言的指针**不能**当 i64 形参传 —— 后端生成的是 unsigned char*，
# 传给 long long 形参会触发 -Wint-conversion。所以本文件所有"名字"一律走
# 全局缓冲 NAMEBUF，函数不再接收字符串指针。
fn atoi_tok() -> i64 {
    let i: i64 = 0;
    let v: i64 = 0;
    let c: i64 = load8(&TOK + i);
    while c != 0 {
        if c >= 48 {
            if c <= 57 {
                v = v * 10 + (c - 48);
            }
        }
        i = i + 1;
        c = load8(&TOK + i);
    }
    return v;
}

fn fs_find() -> i64 {
    let i: i64 = 0;
    while i < 8 {
        if FSUSE[i] == 1 {
            if streq(&FSNAME + i * 16, &NAMEBUF) == 1 {
                return i;
            }
        }
        i = i + 1;
    }
    return -1;
}

fn fs_create() -> i64 {
    if strlen(&NAMEBUF) > 15 {
        return -2;
    }
    let i: i64 = 0;
    while i < 8 {
        if FSUSE[i] == 0 {
            FSUSE[i] = 1;
            FSLEN[i] = 0;
            strcpy(&FSNAME + i * 16, &NAMEBUF);
            store8(&FSDATA + i * 64, 0);
            FSN = FSN + 1;
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn fs_write() -> i64 {
    let s: i64 = fs_find();
    if s < 0 {
        s = fs_create();
    }
    if s < 0 {
        return s;
    }
    let i: i64 = 0;
    let c: i64 = load8(&TOK + i);
    while c != 0 {
        if i < 63 {
            store8(&FSDATA + s * 64 + i, c);
        }
        i = i + 1;
        c = load8(&TOK + i);
    }
    store8(&FSDATA + s * 64 + i, 0);
    FSLEN[s] = i;
    return i;
}

fn fs_cat() -> i64 {
    let s: i64 = fs_find();
    if s < 0 {
        print("\n? no such file");
        return -1;
    }
    print("\n");
    print(&FSDATA + s * 64);
    return FSLEN[s];
}

fn fs_rm() -> i64 {
    let s: i64 = fs_find();
    if s < 0 {
        return -1;
    }
    FSUSE[s] = 0;
    FSLEN[s] = 0;
    store8(&FSNAME + s * 16, 0);
    FSN = FSN - 1;
    return 0;
}

fn fs_ls() -> i64 {
    let i: i64 = 0;
    print("\nfiles=");
    print_i64(FSN);
    while i < 8 {
        if FSUSE[i] == 1 {
            print("\n  ");
            print(&FSNAME + i * 16);
            print(" len=");
            print_i64(FSLEN[i]);
        }
        i = i + 1;
    }
    return FSN;
}

fn pkg_new() -> i64 {
    if strlen(&NAMEBUF) > 15 {
        return -2;
    }
    let i: i64 = 0;
    while i < 4 {
        if PKGLEN[i] == 0 {
            strcpy(&PKGNAME + i * 16, &NAMEBUF);
            PKGN = PKGN + 1;
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn pkg_slot() -> i64 {
    let i: i64 = 0;
    while i < 4 {
        if PKGLEN[i] > 0 {
            if streq(&PKGNAME + i * 16, &NAMEBUF) == 1 {
                return i;
            }
        }
        i = i + 1;
    }
    return -1;
}

fn vm_exec(slot: i64) -> i64 {
    let sp: i64 = 0;
    let i: i64 = 0;
    let n: i64 = PKGLEN[slot];
    let done: i64 = 0;
    let ret: i64 = -1;
    while i < n {
        if done == 0 {
            let op: i64 = PKGCODE[slot * 16 + i];
            let oc: i64 = op / 10;
            let imm: i64 = op - oc * 10;
            if oc == 0 {
                STACK[sp] = imm;
                sp = sp + 1;
            }
            if oc == 1 {
                if sp < 2 {
                    return -3;
                }
                STACK[sp - 2] = STACK[sp - 2] + STACK[sp - 1];
                sp = sp - 1;
            }
            if oc == 2 {
                if sp < 2 {
                    return -3;
                }
                STACK[sp - 2] = STACK[sp - 2] - STACK[sp - 1];
                sp = sp - 1;
            }
            if oc == 3 {
                if sp < 2 {
                    return -3;
                }
                STACK[sp - 2] = STACK[sp - 2] * STACK[sp - 1];
                sp = sp - 1;
            }
            if oc == 9 {
                if sp < 1 {
                    return -3;
                }
                ret = STACK[sp - 1];
                done = 1;
            }
        }
        i = i + 1;
    }
    return ret;
}

fn pkg_ls() -> i64 {
    let i: i64 = 0;
    print("\npackages=");
    print_i64(PKGN);
    while i < 4 {
        if PKGLEN[i] > 0 {
            print("\n  ");
            print(&PKGNAME + i * 16);
            print(" ops=");
            print_i64(PKGLEN[i]);
        }
        i = i + 1;
    }
    return PKGN;
}

fn next_tok() -> i64 {
    let n: i64 = strlen(&LINE);
    let i: i64 = 0;
    let c: i64 = 0;
    let done: i64 = 0;
    store8(&TOK, 0);
    # 两个版本都错在游标推进上，而且错法相反：
    #   1) 把 TPOS+1 放进 done==0 块内 → 取完 token 后还有剩余字符时
    #      TPOS 不动 → **死循环**（单 token 命令恰好走到串尾，全绿）。
    #   2) 无条件推进 → 第一次调用就把整行吃完，后续调用一律返回空
    #      token → write/pkg 的参数全部丢失（静默，只表现为 wrote=0）。
    # 正确的是：循环条件本身就是 done==0，越界在循环内判断。
    while done == 0 {
        if TPOS >= n {
            done = 1;
        } else {
            c = load8(&LINE + TPOS);
            TPOS = TPOS + 1;
            if c == 32 {
                if i > 0 {
                    done = 1;
                }
            } else {
                if i < 15 {
                    store8(&TOK + i, c);
                    i = i + 1;
                }
            }
        }
    }
    store8(&TOK + i, 0);
    return i;
}

fn do_cmd() -> i64 {
    NCMD = NCMD + 1;
    TPOS = 0;
    let l: i64 = next_tok();
    if l == 0 {
        return 0;
    }
    if streq(&TOK, "help") == 1 {
        print("\nls | write <n> <text> | cat <n> | rm <n> | pkg <n> <ops> | run <n> | pkgs | exit");
        return 0;
    }
    if streq(&TOK, "ls") == 1 {
        fs_ls();
        return 0;
    }
    if streq(&TOK, "pkgs") == 1 {
        pkg_ls();
        return 0;
    }
    if streq(&TOK, "cat") == 1 {
        next_tok();
        strcpy(&NAMEBUF, &TOK);
        fs_cat();
        return 0;
    }
    if streq(&TOK, "rm") == 1 {
        next_tok();
        strcpy(&NAMEBUF, &TOK);
        print("\nrm=");
        print_i64(fs_rm());
        return 0;
    }
    if streq(&TOK, "write") == 1 {
        next_tok();
        strcpy(&NAMEBUF, &TOK);
        next_tok();
        print("\nwrote=");
        print_i64(fs_write());
        return 0;
    }
    if streq(&TOK, "run") == 1 {
        next_tok();
        strcpy(&NAMEBUF, &TOK);
        let s: i64 = pkg_slot();
        if s < 0 {
            print("\n? no such package");
            return 0;
        }
        print("\n=");
        print_i64(vm_exec(s));
        return 0;
    }
    if streq(&TOK, "pkg") == 1 {
        next_tok();
        strcpy(&NAMEBUF, &TOK);
        let slot: i64 = pkg_new();
        if slot < 0 {
            print("\npkg err=");
            print_i64(slot);
            return 0;
        }
        let k: i64 = 0;
        let idx: i64 = 0;
        let go: i64 = 1;
        while idx < 16 {
            if go == 1 {
                let m: i64 = next_tok();
                if m == 0 {
                    go = 0;
                } else {
                    PKGCODE[slot * 16 + k] = atoi_tok();
                    k = k + 1;
                }
            }
            idx = idx + 1;
        }
        PKGLEN[slot] = k;
        print("\ninstalled ops=");
        print_i64(k);
        return 0;
    }
    if streq(&TOK, "exit") == 1 {
        return 1;
    }
    print("\n? ");
    print(&TOK);
    return 0;
}

fn shell() -> i64 {
    print("mo> ");
    let halt: i64 = 0;
    let guard: i64 = 0;
    while halt == 0 {
        if guard < 4096 {
            let c: i64 = uart_trygetc();
            if c < 0 {
                halt = 1;
            } else {
                if c == 13 {
                    print("\n");
                    let r: i64 = do_cmd();
                    if r == 1 {
                        halt = 1;
                    }
                    CUR = 0;
                    store8(&LINE, 0);
                    print("\nmo> ");
                } else {
                    if c == 10 {
                        print("\n");
                        let r2: i64 = do_cmd();
                        if r2 == 1 {
                            halt = 1;
                        }
                        CUR = 0;
                        store8(&LINE, 0);
                        print("\nmo> ");
                    } else {
                        if CUR < 120 {
                            store8(&LINE + CUR, c);
                            CUR = CUR + 1;
                            store8(&LINE + CUR, 0);
                            store8(&ONE, c);
                            print(&ONE);
                        }
                    }
                }
            }
            guard = guard + 1;
        } else {
            halt = 1;
        }
    }
    return 0;
}

fn main() -> i64 {
    print("\nMO-KERN64-SYS BOOT\n");
    print("arch=aarch64  console=mmio-uart@0x09000000\n");
    print("no libc / no syscall / no host os\n");
    print("ramfs + shell + pkg\n");
    shell();
    print("\ncmds=");
    print_i64(NCMD);
    print("\n");
    print("MO-KERN64-SYS HALT\n");
    return 0;
}
