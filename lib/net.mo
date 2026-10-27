# net —— 极简 TCP 网络库（用墨语言自己写的）
#
# 直接用 Linux syscall，不依赖 libc。
# 这是墨语言能做网络的前提：编译器直接产出 ELF64，
# 而 socket / bind / listen / accept / send / recv 全是系统调用，
# 不需要任何链接库。
#
# 只做 TCPv4 的服务端与客户端，够写一个真正的 HTTP 服务。

import "str.mo";   # strlen

var AF_INET: i64 = 2;
var SOCK_STREAM: i64 = 1;
var INADDR_ANY: i64 = 0;
var ts: [2] i64 = 0;   # sleep_ns 用的 timespec
var SOL_SOCKET: i64 = 1;
var SO_REUSEADDR: i64 = 2;
var SO_KEEPALIVE: i64 = 9;
var SO_RCVTIMEO: i64 = 20;
var SO_SNDTIMEO: i64 = 21;
var SO_RCVBUF: i64 = 8;
var SO_SNDBUF: i64 = 7;
var SO_ERROR: i64 = 4;
var SO_TYPE: i64 = 3;
var IPPROTO_TCP: i64 = 6;
var TCP_NODELAY: i64 = 1;

# 主机序 -> 网络序（16 位）
fn htons(p: i64) -> i64 {
    return ((p & 255) * 256) + ((p / 256) & 255);
}

# 填 sockaddr_in：family(2) + port(2, 网络序) + addr(4) + 填充(8)
fn sock_addr(buf: i64, addr: i64, port: i64) -> i64 {
    # 逐字节写 sockaddr_in：port 必须是**网络序（大端）**——高字节先写。
    # 不能先手工 htons 再逐字节写：那是双重交换（strace 实测 8099 -> 41759，
    # connect 全部 ECONNREFUSED）。逐字节写时直接按大端摆字节即可。
    store8(buf + 0, AF_INET & 255);
    store8(buf + 1, 0);
    store8(buf + 2, (port / 256) & 255);
    store8(buf + 3, port & 255);
    store8(buf + 4, (addr / 16777216) & 255);
    store8(buf + 5, (addr / 65536) & 255);
    store8(buf + 6, (addr / 256) & 255);
    store8(buf + 7, addr & 255);
    let i: i64 = 8;
    while i < 16 {
        store8(buf + i, 0);
        i = i + 1;
    }
    return 16;
}

# socket(AF_INET, SOCK_STREAM, 0)
fn tcp_socket() -> i64 {
    return syscall(41, AF_INET, SOCK_STREAM, 0, 0, 0, 0);
}

# 允许端口复用，避免重启服务时 "address already in use"
fn sock_reuse(fd: i64) -> i64 {
    let opt: [4] i64 = 0;
    store8(&opt, 1);
    return syscall(54, fd, SOL_SOCKET, SO_REUSEADDR, &opt, 4, 0);
}

# 绑定并监听，返回监听 fd；失败返回负数
# 忽略 SIGPIPE（13）：向已关闭连接 write 会让进程直接死。
# HTTP server 必须在 listen 前调用一次。
fn net_nosigpipe() -> i64 {
    let sa: [256] byte = 0;   # struct sigaction（arm64 152 字节，取余量）
    store64(&sa + 0, 1);      # sa_handler = SIG_IGN(1)
    return syscall(134, 13, &sa, 0, 8, 0, 0);   # rt_sigaction(SIGPIPE, act, NULL, 8)
}

fn tcp_listen(port: i64, backlog: i64) -> i64 {
    let fd: i64 = tcp_socket();
    if fd < 0 { return fd; }
    sock_reuse(fd);
    let sa: [16] byte = 0;
    sock_addr(&sa, INADDR_ANY, port);
    let r: i64 = syscall(49, fd, &sa, 16, 0, 0, 0);
    if r < 0 { return 0 - 2; }
    r = syscall(50, fd, backlog, 0, 0, 0, 0);
    if r < 0 { return 0 - 3; }
    return fd;
}

# 接受一个连接，返回新的 fd（失败返回负数）。不关心对端地址
fn tcp_accept(fd: i64) -> i64 {
    return syscall(43, fd, 0, 0, 0, 0, 0);
}

# 连到 ip:port。ip 用 4 字节整数（如 127.0.0.1 写成 0x0100007f）
fn tcp_connect(ip: i64, port: i64) -> i64 {
    let fd: i64 = tcp_socket();
    if fd < 0 { return fd; }
    let sa: [16] byte = 0;
    sock_addr(&sa, ip, port);
    let r: i64 = syscall(42, fd, &sa, 16, 0, 0, 0);
    if r < 0 {
        syscall(3, fd, 0, 0, 0, 0, 0);
        return 0 - 1;
    }
    return fd;
}

# 收数据，返回字节数；0 表示对端关闭，负数表示出错
fn tcp_recv(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(45, fd, buf, n, 0, 0, 0);
}

# 发数据，返回发出的字节数
fn tcp_send(fd: i64, buf: i64, n: i64) -> i64 {
    return syscall(44, fd, buf, n, 0, 0, 0);
}

