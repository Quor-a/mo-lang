# 对标 C 标准库：ctype / stdlib / string / time
# expect: 1
import "cstd.mo";
import "assert.mo";
import "str.mo";

fn main() -> i64 {
    # ctype
    assert_eq("is_alpha A", is_alpha(65), 1);
    assert_eq("is_alpha z", is_alpha(122), 1);
    assert_eq("is_alpha 0", is_alpha(48), 0);
    assert_eq("is_upper", is_upper(65), 1);
    assert_eq("is_lower", is_lower(97), 1);
    assert_eq("is_alnum", is_alnum(55), 1);
    assert_eq("is_space tab", is_space_c(9), 1);
    assert_eq("is_space nl", is_space_c(10), 1);
    assert_eq("toupper", to_upper(97), 65);
    assert_eq("tolower", to_lower(65), 97);
    assert_eq("toupper noop", to_upper(48), 48);

    # stdlib
    assert_eq("abs neg", abs(-42), 42);
    assert_eq("abs pos", abs(42), 42);
    assert_eq("abs 0", abs(0), 0);
    assert_eq("min", min_i64(3, 7), 3);
    assert_eq("max", max_i64(3, 7), 7);
    # cdiv 采用 C 截断语义（与 Python 的 // 不同）
    assert_eq("cdiv", cdiv(7, 3), 2);
    assert_eq("cdiv rem", C_REM, 1);
    assert_eq("cdiv neg", cdiv(-7, 3), -2);
    assert_eq("cdiv neg rem", C_REM, -1);
    assert_eq("cdiv by zero", cdiv(1, 0), 0);

    # strtol
    assert_eq("strtol", strtol("12345"), 12345);
    assert_eq("strtol neg", strtol("-42"), -42);
    assert_eq("strtol plus", strtol("+7"), 7);
    assert_eq("strtol hex", strtol("0xff"), 255);
    assert_eq("strtol sp", strtol("  99"), 99);

    # memmove 必须正确处理重叠 —— memcpy 在这里会出错
    let b: [32] byte = 0;
    strcpy(&b, "abcdefgh");
    memmove(&b + 2, &b, 8);        # 目标在后 → 从后往前拷
    assert_eq("memmove overlap", streq(&b, "ababcdefgh"), 1);

    strcpy(&b, "abcdefgh");
    memmove(&b, &b + 2, 8);        # 目标在前 → 从前往后拷
    # 期望 "cdefgh"：源 &b+2 起的 8 字节是 "cdefgh"+NUL+NUL，
    # 从前往后拷会把最后的 NUL 也带过来，原 'g''h' 被覆盖。
    assert_eq("memmove overlap2", streq(&b, "cdefgh"), 1);

    # memchr
    strcpy(&b, "hello");
    assert_eq("memchr", memchr(&b, 108, 5), &b + 2);
    assert_eq("memchr miss", memchr(&b, 122, 5), 0);

    # strncmp / strncpy
    assert_eq("strncmp eq", strncmp("abc", "abd", 2), 0);
    assert_eq("strncmp ne", strncmp("abc", "abd", 3) == 0, 0);
    let d: [16] byte = 0;
    strncpy(&d, "hi", 8);
    assert_eq("strncpy", streq(&d, "hi"), 1);

    # strrev
    strcpy(&b, "abcd");
    strrev(&b);
    assert_eq("strrev", streq(&b, "dcba"), 1);

    # 时钟：两次读数不应倒退
    let t1: i64 = clock_ms();
    let t2: i64 = clock_ms();
    assert_true("clock monotonic", t2 >= t1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
