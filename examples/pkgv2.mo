# pkgv2.mo —— 真正的包管理器：**版本升级 + 依赖解析 + 完整性校验**
#
# mo-target: cfs-aarch64   # 非原生后端，projcheck 跳过原生编译
#
#   bash tools/android_native.sh examples/pkgv2.mo /tmp/pkgv2.arm64
#   adb push /tmp/pkgv2.arm64 /data/local/tmp/pkgv2
#   adb shell /data/local/tmp/pkgv2
#
# 它是 examples/pkgmgr.mo（v1.155，能装/列/查/执行/卸）的**升级版**，
# 补上的是一个包管理器真正该有的三件事：
#
#   1. 版本比较与升级      → vcmp() 语义化比较；**降级被拒绝**，不是静默覆盖
#   2. 依赖解析            → DFS 后序拓扑排序，自动装齐依赖；**环被检测出来**
#   3. 完整性校验          → FNV-1a 32 位逐字节算；包被篡改时响亮失败
#
# 为什么这些必须在 freestanding 里自己写
# --------------------------------------
# 安卓原生没有 libc，也没有 fork/exec/git，更没有现成的包管理库。
# 所以版本比较、拓扑排序、哈希全部是手写 —— 而且手写才能做到一件事：
# **不静默**。降级、循环依赖、校验失败都必须返回一个明确的码，
# 而不是"看起来装上了"。
#
# 判据设计（区分"真做了"和"碰巧"）
# ------------------------------
#   · 升级后 CODE 从 6*7=42 换成 5*9=45
#     —— 只改版本号而代码没换，run 会仍旧输出 42，那样测不出"真的升级了"
#   · 降级被拒后，版本仍是 2.0.0、run 仍 45
#     —— 若降级被静默接受，run 会变回 42
#   · 依赖拓扑序必须是 libC → libB → app（后序）
#     —— 若实现成"按声明顺序"，会得到 app 在最前，装的时候依赖还没装
#   · 环检测返回 -2；若只是"跳过正在访问的节点"，会返回 0 且顺序表里少一个包
#
# 依赖的系统调用（全部经 x86→asm-generic 号表翻译）
# ------------------------------------------------
#   mkdirat(83) · openat(2) · write(1) · read(0) · close(3) · unlinkat(87)

# ---------- 字符串工具（自包含：freestanding 下不 import 任何库）----------

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

fn i2s(v: i64, d: ptr) -> i64 {     # 十进制（含负数）
    let n: i64 = 0;
    let t: i64 = 0;
    let i: i64 = 0;
    if v < 0 { store8(d, 45); n = 1; v = 0 - v; }
    if v == 0 { store8(d, 48); store8(d + 1, 0); return 1; }
    while v > 0 {
        t = v - (v / 10) * 10;
        store8(d + n, 48 + t);
        n = n + 1;
        v = v / 10;
    }
    store8(d + n, 0);
    # 反转数字部分
    let s: i64 = 0;
    if load8(d) == 45 { s = 1; }
    i = 0;
    while i < (n - s) / 2 {
        t = load8(d + s + i);
        store8(d + s + i, load8(d + n - 1 - i));
        store8(d + n - 1 - i, t);
        i = i + 1;
    }
    return n;
}

# ---------- 包注册表 ----------
# 全局数组**故意不写 = 0**：freestanding 下大数组的零初始化会被 C 编译器
# 优化成 memset 调用，链接时 undefined symbol: memset（v1.154 记过）。
# 全局数组天然落 .bss，由内核清零，不需要初始化器。

var PKB: [128] i64;      # 包名   8 × 16 字节
var PVB: [128] i64;      # 版本   8 × 16 字节
var PDB: [256] i64;      # 依赖   8 × 32 字节（逗号分隔）
var PN: i64 = 0;         # 已注册包数

var ORD: [8] i64;        # 拓扑序（后序：依赖在前）
var ON: i64 = 0;
var MARK: [8] i64;       # 0 未访问 · 1 访问中 · 2 已完成
var CY: i64 = 0;         # 检测到环


