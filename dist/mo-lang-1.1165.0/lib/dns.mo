# dns —— 最小 DNS 解析器（用墨语言自己写的）
#
# 不依赖 libc 的 resolv：自己读 /etc/resolv.conf 找 nameserver，
# 手工拼 DNS 查询包（UDP 53），解析 A 记录响应。
# 只支持"一次查询一个 A 记录"的最小闭环——够 curl 类客户端用。
#
# 铁律（v1.190.0 踩坑继承）：addr 一律是 htonl 值（如 127.0.0.1=2130706433）。
import "net.mo";
import "str.mo";
import "io.mo";

var NSADDR: i64 = 0;          # nameserver（htonl 值）
var QBUF: [2048] byte = 0;
var TCPB: [4] byte = 0;    # TCP 长度前缀缓冲     # 查询/响应包缓冲（单线程用）
var DNSID: i64 = 4321;
var DNS_PORT: i64 = 53;   # 测试时可指向本地假 DNS        # 事务 ID（固定够用）

# 读 /etc/resolv.conf 的第一个 nameserver 到 NSADDR（htonl）
# 返回 0 成功；-1 失败（用默认 8.8.8.8 兜底由调用方决定）
fn dns_load_resolv() -> i64 {
    let fd: i64 = syscall(2, "/etc/resolv.conf", 0, 0, 0, 0, 0);   # open(O_RDONLY)
    if fd < 0 { return -1; }
    let n: i64 = syscall(0, fd, &QBUF, 500, 0, 0, 0);   # read
    syscall(3, fd, 0, 0, 0, 0, 0);
    if n <= 0 { return -1; }
    store8(&QBUF + n, 0);
    # 找 "nameserver " 行
    let i: i64 = 0;
    while QBUF[i] != 0 {
        if str_starts_with(&QBUF + i, "nameserver ") == 1 {
            let p: i64 = i + 11;
            let a: i64 = 0;
            let b: i64 = 0;
            while QBUF[p] != 0 && QBUF[p] != 10 && QBUF[p] != 13 {
                if QBUF[p] == 46 {
                    a = a * 256 + b;
                    b = 0;
                } else {
                    if QBUF[p] >= 48 {
                        if QBUF[p] <= 57 {
                            b = b * 10 + (QBUF[p] - 48);
                        }
                    }
                }
                p = p + 1;
            }
            a = a * 256 + b;
            NSADDR = a;
            return 0;
        }
        while QBUF[i] != 0 && QBUF[i] != 10 { i = i + 1; }
        if QBUF[i] == 0 { break; }
        i = i + 1;
    }
    return -1;
}

# 把域名编码成 DNS QNAME（3www7example3com0）追加到 dst+*off
fn dns_enc_name(dst: ptr, off: ptr, host: ptr) -> i64 {
    let o: i64 = off[0];
    let i: i64 = 0;
    let seg: i64 = 0;
    while host[i] != 0 {
        if host[i] == 46 {
            store8(dst + o, seg);
            o = o + 1;
            let k: i64 = 0;
            while k < seg {
                store8(dst + o, host[i - seg + k]);
                o = o + 1;
                k = k + 1;
            }
            seg = 0;
        } else {
            seg = seg + 1;
        }
        i = i + 1;
    }
    store8(dst + o, seg);
    o = o + 1;
    let k: i64 = 0;
    while k < seg {
        store8(dst + o, host[i - seg + k]);
        o = o + 1;
        k = k + 1;
    }
    store8(dst + o, 0);
    o = o + 1;
    off[0] = o;
    return 0;
}

# 解析 host 的 A 记录，返回 htonl 值的 IP；失败返回 0

fn dns_query_tcp(n: i64) -> i64 {
    # TCP DNS：2 字节长度前缀 + 查询包；返回响应字节数（存 QBUF），失败 0
    let fd: i64 = tcp_connect(NSADDR, DNS_PORT);
    if fd < 0 { return 0; }
    store8(&TCPB + 0, (n / 256) & 255);
    store8(&TCPB + 1, n & 255);
    if tcp_send(fd, &TCPB, 2) != 2 { tcp_close(fd); return 0; }
    if tcp_send(fd, &QBUF, n) != n { tcp_close(fd); return 0; }
    let got: i64 = 0;
    let r: i64 = 0;
    while got < 2 {
        r = tcp_recv(fd, &TCPB + got, 2 - got);
        if r <= 0 { tcp_close(fd); return 0; }
        got = got + r;
    }
    let m: i64 = TCPB[0] * 256 + TCPB[1];
    if m <= 20 || m > 2048 { tcp_close(fd); return 0; }
    got = 0;
    while got < m {
        r = tcp_recv(fd, &QBUF + got, m - got);
        if r <= 0 { tcp_close(fd); return 0; }
        got = got + r;
    }
    tcp_close(fd);
    return m;
}

