# 墨语言 Mo — 一门从零自举的原创编程语言

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.301.0-blue.svg)](VERSION)

一门静态类型、编译到原生 x86-64 / ARM64 机器码的系统级小语言，编译器**用墨语言自身写成**，
并完成 Stage 0 → 1 → 2 → 3 完整自举闭环。

## 亮点

- 🔁 **完全自举**：手写汇编引导编译器（`bin/seed`）→ 墨语言版编译器（`src/compiler.mo`）→ 编译自身，三级产物字节一致。
- 🧬 **双后端**：原生 x86-64 后端（`moc`）+ 交叉编译到 ARM64 / 安卓（`mo2x`，C 无 libc 落地）。
- 📦 **包管理**：`mopkg`（类 cargo）——`pack` / `publish` / `fetch` / `search` / `list` / `tree` / `verify` / `remove`，支持远程 registry、缓存、sha256 校验、token 鉴权、409 防覆盖。
- 🌐 **网络栈**：HTTP/1.1 keep-alive 客户端（4 槽连接池、gzip、条件请求、读超时）、HTTP 服务器（路由/参数路由/中间件/ETag/日志/配额）、DNS、TCP 自实现。
- 🔐 **密码学**：SHA-256 / CRC32 / Base64 / ChaCha20（纯墨语言实现）。
- 🧮 **标准库**：字符串、数组、JSON、tar、gzip、文件 IO、进程、协程、向量、映射、自动微分（神经网络）、概率数据结构（HLL / Q-digest / LSH / SDM）。
- 🧰 **工具链**：格式化、代码检查、性能基准、交叉编译、内核/安卓/WASM/Windows 目标。

## 快速开始

```bash
# 构建（自举）
./build.sh self bin/seed        # 重建编译器
bash tests/run.sh bin/moc       # 跑全部测试
bash verify_bootstrap.sh        # 验证自举闭环

# 编译并运行一个程序
cat > hello.mo <<'EOF'
import "io.mo";
fn main() -> i64 {
    print("Hello, Mo!\n");
    return 0;
}
EOF
./bin/moc hello.mo hello.elf && ./hello.elf
```

## 包管理（mopkg）

```bash
# 打包并发布到本地 registry
./bin/mopkg pack . mypkg-1.0.0.tar.gz
./bin/mopkg publish mypkg-1.0.0.tar.gz mypkg 1.0.0 http://127.0.0.1:18910 TOKEN

# 依赖安装
./bin/mopkg fetch          # 解析 mo.toml 依赖并安装到 .deps/
./bin/mopkg list           # 列出依赖
./bin/mopkg tree           # 依赖树
./bin/mopkg verify         # 校验锁文件 + 远端 sha 复核
./bin/mopkg search kw URL  # 远程搜索
./bin/mopkg remove pkg --remote URL name TOKEN   # 远端删除
```

运行 registry 服务器：

```bash
./bin/moc examples/regserver256.mo regserver
./regserver                # 监听 18910，提供网页入口 / 搜索 / RSS / 发布 / 下载
```

## 网络编程

```mo
import "httpcli.mo";
import "io.mo";

fn main() -> i64 {
    let buf: [4096] byte = 0;
    let st: i64 = 0;
    let n: i64 = tcp_http_get("http://example.com/", &buf, 4096, &st);
    print(&buf);
    return 0;
}
```

## 编写墨语言

```mo
var counter: i64 = 0;

fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i64 {
    let i: i64 = 0;
    while i < 10 {
        counter = counter + fib(i);
        i = i + 1;
    }
    return counter;
}
```

### 已支持

- 类型：`i64`、`f64`（局部）、`byte`、`bool`、`ptr`、结构体、数组、枚举、类（单继承）
- 运算：`+ - * / % & | ^ ~ ! << >> < <= > >= == != && ||`、一元 `&` 取地址
- 语句：`let` / 赋值 / `if`-`else` / `while` / `return` / `break` / `continue`
- 数组越界检查、常量下标越界编译期拦截
- 模块化：`import "lib.mo";`，多文件共享符号表
- 内建：`load8` `load64` `store8` `store64` `syscall` `argc` `argv`
- 诊断：错误带 `文件名:行:列` + 源码行 + 列指示符
- 复合赋值：`+=` `-=` `*=` `/=` `%=` `&=` `|=` `^=`
- 格式化：`sfmt(dst, f"...")` 插值，仅 `print`/`sfmt` 支持

