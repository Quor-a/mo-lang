# ==========================================================================
#  compiler.mo  --  墨语言编译器（用墨语言自身实现）
#  读取 .mo 源码，输出 ELF64 静态可执行文件（x86-64 / Linux）
# ==========================================================================

# ---------------------------- 内存布局 ----------------------------
var heap:  i64 = 0;
var INPATH: i64 = 0;
var O_SRC: i64 = 0;
var O_CODE: i64 = 4194304;
var O_DATA: i64 = 95000000;  # 输出数据段缓冲。原先 5242880，与 O_NAMES 只隔 1MB，
                             # 全局数据 >1MB 会**静默覆盖名字区**（符号名被冲掉，
                             # 表现为诡异的 no main function / undefined symbol，
                             # docs/backend_portability.md §五.1 早就记录了却一直没修）。
                             # 移到 O_MODS(91MB) 之后、堆顶之前，容量 10485760（10MB），
                             # dbyte 里有响亮的溢出检查。
var O_DCAP: i64 = 10485760;  # 数据段缓冲上限（与 dbyte 的检查保持一致）
var O_NAMES: i64 = 6291456;
var O_SYN: i64 = 6815744;
var K_WARN:   i64 = 464;   # 0=关闭未使用变量警告（有误报，见 docs）
var O_SU: i64 = 9000000;   # 符号是否被读过（未使用检查，见 K_WARN）
var O_SRT: i64 = 9020000;   # 函数返回类型（O_SU 之后 2 万字节处，够 2048 个符号）
var O_SK: i64 = 6832128;
var O_SA: i64 = 6848512;
var O_SP: i64 = 6864896;
var O_SD: i64 = 6881280;
var O_FP: i64 = 6897664;
var O_FS: i64 = 7028736;
var O_JP: i64 = 7160800;
var O_JL: i64 = 7291872;
var O_LB: i64 = 92000000;   # label 地址表。原 7324640 与 O_SCAL(7357408) 只隔 32768 字节
                             # (=4096 条目)。NLAB_MAX 提到 16384 后 O_LB 写越界到 O_SCAL
                             # 破坏 token 缓冲 → 报错位置异常/文件末尾 syntax error。
                             # 移到主堆高区 92MB，容量 16384*8=131072 字节。
var O_SCAL: i64 = 7357408;
# 接口（interface）与虚函数表：放在 O_SRT 之后到 O_FILES 之间的空档里
var O_IFN: i64 = 10000000;   # 接口名（指向 O_IFNB 里名字串的指针）
var O_IFSI: i64 = 10000256;   # 接口对应的结构体索引
var O_IFNM: i64 = 10000512;   # 方法个数
var O_IFMN: i64 = 10000768;   # 方法名（intern），ifidx*128 + midx*8
var O_IFNB: i64 = 10004864;   # 接口名字符串缓冲，每个 32 字节
var O_VTD: i64 = 10005888;   # vtable 在数据段里的偏移
var O_VTN: i64 = 10006144;   # vtable 长度
var O_VTS: i64 = 10006400;   # vtable 各项的函数符号：vtidx*128 + k*8
# 泛型（generic）—— 单态化。放在 88MB 处，远离会增长的字符串池(O_STRS)。
# 主堆 96MB，这里用掉约 700KB + 1MB 临时区，安全。
var O_GN: i64 = 88000000;   # generic 名（指针）
var O_GNT: i64 = 88000256;   # 类型参数个数
var O_GTP: i64 = 88000512;   # 类型参数名（指针）：gidx*128 + tidx*8
var O_GNB: i64 = 88004608;   # 名字缓冲：gidx*32
var O_GTB: i64 = 88005632;   # 类型参数名缓冲：gidx*128 + tidx*32
var O_GBODY: i64 = 88009728;   # 函数体源码（从 '(' 起）：gidx*8192
var O_GAB: i64 = 88271872;   # instantiate 实参类型名：tidx*32
# O_GAB 结束于 88271872 + 4*32，以下三块在其后，仍远小于 O_GENBUF(89000000)
var O_GBC: i64 = 88272896;   # 每个类型参数的 bound 个数：gidx*128 + tidx*8
var O_GBB: i64 = 88276992;   # bound 的 interface 索引：gidx*512 + tidx*128 + bidx*8
var O_BMSG: i64 = 88293376;   # 错误消息拼接缓冲
var O_GENBUF: i64 = 89000000;  # 展开出的临时源码（1MB）
var O_IFMB: i64 = 10010496;   # 接口方法名字符串缓冲：ifidx*512 + midx*32
# ---- 泛型 trait bound ----
# 紧接 O_IFMB 之后（10010496 + 32*512 = 10026880），下一个区域是 O_FILES(12582912)，
# 中间有 2.5MB 空档。每一块都按「32 条 × 每项宽度」算过，不越界。
var O_VTK: i64 = 10026880;   # impl 对应的 interface 索引：vtidx*8
var O_VTT: i64 = 10027136;   # impl 对应的类型名（指针）：vtidx*8
var O_VTTB: i64 = 10027392;   # impl 类型名字符串缓冲：vtidx*32
var O_BCI: i64 = 10028416;   # 待检查的 bound：interface 索引，n*8
var O_BCL: i64 = 10028928;   # 待检查项：instantiate 所在行
var O_BCC: i64 = 10029440;   # 待检查项：instantiate 所在列
var O_BCT: i64 = 10029952;   # 待检查项：类型名（指针），n*8
var O_BCTB: i64 = 10030464;   # 待检查项：类型名字符串缓冲，n*32
var O_FILES: i64 = 12582912;
var O_STRS: i64 = 29360128;   # O_FILES 之后留 16MB：32 个文件 × 512KB
# 结构体表：最多 32 个结构体，每个最多 32 个字段
var O_STN: i64 = 8388608;    # 结构体名（intern 偏移）
var O_STF: i64 = 8388864;    # 字段个数
var O_STFLD: i64 = 8389120;    # 字段名 id：idx = si*32 + fi
var O_STFT: i64 = 8404992;    # 字段类型 id：0=i64，>=1 为结构体索引+1
var O_STY: i64 = 8420864;    # 变量类型：0=i64/数组，>=1 为结构体索引+1
var O_IMP: i64 = 8437760;    # 已导入文件路径（intern 偏移），用于去重与环检测
# 类型表：最多 512 个类型
var O_TK: i64 = 8445952;    # kind: 0=int 1=void 2=struct 3=array 4=ptr
var O_TA: i64 = 8450048;    # aux1: si(结构体) / 元素或指向类型
var O_TB: i64 = 8454144;    # aux2: 数组元素个数
var O_FRT: i64 = 8458240;    # 函数返回类型 id
var O_FPT: i64 = 8462336;    # 形参类型：fidx*8 + pi
# 方法表：最多 512 个（类名 intern / 方法名 intern / 函数符号）
#
# 地址必须落在 O_FPT 之后、O_SU(9000000) 之前的空档里。
# 第一版放在 8466432，正好压在 O_FPT 的区域上（形参类型表 fidx*8+pi，
# 最多 2048 个函数 → 131072 字节），于是注册方法会**覆盖形参类型**，
# 表现为第二个方法一调用就崩、甚至报错说方法未定义。
var O_MCLS: i64 = 8600000;
var O_MNAM: i64 = 8604096;
var O_MSYM: i64 = 8608192;
# 调试信息专用缓冲（都在 O_STRS 之后，堆空间充裕）
# 调试数据放在主堆之后单独申请的一块内存里（DBG 为基址，下列为相对偏移）。
# 早先直接放在 heap + 大偏移处，结果被字符串池覆盖——行号表读出来是字符串内容。
# 单独申请能彻底避开与主堆各区域的冲突。
var DBG:     i64 = 0;
var O_LM:    i64 = 0;          # 行号表：每条 16 字节 (code_len, line)
# 行号表每条记录**属于哪个源文件**（1 字节/条，文件下标 < 32）。
#
# 为什么不把记录扩成 24 字节：O_LM 只有 1MB，60000 条 × 16 = 960000
# 已经贴着上限，扩成 24 字节必然越界写到 O_DBG。单独一张 1 字节表
# 只要 60000 字节，放在 O_SOF 之后到 DBG 末尾的空档里。
var O_LMF: i64 = 8320000;
# 源文件路径表（文件下标 -> 路径字符串），32 × 256 字节。
var O_FNM: i64 = 8388608;
var O_DBG:   i64 = 1048576;    # DWARF 数据缓冲（各 section 分段使用）
var O_SHSTR: i64 = 2097152;    # section 名字符串表
var O_SHDR:  i64 = 2098176;    # section header 表
# -g 调试用的两张表。放在 3MB / 4MB 处，DBG 缓冲区已扩到 8MB，
# 与上面各区域都不重叠。
#   O_DF  函数表，每条 32 字节：name, low_pc, high_pc, decl_line
#   O_DV  局部变量表，每条 32 字节：name, rbp_off, decl_line, func_idx
#
# 为什么需要它们：局部变量**不能**从符号表推导 —— parse_func 结束时
# 有 `sv(K_NSYM, ra)` 把符号表回滚到进入时的位置，局部变量全被丢弃。
# 所以必须在解析时另记一份。
var O_DF:    i64 = 3145728;
var O_DV:    i64 = 4194304;
# .debug_frame 数据（DBG 内偏移 5MB 处，8MB 缓冲区内安全）
var O_DFR:   i64 = 5242880;
# 类型 DIE 偏移表（ty_id -> .debug_info 内偏移），每条 16 字节。
# 为什么需要：同一个类型（比如 Point）会被多个变量用到，
# 而 DWARF 里类型 DIE 只在**第一次**生成，之后用 ref4 指向它。
# 不缓存就会为每个变量重复生成一份结构体 DIE。
var O_DTY: i64 = 6291456;
# C FFI 外部调用点表（DBG 内 7MB 处）：每条 16 字节 (code_off, sym_index)
var O_XC: i64 = 7340032;
# extern 符号去重后的索引表（DBG 内 7.5MB 处）：每条 8 字节 (sym_index)
var O_XS: i64 = 7864320;
# 每条外部重定位的类型（1 = R_X86_64_64 取地址，4 = R_X86_64_PLT32 调用）
#
# 🔴 第一版写 8388608 —— **正好是 DBG 缓冲区（8MB）之后的第一个字节**，
#    越界写 1 字节就段错误。而且每个 -c 程序都会触发（启动代码里
#    自动生成对 exit 的 extern 调用），表现为"加个全局变量就崩"，
#    很容易误判成全局变量的问题。
#    可用区间：O_XS 之后（7872512）到 DBG 末尾（8388608）。
var O_XR: i64 = 8000000;
# ---- -shared：全局变量地址重定位表 ----
# .so 加载基址随机，movabs 里的绝对地址填了也没用 —— 必须交给 ld
# 做 R_X86_64_RELATIVE 重定位（加载时填 base + addend）。
#    O_GVP: 立即数在 .text 中的位置      O_GVA: 数据段内偏移
#    O_GVN: 条数                          O_SOF: 是否 -shared
# 都在 DBG(8MB) 内，8100000/8200000/8300000/8300008 互不重叠。
var O_GVP: i64 = 8100000;
var O_GVA: i64 = 8200000;
var O_GVN: i64 = 8300000;
var O_SOF: i64 = 8300008;

