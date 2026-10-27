# aioecho.mo —— epoll reactor + CSP 协程 echo server（aio.mo 首个端到端实例）
# server: aio_init + csp 协程每连接 echo（aio_accept/aio_recv/aio_send）
# client: 2 线程 × N 轮收发对账
import "io.mo";
import "net.mo";
import "thread.mo";
import "csp.mo";
import "aio.mo";

var PORT: i64 = 18700;
var ROUNDS: i64 = 200;
var NCLI: i64 = 2;
var LFD: i64 = 0;
var TH: [8] i64 = 0;
var CARG: [8] i64 = 0;
var CBAD: [8] i64 = 0;
var NCONN: i64 = 0;

# ---- server 协程：echo 一个连接直到对端关闭 ----
var EBUF: [4096] byte = 0;    # 2 协程并发上限（csp 2 worker；槽位用 csp_self 区分会互踩——实际 echo 请求 <2 并发窗口，简单取 mod 2）

fn echo_conn(arg: i64) -> i64 {
    let fd: i64 = csp_arg();    # csp_go(f, fd) 的参数由 csp_arg() 取（makecontext 0 参）
    let sl: i64 = csp_self() & 1;
    let n: i64 = 0;
    while 1 {
        n = aio_recv(fd, &EBUF + sl * 2048, 2048);
        if n <= 0 { break; }
        if aio_send(fd, &EBUF + sl * 2048, n) != n { break; }
    }
    aio_close(fd);
    return 0;
}

fn serve_loop_aio(arg: i64) -> i64 {
    while 1 {
        let c: i64 = aio_accept(LFD);
        if c < 0 { break; }
        NCONN = NCONN + 1;
        csp_go(&echo_conn, c);
    }
    return 0;
}

# ---- client 线程 ----
var SNDP: [1024] byte = 0;    # 2 × 512 per-client
var RCVP: [1024] byte = 0;

fn client_worker_aio(arg: ptr) -> i64 {
    let cid: i64 = arg[0];
    let bad: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let m: i64 = 0;
    let r: i64 = 0;
    let fd: i64 = 0;
    fd = tcp_connect(2130706433, PORT);
    if fd < 0 { CBAD[cid] = ROUNDS; return 0; }
    sock_set_rcvtimeo(fd, 5);
    i = 0;
    while i < ROUNDS {
        strcpy(&SNDP + cid * 512, "m");
        strcat_i64(&SNDP + cid * 512, cid * 100000 + i);
        n = strlen(&SNDP + cid * 512);
        if tcp_send(fd, &SNDP + cid * 512, n) != n {
            bad = bad + 1;
            i = i + 1;
            continue;
        }
        # 收回显（循环收满 n 字节）
        m = 0;
        while m < n {
            r = tcp_recv(fd, &RCVP + cid * 512 + m, n - m);
            if r <= 0 { break; }
            m = m + r;
        }
        if m != n {
            bad = bad + 1;
        } else {
            store8(&RCVP + cid * 512 + m, 0);
            if strcmp(&RCVP + cid * 512, &SNDP + cid * 512) != 0 { bad = bad + 1; }
        }
        i = i + 1;
    }
    tcp_close(fd);
    CBAD[cid] = bad;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    LFD = tcp_listen(PORT, 64);
    if LFD < 0 {
        print("listen fail\n");
        return 1;
    }
    aio_nbio(LFD);
    if aio_init() != 0 {
        print("aio_init fail\n");
        return 1;
    }
    csp_init(2);
    csp_go(&serve_loop_aio, 0);
    usleep(200000);
    let i: i64 = 0;
    while i < NCLI {
        CARG[i] = i;
        thread_create(&TH + i * 8, &client_worker_aio, &CARG + i * 8);
        i = i + 1;
    }
    i = 0;
    while i < NCLI {
        thread_join(TH[i]);
        i = i + 1;
    }
    usleep(300000);
    let total: i64 = 0;
    i = 0;
    while i < NCLI {
        total = total + CBAD[i];
        i = i + 1;
    }
    print("aioecho clients=2 rounds=");
    print_i64(ROUNDS);
    print(" bad=");
    print_i64(total);
    print(" conns=");
    print_i64(NCONN);
    print_nl();
    print("woke=");
    print_i64(AIO_WOKE);
    print(" nev=");
    print_i64(AIO_NEV);
    print(" perr=");
    print_i64(AIO_PERR);
    print_nl();
    aio_stop();
    if total > 0 { return 1; }
    return 0;
}
