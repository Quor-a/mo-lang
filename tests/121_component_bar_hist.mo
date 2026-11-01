# 测试：bar 字段 hist N 模式（环形历史 + 均值渲染 10/20/30/40 → avg 25）
import "uic.mo";
import "str.mo";

component Bh {
    tag: text width 6;
    cpu: bar width 12 hist 4;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Bh_set_tag("cpu");
    Bh_set_cpu(10);
    Bh_set_cpu(20);
    Bh_set_cpu(30);
    Bh_set_cpu(40);
    Bh_row(3, 5, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
