#!/bin/bash
# 微基准：魔数（乘法倒数） vs idiv 的成本差
#
# 为什么在同一次运行内**交替**测量：机器噪声很大（实测同一个 workload
# 在 6.5ms ~ 10.1ms 之间波动，±50%），分开跑两次根本比不出差异。
# 交替测 + 打印每一轮，可以看出差异是否稳定大于噪声。
set -e
cd "$(dirname "$0")/.."
mkdir -p build
./bin/moc examples/divbench.mo build/divbench.elf
./build/divbench.elf
