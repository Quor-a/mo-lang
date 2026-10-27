# 工具索引

版本 1.9.0

## 构建与验证

| 工具 | 作用 |
|---|---|
| `make` | 主入口：seed → moc |
| `make sync-check` | 校验 `src/mo/` 拼接产物与 `src/compiler.mo` 一致 |
| `make sync` | 从 `src/mo/` 重新拼接出 `src/compiler.mo` |
| `build.sh` | 底层构建（seed / self） |
| `verify_bootstrap.sh` | 自举三级闭环验证 |
| `tests/run.sh` | 主测试套件 |

## 自检（每一类都针对一种"静默漂移"）

| 工具 | 防的是什么 |
|---|---|
| `tools/projcheck.sh` | **总入口**：下面 5 项 + 拼接一致 + 版本号 + 脏文件，共 8 项 |
| `tools/depcheck.sh` | 标准库缺少自己的 `import`（靠主文件顺带引入才"能编译"） |
| `tools/multibackend_test.sh` | 同一程序在多个后端下退出码不一致 |
| `tools/sitetest.sh` | 用真实内容验证 `examples/site.mo`：目录遍历 / front-matter / Markdown 渲染 / 排序 / 转义 / RSS |
| `tools/diag_android.sh` | 在 ARM64 + qemu 下定位测试失败：md5 比对，区分"编译侧字节不同"还是"运行时环境差异" |
| `tools/bignumtest.sh` | 用 **Python 当标准答案**，与墨语言的大数计算逐字节比对 |
| `tools/wavtest.sh` | 端到端验证 `examples/wavinfo.mo`：真解析 WAV + 三种错误路径 |
| `tools/diag_runtime.sh` | 打印 `argc` / 栈未初始化值 / `brk` 地址，找出 qemu、proot 与原生 Linux 的环境差别 |
| `tools/fmttest.sh` | 格式化改写了代码（判据：代码段逐字节相同 + 幂等） |
| `tools/dbgtest.sh` | `-g` 影响程序行为（判据：开与不开运行结果相同） |
| `tools/codesize.sh` | 优化效果无法量化 |
| `tools/ffitest.sh` | 调用真实 C 库（printf / malloc / strcmp / qsort）并逐字比对输出 |
| `tools/mopkgmo_test.sh` | 墨语言版包管理器的端到端验证（本地 git 仓库真克隆） |
| `tools/molinktest.sh` | **自链接器与 GNU ld 不一致**（同一批 `.o` 两种链接，逐字节比对 stdout + 退出码；含变异验证） |
| `tools/fmathtest.sh` | 数学函数精度是**静默**的：漏一项级数、系数写错一位，结果都"看起来是个数"。用 Python（C library，正确舍入）当标准答案，误差按 **ULP**（位模式整数距离）衡量，2200 个测试点。按函数分别给阈值（`log10` 给 4），统一阈值会逼着把合理的派生误差伪装成通过 |
| `tools/fmathrange.sh` | sin/cos 范围规约误差 vs `|x|` 的曲线。**判据被反转过一次**：第一版要求"误差必须随 `|x|` 增长"，因为实测确实如此（2^21 时 4.9e7 ulp）—— 但那其实是 bug（π/2 分裂没做低位清零），被误记成"固有损失"。修好后判据改为"所有量级都 ≤2 ulp（平坦）" |
| `tools/fmathmut.sh` | 变异验证：把 π/2 换回完整 53 位最近双精度值（就是 1.114 抓到的那个 bug），确认 `fmathrange` 会红。否则"全绿"可能只是判据没在盯归约 |

`projcheck` 是这轮补的。此前每一类漂移都真实发生过：
`src/mo/` 与 `compiler.mo` 漂移过（1.9.0 补的修复差点丢失）、
标准库副本与 `lib/` 漂移过、新库写完无测试引用（matrix / stat 就是）。

**一次性补齐没用，得让它变成红灯。**

## 转译与工程

| 工具 | 作用 |
|---|---|
| `tools/mo2x.mo` | 一份前端 + 14 个发射器（c / cfs* / js / py / perl / java / go / rust / cs / swift / ruby / lua / php） |
| `tools/cross.sh` | 交叉编译：先找 `${TRIPLET}-gcc`，没有就用 `zig cc` |
| `tools/android.sh` | 生成 Android 工程（java / ndk / web 三条路径） |
| `tools/mobuild.sh` | 递归收集 import，打印依赖图 |
| `tools/mo.sh` | 统一命令行驱动（9 个子命令） |
| `tools/fmt.mo` | 格式化（只调缩进与行尾） |
| `tools/install.sh` | 安装到 `$PREFIX` |
| `tools/molink.mo` → `bin/molink` | **墨语言自己写的静态链接器**：不调 `ld`、不调 `as`，自己解析 ELF 并注入 `exit` stub |
| `tools/mopkgcli.mo` | 包管理器命令行入口（墨语言实现） |
| `tools/selfcontained.mo` | 自包含度审计：工具链里多少是墨语言自己写的（它自己也必须是墨语言写的，否则数字偏高） |

## 编辑器与 CI

| 路径 | 内容 |
|---|---|
| `tools/editor/` | Vim 语法高亮、VSCode 语法高亮、LSP 配置片段 |
| `tools/ci/` | GitHub Actions 工作流 |
