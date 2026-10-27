# 145 —— Aho–Corasick 多模式匹配自动机                    # expect: 0
#
# ── 概念来源 ────────────────────────────────────────────────
#   Aho & Corasick 1975（CACM 18(6)）：goto / failure / output
#   三函数，构造 O(m)，扫描 O(n+z)，与模式个数 k 无关。
#   主流标准库一个都没有：Python 靠 pyahocorasick、Rust 靠
#   aho-corasick crate、Go 靠 cloudflare/ahocorasick —— 全第三方。
#
# ── 本测试钉住的**定量**结论 ────────────────────────────────
#   ① 经典用例 {he,she,his,hers} × "ushers" → 3 个匹配，pid 逐项确定
#   ② 前缀关系 {"a","ab","abc"}：三个都在 pos 0 起始，end 分别 0/1/2
#   ③ **后缀关系 {"ab","b"}**：同一 end 上两个模式 —— 这一条专门盯
#      输出合并（b 是 ab 的真后缀，必须靠 failure 链继承才报得出来）
#   ④ 与朴素暴力**逐项**对照（不是只比总数）20 组随机用例
#   ⑤ 均摊 O(n)：failure 回退总次数 AC_NFB ≤ 文本长度
#   ⑥ 匹配按**结束位置**单调不减（AC 扫描顺序的必然性质）
#   ⑦ 结构：depth(fail[v]) < depth(v)
#   ⑧ 复杂度对照：AC 的 goto 次数 vs 朴素比较次数
#   ⑨ 二进制安全：字节 > 127 也按无符号处理
#
# ── 空转守卫 ────────────────────────────────────────────────
#   随机对照里同时断言"总匹配数 > 0"：若模式与文本不相交，
#   两边都是 0，"逐项一致"就是恒真的 —— 那等于没测。

import "assert.mo";
import "str.mo";
import "ac.mo";

# ── 随机（自写 xorshift64，不引依赖）────────────────────────
var RS: i64 = 0;
fn rnd() -> i64 {
    RS = RS ^ (RS << 13);
    RS = RS ^ (RS >> 7);
    RS = RS ^ (RS << 17);
    if RS < 0 { RS = 0 - RS; }
    return RS;
}
fn rndn(n: i64) -> i64 {
    return rnd() % n;
}

# ── 模式 / 文本缓冲 ─────────────────────────────────────────
# 每个模式占 8 字节（≤3 字符 + NUL），pid 的缓冲区 = PB + pid*8
var PB: [256] i64 = 0;
var TB: [1024] i64 = 0;
var CH: [8] i64 = 0;
var BPA: [16] i64 = 0;

# ── 暴力对照的输出 ──────────────────────────────────────────
var BNM: i64 = 0;
var BME: [8192] i64 = 0;
var BMP: [8192] i64 = 0;
var BMI: [8192] i64 = 0;
var BCM: i64 = 0;      # 朴素比较次数（复杂度对照用）

fn slen(s: ptr) -> i64 {
    let i: i64 = 0;
    while s[i] != 0 { i = i + 1; }
    return i;
}

fn pmake(pid: i64, len: i64) -> ptr {
    let base: i64 = PB;
    let p: ptr = base + pid * 8;
    p[0] = 0;
    let j: i64 = 0;
    while j < len {
        let c: ptr = CH[rndn(4)];
        strcat(p, c);
        j = j + 1;
    }
    return p;
}

# 朴素：按 (end 升序, pid 升序) 枚举，与 AC 的输出顺序一致
fn brute(t: ptr, np: i64, n: i64) -> i64 {
    BNM = 0;
    BCM = 0;
    let e: i64 = 0;
    while e < n {
        let pid: i64 = 0;
        while pid < np {
            let p: ptr = BPA[pid];
            let lp: i64 = slen(p);
            let s: i64 = e - lp + 1;
            if s >= 0 {
                let k: i64 = 0;
                let ok: i64 = 1;
                while k < lp {
                    BCM = BCM + 1;
                    if t[s + k] != p[k] { ok = 0; }
                    k = k + 1;
                }
                if ok == 1 {
                    BME[BNM] = e;
                    BMP[BNM] = s;
                    BMI[BNM] = pid;
                    BNM = BNM + 1;
                }
            }
            pid = pid + 1;
        }
        e = e + 1;
    }
    return BNM;
}

