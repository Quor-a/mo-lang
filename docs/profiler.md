# 性能分析器 prof.mo

## 可用：手工插桩

```mo
import "prof.mo";

fn hot(n: i64) -> i64 {
    prof_enter("hot");          # 名字任意，自己起
    ...
    prof_leave();
    return s;
}

fn main() -> i64 {
    ...
    prof_report();              # 打印表格
    return 0;
}
```

输出：

```
=== profiler ===
函数                 调用次数      累计(ms)     自身(ms)
alpha               1        0        0
```

自身耗时 = 累计 − 直接子调用之和，所以能层层剥离出真正的热点。
计时用 `clock_gettime` 系统调用（228），**不依赖 libc**，
程序生成的是普通 ELF，不需要走 molink。

## 可用：`-p` 自动插桩

```bash
./bin/moc prog.mo -p prog.elf && ./prog.elf
```

编译器自动在每个函数入口插 `prof_enter("函数名")`、出口插 `prof_leave()`，
`main` 的出口额外插 `prof_report()`。

实跑结果（`mid` 里循环 20 次调 `leaf`）：

```
=== profiler ===
函数                 调用次数      累计(ms)     自身(ms)
main                1        64.2        0.0
mid                 1        64.2        0.0
leaf                20        64.2        64.2
```

**热点一眼可见**：`leaf` 自身 64.2ms，`mid`/`main` 自身都是 0 ——
时间全在 leaf 里。这就是"自身耗时 = 累计 − 子调用"的价值。

只对**主文件**的函数插桩：库函数（strlen/print）被调用几百万次，
插上去既污染数据又把程序拖慢到不可信。

## 挖出的坑（1.59.0 → 1.59.1）

**1. 🔴 状态槽号撞车（最隐蔽的一个）**

K_PROF/K_PROFMAIN/K_INIMP 第一版用了 488/496/504 —— 而这三个槽
已经被占用（局部变量表条数、函数表条数、当前函数下标）。
于是"是否插桩"读到的是完全无关的值，时开时关。

表现是 **-p 编译通过、程序正常、报告一行都没有**，全程无任何报错。

**2. 🔴 `g_movabs_rax` 对小于 2^32 的值发 `mov eax,imm32` 而不是 `movabs`**

所以搜索插桩字节时按 `48 b8` 找，永远找不到。
同一个"把立即数放进 rax"的需求有两种编码，取决于数值大小。

**3. 全局数组声明必须带初值**

`var A: [64] i64;` 报 syntax error，`var A: [64] i64 = 0;` 才合法。

**4. `str_eq` 不存在**，比较字符串要用 `strcmp(a,b) == 0`；
打印字符串是 `print(s)`，没有 `print_s`。

## 🔴 死区 bug 的根因（1.59.1 修好）

`parse_func` 里的顺序是这样的：

```
插桩代码（发射到代码段）        ← 1.59.0 错在这里
let addr = 4194304+176+K_CLEN  ← 这才是函数入口，写进 O_SA 供 call 用
...
g_prologue()                   ← push rbp / mov rbp,rsp / sub rsp,N
```

**插桩发在 `addr` 之前 → addr 落在插桩之后 → 调用直接跳到 prologue，
插桩永远不执行**，落在前一个函数末尾与本函数 prologue 之间的死区里。

修法：**早期只把函数名写进数据段**（`prof_emit_name` 只动数据段，
不影响 `K_CLEN`），真正的调用代码放到 `g_prologue()` 之后发射。
顺带必须早期就固化名字 —— 到 prologue 之后 `scratch2()` 不一定还有效。

## 🔴 clock_gettime 参数写反

```mo
syscall(228, &P_TS, 1, 0, 0, 0, 0)   # ✗ 把缓冲当 clockid、把 1 当地址
syscall(228, 1, &P_TS, 0, 0, 0, 0)   # ✓ clockid=1(CLOCK_MONOTONIC), rsi=缓冲
```

调用返回 `-EFAULT`，时刻恒为 0，**所有耗时显示 0 ms** ——
看起来像"程序跑得太快"，没有任何报错。

> 测试方法必须保证**有可测量的耗时**。工作负载太小的话，
> "报告格式正确"和"计时真的在工作"根本区分不开。

## 🔴 自身耗时不能用「每次 enter 就清零」的全局 P_CHILD[id]

同一函数被调 20 次时，只有最后一次的子调用时间被留下，自身耗时被严重高估。
必须**每个栈帧各记一份**（`P_STKC`），leave 时累加到调用者的那一帧上。

## 验证：`tools/proftest.sh`（12 项）

- 开 -p 后程序结果不变（插桩不改变语义）
- 三个函数都被插桩；leaf 调用次数 = 20
- **耗时 > 0**（clock_gettime 真在工作）
- 自身耗时剥离：leaf 自身 > 0，mid 自身 = 0
- 库函数不被插桩
- 缺 `import "prof.mo"` → 明确报错
- 手工插桩仍可用
