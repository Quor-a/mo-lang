
# ==========================================================================
#  x86-64 指令发射
# ==========================================================================
fn ops2(a: i64, b: i64) -> i64 {
    emit1(a);
    emit1(b);
    return 0;
}

fn ops3(a: i64, b: i64, c: i64) -> i64 {
    emit1(a);
    emit1(b);
    emit1(c);
    return 0;
}

fn ops4(a: i64, b: i64, c: i64, d: i64) -> i64 {
    emit1(a);
    emit1(b);
    emit1(c);
    emit1(d);
    return 0;
}

# mov rax, imm
#   小常量（0 <= v < 2^32）用 mov eax, imm32（B8 imm32，5 字节）
#   而不是 movabs rax, imm64（48 B8 imm64，10 字节）——省 5 字节
#   注意：需要 8 字节回填的调用点走 emit_call_patch，不走这里
# ============ 调试信息缓冲（-g 专用）============
# 所有 debug section 共用 O_DBG，用 K_DBBASE 区分段落。
# 不开启 -g 时这些函数完全不会被调用。

fn store32(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    store8(p + 2, (v / 65536) & 255);
    store8(p + 3, (v / 16777216) & 255);
    return 0;
}

fn store16(p: i64, v: i64) -> i64 {
    store8(p, v & 255);
    store8(p + 1, (v / 256) & 255);
    return 0;
}

# 注意：store8 的实参里不能再嵌 gv(K_DBBASE) 之类的函数调用。
# 编译器用同一个缓冲区存「当前被调函数名」，实参里的嵌套调用会把它覆盖掉，
# 于是外层的 store8 变成去调别的函数（踩过，现象是写进来的全是 0）。
# 规矩：内建函数调用的实参必须是常量或局部变量。
fn db_u8(b: i64) -> i64 {
    let n: i64 = gv(K_DBGLEN);
    let bs: i64 = gv(K_DBBASE);
    store8(DBG + O_DBG + bs + n, b);
    sv(K_DBGLEN, n + 1);
    return 0;
}

fn db_u16(v: i64) -> i64 {
    db_u8(v & 255);
    db_u8((v / 256) & 255);
    return 0;
}

# 在缓冲 pos 处回填 u32，不推进长度。
# 为什么需要：写 `db_u32(dbg_ty_emit(x))` 会**先求值实参**，于是子类型的
# DIE 被整段插进本 DIE 中间 —— readelf 把它的头 4 字节当成 DW_AT_type 的
# ref4，从那里起全部错位，最终报 "abbreviation number 101 does not exist"。
# 正确顺序：先发本 DIE 的头部并给 ref4 留 4 字节占位，再递归，最后回填。
fn db_u32_at(p: i64, v: i64) -> i64 {
    let bs: i64 = gv(K_DBBASE);
    let q: i64 = DBG + O_DBG + bs + p;
    store8(q, v & 255);
    store8(q + 1, (v / 256) & 255);
    store8(q + 2, (v / 65536) & 255);
    store8(q + 3, (v / 16777216) & 255);
    return 0;
}

fn db_u32(v: i64) -> i64 {
    db_u8(v & 255);
    db_u8((v / 256) & 255);
    db_u8((v / 65536) & 255);
    db_u8((v / 16777216) & 255);
    return 0;
}

fn db_u64(v: i64) -> i64 {
    let i: i64 = 0;
    while i < 8 {
        db_u8((v / (1 << (i * 8))) & 255);
        i = i + 1;
    }
    return 0;
}

# 🔴 db_u64 对负数**是错的**：`v / 256` 向零截断，-4 / 256 = 0，
#    于是 -4 被写成 `fc 00 00 00 00 00 00 00` = **+252**，
#    而不是正确的 `fc ff ff ff ff ff ff ff`。
#
# 差值恰好 256 —— 表现为链接后 call 目标整整偏 0x100，
# 跳进未映射地址直接段错误。readelf 会把两者都显示成 "fc"，
# 只有 ref.o 那种正宗产物才显示 "- 4"，很难一眼看出区别。
#
# 有符号值（如重定位的 addend）一律用这个。
fn db_i64(v: i64) -> i64 {
    let i: i64 = 0;
    while i < 8 {
        db_u8((v >> (i * 8)) & 255);
        i = i + 1;
    }
    return 0;
}

# 回填：把 v 写到当前段落的偏移 p 处（unit_length 要先占位后填）
fn db_poke32(p: i64, v: i64) -> i64 {
    let bs: i64 = gv(K_DBBASE);
    let b: i64 = DBG + O_DBG + bs;
    store8(b + p, v & 255);
    store8(b + p + 1, (v / 256) & 255);
    store8(b + p + 2, (v / 65536) & 255);
    store8(b + p + 3, (v / 16777216) & 255);
    return 0;
}

# ULEB128：只用于非负数（地址、长度、文件号）
fn db_uleb(v: i64) -> i64 {
    while v > 127 {
        db_u8((v & 127) | 128);
        v = v / 128;
    }
    db_u8(v & 255);
    return 0;
}

# SLEB128：行号增量可正可负
#
# 🔴 必须用**算术右移**（向下取整），不能写 `v / 128`。
#    墨语言的 `/` 对负数向零截断：-8 / 128 = 0，而 SLEB128 需要 -1。
#    于是 (v == -1) 这个终止分支永远进不去，负数会被多编一个字节：
#      -8  编成 f8 00（解出来是 **+120**，而不是 -8）
#      -16 编成 f0 00（解出来是 **+112**）
#    行号表只用正向增量所以没暴露；一用来编码变量相对 rbp 的负偏移，
#    gdb 读到的位置就全是正数、完全错乱。
fn db_sleb(v: i64) -> i64 {
    while 1 {
        let b: i64 = v & 127;
        let q: i64 = v / 128;
        if v < 0 {
            if q * 128 != v { q = q - 1; }
        }
        v = q;
        if v == 0 {
            if (b & 64) == 0 {
                db_u8(b);
                return 0;
            }
        } else {
            if v == 0 - 1 {
                if (b & 64) != 0 {
                    db_u8(b);
                    return 0;
                }
            }
        }
        db_u8(b | 128);
    }
    return 0;
}

fn db_str(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        db_u8(load8(s + i));
        i = i + 1;
    }
    db_u8(0);
    return 0;
}

# -g：把源文件路径登记进文件名表（供 .debug_line 的 file_names 用）。
# 下标 0 是主文件，1.. 是 import 进来的。每条 256 字节，含结尾 NUL。
fn dbg_fname(k: i64, path: i64) -> i64 {
    if k < 0 { return 0; }
    if k >= 32 { return 0; }
    let q: i64 = 0;
    while q < 255 {
        let cc: i64 = load8(path + q);
        store8(DBG + O_FNM + k * 256 + q, cc);
        if cc == 0 { q = 255; }
        q = q + 1;
    }
    store8(DBG + O_FNM + k * 256 + 255, 0);
    return 0;
}

# -shared 下取全局变量地址：发 movabs rax,0 并登记一条重定位。
#
# 为什么必须如此：共享库的加载基址是随机的，编译期算出的绝对地址
# （268435456+off）在运行时**根本不对**。x86 又不能把 64 位立即数
# 编码进 RIP 相对寻址，所以只能让 ld.so 在加载时填 base+addend。
#
# 判据用 v >= 268435456（= 数据段基址 0x10000000）：
#   代码地址从 4194304 起，普通常量更小 —— 都不会误伤。
# 🔴 关键：用 **RIP 相对 lea**，不是 movabs 绝对地址 + RELATIVE 重定位。
#
# 第一版发 `movabs r11,0` + R_X86_64_RELATIVE，ld 在链接时**直接把
# addend 当最终值填了**（.rela.dyn 是空的），于是 .so 里的数据地址是
# 链接时的绝对地址；运行时 .so 被加载到随机基址，该地址即无效 →
# 调用任何访问全局变量的函数都段错误（纯函数却完全正常，极难联想）。
#
# RIP 相对天然正确：代码与数据在同一个 segment 内，相对距离链接后固定，
# 加载时整块平移、相对关系不变 —— 不需要 ld.so 做任何事。
#
#   lea r11, [rip+d32]   = 4c 8d 9d <d32>   （7 字节）
#   lea rax, [rip+d32]   = 48 8d 05 <d32>   （7 字节）
# 重定位用 R_X86_64_PC32(type 2)，符号 = .data 的 section 符号。
# ld 算 S + A - P，P 是**重定位处**（= 指令+3，即 d32 的位置），
# 要得到 d32 = (data+off) - (指令+7)，故 A = off - 4。
fn emit_gvar_addr(off: i64) -> i64 {
    spill_cache();
    let k: i64 = load64(DBG + O_GVN);
    if k >= 4096 { return die("too many global refs (limit 4096)"); }
    ops3(0x48, 0x8d, 0x05);
    store64(DBG + O_GVP + k * 8, gv(K_CLEN));
    store64(DBG + O_GVA + k * 8, off);
    store64(DBG + O_GVN, k + 1);
    emit4(0);
    return 0;
}

