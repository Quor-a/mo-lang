#!/usr/bin/env python3
"""genunorm —— 生成 lib/uninorm.mo（NFC / NFD，UAX #15）。

数据全部来自 Python 的 unicodedata（Unicode 13.0.0）：
  - UN_SEG  覆盖段
  - UN_CCC  规范组合类（Canonical Combining Class）区间表（只记 ccc != 0 的连续段）
  - UN_DEC  规范分解表（canonical decomposition，1→1 或 1→2）
  - UN_CMP  规范组合表（由 UN_DEC 反推，排除 singleton 与 CompositionExclusions）

⚠️ 表本身来自 Python，所以「表内容与 Python 不一致」这类错误检不出来；
   tools/unormtest.sh 检的是**算法**（递归分解、规范排序、阻挡规则、Hangul），
   表只是它的输入。这一点在 docs/uninorm.md 里写明，不假装全链路独立。
"""

import unicodedata as ud
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SEGS = [(0x0000, 0x0180),   # Latin-1 + Latin Extended-A
        (0x0300, 0x0370),   # Combining Diacritical Marks
        (0x0384, 0x0400),   # Greek（含 tonos / dialytika tonos）
        (0x1E00, 0x1F00),   # Latin Extended Additional（含二级分解）
        (0x1100, 0x1200),   # Hangul Jamo
        (0xAC00, 0xD7A4)]   # Hangul Syllables

# UAX #15 CompositionExclusions.txt 中落在本覆盖范围内的码点
# （singleton 分解天然被排除：组合只收录 1→2 的分解）
EXCL = {0x340, 0x341, 0x343, 0x344, 0x387}


def covered(c):
    return any(lo <= c < hi for lo, hi in SEGS)


def build():
    # ---- CCC 区间 ----
    runs = []
    for c in range(0x0300, 0x0370):
        v = ud.combining(chr(c))
        if v:
            if runs and runs[-1][2] == v and runs[-1][1] == c - 1:
                runs[-1][1] = c
            else:
                runs.append([c, c, v])
    assert max(r[2] for r in runs) <= 255

    # ---- 规范分解 ----
    dec = {}
    for lo, hi in SEGS:
        if lo in (0x1100, 0xAC00):
            continue          # Hangul 走算法，不进表
        for c in range(lo, hi):
            d = ud.decomposition(chr(c))
            if d and not d.startswith('<'):
                parts = [int(x, 16) for x in d.split()]
                assert 1 <= len(parts) <= 2, hex(c)
                dec[c] = parts

    # ---- 规范组合（反推）----
    cmp = {}
    for k, v in dec.items():
        if len(v) == 2 and k not in EXCL:
            cmp[(v[0], v[1])] = k

    return runs, dec, cmp


