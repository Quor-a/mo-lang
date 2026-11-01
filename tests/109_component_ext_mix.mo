# 测试：component 扩展渲染重构回归（bar/gauge/kv/hex 混合组件）
import "uic.mo";
import "str.mo";

component Mix {
    tag: text width 8;
    load: bar width 10;
    temp: gauge width 10;
    note: kv width 10;
    addr: hex width 10;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Mix_set_tag("mix");
    Mix_set_load(60);
    Mix_set_temp(75);
    Mix_set_note("ok");
    Mix_set_addr(171);
    Mix_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
