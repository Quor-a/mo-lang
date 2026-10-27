import "net.mo";
import "str.mo";
import "io.mo";
# expect: 0

var SRV_BUF: [256] byte = 0;
var SRV_IP: [16] byte = 0;

fn main() -> i64 {
    # ① ip 工具
    let ip: i64 = ip_parse("127.0.0.1");
    if ip != 2130706433 { print("n1\n"); return 1; }
    # ② 回环 echo:E2E 一条
    let lst: i64 = tcp_listen(18650, 8);
    if lst < 0 { print("n2\n"); return 1; }
    let pid: i64 = fork();
    if pid == 0 {
        let c: i64 = tcp_connect(ip, 18650);
        if c < 0 { exit(9); }
        tcp_send_str(c, "PING123");
        tcp_recv(c, &SRV_BUF, 64);
        if streq(&SRV_BUF, "ECHO:PING123") != 1 { exit(8); }
        tcp_close(c);
        exit(0);
    }
    let fd: i64 = tcp_accept(lst);
    if fd < 0 { print("n3\n"); return 1; }
    let n: i64 = tcp_recv(fd, &SRV_BUF, 64);
    # 构造响应 "ECHO:" + 收到内容
    strcpy(&SRV_IP, "ECHO:");
    strcat(&SRV_IP, &SRV_BUF);
    tcp_send_str(fd, &SRV_IP);
    tcp_close(fd);
    tcp_close(lst);
    # 等 fork 子进程退出码
    let st: i64 = 0;
    let wr: i64 = syscall(61, pid, &st, 0, 0, 0, 0);   # wait4 → x86;mo2x 翻译
    if (st & 255) != 0 { print("n4 st="); print_i64(st); print("\n"); return 1; }
    print("NETX_OK\n");
    return 0;
}