# ---------------------------- 标量槽 ----------------------------
var K_SRCLEN: i64 = 0;
var K_POS:    i64 = 8;
var K_TOKPOS: i64 = 16;
var K_CLEN:   i64 = 24;
var K_DLEN:   i64 = 32;
var K_NLEN:   i64 = 40;
var K_TKIND:  i64 = 48;
var K_TIVAL:  i64 = 56;
var K_TFLT:   i64 = 400;    # 该数字 token 是否含小数点（浮点字面量）
var K_TFDIG:  i64 = 408;    # 小数部分的数字值（如 3.14 → 14）
var K_TFDIGN: i64 = 416;    # 浮点字面量的十进制指数 k（值 = K_TFDIG / 10^k）
var FSTICKY: i64 = 0;       # 浮点字面量：被截掉的低位里是否有非零数字（参与平局判定）
# ---- enum 表（编译期常量）----
#
# 🔴 地址第一版选错了（7110656 起），**压在 O_JP(7160800) 和
#    O_JL(7291872) 上** —— 跳转回填表被 enum 常量覆盖，
#    症状是编译任何带 enum 的程序直接段错误。
#    这里挪到 O_MSYM 之后、O_SU 之前的空档（8612288 ~ 9000000）。
#
# 🔴 另一个更隐蔽的错误：`sv(O_ECNT, ...)` 把**堆地址**当成了
#    **状态槽**（gv/sv 的槽空间只有几百）。越界写 → 段错误。
#    计数必须用 K_ 槽（小整数），数组才用 O_ 大地址。
# 🔴 第四处错误：7400000 看着在 "O_SCAL 之后的空档"，
#    其实 **O_SCAL 是一个大区域**（7357408 ~ O_STN 8388608，约 1MB），
#    enum 数组落在它**内部**，把 scratch / 槽区之后的内容冲掉了。
#    真正的空档在 O_MSYM(8608192+4096) 之后、O_SU(9000000) 之前。
var O_ENAME: i64 = 8700000;    # 512 × 8 = 4096
var O_ECNAME: i64 = 8704096;
var O_EVAL: i64 = 8708192;
# 计数也用**独立地址**，不用 gv/sv 槽。
#
# 🔴 为什么：槽区（heap+O_SCAL+k，k 是**字节偏移**）里混着
#    scratch1/2/3 和各种名字缓冲区（400/700/1000/1400/1600/1700/
#    1800/3000 ...），**没有分配器**，选哪个都可能踩到别人。
#    调试时为此付出过整轮代价。计数这种"全局标量"用独立地址最稳。
var O_ECNT: i64 = 8712288;
# 当前函数的"错误出口"标签号（-1 = 尚未分配）。同样用独立地址。
var O_ERRLAB: i64 = 8712304;
# 数组字面量 [1,2,3] 的元素值（最多 512 个）。放在 O_ENAME 区之后。
var O_LSTV: i64 = 8720000;
var O_NENUM: i64 = 8712296;
# 外层函数符号表基线栈：EBS[d] = 第 d 层函数的第一个局部符号下标。
# 深层闭包靠它算出「这个符号属于往上第几层」，从而决定沿静态链走几次
# [rbp]。深度上限 16，16 × 8 = 128 字节（O_LSTV 之后，与其不重叠）。
var O_EBS: i64 = 8724096;
# 当前嵌套深度也存独立地址（与 O_EBS 相邻，128 字节之后）。
# 🔴 依据：K_FNBASE 槽（2408）已被实测证明会被名字缓冲区覆盖（见 cap_depth
#    里的注释），而 K_NEST 槽就在它前面 8 字节 —— 同一个风险。深度一旦被
#    写坏，cap_depth 的层数全错，且**不报错**。
var O_NEST: i64 = 8724224;
# 🔴 第三处错误：槽偏移 488 / 496 **落在 scratch1 的缓冲区里**
#    （scratch1 = O_SCAL+400，scratch2 = O_SCAL+700）。
#    写 K_ECNT 会把 scratch1 里的名字冲掉，读回来是字符串字节 ——
#    于是循环次数变成天文数字，越界后段错误。
#    槽区 400~488 已用（K_TFLT/TFDIG/TFDIGN/...），scratch 从 400 起，
#    所以稳妥的做法是**跳过整个 scratch 区**。现有偏移用到 3000
#    （1400/1600/1700/1800/3000 都是名字缓冲区），这里取 4000 / 4008 ——
#    但**每次新增都要重新核对**，这正是"槽区是裸偏移、没有分配器"的代价。

