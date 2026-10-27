# 对标 shell：词法切分 / 通配符 / 进程 / 管道 / 重定向 / 退出码
# expect: 1
import "sh.mo";
import "assert.mo";
import "str.mo";

var OUTB: [65536] byte = 0;
var T: [64] i64 = 0;

fn main() -> i64 {
    heap_init();
    SH_OUT = &OUTB;

    # --- 词法切分：引号内的空格不分词 ---
    let n: i64 = sh_split("echo \"a b\" 'c d' x", &T);
    assert_eq("split n", n, 4);
    assert_eq("tok0", streq(T[0], "echo"), 1);
    assert_eq("tok1 quoted", streq(T[1], "a b"), 1);
    assert_eq("tok2 quoted", streq(T[2], "c d"), 1);
    assert_eq("tok3", streq(T[3], "x"), 1);

    # 转义：反斜杠后的空格不分词
    n = sh_split("a\\ b c", &T);
    assert_eq("escape n", n, 2);
    assert_eq("escape tok", streq(T[0], "a b"), 1);

    # --- 通配符 ---
    assert_eq("glob exact", fnmatch("abc", "abc"), 1);
    assert_eq("glob star", fnmatch("*.mo", "str.mo"), 1);
    assert_eq("glob star2", fnmatch("*.mo", "str.c"), 0);
    assert_eq("glob q", fnmatch("a?c", "abc"), 1);
    assert_eq("glob q2", fnmatch("a?c", "abbc"), 0);
    assert_eq("glob mid", fnmatch("s*r.mo", "str.mo"), 1);
    assert_eq("glob empty", fnmatch("", ""), 1);
    assert_eq("glob star all", fnmatch("*", "anything"), 1);

    # --- 查找可执行文件 ---
    let w: i64 = sh_which("sh");
    assert_true("which sh", w != 0);
    let w2: i64 = sh_which("definitely-not-a-command-xyz");
    assert_eq("which miss", w2, 0);

    # --- 进程：跑一条命令并捕获输出 ---
    let a: [8] i64 = 0;
    store64(&a, str_dup("echo"));
    store64(&a + 8, str_dup("hi-from-mo"));
    store64(&a + 16, 0);
    let rc: i64 = sh_capture(&a);
    assert_eq("capture rc", rc, 0);
    assert_eq("capture out", streq(SH_OUT, "hi-from-mo\n"), 1);

    # 不存在的命令 → 127（与 shell 约定一致）
    let b: [8] i64 = 0;
    store64(&b, str_dup("definitely-not-a-command-xyz"));
    store64(&b + 8, 0);
    rc = sh_capture(&b);
    assert_eq("not found rc", rc, 127);

    # --- 管道：echo "a b c" | wc -w ---
    let p1: [8] i64 = 0;
    store64(&p1, str_dup("echo"));
    store64(&p1 + 8, str_dup("a b c"));
    store64(&p1 + 16, 0);
    let p2: [8] i64 = 0;
    store64(&p2, str_dup("wc"));
    store64(&p2 + 8, str_dup("-w"));
    store64(&p2 + 16, 0);
    rc = sh_pipe_exec(&p1, &p2);
    assert_eq("pipe rc", rc, 0);
    # wc -w 的输出带前导空格，所以用 ends_with 判断
    assert_true("pipe out has 3", str_ends_with(SH_OUT, "3\n") == 1);

    # --- 退出码传递 ---
    let k: [8] i64 = 0;
    store64(&k, str_dup("sh"));
    store64(&k + 8, str_dup("-c"));
    store64(&k + 16, str_dup("exit 7"));
    store64(&k + 24, 0);
    rc = sh_run(&k);
    assert_eq("exit code 7", rc, 7);

    # --- 重定向：> 写到文件，再读回来 ---
    let r: [8] i64 = 0;
    store64(&r, str_dup("echo"));
    store64(&r + 8, str_dup("redirected-mo"));
    store64(&r + 16, 0);
    rc = sh_redirect_out(&r, "/tmp/mo_sh_test.txt", 0);
    assert_eq("redirect rc", rc, 0);
    let got: i64 = sh_slurp("/tmp/mo_sh_test.txt");
    assert_true("slurp ok", got > 0);
    assert_eq("redirect content", streq(SH_OUT, "redirected-mo\n"), 1);

    # 追加 >>
    rc = sh_redirect_out(&r, "/tmp/mo_sh_test.txt", 1);
    assert_eq("append rc", rc, 0);
    got = sh_slurp("/tmp/mo_sh_test.txt");
    assert_eq("append content", streq(SH_OUT, "redirected-mo\nredirected-mo\n"), 1);

    # --- 目录切换 ---
    assert_eq("chdir /tmp", sh_chdir("/tmp"), 0);
    let c: i64 = sh_getcwd();
    assert_true("cwd /tmp", str_ends_with(c, "/tmp") == 1);

    # --- 环境变量表（自建，墨语言不暴露 environ）---
    assert_eq("nenv", SH_NENV, 0);
    sh_setenv("MO_TEST=1");
    assert_eq("nenv after", SH_NENV, 1);
    assert_eq("env content", streq(SH_ENV[0], "MO_TEST=1"), 1);
    # 重复设置不应重复登记
    sh_setenv("MO_TEST=1");
    assert_eq("nenv dedup", SH_NENV, 1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
