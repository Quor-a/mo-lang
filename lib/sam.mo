import "io.mo";

# 后缀自动机（Suffix Automaton / DAWG）
#
# 参考：
#   Blumer, Ehrenfeucht, Haussler, McConnell 1985
#     "The smallest automaton recognizing the subwords of a text"
#     —— 证明状态数 ≤ 2n-1，且这是最优的
#   Crochemore 1986 —— O(n) 在线构造
#
# 它是什么：识别「文本 T 的全部子串」的最小 DFA。
#   · 状态数 ≤ 2n-1，边数 ≤ 3n-4（对 n ≥ 3），构造 O(n)
#   · 从初态沿字符走到底 ⟺ 该串是 T 的子串，O(m)
#   · 每个状态 v 对应一个 endpos 等价类；|endpos(v)| 就是该类的
#     最长串在 T 中的出现次数
#   · 不同子串个数 = Σ_{v≠初态} (len[v] − len[link[v]])
#
# 主流标准库里没有：C/C++、Java、Go、Rust、Python 均无内建
# （Python 有第三方 pydivsufsort，C++ 有 Boost/SDSL，都不是标准库）。
#
# 与正则的关系：lib/regex.mo 是 Thompson NFA + Pike VM（O(n*m) 模拟）。
# SAM 回答的是另一类问题 —— 给定**固定文本**、任意多**查询串**，
# 预处理 O(n) 后每次查询 O(m)，且与查询串个数无关。
#
# 转移用稀疏链表存：稠密表要 2n × |Σ|，字节字母表下是 2n × 256，
# 太浪费。代价是转移查询 O(出度) 而非 O(1)。

var SA_N: i64 = 0;        # 状态数（含初态 0）
var SA_LAST: i64 = 0;     # 当前整个文本对应的状态
var SA_NE: i64 = 0;       # 已用边数
var SA_TN: i64 = 0;       # 已插入字符数
var SA_ERR: i64 = 0;
var SA_NCL: i64 = 0;      # 克隆次数（守卫：为 0 说明 clone 分支从未被测到）      # 0 / 1 边溢出 / 2 克隆时边溢出 / 3 状态溢出 / 4 克隆时状态溢出

var SA_HD: [4200] i64 = 0;    # 每个状态的边链表头，-1 = 无
var SA_LN: [4200] i64 = 0;    # len：该状态代表的最长串长度
var SA_LK: [4200] i64 = 0;    # 后缀链接
var SA_CN: [4200] i64 = 0;    # |endpos|（需 sam_prep 后才有意义）
var SA_CH: [6300] i64 = 0;    # 边上的字符
var SA_TO: [6300] i64 = 0;    # 边的目标状态
var SA_NX: [6300] i64 = 0;    # 边链表的下一条

# prep 用的临时
var SA_ORD: [4200] i64 = 0;   # 按 len 升序排列的状态
var SA_BKT: [2100] i64 = 0;   # len 的计数桶

