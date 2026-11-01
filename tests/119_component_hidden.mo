# 测试：component hidden 属性（字段不渲染、值不出现在输出）
import "uic.mo";
import "str.mo";

component Pan {
    name: text width 8;
    secret: text width 10 hidden;
    ok: text width 6;
}

fn main() -> i64 {
    uc_init(60, 10);
    uc_clear(UC_BLACK, UC_BLUE);
    Pan_set_name("svc");
    Pan_set_secret("topsecret");
    Pan_set_ok("fine");
    Pan_row(1, 2, UC_WHITE, UC_BLUE);
    uc_render();
    return 0;
}
