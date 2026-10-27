import "net.mo";
import "str.mo";
import "io.mo";
# expect: 0

var MG_BUF: [128] byte = 0;

fn main() -> i64 {
    let lst: i64 = tcp_listen(18660, 8);
    if lst < 0 { print("m0\n"); return 1; }
    # sock_name：本端 ip+端口
    let pt: i64 = 0;
    let ip: i64 = sock_name(lst, &pt);
    if ip != 0 { print("m1\n"); return 1; }          # 0.0.0.0
    if pt != 18660 { print("m2:"); print_i64(pt); print("\n"); return 1; }
    # sockopt round-trip：SO_RCVBUF
    if sock_set_opt(lst, 1, SO_RCVBUF, 16384) < 0 { print("m3\n"); return 1; }
    let rb: i64 = sock_get_opt(lst, 1, SO_RCVBUF);
    if rb < 8192 { print("m4:"); print_i64(rb); print("\n"); return 1; }
    # SO_TYPE = SOCK_STREAM(1)
    let ty: i64 = sock_get_opt(lst, 1, SO_TYPE);
    if ty != 1 { print("m5:"); print_i64(ty); print("\n"); return 1; }
    # nodelay on listener 无意义但调用须成功;对 socket 用:
    let c: i64 = tcp_socket();
    if sock_nodelay(c) < 0 { print("m6\n"); return 1; }
    if sock_error(c) != 0 { print("m7\n"); return 1; }
    tcp_close(c);
    tcp_close(lst);
    print("MGMT_OK\n");
    return 0;
}