fn sam_init() -> i64 {
    let i: i64 = 0;
    while i < 4200 {
        SA_HD[i] = -1;
        SA_LN[i] = 0;
        SA_LK[i] = -1;
        SA_CN[i] = 0;
        SA_ORD[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < 2100 {
        SA_BKT[i] = 0;
        i = i + 1;
    }
    SA_N = 1;
    SA_LAST = 0;
    SA_NE = 0;
    SA_TN = 0;
    SA_ERR = 0;
    SA_NCL = 0;
    return 0;
}

# 找 p 经字符 c 的转移；无则 -1
fn sam_get(p: i64, c: i64) -> i64 {
    let e: i64 = SA_HD[p];
    while e >= 0 {
        if SA_CH[e] == c {
            return SA_TO[e];
        }
        e = SA_NX[e];
    }
    return -1;
}

# 设 p 经 c 到 q；已有则改目标，没有则加一条边
fn sam_set(p: i64, c: i64, q: i64) -> i64 {
    let e: i64 = SA_HD[p];
    while e >= 0 {
        if SA_CH[e] == c {
            SA_TO[e] = q;
            return 0;
        }
        e = SA_NX[e];
    }
    e = SA_NE;
    if e >= 6300 {
        SA_ERR = 1;
        return -1;
    }
    SA_CH[e] = c;
    SA_TO[e] = q;
    SA_NX[e] = SA_HD[p];
    SA_HD[p] = e;
    SA_NE = SA_NE + 1;
    return 0;
}

# 把 src 的全部转移复制给 dst
# 🔴 这是克隆最容易漏的一步：漏了之后 clone 状态没有出边，
#    从它出发的查询全部提前失败，而构造过程本身不报错。
fn sam_clone_tr(dst: i64, src: i64) -> i64 {
    SA_HD[dst] = -1;
    let e: i64 = SA_HD[src];
    while e >= 0 {
        let f: i64 = SA_NE;
        if f >= 6300 {
            SA_ERR = 2;
            return -1;
        }
        SA_CH[f] = SA_CH[e];
        SA_TO[f] = SA_TO[e];
        SA_NX[f] = SA_HD[dst];
        SA_HD[dst] = f;
        SA_NE = SA_NE + 1;
        e = SA_NX[e];
    }
    return 0;
}

fn sam_extend(c: i64) -> i64 {
    let cur: i64 = SA_N;
    if cur >= 4200 {
        SA_ERR = 3;
        return -1;
    }
    SA_N = SA_N + 1;
    SA_LN[cur] = SA_LN[SA_LAST] + 1;
    SA_HD[cur] = -1;
    SA_LK[cur] = -1;
    SA_CN[cur] = 1;

    let p: i64 = SA_LAST;
    while p >= 0 {
        if sam_get(p, c) >= 0 {
            break;
        }
        if sam_set(p, c, cur) != 0 {
            return -1;
        }
        p = SA_LK[p];
    }

    if p < 0 {
        SA_LK[cur] = 0;
        SA_LAST = cur;
        SA_TN = SA_TN + 1;
        return cur;
    }

    let q: i64 = sam_get(p, c);
    if SA_LN[p] + 1 == SA_LN[q] {
        SA_LK[cur] = q;
        SA_LAST = cur;
        SA_TN = SA_TN + 1;
        return cur;
    }

    let cl: i64 = SA_N;
    if cl >= 4200 {
        SA_ERR = 4;
        return -1;
    }
    SA_N = SA_N + 1;
    SA_LN[cl] = SA_LN[p] + 1;
    SA_CN[cl] = 0;
    SA_LK[cl] = SA_LK[q];
    SA_NCL = SA_NCL + 1;
    if sam_clone_tr(cl, q) != 0 {
        return -1;
    }
    while p >= 0 {
        if sam_get(p, c) != q {
            break;
        }
        if sam_set(p, c, cl) != 0 {
            return -1;
        }
        p = SA_LK[p];
    }
    SA_LK[q] = cl;
    SA_LK[cur] = cl;
    SA_LAST = cur;
    SA_TN = SA_TN + 1;
    return cur;
}

# 用 s 的前 n 个字节构造
fn sam_build(s: ptr, n: i64) -> i64 {
    sam_init();
    let i: i64 = 0;
    while i < n {
        if sam_extend(s[i]) < 0 {
            return -1;
        }
        i = i + 1;
    }
    return SA_N;
}

# 判子串：能走完就是子串，返回落到的状态；否则 -1
fn sam_find(t: ptr, m: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while i < m {
        let nx: i64 = sam_get(v, t[i]);
        if nx < 0 {
            return -1;
        }
        v = nx;
        i = i + 1;
    }
    return v;
}

# 子串判定（0/1）
fn sam_has(t: ptr, m: i64) -> i64 {
    if sam_find(t, m) >= 0 {
        return 1;
    }
    return 0;
}

# 按 len 计数排序，再沿拓扑序把 cnt 累加到后缀链接上
# cnt[v] 最终 = |endpos(v)| = 该状态最长串的出现次数
fn sam_prep() -> i64 {
    let i: i64 = 0;
    while i < 2100 {
        SA_BKT[i] = 0;
        i = i + 1;
    }
    i = 0;
    while i < SA_N {
        let l: i64 = SA_LN[i];
        if l < 2100 {
            SA_BKT[l] = SA_BKT[l] + 1;
        }
        i = i + 1;
    }
    i = 1;
    while i < 2100 {
        SA_BKT[i] = SA_BKT[i] + SA_BKT[i - 1];
        i = i + 1;
    }
    # 桶后缀和 → 稳定排序（按 len 升序），倒着放保证稳定性
    i = SA_N - 1;
    while i >= 0 {
        let l: i64 = SA_LN[i];
        SA_BKT[l] = SA_BKT[l] - 1;
        SA_ORD[SA_BKT[l]] = i;
        i = i - 1;
    }
    # 按 len 降序遍历：cnt[link[v]] += cnt[v]
    i = SA_N - 1;
    while i > 0 {
        let v: i64 = SA_ORD[i];
        let f: i64 = SA_LK[v];
        if f >= 0 {
            SA_CN[f] = SA_CN[f] + SA_CN[v];
        }
        i = i - 1;
    }
    return 0;
}

# 出现次数（重叠计数）。未出现返回 0。
fn sam_occ(t: ptr, m: i64) -> i64 {
    let v: i64 = sam_find(t, m);
    if v < 0 {
        return 0;
    }
    return SA_CN[v];
}

# 不同子串个数 = Σ (len[v] − len[link[v]])
fn sam_nsub() -> i64 {
    let s: i64 = 0;
    let v: i64 = 1;
    while v < SA_N {
        s = s + SA_LN[v] - SA_LN[SA_LK[v]];
        v = v + 1;
    }
    return s;
}

# 最长重复子串的长度：出现 ≥2 次的状态里 len 最大的
# 注意：直接取 max len(v) s.t. cnt[v] ≥ 2 是对的 ——
# 状态 v 代表的串里最长那个（长度 len[v]）出现 cnt[v] 次。
fn sam_longest_rep() -> i64 {
    let best: i64 = 0;
    let v: i64 = 1;
    while v < SA_N {
        if SA_CN[v] >= 2 {
            if SA_LN[v] > best {
                best = SA_LN[v];
            }
        }
        v = v + 1;
    }
    return best;
}

# 最长公共子串（把 B 喂进 A 的自动机，经典 O(|A|+|B|) 做法）
# 这里简化：返回 A、B 的最长公共子串长度，用 A 的 SAM 走 B。
var SA_LCSL: i64 = 0;
var SA_LCSV: i64 = 0;
fn sam_lcs_len(b: ptr, m: i64) -> i64 {
    let v: i64 = 0;
    let l: i64 = 0;
    let best: i64 = 0;
    let i: i64 = 0;
    while i < m {
        let c: i64 = b[i];
        let nx: i64 = sam_get(v, c);
        if nx >= 0 {
            v = nx;
            l = l + 1;
        } else {
            while v >= 0 {
                if sam_get(v, c) >= 0 {
                    break;
                }
                v = SA_LK[v];
            }
            if v < 0 {
                v = 0;
                l = 0;
            } else {
                l = SA_LN[v] + 1;
                v = sam_get(v, c);
            }
        }
        if l > best {
            best = l;
        }
        i = i + 1;
    }
    SA_LCSL = best;
    return best;
}