# 逐项比对 AC 与暴力的 (end, start, pid) 三元组
fn cmp3(n: i64) -> i64 {
    if n != BNM { return 1; }
    let i: i64 = 0;
    while i < n {
        if ac_mend(i) != BME[i] { return 1; }
        if ac_mpos(i) != BMP[i] { return 1; }
        if ac_mid(i) != BMI[i] { return 1; }
        i = i + 1;
    }
    return 0;
}

# end 必须单调不减
fn mono(n: i64) -> i64 {
    let i: i64 = 1;
    while i < n {
        if ac_mend(i) < ac_mend(i - 1) { return 1; }
        i = i + 1;
    }
    return 0;
}

fn tclassic() -> i64 {
    ac_init();
    ac_add("he");
    ac_add("she");
    ac_add("his");
    ac_add("hers");
    ac_build();
    let n: i64 = ac_scan("ushers");
    assert_eq("经典用例匹配数", n, 3);
    if n != 3 { return 0; }
    # she@1(end3) · he@2(end3) · hers@2(end5)
    assert_eq("m0 end", ac_mend(0), 3);
    assert_eq("m0 pid", ac_mid(0), 0);
    assert_eq("m0 start", ac_mpos(0), 2);
    assert_eq("m1 end", ac_mend(1), 3);
    assert_eq("m1 pid", ac_mid(1), 1);
    assert_eq("m1 start", ac_mpos(1), 1);
    assert_eq("m2 end", ac_mend(2), 5);
    assert_eq("m2 pid", ac_mid(2), 3);
    assert_eq("m2 start", ac_mpos(2), 2);
    assert_eq("经典用例 err", AC_ERR, 0);
    return 0;
}

fn tprefix() -> i64 {
    ac_init();
    ac_add("a");
    ac_add("ab");
    ac_add("abc");
    ac_build();
    let n: i64 = ac_scan("abc");
    assert_eq("前缀关系匹配数", n, 3);
    if n != 3 { return 0; }
    assert_eq("前缀 m0", ac_mend(0) * 100 + ac_mid(0) * 10 + ac_mpos(0), 0);
    assert_eq("前缀 m1", ac_mend(1) * 100 + ac_mid(1) * 10 + ac_mpos(1), 110);
    assert_eq("前缀 m2", ac_mend(2) * 100 + ac_mid(2) * 10 + ac_mpos(2), 220);
    return 0;
}

# 后缀关系：b 是 ab 的真后缀，必须靠 failure 链继承才报得出来
fn tsuffix() -> i64 {
    ac_init();
    ac_add("ab");
    ac_add("b");
    ac_build();
    let n: i64 = ac_scan("ab");
    assert_eq("后缀关系匹配数", n, 2);
    if n != 2 { return 0; }
    assert_eq("后缀 m0 end", ac_mend(0), 1);
    assert_eq("后缀 m0 pid", ac_mid(0), 0);
    assert_eq("后缀 m0 start", ac_mpos(0), 0);
    assert_eq("后缀 m1 end", ac_mend(1), 1);
    assert_eq("后缀 m1 pid", ac_mid(1), 1);
    assert_eq("后缀 m1 start", ac_mpos(1), 1);
    return 0;
}

fn tbin() -> i64 {
    ac_init();
    ac_add("\xc8\xe4");
    ac_add("\xe4");
    ac_build();
    let n: i64 = ac_scan("\x01\xc8\xe4\x02");
    assert_eq("二进制匹配数", n, 2);
    if n != 2 { return 0; }
    assert_eq("二进制 m0 pid", ac_mid(0), 0);
    assert_eq("二进制 m0 start", ac_mpos(0), 1);
    assert_eq("二进制 m1 pid", ac_mid(1), 1);
    assert_eq("二进制 m1 start", ac_mpos(1), 2);
    return 0;
}