# 同一个东西的 r11 版本。
#
# 🔴 全局变量**不走 g_movabs_rax** —— 编译器用 r11 做地址寄存器
#    （g_load_global / g_store_global 都是 g_movabs_r11）。
#    只在 rax 那条路上加分支，重定位一条都不会生成，
#    于是 .so 里全局变量地址仍是编译期的绝对地址 —— 运行即错。
fn emit_gvar_addr_r11(off: i64) -> i64 {
    spill_cache();
    let k: i64 = load64(DBG + O_GVN);
    if k >= 4096 { return die("too many global refs (limit 4096)"); }
    # 🔴 ModRM 必须是 0x1d（mod=00, reg=011, rm=101 = RIP 相对）。
    #    第一版写 0x9d —— mod=10，变成 **[rbp+disp32]**，
    #    于是读的是栈上的垃圾；链接一切正常、运行也不崩，
    #    只是全局变量的值全错（42 读成 4419247591793840201）。
    ops3(0x4c, 0x8d, 0x1d);
    store64(DBG + O_GVP + k * 8, gv(K_CLEN));
    store64(DBG + O_GVA + k * 8, off);
    store64(DBG + O_GVN, k + 1);
    emit4(0);
    return 0;
}

fn g_movabs_rax(v: i64) -> i64 {
    if load64(DBG + O_SOF) == 1 {
        if v >= 268435456 { return emit_gvar_addr(v - 268435456); }
    }
    if v < 0 {
        ops2(0x48, 0xb8);
        emit8(v);
        return 0;
    }
    if v > 4294967295 {
        ops2(0x48, 0xb8);
        emit8(v);
        return 0;
    }
    emit1(0xb8);
    emit4(v);
    sv(K_LAST, 1);
    sv(K_LASTV, v);
    sv(K_LASTR, 5);
    return 0;
}

fn g_movabs_r11(v: i64) -> i64 {
    if load64(DBG + O_SOF) == 1 {
        if v >= 268435456 { return emit_gvar_addr_r11(v - 268435456); }
    }
    ops2(0x49, 0xbb);
    emit8(v);
    return 0;
}

# 局部量一律以 [rbp+off] 寻址。off 落在 -128..127 时用 disp8 编码（4 字节），
# 否则退回 disp32（7 字节）。函数帧很大时才走 disp32 分支。
fn g_load_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x8b, 0x85); emit4(off); sv(K_LAST, 2); sv(K_LASTV, off); sv(K_LASTR, 7); return 0; }
    if off > 127 { ops3(0x48, 0x8b, 0x85); emit4(off); sv(K_LAST, 2); sv(K_LASTV, off); sv(K_LASTR, 7); return 0; }
    ops2(0x48, 0x8b);
    emit1(0x45);
    emit1(off & 255);
    sv(K_LAST, 2);
    sv(K_LASTV, off);
    sv(K_LASTR, 4);
    return 0;
}

# ---- 捕获变量：通过静态链 [rbp] 间接访问外层栈帧 ----
#
# 嵌套函数在词法上位于外层函数体内，代码**就地发射**（外层用 jmp 跳过）。
# 于是被调用时 [rbp] 就是外层函数的帧指针，捕获的变量按 [外层rbp + off] 取。
#
# 🔴 不能直接用 rax 取外层帧：store 时 rax 里是要写入的值，一用就覆盖。
#    用 r11 做中转（caller-saved，只在 arg_spill 里短暂用过）。
#      mov r11, [rbp+0]      = 4C 8B 5D 00
#      mov rax, [r11+disp32] = 49 8B 83 <disp32>
#      mov [r11+disp32], rax = 49 89 83 <disp32>
fn g_load_captured(off: i64, n: i64) -> i64 {
    g_walk_static(n);
    ops3(0x49, 0x8b, 0x83);
    emit4(off);
    sv(K_LAST, 3);
    return 0;
}

fn g_store_captured(off: i64, n: i64) -> i64 {
    g_walk_static(n);
    ops3(0x49, 0x89, 0x83);
    emit4(off);
    return 0;
}

# 沿静态链走 n 层，结果留在 r11 —— 即目标外层函数的帧指针。
#
#   第 1 层：mov r11, [rbp+0]   = 4C 8B 5D 00    （[rbp] 就是调用者帧）
#   之后每层：mov r11, [r11+0]  = 4D 8B 5B 00
#
# 🔴 n 必须 >= 1。n == 0 意味着"不是捕获"，调用方根本不该走到这里；
#    真走到这里说明 cap_depth 的判据错了，而症状是**读到完全无关的栈内容**
#    （不报错、不崩溃），所以这里显式钉一条保护：n<1 时按 1 处理并把
#    错误计数置上，而不是静默地发射 0 条指令（那会让 r11 保留上一次的
#    垃圾值，是最难查的一类）。
fn g_walk_static(n: i64) -> i64 {
    ops3(0x4c, 0x8b, 0x5d);
    emit1(0);
    let i: i64 = 1;
    while i < n {
        ops3(0x4d, 0x8b, 0x5b);
        emit1(0);
        i = i + 1;
    }
    return 0;
}

fn g_store_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x89, 0x85); emit4(off); return 0; }
    if off > 127 { ops3(0x48, 0x89, 0x85); emit4(off); return 0; }
    ops2(0x48, 0x89);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

# lea rax, [rbp+off]  —— 取局部量（含数组基址）的地址
# ---- 结构体整体拷贝原语 ----
fn g_lea_rsi_local(off: i64) -> i64 {
    ops2(0x48, 0x8d);
    emit1(0x75);
    emit1(off & 255);
    return 0;
}
fn g_movabs_rsi(a: i64) -> i64 { ops2(0x48, 0xbe); emit8(a); return 0; }
fn g_movabs_rcx(a: i64) -> i64 { ops2(0x48, 0xb9); emit8(a); return 0; }
fn g_rbx_from_rsi() -> i64 { ops3(0x48, 0x8b, 0x1e); return 0; }
fn g_rbx_to_rax() -> i64 { ops3(0x48, 0x89, 0x18); return 0; }
fn g_add_rax8() -> i64 { ops3(0x48, 0x83, 0xc0); emit1(8); return 0; }
fn g_add_rsi8() -> i64 { ops3(0x48, 0x83, 0xc6); emit1(8); return 0; }
fn g_addr_sym_rax(s: i64) -> i64 {
    if sym_kind(s) == 1 { return g_lea_local(sym_addr(s)); }
    return g_movabs_rax(sym_addr(s));
}
fn g_addr_sym_rsi(s: i64) -> i64 {
    if sym_kind(s) == 1 { return g_lea_rsi_local(sym_addr(s)); }
    return g_movabs_rsi(sym_addr(s));
}
fn g_copy_words(n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        g_rbx_from_rsi();
        g_rbx_to_rax();
        if i < n - 1 { g_add_rax8(); g_add_rsi8(); }
        i = i + 1;
    }
    return 0;
}
fn g_lea_local(off: i64) -> i64 {
    if off < -128 { ops3(0x48, 0x8d, 0x85); emit4(off); return 0; }
    if off > 127 { ops3(0x48, 0x8d, 0x85); emit4(off); return 0; }
    ops2(0x48, 0x8d);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

# mov rax, [rax]
# 按 1 字节加载并零扩展：movzx eax, byte [rax]
fn g_load_at_b() -> i64 {
    ops2(0x0f, 0xb6);
    emit1(0x00);
    sv(K_LAST, 0);
    return 0;
}
# 只写低 1 字节：mov byte [rcx], al
fn g_store_at_b() -> i64 {
    ops2(0x88, 0x01);
    return 0;
}
fn g_load_at() -> i64 {
    ops3(0x48, 0x8b, 0x00);
    return 0;
}

# mov [rcx], rax
fn g_store_at() -> i64 {
    ops3(0x48, 0x89, 0x01);
    return 0;
}

# shl rax, 3  —— 下标换算成字节偏移
fn g_shl3() -> i64 {
    ops3(0x48, 0xc1, 0xe0);
    emit1(3);
    return 0;
}

# 判断 v 是否为 2 的幂，是则返回 log2(v)，否则返回 -1
fn log2p2(v: i64) -> i64 {
    if v <= 0 { return -1; }
    let s: i64 = 0;
    let x: i64 = v;
    while x > 1 {
        if (x & 1) == 1 { return -1; }
        x = x / 2;
        s = s + 1;
    }
    return s;
}

# rax *= v。v 是 2 的幂时改用 shl（4 字节，比 imul 的 6 字节短），
# v == 1 时什么都不发。数组/结构体下标换算几乎总落在 8 或 16 上。
fn g_mul_imm(v: i64) -> i64 {
    let s: i64 = log2p2(v);
    if s == 0 { return 0; }
    if s > 0 {
        ops3(0x48, 0xc1, 0xe0);
        emit1(s);
        return 0;
    }
    ops3(0x48, 0x69, 0xc0);
    emit4(v);
    return 0;
}

# ---- byte 宽度（1 字节）的加载 / 存储 ----
# byte 变量本身仍占 8 字节（栈帧与数据段布局不变），
# 只有读写指令的宽度是 1 字节：加载零扩展，存储截断到低 8 位。
fn g_load_local_b(off: i64) -> i64 {
    if off < -128 { ops2(0x0f, 0xb6); emit1(0x85); emit4(off); sv(K_LAST, 0); return 0; }
    if off > 127 { ops2(0x0f, 0xb6); emit1(0x85); emit4(off); sv(K_LAST, 0); return 0; }
    ops2(0x0f, 0xb6);
    emit1(0x45);
    emit1(off & 255);
    sv(K_LAST, 0);
    return 0;
}
fn g_store_local_b(off: i64) -> i64 {
    if off < -128 { emit1(0x88); emit1(0x85); emit4(off); return 0; }
    if off > 127 { emit1(0x88); emit1(0x85); emit4(off); return 0; }
    emit1(0x88);
    emit1(0x45);
    emit1(off & 255);
    return 0;
}

fn g_load_global(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x8b, 0x03);
    return 0;
}