fn reg(nm: ptr, ver: ptr, deps: ptr) -> i64 {
    let i: i64 = PN;
    if i >= 8 { return -1; }
    scopy((&PKB + i * 16), nm);
    scopy((&PVB + i * 16), ver);
    scopy((&PDB + i * 32), deps);
    PN = PN + 1;
    return i;
}

fn find_pkg(nm: ptr) -> i64 {
    let i: i64 = 0;
    while i < PN {
        if slen((&PKB + i * 16)) == slen(nm) {
            if sfind((&PKB + i * 16), nm) == 0 { return i; }
        }
        i = i + 1;
    }
    return -1;
}

# ---------- 语义化版本比较：a>b → 1，a==b → 0，a<b → -1 ----------
#
# 按 '.' 分段逐段比数字。刻意**不**做字符串比较：
# "1.10.0" < "1.9.0" 按字典序是对的，按语义是错的。
fn vcmp(a: ptr, b: ptr) -> i64 {
    let ai: i64 = 0;
    let bi: i64 = 0;
    let av: i64 = 0;
    let bv: i64 = 0;
    while ai < slen(a) || bi < slen(b) {
        av = 0;
        while ai < slen(a) {
            if load8(a + ai) < 48 { break; }
            if load8(a + ai) > 57 { break; }
            av = av * 10 + load8(a + ai) - 48;
            ai = ai + 1;
        }
        bv = 0;
        while bi < slen(b) {
            if load8(b + bi) < 48 { break; }
            if load8(b + bi) > 57 { break; }
            bv = bv * 10 + load8(b + bi) - 48;
            bi = bi + 1;
        }
        if av > bv { return 1; }
        if av < bv { return -1; }
        if ai < slen(a) { ai = ai + 1; }
        if bi < slen(b) { bi = bi + 1; }
    }
    return 0;
}

# ---------- FNV-1a 32 位：包的完整性校验 ----------
#
# 逐字节。刻意**不**用"长度 + 首字节"这种假校验 —— 那种东西测不出
# "中间被改了一个字节"，而那正是篡改最常发生的地方。
fn fnv1a(p: ptr, n: i64) -> i64 {
    let h: i64 = 2166136261;
    let i: i64 = 0;
    while i < n {
        h = h * 16777619;
        h = h + load8(p + i);
        # 掩码回 32 位（h 恒为正，除法安全）
        h = h - (h / 4294967296) * 4294967296;
        i = i + 1;
    }
    return h;
}

# ---------- 依赖解析：DFS 后序拓扑排序 + 环检测 ----------

fn dfs(i: i64) -> i64 {
    let j: i64 = 0;
    let st: i64 = 0;
    let k: i64 = 0;
    let di: i64 = 0;
    let NM: [16] i64;
    if MARK[i] == 2 { return 0; }
    if MARK[i] == 1 { CY = 1; return -2; }
    MARK[i] = 1;
    # 逐段拆分（以逗号为界）
    st = 0;
    while st <= slen((&PDB + i * 32)) {
        if load8((&PDB + i * 32) + st) == 44 || load8((&PDB + i * 32) + st) == 0 {
            if st > 0 {
                k = 0;
                let q: i64 = 0;
                # 找到这一段起点
                q = st - 1;
                while q > 0 {
                    if load8((&PDB + i * 32) + q - 1) == 44 { break; }
                    q = q - 1;
                }
                while q < st {
                    store8(&NM + k, load8((&PDB + i * 32) + q));
                    q = q + 1;
                    k = k + 1;
                }
                store8(&NM + k, 0);
                if k > 0 {
                    di = find_pkg(&NM);
                    if di < 0 { return -3; }   # 依赖缺失：明确报错，不静默跳过
                    if dfs(di) == -2 { return -2; }
                }
            }
            if load8((&PDB + i * 32) + st) == 0 { st = st + 1; }
            st = st + 1;
        } else {
            st = st + 1;
        }
    }
    MARK[i] = 2;
    ORD[ON] = i;
    ON = ON + 1;
    return 0;
}

fn resolve(nm: ptr) -> i64 {
    let i: i64 = find_pkg(nm);
    ON = 0;
    CY = 0;
    let j: i64 = 0;
    while j < 8 { MARK[j] = 0; j = j + 1; }
    if i < 0 { return -1; }
    if dfs(i) < 0 { return -2; }
    return ON;
}

