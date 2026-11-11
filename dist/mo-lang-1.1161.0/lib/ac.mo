import "io.mo";

# ac —— Aho–Corasick 多模式匹配自动机
#
# 参考：
#   Aho & Corasick 1975 "Efficient string matching: an aid to
#   bibliographic search"（CACM 18(6)）
#     —— goto / failure / output 三函数，O(n + m + z)
#
# 它是什么：给定**模式集合** P = {p1..pk}，预处理出一台 DFA，
#   之后**扫一遍文本**就找出全部模式的所有出现，代价与 k 无关。
#   · 构造 O(m)（m = Σ|pi|）
#   · 扫描 O(n + z)（n = |text|，z = 匹配次数）
#   · failure link 把"失配后重新扫"变成"沿后缀跳"，这是它与朴素
#     逐个 KMP 的本质差别
#
# 主流标准库里没有：C/C++、Java、Go、Rust、Python 均无内建
# （Python 有第三方 pyahocorasick，Rust 有 aho-corasick crate，
#  Go 有 cloudflare/ahocorasick —— 全是第三方，都不是标准库）。
#
# 与 lib/sam.mo 的分工（不是替代）：
#   SAM  预处理**文本**，之后任意查询串 O(m)，回答"是不是子串"
#   AC   预处理**模式集**，之后扫文本 O(n+z)，回答"这些模式在哪"
#   lib/regex.mo 是 Thompson NFA + Pike VM，预处理**模式**、O(n*m)
#
# 转移用稀疏链表存：稠密表要 |states| × 256，本规模下太大。
#   代价是转移查询 O(出度) 而非 O(1)。

var AC_N: i64 = 0;        # 状态数（含根 0）
var AC_NE: i64 = 0;       # 已用边数
var AC_NP: i64 = 0;       # 模式数
var AC_NO: i64 = 0;       # 输出链表节点数
var AC_NM: i64 = 0;       # 本次扫描的匹配数
var AC_ERR: i64 = 0;      # 0 / 1 状态溢出 / 2 边溢出 / 3 输出节点溢出
                          # / 4 匹配溢出 / 5 模式溢出 / 6 未 build
                          # / 7 空模式 / 8 模式总长溢出
var AC_BUILT: i64 = 0;    # 是否已构建
# 计数器（用于验证**结构性质**，不只是"能不能跑出数"）
var AC_NGO: i64 = 0;      # goto 查询次数
var AC_NFB: i64 = 0;      # failure 回退次数（均摊 ≤ n，见下）
var AC_NWR: i64 = 0;      # 输出链表 next 被写的次数（结构守卫）

var AC_HD: [2100] i64 = 0;    # 每个状态的边链表头，-1 = 无
var AC_CH: [4200] i64 = 0;    # 边上的字符
var AC_TO: [4200] i64 = 0;    # 边的目标状态
var AC_NX: [4200] i64 = 0;    # 边链表的下一条
var AC_PA: [2100] i64 = 0;    # trie 父状态（供 fail 定义性质的独立验证）
var AC_PC: [2100] i64 = 0;    # trie 入边字符
var AC_FL: [2100] i64 = 0;    # failure link
var AC_DP: [2100] i64 = 0;    # 深度（根到该状态的串长）
var AC_OH: [2100] i64 = 0;    # 输出链表头，-1 = 无
var AC_OT: [2100] i64 = 0;    # 输出链表尾，-1 = 无
var AC_OL: [512] i64 = 0;     # 输出链表 next，-1 = 尾
var AC_OP: [512] i64 = 0;     # 输出链表上的模式 id
var AC_PL: [64] i64 = 0;      # 模式长度
# 匹配表按**结束位置**升序写入：AC 扫文本时天然就是这个顺序，
#   不能改成按起始位置排 —— 同一结束位置上的短模式起始更靠后，
#   重排会破坏扫描顺序这个可断言的结构性质。
var AC_ME: [8192] i64 = 0;    # 匹配：结束位置（AC 的输出顺序）
var AC_MP: [8192] i64 = 0;    # 匹配：起始位置
var AC_MI: [8192] i64 = 0;    # 匹配：模式 id
var AC_Q: [2100] i64 = 0;     # BFS 队列
var AC_TB: [64] i64 = 0;      # ac_emit 专用临时：本位置的 pid 收集

