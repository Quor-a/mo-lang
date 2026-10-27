#!/bin/bash
# shtest —— 验证"被 C 调用"：墨语言编译成共享库，C 程序链接并调用
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/moshtest
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

# 墨语言库：纯运算 + 读全局变量 + 写全局变量
cat > mylib.mo <<'MO'
var CNT: i64 = 42;
fn mo_add(a: i64, b: i64) -> i64 { return a + b; }
fn mo_get() -> i64 { return CNT; }
fn mo_bump() -> i64 { CNT = CNT + 1; return CNT; }
fn main() -> i64 { return 0; }
MO
$MOC mylib.mo -shared mylib.o >/dev/null 2>&1
ck "$?" "0" "编译 -shared 生成 .o"
bash "$LINK" mylib.o -shared -o libmo.so >/dev/null 2>&1
ck "$?" "0" "ld -shared 生成 libmo.so"

cat > app.c <<'CEOF'
#include <stdio.h>
long mo_add(long a, long b);
long mo_get(void);
long mo_bump(void);
int main(void) {
    // 🔴 不能把四个调用写进同一个 printf —— C 的实参求值顺序**未定义**，
    //    gcc 从右往左求值，于是 mo_bump() 先跑、mo_get() 读到 43。
    //    墨语言本身完全正确，是测试把"未定义行为"当成了确定顺序。
    long a = mo_add(3, 4);
    long b = mo_get();
    long c = mo_bump();
    long d = mo_get();
    printf("%ld %ld %ld %ld\n", a, b, c, d);
    return 0;
}
CEOF
gcc -o app app.c -L. -lmo -Wl,-rpath,. 2>&1|head -3
ck "$?" "0" "gcc 链接 C 程序与墨语言库"
# 关键四项：纯运算 / 读全局 / 写全局后返回 / 写全局后持久化
ck "$(./app)" "7 42 43 43" "C 调用墨函数：运算 + 读全局变量 + 写全局变量"

# main 不能被导出（否则和 C 的 main 冲突）
if nm -D libmo.so 2>/dev/null | grep -qw " T main"; then
  FAIL=$((FAIL+1)); echo "  ✗ 库不应导出 main"; else PASS=$((PASS+1)); echo "  ✓ 库未导出 main（不与 C 的 main 冲突）"
fi
# 全局变量访问必须走 PC 相对重定位（绝对地址在 .so 里必崩）
if readelf -r mylib.o 2>/dev/null | grep -q "R_X86_64_PC32"; then
  PASS=$((PASS+1)); echo "  ✓ 全局变量引用走 R_X86_64_PC32（RIP 相对）"
else FAIL=$((FAIL+1)); echo "  ✗ 未生成 PC32 重定位"; fi

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ]
