# 测试：component fmt 属性（num 十六进制渲染 48879 → beef）
import "uic.mo";
import "str.mo";

component Hex {
    reg: text width 6;
    val: num width 12 fmt hex;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Hex_set_reg("mode");
    Hex_set_val(48879);
    Hex_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
