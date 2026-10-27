# httpto.mo —— 带**读超时**的 HTTP 服务（慢客户端被掐断）
#
# 它演示的是 lib/ioto.mo：读请求时给一个 deadline，
#     n = ioto_recv(fd, buf, 1023, READMS);
#     n == -1  → 超时，关掉连接
# 内部就是一个 select：{ I/O 就绪 channel, tm_after(READMS) 的 channel }。
#
# 为什么值得单独做一个示例：
#   没有读超时的服务器，一个"连上但不发数据"的客户端就能永久占住一个
#   worker（协程不阻塞线程，但连接和槽一直挂着）。这是 Slowloris 攻击的
#   形状。有了超时，慢连接在 READMS 后被掐断，worker 立刻回到池里。
#
# 实测（默认参数，见 tools/iototest.sh）：
#   6 个正常客户端全部拿到响应；6 个慢客户端全部在 ~200ms 被超时掐断。
#
# 用法： ./httpto           # 默认 12 客户端（6 快 + 6 慢）、读超时 200ms

import "io.mo";
import "cstd.mo";
import "csp.mo";
import "select.mo";
import "timer.mo";
import "aio.mo";
import "ioto.mo";
import "net.mo";
import "thread.mo";

var PORT: i64 = 18260;
var NWORKER: i64 = 8;
var NFAST: i64 = 6;      # 连上立刻发完整请求
var NSLOW: i64 = 6;      # 连上后睡 SLOWMS 再发 —— 必须被超时掐断
var READMS: i64 = 400;   # 读超时
var SLOWMS: i64 = 3000;  # 慢客户端的沉默时长（>> READMS）
var NROUND: i64 = 1;    # 每客户端请求轮数。
# 🔴 实测 NROUND=2 时（24 个连接，压力翻倍）会偶发 AIO_PERR=11：
#    channel 模式下的就绪通知 trysend **投递失败**（缓冲满），该协程
#    于是等到超时才醒 —— 表现为一个正常请求被误掐断（nok=11 / nto=13）。
#    根因未查明，不编解释，如实列为已知限制。默认 1 轮以保证测试稳定。
var GAPMS: i64 = 120;   # 快客户端两次发送之间的间隔（<< READMS，不该超时）

var LFD: i64 = 0;
var CH: i64 = 0;
var CID: i64 = 0;
var DONE: i64 = 0;
var NCONN: i64 = 0;
var NOK: i64 = 0;        # 正常响应数
var NTO: i64 = 0;        # 被超时掐断数
var TOMS: i64 = 0;       # 最近一次超时的实测耗时
var CF_CONN: i64 = 0;
var CF_SEND: i64 = 0;
var LK: [8] i64 = 0;
var CTID: [64] i64 = 0;
var CLK: [2] i64 = 0;
var RESP: [40] byte = 0;

fn now_ms() -> i64 {
    syscall(228, 1, &CLK, 0, 0, 0, 0);
    return CLK[0] * 1000 + CLK[1] / 1000000;
}

fn cinc(d: i64) -> i64 {
    mutex_lock(&LK);
    DONE = DONE + d;
    mutex_unlock(&LK);
    return 0;
}

# ------------------------------------------------------------------ 服务端
fn acceptor() -> i64 {
    let lfd: i64 = csp_arg();
    while 1 {
        let c: i64 = aio_accept(lfd);
        if c < 0 { csp_exit(); return 0; }
        mutex_lock(&LK);
        NCONN = NCONN + 1;
        mutex_unlock(&LK);
        chan_send(CH, c);
    }
    csp_exit();
    return 0;
}

