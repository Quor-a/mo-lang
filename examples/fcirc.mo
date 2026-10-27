# fcirc —— 用 f64 做真正的几何计算
#
#   ./fcirc
#
# 为什么写它：单元测试只能证明 f64 "能算"。这是个**真程序** ——
# 有输入（半径表）、有计算（圆面积/周长/球体积）、有输出（格式化）。
#
# 顺便验证 f64 能否作为**函数参数与返回值**在多层调用间正确传递 ——
# 这是"能算"和"能用"的分界线。
import "io.mo";

fn circle_area(r: f64) -> f64 { return r * r * 3.14159265; }
fn circle_peri(r: f64) -> f64 { return 2.0 * r * 3.14159265; }
fn sphere_vol(r: f64) -> f64 { return r * r * r * 3.14159265 * 4.0 / 3.0; }

fn row(r: f64) -> i64 {
    print("r=");
    print_f64(r);
    print("   area=");
    print_f64(circle_area(r));
    print("   peri=");
    print_f64(circle_peri(r));
    print("   vol=");
    print_f64(sphere_vol(r));
    print("\n");
    return 0;
}

fn main() -> i64 {
    print("circle / sphere, computed with f64\n");
    row(1.0);
    row(2.5);
    row(10.0);
    row(0.5);
    return 0;
}
