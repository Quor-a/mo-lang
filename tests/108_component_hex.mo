# 测试：component hex 字段类型（十六进制渲染）
import "uic.mo";
import "str.mo";

component Reg {
    name: text width 8;
    addr: hex width 12;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Reg_set_name("dma");
    Reg_set_addr(48879);
    Reg_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
