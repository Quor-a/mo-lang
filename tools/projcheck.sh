#!/bin/bash
# projcheck —— 项目完整性自检
#
# 背景：这个项目有过好几类「静默漂移」：
#   - src/mo/ 是源、src/compiler.mo 是拼接产物，改了产物没同步回源
#   - 标准库加了函数，测试里却仍引用旧副本
#   - 新库写完了，却没有一个测试引用它
#   - 工具写完了，却没有文档提到它
# 每一类都不是编译错误，而是"看起来能用、实际已经坏了"。
# 这个脚本把它们全部变成**可自动验证的红灯**。
#
#   bash tools/projcheck.sh
set +e
cd "$(dirname "$0")/.."
FAIL=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. 编译器源与拼接产物一致 ==="
cat src/mo/compiler_part*.mo > /tmp/pc_join.mo
if diff -q /tmp/pc_join.mo src/compiler.mo >/dev/null; then ok "src/mo/ 拼接 == src/compiler.mo"
else bad "拼接产物与 compiler.mo 不一致（改了 compiler.mo 没同步回 src/mo/）"; fi

echo "=== 2. 每个标准库都能被单独引用 ==="
bash tools/depcheck.sh >/dev/null 2>&1
if [ $? -eq 0 ]; then ok "全部库可独立引用"; else bad "有库缺少自己的 import（见 depcheck）"; fi

echo "=== 3. 每个标准库都有测试覆盖 ==="
MISS=""
for f in lib/*.mo; do
  b=$(basename "$f" .mo)
  # 需要 libc / pthread 的库（thread / csp）跑不了裸 moc，
  # 由 tools/ 下专用脚本内嵌测试覆盖 —— 只扫 tests/ 会把它们误报成"无覆盖"
  if ! grep -rql "\"$b.mo\"" tests/ tools/*test*.sh 2>/dev/null; then MISS="$MISS $b"; fi
done
if [ -z "$MISS" ]; then ok "全部库均有测试引用"
else bad "以下库没有任何测试引用：$MISS"; fi

echo "=== 4. 每个示例都能编译 ==="
BAD=""
for e in examples/*.mo; do
  # 跨后端示例（内核 / Windows / 安卓原生 / 内核模块）不由原生后端编译，
  # 它们各自有 tools/targets_test.sh 覆盖。用 mo-target: 标注区分。
  if head -20 "$e" | grep -q "mo-target:"; then continue; fi
  rm -rf /tmp/pc_ex && mkdir -p /tmp/pc_ex
  cp lib/*.mo /tmp/pc_ex/ 2>/dev/null
  cp "$e" /tmp/pc_ex/test.mo
  ( cd /tmp/pc_ex && timeout 60 "$OLDPWD/bin/moc" >/dev/null 2>&1 ) || BAD="$BAD $(basename $e)"
done
if [ -z "$BAD" ]; then ok "全部示例可编译"
else bad "以下示例编译失败：$BAD"; fi

echo "=== 5. 每个工具都被文档提及 ==="
UN=""
for t in tools/*.sh tools/*.mo; do
  [ -f "$t" ] || continue
  b=$(basename "$t")
  n=${b%.*}
  case "$b" in run.sh) continue;; esac
  if grep -rql "$b" docs/*.md README.md 2>/dev/null; then continue; fi
  if grep -rql "$n" docs/*.md README.md 2>/dev/null; then continue; fi
  UN="$UN $b"
done
if [ -z "$UN" ]; then ok "全部工具有文档"
else bad "以下工具无文档提及：$UN"; fi

echo "=== 6. 文档非空非占位 ==="
SM=""
for f in docs/*.md; do
  n=$(wc -c < "$f")
  if [ "$n" -lt 800 ]; then SM="$SM $(basename $f)($n)"; fi
done
if [ -z "$SM" ]; then ok "全部文档有实质内容"
else bad "以下文档过短（可能是占位）：$SM"; fi

echo "=== 7. 版本号一致 ==="
V=$(cat VERSION)
if grep -q "## \[$V\]" CHANGELOG.md; then ok "VERSION=$V 且 CHANGELOG 有对应条目"
else bad "VERSION=$V 在 CHANGELOG 里没有条目"; fi

echo "=== 8. 断言必须影响退出码 ==="
# 🔴 v1.115 发现的一类系统性空转：tests/ 下有 12 个文件用了 assert_eq，
#    却以 `return 0;` 收尾 —— assert_eq 的返回值被丢弃，
#    于是**断言全错也照样 PASS**。实测正是靠这条钉子才挖出
#    tests/97 里一条期望值写错的断言（expected(0-7)/2 == 0，真值 -3），
#    它已经悄无声息地"失败"了很久。
#    这不是个别笔误，是一类会让整个测试套件失去意义的写法，必须自动拦。
#
# 🔴🔴 v1.115 又发现本条检查自己的盲区（检查工具也会静默失效）：
#    第一版判据是"文件里出现 test_done 字样就放行"。而 16 个文件写的是
#        test_done();   ← 返回值被丢弃
#        return 1;      ← 期望退出码恰好也是 1
#    **断言失败照样返回 1，与期望值相等 → 判 PASS**。
#    其中 15 个是 `# expect: 1`（约定"main 返回 1 表示跑通"的老测试），
#    失败与成功共用同一个退出码，天然无法区分。
#    所以判据改成"test_done 的结果必须被使用"：
#        要么 return test_done();         （失败数直接当退出码）
#        要么 let f = test_done(); if f != 0 { return 期望+1; }
#    光"出现字样"不算数 —— 这正是上一版漏掉 16 个的原因。
EMPTY=""
for f in tests/*.mo; do
  if grep -q "assert_eq\|assert_true" "$f" 2>/dev/null; then
    if ! grep -q "return test_done" "$f" && ! grep -q "= test_done();" "$f"; then
      EMPTY="$EMPTY $(basename $f)"
    fi
  fi
done
if [ -z "$EMPTY" ]; then ok "全部断言都会进退出码（test_done 结果被使用）"
else bad "以下测试丢弃了 test_done 的返回值（断言失败不影响退出码）：$EMPTY"; fi

echo "=== 9. 无残留脏文件 ==="
JUNK=""
for p in p1.back *.tmp *.bak core *.o *.elf; do
  ls $p >/dev/null 2>&1 && JUNK="$JUNK $p"
done
if [ -z "$JUNK" ]; then ok "仓库无残留产物"
else bad "发现残留文件：$JUNK"; fi

echo "=== 10. all 链里的目标都必须有定义 ==="
# 🔴 v1.115 发现：`fmathmut` 从 1.114 起就写在 all 的依赖里，
#    却从来没有对应的目标定义 —— `make all` 走到它直接
#    "No rule to make target 'fmathmut'" 失败退出。
#    也就是说 **all 链从来没真正跑通过**，而分项都是绿的，
#    于是"make all 全过"这句话一直是假的。
#    "写进 all" 和 "接上了 all" 是两件事，必须能自动验证。
ALLDEPS=$(grep -m1 '^all:' Makefile | sed 's/^all: *//' | tr ' ' '\n' | sed 's/://' | grep -v '^$')
MISS=""
for t in $ALLDEPS; do
  case "$t" in
    all|sync-check|seedalign|boot|test|motools|check|targets|\#|*) ;;
  esac
  # 跳过注释尾巴（all 行末尾常有 # ---...---）
  case "$t" in \#*|---*) continue;; esac
  grep -q "^$t:" Makefile || MISS="$MISS $t"
