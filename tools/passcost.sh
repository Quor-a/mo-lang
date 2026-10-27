#!/bin/bash
# 微基准：量化「栈传递 vs 寄存器传递」的成本差
#
# 目的：判断"寄存器分配"到底值不值。刻意让两个版本的**指令条数相同**，
# 只换传递方式 —— 于是测出来的是"传递方式"本身的成本，而不是
# "少发几条指令"的收益。两者常被混为一谈。
set -e
cd "$(dirname "$0")"
D=passcost
mkdir -p build
gcc -O2 -c $D/micro.s -o build/micro.o
gcc -O2 -c $D/main.c  -o build/micromain.o
gcc build/micro.o build/micromain.o -o build/passcost
./build/passcost
