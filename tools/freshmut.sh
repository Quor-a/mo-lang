#!/bin/bash
# freshbuild 的变异验证：证明它测的正是"目录缺失"那条因果链，不是碰巧通过。
#
# 变异方式：去掉 $(SEED) 规则末尾的 | bin，回到缺陷状态。
# 注意：不要改成"改目录目标名"那类间接变异 —— 实测没区分度（见 docs/freshbuild.md）。
cd "$(dirname "$0")/.."
FAIL=0
MF=Makefile
cp "$MF" /tmp/mofreshmut_Makefile.bak
restore(){
  cp /tmp/mofreshmut_Makefile.bak "$MF"
  rm -f /tmp/mofreshmut_Makefile.bak
}
trap restore EXIT

python3 - <<'EOF'
p='Makefile'
s=open(p).read()
old="$(SEED): $(ASM)/base.s $(ASM)/lex.s $(ASM)/sym.s $(ASM)/expr.s $(ASM)/stmt.s $(ASM)/main.s | bin"
new="$(SEED): $(ASM)/base.s $(ASM)/lex.s $(ASM)/sym.s $(ASM)/expr.s $(ASM)/stmt.s $(ASM)/main.s"
if old not in s:
    raise SystemExit("变异点未找到，脚本空转")
open(p,'w').write(s.replace(old,new))
EOF
[ $? -ne 0 ] && { echo "freshmut: 变异失败"; FAIL=$((FAIL+1)); }

echo "=== 基线应为 3/3，变异后必须掉下来 ==="
bash tools/freshbuild.sh > /tmp/mofreshmut.log 2>&1
RC=$?
grep -E "^freshbuild:" /tmp/mofreshmut.log
if [ "$RC" -eq 0 ]; then
  echo "✗ 变异后仍通过 —— freshbuild 是空转的"; FAIL=$((FAIL+1))
else
  echo "✓ 变异被捕获（退出码 $RC）"
fi
# 报错内容必须就是那个缺陷，不能是别的原因
if grep -q "cannot open output file ../../bin/seed" /tmp/mofreshmut.log; then
  echo "✓ 报错正是目录缺失那条（ld: cannot open output file ../../bin/seed）"
else
  echo "✗ 失败原因不是目录缺失，变异没打中目标"; FAIL=$((FAIL+1))
fi

restore; trap - EXIT

# 收尾核对：变异字符串必须已不在 Makefile 里（否则污染后续所有构建）
if grep -q '^\$(SEED): .*main\.s$' "$MF"; then
  echo "✗ 还原失败：变异仍留在 Makefile 里"; FAIL=$((FAIL+1))
else
  echo "✓ 源码已还原"
fi

echo "freshmut: $([ $FAIL -eq 0 ] && echo OK || echo "$FAIL 项失败")"
[ "$FAIL" -eq 0 ]
