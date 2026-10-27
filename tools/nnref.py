#!/usr/bin/env python3
"""nnref —— 用 Python 复现墨语言 nn.mo 的**定点**运算，用于比对。

为什么要它：

    反向传播的下标 / 权重版本最容易搞错，而**XOR 收敛并不能证明它是对的**
    —— 这次就是：边算 delta 边更新权重的错误实现照样收敛到 4/4，
    只有逐轮 loss 比对才暴露出来。

所以这里必须**按位复现**墨语言的实现，包括：

  * Q16.16 定点乘法 (a*b + 32768) >> 16
  * C 风格的**向零截断**除法（Python 的 // 是 floor，必须区分！）
  * i64 溢出回绕（LCG）
  * 算术右移（对负数向 -inf 取整）

任何一处用了浮点或 floor 除法，比对就会漂移，也就失去了意义。
"""

SC = 65536


def tdiv(a, b):
    """C 风格整数除法：向零截断。"""
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def fmul(a, b):
    return (a * b + 32768) >> 16


def fdiv(a, b):
    if b == 0:
        return 0
    return tdiv(a * SC, b)


def milli(x):
    return (x * 1000 + 32768) >> 16


def isqrt(n):
    if n <= 0:
        return 0
    if n == 1:
        return 1
    x = n
    for _ in range(64):
        y = (x + n // x) // 2
        if y >= x:
            break
        x = y
    while x * x > n:
        x -= 1
    while (x + 1) * (x + 1) <= n:
        x += 1
    return x


def fsqrt(x):
    return 0 if x <= 0 else isqrt(x * SC)


def tanhf(x):
    if x >= 196608:
        return 65536
    if x <= -196608:
        return -65536
    xx = fmul(x, x)
    num = fmul(x, 1769472 + xx)
    den = 1769472 + 9 * xx
    return fdiv(num, den)


def sigmoid(x):
    return (SC + tanhf(x >> 1)) >> 1


def act(a, z):
    if a == 3:
        return tanhf(z)
    if a == 2:
        return sigmoid(z)
    if a == 1:
        return z if z > 0 else 0
    return z


def dact(a, z):
    if a == 3:
        t = tanhf(z)
        return SC - fmul(t, t)
    if a == 2:
        s = sigmoid(z)
        return fmul(s, SC - s)
    if a == 1:
        return SC if z > 0 else 0
    return SC


seed = 12345


def rnd():
    global seed
    seed = (seed * 1103515245 + 12345) % (1 << 64)
    if seed >= (1 << 63):
        seed -= (1 << 64)
    v = (seed >> 8) & 0xFFFFFF
    return v - 8388608


def rand_fp(r):
    return fmul(rnd() >> 7, r)


sizes = [2, 4, 1]
nl = 3
ACT = [0, 3, 2]          # 1 层 tanh，2 层 sigmoid
lr = 32768               # 0.5
X = [[0, 0], [0, SC], [SC, 0], [SC, SC]]
Y = [[0], [SC], [SC], [0]]

W = {}
B = {}


def init():
    for l in range(1, nl):
        np_, nc = sizes[l - 1], sizes[l]
        r = fdiv(SC, fsqrt(np_ * SC))
        for i in range(nc):
            B[(l, i)] = 0
            for j in range(np_):
                W[(l, i, j)] = rand_fp(r)


def train(x, y):
    A, Z, D = {}, {}, {}
    for i in range(sizes[0]):
        A[(0, i)] = x[i]
    for l in range(1, nl):
        for j in range(sizes[l]):
            s = B[(l, j)]
            for k in range(sizes[l - 1]):
                s += fmul(W[(l, j, k)], A[(l - 1, k)])
            Z[(l, j)] = s
            A[(l, j)] = act(ACT[l], s)

    loss = 0
    # 第一阶段：算所有 delta（权重未动）
    for l in reversed(range(1, nl)):
        for i in range(sizes[l]):
            if l == nl - 1:
                e = A[(l, i)] - y[i]
                loss += fmul(e, e)
                D[(l, i)] = fmul(e, dact(ACT[l], Z[(l, i)]))
            else:
                s = 0
                for k in range(sizes[l + 1]):
                    s += fmul(W[(l + 1, k, i)], D[(l + 1, k)])
                D[(l, i)] = fmul(dact(ACT[l], Z[(l, i)]), s)
    # 第二阶段：更新权重
    for m in range(1, nl):
        for j in range(sizes[m]):
            dj = D[(m, j)]
            for k in range(sizes[m - 1]):
                W[(m, j, k)] -= fmul(lr, fmul(dj, A[(m - 1, k)]))
            B[(m, j)] -= fmul(lr, dj)
    return loss


init()
for ep in range(3):
    loss = 0
    for s in range(4):
        loss = train(X[s], Y[s])
    print("epoch %d  loss %d" % (ep, milli(loss)))