# ---------- 字节码构造与栈式 VM ----------

var CB: [64] i64;
var CBN: i64 = 0;
var VS: [64] i64;
var VM_OUT: i64 = 0;
var VOUT: [8] i64;

fn bemit(v: i64) -> i64 {
    store8(&CB + CBN, v);
    CBN = CBN + 1;
    return 0;
}

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

# 造一段 "a * b" 的字节码
fn bcode(a: i64, b: i64) -> i64 {
    CBN = 0;
    bemit(1); bemit32(a);
    bemit(1); bemit32(b);
    bemit(4); bemit(3); bemit(0);
    return CBN;
}

# 指令：0 HALT · 1 PUSHI imm32 · 2 ADD · 3 PRINT · 4 MUL
# 返回 -1 = 非法 opcode（不静默跳过：那会让"执行了"变成假的）
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

# ---------- 包存储：写清单 / 写 CODE / 读回 ----------

var ROOTB: [32] i64;

fn pkg_path(dst: ptr, nm: ptr) -> i64 {
    scopy(dst, &ROOTB);
    sapp(dst, "/");
    sapp(dst, nm);
    return 0;
}

fn read_file_bytes(p: ptr, buf: ptr, cap: i64) -> i64 {
    let fd: i64 = syscall(2, p, 0, 0, 0, 0);
    let n: i64 = 0;
    if fd < 0 { return -1; }
    n = syscall(0, fd, buf, cap, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    if n < 0 { return -1; }
    store8(buf + n, 0);
    return n;
}

fn write_file_bytes(p: ptr, buf: ptr, n: i64) -> i64 {
    let fd: i64 = syscall(2, p, 577, 420, 0, 0);
    let w: i64 = 0;
    if fd < 0 { return -1; }
    w = syscall(1, fd, buf, n, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    return w;
}

# 写清单：name / version / deps / checksum
fn write_manifest(nm: ptr, ver: ptr, deps: ptr, ck: i64) -> i64 {
    let MB: [96] i64;
    let NB: [16] i64;
    let P: [48] i64;
    scopy(&MB, "name=");
    sapp(&MB, nm);
    sapp(&MB, "\nversion=");
    sapp(&MB, ver);
    sapp(&MB, "\ndeps=");
    sapp(&MB, deps);
    sapp(&MB, "\nchecksum=");
    i2s(ck, &NB);
    sapp(&MB, &NB);
    sapp(&MB, "\n");
    pkg_path(&P, nm);
    sapp(&P, "/MANIFEST");
    return write_file_bytes(&P, &MB, slen(&MB));
}

# 从清单里取某个 key 的值（读到 \n 或结尾）
fn mget(src: ptr, key: ptr, out: ptr) -> i64 {
    let p: i64 = sfind(src, key);
    let i: i64 = 0;
    if p < 0 { return -1; }
    p = p + slen(key);
    while load8(src + p + i) != 0 {
        if load8(src + p + i) == 10 { break; }
        store8(out + i, load8(src + p + i));
        i = i + 1;
    }
    store8(out + i, 0);
    return i;
}

fn read_ver(nm: ptr, out: ptr) -> i64 {
    let P: [48] i64;
    let MB: [96] i64;
    pkg_path(&P, nm);
    sapp(&P, "/MANIFEST");
    if read_file_bytes(&P, &MB, 90) < 0 { return -1; }
    return mget(&MB, "version=", out);
}

fn read_ck(nm: ptr) -> i64 {
    let P: [48] i64;
    let MB: [96] i64;
    let CB2: [16] i64;
    let v: i64 = 0;
    let i: i64 = 0;
    let neg: i64 = 0;
    pkg_path(&P, nm);
    sapp(&P, "/MANIFEST");
    if read_file_bytes(&P, &MB, 90) < 0 { return -1; }
    if mget(&MB, "checksum=", &CB2) < 0 { return -1; }
    i = 0;
    if load8(&CB2) == 45 { neg = 1; i = 1; }
    while load8(&CB2 + i) != 0 {
        if load8(&CB2 + i) < 48 { return -1; }
        if load8(&CB2 + i) > 57 { return -1; }
        v = v * 10 + load8(&CB2 + i) - 48;
        i = i + 1;
    }
    if neg == 1 { v = 0 - v; }
    return v;
}

# verify：算 CODE 的校验和，与清单里的比对。一致返回 1，不一致 0，读不到 -1
fn verify(nm: ptr) -> i64 {
    let P: [48] i64;
    let B: [96] i64;
    let n: i64 = 0;
    pkg_path(&P, nm);
    sapp(&P, "/CODE");
    n = read_file_bytes(&P, &B, 90);
    if n < 0 { return -1; }
    if fnv1a(&B, n) == read_ck(nm) { return 1; }
    return 0;
}

# install：建目录 → 写 CODE → 算校验和 → 写清单
fn install(nm: ptr, ver: ptr, deps: ptr, a: i64, b: i64) -> i64 {
    let P: [48] i64;
    let ck: i64 = 0;
    pkg_path(&P, nm);
    if syscall(83, &P, 493, 0, 0, 0) < 0 { return -1; }
    bcode(a, b);
    pkg_path(&P, nm);
    sapp(&P, "/CODE");
    if write_file_bytes(&P, &CB, CBN) != CBN { return -1; }
    ck = fnv1a(&CB, CBN);
    if write_manifest(nm, ver, deps, ck) < 0 { return -1; }
    return reg(nm, ver, deps);
}

# upgrade：新版本必须**严格更高**才允许。返回 0 成功 / -1 降级被拒 / -2 读不到
fn upgrade(nm: ptr, ver: ptr, a: i64, b: i64) -> i64 {
    let OV: [16] i64;
    let P: [48] i64;
    let ck: i64 = 0;
    let i: i64 = 0;
    if read_ver(nm, &OV) < 0 { return -2; }
    if vcmp(ver, &OV) <= 0 { return -1; }      # 降级 / 同版本：拒绝
    bcode(a, b);
    pkg_path(&P, nm);
    sapp(&P, "/CODE");
    if write_file_bytes(&P, &CB, CBN) != CBN { return -2; }
    ck = fnv1a(&CB, CBN);
    # 依赖保持不变：读旧清单里的 deps 再写回
    let MB: [96] i64;
    let DB2: [32] i64;
    pkg_path(&P, nm);
    sapp(&P, "/MANIFEST");
    if read_file_bytes(&P, &MB, 90) < 0 { return -2; }
    mget(&MB, "deps=", &DB2);
    if write_manifest(nm, ver, &DB2, ck) < 0 { return -2; }
    i = find_pkg(nm);
    if i >= 0 { scopy((&PVB + i * 16), ver); }
    return 0;
}

# run：读 CODE → VM 执行 → 返回打印出的第一个值
fn run(nm: ptr) -> i64 {
    let P: [48] i64;
    let B: [96] i64;
    let n: i64 = 0;
    pkg_path(&P, nm);
    sapp(&P, "/CODE");
    n = read_file_bytes(&P, &B, 90);
    if n < 0 { return -1; }
    if vm_run(&B, n) < 0 { return -1; }
    if VM_OUT == 0 { return -1; }
    return VOUT[0];
}

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
    bcode(6, 7);
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

# ---------- 打包分发：包脱离 git / 仓库也能传输 ----------
#
# 安卓上没有 git，也没有包仓库。包怎么从"开发它的地方"到"运行它的地方"？
# 答案：包本身就是一串**可打印字节**，能走任何渠道——剪贴板、二维码、串口、
# HTTP body。pack 生成它，unpack 还原它。这是"自带运行环境"的前提：
# 运行时不依赖任何外部工具链，给它一串字节就能把包装上并跑起来。
#
# 流格式（全部可打印 ASCII，'|' 分隔）
#   MOPK1|<name>|<version>|<deps>|<len:8位hex>|<code:hex>|<ck:8位hex>
#
# 为什么长度字段不能省
# --------------------
# 只给 code 的 hex、靠 '\0' 判结尾的话，**传输被截断**是看不出来的：
# 剩下的半个包会被当成完整包装上，run 出一个错误结果却不报错。
# 所以 len 段必须与实际 hex 长度逐字符核对，不符就是 -5（要重传）。
#
# 为什么错误码要分开
# ------------------
#   -5 长度不符（被截断） → 重传
#   -6 校验不符（被篡改） → 拒收，可能是恶意的
#   -7 超出容量           → 包太大，不是坏了
#   -8 非法 hex           → 格式错
# 统一返回 -1 的话，调用方分不清"重传"和"报警"，恶意包会被无限重试。
#
# 检查顺序刻意是「容量 → 长度 → 内容」：先判装不装得下，再判有没有被截断，
# 最后才判内容对不对。反过来会让"超大包"被报成"被截断"。

var SB: [512] i64;       # 序列化流（可传输形态）
var SB2: [512] i64;      # 副本：改坏之后要能还原
var UBUF: [64] i64;      # 解出的 CODE
var UBN: i64 = 0;
var PHEXN: i64 = 0;

fn hexv(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return c - 48; }
    }
    if c >= 97 {
        if c <= 102 { return c - 97 + 10; }
    }
    return -1;
}

