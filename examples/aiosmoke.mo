import "io.mo";
import "csp.mo";
import "aio.mo";
import "net.mo";

var LFD: i64 = 0;
var GOT: i64 = 0;
var NCONN: i64 = 0;
var PORT: i64 = 0;

fn acceptor() -> i64 {
    let lfd: i64 = csp_arg();
    let i: i64 = 0;
    while i < 3 {
        let c: i64 = aio_accept(lfd);
        if c < 0 { print("accept fail\n"); csp_exit(); return 0; }
        NCONN = NCONN + 1;
        let buf: [64] byte = 0;
        let n: i64 = aio_recv(c, &buf, 63);
        if n > 0 { GOT = GOT + n; buf[n] = 0; }
        let msg: [32] byte = 0;
        msg[0] = 79; msg[1] = 75; msg[2] = 10; msg[3] = 0;
        aio_send(c, &msg, 3);
        aio_close(c);
        i = i + 1;
    }
    csp_exit();
    return 0;
}

fn main() -> i64 {
    PORT = 18230;
    if csp_init(2) != 0 { print("csp_init fail\n"); return 1; }
    if aio_init() != 0 { print("aio_init fail\n"); return 1; }
    LFD = tcp_listen(PORT, 16);
    if LFD < 0 { print("listen fail\n"); return 1; }
    aio_nbio(LFD);

    if csp_go(&acceptor, LFD) < 0 { print("csp_go fail\n"); return 1; }

    # main 不是协程，用阻塞式客户端连 3 次
    let i: i64 = 0;
    while i < 3 {
        let fd: i64 = tcp_connect(0x0100007f, PORT);
        if fd < 0 { print("connect fail\n"); return 1; }
        let s: [16] byte = 0;
        s[0] = 104; s[1] = 105; s[2] = 33; s[3] = 0;   # "hi!"
        tcp_send(fd, &s, 3);
        let rb: [64] byte = 0;
        let n: i64 = tcp_recv(fd, &rb, 63);
        print("client got: ");
        if n > 0 { rb[n] = 0; print(&rb); }
        print("\n");
        tcp_close(fd);
        i = i + 1;
    }

    let spin: i64 = 0;
    while NCONN < 3 {
        usleep(1000);
        spin = spin + 1;
        if spin > 3000 { break; }
    }
    print("NCONN="); print_i64(NCONN); print("\n");
    print("GOT=");   print_i64(GOT);   print("\n");
    print("WOKE=");  print_i64(AIO_WOKE); print("\n");
    print("PERR=");  print_i64(AIO_PERR); print("\n");
    print("QOVF=");  print_i64(CSP_QOVF); print("\n");
    aio_stop();
    return 0;
}
