# kvjson.mo —— KV server 的 JSON/HTTP 门面
# 在 kvserver（行协议）之上加 HTTP/1.0 + JSON 接口：
#   GET  /get?key=K      → {"key":"K","value":"V"} 或 {"error":"miss"}
#   GET  /stats          → {"hits":N,"misses":N,"keys":N,"gets":N,"sets":N,"dels":N}
#   POST /set  body={"key":"K","value":"V"}  → {"ok":1}
#   POST /del  body={"key":"K"}              → {"ok":1} / {"error":"miss"}
# 客户端用 lib/json.mo 解析响应 —— 解析器实战验证。
# v1.196.0：HTTP/1.1 keep-alive —— 每连接多请求（Content-Length 定界 + 剩余字节前移），
# 服务端每连接独立线程（8 槽缓冲池），客户端每线程 1 连接跑完全部请求。
import "io.mo";
import "str.mo";
import "map.mo";
import "net.mo";
import "thread.mo";
import "json.mo";
import "cstd.mo";

var PORT: i64 = 18400;
var RBUF: [32768] byte = 0;   # 8 槽 × 4096（slot*4096 偏移）
# per-slot 服务端缓冲（8 槽 × 各自大小）—— keep-alive 多连接并发处理互不干扰
var SBUF: [16384] byte = 0;      # 8 × 2048
var BBUF: [8192] byte = 0;       # 8 × 1024
var KEYB: [1024] byte = 0;       # 8 × 128
var VALB: [2048] byte = 0;       # 8 × 256
var EXPB: [2048] byte = 0;       # 8 × 256
var TBUF: [8192] byte = 0;       # 8 × 1024
# per-client 压测缓冲（4 线程各一份，cid*步长偏移）——全局缓冲跨线程共享会互踩
var CKEY: [1024] byte = 0;
var CVAL: [1024] byte = 0;
var CEXP: [1024] byte = 0;
var CBOD: [4096] byte = 0;
var CSND: [8192] byte = 0;
var CRCV: [16384] byte = 0;
var M: i64 = 0;
var LFD: i64 = 0;
var HITS: i64 = 0;
var MISSES: i64 = 0;
var NGET: i64 = 0;
var NSET: i64 = 0;
var NDEL: i64 = 0;
var NREQ: i64 = 0;
var ROUNDS: i64 = 0;
var CLIENT_BAD: [16] i64 = 0;
var CLIENT_ARG: [16] i64 = 0;
var TH: [16] i64 = 0;
var JMTX: [64] i64 = 0;   # json 库全局游标互斥锁（json.mo 的 J_* 非线程安全）
var SMTX: [64] i64 = 0;   # 请求缓冲/统计互斥
var NSLOT: i64 = 8;
var CONN_BUF: [32768] byte = 0;   # 8 槽 * 4096，每连接独立请求缓冲
var CONN_LEN: [8] i64 = 0;        # 每槽当前缓冲内字节数
var CONN_FD: [8] i64 = 0;         # 槽位 → fd
var SLOT_ARG: [8] i64 = 0;
var STH: [8] i64 = 0;

fn send_all(fd: i64, s: ptr) -> i64 {
    let n: i64 = strlen(s);
    let sent: i64 = 0;
    while sent < n {
        let w: i64 = tcp_send(fd, s + sent, n - sent);
        if w <= 0 { return 0 - 1; }
        sent = sent + w;
    }
    return 0;
}

