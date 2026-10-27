# pkgmgr.mo —— **自带运行环境的包管理器**（freestanding，可在安卓原生运行）
#
# mo-target: cfs-aarch64   # 非原生后端，projcheck 跳过原生编译
#
#   bash tools/android_native.sh examples/pkgmgr.mo /tmp/pkgmgr.arm64
#   adb push /tmp/pkgmgr.arm64 /data/local/tmp/pkgmgr
#   adb shell /data/local/tmp/pkgmgr
#
# 它回答用户提的四个要求
# ----------------------
#   1. 包管理能在安卓上跑      → 纯 syscall，不 fork / 不 exec / 不链 libc
#   2. 可以开发升级包管理      → 包就是目录 + 清单，install/remove 即升级
#   3. 可以运行执行开发的包    → 包里带字节码，自带栈式 VM 真正执行它
#   4. 自带运行和执行环境      → 静态 ELF，产物不依赖任何外部运行时
#
# 为什么"运行包"不靠 fork+execve
# ------------------------------
# ARM64 没有 fork（只有 clone(220)，参数形态完全不同），execve 又要加载器。
# 所以"执行包"改成：**包里存字节码，包管理器自带一个栈式 VM 解释它**。
# 这样同一个包在手机上和 x86 上跑出同样的数字，且不需要任何外部进程。
#
# 依赖的系统调用（全部经过 x86→asm-generic 号表翻译）
# --------------------------------------------------
#   mkdirat(83) · openat(2) · write(1) · read(0) · close(3)
#   getdents64(217 → ARM64 61) · unlinkat(87)
#
# getdents64 这一条是本轮修掉的真缺陷：此前号表写 217→217，
# 而 ARM64 的 217 是 **add_key**，于是 list 在手机上会静默拿到空列表。
#
# 判据不靠自证：所有结果都打印到 stdout，由 tools/pkgmgrtest.sh 比对；
# 两个包跑出的数字（42 / 84）不同，才能区分"跑对了"和"碰巧输出一个常量"。

var CB: [64] i64;      # 字节码构造缓冲（不初始化：freestanding 下大数组 = 0 会引 memset）
var CBN: i64 = 0;
var VS: [64] i64;      # VM 操作数栈
var VB: [64] i64;      # 字段值缓冲

# ---------- 字符串工具（自己写，不 import：freestanding 下越自包含越好）----------

fn slen(s: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 { i = i + 1; }
    return i;
}

fn pstr(s: ptr) -> i64 {
    let n: i64 = slen(s);
    syscall(1, 1, s, n, 0, 0, 0);
    return n;
}

fn scopy(dst: ptr, src: ptr) -> i64 {
    let i: i64 = 0;
    while load8(src + i) != 0 { store8(dst + i, load8(src + i)); i = i + 1; }
    store8(dst + i, 0);
    return i;
}

fn sapp(dst: ptr, src: ptr) -> i64 {
    let i: i64 = slen(dst);
    let j: i64 = 0;
    while load8(src + j) != 0 { store8(dst + i + j, load8(src + j)); j = j + 1; }
    store8(dst + i + j, 0);
    return i + j;
}

# 找子串，返回下标；找不到返回 -1
fn sfind(hay: ptr, nd: ptr) -> i64 {
    let i: i64 = 0;
    let j: i64 = 0;
    let nl: i64 = slen(nd);
    if nl == 0 { return -1; }
    while load8(hay + i) != 0 {
        j = 0;
        while load8(hay + i + j) == load8(nd + j) {
            j = j + 1;
            if j == nl { return i; }
        }
        i = i + 1;
    }
    return -1;
}

# ---------- 字节码构造 ----------

fn bemit(v: i64) -> i64 {
    store8(&CB + CBN, v);
    CBN = CBN + 1;
    return 0;
}

# 小端 4 字节立即数
fn bemit32(v: i64) -> i64 {
    let k: i64 = 0;
    let mul: i64 = 1;
    let t: i64 = 0;
    while k < 4 {
        t = v / mul;
        t = t - (t / 256) * 256;
        store8(&CB + CBN, t);
        CBN = CBN + 1;
        mul = mul * 256;
        k = k + 1;
    }
    return 0;
}

# ---------- 栈式 VM：真正"执行"包里的代码 ----------
#
# 指令（1 字节 opcode）：
#   0 HALT            1 PUSHI imm32(小端)      2 ADD      3 PRINT      4 MUL
#
# 返回值：-1 = 遇到非法 opcode（不静默跳过：那会让"执行了"变成假的）