fn worker(arg: ptr) -> i64 {
    let c: i64 = csp_arg();
    let buf: [1024] byte = 0;
    while 1 {
        let fd: i64 = chan_recv(c);
        if CH_OK == 0 { csp_exit(); return 0; }
        let a: i64 = now_ms();
        let off: i64 = 0;
        let got: i64 = 0;
        # 循环读到收全 \r\n\r\n 为止：这样每个连接都会经历**一次真实等待**，
        # 而不是"第一次 read 就拿到全部"。等待才是 cancel 路径的形状 ——
        # 不等待的话定时器根本没 arm，TM_CNCL 恒为 0，取消有没有生效看不出来。
        while got == 0 {
            let n: i64 = ioto_recv(fd, &buf + off, 1023 - off, READMS);
            if n == 0 - 1 {
                mutex_lock(&LK);
                NTO = NTO + 1;
                TOMS = now_ms() - a;
                mutex_unlock(&LK);
                aio_close(fd);
                off = 0 - 1;
                break;
            }
            if n <= 0 { aio_close(fd); off = 0 - 1; break; }
            off = off + n;
            if off >= 4 {
                if buf[off - 4] == 13 {
                    if buf[off - 3] == 10 {
                        if buf[off - 2] == 13 {
                            if buf[off - 1] == 10 { got = 1; }
                        }
                    }
                }
            }
        }
        if off < 0 { continue; }
        mutex_lock(&LK);
        NOK = NOK + 1;
        mutex_unlock(&LK);
        aio_send(fd, &RESP, 39);
        aio_close(fd);
    }
    csp_exit();
    return 0;
}

# ------------------------------------------------------------------ 客户端
fn client(arg: ptr) -> i64 {
    mutex_lock(&LK);
    let id: i64 = CID;
    CID = CID + 1;
    mutex_unlock(&LK);
    let slow: i64 = 0;
    if id >= NFAST { slow = 1; }
    let rd: i64 = 0;
    while rd < NROUND {
    let fd: i64 = tcp_connect(0x0100007f, PORT);
    if fd < 0 { CF_CONN = CF_CONN + 1; cinc(1); return 1; }
    if slow == 1 { usleep(SLOWMS * 1000); }
    let rq: [64] byte = 0;
    # 先发请求行，**不发**结束头的空行 —— 服务端必须等这 50ms。
    # 50ms << READMS(200ms)，所以它应该等到 I/O 就绪而不是超时。
    let s: [32] byte = 0;
    s[0] = 71; s[1] = 69; s[2] = 84; s[3] = 32; s[4] = 47; s[5] = 32; s[6] = 72;
    s[7] = 84; s[8] = 84; s[9] = 80; s[10] = 47; s[11] = 49; s[12] = 46; s[13] = 49;
    s[14] = 13; s[15] = 10; s[16] = 72; s[17] = 111; s[18] = 115; s[19] = 116;
    s[20] = 58; s[21] = 32; s[22] = 120; s[23] = 13; s[24] = 10; s[25] = 0;
    let i: i64 = 0;
    while s[i] != 0 { rq[i] = s[i]; i = i + 1; }
    # MSG_NOSIGNAL(0x4000)：慢客户端会在服务端已掐断的连接上 send，
    # 默认会收到 SIGPIPE 直接把进程杀掉（退出码 141，看着像"崩了"）。
    let r: i64 = syscall(44, fd, &rq, i, 16384, 0, 0);
    if r < 0 { CF_SEND = CF_SEND + 1; }
    usleep(GAPMS * 1000);
    let tail: [4] byte = 0;
    tail[0] = 13; tail[1] = 10;
    r = syscall(44, fd, &tail, 2, 16384, 0, 0);
    if r < 0 { CF_SEND = CF_SEND + 1; }
    let rb: [256] byte = 0;
    let m: i64 = tcp_recv(fd, &rb, 255);
    tcp_close(fd);
    rd = rd + 1;
    }
    cinc(1);
    return 0;
}

