# err：结构化错误的基本契约
# expect: 1
import "err.mo";
import "assert.mo";

fn main() -> i64 {
    err_clear();
    assert_eq("a1", err_ok(), 1);
    assert_eq("a2", err_isset(), 0);

    # err_wrap 设置错误并返回 -1
    let r: i64 = err_wrap(E_RANGE, "index out of bounds", "vec_get");
    assert_eq("a3", r, -1);
    assert_eq("a4", err_code(), E_RANGE);
    assert_eq("a5", streq(err_msg(), "index out of bounds"), 1);
    assert_eq("a6", streq(err_where(), "vec_get"), 1);
    assert_eq("a7", err_ok(), 0);

    # 清除后恢复
    err_clear();
    assert_eq("a8", err_code(), E_NONE);
    assert_eq("a9", err_ok(), 1);

    # errno 映射
    assert_eq("a10", err_from_errno(-2), E_FOUND);
    assert_eq("a11", err_from_errno(-13), E_ARG);
    assert_eq("a12", err_from_errno(-12), E_NOMEM);
    assert_eq("a13", err_from_errno(-5), E_IO);
    assert_eq("a14", err_from_errno(0), E_NONE);
    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
