# ARM64 裸机系统（内核 + RAMFS + shell + 包管理）

版本 1.163.0

一句话：**`examples/kernel64.mo` 是"内核"（开机、自检、停机），
`examples/kern64sys.mo` 是"系统"（起来之后能干什么）。**

```bash
bash tools/kernel64.sh examples/kern64sys.mo /tmp/mosys64.elf
python3 tools/kern64run.py /tmp/mosys64.elf --keys "$(printf 'ls\rwrite a hello\rcat a\r')"
bash tools/kern64systest.sh     # 24 项端到端断言
bash tools/kern64sysmut.sh      # 4 个变异验证
```

## 三件套

裸机没有磁盘、没有 OS、没有任何系统调用，所以"包管理"需要的持久化
只能自己做：

| | 在 Linux 用户态（v1.161 uspace） | 在裸机上（本文件） |
|---|---|---|
| 持久化 | `*at` 系统调用 | **RAMFS**（内存文件系统） |
| 输入 | stdin / UART via syscall | 轮询 PL011 的 MMIO |
| 执行 | fork + exec | 栈式 VM（ARM64 无 fork） |

- **RAMFS**：8 个文件槽，名字 ≤15 字节、内容 ≤63 字节。命令
  `write / cat / ls / rm`。
- **shell**：从 UART 逐字符读入并回显，回车执行。输入用**非阻塞**
  `uart_trygetc`，读到 -1 就认为输入耗尽并停机（模拟器只能注入有限按键）。
- **pkg**：包是一串两位十进制指令，`0n=PUSH n / 1n=ADD / 2n=SUB /
  3n=MUL / 9n=HALT`。`pkg demo 05 03 10 90` → `run demo` → **8**。

## 实测（注入 13 条命令）

```
mo> write a hello      →  wrote=5
mo> cat a              →  hello
mo> pkg demo 05 03 10 90 → installed ops=4
mo> run demo           →  =8          （5+3）
mo> run bad            →  =-3         （栈不足）
mo> rm a               →  rm=0
mo> ls                 →  files=0
cmds=13
```

判据是精确值而不是"跑起来了"：`=8` 同时证明装包、VM、栈三者都对；
`=-3` 证明错误路径有确定的错误码而不是静默。

## 四个真缺陷

**一、模拟器的读钩子从来没被执行过。**
`kern64run.py` 的 `on_read` 只写了 5 个形参，而 Unicorn 实际传 6 个
（uc/access/addr/size/value/data）。之前的 ARM64 内核只输出不输入，
这个分支一次都没走到 —— 一旦内核开始读 UART，直接 `TypeError` 崩掉。
又是"存在但从未被验证"，这次长在验证工具自己身上。

**二、Unicorn 的 MEM_READ 钩子在读取「之前」触发。**
所以"先把第一个字节预置进数据寄存器"是错的：钩子会再 pop 一个字节
覆盖它。实测注入 `help\r` 只回显出 `elp`，第一个字符凭空消失 ——
不报错、不崩溃，只是少一个字符。正确做法是只在读 DR 的钩子里给值。
（另外：Python 绑定传给读钩子的 `value` 恒为 0，想知道读到什么不能看它。）

**三、`next_tok` 的游标推进，两种写法都错，而且错法相反。**

| 写法 | 后果 |
|---|---|
| 推进放进 `done==0` 块内 | 取完 token 后还有字符时 TPOS 卡住 → **死循环** |
| 无条件推进 | 第一次调用吃掉整行，后续调用一律返回空 token → **参数全丢** |

第一种在单 token 命令（`help`/`ls`）下恰好走到串尾，所以一直全绿；
第二种表现为 `wrote=0`、`installed ops=0`，看着像"写了个空文件"。
正确写法是让 `done` 本身当循环条件，越界在循环内判断。

**四、墨语言的指针不能当 i64 形参传。**
后端生成的是 `unsigned char*`，传给 `long long` 形参触发
`-Wint-conversion`。所以本文件所有"名字"一律走全局缓冲 `NAMEBUF`，
函数不接收字符串指针。

## 变异验证（4/4 被捕获）

| 变异 | 结果 |
|---|---|
| M1 `next_tok` 回到"推进进错块"（死循环） | ✅ 13/11 项红 |
| M2 `next_tok` 无条件推进（参数丢失） | ✅ 17/7 项红 |
| M3 VM 的 ADD 做完不弹栈 | ✅ 23/1 项红 |
| M4 模拟器预置首字节（回显吃字符） | ✅ 4/20 项红 |

M1 的第一版是**等价变异**（在正确循环结构下把推进包进 `if done==0`
与原始代码数学等价），实测 24/0 —— 改代码不等于改到了那条因果链，
已换成真正的初始错法。M3 只挂 1 项，冗余度薄，改 VM 前应先补断言。

## 已知限制

- **无中断、无 MMU、单核**；UART 基址 `0x09000000` 是 QEMU virt 约定
- 只在 CPU 模拟器里跑过，**未经真实硬件**
- RAMFS 8 个文件、名字 ≤15、内容 ≤63；包 4 个、每包 ≤16 条指令
- 指令立即数只有 0–9（两位十进制编码的代价）
- 输入是非阻塞轮询，真机上应换成阻塞 `uart_getc`
- 包没有签名/鉴权（v1.159 的 pkgv3 有，本文件是精简版）