fn hexch(d: i64) -> i64 {
    if d < 10 { return d + 48; }
    return d + 87;
}

# 追加 v 的 8 位十六进制（固定宽度，用于 len 与 ck）
fn hex8(dst: ptr, v: i64) -> i64 {
    let o: i64 = slen(dst);
    let s: i64 = 268435456;
    let i: i64 = 0;
    let d: i64 = 0;
    while i < 8 {
        d = v / s;
        store8(dst + o + i, hexch(d - (d / 16) * 16));
        v = v - d * s;
        s = s / 16;
        i = i + 1;
    }
    store8(dst + o + 8, 0);
    return 0;
}

# 把 b[0..n) 追加成 hex（每字节 2 字符）
fn tohex(dst: ptr, b: ptr, n: i64) -> i64 {
    let o: i64 = slen(dst);
    let i: i64 = 0;
    let c: i64 = 0;
    let hi: i64 = 0;
    while i < n {
        c = load8(b + i);
        hi = c / 16;
        store8(dst + o, hexch(hi));
        store8(dst + o + 1, hexch(c - hi * 16));
        o = o + 2;
        i = i + 1;
    }
    store8(dst + o, 0);
    return o;
}

# 第 k 段的起点（k 从 0 起）
fn segpos(s: ptr, k: i64) -> i64 {
    let c: i64 = 0;
    let p: i64 = 0;
    while c < k {
        if load8(s + p) == 0 { return -1; }
        while load8(s + p) != 0 {
            if load8(s + p) == 124 { p = p + 1; break; }
            p = p + 1;
        }
        c = c + 1;
    }
    return p;
}

