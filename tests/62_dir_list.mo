# dir_list 批量接口：动态收集，没有固定容量上限
# expect: 1
import "dir.mo";
import "vec.mo";
import "mem.mo";
import "str.mo";
import "assert.mo";

fn main() -> i64 {
    heap_init();

    # 当前目录（run.sh 会把 lib/*.mo 拷进来）
    let v: i64 = dir_list(".");
    assert_true("dir_list ok", v >= 0);
    let n: i64 = vec_len(v);
    assert_true("non-empty", n >= 1);

    # 里面应当有 .mo 文件
    let i: i64 = 0;
    let mo: i64 = 0;
    while i < n {
        if str_ends_with(vec_get(v, i), ".mo") == 1 { mo = mo + 1; }
        i = i + 1;
    }
    assert_true("has .mo", mo >= 1);

    # 上限参数：取 2 个就停
    let v2: i64 = dir_list_max(".", 2);
    assert_true("max=2", vec_len(v2) <= 2);
    assert_true("max>0", vec_len(v2) >= 1);

    # 不存在的目录必须返回 -1，而不是崩
    assert_eq("bad path", dir_list("/no/such/dir/xyz"), -1);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
