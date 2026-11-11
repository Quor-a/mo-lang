# gc —— 保守式 mark-sweep 垃圾回收器（墨语言实现）
#
# 概念来源：Boehm-Demers-Weiser 保守式 GC。
# 主流运行时里它是经典方案，但**没有主流框架把它做成可选库**：
# 要么整个语言有 GC（Go / Java / JS），要么完全没有（C / Rust / Zig）。
# 这里做成一个 import 即可用的库，并把"保守"的代价**量化**。
#
# ── 什么是"保守" ────────────────────────────────────────────
# 运行时不知道哪个 8 字节字是指针、哪个是整数。于是：
#   **落在堆地址范围内、且确实指向某个块的字，一律当指针。**
# 带来两类误差，本库都显式量化而不是含糊带过：
#   1) 误保留：整数恰好等于某块地址 → 该块不会被回收。安全，只是不回收。
#   2) 内部指针：指针指向块中间而非块头 → 本库线性查找所属块并保活。
#
# ── 根集合 ──────────────────────────────────────────────────
#   栈区间  [当前栈顶, gc_init 记录的栈底)
#   数据段  [0x10000000, gc_init 时的 brk)      ← 全局变量的所在
#   寄存器  setjmp 保存到 JB（libc 提供）
#
# ⚠ 必须走 molink + libc：setjmp 在 libc 里。裸 moc 产物链接会失败，
#   是**明确的链接错误**，不是静默少扫根。与 csp.mo（ucontext）同类。
#
# ── 块格式 ──────────────────────────────────────────────────
#   头 16 字节：[0] size（数据区字节数，16 对齐） [8] flags
#   flags: bit0 = used, bit1 = mark
#   块体紧随头部，16 字节对齐 ⇒ 块头地址恒为 16 的倍数。
#
# ── 已知限制（都写在这里，不静默）──────────────────────────
#   * 不移动对象（非 copying / 非 compacting）⇒ 有外部碎片
#   * 不并行、不增量，gc_collect 是一次完整的 stop-the-world
#   * 标记栈容量 MS_MAX，溢出置 GCERR=2 并**停止**（绝不静默少标）
#   * 块数上限 BLK_MAX，超出置 GCERR=3
#   * 依赖 libc 的 setjmp
#
import "io.mo";

extern fn setjmp(p: ptr) -> i32;

var DLO: i64 = 268435456;      # 0x10000000 数据段起始（裸产物与 molink 一致）
var GROW: i64 = 262144;        # 每次向内核申请的量

var HB: i64 = 0;               # 第一个块头
var HP: i64 = 0;               # 当前 brk
var DHI: i64 = 0;              # 数据段结束（= gc_init 时的 brk）
var SB: i64 = 0;               # 栈底（gc_init 记录的近似值）

var MS_MAX: i64 = 8192;
var MS: [8192] i64 = 0;        # 显式标记栈（不放被管理的堆，避免自引用）
var MSP: i64 = 0;
var JB: [64] i64 = 0;          # setjmp 缓冲（寄存器根）

var GRL: i64 = 0;              # gc_range_of 顺带回的区间下界
var GCERR: i64 = 0;            # 0 无错 / 1 堆满 / 2 标记栈溢出 / 3 块数超上限
var GNBLK: i64 = 0;            # 当前块数
var GNALLOC: i64 = 0;          # 累计分配次数
var GNCOL: i64 = 0;            # 累计 collect 次数
var GRECL: i64 = 0;            # 上次 collect 回收的数据字节数

var BLK_MAX: i64 = 65536;

# ── 块访问 ──────────────────────────────────────────────────
fn blk_size(p: i64) -> i64 { return load64(p); }
fn blk_flags(p: i64) -> i64 { return load64(p + 8); }
fn blk_data(p: i64) -> i64 { return p + 16; }
fn blk_isused(p: i64) -> i64 { return blk_flags(p) & 1; }
fn blk_ismark(p: i64) -> i64 { return (blk_flags(p) >> 1) & 1; }
fn blk_next(p: i64) -> i64 { return p + 16 + blk_size(p); }

fn blk_setused(p: i64) -> i64 {
    store64(p + 8, blk_flags(p) | 1);
    return 0;
}
fn blk_setfree(p: i64) -> i64 {
    store64(p + 8, blk_flags(p) - (blk_flags(p) & 1));
    return 0;
}
fn blk_setmark(p: i64) -> i64 {
    store64(p + 8, blk_flags(p) | 2);
    return 0;
}
fn blk_clrmark(p: i64) -> i64 {
    if (blk_flags(p) & 2) == 2 { store64(p + 8, blk_flags(p) - 2); }
    return 0;
}

fn align16(n: i64) -> i64 { return (n + 15) - ((n + 15) & 15); }

