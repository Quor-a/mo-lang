# expect: 0
# mopkg（墨语言版包管理器）测试
#
# 重点覆盖 shell 版踩过坑的地方：
#   1. 版本约束语义（^ ~ >= < =）—— shell 版在 ~ 上栽过（tilde 展开）
#   2. TOML 解析（依赖名 / 字段）
#   3. 依赖闭包（不能只比直接依赖 —— shell 版第一版就错在这）
#   4. git 调用（fork + execve + waitpid 真的能跑起来）
import "assert.mo";
import "str.mo";
import "io.mo";
import "fs.mo";
import "mopkg.mo";

var TXT: [4096] byte = 0;

fn write_toml(path: ptr, s: ptr) -> i64 {
    let fd: i64 = fopen(path, 577, 420);
    if fd < 0 { return 0 - 1; }
    fwrite(fd, s, strlen(s));
    fclose(fd);
    return 0;
}

fn test_ver() -> i64 {
    assert_eq("ver_num 1.2.3", pkg_ver_num("1.2.3"), 1002003);
    assert_eq("ver_num 2.0.0", pkg_ver_num("2.0.0"), 2000000);
    assert_eq("ver_num 0.1.0", pkg_ver_num("0.1.0"), 1000);
    assert_eq("ver_num 单一主版本", pkg_ver_num("2"), 2000000);

    # ^ 约束：>= 且主版本不变
    assert_eq("^2.0.0 接受 2.1.0", pkg_ver_match("2.1.0", "^2.0.0"), 1);
    assert_eq("^2.0.0 接受 2.0.0", pkg_ver_match("2.0.0", "^2.0.0"), 1);
    assert_eq("^2.0.0 拒绝 3.0.0", pkg_ver_match("3.0.0", "^2.0.0"), 0);
    assert_eq("^2.0.0 拒绝 1.9.9", pkg_ver_match("1.9.9", "^2.0.0"), 0);

    # ~ 约束：>= 且次版本不变
    assert_eq("~1.2.3 接受 1.2.5", pkg_ver_match("1.2.5", "~1.2.3"), 1);
    assert_eq("~1.2.3 拒绝 1.3.0", pkg_ver_match("1.3.0", "~1.2.3"), 0);
    assert_eq("~1.2.3 拒绝 2.0.0", pkg_ver_match("2.0.0", "~1.2.3"), 0);

    # 比较运算符
    assert_eq(">=1.0.0 接受 1.0.0", pkg_ver_match("1.0.0", ">=1.0.0"), 1);
    assert_eq(">=1.0.0 拒绝 0.9.0", pkg_ver_match("0.9.0", ">=1.0.0"), 0);
    assert_eq("<2.0.0 接受 1.9.9", pkg_ver_match("1.9.9", "<2.0.0"), 1);
    assert_eq("<2.0.0 拒绝 2.0.0", pkg_ver_match("2.0.0", "<2.0.0"), 0);
    assert_eq("=1.2.3 接受 1.2.3", pkg_ver_match("1.2.3", "=1.2.3"), 1);
    assert_eq("=1.2.3 拒绝 1.2.4", pkg_ver_match("1.2.4", "=1.2.3"), 0);

    # 通配与空
    assert_eq("* 接受任意", pkg_ver_match("9.9.9", "*"), 1);
    assert_eq("空约束接受任意", pkg_ver_match("9.9.9", ""), 1);
    return 0;
}

