# mopkg —— 用墨语言写的包管理器
#
# 自包含生态的最后一环。此前编译器(moc)、标准库、调试信息生成已用墨语言
# 实现，唯独包管理器由 shell + awk + python3 写成（lock_set 里甚至内嵌了
# 一段 python）。本库把它改回墨语言，依赖只剩一个 git。
#
# 能力：init / fetch / tree / verify / update / list / remove
#
# 顺便说明一个用墨语言重写的好处：shell 版踩过 "tilde 展开" 的坑 ——
# 写 ${c#~} 时 ~ 在 pattern 位置会被展开成 $HOME，前缀删不掉，报错
# "operand expected"，离真正原因很远。墨语言没有这种隐式展开。
import "str.mo";
import "httpcli.mo";
import "io.mo";
import "aioclient.mo";
import "err.mo";
import "crypto.mo";
import "sh.mo";
import "fs.mo";
import "archive.mo";
import "net.mo";

# ---------------------------------------------------------------- 常量
var PKG_TOML: [16] byte = "mo.toml";
var PKG_LOCK: [16] byte = "mo.lock";
var PKG_DEP: [16] byte = ".deps";

# ---------------------------------------------------------------- 缓冲
var PKG_TXT: [32768] byte = 0;      # 当前 TOML 全文
var PKG_LK: [32768] byte = 0;       # 锁文件全文
var PKG_OUT: [65536] byte = 0;      # capture 输出
var PKG_LN: [1024] byte = 0;        # 当前行
var PKG_A: [256] byte = 0;
var PKG_B: [256] byte = 0;
var PKG_C: [256] byte = 0;
var PKG_D: [256] byte = 0;
var PKG_E: [256] byte = 0;
var PKG_P: [512] byte = 0;          # 路径拼接
var PKG_CMD: [16] i64 = 0;          # argv
var PKG_NAMES: [64] i64 = 0;        # 依赖名（指向 dup 的字符串）
var PKG_NN: i64 = 0;
var PKG_CLO: [64] i64 = 0;          # 依赖闭包
var PKG_CN: i64 = 0;
var PKG_BAD: i64 = 0;
var PKG_DEPTH: i64 = 0;
var PKG_SEC: [256] byte = 0;       # section 名专用 —— 不能复用 PKG_A，
                                   # 否则调用方把 PKG_A 当 out 传入时会互相覆盖
var PKG_VAL: [256] byte = 0;       # 键值解析专用
var PKG_NM: [256] byte = 0;        # 依赖名比较专用 —— 不能复用 PKG_A/B/C，
                                   # 它们可能正是调用方传进来的 out 缓冲
var PKG_NBUF: [4096] byte = 0;
var PKG_NBI: i64 = 0;

# ------------------------------------------------------- 递归 fetch 用队列
#
# 为什么用迭代 BFS 而不是递归：pkg_load_toml 写全局 PKG_TXT，
# pkg_dep_names 写全局 PKG_NAMES —— 递归调用会互相覆盖。BFS 每次只登记
# 一层就退出，不嵌套取用。
# pkg_closure / pkg_tree_visit 是递归的，已在 v1.151 修掉（局部副本 saved[]）——
# 此前那里留着半个修复：np = PKG_NN 存了却没人读，是 tools/unused.py 报
# 「写了但从未读」才把它重新翻出来的。
var QN: [64] i64 = 0;          # 包名
var QU: [64] i64 = 0;          # git url
var QR: [64] i64 = 0;          # ref
var QV: [64] i64 = 0;          # 版本约束
var QP: [64] i64 = 0;          # path（本地目录依赖；空 = 无）
var QF: [64] i64 = 0;          # file（.mo.tar.gz 依赖；空 = 无）
var QSH: [64] i64 = 0;         # v1.257：每包 sha256 字符串槽（qsave 句柄）
var VF_PATH: [512] byte = 0;
var VF_NAME: [256] byte = 0;
var VF_FN: [256] byte = 0;
var VF_TMP: [384] byte = 0;
var VF_BUF: [65536] byte = 0;
var VF_SHA: [80] byte = 0;
var VF_LSHA: [80] byte = 0;
var QN_N: i64 = 0;
var QPOOL: [16384] byte = 0;   # 队列字符串池（不用堆）
var QPI: i64 = 0;
var QPATH: [512] byte = 0;
var QBUF: [2048] byte = 0;
var QBUF2: [512] byte = 0;
var QVER: [256] byte = 0;
var QCM: [256] byte = 0;

# 名字池：不用 str_dup（heap），改用静态缓冲 —— 避免堆分配干扰
fn pkg_save_name(s: ptr) -> i64 {
    let d: i64 = 0;
    let n: i64 = strlen(s);
    if PKG_NBI + n + 1 >= 4096 { return 0; }
    d = &PKG_NBUF + PKG_NBI;
    strcpy(d, s);
    PKG_NBI = PKG_NBI + n + 1;
    return d;
}

# ---------------------------------------------------------------- 版本

fn pkg_ver_major(v: ptr) -> i64 {
    return pkg_ver_num(v) / 1000000;
}

fn pkg_ver_minor(v: ptr) -> i64 {
    let n: i64 = pkg_ver_num(v);
    return (n / 1000) - (n / 1000000) * 1000;
}

# "1.2.3" -> 1002003
fn pkg_ver_num(v: ptr) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let ch: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    let c: i64 = 0;
    let seg: i64 = 0;
    let seen: i64 = 0;
    while 1 {
        ch = load8(v + i);
        if ch == 0 { break; }
        if ch == 46 {
            if seg == 0 { a = n; }
            if seg == 1 { b = n; }
            seg = seg + 1;
            n = 0;
            seen = 1;
        }
        if ch >= 48 { if ch <= 57 { n = n * 10 + (ch - 48); } }
        i = i + 1;
    }
    if seen == 0 { return n * 1000000; }
    if seg == 1 { b = n; }
    if seg == 2 { c = n; }
    return a * 1000000 + b * 1000 + c;
}

# ver_match <实际版本> <约束>
#   "" | "*"  任意   =1.2.3 相等   >=/</>/<= 比较
#   ^1.2.3  >=1.2.3 且 <2.0.0     ~1.2.3  >=1.2.3 且 <1.3.0
fn pkg_ver_match(have: ptr, c: ptr) -> i64 {
    let h: i64 = pkg_ver_num(have);
    let n: i64 = strlen(c);
    let c0: i64 = 0;
    let c1: i64 = 0;
    let bn: i64 = 0;
    let hi: i64 = 0;
    if n == 0 { return 1; }
    if streq(c, "*") == 1 { return 1; }
    c0 = load8(c);
    if c0 == 62 {
        c1 = load8(c + 1);
        if c1 == 61 {
            strcpy(&PKG_A, c + 2);
            if h >= pkg_ver_num(&PKG_A) { return 1; }
            return 0;
        }
        strcpy(&PKG_A, c + 1);
        if h > pkg_ver_num(&PKG_A) { return 1; }
        return 0;
    }
    if c0 == 60 {
        c1 = load8(c + 1);
        if c1 == 61 {
            strcpy(&PKG_A, c + 2);
            if h <= pkg_ver_num(&PKG_A) { return 1; }
            return 0;
        }
        strcpy(&PKG_A, c + 1);
        if h < pkg_ver_num(&PKG_A) { return 1; }
        return 0;
    }
    if c0 == 61 {
        strcpy(&PKG_A, c + 1);
        if h == pkg_ver_num(&PKG_A) { return 1; }
        return 0;
    }
    if c0 == 94 {
        strcpy(&PKG_A, c + 1);
        bn = pkg_ver_num(&PKG_A);
        hi = (pkg_ver_major(&PKG_A) + 1) * 1000000;
        if h >= bn { if h < hi { return 1; } }
        return 0;
    }
    if c0 == 126 {
        strcpy(&PKG_A, c + 1);
        bn = pkg_ver_num(&PKG_A);
        hi = pkg_ver_major(&PKG_A) * 1000000 + (pkg_ver_minor(&PKG_A) + 1) * 1000;
        if h >= bn { if h < hi { return 1; } }
        return 0;
    }
    if h == pkg_ver_num(c) { return 1; }
    return 0;
}

# ---------------------------------------------------------------- 文本

# 从 txt 的 pos 处取一行到 line，返回下一行起始；结束返回 -1
fn pkg_line_at(txt: ptr, pos: i64, line: ptr) -> i64 {
    let i: i64 = 0;
    let ch: i64 = 0;
    let j: i64 = 0;
    ch = load8(txt + pos);
    if ch == 0 { return 0 - 1; }
    while 1 {
        ch = load8(txt + pos + i);
        if ch == 0 { break; }
        if ch == 10 { break; }
        i = i + 1;
    }
    j = 0;
    while j < i {
        store8(line + j, load8(txt + pos + j));
        j = j + 1;
    }
    store8(line + i, 0);
    if i > 0 { if load8(line + i - 1) == 13 { store8(line + i - 1, 0); } }
    return pos + i + 1;
}

# 跳过空白，返回第一个非空白的下标
fn pkg_skip(s: ptr) -> i64 {
    let i: i64 = 0;
    let ch: i64 = 0;
    while 1 {
        ch = load8(s + i);
        if ch == 0 { return i; }
        if ch != 32 { if ch != 9 { return i; } }
        i = i + 1;
    }
    return 0;
}

# 从 "..." 里取引号内容到 out；成功返回 1
fn pkg_quoted(s: ptr, out: ptr) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let ch: i64 = 0;
    let st: i64 = 0;
    while 1 {
        ch = load8(s + i);
        if ch == 0 { return 0; }
        if ch == 34 { st = i + 1; break; }
        i = i + 1;
    }
    while 1 {
        ch = load8(s + st + j);
        if ch == 0 { return 0; }
        if ch == 34 { break; }
        store8(out + j, ch);
        j = j + 1;
    }
    store8(out + j, 0);
    return 1;
}

# ---------------------------------------------------------------- TOML

# 读 TOML 到 PKG_TXT，返回字节数；失败 -1
fn pkg_load_toml(path: ptr) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0);
    let n: i64 = 0;
    let r: i64 = 0;
    if fd < 0 { return 0 - 1; }
    while 1 {
        r = syscall(0, fd, &PKG_TXT + n, 4096, 0, 0, 0);
        if r <= 0 { break; }
        n = n + r;
        if n > 32000 { break; }
    }
    store8(&PKG_TXT + n, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    return n;
}

