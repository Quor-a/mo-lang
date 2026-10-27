import "io.mo";
# 正则引擎：Thompson NFA 构造 + Pike VM 并行模拟
#
# 参考：
#   Ken Thompson 1968（NFA 构造）
#   Rob Pike 1998 "Regular Expression Matching Can Be Simple And Fast"
#     https://swtch.com/~rsc/regexp/regexp1.html
#
# 为什么不用回溯：回溯匹配器在最坏情况下是指数的（catastrophic
# backtracking / ReDoS），Thompson 模拟是 O(n*m)。本库同时提供
# rx_backtrack() 作为对照，实测两者的步数曲线。
#
# 指令集（顺序生成，无递归；mo 无前向声明，递归下降解析器写不出来）

var RX_OP: [1024] i64 = 0;
var RX_A: [1024] i64 = 0;
var RX_B: [1024] i64 = 0;
var RX_N: i64 = 0;
var RX_CLS: [2560] i64 = 0;
var RX_NC: i64 = 0;
var RX_NS: i64 = 0;
var RX_NG: i64 = 0;
var RX_ERR: i64 = 0;

# 待回填位置：AL = jmp 到本组出口；PN = split 的第二分支（下一分支入口）
var AL_I: [256] i64 = 0;
var AL_N: i64 = 0;
var PN_I: [256] i64 = 0;
var PN_N: i64 = 0;

# 分组栈（后进先出，所以 AL/PN 每层占一段连续区间）
var ST_J: [64] i64 = 0;
var ST_SL: [64] i64 = 0;
var ST_FS: [64] i64 = 0;
var ST_AE: [64] i64 = 0;
var ST_AB: [64] i64 = 0;
var ST_PB: [64] i64 = 0;
var ST_S: [64] i64 = 0;
var ST_V: [64] i64 = 0;
var ST_SP: i64 = 0;

var CU_S: i64 = 0;
var CU_V: i64 = 0;

# ---- 指令 ----

var TH_PC: [256] i64 = 0;
var TH_SL: [5120] i64 = 0;
var TH_N: i64 = 0;
var TH_BASE: i64 = 0;
var TH_VIS: [1024] i64 = 0;
var TH_GEN: i64 = 0;
var LS_T: [512] i64 = 0;
var LS_C: i64 = 0;
var LS_N: i64 = 0;
var STK_P: [2048] i64 = 0;
var STK_T: [2048] i64 = 0;
var STK_N: i64 = 0;
var RX_LEN: i64 = 0;
var RX_HIT: i64 = 0;
var RX_BS: i64 = 0;
var RX_MS: [24] i64 = 0;
var RX_STEPS: i64 = 0;

fn rx_emit(op: i64, a: i64, b: i64) -> i64 {
    let pc: i64 = RX_N;
    RX_OP[pc] = op;
    RX_A[pc] = a;
    RX_B[pc] = b;
    RX_N = RX_N + 1;
    return pc;
}

fn rx_addal(i: i64) -> i64 {
    AL_I[AL_N] = i;
    AL_N = AL_N + 1;
    return 0;
}

fn rx_addpn(i: i64) -> i64 {
    PN_I[PN_N] = i;
    PN_N = PN_N + 1;
    return 0;
}

fn rx_patchal(beg: i64, t: i64) -> i64 {
    let i: i64 = beg;
    while i < AL_N {
        RX_A[AL_I[i]] = t;
        i = i + 1;
    }
    AL_N = beg;
    return 0;
}

fn rx_patchpn(beg: i64, t: i64) -> i64 {
    let i: i64 = beg;
    while i < PN_N {
        RX_B[PN_I[i]] = t;
        i = i + 1;
    }
    PN_N = beg;
    return 0;
}

# ---- 字符类 ----
fn rx_cls_new() -> i64 {
    RX_NC = RX_NC + 1;
    let k: i64 = RX_NC * 256;
    let i: i64 = 0;
    while i < 256 {
        RX_CLS[k + i] = 0;
        i = i + 1;
    }
    return RX_NC;
}

