# 包管理器 mopkg

```bash
bash tools/mopkg.sh init <名字>
bash tools/mopkg.sh install <git-url> [ref] [版本约束]
bash tools/mopkg.sh fetch              # 按 mo.toml 递归拉取全部依赖
bash tools/mopkg.sh tree               # 依赖树（含循环检测）
bash tools/mopkg.sh verify             # 校验锁完整、版本满足约束、可复现
bash tools/mopkg.sh update [名字]
bash tools/mopkg.sh list
bash tools/mopkg.sh remove <名字>
```

```toml
[package]
name = "app"
version = "0.1.0"

[dependencies]
b = { git = "file:///path/to/b", ref = "main", version = "^2.0.0" }
```

锁文件 `mo.lock` 记录每个包的 name / version / git / ref / **commit**，
`fetch` 时按锁里的 commit 检出 —— 保证可复现构建。

## 版本约束

| 写法 | 含义 |
|---|---|
| `^1.2.3` | ≥1.2.3 且 <2.0.0（主版本不变） |
| `~1.2.3` | ≥1.2.3 且 <1.3.0（次版本不变） |
| `>=1.0.0` | 大于等于 |
| `=1.0.0` | 精确相等 |
| `*` / 不写 | 任意 |

`tree` 输出示例：

```
app 0.1.0
  b 2.1.0
    c 1.0.0
```

循环依赖会直接标出而不是无限递归 —— 墨语言里 `import` 循环会无限展开。

## 四个真坑

**1. 🔴 awk 的 `gsub(re, repl)` 缺省作用于 `$0`，不是局部变量。**

```awk
v = $0; sub(/^[^=]*= */, "", v); gsub(/"/, "")   # ← 改的是 $0，v 里的引号还在
```

必须显式写 `gsub(/"/, "", v)`。症状是所有取出的字段**带着引号**
（`"file:///..."`），git 报 `protocol '"file' is not supported` ——
看起来像 URL 写错了，实际是解析没生效。

**2. 🔴 `${c#~}` 里的 `~` 会被 bash 做 tilde 展开。**

在 pattern 位置 `~` 变成 `$HOME`，于是前缀根本不匹配、什么都删不掉，
后续 `ver_major` 拿到空串，算术表达式报 `operand expected` ——
**报错位置离真正原因很远**。改用 `sed 's/^~//'`。

**3. 🔴 不能用 `python3 <<'PY' ... || awk ...`。**

heredoc 的内容从**下一行**开始，整段 awk 被当成 Python 脚本吃掉，
`PY` 结束符直到后面才出现，中间所有 shell 代码全部消失。
`bash -n` 报的语法错误位置极具误导性。

**4. 🔴 verify 要依赖**闭包**，不是直接依赖。**

间接依赖（c 是 b 的依赖）本来就不写在 app 的 mo.toml 里，却必须出现在锁中。
只比直接依赖会让**每个正常项目**都报"锁里有未声明的包"。

## 验证：`tools/pkgtest.sh`（13 项）

用**本地 git 仓库**建三个包（app→b→c）真实 clone/commit/checkout，
而不是 mock —— 包管理器的正确性几乎全在"锁了哪个 commit、检出是否一致"上，
mock 掉 git 等于没测。

覆盖：递归安装、锁记录、tree 显示间接依赖、版本约束失败、
锁与实际 HEAD 不一致（不可复现）、依赖缺失、循环依赖、约束语义。

## 已知限制

- 依赖必须是 git 仓库，没有中心仓库、没有版本号索引
- 不做依赖冲突仲裁（两个包要求同一包的不同版本时，取先到的）
- `update` 只跟随 ref（分支/tag），不做"升级到最新兼容版本"的求解
- 锁定 commit 时若该 commit 不在浅克隆范围内，需要 `git fetch` 该 commit
