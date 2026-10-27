# 墨语言构建入口
#
#   make          从汇编重建 seed，再编译出 moc
#   make test     跑全部测试
#   make boot     验证自举闭环
#   make all      上面三步
#   make clean    清掉产物

SEED := bin/seed
MOC  := bin/moc
ASM  := src/asm
# MO2X 此前**从未定义**，于是所有写 `依赖 $(MO2X)` 的目标（armfstest /
# armfsmut / pkgarmtest ...）展开后那个依赖是空串，根本不会构建 mo2x。
# 在开发目录里 bin/mo2x 早就编好了，所以一直看不出来；全新 checkout 直接
# "bin/mo2x: No such file or directory"（v1.154 解包复跑时暴露）。
MO2X := bin/mo2x

.DEFAULT_GOAL := all

bin/mo2x: $(MOC) tools/mo2x.mo | bin
	./bin/moc tools/mo2x.mo bin/mo2x

mo2x: bin/mo2x

.PHONY: all test boot mkrootfs rootfscheck rootfstest a64test a64mut a64ldtest a64ldmut a64datatest a64datamut a64bsstest a64bssmut a64artest a64armut a64arithtest a64arithmut a64svctest a64svcmut unused pkgclosuretest freshbuild freshmut seedalign clean check codesize f64test mo2x sitetest wavtest bignumtest nntest cnntest adtest adaudit targets molsmotest strcmpmut escxmut kernrun uefirun armrun riscvrun s390xrun armfstest armfsmut pkgarmtest switchmut lsptest lsmotest dwvar dwmotest dwbig dwmut dbgtest modcondtest modmut2 ffitest threadtest shtest pkgtest proftest molink molinktest selfcontained sync sync-check sketchtest sketchmut cbfcumut cbfmergemut qdigestmut fenwtest fenwmut hhtest hhmut sysnocheck pkgmgrtest pkgmgrmut pkgv2test pkgv2mut pkgv3test pkgv3mut uspacetest uspacemut uspace2test uspace2mut aifixmut adopmut kern64run kern64test kern64mut kern64systest kern64sysmut kern64disktest kern64diskmut a64mmutest a64mmumut a64irqtest a64irqmut a64exectest a64execmut a64pkgtest a64pkgmut a64xself a64xselfmut mokerntest mokernmut mokern64 mokern64mut

all: sync-check seedalign $(MOC) boot freshbuild freshmut test motools check sitetest wavtest bignumtest nntest cnntest adtest adaudit fmathtest fmathrange fmathmut floattest floatlitmut molinktest molsmotest lsmotest csptest selecttest timertest timermut iototest scopetest actortest rbxtest dwmotest dwbig dwmut deepclosmut modbtest modtypetest modcondtest modmut2 hdcmut hdcrtmut sdmmut sdmseqmut utf8mut strmut strcmpmut escxmut scatmut gctest gctmut aiotest lftest lfmut nschecktest nscheckmut formut switchmut tbtest tbmut lshtest lshmut hlltest hllmut sammut acmut unitest uninormtest uninormmut unimut importastest importasmut sketchtest sketchmut cbfcumut cbfmergemut qdigestmut fenwtest fenwmut segtest segmut hhtest hhmut pkgclosuretest remut targets kernrun uefirun armrun riscvrun s390xrun armfstest armfsmut pkgarmtest sysnocheck pkgmgrtest pkgmgrmut pkgv2test pkgv2mut pkgv3test pkgv3mut uspacetest uspacemut uspace2test uspace2mut aifixmut adopmut kern64run kern64test kern64mut kern64systest kern64sysmut kern64disktest kern64diskmut a64irqtest a64irqmut a64exectest a64execmut a64pkgtest a64pkgmut a64xself a64xselfmut mokerntest mokernmut mokern64 mokern64mut
#  src/compiler.mo 是 src/mo/compiler_part{1..5}.mo 的**拼接产物**。
#  曾经出现过：只改了 compiler.mo，没同步回 src/mo/ ——
#  于是任何人执行文档里那句 cat 拼接，就会把修复静默还原。
#  这里用一条守护把这件事钉死：拼接结果必须与 compiler.mo 逐字节相同。
# ---------------------------------------------------------------------------
sync-check:
	@cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
	     src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
	     src/mo/compiler_part5.mo > /tmp/mo_joined.mo
	@if ! diff -q /tmp/mo_joined.mo src/compiler.mo >/dev/null; then \
	    echo "✗ src/mo/ 拼接结果与 src/compiler.mo 不一致。"; \
	    echo "  改编译器要改 src/mo/ 下的片段，然后 make sync 重新拼接。"; \
	    diff /tmp/mo_joined.mo src/compiler.mo | head -10; \
	    exit 1; \
	fi
	@echo "✓ 拼接一致"

