#!/bin/bash
# cnntest —— 卷积神经网络验证
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
W=/tmp/mocnn; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/
cp $ROOT/examples/cnn.mo $W/test.mo
echo "cnntest:"
( cd $W && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  ✓ 编译"; else echo "  ✗ 编译"; fail=$((fail+1)); fi
OUT=$( cd $W && timeout 600 ./out.elf 2>&1 )
echo "$OUT" | grep -q "CNN solved"
if [ $? -eq 0 ]; then echo "  ✓ 8/8 形状分类收敛"; else echo "  ✗ 未收敛"; fail=$((fail+1)); fi
echo "$OUT" | grep -q "correct: 8 / 8"
if [ $? -eq 0 ]; then echo "  ✓ 全部样本预测正确"; else echo "  ✗ 预测有误"; fail=$((fail+1)); fi
if [ $fail -eq 0 ]; then echo "cnntest: OK（CNN 可训练）"; else echo "cnntest: $fail 项未通过"; exit 1; fi