# ── 初始化 ──────────────────────────────────────────────────
# 必须在 main 开头调用：它同时决定了栈底与数据段上界。
fn gc_init() -> i64 {
    let probe: [1] i64 = 0;
    SB = gc_range_of(&probe);       # 栈底 = 栈映射区的上界
    DHI = gc_range_of(DLO);         # 数据段上界
    if SB == 0 { GCERR = 4; return -1; }
    if DHI == 0 { GCERR = 4; return -1; }
    HB = syscall(12, 0, 0, 0, 0, 0, 0);
    HP = HB;
    gc_grow(GROW);
    store64(HB, GROW - 16);
    store64(HB + 8, 0);
    GNBLK = 1;
    GNALLOC = 0;
    GNCOL = 0;
    GRECL = 0;
    GCERR = 0;
    return HB;
}

# 读 /proc/self/maps 求"地址 a 所属映射区间的上界"。
#
# 两个用途：数据段上界（a=DLO）、栈底（a=当前局部地址）。
#
# 为什么不能用 brk：链上 libc 之后，brk 已经被推到很远（实测 0x36809000），
# 而数据段只在 0x10000000 起的一小段 —— 直接扫 [0x10000000, brk) 是
# 六百多兆，其中绝大部分**未映射**，一读就 SIGSEGV。这是本库第一个
# 真实踩到的坑：症状是段错误，看起来像"GC 坏了"，其实是根区间算错。
#
# 读不到就置 GCERR=4 并拒绝运行 —— 少扫根比崩溃更难查，绝不留静默路径。
fn gc_hex(p: i64, n: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let c: i64 = load8(p + i);
        let d: i64 = 0;
        if c >= 48 { if c <= 57 { d = c - 48; } }
        if c >= 97 { if c <= 102 { d = c - 87; } }
        if c >= 65 { if c <= 70 { d = c - 55; } }
        v = v * 16 + d;
        i = i + 1;
    }
    return v;
}

fn gc_range_of(a: i64) -> i64 {
    let fd: i64 = syscall(2, "/proc/self/maps", 0, 0, 0, 0);
    if fd < 0 { return 0; }
    let buf: [512] i64 = 0;
    let b: i64 = &buf;
    let n: i64 = syscall(0, fd, b, 4096);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if n <= 0 { return 0; }
    let i: i64 = 0;
    while i < n {
        let at: i64 = 0;
        if i == 0 { at = 1; }
        if load8(b + i) == 10 { at = 1; }
        if at == 1 {
            let s: i64 = b + i;
            if load8(s) == 10 { s = s + 1; }
            let j: i64 = 0;
            while load8(s + j) != 45 { j = j + 1; }        # '-'
            let k: i64 = j + 1;
            let m: i64 = 0;
            while load8(s + k + m) != 32 { m = m + 1; }    # 空格 → end 的位宽
            let lo: i64 = gc_hex(s, j);
            let hi: i64 = gc_hex(s + k, m);
            if a >= lo {
                if a < hi { GRL = lo; return hi; }
            }
        }
        i = i + 1;
    }
    return 0;
}

fn gc_grow(n: i64) -> i64 {
    let r: i64 = syscall(12, HP + n, 0, 0, 0, 0, 0);
    if r < 0 { return -1; }
    HP = HP + n;
    return 0;
}

# ── 分配：first-fit + 块分裂 ────────────────────────────────
fn find_free(n: i64) -> i64 {
    let p: i64 = HB;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return 0; }
        if blk_isused(p) == 0 {
            if blk_size(p) >= n { return p; }
        }
        let nx: i64 = blk_next(p);
        if nx <= p { return 0; }
        p = nx;
    }
    return 0;
}

fn blk_split(p: i64, n: i64) -> i64 {
    let rest: i64 = blk_size(p) - n;
    if rest >= 32 {
        store64(p, n);
        let q: i64 = p + 16 + n;
        store64(q, rest - 16);
        store64(q + 8, 0);
        GNBLK = GNBLK + 1;
    }
    return 0;
}

fn gc_alloc(n: i64) -> i64 {
    let want: i64 = align16(n);
    if want < 16 { want = 16; }
    let p: i64 = find_free(want);
    if p == 0 {
        gc_grow(GROW);
        store64(HP - GROW, GROW - 16);
        store64(HP - GROW + 8, 0);
        GNBLK = GNBLK + 1;
        gc_coalesce_all();
        p = find_free(want);
        if p == 0 { GCERR = 1; return 0; }
    }
    blk_split(p, want);
    blk_setused(p);
    GNALLOC = GNALLOC + 1;
    return blk_data(p);
}

# 把新增长的区域并入前一个空闲块（否则分裂会产生两个相邻空闲块）
fn gc_coalesce_all() -> i64 {
    let p: i64 = HB;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return 0; }
        let nx: i64 = blk_next(p);
        if nx >= HP { return 0; }
        if blk_isused(p) == 0 {
            if blk_isused(nx) == 0 {
                store64(p, blk_size(p) + 16 + blk_size(nx));
                GNBLK = GNBLK - 1;
                return 0;
            }
        }
        p = nx;
    }
    return 0;
}

# ── 保守式：一个字是否指向某个块 ────────────────────────────
# 线性遍历定位"包含 v 的块"，因此**内部指针也能保活整块**。
# 代价 O(块数)，本库明确接受（换二分需要维护块索引，块会分裂合并）。
fn blk_of(v: i64) -> i64 {
    if v < HB { return 0; }
    if v >= HP { return 0; }
    let p: i64 = HB;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return 0; }
        if v >= p {
            if v < p + 16 + blk_size(p) { return p; }
        }
        let nx: i64 = blk_next(p);
        if nx <= p { return 0; }
        p = nx;
    }
    return 0;
}

