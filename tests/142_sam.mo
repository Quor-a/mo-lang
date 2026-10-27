# 142 —— 后缀自动机（SAM）
#
# 概念出处：Blumer et al. 1985「识别文本全部子串的最小自动机」+ Crochemore
# 1986 的 O(n) 在线构造。主流语言标准库均无内建。
#
# 本文件的关键是**每条性质都有独立参照**：SAM 给出的答案全部与暴力算法
# 对照。只有"两边算出来一样"才算验证 —— SAM 自己算出来的数字（状态数、
# nsub、出现次数）不能自己证明自己。
import "assert.mo";
import "sam.mo";

# ---------------- 暴力参照（完全独立于 SAM） ----------------

# 子串判定：O(n*m) 逐个起点比较
fn brute_has(s: ptr, n: i64, t: ptr, m: i64) -> i64 {
    if m > n {
        return 0;
    }
    let i: i64 = 0;
    while i + m <= n {
        let j: i64 = 0;
        let ok: i64 = 1;
        while j < m {
            if s[i + j] != t[j] {
                ok = 0;
                break;
            }
            j = j + 1;
        }
        if ok == 1 {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

# 出现次数：重叠计数
fn brute_occ(s: ptr, n: i64, t: ptr, m: i64) -> i64 {
    if m > n {
        return 0;
    }
    let c: i64 = 0;
    let i: i64 = 0;
    while i + m <= n {
        let j: i64 = 0;
        let ok: i64 = 1;
        while j < m {
            if s[i + j] != t[j] {
                ok = 0;
                break;
            }
            j = j + 1;
        }
        if ok == 1 {
            c = c + 1;
        }
        i = i + 1;
    }
    return c;
}

# 最长公共前缀
fn lcp(a: ptr, b: ptr, la: i64, lb: i64) -> i64 {
    let k: i64 = 0;
    while k < la {
        if k >= lb {
            break;
        }
        if a[k] != b[k] {
            break;
        }
        k = k + 1;
    }
    return k;
}

# 最长重复子串长度：枚举所有 (i,j) 对取 LCP 最大
fn brute_lrep(s: ptr, n: i64) -> i64 {
    let best: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let j: i64 = i + 1;
        while j < n {
            let k: i64 = 0;
            while i + k < n {
                if s[i + k] != s[j + k] {
                    break;
                }
                k = k + 1;
            }
            if k > best {
                best = k;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return best;
}

# ---- 不同子串个数：枚举全部子串 → 存 → 排序 → 去重（精确，无哈希碰撞）----
var BF: [20000] i64 = 0;
var BO: [1200] i64 = 0;
var BL: [1200] i64 = 0;
var BI: [1200] i64 = 0;
var BN: i64 = 0;
var BFP: i64 = 0;

fn sub_lt(x: i64, y: i64) -> i64 {
    let lx: i64 = BL[x];
    let ly: i64 = BL[y];
    let l: i64 = lx;
    if ly < lx {
        l = ly;
    }
    let k: i64 = 0;
    while k < l {
        if BF[BO[x] + k] != BF[BO[y] + k] {
            if BF[BO[x] + k] < BF[BO[y] + k] {
                return 1;
            }
            return 0;
        }
        k = k + 1;
    }
    if lx < ly {
        return 1;
    }
    return 0;
}

# 不同子串个数（精确）
fn brute_nsub(s: ptr, n: i64) -> i64 {
    BN = 0;
    BFP = 0;
    let i: i64 = 0;
    while i < n {
        let j: i64 = i + 1;
        while j <= n {
            BO[BN] = BFP;
            BL[BN] = j - i;
            BI[BN] = BN;
            let k: i64 = i;
            while k < j {
                BF[BFP] = s[k];
                BFP = BFP + 1;
                k = k + 1;
            }
            BN = BN + 1;
            j = j + 1;
        }
        i = i + 1;
    }
    # 插入排序（按子串内容）
    i = 1;
    while i < BN {
        let cur: i64 = BI[i];
        let j2: i64 = i - 1;
        while j2 >= 0 {
            if sub_lt(BI[j2], cur) == 1 {
                break;
            }
            BI[j2 + 1] = BI[j2];
            j2 = j2 - 1;
        }
        BI[j2 + 1] = cur;
        i = i + 1;
    }
    let d: i64 = 0;
    if BN > 0 {
        d = 1;
    }
    i = 1;
    while i < BN {
        let a: i64 = BI[i - 1];
        let b: i64 = BI[i];
        let same: i64 = 1;
        if BL[a] != BL[b] {
            same = 0;
        } else {
            let k2: i64 = 0;
            while k2 < BL[a] {
                if BF[BO[a] + k2] != BF[BO[b] + k2] {
                    same = 0;
                    break;
                }
                k2 = k2 + 1;
            }
        }
        if same == 0 {
            d = d + 1;
        }
        i = i + 1;
    }
    return d;
}

# 最长公共子串（暴力）
fn brute_lcs(a: ptr, na: i64, b: ptr, nb: i64) -> i64 {
    let best: i64 = 0;
    let i: i64 = 0;
    while i < na {
        let j: i64 = 0;
        while j < nb {
            let k: i64 = 0;
            while i + k < na {
                if j + k >= nb {
                    break;
                }
                if a[i + k] != b[j + k] {
                    break;
                }
                k = k + 1;
            }
            if k > best {
                best = k;
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return best;
}

# ---------------- 被测文本 ----------------

var TX: [64] byte = 0;
var TN: i64 = 0;

fn settext(s: ptr) -> i64 {
    TN = 0;
    let i: i64 = 0;
    while s[i] != 0 {
        TX[i] = s[i];
        i = i + 1;
    }
    TN = i;
    TX[TN] = 0;
    return TN;
}

# 固定种子 LCG，生成小字母表文本（重复多 ⇒ 触发 clone 路径）
var SEED: i64 = 0;
fn rnd(k: i64) -> i64 {
    SEED = SEED * 6364136223846793005 + 1442695040888963407;
    let v: i64 = SEED;
    if v < 0 {
        v = v - 1;
    }
    # 取高位（低位质量差）
    v = v / 65536;
    if v < 0 {
        v = 0 - v;
    }
    let r: i64 = v % k;
    if r < 0 {
        r = r + k;
    }
    return r;
}

var RT: [64] byte = 0;
var QB: [40] byte = 0;

fn qclr() -> i64 {
    let i: i64 = 0;
    while i < 40 {
        QB[i] = 0;
        i = i + 1;
    }
    return 0;
}
fn gen_text(n: i64, k: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        let r: i64 = rnd(k);
        RT[i] = 97 + r;
        i = i + 1;
    }
    RT[n] = 0;
    return n;
}

# ---------------- 测试 ----------------

fn t_tiny() -> i64 {
    settext("a");
    sam_build(TX, TN);
    assert_eq("a: 状态数", SA_N, 2);
    assert_eq("a: 不同子串数", sam_nsub(), 1);

    settext("aaaa");
    sam_build(TX, TN);
    assert_eq("aaaa: 状态数", SA_N, 5);
    assert_eq("aaaa: 不同子串数", sam_nsub(), 4);

    settext("abab");
    sam_build(TX, TN);
    assert_eq("abab: 状态数", SA_N, 5);
    assert_eq("abab: 不同子串数", sam_nsub(), 7);

    # 全不同字符：无 clone，状态数 = n+1，不同子串数 = n(n+1)/2
    settext("abcdefghij");
    sam_build(TX, TN);
    assert_eq("10 个不同字符: 状态数", SA_N, 11);
    assert_eq("10 个不同字符: 不同子串数", sam_nsub(), 55);
    assert_eq("10 个不同字符: 无 clone（边数=n+...）", SA_ERR, 0);

    # 空文本
    sam_build(TX, 0);
    assert_eq("空文本: 状态数", SA_N, 1);
    assert_eq("空文本: 不同子串数", sam_nsub(), 0);
    return 0;
}

# 状态数上界 2n-1 / 边数上界 3n-4（Blumer 1985 的两个界）
fn t_bounds() -> i64 {
    SEED = 12345;
    let worst_s: i64 = 0;
    let worst_e: i64 = 0;
    let it: i64 = 0;
    while it < 12 {
        let n: i64 = 20 + it * 3;
        gen_text(n, 3);
        let i: i64 = 0;
        while i < n {
            TX[i] = RT[i];
            i = i + 1;
        }
        TN = n;
        TX[n] = 0;
        sam_build(TX, TN);
        if SA_N > worst_s {
            worst_s = SA_N;
        }
        if SA_NE > worst_e {
            worst_e = SA_NE;
        }
        # 每个文本都必须满足界
        if SA_N > 2 * n - 1 {
            assert_eq("状态数超 2n-1", SA_N, 2 * n - 1);
        }
        if n >= 3 {
            if SA_NE > 3 * n - 4 {
                assert_eq("边数超 3n-4", SA_NE, 3 * n - 4);
            }
        }
        assert_eq("构造无溢出", SA_ERR, 0);
        it = it + 1;
    }
    # 守卫：确实构造到了多个状态（否则上界断言是空转）
    if worst_s < 20 {
        assert_eq("worst_s 太小（空转）", worst_s, 20);
    }
    print("  最坏状态数=");
    print_i64(worst_s);
    print(" 最坏边数=");
    print_i64(worst_e);
    print_nl();
    return 0;
}

# 子串判定 vs 暴力
fn t_find() -> i64 {
    SEED = 999;
    settext("abacabadabacaba");
    sam_build(TX, TN);
    let bad: i64 = 0;
    let tot: i64 = 0;
    let hit: i64 = 0;
    let t: i64 = 0;
    while t < 200 {
        let m: i64 = 1 + rnd(5);
        qclr();
        let i: i64 = 0;
        while i < m {
            QB[i] = 97 + rnd(4);
            i = i + 1;
        }
        QB[m] = 0;
        let g: i64 = sam_has(QB, m);
        let w: i64 = brute_has(TX, TN, QB, m);
        tot = tot + 1;
        if g == 1 {
            hit = hit + 1;
        }
        if g != w {
            bad = bad + 1;
        }
        t = t + 1;
    }
    assert_eq("子串判定 与暴力不一致数", bad, 0);
    # 守卫：查询里必须既有命中也有未命中，否则全 0 也过
    if hit < 20 {
        assert_eq("命中数过少（空转）", hit, 20);
    }
    if tot - hit < 5 {
        assert_eq("未命中数过少（空转）", tot - hit, 5);
    }
    print("  查询 ");
    print_i64(tot);
    print(" 次，命中 ");
    print_i64(hit);
    print_nl();
    return 0;
}

# 出现次数 vs 暴力（重叠计数）
fn t_occ() -> i64 {
    SEED = 4242;
    settext("abacabadabacaba");
    sam_build(TX, TN);
    sam_prep();
    let bad: i64 = 0;
    let sum: i64 = 0;
    let t: i64 = 0;
    while t < 150 {
        let m: i64 = 1 + rnd(4);
        qclr();
        let i: i64 = 0;
        while i < m {
            QB[i] = 97 + rnd(4);
            i = i + 1;
        }
        QB[m] = 0;
        let g: i64 = sam_occ(QB, m);
        let w: i64 = brute_occ(TX, TN, QB, m);
        sum = sum + g;
        if g != w {
            bad = bad + 1;
        }
        t = t + 1;
    }
    assert_eq("出现次数 与暴力不一致数", bad, 0);
    if sum < 50 {
        assert_eq("出现次数总和过少（空转）", sum, 50);
    }
    # 覆盖**所有**子串而不只是随机抽样 —— 随机查询可能一次都碰不到
    # 克隆状态，于是只影响克隆状态的变异看不出来（M5 就这么溜过一次）。
    let allbad: i64 = 0;
    let alln: i64 = 0;
    let i2: i64 = 0;
    while i2 < TN {
        let j2: i64 = i2 + 1;
        while j2 <= TN {
            qclr();
            let k2: i64 = 0;
            while k2 < j2 - i2 {
                QB[k2] = TX[i2 + k2];
                k2 = k2 + 1;
            }
            let gg: i64 = sam_occ(QB, j2 - i2);
            let ww: i64 = brute_occ(TX, TN, QB, j2 - i2);
            alln = alln + 1;
            if gg != ww {
                allbad = allbad + 1;
            }
            j2 = j2 + 1;
        }
        i2 = i2 + 1;
    }
    assert_eq("全部子串 出现次数 与暴力不一致数", allbad, 0);
    if alln < 100 {
        assert_eq("枚举子串数过少（空转）", alln, 100);
    }
    print("  枚举子串 ");
    print_i64(alln);
    print(" 个");
    print_nl();

    # 🔴 "abacabadabacaba" 的构造实测 **SA_NCL = 0**：一次克隆都没发生
    # （16 个状态，每个新字符都恰好满足 len[p]+1 == len[q]）。
    # 于是凡只影响 clone 状态的代码路径，在上面全部测不到 ——
    # 这就是 M5（clone 的 cnt 初值）一开始溜过去的原因。
    # 换一个真正会克隆的文本，并把"确实克隆了"本身写成断言。
    SEED = 20261017;
    gen_text(20, 2);
    let c1: i64 = 0;
    while c1 < 20 {
        TX[c1] = RT[c1];
        c1 = c1 + 1;
    }
    TN = 20;
    TX[20] = 0;
    sam_build(TX, TN);
    if SA_NCL < 1 {
        assert_eq("该文本未触发克隆（空转）", SA_NCL, 1);
    }
    sam_prep();
    let cbad: i64 = 0;
    let cn: i64 = 0;
    let i3: i64 = 0;
    while i3 < TN {
        let j3: i64 = i3 + 1;
        while j3 <= TN {
            qclr();
            let k3: i64 = 0;
            while k3 < j3 - i3 {
                QB[k3] = TX[i3 + k3];
                k3 = k3 + 1;
            }
            let g3: i64 = sam_occ(QB, j3 - i3);
            let w3: i64 = brute_occ(TX, TN, QB, j3 - i3);
            cn = cn + 1;
            if g3 != w3 {
                cbad = cbad + 1;
            }
            j3 = j3 + 1;
        }
        i3 = i3 + 1;
    }
    assert_eq("克隆文本 全部子串 occ 与暴力不一致数", cbad, 0);
    print("  克隆次数=");
    print_i64(SA_NCL);
    print(" 枚举子串 ");
    print_i64(cn);
    print(" 个");
    print_nl();

    # 回到无克隆文本做单点核对
    # 单点核对要在**原文本**上做（sam 刚被克隆文本重建过）
    settext("abacabadabacaba");
    sam_build(TX, TN);
    sam_prep();
    qclr();
    QB[0] = 97;
    assert_eq("'a' 出现次数", sam_occ(QB, 1), 8);
    qclr();
    QB[0] = 97;
    QB[1] = 98;
    QB[2] = 97;
    assert_eq("'aba' 出现次数", sam_occ(QB, 3), 4);
    return 0;
}

# 不同子串数 vs 精确枚举
fn t_nsub() -> i64 {
    SEED = 777;
    let it: i64 = 0;
    while it < 6 {
        let n: i64 = 12 + it * 3;
        gen_text(n, 3);
        let i: i64 = 0;
        while i < n {
            TX[i] = RT[i];
            i = i + 1;
        }
        TN = n;
        TX[n] = 0;
        sam_build(TX, TN);
        let g: i64 = sam_nsub();
        let w: i64 = brute_nsub(TX, TN);
        if g != w {
            print("  nsub 不一致 n=");
            print_i64(n);
            print(" sam=");
            print_i64(g);
            print(" brute=");
            print_i64(w);
            print_nl();
        }
        assert_eq("nsub 与精确枚举一致", g, w);
        it = it + 1;
    }
    # 经典值：全相同字符只有 n 个不同子串
    settext("aaaaaaaaaa");
    sam_build(TX, TN);
    assert_eq("10 个 a 的不同子串数", sam_nsub(), 10);
    return 0;
}

# 最长重复子串 vs 暴力 LCP
fn t_lrep() -> i64 {
    SEED = 31337;
    let it: i64 = 0;
    while it < 8 {
        let n: i64 = 14 + it * 2;
        gen_text(n, 3);
        let i: i64 = 0;
        while i < n {
            TX[i] = RT[i];
            i = i + 1;
        }
        TN = n;
        TX[n] = 0;
        sam_build(TX, TN);
        sam_prep();
        let g: i64 = sam_longest_rep();
        let w: i64 = brute_lrep(TX, TN);
        if g != w {
            print("  lrep 不一致 n=");
            print_i64(n);
            print(" sam=");
            print_i64(g);
            print(" brute=");
            print_i64(w);
            print_nl();
        }
        assert_eq("最长重复子串 与暴力一致", g, w);
        it = it + 1;
    }
    return 0;
}

# 最长公共子串 vs 暴力
fn t_lcs() -> i64 {
    SEED = 555;
    let it: i64 = 0;
    while it < 6 {
        let na: i64 = 16 + it;
        gen_text(na, 3);
        let i: i64 = 0;
        while i < na {
            TX[i] = RT[i];
            i = i + 1;
        }
        TX[na] = 0;
        TN = na;
        sam_build(TX, TN);
        let nb: i64 = 14 + it;
        gen_text(nb, 3);
        let g: i64 = sam_lcs_len(RT, nb);
        let w: i64 = brute_lcs(TX, na, RT, nb);
        if g != w {
            print("  lcs 不一致 sam=");
            print_i64(g);
            print(" brute=");
            print_i64(w);
            print_nl();
        }
        assert_eq("最长公共子串 与暴力一致", g, w);
        it = it + 1;
    }
    return 0;
}

fn main() -> i64 {
    print("== 后缀自动机 ==");
    print_nl();
    t_tiny();
    print("  状态数/边数上界");
    print_nl();
    t_bounds();
    print("  子串判定 vs 暴力");
    print_nl();
    t_find();
    print("  出现次数 vs 暴力");
    print_nl();
    t_occ();
    print("  不同子串数 vs 精确枚举");
    print_nl();
    t_nsub();
    print("  最长重复子串 vs 暴力");
    print_nl();
    t_lrep();
    print("  最长公共子串 vs 暴力");
    print_nl();
    t_lcs();
    return test_done();
}