fn dns_resolve(host: ptr) -> i64 {
    if NSADDR == 0 {
        if dns_load_resolv() != 0 {
            NSADDR = 167772169;   # 8.8.8.8 = 10.0.0.0/1... 实际 8*16777216+8*65536+8*256+8
        }
    }
    # 拼查询包：ID(2) flags(2)=0x0100 QDCount(2)=1 其余 0
    let n: i64 = 0;
    store8(&QBUF + 0, (DNSID / 256) & 255);
    store8(&QBUF + 1, DNSID & 255);
    store8(&QBUF + 2, 1);   # RD=1
    store8(&QBUF + 3, 0);
    store8(&QBUF + 4, 0); store8(&QBUF + 5, 1);   # QDCOUNT=1
    store8(&QBUF + 6, 0); store8(&QBUF + 7, 0);
    store8(&QBUF + 8, 0); store8(&QBUF + 9, 0);
    store8(&QBUF + 10, 0); store8(&QBUF + 11, 0);
    n = 12;
    let off: [1] i64 = 0;
    off[0] = n;
    dns_enc_name(&QBUF, &off, host);
    n = off[0];
    store8(&QBUF + n, 0); store8(&QBUF + n + 1, 1);   # QTYPE=A
    store8(&QBUF + n + 2, 0); store8(&QBUF + n + 3, 1); # QCLASS=IN
    n = n + 4;
    # 发 UDP
    let fd: i64 = udp_socket();
    if fd < 0 { return 0; }
    sock_set_rcvtimeo(fd, 3);
    udp_sendto(fd, &QBUF, n, NSADDR, DNS_PORT);
    # 收响应（阻塞，2KB 内）
    let m: i64 = udp_recvfrom(fd, &QBUF, 2048, 0, 0);
    udp_close(fd);
    if m <= 20 { m = dns_query_tcp(n); }
    if m <= 20 { return 0; }
    # 校验 ID
    if QBUF[0] * 256 + QBUF[1] != DNSID { return 0; }
    # QR=1 且 RCODE=0
    if (QBUF[2] & 128) == 0 { return 0; }
    if (QBUF[3] & 15) != 0 { return 0; }
    let qd: i64 = QBUF[4] * 256 + QBUF[5];
    let an: i64 = QBUF[6] * 256 + QBUF[7];
    if an == 0 { return 0; }
    # 跳过所有 Question
    let p: i64 = 12;
    let k: i64 = 0;
    while k < qd {
        while QBUF[p] != 0 {
            if (QBUF[p] & 192) == 192 { p = p + 1; break; }
            p = p + QBUF[p] + 1;
        }
        p = p + 5;   # 0 字节 + QTYPE(2)+QCLASS(2)
        k = k + 1;
    }
    # 找第一个 A 记录（TYPE=1 RDLENGTH=4）
    k = 0;
    while k < an {
        # 名字（可能是压缩指针 0xC0）
        if (QBUF[p] & 192) == 192 {
            p = p + 2;
        } else {
            while QBUF[p] != 0 { p = p + QBUF[p] + 1; }
            p = p + 1;
        }
        let rtype: i64 = QBUF[p] * 256 + QBUF[p + 1];
        let rdlen: i64 = QBUF[p + 8] * 256 + QBUF[p + 9];
        if rtype == 1 && rdlen == 4 {
            let b0: i64 = QBUF[p + 10];
            let b1: i64 = QBUF[p + 11];
            let b2: i64 = QBUF[p + 12];
            let b3: i64 = QBUF[p + 13];
            let a: i64 = b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
            return a;
        }
        p = p + 10 + rdlen;
        k = k + 1;
    }
    return 0;
}

# ---------- v1.250 DNS 缓存 ----------
var DNC_K: [32] i64 = 0;     # hostname ptr
var DNC_V: [32] i64 = 0;     # ip
var DNC_N: i64 = 0;
var DNC_I: i64 = 0;

# 带缓存解析：命中直接回；未命中 resolve 并存（容量 32，满则不缓存）
fn dns_resolve_cached(host: ptr) -> i64 {
    DNC_I = 0;
    while DNC_I < DNC_N {
        if streq(DNC_K[DNC_I], host) == 1 { return DNC_V[DNC_I]; }
        DNC_I = DNC_I + 1;
    }
    let ip: i64 = dns_resolve(host);
    if ip > 0 && DNC_N < 32 {
        DNC_K[DNC_N] = str_dup(host);
        DNC_V[DNC_N] = ip;
        DNC_N = DNC_N + 1;
    }
    return ip;
}