# 读一段：从 pos 到下一个 '|'，写入 out；返回下一段起点（-1 = 后面没有了）
fn take_seg(s: ptr, pos: i64, out: ptr) -> i64 {
    let i: i64 = 0;
    while load8(s + pos + i) != 0 {
        if load8(s + pos + i) == 124 { break; }
        store8(out + i, load8(s + pos + i));
        i = i + 1;
    }
    store8(out + i, 0);
    if load8(s + pos + i) == 0 { return 0 - 1; }
    return pos + i + 1;
}

# 解包：解析 → 校验 → 落盘 → 注册。成功返回包索引，失败返回负错误码
fn unpack(s: ptr) -> i64 {
    let p: i64 = 0;
    let F0: [16] i64;
    let NM2: [16] i64;
    let VB2: [16] i64;
    let DB2: [32] i64;
    let LH: [16] i64;
    let HH: [256] i64;
    let CH: [16] i64;
    let P: [48] i64;
    let len: i64 = 0;
    let ck: i64 = 0;
    let v: i64 = 0;
    let i: i64 = 0;
    let d: i64 = 0;
    let hi: i64 = 0;
    let lo: i64 = 0;
    if slen(s) == 0 { return -1; }
    p = take_seg(s, 0, &F0);
    if slen(&F0) != 5 { return -1; }
    if sfind(&F0, "MOPK1") != 0 { return -1; }
    if p < 0 { return -1; }
    p = take_seg(s, p, &NM2);
    if p < 0 { return -1; }
    p = take_seg(s, p, &VB2);
    if p < 0 { return -1; }
    p = take_seg(s, p, &DB2);
    if p < 0 { return -1; }
    p = take_seg(s, p, &LH);
    if p < 0 { return -1; }
    p = take_seg(s, p, &HH);
    if p < 0 { return -1; }
    take_seg(s, p, &CH);
    # --- len ---
    if slen(&LH) != 8 { return -8; }
    i = 0;
    while i < 8 {
        d = hexv(load8(&LH + i));
        if d < 0 { return -8; }
        len = len * 16 + d;
        i = i + 1;
    }
    # 容量先判：装不下的包不是"坏了"，不该报成被截断
    if len > 64 { return -7; }
    if len < 0 { return -7; }
    # 长度字段必须与实际 hex 长度逐字符相符
    if slen(&HH) != len * 2 { return -5; }
    # --- 解 hex ---
    i = 0;
    while i < len {
        hi = hexv(load8(&HH + i * 2));
        lo = hexv(load8(&HH + i * 2 + 1));
        if hi < 0 { return -8; }
        if lo < 0 { return -8; }
        store8(&UBUF + i, hi * 16 + lo);
        i = i + 1;
    }
    UBN = len;
    # --- ck ---
    if slen(&CH) != 8 { return -8; }
    i = 0;
    while i < 8 {
        d = hexv(load8(&CH + i));
        if d < 0 { return -8; }
        ck = ck * 16 + d;
        i = i + 1;
    }
    if fnv1a(&UBUF, UBN) != ck { return -6; }
    # --- 落盘 + 注册 ---
    pkg_path(&P, &NM2);
    d = syscall(83, &P, 493, 0, 0, 0);
    # 目录已存在不是错误：重复解包同一个包是正常操作
    if d < 0 { if d != -17 { return -2; } }
    pkg_path(&P, &NM2);
    sapp(&P, "/CODE");
    if write_file_bytes(&P, &UBUF, UBN) != UBN { return -2; }
    if write_manifest(&NM2, &VB2, &DB2, ck) < 0 { return -2; }
    v = find_pkg(&NM2);
    if v >= 0 { return v; }
    return reg(&NM2, &VB2, &DB2);
}

