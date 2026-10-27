import "timer.mo";
import "io.mo";
import "str.mo";
# expect: 0

var S: [32] byte = 0;

fn main() -> i64 {
    let ms: i64 = time_epoch_ms();
    # 合理范围：2020-01-01 ~ 2100 年
    if ms < 1577836800000 || ms > 4102444800000 { print("fail epoch="); print_i64(ms); print("\n"); return 1; }
    time_stamp(&S);
    if strlen(&S) != 15 { print("fail len="); print_i64(strlen(&S)); print("\n"); return 1; }
    # 全数字+连字符：位置 8 是 '-'
    if load8(&S + 8) != 45 { print("fail dash\n"); return 1; }
    let i: i64 = 0;
    while i < 15 {
        if i != 8 {
            let c: i64 = load8(&S + i);
            if c < 48 || c > 57 { print("fail digit\n"); return 1; }
        }
        i = i + 1;
    }
    print(&S);
    print("\nTIME_OK\n");
    return 0;
}
