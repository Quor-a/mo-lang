# freshbuild：全新环境可构建性验证

`make freshbuild` / `bash tools/freshbuild.sh`

## 它守护什么

`bin/` 与 `build/` 只装构建产物。git 不跟踪空目录，所以**从零 checkout 出来的
工作区里这两个目录根本不存在**。此时 `make` 会在第一步就失败：

```
cd src/asm && ld -o ../../bin/seed base.o lex.o ... main.o
ld: cannot open output file ../../bin/seed: No such file or directory
```

注意报错落在 `ld` 上，而不是"目录缺失"。它读起来像链接器坏了、或路径写错了，
很容易往错误方向查。

**这个缺陷在本机永远发现不了**——开发机上 `bin/` 一直存在（里面有 moc、mols、
dwmo 等产物），于是构建永远是通的。只有全新环境才撞得上。这是典型的
"本机永远绿"的缺口，必须靠专门模拟全新环境的测试来守。

## 检查方式

脚本在 `/tmp/mofresh` 里只拷源码与构建入口
（`src tools tests lib examples docs` + `Makefile build.sh verify_bootstrap.sh
VERSION CHANGELOG.md mo.toml`），**明确不拷 `bin/`、`build/`、`dist/`**，然后跑
`make boot`。三条断言：

1. 临时目录确实没有 `bin/` —— 没有这条，漏洞一修好这条测试就空转了
2. `make boot` 在全新环境下成功
3. 全新构建出的 `bin/moc` 与源目录的**逐字节一致**

第 3 条顺带是"可复现构建"的守护：同样一份源码，换个目录从头建，产物必须一样。

## 修法

Makefile 里加一个目录目标，让需要它的规则用 order-only 前置条件声明：

```make
bin build:
	@mkdir -p $@

$(SEED): $(ASM)/base.s ... $(ASM)/main.s | bin
$(MOC): $(SEED) src/compiler.mo | bin
mo2x: $(MOC) | bin
```

用 `|`（order-only）而不是普通前置条件，是因为目录的 mtime 会随内容变化，
普通依赖会让下游目标被无谓地反复重建。

## 变异脚本

`make freshmut` / `bash tools/freshmut.sh`

## 变异验证

必须验证这条测试不是空转。把 `$(SEED)` 规则末尾的 `| bin` 去掉（回到缺陷状态）：

```
通过 1 / 3
  ✗ 全新环境 make boot 失败：
      ld: cannot open output file ../../bin/seed: No such file or directory
  ✗ 未产出 bin/moc
```

报错与最初发现时完全一致——说明这条测试测的正是那个缺陷，不是碰巧通过。

**一次失败的变异尝试值得记下来**：第一版我把目录目标改名（`bin build:` →
`bin build_disabled:`），以为能触发同样的失败，结果脚本仍然 3/3 通过。
原因是 make 对 order-only 前置条件的处理与预期不同：规则名改掉之后它并没有
报错。所以变异必须**直接回到缺陷状态**（去掉 `| bin`），改别的都可能没区分度。
光"改了点东西然后看它失败"是不够的，得确认改的正好是那条因果链。

## 已知限制

- 每次跑都要从头汇编 seed 并用它编译一次 compiler.mo，约一分钟量级，
  所以挂在 `all` 链里而不是 `test` 里
- 只覆盖 `make boot` 这条路径；`make targets`、`make kernrun` 等其他目标的
  目录依赖未逐个验证
- 参照物是源目录的 `bin/moc`；如果源目录产物本身就是脏的，第 3 条会
  "一致地错"。所以它和 `make boot` 是互补的，不能互相替代
