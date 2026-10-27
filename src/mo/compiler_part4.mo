
# ==========================================================================
#  符号表
#    kind 0 = 函数   1 = 局部   2 = 全局
# ==========================================================================
var R_SYM:   i64 = 0;
var R_NARG:  i64 = 0;
var R_L1:    i64 = 0;
var R_L2:    i64 = 0;
var R_BASE:  i64 = 0;
var R_AFTER: i64 = 0;

fn scratch1() -> i64 { return heap + O_SCAL + 400; }
fn scratch2() -> i64 { return heap + O_SCAL + 700; }
fn scratch3() -> i64 { return heap + O_SCAL + 1000; }

# 按调用深度分配的暂存区，避免嵌套调用互相覆盖
var CALLD:  i64 = 0;
# 最近一次函数调用名所在的位置。
#
# 为什么需要：解析完实参后 K_PPOS/K_PCOL 已经走到 `;` 了，
# 此时报错会指向行尾 —— 谁也看不出是哪个名字未定义。
var CE_P: i64 = 0;
var CE_C: i64 = 0;
var CE_L: i64 = 0;
var R_ETY:  i64 = 0;      # 最近一个表达式的类型 id
# ---- `?` 错误传播 ----
#
# `f()?` 展开为：调用 f，若返回值 < 0（约定负数=错误）就**立即带着该值返回**，
# 否则把返回值留在 rax 里继续往下走。等价于手写
#     let t = f(); if t < 0 { return t; }
# 但编译器保证不会忘。
#
# 🔴 只在 rax 上做检查 —— 墨语言所有返回值都在 rax。
#    cmp 不改 rax，所以"检查"和"把值传下去"两件事天然不冲突。
fn emit_err_propagate() -> i64 {
    if gv(K_DEPTH) <= 0 {
        return err_at2("'?' can only be used inside a function", gv(K_LINE), gv(K_COL));
    }
    # 函数必须有返回值：`?` 要"带着错误码返回"，void 函数无从返回
    if gv(K_HASRET) == 0 {
        sv(K_HASRET, 1);
    }
    ops3(0x48, 0x83, 0xf8);      # cmp rax, 0
    emit1(0);
    let el: i64 = load64(heap + O_ERRLAB);
    if el < 0 {
        el = new_label();
        store64(heap + O_ERRLAB, el);
    }
    emit_jcc(0x8c, el);          # 0f 8c = jl rel32
    R_ETY = ty_int();
    return 0;
}


var O_SCR:  i64 = 7454720;

fn cscratch() -> i64 {
    return heap + O_SCR + CALLD * 256;
}

# 同作用域内是否已存在同名符号（用于重复定义检查）
fn sym_dup(name: i64) -> i64 {
    let pf: i64 = gv(K_PFX);
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        if sym_kind(i) != 0 {
            if load64(heap + O_SD + i * 8) == gv(K_DEPTH) {
                # 前缀也要匹配，否则 A.mo 与 B.mo 各自定义的 helper
                # 会被判成"重复定义"（两者 K_DEPTH 都是 0）。
                if load64(heap + O_SPFX + i * 8) == pf {
                    if streq(name_at(i), name) == 1 { return i; }
                }
            }
        }
    }
    return -1;
}

# 符号区容量。各区间隔 16384 字节 = 2048 个符号。
# 超过就**明确报错**：此前没有检查，溢出会静默覆盖相邻的符号类型区，
# 表现为"崩在一个完全无关的简单函数里"，极难定位（mo2x 就栽在这上面）。
fn sym_add(name: i64, kind: i64, addr: i64, npar: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    if i >= 2048 { return die("too many symbols (limit 2048)"); }
    let no: i64 = intern(name);
    store64(heap + O_SYN + i * 8, no);
    store64(heap + O_SK + i * 8, kind);
    store64(heap + O_SA + i * 8, addr);
    store64(heap + O_SP + i * 8, npar);
    store64(heap + O_SD + i * 8, gv(K_DEPTH));
    store64(heap + O_SU + i * 8, 0);
    # import "x.mo" as N; —— 只有**本文件定义的函数**(kind 0) 归入该模块。
    # 🔴 extern(kind 3) 不能归：它是 C 的全局符号，归进模块后
    #    name_at(i) 虽然不变，但 sym_lookup_func 在本模块外查不到它，
    #    而库之间共享 extern 是既有用法（io.mo / cstd.mo 都靠它）。
    # 🔴 变量也不归：库里的全局 var 被 main 直接引用是既有用法。
    if kind == 0 { store64(heap + O_SPFX + i * 8, gv(K_PFX)); }
    else { store64(heap + O_SPFX + i * 8, 0); }
    sv(K_NSYM, i + 1);
    return i;
}

fn sym_kind(i: i64) -> i64 { return load64(heap + O_SK + i * 8); }
fn sym_addr(i: i64) -> i64 { return load64(heap + O_SA + i * 8); }

# 在**指定前缀**下查符号（pf 指向 "N." 这样的字符串，0 = 全局）。
# wantfn=1 找函数（kind 0 本文件定义 / kind 3 extern），wantfn=0 找变量。
#
# 🔴 kind 的判据**两个方向不一样**，第一版统一写成 `sym_kind(i) != 0`
#    （那是 sym_lookup 变量版的写法），结果把所有 kind==0 的函数
#    全过滤掉了 —— 症状是"任何程序都报 no main function"，
#    报错点离改动很远，看 sym_lookup 的源码根本看不出来。
fn sym_lookup_in(name: i64, pf: i64, wantfn: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        let k: i64 = sym_kind(i);
        let ok: i64 = 0;
        if wantfn == 1 {
            if k == 0 { ok = 1; }
            if k == 3 { ok = 1; }
        } else {
            if k != 0 { ok = 1; }
        }
        if ok == 1 {
            if load64(heap + O_SPFX + i * 8) == pf {
                if streq(name_at(i), name) == 1 { return i; }
            }
        }
    }
    return -1;
}

fn sym_lookup(name: i64) -> i64 {
    let pf: i64 = gv(K_PFX);
    let r: i64 = sym_lookup_in(name, pf, 0);
    if r >= 0 { return r; }
    # 回退到全局命名空间：库内部要用 print / alloc 这些全局符号，
    # 它们不属于任何模块。K_PFX==0 时上面已经查过全局，不必再来一遍。
    if pf != 0 { return sym_lookup_in(name, 0, 0); }
    return -1;
}

fn sym_lookup_func(name: i64) -> i64 {
    let pf: i64 = gv(K_PFX);
    # kind 0 = 本文件定义的函数，kind 3 = extern 声明的 C 函数。
    # 两者在调用点上是同一回事 —— 都要走 System V 传参并 call。
    let i: i64 = sym_lookup_in(name, pf, 1);
    if i >= 0 { return i; }
    if pf != 0 { return sym_lookup_in(name, 0, 1); }
    return -1;
}

# 按模块名找模块，返回 mid；没有返回 -1。
fn mod_find(name: i64) -> i64 {
    let n: i64 = load64(heap + O_NMOD);
    let i: i64 = 0;
    while i < n {
        let q: i64 = heap + O_MODS + i * 32;
        # O_MODS 里存的是 "N."（带尾点），比较时跳过这个点：
        # 逐字符比到 name 结束，再确认下一个字符正好是 '.'
        let j: i64 = 0;
        let ok: i64 = 1;
        while load8(name + j) != 0 {
            if load8(name + j) != load8(q + j) { ok = 0; }
            j = j + 1;
        }
        if ok == 1 {
            if load8(q + j) == 46 { return i; }
        }
        i = i + 1;
    }
    return -1;
}

# ==========================================================================
#  结构体表
#    O_STN[si]                 结构体名（intern 偏移）
#    O_STF[si]                 字段个数
#    O_STFLD[si*32+fi]         字段名 id
#    O_STFT[si*32+fi]          字段类型：0=i64，>=1 为结构体索引+1
# ==========================================================================
fn st_add(name: i64) -> i64 {
    let i: i64 = gv(K_NSTRUCT);
    store64(heap + O_STN + i * 8, intern(name));
    store64(heap + O_STF + i * 8, 0);
    sv(K_NSTRUCT, i + 1);
    return i;
}

fn st_lookup(name: i64) -> i64 {
    let i: i64 = gv(K_NSTRUCT);
    while i > 0 {
        i = i - 1;
        if streq(heap + O_NAMES + load64(heap + O_STN + i * 8), name) == 1 { return i; }
    }
    return -1;
}

fn st_nfields(si: i64) -> i64 { return load64(heap + O_STF + si * 8); }

# 反查结构体名字（已 intern 的字符串地址）。
# 方法调用要靠它拼出 "Class.method" 这个内建函数名。
# 返回类型是 i64（地址）—— 墨语言的函数返回类型不支持 ptr
fn st_name(si: i64) -> i64 {
    return heap + O_NAMES + load64(heap + O_STN + si * 8);
}
fn st_field_name(si: i64, fi: i64) -> i64 {
    return heap + O_NAMES + load64(heap + O_STFLD + (si * 32 + fi) * 8);
}

# 类名 → 结构体索引。与 st_lookup 同义，只是名字更贴合类的语境。
fn class_lookup(name: i64) -> i64 { return st_lookup(name); }

# ==========================================================================
#  方法表
#
#  为什么不用"拼字符串 Class.method 再查符号"：
#  compiler.mo 是用 **seed** 编译的，而 seed 只支持语法子集 ——
#  没有局部数组、没有 ptr 变量、没有一元 &，所以没法做字符串拼接。
#  （我第一版就是这么写的，编译直接失败。）
#
#  改用方法表：(类名 intern, 方法名 intern) → 函数符号。
#  intern 保证同一字符串得到同一整数，所以比较整数相等即可。
# ==========================================================================

fn method_reg(si: i64, mname: i64, fsym: i64) -> i64 {
    let k: i64 = gv(K_NMETHOD);
    if k >= 512 { return 0 - 1; }
    store64(heap + O_MCLS + k * 8, load64(heap + O_STN + si * 8));
    store64(heap + O_MNAM + k * 8, intern(mname));
    store64(heap + O_MSYM + k * 8, fsym);
    sv(K_NMETHOD, k + 1);
    return k;
}

# 返回函数符号索引，找不到返回 -1
fn method_find(ci: i64, mi: i64) -> i64 {
    let k: i64 = gv(K_NMETHOD);
    while k > 0 {
        k = k - 1;
        if load64(heap + O_MCLS + k * 8) == ci {
            if load64(heap + O_MNAM + k * 8) == mi {
                return load64(heap + O_MSYM + k * 8);
            }
        }
    }
    return 0 - 1;
}

