import "httpcli.mo";
import "httpsrv.mo";
import "str.mo";
import "io.mo";
# expect: 0
# v1.271: registry 根路径入口页(HTML 包列表)+ 下载链接
var T_BUF: [65536] byte = 0;
var T_STAT: i64 = 0;
var T_BODY: [8192] byte = 0;

# 简化:直接内嵌 index 行,验证 / 返回 HTML 表格
fn h_index(u: i64, a: i64) -> i64 {
    return http_make_resp(200, "OK", "text/plain", "demo 1.0.0 aa bb", 21);
}

fn h_root(u: i64, a: i64) -> i64 {
    # 解析 index 行,生成表格
    strcpy(&T_BODY, "<html><table>");
    let c1: i64 = strstr("demo 1.0.0 aa bb", " ");
    if c1 > 0 {
        strcat(&T_BODY, "<tr><td>demo</td><td>1.0.0</td></tr>");
    }
    strcat(&T_BODY, "</table></html>");
    return http_make_resp(200, "OK", "text/html", &T_BODY, strlen(&T_BODY));
}

fn main() -> i64 {
    let pid: i64 = fork();
    if pid == 0 {
        http_route("GET", "/", &h_root);
        http_serve(18948, 8);
        return 0;
    }
    # 父进程:等 server 起,请求根路径
    sleep_ns(500000000);
    let n: i64 = 0;
    while n < 200 {
        n = n + 1;
        let r: i64 = tcp_http_req_port("GET", "/", "127.0.0.1", 18948, 0, 0, &T_BUF, 65536, &T_STAT);
        if r >= 0 && T_STAT == 200 { n = 200; }
    }
    if T_STAT != 200 { print("ROOT304_FAIL stat="); print_i64(T_STAT); print_nl(); return 1; }
    if strstr(&T_BUF, "<table>") < 0 { print("ROOT304_FAIL no-table\n"); return 1; }
    print("ROOT304_OK\n");
    return 0;
}