var VM_OUT: i64 = 0;
var VOUT: [8] i64;

fn vm_run(code: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    let sp: i64 = 0;
    let op: i64 = 0;
    let v: i64 = 0;
    let k: i64 = 0;
    let mul: i64 = 1;
    VM_OUT = 0;
    while i < n {
        op = load8(code + i);
        if op == 0 { return 0; }
        if op == 1 {
            # 立即数跨过末尾 = 包被截断；栈满 = 包在恶意压栈。
            # 两者都不静默：越界读到的是上一个包留下的字节。
            if i + 5 > n { return -4; }
            if sp >= 64 { return -3; }      # 与 `var VS: [64] i64` 一致
            v = 0; mul = 1; k = 0;
            while k < 4 {
                v = v + load8(code + i + 1 + k) * mul;
                mul = mul * 256;
                k = k + 1;
            }
            VS[sp] = v;
            sp = sp + 1;
            i = i + 5;
        } else {
            if op == 2 {
                if sp < 2 { return -2; }
                VS[sp - 2] = VS[sp - 2] + VS[sp - 1];
                sp = sp - 1;
                i = i + 1;
            } else {
                if op == 4 {
                    if sp < 2 { return -2; }
                    VS[sp - 2] = VS[sp - 2] * VS[sp - 1];
                    sp = sp - 1;
                    i = i + 1;
                } else {
                    if op == 3 {
                        if sp < 1 { return -2; }
                        if VM_OUT < 8 {
                            VOUT[VM_OUT] = VS[sp - 1];
                            VM_OUT = VM_OUT + 1;
                        }
                        sp = sp - 1;
                        i = i + 1;
                    } else {
                        return -1;
                    }
                }
            }
        }
    }
    return 0;
}

# ---------- 主流程 ----------

# ---------- VM 边界自检：损坏的包必须响亮失败 ----------
#
# 包是"AI 开发的"：字节码可能写错、可能被截断、可能是恶意的。
# 栈下溢 / 栈上溢 / 指令截断若静默跳过，包管理器会拿越界内存里的垃圾
# 当执行结果 —— 看起来"跑通了"，实际什么都没执行。
#
#   返回 -1 非法 opcode · -2 栈下溢 · -3 栈上溢 · -4 指令截断

fn vm_selftest() -> i64 {
    let ok: i64 = 1;
    let r: i64 = 0;
    let i: i64 = 0;

    # A) 合法的 6 * 7 —— 基准，证明检查没有把好包一起拦掉
    CBN = 0;
    bemit(1); bemit32(6);
    bemit(1); bemit32(7);
    bemit(4); bemit(3); bemit(0);
    r = vm_run(&CB, CBN);
    print("[9a] legal     ret=");
    print_i64(r);
    print(" out=");
    print_i64(VOUT[0]);
    print_nl();
    if r != 0 { ok = 0; }
    if VM_OUT != 1 { ok = 0; }
    if VOUT[0] != 42 { ok = 0; }

    # B) 单独 ADD —— 栈下溢
    CBN = 0;
    bemit(2); bemit(0);
    r = vm_run(&CB, CBN);
    print("[9b] underflow ret=");
    print_i64(r);
    print_nl();
    if r != -2 { ok = 0; }

    # C) 单独 PRINT —— 栈下溢
    CBN = 0;
    bemit(3); bemit(0);
    r = vm_run(&CB, CBN);
    print("[9c] print uf  ret=");
    print_i64(r);
    print_nl();
    if r != -2 { ok = 0; }

    # D) PUSHI 的立即数被截断（只给了 2 字节）
    CBN = 0;
    bemit(1); bemit(6); bemit(7);
    r = vm_run(&CB, CBN);
    print("[9d] trunc     ret=");
    print_i64(r);
    print_nl();
    if r != -4 { ok = 0; }

    # E) 65 个 PUSHI —— 栈上溢（VS 只有 64 格）
    CBN = 0;
    i = 0;
    while i < 65 { bemit(1); bemit32(1); i = i + 1; }
    bemit(0);
    r = vm_run(&CB, CBN);
    print("[9e] overflow  ret=");
    print_i64(r);
    print_nl();
    if r != -3 { ok = 0; }

    return ok;
}