fn rx_cls_set(c: i64, ch: i64, v: i64) -> i64 {
    if ch < 0 { return 0; }
    if ch > 255 { return 0; }
    RX_CLS[c * 256 + ch] = v;
    return 0;
}

fn rx_cls_get(c: i64, ch: i64) -> i64 {
    if ch < 0 { return 0; }
    if ch > 255 { return 0; }
    return RX_CLS[c * 256 + ch];
}

# ---- 生成一个原子（普通指令）----
# 所有 frag 的出口都是"自然落到下一条指令"，所以不需要 out 链表，
# 只有组出口（jmp END）和 split 第二分支需要回填。
fn rx_atom(op: i64, a: i64, b: i64) -> i64 {
    let pc: i64 = rx_emit(op, a, b);
    if CU_V == 0 {
        CU_S = pc;
        CU_V = 1;
    }
    return 0;
}

# ---- 结束一个分支：emit jmp END ----
fn rx_endbranch() -> i64 {
    let j: i64 = rx_emit(4, 0, 0);
    rx_addal(j);
    return 0;
}

# ---- '|' ----
fn rx_alt() -> i64 {
    if CU_V == 0 {
        RX_ERR = 2;
        return 0 - 1;
    }
    let prev: i64 = CU_S;
    rx_endbranch();
    # PN（上一个 split 的第二分支）指向即将生成的 split
    rx_patchpn(ST_PB[ST_SP], RX_N);
    let sp: i64 = rx_emit(3, prev, 0);
    rx_addpn(sp);
    if ST_AE[ST_SP] == 0 { ST_AE[ST_SP] = sp; }
    CU_S = RX_N;
    CU_V = 1;
    return 0;
}

# ---- 后缀 * + ? ----
fn rx_star() -> i64 {
    if CU_V == 0 { RX_ERR = 3; return 0 - 1; }
    let s: i64 = rx_emit(3, CU_S, 0);
    RX_B[s] = RX_N;
    CU_S = s;
    return 0;
}

fn rx_plus() -> i64 {
    if CU_V == 0 { RX_ERR = 3; return 0 - 1; }
    let s: i64 = rx_emit(3, CU_S, 0);
    RX_B[s] = RX_N;
    return 0;
}

fn rx_ques() -> i64 {
    if CU_V == 0 { RX_ERR = 3; return 0 - 1; }
    let s: i64 = rx_emit(3, CU_S, 0);
    RX_B[s] = RX_N;
    CU_S = s;
    return 0;
}

# ---- '(' ----
fn rx_open() -> i64 {
    let n: i64 = RX_NG;
    RX_NG = RX_NG + 1;
    ST_S[ST_SP] = CU_S;
    ST_V[ST_SP] = CU_V;
    let j: i64 = rx_emit(6, 2 + 2 * n, 0);
    let jm: i64 = rx_emit(4, 0, 0);
    ST_SP = ST_SP + 1;
    ST_J[ST_SP] = jm;
    ST_SL[ST_SP] = n;
    ST_FS[ST_SP] = RX_N;
    ST_AE[ST_SP] = 0;
    ST_AB[ST_SP] = AL_N;
    ST_PB[ST_SP] = PN_N;
    CU_V = 0;
    return j;
}

# ---- ')' 与整组收尾 ----
fn rx_close() -> i64 {
    if ST_SP == 0 { RX_ERR = 4; return 0 - 1; }
    let n: i64 = ST_SL[ST_SP];
    let last: i64 = CU_S;
    if CU_V == 0 { last = ST_FS[ST_SP]; }
    rx_endbranch();
    let sv: i64 = rx_emit(6, 3 + 2 * n, 0);
    rx_patchal(ST_AB[ST_SP], sv);
    rx_patchpn(ST_PB[ST_SP], last);
    let entry: i64 = ST_AE[ST_SP];
    if entry == 0 { entry = last; }
    let jm: i64 = ST_J[ST_SP];
    RX_A[jm] = entry;
    let jj: i64 = jm - 1;
    ST_SP = ST_SP - 1;
    if ST_V[ST_SP] == 0 {
        CU_S = jj;
    } else {
        CU_S = ST_S[ST_SP];
    }
    CU_V = 1;
    return 0;
}

