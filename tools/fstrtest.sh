#!/usr/bin/env bash
# fstrtest —— 字符串插值与手写 print 的逐字节比对
#
# 光"能跑通"不够：插值最容易错的是**片段边界**（丢首字符、丢尾片段）。
# 所以让 f-string 版本和手写 print+print_i64 版本各跑一次，diff 比对。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

W=/tmp/mofstr; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

cat > $W/fstr.mo <<'EOF'
import "io.mo";
fn main() -> i64 {
    let n: i64 = 7;
    let a: i64 = 3;
    let b: i64 = 4;
    print(f"共 {n} 篇\n");
    print(f"{a} + {b} = 7\n");
    print(f"a*b = {a * b}\n");
    print(f"sum = {a + b + n}\n");
    print(f"plain\n");
    print(f"{n}\n");
    print(f"x{n}y\n");
    let name: ptr = "world";
    print(f"hello {name}\n");
    print(f"{name} has {n}\n");
    print(f"lit {"direct"}\n");
    return 0;
}
EOF

cat > $W/hand.mo <<'EOF'
import "io.mo";
fn main() -> i64 {
    let n: i64 = 7;
    let a: i64 = 3;
    let b: i64 = 4;
    print("共 "); print_i64(n); print(" 篇\n");
    print_i64(a); print(" + "); print_i64(b); print(" = 7\n");
    print("a*b = "); print_i64(a * b); print("\n");
    print("sum = "); print_i64(a + b + n); print("\n");
    print("plain\n");
    print_i64(n); print("\n");
    print("x"); print_i64(n); print("y\n");
    let name: ptr = "world";
    print("hello "); print(name); print("\n");
    print(name); print(" has "); print_i64(n); print("\n");
    print("lit "); print("direct"); print("\n");
    return 0;
}
EOF

fail=0
for t in fstr hand; do
    cp $W/$t.mo $W/test.mo
    ( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
    if [ ! -f $W/out.elf ]; then echo "  ✗ $t 编译失败"; fail=$((fail+1)); continue; fi
    ( cd $W && timeout 60 ./out.elf > $W/$t.out 2>&1 )
done

if [ $fail -eq 0 ]; then
    if diff -q $W/fstr.out $W/hand.out >/dev/null 2>&1; then
        echo "  ✓ f-string 输出 == 手写 print 输出（逐字节）"
    else
        echo "  ✗ 输出不一致："
        diff $W/fstr.out $W/hand.out | head -10
        fail=$((fail+1))
    fi
fi

# sfmt：插值写入目标缓冲，与手写 strcat/strcat_i64 逐字节比对
cat > $W/fsfmt.mo <<'EOF'
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
    let g: [128] byte = 0;
    sfmt(&g, f"a{n}b");
    sfmt(&g, f"-{a}-");
    print(&g); print("\n");
    return 0;
}
EOF

cat > $W/hsfmt.mo <<'EOF'
import "io.mo";
import "str.mo";
fn main() -> i64 {
    let b: [128] byte = 0;
    let n: i64 = 7;
    let a: i64 = 3;
    let name: ptr = "world";
    strcat(&b, "共 "); strcat_i64(&b, n); strcat(&b, " 篇");
    print(&b); print("\n");
    let c: [128] byte = 0;
    strcat_i64(&c, a); strcat(&c, " + 4 = 7");
    print(&c); print("\n");
    let d: [128] byte = 0;
    strcat(&d, "hello "); strcat(&d, name); strcat(&d, "!");
    print(&d); print("\n");
    let e: [128] byte = 0;
    strcat(&e, "plain");
    print(&e); print("\n");
    let g: [128] byte = 0;
    strcat(&g, "a"); strcat_i64(&g, n); strcat(&g, "b");
    strcat(&g, "-"); strcat_i64(&g, a); strcat(&g, "-");
    print(&g); print("\n");
    return 0;
}
EOF

sfail=0
for t in fsfmt hsfmt; do
    cp $W/$t.mo $W/test.mo
    ( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
    if [ ! -f $W/out.elf ]; then echo "  ✗ $t 编译失败"; sfail=$((sfail+1)); continue; fi
    ( cd $W && timeout 60 ./out.elf > $W/$t.out 2>&1 )
done
if [ $sfail -eq 0 ]; then
    if diff -q $W/fsfmt.out $W/hsfmt.out >/dev/null 2>&1; then
        echo "  ✓ sfmt 输出 == 手写 strcat 输出（逐字节）"
    else
        echo "  ✗ sfmt 输出不一致："; diff $W/fsfmt.out $W/hsfmt.out | head -10
        fail=$((fail+1))
    fi
fi

# ptr(v) 转换：库函数返回 i64（返回类型不支持 ptr），
# 插值时会被当成数字打印出地址数值。ptr(v) 显式标注"这是个地址"。
cat > $W/ptr.mo <<'EOF'
import "io.mo";
import "str.mo";
fn main() -> i64 {
    let s: ptr = "hello";
    let t: i64 = str_trim(s);
    let b: [128] byte = 0;
    sfmt(&b, f"[{ptr(t)}]");
    print(&b); print("\n");
    let c: [128] byte = 0;
    let n: i64 = 5;
    sfmt(&c, f"n={n} s={ptr(t)}");
    print(&c); print("\n");
    return 0;
}
EOF
cp $W/ptr.mo $W/test.mo
( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ -f $W/out.elf ]; then
    OP=$( cd $W && timeout 60 ./out.elf 2>&1 | head -1 )
    if [ "$OP" = "[hello]" ]; then
        echo "  ✓ ptr(v) 让 i64 被当作字符串插值"
    else
        echo "  ✗ ptr(v) 无效: $OP"; fail=$((fail+1))
    fi
else
    echo "  ✗ ptr 编译失败"; fail=$((fail+1))
fi

# 普通字符串里的花括号必须**不受影响**（site.mo 生成的 CSS/HTML 全是花括号）
cat > $W/braces.mo <<'EOF'
import "io.mo";
fn main() -> i64 {
    print("a{b}c\n");
    return 0;
}
EOF
cp $W/braces.mo $W/test.mo
( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ -f $W/out.elf ]; then
    O=$( cd $W && timeout 60 ./out.elf 2>&1 )
    if [ "$O" = "a{b}c" ]; then
        echo "  ✓ 普通字符串里的 { } 保持原义"
    else
        echo "  ✗ 普通字符串花括号被破坏: $O"; fail=$((fail+1))
    fi
else
    echo "  ✗ braces 编译失败"; fail=$((fail+1))
fi

# 必须用 f 前缀：f" 才会插值，单独的 f 仍是标识符
cat > $W/ident.mo <<'EOF'
import "io.mo";
fn f(x: i64) -> i64 { return x + 1; }
fn main() -> i64 {
    print_i64(f(1));
    print("\n");
    return 0;
}
EOF
cp $W/ident.mo $W/test.mo
( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ -f $W/out.elf ]; then
    O2=$( cd $W && timeout 60 ./out.elf 2>&1 )
    if [ "$O2" = "2" ]; then
        echo "  ✓ 名为 f 的函数仍可正常调用"
    else
        echo "  ✗ f 标识符被误判: $O2"; fail=$((fail+1))
    fi
else
    echo "  ✗ ident 编译失败"; fail=$((fail+1))
fi

if [ $fail -eq 0 ]; then echo "fstrtest: OK（字符串插值可用）"; exit 0; fi
echo "fstrtest: FAILED（$fail 项）"; exit 1