sync:
	@cat src/mo/compiler_part1.mo src/mo/compiler_part2.mo \
	     src/mo/compiler_part3.mo src/mo/compiler_part4.mo \
	     src/mo/compiler_part5.mo > src/compiler.mo
	@echo "已重新拼接 src/compiler.mo"

# 额外自检：库依赖独立可编译 + 两个后端结果一致
check:
	@bash tools/projcheck.sh
	@bash tools/sysnocheck.sh
	@bash tools/pkgarmtest.sh
	@bash tools/pkgmgrtest.sh
	@bash tools/pkgv2test.sh
	@bash tools/pkgv3test.sh
	@bash tools/multibackend_test.sh
	@bash tools/nschecktest.sh
	@bash tools/kern64systest.sh
	@bash tools/a64test.sh
	@bash tools/a64artest.sh
	@bash tools/a64svctest.sh
	@bash tools/a64exectest.sh
	@bash tools/a64irqtest.sh
	@bash tools/a64pkgtest.sh
	@bash tools/a64xself.sh
	@bash tools/mokerntest.sh
	@python3 tools/unused.py --all

# bin/ 与 build/ 只装构建产物；git 不跟踪空目录，全新 checkout 时它们不存在。
# 那时 ld 报的是 "cannot open output file ../../bin/seed" ——
# 报错落在 ld 上而不是"目录缺失"，很容易被误读成链接器坏了。这里统一兜住。
# import "x.mo" as N; —— 模块命名空间（8 项断言 / 5 变异）
importastest: $(MOC)
	@bash tools/importastest.sh

unused:
	@python3 tools/unused.py --all

pkgclosuretest: $(MOC)
	@bash tools/pkgclosuretest.sh

sketchtest: $(MOC)
	@bash tools/sketchtest.sh

sketchmut: $(MOC)
	@bash tools/sketchmut.sh

# cbfcu —— Counting Bloom Filter + Conservative Update（34 项断言 / 5 变异捕获）
cbfcumut: $(MOC)
	@bash tools/cbfcumut.sh

# cbfmerge —— 三种草图结构、三种合并运算（21 项断言 / 6 变异全捕获）
cbfmergemut: $(MOC)
	@bash tools/cbfmergemut.sh

qdigestmut: $(MOC)
	@bash tools/qdigestmut.sh

# hh —— Heavy Hitters：Misra-Gries（下界）+ Space-Saving（上界）（45 项断言 / 7 变异全捕获）
hhtest: $(MOC)
	@bash tools/hhtest.sh

hhmut: $(MOC)
	@bash tools/hhmut.sh

# fenw —— Fenwick 树 / BIT（24 项断言 / 6 变异全捕获）
fenwtest: $(MOC)
	@bash tools/fenwtest.sh

fenwmut: $(MOC)
	@bash tools/fenwmut.sh

# seg —— 线段树 + 懒标记（150 项断言 / 6 变异全捕获）
segtest: $(MOC)
	@bash tools/segtest.sh

segmut: $(MOC)
	@bash tools/segmut.sh

importasmut:
	@bash tools/importasmut.sh

# ac —— Aho–Corasick 多模式匹配（43 项断言 / 5 变异）
acmut:
	@bash tools/acmut.sh

# uninorm —— Unicode NFC/NFD（19 项断言 + Python 全量对照 / 5 变异）
uninormtest: $(MOC)
	@bash tools/uninormtest.sh
uninormmut:
	@bash tools/uninormmut.sh

# nscheck —— 模块命名空间缺失下的「歧义调用」检查
nschecktest:
	@bash tools/nschecktest.sh
nscheckmut:
	@bash tools/nscheckmut.sh

# 泛型 trait bound：正例 + 无 bound 对照 + 三个负例
tbtest: $(MOC)
	@bash tools/tbtest.sh
# 4 个变异：永不拒绝 / 恒已 impl / 不记录 bound / 误拒方向
tbmut: $(MOC)
	@bash tools/tbmut.sh