# ---- 字符类 [...]，返回解析后的下标 ----
fn rx_class(pat: ptr, i: i64) -> i64 {
    let c: i64 = rx_cls_new();
    i = i + 1;
    let neg: i64 = 0;
    if pat[i] == 94 {
        neg = 1;
        i = i + 1;
    }
    while pat[i] != 0 {
        if pat[i] == 93 {
            if neg == 1 {
                let k: i64 = 0;
                while k < 256 {
                    if rx_cls_get(c, k) == 0 { rx_cls_set(c, k, 1); } else { rx_cls_set(c, k, 0); }
                    k = k + 1;
                }
            }
            rx_atom(9, c, 0);
            return i + 1;
        }
        if pat[i + 1] == 45 {
            if pat[i + 2] == 0 { RX_ERR = 5; return 0 - 1; }
            if pat[i + 2] == 93 { RX_ERR = 5; return 0 - 1; }
            let lo: i64 = pat[i];
            let hi: i64 = pat[i + 2];
            let k: i64 = lo;
            while k <= hi {
                rx_cls_set(c, k, 1);
                k = k + 1;
            }
            i = i + 3;
        } else {
            rx_cls_set(c, pat[i], 1);
            i = i + 1;
        }
    }
    RX_ERR = 5;
    return 0 - 1;
}

# ---- 编译 ----
fn re_compile(pat: ptr) -> i64 {
    RX_N = 0;
    RX_NC = 0;
    RX_NG = 0 - 1;
    RX_ERR = 0;
    AL_N = 0;
    PN_N = 0;
    ST_SP = 0;
    CU_S = 0;
    CU_V = 0;
    let anch: i64 = 0;
    if pat[0] == 94 { anch = 1; }
    let p0: i64 = rx_emit(3, 0, 0);
    if anch == 1 {
        RX_OP[p0] = 4;
    } else {
        RX_B[p0] = 1;
        rx_emit(2, 0, 0);
        rx_emit(4, p0, 0);
    }
    let body: i64 = rx_open();
    RX_A[p0] = body;
    let i: i64 = 0;
    if anch == 1 { i = 1; }
    while pat[i] != 0 {
        let c: i64 = pat[i];
        if c == 40 {
            rx_open();
            i = i + 1;
        } else if c == 41 {
            if rx_close() < 0 { return 0 - 1; }
            i = i + 1;
        } else if c == 124 {
            if rx_alt() < 0 { return 0 - 1; }
            i = i + 1;
        } else if c == 42 {
            if rx_star() < 0 { return 0 - 1; }
            i = i + 1;
        } else if c == 43 {
            if rx_plus() < 0 { return 0 - 1; }
            i = i + 1;
        } else if c == 63 {
            if rx_ques() < 0 { return 0 - 1; }
            i = i + 1;
        } else if c == 46 {
            rx_atom(2, 0, 0);
            i = i + 1;
        } else if c == 36 {
            rx_atom(8, 0, 0);
            i = i + 1;
        } else if c == 94 {
            rx_atom(7, 0, 0);
            i = i + 1;
        } else if c == 91 {
            let r: i64 = rx_class(pat, i);
            if r < 0 { return 0 - 1; }
            i = r;
        } else if c == 92 {
            rx_atom(1, pat[i + 1], 0);
            i = i + 2;
        } else {
            rx_atom(1, c, 0);
            i = i + 1;
        }
    }
    if rx_close() < 0 { return 0 - 1; }
    if ST_SP != 0 {
        RX_ERR = 8;
        return 0 - 1;
    }
    rx_emit(5, 0, 0);
    RX_NS = 4 + 2 * RX_NG;
    if RX_NS > 20 { RX_NS = 20; }
    return 0;
}

