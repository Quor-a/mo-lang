# arena —— 区域分配器（region / bump allocator）
#
# 对标 C 里"先算好总量、一把 free"的手法，以及 Rust 的 arena。
#
# **解决什么问题**：lib/heap.mo 的 malloc/free 要求调用方
# 对**每一个**对象都记得 free。真实程序里对象成千上万，
# 漏掉一个就是泄漏，而且这类错误**不报错、不崩溃**——
# 只是内存一路涨，跑到某天 OOM 才知道。
#
# arena 的思路是：**对象不单独释放，整块一起丢弃**。
#   - 分配 = 指针往前推（几次算术，比 malloc 的 first-fit 快得多）
#   - 释放 = 把偏移归零（arena_reset），或整块还给堆（arena_free）
#   - 调用方**永远不需要 free 单个对象** → 从根上没有泄漏
#
# 代价：不能单独回收某个对象（要回收只能整批），
# 且 reset 之前所有对象都活着。适合"一批数据共同生死"的场景：
# 解析一个文件时生成的所有节点、一次请求里的所有临时串、编译器的一遍 pass。

import "heap.mo";

var ARENA_CAP: i64 = 65536;    # 默认块大小（不足时按需开更大的块）

# 每个块：
#   [0]   next   下一块（0 = 无）   —— 方向：first → ... → cur
#   [8]   cap    数据区字节数
#   [16]  used   本块已用偏移
#   [24]  数据区开始
#
# 🔴 next 的方向必须是 **旧块指向新块**，不能反过来。
#    反过来的话 reset 时从 cur 走不到 first，就没法把所有块的
#    used 清零 —— 表现为"reset 之后内存没有真正回收"，
#    而程序照样能跑，极难发现。
# 🔴 块头必须是 **16 的倍数**，不能是 24。
#    malloc 返回的地址是 16 对齐的，但数据区起点是 `块 + BLK_HDR`，
#    24 % 16 = 8 —— 于是每个对象都偏移 8 字节，
#    对 64 位字段来说仍能读（x86 允许非对齐访问），
#    但对需要对齐的场景就是隐患，且 `p % 16 == 0` 这类断言直接失败。
var BLK_HDR: i64 = 32;

class Arena {
    first: i64;
    cur: i64;
    total: i64;
    nblk: i64;
}

fn Arena_init(self: Arena, cap: i64) -> i64 {
    if heap_ready() == 0 { heap2_init(); }
    if cap < 4096 { cap = 4096; }
    let b: i64 = malloc(cap + BLK_HDR);
    if b == 0 { return 0 - 1; }
    store64(b, 0);
    store64(b + 8, cap);
    store64(b + 16, 0);
    self.first = b;
    self.cur = b;
    self.total = 0;
    self.nblk = 1;
    return 0;
}

# 对齐到 16 —— 与 heap.mo 的块对齐一致，避免后续 store64 跨界。
fn arena_align(n: i64) -> i64 { return (n + 15) / 16 * 16; }

fn Arena_alloc(self: Arena, n: i64) -> ptr {
    if n <= 0 { return 0; }
    let m: i64 = arena_align(n);
    let b: i64 = self.cur;
    let cap: i64 = load64(b + 8);
    let used: i64 = load64(b + 16);
    if used + m > cap {
        # 当前块放不下：先看链上有没有现成的下一块（reset 之后可复用）
        let nb: i64 = load64(b);
        if nb != 0 {
            b = nb;
            self.cur = nb;
            cap = load64(b + 8);
            used = load64(b + 16);
        }
        if used + m > cap {
            # 仍然放不下：开一块新的（至少能放下 m）
            let nc: i64 = cap;
            if m > nc { nc = m; }
            let x: i64 = malloc(nc + BLK_HDR);
            if x == 0 { return 0; }
            store64(x, 0);
            store64(x + 8, nc);
            store64(x + 16, 0);
            store64(b, x);          # 旧块 → 新块
            self.cur = x;
            self.nblk = self.nblk + 1;
            b = x;
            cap = nc;
            used = 0;
        }
    }
    let p: i64 = b + BLK_HDR + used;
    store64(b + 16, used + m);
    self.total = self.total + m;
    return p;
}

# reset —— 丢弃**所有**对象，但保留已申请的块供复用。
#
# 这是 arena 的核心操作：一次调用替代成千上万次 free，
# 且不可能漏（没有"漏掉某个对象"这个概念）。
fn Arena_reset(self: Arena) -> i64 {
    let b: i64 = self.first;
    while b != 0 {
        store64(b + 16, 0);
        b = load64(b);
    }
    self.cur = self.first;
    self.total = 0;
    return 0;
}

# free —— 连块一起还给堆（整块丢弃时用，之后这个 arena 不能再用）
fn Arena_free(self: Arena) -> i64 {
    let b: i64 = self.first;
    while b != 0 {
        let nx: i64 = load64(b);
        free(b);
        b = nx;
    }
    self.first = 0;
    self.cur = 0;
    self.total = 0;
    self.nblk = 0;
    return 0;
}

fn Arena_used(self: Arena) -> i64 { return self.total; }
fn Arena_nblk(self: Arena) -> i64 { return self.nblk; }

# 便捷：从 arena 分配一个字符串副本
fn Arena_str(self: Arena, s: ptr) -> ptr {
    let n: i64 = strlen(s);
    let d: ptr = Arena_alloc(self, n + 1);
    if d == 0 { return 0; }
    # heap.mo 的 memcpy 签名是 (dst, src, n)
    memcpy(d, s, n);
    store8(d + n, 0);
    return d;
}