# 发送以 0 结尾的字符串
fn tcp_send_str(fd: i64, s: i64) -> i64 {
    # 不要写成 tcp_send(fd, s, strlen(s))：
    # 实参里嵌套函数调用会让外层函数名缓冲被内层覆盖，报 undefined symbol。
    # 先算出来再传，顺便避开这个坑。
    let n: i64 = strlen(s);
    return tcp_send(fd, s, n);
}

fn tcp_close(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}

# fork：返回 0 表示子进程
fn fork() -> i64 {
    return syscall(57, 0, 0, 0, 0, 0, 0);
}

# 睡眠 nsec 纳秒。父子进程同步要用：
# 父进程必须等子进程 listen 完再 connect，否则会连不上。
fn sleep_ns(nsec: i64) -> i64 {
    store64(&ts, 0);
    store64(&ts + 8, nsec);
    return syscall(35, &ts, 0, 0, 0, 0, 0);
}

fn exit(code: i64) -> i64 {
    return syscall(60, code, 0, 0, 0, 0, 0);
}

# ================= UDP（v1.191.0）=================
# UDP 客户端/服务端最小集：socket/sendto/recvfrom。
# DNS 查询、发现协议、日志上报都用得上。
var SOCK_DGRAM: i64 = 2;

fn udp_socket() -> i64 {
    return syscall(41, AF_INET, SOCK_DGRAM, 0, 0, 0, 0);
}

# UDP 绑定端口（服务端）。返回 fd，失败负数。
fn udp_bind(port: i64) -> i64 {
    let fd: i64 = udp_socket();
    if fd < 0 { return fd; }
    let sa: [16] byte = 0;
    sock_addr(&sa, INADDR_ANY, port);
    if syscall(49, fd, &sa, 16, 0, 0, 0) < 0 {
        syscall(57, fd, 0, 0, 0, 0, 0);
        return -1;
    }
    return fd;
}

# UDP 发送到 addr:port（addr = htonl 值，127.0.0.1=2130706433）
# 返回发送字节数，失败负数。
fn udp_sendto(fd: i64, buf: ptr, n: i64, addr: i64, port: i64) -> i64 {
    let sa: [16] byte = 0;
    sock_addr(&sa, addr, port);
    return syscall(44, fd, buf, n, 0, &sa, 16);
}

# UDP 接收（阻塞）。src 存来源 addr（htonl 值），sport 存来源端口。
# src/sport 传 0 表示不关心来源。返回接收字节数，失败负数。
fn udp_recvfrom(fd: i64, buf: ptr, n: i64, src: ptr, sport: ptr) -> i64 {
    let sa: [16] byte = 0;
    let sl: [4] i64 = 0;
    store64(&sl, 16);
    let r: i64 = syscall(45, fd, buf, n, 0, &sa, &sl);
    if r >= 0 {
        if src != 0 {
            store8(src + 0, 0); store8(src + 1, 0);
            # addr 大端 4 字节 -> 按 htonl 语义拼回整数
            let a0: i64 = sa[4];
            let a1: i64 = sa[5];
            let a2: i64 = sa[6];
            let a3: i64 = sa[7];
            let a: i64 = a0 * 16777216 + a1 * 65536 + a2 * 256 + a3;
            store64(src, a);
        }
        if sport != 0 {
            store64(sport, sa[2] * 256 + sa[3]);
        }
    }
    return r;
}

# sendmsg/recvmsg（v1.219）：msghdr 最小封装（单 iovec）。
# msghdr 布局（x86_64/aarch64 相同）：name(8) namelen(4+4pad) iov(8) iovlen(8)
#   control(8) controllen(8) flags(4+4pad) —— 共 56 字节。
var NMSG: [14] i64 = 0;
var NIOV: [2] i64 = 0;

fn tcp_sendmsg(fd: i64, buf: ptr, n: i64) -> i64 {
    # NIOV[0]=iov_base, NIOV[1]=iov_len
    NIOV[0] = buf;
    NIOV[1] = n;
    # NMSG 全零（无 name/control），iov 指针在 offset 16, iovlen offset 24
    NMSG[2] = &NIOV;
    NMSG[3] = 1;
    return syscall(46, fd, &NMSG, 0, 0, 0, 0);
}

fn tcp_recvmsg(fd: i64, buf: ptr, n: i64) -> i64 {
    NIOV[0] = buf;
    NIOV[1] = n;
    NMSG[2] = &NIOV;
    NMSG[3] = 1;
    return syscall(47, fd, &NMSG, 0, 0, 0, 0);
}

fn udp_close(fd: i64) -> i64 {
    return syscall(3, fd, 0, 0, 0, 0, 0);
}

var TVB: [2] i64 = 0;    # timeval {sec, usec}

fn sock_set_rcvtimeo(fd: i64, sec: i64) -> i64 {
    TVB[0] = sec;
    TVB[1] = 0;
    return syscall(54, fd, 1, 20, &TVB, 16, 0);
}

