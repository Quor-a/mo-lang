# 对标标准 C / C++

版本 1.15.0（2026-10-09）

## 先说清楚：哪些做不到，为什么

C++ 的这些特性**架构上不成立**，不是"还没做"：

| 特性 | 原因 |
|---|---|
| 虚函数 / 动态分派 | 没有 vtable（**类与继承已实现**，见 `docs/class.md`） |
| 模板 / 泛型 / concepts | 需要类型参数化，编译器没有这一层 |
| 异常（try/catch/throw） | 无栈展开机制，也无运行时类型信息 |
| 运算符重载 | 需要按类型分派 |
| lambda / 闭包 | 无闭包捕获 |
| RAII / 智能指针 | 无析构语义 |
| 引用（`int&`） | 只有指针 |
| 命名空间 | 符号表是扁平的 |
| STL 容器与算法 | 需要模板 |

共同前提都是**类型系统与中间表示**。墨语言是边解析边发射、没有 AST
（实测 IR 相关标识符出现 0 次），加这些是重构级工程，不是补丁。

## 这轮做了什么（对标 C 的底层能力）

### 1. `sizeof` / `alignof` —— 编译期运算符

```mo
sizeof(i64)        # 8
sizeof(byte)       # 1
sizeof(ptr)        # 8
sizeof(P)          # 24（三个 i64 字段）
sizeof([8] byte)   # 8
alignof(byte)      # 1
```

只支持 `sizeof(类型)`，**不支持 `sizeof(表达式)`**。
理由：表达式形式要先解析再丢弃代码（否则会把副作用编进去），
在没有 AST 的架构下代价大。类型形式覆盖了绝大多数真实用途。

### 2. 结构体支持 `byte` 字段

此前字段类型只有 `i64` 与结构体 —— 对标 C 的 struct，`char` 字段
是最基本的需要。代码生成层（`g_load_at_b` / `g_store_at_b`）早就支持，
只差解析没接上。

byte 字段按 8 字节对齐存放，与 C 默认对齐结果一致：
`struct { char x; long y; }` 在 C 里同样是 16 字节。

### 3. `lib/heap.mo` —— 真正的 malloc / free

`lib/mem.mo` 是 bump 分配器（只增不减），写任何有"创建-销毁"
循环的东西都会把 brk 一路推高。

新实现：隐式空闲链表 + first-fit + 块分裂 + 相邻合并。

```mo
let p: i64 = malloc(64);
let c: i64 = calloc(16, 8);     # 且清零
let r: i64 = realloc(p, 512);
free(p);
```

`realloc` 支持三种情形：原地缩小（分裂出空闲块）、
后邻空闲块够用时就地扩张、否则搬家。

测试用"反复分配释放 2000 次，堆用量不应单调增长"来验证真的回收了。

### 4. `lib/cstd.mo` —— C 标准库子集

| 分组 | 提供 |
|---|---|
| ctype | `is_alpha` `is_upper` `is_lower` `is_alnum` `is_space_c` `to_upper` `to_lower` |
| stdlib | `abs` `labs` `min_i64` `max_i64` `cdiv`（**C 截断语义**） |
| string | `strtol` `memmove` `memchr` `strncmp` `strncpy` `strrev` |
| time | `clock_ms` `time_secs` |
| process | `exit` `abort` |
| signal | `signal` `raise` |

**`memmove` 是这里的重点**：与 `memcpy` 不同，它必须正确处理重叠
（目标在前从前往后、在后从后往前）。少了这个判断，
重叠时会把还没读的数据覆盖掉。

`cdiv` 用 **C 的截断语义**（`-7/3 = -2`），与 `lib/big.mo`
的 Python 向下取整语义（`-7//3 = -3`）并存 —— 各对标各的。

### 5. `lib/sort.mo` —— qsort / bsearch

**诚实的重要限制**：C 的 `qsort` 靠**函数指针**传比较器，
墨语言目前没有函数指针类型，做不到"传任意比较函数"。

所以提供常用类型的专用版本：`qsort_i64` / `qsort_i64_desc` /
`qsort_str_vec` / `bsearch_i64` / `bsearch_str_vec`。

快排用 Hoare 分区 + **小区间插入排序兜底**（<12 个元素），
且「先递归小的一侧、大的一侧留循环」——这样最坏递归深度也是 O(log n)。

测试覆盖了快排的三个经典退化输入：已排序、逆序、全相等。

## 仍然存在的限制

- **没有函数指针** → 无法写通用 `qsort(buf, n, size, cmp)`、
  无法注册真正的信号处理函数（`signal` 只能传 SIG_DFL/SIG_IGN）
- **没有可变参数** → `printf` 的格式化、`scanf` 系列做不了
- **没有浮点** → `strtod` / `atof` / `%f` 一律不做
- **没有 `enum` / `typedef` / `union` / `goto` / 位域** → 语言层未支持
- **`store64` / `load64` 直接寻址不做越界检查**，
  只有下标语法 `a[i]` 做。测试里曾因此把一个 `[64]` 数组写成 512 个
  而段错误 —— 用原始地址运算时要自己保证范围
- 结构体无 `packed` / `alignas`，字段一律 8 字节对齐

## 一个需要注意的陷阱

测试 68 最初段错误，真因不是编译器：测试用
`store64(&A + i * 8, v)` 直接寻址写越界，绕过了下标语法的越界检查。

> 下标语法 `a[i]` 有越界检查；`store64(&A + off)` 没有。
> 用后者时范围由你自己负责。