# ── 标记栈 ──────────────────────────────────────────────────
fn ms_push(p: i64) -> i64 {
    if MSP >= MS_MAX { GCERR = 2; return -1; }
    MS[MSP] = p;
    MSP = MSP + 1;
    return 0;
}

fn ms_pop() -> i64 {
    if MSP <= 0 { return 0; }
    MSP = MSP - 1;
    return MS[MSP];
}

fn mark_blk(p: i64) -> i64 {
    if p == 0 { return 0; }
    if blk_ismark(p) == 1 { return 0; }
    blk_setmark(p);
    return ms_push(p);
}

# ── 扫描一段内存里的每个字 ──────────────────────────────────
fn scan_range(lo: i64, hi: i64) -> i64 {
    let a: i64 = lo - (lo & 7);
    let cnt: i64 = 0;
    while a + 8 <= hi {
        let v: i64 = load64(a);
        let b: i64 = blk_of(v);
        if b != 0 {
            mark_blk(b);
            cnt = cnt + 1;
        }
        a = a + 8;
    }
    return cnt;
}

# ── 传播：从已标记块出发，扫其数据区 ────────────────────────
fn gc_propagate() -> i64 {
    let p: i64 = ms_pop();
    while p != 0 {
        if blk_isused(p) == 1 { scan_range(blk_data(p), blk_data(p) + blk_size(p)); }
        if GCERR == 2 { return -1; }
        p = ms_pop();
    }
    return 0;
}

# ── 清除 ────────────────────────────────────────────────────
fn gc_sweep() -> i64 {
    let p: i64 = HB;
    let rec: i64 = 0;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return rec; }
        if blk_isused(p) == 1 {
            if blk_ismark(p) == 0 {
                rec = rec + blk_size(p);
                blk_setfree(p);
            }
        }
        let nx: i64 = blk_next(p);
        if nx <= p { return rec; }
        p = nx;
    }
    return rec;
}

fn gc_clear_marks() -> i64 {
    let p: i64 = HB;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return 0; }
        blk_clrmark(p);
        let nx: i64 = blk_next(p);
        if nx <= p { return 0; }
        p = nx;
    }
    return 0;
}

# ── 统计 ────────────────────────────────────────────────────
fn gc_live_blocks() -> i64 {
    let p: i64 = HB;
    let n: i64 = 0;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return n; }
        if blk_isused(p) == 1 { n = n + 1; }
        let nx: i64 = blk_next(p);
        if nx <= p { return n; }
        p = nx;
    }
    return n;
}

fn gc_live_bytes() -> i64 {
    let p: i64 = HB;
    let n: i64 = 0;
    let guard: i64 = 0;
    while p < HP {
        guard = guard + 1;
        if guard > BLK_MAX { return n; }
        if blk_isused(p) == 1 { n = n + blk_size(p); }
        let nx: i64 = blk_next(p);
        if nx <= p { return n; }
        p = nx;
    }
    return n;
}

fn gc_heap_bytes() -> i64 { return HP - HB; }

# p 指向的块是否还在使用（用于量化"误保留"）
fn gc_is_live(p: i64) -> i64 {
    let b: i64 = blk_of(p);
    if b == 0 { return 0; }
    if blk_isused(b) == 1 { return 1; }
    return 0;
}

# ── 主入口 ──────────────────────────────────────────────────
# 返回本次回收的数据字节数；出错返回 -1 并置 GCERR。
fn gc_collect() -> i64 {
    let probe: [1] i64 = 0;          # 栈顶近似（gc_collect 自己的帧）
    let i: i64 = 0;
    while i < 64 { JB[i] = 0; i = i + 1; }   # 清掉上次残留，避免旧寄存器误保活
    setjmp(&JB);

    MSP = 0;
    GCERR = 0;
    GNCOL = GNCOL + 1;

    gc_clear_marks();

    # 根 1：寄存器（setjmp 保存）
    scan_range(&JB, &JB + 512);
    # 根 2：栈（调用者各帧 + 本帧）
    scan_range(&probe, SB);
    # 根 3：静态数据段（全局变量所在）
    scan_range(DLO, DHI);

    if GCERR == 2 { return -1; }
    gc_propagate();
    if GCERR == 2 { return -1; }

    GRECL = gc_sweep();
    gc_coalesce_all();

    # 清标记栈（整段，不是只清 MSP 个）：propagate 结束后 MSP 已经归 0，
    # 只清 MSP 个等于**一个都不清**。残留的块头会在下一轮扫数据段时被
    # 当成根，于是被回收过的对象又"复活" —— 症状是 GC 看起来从不回收，
    # 不报错。这是本库最隐蔽的一个坑，且被另一个缺陷（块头不认）掩盖过。
    i = 0;
    while i < MS_MAX { MS[i] = 0; i = i + 1; }
    MSP = 0;
    return GRECL;
}