fn ac_init() -> i64 {
    let i: i64 = 0;
    while i < 2100 {
        AC_HD[i] = -1;
        AC_FL[i] = 0;
        AC_DP[i] = 0;
        AC_OH[i] = -1;
        AC_OT[i] = -1;
        AC_Q[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < 512 {
        AC_OL[i] = -1;
        AC_OP[i] = 0;
        i = i + 1;
    }
    AC_N = 1;
    AC_NE = 0;
    AC_NP = 0;
    AC_NO = 0;
    AC_NM = 0;
    AC_ERR = 0;
    AC_BUILT = 0;
    AC_NGO = 0;
    AC_NFB = 0;
    AC_NWR = 0;
    return 0;
}

# 找 v 经字符 c 的转移；无则 -1
fn ac_go(v: i64, c: i64) -> i64 {
    let e: i64 = AC_HD[v];
    while e >= 0 {
        if AC_CH[e] == c {
            return AC_TO[e];
        }
        e = AC_NX[e];
    }
    return -1;
}

# 设 p 经 c 到 q；已有则改目标，没有则加一条边
fn ac_set(p: i64, c: i64, q: i64) -> i64 {
    let e: i64 = AC_HD[p];
    while e >= 0 {
        if AC_CH[e] == c {
            AC_TO[e] = q;
            return 0;
        }
        e = AC_NX[e];
    }
    e = AC_NE;
    if e >= 4200 {
        AC_ERR = 2;
        return -1;
    }
    AC_CH[e] = c;
    AC_TO[e] = q;
    AC_PA[q] = p;
    AC_PC[q] = c;
    AC_NX[e] = AC_HD[p];
    AC_HD[p] = e;
    AC_NE = AC_NE + 1;
    return 0;
}

# 给状态 v 追加一个输出（模式 pid 在 v 处结束）
fn ac_add_out(v: i64, pid: i64) -> i64 {
    let o: i64 = AC_NO;
    if o >= 512 {
        AC_ERR = 3;
        return -1;
    }
    AC_OP[o] = pid;
    AC_OL[o] = -1;
    AC_NO = AC_NO + 1;
    if AC_OH[v] < 0 {
        AC_OH[v] = o;
    }
    if AC_OT[v] >= 0 {
        AC_OL[AC_OT[v]] = o;
        AC_NWR = AC_NWR + 1;
    }
    AC_OT[v] = o;
    return 0;
}

# 插入一个模式，返回其 id（从 0 起）；出错返回 -1
fn ac_add(p: ptr) -> i64 {
    if AC_NP >= 64 {
        AC_ERR = 5;
        return -1;
    }
    let pid: i64 = AC_NP;
    let v: i64 = 0;
    let i: i64 = 0;
    let c: i64 = p[0];
    if c == 0 {
        AC_ERR = 7;
        return -1;
    }
    while c != 0 {
        if i >= 4200 {
            AC_ERR = 8;
            return -1;
        }
        let g: i64 = ac_go(v, c);
        if g < 0 {
            g = AC_N;
            if g >= 2100 {
                AC_ERR = 1;
                return -1;
            }
            AC_N = AC_N + 1;
            AC_HD[g] = -1;
            AC_OH[g] = -1;
            AC_OT[g] = -1;
            AC_DP[g] = i + 1;
            AC_FL[g] = 0;
            if ac_set(v, c, g) < 0 {
                return -1;
            }
        }
        v = g;
        i = i + 1;
        c = p[i];
    }
    AC_PL[pid] = i;
    AC_NP = AC_NP + 1;
    if ac_add_out(v, pid) < 0 {
        return -1;
    }
    return pid;
}

# 求 v 的孩子 u（经字符 c）的 failure link
#   = 从 AC_FL[v] 出发沿 failure 上溯，第一个有 c 转移的状态的 c 转移
fn ac_fchild(v: i64, c: i64, u: i64) -> i64 {
    let f: i64 = AC_FL[v];
    while f > 0 {
        let g: i64 = ac_go(f, c);
        AC_NGO = AC_NGO + 1;
        if g >= 0 {
            return g;
        }
        f = AC_FL[f];
    }
    let g0: i64 = ac_go(0, c);
    AC_NGO = AC_NGO + 1;
    if g0 >= 0 {
        if g0 != u {
            return g0;
        }
    }
    return 0;
}

# 输出合并：v 继承 AC_FL[v] 的全部输出
#
# 链表节点**共享**而不是复制：BFS 序保证处理 v 时 fail[v] 的链表已
# 定稿，且此后每个节点的 next 至多再被写一次（只有"该状态自己有输出
# 时才写自己链表的当前尾"），所以共享不会互相改写。复制的话最坏
# |states| × |P| 个节点，装不下。
fn ac_merge(v: i64) -> i64 {
    let f: i64 = AC_FL[v];
    if f == v {
        return 0;
    }
    if f < 0 {
        return 0;
    }
    if AC_OH[f] < 0 {
        return 0;
    }
    if AC_OH[v] < 0 {
        AC_OH[v] = AC_OH[f];
        AC_OT[v] = AC_OT[f];
        return 0;
    }
    AC_OL[AC_OT[v]] = AC_OH[f];
    AC_NWR = AC_NWR + 1;
    AC_OT[v] = AC_OT[f];
    return 0;
}

# 构建 failure link 与输出合并
#
# 🔴 BFS 是**输出合并**必需的，不是 failure 链必需的 —— 这一点被
#    变异 M3（队列改 LIFO，即 DFS）实测推翻了：
#      · failure 链：ac_fchild 只依赖 AC_FL[v]，而 v 是 u 的父，
#        父必在子之前处理 ⟹ **DFS 下 fail 链依然正确**。
#      · 输出合并：ac_merge(v) 依赖 AC_FL[v] 的链表**已合并完**，
#        这要求按深度递增处理 ⟹ 只有 BFS 满足。
#    实测 M3 下"fail 定义性质"断言全过，挂的是"随机对照不一致组数"
#    （3 组）。第一版注释写成"DFS 会让 fail[fail[v]] 未确定"，是错的。
fn ac_build() -> i64 {
    AC_FL[0] = 0;
    let qh: i64 = 0;
    let qt: i64 = 0;
    let e: i64 = AC_HD[0];
    while e >= 0 {
        let u: i64 = AC_TO[e];
        AC_FL[u] = 0;
        AC_DP[u] = 1;
        AC_Q[qt] = u;
        qt = qt + 1;
        e = AC_NX[e];
    }
    while qh < qt {
        let v: i64 = AC_Q[qh];
        qh = qh + 1;
        ac_merge(v);
        let f: i64 = AC_HD[v];
        while f >= 0 {
            let c: i64 = AC_CH[f];
            let u: i64 = AC_TO[f];
            AC_FL[u] = ac_fchild(v, c, u);
            AC_DP[u] = AC_DP[v] + 1;
            AC_Q[qt] = u;
            qt = qt + 1;
            f = AC_NX[f];
        }
    }
    AC_BUILT = 1;
    return 0;
}

# 从状态 v 读入字符 c 后的下一状态（含 failure 回退）
#
# 均摊 O(1)：每读入一个字符最多让深度 +1，而每次回退让深度严格减小
# 且深度不为负 ⟹ 回退总次数 ≤ 前进总次数 ≤ n。
# AC_NGO / AC_NFB 就是用来把这个"均摊"钉成可断言的数字的。
fn ac_step(v: i64, c: i64) -> i64 {
    while v > 0 {
        let g: i64 = ac_go(v, c);
        AC_NGO = AC_NGO + 1;
        if g >= 0 {
            return g;
        }
        AC_NFB = AC_NFB + 1;
        v = AC_FL[v];
    }
    let g0: i64 = ac_go(0, c);
    AC_NGO = AC_NGO + 1;
    if g0 >= 0 {
        return g0;
    }
    return 0;
}

# 把状态 v 在 endpos 处结束的全部输出写入匹配表
# 按 pid **升序**写 —— 这样匹配序列是 (pos 升序, pid 升序)，
# 与朴素暴力的枚举顺序逐项一致，可以直接比对，不必再排序。
fn ac_emit(v: i64, endpos: i64) -> i64 {
    let o: i64 = AC_OH[v];
    let n: i64 = 0;
    while o >= 0 {
        if n < 64 {
            AC_TB[n] = AC_OP[o];
            n = n + 1;
        }
        o = AC_OL[o];
    }
    # 选择排序（n ≤ 64）
    #
    # 🔴 本轮第一版写的是插入排序，且用 "j = -1" 当"找到了插入位置"的
    #    退出标志 —— 于是收尾那句 AC_TB[j+1] = x 落到 **位置 0**，
    #    把原值覆盖掉。实测：模式 {\xc8\xe4, \xe4} 扫 "\x01\xc8\xe4\x02"
    #    应得 pid 0 与 pid 1，实得 **两个 pid 1**。不报错、不崩溃，
    #    只是同一位置上的 pid 全部退化成同一个。
    #    改选择排序：不做元素搬移，就没有"退出时 j 已被改写"这回事。
    let i: i64 = 0;
    while i < n {
        let m: i64 = i;
        let j: i64 = i + 1;
        while j < n {
            if AC_TB[j] < AC_TB[m] {
                m = j;
            }
            j = j + 1;
        }
        let t: i64 = AC_TB[i];
        AC_TB[i] = AC_TB[m];
        AC_TB[m] = t;
        i = i + 1;
    }
    let k: i64 = 0;
    while k < n {
        let pid: i64 = AC_TB[k];
        if AC_NM >= 8192 {
            AC_ERR = 4;
            return -1;
        }
        AC_ME[AC_NM] = endpos;
        AC_MP[AC_NM] = endpos - AC_PL[pid] + 1;
        AC_MI[AC_NM] = pid;
        AC_NM = AC_NM + 1;
        k = k + 1;
    }
    return 0;
}

# 扫描文本，返回匹配数
fn ac_scan(t: ptr) -> i64 {
    if AC_BUILT == 0 {
        AC_ERR = 6;
        return -1;
    }
    AC_NM = 0;
    AC_NGO = 0;
    AC_NFB = 0;
    let v: i64 = 0;
    let i: i64 = 0;
    let c: i64 = t[0];
    while c != 0 {
        v = ac_step(v, c);
        if AC_OH[v] >= 0 {
            if ac_emit(v, i) < 0 {
                return -1;
            }
        }
        i = i + 1;
        c = t[i];
    }
    return AC_NM;
}

fn ac_mpos(i: i64) -> i64 {
    return AC_MP[i];
}

fn ac_mid(i: i64) -> i64 {
    return AC_MI[i];
}

fn ac_mend(i: i64) -> i64 {
    return AC_ME[i];
}
