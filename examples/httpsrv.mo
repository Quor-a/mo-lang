# httpsrv.mo —— CSP 协程 + epoll reactor 的高并发 HTTP 服务
#
# 架构：经典 acceptor/worker
#   acceptor 协程：aio_accept() 收连接，把 fd 投进 channel
#   N 个 worker 协程：chan_recv() 取 fd，读请求、写响应、关闭
#
# 关键点：**worker 协程数量远小于并发连接数**。靠的是 I/O 未就绪时
# aio_recv() 把协程挂起（csp_park），线程立刻去跑别的协程。
#
# A/B：BLOCKING=1 时改用阻塞 accept/recv —— 协程里一次阻塞 read() 会把
# 整个 worker 线程连同它上面**所有**协程一起卡住，并发度退回线程数。
# 两种模式跑同一份负载，比墙钟时间。
#
# 用法： ./httpsrv [0|1]    0=异步（默认） 1=阻塞对照

import "io.mo";
import "csp.mo";
import "aio.mo";
import "net.mo";
import "thread.mo";

var PORT: i64 = 18240;
var NWORKER: i64 = 8;      # worker 协程数
var NCLIENT: i64 = 24;     # 并发客户端线程数
var NROUND: i64 = 3;       # 每客户端请求轮数
var SLOWMS: i64 = 30000;   # 客户端连上后先睡这么久再发请求（制造并发悬挂）

var BLOCKING: i64 = 0;
var LFD: i64 = 0;
var CH: i64 = 0;
var REQ: i64 = 0;
var BAD: i64 = 0;
var NCONN: i64 = 0;
var DONE: i64 = 0;
var CID: i64 = 0;
# 🔴 计数器必须加锁：REQ/NCONN/DONE 由 8 个协程（跑在 2 个 worker 线程上）和
#    24 个客户端线程并发自增，`X = X + 1` 非原子，会丢更新。
#    实测：无锁时 150 次里约 1 次 req=71 而 nconn=72、无任何失败记录 ——
#    看起来像"丢了一个请求"，实际只是计数丢了一次自增。
var CNT_LK: [8] i64 = 0;
fn cinc(p: ptr, d: i64) -> i64 {
    mutex_lock(&CNT_LK);
    let v: i64 = p[0];
    p[0] = v + d;
    mutex_unlock(&CNT_LK);
    return 0;
}
var CF_CONN: i64 = 0;    # 客户端 connect 失败次数
var CF_RECV: i64 = 0;    # 客户端 recv 失败次数
var CF_RV: i64 = 0;      # 最近一次 recv 返回值
var SV_EARLY: i64 = 0;   # 服务端 n<=0 提前关闭次数
var SV_EV: i64 = 0;      # 最近一次提前关闭时的 n
var CLK: [8] i64 = 0;
var CTID: [64] i64 = 0;
var HT0: [2] i64 = 0;
var HT1: [2] i64 = 0;
var HCLK: [2] i64 = 0;

fn now_ms() -> i64 {
    let r: i64 = syscall(228, 1, &HCLK, 0, 0, 0, 0);
    if r < 0 { return 0; }
    return HCLK[0] * 1000 + HCLK[1] / 1000000;
}

# ------------------------------------------------------------------ 服务端
fn acceptor() -> i64 {
    let lfd: i64 = csp_arg();
    while 1 {
        let c: i64 = 0;
        if BLOCKING == 1 { c = tcp_accept(lfd); }
        else { c = aio_accept(lfd); }
        if c < 0 { csp_exit(); return 0; }
        cinc(&NCONN, 1);
        chan_send(CH, c);
    }
    csp_exit();
    return 0;
}