fn rx_newthread(pc: i64, src: i64) -> i64 {
    TH_N = TH_N + 1;
    if TH_N >= 128 { RX_ERR = 6; return 0; }
    let t: i64 = TH_BASE + TH_N;
    TH_PC[t] = pc;
    let k: i64 = 0;
    while k < RX_NS {
        if src == 0 { TH_SL[t * 20 + k] = 0 - 1; } else { TH_SL[t * 20 + k] = TH_SL[src * 20 + k]; }
        k = k + 1;
    }
    return t;
}

fn rx_addthread(nx: i64, pc: i64, src: i64, pos: i64) -> i64 {
    STK_N = 0;
    STK_N = STK_N + 1;
    STK_P[STK_N] = pc;
    STK_T[STK_N] = src;
    while STK_N > 0 {
        let p: i64 = STK_P[STK_N];
        let sr: i64 = STK_T[STK_N];
        STK_N = STK_N - 1;
        RX_STEPS = RX_STEPS + 1;
        let op: i64 = RX_OP[p];
        if op == 4 {
            if TH_VIS[p] == TH_GEN { continue; }
            TH_VIS[p] = TH_GEN;
            STK_N = STK_N + 1;
            STK_P[STK_N] = RX_A[p];
            STK_T[STK_N] = sr;
            continue;
        }
        if op == 3 {
            if TH_VIS[p] == TH_GEN { continue; }
            TH_VIS[p] = TH_GEN;
            STK_N = STK_N + 1;
            STK_P[STK_N] = RX_B[p];
            STK_T[STK_N] = sr;
            STK_N = STK_N + 1;
            STK_P[STK_N] = RX_A[p];
            STK_T[STK_N] = sr;
            continue;
        }
        if op == 6 {
            let t: i64 = rx_newthread(p, sr);
            if t == 0 { return 0 - 1; }
            TH_SL[t * 20 + RX_A[p]] = pos;
            STK_N = STK_N + 1;
            STK_P[STK_N] = p + 1;
            STK_T[STK_N] = t;
            continue;
        }
        if op == 7 {
            if pos == 0 {
                STK_N = STK_N + 1;
                STK_P[STK_N] = p + 1;
                STK_T[STK_N] = sr;
            }
            continue;
        }
        if op == 8 {
            if pos == RX_LEN {
                STK_N = STK_N + 1;
                STK_P[STK_N] = p + 1;
                STK_T[STK_N] = sr;
            }
            continue;
        }
        if op == 5 {
            let t: i64 = rx_newthread(p, sr);
            if t == 0 { return 0 - 1; }
            let s0: i64 = TH_SL[t * 20 + 0];
            if RX_HIT == 0 {
                RX_HIT = 1;
                RX_BS = s0;
            }
            if s0 <= RX_BS {
                RX_BS = s0;
                let k: i64 = 0;
                while k < RX_NS {
                    RX_MS[k] = TH_SL[t * 20 + k];
                    k = k + 1;
                }
            }
            continue;
        }
        let t2: i64 = rx_newthread(p, sr);
        if t2 == 0 { return 0 - 1; }
        if nx == 0 {
            if LS_C >= 256 { RX_ERR = 7; return 0 - 1; }
            LS_T[LS_C] = t2;
            LS_C = LS_C + 1;
        } else {
            if LS_N >= 256 { RX_ERR = 7; return 0 - 1; }
            LS_T[256 + LS_N] = t2;
            LS_N = LS_N + 1;
        }
    }
    return 0;
}

