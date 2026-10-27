# aiokv.mo —— aio + CSP HTTP/1.1 keep-alive KV server（每连接一协程）+ 对账 client
# value 直接作为 body（无 JSON 包裹），CL 精确，方便对账。
import "io.mo";
import "net.mo";
import "thread.mo";
import "csp.mo";
import "aio.mo";
import "lf.mo";

var PORT: i64 = 18910;
var ROUNDS: i64 = 500;
var NCLI: i64 = 2;
var LFD: i64 = 0;
var TH: [8] i64 = 0;
var CARG: [8] i64 = 0;
var CBAD: [8] i64 = 0;
var NCONN: i64 = 0;
var NREQ: i64 = 0;

# ---- KV 表（自旋锁）----
var KV_K: [16384] byte = 0;    # 256 × 64
var KV_V: [16384] byte = 0;    # 256 × 64
var KV_USED: [256] i64 = 0;
var KV_N: i64 = 0;
var KMTX: i64 = 0;

fn kv_lock() -> i64 {
    while lf_cas(0, &KMTX, 0, 1) != 1 { }
    return 0;
}

fn kv_unlock() -> i64 {
    store64(&KMTX, 0);
    return 0;
}

fn kv_find(k: i64) -> i64 {
    let i: i64 = 0;
    while i < 256 {
        if KV_USED[i] == 1 {
            if strcmp(&KV_K + i * 64, k) == 0 { return i; }
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn kv_set(k: i64, v: i64) -> i64 {
    kv_lock();
    let s: i64 = kv_find(k);
    if s < 0 {
        s = 0;
        while s < 256 {
            if KV_USED[s] == 0 { break; }
            s = s + 1;
        }
        if s == 256 { kv_unlock(); return 0 - 1; }
        KV_USED[s] = 1;
        KV_N = KV_N + 1;
        strcpy(&KV_K + s * 64, k);
    }
    strcpy(&KV_V + s * 64, v);
    kv_unlock();
    return 0;
}

fn kv_get(k: i64, out: i64) -> i64 {
    kv_lock();
    let s: i64 = kv_find(k);
    if s < 0 { kv_unlock(); return 0 - 1; }
    strcpy(out, &KV_V + s * 64);
    kv_unlock();
    return 0;
}

fn kv_del(k: i64) -> i64 {
    kv_lock();
    let s: i64 = kv_find(k);
    if s < 0 { kv_unlock(); return 0 - 1; }
    KV_USED[s] = 0;
    KV_N = KV_N - 1;
    kv_unlock();
    return 0;
}

# ---- HTTP 协程 ----
var CRB: [8192] byte = 0;
var CSB2: [8192] byte = 0;

fn http_conn(arg: i64) -> i64 {
    let fd: i64 = csp_arg();
    let sl: i64 = csp_self() & 7;
    let rb: i64 = &CRB + sl * 1024;
    let sb: i64 = &CSB2 + sl * 1024;
    let n: i64 = 0;
    let served: i64 = 0;
    let code: i64 = 200;
    let blen: i64 = 0;
    let vb: i64 = rb + 700;
    let have: i64 = 0;
    let want: i64 = 0;
    let bb: i64 = 0;
    while served < 510 {
        # 循环收齐：头（\r\n\r\n）+ 按 Content-Length 的 body
        have = 0;
        bb = 0 - 1;
        want = 0 - 1;
        while 1 {
            if have >= 900 { break; }
            n = aio_recv(fd, rb + have, 900 - have);
            if n <= 0 { break; }
            have = have + n;
            store8(rb + have, 0);
            if bb < 0 {
                bb = strstr(rb, "\r\n\r\n");
                if bb >= 0 {
                    # 找 Content-Length
                    let cp: i64 = strstr(rb, "Content-Length: ");
                    want = bb + 4;
                    if cp >= 0 && cp < bb { want = bb + 4 + atoi(rb + cp + 16); }
                }
            }
            if bb >= 0 && have >= want { break; }
        }
        if have <= 0 { break; }
        n = have;
        NREQ = NREQ + 1;
        served = served + 1;
        # path
        let pe: i64 = rb + 4;
        while load8(pe) != 32 && load8(pe) != 0 { pe = pe + 1; }
        store8(pe, 0);
        let path: i64 = rb + 4;
        code = 200;
        store8(vb, 0);
        blen = 0;
        if strstr(path, "/k/") == 0 {
            let key: i64 = path + 3;
            if strstr(rb, "PUT ") == 0 {
                if bb < 0 { code = 400; }
                else {
                    kv_set(key, rb + bb + 4);
                    strcpy(vb, "ok");
                    blen = 2;
                }
            } else {
                if strstr(rb, "DELETE ") == 0 {
                    if kv_del(key) != 0 { code = 404; }
                    else { strcpy(vb, "ok"); blen = 2; }
                } else {
                    if kv_get(key, vb) != 0 { code = 404; }
                    blen = strlen(vb);
                }
            }
        } else {
            if strstr(path, "/stats") == 0 {
                strcpy(vb, "keys=");
                strcat_i64(vb, KV_N);
                strcat(vb, " reqs=");
                strcat_i64(vb, NREQ);
                blen = strlen(vb);
            } else {
                code = 404;
            }
        }
        strcpy(sb, "HTTP/1.1 ");
        strcat_i64(sb, code);
        if code == 200 { strcat(sb, " OK"); } else { strcat(sb, " NF"); }
        strcat(sb, "\r\nContent-Length: ");
        strcat_i64(sb, blen);
        strcat(sb, "\r\nConnection: keep-alive\r\n\r\n");
        let hl: i64 = strlen(sb);
        if aio_send(fd, sb, hl) != hl { break; }
        if blen > 0 {
            if aio_send(fd, vb, blen) != blen { break; }
        }
    }
    aio_close(fd);
    return 0;
}

fn serve_loop(arg: i64) -> i64 {
    while 1 {
        let c: i64 = aio_accept(LFD);
        if c < 0 { break; }
        NCONN = NCONN + 1;
        csp_go(&http_conn, c);
    }
    return 0;
}

# ---- client ----
var CSB: [16384] byte = 0;
var CRP: [16384] byte = 0;

fn read_hdr(fd: i64, buf: i64) -> i64 {
    let m: i64 = 0;
    let r: i64 = 0;
    while m < 800 {
        r = tcp_recv(fd, buf + m, 1);
        if r <= 0 { return 0 - 1; }
        m = m + 1;
        if m >= 4 {
            if load8(buf + m - 4) == 13 && load8(buf + m - 3) == 10 && load8(buf + m - 2) == 13 && load8(buf + m - 1) == 10 { return m; }
        }
    }
    return 0 - 1;
}

fn read_n(fd: i64, buf: i64, n: i64) -> i64 {
    let m: i64 = 0;
    let r: i64 = 0;
    while m < n {
        r = tcp_recv(fd, buf + m, n - m);
        if r <= 0 { return 0 - 1; }
        m = m + r;
    }
    return m;
}

# 从头里取 Content-Length（在头缓冲尾 0 处调用）
fn get_cl(buf: i64, hlen: i64) -> i64 {
    store8(buf + hlen, 0);
    let p: i64 = strstr(buf, "Content-Length: ");
    if p < 0 { return 0 - 1; }
    return atoi(buf + p + 16);
}

fn client_kv(arg: ptr) -> i64 {
    let cid: i64 = arg[0];
    let bad: i64 = 0;
    let i: i64 = 0;
    let n: i64 = 0;
    let m: i64 = 0;
    let cl: i64 = 0;
    let fd: i64 = 0;
    let sb: i64 = &CSB + cid * 8192;
    let cpb: i64 = &CRP + cid * 8192;
    let kb: i64 = sb + 3000;
    let vr: i64 = cpb + 2000;
    fd = 0 - 1;
    i = 0;
    while i < ROUNDS {
        if fd < 0 {
            fd = tcp_connect(2130706433, PORT);
            if fd < 0 { bad = bad + 1; i = i + 1; continue; }
            sock_set_rcvtimeo(fd, 5);
        }
        # key = c<cid>i<i%7>（每 client 7 个键循环复用）
        strcpy(kb, "c");
        strcat_i64(kb, cid);
        strcat(kb, "i");
        strcat_i64(kb, i % 7);
        # PUT
        strcpy(sb, "PUT /k/");
        strcat(sb, kb);
        strcat(sb, " HTTP/1.1\r\nHost: x\r\nContent-Length: ");
        strcpy(sb + 400, "val");
        strcat_i64(sb + 400, cid * 100000 + i);
        strcat(sb, sb + 400);
        strcat(sb, "\r\n\r\n");
        strcat(sb, sb + 400);
        n = strlen(sb);
        if tcp_send(fd, sb, n) != n { tcp_close(fd); fd = 0 - 1; continue; }
        m = read_hdr(fd, cpb);
        if m < 0 { tcp_close(fd); fd = 0 - 1; continue; }
        cl = get_cl(cpb, m);
        if cl < 0 || cl != 2 { bad = bad + 1; i = i + 1; continue; }
        read_n(fd, vr, cl);
        # GET
        strcpy(sb, "GET /k/");
        strcat(sb, kb);
        strcat(sb, " HTTP/1.1\r\nHost: x\r\n\r\n");
        n = strlen(sb);
        if tcp_send(fd, sb, n) != n { tcp_close(fd); fd = 0 - 1; continue; }
        m = read_hdr(fd, cpb);
        if m < 0 { tcp_close(fd); fd = 0 - 1; continue; }
        cl = get_cl(cpb, m);
        if cl < 0 { bad = bad + 1; i = i + 1; continue; }
        if cl > 500 { cl = 500; }
        read_n(fd, vr, cl);
        store8(vr + cl, 0);
        # 对账：val<cid*100000+i>，与 sb+400 里的 vali 不同轮会变 —— 重构期望值
        strcpy(sb + 400, "val");
        strcat_i64(sb + 400, cid * 100000 + i);
        if strcmp(vr, sb + 400) != 0 { bad = bad + 1; }
        i = i + 1;
    }
    tcp_close(fd);
    CBAD[cid] = bad;
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    LFD = tcp_listen(PORT, 64);
    if LFD < 0 { print("listen fail\n"); return 1; }
    aio_nbio(LFD);
    if aio_init() != 0 { print("aio_init fail\n"); return 1; }
    csp_init(2);
    csp_go(&serve_loop, 0);
    usleep(200000);
    let i: i64 = 0;
    while i < NCLI {
        CARG[i] = i;
        thread_create(&TH + i * 8, &client_kv, &CARG + i * 8);
        i = i + 1;
    }
    i = 0;
    while i < NCLI {
        thread_join(TH[i]);
        i = i + 1;
    }
    usleep(300000);
    let total: i64 = 0;
    i = 0;
    while i < NCLI {
        total = total + CBAD[i];
        i = i + 1;
    }
    print("aiokv clients=2 rounds=");
    print_i64(ROUNDS);
    print(" bad=");
    print_i64(total);
    print(" conns=");
    print_i64(NCONN);
    print(" reqs=");
    print_i64(NREQ);
    print(" keys=");
    print_i64(KV_N);
    print_nl();
    print("woke=");
    print_i64(AIO_WOKE);
    print(" nev=");
    print_i64(AIO_NEV);
    print(" perr=");
    print_i64(AIO_PERR);
    print_nl();
    aio_stop();
    if total > 0 { return 1; }
    return 0;
}
