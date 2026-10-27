# seedalign.mo —— seed 与 compiler.mo 的对齐检查（墨语言版）
#
# 取代 tools/seedalign.py。
#
# 为什么这件事值得专门写个工具：
#   seed（src/asm/main.s，手写汇编）与 compiler.mo 必须对「全局变量起始
#   偏移」认识一致。改了 compiler.mo 的 reserve_arg_slots() 而忘了同步改
#   seed，表现是**自举失败**，而排查极费时（为此整整流掉一轮，一度误判
#   成「seed 有缺陷」）。这个工具在 make 之前就把它拦下来。
#
# 为什么要用墨语言写：
#   「自举 → 自持 → 固定点 → 自包含生态」这条链上，守护自举的工具本身
#   不该由别的语言写。它由 Python 写时，整条链在最后一环是断的。
#
# 检查项：
#   1. 数据段头的 dquad 数量两边是否一致
#   2. 两边是否都存在 emit_startup / parse_program 锚点
#
# 用法：seedalign [仓库根目录]    缺省 "."
#
# 🔴 注意：文件读不到、锚点找不到一律**报错退出**，不做 SKIP。
#   Python 版遇到读不到文件会打印 SKIP 并返回 0 —— 那是「静默少报」：
#   路径一改，这个守护就悄悄失效了，而 make 照样绿。这类失效正是本项目
#   反复栽跟头的模式，所以这里改成硬失败。

import "fs.mo";
import "io.mo";
import "str.mo";
import "mem.mo";

var BUFSZ: i64 = 2097152;
var B1: i64 = 0;      # src/asm/main.s
var B2: i64 = 0;      # src/mo/compiler_part5.mo
var TMP: i64 = 0;     # 区间拷贝缓冲（strstr 需要 NUL 结尾）
var PATH: [512] byte = 0;

# 在 [lo,hi) 区间内数 needle 出现次数。
# 为什么不直接在整个缓冲区上数：必须限定区间，否则会把别处的同名调用
# 一起数进来（seed 里 call dquad 在别处也有）。
fn cntin(src: i64, lo: i64, hi: i64, nd: ptr) -> i64 {
    let n: i64 = hi - lo;
    let c: i64 = 0;
    let p: i64 = 0;
    let q: i64 = 0;
    if n <= 0 { return 0; }
    if n > BUFSZ - 1 { n = BUFSZ - 1; }
    memcpy(TMP, src + lo, n);
    store8(TMP + n, 0);
    p = TMP;
    while 1 {
        q = strstr(p, nd);
        if q < 0 { return c; }
        c = c + 1;
        p = p + q + 1;
    }
    return c;
}

# 从 from 开始找 "\n}"，返回其下标；找不到返回 -1
fn find_end(src: i64, from: i64, to: i64) -> i64 {
    let i: i64 = from;
    while i + 1 < to {
        if load8(src + i) == 10 {
            if load8(src + i + 1) == 125 { return i; }
        }
        i = i + 1;
    }
    return 0 - 1;
}

# seed 侧：emit_startup 与 parse_program 之间的 call dquad 数量
fn seed_dquads() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    path_join(&PATH, ".", "src/asm/main.s");
    if argc() >= 2 { path_join(&PATH, argv(1), "src/asm/main.s"); }
    n = read_file(&PATH, B1, BUFSZ - 1);
    if n <= 0 {
        print("seedalign: 无法读取 ");
        print(&PATH);
        print_nl();
        return 0 - 1;
    }
    store8(B1 + n, 0);
    i = strstr(B1, "call emit_startup");
    j = strstr(B1, "call parse_program");
    if i < 0 {
        print("seedalign: main.s 里找不到锚点 call emit_startup\n");
        return 0 - 1;
    }
    if j < 0 {
        print("seedalign: main.s 里找不到锚点 call parse_program\n");
        return 0 - 1;
    }
    if j < i {
        print("seedalign: 锚点顺序不对（parse_program 在 emit_startup 之前）\n");
        return 0 - 1;
    }
    return cntin(B1, i, j, "call dquad");
}

# compiler.mo 侧：reserve_arg_slots() 函数体里的 dquad(0); 数量
fn mo_dquads() -> i64 {
    let n: i64 = 0;
    let i: i64 = 0;
    let j: i64 = 0;
    path_join(&PATH, ".", "src/mo/compiler_part5.mo");
    if argc() >= 2 { path_join(&PATH, argv(1), "src/mo/compiler_part5.mo"); }
    n = read_file(&PATH, B2, BUFSZ - 1);
    if n <= 0 {
        print("seedalign: 无法读取 ");
        print(&PATH);
        print_nl();
        return 0 - 1;
    }
    store8(B2 + n, 0);
    i = strstr(B2, "fn reserve_arg_slots() -> i64 {");
    if i < 0 {
        print("seedalign: compiler_part5.mo 里找不到 reserve_arg_slots()\n");
        return 0 - 1;
    }
    j = find_end(B2, i, n);
    if j < 0 {
        print("seedalign: reserve_arg_slots() 没有找到结尾的 }\n");
        return 0 - 1;
    }
    return cntin(B2, i, j, "dquad(0);");
}

fn main() -> i64 {
    let ns: i64 = 0;
    let nm: i64 = 0;
    if heap_ready() == 0 { heap_init(); }
    B1 = alloc(BUFSZ);
    B2 = alloc(BUFSZ);
    TMP = alloc(BUFSZ);
    if B1 == 0 {
        print("seedalign: 堆分配失败\n");
        return 1;
    }
    if B2 == 0 {
        print("seedalign: 堆分配失败\n");
        return 1;
    }
    if TMP == 0 {
        print("seedalign: 堆分配失败\n");
        return 1;
    }
    ns = seed_dquads();
    if ns < 0 { return 1; }
    nm = mo_dquads();
    if nm < 0 { return 1; }
    if ns == nm {
        print("seedalign: OK (数据段头 dquad: seed=");
        print_i64(ns);
        print(", compiler.mo=");
        print_i64(nm);
        print(")\n");
        return 0;
    }
    print("seedalign: ✗ 不对齐\n");
    print("    src/asm/main.s            : ");
    print_i64(ns);
    print(" 个 dquad\n");
    print("    src/mo/compiler_part5.mo  : ");
    print_i64(nm);
    print(" 个 dquad\n");
    print_nl();
    print("    seed 是手写汇编，数据段头布局写死在 src/asm/main.s 里。\n");
    print("    compiler.mo 改了 reserve_arg_slots()，seed 必须同步改，\n");
    print("    否则两边对全局变量起始偏移的认识不同 → 自举失败。\n");
    print_nl();
    print("    详见 docs/self_hosting_alignment.md\n");
    return 1;
}
