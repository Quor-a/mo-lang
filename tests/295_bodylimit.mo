import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [16384] byte = 0;

fn h_up(u: i64, a: i64) -> i64 {
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("POST", "/up/:file", &h_up);
        http_max_body(8000);
        http_serve(18937, 8);
        exit(0);
    }
    sleep_ns(200000000);
    # ① CL=8000 ≤ 上限 → 201
    let i: i64 = 0;
    while i < 8000 {
        store8(&T_BODY + i, 65 + (i % 26));
        i = i + 1;
    }
    let b: i64 = tcp_http_req_port("POST", "/up/a.bin", "127.0.0.1", 18937, &T_BODY, 8000, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("b1:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ② CL=8001 > 上限 → 413
    b = tcp_http_req_port("POST", "/up/a.bin", "127.0.0.1", 18937, &T_BODY, 8001, &T_BUF, 65536, &T_STAT);
    if T_STAT != 413 { print("b2:"); print_i64(T_STAT); print("\n"); exit(1); }
    # ③ 413 后 server 仍活(201 再来一次)
    b = tcp_http_req_port("POST", "/up/a.bin", "127.0.0.1", 18937, &T_BODY, 8000, &T_BUF, 65536, &T_STAT);
    if T_STAT != 201 { print("b3:"); print_i64(T_STAT); print("\n"); exit(1); }
    print("LIM_OK\n");
    return 0;
}
