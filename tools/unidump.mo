# unidump —— 把覆盖段内每个码点的分类与大小写结果全部打印出来
#
# 供 tools/unitest.sh 与 Python 的 unicodedata 做**独立参照**比对。
# 测试文件里的断言是挑出来的几十个具体值；这个程序是 23440 个码点的全量
# 对照 —— 挑出来的值对了不代表表没错位，全量对照才看得出。
#
# 输出每行：cp cat upper spec_upper lower spec_lower
#   未命中特殊多字符映射时 spec 为 0；upper/lower 无映射时返回原码点。

import "io.mo";
import "uni.mo";

fn main() -> i64 {
    uni_init();
    let s: i64 = 0;
    while s < 12 {
        let cp: i64 = UNI_SEG[s];
        let j: i64 = s + 1;
        let hi: i64 = UNI_SEG[j];
        while cp < hi {
            let c: i64 = uni_cat(cp);
            let u: i64 = uni_upper(cp);
            let su: i64 = UNI_SPEC;
            let l: i64 = uni_lower(cp);
            let sl: i64 = UNI_SPEC;
            print_i64(cp);
            print(" ");
            print_i64(c);
            print(" ");
            print_i64(u);
            print(" ");
            print_i64(su);
            print(" ");
            print_i64(l);
            print(" ");
            print_i64(sl);
            print_nl();
            cp = cp + 1;
        }
        s = s + 2;
    }
    return 0;
}