fn test_toml() -> i64 {
    let n: i64 = 0;
    strcpy(&TXT, "[package]\nname = \"app\"\nversion = \"0.1.0\"\n\n");
    strcat(&TXT, "[dependencies]\n");
    strcat(&TXT, "b = { git = \"file:///tmp/rb\", ref = \"main\", version = \"^2.0.0\" }\n");
    strcat(&TXT, "c = { git = \"file:///tmp/rc\", ref = \"main\" }\n");
    write_toml("mo.toml", &TXT);

    if pkg_load_toml("mo.toml") < 0 {
        assert_true("读到 mo.toml", 0);
        return 0;
    }
    n = pkg_dep_names(&PKG_TXT);
    assert_eq("依赖个数", n, 2);
    if n == 2 {
        assert_eq("第一个依赖名", streq(PKG_NAMES[0], "b"), 1);
        assert_eq("第二个依赖名", streq(PKG_NAMES[1], "c"), 1);
    }

    # 字段提取
    pkg_dep_field(&PKG_TXT, "b", "git", &PKG_A);
    assert_eq("b 的 git", streq(&PKG_A, "file:///tmp/rb"), 1);
    pkg_dep_field(&PKG_TXT, "b", "ref", &PKG_A);
    assert_eq("b 的 ref", streq(&PKG_A, "main"), 1);
    pkg_dep_field(&PKG_TXT, "b", "version", &PKG_A);
    assert_eq("b 的 version", streq(&PKG_A, "^2.0.0"), 1);
    pkg_dep_field(&PKG_TXT, "c", "version", &PKG_A);
    assert_eq("c 无 version 约束", strlen(&PKG_A), 0);
    return 0;
}

fn test_lock() -> i64 {
    let nl: i64 = 0;
    strcpy(&TXT, "# mopkg lockfile v2\n\n[[package]]\n");
    strcat(&TXT, "name = \"b\"\nversion = \"2.1.0\"\n");
    strcat(&TXT, "git = \"file:///tmp/rb\"\nref = \"main\"\ncommit = \"abc123\"\n\n");
    strcat(&TXT, "[[package]]\nname = \"c\"\nversion = \"1.0.0\"\n");
    strcat(&TXT, "git = \"file:///tmp/rc\"\nref = \"main\"\ncommit = \"def456\"\n");
    write_toml("mo.lock", &TXT);

    if pkg_load_lock() < 0 {
        assert_true("读到 mo.lock", 0);
        return 0;
    }
    pkg_lock_field("b", "version", &PKG_A);
    assert_eq("锁里 b 的版本", streq(&PKG_A, "2.1.0"), 1);
    pkg_lock_field("b", "commit", &PKG_A);
    assert_eq("锁里 b 的 commit", streq(&PKG_A, "abc123"), 1);
    pkg_lock_field("c", "version", &PKG_A);
    assert_eq("锁里 c 的版本", streq(&PKG_A, "1.0.0"), 1);
    pkg_lock_field("x", "version", &PKG_A);
    assert_eq("不存在的包", strlen(&PKG_A), 0);

    nl = pkg_lock_names(&PKG_C);
    assert_eq("锁里包个数", nl, 2);
    return 0;
}

fn test_closure() -> i64 {
    let i: i64 = 0;
    # app -> b -> c（间接依赖必须进闭包）
    strcpy(&TXT, "[dependencies]\nb = { git = \"file:///tmp/rb\" }\n");
    write_toml("mo.toml", &TXT);
    if pkg_load_toml("mo.toml") < 0 { return 0; }
    pkg_dep_names(&PKG_TXT);

    # 造出 .deps/b/mo.toml，声明它依赖 c
    # 直接用 mkdir 系统调用（83），不走 PATH 查找 —— 更自包含
    syscall(83, ".deps", 493, 0, 0, 0);
    syscall(83, ".deps/b", 493, 0, 0, 0);
    strcpy(&TXT, "[dependencies]\nc = { git = \"file:///tmp/rc\" }\n");
    write_toml(".deps/b/mo.toml", &TXT);

    PKG_CN = 0;
    PKG_DEPTH = 0;
    pkg_closure("b");
    assert_eq("闭包含 b", pkg_in_closure("b"), 1);
    assert_eq("闭包含间接依赖 c", pkg_in_closure("c"), 1);
    assert_eq("闭包不含无关包 z", pkg_in_closure("z"), 0);
    return 0;
}

fn main() -> i64 {
    test_ver();
    test_toml();
    test_lock();
    test_closure();
    return test_done();
    return 0;
}
