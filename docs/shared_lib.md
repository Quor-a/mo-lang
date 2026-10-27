# 被 C 调用：把墨语言编译成共享库

```bash
./bin/moc mylib.mo -shared mylib.o
bash tools/molink.sh mylib.o -shared -o libmo.so
gcc -o app app.c -L. -lmo -Wl,-rpath,.
```

```mo
var CNT: i64 = 42;
fn mo_add(a: i64, b: i64) -> i64 { return a + b; }
fn mo_get() -> i64 { return CNT; }
fn mo_bump() -> i64 { CNT = CNT + 1; return CNT; }
```

```c
long mo_add(long a, long b);
long mo_get(void);
long mo_bump(void);
// 7 42 43 43
```

本文件定义的函数全部导出；`main` 不导出（否则与 C 程序的 main 冲突）。

## 为什么必须用 RIP 相对寻址

共享库加载基址随机，`movabs r11, 绝对地址` 填什么都白搭。

**第一版**发 `movabs r11,0` + `R_X86_64_RELATIVE`：ld 在链接时**把 addend 当最终值直接填了**（`.rela.dyn` 是空的），
于是库里的数据地址是链接时的绝对地址。运行时整个库被搬到随机基址，该地址即无效 ——
调用任何访问全局变量的函数都段错误。

**症状极具误导性**：纯函数（`mo_add`）完全正常，只有碰全局变量的函数崩，
很容易去怀疑线程、锁、初始化，而不是指令编码。

**正确做法**：`lea r11, [rip+d32]` + `R_X86_64_PC32`。
代码与数据在同一个 segment 内，相对距离链接后固定 —— 加载时整块平移、相对关系不变，
不需要 ld.so 做任何事。天然正确。

## 三个编码坑

**1. ModRM 必须是 `0x1d`，不是 `0x9d`。**

```
lea r11, [rip+d32] = 4c 8d 1d <d32>      mod=00 reg=011 rm=101  → RIP 相对
lea r11, [rbp+d32] = 4c 8d 9d <d32>      mod=10                 → 栈相对！
```

写成 `0x9d` 时读的是 `rbp` 相对，拿到栈上垃圾。**链接正常、运行不崩，只是值全错**
（42 读成 4419247591793840201）—— 这是最难发现的一类 bug。

**2. PC32 的 addend 是 `off - 4`。**

ld 算 `S + A - P`，`P` 是**重定位处**（`d32` 字段的位置 = 指令 + 3），
而 `d32` 要相对**下一条指令**（指令 + 7）。两者差 4。

**3. 节头 `sh_info` 要跟着变。**

`-shared` 下符号表 `[1]` 让给了 `.data` 的 section 符号，`_start` 变成 `[2]`。
`sh_info`（第一个非局部符号的下标）必须从 1 改成 2，否则 ld 拒绝：
`local symbol at index 1 (>= sh_info of 1)`。

## 工具链的两个坑

- `molink.sh` 的参数循环里，`-shared` 不能落进 `*)` 分支 —— 否则会把 `OBJ` 覆盖成字符串 `-shared`
- 链接共享库**不要加 `-lc`**：`exit` 由调用方进程提供即可

## 验证：`tools/shtest.sh`（6 项）

最关键的是第 4 项 `7 42 43 43` —— 同时覆盖纯运算、读全局、写全局并返回、写后持久化。

> 测试里四个调用**不能写进同一个 printf**：C 的实参求值顺序未定义，
> gcc 从右往左求值会让 `mo_bump()` 先跑。墨语言是对的，是测试差点把未定义行为当确定顺序。

## 已知限制

- 函数返回类型不支持结构体（>2 字走隐藏指针，未做）
- 导出的是**所有**本文件函数，没有 `export` 关键字做精细控制
- 没有版本脚本（`.map`），符号全部导出