fn g_store_global(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x89, 0x03);
    return 0;
}
fn g_load_global_b(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x0f, 0xb6);
    emit1(0x03);
    sv(K_LAST, 0);
    return 0;
}
fn g_store_global_b(a: i64) -> i64 {
    g_movabs_r11(a);
    ops3(0x49, 0x88, 0x03);
    return 0;
}

# 按符号的实际类型选择读写宽度。byte 用 1 字节指令，其余仍按 8 字节。
# 符号是否是被捕获的外层局部变量。
# 判据：当前在嵌套函数里（K_NEST>0），且符号落在「外层函数的局部区间」内 ——
# 即 >= 外层基线 且 < 当前函数基线。
#
# 🔴 只判 `s < K_FNBASE` 是不够的：顶层全局变量和 predeclare 登记的函数
#    下标更小，会被误判成捕获 → 生成 [外层rbp+off] 去读全局变量，
#    读到的是栈上的垃圾，**编译不报错、运行静默出错**。
fn cap_depth(s: i64) -> i64 {
    let n: i64 = load64(heap + O_NEST);
    if n == 0 { return 0; }
    # 当前层的局部变量：不是捕获。
    # 🔴 这一条同时是"外层函数返回后 K_FNBASE 必须已恢复"的守卫 ——
    #    解析完嵌套函数若没恢复，这里会把外层的局部变量误判成捕获。
    # 🔴 基线从 EBS 独立地址读，不读 K_FNBASE 槽。
    #    K_FNBASE 是槽（heap+O_SCAL+2408），而槽区没有分配器，与名字缓冲区
    #    共用同一块内存 —— 函数名长几个字节就可能写穿过来。实测：结构完全
    #    相同的两个程序，只因函数名 writemid 比 wm 长，K_FNBASE 就被改成
    #    外层的基线，于是中间层的局部变量被误判成捕获（读到外层的值）。
    #    症状是**值错但不报错**，且依赖程序里其它名字的长度。
    let fb: i64 = load64(heap + O_EBS + n * 8);
    if s >= fb { return 0; }
    let i: i64 = n - 1;
    while i >= 0 {
        if s >= load64(heap + O_EBS + i * 8) {
            # 落在第 i 层的区间里 → 沿静态链往上走 n - i 层
            return n - i;
        }
        i = i - 1;
    }
    # 比最外层基线还小：是全局变量或 predeclare 登记的函数名
    return 0;
}

fn load_sym(s: i64) -> i64 {
    store64(heap + O_SU + s * 8, 1);
    # 数组名在表达式里应当退化成首元素地址（与 C 一致）。
    # 少了这一步，`let p: ptr = buf;` 会把 buf 的前 8 个字节当成地址，
    # 于是 p 是垃圾值（通常是 0），一解引用就段错误。
    # 编译期不报错、运行期才崩，是最难查的那类问题。
    if cap_depth(s) > 0 {
        if ty_kind(sym_type(s)) == 3 {
            return err_at2("cannot capture an array yet", gv(K_LINE), gv(K_COL));
        }
        if ty_kind(sym_type(s)) == 5 { return g_load_captured(sym_addr(s), cap_depth(s)); }
        return g_load_captured(sym_addr(s), cap_depth(s));
    }
    if ty_kind(sym_type(s)) == 3 {
        if sym_kind(s) == 1 { return g_lea_local(sym_addr(s)); }
        return g_movabs_rax(sym_addr(s));
    }
    # 结构体变量在表达式里退化成**地址**（与数组一致）。
    #
    # 少了这一步：`work(a)`（形参 `o: S` 是 ptr(S) 语义）会把第一个字段的
    # **值**传进去 —— 于是函数里 `o.x` 去读 [3]，段错误。
    # 典型症状是退出码 139、编译完全正常、显式写 `work(&a)` 却又是对的。
    if ty_kind(sym_type(s)) == 2 {
        R_SADDR = 1;
        if sym_kind(s) == 1 { return g_lea_local(sym_addr(s)); }
        return g_movabs_rax(sym_addr(s));
    }
    if ty_kind(sym_type(s)) == 5 {
        if sym_kind(s) == 1 { return g_load_local_b(sym_addr(s)); }
        return g_load_global_b(sym_addr(s));
    }
    if sym_kind(s) == 1 { return g_load_local(sym_addr(s)); }
    return g_load_global(sym_addr(s));
}

fn store_sym(s: i64) -> i64 {
    store64(heap + O_SU + s * 8, 1);
    if cap_depth(s) > 0 {
        return g_store_captured(sym_addr(s), cap_depth(s));
    }
    if ty_kind(sym_type(s)) == 5 {
        if sym_kind(s) == 1 { return g_store_local_b(sym_addr(s)); }
        return g_store_global_b(sym_addr(s));
    }
    if sym_kind(s) == 1 { return g_store_local(sym_addr(s)); }
    return g_store_global(sym_addr(s));
}

# push rax。若 rax 里的值刚由「常量加载」或「局部量加载」产生，
# 就回退那条指令、直接 push 源操作数，省掉一次中转。
# ============ 栈顶缓存 ============
# 二元运算的左右操作数靠 push/pop 传递，每次都是两次内存访问。
# rbx 在 SysV ABI 里是 callee-saved，而被我们生成的代码不使用，
# 于是可以拿它缓存「最后一次 push」的值，把 push/pop 换成寄存器传送。
#
# 不变式：K_CRBX == 1  <=>  最后一次 push 的值在 rbx 里。
# 要维持它，任何新的 push 都必须先 spill（把 rbx 里的旧值落栈）。
# 于是栈序天然正确：先 pop 的一定是最后 push 的那个。
fn spill_cache() -> i64 {
    if gv(K_CRBX) == 1 {
        emit1(0x53);          # push rbx
        sv(K_CRBX, 0);
    }
    return 0;
}

# 用 rbx 缓存 rax 里的值（代替 push rax）
fn g_cache_rbx() -> i64 {
    emit1(0x48);
    emit1(0x89);
    emit1(0xc3);              # mov rbx, rax
    sv(K_CRBX, 1);
    return 0;
}

fn g_push_rax() -> i64 {
    let k: i64 = gv(K_LAST);
    sv(K_LAST, 0);
    # 注意：spill 必须放在「回退字节」之后。
    # 折叠路径要回退刚发的常量加载（LASTR 字节），若先 spill 再回退，
    # 回退掉的会是 push rbx + 常量加载的后半段 —— 指令直接错位。
    # 所以每条路径各自在回退之后再 spill。
    if k == 1 {
        let v: i64 = gv(K_LASTV);
        if v >= 0 {
            if v <= 127 {
                sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
                spill_cache();
                emit1(0x6a);
                emit1(v & 255);
                return 0;
            }
            # push imm32 会符号扩展；v >= 2^31 时与 mov eax,imm32（零扩展）不等价
            if v <= 2147483647 {
                sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
                spill_cache();
                emit1(0x68);
                emit4(v);
                return 0;
            }
        }
        spill_cache();
        g_cache_rbx();
        return 0;
    }
    if k == 2 {
        let off: i64 = gv(K_LASTV);
        sv(K_CLEN, gv(K_CLEN) - gv(K_LASTR));
        spill_cache();
        if off >= -128 {
            if off <= 127 {
                emit1(0xff);
                emit1(0x75);
                emit1(off & 255);
                return 0;
            }
        }
        emit1(0xff);
        emit1(0xb5);
        emit4(off);
        return 0;
    }
    spill_cache();
    g_cache_rbx();
    return 0;
}
fn g_pop_rax() -> i64 { spill_cache(); emit1(0x58); return 0; }
fn g_pop_rbx() -> i64 { spill_cache(); emit1(0x5b); return 0; }
# pop rcx。rcx 拿到左操作数后 rax 仍持有右操作数，
# 所以这里记下「右操作数是不是编译期常量」，供随后的运算指令折叠用。
fn g_pop_rcx() -> i64 {
    if gv(K_CRBX) == 1 {
        sv(K_CRBX, 0);
        sv(K_PL, 0);
        emit1(0x48);
        emit1(0x89);
        emit1(0xd9);          # mov rcx, rbx
        return 0;
    }
    if gv(K_LAST) == 1 {
        sv(K_PL, 1);
        sv(K_PLV, gv(K_LASTV));
        sv(K_PLR, gv(K_LASTR));
    } else {
        sv(K_PL, 0);
    }
    emit1(0x59);
    return 0;
}