## 计算库

| 文件 | 提供 |
|---|---|
| `lib/big.mo` | **任意精度整数**：对标 Python 的 int，不溢出 |
| `lib/num.mo` | 大数数论：`big_pow` / `big_modpow` / `gcd` / `factorial` / `isqrt` |
| `lib/random.mo` | xorshift64 伪随机数 |
| `lib/heap.mo` | **真正的 malloc / free / realloc**（空闲链表 + 块分裂 + 合并） |
| `lib/cstd.mo` | 对标 C 标准库：ctype / strtol / memmove / clock / signal |
| `lib/sort.mo` | 排序与查找：`qsort_i64` / `bsearch_i64` / `qsort_str_vec` |
| `lib/pack.mo` | 二进制打包：字节序读写 + 格式串 + hexdump |
| `lib/err.mo` | 结构化错误：统一错误码 + 消息 + 位置 |
| `lib/matrix.mo` | 定点矩阵：乘法 / 转置 / 行列式 |
| `lib/stat.mo` | 均值 / 方差 / 标准差 / 协方差 / 相关 / 线性回归 / 中位数 |
| `lib/vec.mo` / `lib/map.mo` | 动态数组 / 字符串键映射 |
| `lib/autodiff.mo` | **自动微分**：神经网络前向 + 自动反向 + 梯度审计 |
| `lib/hll.mo` / `lib/qdigest.mo` / `lib/lsh.mo` / `lib/sdm.mo` | 概率数据结构 |
| `lib/json.mo` | JSON 解析 / 序列化 |
| `lib/archive.mo` | tar 打包解压 + gzip |
| `lib/crypto.mo` | SHA-256 / CRC32 / Base64 / ChaCha20 |
| `lib/httpcli.mo` / `lib/httpsrv.mo` | HTTP 客户端 / 服务器 |
| `lib/net.mo` / `lib/dns.mo` | TCP / DNS |
| `lib/csp.mo` / `lib/thread.mo` / `lib/aio.mo` | 协程 / 线程 / 异步 |
| `lib/proc.mo` / `lib/shm.mo` | 进程池 / 共享内存 |

## 系统级目标

| 目标 | 命令 | 产物 |
|---|---|---|
| Linux 内核镜像 | `bash tools/kernel.sh examples/kernel.mo k.elf` | Multiboot ELF（GRUB 可加载） |
| Windows 原生 | `bash tools/winbuild.sh app.mo app.exe` | PE32+ |
| 安卓原生 | `bash tools/android_native.sh app.mo app` | 静态 ARM64（**无需 NDK**） |
| 服务器包 | `bash tools/pkgserver.sh app.mo svc` | systemd + deb + rpm + Docker |
| Linux 内核模块 | `bash tools/kmod.sh mod.mo name` | 可编译成 `.ko` |
| 包管理 | `bash tools/mopkg.sh install <git-url>` | `deps/` + `mo.lock` |
| WebAssembly | `bash tools/wasm.sh examples/wasmdemo.mo /tmp/demo.wasm` | 可执行 `.wasm` |

`examples/kernel.mo` 是**真内核**：ring0、写 VGA `0xB8000`、`in/out` 端口读键盘、带最小 shell。

## 目录

```
src/asm/*.s        Stage 0 编译器：手写 GNU as 汇编
src/compiler.mo    墨语言写的墨语言编译器（自举主体）
src/mo/            拆分的编译器源码（part1~part5，cat 后即 compiler.mo）
lib/               标准库
tools/             工具链（fmt、交叉编译、内核模块、安卓等）
examples/          示例程序（含 registry 服务器）
tests/             测试套件（247+ 用例）
docs/              设计文档与教程
verify_bootstrap.sh 自举闭环验证脚本
bin/seed           汇编版编译器
bin/moc            墨语言版编译器
bin/mo2x           ARM64 / 安卓交叉编译器
bin/mopkg          包管理工具
```

## 贡献

欢迎提交 Issue 与 PR！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 开源协议

[MIT License](LICENSE) © 2026 Quor-a