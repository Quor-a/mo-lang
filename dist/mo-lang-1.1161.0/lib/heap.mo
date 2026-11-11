# heap —— 真正的动态内存分配器（用墨语言自己写的）
#
# 对标 C 的 malloc / free / realloc / calloc。
#
# 为什么需要它：lib/mem.mo 是 bump 分配器 —— 只增不减，
# alloc 之后永远无法回收。写小程序够用，写任何有"创建-销毁"循环
# 的东西（解析一万个条目、跑一百次搜索）就会把 brk 一路推高。
#
import "str.mo";
import "io.mo";
import "err.mo";

# 实现：隐式空闲链表 + first-fit + 块分裂 + 相邻合并。
#
#   块头（16 字节）：
#     [0]   size   数据区字节数（不含头）
#     [8]   used   1=占用 0=空闲
#   块体紧接着头部，按 16 字节对齐。
#
# 这是教科书级的简单分配器，不做 bin / 分离空闲链表 ——
# 换来的是好读、好验、不会错。

var HB: i64 = 0;          # 堆起始（第一个块头）
var HP: i64 = 0;          # 当前 brk
var HN: i64 = 0;          # 已分配块数（调试用）
var GROW: i64 = 65536;    # 每次向内核申请的量

var MALLOC_ERR: i64 = 0;  # 0=无错 1=无可用块

fn heap2_init() -> i64 {
    HB = syscall(12, 0, 0, 0, 0, 0, 0);
    HP = HB;
    heap2_grow(GROW);
    # 建一个覆盖整块的空闲块
    store64(HB, GROW - 16);
    store64(HB + 8, 0);
    HN = 0;
    MALLOC_ERR = 0;
    return HB;
}

fn heap2_grow(n: i64) -> i64 {
    let r: i64 = syscall(12, HP + n, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    HP = HP + n;
    return 0;
}

fn blk_size(p: i64) -> i64 { return load64(p); }
fn blk_used(p: i64) -> i64 { return load64(p + 8); }
fn blk_next(p: i64) -> i64 { return p + 16 + blk_size(p); }
fn blk_data(p: i64) -> i64 { return p + 16; }

# 找到第一个能放下 n 的空闲块；找不到就扩容再找一次。
fn find_free(n: i64) -> i64 {
    let p: i64 = HB;
    while p < HP {
        if blk_used(p) == 0 {
            if blk_size(p) >= n { return p; }
        }
        p = blk_next(p);
    }
    return 0;
}

# 分裂：块比需要的大出至少 32 字节（一个新头 + 最小块）才值得分
fn split_blk(p: i64, n: i64) -> i64 {
    let sz: i64 = blk_size(p);
    if sz >= n + 32 {
        store64(p, n);
        store64(p + 8, 1);
        let np: i64 = p + 16 + n;
        store64(np, sz - n - 16);
        store64(np + 8, 0);
    } else {
        store64(p + 8, 1);
    }
    return p;
}

fn malloc(n: i64) -> i64 {
    MALLOC_ERR = 0;
    if n <= 0 { return 0; }
    let need: i64 = (n + 15) & -16;
    let p: i64 = find_free(need);
    if p == 0 {
        # 🔴 扩容**之前**必须先定位最后一个块，并记住它是否空闲。
        #
        #    原写法是在 grow **之后**才遍历链表找 last —— 那时 HP 已经被
        #    推高，遍历会走进刚申请、内容未初始化的区域，把全 0 当块头读
        #    （size=0 → 每次只前进 16 字节），last 落到错误的位置；
        #    接着把它的 size 设成跨越 brk 边界的值，split 出一个
        #    **越界地址**。
        #
        #    症状：单次 malloc 超过初始空闲块（65520 字节）时返回一个
        #    越界指针，一写就段错误。因为平时都是小块分配，
        #    这个 bug 一直没被触发 —— 是 leak.mo 一次性申请
        #    3 × 64KB 的追踪表把它逼出来的。
        let last: i64 = HB;
        let q: i64 = HB;
        while blk_next(q) < HP { q = blk_next(q); }
        last = q;
        let wasfree: i64 = 0;
        if blk_used(last) == 0 { wasfree = 1; }

        # 扩容要够放：块头 + 需求 + 一点余量
        let add: i64 = need + 16 + GROW;
        if heap2_grow(add) < 0 {
            MALLOC_ERR = 1;
            return 0;
        }
        # 新区域接在最后一个块后面：要么并入它的空闲块，要么新建
        if wasfree == 1 {
            store64(last, blk_size(last) + add);
        } else {
            let np: i64 = blk_next(last);
            store64(np, add - 16);
            store64(np + 8, 0);
        }
        p = find_free(need);
        if p == 0 {
            MALLOC_ERR = 1;
            return 0;
        }
    }
    HN = HN + 1;
    return blk_data(split_blk(p, need));
}

# calloc：分配并清零。与 C 一致 —— 不清零是"未初始化内存"这类
# bug 的经典来源。
fn calloc(n: i64, sz: i64) -> i64 {
    let p: i64 = malloc(n * sz);
    if p == 0 { return 0; }
    memset(p, 0, n * sz);
    return p;
}

fn free(p: i64) -> i64 {
    if p == 0 { return 0; }
    let b: i64 = p - 16;
    store64(b + 8, 0);
    HN = HN - 1;
    # 与后一个空闲块合并
    let n: i64 = blk_next(b);
    if n < HP {
        if blk_used(n) == 0 {
            store64(b, blk_size(b) + 16 + blk_size(n));
        }
    }
    return 0;
}

fn realloc(p: i64, n: i64) -> i64 {
    if p == 0 { return malloc(n); }
    if n <= 0 { free(p); return 0; }
    let b: i64 = p - 16;
    let old: i64 = blk_size(b);
    let need: i64 = (n + 15) & -16;
    if need <= old {
        # 原地缩小：多余的部分分裂出来变回空闲块
        split_blk(b, need);
        return p;
    }
    # 后面正好是空闲块且够用 → 就地扩
    let nx: i64 = blk_next(b);
    if nx < HP {
        if blk_used(nx) == 0 {
            if old + 16 + blk_size(nx) >= need {
                store64(b, old + 16 + blk_size(nx));
                store64(b + 8, 1);
                split_blk(b, need);
                return p;
            }
        }
    }
    # 否则搬家
    let q: i64 = malloc(n);
    if q == 0 { return 0; }
    memcpy(q, p, old);
    free(p);
    return q;
}

# 已用字节数（含所有块头），用于观察分配器行为
fn heap2_used() -> i64 {
    let p: i64 = HB;
    let s: i64 = 0;
    while p < HP {
        if blk_used(p) == 1 { s = s + 16 + blk_size(p); }
        p = blk_next(p);
    }
    return s;
}

# 空闲字节数
fn heap2_free() -> i64 {
    let p: i64 = HB;
    let s: i64 = 0;
    while p < HP {
        if blk_used(p) == 0 { s = s + 16 + blk_size(p); }
        p = blk_next(p);
    }
    return s;
}
