import unicodedata as ud, sys

# 粗类别（0..22）。细分 Cc/Cf/Cs/Co/Cn 与 Nd/Nl,No，使 isdigit/isprint 精确
C = {'Cn':0,'Cc':19,'Cf':20,'Cs':21,'Co':22,
     'Lu':1,'Ll':2,'Lt':3,'Lm':4,'Lo':5,
     'Mn':6,'Mc':6,'Me':6,
     'Nd':7,'Nl':8,'No':8,
     'Pc':9,'Pd':10,'Ps':11,'Pi':11,'Pe':12,'Pf':12,'Po':13,
     'Sm':14,'Sc':15,'Sk':16,'So':17,
     'Zs':18,'Zl':18,'Zp':18}
SEGS = [(0,0x0500),(0x2000,0x2300),(0x25a0,0x2600),(0x3000,0x3040),
        (0x4e00,0xa000),(0xff00,0xfff0)]
DOFF = 8384

def cps():
    for lo,hi in SEGS:
        for cp in range(lo,hi): yield cp
def rle(it):
    out=[];cur=None
    for cp,k in it:
        if cur and cur[2]==k and cp==cur[1]+1: cur[1]=cp
        else:
            if cur: out.append(cur)
            cur=[cp,cp,k]
    if cur: out.append(cur)
    return out

cat_r = rle((cp, C[ud.category(chr(cp))]) for cp in cps())
def key(cp, fn):
    s = fn(chr(cp))
    if len(s)==1:
        d = ord(s)-cp
        return (0,0) if d==0 else (1, d+DOFF)
    return (2,0)                      # 多字符特殊映射
up_r=[x for x in rle((cp,key(cp,str.upper)) for cp in cps()) if x[2][0]!=0]
lo_r=[x for x in rle((cp,key(cp,str.lower)) for cp in cps()) if x[2][0]!=0]
def pk(lo,hi,kind,d): return lo | (hi<<16) | (kind<<32) | (d<<40)
cat_l=[str(pk(r[0],r[1],r[2],0)) for r in cat_r]
up_l =[str(pk(r[0],r[1],r[2][0],r[2][1])) for r in up_r]
lo_l =[str(pk(r[0],r[1],r[2][0],r[2][1])) for r in lo_r]
print('cat',len(cat_l),'up',len(up_l),'lo',len(lo_l),file=sys.stderr)

def block(var, arr, lines):
    o=['    %s = %d;'%(var,len(lines))]
    for i,l in enumerate(lines): o.append('    %s[%d] = %s;'%(arr,i,l))
    return '\n'.join(o)

