# aiohttp.mo —— aio + CSP HTTP/1.1 keep-alive server（每连接一协程）+ 压测 client
# aiohttp.mo —— aio + CSP HTTP/1.1 keep-alive server（每连接一协程）+ 压测 client
# server: aio_init + csp 协程每连接（aio_accept/aio_recv/aio_send），keep-alive 50 请求轮转
# client: 2 线程阻塞 socket keep-alive 对账（ROUNDS 与 server served<50 配平）
# 🔴 实战：strstr(hay, needle) 的 needle 是 ptr —— 传 int（32/13）= strlen(小整数) 段错
import "io.mo";
import "net.mo";
import "thread.mo";
import "lf.mo";
import "csp.mo";
import "aio.mo";

var PORT: i64 = 18817;
var ROUNDS: i64 = 300;
var NCLI: i64 = 2;
var LFD: i64 = 0;
var TH: [8] i64 = 0;
var CARG: [8] i64 = 0;
var CBAD: [8] i64 = 0;
var NCONN: i64 = 0;
var NREQ: i64 = 0;
var RECON: i64 = 0;

# ---- per-conn 缓冲池（协程并发上限 128）----
var CRB: [1024] byte = 0;

# ---- 协程：一个 HTTP keep-alive 连接 ----
fn http_conn(arg: i64) -> i64 {
    let fd: i64 = csp_arg();
    let sl: i64 = 0;   # 单收缓冲：并发窗口内 aio_recv→strcpy→aio_send 串行完成
    let rb: i64 = &CRB + sl * 1024;
    let n: i64 = 0;
    let hd: i64 = 0;
    let served: i64 = 0;
    while served < 20 {
        n = aio_recv(fd, rb, 1000);
        if n <= 0 { break; }
        NREQ = NREQ + 1;
        served = served + 1;
        strcpy(rb + 800, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\n{}");
        hd = strlen(rb + 800);
        if aio_send(fd, rb + 800, hd) != hd { break; }
    }
    aio_close(fd);
    return 0;
}

fn serve_loop_http(arg: i64) -> i64 {
    while 1 {
        let c: i64 = aio_accept(LFD);
        if c < 0 { break; }
        NCONN = NCONN + 1;
        csp_go(&http_conn, c);
    }
    return 0;
}

# ---- client 线程（阻塞 socket 简单 keep-alive 客户端）----
var CSB: [8192] byte = 0;
var CRP: [8192] byte = 0;

# ---- 连接池（v1.206.0）----
var POOL: [4] i64 = 0;
var PLOCK: i64 = 0;

fn pool_borrow() -> i64 {
    while lf_cas(0, &PLOCK, 0, 1) != 1 { }
    let i: i64 = 0;
    let fd: i64 = 0 - 1;
    while i < 4 {
        if POOL[i] > 0 {
            fd = POOL[i];
            POOL[i] = 0;
            i = 4;
        }
        i = i + 1;
    }
    PLOCK = 0;
    return fd;
}

fn pool_return(fd: i64) -> i64 {
    while lf_cas(0, &PLOCK, 0, 1) != 1 { }
    let i: i64 = 0;
    while i < 4 {
        if POOL[i] == 0 {
            POOL[i] = fd;
            i = 4;
        }
        i = i + 1;
    }
    PLOCK = 0;
    return 0;
}


# ---- 协程版 client（v1.210.0）：全 aio，无阻塞 ----
var DONE: i64 = 0;
var QCB: [4096] byte = 0;

fn client_csp(arg: i64) -> i64 {
    let cid: i64 = csp_arg();
    let sb: i64 = &QCB + cid * 1024;
    let cpb: i64 = &QCB + 2048 + cid * 512;
    let bad: i64 = 0;
    let i: i64 = 0;
    while i < ROUNDS {
        let fd: i64 = pool_borrow();
        let mine: i64 = 0;
        if fd <= 0 {
            fd = aio_connect(2130706433, PORT);
            mine = 1;
            if fd < 0 { bad = bad + 1; i = i + 1; continue; }
        }
        strcpy(sb, "GET /k HTTP/1.1\r\nHost: x\r\n\r\n");
        let n: i64 = strlen(sb);
        if aio_send(fd, sb, n) != n {
            aio_close(fd);
            RECON = RECON + 1;
            continue;
        }
        let m: i64 = 0;
        let r: i64 = 0;
        while m < 900 {
            r = aio_recv(fd, cpb + m, 1);
            if r <= 0 { break; }
            m = m + 1;
            if m >= 4 {
                if load8(cpb + m - 4) == 13 && load8(cpb + m - 3) == 10 && load8(cpb + m - 2) == 13 && load8(cpb + m - 1) == 10 { break; }
            }
        }
        if m < 20 {
            aio_close(fd);
            RECON = RECON + 1;
            continue;
        }
        store8(cpb + m, 0);
        r = aio_recv(fd, cpb + 500, 2);
        if r != 2 {
            aio_close(fd);
            RECON = RECON + 1;
            continue;
        }
        if load8(cpb + 500) != 123 || load8(cpb + 501) != 125 { bad = bad + 1; }
        pool_return(fd);
        i = i + 1;
    }
    CBAD[cid] = bad;
    DONE = DONE + 1;
    return 0;
}

fn client_http(arg: ptr) -> i64 {
    let cid: i64 = arg[0];
    let bad: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let m: i64 = 0;
    let r: i64 = 0;
    let fd: i64 = 0;
    let sb: i64 = &CSB + cid * 4096;
    let cpb: i64 = &CRP + cid * 4096;
    # ---- 连接池：借现有连接或新建（v1.206.0）----
    fd = pool_borrow();
    if fd <= 0 {
        fd = tcp_connect(2130706433, PORT);
        if fd < 0 { CBAD[cid] = ROUNDS; return 0; }
        sock_set_rcvtimeo(fd, 5);
    }
    strcpy(sb, "GET /k HTTP/1.1\r\nHost: x\r\n\r\n");
    n = strlen(sb);
    i = 0;
    while i < ROUNDS {
        fd = pool_borrow();
        let mine: i64 = 0;
        if fd <= 0 {
            fd = tcp_connect(2130706433, PORT);
            mine = 1;
            if fd < 0 { bad = bad + 1; i = i + 1; continue; }
            sock_set_rcvtimeo(fd, 5);
        }
        strcpy(sb, "GET /k HTTP/1.1\r\nHost: x\r\n\r\n");
        n = strlen(sb);
        if tcp_send(fd, sb, n) != n {
            tcp_close(fd);
            RECON = RECON + 1;
            continue;
        }
        m = 0;
        while m < 4090 {
            r = tcp_recv(fd, cpb + m, 1);
            if r <= 0 { break; }
            m = m + 1;
            if m >= 4 {
                if load8(cpb + m - 4) == 13 && load8(cpb + m - 3) == 10 && load8(cpb + m - 2) == 13 && load8(cpb + m - 1) == 10 { break; }
            }
        }
        if m < 20 {
            tcp_close(fd);
            RECON = RECON + 1;
            continue;
        }
        store8(cpb + m, 0);
        r = tcp_recv(fd, cpb + 500, 2);
        if r != 2 {
            tcp_close(fd);
            RECON = RECON + 1;
            continue;
        }
        if load8(cpb + 500) != 123 || load8(cpb + 501) != 125 { bad = bad + 1; }
        pool_return(fd);
        i = i + 1;
    }
    pool_return(fd);   # 归还池（v1.206.0）
    CBAD[cid] = bad;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    LFD = tcp_listen(PORT, 64);
    if LFD < 0 { print("listen fail\n"); return 1; }
    aio_nbio(LFD);
    if aio_init() != 0 { print("aio_init fail\n"); return 1; }
    csp_init(2);
    csp_go(&serve_loop_http, 0);
    print("S\n");
    usleep(200000);
    print("T\n");
    let i: i64 = 0;
    while i < NCLI {
        CARG[i] = i;
        thread_create(&TH + i * 8, &client_http, &CARG + i * 8);
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
    print("poolcli clients=2 rounds=");
    print_i64(ROUNDS);
    print(" bad=");
    print_i64(total);
    print(" conns=");
    print_i64(NCONN);
    print(" recon=");
    print_i64(RECON);
    print(" reqs=");
    print_i64(NREQ);
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
