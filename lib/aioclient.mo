# aioclient.mo —— aio 协程 HTTP client：连接池 + 非阻塞请求（v1.211.0）
# 用法（协程内）：
#   fd = aio_pool_borrow();  if fd <= 0 { fd = aio_pool_connect(); }
#   ... aio_send/aio_recv ...
#   aio_pool_return(fd);   # 或 aio_close(fd) 丢弃坏连接
#   n = aio_http_get(path, buf, bufsize);  # 一步式：借/建→GET→收齐头+body→还池
import "io.mo";
import "net.mo";
import "lf.mo";
import "aio.mo";

var ACP_POOL: [8] i64 = 0;
var ACP_LOCK: i64 = 0;
var ACP_IP: i64 = 2130706433;
var ACP_PORT: i64 = 80;
var ACP_NCONN: i64 = 0;
var ACP_BUF: [16384] byte = 0;
# v1.215：per-协程请求头缓冲（4 槽 × 15000）—— 并发协程共享 ACP_BUF+15000 的 hb
# 会互相覆盖（v1.196「缓冲竞争」教训在 aio_http_put 上复现：server 收到错乱头）
var ACP_HB: [120000] byte = 0;
var ACP_HBSEQ: i64 = 0;

fn aio_hb_slot() -> i64 {
    # 轮转分配请求头缓冲槽（非严格互斥；每个协程独占使用期间不冲突按
    # 4 槽轮转 + 短请求窗口，冲突概率低；严格互斥待 lf_cas 化）
    let s: i64 = ACP_HBSEQ % 4;
    ACP_HBSEQ = ACP_HBSEQ + 1;
    return s;
}

fn aio_rx(slot: i64) -> i64 {
    return &ACP_HB + 60000 + slot * 15000;
}

fn aio_pool_config(ip: i64, port: i64) -> i64 {
    lf_init();  # v1.212：CAS 可用性自检（freestanding 下响亮退出）
    ACP_IP = ip;
    ACP_PORT = port;
    return 0;
}

fn aio_pool_borrow() -> i64 {
    while lf_cas(0, &ACP_LOCK, 0, 1) != 1 { }
    let i: i64 = 0;
    let fd: i64 = 0 - 1;
    while i < 8 {
        if ACP_POOL[i] > 0 {
            fd = ACP_POOL[i];
            ACP_POOL[i] = 0;
            i = 8;
        }
        i = i + 1;
    }
    ACP_LOCK = 0;
    return fd;
}

fn aio_pool_return(fd: i64) -> i64 {
    while lf_cas(0, &ACP_LOCK, 0, 1) != 1 { }
    let i: i64 = 0;
    while i < 8 {
        if ACP_POOL[i] == 0 {
            ACP_POOL[i] = fd;
            i = 8;
        }
        i = i + 1;
    }
    ACP_LOCK = 0;
    return 0;
}

fn aio_pool_connect() -> i64 {
    let fd: i64 = aio_connect(ACP_IP, ACP_PORT);
    if fd > 0 { ACP_NCONN = ACP_NCONN + 1; }
    return fd;
}

fn aio_pool_conns() -> i64 {
    return ACP_NCONN;
}