fn responder(c: i64) -> i64 {
    let buf: [1024] byte = 0;
    let off: i64 = 0;
    let got: i64 = 0;
    # 循环读到收全 \r\n\r\n 为止：每个连接要经历**多次**等待，
    # 这才是能区分异步/阻塞的形状（只等一次的话两者差不多）
    while got == 0 {
        let n: i64 = 0;
        if BLOCKING == 1 { n = tcp_recv(c, &buf + off, 1023 - off); }
        else { n = aio_recv(c, &buf + off, 1023 - off); }
        if n <= 0 { SV_EARLY = SV_EARLY + 1; SV_EV = n; tcp_close(c); return 0; }
        off = off + n;
        buf[off] = 0;
        let i: i64 = 0;
        while i < off - 3 {
            if buf[i] == 13 { if buf[i + 1] == 10 { if buf[i + 2] == 13 { if buf[i + 3] == 10 { got = 1; } } } }
            i = i + 1;
        }
    }
    if got == 0 { BAD = BAD + 1; }
    let body: [32] byte = 0;
    body[0] = 104; body[1] = 105; body[2] = 33; body[3] = 10;   # "hi!\n"
    let resp: [128] byte = 0;
    let h: i64 = 0;
    let s: [64] byte = 0;
    s[0] = 72; s[1] = 84; s[2] = 84; s[3] = 80; s[4] = 47; s[5] = 49; s[6] = 46; s[7] = 49;
    s[8] = 32; s[9] = 50; s[10] = 48; s[11] = 48; s[12] = 32; s[13] = 79; s[14] = 75; s[15] = 13;
    s[16] = 10; s[17] = 67; s[18] = 111; s[19] = 110; s[20] = 116; s[21] = 101; s[22] = 110;
    s[23] = 116; s[24] = 45; s[25] = 76; s[26] = 101; s[27] = 110; s[28] = 103; s[29] = 116;
    s[30] = 104; s[31] = 58; s[32] = 32; s[33] = 52; s[34] = 13; s[35] = 10; s[36] = 13;
    s[37] = 10; s[38] = 104; s[39] = 105; s[40] = 33; s[41] = 10; s[42] = 0;
    while s[h] != 0 {
        resp[h] = s[h];
        h = h + 1;
    }
    if BLOCKING == 1 { tcp_send(c, &resp, h); }
    else { aio_send(c, &resp, h); }
    if BLOCKING == 1 { tcp_close(c); }
    else { aio_close(c); }
    cinc(&REQ, 1);
    return 0;
}

fn worker() -> i64 {
    let ch: i64 = csp_arg();
    while 1 {
        let c: i64 = chan_recv(ch);
        if CH_OK == 0 { csp_exit(); return 0; }
        responder(c);
    }
    csp_exit();
    return 0;
}

# ------------------------------------------------------------------ 客户端
fn client(arg: ptr) -> i64 {
    # 每个客户端拿一个 id，用它把各自的中途延迟**错开**。
    # 若所有客户端延迟相同，它们的等待会彼此重叠，阻塞/异步测不出差别
    # （第一版就栽在这里：blocking 189ms 反而比 async 210ms 快）。
    mutex_lock(&CLK);
    let id: i64 = CID;
    CID = CID + 1;
    mutex_unlock(&CLK);
    let lag: i64 = (id + 1) * 1000;
    let r: i64 = 0;
    while r < NROUND {
        let fd: i64 = tcp_connect(0x0100007f, PORT);
        if fd < 0 { cinc(&CF_CONN, 1); return 1; }
        # 连上后先挂着不发，制造"已建立但无数据"的并发连接。
        # 这正是压测异步 I/O 的形状：同步服务器会为每个连接占住一个线程。
        usleep(lag);
        let rq: [64] byte = 0;
        let s: [40] byte = 0;
        s[0] = 71; s[1] = 69; s[2] = 84; s[3] = 32; s[4] = 47; s[5] = 32; s[6] = 72;
        s[7] = 84; s[8] = 84; s[9] = 80; s[10] = 47; s[11] = 49; s[12] = 46; s[13] = 49;
        s[14] = 13; s[15] = 10; s[16] = 72; s[17] = 111; s[18] = 115; s[19] = 116;
        s[20] = 58; s[21] = 32; s[22] = 120; s[23] = 13; s[24] = 10; s[25] = 13;
        s[26] = 10; s[27] = 0;
        let i: i64 = 0;
        while s[i] != 0 { rq[i] = s[i]; i = i + 1; }
        # 分两次发：先发请求行，隔 SLOWMS 再发空行结束头。
        # 服务器必须**等**这 30ms —— 异步下协程挂起、线程去干别的；
        # 阻塞下整个 worker 线程被这一个连接占死。
        tcp_send(fd, &rq, i - 2);
        usleep(lag);
        let tail: [4] byte = 0;
        tail[0] = 13; tail[1] = 10;
        tcp_send(fd, &tail, 2);
        let rb: [512] byte = 0;
        let n: i64 = tcp_recv(fd, &rb, 511);
        if n < 0 { cinc(&CF_RECV, 1); CF_RV = n; return 1; }
        tcp_close(fd);
        r = r + 1;
    }
    cinc(&DONE, 1);
    return 0;
}

