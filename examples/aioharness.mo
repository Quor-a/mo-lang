# aioharness：aioclient 并发压测工具（v1.220.0）
# 用法：aioharness <并发协程数 N> <每协程请求数 M> [port]
# N 协程并发 aio_http_get /pkg/fin2.mo，统计 ok/bad/连接复用，全对输出 AIOHARNESS_OK。
import "io.mo";
import "net.mo";
import "csp.mo";
import "lf.mo";
import "aio.mo";
import "aioclient.mo";

var N: i64 = 0;
var M: i64 = 0;
var PORT: i64 = 18900;
var OKN: i64 = 0;
var BADN: i64 = 0;
var DONE: i64 = 0;
var HB: [8192] byte = 0;

fn work() -> i64 {
    let id: i64 = csp_arg();
    let j: i64 = 0;
    while j < M {
        let r: i64 = aio_http_get("/pkg/fin2.mo", &HB, 8000);
        if r > 0 { OKN = OKN + 1; } else { BADN = BADN + 1; }
        j = j + 1;
    }
    DONE = DONE + 1;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    aio_init();
    lf_init();
    aio_pool_config(2130706433, PORT);
    N = 3;
    M = 5;
    if argc() >= 3 { N = atoi(argv(1)); M = atoi(argv(2)); }
    print("harness n=");
    print_i64(N);
    print(" m=");
    print_i64(M);
    print("\n");
    csp_init(4);
    let i: i64 = 0;
    while i < N {
        csp_go(&work, i);
        i = i + 1;
    }
    while DONE < N {
        usleep(50000);
    }
    print("ok=");
    print_i64(OKN);
    print(" bad=");
    print_i64(BADN);
    print(" conns=");
    print_i64(aio_pool_conns());
    print("\n");
    if BADN == 0 && OKN == N * M {
        print("AIOHARNESS_OK\n");
        aio_stop();
    return 0;
    }
    return 1;
}