# 随机对照：20 组
fn trand() -> i64 {
    CH[0] = "a"; CH[1] = "b"; CH[2] = "c"; CH[3] = "d";
    RS = 88172645463325252;
    let bad: i64 = 0;
    let tot: i64 = 0;
    let badfb: i64 = 0;
    let badmono: i64 = 0;
    let it: i64 = 0;
    while it < 20 {
        ac_init();
        let np: i64 = 8;
        let pid: i64 = 0;
        while pid < np {
            let p: ptr = pmake(pid, 1 + rndn(3));
            BPA[pid] = p;
            ac_add(p);
            pid = pid + 1;
        }
        ac_build();
        # 文本 = 随机模式 + 随机单字符，保证既有命中也有噪声
        let t: ptr = TB;
        t[0] = 0;
        let k: i64 = 0;
        while k < 60 {
            if rndn(2) == 0 {
                strcat(t, BPA[rndn(np)]);
            }
            strcat(t, CH[rndn(4)]);
            k = k + 1;
        }
        let nt: i64 = slen(t);
        let n: i64 = ac_scan(t);
        tot = tot + n;
        if mono(n) != 0 { badmono = badmono + 1; }
        if AC_NFB > nt { badfb = badfb + 1; }
        brute(t, np, nt);
        if cmp3(n) != 0 { bad = bad + 1; }
        it = it + 1;
    }
    assert_eq("随机对照不一致组数", bad, 0);
    assert_eq("随机对照 回退次数越界组数", badfb, 0);
    assert_eq("随机对照 end单调违反组数", badmono, 0);
    # 空转守卫：总匹配数必须真的 > 0
    if tot < 50 { assert_eq("随机对照 总匹配数(空转守卫)", tot, -1); }
    assert_eq("随机对照 总匹配数>50", tot > 50, 1);
    return 0;
}

# failure link 的**定义性质**（不只是"深度递减"）：
#   fail[v] = v 所代表的串 s 的、最长的、且仍在 trie 中的真后缀
# 这条能直接抓住"构建顺序错了"（BFS 改 DFS）与"fail 恒 0"：
# 前者会让 fail 指向一个**尚未合并完**的后缀，后者会漏掉存在的后缀。
# 只验证"深度递减"抓不到这两种 —— 深度递减太弱。
var FB1: [64] i64 = 0;
var FB2: [64] i64 = 0;

# 从根沿 goto 走串 p，走不通返回 -1
fn walk(p: ptr) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while p[i] != 0 {
        let g: i64 = ac_go(v, p[i]);
        if g < 0 { return -1; }
        v = g;
        i = i + 1;
    }
    return v;
}

# 重建状态 v 代表的串（沿 trie 父指针回溯再反转）
fn rebu(v: i64, b: ptr) -> i64 {
    let n: i64 = 0;
    let x: i64 = v;
    while x > 0 {
        b[n] = AC_PC[x];
        n = n + 1;
        x = AC_PA[x];
    }
    let i: i64 = 0;
    while i < n / 2 {
        let t: i64 = b[i];
        b[i] = b[n - 1 - i];
        b[n - 1 - i] = t;
        i = i + 1;
    }
    b[n] = 0;
    return n;
}

# 逐个状态验证：最长且存在的真后缀 == fail[v]
fn tfailprop() -> i64 {
    ac_init();
    ac_add("abc");
    ac_add("bc");
    ac_add("c");
    ac_add("abd");
    ac_add("bd");
    ac_add("d");
    ac_add("abcd");
    ac_build();
    let b1: ptr = FB1;
    let b2: ptr = FB2;
    let bad: i64 = 0;
    let v: i64 = 1;
    while v < AC_N {
        let n: i64 = rebu(v, b1);
        # 从长到短枚举真后缀，第一个在 trie 中的就是期望的 fail
        let want: i64 = 0;
        # 必须**从长到短**：本轮第一版写成 k 从 1 递增，找到的是
        # 最短的、存在的真后缀，于是 6 个状态里 2 个被误判成违反。
        let k: i64 = n - 1;
        while k >= 1 {
            if want == 0 {
                let j: i64 = 0;
                while j < k {
                    b2[j] = b1[n - k + j];
                    j = j + 1;
                }
                b2[k] = 0;
                let w: i64 = walk(b2);
                if w >= 0 { want = w; }
            }
            k = k - 1;
        }
        if AC_FL[v] != want { bad = bad + 1; }
        v = v + 1;
    }
    assert_eq("fail定义性质违反数", bad, 0);
    return 0;
}

