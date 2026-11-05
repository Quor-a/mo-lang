# Mo 语言发布说明模板

## 版本 `<VERSION>`

### 下载
每个资产都有 SHA256 校验和（`checksums.txt`）与 SSH 签名（`.sig`）。
校验与验签方法见下方。

| 资产 | 说明 |
|------|------|
| `moc` | Mo 编译器（x86-64 Linux，自举；静态链接） |
| `mo-lang-<VERSION>-src.tar.gz` | 完整源码包 |
| `mo-lang-<VERSION>-src.zip` | 完整源码包（Windows 友好） |
| `demo/fib-x86_64-linux` | 演示程序，x86-64 Linux |
| `demo/fib-aarch64-linux` | 演示程序，ARM64 Linux（经 C 后端交叉编译） |
| `demo/fib-aarch64-macos` | 演示程序，Apple Silicon macOS |
| `demo/fib-x86_64-windows.exe` | 演示程序，Windows x64 |

### 校验
```bash
sha256sum -c checksums.txt
```

### 验签
```bash
# 公钥已在仓库 release/SIGNING_KEY.pub
ssh-keygen -Y check-novalidate -n mo-release -s checksums.txt.sig < checksums.txt
```

### 支持平台
- **编译器 (`moc`)**：当前自举编译器生成 x86-64 Linux 原生二进制。
  其它平台请用 C 后端 `mo2x`（Mo → C）+ zig 交叉编译用户程序
  （见 `docs/cross-compile.md`）。演示产物证明用户程序可交叉到
  ARM64 Linux / Apple Silicon macOS / Windows x64 / WASM。

### 变更
<CHANGELOG>