# for 循环：continue 跳 step / break / 作用域 / 嵌套，5 个变异
formut:
	@bash tools/formut.sh

# switch：跳转表 vs 比较链 / 不穿透 / continue 作用于外层循环，5 个变异
switchmut:
	@bash tools/switchmut.sh

bin build:
	@mkdir -p $@

$(SEED): $(ASM)/base.s $(ASM)/lex.s $(ASM)/sym.s $(ASM)/expr.s $(ASM)/stmt.s $(ASM)/main.s | bin
	@echo "== 汇编 seed =="
	cd $(ASM) && for f in base lex sym expr stmt main; do as -o $$f.o $$f.s; done
	cd $(ASM) && ld -o ../../$(SEED) base.o lex.o sym.o expr.o stmt.o main.o

$(MOC): $(SEED) src/compiler.mo | bin
	@echo "== 用 seed 编译 compiler.mo =="
	./build.sh self $(SEED)

test: $(MOC)
	bash tests/run.sh $(MOC) | tail -3

# 全新环境可构建性：只带源码、不带 bin/ 与 build/，验证能从头建出同一个 moc
freshbuild: $(MOC)
	@bash tools/freshbuild.sh

# 上面那条必须证明自己不是空转：去掉 | bin 后它必须真的失败
freshmut: $(MOC)
	@bash tools/freshmut.sh

# seed 冒烟：改 seed 后立刻跑（秒级，不依赖 boot）
seedsmoke:
	@bash tools/seedsmoke.sh

# 墨语言版（1.95 起取代 Python 版）：守护自举的工具本身不该由别的语言写
seedalign: $(MOC)
	@mkdir -p build
	@./bin/moc tools/seedalign.mo build/seedalign.elf && ./build/seedalign.elf .

seedalignpy:
	@python3 tools/seedalign.py

boot: $(MOC)
	bash verify_bootstrap.sh

# 代码体积度量：给出基线与各冗余模式占比，让优化可量化、可回归
codesize: $(MOC)
	@python3 tools/codesize.py bin/moc

# 系统级目标自检：内核 / UEFI / Windows PE / 安卓原生 / 服务器包 / 内核模块 / 包管理器
# HDC：单独跑 + 变异验证（只跑 make test 证明不了断言非空转）
hdctest: $(MOC)
	@bash tools/hdctest.sh

# LSH：MinHash / SimHash / banding（只跑 make test 证明不了断言非空转）
lshtest: $(MOC)
	@bash -c 'rm -rf /tmp/mot && mkdir -p /tmp/mot && cp lib/*.mo /tmp/mot/ && cp tests/137_lsh.mo /tmp/mot/test.mo && cd /tmp/mot && "$(CURDIR)/bin/moc" test.mo out.elf && ./out.elf'

lshmut: $(MOC)
	@bash tools/lshmut.sh

# HLL：HyperLogLog 基数估计
hlltest: $(MOC)
	@bash -c 'rm -rf /tmp/mot && mkdir -p /tmp/mot && cp lib/*.mo /tmp/mot/ && cp tests/138_hll.mo /tmp/mot/test.mo && cd /tmp/mot && "$(CURDIR)/bin/moc" test.mo out.elf && ./out.elf'

hllmut: $(MOC)
	@bash tools/hllmut.sh
sammut:
	@bash tools/sammut.sh

# uni —— Unicode 字符分类与大小写转换（73 项断言 / 全量独立参照 / 5 变异）
unitest: $(MOC)
	@bash tools/unitest.sh
unimut:
	@bash tools/unimut.sh

hdcmut: $(MOC)
	@bash tools/hdcmut.sh

sdmmut: $(MOC)
	@bash tools/sdmmut.sh

sdmseqmut: $(MOC)
	@bash tools/sdmseqmut.sh

# HDC retrain：单独跑 + 变异验证
hdcrttest: $(MOC)
	@bash tools/hdcrttest.sh

hdcrtmut: $(MOC)
	@bash tools/hdcrtmut.sh

targets: $(MOC) $(MO2X)
	@mkdir -p build
	@bash tools/targets_test.sh

# 内核运行时验证（在 CPU 模拟器里真跑，不是只验产物结构）
kernrun: $(MOC) $(MO2X)
	@bash tools/kernrun_test.sh

