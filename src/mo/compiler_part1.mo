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