# ---------- v1.246 IP 字符串 ↔ 整数（大端 sock_addr 兼容） ----------
var IP_I: i64 = 0;
var IP_V: i64 = 0;
var IP_OCT: i64 = 0;
var IP_C: i64 = 0;
var IP_NDOT: i64 = 0;

# "1.2.3.4" → 大端 u32（sock_addr 直接可用）；非法返 -1
fn ip_parse(s: ptr) -> i64 {
    IP_V = 0; IP_I = 0; IP_OCT = 0; IP_NDOT = 0;
    while 1 {
        IP_C = load8(s + IP_I);
        if IP_C == 0 {
            if IP_NDOT != 3 { return 0 - 1; }
            IP_V = IP_V * 256 + IP_OCT;
            return IP_V;
        }
        if IP_C == 46 {
            if IP_OCT > 255 { return 0 - 1; }
            IP_V = IP_V * 256 + IP_OCT;
            IP_OCT = 0; IP_NDOT = IP_NDOT + 1; IP_I = IP_I + 1;
            if IP_NDOT > 3 { return 0 - 1; }
        } else if IP_C >= 48 && IP_C <= 57 {
            IP_OCT = IP_OCT * 10 + (IP_C - 48);
            if IP_OCT > 255 { return 0 - 1; }
            IP_I = IP_I + 1;
        } else { return 0 - 1; }
    }
}

# 大端 u32 → "a.b.c.d"（dst 容量 ≥16）
var IPS_I: i64 = 0;
var IPS_B: i64 = 0;
var IPS_T: i64 = 0;
var IPS_D: [4] i64 = 0;
fn ip_to_str(dst: ptr, ip: i64) -> i64 {
    IPS_I = 3;
    while IPS_I >= 0 {
        IPS_D[3 - IPS_I] = (ip >> (IPS_I * 8)) & 255;
        IPS_I = IPS_I - 1;
    }
    strcpy(dst, "");
    IPS_I = 0;
    while IPS_I < 4 {
        if IPS_I > 0 { strcat(dst, "."); }
        strcat_i64(dst, IPS_D[IPS_I]);
        IPS_I = IPS_I + 1;
    }
    return 0;
}

# ---------- v1.247 网络管理面：sockopt 全家 / sockname / peername / shutdown ----------
# socket 层常量（x86 值；aarch64 asm-generic 同值：SOL_SOCKET=1，SO_* 同）
# setsockopt(fd, level, opt, val_int)：整型选项快捷
fn sock_set_opt(fd: i64, level: i64, opt: i64, val: i64) -> i64 {
    let v: i64 = val;
    return syscall(54, fd, level, opt, &v, 4, 0);
}
# getsockopt(fd, level, opt) → 整型值（-1 错误，值本身可能 -1 用 sock_opt_err 区分）
var SOPT_V: i64 = 0;
var SOPT_L: i64 = 4;
fn sock_get_opt(fd: i64, level: i64, opt: i64) -> i64 {
    SOPT_L = 4;
    let rc: i64 = syscall(55, fd, level, opt, &SOPT_V, &SOPT_L, 0);
    if rc < 0 { return 0 - 1; }
    return SOPT_V;
}
# getsockname(fd) → 大端 u32 ip（端口写 *port）；-1 错
var SN_ADDR: [16] byte = 0;
var SN_LEN: i64 = 16;
fn sock_name(fd: i64, port: ptr) -> i64 {
    SN_LEN = 16;
    let rc: i64 = syscall(51, fd, &SN_ADDR, &SN_LEN, 0, 0, 0);
    if rc < 0 { return 0 - 1; }
    store64(port, load8(&SN_ADDR + 2) * 256 + load8(&SN_ADDR + 3));
    return load8(&SN_ADDR + 4) * 16777216 + load8(&SN_ADDR + 5) * 65536 + load8(&SN_ADDR + 6) * 256 + load8(&SN_ADDR + 7);
}
# getpeername(fd) 同形态
var PN_ADDR: [16] byte = 0;
var PN_LEN: i64 = 16;
fn sock_peer(fd: i64, port: ptr) -> i64 {
    PN_LEN = 16;
    let rc: i64 = syscall(52, fd, &PN_ADDR, &PN_LEN, 0, 0, 0);
    if rc < 0 { return 0 - 1; }
    store64(port, load8(&PN_ADDR + 2) * 256 + load8(&PN_ADDR + 3));
    return load8(&PN_ADDR + 4) * 16777216 + load8(&PN_ADDR + 5) * 65536 + load8(&PN_ADDR + 6) * 256 + load8(&PN_ADDR + 7);
}
# shutdown(fd, how)：0=读 1=写 2=双
fn sock_shutdown(fd: i64, how: i64) -> i64 {
    return syscall(48, fd, how, 0, 0, 0, 0);
}
# TCP_NODELAY 开关
fn sock_nodelay(fd: i64) -> i64 {
    return sock_set_opt(fd, IPPROTO_TCP, TCP_NODELAY, 1);
}
# SO_ERROR 清障读取
fn sock_error(fd: i64) -> i64 {
    return sock_get_opt(fd, 1, SO_ERROR);
}