# UEFI 运行时验证（手工搭最小 UEFI 环境后真跑）
uefirun: $(MOC) $(MO2X)
	@bash tools/uefirun_test.sh

# ARM64 / Android 原生运行时验证（模拟 Linux syscall 表后真跑）
armrun: $(MOC) $(MO2X)
	@bash tools/armrun_test.sh

armfstest: $(MOC) $(MO2X)
	@bash tools/armfstest.sh

armfsmut: $(MOC) $(MO2X)
	@bash tools/armfsmut.sh

# pkgarm —— 包管理在安卓上的最小地基（21 项断言 / 两端对照）
pkgarmtest: $(MOC) $(MO2X)
	@bash tools/pkgarmtest.sh

# 号表核对：mo2x 的 x86→asm-generic 翻译表与内核头文件逐条比对
aifixmut:
	@bash tools/aifixmut.sh

sysnocheck: $(MOC) $(MO2X)
	@bash tools/sysnocheck.sh

# 包管理器：安卓（ARM64 模拟器）与 x86-64 真机两端端到端
pkgmgrtest: $(MOC) $(MO2X)
	@bash tools/pkgmgrtest.sh

pkgmgrmut: $(MOC) $(MO2X)
	@bash tools/pkgmgrmut.sh

pkgv2test: $(MOC) $(MO2X)
	@bash tools/pkgv2test.sh

pkgv2mut: $(MOC) $(MO2X)
	@bash tools/pkgv2mut.sh

pkgv3test: $(MOC) $(MO2X)
	@bash tools/pkgv3test.sh

pkgv3mut: $(MOC) $(MO2X)
	@bash tools/pkgv3mut.sh

uspacetest: $(MOC) $(MO2X)
	@bash tools/uspacetest.sh

uspacemut: $(MOC) $(MO2X)
	@bash tools/uspacemut.sh

uspace2test: $(MOC) $(MO2X)
	@bash tools/uspace2test.sh

uspace2mut: $(MOC) $(MO2X)
	@bash tools/uspace2mut.sh

# autodiff「漏加载 op」变异守护（只改库，不需重建编译器）
adopmut: $(MOC)
	@bash tools/adopmut.sh

# RISC-V 64 运行时验证
riscvrun: $(MOC) $(MO2X)
	@bash tools/riscvrun_test.sh

# 神经网络
nntest: $(MOC)
	@bash tools/nntest.sh

# 自动微分（语言级权重架构）
adaudit: $(MOC)
	@bash tools/adaudit.sh

adtest: $(MOC)
	@bash tools/adtest.sh
	@echo "--- 字符串插值 ---"
	@bash tools/fstrtest.sh

# f64 数学库（ULP 交叉验证 + 范围规约曲线）
# ⚠️ 这两个脚本 1.113 就写好了，但**一直没接进 Makefile**，
#    所以从未在 CI 里跑过 —— 结果 fmathtest 的阈值判断写错也无人发现。
#    "脚本存在"不等于"被验证"，必须接到 all 链上。
fmathtest: $(MOC)
	@bash tools/fmathtest.sh

fmathrange: $(MOC)
	@bash tools/fmathrange.sh

# 🔴 v1.115 发现：fmathmut 早在 1.114 就被写进 all 链，却**从来没有目标定义**。
#    于是 `make all` 走到它就 "No rule to make target" 直接失败 ——
#    也就是说 all 链从来没真正跑通过，而所有人都在报"各分项全过"。
#    "写进 all" 和 "接上了 all" 是两件事，必须能自动验证（见 projcheck 第 10 项）。
fmathmut: $(MOC)
	@bash tools/fmathmut.sh

# 浮点字面量：跨实现逐位比对 + 变异验证
#   同上：脚本 1.114 就写好了，1.115 之前没接进 Makefile，等于没跑过。
floattest: $(MOC)
	@bash tools/floattest.sh

floatlitmut: $(MOC)
	@bash tools/floatlitmut.sh

# str 拼接：单独跑 + 变异验证（只跑 make test 证明不了 '+' 走的是拼接）
scatmut: $(MOC)
	@bash tools/scatmut.sh

# LSP（编辑器语义能力）
lsptest:
	@python3 tools/lsptest.py

# 墨语言版 LSP 服务器：编译 tools/mols.mo，再用同一套 lsptest 验证
molsmotest: $(MOC)
	@bash tools/molsmo_test.sh

