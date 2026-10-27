# 130 —— 深层闭包（多层嵌套 + 跨多层捕获）
#
# v1.130 之前只支持一层：cap_depth 返回 0/1，静态链只走一次 [rbp]，
# 再深一层直接报错 "nested functions cannot be nested further"。
#
# 现在支持到 8 层：cap_depth 返回「往上第几层」，g_walk_static 沿
# [rbp] → [r11] → [r11] ... 走那么多次，再按该层的偏移取。
#
# 🔴 判据必须是**跨层的具体数值**：只测"有没有捕获到"分不清
#    "走了 2 层"和"走了 1 层但偏移恰好落在同值处"。
#    下面每条都让各层持有**互不相同的可辨识值**，和才是唯一解。
import "assert.mo";

# 三层：inner 同时读第 2 层（a, x）、第 1 层（b, m）和自己（n）
fn l3(x: i64) -> i64 {
    let a: i64 = 10;
    fn mid(m: i64) -> i64 {
        let b: i64 = 20;
        fn inner(n: i64) -> i64 {
            return a + b + m + n + x;
        }
        return inner(3);
    }
    return mid(2);
}

# 跨两层**写**：最内层改最外层的变量，状态必须留在最外层栈帧上。
# 这一条能抓到"写到了中间层同偏移处"—— 那时 outer 的 s 始终是 0。
fn acc3(base: i64) -> i64 {
    let s: i64 = 0;
    fn m2() -> i64 {
        fn i3(v: i64) -> i64 {
            s = s + v;
            return s;
        }
        i3(1);
        i3(2);
        return i3(3);
    }
    m2();
    m2();
    return s + base;
}

# 四层：最内层读第 3 层、第 1 层、第 0 层
fn l4(x: i64) -> i64 {
    let a: i64 = 1;
    fn f1() -> i64 {
        let b: i64 = 2;
        fn f2() -> i64 {
            let c: i64 = 4;
            fn f3() -> i64 {
                return a + b + c + x;
            }
            return f3();
        }
        return f2();
    }
    return f1();
}

# 写中间层：inner 写 mid 的 b，mid 随后读自己的 b —— 必须看到新值
fn writemid() -> i64 {
    let a: i64 = 100;
    fn mid() -> i64 {
        let b: i64 = 0;
        fn inner() -> i64 {
            b = b + 5;
            return b;
        }
        inner();
        inner();
        return b;
    }
    let r: i64 = mid();
    return r * 1000 + a;
}

# 各层同名会被**明确报错**（duplicate definition），不是静默遮蔽 ——
# 这比"取最近的那个"安全：后者一旦判错就是静默读到别层的变量。
# 这里用不同名的 near/far 验证"取自己那层"不会误取外层。
fn nearfar() -> i64 {
    let far: i64 = 1;
    fn g1() -> i64 {
        let near: i64 = 2;
        fn g2() -> i64 {
            return near * 10 + far;
        }
        return g2();
    }
    return g1() * 100 + far;
}

# 五层：连续跨 4 层读最外层
fn l5() -> i64 {
    let z: i64 = 7;
    fn a1() -> i64 {
        fn a2() -> i64 {
            fn a3() -> i64 {
                fn a4() -> i64 {
                    return z;
                }
                return a4();
            }
            return a3();
        }
        return a2();
    }
    return a1() * 3;
}

# 跨层捕获 + 调用普通函数（验证捕获通路不干扰其它代码生成）
fn dbl(v: i64) -> i64 { return v * 2; }
fn deepcall(k: i64) -> i64 {
    fn p1() -> i64 {
        fn p2(v: i64) -> i64 {
            return dbl(v) + k;
        }
        return p2(7);
    }
    return p1();
}

# 中间层在嵌套定义**之后**引用自己的局部变量 —— 专门盯 K_FNBASE 的恢复。
#
# 解析完 i2 若不恢复 K_FNBASE，它就停在 i2 的基线上，于是 p、q 的下标
# 都 < K_FNBASE → 被误判成"捕获" → 生成 [rbp+off] 去读**外层**帧的同偏移处。
# 症状是值完全不对但**不报错**；两层时 K_NEST==0 恰好绕开了这条路径，
# 所以这个坑只有支持到三层才会显形。
fn midafter() -> i64 {
    let base: i64 = 1;
    fn m1() -> i64 {
        let p: i64 = 10;
        let q: i64 = 20;
        fn i2() -> i64 {
            return p + q + base;
        }
        i2();
        return p * 100 + q;
    }
    return m1() + base;
}

fn main() -> i64 {
    assert_eq("three levels read", l3(1), 36);
    assert_eq("three levels read 2", l3(100), 135);
    assert_eq("write across two levels", acc3(1000), 1012);
    assert_eq("four levels", l4(8), 15);
    assert_eq("write enclosing mid", writemid(), 10100);
    assert_eq("near vs far", nearfar(), 2101);
    assert_eq("five levels", l5(), 21);
    assert_eq("deep + call", deepcall(5), 19);
    assert_eq("mid uses own local after nested", midafter(), 1021);
    return test_done();
}