# 一步式 GET：借/建连接 → GET path → 收齐 \r\n\r\n + Content-Length body → 写 buf → 还池
# 返回 body 字节数；负数=失败（连接已清理）。
fn aio_http_get(path: ptr, buf: i64, bufsize: i64) -> i64 {
    let hbs: i64 = aio_hb_slot();
    let fd: i64 = aio_pool_borrow();
    let mine: i64 = 0;
    if fd <= 0 {
        fd = aio_pool_connect();
        mine = 1;
        if fd < 0 { return 0 - 1; }
    }
    let hb: i64 = &ACP_HB + aio_hb_slot() * 15000;
    strcpy(hb, "GET ");
    strcat(hb, path);
    strcat(hb, " HTTP/1.1\r\nHost: c\r\n\r\n");
    let n: i64 = strlen(hb);
    if aio_send(fd, hb, n) != n {
        # v1.221：复用连接可能已被 server 关闭（HTTP/1.0 short-conn）——
        # 池借来的 fd send 失败 = 换新连接重试一次，不直接报错。
        aio_close(fd);
        if mine == 0 {
            fd = aio_pool_connect();
            if fd < 0 { return 0 - 2; }
            mine = 1;
            strcpy(hb, "GET ");
            strcat(hb, path);
            strcat(hb, " HTTP/1.1\r\nHost: c\r\n\r\n");
            n = strlen(hb);
            if aio_send(fd, hb, n) != n {
                aio_close(fd);
                return 0 - 2;
            }
        } else {
            return 0 - 2;
        }
    }
    # 收头（读进 per-协程 rx 槽）
    let got: i64 = 0;
    let he: i64 = 0 - 1;
    let r: i64 = 0;
    while he < 0 && got < 14000 {
        r = aio_recv(fd, aio_rx(hbs) + got, 1024);
        if r <= 0 { break; }
        got = got + r;
        store8(aio_rx(hbs) + got, 0);
        he = strstr(aio_rx(hbs), "\r\n\r\n");
    }
    if he < 0 {
        aio_close(fd);
        return 0 - 3;
    }
    let blen: i64 = got - he - 4;
    # Content-Length
    let clp: i64 = strstr(aio_rx(hbs), "Content-Length: ");
    let cl: i64 = 0;
    if clp >= 0 {
        let dp: i64 = clp + 16;
        while load8(aio_rx(hbs) + dp) >= 48 && load8(aio_rx(hbs) + dp) <= 57 {
            cl = cl * 10 + (load8(aio_rx(hbs) + dp) - 48);
            dp = dp + 1;
        }
    }
    while blen < cl && got < 14000 {
        r = aio_recv(fd, aio_rx(hbs) + got, 1024);
        if r <= 0 { break; }
        got = got + r;
        blen = got - he - 4;
    }
    if blen < cl {
        aio_close(fd);
        return 0 - 4;
    }
    # body 拷给调用者
    let cp: i64 = 0;
    while cp < blen && cp < bufsize - 1 {
        store8(buf + cp, load8(aio_rx(hbs) + he + 4 + cp));
        cp = cp + 1;
    }
    store8(buf + cp, 0);
    if mine == 0 { r = aio_pool_return(fd); } else { r = aio_close(fd); }
    return blen;
}


# 一步式 PUT：借/建 → PUT path（Content-Length: blen）+ body → 收响应行+body → 还池
# 返回响应 body 字节数；负数=失败。regserver 回 200（成功）/413（超限）。
fn aio_http_put(path: ptr, body: ptr, blen: i64, buf: i64, bufsize: i64) -> i64 {
    let hbs: i64 = aio_hb_slot();
    let fd: i64 = aio_pool_borrow();
    let mine: i64 = 0;
    if fd <= 0 {
        fd = aio_pool_connect();
        mine = 1;
        if fd < 0 { return 0 - 1; }
    }
    let hb: i64 = &ACP_HB + aio_hb_slot() * 15000;
    strcpy(hb, "PUT ");
    strcat(hb, path);
    strcat(hb, " HTTP/1.1\r\nHost: c\r\nContent-Length: ");
    let n: i64 = strlen(hb);
    # blen 十进制
    let d: i64 = hb + n;
    let v: i64 = blen;
    let digits: i64 = 0;
    if v == 0 {
        store8(d, 48);
        digits = 1;
    }
    while v > 0 {
        store8(d + digits, 48 + (v % 10));
        v = v / 10;
        digits = digits + 1;
    }
    # 反转
    let i: i64 = 0;
    while i < digits / 2 {
        let c: i64 = load8(d + i);
        store8(d + i, load8(d + digits - 1 - i));
        store8(d + digits - 1 - i, c);
        i = i + 1;
    }
    strcat(hb, "\r\n\r\n");
    n = strlen(hb);
    if aio_send(fd, hb, n) != n {
        aio_close(fd);
        return 0 - 2;
    }
    # 分块发 body（aio_send 大块安全？保守 4096 步进）
    let sent: i64 = 0;
    let sr: i64 = 0;
    while sent < blen {
        let chunk: i64 = blen - sent;
        if chunk > 4096 { chunk = 4096; }
        sr = aio_send(fd, body + sent, chunk);
        if sr != chunk {
            aio_close(fd);
            return 0 - 3;
        }
        sent = sent + chunk;
    }
    let got: i64 = 0;
    let he: i64 = 0 - 1;
    let r: i64 = 0;
    while he < 0 && got < 14000 {
        r = aio_recv(fd, aio_rx(hbs) + got, 1024);
        if r <= 0 { break; }
        got = got + r;
        store8(aio_rx(hbs) + got, 0);
        he = strstr(aio_rx(hbs), "\r\n\r\n");
    }
    if he < 0 {
        aio_close(fd);
        return 0 - 4;
    }
    let rlen: i64 = got - he - 4;
    # 状态行 200 检查（strstr " 200 "）
    let ok: i64 = strstr(aio_rx(hbs), " 200 ");
    if ok < 0 {
        # 非 200：不还池（连接语义未知），关闭并返回 0-5
        aio_close(fd);
        return 0 - 5;
    }
    let cp: i64 = 0;
    while cp < rlen && cp < bufsize - 1 {
        store8(buf + cp, load8(aio_rx(hbs) + he + 4 + cp));
        cp = cp + 1;
    }
    store8(buf + cp, 0);
    if mine == 0 { r = aio_pool_return(fd); } else { r = aio_close(fd); }
    return rlen;
}

