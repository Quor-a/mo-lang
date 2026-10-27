#!/bin/bash
# adtest —— 自动微分验证（编译示例 + 检查梯度自检通过）
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
W=/tmp/moad; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/
cp $ROOT/examples/autograd.mo $W/test.mo
echo "adtest:"
( cd $W && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  ✓ 编译"; else echo "  ✗ 编译"; fail=$((fail+1)); fi
OUT=$( cd $W && timeout 600 ./out.elf 2>&1 )
echo "$OUT" | grep -q "grad check: PASS"
if [ $? -eq 0 ]; then echo "  ✓ 数值梯度与自动梯度一致"; else echo "  ✗ 梯度检查未通过"; fail=$((fail+1)); fi
echo "$OUT" | grep -q "autograd done"
if [ $? -eq 0 ]; then echo "  ✓ 自动梯度可驱动训练"; else echo "  ✗ 训练未完成"; fail=$((fail+1)); fi
# nnet2：只用 autodiff（不碰 nn.mo 的反向）训练 2-4-1 解 XOR
W2=/tmp/moad2; rm -rf $W2; mkdir -p $W2/lib
cp $ROOT/lib/*.mo $W2/lib/
cp $ROOT/examples/nnet2.mo $W2/test.mo
( cd $W2 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  ✓ nnet2 编译"; else echo "  ✗ nnet2 编译"; fail=$((fail+1)); fi
OUT2=$( cd $W2 && timeout 900 ./out.elf 2>&1 )
echo "$OUT2" | grep -q "grad check: PASS"
if [ $? -eq 0 ]; then echo "  ✓ 多层网络梯度自检（数值 vs 自动）"; else echo "  ✗ 多层网络梯度未通过"; fail=$((fail+1)); fi
echo "$OUT2" | grep -q "XOR solved by autodiff"
if [ $? -eq 0 ]; then echo "  ✓ 自动微分训练出 XOR（只写前向）"; else echo "  ✗ 未解出 XOR"; fail=$((fail+1)); fi

# mclass：softmax + 交叉熵做多分类
W3=/tmp/moad3; rm -rf $W3; mkdir -p $W3/lib
cp $ROOT/lib/*.mo $W3/lib/
cp $ROOT/examples/mclass.mo $W3/test.mo
( cd $W3 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  ✓ mclass 编译"; else echo "  ✗ mclass 编译"; fail=$((fail+1)); fi
OUT3=$( cd $W3 && timeout 1200 ./out.elf 2>&1 )
echo "$OUT3" | grep -q "grad check: PASS"
if [ $? -eq 0 ]; then echo "  ✓ 分类头梯度自检（数值 vs 自动）"; else echo "  ✗ 分类头梯度未通过"; fail=$((fail+1)); fi
echo "$OUT3" | grep -q "classification solved by autodiff"
if [ $? -eq 0 ]; then echo "  ✓ 自动微分训练出 4 类分类"; else echo "  ✗ 未解出分类"; fail=$((fail+1)); fi

# nnet_ad：自动微分驱动 nn.mo，与手写反向逐轮对照
W4=/tmp/moad4; rm -rf $W4; mkdir -p $W4/lib
cp $ROOT/lib/*.mo $W4/lib/
cp $ROOT/examples/nnet_ad.mo $W4/test.mo
( cd $W4 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  \u2713 nnet_ad 编译"; else echo "  \u2717 nnet_ad 编译"; fail=$((fail+1)); fi
OUT4=$( cd $W4 && timeout 1800 ./out.elf 2>&1 )
echo "$OUT4" | grep -q "loss 逐轮一致"
if [ $? -eq 0 ]; then echo "  \u2713 自动梯度 == 手写梯度（逐轮一致）"; else echo "  \u2717 两条路径分岔"; fail=$((fail+1)); fi
echo "$OUT4" | grep -q "both solved XOR"
if [ $? -eq 0 ]; then echo "  \u2713 两条路径都解出 XOR"; else echo "  \u2717 未解出 XOR"; fail=$((fail+1)); fi

# optim：三种优化器对照
W5=/tmp/moad5; rm -rf $W5; mkdir -p $W5/lib
cp $ROOT/lib/*.mo $W5/lib/
cp $ROOT/examples/optim.mo $W5/test.mo
( cd $W5 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  \u2713 optim 编译"; else echo "  \u2717 optim 编译"; fail=$((fail+1)); fi
OUT5=$( cd $W5 && timeout 1800 ./out.elf 2>&1 )
echo "$OUT5" | grep -q "all optimizers converged"
if [ $? -eq 0 ]; then echo "  \u2713 三种优化器都收敛"; else echo "  \u2717 有优化器未收敛"; fail=$((fail+1)); fi

# batch：batch 梯度应与逐样本之和（/bs）等价
W6=/tmp/moad6; rm -rf $W6; mkdir -p $W6/lib
cp $ROOT/lib/*.mo $W6/lib/
cp $ROOT/examples/batch.mo $W6/test.mo
( cd $W6 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  \u2713 batch 编译"; else echo "  \u2717 batch 编译"; fail=$((fail+1)); fi
OUT6=$( cd $W6 && timeout 1800 ./out.elf 2>&1 )
echo "$OUT6" | grep -q "grad equivalent"
if [ $? -eq 0 ]; then echo "  \u2713 batch 梯度 == 逐样本之和 / bs"; else echo "  \u2717 batch 梯度不等价"; fail=$((fail+1)); fi
echo "$OUT6" | grep -q "batch XOR solved"
if [ $? -eq 0 ]; then echo "  \u2713 batch 训练解出 XOR"; else echo "  \u2717 batch 未解出"; fail=$((fail+1)); fi

# cnn_ad：自动微分训练真正的 CNN
W7=/tmp/moad7; rm -rf $W7; mkdir -p $W7/lib
cp $ROOT/lib/*.mo $W7/lib/
cp $ROOT/examples/cnn_ad.mo $W7/test.mo
( cd $W7 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  \u2713 cnn_ad 编译"; else echo "  \u2717 cnn_ad 编译"; fail=$((fail+1)); fi
OUT7=$( cd $W7 && timeout 1800 ./out.elf 2>&1 )
echo "$OUT7" | grep -q "conv kernel elements updated"
if [ $? -eq 0 ]; then echo "  \u2713 梯度真的传回了卷积层（核被更新）"; else echo "  \u2717 卷积层未收到梯度"; fail=$((fail+1)); fi
echo "$OUT7" | grep -q "CNN solved by autodiff"
if [ $? -eq 0 ]; then echo "  \u2713 自动微分训练出 CNN"; else echo "  \u2717 CNN 未收敛"; fail=$((fail+1)); fi

# cnn_shift：平移泛化对照（证明卷积+池化真的有用）
W8=/tmp/moad8; rm -rf $W8; mkdir -p $W8/lib
cp $ROOT/lib/*.mo $W8/lib/
cp $ROOT/examples/cnn_shift.mo $W8/test.mo
( cd $W8 && timeout 900 $ROOT/bin/moc >/dev/null 2>&1 )
if [ $? -eq 0 ]; then echo "  \u2713 cnn_shift 编译"; else echo "  \u2717 cnn_shift 编译"; fail=$((fail+1)); fi
OUT8=$( cd $W8 && timeout 1800 ./out.elf 2>&1 )
echo "$OUT8" | grep -q "CNN        24 / 24            24 / 24"
if [ $? -eq 0 ]; then echo "  \u2713 CNN 完美泛化到未见位置（24/24）"; else echo "  \u2717 CNN 泛化不足"; fail=$((fail+1)); fi
echo "$OUT8" | grep -q "全连接     24 / 24            19 / 24"
if [ $? -eq 0 ]; then echo "  \u2713 全连接泛化明显更差（19/24）"; else echo "  \u2717 对照组结果异常"; fail=$((fail+1)); fi

if [ $fail -eq 0 ]; then echo "adtest: OK（墨语言会自己求导）"; else echo "adtest: $fail 项未通过"; exit 1; fi