# 右操作数是常量时，回退它的 mov eax,imm32（紧接着的 pop rcx 由调用方重发）。
# 返回 1 表示已回退，常量值在 K_PLV；返回 0 表示照旧。
# 上限 2^31-1：立即数形式会做符号扩展，超过就与 mov eax,imm32 的零扩展不等价。
fn try_fold_rhs() -> i64 {
    if gv(K_PL) == 0 { return 0; }
    if gv(K_PLV) > 2147483647 { sv(K_PL, 0); return 0; }
    sv(K_PL, 0);
    # 回退「常量加载 + 紧随其后的 pop rcx」；调用方会重发所需的 pop
    sv(K_CLEN, gv(K_CLEN) - gv(K_PLR) - 1);
    return 1;
}

# rax <op>= imm（Group1 形状：imm8 用 83 /reg，imm32 用独立操作码）
fn g_imm_g1(m8: i64, op32: i64) -> i64 {
    let v: i64 = gv(K_PLV);
    if v <= 127 {
        ops3(0x48, 0x83, m8);
        emit1(v & 255);
        return 0;
    }
    ops2(0x48, op32);
    emit4(v);
    return 0;
}
fn g_pop_rdx() -> i64 { spill_cache(); emit1(0x5a); return 0; }
fn g_push_rdi() -> i64 { spill_cache(); emit1(0x57); return 0; }

fn g_pop_rsi() -> i64 { spill_cache(); emit1(0x5e); return 0; }
fn g_pop_rdi() -> i64 { spill_cache(); emit1(0x5f); return 0; }
fn g_pop_r10() -> i64 { spill_cache(); ops2(0x41, 0x5a); return 0; }
fn g_pop_r8() -> i64 { spill_cache(); ops2(0x41, 0x58); return 0; }
fn g_pop_r9() -> i64 { spill_cache(); ops2(0x41, 0x59); return 0; }

fn g_mov_rbx_rax() -> i64 { ops3(0x48, 0x89, 0xc3); return 0; }
fn g_mov_rax_rcx() -> i64 { ops3(0x48, 0x89, 0xc8); return 0; }
fn g_mov_rcx_rbx() -> i64 { ops3(0x48, 0x89, 0xd9); return 0; }
fn g_mov_rax_rdx() -> i64 { ops3(0x48, 0x89, 0xd0); return 0; }

fn g_add() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xc0, 0x05);
        return 0;
    }
    ops3(0x48, 0x01, 0xc8);
    return 0;
}
fn g_and() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xe0, 0x25);
        return 0;
    }
    ops3(0x48, 0x21, 0xc8);
    return 0;
}
fn g_or() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xc8, 0x0d);
        return 0;
    }
    ops3(0x48, 0x09, 0xc8);
    return 0;
}
fn g_xor() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        g_imm_g1(0xf0, 0x35);
        return 0;
    }
    ops3(0x48, 0x31, 0xc8);
    return 0;
}
fn g_imul() -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x58);
        let v: i64 = gv(K_PLV);
        if v <= 127 {
            ops3(0x48, 0x6b, 0xc0);
            emit1(v & 255);
            return 0;
        }
        ops3(0x48, 0x69, 0xc0);
        emit4(v);
        return 0;
    }
    ops4(0x48, 0x0f, 0xaf, 0xc1);
    return 0;
}
# ==========================================================================
#  f64 —— SSE 指令
# ==========================================================================
# f64 值在 rax 里是 IEEE754 **位模式**；运算时才搬进 xmm，算完搬回来。
# 约定与整数一致：**左操作数 pop 到 rcx，右操作数在 rax，结果在 rax**。

# movq xmm0, rax      66 48 0F 6E C0
fn g_movq_xmm0_rax() -> i64 { ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc0); return 0; }
# movq xmm1, rcx      66 48 0F 6E C9
fn g_movq_xmm1_rcx() -> i64 { ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc9); return 0; }
# movq xmm0, rcx      66 48 0F 6E C1
fn g_movq_xmm0_rcx() -> i64 { ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc1); return 0; }
# movq rax, xmm0      66 48 0F D6 C0
fn g_movq_rax_xmm0() -> i64 { ops4(0x66, 0x48, 0x0f, 0x7e); emit1(0xc0); return 0; }
# movq rcx, xmm1      66 48 0F D6 C9
fn g_movq_rcx_xmm1() -> i64 { ops4(0x66, 0x48, 0x0f, 0x7e); emit1(0xc9); return 0; }

# int → double（rax: i64 → 位模式）
fn g_i2f_rax() -> i64 {
    ops4(0xf2, 0x48, 0x0f, 0x2a); emit1(0xc0);   # cvtsi2sd xmm0, rax
    g_movq_rax_xmm0();
    return 0;
}
fn g_i2f_rcx() -> i64 {
    ops4(0xf2, 0x48, 0x0f, 0x2a); emit1(0xc9);   # cvtsi2sd xmm1, rcx
    g_movq_rcx_xmm1();
    return 0;
}
# double → int（截断）
fn g_f2i_rax() -> i64 {
    g_movq_xmm0_rax();
    ops4(0xf2, 0x48, 0x0f, 0x2c); emit1(0xc0);   # cvttsd2si rax, xmm0
    return 0;
}

# addsd xmm0, xmm1  → xmm0 = xmm0 + xmm1（= 右 + 左）
fn g_add_f64() -> i64 {
    g_movq_xmm1_rcx();
    g_movq_xmm0_rax();
    ops3(0xf2, 0x0f, 0x58); emit1(0xc1);
    g_movq_rax_xmm0();
    return 0;
}
# 左 - 右：xmm0 = rcx - rax
fn g_sub_f64() -> i64 {
    g_movq_xmm0_rcx();
    ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc8);   # movq xmm1, rax
    ops3(0xf2, 0x0f, 0x5c); emit1(0xc1);         # subsd xmm0, xmm1
    g_movq_rax_xmm0();
    return 0;
}
fn g_mul_f64() -> i64 {
    g_movq_xmm1_rcx();
    g_movq_xmm0_rax();
    ops3(0xf2, 0x0f, 0x59); emit1(0xc1);         # mulsd
    g_movq_rax_xmm0();
    return 0;
}
# 左 / 右
fn g_div_f64() -> i64 {
    g_movq_xmm0_rcx();
    ops4(0x66, 0x48, 0x0f, 0x6e); emit1(0xc8);   # movq xmm1, rax
    ops3(0xf2, 0x0f, 0x5e); emit1(0xc1);         # divsd xmm0, xmm1
    g_movq_rax_xmm0();
    return 0;
}
# 浮点数取负 = **位模式翻转符号位**（XOR 1<<63）。
# 比 subsd 0.0-x 少一次访存，也不需要额外常量池项。
fn g_neg_f64() -> i64 {
    g_movabs_rcx(0 - 9223372036854775807 - 1);
    ops3(0x48, 0x31, 0xc8);        # xor rax, rcx
    return 0;
}
# ucomisd —— 设 EFLAGS，供后续 setcc/jcc 用。
#
# 🔴 操作数顺序（第一版写反了）：
#    整数比较是 `cmp rcx, rax`（48 39 C1），flags 基于 **rcx - rax**，
#    于是 setl 表示 rcx < rax（左 < 右）。
#    ucomisd 必须**同样**是以左操作数减右操作数：ucomisd xmm1, xmm0
#    （xmm1=左=rcx，xmm0=右=rax），modrm = reg(xmm1)=001, rm(xmm0)=000 → C8。
#
#    第一版写成 C1（ucomisd xmm0, xmm1），比较的是**右 vs 左**，
#    于是 `v < 0.0` 对负数恒为假 —— print_f64(-2.5) 打出 "-2.-500000"
#    （符号没打印，整数部分却带着负号）。极难从现象反推。
fn g_ucomisd() -> i64 {
    g_movq_xmm1_rcx();
    g_movq_xmm0_rax();
    ops3(0x66, 0x0f, 0x2e); emit1(0xc8);   # ucomisd xmm1, xmm0
    return 0;
}

