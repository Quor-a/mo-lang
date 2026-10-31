# 测试：component 展开后的目标 Mo 代码模板（手写验证版 v2）
# 文本字段用全局 byte 数组存储
import "uic.mo";
import "str.mo";

# 展开出的全局变量
var Task_name: [32] byte = 0;   # 文本值（字节）
var Task_dur: i64 = 0;
var Task_buf: [64] i64 = 0;     # 数字转字符串工作缓冲

# 展开出的 setter
fn Task_set_name(v: ptr) -> i64 {
    let n: i64 = strlen(v);
    let i: i64 = 0;
    while i < n {
        Task_name[i] = load8(v + i);
        i = i + 1;
    }
    Task_name[n] = 0;
    return 0;
}
fn Task_set_dur(v: i64) -> i64 { Task_dur = v; return 0; }

# 展开出的行渲染函数
fn Task_row(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    let cx: i64 = x;
    # 字段0: name (text)
    uc_text(cx, y, "name", UC_YELLOW, bg);
    let l0: i64 = strlen("name");
    cx = cx + l0 + 1;
    uc_text(cx, y, &Task_name, UC_YELLOW, bg);
    let v0: i64 = strlen(&Task_name);
    let p0: i64 = 10 - v0;
    let j0: i64 = 0;
    while j0 < p0 {
        uc_set(cx + v0 + j0, y, ' ', fg, bg);
        j0 = j0 + 1;
    }
    cx = cx + 10 + 2;
    # 字段1: dur (num)
    uc_text(cx, y, "dur", UC_CYAN, bg);
    let l1: i64 = strlen("dur");
    cx = cx + l1 + 1;
    let b1: i64 = &Task_buf;
    let z1: i64 = 0;
    while z1 < 64 {
        Task_buf[z1] = 0;
        z1 = z1 + 1;
    }
    str_itoa_base(b1, Task_dur, 10);
    uc_text(cx, y, b1, UC_CYAN, bg);
    let v1: i64 = strlen(b1);
    let p1: i64 = 5 - v1;
    let j1: i64 = 0;
    while j1 < p1 {
        uc_set(cx + v1 + j1, y, ' ', fg, bg);
        j1 = j1 + 1;
    }
    cx = cx + 5 + 2;
    return 0;
}

# 展开出的表头函数
fn Task_head(x: i64, y: i64, fg: i64, bg: i64) -> i64 {
    uc_text(x, y, "name", UC_WHITE, bg);
    uc_text(x + 6, y, "dur", UC_WHITE, bg);
    return 0;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Task_set_name("task-01");
    Task_set_dur(5);
    Task_row(1, 2, UC_WHITE, UC_BLUE);
    Task_set_name("task-02");
    Task_set_dur(12);
    Task_row(1, 3, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}