# 打包：读已装好的包 → 生成可传输的字节流
fn pack(nm: ptr) -> i64 {
    let P: [48] i64;
    let MB: [96] i64;
    let VB2: [16] i64;
    let DB2: [32] i64;
    let B: [96] i64;
    let n: i64 = 0;
    let ck: i64 = 0;
    pkg_path(&P, nm);
    sapp(&P, "/CODE");
    n = read_file_bytes(&P, &B, 90);
    if n < 0 { return -1; }
    if n > 64 { return -7; }
    pkg_path(&P, nm);
    sapp(&P, "/MANIFEST");
    if read_file_bytes(&P, &MB, 90) < 0 { return -1; }
    if mget(&MB, "version=", &VB2) < 0 { return -1; }
    if mget(&MB, "deps=", &DB2) < 0 { return -1; }
    ck = fnv1a(&B, n);
    scopy(&SB, "MOPK1|");
    sapp(&SB, nm);
    sapp(&SB, "|");
    sapp(&SB, &VB2);
    sapp(&SB, "|");
    sapp(&SB, &DB2);
    sapp(&SB, "|");
    hex8(&SB, n);
    sapp(&SB, "|");
    PHEXN = tohex(&SB, &B, n);
    sapp(&SB, "|");
    hex8(&SB, ck);
    pkg_path(&P, nm);
    sapp(&P, "/PACK");
    write_file_bytes(&P, &SB, slen(&SB));
    return 0;
}