# 墨语言版 LSP **驱动**：编译 tools/lsptest.mo，spawn bin/mols 跑同一套 27 项
# 并与 Python 驱动 lsptest.py 对同一个服务器交叉验证
lsmotest: $(MOC)
	@bash tools/lsmo_test.sh

# 墨语言自己写的 DWARF 校验器：与 Python 版 dwvar.py 跑同一份 elf
dwmotest: $(MOC)
	@bash tools/dwmotest.sh

# 墨语言自己写的**调试器**：ptrace 起停进程、下断点、按 fbreg 读变量、
# 回溯调用栈。自包含生态此前缺的最后一块。
modbtest: $(MOC)
	@bash tools/modbtest.sh

# p 命令按 DWARF 类型打印：结构体/数组/bool/byte/f64 各自成形。
# 此前一律按 8 字节整数打，byte/bool/f64 全都"看起来有值"却全是错的。
modtypetest: $(MOC)
	@bash tools/modtypetest.sh

# 条件断点（b <位置> if <表达式>）与观察点（watch <变量>）。
# 核心是防静默：条件写错会被当成"不成立"而永不触发，与"没跑到"无法区分。
modcondtest: $(MOC)
	@bash tools/modcondtest.sh

# 变异验证：把条件判断改恒真、把观察点比较反号，确认 modcondtest 真的变红
modmut2: $(MOC)
	@bash tools/modmut2.sh

# 拿 dwmo -s 扫真实大程序 bin/moc 本体（覆盖面：356 函数 / 4 万条例指令）
dwbig: $(MOC)
	@bash tools/dwbig.sh

# 端到端变异验证：故意把编译器的行号登记弄坏，证明 dwbig 里的 -L 不是空转
# （会临时改 src/compiler.mo，任何退出路径都会还原）
dwmut: $(MOC)
	@bash tools/dwmut.sh

# -g 变量位置校验（与机器码比对）
dwvar: $(MOC)
	@python3 tools/dwvar.py

# C FFI 端到端（真链接 + 真运行）
ffitest: $(MOC)
	@bash tools/ffitest.sh

# 线程与同步（真并发 + 无锁对照）
threadtest: $(MOC)
	@bash tools/threadtest.sh

# CSP 并发：协程调度器 + channel（需 molink + libc）
csptest: $(MOC) molink
	@bash tools/csptest.sh

# 异步 I/O：epoll reactor + 协程（需 molink + libc）
# 重复跑 15 次：漏唤醒概率约 1/5，单次通过说明不了任何事。
aiotest: $(MOC) molink
	@bash tools/aiotest.sh

# 变异验证：改坏 aio.mo 确认 aiotest 会变红。不进 all —— 要跑 2×15 次。
aiomut: $(MOC) molink
	@bash tools/aiomut.sh

# 变异验证：逐个改坏 csp.mo 确认测试会变红。
# 不进 all —— 要重编 3 次并跑满死锁超时，约 2~3 分钟。
cspmut: $(MOC) molink
	@bash tools/cspmut.sh

selecttest: $(MOC) molink
	@bash tools/selecttest.sh

selectmut: $(MOC) molink
	@bash tools/selectmut.sh

# 分层时间轮 + select 超时（需 molink + libc：pthread / usleep）
lftest: $(MOC) molink
	@bash tools/lftest.sh

lfmut: $(MOC) molink
	@bash tools/lfmut.sh

timertest: $(MOC) molink
	@bash tools/timertest.sh

timermut: $(MOC) molink
	@bash tools/timermut.sh

# 带超时的异步 I/O：select { I/O 就绪, 定时器 } + O(1) 取消。
# 核心断言是 cncl=6 与 fired=6 —— 证明定时器真的被取消而不是空转。
iototest: $(MOC) molink
	@bash tools/iototest.sh

iotomut: $(MOC) molink
	@bash tools/iotomut.sh

# 结构化并发（nursery）：join 语义、取消双向传播、错误冒泡。
# 需 molink + libc（ucontext / pthread）。
scopetest: $(MOC) molink
	@bash tools/scopetest.sh

# Actor 模型 + 监督树（需 molink + libc：ucontext / pthread）
# 🔴 这个库此前从未被任何测试跑过 —— 参见脚本开头的注释。
actortest: $(MOC) molink
	@bash tools/actortest.sh

# 变异验证：逐个改坏 scope.mo。不进 all —— 要重编 6 次。
scopemut: $(MOC) molink
	@bash tools/scopemut.sh