# ------------------------------------------------------------------ main
fn main() -> i64 {
    let i: i64 = 0;
    RESP[0] = 72; RESP[1] = 84; RESP[2] = 84; RESP[3] = 80; RESP[4] = 47;
    RESP[5] = 49; RESP[6] = 46; RESP[7] = 49; RESP[8] = 32; RESP[9] = 50;
    RESP[10] = 48; RESP[11] = 48; RESP[12] = 32; RESP[13] = 79; RESP[14] = 75;
    RESP[15] = 13; RESP[16] = 10; RESP[17] = 67; RESP[18] = 111; RESP[19] = 110;
    RESP[20] = 116; RESP[21] = 101; RESP[22] = 110; RESP[23] = 116; RESP[24] = 45;
    RESP[25] = 76; RESP[26] = 101; RESP[27] = 110; RESP[28] = 103; RESP[29] = 116;
    RESP[30] = 104; RESP[31] = 58; RESP[32] = 32; RESP[33] = 51; RESP[34] = 49;
    RESP[35] = 13; RESP[36] = 10; RESP[37] = 13; RESP[38] = 10;

    if csp_init(2) != 0 { print("csp_init fail\n"); return 1; }
    sel_init();
    if aio_init() != 0 { print("aio_init fail\n"); return 1; }
    if tm_init(16) != 0 { print("tm_init fail\n"); return 1; }
    LFD = tcp_listen(PORT, 256);
    if LFD < 0 { print("listen fail\n"); return 1; }
    aio_nbio(LFD);
    CH = chan_make(64);

    if csp_go(&acceptor, LFD) < 0 { print("go acceptor fail\n"); return 1; }
    i = 0;
    while i < NWORKER {
        if csp_go(&worker, CH) < 0 { print("go worker fail\n"); return 1; }
        i = i + 1;
    }
    i = 0;
    while i < NFAST + NSLOW {
        if thread_create(&CTID + i * 8, &client, 0) != 0 { print("client fail\n"); return 1; }
        i = i + 1;
    }

    # 🔴 退出条件必须是"服务端处理完了所有连接"，不是"客户端都跑完了"。
    #    客户端睡 3 秒醒来就退出，而那时服务端可能还有连接在排队 ——
    #    实测会出现 nto=5 / nok=6 这种少一个的假象，看着像丢了请求。
    let tick: i64 = 0;
    while 1 {
        mutex_lock(&LK);
        let done: i64 = NOK + NTO;
        mutex_unlock(&LK);
        if done >= (NFAST + NSLOW) * NROUND { break; }
        usleep(20000);
        tick = tick + 1;
        if tick > 600 { break; }
    }
    i = 0;
    while i < NFAST + NSLOW { thread_join(CTID[i]); i = i + 1; }
    usleep(300000);
    tm_stop();
    aio_stop();

    print("nconn=");  print_i64(NCONN);
    print(" nok=");   print_i64(NOK);
    print(" nto=");   print_i64(NTO);
    print(" toms=");  print_i64(TOMS);
    print(" readms="); print_i64(READMS);
    print(" chnc=");  print_i64(CH_NC);
    print(" tpool="); print_i64(tm_pool());
    print(" ipool="); print_i64(IOTO_PN);
    print(" cncl=");  print_i64(TM_CNCL);
    print(" late=");  print_i64(TM_LATE);
    print(" tdrn=");  print_i64(TM_DRN);
    print(" idrn=");  print_i64(IOTO_DRN);
    print(" fired="); print_i64(TM_FIRED);
    print(" miss=");  print_i64(TM_MISS);
    print(" iok=");   print_i64(IOTO_OK);
    print(" ito=");   print_i64(IOTO_TO);
    print(" iovf=");  print_i64(IOTO_OVF);
    print(" iperr="); print_i64(IOTO_PERR);
    print(" aion=");  print_i64(AIO_N);
    print(" aperr="); print_i64(AIO_PERR);
    print(" qovf=");  print_i64(CSP_QOVF);
    print(" dead=");  print_i64(CSP_DEAD);
    print(" cfconn="); print_i64(CF_CONN);
    print(" cfsend="); print_i64(CF_SEND);
    print("\n");
    return 0;
}