# 输出合并的**定义性质**：状态 v 的输出集合，应当恰好等于
#   "v 代表的串 s 的所有后缀里，正好是某个模式的那些"
# 这条比"随机对照"定位更准 —— 它直接指出是哪个状态的输出错了，
# 而且 M2（不合并）与 M3（DFS 合并乱序）都会挂在它上面。
fn issuf(p: ptr, s: ptr, ns: i64) -> i64 {
    let lp: i64 = slen(p);
    if lp > ns { return 0; }
    let i: i64 = 0;
    while i < lp {
        if s[ns - lp + i] != p[i] { return 0; }
        i = i + 1;
    }
    return 1;
}

fn toutprop() -> i64 {
    ac_init();
    ac_add("abc"); ac_add("bc"); ac_add("c");
    ac_add("abd"); ac_add("bd"); ac_add("d");
    ac_add("abcd");
    ac_build();
    BPA[0] = "abc"; BPA[1] = "bc"; BPA[2] = "c";
    BPA[3] = "abd"; BPA[4] = "bd"; BPA[5] = "d";
    BPA[6] = "abcd";
    let np: i64 = 7;
    let b1: ptr = FB1;
    let bad: i64 = 0;
    let v: i64 = 1;
    while v < AC_N {
        let ns: i64 = rebu(v, b1);
        let want: i64 = 0;
        let pid: i64 = 0;
        while pid < np {
            if issuf(BPA[pid], b1, ns) == 1 { want = want | (1 << pid); }
            pid = pid + 1;
        }
        let got: i64 = 0;
        let o: i64 = AC_OH[v];
        while o >= 0 {
            got = got | (1 << AC_OP[o]);
            o = AC_OL[o];
        }
        if got != want { bad = bad + 1; }
        v = v + 1;
    }
    assert_eq("输出合并定义性质违反数", bad, 0);
    return 0;
}

# 结构：depth(fail[v]) < depth(v)
fn tstruct() -> i64 {
    ac_init();
    ac_add("abc");
    ac_add("bc");
    ac_add("c");
    ac_add("abd");
    ac_add("bd");
    ac_build();
    let bad: i64 = 0;
    let v: i64 = 1;
    while v < AC_N {
        if AC_DP[AC_FL[v]] >= AC_DP[v] { bad = bad + 1; }
        v = v + 1;
    }
    assert_eq("结构 fail深度递减违反数", bad, 0);
    assert_eq("结构 状态数>1", AC_N > 1, 1);
    return 0;
}

# 复杂度对照：AC 的 goto 次数 vs 朴素比较次数
fn tcost() -> i64 {
    CH[0] = "a"; CH[1] = "b"; CH[2] = "c"; CH[3] = "d";
    RS = 12345678901234567;
    ac_init();
    let np: i64 = 16;
    let pid: i64 = 0;
    while pid < np {
        let p: ptr = pmake(pid, 2 + rndn(2));
        BPA[pid] = p;
        ac_add(p);
        pid = pid + 1;
    }
    ac_build();
    let t: ptr = TB;
    t[0] = 0;
    let k: i64 = 0;
    while k < 250 {
        strcat(t, CH[rndn(4)]);
        k = k + 1;
    }
    let nt: i64 = slen(t);
    let n: i64 = ac_scan(t);
    let acq: i64 = AC_NGO + AC_NFB;
    brute(t, np, nt);
    assert_eq("复杂度 文本长度", nt, 250);
    assert_eq("复杂度 朴素匹配数一致", cmp3(n), 0);
    # AC 的查询次数必须与 n 同量级（≤ 4n），朴素则 ≈ n·k·|p|
    assert_eq("复杂度 AC查询≤4n", acq <= 4 * nt, 1);
    assert_eq("复杂度 朴素≥AC的5倍", BCM >= 5 * acq, 1);
    return 0;
}

fn terr() -> i64 {
    ac_init();
    assert_eq("空模式返回-1", ac_add(""), -1);
    assert_eq("空模式 err", AC_ERR, 7);
    let r: i64 = ac_scan("abc");
    assert_eq("未build扫描返回-1", r, -1);
    assert_eq("未build err", AC_ERR, 6);
    return 0;
}

fn main() -> i64 {
    tclassic();
    tprefix();
    tsuffix();
    tbin();
    trand();
    tstruct();
    tfailprop();
    toutprop();
    tcost();
    terr();
    return test_done();
}