var K_NSYM:   i64 = 64;
var K_DEPTH:  i64 = 72;
var K_CUROFF: i64 = 80;
var K_NFNP:   i64 = 88;
var K_NMETHOD: i64 = 92;    # 已注册方法数
var K_NJMP:   i64 = 96;
var K_NLAB:   i64 = 104;
var K_FPATCH: i64 = 112;
var K_TOKBUF: i64 = 128;
var K_LINE:  i64 = 176;
var K_COL:   i64 = 184;
var K_CPOS:  i64 = 192;
var K_PLINE: i64 = 200;
var K_PCOL:  i64 = 208;
var K_SRCBASE: i64 = 216;
var K_NFILE: i64 = 224;
var K_NSTR:  i64 = 232;
var K_STROFF: i64 = 240;
var K_NSTRUCT: i64 = 248;
var K_NIMP:   i64 = 256;
var K_NTYPE:  i64 = 264;
var K_PPOS:   i64 = 272;
var K_LAST:   i64 = 280;    # 0=无 1=rax 里是刚发的常量 2=rax 里是刚发的 [rbp+off]
var K_LASTV:  i64 = 288;
var K_LASTR:  i64 = 296;    # 折叠时要回退的字节数
var K_HASRET: i64 = 328;
var K_LDEPTH: i64 = 336;   # 循环标签栈深度
var K_LTOP:   i64 = 344;   # 栈顶索引
var K_PANIC:  i64 = 352;   # 越界处理例程的标签 id；-1 表示还没有数组访问
var K_PJMP:   i64 = 360;   # 上一条无条件 jmp 在跳转表里的下标+1；0 表示没有
var K_PJLBL:  i64 = 368;   # 那条 jmp 的目标标签
var K_PJEND:  i64 = 376;
# --- 调试信息（-g）：默认关闭。开启时才生成 DWARF，
#     不开启时输出字节完全不变，因此不影响自举 ---
var K_DBG:      i64 = 384;   # 0/1 是否开启 -g
var K_NLM:      i64 = 392;   # 行号表条数
var K_DBGLEN:   i64 = 408;   # 当前 debug section 已写长度
var K_DBBASE:   i64 = 416;   # 当前 debug section 在 O_DBG 里的起点
var K_INFOLEN:  i64 = 424;
var K_ABBRLEN:  i64 = 432;
var K_LINELEN:  i64 = 440;
var K_SHSTRLEN: i64 = 448;
var K_CRBX:    i64 = 456;
var K_NDV:     i64 = 488;   # 局部变量表条数
var K_NDF:     i64 = 496;   # 函数表条数
var K_CURFN:   i64 = 504;   # 当前正在解析的函数在函数表里的下标
var K_FRAMELEN: i64 = 512;  # .debug_frame 长度
var K_NDTY:    i64 = 520;   # 类型表条数
var K_TYI64:   i64 = 528;   # 各基础类型 DIE 的偏移
var K_TYBYTE:  i64 = 536;
var K_TYF64:   i64 = 544;
var K_TYBOOL:  i64 = 552;
var K_TYPTR:   i64 = 560;
var K_NXC:     i64 = 568;   # 外部调用点条数
var K_OBJ:     i64 = 576;   # 0/1 是否输出 .o（-c 模式，用于 C FFI 链接）
var K_NXS:     i64 = 584;   # 去重后的 extern 符号个数
var K_OBJSH:   i64 = 592;   # -c 模式：节头表在文件里的偏移
var K_OBJRL:   i64 = 600;   # .rela.text 长度
var K_OBJSL:   i64 = 608;   # .symtab 长度
var K_OBJTL:   i64 = 616;   # .strtab 长度
var K_OBJHL:   i64 = 624;   # .shstrtab 长度
var K_ESCP:    i64 = 688;   # lex_esc 返回后：下一个待读字符的位置
# --- f-string 插值（f"共 {n} 篇"）---
var K_FMODE:   i64 = 464;   # 1 = 正在解析一个 f-string（后续引号走片段模式）
var K_FEND:    i64 = 472;
var K_FPOS:    i64 = 480;
# Profiler（-p）：1 = 在函数入口/出口插桩；K_PROFMAIN = 当前解析的是 main
#
# 🔴 槽号不能用 488/496/504 —— 那三个已经被占用（局部变量表条数、
#    函数表条数、当前函数下标）。第一版就撞在这里：K_PROF 读到的是
#    "局部变量条数"这种完全无关的值，插桩开关时开时关，
#    表现是 -p 编译通过、程序正常、报告却一行都没有 —— 没有任何报错。
var K_PROF:    i64 = 632;
var K_PROFMAIN: i64 = 640;
# 当前是否正在解析 import 进来的文件（-p 只对**主文件**插桩）
var K_INIMP:   i64 = 648;
var K_NIF:     i64 = 656;   # 接口个数
var K_NVT:     i64 = 664;   # vtable 个数
var K_NG:      i64 = 672;   # generic 个数
# import "x.mo" as N; —— 当前正在解析的文件的符号前缀（指向 O_PFXB 里的一
# 条 "N." 字符串；0 = 无前缀，行为与 1.140 之前完全一致）。
#
# 🔴 槽偏移取 2448：2400/2408/2416/2424/2432/2440 已分别被
#    K_NEST/K_FNBASE/K_ENCBASE/K_CURFILE/K_NB/K_NBER 占用，且槽区与
#    `O_SCAL + <字面量>` 共用同一块内存（见下面 688/696/704 的教训）。
var K_PFX:     i64 = 2448;
# 模块表（import "x.mo" as N;）：
#   O_MODS[mid*32]  模块名字符串 "N."（带尾点，32 字节定长）
#   O_MODP[mid*8]   该模块的前缀指针（= heap + O_MODS + mid*32）
#   O_NMOD          模块个数
#   O_SPFX[sym*8]   该符号所属的前缀（0 = 全局命名空间）
#
# 🔴 取 91000000 起：O_GENBUF(89000000) 占 1MB 到 90000000，而 heap 共
#    100663296 字节（见 main 里 syscall(12,...)），故 91000000 之后安全。
# 🔴 为什么是"前缀指针"而不是"前缀字符串拼接"：拼接需要一个临时缓冲，
#    而 import 可嵌套 —— 共用缓冲会被内层冲掉（本项目已多次栽在
#    "共享临时被嵌套调用覆盖"上）。改成指针比较后**完全不需要拼接**。
var O_MODS: i64 = 91000000;
var O_MODP: i64 = 91002048;
var O_NMOD: i64 = 91002560;
var O_SPFX: i64 = 91002568;
# MOD.fn( 解析时暂存函数名的一块**专用**区（64 字节）。
# 🔴 为什么不用 scratch2/scratch3：那两块是 O_SCAL 里的定长槽，与 method 名
#    缓冲共用，在 parse_primary 这个位置已被占用。本项目反复栽在
#    "共用缓冲被覆盖"上，这里给它一个独立地址最省事。
var O_MCB: i64 = 91018960;
# 🔴 这三个槽**不能用 688/696/704**：K_ 槽和 `O_SCAL + <字面量>` 共用同一块
#    内存（sv/gv 就是 store64(heap + O_SCAL + k)），而 O_SCAL+700 已被
#    method 名缓冲占用（8 字节写会跨到 707）。第一版用 696/704 时
#    gv(K_FNBASE) 读出来是 8216206389 这种垃圾 —— 捕获判定因此全错。
#    挪到 2400 起（2112 与 3000 之间的空档）。
var K_NEST:    i64 = 2400;  # 嵌套函数深度：0 = 顶层函数
var K_FNBASE:  i64 = 2408;  # 当前（嵌套）函数的符号表基线
var K_ENCBASE: i64 = 2416;
# 当前正在解析的文件在文件名表里的下标（0 = 主文件，1.. = import 进来的）
var K_CURFILE: i64 = 2424;  # 外层函数的符号表基线（捕获区间下界）
var K_NB:      i64 = 2432;  # 待检查的 trait bound 项数
var K_NBER:    i64 = 2440;  # 已报出的 bound 违例数（>0 即编译失败）
var K_CURFPATH: i64 = 2456; # 当前 compile_file 的源路径（intern 指针）—— import 相对目录查找用
var K_NGA:     i64 = 680;   # 当前 instantiate 的实参个数   # f-string 内部的扫描位置（片段之间**没有引号**）   # 当前片段的结束原因：0 = 收尾引号，1 = 遇到 '{'   # rbx 里是否缓存着「最后一次 push」的值   # 那条 jmp 结束时的 code_len（若标签紧接着就落在这里）   # 当前函数体里是否出现过 return
var K_PL:    i64 = 304;    # 上一句 pop rcx 弹出的左操作数是否为常量
var K_PLV:   i64 = 312;
var K_PLR:   i64 = 320;

# ---------------------------- 标量访问 ----------------------------
fn gv(k: i64) -> i64 {
    return load64(heap + O_SCAL + k);
}

fn sv(k: i64, v: i64) -> i64 {
    store64(heap + O_SCAL + k, v);
    return 0;
}

# ---------------------------- 字节发射 ----------------------------
# 所有字节发射的唯一出口。顺带清掉「rax 刚由常量/局部量产生」的标记：
# 任何后续发射都意味着那个来源信息已经失效。
fn emit1(b: i64) -> i64 {
    sv(K_LAST, 0);
    sv(K_PJMP, 0);
    let n: i64 = gv(K_CLEN);
    store8(heap + O_CODE + n, b);
    sv(K_CLEN, n + 1);
    return 0;
}

fn emit4(v: i64) -> i64 {
    emit1(v & 255);
    emit1((v >> 8) & 255);
    emit1((v >> 16) & 255);
    emit1((v >> 24) & 255);
    return 0;
}

fn emit8(v: i64) -> i64 {
    emit1(v & 255);
    emit1((v >> 8) & 255);
    emit1((v >> 16) & 255);
    emit1((v >> 24) & 255);
    emit1((v >> 32) & 255);
    emit1((v >> 40) & 255);
    emit1((v >> 48) & 255);
    emit1((v >> 56) & 255);
    return 0;
}

fn dbyte(b: i64) -> i64 {
    let n: i64 = gv(K_DLEN);
    if n >= O_DCAP { return die("global data too large: output data segment buffer overflow\n"); }
    store8(heap + O_DATA + n, b);
    sv(K_DLEN, n + 1);
    return 0;
}

fn dquad(v: i64) -> i64 {
    let i: i64 = 0;
    while i < 8 {
        dbyte((v >> (i * 8)) & 255);
        i = i + 1;
    }
    return 0;
}

# ---------------------------- 字符串工具 ----------------------------
fn strlen(s: i64) -> i64 {
    let n: i64 = 0;
    while load8(s + n) != 0 {
        n = n + 1;
    }
    return n;
}

