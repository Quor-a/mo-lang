# aioput.mo —— v1.214 aio_http_put E2E：协程并发 PUT 到 regserver 再 GET 回读
import "io.mo";
import "aioclient.mo";

var OKN: i64 = 0;
var BADN: i64 = 0;
var DONE: i64 = 0;
var RBUF: [4096] byte = 0;
var GETDONE: i64 = 0;
var GETN: i64 = 0;

fn put_csp() -> i64 {
    let id: i64 = csp_arg();
    aio_pool_config(2130706433, 18900);
    # 组 body：按 id 区分
    let body: i64 = &RBUF + 2048 + id * 600;
    strcpy(body, "hello-put-");
    let v: i64 = id;
    let digits: i64 = 0;
    while v > 0 {
        store8(body + 10 + digits, 48 + (v % 10));
        v = v / 10;
        digits = digits + 1;
    }
    store8(body + 10 + digits, 0);
    let path: ptr = "/pkg/aio_put_test.mo?name=aio_put_test&ver=2.1.4";
    let r: i64 = aio_http_put(path, body, strlen(body), &RBUF, 2000);
    if r >= 0 {
        OKN = OKN + 1;
    } else {
        BADN = BADN + 1;
    }
    # id==1 的协程顺带 GET 回读（aio_recv 须协程上下文）
    if id == 1 {
        GETN = aio_http_get("/pkg/aio_put_test.mo", &RBUF, 2000);
        GETDONE = 1;
    }
    DONE = DONE + 1;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    aio_init();
    csp_init(2);
    csp_go(&put_csp, 1);
    csp_go(&put_csp, 2);
    csp_go(&put_csp, 3);
    let r: i64 = 0;
    let waitn: i64 = 0;
    while DONE < 3 && waitn < 400 {
        r = usleep(50000);
        waitn = waitn + 1;
    }
    print("put ok=");
    print_i64(OKN);
    print(" bad=");
    print_i64(BADN);
    print("\n");
    if OKN != 3 { return 1; }
    while GETDONE < 1 && waitn < 400 {
        r = usleep(50000);
        waitn = waitn + 1;
    }
    if GETN > 0 && strstr(&RBUF, "hello-put-") >= 0 {
        print("AIOPUT_E2E_OK\n");
        aio_stop();
    return 0;
    }
    print("content mismatch get=");
    print_i64(GETN);
    print(" gd=");
    print_i64(GETDONE);
    print("\n");
    return 1;
}