fn main() -> i64 {
    let root: ptr = "/tmp/mo_pkgs";
    let ok: i64 = 1;
    let fd: i64 = 0;
    let n: i64 = 0;
    let off: i64 = 0;
    let rl: i64 = 0;
    let cnt: i64 = 0;
    let hit: i64 = 0;
    let skip: i64 = 0;
    let i: i64 = 0;
    # 缓冲区**故意不写 = 0**：freestanding（无 libc）下，大于约 32 个 i64 的
    # 零初始化会被 C 编译器优化成 memset 调用，链接时
    #   ld.lld: error: undefined symbol: memset
    # 症状完全不指向数组本身（v1.154 记过）。
    let PATH: [64] i64;
    let DB: [64] i64;
    let FB: [64] i64;

    print("=== mo-pkg : 自带运行环境的包管理器 ===\n");

    # ---- 1) init：建包根 ----
    n = syscall(83, root, 493, 0, 0, 0);
    print("[1] init root     ret=");
    print_i64(n);
    print_nl();
    if n != 0 { if n != -17 { ok = 0; } }

    # ---- 2) install demo：目录 + 清单 + 字节码 ----
    scopy(&PATH, root);
    sapp(&PATH, "/demo");
    n = syscall(83, &PATH, 493, 0, 0, 0);
    print("[2] mkdir demo    ret=");
    print_i64(n);
    print_nl();
    if n != 0 { if n != -17 { ok = 0; } }

    sapp(&PATH, "/MANIFEST");
    fd = syscall(2, &PATH, 577, 420, 0, 0);
    if fd < 0 { print("open MANIFEST FAIL\n"); return 1; }
    n = syscall(1, fd, "name=demo\nversion=1.0.0\n", 24, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);

    # 字节码：6 * 7 = 42
    CBN = 0;
    bemit(1); bemit32(6);
    bemit(1); bemit32(7);
    bemit(4); bemit(3); bemit(0);
    scopy(&PATH, root);
    sapp(&PATH, "/demo/CODE");
    fd = syscall(2, &PATH, 577, 420, 0, 0);
    n = syscall(1, fd, &CB, CBN, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("[2] install demo  code=");
    print_i64(n);
    print_nl();
    if n != CBN { ok = 0; }

    # ---- 3) install demo2：2 * 42 = 84 ----
    scopy(&PATH, root);
    sapp(&PATH, "/demo2");
    n = syscall(83, &PATH, 493, 0, 0, 0);
    print("[3] mkdir demo2   ret=");
    print_i64(n);
    print_nl();
    if n != 0 { if n != -17 { ok = 0; } }
    sapp(&PATH, "/MANIFEST");
    fd = syscall(2, &PATH, 577, 420, 0, 0);
    n = syscall(1, fd, "name=demo2\nversion=2.0.0\n", 25, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    CBN = 0;
    bemit(1); bemit32(2);
    bemit(1); bemit32(42);
    bemit(4); bemit(3); bemit(0);
    scopy(&PATH, root);
    sapp(&PATH, "/demo2/CODE");
    fd = syscall(2, &PATH, 577, 420, 0, 0);
    n = syscall(1, fd, &CB, CBN, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("[3] install demo2 code=");
    print_i64(n);
    print_nl();
    if n != CBN { ok = 0; }

    # ---- 4) list：getdents64 ----
    fd = syscall(2, root, 65536, 0, 0, 0);
    print("[4] open root     fd=");
    print_i64(fd);
    print_nl();
    if fd < 0 { print("open root FAIL\n"); return 1; }
    n = syscall(217, fd, &DB, 480, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    print("[4] getdents      n=");
    print_i64(n);
    print_nl();
    off = 0;
    cnt = 0;
    hit = 0;
    while off < n {
        rl = load8(&DB + off + 16) + load8(&DB + off + 17) * 256;
        skip = 0;
        if load8(&DB + off + 19) == 46 {
            if load8(&DB + off + 20) == 0 { skip = 1; }
            else {
                if load8(&DB + off + 20) == 46 {
                    if load8(&DB + off + 21) == 0 { skip = 1; }
                }
            }
        }
        if skip == 0 {
            cnt = cnt + 1;
            pstr(&DB + off + 19);
            print(" ");
            if sfind(&DB + off + 19, "demo") == 0 { hit = hit + 1; }
        }
        off = off + rl;
    }
    print("\n[4] list count    =");
    print_i64(cnt);
    print_nl();
    if cnt != 2 { ok = 0; }
    if hit != 2 { ok = 0; }

    # ---- 5) info：读清单并解析 version ----
    scopy(&PATH, root);
    sapp(&PATH, "/demo/MANIFEST");
    fd = syscall(2, &PATH, 0, 0, 0, 0);
    n = syscall(0, fd, &FB, 60, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    store8(&FB + n, 0);
    print("[5] info demo     ver=");
    i = sfind(&FB, "version=");
    if i < 0 { print("NOT-FOUND"); ok = 0; }
    else {
        let v: i64 = 0;
        i = i + 8;
        while load8(&FB + i) != 0 {
            if load8(&FB + i) == 10 { i = n; }
            else { store8(&VB + v, load8(&FB + i)); v = v + 1; i = i + 1; }
        }
        store8(&VB + v, 0);
        pstr(&VB);
    }
    print_nl();

    # ---- 6) run：真正执行包里的字节码 ----
    scopy(&PATH, root);
    sapp(&PATH, "/demo/CODE");
    fd = syscall(2, &PATH, 0, 0, 0, 0);
    n = syscall(0, fd, &FB, 60, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    i = vm_run(&FB, n);
    print("[6] run demo      out=");
    if i < 0 { print("BAD-OPCODE"); ok = 0; }
    else {
        if VM_OUT < 1 { print("NO-OUTPUT"); ok = 0; }
        else { print_i64(VOUT[0]); }
    }
    print_nl();
    if VOUT[0] != 42 { ok = 0; }

    scopy(&PATH, root);
    sapp(&PATH, "/demo2/CODE");
    fd = syscall(2, &PATH, 0, 0, 0, 0);
    n = syscall(0, fd, &FB, 60, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    i = vm_run(&FB, n);
    print("[6] run demo2     out=");
    if i < 0 { print("BAD-OPCODE"); ok = 0; }
    else {
        if VM_OUT < 1 { print("NO-OUTPUT"); ok = 0; }
        else { print_i64(VOUT[0]); }
    }
    print_nl();
    if VOUT[0] != 84 { ok = 0; }

    # ---- 7) remove：先删文件，再删目录（AT_REMOVEDIR = 512）----
    scopy(&PATH, root);
    sapp(&PATH, "/demo/MANIFEST");
    syscall(87, &PATH, 0, 0, 0, 0);
    scopy(&PATH, root);
    sapp(&PATH, "/demo/CODE");
    syscall(87, &PATH, 0, 0, 0, 0);
    scopy(&PATH, root);
    sapp(&PATH, "/demo");
    # rmdir：第二实参 512 = AT_REMOVEDIR。x86 上是 rmdir(path)（该实参被忽略），
    # ARM64 上插入 dfd 后它正好落在 unlinkat 的 flags 位 —— 两端同一语义。
    n = syscall(84, &PATH, 512, 0, 0, 0);
    print("[7] remove demo   ret=");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }

    # ---- 8) 删完再列一次：必须只剩 demo2 ----
    fd = syscall(2, root, 65536, 0, 0, 0);
    n = syscall(217, fd, &DB, 480, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    off = 0;
    cnt = 0;
    hit = 0;
    while off < n {
        rl = load8(&DB + off + 16) + load8(&DB + off + 17) * 256;
        skip = 0;
        if load8(&DB + off + 19) == 46 {
            if load8(&DB + off + 20) == 0 { skip = 1; }
            else {
                if load8(&DB + off + 20) == 46 {
                    if load8(&DB + off + 21) == 0 { skip = 1; }
                }
            }
        }
        if skip == 0 {
            cnt = cnt + 1;
            pstr(&DB + off + 19);
            print(" ");
            if sfind(&DB + off + 19, "demo2") == 0 { hit = hit + 1; }
        }
        off = off + rl;
    }
    print("\n[8] list after rm =");
    print_i64(cnt);
    print_nl();
    if cnt != 1 { ok = 0; }
    if hit != 1 { ok = 0; }

    # ---- 9) VM 边界：损坏 / 恶意的包必须响亮失败，不能静默跑出垃圾 ----
    n = vm_selftest();
    print("[9] vmguard    =");
    print_i64(n);
    print_nl();
    if n != 1 { ok = 0; }

    print("pkg ok = ");
    print_i64(ok);
    print_nl();
    if ok == 1 { return 0; }
    return 1;
}