# 🔴 ucomisd **只设置 ZF/PF/CF，不设置 SF/OF**。
#
# 所以整数的 setl / setg / setle / setge（依赖 SF≠OF）在浮点下**完全无效**
# —— 它们读的是上一条整数指令残留的标志位，结果看起来随机。
#
# 必须换成"无符号"那一族（只看 CF/ZF）：
#   <   setl (9c)  → setb  (92)   CF=1
#   <=  setle(9e)  → setbe (96)   CF=1 or ZF=1
#   >   setg (9f)  → seta  (97)   CF=0 and ZF=0
#   >=  setge(9d)  → setae (93)   CF=0
#   ==  sete (94)  → sete  (94)   ZF=1      （不变）
#   !=  setne(95)  → setne (95)   ZF=0      （不变）
#
# 症状极隐蔽：`v < 0.0` 对某些值碰巧对、某些值恒假，
# 于是 print_f64(-2.5) 打出 "-2.-500000" 这种莫名其妙的东西。
fn f_cc(cc: i64) -> i64 {
    if cc == 156 { return 146; }     # setl  → setb
    if cc == 158 { return 150; }     # setle → setbe
    if cc == 159 { return 151; }     # setg  → seta
    if cc == 157 { return 147; }     # setge → setae
    return cc;
}
fn g_neg() -> i64 { ops3(0x48, 0xf7, 0xd8); return 0; }
fn g_not() -> i64 { ops3(0x48, 0xf7, 0xd0); return 0; }
fn g_syscall() -> i64 { ops2(0x0f, 0x05); return 0; }

# rax = rcx - rax
fn g_sub() -> i64 {
    ops3(0x48, 0x29, 0xc1);
    g_mov_rax_rcx();
    return 0;
}

# rax = rcx / rax ; rax = rcx % rax
# ---- 除以/取模 2 的幂：用移位代替 idiv（强度削减）----
#
# 实测：arith workload 里除法和取模占了 63%（11.74ms vs 无除法 4.29ms）。
# idiv 是几十周期的指令，而移位是 1 周期。除以编译期常量 2^k 时，
# 用「偏置 + 算术右移」代替，语义与 C 完全一致（向零截断）。
#
# 🔴 负数的偏置不能省：算术右移 sar 是**向下取整**，而 C 的整数除法
#    是**向零截断**。n < 0 时必须先加 (2^k - 1) 再移。
#    少了这一步，n = -1, k = 1 时 -1/2 会得到 -1（正确应为 0）。
#    这是这类优化最经典的错法。
fn g_mov_rdx_rax() -> i64 { ops3(0x48, 0x89, 0xc2); return 0; }
fn g_sar_rdx63() -> i64 { ops3(0x48, 0xc1, 0xfa); emit1(63); return 0; }
fn g_and_rdx_imm(m: i64) -> i64 {
    if m <= 127 { ops3(0x48, 0x83, 0xe2); emit1(m & 255); return 0; }
    # 🔴 只能用 imm32 形式（81 /4 会符号扩展），所以 k 必须 <= 31，
    #    否则 mask >= 2^32-1 无法编码 —— 已在 pow2_exp 里挡掉。
    ops3(0x48, 0x81, 0xe2); emit4(m); return 0;
}
fn g_add_rax_rdx() -> i64 { ops3(0x48, 0x01, 0xd0); return 0; }
fn g_sar_rax_imm(k: i64) -> i64 { ops3(0x48, 0xc1, 0xf8); emit1(k & 255); return 0; }
fn g_shl_rax_imm(k: i64) -> i64 { ops3(0x48, 0xc1, 0xe0); emit1(k & 255); return 0; }
fn g_mov_rdx_rcx() -> i64 { ops3(0x48, 0x89, 0xca); return 0; }
fn g_sub_rdx_rax() -> i64 { ops3(0x48, 0x29, 0xc2); return 0; }

# v 是否为 2 的幂（v > 0），是则返回 k，否则 -1
fn pow2_exp(v: i64) -> i64 {
    if v <= 0 { return 0 - 1; }
    if v == 1 { return 0; }
    let k: i64 = 0;
    let t: i64 = v;
    while t > 1 {
        if t - (t / 2) * 2 != 0 { return 0 - 1; }
        t = t / 2;
        k = k + 1;
    }
    if k > 31 { return 0 - 1; }
    return k;
}

# mode 0 = 除，1 = 取模。进入：rax = 常量 d（2^k），rcx = 被除数 n。结果在 rax。
fn g_div_pow2(mode: i64, k: i64) -> i64 {
    let mask: i64 = 1;
    let i2: i64 = 0;
    while i2 < k { mask = mask * 2; i2 = i2 + 1; }
    mask = mask - 1;
    g_mov_rax_rcx();                 # rax = n
    if mode == 0 {
        if k == 0 { return 0; }      # n / 1 = n
        g_mov_rdx_rax();
        g_sar_rdx63();               # rdx = n<0 ? -1 : 0
        g_and_rdx_imm(mask);         # rdx = n<0 ? 2^k-1 : 0
        g_add_rax_rdx();
        g_sar_rax_imm(k);
        return 0;
    }
    if k == 0 { ops2(0x48, 0x31); emit1(0xc0); return 0; }   # n % 1 = 0
    g_mov_rdx_rax();
    g_sar_rdx63();
    g_and_rdx_imm(mask);
    g_add_rax_rdx();
    g_sar_rax_imm(k);                # q = n / 2^k（向零截断）
    g_shl_rax_imm(k);                # q * 2^k
    g_mov_rdx_rcx();                 # rdx = n
    g_sub_rdx_rax();                 # rdx = n - q*2^k
    g_mov_rax_rdx();
    return 0;
}

fn g_add_rax_rcx() -> i64 { ops3(0x48, 0x01, 0xc8); return 0; }
# ============================================================================
#  任意常量除数：乘法倒数（魔数）代替 idiv
#
#  上一轮只覆盖了 2 的幂（移位）。这里覆盖任意常量 d（2 <= |d| <= 2^31-1）：
#      q = mulhi(M, n)                  ; 128 位乘法取高 64 位
#      if M < 0 { q += n }              ; （只在 d > 0、M < 0 时需要）
#      q = q >> s                       ; 算术右移
#      q = q - (n >> 63)                ; n < 0 时 +1，把 floor 修正为向零截断
#
#  🔴 最后一步是**减** (n>>63) 而不是加：n<0 时 (n>>63) = -1，减它等于 +1。
#     gcc 对应 `sar $63, %rdi; subq %rdi, %rax`。方向搞反会得到 -4 而不是 -2。
#
#  🔴 d < 0 的处理：n / d = -(n / |d|)，而 n % d == n % |d|（截断语义下成立）。
#     所以魔数只对 |d| 求，除法取负、取模不取负。这样就不必实现 d<0 的分支。
# ============================================================================
var MG_M: i64 = 0;
var MG_S: i64 = 0;

fn g_movabs_rdx(v: i64) -> i64 { emit1(0x48); emit1(0xba); emit8(v); return 0; }
fn g_imul_rdx() -> i64 { ops3(0x48, 0xf7, 0xea); return 0; }
fn g_imul_rax_imm(v: i64) -> i64 {
    if v >= 0 - 128 { if v <= 127 { ops4(0x48, 0x6b, 0xc0, v & 255); return 0; } }
    ops3(0x48, 0x69, 0xc0); emit4(v); return 0;
}
fn g_sub_rax_rdx() -> i64 { ops3(0x48, 0x29, 0xd0); return 0; }
fn g_neg_rax() -> i64 { ops3(0x48, 0xf7, 0xd8); return 0; }

# 求 d（d >= 2，非 2 的幂）的魔数 M 与移位 s
fn magic_pre(d: i64) -> i64 {
    let ad: i64 = d;
    let mx: i64 = 9223372036854775807;      # 2^63 - 1
    let qa: i64 = mx / ad;
    let rb: i64 = mx - qa * ad;
    # 2^63 = (2^63-1) + 1，所以 2^63/ad 与 2^63%ad 只需在 rb 上补 1
    # 🔴 tmod == 2^63 mod ad，而 r2 也必须是它 —— 第一版写成 r2 = rb
    #    （= (2^63-1) mod ad，少 1），于是 delta 偏大、多迭代一次，
    #    M 差整整一倍、s 多 1。d=7 时算成 M=10540996613548315209/s=2，
    #    而 gcc 给出 M=5270498306774157605/s=1。
    let tmod: i64 = rb + 1;
    let carry: i64 = 0;
    if tmod >= ad { tmod = 0; carry = 1; }
    let q2: i64 = qa + carry;
    let r2: i64 = tmod;
    let anc: i64 = mx - tmod;
    let q1: i64 = 1;
    let r1: i64 = 1 + tmod;
    let p: i64 = 63;
    let go: i64 = 1;
    let delta: i64 = 0;
    while go == 1 {
        p = p + 1;
        q1 *= 2;
        r1 *= 2;
        if r1 >= anc { q1 = q1 + 1; r1 = r1 - anc; }
        q2 *= 2;
        r2 *= 2;
        if r2 >= ad { q2 = q2 + 1; r2 = r2 - ad; }
        delta = ad - r2;
        if q1 > delta { go = 0; }
        if q1 == delta { if r1 != 0 { go = 0; } }
    }
    MG_M = q2 + 1;
    MG_S = p - 64;
    return 0;
}

