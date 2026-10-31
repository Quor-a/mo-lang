# 测试：component kv 字段类型（键值文本渲染）
import "uic.mo";
import "str.mo";

component Host {
    host: text width 10;
    ip: kv width 15;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Host_set_host("node-a");
    Host_set_ip("10.0.0.7");
    Host_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