fn resp_json(slot: i64, fd: i64, body: ptr) -> i64 {
    # body 可能就是 &SBUF（api_* 先拼 body 再 resp）—— 先拷进 TBUF，避免 strcat(SBUF,SBUF) 自拼接 UB
    strcpy(&TBUF + slot * 1024, body);
    strcpy(&SBUF + slot * 2048, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: keep-alive\r\nContent-Length: ");
    strcat_i64(&SBUF + slot * 2048, strlen(&TBUF + slot * 1024));
    strcat(&SBUF + slot * 2048, "\r\n\r\n");
    strcat(&SBUF + slot * 2048, &TBUF + slot * 1024);
    send_all(fd, &SBUF + slot * 2048);
    return 0;
}

fn api_get(slot: i64, fd: i64) -> i64 {
    NGET = NGET + 1;
    json_str(&RBUF + slot * 4096, "key", &KEYB + slot * 128);
    let v: i64 = map_get(M, &KEYB + slot * 128);
    if v == 0 {
        MISSES = MISSES + 1;
        strcpy(&SBUF + slot * 2048, "{\"error\":\"miss\",\"key\":\"");
        strcat(&SBUF + slot * 2048, &KEYB + slot * 128);
        strcat(&SBUF + slot * 2048, "\"}");
        resp_json(slot, fd, &SBUF + slot * 2048);
        return 0;
    }
    HITS = HITS + 1;
    strcpy(&SBUF + slot * 2048, "{\"key\":\"");
    strcat(&SBUF + slot * 2048, &KEYB + slot * 128);
    strcat(&SBUF + slot * 2048, "\",\"value\":\"");
    strcat(&SBUF + slot * 2048, v);
    strcat(&SBUF + slot * 2048, "\"}");
    resp_json(slot, fd, &SBUF + slot * 2048);
}

fn api_set(slot: i64, fd: i64) -> i64 {
    if json_str(&RBUF + slot * 4096, "key", &KEYB + slot * 128) == 0 {
        resp_json(slot, fd, "{\"error\":\"nokey\"}");
        return 0;
    }
    if json_str(&RBUF + slot * 4096, "value", &VALB + slot * 256) == 0 {
        resp_json(slot, fd, "{\"error\":\"novalue\"}");
        return 0;
    }
    map_put(M, &KEYB + slot * 128, str_dup(&VALB + slot * 256));
    NSET = NSET + 1;
    resp_json(slot, fd, "{\"ok\":1}");
}

fn api_del(slot: i64, fd: i64) -> i64 {
    if json_str(&RBUF + slot * 4096, "key", &KEYB + slot * 128) == 0 {
        resp_json(slot, fd, "{\"error\":\"nokey\"}");
        return 0;
    }
    let v: i64 = map_get(M, &KEYB + slot * 128);
    if v == 0 {
        resp_json(slot, fd, "{\"error\":\"miss\"}");
        return 0;
    }
    map_put(M, &KEYB + slot * 128, 0);
    NDEL = NDEL + 1;
    resp_json(slot, fd, "{\"ok\":1}");
}

fn api_stats(slot: i64, fd: i64) -> i64 {
    strcpy(&SBUF + slot * 2048 + slot * 2048, "{\"hits\":");
    strcat_i64(&SBUF + slot * 2048, HITS);
    strcat(&SBUF + slot * 2048, ",\"misses\":");
    strcat_i64(&SBUF + slot * 2048, MISSES);
    strcat(&SBUF + slot * 2048, ",\"keys\":");
    strcat_i64(&SBUF + slot * 2048, map_len(M));
    strcat(&SBUF + slot * 2048, ",\"gets\":");
    strcat_i64(&SBUF + slot * 2048, NGET);
    strcat(&SBUF + slot * 2048, ",\"sets\":");
    strcat_i64(&SBUF + slot * 2048, NSET);
    strcat(&SBUF + slot * 2048, ",\"dels\":");
    strcat_i64(&SBUF + slot * 2048, NDEL);
    strcat(&SBUF + slot * 2048, "}");
    resp_json(slot, fd, &SBUF + slot * 2048);
    return 0;
}

# 解析请求行：METHOD /path HTTP/1.x，body 留在 RBUF（json 函数从 RBUF 找 key）

# 从槽缓冲取一个完整请求（找到 \r\n\r\n + Content-Length body 到齐）
# 返回：1=有请求（RBUF 已填好），0=缓冲里没有完整请求
fn try_extract(slot: i64) -> i64 {
    let p: i64 = strstr(&CONN_BUF, "\r\n\r\n");
    if p < 0 { return 0; }
    let hdr_end: i64 = p + 4;   # strstr: 0 基偏移，-1=未找到
    # 从 headers 提 Content-Length
    let cl: i64 = 0;
    let q: i64 = 0;
    let line: i64 = strstr(&CONN_BUF, "Content-Length: ");
    if line >= 0 {
        q = line + 16;
        while CONN_BUF[q] != 13 {
            cl = cl * 10 + CONN_BUF[q] - 48;
            q = q + 1;
        }
    }
    let total: i64 = hdr_end + cl;
    if CONN_LEN[0] < total { return 0; }
    # 拷请求到槽 RBUF 并把剩余前移
    memcpy(&RBUF + slot * 4096, &CONN_BUF, total);
    store8(&RBUF + slot * 4096 + total, 0);
    memcpy(&CONN_BUF, &CONN_BUF + total, CONN_LEN[0] - total);
    CONN_LEN[0] = CONN_LEN[0] - total;
    store8(&CONN_BUF + CONN_LEN[0], 0);
    return 1;
}

var MAX_PER_CONN: i64 = 50;    # 每连接服务上限，到点主动 close 让其他连接进来

fn handle_slot(arg: ptr) -> i64 {
    let slot: i64 = arg[0];
    let fd: i64 = CONN_FD[slot];
    sock_set_rcvtimeo(fd, 5);
    memcpy(&CONN_BUF, &CONN_BUF + slot * 4096, CONN_LEN[slot]);
    CONN_LEN[0] = CONN_LEN[slot];
    let is_get: i64 = 0;
    let is_set: i64 = 0;
    let is_del: i64 = 0;
    let is_stats: i64 = 0;
    let alive: i64 = 1;
    let served: i64 = 0;
    while alive == 1 {
        served = served + 1;
        if served > MAX_PER_CONN { break; }
        # 1) 缓冲里先试提取
        if try_extract(slot) == 0 {
            # 2) 不够则再收
            let n: i64 = tcp_recv(fd, &CONN_BUF + CONN_LEN[0], 4096 - CONN_LEN[0]);
            if n <= 0 { break; }
            CONN_LEN[0] = CONN_LEN[0] + n;
            store8(&CONN_BUF + CONN_LEN[0], 0);
            if try_extract(slot) == 0 {
                if CONN_LEN[0] >= 4096 { break; }   # 溢出防御
                continue;
            }
        }
        NREQ = NREQ + 1;
        is_get = str_starts_with(&RBUF + slot * 4096, "GET /get");
        is_stats = str_starts_with(&RBUF + slot * 4096, "GET /stats");
        is_set = str_starts_with(&RBUF + slot * 4096, "POST /set");
        is_del = str_starts_with(&RBUF + slot * 4096, "POST /del");
        if is_get == 1 {
            api_get(slot, fd);
        } else {
            if is_stats == 1 {
                api_stats(slot, fd);
            } else {
                if is_set == 1 {
                    api_set(slot, fd);
                } else {
                    if is_del == 1 {
                        api_del(slot, fd);
                    } else {
                        resp_json(slot, fd, "{\"error\":\"unknown\"}");
                    }
                }
            }
        }
    }
    tcp_close(fd);
    CONN_FD[slot] = 0;
    CONN_LEN[slot] = 0;
    CONN_LEN[0] = 0;
    return 0;
}

# 串行 keep-alive：当前连接服务 MAX_PER_CONN 个请求后主动 close，让其他连接进来
# （无 per-conn 线程，规避 qemu-user 多线程 server 并发卡死；客户端断线重连）
fn serve_loop(arg: ptr) -> i64 {
    while 1 {
        let c: i64 = tcp_accept(LFD);
        if c < 0 { break; }
        CONN_FD[0] = c;
        CONN_LEN[0] = 0;
        SLOT_ARG[0] = 0;
        handle_slot(&SLOT_ARG);   # arg[0]=0 → slot 0
    }
    return 0;
}

fn CRCV2_get(cid: i64, p: i64) -> i64 {
    return CRCV[cid * 4096 + p];
}

fn read_resp(cid: i64, fd: i64) -> i64 {
    # 读响应头 + Content-Length body；返回 body 起始后的总字节数，失败 -1
    let n: i64 = 0;
    let m: i64 = 0;
    let hdr: i64 = 0 - 1;
    let cl: i64 = 0;
    let q: i64 = 0;
    let total: i64 = 0;
    let lp: i64 = 0;
    let z: i64 = 0;
    while n < 4000 {
        m = tcp_recv(fd, &CRCV + cid * 4096 + n, 4000 - n);
        if m <= 0 { break; }
        n = n + m;
        store8(&CRCV + cid * 4096 + n, 0);
        hdr = strstr(&CRCV + cid * 4096, "\r\n\r\n");
        if hdr >= 0 {
            q = hdr + 4;
            # 找 Content-Length
            lp = strstr(&CRCV + cid * 4096, "Content-Length: ");
            if lp >= 0 {
                z = lp + 16;
                while CRCV2_get(cid, z) != 13 {
                    cl = cl * 10 + CRCV2_get(cid, z) - 48;
                    z = z + 1;
                }
            }
            total = q + cl;
            while n < total {
                m = tcp_recv(fd, &CRCV + cid * 4096 + n, total - n);
                if m <= 0 { break; }
                n = n + m;
                store8(&CRCV + cid * 4096 + n, 0);
            }
            return total;
        }
    }
    return 0 - 1;
}

fn client_worker(arg: ptr) -> i64 {
    let cid: i64 = arg[0];
    let fd: i64 = 0;
    let i: i64 = 0;
    let bad: i64 = 0;
    let n: i64 = 0;
    let ji: i64 = 0;
    fd = 0 - 1;
    i = 0;
    while i < ROUNDS {
        # 连接失效则重连（server 每 MAX_PER_CONN 主动 close）
        if fd < 0 {
            fd = tcp_connect(2130706433, PORT);
            if fd < 0 { bad = bad + 1; continue; }
            sock_set_rcvtimeo(fd, 5);
        }
        # ---- POST /set（keep-alive 复用连接）----
        strcpy(&CKEY + cid * 256, "k");
        strcat_i64(&CKEY + cid * 256, i * 8 + cid);
        strcpy(&CVAL + cid * 256, "v");
        strcat_i64(&CVAL + cid * 256, i);
        strcpy(&CEXP + cid * 256, &CVAL + cid * 256);
        strcpy(&CBOD + cid * 1024, "{\"key\":\"");
        strcat(&CBOD + cid * 1024, &CKEY + cid * 256);
        strcat(&CBOD + cid * 1024, "\",\"value\":\"");
        strcat(&CBOD + cid * 1024, &CVAL + cid * 256);
        strcat(&CBOD + cid * 1024, "\"}");
        strcpy(&CSND + cid * 2048, "POST /set HTTP/1.1\r\nHost: kv\r\nContent-Length: ");
        strcat_i64(&CSND + cid * 2048, strlen(&CBOD + cid * 1024));
        strcat(&CSND + cid * 2048, "\r\n\r\n");
        strcat(&CSND + cid * 2048, &CBOD + cid * 1024);
        send_all(fd, &CSND + cid * 2048);
        n = read_resp(cid, fd);
        if n < 20 {
            # 连接被 server 主动关闭：重连重发一次
            tcp_close(fd);
            fd = tcp_connect(2130706433, PORT);
            if fd < 0 { bad = bad + 1; fd = 0 - 1; i = i + 1; continue; }
            sock_set_rcvtimeo(fd, 5);
            send_all(fd, &CSND + cid * 2048);
            n = read_resp(cid, fd);
        }
        if n < 20 { bad = bad + 1; }
        else {
            mutex_lock(&JMTX);
            ji = json_int(&CRCV + cid * 4096, "ok");
            mutex_unlock(&JMTX);
            if ji != 1 { bad = bad + 1; }
        }
        # ---- GET /get（同连接）----
        strcpy(&CSND + cid * 2048, "GET /get?key=");
        strcat(&CSND + cid * 2048, &CKEY + cid * 256);
        strcat(&CSND + cid * 2048, " HTTP/1.1\r\nHost: kv\r\n\r\n");
        send_all(fd, &CSND + cid * 2048);
        n = read_resp(cid, fd);
        if n < 20 {
            tcp_close(fd);
            fd = tcp_connect(2130706433, PORT);
            if fd < 0 { bad = bad + 1; fd = 0 - 1; i = i + 1; continue; }
            sock_set_rcvtimeo(fd, 5);
            send_all(fd, &CSND + cid * 2048);
            n = read_resp(cid, fd);
        }
        if n < 20 { bad = bad + 1; }
        else {
            mutex_lock(&JMTX);
            if json_str(&CRCV + cid * 4096, "value", &CVAL + cid * 256) == 0 { bad = bad + 1; }
            else {
                if strcmp(&CVAL + cid * 256, &CEXP + cid * 256) != 0 { bad = bad + 1; }
            }
            mutex_unlock(&JMTX);
        }
        i = i + 1;
    }
    if fd > 0 { tcp_close(fd); }
    CLIENT_BAD[cid] = bad;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    mutex_init(&JMTX);
    M = map_new();
    LFD = tcp_listen(PORT, 64);
    if LFD < 0 {
        print("listen fail\n");
        return 1;
    }
    thread_create(&TH + 15 * 8, &serve_loop, 0);
    usleep(200000);
    ROUNDS = 500;
    let t0: i64 = clock_ms();
    let i: i64 = 0;
    while i < 4 {
        CLIENT_BAD[i] = 0;
        CLIENT_ARG[i] = i;
        let trc: i64 = thread_create(&TH + i * 8, &client_worker, &CLIENT_ARG + i * 8);
        print("tc="); print_i64(trc); print_nl();
        i = i + 1;
    }
    i = 0;
    while i < 4 {
        thread_join(TH[i]);
        i = i + 1;
    }
    let ms: i64 = clock_ms() - t0;
    let total_bad: i64 = 0;
    i = 0;
    while i < 4 {
        total_bad = total_bad + CLIENT_BAD[i];
        i = i + 1;
    }
    print("clients=4 reqeach=500 bad=");
    print_i64(total_bad);
    print(" ms=");
    print_i64(ms);
    print_nl();
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
    print_nl();
    if total_bad > 0 { return 1; }
    return 0;
}