fn main() -> i64 {
    let ok: i64 = 1;
    let n: i64 = 0;
    let i: i64 = 0;
    let q: i64 = 0;
    let c0: i64 = 0;
    let VB: [16] i64;
    let P: [48] i64;

    scopy(&ROOTB, "/tmp/mo_pkgs_v2");
    print("=== mo-pkg v2 : 升级 + 依赖 + 校验 ===\n");

    # ---- 1) 注册并装三个包（app → libB → libC）----
    n = syscall(83, &ROOTB, 493, 0, 0, 0);
    print("[1] init root     ret=");
    print_i64(n);
    print_nl();
    if n != 0 { if n != -17 { ok = 0; } }

    # 注册由 install 内部完成。若在这里预先 reg，同一个包会进两次表，
    # install 的返回值就变成 3/4/5 而不是 0/1/2 —— 那种错位不报错，
    # 只会让"装到第几个"这个判据失去意义。
    n = install("libC", "1.0.0", "", 2, 3);
    print("[1] install libC  ret=");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }
    n = install("libB", "1.0.0", "libC", 4, 5);
    print("[1] install libB  ret=");
    print_i64(n);
    print_nl();
    if n != 1 { ok = 0; }
    n = install("app", "1.0.0", "libB,libC", 6, 7);
    print("[1] install app   ret=");
    print_i64(n);
    print_nl();
    if n != 2 { ok = 0; }

    # ---- 2) 依赖解析：必须是后序（依赖在前）----
    n = resolve("app");
    print("[2] topo n        =");
    print_i64(n);
    print_nl();
    if n != 3 { ok = 0; }
    print("[2] topo order    =");
    i = 0;
    while i < ON {
        pstr((&PKB + ORD[i] * 16));
        print(" ");
        i = i + 1;
    }
    print_nl();
    # 后序：libC(0) → libB(1) → app(2)
    if ON == 3 {
        if ORD[0] != 0 { ok = 0; }
        if ORD[1] != 1 { ok = 0; }
        if ORD[2] != 2 { ok = 0; }
    }

    # ---- 3) 完整性校验：未篡改应通过 ----
    n = verify("app");
    print("[3] verify app    =");
    print_i64(n);
    print_nl();
    if n != 1 { ok = 0; }

    # ---- 4) 升级：1.0.0 → 2.0.0，且 CODE 真的换了 ----
    n = run("app");
    print("[4] run 1.0.0     out=");
    print_i64(n);
    print_nl();
    if n != 42 { ok = 0; }

    n = upgrade("app", "2.0.0", 5, 9);
    print("[4] upgrade ret   =");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }

    if read_ver("app", &VB) >= 0 {
        print("[4] ver after     =");
        pstr(&VB);
        print_nl();
        if sfind(&VB, "2.0.0") != 0 { ok = 0; }
    } else { ok = 0; }

    n = run("app");
    print("[4] run 2.0.0     out=");
    print_i64(n);
    print_nl();
    if n != 45 { ok = 0; }        # 5*9 —— 证明 CODE 真换了，不只是版本号

    n = verify("app");
    print("[4] verify after  =");
    print_i64(n);
    print_nl();
    if n != 1 { ok = 0; }

    # ---- 5) 降级必须被拒绝，且版本与 CODE 都保持不变 ----
    n = upgrade("app", "1.5.0", 6, 7);
    print("[5] downgrade ret =");
    print_i64(n);
    print_nl();
    if n != -1 { ok = 0; }

    if read_ver("app", &VB) >= 0 {
        print("[5] ver after     =");
        pstr(&VB);
        print_nl();
        if sfind(&VB, "2.0.0") != 0 { ok = 0; }
    } else { ok = 0; }

    n = run("app");
    print("[5] run after     out=");
    print_i64(n);
    print_nl();
    if n != 45 { ok = 0; }        # 若降级被静默接受，这里会是 42

    # ---- 6) 篡改：改 CODE 但不动清单 → verify 必须失败 ----
    bcode(9, 9);                   # 81，与原 CODE 不同
    pkg_path(&P, "app");
    sapp(&P, "/CODE");
    n = write_file_bytes(&P, &CB, CBN);
    n = verify("app");
    print("[6] tamper verify =");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }          # 0 = 校验不一致，不是"仍然通过"

    # ---- 7) 循环依赖：必须报 -2，不是静默给一个缺包少包的顺序 ----
    reg("cyc1", "1.0.0", "cyc2");
    reg("cyc2", "1.0.0", "cyc1");
    n = resolve("cyc1");
    print("[7] cycle ret     =");
    print_i64(n);
    print_nl();
    if n != -2 { ok = 0; }
    print("[7] cycle flag    =");
    print_i64(CY);
    print_nl();
    if CY != 1 { ok = 0; }

    # ---- 8) 缺失依赖：报 -3 ----
    reg("gone", "1.0.0", "nosuch");
    n = resolve("gone");
    print("[8] missing ret   =");
    print_i64(n);
    print_nl();
    if n != -2 { ok = 0; }         # dfs 返回 -3 → resolve 归一为 -2

    # ---- 9) VM 边界：损坏 / 恶意的包必须响亮失败，不能静默跑出垃圾 ----
    n = vm_selftest();
    print("[9] vmguard    =");
    print_i64(n);
    print_nl();
    if n != 1 { ok = 0; }

    # ---- 10) 打包分发：pack → 删掉 CODE → unpack 还原；坏包必须响亮拒绝 ----
    n = install("dist", "1.0.0", "", 6, 7);
    print("[10] install dist =");
    print_i64(n);
    print_nl();
    if n != 6 { ok = 0; }

    n = pack("dist");
    print("[10] pack ret     =");
    print_i64(n);
    print_nl();
    if n != 0 { ok = 0; }
    print("[10] stream       =");
    pstr(&SB);
    print_nl();

    # 把磁盘上的 CODE 真的删掉：这样后面 run 能跑出 42，就只可能来自
    # 解包写回的文件，而不是内存里残留的状态
    pkg_path(&P, "dist");
    sapp(&P, "/CODE");
    syscall(87, &P, 0, 0, 0, 0);
    n = run("dist");
    print("[10] run deleted  =");
    print_i64(n);
    print_nl();
    if n != -1 { ok = 0; }

    scopy(&SB2, &SB);
    n = unpack(&SB);
    print("[10] unpack ret   =");
    print_i64(n);
    print_nl();
    if n != 6 { ok = 0; }

    n = run("dist");
    print("[10] run restored =");
    print_i64(n);
    print_nl();
    if n != 42 { ok = 0; }

    # A) 篡改 code hex 的一个字符（仍是合法 hex、长度不变）→ 校验必须失败
    scopy(&SB, &SB2);
    q = segpos(&SB, 5);
    # 必须先把原值读出来：写成两条 if 的话，第二条会把第一条刚改的值
    # 又判一次、改回去 —— 结果是"什么都没改"，unpack 自然照样成功。
    c0 = load8(&SB + q);
    if c0 == 48 { store8(&SB + q, 49); }
    if c0 != 48 { store8(&SB + q, 48); }
    n = unpack(&SB);
    print("[10] tamper ret   =");
    print_i64(n);
    print_nl();
    if n != -6 { ok = 0; }

    # B) 传输被截断：len 说 1 字节，实际给了完整的 hex → 长度不符
    scopy(&SB, &SB2);
    q = segpos(&SB, 4);
    store8(&SB + q + 7, 49);
    n = unpack(&SB);
    print("[10] trunc ret    =");
    print_i64(n);
    print_nl();
    if n != -5 { ok = 0; }

    # C) 非法 hex 字符 → 格式错，不是"内容错"
    scopy(&SB, &SB2);
    q = segpos(&SB, 5);
    store8(&SB + q, 122);
    n = unpack(&SB);
    print("[10] badhex ret   =");
    print_i64(n);
    print_nl();
    if n != -8 { ok = 0; }

    # D) 长度字段超大 → 容量错（装不下，不是被截断）
    scopy(&SB, &SB2);
    q = segpos(&SB, 4);
    store8(&SB + q + 6, 54);
    store8(&SB + q + 7, 52);
    n = unpack(&SB);
    print("[10] toobig ret   =");
    print_i64(n);
    print_nl();
    if n != -7 { ok = 0; }

    print("pkg ok = ");
    print_i64(ok);
    print_nl();
    if ok == 1 { return 0; }
    return 1;
}