fn re_run(txt: ptr) -> i64 {
    TH_N = 0;
    TH_BASE = 0;
    RX_STEPS = 0;
    LS_C = 0;
    LS_N = 0;
    RX_HIT = 0;
    RX_BS = 0 - 1;
    TH_GEN = TH_GEN + 1;
    rx_addthread(0, 0, 0, 0);
    let pos: i64 = 0;
    while pos <= RX_LEN {
        if LS_C == 0 { return RX_HIT; }
        LS_N = 0;
        TH_N = 0;
        if TH_BASE == 0 { TH_BASE = 128; } else { TH_BASE = 0; }
        TH_GEN = TH_GEN + 1;
        let c: i64 = 0 - 1;
        if pos < RX_LEN { c = txt[pos]; }
        let i: i64 = 0;
        while i < LS_C {
            let t: i64 = LS_T[i];
            let pc: i64 = TH_PC[t];
            let op: i64 = RX_OP[pc];
            if op == 1 {
                if c == RX_A[pc] { rx_addthread(1, pc + 1, t, pos + 1); }
            } else {
            if op == 2 {
                if c >= 0 { rx_addthread(1, pc + 1, t, pos + 1); }
            } else {
            if op == 9 {
                if c >= 0 {
                    if rx_cls_get(RX_A[pc], c) != 0 { rx_addthread(1, pc + 1, t, pos + 1); }
                }
            } else { }
            }}
            i = i + 1;
        }
        let k: i64 = 0;
        while k < LS_N { LS_T[k] = LS_T[256 + k]; k = k + 1; }
        LS_C = LS_N;
        pos = pos + 1;
    }
    return RX_HIT;
}

fn re_match(txt: ptr) -> i64 {
    RX_LEN = 0;
    while txt[RX_LEN] != 0 { RX_LEN = RX_LEN + 1; }
    let r: i64 = re_run(txt);
    if r == 0 { return 0 - 1; }
    return RX_MS[0];
}

fn re_exec(pat: ptr, txt: ptr) -> i64 {
    let r: i64 = re_compile(pat);
    if r != 0 { return 0 - 2; }
    return re_match(txt);
}

fn re_endpos() -> i64 {
    if RX_HIT == 0 { return 0 - 1; }
    return RX_MS[1];
}

fn re_gs(n: i64) -> i64 {
    if RX_HIT == 0 { return 0 - 1; }
    return RX_MS[2 + 2 * n];
}

fn re_ge(n: i64) -> i64 {
    if RX_HIT == 0 { return 0 - 1; }
    return RX_MS[3 + 2 * n];
}

fn re_steps() -> i64 { return RX_STEPS; }
fn re_pcount() -> i64 { return RX_N; }
fn re_err() -> i64 { return RX_ERR; }

fn re_nslots() -> i64 { return RX_NS; }
fn re_ms(k: i64) -> i64 { return RX_MS[k]; }
fn re_dump() -> i64 {
    let i: i64 = 0;
    while i < RX_N {
        print_i64(i);
        print(":");
        print_i64(RX_OP[i]);
        print(" ");
        print_i64(RX_A[i]);
        print(" ");
        print_i64(RX_B[i]);
        print("\n");
        i = i + 1;
    }
    return 0;
}

# ---- 回溯对照（概念核心证据）----
# 只支持 . * + ? | ( ) 与单字符原子，不做记忆化 —— 这正是回溯引擎的形状：
# 同一状态会被反复访问，最坏情况指数。Pike VM 有 visited 去重，是线性的。
var BT_PS: [16384] i64 = 0;
var BT_SS: [16384] i64 = 0;
var BT_SP2: i64 = 0;
var BT_STEPS: i64 = 0;
var BT_OVF: i64 = 0;
var BT_MAX: i64 = 0;

fn rx_bt_push(pi: i64, si: i64) -> i64 {
    if BT_SP2 >= 16380 {
        BT_OVF = 1;
        return 0;
    }
    BT_SP2 = BT_SP2 + 1;
    BT_PS[BT_SP2] = pi;
    BT_SS[BT_SP2] = si;
    return 0;
}