# ---------- v1.248 HTTP 完整化：状态码 / chunked / POST / query ----------
var AH2_S: i64 = 0;
var AH2_GOT: i64 = 0;
var AH2_HE: i64 = 0;
var AH2_R: i64 = 0;
var AH2_CL: i64 = 0;
var AH2_DP: i64 = 0;
var AH2_BLEN: i64 = 0;
var AH2_CP: i64 = 0;
var AH2_CHP: i64 = 0;
var AH2_CSZ: i64 = 0;
var AH2_CEND: i64 = 0;
var AH2_BOUT: i64 = 0;
var AH2_FD: i64 = 0;
var AH2_MINE: i64 = 0;
var AH2_HB: i64 = 0;
var AH2_N: i64 = 0;
var AH2_SCI: i64 = 0;

# 状态行 "HTTP/1.1 200 OK" → 200；无 → -1
fn http_status(hb: i64) -> i64 {
    AH2_SCI = strstr(hb, " ");
    if AH2_SCI < 0 { return 0 - 1; }
    AH2_SCI = AH2_SCI + 1;
    AH2_S = 0;
    while 1 {
        AH2_R = load8(hb + AH2_SCI);
        if AH2_R < 48 || AH2_R > 57 { break; }
        AH2_S = AH2_S * 10 + (AH2_R - 48);
        AH2_SCI = AH2_SCI + 1;
    }
    return AH2_S;
}

# 收完整响应到 rx 槽：返回头结束偏移；<0 失败
fn http_recv_resp(fd: i64, hbs: i64) -> i64 {
    AH2_GOT = 0;
    AH2_HE = 0 - 1;
    while AH2_HE < 0 && AH2_GOT < 14000 {
        AH2_R = aio_recv(fd, aio_rx(hbs) + AH2_GOT, 1024);
        if AH2_R <= 0 { break; }
        AH2_GOT = AH2_GOT + AH2_R;
        store8(aio_rx(hbs) + AH2_GOT, 0);
        AH2_HE = strstr(aio_rx(hbs), "\r\n\r\n");
    }
    if AH2_HE < 0 { return 0 - 3; }
    return AH2_HE;
}