done
if [ -z "$MISS" ]; then ok "all 链全部目标有定义"
else bad "all 链里有未定义的目标（make all 会直接失败）：$MISS"; fi

echo "=== 11. bin/moc 是用当前源码编出来的 ==="
# 🔴 v1.136 发现的一类静默失效：变异脚本（switchmut / formut / ...）
#    收尾只还原**源码**，`cp 备份 src/compiler.mo` 与上一次构建常常落在
#    同一秒 —— make 只看 mtime，认为 bin/moc 仍比源码新而**跳过重建**。
#    于是跑完变异脚本之后，整个项目一直在用一个**被改坏的编译器**跑测试：
#    v1.136 就是这样出现 "empty case: got 0, want 42" 的（M5 恰好是
#    "空 case 不穿透"），而源码本身是干净的，看代码永远看不出来。
#    **源码干净 ≠ 产物干净**。build.sh 每次构建都写 bin/moc.srcmd5，
#    这里拿它和当前 src/compiler.mo 的 md5 比对。
if [ -f bin/moc ] && [ -f bin/moc.srcmd5 ]; then
  CUR=$(md5sum src/compiler.mo | cut -d' ' -f1)
  REC=$(cat bin/moc.srcmd5)
  if [ "$CUR" = "$REC" ]; then ok "bin/moc 与 src/compiler.mo 对应"
  else bad "bin/moc 是用**另一份源码**编出来的（变异脚本收尾没重建？）—— 直接跑 make -B bin/moc"; fi
else
  bad "缺少 bin/moc 或 bin/moc.srcmd5（先构建一次）"
fi

echo
if [ $FAIL -eq 0 ]; then echo "projcheck: OK（11 项全通过）"
else echo "projcheck: $FAIL 项未通过"; exit 1; fi
