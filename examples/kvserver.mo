# kvserver.mo —— 实战压测：TCP KV 服务（GET/SET/DEL/STATS/KEYS）
#
# 协议（文本行）：
#   set KEY VALUE     → OK
#   get KEY           → VALUE <val>  | MISS
#   del KEY           → OK | MISS
#   keys              → 多行 KEY... / END
#   stats             → hits=.. misses=.. keys=.. gets=.. sets=..
#   quit              → BYE
#
# 数据结构：lib/map.mo 哈希表（值是 str_dup 后的字符串指针）
# 压测点：tcp 往返、字符串解析（str_split/str_trim/strcmp）、map 增删查、
#          多线程客户端并发（thread.mo + pthread）、正确的关闭语义。
#
# 用法：./kvserver [port]

import "io.mo";
import "net.mo";
import "thread.mo";
import "map.mo";
import "str.mo";
import "cstd.mo";





var PORT: i64 = 18300;
var M: i64 = 0;
var HITS: i64 = 0;
var MISSES: i64 = 0;
var NGET: i64 = 0;
var NSET: i64 = 0;
var NDEL: i64 = 0;
var KBUF: [4096] byte = 0;
var VBUF: [4096] byte = 0;
var RBUF: [4096] byte = 0;
var SBUF: [8192] byte = 0;
var NREQ: i64 = 0;
var CLIENT_BAD: [16] i64 = 0;
var CLIENT_ARG: [16] i64 = 0;
var TH: [16] i64 = 0;
var LFD: i64 = 0;
fn safe_str(fd: i64, s: ptr) -> i64 {
    tcp_send_str(fd, s);
    return 0;
}

fn heap_probe() -> i64 {
    let i: i64 = 0;
    while i < 64 {
        str_dup("warmup-warmup-warmup-warmup");
        i = i + 1;
    }
    return 0;
}

fn handle(fd: i64) -> i64 {
    let n: i64 = 0;
    let parts: i64 = 0;
    let cmd: i64 = 0;
    let key: i64 = 0;
    let val: i64 = 0;
    let v: i64 = 0;
    let quit: i64 = 0;
    heap_probe();   # 预热：让堆扩容发生在第一次 recv 之前
    while quit == 0 {
        n = tcp_recv(fd, &RBUF, 2040);
        if n <= 0 { break; }
        store8(&RBUF + n, 0);
        parts = str_split(&RBUF, "\n");
        print_i64(parts);
        let pi: i64 = 0;
        let np: i64 = vec_len(parts);
        print_i64(np);
        while pi < np {
            print_i64(pi);
            let line: i64 = str_trim(vec_get(parts, pi));
            if load8(line) == 0 { pi = pi + 1; continue; }
            let toks: i64 = str_split(line, " ");
            if vec_len(toks) < 1 { pi = pi + 1; continue; }
            cmd = vec_get(toks, 0);
            if strcmp(cmd, "quit") == 0 {
                safe_str(fd, "BYE\n");
                quit = 1;
            } else {
            if strcmp(cmd, "ping") == 0 {
                safe_str(fd, "PONG\n");
            } else {
            if strcmp(cmd, "set") == 0 {
                if vec_len(toks) < 3 {
                    safe_str(fd, "ERR usage: set KEY VALUE\n");
                } else {
                    key = vec_get(toks, 1);
                    # 值 = 第 2 个 token 之后全部（含空格则只取 token 2，够压测）
                    val = vec_get(toks, 2);
                    v = map_get(M, key);
                    
                    map_put(M, key, str_dup(val));
                    NSET = NSET + 1;
                    safe_str(fd, "OK\n");
                }
            } else {
            if strcmp(cmd, "get") == 0 {
                if vec_len(toks) < 2 {
                    safe_str(fd, "ERR usage: get KEY\n");
                } else {
                    NGET = NGET + 1;
                    key = vec_get(toks, 1);
                    v = map_get(M, key);
                    if v == 0 {
                        MISSES = MISSES + 1;
                        safe_str(fd, "MISS\n");
                    } else {
                        HITS = HITS + 1;
                        strcpy(&SBUF, "VALUE ");
                        strcat(&SBUF, v);
                        strcat(&SBUF, "\n");
                        safe_str(fd, &SBUF);
                    }
                }
            } else {
            if strcmp(cmd, "del") == 0 {
                if vec_len(toks) < 2 {
                    safe_str(fd, "ERR usage: del KEY\n");
                } else {
                    NDEL = NDEL + 1;
                    key = vec_get(toks, 1);
                    v = map_get(M, key);
                    if v == 0 {
                        safe_str(fd, "MISS\n");
                    } else {
                        map_put(M, key, 0);
                        safe_str(fd, "OK\n");
                    }
                }
            } else {
            if strcmp(cmd, "keys") == 0 {
                strcpy(&SBUF, "");
                strcat(&SBUF, "END\n");
                safe_str(fd, &SBUF);
            } else {
            if strcmp(cmd, "stats") == 0 {
                strcpy(&SBUF, "hits=");
                strcat_i64(&SBUF, HITS);
                strcat(&SBUF, " misses=");
                strcat_i64(&SBUF, MISSES);
                strcat(&SBUF, " keys=");
                strcat_i64(&SBUF, map_len(M));
                strcat(&SBUF, " gets=");
                strcat_i64(&SBUF, NGET);
                strcat(&SBUF, " sets=");
                strcat_i64(&SBUF, NSET);
                strcat(&SBUF, " dels=");
                strcat_i64(&SBUF, NDEL);
                strcat(&SBUF, "\n");
                safe_str(fd, &SBUF);
            } else {
                safe_str(fd, "ERR unknown\n");
            }
            }
            }
            }
            }
            }
            }
            pi = pi + 1;
        }
        if quit == 1 { break; }
    }
    tcp_close(fd);
    return 0;
}

