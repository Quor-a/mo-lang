# 85 —— sfmt：插值写入任意目标缓冲
#
# sfmt(&b, f"共 {n} 篇")
#   → strcat(&b, "共 "); strcat_i64(&b, n); strcat(&b, " 篇");
#
# 逐字节比对在 tools/fstrtest.sh 里（与手写 strcat 对照）。
import "io.mo";
import "str.mo";

fn main() -> i64 {
    let b: [128] byte = 0;
    let n: i64 = 7;
    let a: i64 = 3;
    let name: ptr = "world";

    sfmt(&b, f"共 {n} 篇");
    print(&b); print("\n");

    let c: [128] byte = 0;
    sfmt(&c, f"{a} + 4 = 7");
    print(&c); print("\n");

    let d: [128] byte = 0;
    sfmt(&d, f"hello {name}!");
    print(&d); print("\n");

    let e: [128] byte = 0;
    sfmt(&e, f"plain");
    print(&e); print("\n");

    # 多次 sfmt 追加到同一个缓冲
    let g: [128] byte = 0;
    sfmt(&g, f"a{n}b");
    sfmt(&g, f"-{a}-");
    print(&g); print("\n");
    return 0;
}