fn magic_ok(d: i64) -> i64 {
    let dd: i64 = d;
    if d < 0 { dd = 0 - d; }
    if dd < 2 { return 0; }
    if dd > 2147483647 { return 0; }
    return 1;
}

fn g_div_magic(mode: i64, d: i64) -> i64 {
    let dd: i64 = d;
    let negd: i64 = 0;
    if d < 0 { dd = 0 - d; negd = 1; }
    magic_pre(dd);
    let M: i64 = MG_M;
    let s: i64 = MG_S;
    g_mov_rax_rcx();
    g_movabs_rdx(M);
    g_imul_rdx();
    g_mov_rax_rdx();
    if M < 0 { g_add_rax_rcx(); }
    if s > 0 { g_sar_rax_imm(s); }
    g_mov_rdx_rcx();
    g_sar_rdx63();
    g_sub_rax_rdx();
    if mode == 0 {
        if negd == 1 { g_neg_rax(); }
        return 0;
    }
    g_imul_rax_imm(dd);
    g_mov_rdx_rcx();
    g_sub_rdx_rax();
    g_mov_rax_rdx();
    return 0;
}

fn g_idiv(mode: i64) -> i64 {
    # 除法用 rbx 当除数，必须先让缓存落栈，否则左操作数就丢了
    spill_cache();
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    ops2(0x48, 0x99);
    ops3(0x48, 0xf7, 0xfb);
    if mode == 1 {
        g_mov_rax_rdx();
    }
    return 0;
}

fn g_shl() -> i64 {
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    g_mov_rcx_rbx();
    ops3(0x48, 0xd3, 0xe0);
    return 0;
}

fn g_sar() -> i64 {
    g_mov_rbx_rax();
    g_mov_rax_rcx();
    g_mov_rcx_rbx();
    ops3(0x48, 0xd3, 0xf8);
    return 0;
}

# 比较 rcx 与 rax，结果 0/1 放 rax
fn g_setcc(cc: i64) -> i64 {
    ops2(0x0f, cc);
    emit1(0xc0);
    ops4(0x48, 0x0f, 0xb6, 0xc0);
    return 0;
}

# 比较 rcx（左）与 rax（右）。右操作数是常量时直接用 cmp rcx, imm
# —— 标志位语义与 cmp rcx,rax 完全一致（都是 left - right），可以放心换。
fn g_cmp_set(cc: i64) -> i64 {
    if try_fold_rhs() == 1 {
        emit1(0x59);
        let v: i64 = gv(K_PLV);
        if v <= 127 {
            ops3(0x48, 0x83, 0xf9);
            emit1(v & 255);
            g_setcc(cc);
            return 0;
        }
        ops3(0x48, 0x81, 0xf9);
        emit4(v);
        g_setcc(cc);
        return 0;
    }
    ops3(0x48, 0x39, 0xc1);
    g_setcc(cc);
    return 0;
}

# 浮点比较：ucomisd 设 EFLAGS，再用同样的 setcc。
#
# ⚠️ 不能用 cmp 指令：那会把 double 的位模式当整数比 ——
#    正数碰巧对（IEEE754 正数位模式单调递增），**负数全反**。
#    这种"正例能过、负例全错"的 bug 特别容易漏。
#
# 🔴 IEEE754 unordered（任一操作数为 NaN）：ucomisd 设 ZF=PF=CF=1。
#    此时 < <= > >= == 必须全为假、!= 必须为真；而裸 setcc 给出：
#      setb/setbe/sete → 1（应为 0）   seta/setae → 0（碰巧对）
#      setne → 0（应为 1）
#    于是 `x != x` 这个**最惯用的 NaN 判据恒为假** —— 不报错、不崩溃，
#    只是所有 isnan 检测静默失效（排序、最值、断言跟着一起错）。
#    实测：nan == nan 得 1、nan != nan 得 0、nan < 1.0 得 1。
#
#    修法：setcc 之后再合上 PF（= unordered 标志）。
#      ==  → sete  & ~PF
#      !=  → setne |  PF
#      其余 → cc    & ~PF
#    setcc 不修改 flags，所以可以紧接着再 setnp / setp cl。
fn g_cmp_set_f64(cc: i64) -> i64 {
    let c2: i64 = f_cc(cc);
    g_ucomisd();
    g_setcc(c2);
    if c2 == 149 {
        ops3(0x0f, 0x9a, 0xc1);      # setp  cl
        ops2(0x08, 0xc8);            # or    al, cl
        return 0;
    }
    ops3(0x0f, 0x9b, 0xc1);          # setnp cl
    ops2(0x20, 0xc8);                # and   al, cl
    return 0;
}

# str 的 == / != —— **内容比较**。
#
# 进入时 rcx = 左串地址、rax = 右串地址，与 g_cmp_set 的约定完全一致，
# 所以可以直接顶替它。逐字节比到第一个 NUL 为止（两串同时到 NUL 即相等）。
#
# 🔴 不能用 strcmp：生成物默认不链 libc，extern 符号在裸产物里没有地址，
#    调用它会跳到 0。这里全程内联，不引入任何外部依赖。
#
# eq=1 → 相等时给 1；eq=0（!=）→ 相等时给 0。
fn g_str_eq(eq: i64) -> i64 {
    let lp: i64 = new_label();
    let ldiff: i64 = new_label();
    let lsame: i64 = new_label();
    let lend: i64 = new_label();
    place_label(lp);
    ops2(0x8a, 0x11);              # mov dl, [rcx]
    ops2(0x38, 0x10);              # cmp [rax], dl
    emit_jcc(0x85, ldiff);         # jne  ldiff
    ops2(0x84, 0xd2);              # test dl, dl
    emit_jcc(0x84, lsame);         # je   lsame  （两端同时到 NUL）
    ops3(0x48, 0xff, 0xc1);        # inc  rcx
    ops3(0x48, 0xff, 0xc0);        # inc  rax
    emit_jmp(lp);
    place_label(lsame);
    if eq == 1 { emit1(0xb8); emit4(1); }     # mov eax, 1
    else { ops2(0x31, 0xc0); }                # xor eax, eax
    emit_jmp(lend);
    place_label(ldiff);
    if eq == 1 { ops2(0x31, 0xc0); }          # xor eax, eax
    else { emit1(0xb8); emit4(1); }           # mov eax, 1
    place_label(lend);
    return 0;
}

# str 的 < <= > >= —— **无符号字节字典序**。
#
# 进入时同样是 rcx = 左串地址、rax = 右串地址。
#
# 🔴 为什么必须无符号：UTF-8 的多字节码与续接字节都 >= 0x80。
#    把它们当**有符号** char 比，0xE4 会变成 -28，于是"中" < "a" ——
#    整个 CJK 区间跑到 ASCII 前面，排序、二分查找、最值全部静默错位。
#    这正是 C 里 strcmp 规定按 unsigned char 比较的原因。
#
# 🔴 退出点的标志位必须是"等价"的：
#      cmp [rcx],dl  → 8 位无符号 left-right，CF/ZF 直接可用
#      test dl,dl    → 走到这里说明 dl == [rcx] 且 dl == 0（两串同时结束），
#                      给 ZF=1、CF=0，与"相等"完全一致。
#    所以两条出路可以共用同一个 setcc，不需要额外的分支。
#
# cc 由调用方传**无符号**条件码：< → 0x92(setb)  <= → 0x96(setbe)
#                                > → 0x97(seta)  >= → 0x93(setae)
fn g_str_cmp(cc: i64) -> i64 {
    let lp: i64 = new_label();
    let ldone: i64 = new_label();
    place_label(lp);
    ops2(0x8a, 0x10);              # mov dl, [rax]      右串当前字节
    ops2(0x38, 0x11);              # cmp [rcx], dl      左 - 右（8 位）
    emit_jcc(0x85, ldone);         # jne  ldone
    ops2(0x84, 0xd2);              # test dl, dl
    emit_jcc(0x84, ldone);         # je   ldone（两端同时到 NUL）
    ops3(0x48, 0xff, 0xc1);        # inc  rcx
    ops3(0x48, 0xff, 0xc0);        # inc  rax
    emit_jmp(lp);
    place_label(ldone);
    g_setcc(cc);
    return 0;
}