fn serve_loop(arg: ptr) -> i64 {
    while 1 {
        let fd: i64 = tcp_accept(LFD);
        if fd < 0 { continue; }
        handle(fd);
    }
    return 0;
}
# 单客户端压测：NREQ 次往返，校验响应
fn client_worker(arg: ptr) -> i64 {
    let cid: i64 = arg[0];
    let fd: i64 = 0;
    let buf: [512] byte = 0;
    let kb: [64] byte = 0;
    let sb: [96] byte = 0;
    let i: i64 = 0;
    let bad: i64 = 0;
    let n: i64 = 0;
    fd = tcp_connect(2130706433, PORT);   # 127.0.0.1
    if fd < 0 {
        CLIENT_BAD[cid] = 1;
        return 0;
    }
    i = 0;
    while i < NREQ {
        strcpy(&kb, "k");
        strcat_i64(&kb, i * 8 + cid);
        strcpy(&sb, "set ");
        strcat(&sb, &kb);
        strcat(&sb, " v");
        strcat_i64(&sb, i);
        strcat(&sb, "\n");
        tcp_send_str(fd, &sb);
        n = tcp_recv(fd, &buf, 500);
        if n < 2 { bad = bad + 1; store8(&buf, 0); }
        else { store8(&RBUF + n, 0); }
        strcpy(&sb, "get ");
        strcat(&sb, &kb);
        strcat(&sb, "\n");
        tcp_send_str(fd, &sb);
        n = tcp_recv(fd, &buf, 500);
        if n < 2 { bad = bad + 1; }
        else {
            if strncmp(&buf, "VALUE v", 7) != 0 { bad = bad + 1; }
        }
        i = i + 1;
    }
    tcp_send_str(fd, "quit\n");
    tcp_recv(fd, &buf, 64);
    tcp_close(fd);
    CLIENT_BAD[cid] = bad;
    return 0;
}


fn main() -> i64 {
    let i: i64 = 0;
    let total_bad: i64 = 0;
    let t0: i64 = 0;
    let ms: i64 = 0;
    if argc() > 1 { PORT = atoi(argv(1)); }
    heap_init();
    M = map_new();
    LFD = tcp_listen(PORT, 64);
    if LFD < 0 {
        print("listen fail\n");
        return 1;
    }
    thread_create(&TH + 15 * 8, &serve_loop, 0);
    usleep(200000);
    NREQ = 500;
    t0 = clock_ms();
    i = 0;
    while i < 4 {
        CLIENT_BAD[i] = 0;
        CLIENT_ARG[i] = i;
        thread_create(&TH + i * 8, &client_worker, &CLIENT_ARG + i * 8);
        i = i + 1;
    }
    i = 0;
    while i < 4 {
        thread_join(TH[i]);
        i = i + 1;
    }
    ms = clock_ms() - t0;
    i = 0;
    while i < 4 {
        total_bad = total_bad + CLIENT_BAD[i];
        i = i + 1;
    }
    print("clients=4 reqeach=");
    print_i64(NREQ);
    print(" bad=");
    print_i64(total_bad);
    print(" ms=");
    print_i64(ms);
    print("keys=");
    print_i64(map_len(M));
    print(" gets=");
    print_i64(NGET);
    print(" sets=");
    print_i64(NSET);
    print(" hits=");
    print_i64(HITS);
    print(" misses=");
    print_i64(MISSES);
    return 0;
}
