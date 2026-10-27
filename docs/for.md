# for 循环

## 语法

```
for (init; cond; step) { body }
```

三个子句都可省略（`for (;;)` = 无限循环，靠 `break` 退出）。

- `init`：`let` 声明，或空。不支持赋值表达式作 init（墨语言的赋值不是表达式）。
- `cond`：任意表达式，为空则恒真。
- `step`：`i++` / `i--` / `i OP= expr` / `i = expr`，或空。

`continue` 跳到 **step**，`break` 跳出循环。

## 作用域

`for` 自带一层作用域：init 里的 `let` 属于 for，所以多个 for 可以各用 `i`，
且循环结束后外层同名变量的值不受影响（`t_shadow` 用例实测 100003）。

body 比 for 再深一层，body 里声明的变量出 body 即失效。

## 🔴 两个真缺陷（v1.134 引入、v1.135 修复）

v1.134 加了 `for`，但**没有任何测试跑到它** —— 三种最普通的写法全部
报 `syntax error`。本轮补测试时挖出两个缺陷。

### 一、step 的代码位置

`for` 展开为 `init; while (cond) { body; step; }`，**代码**必须 body 在前、
step 在后；而 step 的**文本**在 body 之前。第一版按文本顺序解析，于是
body 的位置上读到的是 step。

报的是 `syntax error`，行列指向 step —— **看起来像用户把 body 写错了**。

### 二、嵌套 for 让 token 位置跑飞（更隐蔽）

第一版的修法是"跳过 step 文本 → 解析 body → `set_pos` 回退解析 step"。
单层和并列 for 都对，`for` 套 `while` 也对，但 **`for` 套 `for` 会坏**：

```
外层记录 sp0 / bend        ← 回退用的位置
  → 解析 body → 内层 for → 内层自己的 set_pos 覆盖了这些位置
  → 外层 set_pos(被覆盖后的值) → 位置越过文件末尾
  → syntax error，行列号超出文件总行数
```

报错行列超出文件末尾，是最难读的那种错：看不出是哪一行写错了。

## 现布局：生成顺序 == 文本顺序

```
    init
  CHECK: cond; jz END; jmp BODY
  STEP:  step;  jmp CHECK      <- continue
  BODY:  body;  jmp STEP
  END:                          <- break
```

靠多两条 `jmp` 换取**完全不碰 token 位置**，于是可任意嵌套。
标准布局（cond 在 body 之后）才是"必须回退"的根源。

> 教训：凡是需要 `set_pos` 回退的解析，都要先问一句"嵌套时外层记录的
> 位置会不会被内层覆盖"。本项目已在共享临时变量上栽过多次，这次是
> 同一个模式换了个载体（token 位置而不是变量）。

## 变异验证（tools/formut.sh）

| 变异 | 结果 |
|---|---|
| M1 continue 跳回循环头 | 捕获（rc=1） |
| M2 break 跳回循环头 | 捕获（rc=1） |
| M3 for 不做作用域 | 捕获（编译失败 rc=2） |
| M4 for 结束不回收 init 变量 | 捕获（编译失败 rc=2） |
| M5 body 后不跳回 step | 捕获（`basic: got 0, want 10`） |

**5 / 5 全部捕获**。

**M4 的第一版（`parse_block(d + 1)` → `parse_block(d)`）未被捕获** ——
那不是断言空转：新布局下 step 在 body 之前解析，两层同层确实无差别。
已换成去掉 `sym_pop_scope(d)`，它才对应"多个 for 各用 i"这条性质。
原结论连同原因保留在脚本注释里，没有悄悄删掉。

M1/M2 会让**测试死循环**，所以每条都套了 `timeout` —— 没有它，
"验证变异被捕获"这件事本身会把 CI 挂住。

### 🔴 脚本自身的两个失效（都不是断言空转）

- **备份取自被污染的源码**：`cp $SRC $BAK` 在源码停在变异态时，会把污染版
  当成基线，下一轮一开工就"基线没通过"。现改为**从 `src/mo/` 分片拼接**
  生成备份 —— 分片是权威源（`sync-check` 就是拿它比对 `compiler.mo` 的），
  即使 `compiler.mo` 被污染也能干净重建。
- **`make` 只看 mtime，于是跳过了重建**：`cp` 与上次构建的间隔落在同一秒时，
  make 认为 `bin/moc` 仍比 `compiler.mo` 新，**不重新编译** —— 每个变异
  测到的其实是**上一个**变异的 moc。症状极具误导性：同一组变异两轮跑出
  不同结论（M1 这轮"未被捕获"、上轮"被捕获"），看着像断言空转，
  实际是结果整体错位一格。现改为每次 `rm -f bin/moc` 强制重建。

## 限制

- 每轮迭代比标准布局多两条 `jmp`（换来可嵌套）
- init 不支持赋值表达式（墨语言的赋值不是表达式，不是 for 的限制）
- 循环变量不能是结构体/数组
