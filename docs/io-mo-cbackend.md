# mo2x C 后端支持 io.mo 全文（v1.1164）

## 之前

`lib/io.mo` 经 mo2x `c` 目标生成的 C 无法编译：
- `fint(v)` / `f64(ip)` 隐式声明（C 前导无内建）
- `str_dup` 把 `ptr` 传给 `memcpy(dst: i64)` —— 指针↔整数硬错误
- `let p: i64 = s + i`（右值 ptr）同理
- mo 定义的 `fn strlen` 与前导 `#define strlen strlen_` 重定义

只有 `moc`（自举编译器）能编含 `print_f64` 的程序。

## 现在

mo2x 生成的 C 全部可编译链接，`print_f64` 语义与 moc 一致。

## 机制

1. **fint/f64 内建**：C 前导加
   `static long long fint(double v){ return (long long)v; }`
   `(long long)double` 向零截断 = cvttsd2si；LLP64 规则一律 long long。
2. **签名表 + 调用点隐式 cast**：emit_sig 注册每个 mo 函数的参数/返回类型
   kind（0=i64, 1=ptr, 2=byte, 3=f64, 4=其他）；普通调用点查表，ptr 形参
   前发 `(unsigned char*)`、i64 形参包 `(long long)(...)`。
   - 🔴 键是函数名 **FNV-1a 哈希**，不是名字指针：POOL 在跨文件
     tokenize 时 `PP=0` 重置，指针键内容被覆盖 → fsg_find 误命中
     （`f64(ip)` 命中 atoi 槽位就是这个坑）。哈希数值跨文件稳定。
3. **初始化 cast**：emit_scalar_or_arr 记录 `LASTTY`（基类型名）；
   emit_local / emit_global 在 `= (` 后按声明类型补 cast。
   - 🔴 `LASTTY == 0` 必须跳过：数组声明路径不设 LASTTY，
     `streq(0, ..)` 解引用空指针 → 段错误。
4. **strlen 冲突**：mo 定义的 `strlen` 发射为 `mo_strlen`
   （调用点同步），避开前导宏。

## 已知限制

- `io.mo` 的 `strstr` 与 libc 内建签名警告（char* vs unsigned char*），
  仅警告不影响结果。
- C 前导 `#define strlen strlen_` 保留 —— extern libc 场景不变；
  mo 程序内的 strlen 调用统一走 mo 自己的实现。
