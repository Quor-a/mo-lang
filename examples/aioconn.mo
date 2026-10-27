# aioconn.mo —— aio_connect 端到端（v1.209.0）：协程内非阻塞 connect + GET 对 regserver
import "io.mo";
import "net.mo";
import "csp.mo";
import "aio.mo";

var RIP: i64 = 0;
var RPORT: i64 = 18900;
var CB: [2048] byte = 0;
var RES: i64 = 0;   # 0=未跑，负=失败，正=成功

fn conn_go(arg: i64) -> i64 {
    let fd: i64 = aio_connect(RIP, RPORT);
    if fd < 0 {
        print("aio_connect fail ");
        print_i64(fd);
        print("\n");
        return 0 - 1;
    }
    strcpy(&CB, "GET /search HTTP/1.0\r\nHost: r\r\n\r\n");
    let n: i64 = strlen(&CB);
    if aio_send(fd, &CB, n) != n { print("send fail\n"); return 0 - 2; }
    let got: i64 = 0;
    while got < 2000 {
        let r: i64 = aio_recv(fd, &CB + got, 512);
        if r <= 0 { break; }
        got = got + r;
    }
    aio_close(fd);
    store8(&CB + got, 0);
    if got > 15 && strstr(&CB, "200 OK") >= 0 {
        RES = 1;
        print("aioconn OK got=");
        print_i64(got);
        print("\n");
    } else {
        RES = 0 - 3;
        print("aioconn bad got=");
        print_i64(got);
        print("\n");
    }
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    RIP = 2130706433;
    aio_init();
    csp_init(2);
    csp_go(&conn_go, 0);
    let i: i64 = 0;
    while i < 2000000 { i = i + 1; }   # 忙等协程完成（main 非协程不能用 aio_wait）
    if RES > 0 { print("AIOCONN_E2E_OK\n"); return 0; }
    return 1;
}
