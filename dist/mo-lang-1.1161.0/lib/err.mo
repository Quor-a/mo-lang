# err —— 结构化错误（用墨语言自己写的）
#
# 为什么需要它：此前整个标准库的错误处理只有两种——
#   1) 打印一句然后 exit(1)     （库不该替调用方决定退出）
#   2) 静默返回 0 或 -1         （"安静地给出错的结果"，最难查）
#
# 两者都不对。这一层提供第三种：调用方能**知道**出了什么错、在哪、
# 并自己决定怎么办。
#
#   if read_file(&path, &buf, cap) < 0 {
#       print(err_msg());          # "cannot open: /x/y.txt"
#       print(" @ "); print(err_where()); print_nl();
#       return err_code();
#   }
#
# 约定：
#   - 函数失败时调用 err_set(code, msg, where) 并返回负值
#   - err_wrap 是"设置并返回 -1"的简写，让失败路径能写成一行
#   - err_ok() 为 1 表示自上次 err_clear() 以来没出错

import "io.mo";
import "str.mo";

var E_CODE: i64 = 0;
var E_MSG: i64 = 0;                 # 指向消息字符串（通常是字面量或静态缓冲）
var E_WHERE: [64] byte = 0;         # 出错位置（模块名 / 函数名）

# 错误码（统一定义，避免各库各写各的）
var E_NONE:  i64 = 0;
var E_IO:    i64 = 1;     # 打开/读写失败
var E_RANGE: i64 = 2;     # 越界 / 长度超限
var E_FORMAT:i64 = 3;     # 格式不对（魔数不符、解析失败）
var E_NOMEM: i64 = 4;     # 分配失败 / 缓冲不够
var E_ARG:   i64 = 5;     # 参数非法
var E_FOUND: i64 = 6;     # 找不到（未找到不算"错误"，但有时要区分）

var E_BUF: [256] byte = 0;          # 需要拼消息时用

fn err_clear() -> i64 {
    E_CODE = E_NONE;
    E_MSG = 0;
    store8(&E_WHERE, 0);
    return 0;
}

fn err_isset() -> i64 {
    if E_CODE == E_NONE { return 0; }
    return 1;
}
fn err_ok() -> i64 {
    if E_CODE == E_NONE { return 1; }
    return 0;
}

fn err_set(code: i64, msg: i64, where: i64) -> i64 {
    E_CODE = code;
    E_MSG = msg;
    if where != 0 { strcpy(&E_WHERE, where); }
    else { store8(&E_WHERE, 0); }
    return 0 - 1;
}

# 设置错误并返回 -1。让失败路径能写成一行：
#     if fd < 0 { return err_wrap(E_IO, "cannot open", "fopen"); }
fn err_wrap(code: i64, msg: i64, where: i64) -> i64 {
    err_set(code, msg, where);
    return 0 - 1;
}

fn err_code() -> i64 { return E_CODE; }

# 消息。没设置过返回 "ok"
fn err_msg() -> i64 {
    if E_MSG == 0 { return "ok"; }
    return E_MSG;
}

fn err_where() -> i64 {
    if load8(&E_WHERE) == 0 { return "-"; }
    return &E_WHERE;
}

# 拼一条消息再设置。因为墨语言没有字符串插值，
# 这类"消息里带个数字"的需求只能这么写。
#   err_setf(E_RANGE, "index ", 42, " out of range", "vec_get")
fn err_setf(code: i64, a: i64, v: i64, b: i64, where: i64) -> i64 {
    strcpy(&E_BUF, a);
    let nb: [24] byte = 0;
    utoa(v, &nb, 10);
    strcat(&E_BUF, &nb);
    strcat(&E_BUF, b);
    E_CODE = code;
    E_MSG = &E_BUF;
    if where != 0 { strcpy(&E_WHERE, where); }
    return 0 - 1;
}

# 打印完整错误行：  <code> <msg> @ <where>
# 返回错误码，方便 `return err_print();`
fn err_print() -> i64 {
    print("error[");
    print_i64(E_CODE);
    print("] ");
    print(err_msg());
    print(" @ ");
    print(err_where());
    print_nl();
    return E_CODE;
}

# errno 映射：把系统调用返回的负 errno 归到一个统一码
fn err_from_errno(e: i64) -> i64 {
    if e == 0 { return E_NONE; }
    if e == -2 { return E_FOUND; }      # ENOENT
    if e == -13 { return E_ARG; }       # EACCES
    if e == -12 { return E_NOMEM; }     # ENOMEM
    if e == -21 { return E_ARG; }       # EISDIR
    return E_IO;
}