def emit(runs, dec, cmp):
    L = []
    A = L.append
    A('# uninorm —— Unicode 规范化 NFC / NFD（UAX #15）')
    A('#')
    A('# ── 概念 ────────────────────────────────────────────────────────────')
    A('#   Unicode 标准的「规范等价」：两个字符序列若规范等价，就应当被一视同仁')
    A('#   —— 显示、比较、检索都该给同一个结果。U+00C5（Å）与 U+0041 U+030A')
    A('#   （A + 上圆环）是同一个字符的两种写法，字节不同、语义相同。')
    A('#   UAX #15 定义了四条规范化形式：')
    A('#     NFD  规范分解   —— 把预组合字符拆成基字符 + 组合记号')
    A('#     NFC  规范分解后重组 —— 尽量合回预组合形式')
    A('#     NFKD / NFKC      —— 同上但用**兼容**分解（本实现不做）')
    A('#   NFC 是 Web 与文件系统的通行形式（W3C Character Model、Apple HFS+）。')
    A('#')
    A('#   为什么算「概念」而不是「工程惯例」：C / C++ 标准库完全没有（只能靠 ICU）；')
    A('#   Go 与 Rust 要装第三方（x/text、unicode-normalization）；Java 有')
    A('#   java.text.Normalizer、Python 有 unicodedata.normalize，但都绑在运行时')
    A('#   自带的完整表上、不可裁剪。可嵌入的纯数据表实现基本是空白。')
    A('#')
    A('# ── 四条规则（本实现的全部难点）────────────────────────────────────')
    A('#   1. 递归分解：U+1E14 → U+0112 U+0300，而 U+0112 → U+0045 U+0304。')
    A('#      不递归就得不到 NFD(U+1E14) = 0045 0304 0300。')
    A('#   2. 规范排序：每个「基字符 + 后继组合记号」段内按 ccc **稳定**排序。')
    A('#      稳定是硬要求 —— 同 ccc 的两个记号不能互换位置。')
    A('#   3. 阻挡规则（blocking）：记号 C 若前面存在 ccc(B) >= ccc(C) 的记号 B，')
    A('#      则 C **不得**与基字符组合。这是最容易被漏掉、漏了又不报错的一条。')
    A('#   4. Hangul 算法化：U+AC00..U+D7A3 的 11172 个音节不进表，按')
    A('#      UAX #15 的公式现算 —— 这是 Unicode 里唯一「用算法代替表」的地方。')
    A('#')
    A('# ── 数据结构：三项打包进一个 i64 ────────────────────────────────────')
    A('#     UN_CCC   bit 0..15 lo / bit 16..31 hi / bit 32..39 ccc')
    A('#     UN_DEC   bit 0..15 cp / bit 16..31 d0 / bit 32..47 d1（0 = singleton）')
    A('#     UN_CMP   bit 0..31 键(d0<<16|d1) / bit 32..47 组合结果')
    A('#')
    A('# ── 覆盖范围（诚实标注，不假装全 Unicode）───────────────────────────')
    for lo, hi in SEGS:
        A('#     U+%04X..U+%04X' % (lo, hi - 1))
    A('#   **之外一律返回 UN_UNK 并置 -1**，不静默给一个像样的答案。')
    A('#   表由 Python 3.10 的 unicodedata（Unicode 13.0.0）导出，见 tools/genunorm.py。')
    A('')
    A('var UN_NC: i64 = 0;      # CCC 区间表项数')
    A('var UN_ND: i64 = 0;      # 分解表项数')
    A('var UN_NP: i64 = 0;      # 组合表项数')
    A('var UN_UNK: i64 = 0;     # 最近一次调用遇到覆盖范围外的码点')
    A('var UN_OVF: i64 = 0;     # 缓冲区溢出')
    A('var UN_NREC: i64 = 0;    # 递归展开次数（二级及以上分解）')
    A('var UN_MAXD: i64 = 0;    # 最大分解深度（1 = 未递归）')
    A('')
    A('var UN_SEG: [%d] i64 = 0;' % (len(SEGS) * 2))
    A('var UN_CCC: [%d] i64 = 0;' % len(runs))
    A('var UN_DEC: [%d] i64 = 0;' % len(dec))
    A('var UN_CMP: [%d] i64 = 0;' % len(cmp))
    A('')
    A('var UN_IN:  [64] i64 = 0;    # 输入码点')
    A('var UN_NN: i64 = 0;          # 输入长度')
    A('var UN_ST:  [64] i64 = 0;    # 分解用栈')
    A('var UN_SF:  [64] i64 = 0;    # 栈元素的分解深度')
    A('var UN_SP: i64 = 0;')
    A('var UN_M: i64 = 0;           # 全分解结果长度')
    A('var UN_D1: [512] i64 = 0;    # 全分解结果（排序前）')
    A('var UN_D2: [512] i64 = 0;    # NFD 结果')
    A('var UN_OUT: [512] i64 = 0;   # NFC 结果')
    A('var UN_LN: i64 = 0;          # NFD 长度')
    A('var UN_LC: i64 = 0;          # NFC 长度')
    A('var UN_SV: [512] i64 = 0;    # 快照（幂等性测试用）')
    A('var UN_SN: i64 = 0;')
    A('')
    A('fn un_init() -> i64 {')
    for i, (lo, hi) in enumerate(SEGS):
        A('    UN_SEG[%d] = %d;' % (i * 2, lo))
        A('    UN_SEG[%d] = %d;' % (i * 2 + 1, hi))
    A('    UN_NC = %d;' % len(runs))
    for i, (lo, hi, v) in enumerate(runs):
        A('    UN_CCC[%d] = %d;' % (i, lo | (hi << 16) | (v << 32)))
    A('    UN_ND = %d;' % len(dec))
    for i, c in enumerate(sorted(dec)):
        v = dec[c]
        d0 = v[0]
        d1 = v[1] if len(v) == 2 else 0
        A('    UN_DEC[%d] = %d;' % (i, c | (d0 << 16) | (d1 << 32)))
    A('    UN_NP = %d;' % len(cmp))
    for i, (d0, d1) in enumerate(sorted(cmp)):
        A('    UN_CMP[%d] = %d;' % (i, (d0 << 16) | d1 | (cmp[(d0, d1)] << 32)))
    A('    return 0;')
    A('}')
    A('')
    A(BODY)
    return '\n'.join(L) + '\n'