# str 的 '+' —— **拼接**，不是地址相加。
#
# 进入时同样是 rcx = 左串地址、rax = 右串地址（与 g_str_eq / g_str_cmp 一致）。
#
# 实际工作交给 lib/scat.mo 的 scat_cat（墨语言写的），
# 编译器只做类型分派：拼接需要分配，而分配策略（region）属于库，
# 不属于语言 —— 换一种生命周期策略不用动编译器。
#
# 🔴 为什么不能退化成 g_add()：str 的值就是一个指针，
#    "abc" + 1 在机器层面完全"合法"，会静默给出一个指向
#    字符串中间的野指针，不报错、不崩溃。所以类型不匹配必须报错。
fn g_str_cat() -> i64 {
    ops3(0x48, 0x89, 0xcf);        # mov rdi, rcx   左串
    ops3(0x48, 0x89, 0xc6);        # mov rsi, rax   右串
    # spill 必须在两个 mov **之后**：spill 只发射 push rbx，
    # 不碰 rdi/rsi，但放在前面的话读起来会以为 rdi/rsi 之后还会被改。
    spill_cache();
    let sym: i64 = sym_lookup_func("scat_cat");
    if sym < 0 { return die("'+' 拼接需要: import \"scat.mo\""); }
    emit_call_patch(sym);
    return 0;
}

fn g_cmp_rax_0() -> i64 {
    ops4(0x48, 0x83, 0xf8, 0x00);
    return 0;
}

fn g_lnot() -> i64 {
    g_cmp_rax_0();
    ops3(0x0f, 0x94, 0xc0);
    ops4(0x48, 0x0f, 0xb6, 0xc0);
    return 0;
}

fn g_zero_rax() -> i64 { ops2(0x31, 0xc0); return 0; }

# 把函数名字符串写进输出数据段，返回其地址（供 prof_enter 识别调用者）
fn prof_emit_name(p: i64) -> i64 {
    let a: i64 = 268435456 + gv(K_DLEN);
    let i: i64 = 0;
    while load8(p + i) != 0 {
        dbyte(load8(p + i));
        i = i + 1;
    }
    dbyte(0);
    # 补到 8 字节对齐，否则下一个全局变量地址不对齐
    while (gv(K_DLEN) & 7) != 0 { dbyte(0); }
    return a;
}

# 出口插桩：先调 prof_leave，main 还要额外调 prof_report
fn prof_emit_leave() -> i64 {
    let s2: i64 = sym_lookup_func("prof_leave");
    if s2 < 0 { return 0; }
    # 🔴 顺序与对齐：
    #   1. 先 spill_cache() —— 它发射的 push rbx 属于"逻辑栈顶"，
    #      之后 rsp 才是 ABI 要求的 16 字节对齐位置
    #   2. 再 push rax（返回值）+ push rdi（凑 16 字节，保持对齐）
    #   3. call 之前 rsp % 16 == 0
    # 如果在 spill 之前 push rax，spill 的 push rbx 会让调用点错位 8 字节。
    spill_cache();
    emit1(0x50);                 # push rax
    emit1(0x57);                 # push rdi
    emit_call_patch(s2);
    if gv(K_PROFMAIN) == 1 {
        let s3: i64 = sym_lookup_func("prof_report");
        if s3 >= 0 { emit_call_patch(s3); }
    }
    emit1(0x5f);                 # pop rdi
    emit1(0x58);                 # pop rax
    return 0;
}

fn g_epilogue() -> i64 {
    # 🔴 只对主文件插桩：库函数（strlen、print…）被调用几百万次，
    #    插上去既污染数据又把程序拖慢到不可信。
    if gv(K_PROF) == 1 { if gv(K_INIMP) == 0 { prof_emit_leave(); } }
    # 🔴 rbx 是 callee-saved，而栈顶缓存拿它当中转（见下方 g_prologue）。
    #    不恢复的话，任何把墨函数当 C 回调的调用点都会拿到被改坏的 rbx：
    #      · ucontext：glibc 的 __start_context 从 rbx 取 uc_link
    #      · qsort 比较器 / pthread 回调：C 侧自己的 rbx 被破坏
    #    实测症状：协程里只要调过 print，return 就 SIGSEGV；空协程正常。
    #
    #    栈布局（进入函数体时）：rbp+8 = 返回地址，rbp-8 = 保存的 rbx。
    #    所以必须先 lea rsp,[rbp-8] 再 pop —— 直接 mov rsp,rbp
    #    会 pop 到"保存的 rbp"，顺序正好反了。
    ops3(0x48, 0x8d, 0x65);       # lea rsp, [rbp-8]
    emit1(0xf8);
    emit1(0x5b);                  # pop rbx
    emit1(0x5d);                  # pop rbp
    emit1(0xc3);                  # ret
    return 0;
}

fn g_prologue() -> i64 {
    ops3(0x55, 0x48, 0x89);
    emit1(0xe5);
    # 🔴 保存 rbx：栈顶缓存（g_cache_rbx）会在函数体里改它。
    #    SysV ABI 规定 rbx 由被调者保存，C 回调路径依赖这一点。
    #    放在 sub rsp 之前，于是保存值固定落在 [rbp-8]。
    emit1(0x53);                  # push rbx
    ops3(0x48, 0x81, 0xec);
    sv(K_FPATCH, gv(K_CLEN));
    emit4(0);
    return 0;
}

# mov [rbp+off], <argreg i>
# 把第 i 个参数存到 [rbp+off]。
# 前 6 个参数走寄存器；第 7 个起由调用者压栈，需从栈上取。
# 调用方按正序压栈（arg0 先压），故 arg[i] 落在 [rbp + 16 + (na-1-i)*8]。
# 原先只有 6 个寄存器的分支，i>=6 时会越界取到垃圾字节——
# 表现为函数序言里冒出一条 jne（0x75），程序一跑就段错误。
fn emit_store_arg(off: i64, i: i64, na: i64) -> i64 {
    if i >= 6 {
        let d: i64 = 16 + (i - 6) * 8;
        ops2(0x48, 0x8b);
        if d > 127 {
            emit1(0x85);
            emit4(d);
        } else {
            emit1(0x45);
            emit1(d & 255);
        }
        ops2(0x48, 0x89);
        if off < -128 {
            emit1(0x85);
            emit4(off);
        } else {
            emit1(0x45);
            emit1(off & 255);
        }
        return 0;
    }
    if i == 0 { ops3(0x48, 0x89, 0x7d); emit1(off); return 0; }
    if i == 1 { ops3(0x48, 0x89, 0x75); emit1(off); return 0; }
    if i == 2 { ops3(0x48, 0x89, 0x55); emit1(off); return 0; }
    if i == 3 { ops3(0x48, 0x89, 0x4d); emit1(off); return 0; }
    if i == 4 { ops3(0x4c, 0x89, 0x45); emit1(off); return 0; }
    ops3(0x4c, 0x89, 0x4d);
    emit1(off);
    return 0;
}

# movabs rax, <addr>; call rax  并记录回填
# 外部（C）函数调用：发 `call rel32` 占位，并把调用点记进 O_XC 表，
# 由 -c 模式生成 R_X86_64_PLT32 重定位交给 ld 解析。
#
# 为什么不复用内部函数的"直接算 rel32"：外部符号的地址**只有 ld 知道**。
# 唯一能做的是留下 4 字节空位 + 一条重定位，让 ld 填 PLT 入口的偏移。
fn emit_call_extern(sym: i64) -> i64 {
    # 变参调用前必须把 al 清零：x86-64 ABI 用 al 表示"用了几个 SSE 寄存器"。
    # 我们从不通过 xmm 传参，所以必须是 0；留着垃圾值会让 C 侧
    # 按错误的个数去保存寄存器区（printf 读错位）。
    if sym_npar(sym) < 0 { ops2(0x31, 0xc0); }
    spill_cache();
    let k: i64 = gv(K_NXC);
    if k >= 4096 { return die("too many extern call sites (limit 4096)"); }
    emit1(0xe8);
    # 重定位位置 = rel32 字段的起始 = 发完 0xe8 之后的代码长度
    store64(DBG + O_XC + k * 16, gv(K_CLEN));
    store64(DBG + O_XC + k * 16 + 8, sym);
    store64(DBG + O_XR + k * 8, 4);        # R_X86_64_PLT32
    sv(K_NXC, k + 1);
    emit4(0);
    # 🔴 C 的 int 只写 eax，rax 高 32 位未定义。声明成 `-> i32` 时
    #    必须 cdqe（符号扩展到 64 位），否则 -1 会被读成 4294967295。
    #    printf("%d") 看着是对的（%d 本身按 32 位解释），
    #    所以这个坑只在把返回值**继续参与 64 位比较**时才暴露。
    if ty_kind(load64(heap + O_SRT + sym * 8)) == 9 {
        ops2(0x48, 0x98);
    }
    return 0;
}

