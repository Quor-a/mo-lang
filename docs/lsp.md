# LSP —— 编辑器智能提示

墨语言有两个 Language Server 实现，**共用同一套测试** `tools/lsptest.py`：

| 实现 | 语言 | 启动方式 |
|---|---|---|
| `tools/mols.mo` → `bin/mols` | **墨语言**（默认） | `bin/mols /path/to/mo` |
| `tools/mols.py` | Python（对照实现） | `python3 tools/mols.py /path/to/mo` |

墨语言版是「自包含生态」的一部分 —— 编辑器支持也不借别人的手。
Python 版保留作对照：`tools/molsmo_test.sh` 会用同一套 27 项断言
先后跑两个实现，两份都过才算通过。

```bash
make molsmotest      # 编译 bin/mols → 跑墨语言版 → 跑 Python 版对照
```

## 能力

1. **诊断**（最有价值）—— 调用真正的 moc 编译当前文件，把
   `file:line:col: error: ...` 解析成编辑器内联的红波浪线。
   它不依赖任何调试信息，只要解析编译器的错误输出格式。
2. **索引** —— 扫源码提取符号定义，供跳转定义 / 悬停签名 / 文档大纲 /
   查找引用使用；顺着 `import` 还能跨文件跳到 `lib/`。
3. **语义高亮** —— 区分「关键字 / 类型 / 函数名 / 数字 / 字符串 / 注释 /
   运算符」，比正则高亮准（不会把注释里的 `fn` 当成关键字）。

## 🔴 诊断为什么必须建临时目录

moc 的 `import` 解析依赖 **cwd**（`import "io.mo"` 会找 `./lib/io.mo`），
而 moc 的输入文件名硬编码为 `test.mo`。所以诊断流程是：

```
mkdir /tmp/mols-<pid>  →  写 test.mo  →  软链 lib/  →  chdir  →  exec moc
```

少了任何一步，moc 都会输出一条**不匹配** `file:line:col: error:` 的消息，
于是诊断数为 0 —— 看起来像"功能没生效"，实际是工具链坏了。

> 这里是本项目第二次踩到同类问题：1.49 是输入文件名不匹配（moc 只读
> `test.mo`），1.93 是 symlink 的系统调用号写错（**88，不是 86**）。
> 共同点是**静默地少报，而不是报错**。

所以 `cannot open input` 与 `cannot open import` 都被显式判成**工具问题**
（severity=2，消息写明"这是工具问题，非代码错误"），绝不伪装成"编译通过"。
变异验证：把 88 改回 86，测试立即失败（got 0, want 2）。

## 编辑器接入

| 编辑器 | 配置 |
|---|---|
| Neovim（原生 LSP） | `vim.lsp.start({ name="mols", cmd={"/abs/path/bin/mols","/abs/path/mo"} })` |
| VSCode | 插件里把 server 命令指到 `bin/mols`，参数给项目根 |
| Emacs | `lsp-mode` 注册 `mols`，`(lsp-stdio-connection '("bin/mols" "/abs/path/mo"))` |

项目根参数是**必需的** —— 服务器靠它定位 `lib/` 与 `bin/moc`。

## 已知限制（不假装支持）

- 诊断是**整文件编译**，不做增量；大文件每次改动会重编一次
- 索引基于逐行扫描，**不做作用域消解**：两个函数里的同名局部变量
  会被当成同一个符号（跳转时给出多个候选）
- **没有自动补全** —— 需要类型推导，1.x 不做
- 语义高亮不区分枚举成员与常量的语义差别


## 墨语言版驱动（tools/lsptest.mo）

服务器 `mols` 早已是墨语言写的，但驱动 `lsptest.py` 仍是 Python。
本轮补上另一半：`tools/lsptest.mo` 编译成 `bin/lsptest`，自己 spawn 起
`bin/mols`，用**双向管道**（一个管道给子进程 stdin，一个给 stdout）说 LSP，
跑同一套 27 项断言。

验证方式（`tools/lsmo_test.sh`）：

1. 编译 `bin/mols`（服务器）与 `bin/lsptest`（驱动）
2. 墨语言驱动 spawn 服务器 → 27/27
3. Python 驱动用 `MOLS` 指到**同一个** `bin/mols` 再跑一遍 → 27/27

两个独立客户端、同一个服务器，各自独立得出一致结论，才谈得上"等价"。
Python 驱动**刻意保留**——它是独立实现，交叉验证才有价值（这与
`seedalignpy` / `codecomposepy` 的处置一致）。

### 🔴 真 bug：syscall 参数个数多写了一个

第一版在 `execve` / `write` / `read` / `wait4` 上都多传了一个 `0`
（写成 7 个参数，而 `syscall` 的约定是号码 + 6 个参数）。
症状极具迷惑性：

```
== initialize ==
✗ initialize 无响应
```

——**不报错、不崩溃**，服务器看起来"启动成功"，只是永远不回应。
很容易误判成"服务器坏了"或"协议帧格式不对"，而真正原因是 `execve`
拿到的寄存器布局被多出来的参数打乱，子进程压根没起来（或起来即退）。
修法：所有 `syscall` 统一为号码 + 6 个参数。

> 这类"多一个参数"的坑和 1.49「moc 默认读 test.mo」同类：
> **静默地不工作，而不是报错**。判断依据不能是"有没有报错"。

### 变异验证

把期望的 `add` 大纲名改成不存在的 `ZZZ`、把定义行号从 8 改成 9：

```
✗ 大纲含 add ...
✗ add 定义行号: got 8, want 9
通过 25 / 失败 2
```

断言确实在起作用，不是空转。

