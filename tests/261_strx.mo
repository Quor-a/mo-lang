import "str.mo";
import "io.mo";
# expect: 0
var T: [64] byte = 0;
var U: [64] byte = 0;

fn main() -> i64 {
    # itoa_base
    str_itoa_base(&T, 255, 16);
    if streq(&T, "ff") != 1 { print("fail hex\n"); return 1; }
    str_itoa_base(&T, 0 - 10, 16);
    if streq(&T, "-a") != 1 { print("fail neghex\n"); return 1; }
    str_itoa_base(&T, 5, 2);
    if streq(&T, "101") != 1 { print("fail bin\n"); return 1; }
    str_itoa_base(&T, 0, 8);
    if streq(&T, "0") != 1 { print("fail zero\n"); return 1; }
    # toupper / tolower
    strcpy(&T, "mO-Lang99");
    str_toupper(&T);
    if streq(&T, "MO-LANG99") != 1 { print("fail upper\n"); return 1; }
    str_tolower(&T);
    if streq(&T, "mo-lang99") != 1 { print("fail lower\n"); return 1; }
    # replace
    str_replace(&U, "a-b-c-a-b", "b", "XY");
    if streq(&U, "a-XY-c-a-XY") != 1 { print("fail rep1\n"); return 1; }
    str_replace(&U, "aaa", "aa", "b");
    if streq(&U, "ba") != 1 { print("fail rep2\n"); return 1; }
    print("STRX_OK\n");
    return 0;
}
