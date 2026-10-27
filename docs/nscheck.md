# nscheck —— 歧义调用静态检查

墨语言没有模块命名空间，所有 `import` 进来的文件共享**同一张**符号表。
`tools/nscheck.py` 检查由此产生的**歧义调用**；`nschecktest.sh` 是它的自检，
`nscheckmut.sh` 证明自检不是空转。

## 绑定语义（实测得出，不是推断）

用 A.mo / B.mo 各自定义 `fn helper()`（返回 111 / 222）：

| 程序 | import 顺序 | 调用 | 结果 |
|---|---|---|---|
| t1 | A 然后 B | `calla()` `callb()`（各文件调自己的） | **111 222** |
| t2 | B 然后 A | 同上 | **111 222** |
| t3 | A 然后 B | main 直接 `helper()` | **222**（B 的） |
| t4 | B 然后 A | main 直接 `helper()` | **111**（A 的） |
| m1 | A 然后 B | A 调用自己**没定义**的 `helper` | `error: undefined symbol` |

三条结论：

1. **文件内部调用自己定义的函数，恒正确，与 import 顺序无关。**
2. **调用点所在文件自己没定义时，绑定到最后被处理的那个文件的定义。**
   不报错、不崩溃，改一行 import 顺序就换了一个实现。
3. **「静默蹭用别的库的函数」不会发生** —— 自己没定义就是 `undefined symbol`。

所以风险面比最初设想的窄，但更实在：真正的隐患不是"同名"，而是
**有一处调用点，它所在文件没有自己的定义，而闭包里有 ≥2 个不同实现**。

## 哨兵用例（端到端，不是静态推断）

`tests/nsambig_ab/` 与 `tests/nsambig_ba/` 两个程序**只差 import 顺序**：

```
nsambig_ab/main.mo   import ambA; import ambB;   return helper();   -> 退出码 222
nsambig_ba/main.mo   import ambB; import ambA;   return helper();   -> 退出码 111
```

同一个 `helper()` 调用绑到了不同实现，编译器不报任何错。
这两个用例同时被 `tests/run.sh` 跑（验证行为）和被 nscheck 报（验证判据）。

## 判据

1. 从主文件出发递归收集 import 闭包
2. 每个文件取顶层 `fn NAME(` 定义，函数体去空白去注释后取摘要
3. 收集调用点（排除关键字 `if(`/`return(` 等，排除 `Rect.area(` 成员调用）
4. 调用点不在这文件自己的定义里、且闭包内可见定义 ≥2 个且摘要不同 → 报

`--lib` 是**清单模式**，恒返回 0：它列的是"同名且实现不同"的清单，供人工
审阅，其中含无害项（cstd/net 的 `exit` 两个实现都是 `syscall(60)`，只在
return 值上差一点，而 exit 不返回）。让它参与成败判定只会制造噪声。

## 用法

```
python3 tools/nscheck.py --all           # 检查 examples/ 与 tests/ 全部 193 个程序
python3 tools/nscheck.py <main.mo> ...   # 检查指定程序
python3 tools/nscheck.py --lib           # 列 lib/ 内同名不同实现的清单
```

退出码：0 = 无歧义调用，1 = 有歧义调用，2 = 用法错误。

## 变异验证（三个都被捕获）

| 变异 | 结果 |
|---|---|
| M1 歧义阈值放宽到 3（永不报） | 3 项变红 |
| M2 不排除本文件自己的定义 | 1 项变红 |
| M3 import 退回进程 cwd 解析 | 3 项变红 |

M2 只让 1 项红，说明 `--all` 里确实存在"文件自己定义了、别处也有不同实现"
的情形，全靠 own 排除拦住 —— 这正是判据的价值所在。

## 踩到的坑

- **不加缓存时 `--lib` 要跑 21 秒**：56 个入口各做一次 closure，反复 stat
  同一批文件。加 `_OPEN_CACHE`/`_TEXT_CACHE`/`_FN_CACHE` 后降到 0.9 秒，
  `--all`（193 个程序）才跑得完。
- **import 要按「引用文件所在目录」解析，不能按进程 cwd**。编译器从
  `/tmp/mot` 跑，而 nscheck 从仓库根跑；只认进程 cwd 的话，
  `tests/*/main.mo` 里 `import "ambA.mo"` 这种同目录裸名会打不开，
  闭包少收文件，**检查静默少报**。
- **变异脚本的 pass/fail 没初始化**：收尾 `[ "$fail" = 0 ]` 把空串当失败，
  于是三个变异明明全被捕获，脚本仍返回 1。

## 已知限制

- 只认顶层 `fn`，结构体方法（`s.area()`）按成员调用跳过，不检查。
- 摘要是"去空白去注释后的字符串"，写法不同但语义等价会误报（如 `exit`）。
- 真正的模块命名空间（`import as`）没做：点号路径已存在（`Rect.area`），
  但要改 primary 解析并同步 `src/mo/` 分片，不是一轮能完成的。
