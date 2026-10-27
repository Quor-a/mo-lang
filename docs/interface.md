# 接口（interface）与动态分派

```mo
interface Shape {
    fn area(self: ptr) -> i64;
    fn perim(self: ptr) -> i64;
}

class Rect { w: i64; h: i64; }
fn Rect_area(self: Rect) -> i64 { return self.w * self.h; }
fn Rect_perim(self: Rect) -> i64 { return (self.w + self.h) * 2; }

class Sq { s: i64; }
fn Sq_area(self: Sq) -> i64 { return self.s * self.s; }
fn Sq_perim(self: Sq) -> i64 { return self.s * 4; }

impl Shape for Rect { area; perim; }
impl Shape for Sq { area; perim; }

fn main() -> i64 {
    let r: Rect;  r.w = 3;  r.h = 4;
    let q: Sq;    q.s = 5;

    let a: Shape;
    a.obj = &r;
    a.vt = &Shape_Rect_vt;
    print_i64(a.area());        # 12

    a.obj = &q;
    a.vt = &Shape_Sq_vt;
    print_i64(a.area());        # 25 —— 同一行代码，不同实现
    return 0;
}
```

## 设计：为什么不需要 IR

通常认为接口/vtable 需要类型系统重写或 IR。这里绕开了：

**接口值就是一个两字段结构体 `{ obj; vt; }`。**

于是现有的三样东西直接拼起来就够：结构体 + 函数指针 + `obj.method()` 语法糖。
`impl` 生成一个全局数组 `Shape_Rect_vt`，里面放函数地址；`s.area()` 编译成
`call [s.vt + idx*8]`。

方法按**名字**索引进 vtable，所以 `impl` 里的顺序不必与接口声明一致。

## 实现要点：vtable 必须在解析全部结束后回填

`impl` 出现时函数可能还没定义（前向引用），地址此刻未知。
所以 impl 时只分配零填充的数组，等 `parse_program()` 全部结束、
`O_SA` 里有了真正的函数地址，再统一写入。

## 🔴 三个真坑

**1. `intern()` 返回的是偏移，不是指针。**

```mo
store64(heap + O_IFMN + ..., intern(tokbuf()));   # ✗ 存的是数字
if streq(load64(...), mname) == 1                  # 把它当地址解引用 → 段错误
```

这与 1.41.1 那个「`ty_int()` 是裸 id 不是类型对象」是**同一类错**：
同一套 API 里混了"偏移/裸 id"和"指针/对象"两种表示。
已专文记在《踩坑合集》里，这是第三次栽在同一类问题上。

**2. 回填函数插错了位置。**

第一次加到了 `compile_file` 里的 `parse_program()` 之后 ——
那个是 `import` 每个文件时跑的，主文件还没解析，`K_NVT` 恒为 0。
于是 vtable 永远是 0，`call 0` 直接段错误，
而**编译全程不报任何错**，问题只体现在运行期。

**3. 表达式位置要单独处理一遍。**

`obj.method()` 有两条路：语句位置和表达式位置。
第一版只改了语句位置，于是 `let x = a.area();` 报 "no such method"，
而 `a.area();` 正常。

## 已知限制

- 绑定要手写两行（`s.obj = &r; s.vt = &Shape_Rect_vt;`），没有自动绑定
- 只支持单接口，没有 `impl A + B for T`
- `impl` 必须写在方法定义**之后**（否则找不到符号）
- 接口方法最多 16 个，接口最多 32 个，impl 最多 32 个

## 验证：`tests/93_interface.mo`

同一变量、同一行调用，运行时走不同实现；含带额外实参的接口方法；
并按名字索引验证顺序无关。

**测试不能空转**：故意把期望值改错会打印 `FAIL rect area: got 12, want 99`，
说明断言真的在起作用。
