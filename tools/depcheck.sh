#!/bin/bash
# 依赖自检：每个标准库文件都必须能「被单独引用」而编译成功。
#
# 为什么要这个检查：
# 库文件如果没声明自己用到的 import，平时是能编译的 ——
# 因为主文件恰好 import 了那个库。但只要有人单独引用它，立刻失败。
# 这类缺陷在测试里很难暴露（所有测试都 import 一大堆），
# 却是真实使用时最常见的踩坑方式。
set -e
cd "$(dirname "$0")/.."
MOC=./bin/moc
TMP=/tmp/modep
rm -rf $TMP && mkdir -p $TMP
cp lib/*.mo $TMP/
FAIL=0
# 例外：**约定回调**的库。
#
# proc.mo 的进程池要求使用者自己定义 `pool_work(task) -> i64`
# —— 因为墨语言没有函数指针，这是唯一能表达"回调"的方式。
# 所以单独引用 proc.mo 时必须补一个桩，否则必然 undefined symbol。
#
# 这不是在掩盖问题：它反映的是"没有函数指针"这个真实的语言限制，
# 已在 docs/process.md 里写明。
stub_for() {
  case "$1" in
    proc.mo) printf '\nfn pool_work(task: i64) -> i64 { return task; }\n' ;;
    *) echo "" ;;
  esac
}

for f in lib/*.mo; do
  b=$(basename $f)
  STUB=$(stub_for "$b")
  printf 'import "%s";\n%s\nfn main() -> i64 { return 0; }\n' "$b" "$STUB" > $TMP/test.mo
  out=$( cd $TMP && $OLDPWD/$MOC 2>&1 )
  if [ -n "$out" ]; then
    echo "FAIL $b 单独引用时编译失败:"
    echo "$out" | head -3 | sed 's/^/    /'
    FAIL=1
  fi
done
# 反向检查：库不应依赖「主文件先 import 过」
if [ $FAIL -eq 0 ]; then echo "depcheck: OK（$(ls lib/*.mo | wc -l) 个库文件均可独立引用）"; else exit 1; fi
