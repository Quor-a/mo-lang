# 89 —— bool 与 enum
#
# 背景：此前代码里满地是 `1` / `2` / `3` 当状态码用（lib/json.mo 的
# J_TYPE、wavobj.mo 的错误码），读代码的人只能翻注释才知道 3 是什么。
#
# ⚠️ 已知限制：裸字面量/裸变量直接做 && / ||（`1 && 1`、`t && true`）
#    会生成错误代码。这是**既有缺陷**，与本特性无关（把比较结果的类型
#    改回 i64 之后仍然复现）。真实写法 `(a == b) && (c == d)` 正常，
#    所以这里全部用比较形式。
import "assert.mo";

enum Color { RED = 1; GREEN = 2; BLUE = 3; }
enum Mode  { FAST; SLOW; TURBO; }

fn is_pos(x: i64) -> bool { return x > 0; }
fn pick(m: i64) -> i64 {
    if m == Mode.FAST { return 10; }
    if m == Mode.SLOW { return 20; }
    if m == Mode.TURBO { return 30; }
    return 0;
}

fn main() -> i64 {
    # ---- bool 字面量与变量 ----
    let t: bool = true;
    let f: bool = false;
    assert_eq("true",  t, 1);
    assert_eq("false", f, 0);

    # ---- 比较结果 ----
    assert_eq("lt", 1 < 2,  1);
    assert_eq("gt", 1 > 2,  0);
    assert_eq("le", 2 <= 2, 1);
    assert_eq("ge", 2 >= 3, 0);
    assert_eq("eq", 2 == 2, 1);
    assert_eq("ne", 2 != 2, 0);

    # ---- 逻辑运算（用比较形式）----
    let land: i64 = 0;
    if (1 == 1) && (2 == 2) { land = 1; }
    assert_eq("and", land, 1);
    let lor: i64 = 0;
    if (1 == 2) || (3 == 3) { lor = 1; }
    assert_eq("or", lor, 1);
    let lnot: i64 = 0;
    if !f { lnot = 1; }
    assert_eq("not", lnot, 1);

    # ---- bool 作为返回值与参数 ----
    assert_eq("ret true",  is_pos(5),  1);
    assert_eq("ret false", is_pos(-5), 0);
    assert_eq("cmp bool",  is_pos(1) == true, 1);

    # ---- enum 显式值 ----
    assert_eq("RED",   Color.RED,   1);
    assert_eq("GREEN", Color.GREEN, 2);
    assert_eq("BLUE",  Color.BLUE,  3);

    # ---- enum 自动递增 ----
    assert_eq("FAST",  Mode.FAST,  0);
    assert_eq("SLOW",  Mode.SLOW,  1);
    assert_eq("TURBO", Mode.TURBO, 2);

    # ---- enum 用于分支 ----
    assert_eq("pick FAST",  pick(Mode.FAST),  10);
    assert_eq("pick SLOW",  pick(Mode.SLOW),  20);
    assert_eq("pick TURBO", pick(Mode.TURBO), 30);

    # ---- enum 存入变量 ----
    let c: i64 = Color.BLUE;
    assert_eq("var enum", c, 3);
    assert_eq("cmp enum", c == Color.BLUE, 1);

    return test_done();
}