# 深层闭包（3~5 层捕获）：变异验证（要重编 5 次）
deepclosmut: $(MOC)
	@bash tools/deepclosmut.sh

# 保守式 mark-sweep GC（需 molink + libc：寄存器根靠 setjmp）
gctest: $(MOC) molink
	@bash tools/gctest.sh

# 变异验证：逐个改坏 gc.mo 确认测试会变红
gctmut: $(MOC) molink
	@bash tools/gctmut.sh

# 变异验证：逐个改坏 regex.mo 确认测试会变红
remut: $(MOC) molink
	@bash tools/remut.sh

# rbx 保存/恢复的端到端回归：协程直接 return（不调 csp_exit）
# 需 molink + libc（ucontext 在 libc 里）
rbxtest: $(MOC) molink
	@bash tools/rbxtest.sh

# 被 C 调用：墨语言编译成共享库，C 链接并调用
shtest: $(MOC)
	@bash tools/shtest.sh

# 包管理器：用本地 git 仓库验证（无需网络）
pkgtest: $(MOC)
	@bash tools/pkgtest.sh

# 性能分析器：自动插桩 (-p) 与 prof.mo
proftest: $(MOC)
	@bash tools/proftest.sh

# 卷积神经网络
cnntest: $(MOC)
	@bash tools/cnntest.sh

# s390x（大端）运行时验证
s390xrun: $(MOC) $(MO2X)
	@bash tools/s390xrun_test.sh

# 用 Python 当标准答案，逐字节比对大数计算
bignumtest: $(MOC)
	@bash tools/bignumtest.sh

# 端到端验证 examples/wavinfo.mo：真解析一个 WAV，并覆盖三种错误路径
wavtest: $(MOC)
	@bash tools/wavtest.sh
	@echo "--- 类的实战检验 ---"
	@bash tools/wavobjtest.sh

# 墨语言自己写的静态链接器（不调 ld、不调 as）
molink: $(MOC)
	./bin/moc tools/molink.mo -nostdlib bin/molink

# 自链接器与 GNU ld 的等价性：同一批 .o 两种链接，逐字节比对输出
molinktest: molink
	@bash tools/molinktest.sh

# 自包含度审计：工具链里有多少是墨语言自己写的
selfcontained: $(MOC)
	@./bin/moc tools/selfcontained.mo /tmp/selfcontained.elf && /tmp/selfcontained.elf

# 用真实内容验证最大的示例应用 site.mo。
# 单元测试覆盖不到目录遍历 / front-matter / Markdown 渲染 / 排序 / 转义
# 这些链路的组合，只有真生成一次站点才知道对不对。
sitetest: $(MOC)
	@bash tools/sitetest.sh

# 墨语言版工具 vs Python 版：两套独立实现必须给出一致结论
motools: $(MOC)
	@bash tools/motools_test.sh

