# 编辑器支持

| 编辑器 | 文件 | 装法 |
|---|---|---|
| Vim / Neovim | `mo.vim` | 拷到 `~/.vim/syntax/`，`~/.vimrc` 加 `autocmd BufRead,BufNewFile *.mo set filetype=mo` |
| VS Code | `mo.tmLanguage.json` | 放进扩展的 `syntaxes/` 并在 `package.json` 里注册 `source.mo` |
| Emacs | — | 未做（缺 `mo-mode.el`） |
| LSP | — | **未做**。LSP 需要语义级能力（跳转定义、悬停类型），
而墨语言目前只生成行号级调试信息，没有变量与类型信息 |

IDE 支持目前只有**语法高亮**，没有补全、跳转、报错内联。
要做到后者需要 LSP 服务，而 LSP 需要编译器暴露符号位置与类型——
这在 1.x 里排在寄存器分配之后。

## LSP（1.49.0 起可用）

```bash
python3 tools/mols.py /path/to/mo     # 默认用当前目录作项目根
```

编辑器配置：

| 编辑器 | 怎么接 |
|---|---|
| Neovim（原生 LSP） | `vim.lsp.start({ name="mols", cmd={"python3","/abs/path/tools/mols.py","/abs/path/mo"} })` |
| VS Code | 需要一个薄扩展把 stdio 转发给上面那条命令；或直接用 `Generic LSP Client` 类插件 |
| Emacs | `lsp-mode` 注册 `mols`，`(lsp-register-client (make-lsp-client :new-connection (lsp-stdio-connection '("python3" "mols.py")) :major-modes '(mo-mode) :server-id 'mols))` |

### 提供的能力

| 能力 | 说明 |
|---|---|
| **诊断** | 调用真 moc 编译，把报错内联成红波浪线（最有价值的一项） |
| 跳转定义 | 支持跨文件（顺着 `import` 找到 `lib/`） |
| 悬停 | 显示签名，如 `fn add(a: i64, b: i64) -> i64` |
| 大纲 | 函数 / 结构体 / 类 / enum 及成员 / 变量 |
| 查找引用 | 当前文件内 |
| 语义高亮 | 区分关键字/类型/函数/变量，不会把注释里的 `fn` 当关键字 |

### 已知限制

- 诊断是**整文件编译**，不做增量；大文件每次改动会重编一次
- 索引基于正则，**不做作用域消解**：两个函数里的同名局部变量会被当成
  同一个符号（跳转时给多个候选）
- **没有自动补全** —— 需要类型推导，1.x 不做

### 验证

```bash
python3 tools/lsptest.py     # 真跑一遍 LSP 会话，27 项断言
```