fn st_add_field(si: i64, fname: i64, ftype: i64) -> i64 {
    if st_field(si, fname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let fi: i64 = load64(heap + O_STF + si * 8);
    store64(heap + O_STFLD + (si * 32 + fi) * 8, intern(fname));
    store64(heap + O_STFT + (si * 32 + fi) * 8, ftype);
    store64(heap + O_STF + si * 8, fi + 1);
    return fi;
}

# 在结构体 si 中查找字段，返回索引或 -1
fn st_field(si: i64, fname: i64) -> i64 {
    let n: i64 = load64(heap + O_STF + si * 8);
    let i: i64 = 0;
    while i < n {
        if streq(heap + O_NAMES + load64(heap + O_STFLD + (si * 32 + i) * 8), fname) == 1 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn st_field_type(si: i64, fi: i64) -> i64 {
    return load64(heap + O_STFT + (si * 32 + fi) * 8);
}

# 结构体占用的 8 字节槽数（递归展开嵌套结构体）。
#
# 🔴 直接用 st_nfields 只数直接字段：
#      struct P { x, y }            nfields=2  槽=2   一致
#      struct W { a, inner: P }     nfields=2  槽=3   ← 少算 1 个
#    少算的后果不是"报错"，而是**静默写坏**：
#      · 结构体局部变量/全局变量在数据段只留出 nfields 个 qword，
#        多出来的槽落到下一个数据（往往是字符串字面量）上。
#        实测 `w.inner.y = 3` 把 "len=" 所在的 8 字节整块覆盖，
#        于是后面 print("...") 全部打空 —— 编译、运行都不报错。
#      · 结构体整体赋值只拷 nfields 个词，嵌套字段拷不全。
#
# 深度上限 16：防护结构体（间接）自引用导致的无限递归。
fn st_words(si: i64) -> i64 { return st_words_d(si, 0); }
fn st_words_d(si: i64, depth: i64) -> i64 {
    if depth > 16 { return die("struct nesting too deep (cycle?)"); }
    let n: i64 = st_nfields(si);
    let i: i64 = 0;
    let w: i64 = 0;
    while i < n {
        let ft: i64 = st_field_type(si, i);
        if ty_kind(ft) == 2 { w = w + st_words_d(ty_a(ft), depth + 1); }
        if ty_kind(ft) != 2 { w = w + 1; }
        i = i + 1;
    }
    return w;
}

# 字段 fi 的字节偏移（累计，不是 fi * 8）。
#
# 🔴 原实现用 `fi * 8`，等价于"每个字段都占 1 个槽"。
#    嵌套结构体字段后面还有字段时全部错位：
#      struct W { inner: P; b: i64; }
#        inner @0（2 槽），b 应在 @16，实际被算成 @8 = inner.y 的槽
#      => w.b = 3 覆盖了 w.inner.y，读回来 inner.y=3、b=3。
#    不崩溃、不报错、值还"看着合理"，是最难发现的一类错。
#
# 与 DWARF 成员偏移（dbg 里的 pos 累加）必须用同一套规则，
# 否则调试器读到的字段和实际代码写的字段对不上。
fn st_field_off(si: i64, fi: i64) -> i64 {
    let i: i64 = 0;
    let pos: i64 = 0;
    while i < fi {
        let ft: i64 = st_field_type(si, i);
        if ty_kind(ft) == 2 { pos = pos + ty_size(ft); }
        if ty_kind(ft) != 2 { pos = pos + 8; }
        i = i + 1;
    }
    return pos;
}

fn sym_type(i: i64) -> i64 { return load64(heap + O_STY + i * 8); }
fn sym_npar(i: i64) -> i64 { return load64(heap + O_SP + i * 8); }

# 两个类型是否可以在赋值/传参中互换
# 当前机器层都是 8 字节；禁止的是把数组或结构体当标量用
fn ty_compat(a: i64, b: i64) -> i64 {
    if ty_eq(a, b) == 1 { return 1; }
    let ka: i64 = ty_kind(a);
    let kb: i64 = ty_kind(b);
    if ka == 3 { return 0; }
    if kb == 3 { return 0; }
    if ka == 2 { return 0; }
    if kb == 2 { return 0; }
    return 1;
}

# 解析 .field 链：进入时当前 token 为 '.'，rax 已持有基址，ty 为基址类型
# 返回最终字段类型（0=i64，>=1 结构体索引+1）；rax 中留下该字段的地址
fn field_chain(ty: i64) -> i64 {
    while tok_is(".") == 1 {
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(scratch1(), tokbuf());
        next_token();
        let si: i64 = 0;
        if ty_kind(ty) == 2 {
            si = ty_a(ty);
        } else {
            # 指向结构体的指针也能用 . 访问字段（对标 C++ 的 ->）。
            # 这是类方法里 self.w 能工作的基础：self 是一个 ptr。
            # rax 里已经是对象地址，与结构体变量取地址后完全一样，
            # 所以后面的偏移计算不用改。
            if ty_kind(ty) == 4 {
                if ty_kind(ty_a(ty)) == 2 {
                    si = ty_a(ty_a(ty));
                } else {
                    return err_atp("field access on non-struct type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            } else {
                return err_atp("field access on non-struct type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
        let fi: i64 = st_field(si, scratch1());
        if fi < 0 { return undef_err(scratch1()); }
        if fi > 0 {
            g_push_rax();
            g_movabs_rax(st_field_off(si, fi));
            g_pop_rcx();
            g_add();
        }
        ty = st_field_type(si, fi);
    }
    return ty;
}

# 从符号 sy 取基址并解析 .field 链
fn field_addr(sy: i64) -> i64 {
    # 指针变量：变量**的值**就是对象地址，必须加载它。
    # 结构体变量：变量所在的地址才是对象地址，取 lea。
    # 这两者弄混的话，self.w 会读到"形参槽里的值的高位字节"。
    if ty_kind(sym_type(sy)) == 4 {
        load_sym(sy);
    } else {
        if sym_kind(sy) == 1 {
            g_lea_local(sym_addr(sy));
        } else {
            g_movabs_rax(sym_addr(sy));
        }
    }
    return field_chain(sym_type(sy));
}

# 打印一行警告。与 undef_err 不同：不退出，编译继续。
fn warn_unused_at(name: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ": warning: unused variable '", 28, 0, 0, 0);
    syscall(1, 2, name, strlen(name), 0, 0, 0);
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    return 0;
}

# 未使用变量检查：只报警告，不影响编译成功。
# 选警告而不是错误，是因为它不该挡住编译 —— 而且这条诊断只在 moc 实现，
# seed 不实现它。保持它是警告的第二个理由：万一误报，
# 代价只是多打几行字，不是编译不过。
fn warn_unused(d: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        let k: i64 = i - 1;
        if load64(heap + O_SD + k * 8) < d {
            return 0;
        }
        # 只查局部变量（kind==1）：全局量可能只被别的文件用
        if load64(heap + O_SK + k * 8) == 1 {
            if load64(heap + O_SU + k * 8) == 0 {
                warn_unused_at(name_at(k));
            }
        }
        i = i - 1;
    }
    return 0;
}

fn sym_pop_scope(d: i64) -> i64 {
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        if load64(heap + O_SD + (i - 1) * 8) < d {
            sv(K_NSYM, i);
            return 0;
        }
        i = i - 1;
    }
    sv(K_NSYM, 0);
    return 0;
}

# ==========================================================================
#  表达式
# ==========================================================================
fn parse_expr() -> i64 { return parse_or(); }

fn parse_or() -> i64 {
    parse_and();
    while accept("||") == 1 {
        let a: i64 = new_label();
        let b: i64 = new_label();
        g_cmp_rax_0();
        emit_jcc(0x85, a);
        parse_and();
        g_cmp_rax_0();
        emit_jcc(0x85, a);
        g_movabs_rax(0);
        emit_jmp(b);
        place_label(a);
        g_movabs_rax(1);
        place_label(b);
    }
    return 0;
}

fn parse_and() -> i64 {
    parse_bor();
    while accept("&&") == 1 {
        let a: i64 = new_label();
        let b: i64 = new_label();
        g_cmp_rax_0();
        emit_jcc(0x84, a);
        parse_bor();
        g_cmp_rax_0();
        emit_jcc(0x84, a);
        g_movabs_rax(1);
        emit_jmp(b);
        place_label(a);
        g_movabs_rax(0);
        place_label(b);
    }
    return 0;
}

fn parse_bor() -> i64 {
    parse_bxor();
    while accept("|") == 1 {
        g_push_rax();
        parse_bxor();
        g_pop_rcx();
        g_or();
    }
    return 0;
}

fn parse_bxor() -> i64 {
    parse_band();
    while accept("^") == 1 {
        g_push_rax();
        parse_band();
        g_pop_rcx();
        g_xor();
    }
    return 0;
}

fn parse_band() -> i64 {
    parse_eq();
    while accept("&") == 1 {
        g_push_rax();
        parse_eq();
        g_pop_rcx();
        g_and();
    }
    return 0;
}

fn parse_eq() -> i64 {
    parse_rel();
    let lt: i64 = R_ETY;
    while 1 {
        if accept("==") == 1 {
            g_push_rax();
            parse_rel();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if ty_kind(lt) == 6 { g_cmp_set_f64(0x94); }
            else {
                if ty_kind(rt) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x94); }
                else {
                    # 两侧**都是** str 才做内容比较；一侧是 str 一侧是整数
                    # （典型：`s == 0` 判空）仍按地址比——那才是想要的语义。
                    if ty_kind(lt) == 10 {
                        if ty_kind(rt) == 10 { g_str_eq(1); }
                        else { g_cmp_set(0x94); }
                    } else { g_cmp_set(0x94); }
                }
            }
            R_ETY = ty_int();
            lt = R_ETY;
        } else {
            if accept("!=") == 1 {
                g_push_rax();
                parse_rel();
                let rt2: i64 = R_ETY;
                g_pop_rcx();
                if ty_kind(lt) == 6 { g_cmp_set_f64(0x95); }
                else {
                    if ty_kind(rt2) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x95); }
                    else {
                        if ty_kind(lt) == 10 {
                            if ty_kind(rt2) == 10 { g_str_eq(0); }
                            else { g_cmp_set(0x95); }
                        } else { g_cmp_set(0x95); }
                    }
                }
                R_ETY = ty_int();
                lt = R_ETY;
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_rel() -> i64 {
    parse_shift();
    let lt: i64 = R_ETY;
    while 1 {
        if accept("<") == 1 {
            g_push_rax();
            parse_shift();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if ty_kind(lt) == 6 { g_cmp_set_f64(0x9c); }
            else {
                if ty_kind(rt) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x9c); }
                else { if ty_kind(lt) == 10 { if ty_kind(rt) == 10 { g_str_cmp(0x92); } else { g_cmp_set(0x9c); } } else { g_cmp_set(0x9c); } }
            }
            R_ETY = ty_int();
            lt = R_ETY;
        } else {
            if accept("<=") == 1 {
                g_push_rax();
                parse_shift();
            let rt: i64 = R_ETY;
                g_pop_rcx();
                if ty_kind(lt) == 6 { g_cmp_set_f64(0x9e); }
            else {
                if ty_kind(rt) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x9e); }
                else { if ty_kind(lt) == 10 { if ty_kind(rt) == 10 { g_str_cmp(0x96); } else { g_cmp_set(0x9e); } } else { g_cmp_set(0x9e); } }
            }
            R_ETY = ty_int();
            lt = R_ETY;
            } else {
                if accept(">") == 1 {
                    g_push_rax();
                    parse_shift();
            let rt: i64 = R_ETY;
                    g_pop_rcx();
                    if ty_kind(lt) == 6 { g_cmp_set_f64(0x9f); }
            else {
                if ty_kind(rt) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x9f); }
                else { if ty_kind(lt) == 10 { if ty_kind(rt) == 10 { g_str_cmp(0x97); } else { g_cmp_set(0x9f); } } else { g_cmp_set(0x9f); } }
            }
            R_ETY = ty_int();
            lt = R_ETY;
                } else {
                    if accept(">=") == 1 {
                        g_push_rax();
                        parse_shift();
            let rt: i64 = R_ETY;
                        g_pop_rcx();
                        if ty_kind(lt) == 6 { g_cmp_set_f64(0x9d); }
            else {
                if ty_kind(rt) == 6 { g_i2f_rcx(); g_cmp_set_f64(0x9d); }
                else { if ty_kind(lt) == 10 { if ty_kind(rt) == 10 { g_str_cmp(0x93); } else { g_cmp_set(0x9d); } } else { g_cmp_set(0x9d); } }
            }
            R_ETY = ty_int();
            lt = R_ETY;
                    } else {
                        return 0;
                    }
                }
            }
        }
    }
    return 0;
}