# ------------------------------------------------------------------ main
fn main() -> i64 {
    let argc: i64 = 0;
    PORT = 18240;
    if BLOCKING == 1 { PORT = 18241; }

    if csp_init(2) != 0 { print("csp_init fail\n"); return 1; }
    if BLOCKING == 0 {
        if aio_init() != 0 { print("aio_init fail\n"); return 1; }
    }
    LFD = tcp_listen(PORT, 256);
    if LFD < 0 { print("listen fail\n"); return 1; }
    if BLOCKING == 0 { aio_nbio(LFD); }
    CH = chan_make(64);

    if csp_go(&acceptor, LFD) < 0 { print("go acceptor fail\n"); return 1; }
    let w: i64 = 0;
    while w < NWORKER {
        if csp_go(&worker, CH) < 0 { print("go worker fail\n"); return 1; }
        w = w + 1;
    }

    HT0[0] = now_ms();

    let c: i64 = 0;
    while c < NCLIENT {
        if thread_create(&CTID + c * 8, &client, 0) != 0 { print("client spawn fail\n"); return 1; }
        c = c + 1;
    }
    c = 0;
    let tick: i64 = 0;
    while DONE < NCLIENT {
        usleep(20000);
        tick = tick + 1;
        print("  tick="); print_i64(tick);
        print(" done=");  print_i64(DONE);
        print(" nconn="); print_i64(NCONN);
        print(" req=");   print_i64(REQ);
        print(" aio_n="); print_i64(AIO_N);
        print(" woke=");  print_i64(AIO_WOKE);
        print(" perr=");  print_i64(AIO_PERR);
        print(" dead=");  print_i64(CSP_DEAD);
        print(" tick2="); print_i64(AIO_TICK);
        print(" ev=");    print_i64(AIO_NEV);
        print(" skp=");   print_i64(AIO_SKP);
        print(" evfd=");  print_i64(AIO_EVFD);
        print(" bad=");   print_i64(AIO_BAD);
        print(" d0=");    print_i64(AIO_D0);
        print(" d1=");    print_i64(AIO_D1);
        print(" aEVS=");  print_i64(&AIO_EVS);
        print(" aFD=");   print_i64(&AIO_FD);
        print(" aSL=");   print_i64(&AIO_SL);
        print(" aCTX=");  print_i64(&CSP_CTX);
        print(" aRQ=");   print_i64(&CSP_RQ);
        print("\n");
        if tick > 60 { break; }
    }
    c = 0;
    while c < NCLIENT {
        thread_join(CTID[c]);
        c = c + 1;
    }

    HT1[0] = now_ms();

    print("mode=");
    if BLOCKING == 1 { print("blocking"); } else { print("async"); }
    print(" workers="); print_i64(NWORKER);
    print(" clients="); print_i64(NCLIENT);
    print(" rounds="); print_i64(NROUND);
    print(" ms=");     print_i64(HT1[0] - HT0[0]);
    print(" nconn=");  print_i64(NCONN);
    print(" req=");    print_i64(REQ);
    print(" bad=");    print_i64(BAD);
    print(" sv_early="); print_i64(SV_EARLY);
    print(" sv_n=");     print_i64(SV_EV);
    print(" cf_conn=");  print_i64(CF_CONN);
    print(" cf_recv=");  print_i64(CF_RECV);
    print(" cf_rv=");    print_i64(CF_RV);
    print(" woke=");   print_i64(AIO_WOKE);
    print(" qovf=");   print_i64(CSP_QOVF);
    print(" perr=");   print_i64(AIO_PERR);
    print("\n");
    return 0;
}