fn streq(a: i64, b: i64) -> i64 {
    let i: i64 = 0;
    while 1 {
        let ca: i64 = load8(a + i);
        if ca != load8(b + i) {
            return 0;
        }
        if ca == 0 {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn memcpy(d: i64, s: i64) -> i64 {
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(d + i, load8(s + i));
        i = i + 1;
    }
    store8(d + i, 0);
    return 0;
}

# 名字池
fn intern(s: i64) -> i64 {
    let off: i64 = gv(K_NLEN);
    let i: i64 = 0;
    while load8(s + i) != 0 {
        store8(heap + O_NAMES + off + i, load8(s + i));
        i = i + 1;
    }
    store8(heap + O_NAMES + off + i, 0);
    sv(K_NLEN, off + i + 1);
    return off;
}

fn name_at(i: i64) -> i64 {
    return heap + O_NAMES + load64(heap + O_SYN + i * 8);
}

# ---------------------------- 错误与退出 ----------------------------
# 输出十进制整数到 stderr
fn emit_dec(v: i64) -> i64 {
    let p: i64 = heap + O_SCAL + 1400;
    let i: i64 = 0;
    if v == 0 {
        store8(p, 48);
        syscall(1, 2, p, 1, 0, 0, 0);
        return 0;
    }
    while v > 0 {
        store8(p + i, 48 + (v % 10));
        v /= 10;
        i += 1;
    }
    let j: i64 = 0;
    while j < i / 2 {
        let t: i64 = load8(p + j);
        store8(p + j, load8(p + i - 1 - j));
        store8(p + i - 1 - j, t);
        j += 1;
    }
    syscall(1, 2, p, i, 0, 0, 0);
    return 0;
}

# 把 K_LINE / K_COL 推进到源码位置 p（增量维护）
fn advance_lc(p: i64) -> i64 {
    let c: i64 = gv(K_CPOS);
    while c < p {
        if sbyte(c) == 10 {
            sv(K_LINE, gv(K_LINE) + 1);
            sv(K_COL, 1);
        } else {
            sv(K_COL, gv(K_COL) + 1);
        }
        c += 1;
    }
    sv(K_CPOS, c);
    return 0;
}

# 带 文件:行:列 的错误输出并退出
# 带 文件:行:列 的错误输出（可指定行列，用于指向上一个 token）
fn err_at2(msg: i64, ln: i64, cl: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(ln);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(cl);
    syscall(1, 2, ": error: ", 9, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn err_at(msg: i64) -> i64 {
    return err_at2(msg, gv(K_LINE), gv(K_COL));
}

# 打印出错源码行与列指示符（p 为出错位置，cl 为列号）
fn err_src(p: i64, cl: i64) -> i64 {
    let b: i64 = p;
    let go: i64 = 1;
    while go == 1 {
        if b <= 0 {
            go = 0;
        } else {
            if sbyte(b - 1) == 10 {
                go = 0;
            } else {
                b -= 1;
            }
        }
    }
    let e: i64 = p;
    let n: i64 = gv(K_SRCLEN);
    go = 1;
    while go == 1 {
        if e >= n {
            go = 0;
        } else {
            if sbyte(e) == 10 {
                go = 0;
            } else {
                e += 1;
            }
        }
    }
    syscall(1, 2, "    ", 4, 0, 0, 0);
    syscall(1, 2, heap + gv(K_SRCBASE) + b, e - b, 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    syscall(1, 2, "    ", 4, 0, 0, 0);
    let i: i64 = 1;
    while i < cl {
        syscall(1, 2, " ", 1, 0, 0, 0);
        i = i + 1;
    }
    syscall(1, 2, "^\n", 2, 0, 0, 0);
    return 0;
}

# 带源码行输出的报错（自己拼头部，不能调 err_at2 —— 它会直接退出进程）
fn err_atp(msg: i64, ln: i64, cl: i64, p: i64) -> i64 {
    syscall(1, 2, INPATH, strlen(INPATH), 0, 0, 0);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(ln);
    syscall(1, 2, ":", 1, 0, 0, 0);
    emit_dec(cl);
    syscall(1, 2, ": error: ", 9, 0, 0, 0);
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(1, 2, "\n", 1, 0, 0, 0);
    err_src(p, cl);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn die(msg: i64) -> i64 {
    syscall(1, 2, msg, strlen(msg), 0, 0, 0);
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

fn syntax_error() -> i64 {
    return err_at("syntax error");
}

# ---------------------------- 类型表 ----------------------------
#  id 0 = int,  id 1 = void，其余由 ty_new 按需分配并去重
fn ty_int() -> i64  { return 0; }
fn ty_void() -> i64 { return 1; }
fn ty_byte() -> i64 { return 2; }

# 预置 id 0 = int, id 1 = void
fn ty_init() -> i64 {
    store64(heap + O_TK + 0, 0);
    store64(heap + O_TA + 0, 0);
    store64(heap + O_TB + 0, 0);
    store64(heap + O_TK + 8, 1);
    # id 2 = byte（kind 5，1 字节无符号，加载时零扩展）
    store64(heap + O_TK + 16, 5);
    store64(heap + O_TA + 16, 0);
    store64(heap + O_TB + 16, 0);
    store64(heap + O_TA + 8, 0);
    store64(heap + O_TB + 8, 0);
    sv(K_NTYPE, 3);
    return 0;
}

fn ty_new(kind: i64, a: i64, b: i64) -> i64 {
    let n: i64 = gv(K_NTYPE);
    let i: i64 = 2;
    while i < n {
        if load64(heap + O_TK + i * 8) == kind {
            if load64(heap + O_TA + i * 8) == a {
                if load64(heap + O_TB + i * 8) == b { return i; }
            }
        }
        i = i + 1;
    }
    store64(heap + O_TK + n * 8, kind);
    store64(heap + O_TA + n * 8, a);
    store64(heap + O_TB + n * 8, b);
    sv(K_NTYPE, n + 1);
    return n;
}

fn ty_struct(si: i64) -> i64 { return ty_new(2, si, 0); }
fn ty_array(el: i64, n: i64) -> i64 { return ty_new(3, el, n); }
fn ty_ptr(to: i64) -> i64 { return ty_new(4, to, 0); }
# f64：kind 6。
#
# ⚠️ f64 值**不放在 xmm 寄存器里**，而是像整数一样在 rax 里传 ——
# 只不过 rax 里装的是 IEEE754 **位模式**。运算时才 movq 进 xmm，
# 算完再 movq 回 rax。
#
# 为什么这么设计：编译器所有值的通路（push/pop、栈顶缓存 rbx、
# 返回值、参数传递）都是按"一个 i64"写的。改成 xmm 要动的地方太多。
# 代价是每次浮点运算多两次 movq（性能），换来的是**实现简单且不会
# 与整数通路互相污染** —— 后者一旦出错极难排查。
fn ty_float() -> i64 { return ty_new(6, 0, 0); }

# bool = kind 7，enum = kind 8。
#
# 🔴 bool **不做隐式类型检查**，也不改变值的通路 —— 它和 i64 一样
# 占 8 字节栈槽、一样在 rax 里传，只是**标记**为布尔。
# 这样 `if x == 1` 这种存量代码（条件位置只测 rax 是否为 0）完全不受影响。
#
# 如果真去严格区分 bool 与 i64，会立刻破坏大量现有代码，
# 而收益只是"写错时早报错" —— 性价比很低，且风险集中在最核心的通路。
fn ty_bool() -> i64 { return ty_new(7, 0, 0); }
# i32：只在 C FFI 的返回类型上有意义。
# C 的 int 只写 eax，rax 高 32 位是垃圾 —— 不符号扩展的话
# strcmp 返回 -1 会被读成 4294967295。
fn ty_i32() -> i64 { return ty_new(9, 0, 0); }
fn ty_enum(ei: i64) -> i64 { return ty_new(8, ei, 0); }
# str：kind 10 —— 字符串成为一等类型。
#
# 值与 ptr **完全一样**（一个指向 NUL 结尾字节的地址，占一个 8 字节槽），
# 变的只是**类型标记**：
#   - == / != 走**内容比较**而不是地址比较（这是最关键的语义差别）
#   - 下标 s[i] 按 1 字节步进（与 ptr 一致，见 elem_type）
# 之所以不改表示：改成 {len,ptr} 胖值会破坏"所有值都是一个 i64"这条
# 贯穿编译器的不变式，而收益只是 O(1) 求长（见 docs/str.md）。
fn ty_str() -> i64 { return ty_new(10, 0, 0); }

fn ty_kind(t: i64) -> i64 { return load64(heap + O_TK + t * 8); }
fn ty_a(t: i64) -> i64 { return load64(heap + O_TA + t * 8); }
fn ty_b(t: i64) -> i64 { return load64(heap + O_TB + t * 8); }

fn ty_eq(x: i64, y: i64) -> i64 {
    if x == y { return 1; }
    return 0;
}

# 结构体类型的 aux1 里存的是结构体索引
fn ty_si(t: i64) -> i64 { return load64(heap + O_TA + t * 8); }

fn ty_size(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 5 { return 1; }
    if k == 9 { return 4; }
    # 🔴 不能用 st_nfields（只数**直接**字段）：嵌套结构体字段占多个槽，
    #    于是 struct W { inner: P; b: i64; } 被算成 2 个槽（实为 3），
    #    后面的字段全被挤到前面去，静默写坏（见 st_words）。
    if k == 2 { return 8 * st_words(ty_a(t)); }
    if k == 3 { return ty_b(t) * ty_size(ty_a(t)); }
    return 8;
}

# 下标访问的元素类型（数组与指针都按指向/元素类型步进）
fn elem_type(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 3 { return ty_a(t); }
    if k == 4 { return ty_a(t); }
    # str 与 ptr 一样按字节步进
    if k == 10 { return ty_byte(); }
    return ty_int();
}

fn elem_size(t: i64) -> i64 {
    let k: i64 = ty_kind(t);
    if k == 3 { return ty_size(ty_a(t)); }
    if k == 4 { return ty_size(ty_a(t)); }
    if k == 10 { return 1; }
    return 8;
}

# rax 里是「结构体地址」还是「结构体值」—— 两者 R_ETY 都是 struct(kind 2)，
# 但后续动作完全不同：
#   地址 → 逐字段拷贝（let q: P = a;）
#   值   → 按 System V 落 rax/rdx（let q: P = f();）
# 只由三处置 1（load_sym 的 struct 变量、下标元素、struct 字段），
# parse_call 末尾置 0（返回值在 rax/rdx）。
var R_SADDR: i64 = 0;

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

# ==========================================================================
#  词法分析
# ==========================================================================
# 读取「当前文件」的第 i 个字节（支持 import 多文件）
fn sbyte(i: i64) -> i64 {
    return load8(heap + gv(K_SRCBASE) + i);
}

fn is_alpha(c: i64) -> i64 {
    if c >= 97 {
        if c <= 122 { return 1; }
    }
    if c >= 65 {
        if c <= 90 { return 1; }
    }
    return 0;
}

fn is_digit(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return 1; }
    }
    return 0;
}

fn is_alnum(c: i64) -> i64 {
    if is_alpha(c) == 1 { return 1; }
    if is_digit(c) == 1 { return 1; }
    if c == 95 { return 1; }
    return 0;
}

fn hexval(c: i64) -> i64 {
    if c >= 48 {
        if c <= 57 { return c - 48; }
    }
    if c >= 97 {
        if c <= 102 { return c - 87; }
    }
    if c >= 65 {
        if c <= 70 { return c - 55; }
    }
    return -1;
}

# 跳过空白与 '#' 注释，返回下一个有效字符位置
fn skip_comment(p: i64) -> i64 {
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        if sbyte(p) == 10 { return p + 1; }
        p = p + 1;
    }
    return p;
}

fn skip_ws() -> i64 {
    let p: i64 = gv(K_POS);
    let n: i64 = gv(K_SRCLEN);
    while p < n {
        let c: i64 = sbyte(p);
        if c == 35 {
            p = skip_comment(p);
        } else {
            if c == 32 { p = p + 1; }
            else {
                if c == 9 { p = p + 1; }
                else {
                    if c == 10 { p = p + 1; }
                    else {
                        if c == 13 { p = p + 1; }
                        else { return p; }
                    }
                }
            }
        }
    }
    return p;
}

fn tokbuf() -> i64 {
    return heap + O_SCAL + K_TOKBUF;
}

fn lex_ident(p: i64) -> i64 {
    let i: i64 = 0;
    let b: i64 = tokbuf();
    while is_alnum(sbyte(p + i)) == 1 {
        store8(b + i, sbyte(p + i));
        i = i + 1;
    }
    store8(b + i, 0);
    sv(K_POS, p + i);
    sv(K_TKIND, 1);
    return 0;
}

fn lex_hex(p: i64) -> i64 {
    let v: i64 = 0;
    let h: i64 = hexval(sbyte(p));
    while h >= 0 {
        v = v * 16 + h;
        p = p + 1;
        h = hexval(sbyte(p));
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

fn lex_number(p: i64) -> i64 {
    # 🔴 这四个状态必须在**任何**返回路径之前清零 —— 包括 0x.. 的十六进制。
    #
    # 原先 `0x...` 走 lex_hex 提前 return，而清零写在函数后半段，
    # 于是十六进制字面量**保留上一个 token 的 K_TFLT**。
    # 后果：紧跟在浮点字面量后面的十六进制字面量被当成浮点解析，
    # 而且用的是**上一个字面量的数字**（K_TFDIG/K_TFDIGN 同样是残留值）：
    #
    #   assert_eq("vs-any", fbits(0.5), 0x1111111111111111)
    #                                   ^ 被解析成 0.5 的位模式
    #
    # 于是 want == got，**断言恒真**。tests/127 那 23 条浮点断言就是这样
    # 整批空转的 —— 而且它骗过了 1.115 的变异验证（改坏词法器，断言照样绿）。
    # 这类"看起来通过、实际什么都没验"正是本项目最该防的模式。
    sv(K_TFLT, 0);
    sv(K_TFDIG, 0);
    sv(K_TFDIGN, 0);
    FSTICKY = 0;
    if sbyte(p) == 48 {
        if sbyte(p + 1) == 120 { return lex_hex(p + 2); }
        if sbyte(p + 1) == 88 { return lex_hex(p + 2); }
    }
    # 整数部分：**不能截断位数**。
    #
    # 🔴 这里踩过一次：第一版给整数部分也加了 18 位上限，
    #   结果 `9223372036854775807`（19 位，i64::MAX）被读成 922337203685477580。
    #   自举立刻报不一致 —— 因为汇编 seed 的词法器是另一套实现，没跟着截。
    #   而 `0 - 9223372036854775807 - 1` 正是墨语言写 i64::MIN 的惯用法，
    #   这个改动会静默改掉全语言的整数下限。
    # 限度只在**浮点**字面量的分子上（N = v*10^k + fd 必须 < 10^18）。
    let v: i64 = 0;
    let idn: i64 = 0;
    let seen: i64 = 0;
    let dc: i64 = 0;
    while is_digit(sbyte(p)) == 1 {
        dc = sbyte(p) - 48;
        v = v * 10 + dc;
        if dc != 0 { seen = 1; }
        if seen == 1 { idn = idn + 1; }
        p = p + 1;
    }
    # 浮点字面量：整数部分后紧跟 '.' 且 '.' 后是数字。
    #
    # ⚠️ 必须同时判断'.'后是数字：`obj.field` 里 `.` 后面是标识符，
    #    只判断 '.' 会把 `r.w` 的 `r` 当成浮点数开头，把 `.w` 吞掉。
    #    这个 bug 会表现为"方法调用莫名其妙报语法错误"。
    #
    # 给 f64_bits 的接口：K_TFDIG = 分子 N，K_TFDIGN = 十进制指数 k，即 值 = N / 10^k。
    sv(K_TFLT, 0);
    sv(K_TFDIG, 0);
    sv(K_TFDIGN, 0);
    FSTICKY = 0;
    if sbyte(p) == 46 {
        if is_digit(sbyte(p + 1)) == 1 {
            p = p + 1;
            # 前导零不占有效位预算，但要计入十进制指数
            let z: i64 = 0;
            while sbyte(p) == 48 { z = z + 1; p = p + 1; }
            let fd: i64 = 0;
            let fdn: i64 = 0;
            # 有效数字预算：整数 + 小数合计 18 位（N 必须 < 10^18）。
            # 十进制指数 k 的上限：v>0 时 N=v*10^k+fd 决定 k <= 18-idn；
            # v==0 时 N=fd，只受「归一化倍增会不会溢出」限制（见 f64_bits）：
            # 需要 2*5^k < 2^63，即 5^k < 4.61e18 —— 5^26=1.49e18 ✓，5^27=7.45e18 ✗。
            # 于是 k 上限取 26，可表示范围从 1e-18 扩大到 1e-26。
            let sig: i64 = 18 - idn;
            let kmax: i64 = sig;
            if v == 0 { kmax = 26; }
            let budget: i64 = 0;
            let k: i64 = 0;
            if z >= kmax {
                # 全部小数位都在可表示范围之外
                while is_digit(sbyte(p)) == 1 {
                    if sbyte(p) != 48 { FSTICKY = 1; }
                    p = p + 1;
                }
            } else {
                budget = sig;
                if kmax - z < budget { budget = kmax - z; }
                while is_digit(sbyte(p)) == 1 {
                    if fdn < budget {
                        fd = fd * 10 + (sbyte(p) - 48);
                        fdn = fdn + 1;
                    } else {
                        if sbyte(p) != 48 { FSTICKY = 1; }
                    }
                    p = p + 1;
                }
                k = z + fdn;
            }
            let N: i64 = fd;
            if v != 0 { N = v * pow10i(k) + fd; }
            sv(K_TFLT, 1);
            sv(K_TFDIG, N);
            sv(K_TFDIGN, k);
        }
    }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, v);
    store8(tokbuf(), 0);
    return 0;
}

# 转义序列：p 指向反斜杠，返回字节值，结束位置写入 K_ESCP。
#
# 🔴 \xHH 此前**完全不支持**，而且是静默的：
#    \x 后面的 'x' 不匹配 n/t/r/0，于是落到"原样输出"分支，
#    输出字符 'x' 自己。所以 "\xe4\xb8\xad" 会安静地变成 "xe4xb8xad"
#    —— 不报错、不崩溃，字符串只是变成了另一个。
#    本轮（1.120）就是在用 \x 构造 UTF-8 用例时发现它的：
#    测出来「中 > z」与「中 < a」同时为 0，两个方向都假，
#    只可能是数据本身不对。
#
# 位数不足的 \x 必须报错，不能悄悄给个值 —— 静默是这个项目
# 反复出现的最危险模式。
fn lex_esc(p: i64) -> i64 {
    let c: i64 = sbyte(p + 1);
    if c == 110 { sv(K_ESCP, p + 2); return 10; }   # \n
    if c == 116 { sv(K_ESCP, p + 2); return 9;  }   # \t
    if c == 114 { sv(K_ESCP, p + 2); return 13; }   # \r
    if c == 48  { sv(K_ESCP, p + 2); return 0;  }   # \0
    if c == 120 {                                    # \xHH
        let hi: i64 = hexval(sbyte(p + 2));
        if hi < 0 { return die("error: bad \\x escape\n"); }
        let lo: i64 = hexval(sbyte(p + 3));
        if lo < 0 { return die("error: bad \\x escape\n"); }
        sv(K_ESCP, p + 4);
        return hi * 16 + lo;
    }
    sv(K_ESCP, p + 2);
    return c;                                        # \\ \" \' 等原样
}

# 字符串字面量：内容写入输出数据段（供生成的程序用），
# 同时拷贝一份到编译器侧字符串池 O_STRS（供编译器自身读取）
fn lex_string(p: i64) -> i64 {
    p = p + 1;
    let addr: i64 = 268435456 + gv(K_DLEN);
    let so: i64 = gv(K_NSTR);
    sv(K_STROFF, so);
    while sbyte(p) != 34 {
        let c: i64 = sbyte(p);
        if c == 92 {
            c = lex_esc(p);
            p = gv(K_ESCP);
        } else {
            p = p + 1;
        }
        dbyte(c);
        store8(heap + O_STRS + so, c);
        so = so + 1;
    }
    p = p + 1;
    dbyte(0);
    store8(heap + O_STRS + so, 0);
    so = so + 1;
    sv(K_NSTR, so);
    sv(K_POS, p);
    sv(K_TKIND, 3);
    sv(K_TIVAL, addr);
    store8(tokbuf(), 0);
    return 0;
}

# f-string 的一个字面片段，例如 f"共 {n} 篇" 里的 "共 " 和 " 篇"。
#
# p 指向开引号。
#   - 遇到 '{'：**提前结束**本片段，且不消费 '{'（让它成为下一个 token）
#   - 遇到 '"' ：正常结束，并把 K_FMODE 清零（f-string 到此为止）
#
# 结束状态记在 K_FEND 里，解析器靠它决定下一步。
fn lex_fstring() -> i64 {
    #
    # 从 **K_FPOS** 读，不从参数读。
    #
    # 因为 f"A{n}B\n" 里片段之间**没有引号** —— 整个 f-string 只有
    # 开头一个 f" 和结尾一个 "。第一版我让 next_token 每次从开引号读，
    # 结果 '}' 之后 p 指向的是片段内容 'B'，被当成引号跳掉，
    # 于是每个后续片段都**丢掉第一个字符**（"B\n" 变成 "\n"）。
    let p: i64 = gv(K_FPOS);
    let addr: i64 = 268435456 + gv(K_DLEN);
    let so: i64 = gv(K_NSTR);
    sv(K_STROFF, so);
    sv(K_FEND, 0);
    let done: i64 = 0;
    while done == 0 {
        let c: i64 = sbyte(p);
        if c == 34 { done = 1; }
        else {
            if c == 123 {
                done = 1;
                sv(K_FEND, 1);
                sv(K_FMODE, 2);      # 进入 { 表达式 } 内部，按普通 token 走
            } else {
                if c == 92 {
                    c = lex_esc(p);
                    p = gv(K_ESCP);
                } else {
                    p = p + 1;
                }
                dbyte(c);
                store8(heap + O_STRS + so, c);
                so = so + 1;
            }
        }
    }
    # '{' 结束时 p 正指向 '{'，留给下一个 token；'"' 结束时吃掉引号并退出 f 模式
    if gv(K_FEND) == 0 {
        p = p + 1;
        sv(K_FMODE, 0);
    }
    dbyte(0);
    store8(heap + O_STRS + so, 0);
    so = so + 1;
    sv(K_NSTR, so);
    sv(K_FPOS, p);
    sv(K_POS, p);
    sv(K_TKIND, 5);
    sv(K_TIVAL, addr);
    store8(tokbuf(), 0);
    return 0;
}

# 当前字符串字面量在编译器侧的可读地址
fn strpool() -> i64 {
    return heap + O_STRS + gv(K_STROFF);
}

fn set_tok(a: i64, b: i64, adv: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, 0);
    sv(K_POS, p + adv);
    sv(K_TKIND, 4);
    return 0;
}

# 三字符 token（<<= >>=）。与 set_tok 同构，只是多写一个字节、多吃一个字符。
fn set_tok3(a: i64, b: i64, c: i64, p: i64) -> i64 {
    let t: i64 = tokbuf();
    store8(t, a);
    store8(t + 1, b);
    store8(t + 2, c);
    store8(t + 3, 0);
    sv(K_POS, p + 3);
    sv(K_TKIND, 4);
    return 0;
}

fn lex_punct(p: i64) -> i64 {
    let c: i64 = sbyte(p);
    let d: i64 = sbyte(p + 1);
    if c == 61 {
        if d == 61 { return set_tok(61, 61, 2, p); }
    }
    # 复合赋值：+= -= *= /= %= &= |= ^=
    # 必须比单字符更早匹配，否则 '+=' 会被当成 '+' 再跟一个 '='
    if c == 43 {
        if d == 61 { return set_tok(43, 61, 2, p); }
        if d == 43 { return set_tok(43, 43, 2, p); }
    }
    if c == 42 {
        if d == 61 { return set_tok(42, 61, 2, p); }
    }
    if c == 47 {
        if d == 61 { return set_tok(47, 61, 2, p); }
    }
    if c == 37 {
        if d == 61 { return set_tok(37, 61, 2, p); }
    }
    if c == 94 {
        if d == 61 { return set_tok(94, 61, 2, p); }
    }
    if c == 33 {
        if d == 61 { return set_tok(33, 61, 2, p); }
    }
    if c == 60 {
        # 三字符必须先试：'<' '<' '=' 若按两字符匹配会切成 "<<" + "="
        if d == 60 {
            if sbyte(p + 2) == 61 { return set_tok3(60, 60, 61, p); }
            return set_tok(60, 60, 2, p);
        }
        if d == 61 { return set_tok(60, 61, 2, p); }
    }
    if c == 62 {
        if d == 62 {
            if sbyte(p + 2) == 61 { return set_tok3(62, 62, 61, p); }
            return set_tok(62, 62, 2, p);
        }
        if d == 61 { return set_tok(62, 61, 2, p); }
    }
    if c == 38 {
        if d == 38 { return set_tok(38, 38, 2, p); }
        if d == 61 { return set_tok(38, 61, 2, p); }
    }
    if c == 124 {
        if d == 124 { return set_tok(124, 124, 2, p); }
        if d == 61 { return set_tok(124, 61, 2, p); }
    }
    if c == 45 {
        if d == 62 { return set_tok(45, 62, 2, p); }
        if d == 61 { return set_tok(45, 61, 2, p); }
        if d == 45 { return set_tok(45, 45, 2, p); }
    }
    return set_tok(c, 0, 1, p);
}

# 字符字面量 'a' / '\n' / '\\' / '\'' —— 值就是一个整数
fn lex_char(p: i64) -> i64 {
    p = p + 1;
    let c: i64 = sbyte(p);
    if c == 92 {
        c = lex_esc(p);
        p = gv(K_ESCP);
    } else {
        p = p + 1;
    }
    # 允许但不强制闭合引号：吃掉它（存在就吃）
    if sbyte(p) == 39 { p = p + 1; }
    sv(K_POS, p);
    sv(K_TKIND, 2);
    sv(K_TIVAL, c);
    store8(tokbuf(), 0);
    return 0;
}

fn next_token() -> i64 {
    let p: i64 = skip_ws();
    sv(K_PLINE, gv(K_LINE));
    sv(K_PCOL, gv(K_COL));
    sv(K_PPOS, gv(K_TOKPOS));
    advance_lc(p);
    sv(K_POS, p);
    sv(K_TOKPOS, p);
    if p >= gv(K_SRCLEN) {
        sv(K_TKIND, 0);
        return 0;
    }
    let c: i64 = sbyte(p);
    # f-string 未结束时，下一个 token 一定是片段（以引号开头）。
    # 不能走普通 lex：'}' 之后紧跟的是片段内容而不是 '}'，
    # 普通 lex 会把它识别成标识符（第一版就是这么错的）。
    if gv(K_FMODE) == 1 { return lex_fstring(); }
    # 'f' 后面紧跟引号才是插值字符串；单独的 f 仍然是普通标识符
    if c == 102 {
        if sbyte(p + 1) == 34 {
            sv(K_FMODE, 1);
            sv(K_FPOS, p + 2);
            return lex_fstring();
        }
    }
    if is_alpha(c) == 1 { return lex_ident(p); }
    if c == 95 { return lex_ident(p); }
    if is_digit(c) == 1 { return lex_number(p); }
    if c == 34 { return lex_string(p); }
    if c == 39 { return lex_char(p); }
    return lex_punct(p);
}

fn set_pos(p: i64) -> i64 {
    sv(K_POS, p);
    sv(K_CPOS, 0);
    sv(K_LINE, 1);
    sv(K_COL, 1);
    next_token();
    return 0;
}

fn tok_is(s: i64) -> i64 {
    if gv(K_TKIND) == 0 { return 0; }
    return streq(tokbuf(), s);
}

fn expect(s: i64) -> i64 {
    if tok_is(s) == 0 { return syntax_error(); }
    next_token();
    return 0;
}

fn accept(s: i64) -> i64 {
    if tok_is(s) == 0 { return 0; }
    next_token();
    return 1;
}

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

# ==========================================================================
#  语句
# ==========================================================================
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
    if ci < 0 { return err_atp("not a class value", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
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
    if accept("break") == 1 { return parse_break(); }
    if accept("continue") == 1 { return parse_continue(); }
    if accept("let") == 1 { return parse_let(); }
    if accept("if") == 1 { return parse_if(); }
    if accept("while") == 1 { return parse_while(); }
    if accept("for") == 1 { return parse_for(); }
    # switch / case / default / fallthrough 都是**上下文关键字**：
    # 只在语句起始位置识别 switch，case 等只在 switch 主体里识别。
    # 于是库里那些叫 case 的变量、注释里的 "case" 都不受影响。
    if accept("switch") == 1 { return parse_switch(); }
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
            # 预读右边是否为「单个标识符」。结构体整体赋值需要右边的地址，
            # 所以只支持 标识符 = 标识符；其它形状仍然报错。
            let rhs: i64 = -1;
            if gv(K_TKIND) == 1 {
                memcpy(scratch3(), tokbuf());
                let save2: i64 = gv(K_TOKPOS);
                next_token();
                if tok_is(";") == 1 { rhs = sym_lookup(scratch3()); }
                set_pos(save2);
            }
            parse_expr();
            expect(";");
            R_SYM = sym_lookup(scratch2());
            if R_SYM < 0 { return undef_err(scratch2()); }
            let lt: i64 = sym_type(R_SYM);
            if ty_kind(lt) == 3 { return err_atp("cannot assign to an array", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
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
            if ty_kind(ft) == 2 { return err_at2("cannot assign a struct value", gv(K_LINE), gv(K_COL)); }
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
        set_pos(save);
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

fn parse_let() -> i64 {
    # 声明行要在解析表达式**之前**取：之后 K_LINE 会走到表达式末尾，
    # 记下来的行号就指向右值而不是声明处。
    let dcln: i64 = gv(K_LINE);
    memcpy(scratch2(), tokbuf());
    next_token();
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
                    dquad(0);
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
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
            }
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
            if ty_kind(et) != 0 { if ty_kind(et) != 5 { return err_at2("cannot init a struct array this way", gv(K_LINE), gv(K_COL)); } }
            let lcnt2: i64 = 0 - 1;
            let sinit2: i64 = 0 - 1;
            if tok_is("[") == 1 { lcnt2 = parse_i64_list(); }
            else {
                if gv(K_TKIND) == 3 { sinit2 = gv(K_STROFF); }
            }
            let v: i64 = gv(K_TIVAL);
            if lcnt2 < 0 { next_token(); }
            expect(";");
            if sym_dup(scratch2()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            let id: i64 = sym_add(scratch2(), 1, off, 0);
            store64(heap + O_STY + id * 8, ty_array(et, n));
            dbg_var(scratch2(), off, dcln, ty_array(et, n));
            let k: i64 = 0;
            while k < n {
                let cv: i64 = v;
                if sinit2 >= 0 {
                    if k < gv(K_NSTR) - sinit2 - 1 { cv = load8(heap + O_STRS + sinit2 + k); }
                    else { cv = 0; }
                } else {
                    if lcnt2 >= 0 {
                        if k < lcnt2 { cv = load64(heap + O_LSTV + k * 8); }
                        else { cv = 0; }
                    }
                }
                g_movabs_rax(cv);
                if ty_kind(et) == 5 { g_store_local_b(off + k * esz); }
                else { g_store_local(off + k * esz); }
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
                    vt = ty_ptr(ty_byte());
                } else {
                    return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
            }
        }
    }
    expect("=");
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
fn parse_if() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let end: i64 = new_label();
    let more: i64 = 1;
    while more == 1 {
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

fn parse_while() -> i64 {
    let d: i64 = gv(K_DEPTH) + 1;
    let a: i64 = new_label();
    let b: i64 = new_label();
    loop_push(a, b, -1);
    place_label(a);
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
        set_pos(gv(K_TOKPOS));
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
fn parse_for() -> i64 {
    expect("(");
    # for 自带一层作用域：init 里的 let 属于 for，多个 for 可以各用 i
    let d: i64 = gv(K_DEPTH) + 1;
    sv(K_DEPTH, d);
    # init
    if tok_is(";") == 0 {
        if accept("let") == 1 { parse_let(); } else { parse_expr(); expect(";"); }
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
        while tok_is("-") == 1 {
            next_token();
            if gv(K_TKIND) != 2 { return 0; }
            v = v - gv(K_TIVAL);
            next_token();
        }
        while tok_is("+") == 1 {
            next_token();
            if gv(K_TKIND) != 2 { return 0; }
            v = v + gv(K_TIVAL);
            next_token();
        }
        store64(out, v);
        return 1;
    }
    if neg == 0 {
        if gv(K_TKIND) == 1 {
            memcpy(nb, tokbuf());
            next_token();
            let e: i64 = enum_value(nb);
            if e >= 0 {
                store64(out, load64(heap + O_EVAL + e * 8));
                return 1;
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
            if sw_const(vals + n * 8) == 0 { return 0 - 2; }
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
        store64(heap + O_SWTOP, base);
        return err_atp("switch: case 必须是编译期常量（整数或 enum）",
                       gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
    }
    set_pos(save);

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
                store64(heap + O_SWTOP, base);
                return err_atp("switch: duplicate case value",
                               gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
            j = j + 1;
        }
        i = i + 1;
    }
    # cmp rax, imm32 / sub rax, imm32 都只接受 imm32，超出会**静默截断**。
    i = 0;
    while i < n {
        if load64(vals + i * 8) > 2147483647 { store64(heap + O_SWTOP, base); return err_atp("switch: case 值超出 32 位", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        if load64(vals + i * 8) < 0 - 2147483648 { store64(heap + O_SWTOP, base); return err_atp("switch: case 值超出 32 位", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
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
        i = 0;
        while i < n {
            emit1(0x48); emit1(0x3d); emit4(load64(vals + i * 8));   # cmp rax, imm32
            emit_jcc(0x84, load64(lbls + i * 8));                    # je
            i = i + 1;
        }
        emit_jmp(dflt);
    }

    expect("{");
    i = 0;
    let fell: i64 = 0;                  # 上一个 case 要求穿透到下一个
    while tok_is("}") == 0 {
        if accept("case") == 1 {
            if i >= n { store64(heap + O_SWTOP, base); return err_atp("switch: case 与扫描结果不一致", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            # 即使上一个 case 写了 fallthrough 也要放标签：顺序流正好落在这里，
            # 而跳转表里这一项也仍然要指向它。
            place_label(load64(lbls + i * 8));
            fell = 0;
            if sw_const(heap + O_SWC) == 0 {
                store64(heap + O_SWTOP, base);
                return err_atp("switch: case 必须是编译期常量",
                               gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
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
                store64(heap + O_SWTOP, base);
                return err_atp("switch: expected 'case' or 'default'",
                               gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
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
        if gv(K_TKIND) != 1 {
            return err_atp("struct return: expected a variable", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
        }
        let rn: i64 = heap + O_SCAL + 1800;
        memcpy(rn, tokbuf());
        next_token();
        expect(";");
        let rs: i64 = sym_lookup(rn);
        if rs < 0 { return undef_err(rn); }
        g_addr_sym_rax(rs);                # rax = &obj
        ops3(0x48, 0x89, 0xc6);            # mov rsi, rax
        ops3(0x48, 0x8b, 0x06);            # mov rax, [rsi]
        if nf2 == 2 {
            ops3(0x48, 0x8b, 0x56);        # mov rdx, [rsi+8]
            emit1(8);
        }
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
                rt = ty_ptr(ty_byte());
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
        if gv(K_TKIND) != 2 { return err_at2("array literal elements must be integer constants", gv(K_LINE), gv(K_COL)); }
        let v: i64 = gv(K_TIVAL);
        if neg == 1 { v = 0 - v; }
        if cnt < 512 { store64(heap + O_LSTV + cnt * 8, v); }
        cnt = cnt + 1;
        next_token();
        if accept(",") == 0 { break; }
    }
    expect("]");
    return cnt;
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
                expect(";");
                # 同全局变量：槽数必须是 st_words，见上面那条注释
                let n: i64 = st_words(si);
                data_align(16);
                let addr: i64 = 268435456 + gv(K_DLEN);
                let j: i64 = 0;
                while j < n {
                    dquad(0);
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
        }
        next_token();
        expect("]");
        if n <= 0 { return err_atp("array length must be a positive constant", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let et: i64 = ty_int();
        if tok_is("i64") == 1 {
            next_token();
        } else {
            if tok_is("byte") == 1 {
                et = ty_byte();
                next_token();
            } else {
                if gv(K_TKIND) == 1 {
                    let si: i64 = st_lookup(tokbuf());
                    if si >= 0 {
                        et = ty_struct(si);
                        next_token();
                    } else {
                        return err_at2("unknown type", gv(K_LINE), gv(K_COL));
                    }
                } else {
                    return err_at2("expected a type", gv(K_LINE), gv(K_COL));
                }
            }
        }
        expect("=");
        let lcnt: i64 = 0 - 1;
        let sinit: i64 = 0 - 1;
        if tok_is("[") == 1 { lcnt = parse_i64_list(); }
        else {
            if gv(K_TKIND) == 3 { sinit = gv(K_STROFF); }
        }
        let v: i64 = gv(K_TIVAL);
        # 🔴 列表分支下 **不能再 next_token**：parse_i64_list 结束时就停在
        #    `;` 上（它内部的 expect("]") 已经把 `]` 吃掉）。
        #    多走一步会跳过分号，于是 expect(";") 读到下一行开头 ——
        #    报错位置指向**下一行**（3:1），很容易误判成下一行写错了。
        if lcnt < 0 { next_token(); }
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
            if accept("byte") == 1 {
                vt = ty_byte();
            } else {
                return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
    }
    expect("=");
    let v: i64 = gv(K_TIVAL);
    next_token();
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
                    pt = ty_ptr(ty_byte());
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
                            return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
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
        let off: i64 = gv(K_CUROFF);
        sv(K_CUROFF, off - 8);
        if sym_dup(scratch1()) >= 0 { return err_atp("duplicate definition", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
        let pid: i64 = sym_add(scratch1(), 1, off, 0);
        store64(heap + O_STY + pid * 8, pt);
        # -g：形参也要登记成变量，否则调试器在被调用函数里 p <参数名>
        #     什么都看不到（1.100：只有 let 声明的局部变量有 DIE）。
        #     偏移用的是**本帧**的槽 —— 参数被复制进自己的栈帧，
        #     与局部变量同一套负数偏移（-8, -16, ...）。
        dbg_var(scratch1(), off, gv(K_PLINE), pt);
        nb = nb + 1;
        if accept(",") == 0 {
            if tok_is(")") == 0 { return syntax_error(); }
        }
    }
    expect(")");
    expect("->");
    # 返回类型：i64（默认） / ptr / 类名
    #
    # **为什么之前只支持 i64**：结构体与指针返回需要按 System V 处理
    # （≤16 字节走 RAX:RDX，更大走隐藏指针），而所有返回值都塞在 rax 里
    # 是最省事的。代价是库函数只能返回 i64 —— 于是 str_trim 这类
    # 明明返回地址的函数，被 sfmt 当成数字打印（只能靠 ptr(v) 绕过）。
    let rt: i64 = ty_int();
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
            rt = ty_ptr(ty_byte());
        } else {
            if gv(K_TKIND) == 1 {
                let rsi: i64 = st_lookup(tokbuf());
                if rsi < 0 { return err_atp("unknown return type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
                if load64(heap + O_STF + rsi * 8) > 2 {
                    # 3 个字段起要走隐藏指针（System V），暂不支持
                    return err_atp("struct return: at most 2 fields", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
                }
                rt = ty_struct(rsi);
                next_token();
            } else {
                return err_atp("expected a type", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS));
            }
        }
        }
        }
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
        return err_atp("missing return statement in a function returning i64", fnln, fncol, fnpos);
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
                        }
                        p = next_line(p);
                    } else {
                        p = next_line(p);
                    }
                } else {
                    p = next_line(p);
                }
            } else {
                p = next_line(p);
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
#   1) 原样
#   2) lib/<basename>
#   3) ../lib/<basename>
# 让 examples/ 下的程序写 import "io.mo" 就能用上标准库，不必手工拷贝。
var SP_BUF: i64 = 7416760;

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

    parse_program();

    sv(K_SRCBASE, s_base);
    sv(K_SRCLEN, s_srclen);
    sv(K_CURFILE, s_cf);
    INPATH = s_in;
    set_pos(s_tok);
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
            if gv(K_TKIND) != 2 { return err_atp("enum value must be an integer literal", gv(K_PLINE), gv(K_PCOL), gv(K_PPOS)); }
            auto = gv(K_TIVAL);
            next_token();
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
    let si: i64 = st_add(scratch2());
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
        # byte 字段也按 8 字节对齐存放（与 C 的默认对齐结果一致：
        # struct { char x; long y; } 在 C 里同样是 16 字节）。
        # 于是 ty_size 的 8*nfields 依然成立。
        st_add_field(si, scratch1(), ft);
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
    next_token();
    while gv(K_TKIND) != 0 {
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
                                    if tok_is("var") == 1 {
                                        parse_global();
                                    } else {
                                            if tok_is("fn") == 1 {
                                                parse_func();
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
    let ai: i64 = 1;
    while ai < argc() {
        let a: i64 = argv(ai);
        if streq(a, "-g") == 1 {
            sv(K_DBG, 1);
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

    # trait bound 检查同样必须在**全部解析结束**后：impl 可能出现在
    # instantiate 之后，此刻 K_NVT 才是完整的。
    gen_check_bounds();
    if gv(K_NBER) > 0 { return 1; }

    emit_panic();
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
fn cmp_setter(compo: i64, fld: i64, kind: i64) -> i64 {
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
        cmp_s("(v: i64) -> i64 {\n    ");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(" = v;\n    return 0;\n}\n");
    }
    return 0;
}

# 生成 row 函数里一个字段的绘制代码。fi 是字段序号。
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
        cmp_s("    uc_text(cx, y, &");
        cmp_s(compo);
        cmp_c(95);
        cmp_s(fld);
        cmp_s(", UC_YELLOW, bg);\n    let v");
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
            cmp_s(", 10);\n    uc_text(cx, y, b");
            cmp_i(fi);
            cmp_s(", UC_CYAN, bg);\n    let v");
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
            if kind == 3 {
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
        } else {
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
        }
        }
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
                            return syntax_error();
                        }
                    }
                }
            }
        }
        next_token();
        let width: i64 = 10;
        if tok_is("width") == 1 {
            next_token();
            if gv(K_TKIND) != 2 { return syntax_error(); }
            width = gv(K_TIVAL);
            next_token();
        }
        if tok_is(";") == 0 { return syntax_error(); }
        next_token();
        let nf: i64 = CMP_NF;
        if nf >= 64 { return err_at2("too many component fields (limit 64)", gv(K_LINE), gv(K_COL)); }
        CMP_TY[nf] = kind;
        CMP_WD[nf] = width;
        if kind == 0 { CMP_CC[nf] = 3; }
        else { if kind == 1 { CMP_CC[nf] = 6; } else { if kind == 2 { CMP_CC[nf] = 2; } else { if kind == 3 { CMP_CC[nf] = 9; } else { CMP_CC[nf] = 11; } } } }
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
    cmp_s("_buf: [64] i64 = 0;\n");
    fi = 0;
    while fi < nf2 {
        cmp_setter(compo, heap + O_NAMES + CMP_FN[fi], CMP_TY[fi]);
        fi = fi + 1;
    }
    cmp_s("fn ");
    cmp_s(compo);
    cmp_s("_row(x: i64, y: i64, fg: i64, bg: i64) -> i64 {\n    let cx: i64 = x;\n");
    fi = 0;
    while fi < nf2 {
        cmp_row_field(compo, heap + O_NAMES + CMP_FN[fi], CMP_TY[fi], CMP_WD[fi], CMP_CC[fi], fi);
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