# 提取 [dependencies] 段里的依赖名 -> PKG_NAMES，返回个数
fn pkg_dep_names(txt: ptr) -> i64 {
    let k: i64 = 0;
    let pos: i64 = 0;
    let insec: i64 = 0;
    let s: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let eq: i64 = 0;
    PKG_NN = 0;
    while 1 {
        pos = pkg_line_at(txt, pos, &PKG_LN);
        if pos < 0 { break; }
        s = pkg_skip(&PKG_LN);
        ch = load8(&PKG_LN + s);
        if ch == 0 {
            insec = insec;
        }
        if ch == 35 {
            insec = insec;
        }
        if ch == 91 {
            # [section]
            if insec == 1 { insec = 0; }
            strcpy(&PKG_A, &PKG_LN + s + 1);
            i = 0;
            while 1 {
                ch = load8(&PKG_A + i);
                if ch == 0 { break; }
                if ch == 93 { store8(&PKG_A + i, 0); break; }
                i = i + 1;
            }
            if streq(&PKG_A, "dependencies") == 1 { insec = 1; }
        }
        if insec == 1 {
            if ch != 91 {
                if ch != 35 {
                    if ch != 0 {
                        # name = ...
                        eq = 0;
                        i = s;
                        while 1 {
                            ch = load8(&PKG_LN + i);
                            if ch == 0 { break; }
                            if ch == 61 { eq = i; break; }
                            i = i + 1;
                        }
                        if eq > s {
                            k = 0;
                            while k < eq - s {
                                store8(&PKG_B + k, load8(&PKG_LN + s + k));
                                k = k + 1;
                            }
                            store8(&PKG_B + k, 0);
                            # 去尾部空白
                            k = strlen(&PKG_B) - 1;
                            while k >= 0 {
                                ch = load8(&PKG_B + k);
                                if ch != 32 { if ch != 9 { break; } }
                                store8(&PKG_B + k, 0);
                                k = k - 1;
                            }
                            if strlen(&PKG_B) > 0 {
                                if PKG_NN < 64 {
                                    PKG_NAMES[PKG_NN] = pkg_save_name(&PKG_B);
                                    PKG_NN = PKG_NN + 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return PKG_NN;
}

# 取依赖 name 的 key 字段（git / ref / version）到 out
fn pkg_dep_field(txt: ptr, name: ptr, key: ptr, out: ptr) -> i64 {
    let k: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    let pos: i64 = 0;
    let insec: i64 = 0;
    let s: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let eq: i64 = 0;
    let kn: i64 = strlen(key);
    store8(out, 0);
    while 1 {
        pos = pkg_line_at(txt, pos, &PKG_LN);
        if pos < 0 { break; }
        s = pkg_skip(&PKG_LN);
        ch = load8(&PKG_LN + s);
        if ch == 91 {
            if insec == 1 { insec = 0; }
            strcpy(&PKG_SEC, &PKG_LN + s + 1);
            i = 0;
            while 1 {
                ch = load8(&PKG_SEC + i);
                if ch == 0 { break; }
                if ch == 93 { store8(&PKG_SEC + i, 0); break; }
                i = i + 1;
            }
            if streq(&PKG_SEC, "dependencies") == 1 { insec = 1; }
        }
        if insec == 1 {
            if ch != 91 {
                if ch != 35 {
                    if ch != 0 {
                        eq = 0;
                        i = s;
                        while 1 {
                            ch = load8(&PKG_LN + i);
                            if ch == 0 { break; }
                            if ch == 61 { eq = i; break; }
                            i = i + 1;
                        }
                        if eq > s {
                            k = 0;
                            while k < eq - s {
                                store8(&PKG_NM + k, load8(&PKG_LN + s + k));
                                k = k + 1;
                            }
                            store8(&PKG_NM + k, 0);
                            k = strlen(&PKG_NM) - 1;
                            while k >= 0 {
                                ch = load8(&PKG_NM + k);
                                if ch != 32 { if ch != 9 { break; } }
                                store8(&PKG_NM + k, 0);
                                k = k - 1;
                            }
                            if streq(&PKG_NM, name) == 1 {
                                # 在这一行里找 key = "..."
                                p = strstr(&PKG_LN + s, key);
                                # strstr 返回的是**索引**不是地址，且找不到返回 -1 而非 0
                                if p >= 0 {
                                    q = pkg_quoted(&PKG_LN + s + p, out);
                                    return q;
                                }
                                return 0;
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# ---------------------------------------------------------------- 锁文件

fn pkg_load_lock() -> i64 {
    let fd: i64 = syscall(2, &PKG_LOCK, 0, 0, 0, 0);
    let n: i64 = 0;
    let r: i64 = 0;
    if fd < 0 { return 0 - 1; }
    while 1 {
        r = syscall(0, fd, &PKG_LK + n, 4096, 0, 0, 0);
        if r <= 0 { break; }
        n = n + r;
        if n > 32000 { break; }
    }
    store8(&PKG_LK + n, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    return n;
}

# 取 [[package]] 块里 name=want 的 key 字段
fn pkg_lock_field(name: ptr, key: ptr, out: ptr) -> i64 {
    let k: i64 = 0;
    let pos: i64 = 0;
    let cur: i64 = 0;
    let s: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let eq: i64 = 0;
    store8(out, 0);
    while 1 {
        pos = pkg_line_at(&PKG_LK, pos, &PKG_LN);
        if pos < 0 { break; }
        s = pkg_skip(&PKG_LN);
        ch = load8(&PKG_LN + s);
        if ch == 91 {
            cur = 0;
        }
        if ch != 91 {
            if ch != 35 {
                if ch != 0 {
                    eq = 0;
                    i = s;
                    while 1 {
                        ch = load8(&PKG_LN + i);
                        if ch == 0 { break; }
                        if ch == 61 { eq = i; break; }
                        i = i + 1;
                    }
                    if eq > s {
                        k = 0;
                        while k < eq - s {
                            store8(&PKG_B + k, load8(&PKG_LN + s + k));
                            k = k + 1;
                        }
                        store8(&PKG_B + k, 0);
                        k = strlen(&PKG_B) - 1;
                        while k >= 0 {
                            ch = load8(&PKG_B + k);
                            if ch != 32 { if ch != 9 { break; } }
                            store8(&PKG_B + k, 0);
                            k = k - 1;
                        }
                        if streq(&PKG_B, "name") == 1 {
                            pkg_quoted(&PKG_LN + s, &PKG_SEC);
                            cur = pkg_save_name(&PKG_SEC);
                        }
                        if cur != 0 {
                            if streq(cur, name) == 1 {
                                if streq(&PKG_B, key) == 1 {
                                    return pkg_quoted(&PKG_LN + s, out);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# 收集锁里所有包名的个数
fn pkg_lock_names(out: i64) -> i64 {
    let k: i64 = 0;
    let pos: i64 = 0;
    let s: i64 = 0;
    let i: i64 = 0;
    let ch: i64 = 0;
    let eq: i64 = 0;
    let n: i64 = 0;
    while 1 {
        pos = pkg_line_at(&PKG_LK, pos, &PKG_LN);
        if pos < 0 { break; }
        s = pkg_skip(&PKG_LN);
        ch = load8(&PKG_LN + s);
        if ch != 91 {
            if ch != 35 {
                if ch != 0 {
                    eq = 0;
                    i = s;
                    while 1 {
                        ch = load8(&PKG_LN + i);
                        if ch == 0 { break; }
                        if ch == 61 { eq = i; break; }
                        i = i + 1;
                    }
                    if eq > s {
                        k = 0;
                        while k < eq - s {
                            store8(&PKG_B + k, load8(&PKG_LN + s + k));
                            k = k + 1;
                        }
                        store8(&PKG_B + k, 0);
                        k = strlen(&PKG_B) - 1;
                        while k >= 0 {
                            ch = load8(&PKG_B + k);
                            if ch != 32 { if ch != 9 { break; } }
                            store8(&PKG_B + k, 0);
                            k = k - 1;
                        }
                        if streq(&PKG_B, "name") == 1 {
                            pkg_quoted(&PKG_LN + s, &PKG_SEC);
                            if n < 64 {
                                store64(out + n * 8, pkg_save_name(&PKG_SEC));
                                n = n + 1;
                            }
                        }
                    }
                }
            }
        }
    }
    return n;
}

# ---------------------------------------------------------------- git

# 执行 git 子命令，输出进 SH_OUT；返回退出码
fn pkg_git(a1: ptr, a2: ptr, a3: ptr, a4: ptr) -> i64 {
    SH_OUT = &PKG_OUT;
    store64(&PKG_CMD, "git");
    store64(&PKG_CMD + 8, a1);
    store64(&PKG_CMD + 16, a2);
    store64(&PKG_CMD + 24, a3);
    store64(&PKG_CMD + 32, a4);
    store64(&PKG_CMD + 40, 0);
    return sh_capture(&PKG_CMD);
}

fn pkg_git4(a1: ptr, a2: ptr, a3: ptr) -> i64 {
    return pkg_git(a1, a2, a3, 0);
}

# 取 dir 目录下 git rev-parse HEAD，结果到 out
fn pkg_head(dir: ptr, out: ptr) -> i64 {
    let rc: i64 = 0;
    store8(out, 0);
    sh_chdir(dir);
    rc = pkg_git4("rev-parse", "HEAD", 0);
    if rc != 0 { return 0 - 1; }
    strcpy(out, SH_OUT);
    # 去掉尾部换行
    let n: i64 = strlen(out);
    let ch: i64 = 0;
    while n > 0 {
        ch = load8(out + n - 1);
        if ch != 10 { if ch != 13 { break; } }
        store8(out + n - 1, 0);
        n = n - 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 闭包

fn pkg_in_closure(nm: ptr) -> i64 {
    let i: i64 = 0;
    while i < PKG_CN {
        if streq(load64(&PKG_CLO + i * 8), nm) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

# 递归收集依赖闭包（含间接依赖）—— shell 版踩过的坑就在这里
fn pkg_closure(nm: ptr) -> i64 {
    let i: i64 = 0;
    let n: i64 = 0;
    let saved: [64] i64 = 0;
    if pkg_in_closure(nm) == 1 { return 0; }
    if PKG_CN < 64 {
        PKG_CLO[PKG_CN] = pkg_save_name(nm);
        PKG_CN = PKG_CN + 1;
    }
    if PKG_DEPTH > 8 { return 0; }
    # 该包的 mo.toml
    strcpy(&PKG_P, &PKG_DEP);
    strcat(&PKG_P, "/");
    strcat(&PKG_P, nm);
    strcat(&PKG_P, "/mo.toml");
    if pkg_load_toml(&PKG_P) < 0 { return 0; }
    n = pkg_dep_names(&PKG_TXT);
    # 递归会重写全局 PKG_NAMES：内层 pkg_dep_names 把名字写回同一个数组，
    # 于是本层 i=1 读到的已是内层留下的名字。实测 app->{b,d}、b->{c1,c2} 时
    # 树里 d 被 c2 顶掉、c2 出现两次（而同一程序里 BFS 的 fetch 是对的）。
    # 名字由 pkg_save_name dup 出去、递归不释放，所以存指针副本即可。
    i = 0;
    while i < n {
        saved[i] = PKG_NAMES[i];
        i = i + 1;
    }
    PKG_DEPTH = PKG_DEPTH + 1;
    i = 0;
    while i < n {
        pkg_closure(saved[i]);
        i = i + 1;
    }
    PKG_DEPTH = PKG_DEPTH - 1;
    return 0;
}

# ---------------------------------------------------------------- 命令

var LST_CACHE: [256] byte = 0;

var LST_HTML: i64 = 0;

fn pkg_cmd_list() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    if argc() > 2 {
        if streq(pkg_arg2(), "--html") == 1 { LST_HTML = 1; }
    }
    if LST_HTML == 1 {
        print("<html><head><title>mo list</title></head><body><h1>dependencies</h1><ul>\n");
    }
    if pkg_load_toml(&PKG_TOML) < 0 {
        print("✗ 没有 mo.toml\n");
        return 1;
    }
    n = pkg_dep_names(&PKG_TXT);
    if n == 0 { print("（无依赖）\n"); return 0; }
    i = 0;
    while i < n {
        if LST_HTML == 1 {
            print("<li>");
        } else {
            print("  ");
        }
        print(PKG_NAMES[i]);
        pkg_dep_field(&PKG_TXT, PKG_NAMES[i], "git", &PKG_A);
        if strlen(&PKG_A) > 0 {
            print("  git=");
            print(&PKG_A);
        }
        pkg_dep_field(&PKG_TXT, PKG_NAMES[i], "version", &PKG_A);
        if strlen(&PKG_A) > 0 {
            print("  version=");
            print(&PKG_A);
        }
        pkg_dep_field(&PKG_TXT, PKG_NAMES[i], "file", &PKG_A);
        if strlen(&PKG_A) > 0 {
            print("  file=");
            print(&PKG_A);
        }
        # v1.269:缓存状态
        strcpy(&LST_CACHE, "/tmp/mopkg_cache/");
        strcat(&LST_CACHE, PKG_NAMES[i]);
        strcat(&LST_CACHE, ".tgz");
        let lfd: i64 = fopen(&LST_CACHE, 0, 0);
        if lfd >= 0 {
            fclose(lfd);
            print("  [cached]");
        }
        if LST_HTML == 1 {
            print("</li>");
        }
        print_nl();
        i = i + 1;
    }
    if LST_HTML == 1 {
        print("</ul></body></html>\n");
        LST_HTML = 0;
    }
    return 0;
}

# 依赖树（含循环检测）
var TR_HTML: i64 = 0;

fn pkg_tree_visit(nm: ptr, depth: i64) -> i64 {
    let i: i64 = 0;
    let d: i64 = 0;
    let n: i64 = 0;
    let saved: [64] i64 = 0;
    while d < depth {
        if TR_HTML == 0 {
            print("  ");
        }
        d = d + 1;
    }
    if TR_HTML == 0 {
        print(nm);
        pkg_dep_field(&PKG_TXT, nm, "version", &PKG_A);
        if strlen(&PKG_A) > 0 {
            print(" @ ");
            print(&PKG_A);
        }
        print_nl();
    } else {
        print("<li>");
        print(nm);
        pkg_dep_field(&PKG_TXT, nm, "version", &PKG_A);
        if strlen(&PKG_A) > 0 {
            print(" @ ");
            print(&PKG_A);
        }
        print("<ul>\n");
    }
    if depth > 8 {
        print("✗ 循环依赖（深度超过 8）: ");
        print(nm);
        print_nl();
        PKG_BAD = 1;
        return 0;
    }
    strcpy(&PKG_P, &PKG_DEP);
    strcat(&PKG_P, "/");
    strcat(&PKG_P, nm);
    strcat(&PKG_P, "/mo.toml");
    if pkg_load_toml(&PKG_P) < 0 { return 0; }
    n = pkg_dep_names(&PKG_TXT);
    i = 0;
    while i < n {
        saved[i] = PKG_NAMES[i];
        i = i + 1;
    }
    PKG_DEPTH = PKG_DEPTH + 1;
    i = 0;
    while i < n {
        pkg_tree_visit(saved[i], depth + 1);
        i = i + 1;
    }
    PKG_DEPTH = PKG_DEPTH - 1;
    if TR_HTML == 1 {
        print("</ul></li>\n");
    }
    return 0;
}

fn pkg_cmd_tree() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let saved: [64] i64 = 0;
    PKG_BAD = 0;
    if argc() > 2 {
        if streq(pkg_arg2(), "--html") == 1 { TR_HTML = 1; }
    }
    if pkg_load_toml(&PKG_TOML) < 0 {
        print("✗ 没有 mo.toml\n");
        return 1;
    }
    if TR_HTML == 1 {
        print("<html><head><title>mo tree</title></head><body><h1>mo dependencies</h1><ul>\n");
    }
    pkg_dep_field(&PKG_TXT, "name", "name", &PKG_A);
    n = pkg_dep_names(&PKG_TXT);
    i = 0;
    while i < n {
        saved[i] = PKG_NAMES[i];
        i = i + 1;
    }
    i = 0;
    while i < n {
        pkg_tree_visit(saved[i], 1);
        i = i + 1;
    }
    if TR_HTML == 1 {
        print("</ul></body></html>\n");
        TR_HTML = 0;
    }
    if PKG_BAD == 1 { return 1; }
    return 0;
}

# verify：完整 / 版本满足 / 可复现 / 无多余包 / 无循环
var VR_HTML: i64 = 0;

fn pkg_cmd_verify() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    let bad: i64 = 0;
    let nl: i64 = 0;
    let saved: [64] i64 = 0;
    PKG_BAD = 0;
    if argc() > 2 {
        if streq(pkg_arg2(), "--html") == 1 { VR_HTML = 1; }
    }
    if VR_HTML == 1 {
        print("<html><head><title>mo verify</title></head><body><h1>verify</h1><pre>\n");
    }
    if pkg_load_toml(&PKG_TOML) < 0 {
        print("✗ 没有 mo.toml\n");
        return 1;
    }
    n = pkg_dep_names(&PKG_TXT);
    i = 0;
    while i < n {
        saved[i] = PKG_NAMES[i];
        i = i + 1;
    }
    if pkg_load_lock() < 0 {
        print("✗ 没有 mo.lock\n");
        return 1;
    }
    i = 0;
    while i < n {
        # 1) 版本约束
        pkg_dep_field(&PKG_TXT, saved[i], "version", &PKG_A);
        pkg_lock_field(saved[i], "version", &PKG_B);
        if strlen(&PKG_A) > 0 {
            if strlen(&PKG_B) == 0 {
                print("✗ ");
                print(saved[i]);
                print(": mo.lock 里没有版本记录\n");
                bad = 1;
            }
            if strlen(&PKG_B) > 0 {
                if pkg_ver_match(&PKG_B, &PKG_A) == 0 {
                    print("✗ ");
                    print(saved[i]);
                    print(": 版本 ");
                    print(&PKG_B);
                    print(" 不满足约束 ");
                    print(&PKG_A);
                    print_nl();
                    bad = 1;
                }
            }
        }
        # 2) commit 可复现（path=/file= 本地包无 commit，跳过）
        pkg_lock_field(saved[i], "path", &PKG_B);
        pkg_lock_field(saved[i], "file", &PKG_VAL);
        if strlen(&PKG_B) == 0 {
            if strlen(&PKG_VAL) == 0 {
                pkg_lock_field(saved[i], "commit", &PKG_B);
                if strlen(&PKG_B) == 0 {
                    print("✗ ");
                    print(saved[i]);
                    print(": mo.lock 里没有 commit\n");
                    bad = 1;
                }
            }
        }
        i = i + 1;
    }
    # 3) 锁里不应有多余包 —— 必须比"依赖闭包"而不是直接依赖
    PKG_CN = 0;
    PKG_DEPTH = 0;
    i = 0;
    while i < n {
        pkg_closure(saved[i]);
        i = i + 1;
    }
    nl = pkg_lock_names(&PKG_C);
    j = 0;
    while j < nl {
        if pkg_in_closure(load64(&PKG_C + j * 8)) == 0 {
            print("✗ mo.lock 里有不属于依赖闭包的多余包: ");
            print(load64(&PKG_C + j * 8));
            print_nl();
            bad = 1;
        }
        j = j + 1;
    }
    # 4) 循环依赖
    if pkg_load_toml(&PKG_TOML) < 0 { return 1; }
    n = pkg_dep_names(&PKG_TXT);
    i = 0;
    while i < n {
        saved[i] = PKG_NAMES[i];
        i = i + 1;
    }
    i = 0;
    while i < n {
        pkg_tree_visit(saved[i], 1);
        i = i + 1;
    }
    if PKG_BAD == 1 {
        print("✗ 存在循环依赖\n");
        bad = 1;
    }
    if bad == 0 {
        print("✓ verify: 依赖完整、版本满足约束\n");
        # v1.258：远端 sha 复核——对每个 http 依赖重新下载,sha256 对比 lock
        let vi: i64 = 0;
        let vbad: i64 = 0;
        let vchk: i64 = 0;
        while vi < n {
            strcpy(&VF_NAME, saved[vi]);
            pkg_lock_field(&VF_NAME, "file", &VF_PATH);
            pkg_lock_field(&VF_NAME, "sha256", &VF_LSHA);
            if strlen(&VF_PATH) > 0 && strlen(&VF_LSHA) > 0 {
                # 提取文件名
                strcpy(&VF_FN, &VF_PATH);
                let vs: i64 = strlen(&VF_FN) - 1;
                while vs >= 0 {
                    if load8(VF_FN + vs) == 47 {   # '/'
                        strcpy(&VF_FN, &VF_FN + vs + 1);
                        vs = 0 - 99;
                    }
                    vs = vs - 1;
                }
                strcpy(&VF_TMP, "/tmp/mopkg_verify_");
                strcat(&VF_TMP, &VF_FN);
                let vrc: i64 = pkg_http_get(&VF_PATH, &VF_TMP);
                if vrc != 0 {
                    print("✗ sha 复核下载失败: ");
                    print(&VF_NAME);
                    print_nl();
                    vbad = 1;
                } else {
                    let fdv: i64 = fopen(&VF_TMP, 0, 0);
                    if fdv < 0 {
                        vbad = 1;
                    } else {
                        let rv: i64 = fread(fdv, &VF_BUF, 65000);
                        fclose(fdv);
                        if rv > 0 {
                            sha256_hex(&VF_BUF, rv, &VF_SHA);
                            if strstr(&VF_LSHA, &VF_SHA) < 0 {
                                print("✗ sha 复核不符: ");
                                print(&VF_NAME);
                                print(" lock=");
                                print(&VF_LSHA);
                                print(" remote=");
                                print(&VF_SHA);
                                print_nl();
                                vbad = 1;
                            } else {
                                vchk = vchk + 1;
                            }
                        }
                    }
                    syscall(87, &VF_TMP, 0, 0, 0, 0);
                }
            }
            vi = vi + 1;
        }
        if vchk > 0 {
            print("✓ sha 复核: ");
            print_i64(vchk);
            print(" 个远端包比对通过\n");
        }
        if vbad == 1 {
            if VR_HTML == 1 { print("</pre></body></html>\n"); VR_HTML = 0; }
            return 1;
        }
        if VR_HTML == 1 { print("</pre></body></html>\n"); VR_HTML = 0; }
        return 0;
    }
    if VR_HTML == 1 { print("</pre></body></html>\n"); VR_HTML = 0; }
    return 1;
}

# ---------------------------------------------------------------- fetch

fn pkg_install(nm: ptr, url: ptr, ref: ptr, want: ptr, path: ptr, fil: ptr) -> i64 {
    let rc: i64 = 0;
    strcpy(&PKG_P, &PKG_DEP);
    strcat(&PKG_P, "/");
    strcat(&PKG_P, nm);
    # file= .mo.tar.gz 依赖：复制 -> gunzip -> tar_unpack 到 .deps/<name>
    # http:// 开头 = 网络依赖：先 HTTP GET 下载到本地，再走 file= 路径
    if strlen(fil) > 0 {
        if strstr(fil, "http://") == 0 {
            let dl: i64 = pkg_http_dep(fil, nm);
            if dl == 0 { return 0 - 1; }
            fil = dl;
        }
        SH_OUT = &PKG_OUT;
        store64(&PKG_CMD, "mkdir");
        store64(&PKG_CMD + 8, "-p");
        store64(&PKG_CMD + 16, &PKG_P);
        store64(&PKG_CMD + 24, 0);
        sh_run(&PKG_CMD);
        strcpy(&QBUF2, &PKG_P);
        strcat(&QBUF2, ".tgz");
        store64(&PKG_CMD, "cp");
        store64(&PKG_CMD + 8, fil);
        store64(&PKG_CMD + 16, &QBUF2);
        store64(&PKG_CMD + 24, 0);
        rc = sh_run(&PKG_CMD);
        if rc != 0 {
            print("✗ 复制失败: ");
            print(fil);
            print_nl();
            return 0 - 1;
        }
        # tar 中间文件放 .deps/ 下；chdir 后相对路径失效，先转绝对
        strcpy(&QBUF, &PKG_DEP);
        strcat(&QBUF, "/");
        strcat(&QBUF, nm);
        strcat(&QBUF, ".tar");
        strcpy(&PKG_VAL, &QBUF);
        pkg_abspath(&PKG_VAL, &QBUF);
        if gunzip_file(&QBUF2, &QBUF) != 0 {
            print("✗ gunzip 失败: ");
            print(fil);
            print_nl();
            return 0 - 1;
        }
        sh_chdir(&PKG_P);
        rc = tar_unpack(&QBUF);
        sh_chdir("..");
        sh_chdir("..");
        syscall(87, &QBUF, 0, 0, 0, 0, 0);   # 清理中间 tar
        if rc < 0 {
            print("✗ tar 解包失败: ");
            print(fil);
            print_nl();
            return 0 - 1;
        }
        print("✓ 已安装 tar 包 ");
        print(nm);
        print_nl();
        return 0;
    }
    # path= 本地目录依赖：直接整目录拷贝进 .deps/<name>（不进 git）
    if strlen(path) > 0 {
        SH_OUT = &PKG_OUT;
        store64(&PKG_CMD, "mkdir");
        store64(&PKG_CMD + 8, "-p");
        store64(&PKG_CMD + 16, &PKG_DEP);
        store64(&PKG_CMD + 24, 0);
        sh_run(&PKG_CMD);
        print("复制本地包 ");
        print(nm);
        print(" <- ");
        print(path);
        print_nl();
        SH_OUT = &PKG_OUT;
        store64(&PKG_CMD, "cp");
        store64(&PKG_CMD + 8, "-r");
        store64(&PKG_CMD + 16, path);
        store64(&PKG_CMD + 24, &PKG_P);
        store64(&PKG_CMD + 32, 0);
        rc = sh_run(&PKG_CMD);
        if rc != 0 {
            print("✗ 复制失败: ");
            print(nm);
            print_nl();
            return 0 - 1;
        }
        return 0;
    }
    print("克隆 ");
    print(nm);
    print_nl();
    SH_OUT = &PKG_OUT;
    store64(&PKG_CMD, "git");
    store64(&PKG_CMD + 8, "clone");
    store64(&PKG_CMD + 16, url);
    store64(&PKG_CMD + 24, &PKG_P);
    store64(&PKG_CMD + 32, 0);
    rc = sh_run(&PKG_CMD);
    if rc != 0 {
        print("✗ 克隆失败: ");
        print(nm);
        print_nl();
        return 0 - 1;
    }
    # 检出指定 ref —— 不检出的话拿到的是默认分支当前头，
    # 锁文件记的 commit 就和实际内容对不上，"可复现"是假的。
    if strlen(ref) > 0 {
        store64(&PKG_CMD, "git");
        store64(&PKG_CMD + 8, "-C");
        store64(&PKG_CMD + 16, &PKG_P);
        store64(&PKG_CMD + 24, "checkout");
        store64(&PKG_CMD + 32, ref);
        store64(&PKG_CMD + 40, 0);
        rc = sh_run(&PKG_CMD);
        if rc != 0 {
            print("✗ 检出失败: ");
            print(nm);
            print(" @ ");
            print(ref);
            print_nl();
            return 0 - 1;
        }
    }
    return 0;
}

# 取 [package] 段里的 key（name / version）到 out
fn pkg_pkg_field(txt: ptr, key: ptr, out: ptr) -> i64 {
    let pos: i64 = 0;
    let s: i64 = 0;
    let i: i64 = 0;
    let k: i64 = 0;
    let ch: i64 = 0;
    let eq: i64 = 0;
    let insec: i64 = 0;
    let v: i64 = 0;
    let st: i64 = 0;
    store8(out, 0);
    while 1 {
        pos = pkg_line_at(txt, pos, &PKG_LN);
        if pos < 0 { break; }
        s = pkg_skip(&PKG_LN);
        ch = load8(&PKG_LN + s);
        if ch == 91 {
            strcpy(&PKG_SEC, &PKG_LN + s + 1);
            i = 0;
            while 1 {
                ch = load8(&PKG_SEC + i);
                if ch == 0 { break; }
                if ch == 93 { store8(&PKG_SEC + i, 0); break; }
                i = i + 1;
            }
            if streq(&PKG_SEC, "package") == 1 { insec = 1; }
            else { insec = 0; }
        } else {
            if insec == 1 {
                if ch != 35 {
                    if ch != 0 {
                        eq = 0;
                        i = s;
                        while 1 {
                            ch = load8(&PKG_LN + i);
                            if ch == 0 { break; }
                            if ch == 61 { eq = i; break; }
                            i = i + 1;
                        }
                        if eq > s {
                            k = 0;
                            while k < eq - s {
                                store8(&PKG_VAL + k, load8(&PKG_LN + s + k));
                                k = k + 1;
                            }
                            store8(&PKG_VAL + k, 0);
                            k = strlen(&PKG_VAL) - 1;
                            while k >= 0 {
                                ch = load8(&PKG_VAL + k);
                                if ch != 32 { if ch != 9 { break; } }
                                store8(&PKG_VAL + k, 0);
                                k = k - 1;
                            }
                            if streq(&PKG_VAL, key) == 1 {
                                # pkg_skip 返回的是**相对传入指针的下标**，
                                # 不是地址。漏加基址 eq+1 会让 v 变成行内
                                # 偏移 1，取出的值形如 `ersion = "2.1.0"`。
                                v = eq + 1 + pkg_skip(&PKG_LN + eq + 1);
                                if load8(&PKG_LN + v) == 34 {
                                    st = v + 1;
                                    k = 0;
                                    while 1 {
                                        ch = load8(&PKG_LN + st + k);
                                        if ch == 0 { break; }
                                        if ch == 34 { break; }
                                        store8(out + k, ch);
                                        k = k + 1;
                                    }
                                    store8(out + k, 0);
                                    return 1;
                                }
                                strcpy(out, &PKG_LN + v);
                                k = strlen(out) - 1;
                                while k >= 0 {
                                    ch = load8(out + k);
                                    if ch != 32 { if ch != 9 { break; } }
                                    store8(out + k, 0);
                                    k = k - 1;
                                }
                                return 1;
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# 取目录下 git rev-parse HEAD。用 git -C 而不是 chdir ——
# pkg_head 内部会 sh_chdir 改动工作目录，调用方很难察觉。
fn pkg_commit(dir: ptr, out: ptr) -> i64 {
    let rc: i64 = 0;
    let n: i64 = 0;
    let ch: i64 = 0;
    store8(out, 0);
    SH_OUT = &PKG_OUT;
    store64(&PKG_CMD, "git");
    store64(&PKG_CMD + 8, "-C");
    store64(&PKG_CMD + 16, dir);
    store64(&PKG_CMD + 24, "rev-parse");
    store64(&PKG_CMD + 32, "HEAD");
    store64(&PKG_CMD + 40, 0);
    rc = sh_capture(&PKG_CMD);
    if rc != 0 { return 0 - 1; }
    strcpy(out, SH_OUT);
    n = strlen(out);
    while n > 0 {
        ch = load8(out + n - 1);
        if ch != 10 { if ch != 13 { break; } }
        store8(out + n - 1, 0);
        n = n - 1;
    }
    return 0;
}

fn pkg_have(nm: ptr) -> i64 {
    strcpy(&QBUF2, &PKG_DEP);
    strcat(&QBUF2, "/");
    strcat(&QBUF2, nm);
    strcat(&QBUF2, "/mo.toml");
    if pkg_load_toml(&QBUF2) < 0 { return 0; }
    return 1;
}

fn pkg_write_lock() -> i64 {
    let fd: i64 = fopen(&PKG_LOCK, 577, 420);
    let i: i64 = 0;
    if fd < 0 {
        print("✗ 无法写 mo.lock\n");
        return 0 - 1;
    }
    i = 0;
    while i < QN_N {
        strcpy(&QBUF2, &PKG_DEP);
        strcat(&QBUF2, "/");
        strcat(&QBUF2, QN[i]);
        strcat(&QBUF2, "/mo.toml");
        store8(&QVER, 0);
        if pkg_load_toml(&QBUF2) >= 0 {
            pkg_pkg_field(&PKG_TXT, "version", &QVER);
        }
        strcpy(&QBUF, &PKG_DEP);
        strcat(&QBUF, "/");
        strcat(&QBUF, QN[i]);
        store8(&QCM, 0);
        pkg_commit(&QBUF, &QCM);
        strcpy(&QBUF, "[[package]]\nname = \"");
        strcat(&QBUF, QN[i]);
        strcat(&QBUF, "\"\nversion = \"");
        strcat(&QBUF, &QVER);
        strcat(&QBUF, "\"\ngit = \"");
        strcat(&QBUF, QU[i]);
        if QF[i] > 0 {
            strcat(&QBUF, "\"\nfile = \"");
            strcat(&QBUF, QF[i]);
        }
        if strlen(QP[i]) > 0 {
            strcat(&QBUF, "\"\npath = \"");
            strcat(&QBUF, QP[i]);
        }
        strcat(&QBUF, "\"\nref = \"");
        strcat(&QBUF, QR[i]);
        strcat(&QBUF, "\"\ncommit = \"");
        strcat(&QBUF, &QCM);
        if QF[i] > 0 && QSH[i] > 0 {
            strcat(&QBUF, "\"\nsha256 = \"");
            strcat(&QBUF, QSH[i]);
        }
        strcat(&QBUF, "\"\n\n");
        fwrite(fd, &QBUF, strlen(&QBUF));
        i = i + 1;
    }
    fclose(fd);
    return 0;
}

fn pkg_cmd_fetch() -> i64 {
    let i: i64 = 0;
    let nm: i64 = 0;
    QN_N = 0;
    QPI = 0;
    if pkg_load_toml(&PKG_TOML) < 0 {
        print("✗ 没有 mo.toml\n");
        return 1;
    }
    pkg_queue_toml(&PKG_TOML);
    if QN_N == 0 {
        print("（无依赖）\n");
        return 0;
    }
    i = 0;
    while i < QN_N {
        nm = QN[i];
        # v1.264:逐包进度 [i+1] name
        print("[");
        print_i64(i + 1);
        print("/");
        print_i64(QN_N);
        print("] ");
        print(nm);
        print("\n");
        if pkg_have(nm) == 0 {
            if pkg_install(nm, QU[i], QR[i], QV[i], QP[i], QF[i]) < 0 { return 1; }
        }
        # 装好后再扫它自己的 mo.toml；新发现的名字追加到队列尾，
        # 循环条件 i < QN_N 会自然把它们也走一遍 —— 这就是递归。
        strcpy(&QBUF2, &PKG_DEP);
        strcat(&QBUF2, "/");
        strcat(&QBUF2, nm);
        strcat(&QBUF2, "/mo.toml");
        pkg_queue_toml(&QBUF2);
        i = i + 1;
    }
    pkg_write_lock();
    print("✓ 已处理 ");
    print_i64(QN_N);
    print(" 个包（含间接依赖），锁已写入 mo.lock\n");
    return 0;
}

# ---------------------------------------------------------------- 队列

fn qsave(s: ptr) -> i64 {
    let n: i64 = strlen(s);
    let d: i64 = 0;
    if QPI + n + 1 >= 16384 { return 0; }
    d = &QPOOL + QPI;
    strcpy(d, s);
    QPI = QPI + n + 1;
    return d;
}

fn pkg_queue_find(nm: ptr) -> i64 {
    let i: i64 = 0;
    while i < QN_N {
        if streq(QN[i], nm) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn pkg_queue_add(nm: ptr, url: ptr, ref: ptr, ver: ptr, path: ptr, fil: ptr) -> i64 {
    if QN_N >= 64 { return 0 - 1; }
    QN[QN_N] = qsave(nm);
    QU[QN_N] = qsave(url);
    QR[QN_N] = qsave(ref);
    QV[QN_N] = qsave(ver);
    QP[QN_N] = qsave(path);
    QF[QN_N] = qsave(fil);
    QN_N = QN_N + 1;
    return QN_N - 1;
}

# 把某个 mo.toml 里的依赖登记进队列（已登记过的跳过）
fn pkg_queue_toml(path: ptr) -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let nm: i64 = 0;
    if pkg_load_toml(path) < 0 { return 0; }
    n = pkg_dep_names(&PKG_TXT);
    i = 0;
    while i < n {
        nm = qsave(PKG_NAMES[i]);
        if pkg_queue_find(nm) < 0 {
            pkg_dep_field(&PKG_TXT, nm, "git", &PKG_A);
            pkg_dep_field(&PKG_TXT, nm, "ref", &PKG_B);
            pkg_dep_field(&PKG_TXT, nm, "version", &PKG_C);
            pkg_dep_field(&PKG_TXT, nm, "path", &PKG_D);
            pkg_dep_field(&PKG_TXT, nm, "file", &PKG_E);
            pkg_queue_add(nm, &PKG_A, &PKG_B, &PKG_C, &PKG_D, &PKG_E);
        }
        i = i + 1;
    }
    return n;
}

# ---------------------------------------------------------------- 入口

# argv(2)：remove/update 的包名参数（缺省空串）
var PKG_ARG2: [256] byte = 0;
fn pkg_arg2() -> i64 {
    store8(&PKG_ARG2, 0);
    if argc() < 3 { return &PKG_ARG2; }
    strcpy(&PKG_ARG2, argv(2));
    return &PKG_ARG2;
}

# remove <name>：删除 .deps/<name> 并从 mo.lock 移除对应段
fn pkg_cmd_remove(nm: ptr) -> i64 {
    if strlen(nm) == 0 {
        print("✗ remove 需要包名\n");
        return 1;
    }
    SH_OUT = &PKG_OUT;
    strcpy(&PKG_P, &PKG_DEP);
    strcat(&PKG_P, "/");
    strcat(&PKG_P, nm);
    store64(&PKG_CMD, "rm");
    store64(&PKG_CMD + 8, "-rf");
    store64(&PKG_CMD + 16, &PKG_P);
    store64(&PKG_CMD + 24, 0);
    sh_run(&PKG_CMD);
    # 重写 mo.lock：过滤掉该包的 [[package]] 段
    if pkg_load_lock() >= 0 {
        let fd: i64 = fopen(&PKG_LOCK, 577, 420);
        if fd < 0 {
            print("✗ 无法写 mo.lock\n");
            return 0 - 1;
        }
        let skip: i64 = 0;
        let pos: i64 = 0;
        let seg: i64 = 0;
        while 1 {
            pos = pkg_line_at(&PKG_LK, pos, &PKG_LN);
            if pos < 0 { break; }
            if str_starts_with(&PKG_LN, "[[package]]") == 1 {
                # 新段开始：先把上一段（未标记删除的）落盘
                if skip == 0 {
                    if seg == 1 {
                        fwrite(fd, &QBUF, strlen(&QBUF));
                    }
                }
                seg = 1;
                skip = 0;
                strcpy(&QBUF, &PKG_LN);
                strcat(&QBUF, "\n");
                # 继续缓冲本段直到下一个段头
                continue;
            }
            if seg == 1 {
                strcat(&QBUF, &PKG_LN);
                strcat(&QBUF, "\n");
                if str_starts_with(&PKG_LN, "name = ") == 1 {
                    if strstr(&PKG_LN, nm) > 0 {
                        skip = 1;
                    }
                }
                continue;
            }
            # 段外内容原样写
            fwrite(fd, &PKG_LN, strlen(&PKG_LN));
            fwrite(fd, "\n", 1);
        }
        # 最后一段
        if seg == 1 {
            if skip == 0 {
                fwrite(fd, &QBUF, strlen(&QBUF));
            }
        }
        fclose(fd);
    }
    print("✓ 已移除 ");
    print(nm);
    print_nl();
    return 0;
}

# update <name>：删掉该包再重新 fetch（拿新 commit）
fn pkg_cmd_update(nm: ptr) -> i64 {
    if strlen(nm) == 0 {
        print("✗ update 需要包名\n");
        return 1;
    }
    if pkg_cmd_remove(nm) != 0 { return 1; }
    return pkg_cmd_fetch();
}

# ---------- pack / file= tarball 依赖（v1.193.0）----------
var PKG_FL: [256] i64 = 0;      # 文件路径指针数组（PBUF 池）
var PKG_FN: i64 = 0;
var PKG_PBUF: [16384] byte = 0;
var PKG_PBI: i64 = 0;
var PKG_ROOT: [512] byte = 0;   # 打包根目录（拼相对路径用）

fn pbuf_save(s: ptr) -> i64 {
    let n: i64 = strlen(s);
    if PKG_PBI + n + 1 >= 16384 { return 0; }
    let d: i64 = &PKG_PBUF + PKG_PBI;
    strcpy(d, s);
    PKG_PBI = PKG_PBI + n + 1;
    return d;
}

# 递归收集 root 下的所有文件（相对 root 的路径存 PKG_FL）
fn pkg_walk(dir: ptr, rel: ptr) -> i64 {
    let sub: [64] i64 = 0;
    let n: i64 = list_dir(dir, &sub, 60);
    if n < 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        # 全路径 = dir/name
        strcpy(&PKG_P, dir);
        strcat(&PKG_P, "/");
        strcat(&PKG_P, sub[i]);
        # 相对路径 = rel/name（顶层 rel 为空串）
        strcpy(&PKG_VAL, rel);
        if strlen(rel) > 0 { strcat(&PKG_VAL, "/"); }
        strcat(&PKG_VAL, sub[i]);
        # 是目录还是文件？读 mo.toml 探测法太怪——用 syscall stat 太重；
        # list_dir 子路径成功 = 目录（否则返回 -1）
        strcpy(&QBUF2, &PKG_P);
        strcat(&QBUF2, "/mo.toml");
        if list_dir(&PKG_P, &sub, 0) >= 0 {
            # 目录：递归（注意 sub 会被内层覆盖，先保存当前名）
            strcpy(&QBUF, sub[i]);
            pkg_walk(&PKG_P, &PKG_VAL);
        } else {
            if PKG_FN < 256 {
                PKG_FL[PKG_FN] = pbuf_save(&PKG_VAL);
                PKG_FN = PKG_FN + 1;
            }
        }
        i = i + 1;
    }
    return PKG_FN;
}

# 把 path 转绝对路径（非 / 开头则前缀 cwd）
fn pkg_abspath(p: ptr, out: ptr) -> i64 {
    if load8(p) == 47 {
        strcpy(out, p);
        return 0;
    }
    let n: i64 = syscall(79, out, 1024, 0, 0, 0, 0);   # getcwd
    strcat(out, "/");
    strcat(out, p);
    return 0;
}

# v1.305:.moignore 支持（每行一个模式，精确或 * 前缀匹配）
var PKG_IGN: [1024] byte = 0;
var PKG_IGN_N: i64 = 0;

fn pkg_ignored(name: ptr) -> i64 {
    if PKG_IGN_N <= 0 { return 0; }
    let line: i64 = &PKG_IGN;
    let end: i64 = &PKG_IGN + PKG_IGN_N;
    while line < end {
        let nl: i64 = strstr(line, "\n");
        if nl < 0 { nl = end - line; }
        if nl > 0 {
            store8(line + nl, 0);
            # 通配：模式以 * 结尾则前缀匹配
            let patlen: i64 = strlen(line);
            if patlen > 0 {
                if load8(line) == 42 && load8(line + patlen - 1) == 42 {
                    # 首尾都是 *：包含匹配
                    if strstr(name, line + 1) >= 0 { store8(line + nl, 10); return 1; }
                } else if load8(line + patlen - 1) == 42 {
                    # 尾部 *：前缀匹配（比较去掉 * 后的头部）
                    if strstr(name, line) == 0 { store8(line + nl, 10); return 1; }
                } else if load8(line) == 42 {
                    # 首部 *：后缀匹配（name 尾部 == line+1）
                    let tail: i64 = line + 1;
                    let nl2: i64 = strlen(name);
                    let tl: i64 = strlen(tail);
                    if nl2 >= tl && streq(name + nl2 - tl, tail) == 1 { store8(line + nl, 10); return 1; }
                } else {
                    if streq(name, line) == 1 { store8(line + nl, 10); return 1; }
                }
            }
            store8(line + nl, 10);
        }
        line = line + nl + 1;
    }
    return 0;
}

# walk 收集相对名（调用方需已 chdir(dir)），返回个数
fn pkg_walk_rel(names: i64, maxn: i64) -> i64 {
    let sub: [64] i64 = 0;
    let n: i64 = list_dir(".", &sub, 60);
    if n < 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        # v1.303:跳过目录、中间 tar、输出 tar.gz(tar_pack 只收普通文件)
        # v1.305:.moignore 命中跳过
        if is_dir(sub[i]) == 0 && strstr(sub[i], ".tmp.tar") < 0 && strstr(sub[i], ".tar.gz") < 0 && pkg_ignored(sub[i]) == 0 {
            if PKG_FN < maxn {
                PKG_FL[PKG_FN] = pbuf_save(sub[i]);
                PKG_FN = PKG_FN + 1;
            }
        }
        i = i + 1;
    }
    return PKG_FN;
}

# pack <dir> <out.mo.tar.gz>：目录（含顶层文件）打成 tar.gz。
# 实现走 chdir(dir) + 收相对名 + tar_pack(绝对 out) + gunzip 逆操作由用户侧处理：
# tar_pack 直接产出 .tar，再 gzip_file 得 .tar.gz。
fn pkg_cmd_pack(dir: ptr, outg: ptr) -> i64 {
    if strlen(dir) == 0 {
        print("✗ pack 需要 <dir> <out.mo.tar.gz>\n");
        return 1;
    }
    # out 转绝对（chdir 后仍有效）
    pkg_abspath(outg, &PKG_ROOT);
    # tar 中间文件也放绝对路径
    strcpy(&PKG_VAL, &PKG_ROOT);
    strcat(&PKG_VAL, ".tmp.tar");
    if sh_chdir(dir) != 0 {
        print("✗ pack: 无法进入目录 ");
        print(dir);
        print_nl();
        return 1;
    }
    PKG_FN = 0;
    PKG_PBI = 0;
    # v1.305:读 .moignore（若无则 PKG_IGN_N=0）
    PKG_IGN_N = 0;
    let igh: i64 = fopen(".moignore", 0, 0);
    if igh >= 0 {
        PKG_IGN_N = fread(igh, &PKG_IGN, 1023);
        fclose(igh);
    }
    pkg_walk_rel(&PKG_FL, 256);
    # v1.303:pack <dir> <out> --list 只列文件不打
    if argc() > 4 {
        if streq(pkg_arg4(), "--list") == 1 {
            let li: i64 = 0;
            while li < PKG_FN {
                print("  ");
                print(PKG_FL[li]);
                print_nl();
                li = li + 1;
            }
            print("共 ");
            print_i64(PKG_FN);
            print(" 个文件\n");
            sh_chdir("..");
            return 0;
        }
    }
    let rc: i64 = tar_pack(&PKG_VAL, &PKG_FL, PKG_FN);
    sh_chdir("..");
    if rc != 0 {
        print("✗ pack: tar 失败\n");
        return 1;
    }
    rc = gzip_file(&PKG_VAL, &PKG_ROOT);
    syscall(87, &PKG_VAL, 0, 0, 0, 0, 0);   # unlink 中间 tar
    if rc != 0 {
        print("✗ pack: gzip 失败\n");
        return 1;
    }
    print("✓ 已打包 ");
    print_i64(PKG_FN);
    print(" 个文件 -> ");
    print(&PKG_ROOT);
    print_nl();
    let li: i64 = 0;
    while li < PKG_FN {
        print("  ");
        print(PKG_FL[li]);
        print_nl();
        li = li + 1;
    }
    return 0;
}

var PKG_ARG3: [256] byte = 0;
fn pkg_arg3() -> i64 {
    store8(&PKG_ARG3, 0);
    if argc() < 4 { return &PKG_ARG3; }
    strcpy(&PKG_ARG3, argv(3));
    return &PKG_ARG3;
}



# ---------------------------------------------------------------- registry
var PKG_CHR: [2] byte = 0;
var PKG_REG: [512] byte = 0;
var PKG_IDX: [8192] byte = 0;
var PKG_NEW: [8192] byte = 0;

# 简版 getenv：读 /proc/self/environ（freestanding 无 libc environ）
var PENV: [8192] byte = 0;

fn pkg_getenv(nm: ptr) -> i64 {
    let fd: i64 = fopen("/proc/self/environ", 0, 0);
    if fd < 0 { return 0; }
    let n: i64 = 0;
    let r: i64 = 0;
    let tries: i64 = 0;
    while n < 8191 && tries < 32 {
        tries = tries + 1;
        r = syscall(0, fd, &PENV + n, 1024, 0, 0, 0);
        if r <= 0 { break; }
        n = n + r;
    }
    fclose(fd);
    store8(&PENV + n, 0);
    if n == 0 { return 0; }
    let nm_len: i64 = strlen(nm);
    let p: i64 = 0;
    while p < n {
        if p == 0 || load8(&PENV + p - 1) == 0 {
            let ok: i64 = 1;
            let k: i64 = 0;
            while k < nm_len {
                if load8(&PENV + p + k) != load8(nm + k) { ok = 0; }
                k = k + 1;
            }
            if ok == 1 && load8(&PENV + p + nm_len) == 61 {
                return &PENV + p + nm_len + 1;
            }
        }
        p = p + 1;
    }
    return 0;
}

fn pkg_registry_dir() -> i64 {
    let v: i64 = pkg_getenv("MOPKG_REGISTRY");
    if v != 0 {
        strcpy(&PKG_REG, v);
        return &PKG_REG;
    }
    let h: i64 = pkg_getenv("HOME");
    if h == 0 {
        strcpy(&PKG_REG, "/tmp/mopkg-registry");
    } else {
        strcpy(&PKG_REG, h);
        strcat(&PKG_REG, "/.mopkg/registry");
    }
    return &PKG_REG;
}

# mkdir -p（逐级）
fn pkg_mkdirp(p: ptr) -> i64 {
    let n: i64 = strlen(p);
    let i: i64 = 1;
    while i <= n {
        if load8(p + i) == 47 || i == n {
            store8(p + i, 0);
            mkdir(p, 493);
            store8(p + i, 47);
        }
        i = i + 1;
    }
    return 0;
}

# cp 文件（fsize 用 lseek END=2）
var PKG_CP: [4096] byte = 0;
var PKG_DST: [512] byte = 0;

fn pkg_cp_file(src: ptr, dst: ptr) -> i64 {
    let fd: i64 = fopen(src, 0, 0);
    if fd < 0 { return 0 - 1; }
    let sz: i64 = syscall(8, fd, 0, 2, 0, 0, 0);
    syscall(8, fd, 0, 0, 0, 0, 0);
    let done: i64 = 0;
    let ofd: i64 = fopen(dst, 577, 448);
    if ofd < 0 { fclose(fd); return 0 - 1; }
    while done < sz {
        let want: i64 = sz - done;
        if want > 4096 { want = 4096; }
        let r: i64 = syscall(0, fd, &PKG_CP, want, 0, 0, 0);
        if r <= 0 { break; }
        syscall(1, ofd, &PKG_CP, r, 0, 0, 0);
        done = done + r;
    }
    fclose(ofd);
    fclose(fd);
    return 0;
}

fn pkg_cmd_publish(tar: ptr, nm: ptr, ver: ptr) -> i64 {
    if strlen(tar) == 0 || strlen(nm) == 0 || strlen(ver) == 0 {
        print("✗ publish 需要 <tarball> <name> <version>\n");
        return 1;
    }
    pkg_registry_dir();
    strcpy(&PKG_VAL, &PKG_REG);
    strcat(&PKG_VAL, "/");
    strcat(&PKG_VAL, nm);
    pkg_mkdirp(&PKG_VAL);
    # 目标 tarball 绝对名
    strcpy(&PKG_DST, &PKG_VAL);
    strcat(&PKG_DST, "/");
    strcat(&PKG_DST, nm);
    strcat(&PKG_DST, "-");
    strcat(&PKG_DST, ver);
    strcat(&PKG_DST, ".tar.gz");
    if pkg_cp_file(tar, &PKG_DST) != 0 {
        print("✗ publish: 拷贝失败\n");
        return 1;
    }
    # 更新 index.txt（重建法：跳过同名旧行）
    strcpy(&PKG_VAL, &PKG_REG);
    strcat(&PKG_VAL, "/index.txt");
    let len: i64 = 0;
    let fd: i64 = fopen(&PKG_VAL, 0, 0);
    if fd >= 0 {
        syscall(0, fd, &PKG_IDX, 8191, 0, 0, 0);
        fclose(fd);
    }
    len = strlen(&PKG_IDX);
    let p: i64 = 0;
    let w: i64 = 0;
    let nm_len: i64 = strlen(nm);
    while p < len {
        let ls: i64 = p;
        while p < len && load8(&PKG_IDX + p) != 10 { p = p + 1; }
        let le: i64 = p;
        p = p + 1;
        let ism: i64 = 1;
        let k: i64 = 0;
        while k < nm_len {
            if ls + k >= le || load8(&PKG_IDX + ls + k) != load8(nm + k) { ism = 0; }
            k = k + 1;
        }
        if ism == 1 && load8(&PKG_IDX + ls + nm_len) != 9 { ism = 0; }
        if ism == 0 {
            let q: i64 = ls;
            while q < le {
                store8(&PKG_NEW + w, load8(&PKG_IDX + q));
                w = w + 1;
                q = q + 1;
            }
            store8(&PKG_NEW + w, 10);
            w = w + 1;
        }
    }
    strcpy(&PKG_NEW + w, nm);
    w = w + strlen(nm);
    store8(&PKG_NEW + w, 9); w = w + 1;
    strcpy(&PKG_NEW + w, ver);
    w = w + strlen(ver);
    store8(&PKG_NEW + w, 9); w = w + 1;
    strcpy(&PKG_NEW + w, &PKG_DST);
    w = w + strlen(&PKG_DST);
    store8(&PKG_NEW + w, 10); w = w + 1;
    let ofd: i64 = fopen(&PKG_VAL, 577, 448);
    if ofd < 0 {
        print("✗ publish: 写索引失败\n");
        return 1;
    }
    syscall(1, ofd, &PKG_NEW, w, 0, 0, 0);
    fclose(ofd);
    print("✓ 已发布 ");
    print(nm);
    print("@");
    print(ver);
    print(" -> ");
    print(&PKG_DST);
    print_nl();
    return 0;
}

fn pkg_cmd_search(kw: ptr) -> i64 {
    pkg_registry_dir();
    strcpy(&PKG_VAL, &PKG_REG);
    strcat(&PKG_VAL, "/index.txt");
    store8(&PKG_IDX, 0);
    let fd: i64 = fopen(&PKG_VAL, 0, 0);
    if fd < 0 {
        print("（registry 为空）\n");
        return 0;
    }
    syscall(0, fd, &PKG_IDX, 8191, 0, 0, 0);
    fclose(fd);
    let n: i64 = strlen(&PKG_IDX);
    let kw_len: i64 = strlen(kw);
    let p: i64 = 0;
    let cnt: i64 = 0;
    while p < n {
        let ls: i64 = p;
        while p < n && load8(&PKG_IDX + p) != 10 { p = p + 1; }
        let le: i64 = p;
        p = p + 1;
        let show: i64 = 0;
        if kw_len == 0 { show = 1; }
        else {
            # kw 出现在 name 字段（行首到 TAB）
            let name_end: i64 = ls;
            while name_end < le && load8(&PKG_IDX + name_end) != 9 { name_end = name_end + 1; }
            let k: i64 = ls;
            while k + kw_len <= name_end {
                let ok: i64 = 1;
                let j: i64 = 0;
                while j < kw_len {
                    if load8(&PKG_IDX + k + j) != kw[j] { ok = 0; }
                    j = j + 1;
                }
                if ok == 1 { show = 1; }
                k = k + 1;
            }
        }
        if show == 1 {
            let q: i64 = ls;
            while q < le {
                if load8(&PKG_IDX + q) == 9 { print("  "); } else { store8(&PKG_CHR, load8(&PKG_IDX + q)); print(&PKG_CHR); }
                q = q + 1;
            }
            print_nl();
            cnt = cnt + 1;
        }
    }
    if cnt == 0 { print("（无匹配）\n"); }
    return 0;
}

var PKG_ARG5: [256] byte = 0;
fn pkg_arg5() -> i64 {
    store8(&PKG_ARG5, 0);
    if argc() < 6 { return &PKG_ARG5; }
    strcpy(&PKG_ARG5, argv(5));
    return &PKG_ARG5;
}

var PKG_ARG6: [256] byte = 0;
fn pkg_arg6() -> i64 {
    store8(&PKG_ARG6, 0);
    if argc() < 7 { return &PKG_ARG6; }
    strcpy(&PKG_ARG6, argv(6));
    return &PKG_ARG6;
}

var PKG_ARG4: [256] byte = 0;
fn pkg_arg4() -> i64 {
    store8(&PKG_ARG4, 0);
    if argc() < 5 { return &PKG_ARG4; }
    strcpy(&PKG_ARG4, argv(4));
    return &PKG_ARG4;
}

# ---------- http= 依赖：HTTP GET 下载 tarball（v1.201.0）----------
# 点分 IPv4 → 大端 u32（127.0.0.1 = 2130706433）
fn pkg_ip4(s: ptr) -> i64 {
    let v: i64 = 0;
    let oct: i64 = 0;
    let i: i64 = 0;
    let nseg: i64 = 0;
    let c: i64 = 0;
    while i <= strlen(s) {
        c = load8(s + i);
        if c >= 48 && c <= 57 {
            oct = oct * 10 + (c - 48);
        } else {
            if c != 46 && c != 0 { return 0; }
            if oct > 255 { return 0; }
            v = v * 256 + oct;
            nseg = nseg + 1;
            oct = 0;
            if c == 0 { break; }
        }
        i = i + 1;
    }
    if nseg != 4 { return 0; }
    return v;
}

# pkg_http_get("http://127.0.0.1:18900/pkg/deplib-1.0.0.tar.gz", "/tmp/x.tgz")
# 成功返回 0。HTTP/1.0 简单语义：读到 EOF 即 body 结束。
var HG_BUF: [16384] byte = 0;
var HG_HOST: [256] byte = 0;
var HG_PATH: [512] byte = 0;
var HG_RESP: [65536] byte = 0;
var HG_DL: [512] byte = 0;
var HG_IDX: [32768] byte = 0;
var HG_SHA: [80] byte = 0;
var HG_LSHA: [80] byte = 0;
var PKG_SHA_LAST: [80] byte = 0;
var HG_CDIR: [128] byte = 0;
# v1.306:缓存上限可配置(MOPKG_CACHE_MAX 环境变量,默认 32)
var PKG_CACHE_MAX: i64 = 0;
var HG_CTGZ: [256] byte = 0;
var HG_CSHA: [256] byte = 0;
var HG_CLS: [256] byte = 0;

var PKG_AIO: i64 = 0;   # v1.216：1=fetch/publish 走 aio（协程上下文）；0=阻塞 tcp 回退

fn pkg_http_get(url: ptr, out: ptr) -> i64 {
    if strstr(url, "http://") != 0 { return 0 - 1; }
    let p: i64 = url + 7;
    let pe: i64 = p;
    while load8(pe) != 0 && load8(pe) != 47 { pe = pe + 1; }
    strcpy(&HG_HOST, p);
    store8(&HG_HOST + (pe - p), 0);
    strcpy(&HG_PATH, pe);
    if strlen(&HG_PATH) == 0 { strcpy(&HG_PATH, "/"); }
    let port: i64 = 80;
    let colon: i64 = strstr(&HG_HOST, ":");
    if colon >= 0 {
        port = atoi(&HG_HOST + colon + 1);
        store8(&HG_HOST + colon, 0);
    }
    # v1.254：统一走 httpcli（状态码校验 + CL 精确收 + gzip 透明解压）
    let st: i64 = 0;
    let gn: i64 = tcp_http_req_port("GET", &HG_PATH, &HG_HOST, port, 0, 0, &HG_RESP, 65000, &st);
    if gn < 0 { return 0 - 4; }
    if st != 200 { return 0 - 40; }
    let ofd: i64 = fopen(out, 577, 438);
    if ofd < 0 { return 0 - 6; }
    let off: i64 = 0;
    while off < gn {
        let w: i64 = 16384;
        if gn - off < w { w = gn - off; }
        syscall(1, ofd, &HG_RESP + off, w, 0, 0, 0);
        off = off + w;
    }
    fclose(ofd);
    return 0;
}

# v1.269:HEAD 预检——包不存在快速失败(免完整下载/缓存流程)
var HP_BUF2: [16384] byte = 0;
var HP_HOST2: [256] byte = 0;

fn pkg_http_head(url: ptr) -> i64 {
    if strstr(url, "http://") != 0 { return 0 - 1; }
    let p: i64 = url + 7;
    let pe: i64 = p;
    while load8(pe) != 0 && load8(pe) != 47 { pe = pe + 1; }
    strcpy(&HP_HOST2, p);
    store8(&HP_HOST2 + (pe - p), 0);
    let port: i64 = 80;
    let colon: i64 = strstr(&HP_HOST2, ":");
    if colon >= 0 {
        port = atoi(&HP_HOST2 + colon + 1);
        store8(&HP_HOST2 + colon, 0);
    }
    # 路径部分
    let path: i64 = url + (pe - url);
    let st: i64 = 0;
    let n: i64 = tcp_http_req_port("HEAD", path, &HP_HOST2, port, 0, 0, &HP_BUF2, 65000, &st);
    if n < 0 { return 0 - 2; }
    if st == 200 { return 0; }
    return 0 - st;
}

fn pkg_http_dep(fil: ptr, nm: ptr) -> i64 {
    # v1.306:首次调用时读环境变量初始化缓存上限
    if PKG_CACHE_MAX <= 0 {
        let cmv: i64 = pkg_getenv("MOPKG_CACHE_MAX");
        if cmv != 0 {
            PKG_CACHE_MAX = atoi(cmv);
            if PKG_CACHE_MAX < 1 { PKG_CACHE_MAX = 32; }
        } else {
            PKG_CACHE_MAX = 32;
        }
    }
    # v1.269:HEAD 预检——包不存在快速失败
    let hrc: i64 = pkg_http_head(fil);
    if hrc < 0 {
        print("✗ 远端包不存在或不可达 (HEAD rc=");
        print_i64(hrc);
        print(") ");
        print(fil);
        print_nl();
        return 0;
    }
    SH_OUT = &PKG_OUT;
    store64(&PKG_CMD, "mkdir");
    store64(&PKG_CMD + 8, "-p");
    store64(&PKG_CMD + 16, &PKG_DEP);
    store64(&PKG_CMD + 24, 0);
    sh_run(&PKG_CMD);
    strcpy(&HG_DL, &PKG_DEP);
    strcat(&HG_DL, "/");
    strcat(&HG_DL, nm);
    strcat(&HG_DL, ".http.tgz");
    # fetch 流程中途会 chdir，cp 相对路径会失效 → 下载路径转绝对
    strcpy(&QBUF2, &HG_DL);
    pkg_abspath(&QBUF2, &HG_DL);
    strcpy(&HG_HOST, fil);
    let hp: i64 = strstr(&HG_HOST, "//");
    if hp >= 0 {
        strcpy(&HG_HOST, &HG_HOST + hp + 2);
        let hsp: i64 = strstr(&HG_HOST, "/");
        if hsp > 0 { store8(&HG_HOST + hsp, 0); }
        let c2: i64 = strstr(&HG_HOST, ":");
        if c2 >= 0 { store8(&HG_HOST + c2, 0); }
        strcpy(&HG_PATH, "/search?kw=");
        strcat(&HG_PATH, nm);
        let st: i64 = 0;
        # 端口从原 url 提取
        strcpy(&HG_RESP, fil);
        let pp: i64 = strstr(&HG_RESP, "//");
        strcpy(&HG_RESP, &HG_RESP + pp + 2);
        let sp: i64 = strstr(&HG_RESP, "/");
        if sp > 0 { store8(&HG_RESP + sp, 0); }
        let prt: i64 = 80;
        let c3: i64 = strstr(&HG_RESP, ":");
        if c3 >= 0 { prt = atoi(&HG_RESP + c3 + 1); }
        let sn: i64 = tcp_http_req_port("GET", &HG_PATH, &HG_HOST, prt, 0, 0, &HG_RESP, 65000, &st);
        if sn >= 0 {
            # 行格式:name version sha;找本包行(首列 = nm)
            let lp: i64 = 0;
            let found: i64 = 0;
            strcpy(&HG_IDX, &HG_RESP);
            let ilen: i64 = strlen(&HG_IDX);
            let cur: i64 = 0;
            while cur < ilen {
                let nl: i64 = strstr(&HG_IDX + cur, "\n");
                if nl < 0 { nl = ilen - cur; }
                if nl > 0 {
                    store8(&HG_IDX + cur + nl, 0);
                    if found == 0 {
                        # 首列匹配?
                        if strstr(&HG_IDX + cur, nm) == 0 {
                            # 第三列:两个空格后
                            let s1p: i64 = strstr(&HG_IDX + cur, " ");
                            if s1p > 0 {
                                let s2p: i64 = strstr(&HG_IDX + cur + s1p + 1, " ");
                                if s2p > 0 {
                                    strcpy(&HG_SHA, &HG_IDX + cur + s1p + s2p + 2);
                                    found = 1;
                                }
                            }
                        }
                    }
                    store8(&HG_IDX + cur + nl, 10);
                }
                cur = cur + nl + 1;
            }
    strcpy(&HG_CDIR, "/tmp/mopkg_cache");
    store64(&PKG_CMD, "mkdir");
    store64(&PKG_CMD + 8, "-p");
    store64(&PKG_CMD + 16, &HG_CDIR);
    store64(&PKG_CMD + 24, 0);
    sh_run(&PKG_CMD);
    strcpy(&HG_CTGZ, &HG_CDIR);
    strcat(&HG_CTGZ, "/");
    strcat(&HG_CTGZ, nm);
    strcat(&HG_CTGZ, ".tgz");
    strcpy(&HG_CSHA, &HG_CDIR);
    strcat(&HG_CSHA, "/");
    strcat(&HG_CSHA, nm);
    strcat(&HG_CSHA, ".sha");
    # 缓存检查:HG_SHA 若已在远端查询中取得且缓存 tgz sha 一致 → 直接 cp
    let grc: i64 = 0 - 99;
    if strlen(&HG_SHA) > 0 {
        let cfd: i64 = fopen(&HG_CTGZ, 0, 0);
        if cfd >= 0 {
            let crn: i64 = fread(cfd, &HG_RESP, 65000);
            fclose(cfd);
            if crn > 0 {
                sha256_hex(&HG_RESP, crn, &HG_LSHA);
                if strstr(&HG_SHA, &HG_LSHA) == 0 {
                    store64(&PKG_CMD, "cp");
                    store64(&PKG_CMD + 8, &HG_CTGZ);
                    store64(&PKG_CMD + 16, &HG_DL);
                    store64(&PKG_CMD + 24, 0);
                    sh_run(&PKG_CMD);
                    print("↳ 缓存命中 ");
                    print(nm);
                    print_nl();
                    # v1.268:命中路径同样执行上限清理
                    SH_OUT = &PKG_OUT;
                    strcpy(&HG_CLS, "ls /tmp/mopkg_cache/*.tgz 2>/dev/null | wc -l");
                    store64(&PKG_CMD, "sh");
                    store64(&PKG_CMD + 8, "-c");
                    store64(&PKG_CMD + 16, &HG_CLS);
                    store64(&PKG_CMD + 24, 0);
                    sh_capture(&PKG_CMD);
                    let cn2: i64 = atoi(&PKG_OUT);
                    if cn2 >= PKG_CACHE_MAX {
                        strcpy(&HG_CLS, "rm -rf /tmp/mopkg_cache");
                        store64(&PKG_CMD, "sh");
                        store64(&PKG_CMD + 8, "-c");
                        store64(&PKG_CMD + 16, &HG_CLS);
                        store64(&PKG_CMD + 24, 0);
                        sh_run(&PKG_CMD);
                        store64(&PKG_CMD, "mkdir");
                        store64(&PKG_CMD + 8, "-p");
                        store64(&PKG_CMD + 16, &HG_CDIR);
                        store64(&PKG_CMD + 24, 0);
                        sh_run(&PKG_CMD);
                    }
                    return &HG_DL;
                }
            }
        }
    }
    grc = pkg_http_get(fil, &HG_DL);
    if grc != 0 {
        print("✗ http 下载失败 rc=");
        print_i64(grc);
        print_nl();
        return 0;
    }
    # v1.267:缓存命中——/tmp/mopkg_cache/<nm>.tgz 的 sha 与远端一致 → cp 跳过下载
    # 先查远端 sha(此函数后半已实现;这里提前查一次并复用)
            if found == 1 {
                # 本地 sha:读文件 → sha256_hex
                let fd0: i64 = fopen(&HG_DL, 0, 0);
                if fd0 >= 0 {
                    let rn: i64 = fread(fd0, &HG_RESP, 65000);
                    fclose(fd0);
                    if rn > 0 {
                        sha256_hex(&HG_RESP, rn, &HG_LSHA);
                        if strstr(&HG_SHA, &HG_LSHA) < 0 {
                            print("✗ sha256 校验失败: 期望 ");
                            print(&HG_SHA);
                            print(" 实得 ");
                            print(&HG_LSHA);
                            print_nl();
                            syscall(87, &HG_DL, 0, 0, 0, 0);
                            return 0;
                        }
                        strcpy(&PKG_SHA_LAST, &HG_LSHA);
                        # v1.267:写缓存(tgz 副本 + sha)
                        let fd0c: i64 = fopen(&HG_CSHA, 577, 438);
                        if fd0c >= 0 {
                            fwrite(fd0c, &HG_LSHA, strlen(&HG_LSHA));
                            fclose(fd0c);
                            store64(&PKG_CMD, "cp");
                            store64(&PKG_CMD + 8, &HG_DL);
                            store64(&PKG_CMD + 16, &HG_CTGZ);
                            store64(&PKG_CMD + 24, 0);
                            sh_run(&PKG_CMD);
                            # v1.268:缓存上限 32 包——超限清空目录(缓存语义无损,下次重下)
                            SH_OUT = &PKG_OUT;
                            strcpy(&HG_CLS, "ls /tmp/mopkg_cache/*.tgz 2>/dev/null | wc -l");
                            store64(&PKG_CMD, "sh");
                            store64(&PKG_CMD + 8, "-c");
                            store64(&PKG_CMD + 16, &HG_CLS);
                            store64(&PKG_CMD + 24, 0);
                            sh_capture(&PKG_CMD);
                            let cn: i64 = atoi(&PKG_OUT);
                            if cn >= PKG_CACHE_MAX {
                                strcpy(&HG_CLS, "rm -rf /tmp/mopkg_cache");
                                store64(&PKG_CMD, "sh");
                                store64(&PKG_CMD + 8, "-c");
                                store64(&PKG_CMD + 16, &HG_CLS);
                                store64(&PKG_CMD + 24, 0);
                                sh_run(&PKG_CMD);
                                store64(&PKG_CMD, "mkdir");
                                store64(&PKG_CMD + 8, "-p");
                                store64(&PKG_CMD + 16, &HG_CDIR);
                                store64(&PKG_CMD + 24, 0);
                                sh_run(&PKG_CMD);
                            }
                        }
                        let qi: i64 = 0 - 1;
                        let qs: i64 = 0;
                        while qs < QN_N {
                            if strcmp(QN[qs], nm) == 0 { qi = qs; }
                            qs = qs + 1;
                        }
                        if qi >= 0 { QSH[qi] = qsave(&HG_LSHA); }
                        print("✓ sha256 校验通过 ");
                        print(&HG_LSHA);
                        print_nl();
                    }
                }
            }
        }
    }
    return &HG_DL;
}

# ---------- push：HTTP PUT 上传 tarball 到远程 registry（v1.203.0）----------
var HP_BUF: [16384] byte = 0;
var HP_HOST: [256] byte = 0;
var HP_PATH: [512] byte = 0;
var HP_BODY: [65536] byte = 0;
var HP_SHA: [80] byte = 0;
var HP_Q: [512] byte = 0;

fn pkg_http_put(url: ptr, file: ptr, name: ptr, ver: ptr) -> i64 {
    return pkg_http_put_tok(url, file, name, ver, "");
}

# v1.266:远端删除——DELETE /pkg/<file>?token=<tok>&name=<name>
var RM_CACHE: [256] byte = 0;

fn pkg_http_delete(url: ptr, file: ptr, name: ptr, tok: ptr) -> i64 {
    if strstr(url, "http://") != 0 { return 0 - 1; }
    let p: i64 = url + 7;
    let pe: i64 = p;
    while load8(pe) != 0 && load8(pe) != 47 { pe = pe + 1; }
    strcpy(&HP_HOST, p);
    store8(&HP_HOST + (pe - p), 0);
    let port: i64 = 80;
    let colon: i64 = strstr(&HP_HOST, ":");
    if colon >= 0 {
        port = atoi(&HP_HOST + colon + 1);
        store8(&HP_HOST + colon, 0);
    }
    strcpy(&HP_PATH, "/pkg/");
    strcat(&HP_PATH, file);
    strcat(&HP_PATH, "?token=");
    strcat(&HP_PATH, tok);
    strcat(&HP_PATH, "&name=");
    strcat(&HP_PATH, name);
    let st: i64 = 0;
    let n: i64 = tcp_http_req_port("DELETE", &HP_PATH, &HP_HOST, port, 0, 0, &HP_BUF, 65000, &st);
    if n < 0 { return 0 - 2; }
    if st != 200 { return 0 - st; }
    return 0;
}

fn pkg_http_put_tok(url: ptr, file: ptr, name: ptr, ver: ptr, tok: ptr) -> i64 {
    if strstr(url, "http://") != 0 { return 0 - 1; }
    let p: i64 = url + 7;
    let pe: i64 = p;
    while load8(pe) != 0 && load8(pe) != 47 { pe = pe + 1; }
    strcpy(&HP_HOST, p);
    store8(&HP_HOST + (pe - p), 0);
    let port: i64 = 80;
    let colon: i64 = strstr(&HP_HOST, ":");
    if colon >= 0 {
        port = atoi(&HP_HOST + colon + 1);
        store8(&HP_HOST + colon, 0);
    }
    let ipu: i64 = pkg_ip4(&HP_HOST);
    if ipu == 0 { return 0 - 7; }
    # 读文件
    let fd0: i64 = fopen(file, 0, 0);
    if fd0 < 0 { return 0 - 8; }
    let sz: i64 = 0;
    let r: i64 = 0;
    while sz < 60000 {
        let room: i64 = 65000 - sz;   # HP_BODY[65536] 越界加固（v1.205.0）
        if room <= 0 {
            print("mopkg: push 文件超 65000 字节上限\n");
            fclose(fd0);
            return 0 - 10;
        }
        let want: i64 = 8192;
        if want > room { want = room; }
        r = syscall(0, fd0, &HP_BODY + sz, want, 0, 0, 0);
        if r <= 0 { break; }
        sz = sz + r;
    }
    fclose(fd0);
    if sz <= 0 { return 0 - 9; }
    if PKG_AIO == 1 {
        # aio 路径（v1.216）：aio_pool_config + aio_http_put
        aio_pool_config(ipu, port);
        strcpy(&HP_PATH, "/pkg/");
        strcat(&HP_PATH, name);
        strcat(&HP_PATH, "-");
        strcat(&HP_PATH, ver);
        strcat(&HP_PATH, ".tar.gz?name=");
        strcat(&HP_PATH, name);
        strcat(&HP_PATH, "&ver=");
        strcat(&HP_PATH, ver);
        let prn: i64 = aio_http_put(&HP_PATH, &HP_BODY, sz, &HP_BUF, 4000);
        # aio_http_put 内部已判状态行（rx 槽含完整响应）；buf 只装 body
        if prn < 0 { return prn; }
        return 0;
    }
    # v1.255：同步分支改走 httpcli（POST gzip 压缩上传 → registry 透明解压入库）
    strcpy(&HP_PATH, "/publish/");
    strcat(&HP_PATH, name);
    strcat(&HP_PATH, "-");
    strcat(&HP_PATH, ver);
    strcat(&HP_PATH, ".tar.gz?name=");
    strcat(&HP_PATH, name);
    strcat(&HP_PATH, "&version=");
    strcat(&HP_PATH, ver);
    if strlen(tok) > 0 {
        strcat(&HP_PATH, "&token=");
        strcat(&HP_PATH, tok);
    }
    let st: i64 = 0;
    let bn: i64 = tcp_http_post_gzip(&HP_PATH, &HP_HOST, port, &HP_BODY, sz, &HP_BUF, 4000, &st);
    if bn < 0 { return bn; }
    if st != 200 && st != 201 {
        # v1.274:409 → 专码 -409(已存在),其余 -6
        if st == 409 { return 0 - 409; }
        return 0 - 6;
    }
    # v1.256：远端 sha256 校验——GET /search?kw=<name> 拿 index 行,比对本地 sha256
    sha256_hex(&HP_BODY, sz, &HP_SHA);
    strcpy(&HP_Q, "/search?kw=");
    strcat(&HP_Q, name);
    let sn: i64 = tcp_http_req_port("GET", &HP_Q, &HP_HOST, port, 0, 0, &HP_BUF, 4000, &st);
    if sn >= 0 {
        # 找含本 sha 的行
        if strstr(&HP_BUF, &HP_SHA) < 0 { return 0 - 11; }
    }
    return 0;
}

# 远程 search：GET /search?kw=，打印响应体（v1.204.0）
var HS_URL: [768] byte = 0;
var HS_RESP: [32768] byte = 0;

var SR_CACHE: [256] byte = 0;

fn pkg_search_remote(kw: ptr, base: ptr) -> i64 {
    strcpy(&HS_URL, base);
    # base 去尾斜杠
    let bl: i64 = strlen(&HS_URL);
    if bl > 0 && load8(&HS_URL + bl - 1) == 47 { store8(&HS_URL + bl - 1, 0); }
    strcat(&HS_URL, "/search?kw=");
    strcat(&HS_URL, kw);
    # v1.268:分页透传(argc>5:mopkg search <kw> <url> <page> <size>)
    if argc() > 5 {
        strcat(&HS_URL, "&page=");
        strcat(&HS_URL, pkg_arg4());
        if argc() > 6 {
            strcat(&HS_URL, "&size=");
            strcat(&HS_URL, pkg_arg5());
        }
    }
    if pkg_http_get(&HS_URL, "/tmp/mopkg-search.out") != 0 {
        print("✗ 远程 search 失败\n");
        return 1;
    }
    let fd: i64 = fopen("/tmp/mopkg-search.out", 0, 0);
    if fd < 0 { return 1; }
    let n: i64 = syscall(0, fd, &HS_RESP, 32000, 0, 0, 0);
    fclose(fd);
    if n <= 0 {
        print("（无匹配）\n");
        return 0;
    }
    # v1.261:格式化输出——行格式 name version sha;sha 截前 12 位加 …
    let lp: i64 = 0;
    while lp < n {
        let le: i64 = lp;
        while le < n && load8(&HS_RESP + le) != 10 { le = le + 1; }
        if le > lp {
            # 找第 2、3 空格
            let s1: i64 = lp;
            while s1 < le && load8(&HS_RESP + s1) != 32 { s1 = s1 + 1; }
            let s2: i64 = s1 + 1;
            while s2 < le && load8(&HS_RESP + s2) != 32 { s2 = s2 + 1; }
            if s2 < le {
                store8(&HS_RESP + le, 0);
                # v1.275:列切分 name=[lp,s1) ver=[s1+1,s2) sha=[s2+1,s3) 时间戳忽略
                let s3: i64 = s2 + 1;
                while s3 < le && load8(&HS_RESP + s3) != 32 { s3 = s3 + 1; }
                store8(&HS_RESP + s3, 0);
                store8(&HS_RESP + s2, 0);
                store8(&HS_RESP + s1, 0);
                print(&HS_RESP + lp);
                print("  ");
                print(&HS_RESP + lp + s1 + 1);
                print("  ");
                print(&HS_RESP + lp + s2 + 1);
                let sha_len: i64 = s3 - s2 - 1;
                print("  (");
                print_i64(sha_len);
                print(" hex)");
                # v1.280:缓存状态
                strcpy(&SR_CACHE, "/tmp/mopkg_cache/");
                strcat(&SR_CACHE, &HS_RESP + lp);
                strcat(&SR_CACHE, ".tgz");
                let cfd: i64 = fopen(&SR_CACHE, 0, 0);
                if cfd >= 0 {
                    fclose(cfd);
                    print("  [cached]");
                }
                print_nl();
            } else {
                store8(&HS_RESP + le, 0);
                print(&HS_RESP + lp);
                print_nl();
            }
        }
        lp = le + 1;
    }
    # v1.287:搜索完打印网页入口
    print("  网页: ");
    print(base);
    print("/");
    print_nl();
    return 0;
}

fn pkg_dispatch(cmd: ptr) -> i64 {
    if streq(cmd, "list") == 1 { return pkg_cmd_list(); }
    if streq(cmd, "tree") == 1 { return pkg_cmd_tree(); }
    if streq(cmd, "verify") == 1 { return pkg_cmd_verify(); }
    if streq(cmd, "fetch") == 1 { return pkg_cmd_fetch(); }
    if streq(cmd, "pack") == 1 { return pkg_cmd_pack(pkg_arg2(), pkg_arg3()); }
    if streq(cmd, "remove") == 1 {
        if argc() > 3 {
            if streq(pkg_arg3(), "--remote") == 1 {
                let drc: i64 = pkg_http_delete(pkg_arg4(), pkg_arg2(), pkg_arg5(), pkg_arg6());
                if drc == 0 {
                    print("✓ 远端已删除 ");
                    print(pkg_arg2());
                    print_nl();
                    # v1.279:同步清理本地缓存副本(缓存按 name 记,不带版本)
                    strcpy(&RM_CACHE, "/tmp/mopkg_cache/");
                    strcat(&RM_CACHE, pkg_arg5());
                    strcat(&RM_CACHE, ".tgz");
                    let cfd: i64 = fopen(&RM_CACHE, 0, 0);
                    if cfd >= 0 {
                        fclose(cfd);
                        syscall(87, &RM_CACHE, 0, 0, 0, 0);
                    }
                    strcpy(&RM_CACHE, "/tmp/mopkg_cache/");
                    strcat(&RM_CACHE, pkg_arg5());
                    strcat(&RM_CACHE, ".sha");
                    let cfd2: i64 = fopen(&RM_CACHE, 0, 0);
                    if cfd2 >= 0 {
                        fclose(cfd2);
                        syscall(87, &RM_CACHE, 0, 0, 0, 0);
                    }
                    print("✓ 已清理缓存 ");
                    print(pkg_arg2());
                    print_nl();
                    return 0;
                }
                print("✗ 远端删除失败 rc=");
                print_i64(drc);
                print_nl();
                return 1;
            }
        }
        return pkg_cmd_remove(pkg_arg2());
    }
    if streq(cmd, "update") == 1 { return pkg_cmd_update(pkg_arg2()); }
    if streq(cmd, "publish") == 1 {
        if argc() > 5 {
            # 远程 publish：publish <tar> <name> <ver> http://host:port
            let pkr: i64 = pkg_http_put_tok(pkg_arg5(), pkg_arg2(), pkg_arg3(), pkg_arg4(), pkg_arg6());
            if pkr == 0 {
                print("✓ 已推送 ");
                print(pkg_arg3());
                print("@");
                print(pkg_arg4());
                print(" -> ");
                print(pkg_arg5());
                print_nl();
                # v1.286:网页入口链接
                print("  网页: ");
                print(pkg_arg5());
                print("/");
                print_nl();
                return 0;
            }
            # v1.274:409 → 提示已存在
            if pkr == 0 - 409 {
                print("✗ 包已存在: ");
                print(pkg_arg3());
                print("@");
                print(pkg_arg4());
                print_nl();
                return 2;
            }
            print("✗ 远程发布失败 (rc=");
            print_i64(pkr);
            print(")\n");
            return 1;
        }
        return pkg_cmd_publish(pkg_arg2(), pkg_arg3(), pkg_arg4());
    }
    if streq(cmd, "search") == 1 {
        if argc() > 3 {
            return pkg_search_remote(pkg_arg2(), pkg_arg3());
        }
        return pkg_cmd_search(pkg_arg2());
    }
    print("mopkg: 未知命令 ");
    print(cmd);
    print_nl();
    print("用法: mopkg <list|tree|verify|fetch|remove|update|pack|publish|search>\n");
    return 1;
}
