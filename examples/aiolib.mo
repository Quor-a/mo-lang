# aiolib.mo —— lib/aioclient.mo 一步式 GET 端到端（v1.211.0）
import "io.mo";
import "net.mo";
import "csp.mo";
import "thread.mo";
import "aio.mo";
import "aioclient.mo";

var RIP2: i64 = 2130706433;
var OKN: i64 = 0;
var GB: [2048] byte = 0;

fn get_go(arg: i64) -> i64 {
    let id: i64 = csp_arg();

    let n: i64 = aio_http_get("/search", &GB, 2000);
    if n > 0 {
        OKN = OKN + 1;
    } else {
        print("get fail id=");
        print_i64(id);
        print(" n=");
        print_i64(n);
        print("\n");
    }
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    aio_pool_config(RIP2, 18900);
    aio_init();
    csp_init(2);
    csp_go(&get_go, 1);
    csp_go(&get_go, 2);
    csp_go(&get_go, 3);
    let waitn: i64 = 0;
    let rs: i64 = 0;
    while OKN < 3 && waitn < 200 {
        rs = usleep(50000);
        waitn = waitn + 1;
    }
    print("ok=");
    print_i64(OKN);
    print(" conns=");
    print_i64(aio_pool_conns());
    print("\n");
    if OKN == 3 { print("AIOLIB_E2E_OK\n"); aio_stop();
    return 0; }
    return 1;
}
