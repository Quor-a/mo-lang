# const fn 循环控制：break / continue（v1.1159）

## 问题

v1.1158 支持了 `while`，但循环体里只有「跑到条件为假」这一种出口。`break` / `continue`
在词法上是普通标识符（`TKIND == 1`），会落进 `cfn_run` 的标识符兜底分支：

```mo
const fn first_div(n: i64) -> i64 {
    let i: i64 = 2;
    let r: i64 = 0 - 1;
    while i < n {
        if n % i == 0 { r = i; break; }   # break 被静默跳过
        i = i + 1;
    }
    return r;
}
```

`break` 被当作「既不是 let 也不是赋值」，`set_pos` + `next_token()` 跳过后继续执行，
`r` 被后续约数反复覆盖。`first_div(35)` 返回 **7**（最后一个约数）而不是 **5**（最小约数）。
不报错、不告警，只是错——这类静默错误最难在用户侧发现。

## 方案：一个全局循环控制标记

新增 `var CFBRK: i64 = 0;`（part1），取值约定：

| 值 | 含义 | 由谁消费 |
|---|---|---|
| 0 | 正常 | — |
| 1 | 本层出现了 `break` | 所属 `while` 处理块：跳到块尾 `}` 之后，退出循环 |
| 2 | 本层出现了 `continue` | 所属 `while` 处理块：清标记，直接回条件判定 |

### 判定点：`cfn_run` 的块内循环

```mo
while gv(K_POS) < limit && CFDONE == 0 && CFBRK == 0 {
```

三个终止条件对应三种「本层块提前收工」：块边界到达、`return` 已求值、`break`/`continue` 已置位。
`cfn_run` 自己不知道身处哪一层循环，只负责「立刻停手并返回」；跳到哪里由外层的 while 处理块决定。

### 消费点：while 的循环体执行

```mo
set_pos(wbs);
cfn_run(wbe);
if CFBRK == 1 {
    CFBRK = 0;
    set_pos(wbe);      # 定位到块尾 `}`，跳过循环体剩余部分
    next_token();      # 消费 `}`，位置落到循环之后
    wgo = 0;           # 结束循环
} else {
    if CFBRK == 2 {
        CFBRK = 0;     # 位置会在下一轮开头由 set_pos(cpos) 重置，无需手动跳
    } else {
        if CFDONE == 0 { next_token(); }
    }
}
```

`continue` 不需要手动重置位置，因为循环体每轮开头都会 `set_pos(cpos)` 重新从条件处推进。

### 嵌套隔离：`cfn_eval` 保存/恢复 `CFBRK`

```mo
let old_bk: i64 = CFBRK;
... 调用 ...
CFBRK = old_bk;
```

没有这一步，被调函数内部的 `break` 会污染调用者的循环。这是 v1.1158 踩过的同类坑
（`CFDONE` 未恢复导致循环只跑一轮），必须同样处理。

内层循环之间不需要额外隔离：内层 while 在自己的处理块里就把 `CFBRK` 清零了，
外层只会在它被清零之后才继续执行循环体。

## 验证

`tests/338_constfn_break.mo`（expect **127**）九个场景，期望值由 Python 模型独立算出后加权求和：

| 场景 | 值 | 覆盖点 |
|---|---|---|
| `fd(35)` | 5 | 找到最小约数后 break |
| `sum_odd(6)` | 9 | continue 跳过偶数 |
| `nested_brk(3)` | 10 | 内层 break 不终止外层 |
| `first_over(10,12)` | 5 | 累加越界即 break |
| `cnt(10)` | 7 | continue 跳过 3 的倍数 |
| `felse(9)` | 23 | break 位于 if/else 的 else 分支 |
| `fcont(6)` | 71 | 两处 continue |
| `loop_call(12)` | 10 | 循环内调用含 break 的 const fn，互不干扰 |
| `ceil_sq(50)` | 8 | break 前有复合赋值 |

加权威重 1..9，总和 895，`895 % 256 = 127`（main 返回值取 mod 256）。

回归：337=136、336=142、335=98；自举 md5 一致；门禁全绿。

## 踩坑记录

- **`| head -3` 会杀掉编译器**：`/tmp/moc1159 b1.mo b1.elf | head -3` 让父进程提前关闭管道，
  编译器收到 SIGPIPE 后死亡、不产出 elf，表现为「RC=0 但没有产物」。测编译器必须
  `> log 2>&1` 重定向后单独判断。
- **期望值别手算**：`first_div(5)=255`（-1）、`first_div(11)=-1` 这类「质数没有真约数」
  的边界，手算极易错成把 n 自己当约数。338 的九个期望值全部由 Python 模型生成。