BODY = r'''
# ── 覆盖判断 ────────────────────────────────────────────────────────────
fn un_cov(cp: i64) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    while i < 12 {
        j = i + 1;
        if cp >= UN_SEG[i] {
            if cp < UN_SEG[j] { return 1; }
        }
        i = i + 2;
    }
    return 0;
}

# ── 规范组合类。表外一律 0（表只收 ccc != 0 的连续段）─────────────────
fn un_ccc(cp: i64) -> i64 {
    let lo: i64 = 0;
    let hi: i64 = UN_NC - 1;
    let mid: i64 = 0;
    let v: i64 = 0;
    let l: i64 = 0;
    let h: i64 = 0;
    while lo <= hi {
        mid = (lo + hi) / 2;
        v = UN_CCC[mid];
        l = v & 65535;
        h = (v >> 16) & 65535;
        if cp < l { hi = mid - 1; }
        if cp >= l {
            if cp > h { lo = mid + 1; }
        }
        if cp >= l {
            if cp <= h { return (v >> 32) & 255; }
        }
    }
    return 0;
}

# ── 规范分解表查询。返回打包项，无分解返回 -1 ─────────────────────────
fn un_dec_of(cp: i64) -> i64 {
    let lo: i64 = 0;
    let hi: i64 = UN_ND - 1;
    let mid: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    while lo <= hi {
        mid = (lo + hi) / 2;
        v = UN_DEC[mid];
        k = v & 65535;
        if cp < k { hi = mid - 1; }
        if cp > k { lo = mid + 1; }
        if cp == k { return v; }
    }
    return 0 - 1;
}

# ── 规范组合表查询 ──────────────────────────────────────────────────────
fn un_cmp_of(d0: i64, d1: i64) -> i64 {
    let key: i64 = d0 * 65536 + d1;
    let lo: i64 = 0;
    let hi: i64 = UN_NP - 1;
    let mid: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    while lo <= hi {
        mid = (lo + hi) / 2;
        v = UN_CMP[mid];
        k = v & 4294967295;
        if key < k { hi = mid - 1; }
        if key > k { lo = mid + 1; }
        if key == k { return (v >> 32) & 65535; }
    }
    return 0 - 1;
}

# ── Hangul 常量（UAX #15 的算法化部分）─────────────────────────────────
#    SBase=44032(0xAC00)  LBase=4352(0x1100)  VBase=4449(0x1161)
#    TBase=4519(0x11A7)   LEnd=4370  VEnd=4469  TEnd=4546
#    NCount=588(21*28)    TCount=28   SCount=11172   SEnd=55203(0xD7A3)
fn un_comp_pair(a: i64, b: i64) -> i64 {
    # L + V -> LV
    if a >= 4352 {
        if a <= 4370 {
            if b >= 4449 {
                if b <= 4469 {
                    return 44032 + (a - 4352) * 588 + (b - 4449) * 28;
                }
            }
        }
    }
    # LV + T -> LVT（只有 T 无尾、即 (S-SBase)%28==0 的 LV 才能再接 T）
    if a >= 44032 {
        if a <= 55203 {
            let r: i64 = (a - 44032) % 28;
            if r == 0 {
                if b > 4519 {
                    if b <= 4546 { return a + (b - 4519); }
                }
            }
        }
    }
    return un_cmp_of(a, b);
}

# ── 写入全分解结果 ──────────────────────────────────────────────────────
fn un_emit(c: i64) -> i64 {
    if UN_M >= 512 { UN_OVF = 1; return 0 - 1; }
    UN_D1[UN_M] = c;
    UN_M = UN_M + 1;
    return 0;
}

# ── 递归全分解（含 Hangul 算法分解）────────────────────────────────────
fn un_dec_all() -> i64 {
    let i: i64 = 0;
    let cp: i64 = 0;
    let c: i64 = 0;
    let d: i64 = 0;
    let dep: i64 = 0;
    let hang: i64 = 0;
    let sidx: i64 = 0;
    let t: i64 = 0;
    UN_M = 0;
    while i < UN_NN {
        cp = UN_IN[i];
        if un_cov(cp) == 0 { UN_UNK = 1; return 0 - 1; }
        UN_SP = 0;
        UN_ST[0] = cp;
        UN_SF[0] = 0;
        UN_SP = 1;
        while UN_SP > 0 {
            UN_SP = UN_SP - 1;
            c = UN_ST[UN_SP];
            dep = UN_SF[UN_SP];
            hang = 0;
            if c >= 44032 { if c <= 55203 { hang = 1; } }
            if hang == 1 {
                sidx = c - 44032;
                t = 4519 + sidx % 28;
                if un_emit(4352 + sidx / 588) < 0 { return 0 - 1; }
                if un_emit(4449 + (sidx % 588) / 28) < 0 { return 0 - 1; }
                if t != 4519 { if un_emit(t) < 0 { return 0 - 1; } }
            }
            if hang == 0 {
                d = un_dec_of(c);
                if d < 0 {
                    if un_emit(c) < 0 { return 0 - 1; }
                }
                if d >= 0 {
                    if dep >= 1 { UN_NREC = UN_NREC + 1; }
                    if dep + 1 > UN_MAXD { UN_MAXD = dep + 1; }
                    let e0: i64 = (d >> 16) & 65535;
                    let e1: i64 = (d >> 32) & 65535;
                    if e1 != 0 {
                        UN_SF[UN_SP] = dep + 1;
                        UN_ST[UN_SP] = e1;
                        UN_SP = UN_SP + 1;
                    }
                    UN_SF[UN_SP] = dep + 1;
                    UN_ST[UN_SP] = e0;
                    UN_SP = UN_SP + 1;
                }
            }
        }
        i = i + 1;
    }
    return UN_M;
}

# ── 规范排序：每段「基字符 + 组合记号」内按 ccc 稳定插入排序 ───────────
fn un_reorder() -> i64 {
    let n: i64 = UN_M;
    let i: i64 = 0;
    let j: i64 = 0;
    let k: i64 = 0;
    let cj: i64 = 0;
    let ck: i64 = 0;
    let go: i64 = 0;
    while i < n {
        if un_ccc(UN_D1[i]) == 0 {
            j = i + 1;
            while j < n {
                cj = UN_D1[j];
                if un_ccc(cj) == 0 { j = n; }
                if j < n {
                    k = j - 1;
                    go = 1;
                    while k >= i + 1 {
                        if go == 1 {
                            ck = UN_D1[k];
                            if un_ccc(ck) > un_ccc(cj) {
                                UN_D1[k + 1] = ck;
                                k = k - 1;
                            }
                            if un_ccc(ck) <= un_ccc(cj) { go = 0; }
                        }
                        if go == 0 { k = i; }
                    }
                    UN_D1[k + 1] = cj;
                    j = j + 1;
                }
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < n {
        UN_D2[i] = UN_D1[i];
        i = i + 1;
    }
    UN_LN = n;
    return n;
}

# ── 规范组合（含阻挡规则）──────────────────────────────────────────────
fn un_compose() -> i64 {
    let n: i64 = UN_LN;
    let i: i64 = 0;
    let o: i64 = 0;
    let last: i64 = 0 - 1;
    let c: i64 = 0;
    let cc: i64 = 0;
    let ok: i64 = 0;
    let comp: i64 = 0;
    while i < n {
        c = UN_D2[i];
        cc = un_ccc(c);
        if cc == 0 {
            UN_OUT[o] = c;
            last = o;
            o = o + 1;
        }
        if cc != 0 {
            ok = 0;
            if last >= 0 {
                if o - 1 == last { ok = 1; }
                if o - 1 > last {
                    if un_ccc(UN_OUT[o - 1]) < cc { ok = 1; }
                }
            }
            if ok == 1 {
                comp = un_comp_pair(UN_OUT[last], c);
                if comp < 0 { ok = 0; }
                if comp >= 0 { UN_OUT[last] = comp; }
            }
            if ok == 0 {
                UN_OUT[o] = c;
                o = o + 1;
            }
        }
        i = i + 1;
    }
    UN_LC = o;
    return o;
}

# ── 对外接口 ────────────────────────────────────────────────────────────
# 输入：UN_IN[0..UN_NN)   输出：UN_D2[0..UN_LN) 为 NFD，UN_OUT[0..UN_LC) 为 NFC
fn un_nfd() -> i64 {
    UN_UNK = 0;
    UN_OVF = 0;
    UN_NREC = 0;
    UN_MAXD = 0;
    let r: i64 = un_dec_all();
    if r < 0 { return 0 - 1; }
    un_reorder();
    return UN_LN;
}

fn un_nfc() -> i64 {
    let r: i64 = un_nfd();
    if r < 0 { return 0 - 1; }
    un_compose();
    return UN_LC;
}

# 把上一轮结果喂回输入（幂等性测试用）
fn un_from_nfd() -> i64 {
    let i: i64 = 0;
    while i < UN_LN {
        UN_IN[i] = UN_D2[i];
        i = i + 1;
    }
    UN_NN = UN_LN;
    return UN_LN;
}

fn un_from_nfc() -> i64 {
    let i: i64 = 0;
    while i < UN_LC {
        UN_IN[i] = UN_OUT[i];
        i = i + 1;
    }
    UN_NN = UN_LC;
    return UN_LC;
}

# 快照与比对
fn un_snap_nfd() -> i64 {
    let i: i64 = 0;
    while i < UN_LN {
        UN_SV[i] = UN_D2[i];
        i = i + 1;
    }
    UN_SN = UN_LN;
    return UN_SN;
}

fn un_snap_nfc() -> i64 {
    let i: i64 = 0;
    while i < UN_LC {
        UN_SV[i] = UN_OUT[i];
        i = i + 1;
    }
    UN_SN = UN_LC;
    return UN_SN;
}

fn un_cmp_nfd() -> i64 {
    if UN_LN != UN_SN { return 0; }
    let i: i64 = 0;
    while i < UN_LN {
        if UN_D2[i] != UN_SV[i] { return 0; }
        i = i + 1;
    }
    return 1;
}

fn un_cmp_nfc() -> i64 {
    if UN_LC != UN_SN { return 0; }
    let i: i64 = 0;
    while i < UN_LC {
        if UN_OUT[i] != UN_SV[i] { return 0; }
        i = i + 1;
    }
    return 1;
}
'''


def main():
    runs, dec, cmp = build()
    print('CCC 区间 %d / 分解表 %d / 组合表 %d' % (len(runs), len(dec), len(cmp)))
    src = emit(runs, dec, cmp)
    with open(os.path.join(ROOT, 'lib', 'uninorm.mo'), 'w') as f:
        f.write(src)
    print('写出 lib/uninorm.mo  %d 行' % src.count('\n'))


if __name__ == '__main__':
    main()
