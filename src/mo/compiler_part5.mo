
# ==========================================================================
#  语句
# ==========================================================================
# v1.1060: struct 字段默认值表 —— SDV[si*64+fi] 值, SDH[si*64+fi] 存在标志。
# 必须定义在所有使用点（parse_let/parse_struct）之前。
var SDV: [16384] i64 = 0;
var SDH: [16384] i64 = 0;

fn parse_block(d: i64) -> i64 {
    let prev: i64 = gv(K_DEPTH);
    sv(K_DEPTH, d);
    expect("{");
    while tok_is("}") == 0 {
        parse_stmt();
    }
    next_token();
    if gv(K_WARN) == 1 {
        warn_unused(d);
    }
    sym_pop_scope(d);
    sv(K_DEPTH, prev);
    return 0;
}

# break / continue：跳到当前循环的出口 / 循环头
fn parse_break() -> i64 {
    expect(";");
    let l: i64 = loop_brk();
    if l < 0 { return err_atp("break outside of a loop", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    emit_jmp(l);
    return 0;
}

fn parse_continue() -> i64 {
    expect(";");
    # 🔴 switch 也会压一层循环栈（为了让 break 能跳出 switch），但它的
    #    cnt 传的是 -1，表示"这层不是循环"。continue 必须**往下跳过**
    #    这类层：C 的语义是 switch 里的 continue 作用于外层循环，
    #    而如果直接取栈顶，continue 会跳到 switch 出口（语义错），
    #    或者因为 cnt=-1 被当成"不在循环里"而报错（更迷惑）。
    let i: i64 = gv(K_LTOP);
    while i > 0 {
        let c: i64 = load64(heap + O_LSTK + (i - 1) * 24);
        if c >= 0 {
            let s: i64 = load64(heap + O_LSTK + (i - 1) * 24 + 16);
            if s >= 0 { emit_jmp(s); return 0; }
            emit_jmp(c);
            return 0;
        }
        i = i - 1;
    }
    return err_atp("continue outside of a loop", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
}

# 复合赋值运算符识别与运算分发。
# 编码：1=+ 2=- 3=* 4=/ 5=% 6=& 7=| 8=^
fn compound_op() -> i64 {
    if tok_is("+=") == 1 { return 1; }
    if tok_is("-=") == 1 { return 2; }
    if tok_is("*=") == 1 { return 3; }
    if tok_is("/=") == 1 { return 4; }
    if tok_is("%=") == 1 { return 5; }
    if tok_is("&=") == 1 { return 6; }
    if tok_is("|=") == 1 { return 7; }
    if tok_is("^=") == 1 { return 8; }
    # <<= >>= 是三字符 token，词法必须单独识别，
    # 否则会被切成 "<" 与 "<="，解析必然失败
    if tok_is("<<=") == 1 { return 9; }
    if tok_is(">>=") == 1 { return 10; }
    if tok_is("&&=") == 1 { return 11; }
    if tok_is("||=") == 1 { return 12; }
    return 0;
}

# 此刻 rax = 右操作数，rcx = 左操作数（变量原值）。
# 直接复用二元运算的那套 g_* 函数，所以语义与 x = x OP e 完全一致，
# 包括不可交换的减法和除法。
# 复合赋值的常量除数识别。
#
# 🔴 必须在 g_pop_rcx() **之前**读取 K_LAST/K_LASTV：g_pop_rcx 会清掉 last。
#    （seed 侧为此专门准备了 pow2d 全局，注释里也写了这一点。）
#
# 返回 k >= 0  → 除数是 2^k，走 g_div_pow2
# 返回 d != 0  → 除数是任意常量，走 g_div_magic
# 两者都不满足 → 退回 idiv
fn cmpdiv_k() -> i64 {
    if gv(K_LAST) != 1 { return 0 - 1; }
    return pow2_exp(gv(K_LASTV));
}
fn cmpdiv_d() -> i64 {
    if gv(K_LAST) != 1 { return 0; }
    let v: i64 = gv(K_LASTV);
    if pow2_exp(v) >= 0 { return 0; }
    if magic_ok(v) == 1 { return v; }
    return 0;
}

fn g_compound(op: i64, d: i64, k: i64) -> i64 {
    if op == 1 { g_add(); return 0; }
    if op == 2 { g_sub(); return 0; }
    if op == 3 { g_imul(); return 0; }
    if op == 4 {
        if k >= 0 { g_div_pow2(0, k); return 0; }
        if d != 0 { g_div_magic(0, d); return 0; }
        g_idiv(0); return 0;
    }
    if op == 5 {
        if k >= 0 { g_div_pow2(1, k); return 0; }
        if d != 0 { g_div_magic(1, d); return 0; }
        g_idiv(1); return 0;
    }
    if op == 6 { g_and(); return 0; }
    if op == 7 { g_or(); return 0; }
    if op == 8 { g_xor(); return 0; }
    if op == 9 { g_shl(); return 0; }
    if op == 10 { g_sar(); return 0; }
    if op == 11 { g_and(); return cmp_lg(11); }
    if op == 12 { g_or(); return cmp_lg(12); }
    return 0;
}

# v1.1072: 逻辑复合赋值 &&= ||＝ —— 布尔短路语义，但左值是简单变量
#（无副作用），退化为 a = a && b：与常规 compound 相同的 push/pop 流程，
# 只是运算走短路表达式原语（g_cmp_rax_0 + 布尔化）。
fn cmp_lg(op: i64) -> i64 {
    # rax=右值 rcx=左原值（由 compound 主路径 push/pop 传入——cmp_lg 内先
    # 自己重算：此 fn 在 rax=右值、栈顶=左原值 时被调？见调用点约定）
    # 约定：rax = 左&&右 / 左||右 的**位运算结果**之前——这里只做布尔化：
    # 若 (op==11: rax 已= and 结果；op==12: or 结果) → cmp rax,0 → 0/1 模板
    let lz: i64 = new_label();
    let le: i64 = new_label();
    g_cmp_rax_0();
    emit_jcc(0x84, lz);      # je → 结果 0
    g_movabs_rax(1);
    emit_jmp(le);
    place_label(lz);
    g_movabs_rax(0);
    place_label(le);
    return 0;
}

# 尝试解析 `obj.method(args);` 语句。
# 进入时：obj 名在 oname（scratch2），当前 token 是 '.'。
# 返回 1 = 已处理（含 expect(";")），0 = 不是方法调用，调用方回退。
# 在符号表里找 "Class_method"。
#
# **为什么不能用 method_find（方法表）**：方法登记已经被移除了
# —— 现在方法的函数名就是 Class_method 整体（见 parse_func 里的注释：
# "原先的 method_reg 会让编译器段错误"）。所以只能查符号表。
#
# **为什么不能拼字符串再 sym_lookup**：compiler.mo 是用 **seed** 编译的，
# seed 不支持局部数组、ptr 变量、一元 &，做不了字符串拼接。
#
# **解法**：不拼接，改成**两段逐字节比较** —— 先看符号名是否以类名
# 开头、紧接着是不是下划线，再比剩下部分是否等于方法名。全程只用到
# 字节读和 streq，seed 完全支持。
fn find_method_sym(cls: i64, m: i64) -> i64 {
    let cl: i64 = strlen(cls);
    let i: i64 = gv(K_NSYM);
    while i > 0 {
        i = i - 1;
        if sym_kind(i) == 0 {
            let nm: i64 = name_at(i);
            let ok: i64 = 1;
            let j: i64 = 0;
            while j < cl {
                if load8(nm + j) != load8(cls + j) { ok = 0; }
                j += 1;
            }
            if ok == 1 {
                if load8(nm + cl) == 95 {
                    if streq(nm + cl + 1, m) == 1 { return i; }
                }
            }
        }
    }
    return 0 - 1;
}

# 预扫描：当前 token 是 '.' 时，判断后面是不是 `标识符 (`。
#
# **为什么必须预扫描**：
#   第一版先 next_token 再判断，失败时用 set_pos 回退。但
#   `self.w = a;` 这种**字段赋值**同样以 `ident .` 开头，
#   回退后 token 流已被 next_token 推进过，解析错位 → syntax error。
#   实测 69_class.mo 直接编译失败。
#
#   纯读字节、不碰任何状态，就不需要回退。
fn peek_method_call() -> i64 {
    let p: i64 = gv(K_POS);              # '.' 之后
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

fn parse_method_stmt(oname: i64) -> i64 {
    next_token();                      # 吃掉 '.'
    # ⚠️ 不能用 O_SCR + 4096：O_SCR 是调用名栈（CALLD*256），
    # 往后 4096 已经越过该区域，写进去会破坏别的数据 —— 实测段错误。
    # 用 O_SCAL 里的独立槽（避开 400/700/1000/128+tokbuf/1400/3000）。
    let mname: i64 = heap + O_SCAL + 1600;
    memcpy(mname, tokbuf());
    next_token();                      # 吃掉方法名，现在应是 '('
    expect("(");

    let sy: i64 = sym_lookup(oname);
    if sy < 0 { return undef_err(oname); }
    let t: i64 = sym_type(sy);
    # 只支持结构体值与其指针：取类的结构体索引
    let ci: i64 = 0 - 1;
    if ty_kind(t) == 2 { ci = ty_si(t); }
    else {
        if ty_kind(t) == 4 {
            let inner: i64 = ty_a(t);
            if ty_kind(inner) == 2 { ci = ty_si(inner); }
        }
    }
    if ci < 0 {
        # v1.1074: 非结构体接收者回退 —— 库自由函数作方法：
        # s.trim() → str_trim(s)，s.split(",") → str_split(s, ",")
        # 条件：接收者变量 kind1（栈变量）且函数存在。
        let ff: i64 = sym_lookup_func(mname);
        if ff < 0 {
            # v1.1074: trim → str_trim（str 库函数命名约定 str_ 前缀）
            memcpy(heap + O_SCAL + 5900, heap + O_SCAL + 4700);  # "str_" 放头部？直接拼
            # 拼 "str_" + mname 到 5900 槽
            let q: i64 = heap + O_SCAL + 5900;
            store8(q + 0, 115); store8(q + 1, 116); store8(q + 2, 114); store8(q + 3, 95);
            memcpy(q + 4, mname);
            ff = sym_lookup_func(q);
            if ff < 0 {
                # 特例别名：contains → strstr
                if streq(mname, "contains") == 1 { ff = sym_lookup_func("strstr"); }
            }
        }        if ff < 0 { return err_atp("not a class value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        load_sym(sy);                 # str 变量的值就是地址
        g_push_rax();
        let na: i64 = 1;
        while tok_is(")") == 0 {
            parse_expr();
            g_push_rax();
            na += 1;
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
        spill_cache();
        emit_call_patch(ff);
        return 0;
    }
    # 接口值的动态分派：接口就是 { obj; vt } 两字段结构体
    let ifk: i64 = if_lookup_si(ci);
    let midx: i64 = 0 - 1;
    let fsym: i64 = 0 - 1;
    if ifk >= 0 {
        midx = if_method_idx(ifk, mname);
        if midx < 0 {
            return err_atp("no such interface method", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
    } else {
        fsym = find_method_sym(st_name(ci), mname);
        if fsym < 0 {
            return err_atp("no such method", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
    }

    # this：结构体变量取地址（lea/绝对地址），指针变量直接取值
    if ty_kind(t) == 2 { g_addr_sym_rax(sy); }
    else { load_sym(sy); }
    if ifk >= 0 {
        ops3(0x48, 0x8b, 0x40);
        emit1(0);                 # mov rax,[rax+0]  → obj
    }
    g_push_rax();
    # ⚠️ 这里不能再 expect("(")：'(' 在前面已经消费过了。
    # 第一版照抄 parse_call 结构留了第二个 expect("(")，
    # 于是零参方法调用时它把 ')' 当 '(' 期望 —— 报错正指向 ')' 那一列。
    let na: i64 = 1;
    while tok_is(")") == 0 {
        parse_expr();
        g_push_rax();
        na += 1;
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
        # 间接调用：rax = [[s+8] + midx*8]，然后 call rax
        #
        # 🔴 必须等参数都弹出**之后**再取函数地址：g_pop_rdi 等只改
        #    参数寄存器，不动 rax，所以顺序上取地址放在最后也没问题；
        #    反过来先取再弹的话，push/pop 会把地址压进栈里当参数。
        spill_cache();
        if ty_kind(t) == 2 { g_addr_sym_rax(sy); }
        else { load_sym(sy); }
        ops3(0x48, 0x8b, 0x40);
        emit1(8);                 # mov rax,[rax+8]  → vt
        ops3(0x48, 0x8b, 0x40);
        emit1(midx * 8);          # mov rax,[rax+midx*8]
        ops2(0xff, 0xd0);         # call rax
    } else {
        emit_call_patch(fsym);
    }
    if na > 6 { arg_cleanup(na); }
    expect(";");
    return 1;
}

# 嵌套函数。
#
# 代码**就地发射**在外层函数体中间，外层用一条 jmp 跳过去 ——
# 于是嵌套函数的入口地址就是外层函数代码里的某个位置，调用它跟调用
# 普通函数没区别（predeclare 扫源码里的 "fn " 时已经把它登记了）。
#
# 捕获靠静态链：被调用时 [rbp] 就是调用者的帧指针。本实现支持深度 1，
# 即嵌套函数只能从**直接外层**调用（不能当作回调传出去再调）。
fn parse_nested_fn() -> i64 {
    # 捕获只支持一层：[rbp] 是调用者的帧指针，直接就是外层。
    # 再深一层需要 [[rbp]] 的静态链，未实现 —— 明确报错，
    # 否则会静默地按一层去解引用，读到完全无关的栈内容。
    if load64(heap + O_NEST) >= 8 {
        return err_at2("nested functions too deep (max 8)", gv(K_LINE), gv(K_COL));
    }
    let l: i64 = new_label();
    emit_jmp(l);
    # 🔴 必须**逐个保存并恢复**函数级状态，再调用 parse_func。
    #    parse_func 会重置 K_CUROFF（局部偏移）和 K_FPATCH（`sub rsp,N`
    #    的回填位置）—— 嵌套函数解析完，外层的这两个槽已被改成嵌套函数的。
    #    于是外层的 `sub rsp,N` 永远停在占位值 0：栈帧一个字节都没预留，
    #    后面的 push / call 直接把返回地址写到局部变量的槽上。
    #
    #    症状极难归因：外层函数**看起来完全正常**（局部变量偏移是对的），
    #    只是被捕获的变量读出来是返回地址那个数量级的巨大数值。
    # 🔴 K_FNBASE 必须一并保存：它是 cap_depth 判定"当前层局部变量"的下界。
    #    解析完嵌套函数后它停留在嵌套函数的基线上，若不恢复，外层后续引用
    #    自己的局部变量会被误判成捕获 → 生成 [外层rbp+off] 去读，
    #    值完全不对但**不报错**（一层时 NEST==0 恰好绕过了这条路径，
    #    所以这个坑要到支持两层才会显形）。
    let fb:  i64 = gv(K_FNBASE);
    let of:  i64 = gv(K_CUROFF);
    let fp:  i64 = gv(K_FPATCH);
    let hr:  i64 = gv(K_HASRET);
    let dp:  i64 = gv(K_DEPTH);
    let lt:  i64 = gv(K_LTOP);
    let cb:  i64 = gv(K_CRBX);
    let cf:  i64 = gv(K_CURFN);
    let nd:  i64 = gv(K_NDF);
    let el:  i64 = load64(heap + O_ERRLAB);
    store64(heap + O_NEST, load64(heap + O_NEST) + 1);
    parse_func();
    store64(heap + O_NEST, load64(heap + O_NEST) - 1);
    sv(K_FNBASE, fb);
    sv(K_CUROFF, of);
    sv(K_FPATCH, fp);
    sv(K_HASRET, hr);
    sv(K_DEPTH, dp);
    sv(K_LTOP, lt);
    sv(K_CRBX, cb);
    sv(K_CURFN, cf);
    sv(K_NDF, nd);
    store64(heap + O_ERRLAB, el);
    place_label(l);
    return 0;
}

fn parse_stmt() -> i64 {
    dbg_mark();
    # v1.1047: 裸块语句 { ... }（case 体花括号等）—— 复用 parse_block
    if tok_is("{") == 1 {
        let bd: i64 = gv(K_DEPTH) + 1;
        return parse_block(bd);
    }
    if accept("break") == 1 { return parse_break(); }
    if accept("continue") == 1 { return parse_continue(); }
    if accept("let") == 1 { return parse_let(); }
    # 局部 const 声明（v1.989）：parse_const 自己消费首 token，
    # 这里只判断不消费
    if tok_is("const") == 1 { return parse_const(); }
    # v1.1116: 语句级 enum 声明（局部枚举，常量注册进全局 enum 表）
    if tok_is("enum") == 1 {
        parse_enum();
        accept(";");
        return 0;
    }
    if accept("if") == 1 { return parse_if(); }
    if accept("while") == 1 { return parse_while(); }
    # v1.1071: do { ... } while (cond); —— 先执行后判（continue → cond）
    if accept("do") == 1 { return parse_do_while(); }
    if accept("for") == 1 { return parse_for(); }
    # switch / case / default / fallthrough 都是**上下文关键字**：
    # 只在语句起始位置识别 switch，case 等只在 switch 主体里识别。
    # 于是库里那些叫 case 的变量、注释里的 "case" 都不受影响。
    if accept("switch") == 1 { return parse_switch(); }
        if gv(K_TKIND) == 1 && streq(tokbuf(), "match") == 1 {
        # match 是上下文关键字：若后面是 '='（变量赋值）则当标识符放行
        let mpk: i64 = gv(K_TOKPOS);
        next_token();
        if tok_is("=") == 1 { set_back(mpk); }
        else { set_back(mpk); return parse_match(); }
    }
    if accept("return") == 1 { return parse_return(); }
    # 嵌套函数（闭包）：定义在函数体内，可捕获外层的局部变量
    if tok_is("fn") == 1 { return parse_nested_fn(); }
    if gv(K_TKIND) == 1 {
        memcpy(scratch2(), tokbuf());
        let save: i64 = gv(K_TOKPOS);
        next_token();
        if tok_is("++") == 1 {
            next_token();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let it: i64 = sym_type(R_SYM);
            if ty_kind(it) == 3 { return err_atp("cannot increment an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(it) == 2 { return err_atp("cannot increment a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_add();
            store_sym(R_SYM);
            return 0;
        }
        # v1.1129: 多重赋值 a, b = e1, e2 —— 先全部右值求值到临时槽，
        # 再逐个写入左边（避免 a, b = b, a 顺序污染）。
        if tok_is(",") == 1 {
            let mna: i64 = heap + O_SCAL + 4400;
            memcpy(mna, scratch2());
            let mns: [8] i64;
            let mno: [8] i64;
            let mnt: [8] i64;
            let mnc: i64 = 0;
            let msy: i64 = sym_lookup(mna);
            if msy < 0 { return undef_err(mna); }
            mns[0] = msy;
            mnt[0] = sym_type(msy);
            if ty_kind(mnt[0]) == 3 || ty_kind(mnt[0]) == 2 { return err_at2("multi-assign: element must be scalar", gv(K_LINE), gv(K_COL)); }
            mnc = 1;
            while tok_is(",") == 1 {
                if mnc >= 8 { return err_at2("multi-assign: too many targets (max 8)", gv(K_LINE), gv(K_COL)); }
                next_token();                    # 吃 ','
                if gv(K_TKIND) != 1 { return syntax_error(); }
                memcpy(scratch3(), tokbuf());
                let msy2: i64 = sym_lookup(scratch3());
                if msy2 < 0 { return undef_err(scratch3()); }
                mns[mnc] = msy2;
                mnt[mnc] = sym_type(msy2);
                if ty_kind(mnt[mnc]) == 3 || ty_kind(mnt[mnc]) == 2 { return err_at2("multi-assign: element must be scalar", gv(K_LINE), gv(K_COL)); }
                mnc = mnc + 1;
                next_token();
            }
            expect("=");
            # 右值全部求值到临时槽（先于任何写入）
            let mri: i64 = 0;
            let mrv: [8] i64;
            while mri < mnc {
                let mto: i64 = gv(K_CUROFF);
                sv(K_CUROFF, mto - 8);
                parse_expr();
                spill_cache();
                g_store_local(mto);
                mrv[mri] = mto;
                mri = mri + 1;
                if mri < mnc { expect(","); }
            }
            expect(";");
            # 逐个写入
            mri = 0;
            while mri < mnc {
                g_load_local(mrv[mri]);
                spill_cache();
                R_SYM = mns[mri];
                store_sym(R_SYM);
                mri = mri + 1;
            }
            return 0;
        }
        # obj.method(args) 作为**语句**：r.set(5, 6);
        #
        # ⚠️ 必须在 parse_primary 之外（语句层）处理。
        # 之前放在 parse_primary 里会破坏 token 流：parse_call 消耗了
        # 右括号之后的 token，调用方再检查 `tok_is("=")` 判断
        # "赋值还是表达式语句"时位置已经不对，于是后续 `let a = ...`
        # 的符号注册丢失。
        # 放在语句层就没有这个问题：语句边界本身就是这里确定的。
        if tok_is(".") == 1 {
            if peek_method_call() == 1 { return parse_method_stmt(scratch2()); }
        }
        if tok_is("--") == 1 {
            next_token();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let dt: i64 = sym_type(R_SYM);
            if ty_kind(dt) == 3 { return err_atp("cannot decrement an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(dt) == 2 { return err_atp("cannot decrement a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_sub();
            store_sym(R_SYM);
            return 0;
        }
        if compound_op() > 0 {
            let cop: i64 = compound_op();
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let clt: i64 = sym_type(R_SYM);
            if ty_kind(clt) == 3 { return err_atp("cannot assign to an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            if ty_kind(clt) == 2 { return err_atp("cannot assign a struct value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            # 先取原值入栈当作左操作数，再算右操作数，最后运算并存回
            load_sym(R_SYM);
            g_push_rax();
            parse_expr();
            expect(";");
            let cdv: i64 = 0;
            let cdk: i64 = 0 - 1;
            if cop == 4 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
            if cop == 5 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
            g_pop_rcx();
            # 🔴 str 的 '+=' 必须是**拼接**，不能走 g_compound → g_add。
            #    两个字符串地址相加在机器层面完全"合法"：
            #    实测 `s += "cd"` 之后 print 直接段错误（exit 139）；
            #    而如果相加结果恰好落在已映射内存里，就会**静默**给出
            #    一个偏移后的串，不报错也不崩。两种情况都必须挡住。
            if ty_kind(clt) == 10 {
                if cop != 1 {
                    return err_at2("str 只支持 '+='", gv(K_LINE), gv(K_COL));
                }
                if ty_kind(R_ETY) != 10 {
                    return err_at2("'+=': str 只能拼 str", gv(K_LINE), gv(K_COL));
                }
                if g_str_cat() != 0 { return -1; }
            } else {
                if ty_kind(R_ETY) == 10 {
                    return err_at2("'+=': 非 str 不能拼 str", gv(K_LINE), gv(K_COL));
                }
                g_compound(cop, cdv, cdk);
            }
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("=") == 1 {
            next_token();
            # v1.1054: p = P { x: 1; y: 2; }; —— 字面量整体赋值。
            # 探测 ident+'{' 且 ident 是 struct：字段逐一直接 store
            # 到变量地址（语句层，变量可能是局部或全局，load_sym 前）。
            if gv(K_TKIND) == 1 {
                let lsiS: i64 = st_lookup(tokbuf());
                if lsiS >= 0 {
                    let svpS: i64 = gv(K_TOKPOS);
                    next_token();
                    if tok_is("{") == 1 {
                        R_SYM = sym_lookup(scratch2());
                        if R_SYM < 0 { return undef_err(scratch2()); }
                        let ltS: i64 = sym_type(R_SYM);
                        if ty_kind(ltS) != 2 { return err_at2("struct literal assigned to non-struct", gv(K_LINE), gv(K_COL)); }
                        let siS: i64 = ty_si(ltS);
                        if siS != lsiS { return err_at2("struct assignment requires the same type", gv(K_LINE), gv(K_COL)); }
                        g_addr_sym_rax(R_SYM);
                        next_token();   # 吃 '{'（探测已消费 struct 名）
                        while tok_is("}") == 0 {
                            if gv(K_TKIND) != 1 { return syntax_error(); }
                            let fniS: i64 = 0 - 1;
                            let fiS: i64 = 0;
                            while fiS < st_nfields(siS) {
                                if streq(tokbuf(), st_field_name(siS, fiS)) == 1 { fniS = fiS; }
                                fiS = fiS + 1;
                            }
                            if fniS < 0 { return err_at2("struct literal: no such field", gv(K_LINE), gv(K_COL)); }
                            next_token();
                            expect(":");
                            g_movabs_rsi(sym_addr(R_SYM) + st_field_off(siS, fniS));
                            parse_expr();
                            expect(";");
                            spill_cache();
                            g_pop_rcx();
                            ops3(0x48, 0x89, 0x06);   # mov [rsi], rax
                            accept(",");
                        }
                        next_token();   # 吃 '}'
                        expect(";");
                        R_ETY = ltS;
                        return 0;
                    } else {
                        set_back(svpS);
                    }
                }
            }
            # 预读右边是否为「单个标识符」。结构体整体赋值需要右边的地址，
            # 所以只支持 标识符 = 标识符；其它形状仍然报错。
            let rhs: i64 = -1;
            if gv(K_TKIND) == 1 {
                memcpy(scratch3(), tokbuf());
                let save2: i64 = gv(K_TOKPOS);
                next_token();
                if tok_is(";") == 1 { rhs = sym_lookup(scratch3()); }
                set_back(save2);
            }
            parse_expr();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let lt: i64 = sym_type(R_SYM);
            if ty_kind(lt) == 3 {
                # v1.1078: 数组整体赋值 q = p; —— 仅支持纯 ident RHS（同型数组）
                if rhs < 0 { return err_atp("array assignment requires an array variable on the right", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                if ty_kind(sym_type(rhs)) != 3 { return err_atp("array assignment type mismatch", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                if ty_size(sym_type(rhs)) != ty_size(lt) { return err_atp("array assignment size mismatch", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                g_addr_sym_rax(R_SYM);            # rdi = 目的（q 基址）
                g_addr_sym_rsi(rhs);              # rsi = 源（p 基址）
                g_copy_words(ty_size(lt) / 8);    # 与 struct 整体赋值同款块拷贝
                return 0;
            }
            if ty_kind(lt) == 2 {
                if rhs >= 0 {
                    if ty_kind(sym_type(rhs)) == 2 {
                        if ty_si(sym_type(rhs)) == ty_si(lt) {
                            g_addr_sym_rax(R_SYM);
                            g_addr_sym_rsi(rhs);
                            # 拷贝词数同样必须是 st_words：
                            # 否则嵌套结构体的后半部分字段根本没被拷过去。
                            g_copy_words(st_words(ty_si(lt)));
                            R_ETY = lt;
                            return 0;
                        }
                    }
                    return err_atp("struct assignment requires the same type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                return err_atp("cannot assign a struct value: right side must be a variable", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            if ty_compat(lt, R_ETY) == 0 { return err_atp("incompatible assignment", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("[") == 1 {
            let sy: i64 = sym_lookup(scratch2());
            if sy < 0 { return undef_err(scratch2()); }
            index_addr(sy);
            let at: i64 = elem_type(sym_type(sy));
            if tok_is(".") == 1 {
                let ft: i64 = field_chain(at);
                if ty_kind(ft) == 2 { return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL)); }
                at = ft;
            }
            if tok_is("++") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_add();
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if tok_is("--") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_sub();
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if compound_op() > 0 {
                let cop2: i64 = compound_op();
                next_token();
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                parse_expr();
                expect(";");
                let cdv: i64 = 0;
                let cdk: i64 = 0 - 1;
                if cop2 == 4 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
                if cop2 == 5 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
                g_pop_rcx();
                # str 元素的 '+=' 同样是拼接，理由见上面那条注释
                if ty_kind(at) == 10 {
                    if cop2 != 1 { return err_at2("str 只支持 '+='", gv(K_LINE), gv(K_COL)); }
                    if ty_kind(R_ETY) != 10 { return err_at2("'+=': str 只能拼 str", gv(K_LINE), gv(K_COL)); }
                    if g_str_cat() != 0 { return -1; }
                } else {
                    if ty_kind(R_ETY) == 10 { return err_at2("'+=': 非 str 不能拼 str", gv(K_LINE), gv(K_COL)); }
                    g_compound(cop2, cdv, cdk);
                }
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            g_push_rax();
            expect("=");
            # v1.1065: a[i] = P { ... }; —— 数组元素 struct 字面量整体赋值
            #（kind2 元素）：表达式求到常量区地址后整块拷贝。
            if ty_kind(at) == 2 && gv(K_TKIND) == 1 {
                let alsi: i64 = st_lookup(tokbuf());
                if alsi == ty_si(at) {
                    let alvp: i64 = gv(K_TOKPOS);
                    next_token();
                    if tok_is("{") == 1 {
                        next_token();   # 吃 '{'（探测已消费 struct 名）
                        while tok_is("}") == 0 {
                            if gv(K_TKIND) != 1 { return syntax_error(); }
                            let afni: i64 = 0 - 1;
                            let afi: i64 = 0;
                            while afi < st_nfields(alsi) {
                                if streq(tokbuf(), st_field_name(alsi, afi)) == 1 { afni = afi; }
                                afi = afi + 1;
                            }
                            if afni < 0 { return err_at2("struct literal: no such field", gv(K_LINE), gv(K_COL)); }
                            next_token();
                            expect(":");
                            sv(K_LAST, 0);
                            parse_expr();
                            expect(";");
                            spill_cache();
                            ops4(0x48, 0x8b, 0x34, 0x24);  # mov rsi,[rsp] = 元素基地址
                            if st_field_off(alsi, afni) != 0 {
                                ops2(0x48, 0x81); emit1(0xc6); emit4(st_field_off(alsi, afni));  # add rsi, off
                            }
                            ops3(0x48, 0x89, 0x06);  # mov [rsi], rax
                            accept(",");
                        }
                        emit1(0x58);        # pop rax（平衡真栈）
                        next_token();   # 吃 '}'
                        expect(";");
                        return 0;
                    }
                    set_back(alvp);
                }
            }
            parse_expr();
            expect(";");
            g_pop_rcx();
            if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
            return 0;
        }
        if tok_is(".") == 1 {
            let sy: i64 = sym_lookup(scratch2());
            if sy < 0 { return undef_err(scratch2()); }
            let ft: i64 = field_addr(sy);
            # v1.1035: r.v[i] 数组字段索引 —— 与语句层 a[i] 同构:
            # rax=数组基址(field_addr 已算好)，吃 '['，下标*宽加回，
            # 之后 ++/--/复合/= 全部照 a[i] 分支处理。
            if tok_is("[") == 1 {
                next_token();
                let at0: i64 = elem_type(ft);
                g_push_rax();
                parse_expr();
                expect("]");
                let ets0: i64 = ty_size(at0);
                if ets0 > 1 {
                    g_movabs_rdx(ets0);
                    g_imul_rdx();
                }
                g_pop_rcx();
                g_add();
                let at: i64 = at0;
                # 数组元素是 struct：w.a[i].x 继续走字段链
                if tok_is(".") == 1 {
                    let ft5: i64 = field_chain(at);
                    if ty_kind(ft5) == 2 { return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL)); }
                    at = ft5;
                }
                if tok_is("++") == 1 {
                    next_token();
                    expect(";");
                    sv(K_LAST, 0);
                    g_push_rax();
                    if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                    g_push_rax();
                    g_movabs_rax(1);
                    g_pop_rcx();
                    g_add();
                    g_pop_rcx();
                    if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                    return 0;
                }
                if tok_is("--") == 1 {
                    next_token();
                    expect(";");
                    sv(K_LAST, 0);
                    g_push_rax();
                    if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                    g_push_rax();
                    g_movabs_rax(1);
                    g_pop_rcx();
                    g_sub();
                    g_pop_rcx();
                    if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                    return 0;
                }
                if compound_op() > 0 {
                    let cop4: i64 = compound_op();
                    next_token();
                    sv(K_LAST, 0);
                    g_push_rax();
                    if ty_kind(at) == 5 { g_load_at_b(); } else { g_load_at(); }
                    g_push_rax();
                    parse_expr();
                    expect(";");
                    let cdv4: i64 = 0;
                    let cdk4: i64 = 0 - 1;
                    if cop4 == 4 { cdv4 = cmpdiv_d(); cdk4 = cmpdiv_k(); }
                    if cop4 == 5 { cdv4 = cmpdiv_d(); cdk4 = cmpdiv_k(); }
                    g_pop_rcx();
                    g_compound(cop4, cdv4, cdk4);
                    g_pop_rcx();
                    if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                    return 0;
                }
                g_push_rax();
                expect("=");
                parse_expr();
                expect(";");
                g_pop_rcx();
                if ty_kind(at) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if ty_kind(ft) == 2 {
                # v1.1059: r.f = Q { ... }; —— 字段整体赋值（字面量）。
                # rax 已是字段地址（field_addr）。字段地址压栈保存，
                # 逐字段：值算好 → 弹地址到 rsi → 加偏移 → store。
                if tok_is("=") == 1 {
                    let fsq: i64 = gv(K_TOKPOS);
                    next_token();
                    if gv(K_TKIND) == 1 {
                        let fsi: i64 = st_lookup(tokbuf());
                        if fsi >= 0 {
                            let fsvp: i64 = gv(K_TOKPOS);
                            next_token();
                            if tok_is("{") == 1 {
                                if ty_si(ft) != fsi { return err_at2("struct assignment requires the same type", gv(K_LINE), gv(K_COL)); }
                                spill_cache();
                                emit1(0x50);        # 真 push rax —— 字段基地址（g_push_rax 是 rbx 缓存不是真栈）
                                sv(K_LAST, 0);
                                next_token();   # 吃 '{'
                                while tok_is("}") == 0 {
                                    if gv(K_TKIND) != 1 { return syntax_error(); }
                                    let ffni: i64 = 0 - 1;
                                    let ffi: i64 = 0;
                                    while ffi < st_nfields(fsi) {
                                        if streq(tokbuf(), st_field_name(fsi, ffi)) == 1 { ffni = ffi; }
                                        ffi = ffi + 1;
                                    }
                                    if ffni < 0 { return err_at2("struct literal: no such field", gv(K_LINE), gv(K_COL)); }
                                    next_token();
                                    expect(":");
                                    sv(K_LAST, 0);
                                    parse_expr();
                                    expect(";");
                                    spill_cache();
                                    ops4(0x48, 0x8b, 0x34, 0x24);  # mov rsi,[rsp] = 字段基地址
                                    if st_field_off(fsi, ffni) != 0 {
                                        ops2(0x48, 0x81); emit1(0xc6); emit4(st_field_off(fsi, ffni));  # add rsi, off
                                    }
                                    ops3(0x48, 0x89, 0x06);  # mov [rsi], rax
                                }
                                emit1(0x58);        # pop rax（平衡真栈）
                                next_token();   # 吃 '}'
                                expect(";");
                                return 0;
                            }
                            set_back(fsvp);
                        }
                    }
                    # v1.1062: r.f = q2; —— 字段整体赋值（struct 变量）。
                    # '=' 后 parse_expr 给出源地址（kind2 变量）→ g_struct_copy。
                    set_back(fsq);
                    syscall(1, 2, tokbuf(), 2, 0, 0, 0);
                    if tok_is("=") == 1 {
                        next_token();
                        if gv(K_TKIND) == 1 {
                            let vsi: i64 = sym_lookup(tokbuf());

                            if vsi >= 0 && ty_kind(sym_type(vsi)) == 2 {
                                if ty_si(ft) != ty_si(sym_type(vsi)) { return err_at2("struct assignment requires the same type", gv(K_LINE), gv(K_COL)); }
                                next_token();   # 吃变量名
                                expect(";");
                                spill_cache();
                                emit1(0x50);        # 真 push rax = 字段基地址（dst）
                                sv(K_LAST, 0);
                                g_movabs_rax(sym_addr(vsi));   # rax = 源地址
                                ops3(0x48, 0x89, 0xc7);        # mov rdi, rax（源）
                                emit1(0x5e);                   # pop rsi（dst = 字段基地址）
                                sv(K_LAST, 0);
                                # 内联 word 拷贝（不能走 g_struct_copy：dst 是运行时地址）
                                let wi: i64 = 0;
                                while wi < st_words(ty_si(sym_type(vsi))) {
                                    ops3(0x48, 0x8b, 0x8f);    # mov rcx, [rdi+disp32]
                                    emit4(wi * 8);
                                    ops3(0x48, 0x89, 0x8e);    # mov [rsi+disp32], rcx
                                    emit4(wi * 8);
                                    wi = wi + 1;
                                }
                                sv(K_LAST, 0);
                                R_ETY = ft;
                                return 0;
                            }
                        }
                        set_back(fsq);
                    }
                }
                return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL));
            }
            if tok_is("++") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_add();
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if tok_is("--") == 1 {
                next_token();
                expect(";");
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                g_movabs_rax(1);
                g_pop_rcx();
                g_sub();
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            if compound_op() > 0 {
                let cop3: i64 = compound_op();
                next_token();
                sv(K_LAST, 0);
                g_push_rax();
                if ty_kind(ft) == 5 { g_load_at_b(); } else { g_load_at(); }
                g_push_rax();
                parse_expr();
                expect(";");
                let cdv: i64 = 0;
                let cdk: i64 = 0 - 1;
                if cop3 == 4 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
                if cop3 == 5 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
                g_pop_rcx();
                # str 字段的 '+=' 同样是拼接，理由见上面那条注释
                if ty_kind(ft) == 10 {
                    if cop3 != 1 { return err_at2("str 只支持 '+='", gv(K_LINE), gv(K_COL)); }
                    if ty_kind(R_ETY) != 10 { return err_at2("'+=': str 只能拼 str", gv(K_LINE), gv(K_COL)); }
                    if g_str_cat() != 0 { return -1; }
                } else {
                    if ty_kind(R_ETY) == 10 { return err_at2("'+=': 非 str 不能拼 str", gv(K_LINE), gv(K_COL)); }
                    g_compound(cop3, cdv, cdk);
                }
                g_pop_rcx();
                if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
                return 0;
            }
            g_push_rax();
            expect("=");
            parse_expr();
            expect(";");
            g_pop_rcx();
            if ty_kind(ft) == 5 { g_store_at_b(); } else { g_store_at(); }
            return 0;
        }
        set_back(save);
    }
    parse_expr();
    expect(";");
    return 0;
}

# -g：登记一个局部变量（名字、相对 rbp 的偏移、声明行、所属函数）。
#
# **为什么必须在这里另记一份**：parse_func 结束时有 `sv(K_NSYM, ra)`
# 把符号表回滚到进入时的位置 —— 局部变量符号全部丢弃。
# 所以生成 DWARF 时遍历符号表是拿不到局部变量的。
fn dbg_var(nm: i64, off: i64, ln: i64, ty: i64) -> i64 {
    if gv(K_DBG) == 0 { return 0; }
    if gv(K_INIMP) == 1 { return 0; }
    let i: i64 = gv(K_NDV);
    if i >= 40000 { return 0; }
    let p: i64 = DBG + O_DV + i * 40;
    store64(p, intern(nm));
    store64(p + 8, off);
    store64(p + 16, ln);
    store64(p + 24, gv(K_CURFN));
    store64(p + 32, ty);
    sv(K_NDV, i + 1);
    return 0;
}

# -g：登记一个全局变量。复用同一张表，func_idx 记 -1 表示
# "这条的 off 字段是**绝对地址**而不是 rbp 相对偏移"。
fn dbg_gvar(nm: i64, addr: i64, ln: i64, ty: i64) -> i64 {
    if gv(K_DBG) == 0 { return 0; }
    if gv(K_INIMP) == 1 { return 0; }
    let i: i64 = gv(K_NDV);
    if i >= 40000 { return 0; }
    let p: i64 = DBG + O_DV + i * 40;
    store64(p, intern(nm));
    store64(p + 8, addr);
    store64(p + 16, ln);
    store64(p + 24, 0 - 1);
    store64(p + 32, ty);
    sv(K_NDV, i + 1);
    return 0;
}

# v1.1073: 数组解构 let [x, y, z] = arr; —— 逐元素拷贝（x_i = arr[i]）。
# v1 限制：RHS 必须是一维数组变量名；元素 i64（stride 8）。
# v1.1081: struct 解构 let P { x, y } = r; —— 字段逐一 load 到新栈槽
fn parse_struct_destr(dcln: i64) -> i64 {
    let si: i64 = st_lookup(scratch3());   # struct 名由调用点存入 scratch3
    expect("{");
    # 收集：字段名 → 名字缓冲 O_SCAL+6200+i*32
    let cnt: i64 = 0;
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(heap + O_SCAL + 6200 + cnt * 32, tokbuf());
        cnt = cnt + 1;
        next_token();
        if tok_is(",") == 1 { next_token(); }
        else { break; }
    }
    expect("}");
    expect("=");
    if gv(K_TKIND) != 1 { return err_at2("destructure: right side must be a struct variable", gv(K_LINE), gv(K_COL)); }
    let rs: i64 = sym_lookup(tokbuf());
    if rs < 0 { return undef_err(tokbuf()); }
    if ty_kind(sym_type(rs)) != 2 { return err_at2("destructure: right side is not a struct", gv(K_LINE), gv(K_COL)); }
    if ty_si(sym_type(rs)) != si { return err_at2("destructure: struct type mismatch", gv(K_LINE), gv(K_COL)); }
    next_token();
    expect(";");
    g_addr_sym_rax(rs);         # rax = &r
    let i: i64 = 0;
    while i < cnt {
        let nm: i64 = heap + O_SCAL + 6200 + i * 32;
        let fi: i64 = 0 - 1;
        let fj: i64 = 0;
        while fj < st_nfields(si) {
            if streq(nm, st_field_name(si, fj)) == 1 { fi = fj; }
            fj = fj + 1;
        }
        if fi < 0 { return err_at2("destructure: no such field", gv(K_LINE), gv(K_COL)); }
        if sym_dup(nm) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let ft: i64 = st_field_type(si, fi);
        let esz: i64 = ty_size(ft);
        let vo: i64 = gv(K_CUROFF);
        sv(K_CUROFF, vo - esz);
        let vid: i64 = sym_add(nm, 1, vo, 0);
        store64(heap + O_STY + vid * 8, ft);
        dbg_var(nm, vo, dcln, ft);
        # rax 当前 = &r + 已走偏移; 需要绝对：重取源地址 + off
        g_addr_sym_rax(rs);
        if st_field_off(si, fi) > 0 {
            g_push_rax();
            g_movabs_rax(st_field_off(si, fi));
            g_pop_rcx();
            g_add();
        }
        if ty_kind(ft) == 0 || ty_kind(ft) == 4 || ty_kind(ft) == 10 {
            ops3(0x48, 0x89, 0xc1);      # mov rcx, rax
            g_load_at();                 # rax = [rcx]
            g_store_local(vo);
        } else {
            # 字段是数组/嵌套 struct：块拷贝（rax=源, rsi=目的）
            ops3(0x48, 0x89, 0xc6);      # mov rsi, rax
            g_lea_local(vo);             # rax = 目的
            let nw: i64 = esz / 8;
            let w: i64 = 0;
            while w < nw {
                ops3(0x48, 0x8b, 0x1e);  # mov rbx, [rsi]
                ops3(0x48, 0x89, 0x18);  # mov [rax], rbx
                ops4(0x48, 0x83, 0xc0, 0x08);
                ops4(0x48, 0x83, 0xc6, 0x08);
                w = w + 1;
            }
        }
        i = i + 1;
    }
    return 0;
}

fn parse_destructure(dcln: i64) -> i64 {
    expect("[");
    # 收变量名到 O_SCAL+5800（每 32 字节一个）
    let cnt: i64 = 0;
    # v1.1082: 嵌套解构 [[x, y], [z, w]] —— meta[i*16]=0 标量 / 1 嵌套
    let subn: i64 = 0;              # 子名总数（平铺在 +6800）
    while tok_is("]") == 0 {
        if tok_is("[") == 1 {
            next_token();
            store64(heap + O_SCAL + 6600 + cnt * 24, 1);     # nested
            store64(heap + O_SCAL + 6600 + cnt * 24 + 8, subn);  # 子名起点
            while tok_is("]") == 0 {
                if gv(K_TKIND) != 1 { return syntax_error(); }
                memcpy(heap + O_SCAL + 6800 + subn * 32, tokbuf());
                subn = subn + 1;
                next_token();
                if tok_is(",") == 1 { next_token(); }
                else { break; }
            }
            expect("]");
            store64(heap + O_SCAL + 6600 + cnt * 24 + 16, subn);   # 子名终点
            cnt = cnt + 1;
            if tok_is(",") == 1 { next_token(); }
            else { break; }
            continue;
        }
        store64(heap + O_SCAL + 6600 + cnt * 24, 0);
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(heap + O_SCAL + 5800 + cnt * 32, tokbuf());
        cnt = cnt + 1;
        next_token();
        if tok_is(",") == 1 { next_token(); }
        else { break; }
    }
    expect("]");
    expect("=");
    # v1.1089: RHS 支持函数调用 let [x, y, z] = mk(); —— 数组地址存隐藏槽
    let hcall: i64 = 0;      # 哨兵 0=无调用（栈槽偏移恒为负）
    let at: i64 = ty_int();
    if gv(K_TKIND) == 1 {
        let lk0: i64 = sym_lookup(tokbuf());
        let isfn: i64 = 0;
        if lk0 < 0 { if sym_lookup_func(tokbuf()) >= 0 { isfn = 1; } }
        else { if sym_kind(lk0) == 0 { isfn = 1; } }
        if isfn == 1 {
            {
                memcpy(scratch1(), tokbuf());
                next_token();             # 吃函数名 → tok='(' 交 parse_call
                let hv: i64 = gv(K_CUROFF);
                sv(K_CUROFF, hv - 8);
                parse_call();
                g_store_local(hv);        # rax(数组地址) → 隐藏槽
                hcall = hv;
                if ty_kind(R_ETY) == 3 { at = R_ETY; } else { return err_at2("destructure: call must return an array", gv(K_LINE), gv(K_COL)); }
            }
        }
    }
    let asym: i64 = 0 - 1;
    if hcall == 0 {
        if gv(K_TKIND) != 1 { return err_at2("destructure: right side must be an array variable", gv(K_LINE), gv(K_COL)); }
        asym = sym_lookup(tokbuf());
        if asym < 0 { return undef_err(tokbuf()); }
        at = sym_type(asym);
        if ty_kind(at) != 3 { return err_at2("destructure: right side must be an array", gv(K_LINE), gv(K_COL)); }
    }
    # v1.1077: RHS 支持常量行索引 m[1] —— aoff += idx * 行stride
    let aoff_extra: i64 = 0;
    let rowidx: i64 = 0;
    if asym >= 0 { next_token(); }               # 吃掉数组名，现在可能是 '['
    if tok_is("[") == 1 {
        next_token();
        if gv(K_TKIND) != 2 { return err_at2("destructure: row index must be a constant", gv(K_LINE), gv(K_COL)); }
        rowidx = gv(K_TIVAL);
        next_token();
        expect("]");
        # 行 stride = ty_size(elem)
        aoff_extra = rowidx * ty_size(ty_a(at));
        at = ty_a(at);            # 🔴 索引下降一层：m[1] 的元素 = 内层元素
    }
    expect(";");
    let et: i64 = ty_a(at);
    let stride: i64 = ty_size(et);
    # 数组变量在栈上（local）还是数据段？与 parse_addr 同判据：sym_kind==1
    # v1.1089: is_local==2 = 函数调用 RHS —— 基址从隐藏槽加载
    let is_local: i64 = 2;
    let aoff: i64 = hcall;
    if hcall == 0 {
        is_local = sym_kind(asym);
        aoff = sym_addr(asym) + aoff_extra;
    }
    let i: i64 = 0;
    let src: i64 = 0;   # 当前元素字节偏移
    while i < cnt {
        # v1.1082: 嵌套槽 —— 元素是行（数组），子元素逐一 load
        if load64(heap + O_SCAL + 6600 + i * 24) == 1 {
            let etin: i64 = ty_a(et);
            if ty_kind(etin) == 3 { etin = ty_a(etin); }   # m 二维: 元素=行=数组 → 再下: 标量
            let esz2: i64 = ty_size(etin);
            let st: i64 = load64(heap + O_SCAL + 6600 + i * 24 + 8);
            let se2: i64 = st;
            let subend: i64 = load64(heap + O_SCAL + 6600 + i * 24 + 16);
            while se2 < subend {
                if sym_dup(heap + O_SCAL + 6800 + se2 * 32) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let vo2: i64 = gv(K_CUROFF);
                sv(K_CUROFF, vo2 - esz2);
                let vid2: i64 = sym_add(heap + O_SCAL + 6800 + se2 * 32, 1, vo2, 0);
                store64(heap + O_STY + vid2 * 8, etin);
                dbg_var(heap + O_SCAL + 6800 + se2 * 32, vo2, dcln, etin);
                # rax = &arr + src + (se2-st)*esz2 → load → store vo2
                if is_local == 1 { g_lea_local(aoff); } else {
                    if is_local == 2 { g_lea_local(hcall); g_load_at(); sv(K_LAST, 0); }
                    else { g_movabs_rax(aoff); }
                }
                let off2: i64 = src + (se2 - st) * esz2;
                if off2 > 0 {
                    g_push_rax();
                    g_movabs_rax(off2);
                    g_pop_rcx();
                    g_add();
                }
                ops3(0x48, 0x89, 0xc1);
                g_load_at();
                g_store_local(vo2);
                se2 = se2 + 1;
            }
            src = src + stride;
            i = i + 1;
            continue;
        }
        let nm: i64 = heap + O_SCAL + 5800 + i * 32;
        if sym_dup(nm) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let esz: i64 = ty_size(et);
        let vo: i64 = gv(K_CUROFF);
        sv(K_CUROFF, vo - esz);
        let vid: i64 = sym_add(nm, 1, vo, 0);
        store64(heap + O_STY + vid * 8, et);
        dbg_var(nm, vo, dcln, et);
        # rax = &arr + src
        if is_local == 1 {
            g_lea_local(aoff);         # rax = &arr
        } else {
            if is_local == 2 {
                g_lea_local(hcall);    # v1.1089: 基址 = 隐藏槽里的地址
                g_load_at();
                sv(K_LAST, 0);         # 🔴 防折叠吃掉 lea/load 对
            } else {
                g_movabs_rax(aoff);    # rax = 绝对地址
            }
        }
        if src > 0 {
            g_push_rax();
            g_movabs_rax(src);
            g_pop_rcx();
            g_add();
        }
        if ty_kind(et) == 0 {
            # 标量元素：rax = *(src)
            ops3(0x48, 0x89, 0xc1);   # mov rcx, rax
            g_load_at();              # mov rax, [rcx]
            g_store_local(vo);
        } else {
            # 行（数组/struct）：src 块拷贝到栈槽 vo —— rep movsq 太重，
            # 逐 8 字节：rdi 源游标，目的用 g_lea_local(vo) 再 store_at
            ops3(0x48, 0x89, 0xc7);   # mov rdi, rax  (源块地址)
            g_lea_rsi_local(vo);      # rsi = 目的栈槽
            let nw: i64 = esz / 8;
            let w: i64 = 0;
            while w < nw {
                ops3(0x48, 0x8b, 0x07);   # mov rax, [rdi]
                ops3(0x48, 0x89, 0x06);   # mov [rsi], rax
                ops4(0x48, 0x83, 0xc7, 0x08);   # add rdi, 8
                ops4(0x48, 0x83, 0xc6, 0x08);   # add rsi, 8
                w = w + 1;
            }
        }
        src = src + stride;
        i = i + 1;
    }
    return 0;
}

fn parse_let() -> i64 {
    # 声明行要在解析表达式**之前**取：之后 K_LINE 会走到表达式末尾，
    # 记下来的行号就指向右值而不是声明处。
    let dcln: i64 = gv(K_LINE);
    # v1.1073: 数组解构 let [x, y, z] = arr;
    if tok_is("[") == 1 { return parse_destructure(dcln); }
    # v1.1081: struct 解构 let P { x, y } = r;
    if gv(K_TKIND) == 1 {
        if st_lookup(tokbuf()) >= 0 {
            let pkp: i64 = gv(K_TOKPOS);
            memcpy(scratch3(), tokbuf());
            next_token();
            if tok_is("{") == 1 { return parse_struct_destr(dcln); }
            set_back(pkp);
        }
    }
    memcpy(scratch2(), tokbuf());
    next_token();
    # v1.1083: 无类型推断 let f = add; —— 从 RHS 表达式类型推
    if tok_is("=") == 1 {
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let bo2: i64 = gv(K_CUROFF);
        sv(K_CUROFF, bo2 - 8);
        next_token();             # 吃 '='
        # v1.1102: match 右值走通用 parse_expr（primary 集成），无需特判。
        # 旧探测块把 match 发射后直接 expect(";")，遇到 `match …} * 2` 之类
        # 后续运算符直接 syntax error —— 已删，探针 pt8 实证。
        parse_expr();
        expect(";");
        let ity: i64 = R_ETY;
        let isz: i64 = ty_size(ity);
        if isz < 8 { isz = 8; }
        # v1.1100: 与 typed 标量路径统一 —— CUROFF 留在已用槽顶，下个声明从 CUROFF-8 分配
        # （旧代码 sv(CUROFF, bo2-isz) 让下一个 typed let 与本变量撞槽，pq 探针实证）
        sv(K_CUROFF, bo2 - isz - 8);
        let iid: i64 = sym_add(scratch2(), 1, bo2 - isz, 0);
        store64(heap + O_STY + iid * 8, ity);
        dbg_var(scratch2(), bo2 - isz, dcln, ity);
        if ty_kind(ity) == 0 || ty_kind(ity) == 4 || ty_kind(ity) == 10 {
            g_store_local(bo2 - isz);
        } else {
            if ty_kind(ity) == 2 {
                if R_SADDR == 1 {
                    # 字面量/struct 变量：rax=对象地址 → 块拷
                    ops3(0x48, 0x89, 0xc6);      # mov rsi, rax
                    g_lea_local(bo2 - isz);
                    let nw6: i64 = isz / 8;
                    let w6: i64 = 0;
                    while w6 < nw6 {
                        ops3(0x48, 0x8b, 0x1e);
                        ops3(0x48, 0x89, 0x18);
                        ops4(0x48, 0x83, 0xc0, 0x08);
                        ops4(0x48, 0x83, 0xc6, 0x08);
                        w6 = w6 + 1;
                    }
                    R_SADDR = 0;
                } else {
                    # v1.1088: struct **返回值**走两字寄存器（rax=x, rdx=y）
                    g_store_local(bo2 - isz);
                    if st_words(ty_si(ity)) == 2 {
                        ops3(0x48, 0x89, 0xd0);      # mov rax, rdx
                        g_store_local(bo2 - isz + 8);
                    }
                }
            } else {
                # 数组值：rax=地址 → 块拷贝
                ops3(0x48, 0x89, 0xc6);      # mov rsi, rax
                g_lea_local(bo2 - isz);      # rax = 目的
                let nw5: i64 = isz / 8;
                let w5: i64 = 0;
                while w5 < nw5 {
                    ops3(0x48, 0x8b, 0x1e);  # mov rbx, [rsi]
                    ops3(0x48, 0x89, 0x18);  # mov [rax], rbx
                    ops4(0x48, 0x83, 0xc0, 0x08);
                    ops4(0x48, 0x83, 0xc6, 0x08);
                    w5 = w5 + 1;
                }
            }
        }
        return 0;
    }
    expect(":");
    # f64 局部变量：与 i64 同样占 8 字节栈槽，只是 R_ETY 标记为浮点，
    # 于是后续算术/比较会自动走 SSE。
    if accept("bool") == 1 {
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let bo: i64 = gv(K_CUROFF);
        sv(K_CUROFF, bo - 8);
        let bid: i64 = sym_add(scratch2(), 1, bo, 0);
        store64(heap + O_STY + bid * 8, ty_bool());
        dbg_var(scratch2(), bo, dcln, ty_bool());
        if accept("=") == 1 {
            parse_expr();
            expect(";");
            g_store_local(bo);
            return 0;
        }
        expect(";");
        return 0;
    }
    if accept("f64") == 1 {
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let fo: i64 = gv(K_CUROFF);
        sv(K_CUROFF, fo - 8);
        let fid: i64 = sym_add(scratch2(), 1, fo, 0);
        store64(heap + O_STY + fid * 8, ty_float());
        dbg_var(scratch2(), fo, dcln, ty_float());
        # ⚠️ 不能写 expect("f64")：accept 失败时**没有消费** token，
        # 再 expect 就把它当成必须是 f64 —— 非 f64 声明全报语法错误。
        if accept("=") == 1 {
            parse_expr();
            expect(";");
            g_store_local(fo);
            return 0;
        }
        expect(";");
        return 0;
    }
    if tok_is("i64") == 0 {
        if gv(K_TKIND) == 1 {
            let si: i64 = st_lookup(tokbuf());
            if si >= 0 {
                next_token();
                # 🔴 槽数必须是 st_words（递归展开嵌套结构体），不是 st_nfields。
                #    少分配槽不会报错，只会让结构体末尾字段写到相邻数据上
                #    （实测覆盖了字符串字面量，print 输出变空/变怪字符）。
                let n: i64 = st_words(si);
                data_align(16);
                let addr: i64 = 268435456 + gv(K_DLEN);
                let j: i64 = 0;
                while j < n {
                    # v1.1060: 字段默认值 —— 槽 j 若对应有默认值的字段则填默认
                    let dv: i64 = 0;
                    let fi2: i64 = 0;
                    while fi2 < st_nfields(si) {
                        if st_field_off(si, fi2) == j * 8 {
                            if SDH[si * 64 + fi2] == 1 { dv = SDV[si * 64 + fi2]; }
                        }
                        fi2 = fi2 + 1;
                    }
                    dquad(dv);
                    j += 1;
                }
                if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let id: i64 = sym_add(scratch2(), 2, addr, 0);
                store64(heap + O_STY + id * 8, ty_struct(si));
                # 结构体变量落在**数据段**（不是栈上），所以记成
                # "全局"那条路（fidx=-1 表示 off 字段是绝对地址）
                dbg_gvar(scratch2(), addr, dcln, ty_struct(si));
                # let q: Pair = mk(7, 9);  —— 结构体变量初始化。
                #
                # 之前只支持 `let q: Pair;` 再逐字段赋值。函数能返回
                # 结构体之后，这条路径就成了自然需求。
                # 值按 System V 放在 rax（第 0 字段）与 rdx（第 1 字段）。
                if accept("=") == 1 {
                    # v1.1048: struct 字面量 let q: Pair = Pair { x: 1, y: 2 };
                    let svp: i64 = gv(K_TOKPOS);
                    let litok: i64 = 0;
                    # v1.1100: match 表达式（typed let 右值）
                    if gv(K_TKIND) == 1 && streq(tokbuf(), "match") == 1 {
                        let mhoff: i64 = addr;
                        if parse_match_expr(mhoff) != 0 { return -1; }
                        expect(";");
                        return 0;
                    }
                    if gv(K_TKIND) == 1 {
                        let lsi: i64 = st_lookup(tokbuf());
                        if lsi == si {
                            let svp2: i64 = gv(K_TOKPOS);
                            next_token();
                            if tok_is("{") == 1 { litok = 1; }
                            else { set_back(svp2); }
                        }
                    }
                    if litok == 1 {
                        next_token();   # 吃 '{'（探测已消费 struct 名）

                        while tok_is("}") == 0 {
                            if gv(K_TKIND) != 1 { return syntax_error(); }
                            let fni: i64 = 0 - 1;
                            let fi2: i64 = 0;
                            while fi2 < st_nfields(si) {
                                if streq(tokbuf(), st_field_name(si, fi2)) == 1 { fni = fi2; }
                                fi2 = fi2 + 1;
                            }
                            if fni < 0 { return err_at2("struct literal: no such field", gv(K_LINE), gv(K_COL)); }
                            next_token();
                            expect(":");
                            parse_expr();
                            expect(";");
                            spill_cache();
                            let fo2: i64 = addr + st_field_off(si, fni);
                            # v1.1059: 字段值为 struct（嵌套字面量）—— rax 是
                            # 数据段常量区地址，需整块拷贝（g_struct_copy）。
                            if ty_kind(R_ETY) == 2 {
                                # v1.1064: 嵌套字面量/变量一律按地址整块拷贝
                                #（emit_lit_struct 返回常量区地址; 变量表达式
                                #  返回变量地址 — R_SADDR 残留不再参与判定）
                                g_struct_copy(fo2, st_words(ty_si(R_ETY)));
                                accept(",");
                                continue;
                            }
                            g_movabs_rsi(fo2);
                            ops3(0x48, 0x89, 0x06);   # mov [rsi], rax
                            accept(",");
                        }
                        next_token();   # 吃 '}'
                        expect(";");
                        return 0;
                    }
                    set_back(svp);
                    parse_expr();
                    expect(";");
                    spill_cache();         # 值可能还在 rbx 里，先落回 rax
                    # 结构体**变量/元素/字段**在表达式里是地址（R_SADDR=1），
                    # 函数返回的结构体是值（rax/rdx）。混用会把地址写进字段。
                    if ty_kind(R_ETY) == 2 {
                        if R_SADDR == 1 {
                            g_struct_copy(addr, n);
                            return 0;
                        }
                    }
                    # rbx 是栈顶缓存，不能随便占用 —— 用 rsi 做地址中转
                    g_movabs_rsi(addr);
                    ops3(0x48, 0x89, 0x06);            # mov [rsi], rax
                    if n == 2 {
                        ops3(0x48, 0x89, 0x56);        # mov [rsi+8], rdx
                        emit1(8);
                    }
                    return 0;
                }
                expect(";");
                return 0;
            }
        }
    }
    if tok_is("[") == 1 {
        let n: i64 = 0;
        next_token();
        if gv(K_TKIND) == 2 {
            n = gv(K_TIVAL);
        } else {
            if gv(K_TKIND) == 1 {
                # const 名做数组长度（v1.975）；O_SU 标记（v1.1000）
                let csi: i64 = sym_lookup(tokbuf());
                if csi >= 0 {
                    if load64(heap + O_SK + csi * 8) == 4 {
                        n = load64(heap + O_SCV + csi * 8);
                        store64(heap + O_SU + csi * 8, 1);
                    }
                }
            }
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        # v1.1050 二维 / v1.1058 任意维 —— et 声明前收全部内维到 O_LSTV
        # （[2][3][4] 存 3,4 内维在前），元素类型出来后倒序逐层包装。
        let ndims: i64 = 0;
        while tok_is("[") == 1 {
            let dimx: i64 = 0 - 1;
            next_token();
            if gv(K_TKIND) == 2 { dimx = gv(K_TIVAL); next_token(); }
            else {
                if gv(K_TKIND) == 1 {
                    let csi2: i64 = sym_lookup(tokbuf());
                    if csi2 >= 0 {
                        if load64(heap + O_SK + csi2 * 8) == 4 {
                            dimx = load64(heap + O_SCV + csi2 * 8);
                            next_token();
                        }
                    }
                }
            }
            expect("]");
            if dimx <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            store64(heap + O_LSTV + ndims * 8, dimx);
            ndims = ndims + 1;
        }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("f64") == 1 {
                et = ty_float();
                next_token();
            } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if tok_is("ptr") == 1 { next_token(); et = ty_ptr(parse_ptr_target()); }   # v1.1043
                else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        # v1.1057: enum 名作类型（等价 i64）
                        let enmL: i64 = intern(tokbuf());
                        if enum_type_exists(enmL) == 1 {
                            next_token();
                            et = ty_int();
                        } else {
                            # v1.1110: 前向 struct —— 预注册
                            et = ty_struct(st_add(tokbuf()));
                            next_token();
                        }
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
                }
                }
            }
        }
        # v1.1058: 内维倒序包装（[2][3] et=ty_array(ty_array(elem,3),2)）
        let wi: i64 = ndims - 1;
        while wi >= 0 {
            et = ty_array(et, load64(heap + O_LSTV + wi * 8));
            wi = wi - 1;
        }
        let esz: i64 = ty_size(et);
        let p: i64 = gv(K_CUROFF);
        # 🔴 栈槽约定：变量 off 是它的**最低字节**，占 [off, off+size-1]（向上）。
        #    上一个变量占 [p+8, ...]（p 是它的下边界再往下 8），所以数组顶端
        #    最高只能到 p+7 → off = p + 8 - esz*n。
        #
        #    原来写成 p - esz*(n-1)，只有在 esz==8（i64 数组）时才等于正确值；
        #    esz>8 时整体偏高 esz-8 字节，最后一个元素的最后几个字节会写到
        #    数组之上——当数组是**第一个局部变量**时，那里正是保存的 rbp 与
        #    返回地址，于是 `a[2].b = 9` 直接改掉返回地址，函数返回时 SIGSEGV。
        #    （写倒数第二个元素、或数组前面还有别的局部变量，都不会崩，
        #     所以这个 bug 只在很窄的组合下暴露。）
        let off: i64 = p - esz * n + 8;
        # byte 数组必须把 K_CUROFF 压到 8 字节对齐。
        # 否则下一个 i64 变量拿到 off=CUROFF，占 [CUROFF, CUROFF+7]，
        # 会与 byte 数组的低地址端重叠，i64 的写入会把数组内容冲掉。
        if esz == 1 {
            sv(K_CUROFF, ((p - esz * n) - 7) & -8);
        } else {
            sv(K_CUROFF, p - esz * n);
        }
        if accept("=") == 1 {
            # v1.1050: kind 3 且 elem 是数组 = 二维数组初始化，放行
            if ty_kind(et) != 0 { if ty_kind(et) != 5 { if ty_kind(et) != 4 { if ty_kind(et) != 3 { if ty_kind(et) != 6 { if ty_kind(elem_type(et)) != 3 { return err_at2("cannot init a struct array this way", gv(K_LINE), gv(K_COL)); } } } } } }   # v1.1019: kind 4 = ptr 数组字面量（&fn 表）; v1.1050: 二维放行
            # v1.1079: 非字面量 RHS —— 仅当「函数调用」返回数组
            # （rax = 数组地址）。标量 0 清零初始化等仍走字面量填 0 路径。
            let arrcall: i64 = 0;
            if gv(K_TKIND) == 1 {
                memcpy(scratch3(), tokbuf());
                let pkq: i64 = gv(K_TOKPOS);
                next_token();
                if tok_is("(") == 1 {
                    if sym_lookup_func(scratch3()) >= 0 { arrcall = 1; }
                }
                set_back(pkq);
            }
            if arrcall == 1 {
                if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let ida: i64 = sym_add(scratch2(), 1, off, 0);
                store64(heap + O_STY + ida * 8, ty_array(et, n));
                dbg_var(scratch2(), off, dcln, ty_array(et, n));
                parse_expr();
                expect(";");
                g_push_rax();                     # 自带 spill；源地址入栈
                g_lea_local(off);                 # rax = 目的（新数组槽）—— g_copy_words 约定 rax=目的游标 rsi=源
                spill_cache();
                emit1(0x5e);                      # pop rsi = 源
                g_copy_words(ty_size(ty_array(et, n)) / 8);
                return 0;
            }
            let lcnt2: i64 = 0 - 1;
            let sinit2: i64 = 0 - 1;
            # v1.1066: 二维数组嵌套字面量 [[1,2],[3,4]] —— elem 是数组时
            # 逐子列表解析, 行主展开铺平到 O_LSTV。
            # v1.1066: 任意维嵌套字面量 [[[1,2],[3,4]],[[5,6],[7,8]]] —
            # 递归下降: dp 栈(O_LSTV+900 区)存每层写指针, 叶子值直接铺平
            # 写入 O_LSTV[512..)。行长度校验: 同层第二行起长度须与首行一致。
            if tok_is("[") == 1 && ndims >= 0 {
                # 维度链: dims[0]=最内 … dims[ndims-1]=最外; 总元数 prod
                let prod: i64 = n;
                let di: i64 = 0;
                while di < ndims {
                    prod = prod * load64(heap + O_LSTV + di * 8);
                    di = di + 1;
                }
                # 深度优先解析 — 计数栈用 heap 高区 89981000（无 let，不占局部槽）
                let sp: i64 = 0;          # 栈深
                let wp: i64 = 0;          # 铺平写指针（O_LSTV 512+ 区废弃）
                next_token();             # 吃最外 '['
                sp = 1;
                store64(heap + 89981000, 0);
                while sp > 0 {
                    if tok_is("[") == 1 {
                        next_token();
                        store64(heap + 89981000 + sp * 8, 0);
                        sp = sp + 1;
                    } else {
                        if tok_is("]") == 1 {
                            next_token();
                            sp = sp - 1;
                            # 校验本层子数 = 期望维
                            let lvlcnt: i64 = load64(heap + 89981000 + sp * 8);
                            if sp > 0 { store64(heap + 89981000 + (sp - 1) * 8, load64(heap + 89981000 + (sp - 1) * 8) + 1); }
                            let wantd: i64 = n;
                            if sp > 0 { wantd = load64(heap + O_LSTV + (ndims - sp) * 8); }
                            if lvlcnt != wantd { return err_at2("nested array literal: row count mismatch", gv(K_LINE), gv(K_COL)); }
                            accept(",");
                        } else {
                            # 叶子: 常量表达式元素（负数/const/enum）
                            let lv: i64 = 0;
                            let negv: i64 = 0;
                            if accept("-") == 1 { negv = 1; }
                            if gv(K_TKIND) == 2 {
                                # v1.1122: f64 叶子 → IEEE754 位模式（neg 已含于 f64_bits）
                                if gv(K_TFLT) == 1 {
                                    lv = f64_bits(gv(K_TFDIG), gv(K_TFDIGN), FSTICKY, negv);
                                    negv = 0;
                                } else { lv = gv(K_TIVAL); }
                                next_token();
                            }
                            else {
                                if gv(K_TKIND) == 1 {
                                    let csi3: i64 = sym_lookup(tokbuf());
                                    if csi3 >= 0 && load64(heap + O_SK + csi3 * 8) == 4 { lv = const_expr(); }
                                    else {
                                        # v1.1097: 变量名 → 运行期求值
                                        if sym_lookup(tokbuf()) >= 0 {
                                            spill_cache();
                                            parse_expr();
                                            if negv == 1 { emit1(0x48); emit1(0xf7); emit1(0xd8); }  # neg rax
                                            if ty_kind(et) == 5 { g_store_local_b(off + wp * 8); }
                                            else { g_store_local(off + wp * 8); }
                                            store64(heap + 89981300 + wp * 8, 1);
                                            lv = 0;
                                        } else {
                                            if enum_value(tokbuf()) >= 0 {
                                                spill_cache();
                                                lv = const_expr();   # const_atom 兜底 enum（v1.1049），折叠算术后缀
                                                g_movabs_rax(lv);
                                            } else { lv = const_expr(); }
                                            if negv == 1 { emit1(0x48); emit1(0xf7); emit1(0xd8); }  # neg rax（变量/enum 负前缀）
                                            if ty_kind(et) == 5 { g_store_local_b(off + wp * 8); }
                                            else { g_store_local(off + wp * 8); }
                                            store64(heap + 89981300 + wp * 8, 1);
                                            lv = 0;
                                        }
                                    }
                                } else {
                                    # v1.1097: 其他 token（括号表达式等）→ 运行期求值
                                    spill_cache();
                                    parse_expr();
                                    if ty_kind(et) == 5 { g_store_local_b(off + wp * 8); }
                                    else { g_store_local(off + wp * 8); }
                                    store64(heap + 89981300 + wp * 8, 1);
                                    lv = 0;
                                }
                            }
                            if load64(heap + 89981300 + wp * 8) == 0 {
                                if negv == 1 { lv = 0 - lv; }
                                # 叶子直接写 O_LSTV[wp]（嵌套分支独占该区，无冲突）
                                store64(heap + O_LSTV + (64 + wp) * 8, lv);
                            }
                            wp = wp + 1;
                            # 只计最深层（叶子数）; 行闭包时上级+1
                            store64(heap + 89981000 + (sp - 1) * 8, load64(heap + 89981000 + (sp - 1) * 8) + 1);
                            accept(",");
                        }
                    }
                }
                if wp != prod { return err_at2("nested array literal: total element count mismatch", gv(K_LINE), gv(K_COL)); }
                lcnt2 = 0 - 65536 - prod;   # 编码: < -65535 标记嵌套铺平
            } else {
            if tok_is("[") == 1 { lcnt2 = parse_i64_list(); }
            else {
                if gv(K_TKIND) == 3 { sinit2 = gv(K_STROFF); }
            }
            }
            let v: i64 = gv(K_TIVAL);
            # 嵌套铺平（<= -65536）后 token 已在 ';'；其余（标量值/str）
            # 需 next_token 吃掉当前 token
            if lcnt2 < 0 && lcnt2 > 0 - 65536 { next_token(); }
            expect(";");
            if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            let id: i64 = sym_add(scratch2(), 1, off, 0);
            store64(heap + O_STY + id * 8, ty_array(et, n));
            dbg_var(scratch2(), off, dcln, ty_array(et, n));
            let k: i64 = 0;
            # v1.1066: 嵌套字面量需填 n*inn 个元素（铺平）
            let filln: i64 = n;
            if lcnt2 <= 0 - 65536 {
                filln = 0 - 65536 - lcnt2;   # prod（铺平元素总数）
            }
            while k < filln {
                if lcnt2 <= 0 - 65536 && load64(heap + 89981300 + k * 8) == 1 { k = k + 1; continue; }
                let cv: i64 = v;
                if sinit2 >= 0 {
                    if k < gv(K_NSTR) - sinit2 - 1 { cv = load8(heap + O_STRS + sinit2 + k); }
                    else { cv = 0; }
                } else {
                    if lcnt2 >= 0 {
                        if k < lcnt2 { cv = load64(heap + O_LSTV + k * 8); }
                        else { cv = 0; }
                    } else {
                        if lcnt2 <= 0 - 65536 {
                            let dec: i64 = 0 - 65536 - lcnt2;
                            if k < dec { cv = load64(heap + O_LSTV + (64 + k) * 8); }
                            else { cv = 0; }
                        }
                    }
                }
                g_movabs_rax(cv);
                # v1.1066: 嵌套字面量铺平按 word 步进（esz 是整行大小）
                # v1.1097: byte 数组例外 —— 叶子本就逐字节，step 保持 esz=1
                let step: i64 = esz;
                if lcnt2 <= 0 - 65536 && esz > 1 { step = 8; }
                if ty_kind(et) == 5 { g_store_local_b(off + k * step); }
                else { g_store_local(off + k * step); }
                k = k + 1;
            }
            return 0;
        }
        expect(";");
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let id: i64 = sym_add(scratch2(), 1, off, 0);
        store64(heap + O_STY + id * 8, ty_array(et, n));
        dbg_var(scratch2(), off, dcln, ty_array(et, n));
        return 0;
    }
    # 标量声明：i64 / byte / ptr
    #   ptr 是「指向字节的指针」，专门用于字符串与字节缓冲区——
    #   有了它才能写 s[i]，否则字符串形参只能声明成 i64 然后用 load8 手算。
    let vt: i64 = ty_int();
    if accept("str") == 1 {
        vt = ty_str();
    } else {
        if accept("i64") == 1 {
            vt = ty_int();
        } else {
            if accept("byte") == 1 {
                vt = ty_byte();
            } else {
                if accept("ptr") == 1 {
                    # v1.1043: ptr [i64/byte/P]
                    vt = ty_ptr(parse_ptr_target());
                } else {
                    # v1.1057: enum 名作类型（等价 i64，值即成员常量）
                    if gv(K_TKIND) == 1 {
                        let enmS: i64 = intern(tokbuf());
                        if enum_type_exists(enmS) == 1 {
                            next_token();
                            vt = ty_int();
                        } else {
                            return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                        }
                    } else {
                        return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                    }
                }
            }
        }
    }
    expect("=");
    # v1.1102: match 右值走通用 parse_expr（primary 集成），无特判（旧特判
    # 遇 `let b: i64 = match …} + 1;` 之类后续运算符会 syntax error）。
    parse_expr();
    expect(";");
    let off: i64 = gv(K_CUROFF);
    sv(K_CUROFF, off - 8);
    if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let id: i64 = sym_add(scratch2(), 1, off, 0);
    store64(heap + O_STY + id * 8, vt);
    dbg_var(scratch2(), off, dcln, vt);
    if ty_kind(vt) == 5 { g_store_local_b(off); }
    else { g_store_local(off); }
    return 0;
}

# if / else if / else 链。
# 用迭代而非递归：整条链共用一个出口标签 end，每一轮各有一个「下一分支」标签。
# 这样 else if 不会层层嵌套、也不会为每层多生成一对 jmp/label。
fn warn_const_cond() -> i64 {
    # 条件为纯 0/1 字面量时告警（v1.1004，仅 -Wall）。
    # 条件语法 if (expr)，跳过 '(' 探测首个 token。
    if gv(K_WARN) == 1 {
        if tok_is("(") == 1 {
            let sp: i64 = gv(K_TOKPOS);
            next_token();
            let hit: i64 = 0;
            if gv(K_TKIND) == 2 {
                if gv(K_TIVAL) == 0 || gv(K_TIVAL) == 1 {
                    hit = 1;
                }
            }
            set_back(sp);
            return hit;
        }
    }
    return 0;
}

fn parse_if() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let end: i64 = new_label();
    let more: i64 = 1;
    while more == 1 {
        if warn_const_cond() == 1 {
            syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
            syscall(1, 2, ": warning: constant condition\n", 30, 0, 0, 0);
        }
        parse_expr();
        g_cmp_rax_0();
        let els: i64 = new_label();
        emit_jcc(0x84, els);
        parse_block(d);
        emit_jmp(end);
        place_label(els);
        if accept("else") == 1 {
            if accept("if") == 1 {
                more = 1;
            } else {
                parse_block(d);
                more = 0;
            }
        } else {
            more = 0;
        }
    }
    place_label(end);
    return 0;
}

# v1.1071: do { ... } while (cond); —— body 先行，尾部判 cond 非零回跳。
# loop_push(chk=cond, end, stp=cond)：continue 跳 cond，break 跳 end。
fn parse_do_while() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    let cond: i64 = new_label();
    let end: i64 = new_label();
    loop_push(cond, end, cond);
    place_label(cond);
    parse_block(d);
    if accept("while") == 0 { return syntax_error(); }
    expect("(");
    parse_expr();
    expect(")");
    g_cmp_rax_0();
    emit_jcc(0x85, cond);   # jne → 回跳 body
    place_label(end);
    expect(";");
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

fn parse_while() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let a: i64 = new_label();
    let b: i64 = new_label();
    loop_push(a, b, -1);
    place_label(a);
    if warn_const_cond() == 1 {
        syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
        syscall(1, 2, ": warning: constant condition\n", 30, 0, 0, 0);
    }
    parse_expr();
    g_cmp_rax_0();
    emit_jcc(0x84, b);
    parse_block(d);
    emit_jmp(a);
    place_label(b);
    loop_pop();
    return 0;
}

# for (init; cond; step) { body }
#   展开为：init; while (cond) { body; __step: step; }
# 关键点：continue 要跳到 step，不是跳到循环头 ——
# 否则 continue 会跳过 i++ 直接回到条件判断，造成死循环。
# 这正是循环栈要多存一个 stp 标签的原因。
# for 的步进子句：不以 ';' 结尾，所以不能直接用 parse_stmt。
# 支持 i++ / i-- / i OP= expr / i = expr，其余当表达式丢弃结果。
fn parse_for_step() -> i64 {
    if gv(K_TKIND) == 1 {
        memcpy(scratch2(), tokbuf());
        next_token();
        if tok_is("++") == 1 {
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_add();
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("--") == 1 {
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            g_movabs_rax(1);
            g_pop_rcx();
            g_sub();
            store_sym(R_SYM);
            return 0;
        }
        if compound_op() > 0 {
            let fs: i64 = compound_op();
            next_token();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            load_sym(R_SYM);
            g_push_rax();
            parse_expr();
            let cdv: i64 = 0;
            let cdk: i64 = 0 - 1;
            if fs == 4 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
            if fs == 5 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
            g_pop_rcx();
            g_compound(fs, cdv, cdk);
            store_sym(R_SYM);
            return 0;
        }
        if tok_is("=") == 1 {
            next_token();
            parse_expr();
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            store_sym(R_SYM);
            return 0;
        }
        set_back(gv(K_TOKPOS));
    }
    parse_expr();
    return 0;
}

# for (init; cond; step) body
#
# 布局刻意**不**用标准写法（cond 在 body 之后），而是让**生成顺序等于文本顺序**：
#
#     init
#   CHECK: cond; jz END; jmp BODY
#   STEP:  step;  jmp CHECK      <- continue 跳到这里
#   BODY:  body;  jmp STEP
#   END:                          <- break 跳到这里
#
# 标准布局（init; CHECK: cond; jz END; BODY: body; STEP: step; jmp CHECK）
# 要求 step 的代码生成在 body 之后，而 step 的**文本**在 body 之前 ——
# 于是必须"跳过 step 文本 → 解析 body → set_pos 回退解析 step"。
# 那条路在**嵌套 for** 上会坏：外层记录的回退位置被内层 for 的 set_pos
# 覆盖，位置跑飞，报 syntax error 且行列超出文件末尾（n1 用例实测）。
# 本布局靠多两条 jmp 换取"线性解析、可任意嵌套"，不碰 token 位置。

# v1.1072: for 的 init 里支持裸赋值 `i = 0` / `i += 1`。
# 返回 1 = 已完整消费（含 ';'，调用方直接结束 init）；0 = 不是赋值（未消费任何 token）。
fn parse_for_init() -> i64 {
    memcpy(heap + O_SCAL + 5700, tokbuf());
    next_token();
    let fs: i64 = 0;
    if tok_is("=") == 1 { fs = 100; } else { fs = compound_op(); }
    if fs == 0 {
        set_back(gv(K_TOKPOS));   # 回退：让调用方走普通 parse_expr
        return 0;
    }
    next_token();                # 吃 '=' / compound op
    R_SYM = sym_lookup(heap + O_SCAL + 5700);
    if R_SYM < 0 { return undef_err(heap + O_SCAL + 5700); }
    if fs == 100 {
        parse_expr();
    } else {
        load_sym(R_SYM);
        g_push_rax();
        parse_expr();
        let cdv: i64 = 0;
        let cdk: i64 = 0 - 1;
        if fs == 4 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
        if fs == 5 { cdv = cmpdiv_d(); cdk = cmpdiv_k(); }
        g_pop_rcx();
        g_compound(fs, cdv, cdk);
    }
    store_sym(R_SYM);
    expect(";");
    return 1;
}
# v1.1090: for v in row —— row 是 ptr(标量) 行变量（外层 for-in 的行）。
# 上界 = 外层登记的 _fl_<depth>（行长度）。行变量名已在 tokbuf（未消费）。
fn parse_for_in_ptr(vname: i64, rowname: i64) -> i64 {
    let rn: i64 = heap + O_SCAL + 5450;
    memcpy(rn, rowname);
    let rsym: i64 = sym_lookup(rn);
    if rsym < 0 { return undef_err(rn); }
    if ty_kind(sym_type(rsym)) != 4 { return err_at2("for-in: right side must be an array", gv(K_LINE), gv(K_COL)); }
    next_token();            # 吃 'in' 后的行变量名
    let fb3: i64 = heap + O_SCAL + 5500;
    memcpy(fb3, "_fl_");
    store8(fb3 + 4, 47 + gv(K_DEPTH));   # 外层 body depth = 本层-1
    store8(fb3 + 5, 0);
    let fsi3: i64 = sym_lookup(fb3);
    if fsi3 < 0 { return err_at2("for-in: pointer needs an enclosing row loop", gv(K_LINE), gv(K_COL)); }
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    if sym_dup(vname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let xo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, xo - 8);
    let xid: i64 = sym_add(vname, 1, xo, 0);
    let etp: i64 = ty_a(sym_type(rsym));   # 元素类型
    store64(heap + O_STY + xid * 8, etp);
    dbg_var(vname, xo, gv(K_LINE), etp);
    # 内层索引 _fi_<depth>（外层是 _fi_<depth-1>，深度不同不撞）
    let ibuf: i64 = heap + O_SCAL + 5600;
    memcpy(ibuf, "_fi_");
    store8(ibuf + 4, 48 + gv(K_DEPTH));
    store8(ibuf + 5, 0);
    if sym_dup(ibuf) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let fo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, fo - 8);
    let fid: i64 = sym_add(ibuf, 1, fo, 0);
    store64(heap + O_STY + fid * 8, ty_int());
    dbg_var(ibuf, fo, gv(K_LINE), ty_int());
    # _fi = 0
    g_movabs_rax(0);
    g_store_local(fo);
    let chk: i64 = new_label();
    let end: i64 = new_label();
    let stp: i64 = new_label();
    let bdy: i64 = new_label();
    loop_push(chk, end, stp);
    place_label(chk);
    # cond: _fi - len(_fl_) >= 0 → end
    g_load_local(fo);
    g_push_rax();
    load_sym(fsi3);              # rax = 行长度（外层登记的变量）
    g_pop_rcx();
    g_sub();
    g_cmp_rax_0();
    emit_jcc(0x8d, end);
    emit_jmp(bdy);
    place_label(stp);
    g_load_local(fo);
    ops3(0x48, 0x83, 0xc0); emit1(1);
    g_store_local(fo);
    emit_jmp(chk);
    place_label(bdy);
    # x = row[_fi]（ptr 标量步长）
    load_sym(rsym);              # rax = row 指针值
    g_push_rax();
    g_load_local(fo);
    if ty_size(etp) == 1 {
        g_mul_imm(1);
    } else {
        g_mul_imm(ty_size(etp));
    }
    g_pop_rcx();
    g_add();
    if ty_kind(etp) == 0 { ops3(0x48, 0x8b, 0x00); }
    g_store_local(xo);
    parse_block(d + 1);
    emit_jmp(stp);
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

# v1.1095: range 端点原子 —— 数字/const 名/裸 enum 成员（比 const_atom 多裸 enum）。
fn range_atom() -> i64 {
    if gv(K_TKIND) == 2 {
        let v: i64 = gv(K_TIVAL);
        next_token();
        return v;
    }
    if gv(K_TKIND) == 1 {
        let csi: i64 = sym_lookup(tokbuf());
        if csi >= 0 {
            if load64(heap + O_SK + csi * 8) == 4 {
                let v: i64 = load64(heap + O_SCV + csi * 8);
                store64(heap + O_SU + csi * 8, 1);
                next_token();
                return v;
            }
        }
        let buf: i64 = heap + O_SCAL + 5700;
        memcpy(buf, tokbuf());
        let ev: i64 = enum_value(buf);
        if ev >= 0 {
            next_token();
            return ev;
        }
    }
    return err_at2("for-in: range endpoint must be a constant", gv(K_LINE), gv(K_COL));
}

# v1.1095: for i in A..B { BODY } —— range 遍历糖。
# 发射：i=A; chk: i>=B→end; BODY; i++; jmp chk
# A/B 支持数字字面量、const 名、enum 成员（const_atom 统一解析）。
fn parse_range_for(vname: i64) -> i64 {
    let lo: i64 = range_atom();
    # 吃 '..'
    if tok_is("..") == 0 { return err_at2("for-in: expected '..' in range", gv(K_LINE), gv(K_COL)); }
    next_token();
    let hi: i64 = range_atom();
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    if sym_dup(vname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let xo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, xo - 8);
    let xid: i64 = sym_add(vname, 1, xo, 0);
    store64(heap + O_STY + xid * 8, ty_int());
    dbg_var(vname, xo, gv(K_LINE), ty_int());
    # i = lo
    g_movabs_rax(lo);
    g_store_local(xo);
    let chk: i64 = new_label();
    let end: i64 = new_label();
    let stp: i64 = new_label();
    loop_push(chk, end, stp);
    place_label(chk);
    # cond: i - hi >= 0 → end
    g_load_local(xo);
    g_push_rax();
    g_movabs_rax(hi);
    g_pop_rcx();
    g_sub();
    g_cmp_rax_0();
    emit_jcc(0x8d, end);
    let bdy: i64 = new_label();
    emit_jmp(bdy);
    # step（continue 跳到这里）：i++
    place_label(stp);
    g_load_local(xo);
    ops3(0x48, 0x83, 0xc0); emit1(1);   # add rax, 1
    g_store_local(xo);
    emit_jmp(chk);
    place_label(bdy);
    parse_block(d + 1);
    emit_jmp(stp);
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

# v1.1070: for x in arr { BODY } —— 数组遍历糖。
# 进入时 tok=元素变量名(x)，peek_in_kw 已确认其后是 'in'。
# 发射：_fi=0; chk: _fi-n>=0→end; x=a[_fi]; BODY; _fi++; jmp chk
# v1 限制：in 右侧必须是数组变量名（不支持任意表达式）。
# v1.1124: for c in <str expr> —— 逐字节迭代。表达式求值一次存槽 so，
# strlen 存槽 no；循环 _fi: c = movzx byte [so+_fi]。
fn parse_for_in_str(vname: i64) -> i64 {
    # 先声明槽再求值（表达式可能用调用，不能占着 CUROFF 未注册状态）——
    # 但 parse_expr 期间 CUROFF 会为调用临时变量下移，先求值再开槽会覆盖；
    # 安全顺序：先求值到 rax → 用 spill 区？不行，跨 body 存活需局部槽。
    # 做法：先开 so/no/_fi 三个槽并注册符号，再 parse_expr 求值（表达式
    # 中间产生的临时都在更深处，不冲突）。
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    if sym_dup(vname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let xo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, xo - 8);
    let xid: i64 = sym_add(vname, 1, xo, 0);
    store64(heap + O_STY + xid * 8, ty_int());
    dbg_var(vname, xo, gv(K_LINE), ty_int());
    let ibuf: i64 = heap + O_SCAL + 5600;
    memcpy(ibuf, "_fi_");
    store8(ibuf + 4, 48 + gv(K_DEPTH));
    store8(ibuf + 5, 0);
    if sym_dup(ibuf) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let fo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, fo - 8);
    let fid: i64 = sym_add(ibuf, 1, fo, 0);
    store64(heap + O_STY + fid * 8, ty_int());
    dbg_var(ibuf, fo, gv(K_LINE), ty_int());
    let so: i64 = gv(K_CUROFF);
    sv(K_CUROFF, so - 8);
    # 表达式求值 → so
    if parse_expr() != 0 { return -1; }
    if ty_kind(R_ETY) != 10 && ty_kind(R_ETY) != 4 { return err_at2("for-in: right side must be a string", gv(K_LINE), gv(K_COL)); }
    accept(")");                 # 括号形式吃 ')'；无括号形式无 ')'
    g_store_local(so);
    # no = strlen(so)
    let no: i64 = gv(K_CUROFF);
    sv(K_CUROFF, no - 8);
    g_load_local(so);
    ops3(0x48, 0x89, 0xc7);          # mov rdi, rax
    let slsym: i64 = sym_lookup_func("strlen");
    if slsym < 0 { return err_at2("for-in str: import \"str.mo\" first", gv(K_LINE), gv(K_COL)); }
    emit_call_patch(slsym);
    CALLD = CALLD - 1;
    g_store_local(no);
    # _fi = 0
    g_movabs_rax(0);
    g_store_local(fo);
    let chk: i64 = new_label();
    let end: i64 = new_label();
    let stp: i64 = new_label();
    let bdy: i64 = new_label();
    loop_push(chk, end, stp);
    place_label(chk);
    # cond: _fi >= no → end
    g_load_local(fo);
    g_push_rax();
    g_load_local(no);
    g_pop_rcx();
    g_sub();
    g_cmp_rax_0();
    emit_jcc(0x8d, end);
    emit_jmp(bdy);
    place_label(stp);
    g_load_local(fo);
    ops3(0x48, 0x83, 0xc0); emit1(1);
    g_store_local(fo);
    emit_jmp(chk);
    place_label(bdy);
    # c = movzx byte [so + _fi]
    g_load_local(so);
    g_push_rax();
    g_load_local(fo);
    g_pop_rcx();
    g_add();
    emit1(0x48); emit1(0x0f); emit1(0xb6); emit1(0x00);   # movzx rax, byte [rax]
    g_store_local(xo);
    parse_block(d + 1);
    emit_jmp(stp);
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

fn parse_for_in(vname: i64) -> i64 {
    next_token();            # 吃 'in'（x 名已在 vname 独立缓冲）
    # v1.1095: range 形式 for i in A..B { BODY } —— 变量 i 走 A..B-1
    if gv(K_TKIND) == 2 {
        return parse_range_for(vname);
    }
    # 常量/enum 起点：range_atom 统一解析（const 名、裸 enum 成员）
    if gv(K_TKIND) == 1 {
        let bufR: i64 = heap + O_SCAL + 5720;
        memcpy(bufR, tokbuf());
        if sym_lookup(bufR) >= 0 {
            if load64(heap + O_SK + sym_lookup(bufR) * 8) == 4 {
                return parse_range_for(vname);
            }
        }
        if enum_value(bufR) >= 0 {
            return parse_range_for(vname);
        }
    }
    # v1.1124: for c in <str> —— str 字面量等表达式按字节迭代
    if gv(K_TKIND) == 3 {
        return parse_for_in_str(vname);
    }
    if gv(K_TKIND) != 1 { return err_at2("for-in: expected array variable", gv(K_LINE), gv(K_COL)); }
    let asym: i64 = sym_lookup(tokbuf());
    if asym < 0 { return undef_err(tokbuf()); }
    let at: i64 = sym_type(asym);
    # v1.1124: str 变量 → 字节迭代
    if ty_kind(at) == 10 {
        return parse_for_in_str(vname);
    }
    # kind3=数组变量；ptr(数组)=嵌套行的行指针（parse_for_in 自身产生）
    if ty_kind(at) == 4 {
        if ty_kind(ty_a(at)) != 3 { return parse_for_in_ptr(vname, tokbuf()); }
        at = ty_a(at);   # 解包：elem=行类型
    } else {
        if ty_kind(at) != 3 { return err_at2("for-in: right side must be an array", gv(K_LINE), gv(K_COL)); }
    }
    # v1.1086: RHS 支持 m[i] 行索引 —— 遍历第 i 行（长度=内维，编译期知）
    let rowoff: i64 = 0;
    let rowidx: i64 = 0;
    next_token();            # 吃数组名（无括号形式；'(' 已在老路径由 accept 兜底）
    if tok_is("[") == 1 {
        next_token();
        if gv(K_TKIND) != 2 { return err_at2("for-in: row index must be a constant", gv(K_LINE), gv(K_COL)); }
        rowidx = gv(K_TIVAL);
        next_token();
        expect("]");
        if ty_kind(ty_a(at)) != 3 { return err_at2("for-in: right side must be a 2-D array", gv(K_LINE), gv(K_COL)); }
        at = ty_a(at);       # 降一层：遍历行内元素
        rowoff = rowidx * ty_size(at);
    }
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    # 元素变量 x
    if sym_dup(vname) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let xo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, xo - 8);
    let xid: i64 = sym_add(vname, 1, xo, 0);
    # 行元素（kind3）存**行地址** → 声明成 ptr(标量)：行内 p[i] 按
    # 标量步长索引（ptr 目标必须是标量，否则行内索引跨整行）
    let xty: i64 = elem_type(at);
    if ty_kind(xty) == 3 {
        let rowlen: i64 = ty_b(xty);    # v1.1090: 行长度（改 xty 前取）
        let e3: i64 = xty;
        while ty_kind(e3) == 3 { e3 = elem_type(e3); }
        xty = ty_ptr(e3);
        # v1.1090: 同时登记行长度变量 _fl_<depth>（内维编译期知），
        # 供内层 for v in row 用作遍历上界
        let fbuf2: i64 = heap + O_SCAL + 5500;
        memcpy(fbuf2, "_fl_");
        store8(fbuf2 + 4, 48 + gv(K_DEPTH));
        store8(fbuf2 + 5, 0);
        if sym_dup(fbuf2) < 0 {
            let f2o: i64 = gv(K_CUROFF);
            sv(K_CUROFF, f2o - 8);
            let f2id: i64 = sym_add(fbuf2, 1, f2o, 0);
            store64(heap + O_STY + f2id * 8, ty_int());
            g_movabs_rax(rowlen);
            g_store_local(f2o);
        }
    }
    store64(heap + O_STY + xid * 8, xty);
    dbg_var(vname, xo, gv(K_LINE), xty);
    # 索引变量 _fiN（按深度区分嵌套）
    let fbuf: i64 = heap + O_SCAL + 5600;
    memcpy(fbuf, "_fi_");
    store8(fbuf + 4, 48 + gv(K_DEPTH));
    store8(fbuf + 5, 0);
    if sym_dup(fbuf) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let fo: i64 = gv(K_CUROFF);
    sv(K_CUROFF, fo - 8);
    let fid: i64 = sym_add(fbuf, 1, fo, 0);
    store64(heap + O_STY + fid * 8, ty_int());
    dbg_var(fbuf, fo, gv(K_LINE), ty_int());
    # _fi = 0
    g_movabs_rax(0);
    g_store_local(fo);
    let chk: i64 = new_label();
    let end: i64 = new_label();
    let stp: i64 = new_label();
    let bdy: i64 = new_label();
    loop_push(chk, end, stp);
    place_label(chk);
    # cond: _fi - n >= 0 → end
    g_load_local(fo);
    g_push_rax();
    g_movabs_rax(ty_b(at));   # 元素个数（编译期常量）
    g_pop_rcx();
    g_sub();                  # rax = _fi - n
    g_cmp_rax_0();
    emit_jcc(0x8d, end);      # jge → end
    emit_jmp(bdy);
    # step（continue 跳到这里）：_fi++
    place_label(stp);
    g_load_local(fo);
    ops3(0x48, 0x83, 0xc0); emit1(1);   # add rax, 1
    g_store_local(fo);
    emit_jmp(chk);
    # body 前置段：x = arr[_fi]
    place_label(bdy);
    load_sym(asym);           # 数组退化首地址（kind3 → lea/movabs）
    if rowoff > 0 {
        g_movabs_rcx(rowoff);
        g_add_rax_rcx();       # m[i]：基址 += i*行stride
    }
    g_push_rax();
    g_load_local(fo);
    # 步长 = 元素大小。v1.1085 修复：**不能只对 2 次幂用移位** ——
    # 二维行 [3] i64 的 stride=24，shl 4 得 16，第二轮 row 从 m[0][2]
    # 起步（打出 3,4,5）。非 2 次幂走 imul（g_mul_imm 内部自判）。
    let esz: i64 = ty_size(elem_type(at));
    if esz > 1 { g_mul_imm(esz); }
    g_pop_rcx();
    g_add();                  # rax = 基址 + _fi*esz
    # 标量元素 load 值；数组/struct 元素保留地址（与 load_sym 退化语义一致）
    if ty_kind(elem_type(at)) != 3 { ops3(0x48, 0x8b, 0x00); }   # mov rax,[rax]：标量 load 值；数组/struct 行保留地址
    g_store_local(xo);
    parse_block(d + 1);
    emit_jmp(stp);
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

fn parse_for() -> i64 {
    # v1.1070: for x in arr {...}（无括号形式）。探测：'for' 后是标识符
    # 且下一 token 是 'in'；命中后 x 名已存 5400 缓冲、tok='in'。
    if gv(K_TKIND) == 1 {
        memcpy(heap + O_SCAL + 5400, tokbuf());
        next_token();
        if tok_is("in") == 1 { return parse_for_in(heap + O_SCAL + 5400); }
    }
    expect("(");   # v1.1072 修复：v1.1070 引入 for-in 时误删了括号形式 '(' 的消费
    # for 自带一层作用域：init 里的 let 属于 for，多个 for 可以各用 i
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    # init
    if tok_is(";") == 0 {
        if accept("let") == 1 {
            parse_let();
        } else {
            # v1.1072: init 支持裸赋值 `i = 0` / `i += 1`（ident 开头才探测）
            # v1.1072: parse_for_init()==1 表示已消费完 init（含 ';'），落 cond。
            # ==0 表示不是赋值 → set_pos 回退走普通 parse_expr。
            if gv(K_TKIND) == 1 {
                if parse_for_init() == 0 { set_back(gv(K_TOKPOS)); parse_expr(); expect(";"); }
            } else {
                parse_expr();
                expect(";");
            }
        }
    } else {
        next_token();
    }
    let chk: i64 = new_label();
    let end: i64 = new_label();
    let stp: i64 = new_label();
    let bdy: i64 = new_label();
    loop_push(chk, end, stp);
    place_label(chk);
    # cond
    if tok_is(";") == 1 {
        g_movabs_rax(1);
    } else {
        parse_expr();
    }
    expect(";");
    g_cmp_rax_0();
    emit_jcc(0x84, end);
    emit_jmp(bdy);
    # step（continue 跳到这里）
    place_label(stp);
    if tok_is(")") == 0 { parse_for_step(); }
    expect(")");
    emit_jmp(chk);
    # body
    place_label(bdy);
    parse_block(d + 1);
    emit_jmp(stp);
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    return 0;
}

# ---------------------------------------------------------------------------
#  switch
# ---------------------------------------------------------------------------
#  switch (e) { case C: ... case D: ... default: ... }
#
#  两条**与 C 不同**、且是有意为之的语义（理由见 docs/switch.md）：
#    · case 之间不穿透：每个 case 末尾隐含 break，要穿透必须写 fallthrough;
#      C 的隐式穿透让"漏写 break"成为一类既不报错也不崩溃的错误。
#    · continue 作用于外层循环（与 C 一致）——所以 switch 层对 continue
#      透明，它压栈时 cnt 传 -1，parse_continue 会往下跳。
#
#  代码生成在两种策略间自适应（这才是它不只是 if/else 语法糖的地方）：
#    · 跳转表：case 值够密（n>=4 且 范围 <= 4*n）→ O(1)，但要占 8*范围 字节
#    · 比较链：稀疏或 case 太少 → O(n)，不占额外体积
# ---------------------------------------------------------------------------

# 按常量名查 enum 值（不带 enum 名）。返回表下标，-1 = 不是 enum 常量。
fn enum_value(cname: i64) -> i64 {
    let i: i64 = 0;
    while i < load64(heap + O_ECNT) {
        if streq(heap + O_NAMES + load64(heap + O_ECNAME + i * 8), cname) == 1 {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

# 🔴 这三个是**全局**而不是局部数组，因为汇编 seed 不支持局部数组声明
#    （`let a: [8] i64 = 0;` 在 seed 下直接 syntax error）。
#    于是用「栈式分配」保证嵌套安全：每个 switch 进入时记下 base，
#    只用 [base, base+128) 这一段，退出时把 SWTOP 恢复成 base。
#    直接用固定的全局下标会被内层 switch 覆盖 —— 本项目已多次栽在
#    "共享临时被嵌套调用抹掉"上，这里从一开始就避开。
# 用手工 heap 偏移而不是 `var A: [1024] i64`：后者在**汇编 seed** 下
# 直接 syntax error（seed 只覆盖 compiler.mo 实际用到的语法子集，
# 而 compiler.mo 从来不声明数组）。所以这里沿用 O_ 偏移的既有做法。
# 落在 O_NEST(8724224) 之后、O_SU(9000000) 之前的空档里。
var O_SWV:   i64 = 8750000;   # case 值：(base + i) * 8，1024 项 = 8192 字节
var O_SWL:   i64 = 8760000;   # case 标签号，同上
var O_SWTOP: i64 = 8768000;   # 下一个 switch 的基址（栈式分配）
var O_SWC:   i64 = 8768008;   # sw_const 的输出槽
var O_SWNB:  i64 = 8768100;   # sw_const 的名字缓冲（64 字节）
var SWSTR:   i64 = 8770000;   # v1.1047: case 是否字符串（n*8，128 项）
var O_SWG:   i64 = 8771000;   # v1.1099: match 臂是否带守卫 if（n*8，128 项）
var O_SWGL:  i64 = 8772000;   # v1.1099: 守卫臂的匹配点标签（n*8，128 项）
var O_SWSM:  i64 = 8773000;   # v1.1103: match struct 模式区。每臂 64 槽：
                              #   槽0=struct si（-1=非 struct 模式），槽1=字段数，
                              #   槽 2+2k=字段 offset，槽 3+2k=字段常量值。
                              #   128 臂 × 64 槽 × 8 = 65536 字节（至 8838536）。
var O_SWSN:  i64 = 8839000;   # v1.1103: struct 模式结构体类型（ty_struct 值，n*8，128 项）
var O_SWVB:  i64 = 8840000;   # v1.1107: 守卫臂绑定名 intern id（n*8，128 项）
var O_SWSB:  i64 = 8840000;   # v1.1104: struct 模式字段**绑定名**（intern id，臂×31；0=常量比较）

# 读一个编译期常量写入 *out：整数字面量 / 前导负号 / enum 常量。
# 返回 1 成功、0 失败。**失败时不报错**，由调用方决定怎么提示。
fn sw_const(out: i64) -> i64 {
    let nb: i64 = heap + O_SWNB;
    let neg: i64 = 0;
    if tok_is("-") == 1 { neg = 1; next_token(); }
    if gv(K_TKIND) == 2 {
        let v: i64 = gv(K_TIVAL);
        if neg == 1 { v = 0 - v; }
        next_token();
        # 墨语言没有负字面量，负数只能写 `0 - 3`。这里把连续的 +/- 折叠掉。
        # 🔴 不折叠的话 `case 0 - 3:` 会被取成 **0**，而 `case 0 - 2:` 也
        #    是 0 —— 于是只报一句 duplicate case，看不出真正的原因。
        #    折不动就返回 0（由调用方报"必须是编译期常量"），绝不静默。
        # v1.999：后缀接受 const/enum 原子（case 0 - N）
        # v1.1092：扩展 * / （乘除折叠，与 + - 同级从左到右）
        while tok_is("-") == 1 || tok_is("+") == 1 || tok_is("*") == 1 || tok_is("/") == 1 {
            let do_: i64 = 0 - 1;
            if tok_is("-") == 1 { do_ = 0; }
            if tok_is("+") == 1 { do_ = 1; }
            if tok_is("*") == 1 { do_ = 2; }
            if do_ < 0 { do_ = 3; }   # '/'
            next_token();
            let sa2: i64 = 0;
            if gv(K_TKIND) == 2 { sa2 = gv(K_TIVAL); next_token(); }
            else {
                sa2 = const_atom();
                if sa2 == 0 && gv(K_TKIND) != 2 { return 0; }
            }
            if do_ == 0 { v = v - sa2; }
            if do_ == 1 { v = v + sa2; }
            if do_ == 2 { v = v * sa2; }
            if do_ == 3 { v = v / sa2; }
        }
        store64(out, v);
        return 1;
    }
    if neg == 0 {
        # 括号 case 表达式（v1.998）：`(N * 2) - 1` —— 整个交给 const_expr
        if tok_is("(") == 1 {
            next_token();
            let v: i64 = const_expr();
            if tok_is(")") == 0 { return 0; }
            next_token();
            # 括号后的 +/- 后缀折叠（v1.998）：case (N * 2) - 1
            while tok_is("-") == 1 || tok_is("+") == 1 {
                let po: i64 = tok_is("-");
                next_token();
                let pa: i64 = const_atom();
                if po == 1 { v = v - pa; } else { v = v + pa; }
            }
            store64(out, v);
            return 1;
        }
        if gv(K_TKIND) == 1 {
            memcpy(nb, tokbuf());
            next_token();
            let e: i64 = enum_value(nb);
            if e >= 0 {
                let v: i64 = load64(heap + O_EVAL + e * 8);
                # v1.1051/v1.1092: enum case 的 +/-/*/ 后缀折叠
                while tok_is("-") == 1 || tok_is("+") == 1 || tok_is("*") == 1 || tok_is("/") == 1 {
                    let op2: i64 = 0 - 1;
                    if tok_is("-") == 1 { op2 = 0; }
                    if tok_is("+") == 1 { op2 = 1; }
                    if tok_is("*") == 1 { op2 = 2; }
                    if op2 < 0 { op2 = 3; }
                    next_token();
                    let a2: i64 = 0;
                    if gv(K_TKIND) == 2 { a2 = gv(K_TIVAL); next_token(); }
                    else { a2 = const_atom(); }
                    if op2 == 0 { v = v - a2; }
                    if op2 == 1 { v = v + a2; }
                    if op2 == 2 { v = v * a2; }
                    if op2 == 3 { v = v / a2; }
                }
                store64(out, v);
                return 1;
            }
            # const（kind 4）做 case 标签（v1.977）。
            # 🔴 进入此分支时名字 token 已被消费（上面 next_token）。
            #    v1.979：支持 case A + 1 后缀折叠——消费 +/- 与数字/const 原子，
            #    与数字路径的折叠对称。
            let csi: i64 = sym_lookup(nb);
            if csi >= 0 {
                if load64(heap + O_SK + csi * 8) == 4 {
                    store64(heap + O_SU + csi * 8, 1);
                    let v: i64 = load64(heap + O_SCV + csi * 8);
                    while tok_is("-") == 1 || tok_is("+") == 1 || tok_is("*") == 1 || tok_is("/") == 1 {
                        let op: i64 = 0 - 1;
                        if tok_is("-") == 1 { op = 0; }
                        if tok_is("+") == 1 { op = 1; }
                        if tok_is("*") == 1 { op = 2; }
                        if op < 0 { op = 3; }
                        next_token();
                        let a: i64 = 0;
                        if gv(K_TKIND) == 2 { a = gv(K_TIVAL); next_token(); }
                        else { a = const_atom(); }
                        if op == 0 { v = v - a; }
                        if op == 1 { v = v + a; }
                        if op == 2 { v = v * a; }
                        if op == 3 { v = v / a; }
                    }
                    store64(out, v);
                    return 1;
                }
            }
        }
    }
    return 0;
}

# 词法扫描 switch 主体，收集 case 常量。
#
# **只走词法、不做任何解析** —— 于是嵌套 switch 不会互相干扰 token 位置。
# 对照 docs/for.md：嵌套 for 的第一版用"解析时 set_pos 回退"，外层记下的
# 回退位置被内层的 set_pos 覆盖，报 syntax error 且行列超出文件末尾。
#
# 返回 case 个数；-1 = 超过上限；-2 = 有 case 不是编译期常量 / 结构不对。
fn sw_scan(vals: i64) -> i64 {
    let n: i64 = 0;
    let d: i64 = 1;
    next_token();                       # 越过 '('
    while d > 0 {                       # 跳过整个表达式（里面可能有 {1,2}）
        if gv(K_TKIND) == 0 { return 0 - 2; }   # EOF：不停下就会死循环
        if tok_is("(") == 1 { d = d + 1; }
        if tok_is(")") == 1 { d = d - 1; }
        next_token();
    }
    if tok_is("{") == 0 { return 0 - 2; }
    next_token();
    d = 1;
    while d > 0 {
        if gv(K_TKIND) == 0 { return 0 - 2; }   # EOF：不停下就会死循环
        let iscase: i64 = 0;
        let skipped: i64 = 0;
        if gv(K_TKIND) == 1 {
            if streq(tokbuf(), "case") == 1 { iscase = 1; }
            # 🔴 嵌套 switch 必须**整段跳过**，不能照着 case 收。
            #    扫描是纯词法的，看不出 case 属于哪一层：外层会把内层
            #    的 case 一起收进来，于是 switch{case 1: switch{case 1:}}
            #    被当成"case 1 出现两次"而误报 duplicate。
            if streq(tokbuf(), "switch") == 1 {
                # 🔴 计数必须从**开括号之后**开始。第一版在 next_token()
                #    越过 'switch' 之后就进循环，于是当前那个 '(' 自己
                #    又把 e 加成了 2 —— 要两个 ')' 才归零，扫描一路吃到
                #    文件末尾也找不到，在 EOF 上**死循环**（不报错）。
                #    嵌套 switch 的用例就是这样挂住的。
                next_token();                   # 越过 'switch'
                next_token();                   # 越过 '('
                let e: i64 = 1;
                while e > 0 {                   # 跳过 (...)
                    if gv(K_TKIND) == 0 { return 0 - 2; }
                    if tok_is("(") == 1 { e = e + 1; }
                    if tok_is(")") == 1 { e = e - 1; }
                    next_token();
                }
                next_token();                   # 越过 '{'
                e = 1;
                while e > 0 {                   # 跳过 {...}
                    if gv(K_TKIND) == 0 { return 0 - 2; }
                    if tok_is("{") == 1 { e = e + 1; }
                    if tok_is("}") == 1 { e = e - 1; }
                    next_token();
                }
                skipped = 1;
            }
        }
        if iscase == 1 {
            next_token();
            if n >= 128 { return 0 - 1; }
            if tok_is_strlit() == 1 {
                # v1.1047: 字符串 case —— 存数据段绝对地址（与 str 表达式同形态）+ 标记
                store64(heap + SWSTR + n * 8, 1);
                store64(vals + n * 8, gv(K_TIVAL));
                next_token();
            } else {
                store64(heap + SWSTR + n * 8, 0);
                if sw_const(vals + n * 8) == 0 { return 0 - 2; }
            }
            n = n + 1;
        } else {
            # 🔴 跳过嵌套 switch 之后**不能再推进**：跳过的终点正好落在
            #    内层 '}' 之后的那个 token 上（典型就是外层的下一个
            #    case）。多推进一次就会把它整个吃掉 —— 于是外层少收一个
            #    case，第二遍解析时 i 走到 n 还遇到 case，报
            #    "case 与扫描结果不一致"（而真正的原因在这里，看不出来）。
            if skipped == 0 {
                if tok_is("{") == 1 { d = d + 1; }
                if tok_is("}") == 1 { d = d - 1; }
                next_token();
            }
        }
    }
    return n;
}

# switch 报错统一出口：跳过与 switch 配对的 {...} 再报错。
# 🔴 err_atp 软化（v1.971）后返回 -1，若不消费 switch 的 {...} token，
#    上层语句循环重读同一 token → 死循环（v1.976 及以前即触发）。
fn sw_fail(msg: i64, base: i64) -> i64 {
    store64(heap + O_SWTOP, base);
    let sd: i64 = 0;
    while tok_is("{") == 0 {
        if gv(K_TKIND) == 0 { break; }
        next_token();
    }
    if tok_is("{") == 1 {
        next_token();
        sd = 1;
        while sd > 0 {
            if gv(K_TKIND) == 0 { break; }
            if tok_is("{") == 1 { sd = sd + 1; }
            if tok_is("}") == 1 { sd = sd - 1; }
            next_token();
        }
    }
    return err_atp(msg, gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
}

fn parse_switch() -> i64 {
    let base: i64 = load64(heap + O_SWTOP);
    if base + 128 > 1024 {
        return err_atp("switch: 嵌套过深（上限 8 层）", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    store64(heap + O_SWTOP, base + 128);
    let vals: i64 = heap + O_SWV + base * 8;
    let lbls: i64 = heap + O_SWL + base * 8;
    let save: i64 = gv(K_TOKPOS);
    let n: i64 = sw_scan(vals);
    if n < 0 {
        return sw_fail("switch: case 必须是编译期常量（整数或 enum）", base);
    }
    set_back(save);
    # v1.1047: 任一 case 为字符串 → 字符串 switch（要求全部 case 均为字符串）
    let sws: i64 = 0;
    let qi: i64 = 0;
    while qi < n {
        if load64(heap + SWSTR + qi * 8) == 1 { sws = 1; }
        else { if sws == 1 { return sw_fail("switch: 字符串与整数 case 不能混用", base); } }
        qi = qi + 1;
    }

    let mn: i64 = 0;
    let mx: i64 = 0;
    if n > 0 { mn = load64(vals); mx = load64(vals); }
    let i: i64 = 1;
    while i < n {
        let v: i64 = load64(vals + i * 8);
        if v < mn { mn = v; }
        if v > mx { mx = v; }
        # 重复 case：C 里是错误。静默取后者会让前一个分支永远不可达。
        let j: i64 = 0;
        while j < i {
            if load64(vals + j * 8) == v {
                return sw_fail("switch: duplicate case value", base);
            }
            j = j + 1;
        }
        i = i + 1;
    }
    # cmp rax, imm32 / sub rax, imm32 都只接受 imm32，超出会**静默截断**。
    i = 0;
    while i < n {
        if load64(vals + i * 8) > 2147483647 { return sw_fail("switch: case 值超出 32 位", base); }
        if load64(vals + i * 8) < 0 - 2147483648 { return sw_fail("switch: case 值超出 32 位", base); }
        i = i + 1;
    }

    # 跳转表判据：至少 4 个 case、范围不超过 4×n（够密）、表不超过 1024 项。
    # 稀疏值建表是纯浪费：case 1 / case 1000000 会生成 8MB 的表。
    let use_tbl: i64 = 0;
    if n >= 4 {
        if mx - mn + 1 <= n * 4 {
            if mx - mn + 1 <= 1024 { use_tbl = 1; }
        }
    }

    let end: i64 = new_label();
    let dflt: i64 = new_label();
    let hasdflt: i64 = 0;
    i = 0;
    while i < n { store64(lbls + i * 8, new_label()); i = i + 1; }

    expect("(");
    parse_expr();                       # switch 值 → rax
    expect(")");

    # switch 自带一层作用域：各 case 里 let 的变量互不干扰
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    # cnt 传 -1 = "这层不是循环"，continue 会往下找真正的循环
    loop_push(0 - 1, end, 0 - 1);

    let timm: i64 = 0;                  # movabs 立即数在代码里的偏移（最后回填）
    if use_tbl == 1 {
        # sub rax, mn
        #   无符号视角下 val < mn 会**回绕**成巨大的正数，于是下面一条 ja
        #   同时抓住了"太小"和"太大" —— 只需要两条指令而不是四次比较。
        emit1(0x48); emit1(0x2d); emit4(mn);
        # cmp rax, (mx - mn)
        emit1(0x48); emit1(0x3d); emit4(mx - mn);
        emit_jcc(0x87, dflt);           # ja（无符号 >）
        # movabs rcx, <表地址>   —— 表在最后，地址此刻还不知道，先占位
        emit1(0x48); emit1(0xb9);
        timm = gv(K_CLEN);
        emit8(0);
        # jmp [rcx + rax*8]
        emit1(0xff); emit1(0x24); emit1(0xc1);
    } else {
        if sws == 1 {
            # v1.1047: 字符串 switch —— 逐 case 调 g_str_eq 约定(rcx=左串, rax=右串)
            ops3(0x49, 0x89, 0xc3);                    # v1.1047: mov r11, rax —— 判别串保值（g_str_eq 破坏 rax/rcx）
            i = 0;
            while i < n {
                ops3(0x4c, 0x89, 0xd9);                # mov rcx, r11 (判别串)
                g_movabs_rax(load64(vals + i * 8));        # movabs rax, case 串地址
                g_str_eq(1);                               # rax = (equal ? 1 : 0)
                ops2(0x85, 0xc0);                          # test eax, eax
                emit_jcc(0x85, load64(lbls + i * 8));      # jne → case
                i = i + 1;
            }
            emit_jmp(dflt);
        } else {
            i = 0;
            while i < n {
                emit1(0x48); emit1(0x3d); emit4(load64(vals + i * 8));   # cmp rax, imm32
                emit_jcc(0x84, load64(lbls + i * 8));                    # je
                i = i + 1;
            }
            emit_jmp(dflt);
        }
    }

    expect("{");
    i = 0;
    let fell: i64 = 0;                  # 上一个 case 要求穿透到下一个
    while tok_is("}") == 0 {
        if accept("case") == 1 {
            if i >= n { return sw_fail("switch: case 与扫描结果不一致", base); }
            # 即使上一个 case 写了 fallthrough 也要放标签：顺序流正好落在这里，
            # 而跳转表里这一项也仍然要指向它。
            place_label(load64(lbls + i * 8));
            fell = 0;
            if tok_is_strlit() == 1 {
                # v1.1047: 字符串 case —— 发射时值已在 sw_scan 录入，这里只吃 token。
                # 但必须与 sw_scan 的顺序一致：SWSTR[i] 已由扫描置 1。
                if i >= n { return sw_fail("switch: case 与扫描结果不一致", base); }
                if load64(heap + SWSTR + i * 8) != 1 { return sw_fail("switch: 字符串与整数 case 不能混用", base); }
                next_token();
            } else {
                if sw_const(heap + O_SWC) == 0 {
                    return sw_fail("switch: case 必须是编译期常量", base);
                }
            }
            expect(":");
            let cd: i64 = d + 1;
            sv(K_DEPTH, cd);
            let any: i64 = 0;
            while tok_is("}") == 0 {
                if tok_is("case") == 1 { break; }
                if tok_is("default") == 1 { break; }
                if accept("fallthrough") == 1 {
                    expect(";");
                    fell = 1;
                    break;
                }
                parse_stmt();
                any = 1;
            }
            sym_pop_scope(cd);
            sv(K_DEPTH, d);
            # 空 case（`case 1: case 2: body`）在 C 里是穿透，这里必须同义：
            # 一条语句都没有 → 视为隐式穿透，不能补 jmp end。
            if any == 0 { fell = 1; }
            if fell == 0 { emit_jmp(end); }
            i = i + 1;
        } else {
            if accept("default") == 1 {
                expect(":");
                hasdflt = 1;
                place_label(dflt);
                let dd: i64 = d + 1;
                sv(K_DEPTH, dd);
                while tok_is("}") == 0 {
                    if tok_is("case") == 1 { break; }
                    parse_stmt();
                }
                sym_pop_scope(dd);
                sv(K_DEPTH, d);
                emit_jmp(end);
            } else {
                return sw_fail("switch: expected 'case' or 'default'", base);
            }
        }
    }
    next_token();                       # 越过 '}'
    # 🔴 只有**没有** default 时才在这里放 dflt。第一版无条件放了一次，
    #    于是已有的 default 标签被覆盖成 end 的位置 —— "没命中的 case"
    #    和 "default" 都直接跳到出口，default 的整段代码变成死代码。
    #    症状是 default 的值永远取不到（实测 got 0, want 777），
    #    既不报错也不崩。
    if hasdflt == 0 { place_label(dflt); }
    place_label(end);

    if use_tbl == 1 {
        # 表放在 end **之后**：end 前面一定有 jmp，顺序流不会穿过表。
        # 但 end 之后顺序流会继续往下走，所以还要再跳一次绕过表。
        let after: i64 = new_label();
        emit_jmp(after);
        let tp: i64 = gv(K_CLEN);
        let tsz: i64 = mx - mn + 1;
        let k: i64 = 0;
        while k < tsz { emit8(0); k = k + 1; }
        place_label(after);
        # 🔴 绝对地址是 4194304 + **176** + 代码内偏移：段的 vaddr 是
        #    0x400000，而代码在段内从 ELF 头之后（64+56*2=176）才开始。
        #    第一版漏了 176，于是表和表项全部指向偏前 176 字节的位置 ——
        #    跳转表路径**无一例外**段错误，而比较链路径全对。
        #    注意：现有的 jmp/jcc 都是**相对**偏移，所以这个偏差此前
        #    从未暴露过 —— 只有引入绝对地址才发现得了。
        let cb: i64 = 4194304 + 176;
        # 回填：先全部指向 default，再按 case 值覆盖对应槽
        k = 0;
        while k < tsz {
            store64(heap + O_CODE + tp + k * 8,
                    cb + load64(heap + O_LB + dflt * 8));
            k = k + 1;
        }
        k = 0;
        while k < n {
            let slot: i64 = load64(vals + k * 8) - mn;
            store64(heap + O_CODE + tp + slot * 8,
                    cb + load64(heap + O_LB + load64(lbls + k * 8) * 8));
            k = k + 1;
        }
        store64(heap + O_CODE + timm, cb + tp);
    }
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    store64(heap + O_SWTOP, base);
    return 0;
}

# ---------------------------------------------------------------------------
#  v1.1098: match 表达式
#  match e { PAT => { ... }  PAT => { ... }  _ => { ... } }
#  PAT = 数字 / enum 成员 / const 名 / _（else）。比较链发射（无跳转表），
#  每臂隐式 break（无穿透）。复用 switch 的栈式 case 表（O_SWV/O_SWL）。
# ---------------------------------------------------------------------------
fn mt_scan(vals: i64) -> i64 {
    let n: i64 = 0;
    # 'match' 已被 parse_stmt 的 accept 消费；这里从判别表达式开始
    while tok_is("{") == 0 {
        if gv(K_TKIND) == 0 { return 0 - 2; }
        next_token();
    }
    next_token();                       # 吃 '{'
    let d: i64 = 1;
    while d > 0 {
        if gv(K_TKIND) == 0 { return 0 - 2; }
        # 嵌套 match 整段跳过
        if gv(K_TKIND) == 1 && streq(tokbuf(), "match") == 1 {
            next_token();
            while tok_is("{") == 0 {
                if gv(K_TKIND) == 0 { return 0 - 2; }
                next_token();
            }
            next_token();
            let e: i64 = 1;
            while e > 0 {
                if gv(K_TKIND) == 0 { return 0 - 2; }
                if tok_is("{") == 1 { e = e + 1; }
                if tok_is("}") == 1 { e = e - 1; }
                next_token();
            }
            continue;
        }
        if tok_is("}") == 1 { d = d - 1; next_token(); continue; }
        # v1.1099: 守卫 `PAT if cond =>` —— 词法跳过 if 条件（括号平衡）。
        # n 已 ++（收臂时），守卫标记写 n-1。
        if gv(K_TKIND) == 1 && streq(tokbuf(), "if") == 1 {
            next_token();
            store64(heap + O_SWG + (n - 1) * 8, 1);
            let pd: i64 = 0;
            while tok_is("=>") == 0 {
                if gv(K_TKIND) == 0 { return 0 - 2; }
                if tok_is("(") == 1 { pd = pd + 1; }
                if tok_is(")") == 1 { pd = pd - 1; }
                next_token();
            }
        }
        if tok_is("=>") == 1 {
            next_token();               # 箭头（模式已收）
            if tok_is("{") == 1 {       # 跳过臂体 {...}
                next_token();
                let b: i64 = 1;
                while b > 0 {
                    if gv(K_TKIND) == 0 { return 0 - 2; }
                    if tok_is("{") == 1 { b = b + 1; }
                    if tok_is("}") == 1 { b = b - 1; }
                    next_token();
                }
            } else {
                # v1.1100: 表达式臂 —— 跳到深度 0 的 ',' 或 '}'（括号平衡）
                let pd2: i64 = 0;
                while tok_is(",") == 0 && tok_is("}") == 0 {
                    if gv(K_TKIND) == 0 { return 0 - 2; }
                    if tok_is("(") == 1 { pd2 = pd2 + 1; }
                    if tok_is(")") == 1 { pd2 = pd2 - 1; }
                    next_token();
                }
                if tok_is(",") == 1 { next_token(); }
            }
            continue;
        }
        if gv(K_TKIND) == 3 {
            # v1.1099: 字符串模式 —— 存数据段串地址（同 str 表达式形态）
            if n >= 128 { return 0 - 1; }
            store64(vals + n * 8, gv(K_TIVAL));
            store64(heap + SWSTR + n * 8, 1);
            next_token();
            n = n + 1;
        } else {
        if gv(K_TKIND) == 2 {
            if n >= 128 { return 0 - 1; }
            store64(vals + n * 8, gv(K_TIVAL));
            store64(heap + SWSTR + n * 8, 0);   # v1.1102: 🔴 清残留（上一函数的字符串模式标记会让本函数数字 match 误走 g_str_eq 链，pth/pti 探针实证）
            next_token();
            n = n + 1;
        } else {
        if gv(K_TKIND) == 1 {
            # _ = default 不收；数字/enum/const 模式 sw_const 折叠
            if streq(tokbuf(), "_") == 1 { next_token(); continue; }
            # v1.1103: struct 模式 —— `P { x: 1; y: 2; }`（P 是 struct 名）
            if st_lookup(tokbuf()) >= 0 {
                let smbase: i64 = n * 64;
                store64(heap + O_SWSM + (smbase + 0) * 8, st_lookup(tokbuf()));
                store64(vals + n * 8, 0);
                store64(heap + SWSTR + n * 8, 0);
                next_token();
                if tok_is("{") == 0 { return 0 - 2; }
                next_token();
                let cnt: i64 = 0;
                while tok_is("}") == 0 {
                    if gv(K_TKIND) == 0 { return 0 - 2; }
                    # 字段名: 常量值 ;
                    memcpy(scratch3(), tokbuf());   # 字段名缓冲（st_field 要地址）
                    let fnm: i64 = scratch3();
                    next_token();
                    expect(":");
                    let ssi: i64 = load64(heap + O_SWSM + smbase * 8);
                    let fidx: i64 = st_field(ssi, fnm);
                    let foff: i64 = st_field_off(ssi, fidx);
                    # v1.1106: 嵌套 struct 模式 —— 字段值是 struct 名 → 展开一层
                    # （子字段 offset = 外层 foff + 子 off；绑定名同样下沉）
                    if gv(K_TKIND) == 1 && st_lookup(tokbuf()) >= 0 {
                                                # v1.1109: 多级嵌套 —— struct 栈下钻（最多 8 层）
                        let nsis: [8] i64;
                        let offs: [8] i64;
                        let depth: i64 = 0;
                        nsis[0] = st_lookup(tokbuf());
                        offs[0] = foff;
                        next_token();
                        if tok_is("{") == 0 { return 0 - 2; }
                        next_token();
                        while depth >= 0 {
                            if gv(K_TKIND) == 0 { return 0 - 2; }
                            if tok_is("}") == 1 {
                                depth = depth - 1;
                                next_token();
                                if depth >= 0 {
                                    if tok_is(";") == 1 { next_token(); }   # 吃本层最后字段的 ';'
                                }
                                continue;
                            }
                            memcpy(scratch3(), tokbuf());
                            let nfo: i64 = offs[depth] + st_field_off(nsis[depth], st_field(nsis[depth], scratch3()));
                            next_token();
                            expect(":");
                            # 字段值又是 struct → 下钻一层
                            if gv(K_TKIND) == 1 && st_lookup(tokbuf()) >= 0 {
                                if depth >= 7 { return 0 - 2; }
                                depth = depth + 1;
                                nsis[depth] = st_lookup(tokbuf());
                                offs[depth] = nfo;
                                next_token();
                                if tok_is("{") == 0 { return 0 - 2; }
                                next_token();
                                continue;
                            }
                            if gv(K_TKIND) == 1 {
                                memcpy(scratch3(), tokbuf());
                                store64(heap + O_SWSB + (smbase/64*31 + cnt) * 8, intern(scratch3()));
                                store64(heap + O_SWSM + (smbase + 3 + cnt * 2) * 8, 0 - 1);
                                next_token();
                            } else {
                                store64(heap + O_SWSB + (smbase/64*31 + cnt) * 8, 0);
                                if sw_const(heap + O_SWC) == 0 { return 0 - 2; }
                                store64(heap + O_SWSM + (smbase + 3 + cnt * 2) * 8, load64(heap + O_SWC));
                            }
                            store64(heap + O_SWSM + (smbase + 2 + cnt * 2) * 8, nfo);
                            cnt = cnt + 1;
                            next_token();       # 吃 ';'
                        }
                        next_token();           # 吃外层字段的 ';'
                                                continue;               # 🔴 cnt 已在子循环内加过，不再加
                    } else {
                    store64(heap + O_SWSM + (smbase + 2 + cnt * 2) * 8, foff);
                    # v1.1104: 字段值为标识符 → 绑定变量（capture）
                    if gv(K_TKIND) == 1 {
                        # 🔴 scratch2 存着推断 let 的变量名（parse_let 记下，声明
                        # 在 parse_expr 之后 sym_add）—— 必须用 scratch3
                        memcpy(scratch3(), tokbuf());   # 绑定名
                        store64(heap + O_SWSB + (smbase/64*31 + cnt) * 8, intern(scratch3()));
                        store64(heap + O_SWSM + (smbase + 3 + cnt * 2) * 8, 0 - 1);
                        next_token();
                    } else {
                        store64(heap + O_SWSB + (smbase/64*31 + cnt) * 8, 0);
                        if sw_const(heap + O_SWC) == 0 { return 0 - 2; }
                        store64(heap + O_SWSM + (smbase + 3 + cnt * 2) * 8, load64(heap + O_SWC));
                    }
                    }
                    cnt = cnt + 1;
                    next_token();               # 吃 ';'
                }
                next_token();                   # 吃 '}'
                store64(heap + O_SWSM + (smbase + 1) * 8, cnt);
                store64(heap + O_SWSN + n * 8, 1);
                n = n + 1;
                continue;
            }
            if n >= 128 { return 0 - 1; }
            store64(heap + SWSTR + n * 8, 0);
            # v1.1107: 守卫绑定模式 `y if cond =>` —— 模式是**未定义标识符**
            # （sym_lookup<0；const/enum 名 sym_lookup>=0 走 sw_const —— 280 回归实证）
            if gv(K_TKIND) == 1 && streq(tokbuf(), "_") != 1 {
                memcpy(scratch1(), tokbuf());
            }
            if gv(K_TKIND) == 1 && streq(tokbuf(), "_") != 1 && sym_lookup(scratch1()) < 0 && enum_value(scratch1()) < 0 {
                memcpy(scratch3(), tokbuf());
                store64(heap + O_SWVB + n * 8, intern(scratch3()));
                next_token();               # 吃绑定名
                if gv(K_TKIND) == 1 && streq(tokbuf(), "if") == 1 {
                    next_token();
                    store64(heap + O_SWG + n * 8, 1);
                    let pd7: i64 = 0;
                    while tok_is("=>") == 0 {
                        if gv(K_TKIND) == 0 { return 0 - 2; }
                        if tok_is("(") == 1 { pd7 = pd7 + 1; }
                        if tok_is(")") == 1 { pd7 = pd7 - 1; }
                        next_token();
                    }
                    store64(vals + n * 8, 0);
                    n = n + 1;
                    continue;
                }
                # 不是守卫 —— 非常量标识符，报错
                return 0 - 2;
            }
            if sw_const(vals + n * 8) == 0 { return 0 - 2; }
            n = n + 1;
        } else {
            next_token();
        }
        }
        }
    }
    return n;
}

fn parse_match() -> i64 {
    let base: i64 = load64(heap + O_SWTOP);
    if base + 128 > 1024 {
        return err_atp("match: 嵌套过深（上限 8 层）", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    store64(heap + O_SWTOP, base + 128);
    let vals: i64 = heap + O_SWV + base * 8;
    let lbls: i64 = heap + O_SWL + base * 8;
    let save: i64 = gv(K_TOKPOS);
    # v1.1107: 🔴 清跨 match 残留（SWG/SWVB/SWSTR/SWSN 是全局 n 槽，上一 match 的
    # 标记会让本 match 误走守卫/字符串/struct 路径——c 探针实证）
    let cz: i64 = 0;
    while cz < 128 {
        store64(heap + O_SWG + cz * 8, 0);
        store64(heap + O_SWVB + cz * 8, 0);
        store64(heap + SWSTR + cz * 8, 0);
        store64(heap + O_SWSN + cz * 8, 0);
        cz = cz + 1;
    }
    let n: i64 = mt_scan(vals);
    if n < 0 {
        store64(heap + O_SWTOP, base);
        return err_atp("match: 模式必须是编译期常量（数字/enum/const/_）", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    set_back(save);
    let qi: i64 = 0;
    while qi < n {
        if load64(heap + O_SWG + qi * 8) == 1 { qi = qi + 1; continue; }   # 守卫臂豁免
        let qj: i64 = 0;
        while qj < qi {
            if load64(vals + qi * 8) == load64(vals + qj * 8) && load64(heap + O_SWSN + qi * 8) != 1 && load64(heap + O_SWSN + qj * 8) != 1 && load64(heap + O_SWG + qi * 8) != 1 && load64(heap + O_SWG + qj * 8) != 1 {
                store64(heap + O_SWTOP, base);
                return err_atp("match: duplicate pattern value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            qj = qj + 1;
        }
        qi = qi + 1;
    }
    let end: i64 = new_label();
    let dflt: i64 = new_label();
    let hasdflt: i64 = 0;
    let i: i64 = 0;
    while i < n {
        store64(lbls + i * 8, new_label());
        if load64(heap + O_SWG + i * 8) == 1 { store64(heap + O_SWGL + i * 8, new_label()); }
        i = i + 1;
    }
    next_token();                       # 越过 'match'（路由是探测式，不消费）
    parse_expr();                       # 判别值 → rax
    # v1.1108: 有绑定守卫臂时预留判别槽并存值
    let hasvb: i64 = 0;
    let hv: i64 = 0;
    while hv < n {
        if load64(heap + O_SWVB + hv * 8) != 0 { hasvb = 1; }
        hv = hv + 1;
    }
    let vboff: i64 = 0;
    if hasvb == 1 {
        vboff = gv(K_CUROFF) - 8;
        sv(K_CUROFF, vboff);
        g_store_local(vboff);
    }
    # v1.1099: 混合约束（同 switch）—— 任一字符串模式则全部必须为字符串
    let msws: i64 = 0;
    let mq: i64 = 0;
    while mq < n {
        if load64(heap + SWSTR + mq * 8) == 1 { msws = 1; }
        mq = mq + 1;
    }
    if msws == 1 {
        ops3(0x49, 0x89, 0xc3);                    # mov r11, rax —— 判别串保值
        i = 0;
        while i < n {
            ops3(0x4c, 0x89, 0xd9);                # mov rcx, r11
            g_movabs_rax(load64(vals + i * 8));    # movabs rax, 模式串地址
            g_str_eq(1);
            ops2(0x85, 0xc0);                      # test eax, eax
            if load64(heap + O_SWG + i * 8) == 1 {
                emit_jcc(0x85, load64(heap + O_SWGL + i * 8));  # jne → 守卫检查点
            } else {
                emit_jcc(0x85, load64(lbls + i * 8));           # jne → 臂
            }
            i = i + 1;
        }
    } else {
        # v1.1103: 任一 struct 模式臂 → 判别对象地址保 r11（数字臂不用 r11）
        let smany: i64 = 0;
        let smq2: i64 = 0;
        while smq2 < n {
            if load64(heap + O_SWSN + smq2 * 8) == 1 { smany = 1; }
            smq2 = smq2 + 1;
        }
        if smany == 1 { ops3(0x49, 0x89, 0xc3); }    # mov r11, rax
        i = 0;
        while i < n {
            if load64(heap + O_SWSN + i * 8) == 1 {
                # v1.1103: struct 模式 —— 判别对象地址保 r11（比较链前 mov r11,rax
                # 一次），逐字段 mov rsi,r11; mov rax,[rsi+off]; cmp imm32。
                ops3(0x4c, 0x89, 0xde);              # mov rsi, r11
                let smk: i64 = 0;
                let smcnt: i64 = load64(heap + O_SWSM + ((i * 64) + 1) * 8);
                let smf: i64 = new_label();
                let smcmp: i64 = 0;
                while smk < smcnt {
                    if load64(heap + O_SWSM + ((i * 64) + 3 + smk * 2) * 8) != 0 - 1 {
                        smcmp = 1;
                        # mov rax, [rsi+off]; cmp imm32; jne smfail
                        emit1(0x48); emit1(0x8b); emit1(0x86); emit4(load64(heap + O_SWSM + ((i * 64) + 2 + smk * 2) * 8));
                        emit1(0x48); emit1(0x3d); emit4(load64(heap + O_SWSM + ((i * 64) + 3 + smk * 2) * 8));
                        emit_jcc(0x85, smf);
                    }
                    smk = smk + 1;
                }
                if smcmp == 0 {
                    # v1.1104: 全绑定字段无比较 → 无条件进臂（je 无 cmp 撞残留标志）
                    emit_jmp(load64(lbls + i * 8));
                    place_label(smf);
                    i = i + 1;
                    continue;
                }
                if load64(heap + O_SWG + i * 8) == 1 {
                    emit_jcc(0x84, load64(heap + O_SWGL + i * 8));   # je 守卫检查点
                } else {
                    emit_jcc(0x84, load64(lbls + i * 8));            # je 臂
                }
                place_label(smf);
                i = i + 1;
                continue;
            }
            # v1.1108: 绑定守卫臂 —— 无条件进守卫标签（vals=-1 无意义）
            if load64(heap + O_SWVB + i * 8) != 0 {
                emit_jmp(load64(heap + O_SWGL + i * 8));
                i = i + 1;
                continue;
            }
            emit1(0x48); emit1(0x3d); emit4(load64(vals + i * 8));   # cmp rax, imm32
            if load64(heap + O_SWG + i * 8) == 1 {
                emit_jcc(0x84, load64(heap + O_SWGL + i * 8));       # je 守卫检查点
            } else {
                emit_jcc(0x84, load64(lbls + i * 8));                # je
            }
            i = i + 1;
        }
    }
    i = 0;                              # 复位（臂循环要用）
    emit_jmp(dflt);
    i = 0;                              # 复位：发射比较链的循环已把 i 走到 n
    if tok_is("{") == 0 { return err_atp("match: ERR-B no brace after expr", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    expect("{");
    if tok_is("}") == 1 { return err_atp("match: ERR-C empty brace next", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    loop_push(0 - 1, end, 0 - 1);
    while tok_is("}") == 0 {
        if gv(K_TKIND) == 1 && streq(tokbuf(), "_") == 1 {
            next_token();
            expect("=>");
            hasdflt = 1;
            place_label(dflt);
            expect("{");
            while tok_is("}") == 0 { parse_stmt(); }
            next_token();
            emit_jmp(end);
            continue;
        }
        if i >= n {
            loop_pop();
            store64(heap + O_SWTOP, base);
            return err_atp("match: 模式与扫描结果不一致", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        if load64(heap + O_SWG + i * 8) == 1 { place_label(load64(heap + O_SWGL + i * 8)); }
        if load64(heap + O_SWSN + i * 8) == 1 {
            # v1.1109: struct 模式第二遍 —— 深度计数跳过整个模式 token + 数据驱动建绑定符号
            # （scan 顺序 = O_SWSB/O_SWSM cnt 顺序，逐 token 重放对多层嵌套太脆弱，弃用）
            let smbi: i64 = i * 64;
            let smn2: i64 = load64(heap + O_SWSM + (smbi + 1) * 8);
            next_token();               # struct 名
            expect("{");
            let sd9: i64 = 1;
            next_token();
            while sd9 > 0 {
                if gv(K_TKIND) == 0 { return -1; }
                if tok_is("{") == 1 { sd9 = sd9 + 1; }
                else { if tok_is("}") == 1 { sd9 = sd9 - 1; if sd9 == 0 { break; } } }
                next_token();
            }
            next_token();               # 吃模式收尾 '}'
            let smk2: i64 = 0;
            while smk2 < smn2 {
                let bvid: i64 = load64(heap + O_SWSB + ((smbi/64) * 31 + smk2) * 8);
                let bval: i64 = load64(heap + O_SWSM + ((smbi) + 3 + smk2 * 2) * 8);
                if bval == 0 - 1 {
                    memcpy(scratch2(), heap + O_NAMES + bvid);
                    let boff: i64 = gv(K_CUROFF) - 8;
                    sv(K_CUROFF, boff);
                    if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                    let ssd: i64 = gv(K_DEPTH);
                    sv(K_DEPTH, ssd + 1);
                    let bid: i64 = sym_add(scratch2(), 1, boff, 0);
                    sv(K_DEPTH, ssd);
                    store64(heap + O_STY + bid * 8, ty_int());
                    store64(heap + O_SWC + (i * 8 + smk2 * 8), boff);
                }
                smk2 = smk2 + 1;
            }
        } else {
        if load64(heap + SWSTR + i * 8) == 1 {
            next_token();               # 吃字符串模式（值已在 scan 录入）
        } else {
            # v1.1108: 绑定守卫模式 —— 建符号（槽 = 判别槽）
            if load64(heap + O_SWVB + i * 8) != 0 {
                memcpy(scratch3(), heap + O_NAMES + load64(heap + O_SWVB + i * 8));
                sv(K_CUROFF, gv(K_CUROFF));
                if sym_dup(scratch3()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                let wsd: i64 = gv(K_DEPTH);
                sv(K_DEPTH, wsd + 1);
                let wbid: i64 = sym_add(scratch3(), 1, vboff, 0);
                sv(K_DEPTH, wsd);
                store64(heap + O_STY + wbid * 8, ty_int());
                next_token();               # 吃绑定名
            } else {
            if sw_const(heap + O_SWC) == 0 {
                loop_pop();
                store64(heap + O_SWTOP, base);
                return err_atp("match: 模式必须是编译期常量", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            }
        }
        }
        # v1.1099: 守卫 —— 模式匹配后再验 if 条件；失败跳下一臂（或 default）
        # v1.1108: 绑定守卫臂的匹配点 = O_SWGL 标签（发射段无条件 jmp 到此）
        if load64(heap + O_SWVB + i * 8) != 0 { place_label(load64(heap + O_SWGL + i * 8)); }        if load64(heap + O_SWG + i * 8) == 1 {
            expect("if");
            parse_expr();               # cond → rax
            spill_cache();              # 值可能还在 rbx 缓存里，落回 rax
            ops2(0x85, 0xc0);           # test eax, eax
            if i + 1 < n {
                if load64(heap + O_SWG + (i + 1) * 8) == 1 { emit_jcc(0x84, load64(heap + O_SWGL + (i + 1) * 8)); }
                else { emit_jcc(0x84, load64(lbls + (i + 1) * 8)); }
            } else { emit_jcc(0x84, dflt); }
        }
        place_label(load64(lbls + i * 8));
        if load64(heap + O_SWSN + i * 8) == 1 {
            # v1.1104: 绑定字段 store（数据驱动重放，地址在 r11）
            let sbi2: i64 = i * 64;
            let sbk2: i64 = 0;
            while sbk2 < load64(heap + O_SWSM + (sbi2 + 1) * 8) {
                if load64(heap + O_SWSM + (sbi2 + 3 + sbk2 * 2) * 8) == 0 - 1 {
                    ops3(0x4c, 0x89, 0xde);              # mov rsi, r11
                    emit1(0x48); emit1(0x8b); emit1(0x86); emit4(load64(heap + O_SWSM + (sbi2 + 2 + sbk2 * 2) * 8));  # mov rax,[rsi+off]
                    g_store_local(load64(heap + O_SWC + (i * 8 + sbk2 * 8)));
                }
                sbk2 = sbk2 + 1;
            }
        }
        expect("=>");
        let cd: i64 = d + 1;
        sv(K_DEPTH, cd);
        expect("{");
        while tok_is("}") == 0 {
            memcpy(scratch3(), tokbuf());
            syscall(1, 2, scratch3(), 0, 0, 0, 0);
            syscall(1, 2, "\n", 1, 0, 0, 0);
            parse_stmt();
        }
        next_token();
        sym_pop_scope(cd);
        sv(K_DEPTH, d);
        emit_jmp(end);
        i = i + 1;
    }
    next_token();                       # 越过 match 的 '}'
    if hasdflt == 0 { place_label(dflt); }
    place_label(end);
    sym_pop_scope(d);
    sv(K_DEPTH, d - 1);
    loop_pop();
    store64(heap + O_SWTOP, base);
    return 0;
}


# v1.1100: match 表达式 —— `let r = match c { PAT => EXPR, _ => EXPR };`
# 臂体是单个表达式（逗号分隔），各臂值存隐藏槽后 jmp 汇合。
# tok 入口: 'match' 未消费。结果 rax；hs_off = 结果槽偏移（调用方保证已分配）。
fn parse_match_expr(hs_off: i64) -> i64 {
    let base: i64 = load64(heap + O_SWTOP);
    if base + 128 > 1024 {
        return err_atp("match: 嵌套过深（上限 8 层）", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    store64(heap + O_SWTOP, base + 128);
    let vals: i64 = heap + O_SWV + base * 8;
    let lbls: i64 = heap + O_SWL + base * 8;
    let save: i64 = gv(K_TOKPOS);
    # v1.1107: 🔴 清跨 match 残留（SWG/SWVB/SWSTR/SWSN 是全局 n 槽，上一 match 的
    # 标记会让本 match 误走守卫/字符串/struct 路径——c 探针实证）
    let cz: i64 = 0;
    while cz < 128 {
        store64(heap + O_SWG + cz * 8, 0);
        store64(heap + O_SWVB + cz * 8, 0);
        store64(heap + SWSTR + cz * 8, 0);
        store64(heap + O_SWSN + cz * 8, 0);
        cz = cz + 1;
    }
    let n: i64 = mt_scan(vals);
    if n < 0 {
        store64(heap + O_SWTOP, base);
        return err_atp("match: 模式必须是编译期常量（数字/enum/const/_）", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    set_back(save);
    let qi: i64 = 0;
    while qi < n {
        let qj: i64 = 0;
        while qj < qi {
            if load64(vals + qi * 8) == load64(vals + qj * 8) && load64(heap + O_SWSN + qi * 8) != 1 && load64(heap + O_SWSN + qj * 8) != 1 && load64(heap + O_SWG + qi * 8) != 1 && load64(heap + O_SWG + qj * 8) != 1 {
                store64(heap + O_SWTOP, base);
                return err_atp("match: duplicate pattern value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            qj = qj + 1;
        }
        qi = qi + 1;
    }
    let end: i64 = new_label();
    let dflt: i64 = new_label();
    let hasdflt: i64 = 0;
    let i: i64 = 0;
    while i < n {
        store64(lbls + i * 8, new_label());
        if load64(heap + O_SWG + i * 8) == 1 { store64(heap + O_SWGL + i * 8, new_label()); }
        i = i + 1;
    }
    # primary 调用方已消费 'match'；语句/let 路由未消费 —— 探测式越过
    if streq(tokbuf(), "match") == 1 { next_token(); }
    parse_expr();                       # 判别值 → rax
    # v1.1107: 有绑定守卫臂时，把判别值先存 hs 槽（绑定变量即读它）
    let hasvb: i64 = 0;
    let hv: i64 = 0;
    while hv < n {
        if load64(heap + O_SWVB + hv * 8) != 0 { hasvb = 1; }
        hv = hv + 1;
    }
    if hasvb == 1 { g_store_local(hs_off); }
    # v1.1102: 字符串模式（抄语句版 v1.1099）——任一字符串模式则全部必须为字符串
    let msws: i64 = 0;
    let mq: i64 = 0;
    while mq < n {
        if load64(heap + SWSTR + mq * 8) == 1 { msws = 1; }
        mq = mq + 1;
    }
    if msws == 1 {
        ops3(0x49, 0x89, 0xc3);                    # mov r11, rax —— 判别串保值
        i = 0;
        while i < n {
            ops3(0x4c, 0x89, 0xd9);                # mov rcx, r11
            g_movabs_rax(load64(vals + i * 8));    # movabs rax, 模式串地址
            g_str_eq(1);
            ops2(0x85, 0xc0);                      # test eax, eax
            emit_jcc(0x85, load64(lbls + i * 8));  # jne → 臂
            i = i + 1;
        }
    } else {
        # v1.1105: 任一 struct 模式臂 → 判别对象地址保 r11（数字臂不用 r11）
        let smany: i64 = 0;
        let smq2: i64 = 0;
        while smq2 < n {
            if load64(heap + O_SWSN + smq2 * 8) == 1 { smany = 1; }
            smq2 = smq2 + 1;
        }
        if smany == 1 { ops3(0x49, 0x89, 0xc3); }    # mov r11, rax
        i = 0;
        while i < n {
            if load64(heap + O_SWSN + i * 8) == 1 {
                # v1.1105: struct 模式（抄语句版 v1.1103）—— r11=对象地址，
                # 逐字段 mov rsi,r11 / mov rax,[rsi+off] / cmp imm32 / jne smfail
                ops3(0x4c, 0x89, 0xde);              # mov rsi, r11
                let smk: i64 = 0;
                let smcnt: i64 = load64(heap + O_SWSM + ((i * 64) + 1) * 8);
                let smf: i64 = new_label();
                let smcmp: i64 = 0;
                while smk < smcnt {
                    if load64(heap + O_SWSM + ((i * 64) + 3 + smk * 2) * 8) != 0 - 1 {
                        smcmp = 1;
                        emit1(0x48); emit1(0x8b); emit1(0x86); emit4(load64(heap + O_SWSM + ((i * 64) + 2 + smk * 2) * 8));
                        emit1(0x48); emit1(0x3d); emit4(load64(heap + O_SWSM + ((i * 64) + 3 + smk * 2) * 8));
                        emit_jcc(0x85, smf);
                    }
                    smk = smk + 1;
                }
                if smcmp == 0 {
                    emit_jmp(load64(lbls + i * 8));  # 全绑定臂无条件进
                    place_label(smf);
                    i = i + 1;
                    continue;
                }
                if load64(heap + O_SWG + i * 8) == 1 { emit_jcc(0x84, load64(heap + O_SWGL + i * 8)); }
                else { emit_jcc(0x84, load64(lbls + i * 8)); }
                place_label(smf);
                i = i + 1;
                continue;
            }
            # v1.1107: 绑定守卫臂 —— 无条件进（值任意），条件在第二遍验
            if load64(heap + O_SWVB + i * 8) != 0 {
                emit_jmp(load64(heap + O_SWGL + i * 8));
            } else {
            emit1(0x48); emit1(0x3d); emit4(load64(vals + i * 8));   # cmp rax, imm32
            if load64(heap + O_SWG + i * 8) == 1 { emit_jcc(0x84, load64(heap + O_SWGL + i * 8)); }
            else { emit_jcc(0x84, load64(lbls + i * 8)); }
            }
            i = i + 1;
        }
    }
    i = 0;
    emit_jmp(dflt);
    expect("{");
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    while tok_is("}") == 0 {
        if gv(K_TKIND) == 1 && streq(tokbuf(), "_") == 1 {
            accept(",");                    # 臂间逗号（首臂无害）
            next_token();
            expect("=>");
            hasdflt = 1;
            place_label(dflt);
            if tok_is("{") == 1 {
                next_token();
                parse_expr();
                expect("}");
            } else {
                parse_expr();
            }
            g_store_local(hs_off);
            emit_jmp(end);
            accept(",");
            continue;
        }
        if i >= n {
            sv(K_DEPTH, d - 1);
            store64(heap + O_SWTOP, base);
            return err_atp("match: 模式与扫描结果不一致", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        accept(",");                        # 臂间逗号（首臂无害）
        place_label(load64(lbls + i * 8));
        if load64(heap + O_SWSN + i * 8) == 1 {
            # v1.1105: struct 模式 —— 吃 token + 建绑定符号 + place 后 store
            let smbi: i64 = i * 64;
            let smn2: i64 = load64(heap + O_SWSM + (smbi + 1) * 8);
            next_token();                   # struct 名
            expect("{");
            let sd8: i64 = 1;
            next_token();
            while sd8 > 0 {
                if gv(K_TKIND) == 0 { return -1; }
                if tok_is("{") == 1 { sd8 = sd8 + 1; }
                else { if tok_is("}") == 1 { sd8 = sd8 - 1; if sd8 == 0 { break; } } }
                next_token();
            }
            next_token();                   # 模式收尾 '}'
            # v1.1109: 数据驱动建绑定符号（scan 顺序 = cnt 顺序，不再逐 token 重放）
            let smk2: i64 = 0;
            while smk2 < smn2 {
                let bvid: i64 = load64(heap + O_SWSB + ((smbi/64) * 31 + smk2) * 8);
                let bval: i64 = load64(heap + O_SWSM + ((smbi) + 3 + smk2 * 2) * 8);
                if bval == 0 - 1 {
                    memcpy(scratch3(), heap + O_NAMES + bvid);
                    let boff: i64 = gv(K_CUROFF) - 8;
                    sv(K_CUROFF, boff);
                    if sym_dup(scratch3()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                    # v1.1105 铁律: 绑定符号记臂内深度，结束后统一 pop（d+1）
                    let esd: i64 = gv(K_DEPTH);
                    sv(K_DEPTH, esd + 1);
                    let bid: i64 = sym_add(scratch3(), 1, boff, 0);
                    sv(K_DEPTH, esd);
                    store64(heap + O_STY + bid * 8, ty_int());
                    store64(heap + O_SWC + (i * 8 + smk2 * 8), boff);
                }
                smk2 = smk2 + 1;
            }
            # place 已过 → 立即发射绑定 store（数据驱动，地址在 r11）
            let sbk2: i64 = 0;
            while sbk2 < smn2 {
                if load64(heap + O_SWSM + (smbi + 3 + sbk2 * 2) * 8) == 0 - 1 {
                    ops3(0x4c, 0x89, 0xde);              # mov rsi, r11
                    emit1(0x48); emit1(0x8b); emit1(0x86); emit4(load64(heap + O_SWSM + (smbi + 2 + sbk2 * 2) * 8));
                    g_store_local(load64(heap + O_SWC + (i * 8 + sbk2 * 8)));
                }
                sbk2 = sbk2 + 1;
            }
        } else {
            if load64(heap + SWSTR + i * 8) == 1 {
                next_token();                   # v1.1102: 字符串模式（值已在 scan 录入）
            } else {
                # v1.1107: 守卫绑定模式 —— 建绑定符号（类型 = 判别式，这里按 i64）
                if load64(heap + O_SWVB + i * 8) != 0 {
                    memcpy(scratch3(), heap + O_NAMES + load64(heap + O_SWVB + i * 8));
                    let vboff: i64 = hs_off;    # 绑定 = 判别值槽（发射段已存）
                    sv(K_CUROFF, gv(K_CUROFF));
                    if sym_dup(scratch3()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                    let vsd: i64 = gv(K_DEPTH);
                    sv(K_DEPTH, vsd + 1);
                    let vbid: i64 = sym_add(scratch3(), 1, vboff, 0);
                    sv(K_DEPTH, vsd);
                    store64(heap + O_STY + vbid * 8, ty_int());
                    next_token();               # 吃绑定名
                } else {
                if sw_const(heap + O_SWC) == 0 {
                    sv(K_DEPTH, d - 1);
                    store64(heap + O_SWTOP, base);
                    return err_atp("match: 模式必须是编译期常量", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                }
            }
        }
        # v1.1107: 守卫 —— 匹配点已在发射段跳到 O_SWGL 标签；此处 place + 验条件
        if load64(heap + O_SWG + i * 8) == 1 {
            place_label(load64(heap + O_SWGL + i * 8));
            expect("if");
            parse_expr();               # cond → rax
            spill_cache();
            ops2(0x85, 0xc0);           # test eax, eax
            if i + 1 < n {
                if load64(heap + O_SWG + (i + 1) * 8) == 1 { emit_jcc(0x84, load64(heap + O_SWGL + (i + 1) * 8)); }
                else { emit_jcc(0x84, load64(lbls + (i + 1) * 8)); }
            } else { emit_jcc(0x84, dflt); }
        }
        expect("=>");
        # v1.1100: 臂值 = 表达式 或 { expr }（单表达式块）
        if tok_is("{") == 1 {
            next_token();
            parse_expr();
            expect("}");
        } else {
            parse_expr();
        }
        g_store_local(hs_off);
        emit_jmp(end);
        accept(",");
        # v1.1107: 回收守卫绑定符号
        if load64(heap + O_SWVB + i * 8) != 0 { sym_pop_scope(gv(K_DEPTH) + 1); }
        i = i + 1;
    }
    next_token();                       # 越过 '}'
    if hasdflt == 0 { place_label(dflt); }
    place_label(end);
    # v1.1105: 回收臂内绑定变量（同语句版 sym_pop_scope）—— 否则下一个
    # match 的同名绑定报 duplicate（t287 实证）
    sym_pop_scope(d + 1);
    sv(K_DEPTH, d - 1);
    g_load_local(hs_off);               # rax = 结果
    store64(heap + O_SWTOP, base);
    return 0;
}

# 当前正在编译的函数的返回类型（parse_func 里设，parse_return 里读）。
var CUR_RET: i64 = 0;

fn parse_return() -> i64 {
    sv(K_HASRET, 1);
    if tok_is(";") == 1 {
        return err_atp("return with no value in a function returning i64", gv(K_LINE), gv(K_COL), gv(K_TOKPOS));
    }
    # 结构体返回：只支持 `return <变量名>;`
    #
    # **为什么不走通用 parse_expr**：结构体表达式在 rax 里留下的是
    # **对象地址**（load_sym 对结构体取 lea），而"地址"和"值"在生成的
    # 代码里都是 rax 中的一个数，靠类型系统区分 —— 返回时要按值拷贝
    # 两字，必须明确知道基址。限制成变量既能拿到符号（从而拿到地址），
    # 也让语义清楚。返回别的东西（表达式、调用结果）明确报错。
    if ty_kind(CUR_RET) == 2 {
        let si2: i64 = ty_si(CUR_RET);
        let nf2: i64 = load64(heap + O_STF + si2 * 8);
        # v1.1055: return P { x: 1; y: 2; }; —— 字面量直接返回。
        # 字面量发射到数据段常量区，返回时按值拷到 rax/rdx。
        if gv(K_TKIND) == 1 {
            let rlsi: i64 = st_lookup(tokbuf());
            if rlsi >= 0 {
                let rsvp: i64 = gv(K_TOKPOS);
                next_token();
                if tok_is("{") == 1 {
                    if rlsi != si2 { return err_at2("struct return type mismatch", gv(K_LINE), gv(K_COL)); }
                    data_align(16);
                    let raddr: i64 = 268435456 + gv(K_DLEN);
                    let rj: i64 = 0;
                    while rj < st_words(si2) { dquad(0); rj = rj + 1; }
                    next_token();   # 吃 '{'（探测已消费 struct 名）
                    while tok_is("}") == 0 {
                        if gv(K_TKIND) != 1 { return syntax_error(); }
                        let rfi: i64 = 0 - 1;
                        let rfj: i64 = 0;
                        while rfj < st_nfields(si2) {
                            if streq(tokbuf(), st_field_name(si2, rfj)) == 1 { rfi = rfj; }
                            rfj = rfj + 1;
                        }
                        if rfi < 0 { return err_at2("struct literal: no such field", gv(K_LINE), gv(K_COL)); }
                        next_token();
                        expect(":");
                        g_movabs_rsi(raddr + st_field_off(si2, rfi));
                        parse_expr();
                        expect(";");
                        spill_cache();
                        g_pop_rcx();
                        ops3(0x48, 0x89, 0x06);   # mov [rsi], rax
                        accept(",");
                    }
                    next_token();   # 吃 '}'
                    expect(";");
                    g_movabs_rax(raddr);            # rax = &字面量
                    ops3(0x48, 0x89, 0xc6);         # mov rsi, rax
                    ops3(0x48, 0x8b, 0x06);         # mov rax, [rsi]
                    if nf2 == 2 {
                        ops3(0x48, 0x8b, 0x56);     # mov rdx, [rsi+8]
                        emit1(8);
                    }
                    g_epilogue();
                    return 0;
                } else {
                    set_back(rsvp);
                }
            }
        }
        if gv(K_TKIND) != 1 {
            return err_atp("struct return: expected a variable", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        let rn: i64 = heap + O_SCAL + 1800;
        memcpy(rn, tokbuf());
        next_token();
        expect(";");
        let rs: i64 = sym_lookup(rn);
        if rs < 0 { return undef_err(rn); }
        g_addr_sym_rax(rs);                # rax = &obj（或 &形参槽）
        # v1.1111: struct 形参槽内容 = 调用方对象地址 —— 解引用一层
        if load64(heap + O_SP + rs * 8) == 1 {
            ops2(0x48, 0x8b); emit1(0x00); # mov rax, [rax]
        }
        ops3(0x48, 0x89, 0xc6);            # mov rsi, rax
        ops3(0x48, 0x8b, 0x06);            # mov rax, [rsi]
        if nf2 == 2 {
            ops3(0x48, 0x8b, 0x56);        # mov rdx, [rsi+8]
            emit1(8);
        }
        g_epilogue();
        return 0;
    }
    if ty_kind(CUR_RET) == 3 {
        # v1.1079: 数组返回 —— rax = 数组变量地址（调用方按地址用）
        if gv(K_TKIND) != 1 {
            return err_atp("array return: expected a variable", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        let an2: i64 = heap + O_SCAL + 1800;
        memcpy(an2, tokbuf());
        next_token();
        expect(";");
        let as2: i64 = sym_lookup(an2);
        if as2 < 0 { return undef_err(an2); }
        # v1.1089→v1.1096: 局部数组返回改为**拷入隐藏全局缓冲**再返回地址。
        # 之前硬错（悬垂）。缓冲在数据段预留一次（K_RBOFF 记偏移，-1 未分配），
        # 容量上限 8KB（1000×8）。注意：两次这类调用之间上一次结果会被覆盖，
        # 调用方应立即消费（拷出/取元素）。
        if sym_kind(as2) == 1 {
            let asz: i64 = ty_size(sym_type(as2));
            if asz > 8192 { return err_at2("array return: local array too large (8KB limit)", gv(K_LINE), gv(K_COL)); }
            let rbo: i64 = gv(K_RBOFF);
            if rbo < 0 {
                data_align(16);
                rbo = gv(K_DLEN);
                let pad: i64 = 0;
                while pad < 8192 {
                    dquad(0);
                    pad += 1;
                }
                sv(K_RBOFF, rbo);
            }
            # rax = &local; rdi = dst; rsi = src; 拷 asz/8 字
            g_addr_sym_rax(as2);
            ops3(0x48, 0x89, 0xc6);            # mov rsi, rax（源=局部数组）
            g_movabs_rax(268435456 + rbo);     # rax = 目的（缓冲）
            g_copy_words(asz / 8);
            g_movabs_rax(268435456 + rbo);     # 返回缓冲地址
            g_epilogue();
            return 0;
        }
        g_addr_sym_rax(as2);
        g_epilogue();
        return 0;
    }
    parse_expr();
    expect(";");
    g_epilogue();
    return 0;
}

# ============ C FFI：extern 声明 ============
#
#     extern fn printf(fmt: ptr) -> i64;
#     extern fn malloc(n: i64) -> ptr;
#
# 只登记符号（kind 3），**不生成任何代码**。
# 调用点发 `call rel32` 占位 + R_X86_64_PLT32 重定位，
# 由 ld 在链接时解析到 libc。
#
# 因为墨语言的调用约定本来就是 System V（rdi/rsi/rdx/rcx/r8/r9），
# 所以调 C 函数**不需要任何参数转换** —— 这点是白拿的。
fn parse_extern() -> i64 {
    next_token();
    if accept("fn") == 0 { return err_at2("expected 'fn' after extern", gv(K_LINE), gv(K_COL)); }
    memcpy(scratch2(), tokbuf());
    next_token();
    if sym_dup(scratch2()) >= 0 {
        return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    expect("(");
    let np: i64 = 0;
    let va: i64 = 0;
    while tok_is(")") == 0 {
        # `...` 变参：printf 这类函数每次调用的参数个数都不一样，
        # 不可能用固定 arity 声明。记成 -(最少参数数+1) 以便区分。
        if tok_is(".") == 1 {
            next_token();
            if tok_is(".") == 0 { return err_at2("expected '...'", gv(K_LINE), gv(K_COL)); }
            next_token();
            if tok_is(".") == 0 { return err_at2("expected '...'", gv(K_LINE), gv(K_COL)); }
            next_token();
            va = 1;
            if tok_is(")") == 0 { return err_at2("'...' must be last", gv(K_LINE), gv(K_COL)); }
        } else {
        # 形参名后面必须跟类型；类型不参与代码生成（C 侧自己知道），
        # 但仍要解析，否则 `)` 永远匹配不上。
        next_token();
        if accept(":") == 0 { return err_at2("expected ':' in extern parameter", gv(K_LINE), gv(K_COL)); }
        next_token();
        np = np + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return err_at2("expected ')'", gv(K_LINE), gv(K_COL)); }
        }
        }
    }
    expect(")");
    let rt: i64 = ty_int();
    if accept("->") == 1 {
        if accept("i64") == 1 {
            rt = ty_int();
        } else {
            if accept("ptr") == 1 {
                rt = ty_ptr(parse_ptr_target());
            } else {
                if accept("f64") == 1 {
                    rt = ty_float();
                } else {
                    if accept("byte") == 1 {
                        rt = ty_byte();
                    } else {
                        if accept("i32") == 1 {
                            rt = ty_i32();
                        } else {
                            return err_at2("unsupported extern return type", gv(K_LINE), gv(K_COL));
                        }
                    }
                }
            }
        }
    }
    expect(";");
    if va == 1 { np = 0 - (np + 1); }
    let id: i64 = sym_add(scratch2(), 3, 0, np);
    store64(heap + O_SRT + id * 8, rt);
    return 0;
}

# 数据段对齐到 a 字节边界。
#
# 🔴 为什么必须做：全局变量前面可能有任意长度的字符串常量，
#    于是变量的地址可能**不是 8 的倍数**（实测出现过 0x1000019D）。
#    x86 允许未对齐访问，所以 i64 变量只是慢一点、看不出问题；
#    但 pthread_mutex_t 里含有 futex word，内核要求地址对齐，
#    未对齐会让 glibc 直接 abort：
#      "The futex facility returned an unexpected error code."
#    这个错误看上去像线程/锁用错了，实际是**数据段没对齐**。
#
# 对齐到 16：既满足 i64/f64，也满足 pthread_mutex_t 和常见结构体。
fn data_align(a: i64) -> i64 {
    while (gv(K_DLEN) & (a - 1)) != 0 {
        dbyte(0);
    }
    return 0;
}

# 解析数组字面量 `[1, 2, -3]`，返回元素个数，值存到 O_LSTV。
#
# 为什么只支持常量：数组初始化发生在**声明处**，局部数组在栈上、
# 全局数组在数据段 —— 两者都要在**编译期**把值写出来，
# 运行时表达式在这里没有可发射的位置。
fn parse_i64_list() -> i64 {
    expect("[");
    let cnt: i64 = 0;
    if tok_is("]") == 1 { next_token(); return 0; }
    while tok_is("]") == 0 {
        let neg: i64 = 0;
        if accept("-") == 1 { neg = 1; }
        let v: i64 = 0;
        # v1.1019: &funcname 元素 —— 函数指针表（[N] ptr = [&a, &b]）
        if tok_is("&") == 1 {
            next_token();
            if gv(K_TKIND) != 1 { return err_at2("array literal: expected function name after &", gv(K_LINE), gv(K_COL)); }
            let fsy: i64 = sym_lookup_func(tokbuf());
            if fsy < 0 { return err_at2("array literal: unknown function", gv(K_LINE), gv(K_COL)); }
            store64(heap + O_SU + fsy * 8, 1);
            # 复用 func_addr 发 movabs（前向引用也由 resolve_all 兜底），
            # 然后回退代码指针，从 movabs 立即数里抄出地址（v1.1019）。
            # O_COD 设 268435456？代码缓冲基址未知 —— 直接用 sym_addr；
            # 若函数地址 < 4M（前向引用未解析）则响亮报错。
            next_token();                # 消费函数名（v1.1019 修复）
            let ta: i64 = sym_addr(fsy);
            if ta < 4194304 { return err_at2("array literal: cannot take function address here", gv(K_LINE), gv(K_COL)); }
            v = ta;
        } else {
        if gv(K_TKIND) == 2 {
            # v1.1120: f64 literal element -> IEEE754 bits in O_LSTV
            if gv(K_TFLT) == 1 {
                v = f64_bits(gv(K_TFDIG), gv(K_TFDIGN), FSTICKY, neg);
                neg = 0;
                next_token();
            } else {
                v = gv(K_TIVAL);
                next_token();
            }
        } else {
            if gv(K_TKIND) == 1 {
                # const/enum 成员（v1.985）：const_atom 消费名字，
                # const_expr 继续折叠后缀算术
                let lsi: i64 = sym_lookup(tokbuf());
                if lsi >= 0 {
                    if load64(heap + O_SK + lsi * 8) == 4 {
                        v = const_expr();
                    } else {
                        return err_at2("array literal elements must be integer constants", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    let le: i64 = enum_value(tokbuf());
                    if le >= 0 {
                        v = const_expr();
                    } else {
                        return err_at2("array literal elements must be integer constants", gv(K_LINE), gv(K_COL));
                    }
                }
            } else {
                return err_at2("array literal elements must be integer constants", gv(K_LINE), gv(K_COL));
            }
        }
        }   # v1.1019: & 元素 else 块闭合
        if neg == 1 { v = 0 - v; }
        if cnt >= 512 { return err_at2("array literal exceeds 512 elements", gv(K_LINE), gv(K_COL)); }
        store64(heap + O_LSTV + cnt * 8, v);
        cnt = cnt + 1;
        if accept(",") == 0 { break; }
    }
    expect("]");
    return cnt;
}

# const NAME: i64 = 常量表达式;  编译期求值，符号 kind 4（不占数据段）。
# 只支持 + - * / 与括号的整数常量表达式（字面量与已定义 const）。
fn parse_const() -> i64 {
    next_token();
    # v1.1112: const fn —— 编译期可折叠函数（单参数 i64，体仅字面量/参数/算术）
    if tok_is("fn") == 1 {
        # v1.1112: const fn —— predeclare 已登记 sym；此处记 body 范围 + O_CFF 标记
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        let ssid: i64 = sym_lookup_func(tokbuf());

        if ssid < 0 { return err_at2("const fn: not predeclared", gv(K_LINE), gv(K_COL)); }
        next_token();
        expect("(");
        if gv(K_TKIND) != 1 { return syntax_error(); }
        # 参数名内容 → O_CFA[0]（单参数；名字 16B + 值 8B）
        let cp9: i64 = heap + O_CFA;
        let cn9: i64 = tokbuf();
        let ci9b: i64 = 0;
        while ci9b < 16 {
            if load8(cn9 + ci9b) == 0 { break; }
            store8(cp9 + ci9b, load8(cn9 + ci9b));
            ci9b = ci9b + 1;
        }
        store8(cp9 + ci9b, 0);
        next_token();
        expect(":");
        expect("i64");
        expect(")");
        if accept("->") == 1 { expect("i64"); }
        expect("{");
        let cbs: i64 = gv(K_TOKPOS);   # v1.1112: 体首 token 起点字节数（K_POS=token 末+1，set_pos 须用起点）
        let cd9: i64 = 1;
        while cd9 > 0 {
            if gv(K_TKIND) == 0 { return syntax_error(); }
            if tok_is("{") == 1 { cd9 = cd9 + 1; }
            else { if tok_is("}") == 1 { cd9 = cd9 - 1; if cd9 == 0 { break; } } }
            next_token();
        }
        next_token();
        store64(heap + O_CFB + ssid * 16, cbs);
        store64(heap + O_CFB + ssid * 16 + 8, gv(K_POS));   # '}' 后字节偏移
        store8(heap + O_CFF + ssid, 1);
        accept(";");
        return 0;
    }
    memcpy(scratch2(), tokbuf());
    next_token();
    expect(":");
    # v1.1046: const 数组 const A: [N] i64 = [...] —— 数据段常量区发射
    if tok_is("[") == 1 {
        next_token();
        if gv(K_TKIND) != 2 { return err_at2("const array: expected element count", gv(K_LINE), gv(K_COL)); }
        let n2: i64 = gv(K_TIVAL);
        next_token();
        if tok_is("]") == 0 { return syntax_error(); }
        next_token();
        # 元素类型（i64 或 byte）
        let isb: i64 = 0;
        if tok_is("byte") == 1 { isb = 1; next_token(); }
        else { if tok_is("i64") == 0 { return err_at2("const array: only i64/byte supported", gv(K_LINE), gv(K_COL)); } else { next_token(); } }
        expect("=");
        let lcnt: i64 = parse_i64_list();
        expect(";");
        if lcnt < 0 { return syntax_error(); }
        if lcnt > n2 { return err_at2("const array: too many initializers", gv(K_LINE), gv(K_COL)); }
        if const_dup_check() >= 0 { return 0; }
        data_align(16);
        let addr2: i64 = 268435456 + gv(K_DLEN);
        let i2: i64 = 0;
        while i2 < n2 {
            if isb == 1 {
                if i2 < lcnt { dbyte(load64(heap + O_LSTV + i2 * 8) & 255); } else { dbyte(0); }
            } else {
                if i2 < lcnt { dquad(load64(heap + O_LSTV + i2 * 8)); } else { dquad(0); }
            }
            i2 = i2 + 1;
        }
        if isb == 0 { data_align(16); }
        let ca_id: i64 = sym_add(scratch2(), 2, addr2, 0);   # 顶层 = kind 2（同全局 var 数组）
        if isb == 1 {
            store64(heap + O_STY + ca_id * 8, ty_array(ty_byte(), n2));
        } else {
            store64(heap + O_STY + ca_id * 8, ty_array(ty_int(), n2));
        }
        return 0;
    }
    if tok_is("i64") == 0 { return err_at2("const: only i64 supported", gv(K_LINE), gv(K_COL)); }
    next_token();
    expect("=");
    let v: i64 = const_expr();
    expect(";");
    # 软恢复（v1.1006）：const 表达式出错后消费到 ';'，让后续定义继续
    if ERR_N > 0 {
        while gv(K_TKIND) != 0 {
            if tok_is(";") == 1 { next_token(); break; }
            next_token();
        }
    }
    if const_dup_check() >= 0 { return 0; }
    let id: i64 = sym_add(scratch2(), 4, v, 0);
    store64(heap + O_SCV + id * 8, v);
    return 0;
}

# 重复 const 检查封装（v1.991）：sym_add 前查 sym_dup
fn const_dup_check() -> i64 {
    if sym_dup(scratch2()) >= 0 {
        return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    return 0 - 1;
}

# 常量表达式求值：递归下降，一层乘除一层加减一层原子。
# 原子 = 数字字面量 | ( expr ) | 已定义的 const 名（kind 4，O_SCV 取值）。
# v1.1112: const fn 编译期求值——名 id 与参数值给入，重入 token 流解释函数体（仅 return expr）
fn cfn_eval(fid: i64, arg: i64) -> i64 {
    let cbs: i64 = load64(heap + O_CFB + fid * 16);
    let cbe: i64 = load64(heap + O_CFB + fid * 16 + 8);
    # 保存扫描位置（恢复用 set_back 重读 token，保证 tokbuf 一致）
    let sv_tk: i64 = gv(K_POS);
    let sv_ln: i64 = gv(K_LINE);
    let sv_cl: i64 = gv(K_CPOS);
    # 参数值 → O_CFA+16（名内容在 O_CFA[0..16)，声明时写入）
    store64(heap + O_CFA + 16, arg);
    # 跳到函数体（set_pos 重读 token → tokbuf 同步）
    sv(K_LINE, 1);
    sv(K_CPOS, 0);
    set_pos(cbs);
    let rv: i64 = 0;
    while gv(K_POS) < cbe {
        if tok_is("return") == 1 {
            next_token();
            rv = cfn_expr(0);
        } else {
            next_token();
        }
    }
    # 恢复（set_back 重读 token）
    sv(K_LINE, sv_ln);
    sv(K_CPOS, sv_cl);
    set_back(sv_tk);
    return rv;
}

# cfn 表达式求值（递归下降；支持 参数/数字/() 一元- + - * / %）
fn cfn_atom() -> i64 {
    if tok_is("(") == 1 {
        next_token();
        let v: i64 = cfn_expr(0);
        expect(")");
        return v;
    }
    if tok_is("-") == 1 {
        next_token();
        return 0 - cfn_atom();
    }
    if gv(K_TKIND) == 2 {
        let v: i64 = gv(K_TIVAL);
        next_token();
        return v;
    }
    # 参数名（O_CFA[0..16) 名内容, [16] 值）；其它标识符若是 const fn 调用 → 递归折叠
    if gv(K_TKIND) == 1 {
        if streq(tokbuf(), heap + O_CFA) == 1 {
            next_token();
            return load64(heap + O_CFA + 16);
        }
        let nid9: i64 = sym_lookup_func(tokbuf());
        if nid9 >= 0 && load8(heap + O_CFF + nid9) == 1 && load64(heap + O_CFB + nid9 * 16) > 0 {
            next_token();
            expect("(");
            let na9: i64 = cfn_expr(0);
            expect(")");
            return cfn_eval(nid9, na9);
        }
        return err_at2("const fn: undefined name", gv(K_LINE), gv(K_COL));
    }
    return err_at2("const fn: unsupported token in body", gv(K_LINE), gv(K_COL));
}

fn cfn_term() -> i64 {
    let v: i64 = cfn_atom();
    while tok_is("*") == 1 || tok_is("/") == 1 || tok_is("%") == 1 {
        if tok_is("*") == 1 {
            next_token();
            v = v * cfn_atom();
        } else {
            if tok_is("/") == 1 {
                next_token();
                v = v / cfn_atom();
            } else {
                next_token();
                v = v % cfn_atom();
            }
        }
    }
    return v;
}

fn cfn_expr(depth: i64) -> i64 {
    let ev: i64 = cfn_term();
    return ev;
}

fn const_atom() -> i64 {
    # v1.1112: const fn 调用点折叠 —— 名(常量实参)
    if gv(K_TKIND) == 1 {
        let csid: i64 = sym_lookup_func(tokbuf());
        if csid >= 0 && load8(heap + O_CFF + csid) == 1 && load64(heap + O_CFB + csid * 16) > 0 {
            memcpy(scratch3(), tokbuf());
            next_token();
            if tok_is("(") == 1 {
                next_token();
                let ca: i64 = const_expr();
                expect(")");
                return cfn_eval(csid, ca);
            }
            err_at2("const fn used as value", gv(K_LINE), gv(K_COL));
        }
    }
    # 一元负号/正号（v1.976）
    if tok_is("-") == 1 {
        next_token();
        return 0 - const_atom();
    }
    if tok_is("+") == 1 {
        next_token();
        return const_atom();
    }
    if tok_is("(") == 1 {
        next_token();
        let v: i64 = const_expr();
        expect(")");
        return v;
    }
    if tok_is("sizeof") == 1 {
        # 编译期 sizeof（v1.993）：复用 part4 的 try_parse_type
        next_token();
        expect("(");
        let st: i64 = try_parse_type();
        if st < 0 {
            return err_at2("sizeof requires a type in parentheses", gv(K_LINE), gv(K_COL));
        }
        expect(")");
        return ty_size(st);
    }
    if tok_is("alignof") == 1 {
        # 编译期 alignof（v1.995）：与 sizeof 对称
        next_token();
        expect("(");
        let at: i64 = try_parse_type();
        if at < 0 {
            return err_at2("alignof requires a type in parentheses", gv(K_LINE), gv(K_COL));
        }
        expect(")");
        return ty_align(at);
    }
    if gv(K_TKIND) == 2 {
        let v: i64 = gv(K_TIVAL);
        next_token();
        return v;
    }
    if gv(K_TKIND) == 1 {
        # enum 类型点访问 E.A（v1.992）：E 是 enum 类型名 → 吃 '.' 查成员
        let savep: i64 = gv(K_TOKPOS);
        memcpy(scratch3(), tokbuf());
        let tn: i64 = scratch3();
        next_token();
        if tok_is(".") == 1 {
            next_token();
            let me: i64 = enum_lookup(tn, tokbuf());
            if me >= 0 {
                let mv: i64 = load64(heap + O_EVAL + me * 8);
                next_token();
                return mv;
            }
            set_back(savep);
        } else {
            set_back(savep);
        }
        # enum 值也可作 const 原子（v1.981）
        let ev: i64 = enum_value(tokbuf());
        if ev >= 0 {
            let evv: i64 = load64(heap + O_EVAL + ev * 8);
            next_token();
            return evv;
        }
        let si: i64 = sym_lookup(tokbuf());
        if si >= 0 {
            if load64(heap + O_SK + si * 8) == 4 {
                let v: i64 = load64(heap + O_SCV + si * 8);
                next_token();
                return v;
            }
            # v1.1046: const 数组编译期下标 A[0] —— O_DATA 镜像直接取值
            if load64(heap + O_SK + si * 8) == 2 {
                let cst: i64 = sym_type(si);
                if ty_kind(cst) == 3 {
                    next_token();
                    if tok_is("[") == 1 {
                        next_token();
                        let iv: i64 = const_expr();
                        expect("]");
                        if iv < 0 { return err_at2("const array index: negative", gv(K_LINE), gv(K_COL)); }
                        if iv >= ty_b(cst) { return err_at2("const array index out of bounds", gv(K_LINE), gv(K_COL)); }
                        let da: i64 = sym_addr(si) - 268435456;
                        if ty_kind(ty_a(cst)) == 5 {
                            return load8(heap + O_DATA + da + iv);
                        }
                        return load64(heap + O_DATA + da + iv * 8);
                    }
                    return err_at2("const: array requires subscript", gv(K_LINE), gv(K_COL));
                }
            }
        }
        return err_at2("const: unknown identifier", gv(K_LINE), gv(K_COL));
    }
    return err_at2("const: expected number", gv(K_LINE), gv(K_COL));
}

fn const_term() -> i64 {
    let v: i64 = const_atom();
    while tok_is("*") == 1 || tok_is("/") == 1 || tok_is("%") == 1 {
        let op: i64 = tok_is("*") + tok_is("/") * 2 + tok_is("%") * 3;
        next_token();
        let r: i64 = const_atom();
        if op == 1 { v = v * r; } else {
            if r == 0 { return err_at2("const: division by zero", gv(K_LINE), gv(K_COL)); }
            if op == 2 { v = v / r; } else { v = v % r; }
        }
    }
    return v;
}

fn const_expr() -> i64 {
    let v: i64 = const_term();
    while tok_is("+") == 1 || tok_is("-") == 1 {
        let op: i64 = tok_is("+") + tok_is("-") * 2;
        next_token();
        let r: i64 = const_term();
        if op == 1 { v = v + r; } else { v = v - r; }
    }
    # 移位（v1.988）：与 parse_shift 对应，<< 为 3、>> 为 2
    while tok_is("<<") == 1 || tok_is(">>") == 1 {
        let op: i64 = tok_is(">>") * 2 + tok_is("<<") * 3;
        next_token();
        let r: i64 = const_term();
        if op == 3 { v = v << r; } else { v = v >> r; }
    }
    # 位运算 & | ^（v1.990）：在移位之后求值（优先级最低近似）
    while tok_is("&") == 1 || tok_is("|") == 1 || tok_is("^") == 1 {
        let op: i64 = tok_is("&") + tok_is("|") * 2 + tok_is("^") * 3;
        next_token();
        let r: i64 = const_term();
        if op == 1 { v = v & r; } else {
            if op == 2 { v = v | r; } else { v = v ^ r; }
        }
    }
    # 逻辑 && ||（v1.1002）：编译期短路（无副作用，仅取真值）
    while tok_is("&&") == 1 || tok_is("||") == 1 {
        let lo: i64 = tok_is("||");
        next_token();
        let r: i64 = const_expr();
        if lo == 1 { v = v | r; } else { v = v & r; }
    }
    # 比较（v1.1003）：== != < <= > >=，返回 0/1
    while tok_is("==") == 1 || tok_is("!=") == 1 || tok_is("<") == 1 || tok_is("<=") == 1 || tok_is(">") == 1 || tok_is(">=") == 1 {
        let cop: i64 = tok_is("==") + tok_is("!=") * 2 + tok_is("<") * 3 + tok_is("<=") * 4 + tok_is(">") * 5 + tok_is(">=") * 6;
        next_token();
        let r: i64 = const_expr();
        let b: i64 = 0;
        if cop == 1 { if v == r { b = 1; } } else {
            if cop == 2 { if v != r { b = 1; } } else {
                if cop == 3 { if v < r { b = 1; } } else {
                    if cop == 4 { if v <= r { b = 1; } } else {
                        if cop == 5 { if v > r { b = 1; } } else {
                            if v >= r { b = 1; }
                        }
                    }
                }
            }
        }
        v = b;
    }
    return v;
}

fn parse_global() -> i64 {
    next_token();
    memcpy(scratch2(), tokbuf());
    next_token();
    expect(":");
    if tok_is("i64") == 0 {
        if gv(K_TKIND) == 1 {
            let si: i64 = st_lookup(tokbuf());
            if si >= 0 {
                next_token();
                # v1.1091: var G: P = P { x: 1; y: 2; }; —— 字面量初始化
                let gfv: [8] i64;
                let gfn: i64 = st_nfields(si);
                let gfj: i64 = 0;
                while gfj < 8 { gfv[gfj] = 0 - 1; gfj = gfj + 1; }
                let ghas: i64 = accept("=");
                if ghas == 1 {
                    # P { x: 1; y: 2; }
                    let gnm2: i64 = heap + O_SCAL + 6200;
                    memcpy(gnm2, tokbuf());
                    next_token();
                    expect("{");
                    while tok_is("}") == 0 {
                        memcpy(scratch1(), tokbuf());
                        next_token();
                        expect(":");
                        parse_expr();
                        # 字段下标
                        let ffi2: i64 = 0;
                        while ffi2 < gfn {
                            if streq(scratch1(), st_field_name(si, ffi2)) == 1 { gfv[ffi2] = gv(K_TIVAL); }
                            ffi2 = ffi2 + 1;
                        }
                        if tok_is(";") == 1 { next_token(); }
                    }
                    expect("}");
                }
                expect(";");
                # 同全局变量：槽数必须是 st_words，见上面那条注释
                let n: i64 = st_words(si);
                data_align(16);
                let addr: i64 = 268435456 + gv(K_DLEN);
                let j: i64 = 0;
                while j < n {
                    # v1.1060: 全局 struct 字段默认值（与局部 let 同约定）
                    let dv2: i64 = 0;
                    let fj2: i64 = 0;
                    # v1.1091: 字面量初始化值优先
                    let fk2: i64 = 0;
                    while fk2 < gfn {
                        if st_field_off(si, fk2) == j * 8 {
                            if gfv[fk2] != 0 - 1 { dv2 = gfv[fk2]; }
                        }
                        fk2 = fk2 + 1;
                    }
                    while fj2 < st_nfields(si) {
                        if st_field_off(si, fj2) == j * 8 {
                            if SDH[si * 64 + fj2] == 1 { if gfv[fj2] == 0 - 1 { dv2 = SDV[si * 64 + fj2]; } }
                        }
                        fj2 = fj2 + 1;
                    }
                    dquad(dv2);
                    j = j + 1;
                }
                let id: i64 = sym_add(scratch2(), 2, addr, 0);
                store64(heap + O_STY + id * 8, ty_struct(si));
                return 0;
            }
        }
    }
    if tok_is("[") == 1 {
        let n: i64 = 0;
        next_token();
        if gv(K_TKIND) == 2 {
            n = gv(K_TIVAL);
        } else {
            if gv(K_TKIND) == 1 {
                # const 名做数组长度（v1.975）；O_SU 标记（v1.1000）
                let csi: i64 = sym_lookup(tokbuf());
                if csi >= 0 {
                    if load64(heap + O_SK + csi * 8) == 4 {
                        n = load64(heap + O_SCV + csi * 8);
                        store64(heap + O_SU + csi * 8, 1);
                    }
                }
            }
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        # v1.1050 二维 / v1.1058 任意维 —— et 声明前收全部内维到 O_LSTV
        # （[2][3][4] 存 3,4 内维在前），元素类型出来后倒序逐层包装。
        let ndims: i64 = 0;
        while tok_is("[") == 1 {
            let dimx: i64 = 0 - 1;
            next_token();
            if gv(K_TKIND) == 2 { dimx = gv(K_TIVAL); next_token(); }
            else {
                if gv(K_TKIND) == 1 {
                    let csi2: i64 = sym_lookup(tokbuf());
                    if csi2 >= 0 {
                        if load64(heap + O_SK + csi2 * 8) == 4 {
                            dimx = load64(heap + O_SCV + csi2 * 8);
                            next_token();
                        }
                    }
                }
            }
            expect("]");
            if dimx <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            store64(heap + O_LSTV + ndims * 8, dimx);
            ndims = ndims + 1;
        }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("f64") == 1 {
                et = ty_float();
                next_token();
            } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if tok_is("ptr") == 1 { next_token(); et = ty_ptr(parse_ptr_target()); }   # v1.1043
                else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        # v1.1057: enum 名作类型（等价 i64）
                        let enmL: i64 = intern(tokbuf());
                        if enum_type_exists(enmL) == 1 {
                            next_token();
                            et = ty_int();
                        } else {
                            # v1.1110: 前向 struct —— 预注册
                            et = ty_struct(st_add(tokbuf()));
                            next_token();
                        }
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
                }
                }
            }
        }
        # v1.1058: 内维倒序包装（[2][3] et=ty_array(ty_array(elem,3),2)）
        let wi: i64 = ndims - 1;
        while wi >= 0 {
            et = ty_array(et, load64(heap + O_LSTV + wi * 8));
            wi = wi - 1;
        }
        # v1.1030: 全局数组可省略初始化（var G: [N] T;）—— 默认 0 填充
        let lcnt: i64 = 0 - 1;
        let sinit: i64 = 0 - 1;
        let has_eq: i64 = accept("=");
        if has_eq == 0 {
            if tok_is(";") == 0 { return syntax_error(); }
        }
        if has_eq == 1 {
        if tok_is("[") == 1 { lcnt = parse_i64_list(); }
        else {
            if gv(K_TKIND) == 3 { sinit = gv(K_STROFF); }
        }
        }
        let v: i64 = gv(K_TIVAL);
        if has_eq == 0 { v = 0; }   # v1.1030: 无初始化默认 0
        # 🔴 列表分支下 **不能再 next_token**：parse_i64_list 结束时就停在
        #    `;` 上（它内部的 expect("]") 已经把 `]` 吃掉）。
        #    多走一步会跳过分号，于是 expect(";") 读到下一行开头 ——
        #    报错位置指向**下一行**（3:1），很容易误判成下一行写错了。
        #    v1.1030：无初始化时 token 已停在 ';'，同样不能再吃。
        if has_eq == 1 { if lcnt < 0 { next_token(); } }
        expect(";");
        data_align(16);
        let addr: i64 = 268435456 + gv(K_DLEN);
        let esz: i64 = ty_size(et);
        let i: i64 = 0;
        if ty_kind(et) == 5 {
            # byte 数组：一个元素一个字节。
            # 原来走的是 esz/8 = 0 的分支——一个字节都没分配，
            # 于是数组地址直接落在下一个全局变量上，写数组就是写别人。
            while i < n {
                if sinit >= 0 {
                    if i < gv(K_NSTR) - sinit - 1 { dbyte(load8(heap + O_STRS + sinit + i)); }
                    else { dbyte(0); }
                } else {
                    # 🔴 读字符串池必须用 load8，不能用 sbyte。
                    #    sbyte(i) = load8(heap + K_SRCBASE + i) —— 它是**源码**
                    #    的读字节函数，参数是源码偏移。拿绝对地址当偏移传进去
                    #    会读到 O_SRC 之后几十 MB 处 → 段错误。
                    if lcnt >= 0 {
                        if i < lcnt { dbyte(load64(heap + O_LSTV + i * 8) & 255); }
                        else { dbyte(0); }
                    } else { dbyte(v & 255); }
                }
                i = i + 1;
            }
            # 补齐到 8 字节，让后面的全局变量仍对齐
            while (gv(K_DLEN) & 7) != 0 {
                dbyte(0);
            }
        } else {
            while i < n {
                if lcnt >= 0 {
                    if i < lcnt { dquad(load64(heap + O_LSTV + i * 8)); }
                    else { dquad(0); }
                } else {
                    if ty_kind(et) == 0 {
                        dquad(v);
                    } else {
                        let j: i64 = 0;
                        while j < esz / 8 {
                            dquad(0);
                            j = j + 1;
                        }
                    }
                }
                i = i + 1;
            }
        }
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let id: i64 = sym_add(scratch2(), 2, addr, 0);
        store64(heap + O_STY + id * 8, ty_array(et, n));
        return 0;
    }
    let vt: i64 = ty_int();
    if accept("str") == 1 {
        vt = ty_str();
    } else {
        if accept("i64") == 1 {
            vt = ty_int();
        } else {
            if accept("f64") == 1 {
                # v1.1128: 全局 f64 var —— 字面量按 f64_bits 落数据段位模式
                vt = ty_float();
            } else {
            if accept("byte") == 1 {
                vt = ty_byte();
            } else {
                # v1.1057: enum 名作全局 var 类型（等价 i64）
                if gv(K_TKIND) == 1 {
                    let genm: i64 = intern(tokbuf());
                    if enum_type_exists(genm) == 1 {
                        next_token();
                        vt = ty_int();
                    } else {
                        return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                    }
                } else {
                    return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
            }
        }
    }
    # v1.1032: 全局标量可省略初始化（var X: i64;）—— 默认 0
    let ghe: i64 = accept("=");
    if ghe == 0 {
        if tok_is(";") == 0 { return syntax_error(); }
        let gaddr0: i64 = 268435456 + gv(K_DLEN);
        data_align(16);
        let gaddr: i64 = 268435456 + gv(K_DLEN);
        dquad(0);
        if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let gid: i64 = sym_add(scratch2(), 2, gaddr, 0);
        store64(heap + O_STY + gid * 8, vt);
        dbg_gvar(scratch2(), gaddr, gv(K_LINE), vt);
        expect(";");
        return 0;
    }
    let v: i64 = gv(K_TIVAL);
    # v1.1128: 负号（f64 位模式由 f64_bits(neg=1) 处理；整数取负）
    let gneg: i64 = 0;
    if accept("-") == 1 { gneg = 1; }
    if gv(K_TKIND) == 2 {
        # v1.1128: f64 字面量 → IEEE754 位模式（负号已含于 bits）
        if gv(K_TFLT) == 1 && ty_kind(vt) == 6 {
            v = f64_bits(gv(K_TFDIG), gv(K_TFDIGN), FSTICKY, gneg);
        } else {
            if gneg == 1 { v = 0 - gv(K_TIVAL); }
        }
        next_token();
    } else {
        if gv(K_TKIND) == 1 {
            # const 表达式（v1.984）：const_atom 已消费名字，
            # const_expr 继续折叠 +/-/*///
            let gcsi: i64 = sym_lookup(tokbuf());
            if gcsi >= 0 {
                if load64(heap + O_SK + gcsi * 8) == 4 {
                    v = const_expr();
                    if gneg == 1 { v = 0 - v; }
                } else {
                    return syntax_error();
                }
            } else {
                let ge: i64 = enum_value(tokbuf());
                if ge >= 0 {
                    v = const_expr();
                    if gneg == 1 { v = 0 - v; }
                } else {
                    return syntax_error();
                }
            }
        } else {
            next_token();
        }
    }
    expect(";");
    data_align(16);
    let addr: i64 = 268435456 + gv(K_DLEN);
    dquad(v);
    if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    let id: i64 = sym_add(scratch2(), 2, addr, 0);
    store64(heap + O_STY + id * 8, vt);
    dbg_gvar(scratch2(), addr, gv(K_LINE), vt);
    return 0;
}

# 方法定义的第一个形参若是 ptr，则把它的类型收紧为 ptr(类)。
# 这样方法体里 self.w 才能工作 —— 否则 self 只是 ptr(byte)，
# 字段访问会在类型检查处被拒。
fn method_self_class(scratch2_: i64) -> i64 {
    let i: i64 = 0;
    while load8(scratch2_ + i) != 0 {
        if load8(scratch2_ + i) == 46 { break; }     # '.'
        i = i + 1;
    }
    if load8(scratch2_ + i) != 46 { return 0 - 1; }
    store8(scratch2_ + i, 0);                        # 截出类名
    let si: i64 = st_lookup(scratch2_);
    store8(scratch2_ + i, 46);                       # 还原
    return si;
}

# v1.1079: '->' 之后的普通返回类型（不含 '[' 数组，那由 parse_arr_ret 处理）。
# 返回类型 id；解析失败返回 -1（调用方报错）。
fn parse_ret_type() -> i64 {
    let rt: i64 = -1;
    if accept("str") == 1 {
        rt = ty_str();
    } else {
    if accept("i64") == 1 {
        rt = ty_int();
    } else {
        if accept("f64") == 1 {
            rt = ty_float();
        } else {
        if accept("bool") == 1 {
            rt = ty_bool();
        } else {
        if accept("ptr") == 1 {
            # v1.1043: -> ptr [i64/byte/P]
            rt = ty_ptr(parse_ptr_target());
        } else {
            if gv(K_TKIND) == 1 {
                let rsi: i64 = st_lookup(tokbuf());
                let renum: i64 = 0;
                if rsi < 0 {
                    # v1.1057: enum 名作返回类型（等价 i64）
                    let renm: i64 = intern(tokbuf());
                    if enum_type_exists(renm) == 1 {
                        next_token();
                        rt = ty_int();
                        renum = 1;
                    }
                }
                if renum == 1 {
                    # enum 命中已消费（rt=ty_int），跳过 struct 路径
                } else {
                if rsi < 0 {
                    # v1.1110: 前向 struct —— 预注册
                    rsi = st_add(tokbuf());
                }
                if load64(heap + O_STF + rsi * 8) > 2 {
                    # 3 个字段起要走隐藏指针（System V），暂不支持
                    return -1;
                }
                rt = ty_struct(rsi);
                next_token();
                }
            } else {
                return -1;
            }
        }
        }
        }
    }
    }
    return rt;
}

# v1.1079: 解析 -> [N] T 数组返回类型。命中返回类型 id，未命中回退返回 -1。
fn parse_arr_ret() -> i64 {
    let back: i64 = gv(K_TOKPOS);
    next_token();
    let n: i64 = 0;
    if gv(K_TKIND) == 2 { n = gv(K_TIVAL); }
    next_token();
    expect("]");
    let et: i64 = -1;
    if tok_is("i64") == 1 { next_token(); et = ty_int(); }
    else {
        if tok_is("byte") == 1 { next_token(); et = ty_byte(); }
        else {
            if tok_is("ptr") == 1 { next_token(); et = ty_ptr(parse_ptr_target()); }
            else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 { next_token(); et = ty_struct(si); }
                }
            }
        }
    }
    if et < 0 { set_back(back); return -1; }
    if n <= 0 { set_back(back); return -1; }
    return ty_array(et, n);
}

fn parse_func() -> i64 {
    next_token();
    memcpy(scratch2(), tokbuf());
    next_token();
    # 方法定义：fn Class.method(...)。函数名整体 intern 成 "Class.method"，
    # 于是它与普通函数共用同一套符号表 / 回填机制，不需要单独的调用通路。
    # 方法定义语法糖 fn Class.method(...) 已撤回（配合方法调用一起撤）。
    # 方法就是普通函数：fn Rect_area(self: ptr) { ... }
    let fnln: i64 = gv(K_LINE);
    let fncol: i64 = gv(K_COL);
    let fnpos: i64 = gv(K_TOKPOS);
    expect("(");
    sv(K_DEPTH, 1);
    sv(K_CUROFF, -16);
    store64(heap + O_ERRLAB, 0 - 1);
    # -p：入口插桩。
    #
    # 🔴 **根因（1.59.0 那个"死区"）**：插桩代码不能发射在 `let addr` 之前。
    #    addr = 4194304 + 176 + K_CLEN 是在**后面**才取的，而它才是函数入口
    #    地址（写进 O_SA 供 call 使用）。插桩先发射 → addr 落在插桩之后 →
    #    调用直接跳到 prologue，插桩永远不执行。
    #    用 int3 验证过：程序正常跑完、一次都没触发，且没有任何报错。
    #
    # 修法：这里**只**把函数名写进数据段（prof_emit_name 只动数据段，
    # 不影响 K_CLEN），真正的调用代码放到 g_prologue() 之后发射。
    # 另外 scratch2() 到这里之后不一定还有效，所以名字必须现在就固化。
    if streq(scratch2(), "main") == 1 { sv(K_PROFMAIN, 1); } else { sv(K_PROFMAIN, 0); }
    let pnm: i64 = 0;
    if gv(K_PROF) == 1 {
        if gv(K_INIMP) == 0 {
            let ps0: i64 = sym_lookup_func("prof_enter");
            if ps0 < 0 {
                return err_atp("-p requires: import \"prof.mo\"", gv(K_LINE), gv(K_COL), gv(K_TOKPOS));
            }
            pnm = prof_emit_name(scratch2());
        }
    }
    let nb: i64 = 0;
    let addr: i64 = 4194304 + 176 + gv(K_CLEN);
    # -g：把**函数定义行**登记进行号表。必须在发射序言之前 —— 此刻
    #   K_CLEN 正是函数入口偏移，之后就被序言推进了。
    #   少了这一条，函数入口地址在行号表里没有记录，行号表实际从
    #   函数体第一行开始，于是定义行下不了断点（dwmo -l 可检出）。
    dbg_mark_at(fnln);
    let ex: i64 = sym_lookup_func(scratch2());
    # -g：登记到函数表，high_pc 等函数体解析完再回填。
    # 必须放在 addr 之后 —— 墨语言要求符号**先定义后使用**。
    let fidx: i64 = 0 - 1;
    if gv(K_DBG) == 1 {
        fidx = gv(K_NDF);
        if fidx < 4000 {
            let fp: i64 = DBG + O_DF + fidx * 40;
            store64(fp, intern(scratch2()));
            store64(fp + 8, addr);
            store64(fp + 16, addr);
            store64(fp + 24, fnln);
            # 所属源文件下标。之前函数表只为**主文件**登记，于是库里的函数
            # 在 .debug_info 里根本没有 DIE —— gdb 对那些帧显示不了函数名，
            # 而行号表里的库代码又落在"任何函数之外"（dwmo 能检出）。
            store64(fp + 32, gv(K_CURFILE));
            sv(K_NDF, fidx + 1);
            sv(K_CURFN, fidx);
        } else {
            fidx = 0 - 1;
        }
    }
    let fsi: i64 = ex;
    if ex >= 0 {
        if sym_addr(ex) != 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        store64(heap + O_SA + ex * 8, addr);
    } else {
        fsi = sym_add(scratch2(), 0, addr, 0);
    }
    # 方法登记已移除：现按 "Class.method" 整体作为函数名查符号表。
    # 原先的 method_reg 会让编译器段错误（intern 传入的偏移在拼接后失效）。
    let ra: i64 = gv(K_NSYM);
    sv(K_FNBASE, ra);
    # v1.1037: 本函数默认参数表清 -1；ndf = 有默认值的形参个数（尾部连续）
    let dvi: i64 = 0;
    while dvi < 8 {
        store64(DFV + fsi * 80 + dvi * 8, 0 - 1);
        dvi = dvi + 1;
    }
    store64(DFVDONE + fsi * 8, 1);
    let ndf: i64 = 0;
    # 各层函数的符号表基线入栈：EBS[K_NEST] = 本层第一个局部符号下标。
    # cap_depth 靠它算出符号属于往上第几层（K_ENCBASE 只记了一层，深层不够用）。
    store64(heap + O_EBS + load64(heap + O_NEST) * 8, ra);
    while tok_is(")") == 0 {
        memcpy(scratch1(), tokbuf());
        next_token();
        expect(":");
        let pt: i64 = ty_int();
        if accept("str") == 1 {
            pt = ty_str();
        } else {
        if accept("i64") == 1 {
            pt = ty_int();
        } else {
            if accept("f64") == 1 {
                pt = ty_float();
            } else {
            if accept("bool") == 1 {
                pt = ty_bool();
            } else {
            if accept("byte") == 1 {
                pt = ty_byte();
            } else {
                if accept("ptr") == 1 {
                    # v1.1043: 形参 ptr [i64/byte/P]
                    pt = ty_ptr(parse_ptr_target());
                } else {
                if tok_is("[") == 1 {
                    # v1.1087: 数组形参 fn sum(a: [3] i64) —— 一维数组按
                    # ptr(元素) 传入（实参数组退化为首地址，a[i] 标量步长）。
                    # 长度信息不随参数传递（调用方需自行传 len）。
                    next_token();
                    let dimp: i64 = 0;
                    if gv(K_TKIND) == 2 { dimp = gv(K_TIVAL); next_token(); }
                    expect("]");
                    let etp: i64 = ty_int();
                    if accept("i64") == 1 { etp = ty_int(); }
                    else { if accept("byte") == 1 { etp = ty_byte(); }
                    else { if accept("f64") == 1 { etp = ty_float(); }
                    else { if accept("bool") == 1 { etp = ty_bool(); }
                    else { if gv(K_TKIND) == 1 {
                        let qsi: i64 = st_lookup(tokbuf());
                        if qsi >= 0 { etp = ty_struct(qsi); next_token(); }
                        else { return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                    } else { return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                    } } } }
                    pt = ty_ptr(etp);
                } else {
                    # 形参声明成**类名** = this 指针（对标 C++ 的 Rect& self）。
                    # 实现为 ptr(该类)：于是方法体里 self.w 能直接写 ——
                    # field_chain 已支持 ptr→struct 的字段访问。
                    if gv(K_TKIND) == 1 {
                        let psi: i64 = st_lookup(tokbuf());
                        if psi >= 0 {
                            pt = ty_ptr(ty_struct(psi));
                            next_token();
                        } else {
                            # v1.1057: enum 名作形参类型（等价 i64）
                            let penm: i64 = intern(tokbuf());
                            if enum_type_exists(penm) == 1 {
                                next_token();
                                pt = ty_int();
                            } else {
                                # v1.1110: 前向 struct —— 预注册
                                pt = ty_struct(st_add(tokbuf()));
                                next_token();
                            }
                        }
                    } else {
                        return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                    }
                }
                }
            }
            }
            }
        }
        }
        let off: i64 = gv(K_CUROFF);
        sv(K_CUROFF, off - 8);
        if sym_dup(scratch1()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let pid: i64 = sym_add(scratch1(), 1, off, 0);
        store64(heap + O_STY + pid * 8, pt);
        # v1.1111: struct 形参 = 引用语义（槽内存调用方对象地址）—— return 按值拷贝时须解引用一层
        if ty_kind(pt) == 2 || (ty_kind(pt) == 4 && ty_kind(ty_a(pt)) == 2) { store64(heap + O_SP + pid * 8, 1); }
        # v1.1039: 形参名登记（命名实参用）：PNMT[fid*256 + pidx*8] = 名字地址
        store64(PNMT + fsi * 256 + nb * 8, heap + O_NAMES + intern(scratch1()));
        # -g：形参也要登记成变量，否则调试器在被调用函数里 p <参数名>
        #     什么都看不到（1.100：只有 let 声明的局部变量有 DIE）。
        #     偏移用的是**本帧**的槽 —— 参数被复制进自己的栈帧，
        #     与局部变量同一套负数偏移（-8, -16, ...）。
        dbg_var(scratch1(), off, gv(K_PLINE), pt);
        # v1.1037: 形参默认值（const 表达式，必须尾部连续）
        if accept("=") == 1 {
            let dv: i64 = const_expr();
            store64(DFV + fsi * 80 + nb * 8, dv);
            store8(DFVHAS + fsi * 8 + nb, 1);
            ndf = nb + 1;
        } else {
            if ndf > 0 {
                return err_atp("default parameters must be trailing", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
        nb = nb + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return syntax_error(); }
        }
    }
    expect(")");
    # v1.1036: void 函数 —— 省略 "-> i64"（默认返回 i64）
    let hasarrow: i64 = accept("->");
    sv(K_VOIDFN, 1 - hasarrow);
    # 返回类型：i64（默认） / ptr / 类名
    #
    # **为什么之前只支持 i64**：结构体与指针返回需要按 System V 处理
    # （≤16 字节走 RAX:RDX，更大走隐藏指针），而所有返回值都塞在 rax 里
    # 是最省事的。代价是库函数只能返回 i64 —— 于是 str_trim 这类
    # 明明返回地址的函数，被 sfmt 当成数字打印（只能靠 ptr(v) 绕过）。
    let rt: i64 = ty_int();
    if hasarrow == 0 {
        rt = ty_int();
    } else {
        # v1.1079: '->' 返回类型整体提出为独立 fn（str/i64/f64/bool/ptr/
        # struct/enum），parse_func 嵌套深度因此减 1 —— 之前再加一层
        # if/else 就会让符号作用域错位（duplicate definition 假报）。
        if tok_is("[") == 1 {
            rt = parse_arr_ret();
            if rt < 0 { return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        } else {
            rt = parse_ret_type();
            if rt < 0 { return err_atp("unknown return type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        }
    }
    store64(heap + O_SRT + fsi * 8, rt);
    CUR_RET = rt;
    # 参数上限 6：**静默错误比限制更糟**。
    #
    # 第 7 个起的参数传递是错的：调用方顺序 push 实参再 pop 前 6 个到
    # 寄存器，于是 na>6 时 rdi..r9 拿到的是参数 3..8，栈上剩下参数 1、2
    # —— 整体错位。实测 f(1..8) 里 h(a)+hh+i 得 9 而不是 17，
    # 与"rdi=3、参数7槽=1、参数8槽=2"完全吻合。
    #
    # 只做加法的函数看不出来（加法可交换），所以这个 bug 极隐蔽。
    # 正确修法要改调用约定（按 System V 布置栈参数），改动面大；
    # 在此之前先明确报错，绝不生成悄悄算错的代码。
    if nb > 32 {
        return err_atp("too many parameters (limit 32)", fnln, fncol, fnpos);
    }
    store64(heap + O_SP + fsi * 8, nb);
    store64(DFV + fsi * 80 + 9 * 8, ndf);   # v1.1038: 槽 9 存 ndf（槽 0..7 属形参）
    g_prologue();
    let i: i64 = 0;
    while i < nb {
        # 🔴 参数槽也从 [rbp-16] 起：rbx 保存槽固定占 [rbp-8]，
        #    参数写在 -8 会把保存的 rbx 覆盖掉（与局部变量同理）。
        emit_store_arg(-8 * (i + 2), i, nb);
        i = i + 1;
    }
    sv(K_HASRET, 0);
    # -p：真正的入口插桩（放在 prologue 之后，于是在 addr 之后、函数体之前）
    if pnm != 0 {
        let ps: i64 = sym_lookup_func("prof_enter");
        spill_cache();
        emit1(0x57);                      # push rdi（第一个参数，须保留）
        emit1(0x56);                      # push rsi（凑 16 字节对齐）
        g_movabs_rax(pnm);
        ops3(0x48, 0x89, 0xc7);           # mov rdi, rax
        emit_call_patch(ps);
        emit1(0x5e);                      # pop rsi
        emit1(0x5f);                      # pop rdi
    }
    parse_block(2);
    if gv(K_HASRET) == 0 {
        # v1.1036: void 函数（省略 "->"）可以没有 return
        if gv(K_VOIDFN) == 0 {
            return err_atp("missing return statement in a function returning i64", fnln, fncol, fnpos);
        }
    }
    let frame: i64 = 0 - gv(K_CUROFF);
    # 🔴 序言多了一个 push rbx：进入函数体时 rsp = rbp - 8 - frame。
    #    rbp 本身 ≡ 0 (mod 16)，要让函数体里的 call 满足 rsp%16==0，
    #    frame 必须 ≡ 8 (mod 16) —— 仍按 ≡ 0 对齐会整体偏 8 字节，
    #    调 printf 这类依赖栈对齐的 libc 函数时会落到未对齐栈上。
    frame = ((frame + 7) & -16) + 8;
    let pp: i64 = gv(K_FPATCH);
    store8(heap + O_CODE + pp, frame & 255);
    store8(heap + O_CODE + pp + 1, (frame >> 8) & 255);
    store8(heap + O_CODE + pp + 2, (frame >> 16) & 255);
    store8(heap + O_CODE + pp + 3, (frame >> 24) & 255);
    # `?` 的错误出口：所有 jl 都跳到这里，rax 已是错误码，
    # 直接走标准尾声即可（与正常 return 共用同一份尾声代码）。
    # 必须放在 g_epilogue **之前** —— 放在之后就成了跳到 ret 后面。
    let el2: i64 = load64(heap + O_ERRLAB);
    if el2 >= 0 { place_label(el2); }
    g_epilogue();
    # -g：回填本函数的 high_pc（当前代码末尾）
    if gv(K_DBG) == 1 {
        if fidx >= 0 {
            store64(DBG + O_DF + fidx * 40 + 16, 4194304 + 176 + gv(K_CLEN));
        }
    }
    sv(K_NSYM, ra);
    sv(K_DEPTH, 0);
    return 0;
}

fn next_line(p: i64) -> i64 {
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        if sbyte(p) == 10 { return p + 1; }
        p = p + 1;
    }
    return p;
}

# 预扫描：把顶层 fn 名登记为函数符号，使前向与互递归调用可用
fn predeclare() -> i64 {
    let p: i64 = 0;
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        let c: i64 = sbyte(p);
        if c == 35 {
            p = skip_comment(p);
        } else {
            if c == 102 {
                if sbyte(p + 1) == 110 {
                    if sbyte(p + 2) == 32 {
                        let q: i64 = p + 3;
                        let i: i64 = 0;
                        let b: i64 = scratch1();
                        while is_alnum(sbyte(q + i)) == 1 {
                            store8(b + i, sbyte(q + i));
                            i = i + 1;
                        }
                        store8(b + i, 0);
                        if sbyte(q + i) == 40 {
                            # 数形参个数：扫到 ')'，按逗号计。
                            #
                            # 曾经的写法是 `if sbyte(j) == 10 { j = j - 1; }`，
                            # 本意是"遇到换行就停"，但末尾还有 `j = j + 1`，
                            # 一减一加等于原地不动 —— 参数列表只要跨行，
                            # 这里就**无限循环**（编译器挂死，无任何输出）。
                            let np: i64 = 0;
                            let any: i64 = 0;
                            let j: i64 = q + i + 1;
                            let go: i64 = 1;
                            while go == 1 {
                                if j >= n { go = 0; }
                                else {
                                    if sbyte(j) == 41 { go = 0; }
                                    else {
                                        if sbyte(j) == 44 { np = np + 1; }
                                        else {
                                            if sbyte(j) != 10 { any = 1; }
                                        }
                                        j = j + 1;
                                    }
                                }
                            }
                            if any == 1 { np = np + 1; }
                                                        let sid: i64 = sym_add(b, 0, 0, np);
                            # v1.1040: predeclare 顺手抄录形参名 → PNMT，
                            # 使前向调用的命名实参也能查到形参名。
                            # 形参形状: [mut] ident ':' ... ',' 或 ')'。
                            let k2: i64 = q + i + 1;
                            let pi2: i64 = 0;
                            let go2: i64 = 1;
                            while go2 == 1 {
                                # 跳空白（遇到非空白停住 —— 不是退出）
                                let wdone: i64 = 0;
                                while wdone == 0 {
                                    if k2 >= n { wdone = 1; }
                                    else {
                                        let w: i64 = sbyte(k2);
                                        if w == 32 { k2 = k2 + 1; }
                                        else {
                                            if w == 9 { k2 = k2 + 1; }
                                            else {
                                                if w == 10 { k2 = k2 + 1; }
                                                else {
                                                    if w == 13 { k2 = k2 + 1; }
                                                    else { wdone = 1; }
                                                }
                                            }
                                        }
                                    }
                                }
                                if k2 >= n { go2 = 0; }
                                else {
                                    # 读一个 ident
                                    let i3: i64 = 0;
                                    let c3: i64 = sbyte(k2);
                                    if is_alnum(c3) == 1 {
                                        while is_alnum(sbyte(k2 + i3)) == 1 { i3 = i3 + 1; }
                                    }
                                    if i3 == 0 { go2 = 0; }
                                    else {
                                        # 类型名(如 i64) vs 形参名: 形参名后必须紧跟 ':'（跳空白）
                                        let k4: i64 = k2 + i3;
                                        let k5: i64 = k4;
                                        let sp4: i64 = 0;
                                        while sp4 < 8 {
                                            let w4: i64 = sbyte(k5);
                                            if w4 == 32 { k5 = k5 + 1; sp4 = sp4 + 1; }
                                            else {
                                                if w4 == 9 { k5 = k5 + 1; sp4 = sp4 + 1; }
                                                else { sp4 = 99; }
                                            }
                                        }
                                        if sbyte(k5) == 58 {
                                            # 形参名: 抄进 scratch2 再 intern
                                            let b3: i64 = scratch2();
                                            let t3: i64 = 0;
                                            while t3 < i3 {
                                                store8(b3 + t3, sbyte(k2 + t3));
                                                t3 = t3 + 1;
                                            }
                                            store8(b3 + i3, 0);
                                                                                        if pi2 < 60 {
                                                store64(PNMT + sid * 256 + pi2 * 8, heap + O_NAMES + intern(b3));
                                                pi2 = pi2 + 1;
                                                                                            }
                                        }
                                        k2 = k2 + i3;
                                        # 跳到下一个 ',' 或 ')'
                                        let go3: i64 = 1;
                                        while go3 == 1 {
                                            if k2 >= n { go3 = 0; go2 = 0; }
                                            else {
                                                let c5: i64 = sbyte(k2);
                                                if c5 == 44 { k2 = k2 + 1; go3 = 0; }
                                                else {
                                                    if c5 == 41 { go3 = 0; go2 = 0; }
                                                    else { k2 = k2 + 1; }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        p = next_line(p);
                    } else {
                        p = next_line(p);
                    }
                } else {
                    p = next_line(p);
                }
            } else {
                # v1.1112: 'const fn' 行 — 不跳行, 前进 1 字节让内层 'fn ' 扫描命中
                let pk9: i64 = p;
                while sbyte(pk9) == 32 || sbyte(pk9) == 9 { pk9 = pk9 + 1; }
                if sbyte(pk9) == 99 && sbyte(pk9+1) == 111 && sbyte(pk9+2) == 110 && sbyte(pk9+3) == 115 && sbyte(pk9+4) == 116 && sbyte(pk9+5) == 32 && sbyte(pk9+6) == 102 && sbyte(pk9+7) == 110 {
                    p = pk9 + 6;
                } else {
                    p = next_line(p);
                }
            }
        }
    }
    return 0;
}

# 纯查询：该文件是否已导入过（**不登记**）。
#
# 🔴 为什么单独拆一个：imp_seen 查询时会顺手登记，而 parse_import 需要先问
#    一句"这个文件导入过吗"再决定要不要报错 —— 用 imp_seen 问完就已经登记
#    了，随后 compile_file 里的 imp_seen 必然返回 1，**文件根本不会被编译**，
#    而模块名却已经登记好了。那才是真正的静默错误。
fn imp_have(path: i64) -> i64 {
    let n: i64 = gv(K_NIMP);
    let i: i64 = 0;
    while i < n {
        if streq(heap + O_NAMES + load64(heap + O_IMP + i * 8), path) == 1 { return 1; }
        i = i + 1;
    }
    return 0;
}

# 读取并编译 import 的另一个源文件（共享符号表与代码/数据缓冲）
# 已导入过该文件则返回 1（跳过），否则登记并返回 0
fn imp_seen(path: i64) -> i64 {
    if imp_have(path) == 1 { return 1; }
    let n: i64 = gv(K_NIMP);
    store64(heap + O_IMP + n * 8, intern(path));
    sv(K_NIMP, n + 1);
    return 0;
}

# 依次尝试若干路径，返回第一个能打开的 fd；全失败返回 -1
#   1) 原样  2) lib/<basename>  3) ../lib/<basename>
# 让 examples/ 下的程序写 import "io.mo" 就能用上标准库，不必手工拷贝。
# 拼接缓冲直接取 O_SCAL 里的空闲区，不用全局变量（省得再占一个数据段槽）。
fn try_open(path: i64) -> i64 {
    let fd: i64 = syscall(2, path, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    let b: i64 = path;
    let i: i64 = strlen(path);
    while i > 0 {
        if load8(path + i - 1) == 47 { b = path + i; i = 0; }
        else { i = i - 1; }
    }
    let p: i64 = heap + O_SCAL + 3000;
    let q: i64 = "lib/";
    let j: i64 = 0;
    while load8(q + j) != 0 {
        store8(p + j, load8(q + j));
        j = j + 1;
    }
    let k: i64 = 0;
    while load8(b + k) != 0 {
        store8(p + j + k, load8(b + k));
        k = k + 1;
    }
    store8(p + j + k, 0);
    fd = syscall(2, p, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    let p2: i64 = p + 256;
    let q2: i64 = "../lib/";
    j = 0;
    while load8(q2 + j) != 0 {
        store8(p2 + j, load8(q2 + j));
        j = j + 1;
    }
    k = 0;
    while load8(b + k) != 0 {
        store8(p2 + j + k, load8(b + k));
        k = k + 1;
    }
    store8(p2 + j + k, 0);
    fd = syscall(2, p2, 0, 0, 0, 0, 0);
    if fd >= 0 { return fd; }
    # 4) 逐个已加载源文件（先主文件 INPATH，再 imp 表）的目录 +
    #    basename —— 项目目录/包目录下的 import 不必拷进 lib/。
    #    O_IMP 存的是 O_NAMES 偏移（intern），取路径要 heap+O_NAMES+。
    let d: i64 = p2 + 256;
    let nimp: i64 = gv(K_NIMP);
    let m: i64 = -1;
    while m < nimp {
        let cf: i64 = 0;
        if m < 0 {
            cf = INPATH;
        } else {
            cf = heap + O_NAMES + load64(heap + O_IMP + m * 8);
        }
        if cf != 0 {
            let e: i64 = strlen(cf);
            let sl: i64 = -1;
            let t: i64 = 0;
            while t < e {
                if load8(cf + t) == 47 { sl = t; }
                t = t + 1;
            }
            if sl >= 0 {
                let u: i64 = 0;
                while u <= sl {
                    store8(d + u, load8(cf + u));
                    u = u + 1;
                }
                let v: i64 = 0;
                while load8(b + v) != 0 {
                    store8(d + u + v, load8(b + v));
                    v = v + 1;
                }
                store8(d + u + v, 0);
                fd = syscall(2, d, 0, 0, 0, 0, 0);
                if fd >= 0 { return fd; }
            }
        }
        m = m + 1;
    }
    return -1;
}

fn compile_file(path: i64) -> i64 {
    if imp_seen(path) == 1 { return 0; }
    let s_srclen: i64 = gv(K_SRCLEN);
    let s_tok: i64 = gv(K_TOKPOS);
    let s_base: i64 = gv(K_SRCBASE);
    let s_cf: i64 = gv(K_CURFILE);
    let s_in: i64 = INPATH;

    let k: i64 = gv(K_NFILE);
    if k >= 32 { return die("too many imported files (limit 32)\n"); }
    sv(K_NFILE, k + 1);
    # -g：登记文件名与「当前文件下标」，行号表每条记录要带上它。
    # 下标 0 留给主文件，所以 import 从 1 起（main 里 sv(K_NFILE, 1)）。
    dbg_fname(k, path);
    sv(K_CURFILE, k);
    let base: i64 = O_FILES + k * 524288;


    let fd: i64 = try_open(path);
    if fd < 0 {
        syscall(1, 2, "cannot open import: ", 20, 0, 0, 0);
        syscall(1, 2, path, strlen(path), 0, 0, 0);
        syscall(1, 2, "\n", 1, 0, 0, 0);
        syscall(60, 1, 0, 0, 0, 0, 0);
    }
    let n: i64 = syscall(0, fd, heap + base, 1048575, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);

    sv(K_SRCBASE, base);
    sv(K_SRCLEN, n);
    sv(K_POS, 0);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    INPATH = path;

    let en0: i64 = ERR_N;
    parse_program();
    let en1: i64 = ERR_N;

    sv(K_SRCBASE, s_base);
    sv(K_SRCLEN, s_srclen);
    sv(K_CURFILE, s_cf);
    INPATH = s_in;
    set_back(s_tok);
    if en1 > en0 {
        return -1;
    }
    return 0;
}

fn parse_import() -> i64 {
    next_token();
    if gv(K_TKIND) != 3 { return syntax_error(); }
    let p: i64 = strpool();
    next_token();
    # import "x.mo" path="/dir"; —— 显式目录查找（v1.207.0）
    if tok_is("path") == 1 {
        next_token();
        expect("=");
        if gv(K_TKIND) != 3 { return syntax_error(); }
        let pb: i64 = strpool();
        # 拼 dir + "/" + basename(p)
        let full: i64 = heap + O_SCAL + 3600;
        let j2: i64 = 0;
        # 相对 path：相对「当前源文件」目录（INPATH，v1.207.0）
        if load8(pb) != 47 {
            let ip: i64 = INPATH;
            let il: i64 = strlen(ip);
            let islash: i64 = 0 - 1;
            let i3: i64 = 0;
            while i3 < il {
                if load8(ip + i3) == 47 { islash = i3; }
                i3 = i3 + 1;
            }
            if islash >= 0 {
                let i4: i64 = 0;
                while i4 <= islash {
                    store8(full + i4, load8(ip + i4));
                    i4 = i4 + 1;
                }
                j2 = islash + 1;
            }
        }
        let pj: i64 = 0;
        while load8(pb + pj) != 0 {
            store8(full + j2, load8(pb + pj));
            j2 = j2 + 1;
            pj = pj + 1;
        }
        if j2 > 0 && load8(full + j2 - 1) != 47 {
            store8(full + j2, 47);
            j2 = j2 + 1;
        }
        # basename(p)
        let b2: i64 = p;
        let i2: i64 = strlen(p);
        while i2 > 0 {
            if load8(p + i2 - 1) == 47 { b2 = p + i2; i2 = 0; }
            else { i2 = i2 - 1; }
        }
        let k2: i64 = 0;
        while load8(b2 + k2) != 0 {
            store8(full + j2 + k2, load8(b2 + k2));
            k2 = k2 + 1;
        }
        store8(full + j2 + k2, 0);
        p = full;
        next_token();
    }
    # import "x.mo" as N; —— 给该文件一个命名空间前缀
    let pfx: i64 = 0;
    if tok_is("as") == 1 {
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        # 🔴 必须拦住"同一个文件先裸 import、再带 as import"。
        #    那次 as 会因 imp_seen 去重而**什么符号都没收进模块**，
        #    但模块名照样登记 —— 于是 A.anything() 在模块里查不到，
        #    回退到全局，可能静默绑到一个完全无关的同名函数上。
        #    不报错的话，用户看到的是"能编译、结果不对"。
        if imp_have(p) == 1 {
            return err_atp("import as: file already imported; a file can be imported only once", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        let n: i64 = load64(heap + O_NMOD);
        if n >= 64 { return die("too many modules (limit 64)"); }
        let q: i64 = heap + O_MODS + n * 32;
        let tb: i64 = tokbuf();
        let j: i64 = 0;
        while load8(tb + j) != 0 {
            if j >= 30 { return die("module name too long (limit 30)"); }
            store8(q + j, load8(tb + j));
            j = j + 1;
        }
        store8(q + j, 46);                 # '.'
        store8(q + j + 1, 0);
        store64(heap + O_MODP + n * 8, q);
        store64(heap + O_NMOD, n + 1);
        pfx = q;
        next_token();
    }
    expect(";");
    # import 进来的文件**也要记行号**，只是记到它自己的文件下标上
    # （dbg_mark 写 O_LMF[n] = K_CURFILE），这样多文件行号才对得上。
    #
    # 早先这里是 `sv(K_DBG, 0)` 直接关掉，后果是：import 进来的库代码
    # 在行号表里**完全没有记录**，gdb 对那部分地址显示"无行号信息"。
    # 实测一份带 import 的小程序：.text 共 14690 字节，行号记录只覆盖
    # 最后 91 字节 —— 99% 的代码没有行号。编译和运行都不受影响，
    # 所以这件事一直没人发现。
    #
    # K_INIMP 仍然置 1：局部变量表 / 函数表只为**主文件**登记。
    # 那两张表（O_DV/O_DF）容量是按单文件定的，把库的全塞进来会越界。
    let oldimp: i64 = gv(K_INIMP);
    let oldpfx: i64 = gv(K_PFX);
    sv(K_INIMP, 1);
    # 🔴 每个文件的 as 只作用于它自己：内层文件若是裸 import（不带 as），
    #    K_PFX 必须是 0，不能继承外层的。所以这里传 pfx（可能是 0）
    #    而不是"若 pfx==0 就保持外层不变"。
    sv(K_PFX, pfx);
    let r: i64 = compile_file(p);
    sv(K_INIMP, oldimp);
    sv(K_PFX, oldpfx);
    return r;
}

# struct Name { f: i64; g: Other; }
# ==========================================================================
#  class —— 对标 C++ 的类
#
#  实现策略：**类 = 结构体（数据）+ 自由函数（方法）**。
#  这正是 C++ 早期编译器（cfront）的做法，也是在没有 vtable / 成员函数
#  概念的语言里唯一现实的路径。
#
#    class Rect { w: i64; h: i64; }
#    fn Rect.area(self: ptr) -> i64 { return self.w * self.h; }
#    let r: Rect;  r.area();          # 编译为 Rect.area(&r)
#
#  继承采用**字段内联**：把基类字段复制到派生类前面。
#  于是 Derived* 与 Base* 在内存上前缀兼容，向上转换是天然成立的。
#
#  没有虚函数：没有 vtable，也就没有动态分派。
#  这是本实现的明确边界，不假装支持多态。
# ==========================================================================

# 把基类字段复制到派生类前面（继承）
fn inherit_fields(si: i64, base: i64) -> i64 {
    let n: i64 = st_nfields(base);
    let i: i64 = 0;
    while i < n {
        st_add_field(si, st_field_name(base, i), st_field_type(base, i));
        i = i + 1;
    }
    return n;
}

# enum —— 具名整数字面量
#
#   enum Color { RED = 1; GREEN = 2; BLUE = 3; }
#   enum Mode  { FAST; SLOW; }          # 自动 0, 1, 2 ...
#   let c: i64 = Color.RED;
#
# **为什么值得做**：现在代码里满地是 `1` / `2` / `3` 当状态码用
# （lib/json.mo 的 J_TYPE、wavobj.mo 的错误码），读代码的人
# 只能翻注释才知道 3 是什么。enum 让它们有名字。
#
# **为什么不是"真 enum 类型"**：那需要类型检查 + 禁止跨 enum 赋值，
# 改动面大且立刻会破坏现有代码。**常量 + 命名空间**已经解决了
# 90% 的可读性问题，成本却只有十分之一。
# 🔴 `intern()` 返回的是**名字表偏移**，而且**不查重** ——
#    同一个名字 intern 两次会得到两个不同偏移。
#
# 第一版直接比较偏移（`streq(load64(...), ename)`），于是
# `Mode.FAST` 永远查不到（声明时 intern 一次、引用时又 intern 一次），
# 走回退路径 —— 症状是编译带 enum 引用的程序**直接段错误**。
#
# 所以表里存偏移、比较时**比字符串内容**（name_at 取出的指针）。
fn enum_add_const(ename: i64, cname: i64, val: i64) -> i64 {
    let n: i64 = load64(heap + O_ECNT);
    if n >= 512 { return die("too many enum constants (limit 512)"); }
    store64(heap + O_ENAME + n * 8, intern(ename));
    store64(heap + O_ECNAME + n * 8, intern(cname));
    store64(heap + O_EVAL + n * 8, val);
    store64(heap + O_ECNT, n + 1);
    return 0;
}

fn enum_lookup(ename: i64, cname: i64) -> i64 {
    let i: i64 = 0;
    while i < load64(heap + O_ECNT) {
        # 🔴 `name_at(i)` 是 **"取符号 i 的名字"**（内部查 O_SYN 表），
        #    不是"取 O_NAMES 偏移 i 处的字符串"。
        #    第一版误用了它，于是拿 O_NAMES 偏移当符号索引去 O_SYN 里查，
        #    查出来的是别人的名字 —— enum 永远匹配不上。
        #    这里存的是 intern() 的返回值（O_NAMES 偏移），
        #    所以直接 heap + O_NAMES + off。
        if streq(heap + O_NAMES + load64(heap + O_ENAME + i * 8), ename) == 1 {
            if streq(heap + O_NAMES + load64(heap + O_ECNAME + i * 8), cname) == 1 {
                return i;
            }
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn parse_enum() -> i64 {
    next_token();                       # 跳过 'enum'
    if gv(K_TKIND) != 1 { return syntax_error(); }
    # 🔴 名字必须**拷到独立缓冲区**：tokbuf() 是**共享**的，
    #    next_token() 之后内容就没了。第一版直接把 tokbuf() 的指针
    #    存起来稍后用，于是 intern 到的是 ";" 这种垃圾 ——
    #    更糟的是后来改成 intern 返回的**偏移**再传给 intern，
    #    等于拿数字 5 当地址读，直接段错误。
    let ebuf: i64 = heap + O_SCAL + 5000;
    memcpy(ebuf, tokbuf());
    let cbuf: i64 = heap + O_SCAL + 5400;
    next_token();
    expect("{");
    let auto: i64 = 0;
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(cbuf, tokbuf());
        next_token();
        if accept("=") == 1 {
            if gv(K_TKIND) == 2 {
                auto = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    # const/enum 成员作 enum 显式值（v1.986）
                    let esi: i64 = sym_lookup(tokbuf());
                    if esi >= 0 {
                        if load64(heap + O_SK + esi * 8) == 4 {
                            auto = const_expr();
                        } else {
                            return err_atp("enum value must be an integer literal", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                        }
                    } else {
                        let ee: i64 = enum_value(tokbuf());
                        if ee >= 0 {
                            auto = const_expr();
                        } else {
                            return err_atp("enum value must be an integer literal", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                        }
                    }
                } else {
                    return err_atp("enum value must be an integer literal", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
        }
        enum_add_const(ebuf, cbuf, auto);
        auto = auto + 1;
        if accept(";") == 0 {
            if tok_is("}") == 0 { return err_atp("expected ';' in enum", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        }
    }
    next_token();                       # 跳过 '}'
    store64(heap + O_NENUM, load64(heap + O_NENUM) + 1);
    return 0;
}

fn parse_class() -> i64 {
    next_token();                       # 吃掉 'class'
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(scratch2(), tokbuf());
    next_token();
    if st_lookup(scratch2()) >= 0 {
        return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    let base: i64 = 0 - 1;
    if tok_is(":") == 1 {
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        base = st_lookup(tokbuf());
        if base < 0 { return err_at2("unknown base class", gv(K_LINE), gv(K_COL)); }
        next_token();
    }
    let si: i64 = st_add(scratch2());
    if base >= 0 { inherit_fields(si, base); }
    expect("{");
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(scratch1(), tokbuf());
        next_token();
        expect(":");
        let ft: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                ft = ty_byte();
                next_token();
            } else {
                if tok_is("[") == 1 {
                    # v1.1035: 结构体字段可为数组类型 v: [N] T
                    next_token();
                    let an: i64 = const_expr();
                    expect("]");
                    let et: i64 = ty_int();
                    if tok_is("i64") == 1 {
                        next_token();
                    } else {
                        if tok_is("byte") == 1 {
                            et = ty_byte();
                            next_token();
                        } else {
                            if gv(K_TKIND) == 1 {
                                let sub2: i64 = st_lookup(tokbuf());
                                if sub2 < 0 { return err_at2("unknown type", gv(K_LINE), gv(K_COL)); }
                                et = ty_struct(sub2);
                                next_token();
                            } else {
                                return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                            }
                        }
                    }
                    ft = ty_array(et, an);
                } else {
                if gv(K_TKIND) == 1 {
                    let sub: i64 = st_lookup(tokbuf());
                    if sub >= 0 {
                        ft = ty_struct(sub);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
                }
            }
        }
        st_add_field(si, scratch1(), ft);
        expect(";");
    }
    next_token();
    return 0;
}


# ==========================================================================
#  interface / impl —— 接口与动态分派
#
#  设计：**接口值 = { obj: ptr; vt: ptr }**，就是一个两字段的结构体。
#  于是不需要动类型系统，也不需要 IR —— 现有的结构体、函数指针、
#  方法语法糖（obj.method()）三样东西拼起来就够了。
#
#    interface Shape { fn area(self: ptr) -> i64; }
#    class Rect { w: i64; h: i64; }
#    fn Rect.area(self: ptr) -> i64 { return self.w * self.h; }
#    impl Shape for Rect { area; }
#
#    let s: Shape;
#    s.obj = &r;
#    s.vt = &Shape_Rect_vt;      # 由 impl 自动生成的全局数组
#    print_i64(s.area());        # 间接调用，运行时分派
#
#  vt 里放的是函数地址。数据段必须在**解析结束后**回填 ——
#  impl 出现时函数可能还没定义（前向引用），地址此刻未知。
# ==========================================================================

fn if_lookup(name: i64) -> i64 {
    let i: i64 = 0;
    while i < gv(K_NIF) {
        if streq(load64(heap + O_IFN + i * 8), name) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn if_lookup_si(si: i64) -> i64 {
    let i: i64 = 0;
    while i < gv(K_NIF) {
        if load64(heap + O_IFSI + i * 8) == si { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn if_method_idx(k: i64, mname: i64) -> i64 {
    let n: i64 = load64(heap + O_IFNM + k * 8);
    let i: i64 = 0;
    while i < n {
        if streq(load64(heap + O_IFMN + k * 128 + i * 8), mname) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn parse_interface() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    let nb: i64 = heap + O_IFNB + gv(K_NIF) * 32;
    memcpy(nb, tokbuf());
    next_token();
    let k: i64 = gv(K_NIF);
    if k >= 32 { return err_at2("too many interfaces (limit 32)", gv(K_LINE), gv(K_COL)); }
    if if_lookup(nb) >= 0 { return err_at2("duplicate interface", gv(K_LINE), gv(K_COL)); }
    let si: i64 = st_add(nb);
    st_add_field(si, "obj", ty_int());
    st_add_field(si, "vt", ty_int());
    store64(heap + O_IFN + k * 8, nb);
    store64(heap + O_IFSI + k * 8, si);
    store64(heap + O_IFNM + k * 8, 0);
    sv(K_NIF, k + 1);
    expect("{");
    let mi: i64 = 0;
    while tok_is("}") == 0 {
        if tok_is("fn") == 0 { return syntax_error(); }
        next_token();
        if gv(K_TKIND) != 1 { return syntax_error(); }
        if mi >= 16 { return err_at2("too many interface methods (limit 16)", gv(K_LINE), gv(K_COL)); }
        # 🔴 不能存 intern() 的返回值：那是名字表里的**偏移**（一个数），
        #    不是指针。if_method_idx 里用 streq 比较会把它当地址解引用
        #    → 段错误。这与 1.41.1 那个「ty_int() 是裸 id 不是类型对象」
        #    是同一类错：同一套 API 里混了两种表示。
        let mb: i64 = heap + O_IFMB + k * 512 + mi * 32;
        memcpy(mb, tokbuf());
        store64(heap + O_IFMN + k * 128 + mi * 8, mb);
        mi = mi + 1;
        while tok_is(";") == 0 {
            if gv(K_TKIND) == 0 { return syntax_error(); }
            next_token();
        }
        next_token();
    }
    next_token();
    store64(heap + O_IFNM + k * 8, mi);
    return 0;
}

# 拼接三段字符串：dst = a + b + c
fn scat3(dst: i64, a: i64, b: i64, c: i64) -> i64 {
    let i: i64 = 0;
    while load8(a + i) != 0 { store8(dst + i, load8(a + i)); i = i + 1; }
    let j: i64 = 0;
    while load8(b + j) != 0 { store8(dst + i + j, load8(b + j)); j = j + 1; }
    let p: i64 = i + j;
    let m: i64 = 0;
    while load8(c + m) != 0 { store8(dst + p + m, load8(c + m)); m = m + 1; }
    store8(dst + p + m, 0);
    return p + m;
}

fn parse_impl() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(heap + O_SCAL + 1728, tokbuf());
    next_token();
    if tok_is("for") == 0 { return syntax_error(); }
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(heap + O_SCAL + 1792, tokbuf());
    next_token();
    let k: i64 = if_lookup(heap + O_SCAL + 1728);
    if k < 0 { return err_at2("unknown interface", gv(K_LINE), gv(K_COL)); }
    let nm: i64 = load64(heap + O_IFNM + k * 8);
    # 分配 vtable 全局数组（8 字节对齐 —— 不对齐会让 futex/原子操作直接失败）
    while (gv(K_DLEN) & 7) != 0 { dbyte(0); }
    let voff: i64 = gv(K_DLEN);
    let i: i64 = 0;
    while i < nm { dquad(0); i = i + 1; }
    let vn: i64 = heap + O_SCAL + 1856;
    scat3(vn, load64(heap + O_IFN + k * 8), "_", heap + O_SCAL + 1792);
    scat3(vn, vn, "_vt", "");
    let vs: i64 = sym_add(vn, 2, 268435456 + voff, 0);
    store64(heap + O_STY + vs * 8, ty_array(ty_int(), nm));
    let v: i64 = gv(K_NVT);
    if v >= 32 { return err_at2("too many impls (limit 32)", gv(K_LINE), gv(K_COL)); }
    store64(heap + O_VTD + v * 8, voff);
    store64(heap + O_VTN + v * 8, 0);
    # trait bound 检查要用 (interface, 类型名) → 有没有 impl。
    # 🔴 类型名必须拷进 O_VTTB 自己的缓冲，不能留 O_SCAL + 1792 ——
    #    那是共享临时区，下一次解析就把它冲掉了。
    memcpy(heap + O_VTTB + v * 32, heap + O_SCAL + 1792);
    store64(heap + O_VTT + v * 8, heap + O_VTTB + v * 32);
    store64(heap + O_VTK + v * 8, k);
    sv(K_NVT, v + 1);
    expect("{");
    let cnt: i64 = 0;
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        let mn: i64 = heap + O_SCAL + 1920;
        memcpy(mn, tokbuf());
        next_token();
        let midx: i64 = if_method_idx(k, mn);
        if midx < 0 { return err_at2("not an interface method", gv(K_LINE), gv(K_COL)); }
        # Type_method —— 与现有的「类方法」命名一致，所以直接复用
        let fnm: i64 = heap + O_SCAL + 1984;
        scat3(fnm, heap + O_SCAL + 1792, "_", mn);
        let fs: i64 = sym_lookup_func(fnm);
        if fs < 0 { return err_at2("no such method (define it before impl)", gv(K_LINE), gv(K_COL)); }
        store64(heap + O_VTS + v * 128 + midx * 8, fs);
        cnt = cnt + 1;
        expect(";");
    }
    next_token();
    store64(heap + O_VTN + v * 8, cnt);
    return 0;
}

# 解析结束后回填 vtable：此刻所有函数地址都已确定
fn iface_patch_vtables() -> i64 {
    let v: i64 = 0;
    while v < gv(K_NVT) {
        let voff: i64 = load64(heap + O_VTD + v * 8);
        let n: i64 = load64(heap + O_VTN + v * 8);
        let k: i64 = 0;
        while k < n {
            let fs: i64 = load64(heap + O_VTS + v * 128 + k * 8);
            store64(heap + O_DATA + voff + k * 8, load64(heap + O_SA + fs * 8));
            k = k + 1;
        }
        v = v + 1;
    }
    return 0;
}

# ---- trait bound：解析结束后统一检查 ----
#
#  泛型本来是**结构化**匹配的：只要类型碰巧有个同名方法就能过。Sneaky 从没
#  `impl Shape`，但只要定义了 `Sneaky_area`，`instantiate areag(Sneaky)`
#  照样编译通过并运行 —— 实测确实如此。这就是 trait bound 要补的：
#  契约是**名义**的，必须显式 impl 才算实现了接口。
#  另一个理由：impl 保证实现接口的**全部**方法，而泛型体可能只用其中一个；
#  结构化匹配只保证"碰巧有这一个"，不保证契约完整。

fn gen_has_impl(iface: i64, tname: i64) -> i64 {
    let v: i64 = 0;
    while v < gv(K_NVT) {
        if load64(heap + O_VTK + v * 8) == iface {
            if streq(load64(heap + O_VTT + v * 8), tname) == 1 { return 1; }
        }
        v = v + 1;
    }
    return 0;
}

fn gen_check_bounds() -> i64 {
    let i: i64 = 0;
    while i < gv(K_NB) {
        let kif: i64 = load64(heap + O_BCI + i * 8);
        let tn: i64 = load64(heap + O_BCT + i * 8);
        if gen_has_impl(kif, tn) == 0 {
            let msg: i64 = heap + O_BMSG;
            scat3(msg, tn, " does not implement ", load64(heap + O_IFN + kif * 8));
            err_at2(msg, load64(heap + O_BCL + i * 8), load64(heap + O_BCC + i * 8));
            sv(K_NBER, gv(K_NBER) + 1);
        }
        i = i + 1;
    }
    return 0;
}

fn parse_struct() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(scratch2(), tokbuf());
    next_token();
    # v1.1110: 前向引用 —— 签名里已预注册的 struct 直接复用（字段槽必须为空）
    let si: i64 = st_lookup(scratch2());
    if si < 0 { si = st_add(scratch2()); }
    else {
        if load64(heap + O_STF + si * 8) != 0 { return err_atp("duplicate struct definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
    }
    expect("{");
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        memcpy(scratch1(), tokbuf());
        next_token();
        expect(":");
        let ft: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                # 字段类型此前只支持 i64 与结构体 —— 对标 C 的 struct，
                # char 字段是最基本的需要。代码生成层（g_load_at_b /
                # g_store_at_b）早就支持，只差解析这里没接上。
                ft = ty_byte();
                next_token();
            } else {
                if tok_is("[") == 1 {
                    # v1.1035: 结构体字段可为数组类型 v: [N] T
                    next_token();
                    let an: i64 = const_expr();
expect("]");
                    let et: i64 = ty_int();
                    if tok_is("i64") == 1 {
                        next_token();
                    } else {
                        if tok_is("byte") == 1 {
                            et = ty_byte();
                            next_token();
                        } else {
                            if gv(K_TKIND) == 1 {
                                let sub2: i64 = st_lookup(tokbuf());
                                if sub2 < 0 { return err_at2("unknown type", gv(K_LINE), gv(K_COL)); }
                                et = ty_struct(sub2);
                                next_token();
                            } else {
                                return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                            }
                        }
                    }
                    ft = ty_array(et, an);
                } else {
                if tok_is("ptr") == 1 {
                    # v1.1094: 字段可为指针类型（含 struct 自引用链表）——
                    # Node 在 st_add 时已登记，自引用 ptr Node 可解析。
                    next_token();
                    ft = ty_ptr(parse_ptr_target());
                } else {
                if gv(K_TKIND) == 1 {
                    let sub: i64 = st_lookup(tokbuf());
                    if sub >= 0 {
                        ft = ty_struct(sub);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
                }
                }
            }
        }
        # byte 字段也按 8 字节对齐存放（与 C 的默认对齐结果一致：
        # struct { char x; long y; } 在 C 里同样是 16 字节）。
        # 于是 ty_size 的 8*nfields 依然成立。
        st_add_field(si, scratch1(), ft);
        # v1.1060: 字段默认值 struct P { x: i64 = 10; }
        if accept("=") == 1 {
            SDV[si * 64 + st_nfields(si) - 1] = const_expr();
            SDH[si * 64 + st_nfields(si) - 1] = 1;
        }
        expect(";");
    }
    next_token();
    return 0;
}

# 数据段头布局：argc/argv(16) + 参数暂存区(32×8=256) = 272 字节
#
# ⚠️ 改这里的数量必须**同步改 `src/asm/main.s`**！
# seed 是手写汇编，同样一段逻辑写死在那里。两边不一致时，
# 生成的代码里全局变量地址不同，自举立即失败（详见 log 第八节）。
fn reserve_arg_slots() -> i64 {
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    dquad(0);
    return 0;
}

fn parse_program() -> i64 {
    predeclare();
    # v1.1089: 数据段头预留 256B 返回暂存区（全零，不与全局冲突）
    data_align(16);
    RETB = 268435456 + gv(K_DLEN);
    let rbi: i64 = 0;
    while rbi < 32 { dquad(0); rbi = rbi + 1; }
    next_token();
    while gv(K_TKIND) != 0 {
        if ERR_DUP > 3 { break; }   # 恢复卡死：停止解析，走完编译流程报错退出
        if tok_is("import") == 1 {
            parse_import();
        } else {
            if tok_is("struct") == 1 {
                parse_struct();
            } else {
                if tok_is("enum") == 1 {
                    parse_enum();
                } else {
                    if tok_is("interface") == 1 {
                        parse_interface();
                    } else {
                        if tok_is("impl") == 1 {
                            parse_impl();
                        } else {
                            if tok_is("class") == 1 {
                                parse_class();
                            } else {
                                if tok_is("generic") == 1 {
                                    parse_generic();
                                } else {
                                    if tok_is("component") == 1 {
                                        parse_component();
                                    } else {
                                    if tok_is("instantiate") == 1 {
                                        parse_instantiate();
                                    } else {
                                if tok_is("extern") == 1 {
                                    parse_extern();
                                } else {
                                    if tok_is("var") == 1 || tok_is("let") == 1 {
                                        parse_global();
                                    } else {
                                    if tok_is("const") == 1 {
                                        parse_const();
                                    } else {
                                            if tok_is("fn") == 1 {
                                                parse_func();
                                            } else {
                                                syntax_error();
                                                while gv(K_TKIND) != 0 {
                                                    if tok_is("fn") == 1 || tok_is("var") == 1 || tok_is("import") == 1 || tok_is("struct") == 1 || tok_is("enum") == 1 || tok_is("class") == 1 || tok_is("component") == 1 || tok_is("generic") == 1 || tok_is("impl") == 1 || tok_is("interface") == 1 || tok_is("extern") == 1 || tok_is("instantiate") == 1 {
                                                        break;
                                                    }
                                                    next_token();
                                                }
                                            }
                                            }
                                        }
                                    }
                                    }
                                }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

# ==========================================================================
#  generic / instantiate —— 泛型函数与单态化
#
#  不用 IR、不用改类型系统。做法朴素但完整：把函数体**源码文本**存下来，
#  instantiate 时把类型参数名替换成实际类型，重新解析一遍。
#
#    generic fn maxg<T>(a: T, b: T) -> T {
#        if a > b { return a; }
#        return b;
#    }
#    instantiate maxg(i64) as maxg_i64;
#    instantiate maxg(f64) as maxg_f64;
#
#  之所以可行：`sbyte()` 用的是 `heap + K_SRCBASE + i`，**源码基址可切换**。
#  于是展开出的文本写进临时区，切过去解析，再切回来即可。
# ==========================================================================

# 从 start 扫到函数体匹配的 '}' 之后（跳过字符串与 # 注释）
fn gen_scan_end(start: i64) -> i64 {
    let sb: i64 = gv(K_SRCBASE);
    let n: i64 = gv(K_SRCLEN);
    let i: i64 = start;
    let depth: i64 = 0;
    while i < n {
        let c: i64 = load8(heap + sb + i);
        if c == 35 {
            while i < n {
                if load8(heap + sb + i) == 10 { break; }
                i = i + 1;
            }
        } else {
            if c == 34 {
                i = i + 1;
                while i < n {
                    let d: i64 = load8(heap + sb + i);
                    if d == 92 { i = i + 2; }
                    else {
                        if d == 34 { break; }
                        i = i + 1;
                    }
                }
            } else {
                if c == 123 { depth = depth + 1; }
                if c == 125 {
                    depth = depth - 1;
                    if depth == 0 { return i + 1; }
                }
            }
        }
        i = i + 1;
    }
    return n;
}

fn gen_lookup(name: i64) -> i64 {
    let i: i64 = 0;
    while i < gv(K_NG) {
        if streq(load64(heap + O_GN + i * 8), name) == 1 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

# 标识符 src[0..len) 是否等于 tname（要求等长）
fn gen_ident_is(src: i64, len: i64, tname: i64) -> i64 {
    let k: i64 = 0;
    while k < len {
        if load8(src + k) != load8(tname + k) { return 0; }
        k = k + 1;
    }
    if load8(tname + len) != 0 { return 0; }
    return 1;
}

# 展开：dst = "fn " + newname + body(T→实参)
fn gen_expand(g: i64, newname: i64) -> i64 {
    let dst: i64 = heap + O_GENBUF;
    store8(dst, 102);
    store8(dst + 1, 110);
    store8(dst + 2, 32);
    let d: i64 = 3;
    let j: i64 = 0;
    while load8(newname + j) != 0 {
        store8(dst + d, load8(newname + j));
        d = d + 1;
        j = j + 1;
    }
    let src: i64 = heap + O_GBODY + g * 8192;
    let nt: i64 = load64(heap + O_GNT + g * 8);
    let i: i64 = 0;
    while load8(src + i) != 0 {
        let c: i64 = load8(src + i);
        if is_alpha(c) == 1 {
            let k: i64 = 0;
            while is_alnum(load8(src + i + k)) == 1 { k = k + 1; }
            let t: i64 = 0 - 1;
            let m: i64 = 0;
            while m < nt {
                if gen_ident_is(src + i, k, load64(heap + O_GTP + g * 128 + m * 8)) == 1 { t = m; }
                m = m + 1;
            }
            if t >= 0 {
                let an: i64 = heap + O_GAB + t * 32;
                let q: i64 = 0;
                while load8(an + q) != 0 {
                    store8(dst + d, load8(an + q));
                    d = d + 1;
                    q = q + 1;
                }
            } else {
                let q2: i64 = 0;
                while q2 < k {
                    store8(dst + d, load8(src + i + q2));
                    d = d + 1;
                    q2 = q2 + 1;
                }
            }
            i = i + k;
        } else {
            store8(dst + d, c);
            d = d + 1;
            i = i + 1;
        }
    }
    store8(dst + d, 0);
    return d;
}

fn parse_generic() -> i64 {
    next_token();
    if tok_is("fn") == 0 { return syntax_error(); }
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    let g: i64 = gv(K_NG);
    if g >= 32 { return err_at2("too many generic functions (limit 32)", gv(K_LINE), gv(K_COL)); }
    let nb: i64 = heap + O_GNB + g * 32;
    memcpy(nb, tokbuf());
    store64(heap + O_GN + g * 8, nb);
    next_token();
    if tok_is("<") == 0 { return syntax_error(); }
    next_token();
    let nt: i64 = 0;
    while tok_is(">") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        if nt >= 4 { return err_at2("too many type parameters (limit 4)", gv(K_LINE), gv(K_COL)); }
        let tb: i64 = heap + O_GTB + g * 128 + nt * 32;
        memcpy(tb, tokbuf());
        store64(heap + O_GTP + g * 128 + nt * 8, tb);
        next_token();
        # ---- trait bound：<T: Shape> / <T: Shape + Ord> / <T: Shape, U> ----
        # 🔴 读完名字必须**立刻推进**才能看到 ':'（accept(",") 失败时 token
        #    还是刚才那个名字，紧接着的 tok_is(">") 会拿名字去比 '>' →
        #    syntax error，而且位置正指向类型参数名那一列，极易误导）。
        #    推进只能有**一次** —— 多推进一次就会把 '>' 跳过去，
        #    症状是在函数体的 '(' 上报 syntax error。
        let nbnd: i64 = 0;
        if tok_is(":") == 1 {
            next_token();
            let more: i64 = 1;
            while more == 1 {
                more = 0;
                if gv(K_TKIND) != 1 { return syntax_error(); }
                let kb: i64 = if_lookup(tokbuf());
                if kb < 0 { return err_at2("unknown interface in bound", gv(K_LINE), gv(K_COL)); }
                if nbnd >= 4 { return err_at2("too many bounds (limit 4)", gv(K_LINE), gv(K_COL)); }
                store64(heap + O_GBB + g * 512 + nt * 128 + nbnd * 8, kb);
                nbnd = nbnd + 1;
                next_token();
                if tok_is("+") == 1 { next_token(); more = 1; }
            }
        }
        store64(heap + O_GBC + g * 128 + nt * 8, nbnd);
        nt = nt + 1;
        if accept(",") == 0 { break; }
    }
    if tok_is(">") == 0 { return syntax_error(); }
    next_token();
    if tok_is("(") == 0 { return syntax_error(); }
    let pp: i64 = gv(K_TOKPOS);
    let pe: i64 = gen_scan_end(pp);
    let dst: i64 = heap + O_GBODY + g * 8192;
    let i: i64 = 0;
    while pp + i < pe {
        if i >= 8180 { return err_at2("generic body too long (limit 8180 bytes)", gv(K_LINE), gv(K_COL)); }
        store8(dst + i, load8(heap + gv(K_SRCBASE) + pp + i));
        i = i + 1;
    }
    store8(dst + i, 0);
    store64(heap + O_GNT + g * 8, nt);
    sv(K_NG, g + 1);
    # 🔴 必须用 advance_lc 而不是自己逐字节推进：advance_lc 会同步 K_CPOS。
    #    自己写的版本只更新 K_LINE/K_COL/K_POS，K_CPOS 留在旧值，
    #    下一次 next_token 里的 advance_lc 就从旧位置**再算一遍**，
    #    行号被翻倍累加 —— 实测 11 行的文件报"第 9 行"，
    #    而且列号也全错，把人完全带偏。
    # 🔴 advance_lc 只推进行号游标，**不动 K_POS**。
    #    少了这一句，next_token 仍从 '(' 附近读，把形参列表当成下一条语句。
    sv(K_POS, pe);
    advance_lc(pe);
    next_token();
    return 0;
}

fn parse_instantiate() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(heap + O_SCAL + 2048, tokbuf());
    next_token();
    let g: i64 = gen_lookup(heap + O_SCAL + 2048);
    if g < 0 { return err_at2("unknown generic function", gv(K_LINE), gv(K_COL)); }
    if tok_is("(") == 0 { return syntax_error(); }
    next_token();
    let na: i64 = 0;
    while tok_is(")") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        if na >= 4 { return err_at2("too many type arguments (limit 4)", gv(K_LINE), gv(K_COL)); }
        memcpy(heap + O_GAB + na * 32, tokbuf());
        na = na + 1;
        next_token();
        if accept(",") == 0 { break; }
    }
    if tok_is(")") == 0 { return syntax_error(); }
    next_token();
    if na != load64(heap + O_GNT + g * 8) {
        return err_at2("wrong number of type arguments", gv(K_LINE), gv(K_COL));
    }
    # ---- 登记 trait bound 待检查项 ----
    # 🔴 不能在这里**立即**检查：impl 可能出现在 instantiate 之后，
    #    此刻 vtable 表还没填完，会误报。推迟到全部解析结束后统一查。
    let ti: i64 = 0;
    while ti < na {
        let nb: i64 = load64(heap + O_GBC + g * 128 + ti * 8);
        let bi: i64 = 0;
        while bi < nb {
            let n: i64 = gv(K_NB);
            if n >= 64 { return err_at2("too many bound checks (limit 64)", gv(K_LINE), gv(K_COL)); }
            store64(heap + O_BCI + n * 8, load64(heap + O_GBB + g * 512 + ti * 128 + bi * 8));
            store64(heap + O_BCL + n * 8, gv(K_LINE));
            store64(heap + O_BCC + n * 8, gv(K_COL));
            # 🔴 类型名必须拷出来：O_GAB 是共享区，下一次 instantiate 就覆盖。
            memcpy(heap + O_BCTB + n * 32, heap + O_GAB + ti * 32);
            store64(heap + O_BCT + n * 8, heap + O_BCTB + n * 32);
            sv(K_NB, n + 1);
            bi = bi + 1;
        }
        ti = ti + 1;
    }
    if tok_is("as") == 0 { return syntax_error(); }
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    memcpy(heap + O_SCAL + 2112, tokbuf());
    next_token();
    # 🔴 整条语句必须先读完再切走：切换源码基址后，原来的位置就找不回了。
    #
    # 🔴 位置必须在 expect(";") **之前**取。expect 内部会 next_token，
    #    而 next_token 结束后 K_POS 指向**新读到的那个 token 的末尾** ——
    #    也就是 'fn' 的末尾。拿它当恢复点，切回来就会从 'fn' 之后继续，
    #    把 'fn' 整个丢掉（实测恢复后读到的 token 是 'main'）。
    if tok_is(";") == 0 { return syntax_error(); }
    let ob: i64 = gv(K_SRCBASE);
    let ol: i64 = gv(K_SRCLEN);
    let op: i64 = gv(K_POS);
    let oln: i64 = gv(K_LINE);
    let oc: i64 = gv(K_COL);
    next_token();
    sv(K_NGA, na);
    # 🔴 必须**先把新函数名登记进符号表**，再切过去解析。
    #    parse_func 结束时会把符号表回滚到函数开始处（清局部变量）。
    #    正常函数靠 predeclare() 预先登记在基线之前（源码里扫 `fn`），
    #    而展开出的函数不在源码里，predeclare 扫不到 —— 于是 sym_add
    #    刚加进去就被回滚掉了，调用点报 syntax error 而不是"未定义"。
    sym_add(heap + O_SCAL + 2112, 0, 0, 0);
    let len: i64 = gen_expand(g, heap + O_SCAL + 2112);
    sv(K_SRCBASE, O_GENBUF);
    sv(K_SRCLEN, len);
    set_pos(0);
    parse_func();
    sv(K_SRCBASE, ob);
    sv(K_SRCLEN, ol);
    sv(K_POS, op);
    sv(K_LINE, oln);
    sv(K_COL, oc);
    sv(K_CPOS, op);
    next_token();
    return 0;
}

# ==========================================================================
#  回填
# ==========================================================================
fn resolve_all() -> i64 {
    let i: i64 = 0;
    while i < gv(K_NFNP) {
        let p: i64 = load64(heap + O_FP + i * 8);
        let a: i64 = sym_addr(load64(heap + O_FS + i * 8));
        # patch 类型靠占位处的第一个字节判断（见 emit_call_patch 注释）：
        #   0xe8 → call rel32：写 4 字节相对偏移
        #   0x48 → movabs rax,imm64：写 8 字节绝对地址（旧路径，已不再产生）
        if load8(heap + O_CODE + p - 1) == 232 {
            # p 是 rel32 **字段**的偏移（见 emit_call_patch 的 -c 分支）：
            # call 指令在 p-1，长 5 字节 → 下一条指令在 p+4。
            let r: i64 = a - (4194304 + 176 + p + 4);
            let j: i64 = 0;
            while j < 4 {
                store8(heap + O_CODE + p + j, (r >> (j * 8)) & 255);
                j = j + 1;
            }
        } else {
            let j: i64 = 0;
            while j < 8 {
                store8(heap + O_CODE + p + j, (a >> (j * 8)) & 255);
                j = j + 1;
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < gv(K_NJMP) {
        let p: i64 = load64(heap + O_JP + i * 8);
        let t: i64 = load64(heap + O_LB + load64(heap + O_JL + i * 8) * 8);
        let r: i64 = t - p - 4;
        store8(heap + O_CODE + p, r & 255);
        store8(heap + O_CODE + p + 1, (r >> 8) & 255);
        store8(heap + O_CODE + p + 2, (r >> 16) & 255);
        store8(heap + O_CODE + p + 3, (r >> 24) & 255);
        i = i + 1;
    }
    return 0;
}

# ==========================================================================
#  ELF64 输出
# ==========================================================================
var O_ELF:   i64 = 7471104;
var O_ZERO:  i64 = 7471280;
var MAINPAT: i64 = 0;

fn zero_elf() -> i64 {
    let i: i64 = 0;
    while i < 176 {
        store8(heap + O_ELF + i, 0);
        i = i + 1;
    }
    return 0;
}

# 启动：先把 argc / argv 存进数据段头 16 字节，再调 main
#   入口时 rsp -> argc, rsp+8 -> argv[0] 指针
#   数据段虚拟地址 0x10000000 起：+0 存 argc，+8 存 argv 指针
# 取（必要时创建）一个 extern 符号，用于编译器自己生成的调用。
fn extern_intern(nm: i64) -> i64 {
    let i: i64 = sym_lookup_func(nm);
    if i >= 0 { return i; }
    let id: i64 = sym_add(nm, 3, 0, 1);
    store64(heap + O_SRT + id * 8, ty_int());
    return id;
}

fn emit_startup() -> i64 {
    # mov rax, [rsp]              ; argc
    ops3(0x48, 0x8b, 0x04);
    emit1(0x24);
    # mov r11, 0x10000000
    ops2(0x49, 0xbb);
    emit8(268435456);
    # mov [r11], rax
    ops3(0x49, 0x89, 0x03);
    # lea rcx, [rsp+8]
    ops3(0x48, 0x8d, 0x4c);
    ops2(0x24, 0x08);
    # mov [r11+8], rcx
    ops3(0x49, 0x89, 0x4b);
    emit1(8);
    # -c 模式：同样必须用 rel32（理由见 emit_call_patch 的 -c 分支）。
    # 这里嵌的是 main 的**绝对**地址，.text 被 ld 搬走后就跳进垃圾里。
    if gv(K_OBJ) == 1 {
        # 🔴 不能在这里 sym_lookup_func("main")：
        #    emit_startup 在 parse_program **之前**跑，此刻 main 还没登记，
        #    查到 -1，于是 rel32 填成 0 —— call 跳到下一条指令，
        #    main 永远不执行，程序直接跑到 exit。
        #    改成记下位置，等 main 定义之后再手工回填。
        spill_cache();
        emit1(0xe8);
        MAINPAT = gv(K_CLEN);
        emit4(0);
        ops3(0x48, 0x89, 0xc7);
        # 🔴 退出必须走 libc 的 exit()，不能用 `mov $60; syscall`。
        #    printf 的输出在 stdio 缓冲区里，raw exit_group 直接终止进程、
        #    从不 flush —— 表现为 printf 静默无输出（且不报错）。
        #    实测加了 fflush(0) 就有输出，换成 exit() 后也不再需要手写 flush。
        #    -nostdlib 时由 tools/mocrt.s 提供一个 syscall 版 exit。
        emit_call_extern(extern_intern("exit"));
        return 0;
    }
    ops2(0x48, 0xb8);
    MAINPAT = gv(K_CLEN);
    emit8(0);
    # 调用前必须先落栈：被调函数里的 push 会 spill 调用者缓存在 rbx 里的值，
    # 把它压进被调函数的栈帧，调用者返回后取回的就是错的
    spill_cache();
    ops2(0xff, 0xd0);
    ops3(0x48, 0x89, 0xc7);
    ops3(0x48, 0xc7, 0xc0);
    emit4(60);
    ops2(0x0f, 0x05);
    return 0;
}

fn build_elf(entry: i64) -> i64 {
    zero_elf();
    let e: i64 = heap + O_ELF;
    store8(e, 0x7f);
    store8(e + 1, 0x45);
    store8(e + 2, 0x4c);
    store8(e + 3, 0x46);
    store8(e + 4, 2);
    store8(e + 5, 1);
    store8(e + 6, 1);
    store8(e + 16, 2);
    store8(e + 18, 0x3e);
    store8(e + 20, 1);
    store64(e + 24, entry);
    store64(e + 32, 64);
    store8(e + 52, 64);
    store8(e + 54, 56);
    store8(e + 56, 2);
    let sz: i64 = (gv(K_CLEN) + 176 + 4095) & -4096;
    let p1: i64 = e + 64;
    store8(p1, 1);
    store8(p1 + 4, 5);
    store64(p1 + 8, 0);
    store64(p1 + 16, 4194304);
    store64(p1 + 24, 4194304);
    store64(p1 + 32, sz);
    store64(p1 + 40, sz);
    store64(p1 + 48, 4096);
    let p2: i64 = e + 120;
    store8(p2, 1);
    store8(p2 + 4, 6);
    store64(p2 + 8, sz);
    store64(p2 + 16, 268435456);
    store64(p2 + 24, 268435456);
    store64(p2 + 32, gv(K_DLEN));
    store64(p2 + 40, gv(K_DLEN));
    store64(p2 + 48, 4096);
    return 0;
}

fn write_all(fd: i64, p: i64, n: i64) -> i64 {
    syscall(1, fd, p, n, 0, 0, 0);
    return 0;
}

# ==========================================================================
#  main
# ==========================================================================
var OUTPATH: i64 = 0;

# ============ DWARF 生成（-g）============
# 只生成最小可用集：.debug_info（一个 CU DIE）+ .debug_abbrev + .debug_line。
# 够 gdb 做到「按源码行下断点、看行号」，不含变量、类型、栈帧信息。

# SLEB128 的字节数。必须与 db_sleb **用同样的除法**（`v / 128`，
# 墨语言对负数向零截断），否则算出的长度和实际写入的字节数不一致，
# exprloc 的长度字段就错了 —— 表现为 readelf 读出一个错位的表达式。
fn db_sleb_len(v0: i64) -> i64 {
    let v: i64 = v0;
    let n: i64 = 0;
    while 1 {
        let b: i64 = v & 127;
        # 与 db_sleb 保持一致：算术右移（向下取整），不是向零截断
        let q: i64 = v / 128;
        if v < 0 {
            if q * 128 != v { q = q - 1; }
        }
        v = q;
        if v == 0 {
            if (b & 64) == 0 { return n + 1; }
        } else {
            if v == 0 - 1 {
                if (b & 64) != 0 { return n + 1; }
            }
        }
        n = n + 1;
    }
    return n;
}

# 取一个已 intern 名字的字符串指针（intern 返回的是相对 O_NAMES 的偏移）
fn dname(off: i64) -> i64 { return heap + O_NAMES + off; }

# ---------- 类型 DIE ----------
# 类型 DIE 必须在引用它的变量 DIE **之前**生成，
# 所以走两遍：dbg_ty_prepass 先把所有用到的类型都生成好，
# 之后变量 DIE 只需 dbg_ty_ref 查偏移。

# 基础类型：裸 id 0=int 1=void 2=byte，id >= 3 都是 ty_new 出来的对象。
#
# 🔴 不能写 `if t >= 100` 来判断"是不是类型对象"。
#    ty_new 的 id 从 **2** 开始顺序分配，f64/bool/ptr 拿到的 id
#    只有个位数 —— 于是它们全被当成裸 id、映射到 i64，
#    表现为所有浮点/布尔/指针变量的 DW_AT_type 都指向同一个类型。
#    readelf 看起来"每个变量都有类型"，只是**类型全是错的**。
fn dbg_ty_isbasic(t: i64) -> i64 {
    if t == 0 { return 1; }
    if t == 1 { return 1; }
    if t == 2 { return 1; }
    let k: i64 = ty_kind(t);
    if k == 0 { return 1; }
    if k == 1 { return 1; }
    if k == 6 { return 1; }
    if k == 7 { return 1; }
    return 0;
}

fn dbg_ty_basic_off(t: i64) -> i64 {
    if t == 2 { return gv(K_TYBYTE); }
    let k: i64 = ty_kind(t);
    if k == 6 { return gv(K_TYF64); }
    if k == 7 { return gv(K_TYBOOL); }
    return gv(K_TYI64);
}

# 查表：已生成过就返回偏移，否则 0
fn dbg_ty_find(t: i64) -> i64 {
    let n: i64 = gv(K_NDTY);
    let i: i64 = 0;
    while i < n {
        if load64(DBG + O_DTY + i * 16) == t {
            return load64(DBG + O_DTY + i * 16 + 8);
        }
        i = i + 1;
    }
    return 0;
}

fn dbg_ty_note(t: i64, off: i64) -> i64 {
    let n: i64 = gv(K_NDTY);
    if n >= 1024 { return 0; }
    store64(DBG + O_DTY + n * 16, t);
    store64(DBG + O_DTY + n * 16 + 8, off);
    sv(K_NDTY, n + 1);
    return 0;
}

# 生成（必要时）并返回该类型的 DIE 偏移。
# 🔴 必须先 dbg_ty_note 再写子 DIE —— 自引用类型
#    （struct Node { next: ptr } 指向自己）会在递归时再次查到本条，
#    若先写子 DIE 就会无限递归。
fn dbg_ty_emit(t: i64) -> i64 {
    if dbg_ty_isbasic(t) == 1 { return dbg_ty_basic_off(t); }
    let ex: i64 = dbg_ty_find(t);
    if ex != 0 { return ex; }
    let off: i64 = gv(K_DBGLEN);
    dbg_ty_note(t, off);
    let k: i64 = ty_kind(t);
    if k == 4 {
        # pointer_type
        db_uleb(9);
        db_u8(8);
        let rp: i64 = gv(K_DBGLEN);
        db_u32(0);
        let et: i64 = dbg_ty_emit(ty_a(t));
        db_u32_at(rp, et);
        return off;
    }
    if k == 3 {
        # array_type + subrange_type(count)
        db_uleb(7);
        let ap: i64 = gv(K_DBGLEN);
        db_u32(0);
        db_uleb(8);
        db_u32(ty_b(t));
        db_uleb(0);
        let el: i64 = dbg_ty_emit(ty_a(t));
        db_u32_at(ap, el);
        return off;
    }
    if k == 2 {
        # structure_type + 各 member
        let si: i64 = ty_a(t);
        db_uleb(5);
        db_str(st_name(si));
        db_u8(ty_size(t));
        let nf: i64 = st_nfields(si);
        let fi: i64 = 0;
        let pos: i64 = 0;
        while fi < nf {
            let ft: i64 = st_field_type(si, fi);
            db_uleb(6);
            db_str(st_field_name(si, fi));
            let mp: i64 = gv(K_DBGLEN);
            db_u32(0);
            db_u8(pos);
            let fo: i64 = dbg_ty_emit(ft);
            db_u32_at(mp, fo);
            # 🔴 字段在结构体里一律占**一个 8 字节槽**，byte/bool 也不例外。
            #    按 ty_size 累加（byte 是 1）会让后面所有成员的偏移都偏小：
            #    bv@16 之后 in 被算成 @17，实际在 @24 —— 调试器读出来是
            #    下一个槽的高位字节，表现为 360287970189639680 这种怪值。
            if ty_kind(ft) == 2 { pos = pos + ty_size(ft); }
            if ty_kind(ft) != 2 { pos = pos + 8; }
            fi = fi + 1;
        }
        db_uleb(0);
        return off;
    }
    return gv(K_TYI64);
}

# 第一遍：把所有变量用到的类型都生成出来
fn dbg_ty_prepass() -> i64 {
    let n: i64 = gv(K_NDV);
    let i: i64 = 0;
    while i < n {
        dbg_ty_emit(load64(DBG + O_DV + i * 40 + 32));
        i = i + 1;
    }
    return 0;
}

fn gen_info() -> i64 {
    sv(K_DBBASE, 0);
    sv(K_DBGLEN, 0);
    db_u32(0);                 # unit_length（稍后回填）
    db_u16(4);                 # version 4
    db_u32(0);                 # debug_abbrev_offset
    db_u8(8);                  # address_size
    db_uleb(1);                # abbrev code
    db_str(INPATH);            # DW_AT_name
    let cl0: i64 = gv(K_CLEN);
    db_u64(4194480);           # DW_AT_low_pc  = 代码段起始虚址
    db_u64(4194480 + cl0);     # DW_AT_high_pc
    db_u32(0);                 # DW_AT_stmt_list（.debug_line 内偏移 0）
    db_str("mo compiler");     # DW_AT_producer
    db_u16(12);                # DW_AT_language = DW_LANG_C89

    # ---- 内置类型 i64（变量的 DW_AT_type 指向这里）----
    # 记下它在 .debug_info 里的偏移，供 ref4 引用。
    sv(K_TYI64, gv(K_DBGLEN));
    db_uleb(2);
    db_str("i64");
    db_u8(5);                  # DW_ATE_signed
    db_u8(8);                  # byte_size

    # ---- 其余基础类型 ----
    sv(K_TYBYTE, gv(K_DBGLEN));
    db_uleb(2); db_str("byte"); db_u8(6); db_u8(1);   # DW_ATE_unsigned_char
    sv(K_TYF64, gv(K_DBGLEN));
    db_uleb(2); db_str("f64"); db_u8(4); db_u8(8);    # DW_ATE_float
    sv(K_TYBOOL, gv(K_DBGLEN));
    db_uleb(2); db_str("bool"); db_u8(6); db_u8(1);
    sv(K_TYPTR, gv(K_DBGLEN));
    db_uleb(10); db_u8(8);                            # pointer_type（void*）

    # ---- 变量用到的复合类型（结构体 / 数组 / 指针）----
    dbg_ty_prepass();

    # ---- 全局变量（CU 的直接子 DIE，location 是绝对地址）----
    let nv0: i64 = gv(K_NDV);
    let vi0: i64 = 0;
    while vi0 < nv0 {
        let vp: i64 = DBG + O_DV + vi0 * 40;
        if load64(vp + 24) == 0 - 1 {
            db_uleb(4);                     # DW_TAG_variable
            db_str(dname(load64(vp)));
            # DW_AT_location = DW_OP_addr + addr8
            db_uleb(9);
            db_u8(3);                       # DW_OP_addr
            db_u64(load64(vp + 8));
            db_u16(load64(vp + 16));
            db_u32(dbg_ty_emit(load64(vp + 32)));
        }
        vi0 = vi0 + 1;
    }

    # ---- 各函数及其局部变量 ----
    let nf: i64 = gv(K_NDF);
    let fi: i64 = 0;
    while fi < nf {
        let fp: i64 = DBG + O_DF + fi * 40;
        db_uleb(3);                        # DW_TAG_subprogram
        db_str(dname(load64(fp)));
        db_u64(load64(fp + 8));            # low_pc
        db_u64(load64(fp + 16));           # high_pc
        # DW_AT_frame_base = DW_OP_breg6(rbp) + 0
        # 于是变量的 fbreg 偏移就是反汇编里看到的 [rbp+off]，不用换算 CFA。
        db_uleb(2);
        db_u8(118);                        # DW_OP_breg6
        db_sleb(0);
        db_u16(load64(fp + 24));           # decl_line
        # DW_AT_decl_file：file_names 表里的编号（**从 1 起**）。
        # 少这一条，库里的函数会被当成主文件的，gdb 把断点下错文件。
        db_u8(load64(fp + 32) + 1);
        # 该函数的局部变量
        let nv: i64 = gv(K_NDV);
        let vi: i64 = 0;
        while vi < nv {
            let vp: i64 = DBG + O_DV + vi * 40;
            if load64(vp + 24) == fi {
                let voff: i64 = load64(vp + 8);
                db_uleb(4);                        # DW_TAG_variable
                db_str(dname(load64(vp)));
                # DW_AT_location = DW_OP_fbreg + sleb(off)
                db_uleb(1 + db_sleb_len(voff));
                db_u8(145);                        # DW_OP_fbreg
                db_sleb(voff);
                db_u16(load64(vp + 16));           # decl_line
                db_u32(dbg_ty_emit(load64(vp + 32)));   # DW_AT_type
            }
            vi = vi + 1;
        }
        db_uleb(0);                        # 子 DIE 结束
        fi = fi + 1;
    }
    db_uleb(0);                            # CU 子 DIE 结束

    let il: i64 = gv(K_DBGLEN);
    db_poke32(0, il - 4);
    sv(K_INFOLEN, il);
    return 0;
}

fn gen_abbrev() -> i64 {
    sv(K_DBBASE, 262144);
    sv(K_DBGLEN, 0);
    # 1: DW_TAG_compile_unit
    db_uleb(1);                # abbrev code
    db_uleb(17);               # DW_TAG_compile_unit
    db_u8(1);                  # DW_CHILDREN_yes
    db_uleb(3);  db_uleb(8);   # DW_AT_name     DW_FORM_string
    db_uleb(17); db_uleb(1);   # DW_AT_low_pc   DW_FORM_addr
    db_uleb(18); db_uleb(1);   # DW_AT_high_pc  DW_FORM_addr
    db_uleb(16); db_uleb(6);   # DW_AT_stmt_list DW_FORM_data4
    db_uleb(37); db_uleb(8);   # DW_AT_producer DW_FORM_string
    db_uleb(19); db_uleb(5);   # DW_AT_language DW_FORM_data2
    db_uleb(0);  db_uleb(0);
    # 2: DW_TAG_base_type
    db_uleb(2);
    db_uleb(36);               # DW_TAG_base_type
    db_u8(0);                  # no children
    db_uleb(3);  db_uleb(8);   # DW_AT_name      DW_FORM_string
    db_uleb(62); db_uleb(11);  # DW_AT_encoding  DW_FORM_data1
    db_uleb(11); db_uleb(11);  # DW_AT_byte_size DW_FORM_data1
    db_uleb(0);  db_uleb(0);
    # 3: DW_TAG_subprogram
    db_uleb(3);
    db_uleb(46);               # DW_TAG_subprogram
    db_u8(1);                  # has children
    db_uleb(3);  db_uleb(8);   # DW_AT_name       DW_FORM_string
    db_uleb(17); db_uleb(1);   # DW_AT_low_pc     DW_FORM_addr
    db_uleb(18); db_uleb(1);   # DW_AT_high_pc    DW_FORM_addr
    db_uleb(64); db_uleb(24);  # DW_AT_frame_base DW_FORM_exprloc
    db_uleb(59); db_uleb(5);   # DW_AT_decl_line  DW_FORM_data2
    db_uleb(58); db_uleb(11);  # DW_AT_decl_file  DW_FORM_data1
    db_uleb(0);  db_uleb(0);
    # 4: DW_TAG_variable
    db_uleb(4);
    db_uleb(52);               # DW_TAG_variable
    db_u8(0);                  # no children
    db_uleb(3);  db_uleb(8);   # DW_AT_name     DW_FORM_string
    db_uleb(2);  db_uleb(24);  # DW_AT_location DW_FORM_exprloc
    db_uleb(59); db_uleb(5);   # DW_AT_decl_line DW_FORM_data2
    db_uleb(73); db_uleb(19);  # DW_AT_type     DW_FORM_ref4
    db_uleb(0);  db_uleb(0);
    # 5: DW_TAG_structure_type
    db_uleb(5);
    db_uleb(19);               # DW_TAG_structure_type
    db_u8(1);                  # has children
    db_uleb(3);  db_uleb(8);   # DW_AT_name      DW_FORM_string
    db_uleb(11); db_uleb(11);  # DW_AT_byte_size DW_FORM_data1
    db_uleb(0);  db_uleb(0);
    # 6: DW_TAG_member
    db_uleb(6);
    db_uleb(13);               # DW_TAG_member
    db_u8(0);
    db_uleb(3);  db_uleb(8);   # DW_AT_name      DW_FORM_string
    db_uleb(73); db_uleb(19);  # DW_AT_type      DW_FORM_ref4
    db_uleb(56); db_uleb(11);  # DW_AT_data_member_location DW_FORM_data1
    db_uleb(0);  db_uleb(0);
    # 7: DW_TAG_array_type
    db_uleb(7);
    db_uleb(1);                # DW_TAG_array_type
    db_u8(1);                  # has children
    db_uleb(73); db_uleb(19);  # DW_AT_type DW_FORM_ref4
    db_uleb(0);  db_uleb(0);
    # 8: DW_TAG_subrange_type
    db_uleb(8);
    # 🔴 subrange_type 是 0x21 = **33**，不是 21。
    #    21 (0x15) 是 DW_TAG_subroutine_type —— 于是 readelf 把数组的
    #    子范围解成"函数类型"，还顺带把 count 当成 DW_AT_base_types。
    #    数组 DIE 看起来"有子元素"，其实类型结构全错。
    db_uleb(33);               # DW_TAG_subrange_type
    db_u8(0);
    # 🔴 DW_AT_count 是 0x37 = **55**，不是 53。
    #    53 (0x35) 是 DW_AT_base_types —— 于是 readelf 把数组长度
    #    显示成 "DW_AT_base_types: 0x4"，看着像有值，其实是别的属性。
    db_uleb(55); db_uleb(6);   # DW_AT_count DW_FORM_data4
    db_uleb(0);  db_uleb(0);
    # 9: DW_TAG_pointer_type（有目标类型）
    db_uleb(9);
    db_uleb(15);               # DW_TAG_pointer_type
    db_u8(0);
    db_uleb(11); db_uleb(11);  # DW_AT_byte_size DW_FORM_data1
    db_uleb(73); db_uleb(19);  # DW_AT_type      DW_FORM_ref4
    db_uleb(0);  db_uleb(0);
    # 10: DW_TAG_pointer_type（void*，无目标类型）
    db_uleb(10);
    db_uleb(15);
    db_u8(0);
    db_uleb(11); db_uleb(11);
    db_uleb(0);  db_uleb(0);
    # 结束
    db_uleb(0);
    let al: i64 = gv(K_DBGLEN);
    sv(K_ABBRLEN, al);
    return 0;
}

fn gen_line() -> i64 {
    sv(K_DBBASE, 327680);
    sv(K_DBGLEN, 0);
    db_u32(0);                 # unit_length（回填）
    db_u16(4);                 # version 4
    let hpos: i64 = gv(K_DBGLEN);
    db_u32(0);                 # header_length（回填）
    let hstart: i64 = gv(K_DBGLEN);
    db_u8(1);                  # minimum_instruction_length
    db_u8(1);                  # maximum_operations_per_instruction
    db_u8(1);                  # default_is_stmt
    db_u8(251);                # line_base  = -5
    db_u8(14);                 # line_range = 14
    db_u8(13);                 # opcode_base
    # standard_opcode_lengths[12]
    db_u8(0); db_u8(1); db_u8(1); db_u8(1); db_u8(1); db_u8(0);
    db_u8(0); db_u8(0); db_u8(1); db_u8(0); db_u8(0); db_u8(1);
    # include_directories：空（只有一个结尾 NUL 表示表结束）
    db_u8(0);
    # file_names：所有参与编译的源文件（主文件 + import 进来的）。
    #
    # 早先这里只写主文件一个条目。那时 import 进来的代码没有行号记录，
    # 于是"只有一个文件"是自洽的；现在每条记录都带文件下标，表里
    # 少一个条目就会让 readelf 报 "file number N out of range"。
    let fi: i64 = 0;
    let nf: i64 = gv(K_NFILE);
    if nf < 1 { nf = 1; }
    if nf > 32 { nf = 32; }
    while fi < nf {
        db_str(DBG + O_FNM + fi * 256);
        db_u8(0); db_u8(0); db_u8(0);   # dir=0, mtime=0, length=0
        fi = fi + 1;
    }
    db_u8(0);                  # file table 结束
    let hl: i64 = gv(K_DBGLEN);
    db_poke32(hpos, hl - hstart);

    # ---- line number program ----
    # 只用最保守的三种操作：set_file / advance_line / advance_pc + copy。
    # 不用 special opcode，避免因 line_base/line_range 算错而整体错位。
    let cur: i64 = 0;
    let cline: i64 = 1;
    # DWARF 的文件编号从 **1** 起（1 = file_names 表的第一个条目），
    # 而内部下标从 0 起。少这个 +1 会让所有行号都归到"下一个文件"。
    let cfile: i64 = 1;
    let i: i64 = 0;
    let n: i64 = gv(K_NLM);
    while i < n {
        let a: i64 = load64(DBG + O_LM + i * 16);
        let ln: i64 = load64(DBG + O_LM + i * 16 + 8);
        let fn2: i64 = load8(DBG + O_LMF + i) + 1;
        if fn2 != cfile {
            db_u8(4);              # DW_LNS_set_file
            db_uleb(fn2);
            cfile = fn2;
        }
        if ln != cline {
                db_u8(3);              # DW_LNS_advance_line
                db_sleb(ln - cline);
                cline = ln;
            }
            if a + 4194480 != cur {
                db_u8(2);              # DW_LNS_advance_pc
                db_uleb(a + 4194480 - cur);
                cur = a + 4194480;
            }
        db_u8(1);                      # DW_LNS_copy
        i = i + 1;
    }
    # end_sequence：把地址推到代码末尾再收尾
    let enda: i64 = 4194480 + gv(K_CLEN);
    if enda != cur {
        db_u8(2);
        db_uleb(enda - cur);
    }
    db_u8(0); db_u8(1); db_u8(1);      # DW_LNE_end_sequence
    let ll: i64 = gv(K_DBGLEN);
    db_poke32(0, ll - 4);
    sv(K_LINELEN, ll);
    return 0;
}

# section 名字符串表。名字固定，偏移写死（省去回传六个偏移量）：
#   .text(1) .data(7) .debug_info(13) .debug_abbrev(25) .debug_line(39) .shstrtab(51)
# ============ .debug_frame（CFI，栈帧展开规则）============
#
# 有了它 gdb 才能做 `bt`（回溯调用栈）。
# .debug_info 里的变量位置只说明"变量在哪"，
# 而"上一帧在哪"必须由 CFI 描述 —— 两者是独立的。
#
# 墨语言的函数序言固定为：
#     push rbp            ; 1 字节
#     mov  rbp, rsp       ; 3 字节
#     sub  rsp, imm32     ; 7 字节（不改变 CFA，因为 CFA 用 rbp 表达）
# 尾声固定为：
#     mov rsp, rbp        ; 3 字节
#     pop rbp             ; 1 字节
#     ret                 ; 1 字节
#
# 于是 CFA 的取值只有三种：
#     入口处      CFA = rsp + 8    （call 已压返回地址）
#     push 之后   CFA = rsp + 16
#     mov 之后    CFA = rbp + 16   （此后 rsp 再变也不影响）
fn gen_frame() -> i64 {
    # 🔴 K_DBBASE 是**相对 O_DBG** 的偏移，而 O_DFR 是**相对 DBG** 的。
    #    两者坐标系不同，这里必须做减法，否则会写到完全错误的区域。
    sv(K_DBBASE, O_DFR - O_DBG);
    sv(K_DBGLEN, 0);

    # ---- CIE（version 1，augmentation 为空）----
    db_u32(0);                    # length（回填）
    db_u32(4294967295);           # CIE_id：32-bit DWARF 的标识
    db_u8(1);                     # version
    db_u8(0);                     # augmentation = ""
    db_uleb(1);                   # code_alignment_factor
    db_sleb(0 - 8);               # data_alignment_factor
    db_u8(16);                    # return_address_register = 16 (x86-64 ra)
    # 初始规则：CFA = rsp + 8，返回地址在 CFA-8
    db_u8(12); db_uleb(7); db_uleb(8);     # DW_CFA_def_cfa rsp, 8
    db_u8(144); db_uleb(1);                 # DW_CFA_offset r16(ra) @ CFA-8
    while gv(K_DBGLEN) % 8 != 0 { db_u8(0); }
    let cielen: i64 = gv(K_DBGLEN);
    db_poke32(0, cielen - 4);

    # ---- 每个函数一条 FDE ----
    let nf: i64 = gv(K_NDF);
    let i: i64 = 0;
    while i < nf {
        # 🔴 条目是 40 字节（name/low/high/decl_line/decl_file）。
        #    1.100 加 decl_file 时把 O_DF 从 32 扩到 40，只改了登记与
        #    .debug_info 三处，**漏了这里** —— 于是 lo/hi 读到下一条的
        #    字段，.debug_frame 里混进 lo=259 / range=4194376 这种垃圾。
        let fp: i64 = DBG + O_DF + i * 40;
        let lo: i64 = load64(fp + 8);
        let hi: i64 = load64(fp + 16);
        if hi > lo + 4 {
            let fpos: i64 = gv(K_DBGLEN);
            db_u32(0);                 # length（回填）
            db_u32(0);                 # CIE_pointer：CIE 在本 section 开头
            db_u64(lo);                # initial_location
            db_u64(hi - lo);           # address_range
            # 入口规则已由 CIE 给出（CFA = rsp+8）
            db_u8(65);                 # DW_CFA_advance_loc 1  → push 之后
            # 🔴 0x0e 才是 DW_CFA_def_cfa_offset；0x0f 是
            #    DW_CFA_def_cfa_expression —— 后者要跟一整个
            #    DWARF 表达式块，于是把后面的字节当成长度解析，
            #    readelf 报 "corrupt len"，CFA 规则全废。
            db_u8(14); db_uleb(16);    # DW_CFA_def_cfa_offset 16
            db_u8(134); db_uleb(2);    # DW_CFA_offset rbp(6), 2*(-8) = -16
            db_u8(67);                 # DW_CFA_advance_loc 3  → mov 之后
            db_u8(13); db_uleb(6);     # DW_CFA_def_cfa_register rbp
            while gv(K_DBGLEN) % 8 != 0 { db_u8(0); }
            let flen: i64 = gv(K_DBGLEN);
            db_poke32(fpos, flen - fpos - 4);
        }
        i = i + 1;
    }
    sv(K_FRAMELEN, gv(K_DBGLEN));
    return 0;
}

# ============ -c 模式：输出可重定位 .o（供 ld 链接 libc）============
#
# 为什么不直接生成可执行文件：外部符号的地址**只有 ld 知道**。
# 生成 .o + 重定位，再交给 ld 链接 libc，是唯一能真正调到 C 库的路径。
#
# .o 里 .text / .data 的地址都是 0，但代码里嵌的是**绝对地址**
# （movabs rax, 0x10000000+off）。所以链接时必须用
#   --section-start=.text=0x4000b0 --section-start=.data=0x10000000
# 把它们放回编译器假设的位置 —— 否则全局变量全部错位。
# 内部调用用的是 rel32，在同一个 section 内平移不变，不受影响。

fn obj_sym_index(sym: i64) -> i64 {
    let n: i64 = gv(K_NXS);
    let i: i64 = 0;
    while i < n {
        if load64(DBG + O_XS + i * 8) == sym { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

# 去重：同一个 extern 函数被调用多次只占一条 symtab
fn obj_collect() -> i64 {
    sv(K_NXS, 0);
    let n: i64 = gv(K_NXC);
    let i: i64 = 0;
    while i < n {
        let sy: i64 = load64(DBG + O_XC + i * 16 + 8);
        if obj_sym_index(sy) < 0 {
            let k: i64 = gv(K_NXS);
            if k < 1024 {
                store64(DBG + O_XS + k * 8, sy);
                sv(K_NXS, k + 1);
            }
        }
        i = i + 1;
    }
    # -shared：本文件定义的函数全部导出，否则 C 那边链接不到
    # （默认只登记 extern 和被 & 取过地址的）。
    if load64(DBG + O_SOF) == 1 {
        let s2: i64 = 0;
        while s2 < gv(K_NSYM) {
            if sym_kind(s2) == 0 {
                if streq(name_at(s2), "main") == 0 {
                if obj_sym_index(s2) < 0 {
                    let k2: i64 = gv(K_NXS);
                    if k2 < 1024 {
                        store64(DBG + O_XS + k2 * 8, s2);
                        sv(K_NXS, k2 + 1);
                    }
                }
                }
            }
            s2 = s2 + 1;
        }
    }
    return 0;
}

fn gen_obj() -> i64 {
    obj_collect();
    let ns: i64 = gv(K_NXS);

    # ---- .strtab ----
    sv(K_DBBASE, 262144);
    sv(K_DBGLEN, 0);
    db_u8(0);
    db_str("_start");
    let si: i64 = 0;
    while si < ns {
        db_str(name_at(load64(DBG + O_XS + si * 8)));
        si = si + 1;
    }
    let strl: i64 = gv(K_DBGLEN);

    # ---- .symtab ----（[0] null, [1] _start, [2..] extern UND）
    sv(K_DBBASE, 0);
    sv(K_DBGLEN, 0);
    # null
    db_u32(0); db_u8(0); db_u8(0); db_u16(0); db_u64(0); db_u64(0);
    let sb: i64 = 2;                  # 符号表下标基数（0=null,1=_start）
    if load64(DBG + O_SOF) == 1 {
        # [1] .data section 符号 —— R_X86_64_RELATIVE 的 addend 要挂它，
        #     ld 才会把 .data 的输出 vaddr 加进去（最终 = base + vaddr + off）
        db_u32(0); db_u8(0); db_u8(3); db_u16(2); db_u64(0); db_u64(0);
        sb = 3;
    }
    # _start：GLOBAL FUNC，定义在 .text(1) 偏移 0
    db_u32(1); db_u8(18); db_u8(0); db_u16(1); db_u64(0); db_u64(0);
    let i: i64 = 0;
    while i < ns {
        let sy: i64 = load64(DBG + O_XS + i * 8);
        # 名字在 strtab 里的偏移：累加前面所有名字的长度。
        # 🔴 起点是 **8** 不是 7：strtab 先是 1 字节 NUL，
        #    再是 "_start" 6 字节 + 1 字节 NUL = 7，下一个名字从 8 开始。
        #    第一版写 7 —— 正好指向 `_start` 结尾的 NUL，
        #    于是 extern 符号的名字是空串，ld 报 "corrupt symbol table"。
        let off: i64 = 1 + strlen("_start") + 1;
        let j: i64 = 0;
        while j < i {
            off = off + strlen(name_at(load64(DBG + O_XS + j * 8))) + 1;
            j = j + 1;
        }
        db_u32(off);
        db_u8(18);             # STB_GLOBAL | STT_FUNC
        db_u8(0);
        # 🔴 必须区分"本文件定义的函数"和"extern 的 C 函数"：
        #    kind 3（extern）→ SHN_UNDEF，地址由 ld 解析；
        #    kind 0（本文件定义，`&func` 取了它的地址）→ 定义在 .text，
        #    shndx=1、st_value=函数在 .text 内的偏移。
        #    一律写成 UND 会让 ld 报 "undefined reference to 'cmp'"
        #    —— 明明代码就在 .text 里。
        if sym_kind(sy) == 3 {
            db_u16(0);
            db_u64(0);
        } else {
            db_u16(1);
            # 代码里 sym_addr 是 4194304+176+off，.o 里 .text 从 0 开始
            db_u64(sym_addr(sy) - 4194480);
        }
        db_u64(0);
        i = i + 1;
    }
    let syml: i64 = gv(K_DBGLEN);

    # ---- .rela.text ----
    sv(K_DBBASE, 327680);
    sv(K_DBGLEN, 0);
    let nx: i64 = gv(K_NXC);
    let k: i64 = 0;
    while k < nx {
        let coff: i64 = load64(DBG + O_XC + k * 16);
        let sy: i64 = load64(DBG + O_XC + k * 16 + 8);
        let si2: i64 = obj_sym_index(sy);
        # 符号表下标 = 2 + si2（0 是 null，1 是 _start）
        let rt2: i64 = load64(DBG + O_XR + k * 8);   # 1 = 64 位绝对，4 = PLT32
        db_u64(coff);
        db_u64((sb + si2) * 4294967296 + rt2);
        if rt2 == 4 {
            db_i64(0 - 4);                    # 调用：-4（有符号！）
        } else {
            db_i64(0);                        # 取地址：0
        }
        k = k + 1;
    }
    if load64(DBG + O_SOF) == 1 {
        let ng: i64 = load64(DBG + O_GVN);
        let g2: i64 = 0;
        while g2 < ng {
            db_u64(load64(DBG + O_GVP + g2 * 8));
            # sym=1(.data section), R_X86_64_PC32 = 2；A = off - 4
            db_u64(4294967296 + 2);
            db_i64(load64(DBG + O_GVA + g2 * 8) - 4);
            g2 = g2 + 1;
        }
    }
    let relal: i64 = gv(K_DBGLEN);

    # ---- .shstrtab ----
    sv(K_DBBASE, 917504);
    sv(K_DBGLEN, 0);
    db_u8(0);
    db_str(".text");
    db_str(".data");
    db_str(".rela.text");
    db_str(".symtab");
    db_str(".strtab");
    db_str(".shstrtab");
    let shstrl: i64 = gv(K_DBGLEN);

    # ---- section header 表 ----
    let c1: i64 = gv(K_CLEN);
    let d1: i64 = gv(K_DLEN);
    let o: i64 = 64;
    let t_off: i64 = o;  o = o + c1;
    let t_off2: i64 = ((o + 7) & -8);  o = t_off2 + d1;
    let r_off: i64 = o;  o = o + relal;
    let s_off: i64 = o;  o = o + syml;
    let st_off: i64 = o; o = o + strl;
    let ss_off: i64 = o; o = o + shstrl;
    let sh_off: i64 = (o + 7) & -8;

    sh_hdr(0, 0, 0, 0, 0);            sh_rest(0, 0, 0, 0);
    sh_hdr(1, 1, 1, 6, 0);            sh_rest(1, t_off, c1, 16);
    sh_hdr(2, 7, 1, 3, 0);            sh_rest(2, t_off2, d1, 8);
    sh_hdr(3, 13, 4, 0, 0);           sh_rest(3, r_off, relal, 8);
    sh_hdr(4, 24, 2, 0, 0);           sh_rest(4, s_off, syml, 8);
    sh_hdr(5, 32, 3, 0, 0);           sh_rest(5, st_off, strl, 1);
    sh_hdr(6, 40, 3, 0, 0);           sh_rest(6, ss_off, shstrl, 1);
    # rela.text / symtab 的 sh_link 与 sh_info
    store32(DBG + O_SHDR + 3 * 64 + 40, 4);   # sh_link = symtab
    store32(DBG + O_SHDR + 3 * 64 + 44, 1);   # sh_info = .text
    store32(DBG + O_SHDR + 4 * 64 + 40, 5);   # symtab sh_link = strtab
    # sh_info = 第一个非局部符号的下标（-shared 下 _start 是 2，
    # 因为 [1] 让给了 .data section 符号）。
    # 不设的话 ld 直接拒绝："local symbol at index 1 (>= sh_info of 1)"。
    if load64(DBG + O_SOF) == 1 {
        store32(DBG + O_SHDR + 4 * 64 + 44, 2);
    } else {
        store32(DBG + O_SHDR + 4 * 64 + 44, 1);
    }
    # 🔴 Elf64_Shdr 里 sh_addralign 在 **48**、sh_entsize 在 **56**。
    #    第一版两个都写到 48 —— 于是 addralign 变成 24、entsize 留 0，
    #    readelf 报 "invalid sh_entsize"，而且**照常显示重定位内容**，
    #    很容易误以为节表是对的。
    store64(DBG + O_SHDR + 3 * 64 + 48, 8);   # addralign
    store64(DBG + O_SHDR + 3 * 64 + 56, 24);  # entsize
    store64(DBG + O_SHDR + 4 * 64 + 48, 8);
    store64(DBG + O_SHDR + 4 * 64 + 56, 24);

    # ---- ELF header（ET_REL）----
    zero_elf();
    let e: i64 = heap + O_ELF;
    store8(e, 0x7f); store8(e + 1, 0x45); store8(e + 2, 0x4c); store8(e + 3, 0x46);
    store8(e + 4, 2);        # ELFCLASS64
    store8(e + 5, 1);        # ELFDATA2LSB
    store8(e + 6, 1);        # EV_CURRENT
    store8(e + 16, 1);       # e_type = ET_REL
    store16(e + 18, 0x3e);   # EM_X86_64
    store32(e + 20, 1);
    store64(e + 24, 0);      # e_entry = 0（重定位文件无入口）
    store64(e + 32, 0);      # e_phoff = 0
    store64(e + 40, sh_off); # e_shoff
    store32(e + 48, 0);
    store16(e + 52, 64);     # e_ehsize
    store16(e + 54, 0);      # e_phentsize
    store16(e + 56, 0);      # e_phnum
    store16(e + 58, 64);     # e_shentsize
    store16(e + 60, 7);      # e_shnum
    store16(e + 62, 6);      # e_shstrndx
    sv(K_OBJSH, sh_off);
    sv(K_OBJRL, relal);
    sv(K_OBJSL, syml);
    sv(K_OBJTL, strl);
    sv(K_OBJHL, shstrl);
    return 0;
}

fn gen_shstr() -> i64 {
    sv(K_DBBASE, 917504);
    sv(K_DBGLEN, 0);
    db_u8(0);
    db_str(".text");
    db_str(".data");
    db_str(".debug_info");
    db_str(".debug_abbrev");
    db_str(".debug_line");
    db_str(".debug_frame");
    db_str(".shstrtab");
    let sl: i64 = gv(K_DBGLEN);
    sv(K_SHSTRLEN, sl);
    return 0;
}

# 写一条 section header（每项 64 字节）。
# 刻意拆成两个不超过 5 个参数的函数：参数 7 个以上要走栈上传参，
# 那条路径刚修过但还没被真实程序验证过；寄存器传参（<=6）则是
# 编译器从一开始就走的路。这里不需要冒这个险。
fn sh_hdr(i: i64, name: i64, typ: i64, flags: i64, addr: i64) -> i64 {
    let p: i64 = DBG + O_SHDR + i * 64;
    store32(p, name);
    store32(p + 4, typ);
    store64(p + 8, flags);
    store64(p + 16, addr);
    return 0;
}

fn sh_rest(i: i64, off: i64, size: i64, align: i64) -> i64 {
    let p: i64 = DBG + O_SHDR + i * 64;
    store64(p + 24, off);
    store64(p + 32, size);
    store32(p + 40, 0);
    store32(p + 44, 0);
    store64(p + 48, align);
    store64(p + 56, 0);
    return 0;
}

fn gen_shdr(base: i64, sz: i64) -> i64 {
    let o: i64 = base;
    # 0: NULL
    sh_hdr(0, 0, 0, 0, 0);
    sh_rest(0, 0, 0, 0);
    # 1: .text —— vaddr 4194304 对应文件 offset 0，所以代码在 176 处
    # 实参里一律先取到局部变量，避免嵌套调用覆盖函数名缓冲
    let c1: i64 = gv(K_CLEN);
    let d1: i64 = gv(K_DLEN);
    let i1: i64 = gv(K_INFOLEN);
    let a1: i64 = gv(K_ABBRLEN);
    let l1: i64 = gv(K_LINELEN);
    let s1: i64 = gv(K_SHSTRLEN);
    let f1: i64 = gv(K_FRAMELEN);
    sh_hdr(1, 1, 1, 6, 4194480);
    sh_rest(1, 176, c1, 16);
    sh_hdr(2, 7, 1, 3, 268435456);
    sh_rest(2, sz, d1, 8);
    sh_hdr(3, 13, 1, 0, 0);
    sh_rest(3, o, i1, 1);
    o = o + i1;
    sh_hdr(4, 25, 1, 0, 0);
    sh_rest(4, o, a1, 1);
    o = o + a1;
    sh_hdr(5, 39, 1, 0, 0);
    sh_rest(5, o, l1, 1);
    o = o + l1;
    sh_hdr(6, 51, 1, 0, 0);          # .debug_frame
    sh_rest(6, o, f1, 1);
    o = o + f1;
    sh_hdr(7, 64, 3, 0, 0);          # .shstrtab（名字偏移因新增节而下移）
    sh_rest(7, o, s1, 1);
    o = o + s1;
    # ELF header 里补上节头表位置
    let e: i64 = heap + O_ELF;
    store64(e + 40, o);
    store16(e + 58, 64);
    store16(e + 60, 8);              # 节数由 7 增到 8
    store16(e + 62, 7);              # e_shstrndx：.shstrtab 现在是第 7 个
    return 0;
}

fn main() -> i64 {
    # 申请堆：brk 到 16MB
    let brk: i64 = syscall(12, 0, 0, 0, 0, 0, 0);
    let need: i64 = brk + O_DATA + O_DCAP + 8388608;
    syscall(12, need, 0, 0, 0, 0, 0);
    heap = brk + 4096;
    # 调试数据单独申请 4MB，放在主堆之后。
    # 主堆里的字符串池（O_STRS 起）会一直增长，早先调试区放在主堆内部，
    # 编译自身时被它覆盖，行号表读出来全是字符串内容。
    # 8MB：行号表(O_LM 起 1MB) + DWARF(O_DBG 起 1MB) + shstr/shdr
    #      + 函数表(O_DF 3MB) + 变量表(O_DV 4MB)，各区互不重叠。
    # 原先 4MB 时 O_DV/O_DF 会越界写到未映射内存 —— 表现为 -g 编译时
    # 段错误，且只在变量较多的文件上出现。
    # 9MB：上面各区 + O_LMF(8320000 起 60000 字节) + O_FNM(8388608 起
    #      32×256 字节)。8MB 时 O_FNM 写到了未映射内存，表现为 -g
    #      编译直接段错误，且只在带 import 的程序上出现。
    let need2: i64 = need + 9437184;
    syscall(12, need2, 0, 0, 0, 0, 0);
    DBG = need + 4096;

    # 命令行：argv[1] 为输入，argv[2] 为输出（缺省 test.mo / out.elf）
    let inpath: i64 = "test.mo";
    let outpath: i64 = "out.elf";
    let npath: i64 = 0;
    sv(K_DBG, 0);
    sv(K_NDV, 0);
    sv(K_NDF, 0);
    sv(K_CURFN, 0);
    # v1.1112: const fn 表清零（堆初值非零，O_CFF 残留会误触发折叠）
    let czc: i64 = 0;
    while czc < 5000 {
        store8(heap + O_CFF + czc, 0);
        store64(heap + O_CFB + czc * 16, 0);
        store64(heap + O_CFB + czc * 16 + 8, 0);
        czc = czc + 1;
    }
    let ai: i64 = 1;
    while ai < argc() {
        let a: i64 = argv(ai);
        if streq(a, "-g") == 1 {
            sv(K_DBG, 1);
        } else {
            if streq(a, "-Wall") == 1 {
                sv(K_WARN, 1);
            } else {
                if streq(a, "-p") == 1 {
                    sv(K_PROF, 1);
                } else {
                    if streq(a, "-c") == 1 {
                        sv(K_OBJ, 1);
                    } else {
                        if streq(a, "-shared") == 1 {
                            sv(K_OBJ, 1);
                            store64(DBG + O_SOF, 1);
                        } else {
                            if npath == 0 {
                                inpath = a;
                                npath = 1;
                            } else {
                                outpath = a;
                            }
                        }
                    }
                }
            }
        }
        ai = ai + 1;
    }
    INPATH = inpath;

    # 读源文件
    let fd: i64 = syscall(2, inpath, 0, 0, 0, 0, 0);
    if fd < 0 { return die("cannot open input\n"); }
    let n: i64 = syscall(0, fd, heap + O_SRC, 4194303, 0, 0, 0);
    syscall(3, fd, 0, 0, 0, 0, 0);
    sv(K_SRCLEN, n);
    sv(K_POS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    sv(K_CPOS, 0);
    sv(K_SRCBASE, O_SRC);
    sv(K_RBOFF, 0 - 1);   # v1.1096: 返回值缓冲未分配
    # 文件名表下标 0 是**主文件**，import 从 1 起（compile_file 里 +1）。
    # 所以这里必须是 1 而不是 0 —— 否则第一个 import 也拿到下标 0，
    # 与主文件撞号，两个文件的行号会混在同一条目下。
    sv(K_NFILE, 1);
    sv(K_CURFILE, 0);
    dbg_fname(0, inpath);
    sv(K_NSTR, 0);
    sv(K_NSTRUCT, 0);
    sv(K_NIMP, 0);
    sv(K_PANIC, 0 - 1);
    sv(K_PJMP, 0);
    sv(K_NLM, 0);
    sv(K_CRBX, 0);
    ty_init();
    # 数据段头 16 字节留给 argc/argv，全局变量从 +16 开始
    reserve_arg_slots();

    emit_startup();
    parse_program();
    # vtable 必须在**全部解析结束**后回填：impl 出现时函数可能还没定义，
    # 此刻 O_SA 里才有真正的函数地址。
    #
    # 🔴 第一次插错了位置 —— 加到了 compile_file 里的那一次
    #    （import 每个文件都会跑）。那时主文件还没解析，K_NVT 恒为 0，
    #    于是 vtable 永远是 0，call 0 直接段错误，而编译**完全不报错**。
    iface_patch_vtables();
    # 未使用函数警告（-Wall 同款）：本文件定义（kind 0）、非 main、
    # 从未被引用（O_SU==0）。必须在全部解析结束后扫 —— impl/vtable
    # 回填不会引用函数，但虚表 call 不走名字查找，避免误报只在
    # interface 方法上排除：有 vtable 槽位的函数一律算"可能被调用"。
    if gv(K_WARN) == 1 {
        # 先扫虚表：被任何 vtable 槽引用的函数一律算"可能被调用"
        # （虚表 call 不走名字查找），避免对 interface 方法误报。
        let wi: i64 = 0;
        let wv: i64 = 0;
        while wv < gv(K_NVT) {
            let wn2: i64 = load64(heap + O_VTN + wv * 8);
            let wk: i64 = 0;
            while wk < wn2 {
                let fs: i64 = load64(heap + O_VTS + wv * 128 + wk * 8);
                if fs >= 0 && fs < 2048 {
                    store64(heap + O_SU + fs * 8, 1);
                }
                wk = wk + 1;
            }
            wv = wv + 1;
        }
        while wi < gv(K_NSYM) {
            if load64(heap + O_SWN + wi * 8) == 0 {
            if load64(heap + O_SK + wi * 8) == 0 || load64(heap + O_SK + wi * 8) == 2 || load64(heap + O_SK + wi * 8) == 4 {
                if load64(heap + O_SU + wi * 8) == 0 {
                    let wn: i64 = name_at(wi);
                    if streq(wn, "main") == 0 {
                        syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
                        if load64(heap + O_SK + wi * 8) == 0 {
                            syscall(1, 2, ": warning: unused function '", 28, 0, 0, 0);
                        } else {
                            if load64(heap + O_SK + wi * 8) == 4 {
                                syscall(1, 2, ": warning: unused const '", 25, 0, 0, 0);
                            } else {
                                syscall(1, 2, ": warning: unused global '", 26, 0, 0, 0);
                            }
                        }
                        syscall(1, 2, wn, strlen(wn), 0, 0, 0);
                        syscall(1, 2, "'\n", 2, 0, 0, 0);
                    }
                }
            }
            }
            wi = wi + 1;
        }
    }

    # trait bound 检查同样必须在**全部解析结束**后：impl 可能出现在
    # instantiate 之后，此刻 K_NVT 才是完整的。
    gen_check_bounds();
    if gv(K_NBER) > 0 { return 1; }
    let had_err: i64 = ERR_N;

    # 有语法错误（软恢复后）仍生成 elf，让错误行之后的正确代码照常运行；
    # 退出码由调用方按 ERR_N 判 1。
    emit_panic();
    resolve_defp();
    resolve_all();

    let m: i64 = sym_lookup_func("main");
    if m < 0 { return die("no main function\n"); }
    let ma: i64 = sym_addr(m);
    if gv(K_OBJ) == 0 {
        let j: i64 = 0;
        while j < 8 {
            store8(heap + O_CODE + MAINPAT + j, (ma >> (j * 8)) & 255);
            j = j + 1;
        }
    } else {
        # rel32 = 段内偏移之差，与 .text 最终落在哪儿无关
        let rl: i64 = (ma - 4194480) - (MAINPAT + 4);
        let j2: i64 = 0;
        while j2 < 4 {
            store8(heap + O_CODE + MAINPAT + j2, (rl >> (j2 * 8)) & 255);
            j2 = j2 + 1;
        }
    }
    if gv(K_OBJ) == 1 {
        gen_obj();
    } else {
        build_elf(4194304 + 176);
    }

    # 调试信息：必须在写盘之前生成，因为它会改 ELF header（e_shoff 等）。
    # 不开启 -g 时这段不执行，输出字节与以前完全一致。
    if gv(K_DBG) == 1 {
        let sz: i64 = (gv(K_CLEN) + 176 + 4095) & -4096;
        gen_info();
        gen_abbrev();
        gen_line();
        gen_frame();
        gen_shstr();
        let dl: i64 = gv(K_DLEN);
        gen_shdr(sz + dl, sz);
    }

    let ofd: i64 = syscall(2, outpath, 577, 493, 0, 0, 0);
    if ofd < 0 { return die("cannot open output\n"); }
    if gv(K_OBJ) == 1 {
        # ---- .o：ELF 头 → .text → .data → rela → symtab → strtab → shstr → shdr
        write_all(ofd, heap + O_ELF, 64);
        write_all(ofd, heap + O_CODE, gv(K_CLEN));
        let c1: i64 = gv(K_CLEN);
        let d1: i64 = gv(K_DLEN);
        let o1: i64 = 64 + c1;
        let t2: i64 = (o1 + 7) & -8;
        let p1: i64 = t2 - o1;
        let rl: i64 = gv(K_OBJRL);
        let sl: i64 = gv(K_OBJSL);
        let tl: i64 = gv(K_OBJTL);
        let hl: i64 = gv(K_OBJHL);
        write_all(ofd, heap + O_ZERO, p1);
        write_all(ofd, heap + O_DATA, d1);
        write_all(ofd, DBG + O_DBG + 327680, rl);
        write_all(ofd, DBG + O_DBG + 0, sl);
        write_all(ofd, DBG + O_DBG + 262144, tl);
        write_all(ofd, DBG + O_DBG + 917504, hl);
        let sh: i64 = gv(K_OBJSH);
        let cur: i64 = t2 + d1 + rl + sl + tl + hl;
        write_all(ofd, heap + O_ZERO, sh - cur);
        write_all(ofd, DBG + O_SHDR, 448);
        syscall(3, ofd, 0, 0, 0, 0, 0);
        return 0;
    }
    write_all(ofd, heap + O_ELF, 176);
    write_all(ofd, heap + O_CODE, gv(K_CLEN));
    let pad: i64 = (4096 - ((gv(K_CLEN) + 176) & 4095)) & 4095;
    write_all(ofd, heap + O_ZERO, pad);
    write_all(ofd, heap + O_DATA, gv(K_DLEN));
    if gv(K_DBG) == 1 {
        write_all(ofd, DBG + O_DBG + 0, gv(K_INFOLEN));
        write_all(ofd, DBG + O_DBG + 262144, gv(K_ABBRLEN));
        write_all(ofd, DBG + O_DBG + 327680, gv(K_LINELEN));
        # 🔴 写盘顺序必须与 gen_shdr 里累加 `o` 的顺序**完全一致**：
        #    info → abbrev → line → frame → shstr。
        #    第一版按旧顺序把 shstr 写在了 frame 之前，
        #    于是节头表里 .shstrtab 的 offset 指向了 frame 数据、
        #    .debug_frame 的 offset 指向了字符串表 ——
        #    readelf 打出的节名全是乱码，且报 "Corrupt debuglink"。
        #    这类错误**不会让程序跑不起来**，只让调试信息不可用。
        write_all(ofd, DBG + O_DFR, gv(K_FRAMELEN));
        write_all(ofd, DBG + O_DBG + 917504, gv(K_SHSTRLEN));
        write_all(ofd, DBG + O_SHDR, 512);
    }
    syscall(3, ofd, 0, 0, 0, 0, 0);
    # 有语法错误（elf 已生成）：退出码 1
    if had_err > 0 { return 1; }
    return 0;
}

# 结构体逐字段拷贝：rax = 源地址，dst = 目标绝对地址，n = 字段数。
#
# 为什么需要：`let q: P = a;` 里 a 退化成**地址**（与数组名一致），
# 而函数返回结构体时值在 rax/rdx（System V）。两者 R_ETY 都是 struct，
# 必须靠 R_SADDR 区分 —— 混用会把地址写进字段，或把值当地址去解引用。
# 用 disp32 而不是 disp8：字段数一多（>15）disp8 就不够。
fn g_struct_copy(dst: i64, n: i64) -> i64 {
    g_movabs_rsi(dst);             # rsi = 目标
    ops3(0x48, 0x89, 0xc7);        # mov rdi, rax   （rdi = 源）
    let i: i64 = 0;
    while i < n {
        let o: i64 = i * 8;
        ops3(0x48, 0x8b, 0x8f);    # mov rcx, [rdi+disp32]
        emit4(o);
        ops3(0x48, 0x89, 0x8e);    # mov [rsi+disp32], rcx
        emit4(o);
        i = i + 1;
    }
    return 0;
}
# ==========================================================================
#  组件（component）原生支持 —— 自举组件（追加部分）
#  见 parse_component：把 component 声明展开成 Mo 源码并解析。
# ==========================================================================
var CMP_P: i64 = 0;          # 展开缓冲（O_GENBUF）写指针
var CMP_TY: [64] i64 = 0;    # 字段类型：0=text 1=num 2=state
var CMP_WD: [64] i64 = 0;    # 字段宽度
var CMP_CC: [64] i64 = 0;    # 字段颜色（text/num 用）
var CMP_FN: [64] i64 = 0;    # 字段名在 O_NAMES 里的偏移
var CMP_AL: [64] i64 = 0;    # 字段对齐：0=左 1=右
var CMP_HD: [64] i64 = 0;    # 字段隐藏：1=hidden（row 不渲染，生成 X_hdN 变量可切换）
var CMP_HS: [64] i64 = 0;    # spark 历史长度：0=单值模式，>N=hist M 环形走势
var CMP_CB: [64] i64 = 0;    # on_click 回调函数名 O_NAMES 偏移；-1=无
var CMP_HB: [64] i64 = 0;    # on_hover 回调函数名 O_NAMES 偏移；-1=无
var CMP_LO: [64] i64 = 0;    # 数值字段 min 钳制
var CMP_HI: [64] i64 = 0;    # 数值字段 max 钳制
var CMP_PX: [64] i64 = 0;    # prefix 字符串 O_STRS 偏移；-1=无
var CMP_SX: [64] i64 = 0;    # suffix 字符串 O_STRS 偏移；-1=无
var CMP_DV: [64] i64 = 0;    # default 数值（dflts>=0 时无效）
var CMP_DS: [64] i64 = 0;    # default 字符串 O_STRS 偏移；-1=无
var CMP_FM: [64] i64 = 0;    # num 渲染进制：10 默认 / 16 hex / 2 bin / 8 oct
var CMP_NF: i64 = 0;         # 字段数

fn cmp_c(c: i64) -> i64 {
    store8(heap + O_GENBUF + CMP_P, c);
    CMP_P = CMP_P + 1;
    return 0;
}

fn cmp_s(s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        cmp_c(load8(s + i));
        i = i + 1;
    }
    return 0;
}

fn cmp_i(v: i64) -> i64 {
    let p: i64 = heap + O_SCAL + 1400;
    let i: i64 = 0;
    if v == 0 {
        cmp_c(48);
        return 0;
    }
    let vv: i64 = v;
    while vv > 0 {
        store8(p + i, 48 + (vv % 10));
        vv = vv / 10;
        i = i + 1;
    }
    let j: i64 = 0;
    while j < i / 2 {
        let t: i64 = load8(p + j);
        store8(p + j, load8(p + i - 1 - j));
        store8(p + i - 1 - j, t);
        j = j + 1;
    }
    let k: i64 = 0;
    while k < i {
        cmp_c(load8(p + k));
        k = k + 1;
    }
    return 0;
}

# 生成一个字段的全局变量声明
fn cmp_field_var(compo: i64, fld: i64, kind: i64) -> i64 {
    cmp_s("var ");
    cmp_s(compo);
    cmp_c(95);
    cmp_s(fld);
    if kind == 0 {
        cmp_s(": [32] byte = 0;\n");
    } else {
        cmp_s(": i64 = 0;\n");
    }
    return 0;
}

# 生成一个字段的 setter 函数
fn cmp_setter(compo: i64, fld: i64, kind: i64, hs: i64, lo: i64, hi: i64) -> i64 {
    cmp_s("fn ");
    cmp_s(compo);
    cmp_c(95);
    cmp_s("set_");
    cmp_s(fld);
    if kind == 0 {
        cmp_s("(v: ptr) -> i64 {\n    let n: i64 = strlen(v);\n    let i: i64 = 0;\n    while i < n {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("[i] = load8(v + i);\n        i = i + 1;\n    }\n    ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("[n] = 0;\n    return 0;\n}\n");
    } else {
        if hs > 0 {
        cmp_s("(v: i64) -> i64 {\n    if ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n >= ");
        cmp_i(hs);
        cmp_s(" {\n    let k: i64 = 1;\n    while k < ");
        cmp_i(hs);
        cmp_s(" {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[k - 1] = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[k];\n        k = k + 1;\n    }\n    } else {\n    ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n + 1;\n    }\n    ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n - 1] = v;\n    return 0;\n}\n");
        return 0;
        }
        cmp_s("(v: i64) -> i64 {\n");
        if lo != 0 || hi != 0 {
        cmp_s("    if v < ");
        cmp_i(lo);
        cmp_s(" {\n        v = ");
        cmp_i(lo);
        cmp_s(";\n    }\n    if v > ");
        cmp_i(hi);
        cmp_s(" {\n        v = ");
        cmp_i(hi);
        cmp_s(";\n    }\n");
        }
        cmp_s("    ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = v;\n    return 0;\n}\n");
    }
    return 0;
}

# 生成 row 函数里一个字段的绘制代码。fi 是字段序号。

# kind>=3 的扩展渲染（bar/gauge/kv/hex）—— 独立函数避免深层 else 链
fn cmp_row_ext(compo: i64, fld: i64, kind: i64, wd: i64, col: i64, fi: i64) -> i64 {
    if kind == 3 {
        if CMP_HS[fi] > 0 {
        cmp_s("    let bsum: i64 = 0;\n    let bct: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n;\n    let bidx: i64 = 0;\n    while bidx < bct {\n        bsum = bsum + ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[bidx];\n        bidx = bidx + 1;\n    }\n    if bct > 0 {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = bsum / bct;\n    }\n");
        }
        cmp_s("    let bf: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let bz: i64 = 0;\n    while bz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[bz] = 0;\n        bz = bz + 1;\n    }\n    str_itoa_base(bf, ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", 10);\n    let bl: i64 = strlen(bf);\n    let fill: i64 = ");
        cmp_i(wd);
        cmp_s(" - bl - 2;\n    uc_set(cx, y, '[', UC_WHITE, bg);\n    let bi: i64 = 0;\n    while bi < fill {\n        if bi < (");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" * fill) / 100 {\n            uc_set(cx + 1 + bi, y, '#', UC_GREEN, bg);\n        } else {\n            uc_set(cx + 1 + bi, y, '-', UC_WHITE, bg);\n        }\n        bi = bi + 1;\n    }\n    uc_set(cx + 1 + fill, y, ']', UC_WHITE, bg);\n    uc_text(cx + fill + 3, y, bf, UC_CYAN, bg);\n");
        return 0;
    }
    if kind == 4 {
        cmp_s("    let gf: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let gz: i64 = 0;\n    while gz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[gz] = 0;\n        gz = gz + 1;\n    }\n    str_itoa_base(gf, ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", 10);\n    let gl: i64 = strlen(gf);\n    let gw: i64 = ");
        cmp_i(wd);
        cmp_s(" - gl - 1;\n    let gq: i64 = (");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" * 8) / 100;\n    let gi: i64 = 0;\n    while gi < gw {\n        uc_set(cx + gi, y, 9608, UC_CYAN, bg);\n        gi = gi + 1;\n    }\n    let gj: i64 = 0;\n    while gj < gq {\n        if gj < gw {\n            uc_set(cx + gj, y, 9619, UC_YELLOW, bg);\n        }\n        gj = gj + 1;\n    }\n    uc_text(cx + gw + 1, y, gf, UC_WHITE, bg);\n");
        return 0;
    }
    if kind == 5 {
        cmp_s("    uc_text(cx, y, &");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", UC_MAGENTA, bg);\n");
        return 0;
    }
    if kind == 9 {
        if CMP_HS[fi] > 0 {
        cmp_s("    let dsum: i64 = 0;\n    let dct: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n;\n    let didx: i64 = 0;\n    while didx < dct {\n        dsum = dsum + ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[didx];\n        didx = didx + 1;\n    }\n    if dct > 0 {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = dsum / dct;\n    }\n");
        }
        if CMP_AL[fi] == 1 {
        cmp_s("    let dv: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(";\n    let db: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let dz: i64 = 0;\n    while dz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[dz] = 0;\n        dz = dz + 1;\n    }\n    if dv < 0 {\n        str_itoa_base(db, 0 - dv, 10);\n    } else {\n        str_itoa_base(db, dv, 10);\n    }\n    let dl: i64 = strlen(db);\n    let dp: i64 = ");
        cmp_i(wd);
        cmp_s(" - dl - 1;\n    let dq: i64 = 0;\n    while dq < dp {\n        uc_set(cx + dq, y, ' ', fg, bg);\n        dq = dq + 1;\n    }\n    if dv < 0 {\n        uc_set(cx + dp, y, 9660, UC_RED, bg);\n    } else {\n        uc_set(cx + dp, y, 9650, UC_GREEN, bg);\n    }\n    uc_text(cx + dp + 1, y, db, UC_CYAN, bg);\n    cx = cx + ");
        cmp_i(wd);
        cmp_s(" + 2;\n");
        return 0;
        }
        cmp_s("    let dv: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(";\n    let db: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let dz: i64 = 0;\n    while dz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[dz] = 0;\n        dz = dz + 1;\n    }\n    if dv < 0 {\n        uc_set(cx, y, 9660, UC_RED, bg);\n        str_itoa_base(db, 0 - dv, 10);\n    } else {\n        uc_set(cx, y, 9650, UC_GREEN, bg);\n        str_itoa_base(db, dv, 10);\n    }\n    if strlen(db) > ");
        cmp_i(wd);
        cmp_s(" { ");
        cmp_s(compo);
        cmp_s("_buf[");
        cmp_i(wd);
        cmp_s("] = 0;\n    }\n    uc_text(cx + 1, y, db, UC_CYAN, bg);\n");
        return 0;
    }
    if kind == 8 {
        if CMP_HS[fi] > 0 {
        cmp_s("    let psum: i64 = 0;\n    let pct_n: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n;\n    let pidx: i64 = 0;\n    while pidx < pct_n {\n        psum = psum + ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[pidx];\n        pidx = pidx + 1;\n    }\n    if pct_n > 0 {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = psum / pct_n;\n    }\n");
        }
        if CMP_AL[fi] == 1 {
        cmp_s("    let pb: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let pz: i64 = 0;\n    while pz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[pz] = 0;\n        pz = pz + 1;\n    }\n    str_itoa_base(pb, ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", 10);\n    let pl: i64 = strlen(pb);\n    let pp: i64 = ");
        cmp_i(wd);
        cmp_s(" - pl - 1;\n    let pq: i64 = 0;\n    while pq < pp {\n        uc_set(cx + pq, y, ' ', fg, bg);\n        pq = pq + 1;\n    }\n    uc_text(cx + pp, y, pb, UC_CYAN, bg);\n    uc_set(cx + pp + pl, y, '%', UC_GREEN, bg);\n    cx = cx + ");
        cmp_i(wd);
        cmp_s(" + 2;\n");
        return 0;
        }
        cmp_s("    let pb: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let pz: i64 = 0;\n    while pz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[pz] = 0;\n        pz = pz + 1;\n    }\n    str_itoa_base(pb, ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", 10);\n    if strlen(pb) > ");
        cmp_i(wd);
        cmp_s(" { ");
        cmp_s(compo);
        cmp_s("_buf[");
        cmp_i(wd);
        cmp_s("] = 0;\n    }\n    uc_text(cx, y, pb, UC_CYAN, bg);\n    let pl: i64 = strlen(pb);\n    uc_set(cx + pl, y, '%', UC_GREEN, bg);\n");
        return 0;
    }
    if kind == 7 {
        if CMP_HS[fi] > 0 {
        cmp_s("    let hh: i64 = ");
        cmp_i(wd - 0);
        cmp_s(" - 0;\n    let hj: i64 = 0;\n    while hj < ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n {\n        let hv: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[hj];\n        let hq: i64 = (hv * ");
        cmp_i(6);
        cmp_s(") / 100;\n        let hr: i64 = 0;\n        while hr < ");
        cmp_i(6);
        cmp_s(" {\n            if hr < hq {\n                uc_set(cx + hj, y - hr, 9608, UC_YELLOW, bg);\n            }\n            hr = hr + 1;\n        }\n        hj = hj + 1;\n    }\n    cx = cx + ");
        cmp_i(wd);
        cmp_s(" + 2;\n");
        return 0;
        }
        cmp_s("    let sv: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(";\n    let sl: i64 = ");
        cmp_i(wd);
        cmp_s(" - 4;\n    let sq: i64 = (sv * sl) / 100;\n    let sj: i64 = 0;\n    while sj < sl {\n        if sj < sq {\n            uc_set(cx + sj, y, 9608, UC_YELLOW, bg);\n        } else {\n            uc_set(cx + sj, y, 9617, UC_WHITE, bg);\n        }\n        sj = sj + 1;\n    }\n    let sb: i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n    let sz: i64 = 0;\n    while sz < 64 {\n        ");
        cmp_s(compo);
        cmp_s("_buf[sz] = 0;\n        sz = sz + 1;\n    }\n    str_itoa_base(sb, sv, 10);\n    uc_text(cx + sl + 1, y, sb, UC_CYAN, bg);\n");
        return 0;
    }
    cmp_s("    let hf: i64 = &");
    cmp_s(compo);
    cmp_s("_buf;\n    let hz: i64 = 0;\n    while hz < 64 {\n        ");
    cmp_s(compo);
    cmp_s("_buf[hz] = 0;\n        hz = hz + 1;\n    }\n    str_itoa_base(hf, ");
    cmp_s(compo);
    cmp_c(95);
    cmp_s(fld);
    cmp_s(", 16);\n    uc_text(cx, y, hf, UC_CYAN, bg);\n");
    return 0;
}

fn cmp_row_field(compo: i64, fld: i64, kind: i64, wd: i64, col: i64, fi: i64) -> i64 {
    cmp_s("    uc_text(cx, y, \"");
    cmp_s(fld);
    cmp_s("\", UC_WHITE, bg);\n");
    cmp_s("    let l");
    cmp_i(fi);
    cmp_s(": i64 = strlen(\"");
    cmp_s(fld);
    cmp_s("\");\n    cx = cx + l");
    cmp_i(fi);
    cmp_s(" + 1;\n");
    if kind == 0 {
        if CMP_AL[fi] == 1 {
        cmp_s("    let v");
        cmp_i(fi);
        cmp_s(": i64 = strlen(&");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(");\n    let p");
        cmp_i(fi);
        cmp_s(": i64 = ");
        cmp_i(wd);
        cmp_s(" - v");
        cmp_i(fi);
        cmp_s(";\n    let q");
        cmp_i(fi);
        cmp_s(": i64 = 0;\n    while q");
        cmp_i(fi);
        cmp_s(" < p");
        cmp_i(fi);
        cmp_s(" {\n        uc_set(cx + q");
        cmp_i(fi);
        cmp_s(", y, ' ', fg, bg);\n        q");
        cmp_i(fi);
        cmp_s(" = q");
        cmp_i(fi);
        cmp_s(" + 1;\n    }\n    uc_text(cx + p");
        cmp_i(fi);
        cmp_s(", y, &");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", UC_YELLOW, bg);\n    cx = cx + ");
        cmp_i(wd);
        cmp_s(" + 2;\n");
        return 0;
        }
        cmp_s("    let tv");
        cmp_i(fi);
        cmp_s(": i64 = strlen(&");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(");\n    if tv");
        cmp_i(fi);
        cmp_s(" > ");
        cmp_i(wd);
        cmp_s(" {\n        let tb");
        cmp_i(fi);
        cmp_s(": i64 = &");
        cmp_s(compo);
        cmp_s("_buf;\n        let tz");
        cmp_i(fi);
        cmp_s(": i64 = 0;\n        while tz");
        cmp_i(fi);
        cmp_s(" < ");
        cmp_i(wd);
        cmp_s(" {\n            ");
        cmp_s(compo);
        cmp_s("_buf[tz");
        cmp_i(fi);
        cmp_s("] = load8(&");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" + tz");
        cmp_i(fi);
        cmp_s(");\n            tz");
        cmp_i(fi);
        cmp_s(" = tz");
        cmp_i(fi);
        cmp_s(" + 1;\n        }\n        ");
        cmp_s(compo);
        cmp_s("_buf[");
        cmp_i(wd);
        cmp_s("] = 0;\n        uc_text(cx, y, tb");
        cmp_i(fi);
        cmp_s(", UC_YELLOW, bg);\n    } else {\n        uc_text(cx, y, &");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", UC_YELLOW, bg);\n    }\n    let v");
        cmp_i(fi);
        cmp_s(": i64 = strlen(&");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(");\n    let p");
        cmp_i(fi);
        cmp_s(": i64 = ");
        cmp_i(wd);
        cmp_s(" - v");
        cmp_i(fi);
        cmp_s(";\n    let j");
        cmp_i(fi);
        cmp_s(": i64 = 0;\n    while j");
        cmp_i(fi);
        cmp_s(" < p");
        cmp_i(fi);
        cmp_s(" {\n        uc_set(cx + v");
        cmp_i(fi);
        cmp_s(" + j");
        cmp_i(fi);
        cmp_s(", y, ' ', fg, bg);\n        j");
        cmp_i(fi);
        cmp_s(" = j");
        cmp_i(fi);
        cmp_s(" + 1;\n    }\n");
    } else {
        if kind == 1 {
        if CMP_HS[fi] > 0 {
        cmp_s("    let nsum: i64 = 0;\n    let nct: i64 = ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_n;\n    let nidx: i64 = 0;\n    while nidx < nct {\n        nsum = nsum + ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s("_hist[nidx];\n        nidx = nidx + 1;\n    }\n    if nct > 0 {\n        ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = nsum / nct;\n    }\n");
        }
        if CMP_AL[fi] == 1 {
            cmp_s("    let b");
            cmp_i(fi);
            cmp_s(": i64 = &");
            cmp_s(compo);
            cmp_s("_buf;\n    let z");
            cmp_i(fi);
            cmp_s(": i64 = 0;\n    while z");
            cmp_i(fi);
            cmp_s(" < 64 {\n        ");
            cmp_s(compo);
            cmp_s("_buf[z");
            cmp_i(fi);
            cmp_s("] = 0;\n        z");
            cmp_i(fi);
            cmp_s(" = z");
            cmp_i(fi);
            cmp_s(" + 1;\n    }\n    str_itoa_base(b");
            cmp_i(fi);
            cmp_s(", ");
            cmp_s(compo);
            cmp_c(95);
            cmp_s(fld);
            cmp_s(", 10);\n    let v");
            cmp_i(fi);
            cmp_s(": i64 = strlen(b");
            cmp_i(fi);
            cmp_s(");\n    let p");
            cmp_i(fi);
            cmp_s(": i64 = ");
            cmp_i(wd);
            cmp_s(" - v");
            cmp_i(fi);
            cmp_s(";\n    let q");
            cmp_i(fi);
            cmp_s(": i64 = 0;\n    while q");
            cmp_i(fi);
            cmp_s(" < p");
            cmp_i(fi);
            cmp_s(" {\n        uc_set(cx + q");
            cmp_i(fi);
            cmp_s(", y, ' ', fg, bg);\n        q");
            cmp_i(fi);
            cmp_s(" = q");
            cmp_i(fi);
            cmp_s(" + 1;\n    }\n    uc_text(cx + p");
            cmp_i(fi);
            cmp_s(", y, b");
            cmp_i(fi);
            cmp_s(", UC_CYAN, bg);\n    cx = cx + ");
            cmp_i(wd);
            cmp_s(" + 2;\n");
            return 0;
        }
            cmp_s("    let b");
            cmp_i(fi);
            cmp_s(": i64 = &");
            cmp_s(compo);
            cmp_s("_buf;\n    let z");
            cmp_i(fi);
            cmp_s(": i64 = 0;\n    while z");
            cmp_i(fi);
            cmp_s(" < 64 {\n        ");
            cmp_s(compo);
            cmp_s("_buf[z");
            cmp_i(fi);
            cmp_s("] = 0;\n        z");
            cmp_i(fi);
            cmp_s(" = z");
            cmp_i(fi);
            cmp_s(" + 1;\n    }\n    str_itoa_base(b");
            cmp_i(fi);
            cmp_s(", ");
            cmp_s(compo);
            cmp_c(95);
            cmp_s(fld);
            cmp_s(", ");
            cmp_i(CMP_FM[fi]);
            cmp_s(");\n");
        if CMP_PX[fi] >= 0 {
        cmp_s("    uc_text(cx, y, \"");
        let pk: i64 = 0;
        let pc: i64 = 0;
        while load8(heap + O_STRS + CMP_PX[fi] + pk) != 0 {
            pc = load8(heap + O_STRS + CMP_PX[fi] + pk);
            if pc == 34 {
                cmp_c(92);
                cmp_c(34);
            } else {
                if pc == 92 {
                    cmp_c(92);
                    cmp_c(92);
                } else {
                    cmp_c(pc);
                }
            }
            pk = pk + 1;
        }
        cmp_s("\", UC_CYAN, bg);\n    cx = cx + strlen(\"");
        let qk: i64 = 0;
        let qc: i64 = 0;
        while load8(heap + O_STRS + CMP_PX[fi] + qk) != 0 {
            qc = load8(heap + O_STRS + CMP_PX[fi] + qk);
            if qc == 34 {
                cmp_c(92);
                cmp_c(34);
            } else {
                if qc == 92 {
                    cmp_c(92);
                    cmp_c(92);
                } else {
                    cmp_c(qc);
                }
            }
            qk = qk + 1;
        }
        cmp_s("\");\n    ");
        }
        cmp_s("    if strlen(b");
            cmp_i(fi);
            cmp_s(") > ");
            cmp_i(wd);
            cmp_s(" { ");
            cmp_s(compo);
            cmp_s("_buf[");
            cmp_i(wd);
            cmp_s("] = 0;\n    }\n    uc_text(cx, y, b");
            cmp_i(fi);
            cmp_s(", UC_CYAN, bg);\n");
        cmp_s("    let v");
            cmp_i(fi);
            cmp_s(": i64 = strlen(b");
            cmp_i(fi);
            cmp_s(");\n    let p");
            cmp_i(fi);
            cmp_s(": i64 = ");
            cmp_i(wd);
            cmp_s(" - v");
            cmp_i(fi);
            cmp_s(";\n    let j");
            cmp_i(fi);
            cmp_s(": i64 = 0;\n    while j");
            cmp_i(fi);
            cmp_s(" < p");
            cmp_i(fi);
            cmp_s(" {\n        uc_set(cx + v");
            cmp_i(fi);
            cmp_s(" + j");
            cmp_i(fi);
            cmp_s(", y, ' ', fg, bg);\n        j");
            cmp_i(fi);
            cmp_s(" = j");
            cmp_i(fi);
            cmp_s(" + 1;\n    }\n");
        } else {
            if kind == 2 {
            cmp_s("    let st");
            cmp_i(fi);
            cmp_s(": i64 = ");
            cmp_s(compo);
            cmp_c(95);
            cmp_s(fld);
            cmp_s(";\n    if st");
            cmp_i(fi);
            cmp_s(" == 0 {\n        uc_text(cx, y, \"OFF\", UC_WHITE, bg);\n    } else {\n        if st");
            cmp_i(fi);
            cmp_s(" == 1 {\n            uc_text(cx, y, \"RUN\", UC_GREEN, bg);\n        } else {\n            if st");
            cmp_i(fi);
            cmp_s(" == 2 {\n                uc_text(cx, y, \"OK\", UC_CYAN, bg);\n            } else {\n                uc_text(cx, y, \"ERR\", UC_RED, bg);\n            }\n        }\n    }\n    let v");
            cmp_i(fi);
            cmp_s(": i64 = 4;\n    let p");
            cmp_i(fi);
            cmp_s(": i64 = ");
            cmp_i(wd);
            cmp_s(" - 4;\n    let j");
            cmp_i(fi);
            cmp_s(": i64 = 0;\n    while j");
            cmp_i(fi);
            cmp_s(" < p");
            cmp_i(fi);
            cmp_s(" {\n        uc_set(cx + 4 + j");
            cmp_i(fi);
            cmp_s(", y, ' ', fg, bg);\n        j");
            cmp_i(fi);
            cmp_s(" = j");
            cmp_i(fi);
            cmp_s(" + 1;\n    }\n");
        } else {
            cmp_row_ext(compo, fld, kind, wd, col, fi);
        }
        }
        if CMP_SX[fi] >= 0 && CMP_TY[fi] == 1 {
        cmp_s("    uc_text(cx + strlen(&");
        cmp_s(compo);
        cmp_s("_buf), y, \"");
        let sk: i64 = 0;
        let sc: i64 = 0;
        while load8(heap + O_STRS + CMP_SX[fi] + sk) != 0 {
            sc = load8(heap + O_STRS + CMP_SX[fi] + sk);
            if sc == 34 {
                cmp_c(92);
                cmp_c(34);
            } else {
                if sc == 92 {
                    cmp_c(92);
                    cmp_c(92);
                } else {
                    cmp_c(sc);
                }
            }
            sk = sk + 1;
        }
        cmp_s("\", UC_WHITE, bg);\n");
        }
    }
    cmp_s("    cx = cx + ");
    cmp_i(wd);
    cmp_s(" + 2;\n");
    return 0;
}

# 生成 head 函数里一个字段的表头代码
fn cmp_head_field(fld: i64, fi: i64) -> i64 {
    cmp_s("    uc_text(cx, y, \"");
    cmp_s(fld);
    cmp_s("\", UC_WHITE, bg);\n    let l");
    cmp_i(fi);
    cmp_s(": i64 = strlen(\"");
    cmp_s(fld);
    cmp_s("\");\n    let j");
    cmp_i(fi);
    cmp_s(": i64 = 0;\n    while j");
    cmp_i(fi);
    cmp_s(" < 2 {\n        uc_set(cx + l");
    cmp_i(fi);
    cmp_s(" + j");
    cmp_i(fi);
    cmp_s(", y, '-', UC_WHITE, bg);\n        j");
    cmp_i(fi);
    cmp_s(" = j");
    cmp_i(fi);
    cmp_s(" + 1;\n    }\n    cx = cx + l");
    cmp_i(fi);
    cmp_s(" + 4;\n");
    return 0;
}

# 解析 component 声明并展开
fn parse_component() -> i64 {
    next_token();
    if gv(K_TKIND) != 1 { return syntax_error(); }
    let cname: i64 = intern(tokbuf());
    let compo: i64 = heap + O_NAMES + cname;
    next_token();
    let nrows: i64 = 0;
    if tok_is("rows") == 1 {
        next_token();
        if gv(K_TKIND) == 2 {
            nrows = gv(K_TIVAL);
            next_token();
        } else {
            if gv(K_TKIND) == 1 {
                # const 名做 rows（v1.982）
                let rsi: i64 = sym_lookup(tokbuf());
                if rsi >= 0 {
                    if load64(heap + O_SK + rsi * 8) == 4 {
                        nrows = load64(heap + O_SCV + rsi * 8);
                        next_token();
                    } else {
                        return syntax_error();
                    }
                } else {
                    return syntax_error();
                }
            } else {
                return syntax_error();
            }
        }
    }
    let sep: i64 = 0;
    if tok_is("sep") == 1 {
        next_token();
        sep = 1;
    }
    let ttl: i64 = -1;
    if tok_is("title") == 1 {
        next_token();
        if gv(K_TKIND) != 3 { return syntax_error(); }
        ttl = gv(K_STROFF);
        next_token();
    }
    if tok_is("{") == 0 { return syntax_error(); }
    next_token();
    CMP_NF = 0;
    while tok_is("}") == 0 {
        if gv(K_TKIND) != 1 { return syntax_error(); }
        let fname: i64 = intern(tokbuf());
        let fld: i64 = heap + O_NAMES + fname;
        next_token();
        if tok_is(":") == 0 { return syntax_error(); }
        next_token();
        let kind: i64 = 0;
        if tok_is("text") == 1 {
            kind = 0;
        } else {
            if tok_is("num") == 1 {
                kind = 1;
            } else {
                if tok_is("state") == 1 {
                    kind = 2;
                } else {
                    if tok_is("bar") == 1 {
                        kind = 3;
                    } else {
                        if tok_is("gauge") == 1 {
                            kind = 4;
                        } else {
                            if tok_is("kv") == 1 {
                                kind = 5;
                            } else {
                                if tok_is("hex") == 1 {
                                    kind = 6;
                                } else {
                                    if tok_is("spark") == 1 {
                                        kind = 7;
                                    } else {
                                        if tok_is("pct") == 1 {
                                            kind = 8;
                                        } else {
                                            if tok_is("delta") == 1 {
                                                kind = 9;
                                            } else {
                                                return syntax_error();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        next_token();
        let width: i64 = 10;
        if tok_is("width") == 1 {
            next_token();
            if gv(K_TKIND) == 2 {
                width = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    # const 名做 width（v1.983）
                    let wsi: i64 = sym_lookup(tokbuf());
                    if wsi >= 0 {
                        if load64(heap + O_SK + wsi * 8) == 4 {
                            width = load64(heap + O_SCV + wsi * 8);
                            next_token();
                        } else {
                            return syntax_error();
                        }
                    } else {
                        return syntax_error();
                    }
                } else {
                    return syntax_error();
                }
            }
        }
        let align: i64 = 0;
        if tok_is("align") == 1 {
            next_token();
            if tok_is("right") == 1 {
                align = 1;
            } else {
                if tok_is("left") == 1 {
                    align = 0;
                } else {
                    return syntax_error();
                }
            }
            next_token();
        }
        let hidden: i64 = 0;
        if tok_is("hidden") == 1 {
            next_token();
            hidden = 1;
        }
        let hist: i64 = 0;
        if tok_is("hist") == 1 {
            next_token();
            if gv(K_TKIND) == 2 {
                hist = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    # const 名做 hist（v1.997）
                    let hsi: i64 = sym_lookup(tokbuf());
                    if hsi >= 0 {
                        if load64(heap + O_SK + hsi * 8) == 4 {
                            hist = load64(heap + O_SCV + hsi * 8);
                            next_token();
                        } else {
                            return syntax_error();
                        }
                    } else {
                        return syntax_error();
                    }
                } else {
                    return syntax_error();
                }
            }
        }
        let cbname: i64 = -1;
        if tok_is("on_click") == 1 {
            next_token();
            if gv(K_TKIND) != 1 { return syntax_error(); }
            cbname = intern(tokbuf());
            next_token();
        }
        let hovname: i64 = -1;
        if tok_is("on_hover") == 1 {
            next_token();
            if gv(K_TKIND) != 1 { return syntax_error(); }
            hovname = intern(tokbuf());
            next_token();
        }
        let vmin: i64 = 0;
        let vmax: i64 = 0;
        if tok_is("min") == 1 {
            next_token();
            if gv(K_TKIND) == 2 {
                vmin = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    # const 名做 min（v1.997）
                    let nsi: i64 = sym_lookup(tokbuf());
                    if nsi >= 0 {
                        if load64(heap + O_SK + nsi * 8) == 4 {
                            vmin = load64(heap + O_SCV + nsi * 8);
                            next_token();
                        } else {
                            return syntax_error();
                        }
                    } else {
                        return syntax_error();
                    }
                } else {
                    return syntax_error();
                }
            }
        }
        if tok_is("max") == 1 {
            next_token();
            if gv(K_TKIND) == 2 {
                vmax = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    # const 名做 max（v1.996）
                    let msi: i64 = sym_lookup(tokbuf());
                    if msi >= 0 {
                        if load64(heap + O_SK + msi * 8) == 4 {
                            vmax = load64(heap + O_SCV + msi * 8);
                            next_token();
                        } else {
                            return syntax_error();
                        }
                    } else {
                        return syntax_error();
                    }
                } else {
                    return syntax_error();
                }
            }
        }
        let pfx: i64 = -1;
        if tok_is("prefix") == 1 {
            next_token();
            if gv(K_TKIND) != 3 { return syntax_error(); }
            pfx = gv(K_STROFF);
            next_token();
        }
        let sfx: i64 = -1;
        if tok_is("suffix") == 1 {
            next_token();
            if gv(K_TKIND) != 3 { return syntax_error(); }
            sfx = gv(K_STROFF);
            next_token();
        }
        let dflt: i64 = 0;
        let dflts: i64 = -1;
        if tok_is("default") == 1 {
            next_token();
            if gv(K_TKIND) == 2 {
                dflt = gv(K_TIVAL);
                next_token();
            } else {
                if gv(K_TKIND) == 3 {
                    dflts = gv(K_STROFF);
                    next_token();
                } else {
                    return syntax_error();
                }
            }
        }
        let fmtd: i64 = 10;
        if tok_is("fmt") == 1 {
            next_token();
            if tok_is("hex") == 1 {
                fmtd = 16;
            } else {
                if tok_is("bin") == 1 {
                    fmtd = 2;
                } else {
                    if tok_is("oct") == 1 {
                        fmtd = 8;
                    } else {
                        return syntax_error();
                    }
                }
            }
            next_token();
        }
        if tok_is(";") == 0 { return syntax_error(); }
        next_token();
        let nf: i64 = CMP_NF;
        if nf >= 64 { return err_at2("too many component fields (limit 64)", gv(K_LINE), gv(K_COL)); }
        CMP_TY[nf] = kind;
        CMP_WD[nf] = width;
        CMP_AL[nf] = align;
        CMP_HD[nf] = hidden;
        CMP_HS[nf] = hist;
        CMP_CB[nf] = cbname;
        CMP_HB[nf] = hovname;
        CMP_LO[nf] = vmin;
        CMP_PX[nf] = pfx;
        CMP_SX[nf] = sfx;
        CMP_DV[nf] = dflt;
        CMP_DS[nf] = dflts;
        CMP_FM[nf] = fmtd;
        CMP_HI[nf] = vmax;
        if kind == 0 { CMP_CC[nf] = 3; }
        else { if kind == 1 { CMP_CC[nf] = 6; } else { if kind == 2 { CMP_CC[nf] = 2; } else { if kind == 3 { CMP_CC[nf] = 9; } else { if kind == 4 { CMP_CC[nf] = 11; } else { if kind == 5 { CMP_CC[nf] = 5; } else { if kind == 6 { CMP_CC[nf] = 7; } else { if kind == 7 { CMP_CC[nf] = 9; } else { if kind == 8 { CMP_CC[nf] = 6; } else { CMP_CC[nf] = 9; } } } } } } } } }
        CMP_FN[nf] = fname;
        CMP_NF = nf + 1;
    }
    if tok_is("}") == 0 { return syntax_error(); }
    # 生成展开代码到 O_GENBUF
    CMP_P = 0;
    let nf2: i64 = CMP_NF;
    let fi: i64 = 0;
    while fi < nf2 {
        cmp_field_var(compo, heap + O_NAMES + CMP_FN[fi], CMP_TY[fi]);
        fi = fi + 1;
    }
    cmp_s("var ");
    cmp_s(compo);
    cmp_s("_buf: [64] byte = 0;\n");
    fi = 0;
    while fi < nf2 {
        if CMP_HS[fi] > 0 {
        cmp_s("var ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("_hist: [");
        cmp_i(CMP_HS[fi]);
        cmp_s("] i64 = 0;\n");
        cmp_s("var ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("_n: i64 = 0;\n");
        }
        cmp_setter(compo, heap + O_NAMES + CMP_FN[fi], CMP_TY[fi], CMP_HS[fi], CMP_LO[fi], CMP_HI[fi]);
        if CMP_CB[fi] >= 0 {
        cmp_s("fn ");
        cmp_s(compo);
        cmp_s("_click_");
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("() -> i64 {\n    call1(&");
        cmp_s(heap + O_NAMES + CMP_CB[fi]);
        cmp_s(", ");
        if CMP_TY[fi] == 0 {
        cmp_c(38);   # &
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        } else {
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        }
        cmp_s(");\n    return 0;\n}\n");
        }
        if CMP_HB[fi] >= 0 {
        cmp_s("fn ");
        cmp_s(compo);
        cmp_s("_hover_");
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("() -> i64 {\n    call1(&");
        cmp_s(heap + O_NAMES + CMP_HB[fi]);
        cmp_s(", ");
        if CMP_TY[fi] == 0 {
        cmp_c(38);
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        } else {
        cmp_s(compo);
        cmp_c(95);
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        }
        cmp_s(");\n    return 0;\n}\n");
        }
        fi = fi + 1;
    }
    # v1.1052: _row 自动初始化 —— 首次调用 _row 时自动跑一次 _init（default 生效）
    cmp_s("var ");
    cmp_s(compo);
    cmp_s("_auto: i64 = 0;\n");
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_row(x: i64, y: i64, fg: i64, bg: i64) -> i64 {\n    let cx: i64 = x;\n");
    cmp_s("    if ");
    cmp_s(compo);
    cmp_s("_auto == 0 { ");
    cmp_s(compo);
    cmp_s("_init(); ");
    cmp_s(compo);
    cmp_s("_auto = 1; }\n");
    fi = 0;
    while fi < nf2 {
        if CMP_HD[fi] == 1 {
        } else {
        cmp_row_field(compo, heap + O_NAMES + CMP_FN[fi], CMP_TY[fi], CMP_WD[fi], CMP_CC[fi], fi);
        }
        fi = fi + 1;
    }
    cmp_s("    return 0;\n}\n");
    if nrows > 0 {
    if ttl >= 0 {
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_grid(x: i64, y: i64, fg: i64, bg: i64) -> i64 {\n    uc_text(x, y, \"");
    let tk: i64 = 0;
    let tc: i64 = 0;
    while load8(heap + O_STRS + ttl + tk) != 0 {
        tc = load8(heap + O_STRS + ttl + tk);
        if tc == 34 {
            cmp_c(92);
            cmp_c(34);
        } else {
            if tc == 92 {
                cmp_c(92);
                cmp_c(92);
            } else {
                cmp_c(tc);
            }
        }
        tk = tk + 1;
    }
    cmp_s("\", UC_WHITE, bg);\n");
    cmp_s("    let gi: i64 = 0;\n    while gi < ");
    cmp_i(nrows);
    cmp_s(" {\n        ");
    cmp_s(compo);
    cmp_s("_row(x, y + gi * 2 + 2, fg, bg);\n");
    if sep == 1 {
    cmp_s("        if gi < ");
    cmp_i(nrows - 1);
    cmp_s(" {\n            let sj: i64 = 0;\n            while sj < 40 {\n                uc_set(x + sj, y + gi * 2 + 3, 45, UC_WHITE, bg);\n                sj = sj + 1;\n            }\n        }\n");
    }
    cmp_s("        gi = gi + 1;\n    }\n    return 0;\n}\n");
    } else {
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_grid(x: i64, y: i64, fg: i64, bg: i64) -> i64 {\n    let gi: i64 = 0;\n    while gi < ");
    cmp_i(nrows);
    cmp_s(" {\n        ");
    cmp_s(compo);
    cmp_s("_row(x, y + gi * 2, fg, bg);\n");
    if sep == 1 {
    cmp_s("        if gi < ");
    cmp_i(nrows - 1);
    cmp_s(" {\n            let sj: i64 = 0;\n            while sj < 40 {\n                uc_set(x + sj, y + gi * 2 + 1, 45, UC_WHITE, bg);\n                sj = sj + 1;\n            }\n        }\n");
    }
    cmp_s("        gi = gi + 1;\n    }\n    return 0;\n}\n");
    }
    }
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_init() -> i64 {\n");
    fi = 0;
    while fi < nf2 {
        if CMP_DS[fi] >= 0 {
        cmp_s("    ");
        cmp_s(compo);
        cmp_s("_set_");
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("(\"");
        let dk: i64 = 0;
        let dc: i64 = 0;
        while load8(heap + O_STRS + CMP_DS[fi] + dk) != 0 {
            dc = load8(heap + O_STRS + CMP_DS[fi] + dk);
            if dc == 34 {
                cmp_c(92);
                cmp_c(34);
            } else {
                if dc == 92 {
                    cmp_c(92);
                    cmp_c(92);
                } else {
                    cmp_c(dc);
                }
            }
            dk = dk + 1;
        }
        cmp_s("\");\n");
        } else {
            if CMP_DV[fi] != 0 {
        cmp_s("    ");
        cmp_s(compo);
        cmp_s("_set_");
        cmp_s(heap + O_NAMES + CMP_FN[fi]);
        cmp_s("(");
        cmp_i(CMP_DV[fi]);
        cmp_s(");\n");
        }
        }
        fi = fi + 1;
    }
    cmp_s("    return 0;\n}\n");
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_head(x: i64, y: i64, fg: i64, bg: i64) -> i64 {\n    let cx: i64 = x;\n");
    fi = 0;
    while fi < nf2 {
        cmp_head_field(heap + O_NAMES + CMP_FN[fi], fi);
        fi = fi + 1;
    }
    cmp_s("    return 0;\n}\n");
    cmp_c(0);
    let ob: i64 = gv(K_SRCBASE);
    let ol: i64 = gv(K_SRCLEN);
    let op: i64 = gv(K_POS);
    let oln: i64 = gv(K_LINE);
    let oc: i64 = gv(K_COL);
    let opos: i64 = gv(K_CPOS);
    let len: i64 = CMP_P - 1;
    let fb:  i64 = gv(K_FNBASE);
    let of:  i64 = gv(K_CUROFF);
    let fp:  i64 = gv(K_FPATCH);
    let hr:  i64 = gv(K_HASRET);
    let dp:  i64 = gv(K_DEPTH);
    let lt:  i64 = gv(K_LTOP);
    let cb:  i64 = gv(K_CRBX);
    let cf:  i64 = gv(K_CURFN);
    let nd:  i64 = gv(K_NDF);
    let el:  i64 = load64(heap + O_ERRLAB);
    sv(K_SRCBASE, O_GENBUF);
    sv(K_SRCLEN, len);
    sv(K_POS, 0);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    parse_program();
    sv(K_SRCBASE, ob);
    sv(K_SRCLEN, ol);
    sv(K_POS, op);
    sv(K_LINE, oln);
    sv(K_COL, oc);
    sv(K_CPOS, opos);
    sv(K_FNBASE, fb);
    sv(K_CUROFF, of);
    sv(K_FPATCH, fp);
    sv(K_HASRET, hr);
    sv(K_DEPTH, dp);
    sv(K_LTOP, lt);
    sv(K_CRBX, cb);
    sv(K_CURFN, cf);
    sv(K_NDF, nd);
    store64(heap + O_ERRLAB, el);
    next_token();
    return 0;
}