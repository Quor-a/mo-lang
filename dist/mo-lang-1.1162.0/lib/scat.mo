# scat.mo —— 带生命周期的字符串拼接（region / arena）
#
# **为什么需要它**：str.mo 的 strcat 是"追加到目标缓冲"，
# 目标必须预先足够大。要写 "a" + "b" 这种表达式，
# 必须先算总长、分配一块新内存、再拷两次 ——
# 也就是说，`+` 必然要分配。
#
# **分配出来的东西归谁释放**？三条路：
#   1. 每个结果单独 free → 漏一个就是泄漏，而且**不报错、不崩溃**，
#      只是内存一路涨，跑到某天 OOM 才知道
#   2. 永不释放（mem.mo 的 bump）→ 长跑程序把 brk 一路推高
#   3. region（本库）→ **整批一起丢弃**，调用方永不 free 单个对象
#
# region 这条路线对标 Tofte & Talpin 1994 的 region inference
#（ML Kit）、Cyclone 的 region（Grossman 等，PLDI 2002）、
# 以及 Rust 生态里的 arena / bumpalo。
# **它不是 GC**：不需要 tracing、不需要引用计数、不需要写屏障，
# 代价是不能单独回收某一个对象（要回收只能整批）。
#
# 本库**故意不 import 任何库**：str.mo → arena.mo → heap.mo → str.mo
# 会形成循环依赖，于是只 import str.mo 的示例全部编译失败
#（str.mo 里 strcat_i64 的注释记过这个坑）。
# 所以 strlen / 拷贝都在本文件里自己写一遍，分配直接用 brk。

var SB_BASE: i64 = 0;    # region 起点
var SB_PTR:  i64 = 0;    # 当前分配指针（bump）
var SB_END:  i64 = 0;    # region 末尾（已向内核申请到的边界）
var SB_N:    i64 = 0;    # 本批已分配对象数
var SB_MOV:  i64 = 0;    # 发生过的 brk 移动次数
var SB_ERR:  i64 = 0;    # 1 = 分配失败
var SB_COPY: i64 = 0;    # 累计复制字节数（用来量化朴素拼接的代价）

# 幂等：重复调用不会重新定位 region（否则已发出的指针全部失效）。
fn scat_init() -> i64 {
    if SB_BASE != 0 { return 0; }
    let b: i64 = syscall(12, 0, 0, 0, 0, 0, 0);
    SB_BASE = b;
    SB_PTR = b;
    SB_END = b;
    SB_N = 0;
    SB_MOV = 0;
    SB_ERR = 0;
    SB_COPY = 0;
    return 0;
}

# 向内核再要一段。need 是要放下的字节数。
fn scat_grow(need: i64) -> i64 {
    let m: i64 = need;
    if m < 65536 { m = 65536; }
    let want: i64 = (SB_END + m + 15) / 16 * 16;
    let r: i64 = syscall(12, want, 0, 0, 0, 0, 0);
    # 🔴 brk 失败时返回的是**当前的** brk，不是负数。
    #    只判 `r < 0` 会把失败当成成功：SB_END 被推到一个内核
    #    根本没给的地址上，随后的写入静默落到未映射页 → SIGSEGV，
    #    而报错点离真正的失败点很远。判 `r != want` 才抓得住。
    if r != want {
        SB_ERR = 1;
        return 0;
    }
    SB_END = want;
    SB_MOV = SB_MOV + 1;
    return 1;
}

# 分配 n 字节，16 对齐。失败返回 0（并置 SB_ERR）。
fn scat_alloc(n: i64) -> i64 {
    if SB_BASE == 0 { scat_init(); }
    if n <= 0 { return 0; }
    let m: i64 = (n + 15) / 16 * 16;
    if SB_PTR + m > SB_END {
        if scat_grow(m) == 0 { return 0; }
    }
    let p: i64 = SB_PTR;
    SB_PTR = SB_PTR + m;
    SB_N = SB_N + 1;
    return p;
}

# 不 import str.mo，自己写一份求长。
fn scat_len(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        i = i + 1;
    }
    return i;
}

# 拼接：返回**新分配**的串，两个入参都不改动。
#
# 返回的指针归当前 region 所有 —— 调用方**不要** free 它，
# 要回收就 scat_reset()。
fn scat_cat(a: ptr, b: ptr) -> str {
    let n: i64 = scat_len(a);
    let m: i64 = scat_len(b);
    let p: i64 = scat_alloc(n + m + 1);
    if p == 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        store8(p + i, load8(a + i));
        i = i + 1;
    }
    let j: i64 = 0;
    while j < m {
        store8(p + n + j, load8(b + j));
        j = j + 1;
    }
    store8(p + n + m, 0);
    # 复制量是**每次拼接都要重抄一遍已有前缀**的证据：
    # 循环里 s = s + "x" 做 n 次，累计约 n^2/2 —— 见 docs/scat.md
    SB_COPY = SB_COPY + n + m;
    return p;
}

# 复制一份到 region 里（相当于 str_dup，但归 region）。
fn scat_dup(s: ptr) -> str {
    let n: i64 = scat_len(s);
    let p: i64 = scat_alloc(n + 1);
    if p == 0 { return 0; }
    let i: i64 = 0;
    while i <= n {
        store8(p + i, load8(s + i));
        i = i + 1;
    }
    SB_COPY = SB_COPY + n;
    return p;
}

# reset —— 丢弃**本批全部**对象，但**保留**已申请的内存供复用。
#
# 这是 region 的核心操作：一次调用替代成千上万次 free，
# 且不可能漏 —— 根本没有"漏掉某个对象"这个概念。
fn scat_reset() -> i64 {
    SB_PTR = SB_BASE;
    SB_N = 0;
    SB_ERR = 0;
    return 0;
}

# 本批已用字节数
fn scat_used() -> i64 { return SB_PTR - SB_BASE; }
# 已向内核申请到的总容量（reset 不会减少它）
fn scat_cap() -> i64 { return SB_END - SB_BASE; }
# 本批对象数
fn scat_n() -> i64 { return SB_N; }
# 累计复制字节数
fn scat_copy() -> i64 { return SB_COPY; }
# brk 移动次数：用来证明 reset 之后**没有再向内核要内存**
fn scat_mov() -> i64 { return SB_MOV; }
# 分配是否失败过
fn scat_err() -> i64 { return SB_ERR; }
