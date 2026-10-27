# 泛型（generic / instantiate）

```mo
generic fn maxg<T>(a: T, b: T) -> T {
    if a > b { return a; }
    return b;
}
instantiate maxg(i64) as maxi;
instantiate maxg(f64) as maxf;

fn main() -> i64 {
    print_i64(maxi(3, 9));      # 9
    print_f64(maxf(1.5, 4.25)); # 4.250000
    return 0;
}
```

一份源码，生成多份类型特化的机器码。传 `i64` 走整数比较，
传 `f64` 走浮点比较 —— 各自的指令确实不同，不是同一份代码换个名字。

## 为什么不需要 IR

通常认为泛型需要类型系统重写或 IR。这里绕开了，靠两点：

1. **保存函数体源码文本**，instantiate 时把类型参数名替换成实际类型，重新解析
2. `sbyte()` 用的是 `heap + K_SRCBASE + i` —— **源码基址可切换**

于是展开出的文本写进临时区，切过去解析，再切回来。整个机制不到 200 行。

## 实现流程

1. `generic fn name<T>(...)`：记录函数名、类型参数名、`(` 到函数体 `}` 之后的源码区间，**不解析、不发射代码**
2. `instantiate name(i64) as newname;`：先预登记符号 → 展开文本 → 切源码 → `parse_func()` → 切回

## 🔴 五个坑，每个都让"看起来对"的代码悄悄错

**1. `expect(";")` 会让恢复点偏后一个 token。**

`expect` 内部会 `next_token`，而 `next_token` 结束后 `K_POS` 指向**新读到那个 token 的末尾**。
拿它当恢复点，切回来就从 `fn` 之后继续，`fn` 整个被丢掉（实测恢复后读到的 token 是 `main`）。

**2. 自己写的"推进位置"漏了同步 `K_CPOS`。**

`advance_lc(p)` 才是正确做法：它一并更新 `K_LINE`/`K_COL`/`K_CPOS`。
自己逐字节推进只改前三者，`K_CPOS` 留在旧值 → 下次 `next_token` 从旧位置**再算一遍**行号，
行号被翻倍累加。实测 11 行的文件报"第 9 行"，列号也全错，把人完全带偏。

**3. `advance_lc` 不动 `K_POS`。**

补行号的同时必须显式 `sv(K_POS, pe)`，否则 `next_token` 仍从 `(` 附近读，
把形参列表当成下一条语句。

**4. 新函数名必须先登记，再切过去解析。**

`parse_func` 结束时会把符号表回滚到函数开始处（清局部变量）。
正常函数靠 `predeclare()` 预先登记在基线之前（源码里扫 `fn`），
而展开出的函数不在源码里，predeclare 扫不到 —— `sym_add` 刚加进去就被回滚掉了，
症状是调用点报 **syntax error** 而不是"未定义"。

**5. `predeclare` 会把 `generic fn maxg<...>` 也当成普通函数登记。**

放任不管的话，写 `maxg(1,2)` 会生成一个地址无意义的 call —— 编译通过、运行才崩。
现在把它的 kind 改成变量，调用点会明确报 `undefined symbol 'maxg'`。

## 已知限制

- 替换是**文本级**的，在标识符边界上发生（形参 `Tx` 不会被当成 `T`）
- 实例化出来的函数，报错行号指向展开后的临时源码，不是原文件
- 最多 32 个泛型、每个最多 4 个类型参数、函数体 ≤ 8180 字节
- 没有自动实例化：必须显式写 `instantiate`

## 验证：`tests/94_generic.mo`

i64/f64 两种实例、两个类型参数、与类型参数同前缀的形参、泛型体内调用普通函数。
故意改错期望值会打印 `FAIL max i64 a: got 9, want 99`，说明断言真的在起作用。