fn rx_bt_open(pat: ptr, ci: i64) -> i64 {
    let d: i64 = 0;
    let i: i64 = ci - 1;
    while i >= 0 {
        if pat[i] == 41 { d = d + 1; }
        if pat[i] == 40 {
            if d == 0 { return i; }
            d = d - 1;
        }
        i = i - 1;
    }
    return 0 - 1;
}

fn rx_bt_close(pat: ptr, oi: i64) -> i64 {
    let d: i64 = 0;
    let i: i64 = oi;
    while pat[i] != 0 {
        if pat[i] == 40 { d = d + 1; }
        if pat[i] == 41 {
            if d == 1 { return i; }
            d = d - 1;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn rx_bt(pat: ptr, txt: ptr, budget: i64) -> i64 {
    BT_SP2 = 0;
    BT_STEPS = 0;
    BT_OVF = 0;
    BT_MAX = budget;
    rx_bt_push(0, 0);
    while BT_SP2 > 0 {
        if BT_OVF == 1 { return 0 - 2; }
        let pi: i64 = BT_PS[BT_SP2];
        let si: i64 = BT_SS[BT_SP2];
        BT_SP2 = BT_SP2 - 1;
        BT_STEPS = BT_STEPS + 1;
        if BT_STEPS > BT_MAX { return 0 - 2; }
        if pat[pi] == 0 {
            if txt[si] == 0 { return 1; }
            continue;
        }
        let c: i64 = pat[pi];
        let nx: i64 = pat[pi + 1];
        if c == 40 {
            rx_bt_push(pi + 1, si);
            continue;
        }
        if c == 41 {
            if nx == 42 {
                let o: i64 = rx_bt_open(pat, pi);
                rx_bt_push(pi + 2, si);
                rx_bt_push(o + 1, si);
            } else if nx == 43 {
                let o: i64 = rx_bt_open(pat, pi);
                rx_bt_push(pi + 2, si);
                rx_bt_push(o + 1, si);
            } else {
                rx_bt_push(pi + 1, si);
            }
            continue;
        }
        if c == 124 {
            let cl: i64 = rx_bt_close(pat, rx_bt_open(pat, pi));
            rx_bt_push(pi + 1, si);
            rx_bt_push(cl + 1, si);
            continue;
        }
        if c == 42 {
            if pat[pi - 1] == 41 {
                let o: i64 = rx_bt_open(pat, pi - 1);
                rx_bt_push(pi + 1, si);
                rx_bt_push(o + 1, si);
            } else {
                rx_bt_push(pi + 1, si);
                if txt[si] != 0 {
                    if txt[si] == pat[pi - 1] { rx_bt_push(pi, si + 1); } else { if pat[pi - 1] == 46 { rx_bt_push(pi, si + 1); } }
                }
            }
            continue;
        }
        if c == 43 {
            if pat[pi - 1] == 41 {
                let o: i64 = rx_bt_open(pat, pi - 1);
                rx_bt_push(pi + 1, si);
                rx_bt_push(o + 1, si);
            } else {
                rx_bt_push(pi + 1, si);
                if txt[si] != 0 {
                    if txt[si] == pat[pi - 1] { rx_bt_push(pi, si + 1); } else { if pat[pi - 1] == 46 { rx_bt_push(pi, si + 1); } }
                }
            }
            continue;
        }
        if c == 63 {
            rx_bt_push(pi + 1, si);
            continue;
        }
        let ok: i64 = 0;
        if txt[si] != 0 {
            if c == 46 { ok = 1; } else { if txt[si] == c { ok = 1; } }
        }
        if nx == 42 { rx_bt_push(pi + 2, si); } else { if nx == 63 { rx_bt_push(pi + 2, si); } }
        if ok == 1 { rx_bt_push(pi + 1, si + 1); }
    }
    return 0;
}

fn rx_bt_steps() -> i64 { return BT_STEPS; }
fn rx_bt_ovf() -> i64 { return BT_OVF; }