HEAD = r'''# uni —— Unicode 字符分类与大小写转换
#
# ── 概念 ────────────────────────────────────────────────────────────
#   Unicode 通用类别（General Category，UAX #44）把每个码点归入
#   Lu / Ll / Lt / Lm / Lo / Mn / Mc / Me / Nd / Nl / No / Pc / Pd / Ps /
#   Pe / Pi / Pf / Po / Sm / Sc / Sk / So / Zs / Zl / Zp / Cc / Cf / Cs /
#   Co / Cn 三十个细类。大小写转换由 UnicodeData.txt 的 Simple_Uppercase /
#   Simple_Lowercase 字段给出（SpecialCasing.txt 里还有一批「一个码点变成
#   多个码点」的特殊映射，本表无法用单个 delta 表示）。
#
#   为什么算「概念」而不是「工程惯例」：C/C++ 的 <ctype.h> 只有 ASCII 且
#   受 locale 支配；Java / Go / Rust / Python 有字符分类，但都依赖运行时
#   自带的完整 Unicode 表且不可裁剪；**没有任何主流语言把它做成可嵌入的
#   纯数据表**。本实现是区间表 + 二分查找，数据自举生成（见 tools/genuni.py）。
#
# ── 数据结构：区间打包进一个 i64 ────────────────────────────────────
#     bit 0..15   lo       区间下界
#     bit 16..31  hi       区间上界
#     bit 32..39  kind     类别表：粗类别 0..22
#                          大小写表：0 无映射 / 1 delta 可用 / 2 特殊多字符
#     bit 40..63  delta    映射增量，存 delta + 8384（避开负数字面量）
#
#   一个区间一个 i64，三张表共 __NTOT__ 项。查询是 O(log n) 二分。
#   之所以打包而不是开三个数组：墨语言没有数组字面量初始化，只能逐项赋值，
#   打包把赋值条数压到原来的 1/3。
#
# ── 覆盖范围（诚实标注，不假装全 Unicode）───────────────────────────
#     U+0000..U+04FF    Latin-1 / Latin Ext-A,B / IPA / Greek / Cyrillic
#     U+2000..U+22FF    通用标点、上标下标、货币、字母符号、数字形式、
#                       箭头、数学运算符
#     U+25A0..U+25FF    几何图形
#     U+3000..U+303F    CJK 标点
#     U+4E00..U+9FFF    CJK 统一汉字
#     U+FF00..U+FFEF    全角/半角形式
#   **之外的码点一律返回「未覆盖」**：uni_cat 返回 -1 并置 UNI_UNK。
#   表由 Python 3.10 的 unicodedata（Unicode __UVER__）导出。

var UNI_NC: i64 = 0;      # 类别表项数
var UNI_NU: i64 = 0;      # 大写映射表项数
var UNI_NL: i64 = 0;      # 小写映射表项数
var UNI_UNK: i64 = 0;     # 最近一次查询落在覆盖范围之外
var UNI_SPEC: i64 = 0;    # 最近一次查询命中「一个码点变多个码点」的特殊映射
var UNI_SEG: [12] i64 = 0;    # 覆盖段（成对 lo,hi），供 uni_covered 快速判断

var UNI_CAT: [__NC__] i64 = 0;
var UNI_UP:  [__NU__] i64 = 0;
var UNI_LO:  [__NL__] i64 = 0;

fn uni_init() -> i64 {
'''
SEG_L = [0,0x500, 0x2000,0x2300, 0x25a0,0x2600, 0x3000,0x3040, 0x4e00,0xa000, 0xff00,0xfff0]
tail = r'''
    UNI_SEG[0] = 0;      UNI_SEG[1] = 1280;
    UNI_SEG[2] = 8192;   UNI_SEG[3] = 8960;
    UNI_SEG[4] = 9632;   UNI_SEG[5] = 9728;
    UNI_SEG[6] = 12288;  UNI_SEG[7] = 12352;
    UNI_SEG[8] = 19968;  UNI_SEG[9] = 40960;
    UNI_SEG[10] = 65280; UNI_SEG[11] = 65520;
    return 0;
}

# 覆盖段判断。放在二分之前是必要的：二分查不到时无法区分
# 「覆盖了但无映射」与「压根没覆盖」，前者是合法结果、后者是数据缺失。
fn uni_covered(cp: i64) -> i64 {
    let i = 0;
    while i < 12 {
        if cp >= UNI_SEG[i] {
            if cp < UNI_SEG[i + 1] { return 1; }
        }
        i = i + 2;
    }
    return 0;
}

# 二分查找。which: 0 类别 / 1 大写 / 2 小写。返回打包值，未命中返回 -1。
fn uni_bsearch(which: i64, cp: i64) -> i64 {
    let n = 0;
    if which == 0 { n = UNI_NC; }
    if which == 1 { n = UNI_NU; }
    if which == 2 { n = UNI_NL; }
    let lo = 0;
    let hi = n - 1;
    while lo <= hi {
        let mid = (lo + hi) / 2;
        let v = 0;
        if which == 0 { v = UNI_CAT[mid]; }
        if which == 1 { v = UNI_UP[mid]; }
        if which == 2 { v = UNI_LO[mid]; }
        let l = v & 65535;
        let h = (v >> 16) & 65535;
        if cp < l { hi = mid - 1; }
        if cp >= l {
            if cp > h { lo = mid + 1; }
        }
        if cp >= l {
            if cp <= h { return v; }
        }
    }
    return 0 - 1;
}

# 粗类别 0..22。覆盖范围外返回 -1 并置 UNI_UNK。
fn uni_cat(cp: i64) -> i64 {
    UNI_UNK = 0;
    if cp < 0 { UNI_UNK = 1; return 0 - 1; }
    if cp > 65535 { UNI_UNK = 1; return 0 - 1; }
    if uni_covered(cp) == 0 { UNI_UNK = 1; return 0 - 1; }
    let v = uni_bsearch(0, cp);
    if v < 0 { UNI_UNK = 1; return 0 - 1; }
    return (v >> 32) & 255;
}

fn uni_isupper(cp: i64) -> i64 {
    if uni_cat(cp) == 1 { return 1; }
    return 0;
}
fn uni_islower(cp: i64) -> i64 {
    if uni_cat(cp) == 2 { return 1; }
    return 0;
}
fn uni_istitle(cp: i64) -> i64 {
    if uni_cat(cp) == 3 { return 1; }
    return 0;
}
fn uni_isalpha(cp: i64) -> i64 {
    let c = uni_cat(cp);
    if c >= 1 { if c <= 5 { return 1; } }
    return 0;
}
fn uni_isdigit(cp: i64) -> i64 {
    if uni_cat(cp) == 7 { return 1; }
    return 0;
}
fn uni_isalnum(cp: i64) -> i64 {
    if uni_isalpha(cp) == 1 { return 1; }
    if uni_isdigit(cp) == 1 { return 1; }
    return 0;
}
# 空白 = Zs/Zl/Zp，加上 ASCII 的 \t \n \v \f \r（它们在 Unicode 里是 Cc，
# 但习惯上算空白；U+0085 NEL 与 U+00A0 NBSP 属于 Cc / Zs，已按类别命中）。
fn uni_isspace(cp: i64) -> i64 {
    if uni_cat(cp) == 18 { return 1; }
    if cp >= 9 { if cp <= 13 { return 1; } }
    return 0;
}
fn uni_ispunct(cp: i64) -> i64 {
    let c = uni_cat(cp);
    if c >= 9 { if c <= 13 { return 1; } }
    return 0;
}
fn uni_issymbol(cp: i64) -> i64 {
    let c = uni_cat(cp);
    if c >= 14 { if c <= 17 { return 1; } }
    return 0;
}
fn uni_iscntrl(cp: i64) -> i64 {
    if uni_cat(cp) == 19 { return 1; }
    return 0;
}
# 可打印 = 已覆盖且不是 Cc / Cf / Cs / Cn
fn uni_isprint(cp: i64) -> i64 {
    let c = uni_cat(cp);
    if c < 0 { return 0; }
    if c == 0 { return 0; }
    if c == 19 { return 0; }
    if c == 20 { return 0; }
    if c == 21 { return 0; }
    return 1;
}

# 单个码点的大写。覆盖范围外返回 -1 并置 UNI_UNK；
# 命中特殊多字符映射（如 U+00DF ß → SS）时置 UNI_SPEC 并返回原码点。
fn uni_upper(cp: i64) -> i64 {
    UNI_UNK = 0;
    UNI_SPEC = 0;
    if cp < 0 { UNI_UNK = 1; return 0 - 1; }
    if cp > 65535 { UNI_UNK = 1; return 0 - 1; }
    if uni_covered(cp) == 0 { UNI_UNK = 1; return 0 - 1; }
    let v = uni_bsearch(1, cp);
    if v < 0 { return cp; }
    let k = (v >> 32) & 255;
    if k == 2 { UNI_SPEC = 1; return cp; }
    let d = ((v >> 40) & 16777215) - 8384;
    return cp + d;
}

fn uni_lower(cp: i64) -> i64 {
    UNI_UNK = 0;
    UNI_SPEC = 0;
    if cp < 0 { UNI_UNK = 1; return 0 - 1; }
    if cp > 65535 { UNI_UNK = 1; return 0 - 1; }
    if uni_covered(cp) == 0 { UNI_UNK = 1; return 0 - 1; }
    let v = uni_bsearch(2, cp);
    if v < 0 { return cp; }
    let k = (v >> 32) & 255;
    if k == 2 { UNI_SPEC = 1; return cp; }
    let d = ((v >> 40) & 16777215) - 8384;
    return cp + d;
}

# 首字母大写。Unicode 的 toTitlecase：Lt 类码点的 title 是它自己，
# 其余码点取 uppercase（这是 Default Case Conversion 的定义）。
fn uni_title(cp: i64) -> i64 {
    if uni_cat(cp) == 3 { return cp; }
    return uni_upper(cp);
}
'''
import io
head = HEAD.replace('__NC__', str(len(cat_l)+8)).replace('__NU__', str(len(up_l)+8)).replace('__NL__', str(len(lo_l)+8))
head = head.replace('__NTOT__', str(len(cat_l)+len(up_l)+len(lo_l)))
head = head.replace('__UVER__', ud.unidata_version)
body = '\n'.join([block('UNI_NC','UNI_CAT',cat_l), block('UNI_NU','UNI_UP',up_l), block('UNI_NL','UNI_LO',lo_l)])
open('lib/uni.mo','w').write(head + body + '\n' + tail)
print('uni.mo written', file=sys.stderr)
