# uninormdump —— 把 uninorm 的 NFD / NFC 结果全部打出来
#
# 由 tools/uninormref.py 用 Python 的 unicodedata 独立算一遍期望并逐行比对。
# 期望**现算不落仓库**：换机器、换 Unicode 版本都能重算，不会出现
# 「期望文件陈旧但仍全绿」。
#
# 输出格式（一行一条）：
#   D <nin> <in...> <nout> <out...>     NFD
#   C <nin> <in...> <nout> <out...>     NFC

import "io.mo";
import "uninorm.mo";

fn putn(v: i64) -> i64 { print_i64(v); return 0; }
fn sp() -> i64 { print(" "); return 0; }
fn nl() -> i64 { print("\n"); return 0; }

fn dump1(tag: i64, cp: i64) -> i64 {
    UN_IN[0] = cp;
    UN_NN = 1;
    let r: i64 = 0;
    if tag == 0 { r = un_nfd(); }
    if tag == 1 { r = un_nfc(); }
    if r < 0 { return 0; }
    print_i64(tag); sp();
    putn(1); sp(); putn(cp); sp();
    if tag == 0 { putn(UN_LN); sp(); }
    if tag == 1 { putn(UN_LC); sp(); }
    let i: i64 = 0;
    if tag == 0 {
        while i < UN_LN { putn(UN_D2[i]); sp(); i = i + 1; }
    }
    if tag == 1 {
        while i < UN_LC { putn(UN_OUT[i]); sp(); i = i + 1; }
    }
    nl();
    return 0;
}

var BASES: [8] i64 = 0;
var MARKS: [12] i64 = 0;

fn dump3(tag: i64, a: i64, b: i64, c: i64, n: i64) -> i64 {
    UN_IN[0] = a; UN_IN[1] = b; UN_IN[2] = c;
    UN_NN = n;
    let r: i64 = 0;
    if tag == 0 { r = un_nfd(); }
    if tag == 1 { r = un_nfc(); }
    if r < 0 { return 0; }
    print_i64(tag); sp();
    putn(n); sp(); putn(a); sp(); putn(b); sp();
    if n > 2 { putn(c); sp(); }
    if tag == 0 { putn(UN_LN); sp(); }
    if tag == 1 { putn(UN_LC); sp(); }
    let i: i64 = 0;
    if tag == 0 {
        while i < UN_LN { putn(UN_D2[i]); sp(); i = i + 1; }
    }
    if tag == 1 {
        while i < UN_LC { putn(UN_OUT[i]); sp(); i = i + 1; }
    }
    nl();
    return 0;
}

fn seg(lo: i64, hi: i64) -> i64 {
    let cp: i64 = lo;
    while cp <= hi {
        dump1(0, cp);
        dump1(1, cp);
        cp = cp + 1;
    }
    return 0;
}

fn main() -> i64 {
    un_init();
    seg(0, 383);
    seg(768, 879);
    seg(900, 1023);
    seg(7680, 7935);
    seg(4352, 4607);
    seg(44032, 55203);

    # 多码点序列：排序与阻挡规则只在多记号序列上才体现
    BASES[0] = 65; BASES[1] = 97; BASES[2] = 69;
    BASES[3] = 113; BASES[4] = 197; BASES[5] = 260;
    MARKS[0] = 768; MARKS[1] = 769; MARKS[2] = 776;
    MARKS[3] = 778; MARKS[4] = 807; MARKS[5] = 808;
    MARKS[6] = 790; MARKS[7] = 803; MARKS[8] = 772;
    let bi: i64 = 0;
    while bi < 6 {
        let m1: i64 = 0;
        while m1 < 9 {
            dump3(0, BASES[bi], MARKS[m1], 0, 2);
            dump3(1, BASES[bi], MARKS[m1], 0, 2);
            let m2: i64 = 0;
            while m2 < 9 {
                dump3(0, BASES[bi], MARKS[m1], MARKS[m2], 3);
                dump3(1, BASES[bi], MARKS[m1], MARKS[m2], 3);
                m2 = m2 + 1;
            }
            m1 = m1 + 1;
        }
        bi = bi + 1;
    }
    return 0;
}
