# selfcontained —— 自包含度审计（用墨语言自己写的）
#
# 「自包含生态」不能靠宣称，得能度量。这个工具扫描一个目录，
# 按实现语言统计文件数与行数，给出墨语言占比。
#
# 为什么按行数而不是文件数：一个 2500 行的编译器和 30 行的脚本
# 都算"一个文件"，按文件数统计会把真实工作量抹平。
#
# 为什么它自己必须是墨语言写的：审计工具若由 Python 写成，
# 那它报告出来的"自包含度"里就没算自己 —— 数字是偏高的。
import "dir.mo";
import "io.mo";
import "fs.mo";
import "str.mo";

var SC_BUF: [65536] byte = 0;
var SC_PATH: [512] byte = 0;
var SC_NAME: [256] byte = 0;
var SC_EXT: [64] byte = 0;      # 扩展名专用 —— 不能共用 SC_BUF，
                               # 否则会被 sc_lines 读文件时覆盖
var SC_TY: i64 = 0;

var SC_FMO: i64 = 0;
var SC_FSH: i64 = 0;
var SC_FPY: i64 = 0;
var SC_FOTH: i64 = 0;
var SC_LMO: i64 = 0;
var SC_LSH: i64 = 0;
var SC_LPY: i64 = 0;
var SC_LOTH: i64 = 0;

# 取扩展名（最后一个 '.' 之后），没有返回空串
fn sc_ext(s: ptr, out: ptr) -> i64 {
    let n: i64 = strlen(s);
    let i: i64 = n - 1;
    let k: i64 = 0;
    store8(out, 0);
    while i >= 0 {
        if load8(s + i) == 46 {
            k = 0;
            while load8(s + i + 1 + k) != 0 {
                store8(out + k, load8(s + i + 1 + k));
                k = k + 1;
            }
            store8(out + k, 0);
            return 1;
        }
        i = i - 1;
    }
    return 0;
}

fn sc_lines(path: ptr) -> i64 {
    let n: i64 = read_file(path, &SC_BUF, 65535);
    let i: i64 = 0;
    let c: i64 = 0;
    if n <= 0 { return 0; }
    store8(&SC_BUF + n, 0);
    i = 0;
    while i < n {
        if load8(&SC_BUF + i) == 10 { c = c + 1; }
        i = i + 1;
    }
    if load8(&SC_BUF + n - 1) != 10 { c = c + 1; }
    return c;
}

fn sc_scan(d: ptr) -> i64 {
    let l: i64 = 0;
    SC_FMO = 0;
    SC_FSH = 0;
    SC_FPY = 0;
    SC_FOTH = 0;
    SC_LMO = 0;
    SC_LSH = 0;
    SC_LPY = 0;
    SC_LOTH = 0;
    if dir_open(d) < 0 { return 0 - 1; }
    while dir_next(&SC_NAME, &SC_TY) == 1 {
        # d_type: 4=目录 8=普通文件。有些文件系统返回 0(DT_UNKNOWN)，
        # 所以这里排除目录而不是只认 8。
        if SC_TY != 4 {
            strcpy(&SC_PATH, d);
            strcat(&SC_PATH, "/");
            strcat(&SC_PATH, &SC_NAME);
            sc_ext(&SC_NAME, &SC_EXT);
            l = sc_lines(&SC_PATH);
            if streq(&SC_EXT, "mo") == 1 {
                SC_FMO = SC_FMO + 1;
                SC_LMO = SC_LMO + l;
            } else {
                if streq(&SC_EXT, "sh") == 1 {
                    SC_FSH = SC_FSH + 1;
                    SC_LSH = SC_LSH + l;
                } else {
                    if streq(&SC_EXT, "py") == 1 {
                        SC_FPY = SC_FPY + 1;
                        SC_LPY = SC_LPY + l;
                    } else {
                        SC_FOTH = SC_FOTH + 1;
                        SC_LOTH = SC_LOTH + l;
                    }
                }
            }
        }
    }
    dir_close();
    return 0;
}

# 整数百分比：a*100/total
fn sc_pct(a: i64, total: i64) -> i64 {
    if total <= 0 { return 0; }
    return a * 100 / total;
}

fn sc_report(d: ptr) -> i64 {
    let tf: i64 = SC_FMO + SC_FSH + SC_FPY + SC_FOTH;
    let tl: i64 = SC_LMO + SC_LSH + SC_LPY + SC_LOTH;
    print("自包含度审计: ");
    print(d);
    print_nl();
    print("\n");
    print("  语言      文件数   行数      行占比\n");
    print("  ------------------------------------\n");
    print("  墨语言    ");
    print_i64(SC_FMO);
    print("        ");
    print_i64(SC_LMO);
    print("       ");
    print_i64(sc_pct(SC_LMO, tl));
    print("%\n");
    print("  shell     ");
    print_i64(SC_FSH);
    print("        ");
    print_i64(SC_LSH);
    print("       ");
    print_i64(sc_pct(SC_LSH, tl));
    print("%\n");
    print("  python    ");
    print_i64(SC_FPY);
    print("        ");
    print_i64(SC_LPY);
    print("       ");
    print_i64(sc_pct(SC_LPY, tl));
    print("%\n");
    print("  其他      ");
    print_i64(SC_FOTH);
    print("        ");
    print_i64(SC_LOTH);
    print("       ");
    print_i64(sc_pct(SC_LOTH, tl));
    print("%\n");
    print("\n");
    print("  合计 ");
    print_i64(tf);
    print(" 个文件, ");
    print_i64(tl);
    print(" 行\n");
    print("  墨语言行占比: ");
    print_i64(sc_pct(SC_LMO, tl));
    print("%\n");
    return 0;
}

fn main() -> i64 {
    let d: i64 = "tools";
    if argc() >= 2 { d = argv(1); }
    if sc_scan(d) < 0 {
        print("cannot open: ");
        print(d);
        print_nl();
        return 1;
    }
    return sc_report(d);
}