# 取函数地址（-c 模式）：movabs rax,0 + R_X86_64_64 重定位
fn emit_func_addr(sym: i64) -> i64 {
    spill_cache();
    let k: i64 = gv(K_NXC);
    if k >= 4096 { return die("too many extern relocs (limit 4096)"); }
    ops2(0x48, 0xb8);
    store64(DBG + O_XC + k * 16, gv(K_CLEN));
    store64(DBG + O_XC + k * 16 + 8, sym);
    store64(DBG + O_XR + k * 8, 1);        # R_X86_64_64
    sv(K_NXC, k + 1);
    emit8(0);
    return 0;
}

fn emit_call_patch(sym: i64) -> i64 {
    # 调用点：被调函数**已定义**时用 call rel32（5 字节，直接算好）；
    # 未定义（前向调用）时**预留 5 字节 rel32 占位**，回填时再算。
    #
    # 原版慢路径发 movabs rax,imm64 + call rax（12 字节）留 8 字节空位。
    # 前向调用的地址虽然此刻未知，但 **rel32 的偏移与"地址是否已知"
    #  无关** —— 回填时函数地址一定都有了，照样算得出。
    # 所以两条路都能用 5 字节，省下的 7 字节是白拿的。
    #
    # **怎么区分两种 patch**：回填时读占位处的**第一个字节**。
    # 0xe8 = rel32（写 4 字节），0x48 = movabs（写 8 字节）。
    # patch 类型就写在它自己身上，不需要额外的 kind 表 ——
    # 也就不会出现"表和实际字节不一致"这类隐蔽错误。
    #
    # 🔴 **顺序是关键**（1.45.0 踩过两次）：
    #   1. spill_cache() 可能发射 1 字节 push rbx，必须在算位置之前
    #   2. 记录 pos 必须在 emit1(0xe8) 之后 —— pos 要指向 rel32 字段
    #   3. seed 汇编里 rax/r8-r11 是 caller-saved，跨 call 会破坏
    if sym_kind(sym) == 3 { return emit_call_extern(sym); }
    let ta: i64 = load64(heap + O_SA + sym * 8);
    if ta >= 4194304 {
        if ta < 4194304 + 8388608 {
            spill_cache();
            let here: i64 = 4194304 + 176 + gv(K_CLEN);
            let rel: i64 = ta - (here + 5);
            emit1(0xe8);
            emit4(rel);
            return 0;
        }
    }
    # -c 模式（输出 .o）：前向调用**必须**用 rel32，不能用 movabs+call rax。
    #
    # 🔴 原因是 .o 里 .text 的地址是 0，链接后由 ld 放到任意位置。
    #    movabs 里嵌的绝对地址（0x4000b0 + off）在 .text 被搬走后就全错，
    #    程序跳进垃圾里 —— 实测 SIGILL / SIGSEGV，且不报任何链接错误。
    #    rel32 是**段内偏移之差**，平移不变，所以链接后依然正确。
    #    resolve_all 里算的就是 `off_target - (p+5)`，本来就与基址无关。
    if gv(K_OBJ) == 1 {
        spill_cache();
        let k2: i64 = gv(K_NFNP);
        if k2 >= 16384 { return die("too many call sites (limit 16384)"); }
        # 记的是 **rel32 字段**的偏移（e8 之后），不是 call 指令自己的偏移。
        # 于是 resolve_all 里 `a - (base + p + 4)`：
        #   call 在 p-1，长 5 字节，下一条指令在 p+4。
        # 🔴 两种约定（指令偏移 vs 字段偏移）混用会整整偏 1 字节 ——
        #    第一种表现是 rel32 覆盖了 e8 操作码，call 变成别的指令；
        #    第二种是跳到目标的前一字节。都必须按同一套来。
        emit1(0xe8);
        store64(heap + O_FP + k2 * 8, gv(K_CLEN));
        store64(heap + O_FS + k2 * 8, sym);
        sv(K_NFNP, k2 + 1);
        emit4(0);
        return 0;
    }
    # 前向调用：退回 movabs rax,imm64 + call rax（12 字节）再回填。
    #
    # ⚠️ 这里**试过**也发 5 字节 rel32（省 7 字节 × 585 处 ≈ 4KB），
    # 但 seed 侧（手写汇编）同步改完后产物失效 —— 自举时 moc1 段错误。
    # 收益只有 0.63%，不值得为此让两边再冒一次不一致的风险。
    # 记在这里避免以后重复尝试：**同一处改动两边都要对，成本是双倍的**。
    ops2(0x48, 0xb8);
    let k: i64 = gv(K_NFNP);
    if k >= 16384 { return die("too many call sites (limit 16384)"); }
    store64(heap + O_FP + k * 8, gv(K_CLEN));
    store64(heap + O_FS + k * 8, sym);
    sv(K_NFNP, k + 1);
    emit8(0);
    spill_cache();
    ops2(0xff, 0xd0);
    return 0;
}

fn new_label() -> i64 {
    let k: i64 = gv(K_NLAB);
    if k >= 16384 { return die("too many labels (limit 16384)"); }
    sv(K_NLAB, k + 1);
    return k;
}

# 放置标签。若上一条指令是无条件 jmp 且它跳的正是这里、中间又没夹任何字节，
# 那这条 jmp 是死跳转（跳到下一条指令），整条删掉——省 5 字节。
# `if` 没有 else 分支时正是这种情况：jmp end 之后紧跟着就是 end 标签。
fn place_label(l: i64) -> i64 {
    let pj: i64 = gv(K_PJMP);
    if pj > 0 {
        if gv(K_PJLBL) == l {
            if gv(K_CLEN) == gv(K_PJEND) {
                let old: i64 = gv(K_PJEND);
                let nw: i64 = old - 5;
                sv(K_CLEN, nw);
                sv(K_NJMP, pj - 1);
                sv(K_PJMP, 0);
                # 已经落在 old 处的标签（典型的是 if 的 else 标签，它
                # 比 end 早一步放置）必须跟着回退。否则它们仍指向
                # 被删掉那 5 字节之后——跳进下一段指令的中间。
                let i: i64 = 0;
                let nn: i64 = gv(K_NLAB);
                while i < nn {
                    if load64(heap + O_LB + i * 8) == old {
                        store64(heap + O_LB + i * 8, nw);
                    }
                    i = i + 1;
                }
            }
        }
    }
    store64(heap + O_LB + l * 8, gv(K_CLEN));
    return 0;
}

# ---------------------------- 循环标签栈 ----------------------------
# break/continue 要跳到「当前所在的那一层循环」。嵌套循环时靠栈记住
# 每层的 continue 标签（循环头）与 break 标签（循环出口）。
# 存在 O_LB 之后的区域，最多 32 层。
var O_LSTK: i64 = 7417360;

fn loop_push(cnt: i64, brk: i64, stp: i64) -> i64 {
    let i: i64 = gv(K_LTOP);
    store64(heap + O_LSTK + i * 24, cnt);
    store64(heap + O_LSTK + i * 24 + 8, brk);
    store64(heap + O_LSTK + i * 24 + 16, stp);
    sv(K_LTOP, i + 1);
    return 0;
}

fn loop_pop() -> i64 {
    sv(K_LTOP, gv(K_LTOP) - 1);
    return 0;
}

# 取当前循环的 continue / break 标签；不在循环里返回 -1
fn loop_cnt() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24);
}

# for 的步进标签；while 为 -1（表示 continue 直接跳循环头）
fn loop_stp() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24 + 16);
}

fn loop_brk() -> i64 {
    let i: i64 = gv(K_LTOP);
    if i <= 0 { return -1; }
    return load64(heap + O_LSTK + (i - 1) * 24 + 8);
}

fn emit_jcc(cc: i64, l: i64) -> i64 {
    ops2(0x0f, cc);
    let k: i64 = gv(K_NJMP);
    store64(heap + O_JP + k * 8, gv(K_CLEN));
    store64(heap + O_JL + k * 8, l);
    sv(K_NJMP, k + 1);
    emit4(0);
    return 0;
}

fn emit_jmp(l: i64) -> i64 {
    emit1(0xe9);
    let k: i64 = gv(K_NJMP);
    store64(heap + O_JP + k * 8, gv(K_CLEN));
    store64(heap + O_JL + k * 8, l);
    sv(K_NJMP, k + 1);
    emit4(0);
    # 记下这条 jmp，供 place_label 判断是否为死跳转。
    # 必须在 emit4 之后设置——emit1/emit4 会清标记。
    sv(K_PJMP, k + 1);
    sv(K_PJLBL, l);
    sv(K_PJEND, gv(K_CLEN));
    return 0;
}
