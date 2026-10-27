#!/bin/bash
# nntest —— 神经网络验证
#
# 两套检查，缺一不可：
#
#   1. **端到端**：XOR 必须 4/4。XOR 是非线性可分的，没有隐藏层、
#      反向传播错了，都几乎必然收敛不了。
#   2. **逐轮 loss 与 Python 定点实现比对**：
#      光看 XOR 收敛**不够** —— 曾经"边算 delta 边更新权重"的错误实现
#      照样收敛到 4/4，只有逐轮 loss 比对才暴露出来（见 nn.mo 注释）。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
fail=0
chk(){ if [ "$1" = "0" ]; then echo "  ✓ $2"; else echo "  ✗ $2"; fail=$((fail+1)); fi; }

W=/tmp/monn; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/
cp $ROOT/examples/nnet.mo $W/test.mo
echo "nntest:"
( cd $W && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
chk $? "  编译"

OUT=$( cd $W && timeout 600 ./out.elf 2>&1 )
echo "$OUT" | grep -q "XOR solved"
chk $? "  XOR 收敛到 4/4（端到端）"

# 逐轮 loss 比对
MO=$(echo "$OUT" | grep -E "^epoch [0-9] " | sed 's/  */ /g')
PY=$(python3 $ROOT/tools/nnref.py 2>/dev/null | sed 's/  */ /g')
if [ "$MO" = "$PY" ] && [ -n "$MO" ]; then
    echo "  ✓ 逐轮 loss 与定点参考实现一致"
else
    echo "  ✗ 逐轮 loss 不一致："
    echo "    墨语言: $MO"
    echo "    参考  : $PY"
    fail=$((fail+1))
fi

# 抽查定点基础：sigmoid/tanh 的已知值
python3 - "$ROOT" <<'PYEOF'
import sys
root = sys.argv[1]
src = open(root + '/tools/nnref.py').read()
ns = {}
exec(compile(src.split('sizes = [2')[0], 'nnref', 'exec'), ns)
fmul, SC = ns['fmul'], ns['SC']
ok = True
# sigmoid(0) 应为 0.5 = 32768
v = ns['sigmoid'](0)
if abs(v - 32768) > 2: ok = False; print("    sigmoid(0) =", v, "期望 ~32768")
# tanh(1.0) 应约 0.7616 → 49900 左右（Padé 近似有误差，放宽到 3%）
t = ns['tanhf'](SC)
if abs(t - 49900) > 1500: ok = False; print("    tanh(1) =", t, "期望 ~49900")
# 定点乘法 0.5*0.5 = 0.25
m = fmul(SC // 2, SC // 2)
if abs(m - 16384) > 1: ok = False; print("    0.5*0.5 =", m, "期望 16384")
print("  ✓ 定点基础（sigmoid/tanh/乘法）" if ok else "  ✗ 定点基础")
sys.exit(0 if ok else 1)
PYEOF
[ $? -eq 0 ] || fail=$((fail+1))

if [ $fail -eq 0 ]; then echo "nntest: OK（神经网络可训练且与参考实现一致）"; else echo "nntest: $fail 项未通过"; exit 1; fi