fn parse_shift() -> i64 {
    parse_add();
    while 1 {
        if accept("<<") == 1 {
            g_push_rax();
            parse_add();
            g_pop_rcx();
            g_shl();
            R_ETY = ty_int();
        } else {
            if accept(">>") == 1 {
                g_push_rax();
                parse_add();
                g_pop_rcx();
                g_sar();
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_add() -> i64 {
    parse_mul();
    let lt: i64 = R_ETY;
    while 1 {
        if accept("+") == 1 {
            g_push_rax();
            parse_mul();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            # 🔴 str 的 '+' 是拼接。两侧必须**都是** str：
            #    str + 整数、整数 + str 一律报错，绝不退化成地址相加 ——
            #    那会静默给出一个指向字符串中间的野指针。
            if ty_kind(lt) == 10 {
                if ty_kind(rt) != 10 {
                    return err_at2("'+': str 只能与 str 相加", gv(K_LINE), gv(K_COL));
                }
                if g_str_cat() != 0 { return -1; }
                R_ETY = ty_str();
            } else {
                if ty_kind(rt) == 10 {
                    return err_at2("'+': str 只能与 str 相加", gv(K_LINE), gv(K_COL));
                }
                if ty_kind(lt) == 6 {
                    if ty_kind(rt) != 6 { g_i2f_rax(); }
                    g_add_f64();
                    R_ETY = ty_float();
                } else {
                    if ty_kind(rt) == 6 {
                        g_i2f_rcx();
                        g_add_f64();
                        R_ETY = ty_float();
                    } else {
                        g_add();
                        R_ETY = ty_int();
                    }
                }
            }
            lt = R_ETY;
        } else {
            if accept("-") == 1 {
                g_push_rax();
                parse_mul();
                let rt2: i64 = R_ETY;
                g_pop_rcx();
                # str 没有减法：两个地址相减在机器层面完全"合法"，
                # 会静默给出一个和字符串内容无关的整数。
                if ty_kind(lt) == 10 {
                    return err_at2("'-': str 不支持减法", gv(K_LINE), gv(K_COL));
                }
                if ty_kind(rt2) == 10 {
                    return err_at2("'-': str 不支持减法", gv(K_LINE), gv(K_COL));
                }
                if ty_kind(lt) == 6 {
                    if ty_kind(rt2) != 6 { g_i2f_rax(); }
                    g_sub_f64();
                    R_ETY = ty_float();
                } else {
                    if ty_kind(rt2) == 6 {
                        g_i2f_rcx();
                        g_sub_f64();
                        R_ETY = ty_float();
                    } else {
                        g_sub();
                        R_ETY = ty_int();
                    }
                }
                lt = R_ETY;
            } else {
                return 0;
            }
        }
    }
    return 0;
}

fn parse_mul() -> i64 {
    parse_unary();
    let lt: i64 = R_ETY;
    while 1 {
        if accept("*") == 1 {
            g_push_rax();
            parse_unary();
            let rt: i64 = R_ETY;
            g_pop_rcx();
            if ty_kind(lt) == 6 {
                if ty_kind(rt) != 6 { g_i2f_rax(); }
                g_mul_f64();
                R_ETY = ty_float();
            } else {
                if ty_kind(rt) == 6 {
                    g_i2f_rcx();
                    g_mul_f64();
                    R_ETY = ty_float();
                } else {
                    g_imul();
                    R_ETY = ty_int();
                }
            }
            lt = R_ETY;
        } else {
            if accept("/") == 1 {
                g_push_rax();
                parse_unary();
                let rt2: i64 = R_ETY;
                # 🔴 常量必须在 g_pop_rcx() **之前**捕获：pop 会清掉
                #    「rax 刚由常量产生」的标记，之后就读不到了。
                let ck: i64 = 0 - 1;
                let cm: i64 = 0;
                if gv(K_LAST) == 1 {
                    ck = pow2_exp(gv(K_LASTV));
                    if ck < 0 { if magic_ok(gv(K_LASTV)) == 1 { cm = gv(K_LASTV); } }
                }
                g_pop_rcx();
                if ty_kind(lt) == 6 {
                    if ty_kind(rt2) != 6 { g_i2f_rax(); }
                    g_div_f64();
                    R_ETY = ty_float();
                } else {
                    if ty_kind(rt2) == 6 {
                        g_i2f_rcx();
                        g_div_f64();
                        R_ETY = ty_float();
                    } else {
                        if ck >= 0 { g_div_pow2(0, ck); } else { if cm != 0 { g_div_magic(0, cm); } else { g_idiv(0); } }
                        R_ETY = ty_int();
                    }
                }
                lt = R_ETY;
            } else {
                if accept("%") == 1 {
                    g_push_rax();
                    parse_unary();
                    let ck2: i64 = 0 - 1;
                    let cm2: i64 = 0;
                    if gv(K_LAST) == 1 {
                        ck2 = pow2_exp(gv(K_LASTV));
                        if ck2 < 0 { if magic_ok(gv(K_LASTV)) == 1 { cm2 = gv(K_LASTV); } }
                    }
                    g_pop_rcx();
                    if ck2 >= 0 { g_div_pow2(1, ck2); } else { if cm2 != 0 { g_div_magic(1, cm2); } else { g_idiv(1); } }
                } else {
                    return 0;
                }
            }
        }
    }
    return 0;
}

# 一元 & ：取变量 / 数组首元素的地址（指针即整数）
fn parse_addr() -> i64 {
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(scratch1(), tokbuf());
    next_token();
    let sy: i64 = sym_lookup_func(scratch1());
    if sy >= 0 { return func_addr(sy); }
    let sv: i64 = sym_lookup(scratch1());
    if sv < 0 { return undef_err(scratch1()); }
    if sym_kind(sv) == 1 {
        g_lea_local(sym_addr(sv));
    } else {
        g_movabs_rax(sym_addr(sv));
    }
    R_ETY = ty_ptr(elem_type(sym_type(sv)));
    return 0;
}

# &funcname —— 取函数地址（函数指针）
#
# 有了它才能把墨函数当回调传给 C（qsort 的比较器、pthread 的入口、
# atexit 等）。此前这是硬限制：函数名在墨语言里不是值。
fn func_addr(sy: i64) -> i64 {
    R_ETY = ty_ptr(ty_void());
    # -c 模式：发 movabs rax,0 并留一条 R_X86_64_64 重定位，
    # 让 ld 把真实地址填进去（.text 会被搬走，编译期算不出来）。
    if gv(K_OBJ) == 1 { return emit_func_addr(sy); }
    # extern（C 函数）不链接 libc 时没有地址
    if sym_kind(sy) == 3 { return 0; }
    spill_cache();
    let ta: i64 = sym_addr(sy);
    if ta >= 4194304 {
        if ta < 4194304 + 8388608 {
            ops2(0x48, 0xb8);
            emit8(ta);
            return 0;
        }
    }
    # 前向引用：函数还没定义。发 movabs 占位，交由 resolve_all 回填
    # （resolve_all 判断首字节不是 0xe8 就写 8 字节，正好对上）。
    ops2(0x48, 0xb8);
    let k: i64 = gv(K_NFNP);
    if k >= 16384 { return die("too many call sites (limit 16384)"); }
    store64(heap + O_FP + k * 8, gv(K_CLEN));
    store64(heap + O_FS + k * 8, sy);
    sv(K_NFNP, k + 1);
    emit8(0);
    return 0;
}

# ==========================================================================
#  sizeof / alignof —— 编译期运算符（对标 C）
#
#  只支持 sizeof(类型) 这一种形式，不支持 sizeof(表达式)。
#  理由：表达式形式需要先解析表达式再丢弃代码（否则会把副作用编进去），
#  在没有 AST 的架构下代价大；而类型形式覆盖了绝大多数真实用途。
# ==========================================================================

# 解析一个类型名，成功返回类型 id，失败返回 -1 并**恢复位置**。
# 支持：i64 / byte / ptr / 结构体名 / [N] 元素类型
fn try_parse_type() -> i64 {
    let back: i64 = gv(K_TOKPOS);
    let t: i64 = -1;
    # str 是**上下文关键字**：只在类型位置生效，不占用标识符空间。
    # 做成真关键字会破坏已有代码里名为 str 的变量（本编译器里没有，
    # 但用户代码可能有）。早退即可，不必重排下面的 if/else 链。
    if tok_is("str") == 1 { next_token(); return ty_str(); }
    if tok_is("i64") == 1 {
        next_token();
        t = ty_int();
    } else {
        if tok_is("byte") == 1 {
            next_token();
            t = ty_byte();
        } else {
            if tok_is("ptr") == 1 {
                next_token();
                t = ty_ptr(ty_byte());
            } else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        next_token();
                        t = ty_struct(si);
                    }
                } else {
                    if tok_is("[") == 1 {
                        next_token();
                        let n: i64 = 0;
                        if gv(K_TKIND) == 2 {
                            n = gv(K_TIVAL);
                        }
                        next_token();
                        expect("]");
                        let et: i64 = -1;
                        if tok_is("i64") == 1 { next_token(); et = ty_int(); }
                        else {
                            if tok_is("byte") == 1 { next_token(); et = ty_byte(); }
                            else {
                                if gv(K_TKIND) == 1 {
                                    let si2: i64 = st_lookup(tokbuf());
                                    if si2 >= 0 { next_token(); et = ty_struct(si2); }
                                }
                            }
                        }
                        if et < 0 { set_pos(back); return -1; }
                        if n <= 0 { set_pos(back); return -1; }
                        t = ty_array(et, n);
                    }
                }
            }
        }
    }
    if t < 0 { set_pos(back); return -1; }
    return t;
}

# 对齐：与 C 一致 —— 标量对齐等于自身大小，数组等于元素对齐，
# 结构体等于最大字段对齐。墨语言目前没有 packed/alignas，所以
# 结构体对齐恒为 8。
fn ty_align(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 5 { return 1; }        # byte
    if k == 3 { return ty_align(ty_a(t)); }
    return 8;
}

fn parse_sizeof() -> i64 {
    expect("(");
    let t: i64 = try_parse_type();
    if t < 0 {
        return err_at2("sizeof requires a type in parentheses", gv(K_LINE), gv(K_COL));
    }
    expect(")");
    g_movabs_rax(ty_size(t));
    R_ETY = ty_int();
    return 0;
}

fn parse_alignof() -> i64 {
    expect("(");
    let t: i64 = try_parse_type();
    if t < 0 {
        return err_at2("alignof requires a type in parentheses", gv(K_LINE), gv(K_COL));
    }
    expect(")");
    g_movabs_rax(ty_align(t));
    R_ETY = ty_int();
    return 0;
}

fn parse_unary() -> i64 {
    if tok_is("sizeof") == 1 { next_token(); return parse_sizeof(); }
    if tok_is("alignof") == 1 { next_token(); return parse_alignof(); }
    if accept("&") == 1 { return parse_addr(); }
    if accept("-") == 1 {
        parse_unary();
        if ty_kind(R_ETY) == 6 { g_neg_f64(); }
        else { g_neg(); }
        return 0;
    }
    if accept("~") == 1 {
        parse_unary();
        g_not();
        R_ETY = ty_int();
        return 0;
    }
    if accept("!") == 1 {
        parse_unary();
        g_lnot();
        R_ETY = ty_int();
        return 0;
    }
    return parse_primary();
}

# 未定义符号时，猜它可能在哪个库里。
#
# 这不是"智能推断"，就是一张手写表 —— 但足够覆盖绝大多数情况。
# 没有提示时，用户看到 "undefined symbol 'print'" 完全想不到是缺 import。
fn lib_hint(name: i64) -> i64 {
    if streq(name, "print") == 1 { return "io.mo"; }
    if streq(name, "print_i64") == 1 { return "io.mo"; }
    if streq(name, "print_c") == 1 { return "io.mo"; }
    if streq(name, "die") == 1 { return "io.mo"; }
    if streq(name, "strlen") == 1 { return "str.mo"; }
    if streq(name, "strcmp") == 1 { return "str.mo"; }
    if streq(name, "strcpy") == 1 { return "str.mo"; }
    if streq(name, "strcat") == 1 { return "str.mo"; }
    if streq(name, "strchr") == 1 { return "str.mo"; }
    if streq(name, "itoa") == 1 { return "str.mo"; }
    if streq(name, "alloc") == 1 { return "mem.mo"; }
    if streq(name, "alloc8") == 1 { return "mem.mo"; }
    if streq(name, "heap_init") == 1 { return "mem.mo"; }
    if streq(name, "scat_cat") == 1 { return "scat.mo"; }
    if streq(name, "scat_reset") == 1 { return "scat.mo"; }
    return 0;
}

fn undef_call() -> i64 {
    let nm: i64 = cscratch();
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(CE_L);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(CE_C);
    syscall(1, 2, ": error: undefined symbol '", 27, 0, 0, 0);
    syscall(1, 2, nm, strlen(nm), 0, 0, 0);
    syscall(1, 2, "'", 1, 0, 0, 0);
    let h: i64 = lib_hint(nm);
    if h != 0 {
        # 用单引号包库名：双引号在墨语言字符串里要转义，
        # 而转义在这里没生效，会输出成 `import io.mo";` 这种缺一半的样子。
        syscall(1, 2, " -- try: import '", 17, 0, 0, 0);
        syscall(1, 2, h, strlen(h), 0, 0, 0);
        syscall(1, 2, "'", 1, 0, 0, 0);
    }
    syscall(1, 2, "\n", 1, 0, 0, 0);
    err_src(CE_P, CE_C);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn undef_err(name: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(gv(K_PLINE));
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(gv(K_PCOL));
    syscall(1, 2, ": error: undefined symbol '", 27, 0, 0, 0);
    syscall(1, 2, name, strlen(name), 0, 0, 0);
    syscall(1, 2, "'\n", 2, 0, 0, 0);
    err_src(gv(K_PPOS), gv(K_PCOL));
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn parse_primary() -> i64 {
    let k: i64 = gv(K_TKIND);
    if k == 2 {
        # 浮点字面量：编译器自身没有浮点，位模式在**编译期用整数算出来**
        # （见 f64_bits），生成 movabs rax, <bits>。
        if gv(K_TFLT) == 1 {
            let bits: i64 = f64_bits(gv(K_TFDIG), gv(K_TFDIGN), FSTICKY, 0);
            g_movabs_rax(bits);
            next_token();
            R_ETY = ty_float();
            return 0;
        }
        g_movabs_rax(gv(K_TIVAL));
        next_token();
        R_ETY = ty_int();
        return 0;
    }
    if k == 3 {
        g_movabs_rax(gv(K_TIVAL));
        next_token();
        R_ETY = ty_str();
        # 字符串字面量直接下标："hello"[1]
        # 以前必须先赋给 ptr 变量才能用下标，很别扭。
        # 这里就地处理：基址已在 rax，算偏移后按 1 字节加载。
        if tok_is("[") == 1 {
            next_token();
            parse_expr();
            expect("]");
            g_push_rax();
            g_pop_rcx();
            g_add();
            g_load_at_b();
            R_ETY = ty_byte();
        }
        return 0;
    }
    if k == 4 {
        if accept("(") == 1 {
            parse_expr();
            expect(")");
            return 0;
        }
        return syntax_error();
    }
    if k == 1 {
        memcpy(scratch1(), tokbuf());
        next_token();
        # true / false —— 布尔字面量。
        #
        # ⚠️ 位置：必须在 **k==1（标识符）分支里、next_token 之后**。
        #    第一版放在 ptr/f64 那一簇（只在后跟 '(' 时才走到），
        #    于是 `let a: bool = true;` 报 undefined symbol 'true' ——
        #    true 后面没有 '('，根本走不到那里。
        #
        # 也**故意不做成关键字**：做成关键字会破坏已有代码里
        # 名为 true/false 的变量（lib/json.mo 注释里就有）。
        if streq(scratch1(), "true") == 1 {
            g_movabs_rax(1);
            R_ETY = ty_bool();
            return 0;
        }
        # Enum.CONST —— 具名整型常量。
        #
        # ⚠️ 位置：必须在**变量查找之前**，且只在 tok 是 '.' 时才试探。
        #    这样 `obj.field`（结构体字段）完全不受影响 ——
        #    那条路 tok 也是 '.'，但 enum 查不到会 fall through。
        if tok_is(".") == 1 {
            let save: i64 = gv(K_TOKPOS);
            next_token();
            if gv(K_TKIND) == 1 {
                let ei: i64 = enum_lookup(scratch1(), tokbuf());
                if ei >= 0 {
                    next_token();
                    g_movabs_rax(load64(heap + O_EVAL + ei * 8));
                    R_ETY = ty_int();
                    return 0;
                }
            }
            set_pos(save);              # 不是 enum：回退，走字段/方法路径
        }
        if streq(scratch1(), "false") == 1 {
            g_movabs_rax(0);
            R_ETY = ty_bool();
            return 0;
        }
        if tok_is("(") == 1 {
            if streq(scratch1(), "argc") == 1 {
                next_token();
                expect(")");
                g_movabs_rax(268435456);
                g_load_at();
                R_ETY = ty_int();
                return 0;
            }
            if streq(scratch1(), "argv") == 1 {
                next_token();
                parse_expr();
                expect(")");
                g_push_rax();
                g_pop_rax();
                g_mul_imm(8);
                g_push_rax();
                g_movabs_rax(268435464);
                g_load_at();
                g_pop_rcx();
                g_add();
                g_load_at();
                R_ETY = ty_int();
                return 0;
            }
            # ptr(v) —— 把整数当地址用（类型转换内建）
            #
            # **为什么需要它**：很多库函数（str_trim、str_dup、dir_next ...）
            # 返回 i64 —— 因为返回类型不支持 ptr。于是 sfmt 插值项会被判成
            # 数字，打印出地址数值（`hello 268435830` 那类）。
            #
            #   sfmt(dst, f"<h2>{ptr(L + 3)}</h2>")
            #
            # ⚠️ 位置很关键：标识符后跟 '(' **默认走函数调用**，
            # 所以必须在这个 `return parse_call()` **之前**拦截。
            # 放在 sym_lookup 之前也没用 —— 根本走不到那里
            #（第一版就是这么错的，报 undefined symbol 'ptr'）。
            # f64(x) / fint(x) —— int 与 double 的互转（内建）。
            #
            # 墨语言没有强制类型转换语法，用**内建函数**表达。
            # x 可以是任意表达式，所以走完整 parse_expr。
            if streq(scratch1(), "f64") == 1 {
                next_token();
                parse_expr();
                expect(")");
                if ty_kind(R_ETY) != 6 { g_i2f_rax(); }
                R_ETY = ty_float();
                return 0;
            }
            # fbits(x) —— 取 f64 的 **IEEE754 位模式**（不转换）。
            # f64 值在 rax 里本来就是位模式，所以这条指令什么都不发。
            # 用途：测试里与已知 double 位逐一核对。
            if streq(scratch1(), "fbits") == 1 {
                next_token();
                parse_expr();
                expect(")");
                R_ETY = ty_int();
                return 0;
            }
            # ffrombits(x) —— fbits 的逆：把 **IEEE754 位模式**直接当 f64
            # 用（不转换）。同样什么都不发，只改静态类型。
            #
            # 为什么需要它：数学库要在位层面构造常量（NaN、Inf、2^k），
            # 而 `f64(i)` 是**数值转换**（i=1 → 1.0），构造不出位模式。
            if streq(scratch1(), "ffrombits") == 1 {
                next_token();
                parse_expr();
                expect(")");
                R_ETY = ty_float();
                return 0;
            }
            if streq(scratch1(), "fint") == 1 {
                next_token();
                parse_expr();
                expect(")");
                if ty_kind(R_ETY) == 6 { g_f2i_rax(); }
                R_ETY = ty_int();
                return 0;
            }
            if streq(scratch1(), "ptr") == 1 {
                next_token();
                parse_expr();
                expect(")");
                R_ETY = ty_ptr(ty_byte());
                return 0;
            }
            let rc: i64 = parse_call();
            # `?`：返回值 < 0 就直接带着它返回（错误传播）
            if accept("?") == 1 { emit_err_propagate(); return 0; }
            # 链式：mk(1,2).sum()
            #
            # 函数返回结构体时值在 rax/rdx 里，而方法调用需要**对象地址**。
            # 所以先把它落到一个临时槽，再用该槽当 this。
            # 每次链式分配一个新槽（不复用），避免嵌套时互相覆盖。
            if ty_kind(R_ETY) == 2 {
                if peek_expr_method() == 1 { return parse_chain_method(); }
            }
            return rc;
        }
        let sy: i64 = sym_lookup(scratch1());
        # MOD.fn( —— 模块限定调用（import "x.mo" as MOD;）
        #
        # 🔴 只在**普通查找失败**时才试探。这是刻意的：`obj.method()`
        #    里 obj 是变量，sym_lookup 会命中，根本走不到这里 ——
        #    所以方法调用、字段访问、enum 全部不受影响。
        #    放在 sym_lookup 之前就会把 `r.area()` 抢走。
        if sy < 0 {
            if tok_is(".") == 1 {
                let save: i64 = gv(K_TOKPOS);
                next_token();
                if gv(K_TKIND) == 1 {
                    let mid: i64 = mod_find(scratch1());
                    if mid >= 0 {
                        memcpy(heap + O_MCB, tokbuf());
                        next_token();
                        if tok_is("(") == 1 {
                            memcpy(scratch1(), heap + O_MCB);
                            let oldpfx: i64 = gv(K_PFX);
                            sv(K_PFX, load64(heap + O_MODP + mid * 8));
                            let rc2: i64 = parse_call();
                            sv(K_PFX, oldpfx);
                            if accept("?") == 1 { emit_err_propagate(); return 0; }
                            return rc2;
                        }
                    }
                }
                set_pos(save);
            }
        }
        # 标记「被引用」。必须在解析处标记，不能只在 load_sym 里标：
        # 数组几乎都通过 &arr 使用，参数也常直接进内建函数实参，
        # 这两条路都不走 load_sym —— 放在那里标记会大量误报。
        if sy >= 0 {
            store64(heap + O_SU + sy * 8, 1);
        }
        if sy < 0 { return undef_err(scratch1()); }
        if tok_is("[") == 1 {
            index_addr(sy);
            let e2: i64 = elem_type(sym_type(sy));
            if tok_is(".") == 1 {
                let ft: i64 = field_chain(e2);
                if ty_kind(ft) != 2 {
                    if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                }
                return 0;
            }
            # 结构体元素在表达式里退化成**地址**（与结构体变量、数组名一致）。
            # 少了这一步，`sum(arr[0])` 会把第一个字段的**值**传进去，
            # 而形参是 ptr(S) 语义 —— 于是 o.x 去读 [5]，段错误。
            # 注意 index_addr 已经把地址放进 rax，这里直接返回即可。
            if ty_kind(e2) == 2 {
                R_SADDR = 1;
                R_ETY = e2;
                return 0;
            }
            # 元素宽度决定加载宽度：byte 元素必须按 1 字节零扩展，
            # 否则 s[i] 会一次读进 8 个字节。
            if ty_kind(e2) == 5 { g_load_at_b(); } else { g_load_at(); }
            R_ETY = e2;
            return 0;
        }
        # 方法调用（表达式位置）：let a = r.area();
        #
        # ⚠️ 必须**先预扫描再推进**。
        # 之前直接在这里实现会破坏 token 流：parse_call 消耗了右括号
        # 之后的 token，调用方再检查 tok_is("=") 判断"赋值还是表达式语句"
        # 时位置已不对，于是后续 let 的符号注册丢失。
        #
        # peek_expr_method() 纯读字节、不碰任何状态，确认是 `ident (`
        # 才真正解析；否则原样走字段访问。这样既不需要回退，
        # 也不会误伤 self.w = a 这种字段赋值。
        if tok_is(".") == 1 {
            if peek_expr_method() == 1 { return parse_expr_method(sy); }
        }
        # 保留 field_chain 对 ptr→struct 的支持，于是 self.w 依然可用。
        if tok_is(".") == 1 {
            let ft: i64 = field_addr(sy);
            if ty_kind(ft) != 2 { g_load_at(); }
            else { R_SADDR = 1; }
            R_ETY = ft;
            return 0;
        }
        load_sym(sy);
        R_ETY = sym_type(sy);
        return 0;
    }
    return syntax_error();
}

# 生成 a[i] 的地址到 rax（s 为数组符号索引）；进入时当前 token 为 '['
# 越界处理：所有下标检查跳转到的公共例程标签（按需创建）
fn panic_label() -> i64 {
    let l: i64 = gv(K_PANIC);
    if l < 0 {
        l = new_label();
        sv(K_PANIC, l);
    }
    return l;
}

# 把 "mo: index out of bounds\n"（24 字节）写进输出数据段，返回地址。
# 刻意用字符字面量逐字节写，而不是字符串字面量：
# 被编译程序里的字符串编译器读不到——那片虚拟地址在 moc 进程里
# 映射的是 moc 自己的数据段，读到的是垃圾。
fn panic_msg() -> i64 {
    let addr: i64 = 268435456 + gv(K_DLEN);
    dbyte('m'); dbyte('o'); dbyte(':'); dbyte(' ');
    dbyte('i'); dbyte('n'); dbyte('d'); dbyte('e'); dbyte('x');
    dbyte(' '); dbyte('o'); dbyte('u'); dbyte('t'); dbyte(' ');
    dbyte('o'); dbyte('f'); dbyte(' '); dbyte('b'); dbyte('o');
    dbyte('u'); dbyte('n'); dbyte('d'); dbyte('s'); dbyte('\n');
    dbyte(0);
    return addr;
}

# 在代码段末尾生成越界处理例程：打印消息并以 1 退出。
# 放在末尾而不是每个检查点内联，是为了让检查点只有 12 字节。
fn emit_panic() -> i64 {
    let l: i64 = gv(K_PANIC);
    if l < 0 { return 0; }
    place_label(l);
    # write(2, msg, 24)
    ops3(0x48, 0xc7, 0xc0); emit4(1);
    ops3(0x48, 0xc7, 0xc7); emit4(2);
    ops2(0x48, 0xbe); emit8(panic_msg());
    ops3(0x48, 0xc7, 0xc2); emit4(24);
    ops2(0x0f, 0x05);
    # exit(1)
    ops3(0x48, 0xc7, 0xc0); emit4(60);
    ops3(0x48, 0xc7, 0xc7); emit4(1);
    ops2(0x0f, 0x05);
    return 0;
}

# 记录「代码位置 -> 源码行」映射，供 -g 生成 DWARF 行号表。
# 每条 16 字节：(code_len, line)。
# 只记主文件（fileidx==0）的行号；import 进来的文件也记 fileidx，
# 生成时跳过——它们的行号属于别的源文件，混进主文件的行号表会错乱。
# 记录「代码位置 -> 源码行」映射，供 -g 生成 DWARF 行号表。
# 每条 16 字节：(code_len, line)。
#
# 只记主文件：parse_import 会在解析子文件期间把 K_DBG 临时置 0，
# 于是 dbg_mark 直接返回。用开关而不是给每条记录打文件号，
# 是因为后者依赖一个「当前文件索引」全局量，而那个量在实测中
# 读出来是脏值——与其追它，不如用一条本来就存在的开关。
fn dbg_mark() -> i64 {
    if gv(K_DBG) == 0 { return 0; }
    let n: i64 = gv(K_NLM);
    if n >= 60000 { return 0; }
    let a: i64 = gv(K_CLEN);
    # 同一地址不重复记录（多条语句可能在同一地址开始）
    if n > 0 {
        if load64(DBG + O_LM + (n - 1) * 16) == a { return 0; }
    }
    let ln0: i64 = gv(K_LINE);
    store64(DBG + O_LM + n * 16, a);
    store64(DBG + O_LM + n * 16 + 8, ln0);
    store8(DBG + O_LMF + n, gv(K_CURFILE));
    sv(K_NLM, n + 1);
    return 0;
}

# 在**指定行号**上登记一条映射，而不是取当前 K_LINE。
#
# 为什么需要它：dbg_mark() 只在 parse_stmt() 开头调用，而
# `fn xxx(...)` 的函数定义行**不是语句**，根本不经过 parse_stmt。
# 于是函数入口地址处没有行号记录 —— 行号表从函数体第一行开始。
#
# 后果（用 dwmo -l 量到，1.98）：bin/moc 里 355 个函数有 290 个的
# 定义行不在自己的行号记录里，gdb 在 `fn sv` 那行下不了断点。
# 编译和运行都正常，所以这件事在此之前从未被发现。
#
# 行号必须显式传入：到函数入口登记时，K_LINE 已经走到参数或函数体了。
fn dbg_mark_at(ln: i64) -> i64 {
    if gv(K_DBG) == 0 { return 0; }
    let n: i64 = gv(K_NLM);
    if n >= 60000 { return 0; }
    let a: i64 = gv(K_CLEN);
    # 同一地址已有记录：保留**更小**的行号（定义行在语句之前）
    if n > 0 {
        if load64(DBG + O_LM + (n - 1) * 16) == a {
            if ln < load64(DBG + O_LM + (n - 1) * 16 + 8) {
                store64(DBG + O_LM + (n - 1) * 16 + 8, ln);
            }
            return 0;
        }
    }
    store64(DBG + O_LM + n * 16, a);
    store64(DBG + O_LM + n * 16 + 8, ln);
    store8(DBG + O_LMF + n, gv(K_CURFILE));
    sv(K_NLM, n + 1);
    return 0;
}

fn index_addr(s: i64) -> i64 {
    let st: i64 = sym_type(s);
    let k: i64 = ty_kind(st);
    if k != 3 {
        if k != 4 {
            # str 与 ptr 一样按字节下标（elem_size(kind 10)=1）
            if k != 10 {
                return err_atp("subscript on non-array type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
    }
    expect("[");
    # 编译期常量下标：a[9] 这种一眼就看得出越界的，不必等到运行时。
    # 做法是先试探性地多读一个 token 看是不是 ']'，再 set_pos 退回去
    # 走正常的 parse_expr 路径。set_pos 会把 LINE/COL 也重算一遍，
    # 所以回退后行列信息依然正确。
    let cidx: i64 = -1;          # >=0 表示下标是编译期常量
    if gv(K_TKIND) == 2 {
        let iv: i64 = gv(K_TIVAL);
        let back: i64 = gv(K_TOKPOS);
        next_token();
        if tok_is("]") == 1 {
            cidx = iv;
            if k == 3 {
                let ne: i64 = ty_b(st);
                if iv < 0 {
                    return err_atp("index out of bounds: negative constant index", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                if iv >= ne {
                    return err_atp("index out of bounds: constant index >= array length", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
        }
        set_pos(back);
    }
    parse_expr();
    expect("]");
    # 越界检查：只对「编译期已知长度」的数组做。
    # 用无符号比较 cmp rax, n / jae —— 负数作为无符号是超大值，
    # 于是一条 cmp + 一条 jae 同时拦住了负下标与上界。
    # cmp 不破坏 rax，下标值还能继续用于下面的地址计算。
    if k == 3 {
        if cidx < 0 {
            let ne: i64 = ty_b(st);
            if ne <= 2147483647 {
                ops2(0x48, 0x3d);
                emit4(ne);
                emit_jcc(0x83, panic_label());
            }
        }
    }
    g_mul_imm(elem_size(st));
    g_push_rax();
    # 数组变量：变量所在的地址就是数组基址 —— 取地址（lea / 绝对地址）
    # 指针变量：变量的值是地址 —— 必须加载它的值
    # 这两者弄混的话，p[1] 会去读「指针变量本身的第 1 个字节」，
    # 也就是指针值的高位字节，而不是它指向的内容。
    # str 与 ptr 一样是「值里存地址」，必须加载变量的**值**。
    # 少了 kind 10 这一支会落到下面 sym_kind==1 的分支去 lea 变量自身，
    # 于是 p[0] 读到的是指针变量的低字节（实测 104 读成 216），
    # 不报错、不崩溃，只是值错。
    if ty_kind(st) == 4 {
        load_sym(s);
    } else {
        if ty_kind(st) == 10 {
            load_sym(s);
        } else {
        if sym_kind(s) == 1 {
            g_lea_local(sym_addr(s));
        } else {
            g_movabs_rax(sym_addr(s));
        }
        }
    }
    g_pop_rcx();
    g_add();
    return 0;
}

# argc() / argv(i)：读取启动时存进数据段头部的 argc / argv
fn is_argc() -> i64 {
    if streq(cscratch(), "argc") == 1 { return 1; }
    return 0;
}

# ---------------------------------------------------------------------------
#  超过 6 个实参的参数布置（System V：第 7 个起走栈，地址递增）
#
#  实参**顺序** push，栈顶是最后一个。na<=6 时依次 pop 到 r9..rdi
#  正好得到 arg6..arg1，天然正确。
#
#  na>6 时直接 pop 会拿到 argNa..arg(Na-5)，整体错位 —— 曾经
#  f(1..8) 里 h(a)+hh+i 得 9 而不是 17（rdi=arg3、参数7=arg2、
#  参数8=arg1，正好 6+2+1=9）。
#
#  修法：
#    1) arg_spill   ：pop 出多出来的 argNa..arg7 到**数据段暂存区**
#    2)             ：照常 pop 6 个到 r9..rdi（此时拿到 arg6..arg1）
#    3) arg_restack ：T[0] 先压回（argNa 最深、arg7 在栈顶）
#                     → [rsp+0]=arg7，对应 emit_store_arg 的 [rbp+16+(i-6)*8]
#    4) arg_cleanup ：调用方清理栈参数
#
#  暂存区**不需要按调用深度分层**：spill 与 restack 之间不解析、不递归
#  （所有实参在 spill 之前就解析完了）。
#
#  地址 0x10000010 是**被生成程序**数据段中 argc/argv 之后的位置。
#  曾经误用编译器自己的堆地址 → 生成的代码一运行就段错误。
var NARGS_MAX: i64 = 32;

# ==========================================================================
#  f64 字面量 → IEEE754 位模式
# ==========================================================================
# 编译器自身**没有浮点**（它是墨语言写的，只有 i64），所以把 "3.14159"
# 变成 double 的位模式必须**纯整数**算出来。
#
# 🔴 不能写 num << k / den：
#    3.14159 若按 314159/100000 算，分子要左移到 2^52 量级 ——
#    314159 << 52 早就溢出 i64 了，结果全是垃圾。
#    这个错误很隐蔽：小数看起来"差不多对"，符号和指数却是乱的。
#
# 正确做法：**模拟长除法逐位生成尾数** —— 每次只把余数乘 2，
# 余数始终 < den <= 10^8，乘 2 后仍远小于 i64 上限。

# 10^n，用循环而非查表：表只覆盖到 10^8，现在要支持到 10^18。
# 字面量不多，O(n) 完全可以接受。
fn pow10i(n: i64) -> i64 {
    let r: i64 = 1;
    let i: i64 = 0;
    while i < n {
        r = r * 10;
        i = i + 1;
    }
    return r;
}

# 5^n。为什么需要它：值 = N/10^k，而 10^k 在 k>18 时会溢出 i64。
# 利用 10^k = 5^k * 2^k —— 除以 5^k 用长除法，2^k 只是**二进制指数的位移**，
# 精确无损。可表示下限因此从 1e-18 推到 1e-26。
#
# 🔴 k 的上限为什么是 26 而不是 27：归一化靠「N 反复乘 2 直到 N >= D」，
#    循环内 N < D，所以 N*2 < 2D。一旦 2D > 2^63 就会**溢出成负数**，
#    于是 N < D 永远成立 —— 编译器死循环。0.0000000000000000000000008192
#    （k=27，D=5^27=7.45e18）实测就是这样卡死的：819*2^53=7.38e18 还差一点，
#    再乘 2 就溢出。要求 2*5^k < 2^63 → k <= 26。
#    这个失败模式是「编译卡住」而不是报错，属于最难查的一类。
fn pow5i(n: i64) -> i64 {
    let r: i64 = 1;
    let i: i64 = 0;
    while i < n {
        r = r * 5;
        i = i + 1;
    }
    return r;
}

# 位长度（q > 0）
fn bitlen(q: i64) -> i64 {
    let n: i64 = 0;
    let t: i64 = q;
    while t > 0 {
        n = n + 1;
        t = t / 2;
    }
    return n;
}

# N / 10^k → double 位模式。neg=1 表示负数，st=1 表示被截断的低位里有非零数字。
#
# 与旧实现的区别（也是当年那个"只取 8 位小数"的根源）：
#   旧代码把小数部分硬截成 8 位。0.693147180559945 被读成 0.69314718，
#   跟真值差了 5e6 个 ulp —— 而且**不报错、不崩溃**，只是静默给一个看起来合理的数。
#
# 现在：整数与小数合计保留 18 位有效数字（由 lex_number 分配预算），
# 再在位层面做 round-half-to-even；被截掉的位通过 st 参与平局判定。
fn f64_bits(N: i64, k: i64, st: i64, neg: i64) -> i64 {
    if N == 0 {
        if neg == 1 { return 0 - 9223372036854775807 - 1; }
        return 0;
    }
    # 除以 5^k 而非 10^k：10^k 在 k>18 时放不进 i64，
    # 而 2^k 那一半是精确的二进制位移，最后从指数里减掉即可。
    let D: i64 = pow5i(k);
    # 归一化到 [1,2)：纯小数时反复倍增，每倍增一次指数 -1
    let e_adj: i64 = 0;
    while N < D {
        N = N * 2;
        e_adj = e_adj + 1;
        # 兜底：k<=26 时不可能触发（最多约 63 次）。留着是因为这个循环
        # 一旦真溢出就会**静默死循环**——编译器卡住比报错难查得多。
        if e_adj > 200 { return 0; }
    }
    let q: i64 = N / D;
    let r: i64 = N - q * D;
    let bl: i64 = bitlen(q);
    let m: i64 = 0;
    if bl > 53 {
        # 整数部分超过 53 位有效位：右移后四舍五入，小数部分只作 sticky 参与平局
        let sh: i64 = bl - 53;
        let q2: i64 = q >> sh;
        let low: i64 = q - (q2 << sh);
        let half: i64 = 1 << (sh - 1);
        let odd: i64 = q2 - (q2 >> 1) * 2;
        let up: i64 = 0;
        if low > half { up = 1; }
        if low == half {
            if r > 0 { up = 1; }
            else {
                if st == 1 { up = 1; }
                else { if odd == 1 { up = 1; } }
            }
        }
        if up == 1 { q2 = q2 + 1; }
        if q2 >= 9007199254740992 { q2 = q2 >> 1; bl = bl + 1; }
        m = q2;
    } else {
        let nfrac: i64 = 53 - bl;
        let frac: i64 = 0;
        let i: i64 = 0;
        while i < nfrac {
            r = r * 2;
            if r >= D {
                frac = frac * 2 + 1;
                r = r - D;
            } else {
                frac = frac * 2;
            }
            i = i + 1;
        }
        # 舍入：再看一位，round-half-to-even；有被截断的非零低位时向上
        r = r * 2;
        if r > D { frac = frac + 1; }
        else {
            if r == D {
                if st == 1 { frac = frac + 1; }
                else {
                    let fo: i64 = frac - (frac >> 1) * 2;
                    if fo == 1 { frac = frac + 1; }
                }
            }
        }
        m = (q << nfrac) + frac;
        if m >= 9007199254740992 {      # 2^53，舍入进位
            m = m / 2;
            bl = bl + 1;
        }
    }
    let mant: i64 = m - 4503599627370496;   # 去掉隐含的最高位 2^52
    let exp: i64 = 1023 + bl - 1 - e_adj - k;
    if exp <= 0 { return 0; }               # 次正规：简化为 0
    if exp >= 2047 { exp = 2047; mant = 0; }
    let bits: i64 = (exp << 52) + mant;
    if neg == 1 {
        # 1<<63 在 i64 里是 MIN，不能直接写字面量（会溢出词法器）
        bits = bits + (0 - 9223372036854775807) - 1;
    }
    return bits;
}


# 预扫描：当前 token 是 '.' 时，判断后面是不是 `标识符 (`。
#
# 纯读字节，**不推进任何状态** —— 这样"判断错了"也不需要回退。
# 回退要恢复的东西太多（行号、列号、token 缓冲…），极易漏。
fn peek_expr_method() -> i64 {
    let p: i64 = gv(K_POS);
    while sbyte(p) == 32 { p = p + 1; }
    while sbyte(p) == 10 { p = p + 1; }
    while sbyte(p) == 9  { p = p + 1; }
    while sbyte(p) == 13 { p = p + 1; }
    if is_alpha(sbyte(p)) == 0 { return 0; }
    while is_alnum(sbyte(p)) == 1 { p = p + 1; }
    while sbyte(p) == 32 { p = p + 1; }
    while sbyte(p) == 10 { p = p + 1; }
    while sbyte(p) == 9  { p = p + 1; }
    while sbyte(p) == 13 { p = p + 1; }
    if sbyte(p) == 40 { return 1; }
    return 0;
}

# 在**表达式位置**解析 obj.method(args)，结果留在 rax。
# 进入时：对象符号索引在 osym，当前 token 是 '.'。
fn parse_expr_method(osym: i64) -> i64 {
    next_token();
    let mname: i64 = heap + O_SCAL + 1700;
    memcpy(mname, tokbuf());
    next_token();
    expect("(");

    let t: i64 = sym_type(osym);
    let ci: i64 = 0 - 1;
    if ty_kind(t) == 2 { ci = ty_si(t); }
    else {
        if ty_kind(t) == 4 {
            let inner: i64 = ty_a(t);
            if ty_kind(inner) == 2 { ci = ty_si(inner); }
        }
    }
    if ci < 0 { return err_atp("not a class value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    # 接口值（{ obj; vt }）→ 运行时动态分派
    let ifk: i64 = if_lookup_si(ci);
    let midx: i64 = 0 - 1;
    let fsym: i64 = 0 - 1;
    if ifk >= 0 {
        midx = if_method_idx(ifk, mname);
        if midx < 0 { return err_atp("no such interface method", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    } else {
        fsym = find_method_sym(st_name(ci), mname);
        if fsym < 0 { return err_atp("no such method", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    }

    # this + 实参
    if ty_kind(t) == 2 { g_addr_sym_rax(osym); }
    else { load_sym(osym); }
    if ifk >= 0 {
        ops3(0x48, 0x8b, 0x40);
        emit1(0);                    # mov rax,[rax+0] → obj
    }
    g_push_rax();
    let na: i64 = 1;
    while tok_is(")") == 0 {
        parse_expr();
        g_push_rax();
        na = na + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return syntax_error(); }
        }
    }
    expect(")");
    if na > NARGS_MAX { return err_atp("too many arguments", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    if na > 6 { arg_spill(na); }
    if na >= 6 { g_pop_r9(); }
    if na >= 5 { g_pop_r8(); }
    if na >= 4 { g_pop_rcx(); }
    if na >= 3 { g_pop_rdx(); }
    if na >= 2 { g_pop_rsi(); }
    if na >= 1 { g_pop_rdi(); }
    if na > 6 { arg_restack(na); }
    if ifk >= 0 {
        spill_cache();
        if ty_kind(t) == 2 { g_addr_sym_rax(osym); }
        else { load_sym(osym); }
        ops3(0x48, 0x8b, 0x40);
        emit1(8);                    # mov rax,[rax+8] → vt
        ops3(0x48, 0x8b, 0x40);
        emit1(midx * 8);
        ops2(0xff, 0xd0);            # call rax
    } else {
        emit_call_patch(fsym);
    }
    if na > 6 { arg_cleanup(na); }
    R_ETY = ty_int();
    return 0;
}

var ARG_OFF:  i64 = 268435472;      # 0x10000000 + 16

# 链式方法调用：紧跟在"返回结构体的函数调用"之后。
# 进入时：对象值已在 rax（第0字段）/ rdx（第1字段），当前 token 是 '.'。
fn parse_chain_method() -> i64 {
    let ta: i64 = 268435456 + gv(K_DLEN);
    dquad(0);
    dquad(0);
    g_movabs_rsi(ta);
    ops3(0x48, 0x89, 0x06);            # mov [rsi], rax
    ops3(0x48, 0x89, 0x56);            # mov [rsi+8], rdx
    emit1(8);
    next_token();
    let mname: i64 = heap + O_SCAL + 1700;
    memcpy(mname, tokbuf());
    next_token();
    expect("(");

    # 类型从**被调用函数的返回类型**取：链式时没有变量符号可查
    let ci: i64 = ty_si(R_ETY);
    let fsym: i64 = find_method_sym(st_name(ci), mname);
    if fsym < 0 { return err_atp("no such method", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }

    # this = 临时槽地址
    g_movabs_rax(ta);
    g_push_rax();
    let na: i64 = 1;
    while tok_is(")") == 0 {
        parse_expr();
        g_push_rax();
        na = na + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return syntax_error(); }
        }
    }
    expect(")");
    if na > NARGS_MAX { return err_atp("too many arguments", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    if na > 6 { arg_spill(na); }
    if na >= 6 { g_pop_r9(); }
    if na >= 5 { g_pop_r8(); }
    if na >= 4 { g_pop_rcx(); }
    if na >= 3 { g_pop_rdx(); }
    if na >= 2 { g_pop_rsi(); }
    if na >= 1 { g_pop_rdi(); }
    if na > 6 { arg_restack(na); }
    emit_call_patch(fsym);
    if na > 6 { arg_cleanup(na); }
    R_ETY = ty_int();
    return 0;
}

fn arg_addr() -> i64 {
    ops2(0x49, 0xbb);               # movabs r11, ARG_OFF
    emit8(ARG_OFF);
    return 0;
}

fn arg_spill(na: i64) -> i64 {
    let k: i64 = na - 6;
    arg_addr();
    let j: i64 = 0;
    while j < k {
        g_pop_rax();
        let d: i64 = j * 8;
        if d > 127 {
            ops3(0x49, 0x89, 0x83); # mov [r11 + disp32], rax
            emit4(d);
        } else {
            ops3(0x49, 0x89, 0x43); # mov [r11 + disp8], rax
            emit1(d);
        }
        j = j + 1;
    }
    return 0;
}

fn arg_restack(na: i64) -> i64 {
    let k: i64 = na - 6;
    arg_addr();
    let j: i64 = 0;
    while j < k {
        let d: i64 = j * 8;
        if d > 127 {
            ops3(0x49, 0x8b, 0x83); # mov rax, [r11 + disp32]
            emit4(d);
        } else {
            ops3(0x49, 0x8b, 0x43); # mov rax, [r11 + disp8]
            emit1(d);
        }
        emit1(0x50);                # push rax
        j = j + 1;
    }
    return 0;
}

fn arg_cleanup(na: i64) -> i64 {
    let d: i64 = (na - 6) * 8;
    if d == 0 { return 0; }
    if d <= 127 {
        ops3(0x48, 0x83, 0xc4);     # add rsp, imm8
        emit1(d & 255);
        return 0;
    }
    ops3(0x48, 0x81, 0xc4);         # add rsp, imm32
    emit4(d);
    return 0;
}

# ---------------------------------------------------------------- 字符串插值
#
# print(f"共 {n} 篇")  展开为
#     print("共 "); print_i64(n); print(" 篇");
#
# **为什么只在 print 里支持**：
#   墨语言没有 AST，是边解析边发射。要把插值结果作为"值"返回，
#   需要一个目标缓冲区 + 生命周期管理，改动大得多。
#   直接展开成 print 调用序列，是最贴合现有架构的做法。
#
# **为什么用 f" 前缀而不是改普通字符串**：
#   普通字符串里的 '{' 必须保持原义（site.mo 生成的 CSS/HTML 里全是花括号），
#   截断它们会是破坏性变更。
fn emit_print_str(addr: i64) -> i64 {
    ops2(0x48, 0xbf);          # movabs rdi, imm64
    emit8(addr);
    spill_cache();
    let sym: i64 = sym_lookup_func("print");
    if sym < 0 { return die("f-string 需要: import \"io.mo\""); }
    emit_call_patch(sym);
    return 0;
}

fn emit_print_i64_call() -> i64 {
    ops3(0x48, 0x89, 0xc7);    # mov rdi, rax
    spill_cache();
    let sym: i64 = sym_lookup_func("print_i64");
    if sym < 0 { return die("f-string 需要: import \"io.mo\""); }
    emit_call_patch(sym);
    return 0;
}

# 按**表达式的类型**分派：i64 走 print_i64，字符串（ptr to byte）走 print。
#
# 判据：ty_kind(t) == 4（ptr）且 ty_a(t) == 2（byte）。
#
# ⚠️ 是 `ty_a(t) == 2`，不是 `ty_kind(ty_a(t)) == 2`。
#   ty_int()/ty_byte()/ty_void() 返回的是**裸 id**（0/2/1），
#   不是 ty_new 出来的类型对象 —— 对它们调 ty_kind 读的是
#   类型表第 N 号槽的内容，是垃圾。
#   第一版就是这么错的：字符串变量被判成 i64，打印出地址数值。
fn emit_print_val() -> i64 {
    let t: i64 = R_ETY;
    let isstr: i64 = 0;
    if ty_kind(t) == 4 {
        if ty_a(t) == 2 { isstr = 1; }
    }
    ops3(0x48, 0x89, 0xc7);    # mov rdi, rax
    spill_cache();
    let sym: i64 = 0;
    if isstr == 1 { sym = sym_lookup_func("print"); }
    else { sym = sym_lookup_func("print_i64"); }
    if sym < 0 { return die("f-string 需要: import \"io.mo\""); }
    emit_call_patch(sym);
    return 0;
}

# sfmt(dst, f"...") —— 插值**写入目标缓冲**而不是打印
#
#   sfmt(&b, f"共 {n} 篇")
#   展开为：strcat(&b, "共 "); strcat_i64(&b, n); strcat(&b, " 篇");
#
# 目标（第一个实参）在进入时就已压栈；每个片段要把 dst 重新
# pop 出来 —— 因为 strcat 会破坏 rax，而且它要的是 rdi。
#
# 需要 import "str.mo"。
fn emit_sfmt_str(addr: i64) -> i64 {
    ops2(0x48, 0xbe);          # movabs rsi, imm64（src = 字面量地址）
    emit8(addr);
    g_pop_rdi();               # dst
    g_push_rdi();              # 留着给下一段
    spill_cache();
    let sym: i64 = sym_lookup_func("strcat");
    if sym < 0 { return die("sfmt 需要: import \"str.mo\""); }
    emit_call_patch(sym);
    return 0;
}

fn emit_sfmt_val() -> i64 {
    g_pop_rdi();               # dst
    ops3(0x48, 0x89, 0xc6);    # mov rsi, rax（第一个参数已在 rax）
    g_push_rdi();
    spill_cache();
    let t: i64 = R_ETY;
    let isstr: i64 = 0;
    if ty_kind(t) == 4 {
        if ty_a(t) == 2 { isstr = 1; }
    }
    let sym: i64 = 0;
    if isstr == 1 { sym = sym_lookup_func("strcat"); }
    else { sym = sym_lookup_func("strcat_i64"); }
    if sym < 0 { return die("sfmt 需要: import \"str.mo\""); }
    emit_call_patch(sym);
    return 0;
}

fn parse_sfmt_fmt() -> i64 {
    let more: i64 = 1;
    while more == 1 {
        if gv(K_TKIND) != 5 { CALLD = CALLD - 1; return syntax_error(); }
        emit_sfmt_str(gv(K_TIVAL));
        let fend: i64 = gv(K_FEND);
        next_token();
        if fend == 0 { more = 0; }
        else {
            if tok_is("{") == 0 { CALLD = CALLD - 1; return syntax_error(); }
            next_token();
            parse_expr();
            emit_sfmt_val();
            if tok_is("}") == 0 { CALLD = CALLD - 1; return syntax_error(); }
            sv(K_FPOS, gv(K_POS));
            sv(K_FMODE, 1);
            next_token();
            if gv(K_TKIND) != 5 { CALLD = CALLD - 1; return syntax_error(); }
        }
    }
    expect(")");
    g_pop_rax();               # 弹出 dst，丢弃
    g_zero_rax();
    CALLD = CALLD - 1;
    return 0;
}

fn parse_print_fmt() -> i64 {
    let more: i64 = 1;
    while more == 1 {
        if gv(K_TKIND) != 5 { CALLD = CALLD - 1; return syntax_error(); }
        emit_print_str(gv(K_TIVAL));
        let fend: i64 = gv(K_FEND);
        next_token();
        if fend == 0 { more = 0; }
        else {
            if tok_is("{") == 0 { CALLD = CALLD - 1; return syntax_error(); }
            next_token();
            parse_expr();
            emit_print_val();
            if tok_is("}") == 0 { CALLD = CALLD - 1; return syntax_error(); }
            # '}' 之后紧跟着就是下一段内容（中间没有引号），
            # 所以先把扫描位置指到 '}' 之后、切回片段模式，再读。
            # gv(K_POS) 此时已经是 '}' 的下一个字符。
            sv(K_FPOS, gv(K_POS));
            sv(K_FMODE, 1);
            next_token();
            # 下一个 token 应该是 f 片段（K_FMODE 仍为 1，引号会走片段模式）
            if gv(K_TKIND) != 5 { CALLD = CALLD - 1; return syntax_error(); }
        }
    }
    expect(")");
    CALLD = CALLD - 1;
    return 0;
}

fn parse_call() -> i64 {
    CALLD = CALLD + 1;
    memcpy(cscratch(), scratch1());
    CE_P = gv(K_PPOS);
    CE_C = gv(K_PCOL);
    CE_L = gv(K_PLINE);
    expect("(");
    # print(f"...") / sfmt(dst, f"...") —— 插值字符串特判
    if streq(cscratch(), "print") == 1 {
        if gv(K_TKIND) == 5 { return parse_print_fmt(); }
    }
    if streq(cscratch(), "sfmt") == 1 {
        # 第一个参数是目标缓冲（表达式），第二个必须是 f-string
        parse_expr();
        g_push_rax();
        if accept(",") == 0 { CALLD = CALLD - 1; return syntax_error(); }
        if gv(K_TKIND) != 5 { CALLD = CALLD - 1; return syntax_error(); }
        let r: i64 = parse_sfmt_fmt();
        return r;
    }
    let na: i64 = 0;
    while tok_is(")") == 0 {
        parse_expr();
        g_push_rax();
        na = na + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { CALLD = CALLD - 1; return syntax_error(); }
        }
    }
    expect(")");
    if streq(cscratch(), "load8") == 1 {
        g_pop_rax();
        ops3(0x0f, 0xb6, 0x00);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "load64") == 1 {
        g_pop_rax();
        ops3(0x48, 0x8b, 0x00);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "store8") == 1 {
        g_pop_rbx();
        g_pop_rcx();
        ops2(0x88, 0x19);
        g_zero_rax();
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "store64") == 1 {
        g_pop_rbx();
        g_pop_rcx();
        ops3(0x48, 0x89, 0x19);
        g_zero_rax();
        CALLD = CALLD - 1;
        return 0;
    }
    # v1.213 内建 atomic_cas(p, exp, des) -> i64（0/1）：
    #   lock cmpxchg [p], des —— x86 freestanding 无 libc 也能用真原子。
    #   栈序（后推先弹）：p 最先推 → 弹序 des(rbx) exp(rcx) p(rdx)。
    # v1.228 内建 call2(f, a, b)：函数指针间接调用（2 参）。栈序 f a b
    #   → 弹序 b(rsi) a(rdi) f(rax) → call rax。
    if streq(cscratch(), "call2") == 1 {
        g_pop_rsi();
        g_pop_rdi();
        emit1(0x58);                      # pop rax = f
        ops2(0xff, 0xd0);                 # call rax
        CALLD = CALLD - 1;
        return 0;
    }
    # v1.229 call0/1/3 家族：
    #   call0(f)          —— 无参
    #   call1(f, a)       —— a→rdi
    #   call3(f, a, b, c) —— a→rdi b→rsi c→rdx
    if streq(cscratch(), "call0") == 1 {
        # 🔴 栈顶缓存:f 可能还挂在 rbx(K_CRBX=1)——必须先 spill 落栈再 pop
        #    （g_pop_rax 自带 spill，但这里手动 emit 必须 spill_cache() 领路）。
        spill_cache();
        emit1(0x58);                      # pop rax = f
        ops2(0xff, 0xd0);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "call1") == 1 {
        g_pop_rdi();
        emit1(0x58);
        ops2(0xff, 0xd0);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "call3") == 1 {
        g_pop_rdx();
        g_pop_rsi();
        g_pop_rdi();
        emit1(0x58);
        ops2(0xff, 0xd0);
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "atomic_cas") == 1 {
        g_pop_rbx();                      # des
        g_pop_rcx();                      # exp
        emit1(0x5a);                      # pop rdx = p
        ops3(0x48, 0x89, 0xc8);           # mov rax, rcx
        ops4(0xf0, 0x48, 0x0f, 0xb1);     # lock cmpxchg
        emit1(0x1a);                      # [rdx], rbx
        ops3(0x0f, 0x94, 0xc0);           # sete al
        ops4(0x48, 0x0f, 0xb6, 0xc0);     # movzx rax, al
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "syscall") == 1 {
        if na >= 7 { g_pop_r9(); }
        if na >= 6 { g_pop_r8(); }
        if na >= 5 { g_pop_r10(); }
        if na >= 4 { g_pop_rdx(); }
        if na >= 3 { g_pop_rsi(); }
        if na >= 2 { g_pop_rdi(); }
        g_pop_rax();
        g_syscall();
        CALLD = CALLD - 1;
        return 0;
    }
    if streq(cscratch(), "syscall") == 0 {
        if streq(cscratch(), "load8") == 0 {
            if streq(cscratch(), "load64") == 0 {
                if streq(cscratch(), "store8") == 0 {
                    if streq(cscratch(), "store64") == 0 {
                        R_SYM = sym_lookup_func(cscratch());
                        if R_SYM >= 0 {
                            let npv: i64 = sym_npar(R_SYM);
                            if npv >= 0 {
                                if npv != na {
                                    return err_atp("wrong number of arguments", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                                }
                            } else {
                                # 变参（extern ...）：只查下界
                                if na < 0 - (npv + 1) {
                                    return err_atp("too few arguments for variadic call", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if na > NARGS_MAX {
        CALLD = CALLD - 1;
        return err_atp("too many arguments (limit 32)", CE_L, CE_C, CE_P);
    }
    if na > 6 { arg_spill(na); }
    if na >= 6 { g_pop_r9(); }
    if na >= 5 { g_pop_r8(); }
    if na >= 4 { g_pop_rcx(); }
    if na >= 3 { g_pop_rdx(); }
    if na >= 2 { g_pop_rsi(); }
    if na >= 1 { g_pop_rdi(); }
    if na > 6 { arg_restack(na); }
    R_SYM = sym_lookup_func(cscratch());
    # 不能先 `CALLD = CALLD - 1` 再取名字：cscratch() 是
    # heap + O_SCR + CALLD*256，CALLD 一减就指向**上一层调用**的槽，
    # 里面是空的 —— 这正是当初报出 `undefined symbol ''` 的根因。
    # 这里反正要 exit，不减也无所谓。
    if R_SYM < 0 { return undef_call(); }
    emit_call_patch(R_SYM);
    if na > 6 { arg_cleanup(na); }
    # 返回值类型：让调用方知道它拿到的是什么。
    # 结构体/指针返回如果一律当成 i64，sfmt 会把字符串当数字打印
    # （只能靠 ptr(v) 绕过 —— 有了这个就不用了）。
    R_ETY = load64(heap + O_SRT + R_SYM * 8);
    R_SADDR = 0;
    CALLD = CALLD - 1;
    return 0;
}
