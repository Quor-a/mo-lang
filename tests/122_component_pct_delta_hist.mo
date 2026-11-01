# 测试：pct/delta 字段 hist N 模式（历史均值：10-40→25%，100-400→▲250）
import "uic.mo";
import "str.mo";

component Dh {
    id: text width 5;
    cpu: pct width 10 hist 4;
    net: delta width 10 hist 4;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Dh_set_id("a");
    Dh_set_cpu(10);
    Dh_set_cpu(20);
    Dh_set_cpu(30);
    Dh_set_cpu(40);
    Dh_set_net(100);
    Dh_set_net(200);
    Dh_set_net(300);
    Dh_set_net(400);
    Dh_row(2, 5, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
