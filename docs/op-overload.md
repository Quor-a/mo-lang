# 结构体运算符重载（v1.1167）

## 语法
按 Mo 现有方法命名约定（`Class_method` 全局函数，`find_method_sym` 查找）：

```mo
struct Vec2 { x: i64; y: i64; }

fn Vec2_add(self: Vec2, o: Vec2) -> Vec2 {
    let r: Vec2;
    r.x = self.x + o.x;
    r.y = self.y + o.y;
    return r;
}

let c: Vec2 = a + b;    # 编译器发现 lhs 是 Vec2 且有 Vec2_add → 发调用
```

## 支持的运算符（v1.1167 + v1.1168）
| 运算符 | 方法名 |
|---|---|
| `+` | `add` |
| `-` | `sub` |
| `*` | `mul` |
| `==` | `eq` |
| `!=` | `ne` |
| `<` | `lt` |
| `<=` | `le` |
| `>` | `gt` |
| `>=` | `ge` |

比较重载方法返回 i64（0/1），R_ETY 取方法返回类型。
⚠️ 没有对应重载方法时比较走原逻辑：struct 变量是**地址**，
地址比较结果与内容无关 —— 想按内容比较就必须定义 eq。

## 约定与限制
- lhs/rhs 都按**地址**传给方法（rdi=lhs 槽、rsi=rhs 槽）；rhs 为值形态
  （函数返回）或左值都自动归一化到数据段临时槽。
- struct 尺寸 ≤2 words（System V 值返回只有 rax/rdx）；更大的 struct
  静默不重载，走原逻辑（会报类型错）。
- 方法返回类型取自符号返回类型表 O_SRT[fsym]；调用后 R_SADDR=0（值形态）。
  🔴 忘记清 R_SADDR 会让 `let c: T = a + b` 的初始化走地址拷贝路径
  （把 rax=11 当地址解引用 → SIGSEGV）。
- lhs 形态由 R_SADDR 决定：struct 变量是地址（引用语义，与 119 一致），
  函数返回是值。

## 实现要点
- `op_try_overload(lt, m)`：lhs 为 struct（ty_kind==2）且 find_method_sym
  命中才返回 fsym，否则走原逻辑 —— 完全向后兼容。
- `op_lhs_to_slot` / `parse_op_overload_impl`：dquad 分配数据段槽 +
  逐 word 拷贝（值形态 mov [rsi],rax/[rsi+8],rdx；地址形态 mov rcx,[rax+d]）。
- mo2x 各后端暂不支持重载（无类型系统）—— 已知限制。