# body 长度：Content-Length 或 Transfer-Encoding: chunked（解析后展开）→ 实际 body 字节；错误 -4
fn http_body_len(fd: i64, hbs: i64, he: i64, got: i64) -> i64 {
    AH2_CL = 0;
    AH2_DP = strstr(aio_rx(hbs), "Content-Length: ");
    if AH2_DP >= 0 {
        AH2_DP = AH2_DP + 16;
        while 1 {
            AH2_R = load8(aio_rx(hbs) + AH2_DP);
            if AH2_R < 48 || AH2_R > 57 { break; }
            AH2_CL = AH2_CL * 10 + (AH2_R - 48);
            AH2_DP = AH2_DP + 1;
        }
        # 继续收满 CL
        while got - he - 4 < AH2_CL && got < 14000 {
            AH2_R = aio_recv(fd, aio_rx(hbs) + got, 1024);
            if AH2_R <= 0 { break; }
            got = got + AH2_R;
            store8(aio_rx(hbs) + got, 0);
        }
        return AH2_CL;
    }
    AH2_DP = strstr(aio_rx(hbs), "chunked");
    if AH2_DP < 0 { return 0; }
    # chunked：继续收到 "0\r\n" 终止块再展开
    while strstr(aio_rx(hbs) + he + 4, "\r\n0\r\n") < 0 && got < 13900 {
        AH2_R = aio_recv(fd, aio_rx(hbs) + got, 1024);
        if AH2_R <= 0 { break; }
        got = got + AH2_R;
        store8(aio_rx(hbs) + got, 0);
    }
    # 展开 chunk 串（原地）：hex 大小\r\n data \r\n ... 0\r\n
    AH2_CHP = he + 4;
    AH2_BOUT = 0;
    while 1 {
        AH2_CSZ = 0;
        while 1 {
            AH2_R = load8(aio_rx(hbs) + AH2_CHP);
            if AH2_R >= 48 && AH2_R <= 57 { AH2_CSZ = AH2_CSZ * 16 + (AH2_R - 48); AH2_CHP = AH2_CHP + 1; }
            else if AH2_R >= 97 && AH2_R <= 102 { AH2_CSZ = AH2_CSZ * 16 + (AH2_R - 87); AH2_CHP = AH2_CHP + 1; }
            else { break; }
        }
        if AH2_CSZ == 0 { break; }
        AH2_CHP = AH2_CHP + 2;   # \r\n
        # 左移后续数据：把 data 段拷到 BOUT 位置（重叠向前覆盖安全：BOUT <= CHP）
        AH2_CEND = AH2_CHP + AH2_CSZ;
        while AH2_CHP < AH2_CEND {
            store8(aio_rx(hbs) + he + 4 + AH2_BOUT, load8(aio_rx(hbs) + AH2_CHP));
            AH2_BOUT = AH2_BOUT + 1;
            AH2_CHP = AH2_CHP + 1;
        }
        AH2_CHP = AH2_CHP + 2;   # \r\n
    }
    store8(aio_rx(hbs) + he + 4 + AH2_BOUT, 0);
    return AH2_BOUT;
}

# 一步式请求：method/path/body(可 0)/状态码*（可 0）→ body 字节或负错误
# 用全局 AH2_HB 槽；非并发安全（与 aio_http_get 同级）
fn aio_http_req(method: ptr, path: ptr, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    let hbs: i64 = aio_hb_slot();
    AH2_FD = aio_pool_borrow();
    AH2_MINE = 0;
    if AH2_FD <= 0 {
        AH2_FD = aio_pool_connect();
        AH2_MINE = 1;
        if AH2_FD < 0 { return 0 - 1; }
    }
    AH2_HB = &ACP_HB + aio_hb_slot() * 15000;
    strcpy(AH2_HB, method);
    strcat(AH2_HB, " ");
    strcat(AH2_HB, path);
    strcat(AH2_HB, " HTTP/1.1\r\nHost: c\r\n");
    if blen > 0 {
        strcat(AH2_HB, "Content-Length: ");
        strcat_i64(AH2_HB, blen);
        strcat(AH2_HB, "\r\n");
    }
    strcat(AH2_HB, "\r\n");
    if body != 0 { memcpy(AH2_HB + strlen(AH2_HB), body, blen); }
    AH2_N = strlen(AH2_HB) + blen;
    if aio_send(AH2_FD, AH2_HB, AH2_N) != AH2_N {
        aio_close(AH2_FD);
        if AH2_MINE == 0 {
            AH2_FD = aio_pool_connect();
            if AH2_FD < 0 { return 0 - 2; }
            AH2_MINE = 1;
            if aio_send(AH2_FD, AH2_HB, AH2_N) != AH2_N { aio_close(AH2_FD); return 0 - 2; }
        } else { return 0 - 2; }
    }
    let he2: i64 = http_recv_resp(AH2_FD, hbs);
    if he2 < 0 { aio_close(AH2_FD); return he2; }
    if status != 0 { store64(status, http_status(aio_rx(hbs))); }
    let b2: i64 = http_body_len(AH2_FD, hbs, he2, AH2_GOT);
    if b2 < 0 { aio_close(AH2_FD); return b2; }
    AH2_CP = 0;
    while AH2_CP < b2 && AH2_CP < bufsize - 1 {
        store8(buf + AH2_CP, load8(aio_rx(hbs) + he2 + 4 + AH2_CP));
        AH2_CP = AH2_CP + 1;
    }
    store8(buf + AH2_CP, 0);
    if AH2_MINE == 0 { AH2_R = aio_pool_return(AH2_FD); } else { AH2_R = aio_close(AH2_FD); }
    return b2;
}