clean:
	rm -f $(SEED) $(MOC) $(ASM)/*.o

# 代码段体积构成：按指令统计占比，判断优化方向
# 墨语言版：自己解析 ELF + 自己解码指令，不调 readelf / objdump / Python
codecompose: $(MOC)
	@mkdir -p build
	@./bin/moc tools/codecompose.mo build/codecompose.elf && ./build/codecompose.elf bin/moc

codecomposepy: $(MOC)
	@python3 tools/codecompose.py bin/moc

# 性能基线：与 docs/perf_baseline.txt 对比
benchtest: $(MOC)
	@bash tools/benchtest.sh

# 微基准：魔数除法 vs idiv 的成本差（交替测量以压住噪声）
divcost: $(MOC)
	@bash tools/divcost.sh

# 微基准：栈传递 vs 寄存器传递的成本差
passcost:
	@bash tools/passcost.sh

# UTF-8：SWAR 校验的变异验证（只跑 make test 证明不了断言非空转）
utf8mut: $(MOC)
	@bash tools/utf8mut.sh

strmut: $(MOC)
	@bash tools/strmut.sh
strcmpmut: $(MOC)
	@bash tools/strcmpmut.sh

escxmut: $(MOC)
	@bash tools/escxmut.sh

# ARM64 裸机内核：构建 + 在 CPU 模拟器里真跑
kern64run: bin/mo2x
	bash tools/kern64test.sh

# all 链里引用了这两个目标但此前没定义 —— make all 会直接失败。
# 按 projcheck 第 10 项报出来的，属于"接线写了、目标没写"。
kern64test: bin/mo2x
	@bash tools/kern64test.sh

kern64mut: bin/mo2x
	@bash tools/kern64mut.sh

# ARM64 裸机系统：内核 + RAMFS + shell + 包管理（真交互，注入按键）
kern64systest: bin/mo2x
	bash tools/kern64systest.sh

kern64sysmut: bin/mo2x
	@bash tools/kern64sysmut.sh

# ARM64 裸机持久存储：virtio-blk + 跨次启动保留的文件系统
kern64disktest: bin/mo2x
	bash tools/kern64disktest.sh

kern64diskmut: bin/mo2x
	@bash tools/kern64diskmut.sh

# 墨语言自举 aarch64 汇编器：不经 C 编译器/as/ld，直接 emit 机器码 + ELF
a64test:
	@bash tools/a64test.sh

a64mut:
	@bash tools/a64mut.sh

# 墨语言自举 aarch64 链接器：解析 ET_REL、布局、按 AArch64 规范算重定位
a64ldtest:
	@bash tools/a64ldtest.sh

a64ldmut:
	@bash tools/a64ldmut.sh

a64datatest:
	@bash tools/a64datatest.sh

a64datamut:
	@bash tools/a64datamut.sh

# .bss：占内存不占文件（SHT_NOBITS），filesz < memsz
a64bsstest:
	@bash tools/a64bsstest.sh

a64bssmut:
	@bash tools/a64bssmut.sh

a64artest:
	@bash tools/a64artest.sh

a64armut:
	@bash tools/a64armut.sh

# 第二批：算术与条件（udiv/sdiv/msub/lsr/asr/csel/cbz/cbnz/subs/adds/...）
a64arithtest:
	@bash tools/a64arithtest.sh

a64arithmut:
	@bash tools/a64arithmut.sh

# 特权级分离：EL1 内核 + EL0 用户 + svc 系统调用（异常向量表 / eret / 陷入）
a64svctest:
	@bash tools/a64svctest.sh

a64svcmut:
	@bash tools/a64svcmut.sh

a64mmutest:
	@bash tools/a64mmutest.sh

a64mmumut:
	@bash tools/a64mmumut.sh

a64irqtest:
	@bash tools/a64irqtest.sh

a64irqmut:
	@bash tools/a64irqmut.sh

a64exectest:
	@bash tools/a64exectest.sh

a64execmut:
	@bash tools/a64execmut.sh

a64pkgtest:
	@bash tools/a64pkgtest.sh

a64pkgmut:
	@bash tools/a64pkgmut.sh

# 墨语言写的 AArch64 汇编器，**跑在 ARM64 上**再产出 ARM64 系统。
# 此前 a64 系列只验证"能产出 ARM64 代码"，没验证"墨语言写的工具能在 ARM64 上跑"。
a64xself: mo2x
	@bash tools/a64xself.sh
	@bash tools/mokerntest.sh

a64xselfmut:
	@bash tools/a64xselfmut.sh

mokerntest: $(MOC)
	@bash tools/mokerntest.sh

mokernmut: $(MOC)
	@bash tools/mokernmut.sh

# 自举内核**跑在 ARM64 上**，再产出 ARM64 裸机内核（mokerntest 只证明
# "墨语言能造内核"，生成器本身跑在 x86-64）。需要 zig 交叉编译器。
# 🔴 这里**不能**依赖 mo2x：make 会比较 mtime，解包后 bin/mo2x 的时间戳
# 与 tools/mo2x.mo 相同（或更早），于是必然触发 "bin/mo2x: tools/mo2x.mo"
# 重建 —— 而重建会撞上编译器容量缺陷（no main function，见 docs/mokern64.md）
# 并失败。判据本身只需要"有一个能用的 bin/mo2x"，发布包里带着它；
# 缺失时的处理放在脚本里，那里能给出指向文档的明确说明。
mokern64:
	@bash tools/mokern64.sh

mokern64mut:
	@bash tools/mokern64mut.sh

mkrootfs: mo2x
	bash tools/mkrootfs.sh /tmp/mo_rootfs

rootfscheck: mkrootfs
	bash tools/rootfscheck.sh /tmp/mo_rootfs

rootfstest: mo2x
	bash tools/rootfstest.sh
