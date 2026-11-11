import "net.mo";
import "str.mo";
import "archive.mo";
import "io.mo";
# 同步 HTTP 客户端（阻塞 tcp，无 aio 依赖）——v1.248

var HC_REQ: [65536] byte = 0;
var HC_HN: [128] byte = 0;
var HC_RB: [32768] byte = 0;
var HC_GOT: i64 = 0;
var HC_HE: i64 = 0;
var HC_R: i64 = 0;
var HC_CL: i64 = 0;
var HC_DP: i64 = 0;
var HC_BLEN: i64 = 0;
var HC_CHP: i64 = 0;
var HC_CSZ: i64 = 0;
var HC_CEND: i64 = 0;
var HC_BOUT: i64 = 0;
var HC_CP: i64 = 0;
var HC_IP: i64 = 0;
var HC_SCI: i64 = 0;

fn http_status(hb: i64) -> i64 {
    HC_SCI = strstr(hb, " ");
    if HC_SCI < 0 { return 0 - 1; }
    HC_SCI = HC_SCI + 1;
    HC_CL = 0;
    while 1 {
        HC_R = load8(hb + HC_SCI);
        if HC_R < 48 || HC_R > 57 { break; }
        HC_CL = HC_CL * 10 + (HC_R - 48);
        HC_SCI = HC_SCI + 1;
    }
    return HC_CL;
}

# method path host body(可 0) blen buf bufsize status(可 0) → body 字节;<0 错
fn tcp_http_req(method: ptr, path: ptr, host: ptr, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    return tcp_http_req_port(method, path, host, 80, body, blen, buf, bufsize, status);
}

fn tcp_http_req_port(method: ptr, path: ptr, host: ptr, port: i64, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    let fd: i64 = tcp_connect(HC_IP, port);
    if fd < 0 { return 0 - 2; }
    strcpy(&HC_REQ, method);
    strcat(&HC_REQ, " ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nAccept-Encoding: gzip\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: close\r\n");
    if blen > 0 {
        strcat(&HC_REQ, "Content-Length: ");
        strcat_i64(&HC_REQ, blen);
        strcat(&HC_REQ, "\r\n");
    }
    strcat(&HC_REQ, "\r\n");
    let hl: i64 = strlen(&HC_REQ);
    if body != 0 { memcpy(&HC_REQ + hl, body, blen); }
    let n: i64 = hl + blen;
    if tcp_send(fd, &HC_REQ, n) != n { tcp_close(fd); return 0 - 2; }
    HC_GOT = 0;
    HC_HE = 0 - 1;
    while HC_HE < 0 && HC_GOT < 31000 {
        HC_R = tcp_recv(fd, &HC_RB + HC_GOT, 4096);
        if HC_R <= 0 { break; }
        HC_GOT = HC_GOT + HC_R;
        store8(&HC_RB + HC_GOT, 0);
        HC_HE = strstr(&HC_RB, "\r\n\r\n");
    }
    if HC_HE < 0 { tcp_close(fd); return 0 - 3; }
    if status != 0 { store64(status, http_status(&HC_RB)); }
    HC_CL = 0;
    HC_DP = strstr(&HC_RB, "Content-Length: ");
    if HC_DP >= 0 {
        HC_DP = HC_DP + 16;
        while 1 {
            HC_R = load8(&HC_RB + HC_DP);
            if HC_R < 48 || HC_R > 57 { break; }
            HC_CL = HC_CL * 10 + (HC_R - 48);
            HC_DP = HC_DP + 1;
        }
        while HC_GOT - HC_HE - 4 < HC_CL && HC_GOT < 31000 {
            HC_R = tcp_recv(fd, &HC_RB + HC_GOT, 4096);
            if HC_R <= 0 { break; }
            HC_GOT = HC_GOT + HC_R;
            store8(&HC_RB + HC_GOT, 0);
        }
        HC_BLEN = HC_CL;
    } else {
        HC_DP = strstr(&HC_RB, "chunked");
        if HC_DP < 0 {
            HC_BLEN = HC_GOT - HC_HE - 4;
        } else {
            while strstr(&HC_RB + HC_HE + 4, "\r\n0\r\n") < 0 && HC_GOT < 30500 {
                HC_R = tcp_recv(fd, &HC_RB + HC_GOT, 4096);
                if HC_R <= 0 { break; }
                HC_GOT = HC_GOT + HC_R;
                store8(&HC_RB + HC_GOT, 0);
            }
            HC_CHP = HC_HE + 4;
            HC_BOUT = 0;
            while 1 {
                HC_CSZ = 0;
                while 1 {
                    HC_R = load8(&HC_RB + HC_CHP);
                    if HC_R >= 48 && HC_R <= 57 { HC_CSZ = HC_CSZ * 16 + (HC_R - 48); HC_CHP = HC_CHP + 1; }
                    else if HC_R >= 97 && HC_R <= 102 { HC_CSZ = HC_CSZ * 16 + (HC_R - 87); HC_CHP = HC_CHP + 1; }
                    else { break; }
                }
                if HC_CSZ == 0 { break; }
                HC_CHP = HC_CHP + 2;
                HC_CEND = HC_CHP + HC_CSZ;
                while HC_CHP < HC_CEND {
                    store8(&HC_RB + HC_HE + 4 + HC_BOUT, load8(&HC_RB + HC_CHP));
                    HC_BOUT = HC_BOUT + 1;
                    HC_CHP = HC_CHP + 1;
                }
                HC_CHP = HC_CHP + 2;
            }
            store8(&HC_RB + HC_HE + 4 + HC_BOUT, 0);
            HC_BLEN = HC_BOUT;
        }
    }
    # gzip 响应 → 临时文件 gunzip
    HC_DP = strstr(&HC_RB, "Content-Encoding: gzip");
    if HC_DP >= 0 && HC_DP < HC_HE {
        let wfd: i64 = fopen("/tmp/hc_gz_in.gz", 577, 438);
        if wfd >= 0 {
            fwrite(wfd, &HC_RB + HC_HE + 4, HC_BLEN);
            fclose(wfd);
        }
        let gr: i64 = gunzip_file("/tmp/hc_gz_in.gz", "/tmp/hc_gz_out.bin");
        if gr >= 0 {
            let rfd: i64 = fopen("/tmp/hc_gz_out.bin", 0, 0);
            if rfd >= 0 {
                HC_BLEN = fread(rfd, buf, bufsize - 1);
                fclose(rfd);
                store8(buf + HC_BLEN, 0);
                tcp_close(fd);
                return HC_BLEN;
            }
        }
    }
    HC_CP = 0;
    while HC_CP < HC_BLEN && HC_CP < bufsize - 1 {
        store8(buf + HC_CP, load8(&HC_RB + HC_HE + 4 + HC_CP));
        HC_CP = HC_CP + 1;
    }
    store8(buf + HC_CP, 0);
    tcp_close(fd);
    return HC_BLEN;
}

# ---------- v1.253 keep-alive 连接池 ----------
var HCK_FD: [4] i64 = 0;
var HCK_IP: [4] i64 = 0;
var HCK_PORT: [4] i64 = 0;
var HCK_LAST: [4] i64 = 0;
var HCK_TV: [16] byte = 0;
var HCK_N: i64 = 0;
var HCK_RC: i64 = 0;

# 带 keep-alive 的请求：同 host:port 复用连接；失败重连一次
fn tcp_http_ka(method: ptr, path: ptr, host: ptr, port: i64, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    # v1.270:4 槽连接池——找同 host:port 槽,无则换掉 LRU 槽
    let ki: i64 = 0 - 1;
    let ki0: i64 = 0;
    let kk: i64 = 0;
    while kk < 4 {
        if HCK_FD[kk] > 0 && HCK_IP[kk] == HC_IP && HCK_PORT[kk] == port { ki = kk; }
        if HCK_FD[kk] <= 0 && ki < 0 { ki0 = kk; ki = ki0; }
        kk = kk + 1;
    }
    # v1.283:命中已有槽时,若空闲超 30s 则回收重连
    if ki >= 0 && HCK_FD[ki] > 0 {
        syscall(96, &HCK_TV, 0, 0, 0, 0, 0);
        let now: i64 = load64(&HCK_TV);
        if now - HCK_LAST[ki] > 30 {
            tcp_close(HCK_FD[ki]);
            HCK_FD[ki] = 0;
        }
    }
    if ki < 0 {
        # 全占:换槽 0(简单策略)
        ki = 0;
        if HCK_FD[0] > 0 { tcp_close(HCK_FD[0]); HCK_FD[0] = 0; }
    } else if HCK_FD[ki] <= 0 {
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        # v1.294:读超时 10s,防服务端不发数据挂死
        sock_set_rcvtimeo(HCK_FD[ki], 10);
        HCK_IP[ki] = HC_IP; HCK_PORT[ki] = port;
        syscall(96, &HCK_TV, 0, 0, 0, 0, 0);
        HCK_LAST[ki] = load64(&HCK_TV);
    }
    strcpy(&HC_REQ, method);
    strcat(&HC_REQ, " ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nAccept-Encoding: gzip\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: keep-alive\r\n");
    if blen > 0 {
        strcat(&HC_REQ, "Content-Length: ");
        strcat_i64(&HC_REQ, blen);
        strcat(&HC_REQ, "\r\n");
    }
    strcat(&HC_REQ, "\r\n");
    let hl: i64 = strlen(&HC_REQ);
    if body != 0 { memcpy(&HC_REQ + hl, body, blen); }
    HCK_N = hl + blen;
    if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        sock_set_rcvtimeo(HCK_FD[ki], 10);
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
    }
    HCK_RC = 0;
    if strcmp(method, "HEAD") == 0 {
        # HEAD:只读头,不读 body,响应后连接仍可复用
        HCK_RC = tcp_http_ka_head(ki, status);
        return HCK_RC;
    }
    HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    # v1.273:断线重连上限 3 次
    let tries: i64 = 0;
    while HCK_RC == 0 - 9 && tries < 3 {
        tries = tries + 1;
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
        HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    }
    return HCK_RC;
}

# v1.262:ka + 自定义头(If-None-Match 等条件请求;extra_hdr 形如 "If-None-Match: W/\"abc\"\r\n",可空)
fn tcp_http_ka_hdr(method: ptr, path: ptr, host: ptr, port: i64, extra: ptr, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    # v1.270:4 槽池(与 tcp_http_ka 同策略)
    let ki: i64 = 0 - 1;
    let kk: i64 = 0;
    let ki0: i64 = 0;
    while kk < 4 {
        if HCK_FD[kk] > 0 && HCK_IP[kk] == HC_IP && HCK_PORT[kk] == port { ki = kk; }
        if HCK_FD[kk] <= 0 && ki < 0 { ki0 = kk; ki = ki0; }
        kk = kk + 1;
    }
    if ki < 0 {
        ki = 0;
        if HCK_FD[0] > 0 { tcp_close(HCK_FD[0]); HCK_FD[0] = 0; }
    } else if HCK_FD[ki] <= 0 {
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        HCK_IP[ki] = HC_IP; HCK_PORT[ki] = port;
    }
    strcpy(&HC_REQ, method);
    strcat(&HC_REQ, " ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nAccept-Encoding: gzip\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: keep-alive\r\n");
    if extra != 0 {
        if strlen(extra) > 0 { strcat(&HC_REQ, extra); }
    }
    if blen > 0 {
        strcat(&HC_REQ, "Content-Length: ");
        strcat_i64(&HC_REQ, blen);
        strcat(&HC_REQ, "\r\n");
    }
    strcat(&HC_REQ, "\r\n");
    let hl: i64 = strlen(&HC_REQ);
    if body != 0 { memcpy(&HC_REQ + hl, body, blen); }
    HCK_N = hl + blen;
    if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
    }
    if strcmp(method, "HEAD") == 0 {
        return tcp_http_ka_head(ki, status);
    }
    HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    if HCK_RC == 0 - 9 {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
        HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    }
    return HCK_RC;
}

# 读响应（keep-alive：按 CL 精确收,连接保留）
fn tcp_http_ka_read(ki: i64, port: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    HC_GOT = 0;
    HC_HE = 0 - 1;
    while HC_HE < 0 && HC_GOT < 31000 {
        HC_R = tcp_recv(HCK_FD[ki], &HC_RB + HC_GOT, 4096);
        if HC_R <= 0 { return 0 - 9; }   # 连接被关
        HC_GOT = HC_GOT + HC_R;
        store8(&HC_RB + HC_GOT, 0);
        HC_HE = strstr(&HC_RB, "\r\n\r\n");
    }
    if HC_HE < 0 { return 0 - 3; }
    if status != 0 { store64(status, http_status(&HC_RB)); }
    HC_CL = 0;
    HC_DP = strstr(&HC_RB, "Content-Length: ");
    if HC_DP >= 0 {
        HC_DP = HC_DP + 16;
        while 1 {
            HC_R = load8(&HC_RB + HC_DP);
            if HC_R < 48 || HC_R > 57 { break; }
            HC_CL = HC_CL * 10 + (HC_R - 48);
            HC_DP = HC_DP + 1;
        }
        while HC_GOT - HC_HE - 4 < HC_CL && HC_GOT < 31000 {
            HC_R = tcp_recv(HCK_FD[ki], &HC_RB + HC_GOT, 4096);
            if HC_R <= 0 { return 0 - 9; }
            HC_GOT = HC_GOT + HC_R;
            store8(&HC_RB + HC_GOT, 0);
        }
        HC_BLEN = HC_CL;
    } else {
        HC_BLEN = HC_GOT - HC_HE - 4;   # ka 模式不用 chunked
    }
    # gzip
    HC_DP = strstr(&HC_RB, "Content-Encoding: gzip");
    if HC_DP >= 0 && HC_DP < HC_HE {
        let wfd: i64 = fopen("/tmp/hck_gz.gz", 577, 438);
        if wfd >= 0 { fwrite(wfd, &HC_RB + HC_HE + 4, HC_BLEN); fclose(wfd); }
        let gr: i64 = gunzip_file("/tmp/hck_gz.gz", "/tmp/hck_gz.bin");
        if gr >= 0 {
            let rfd: i64 = fopen("/tmp/hck_gz.bin", 0, 0);
            if rfd >= 0 {
                HC_BLEN = fread(rfd, buf, bufsize - 1);
                fclose(rfd);
                store8(buf + HC_BLEN, 0);
                return HC_BLEN;
            }
        }
    }
    HC_CP = 0;
    while HC_CP < HC_BLEN && HC_CP < bufsize - 1 {
        store8(buf + HC_CP, load8(&HC_RB + HC_HE + 4 + HC_CP));
        HC_CP = HC_CP + 1;
    }
    store8(buf + HC_CP, 0);
    return HC_BLEN;
}

# HEAD 响应:收头即止
fn tcp_http_ka_head(ki: i64, status: ptr) -> i64 {
    HC_GOT = 0;
    HC_HE = 0 - 1;
    while HC_HE < 0 && HC_GOT < 31000 {
        HC_R = tcp_recv(HCK_FD[ki], &HC_RB + HC_GOT, 4096);
        if HC_R <= 0 { return 0 - 9; }
        HC_GOT = HC_GOT + HC_R;
        store8(&HC_RB + HC_GOT, 0);
        HC_HE = strstr(&HC_RB, "\r\n\r\n");
    }
    if HC_HE < 0 { return 0 - 3; }
    if status != 0 { store64(status, http_status(&HC_RB)); }
    return 0;
}

fn tcp_http_ka_close() -> i64 {
    let kk: i64 = 0;
    while kk < 4 {
        if HCK_FD[kk] > 0 { tcp_close(HCK_FD[kk]); HCK_FD[kk] = 0; }
        kk = kk + 1;
    }
    return 0;
}

# ---------- v1.254 POST gzip 上传 + ETag 条件请求 ----------
# gzip POST:body>32 → gzip_write 压缩后发送(Content-Encoding: gzip)
var HCG_FD: i64 = 0;
var HCG_N: i64 = 0;

# v1.261:从原始响应取任意头(名不区分大小写不做,精确匹配 "Name: ")
fn http_resp_header(raw: ptr, name: ptr, out: ptr) -> i64 {
    strcpy(out, "");
    strcpy(&HC_HN, name);
    strcat(&HC_HN, ": ");
    let p: i64 = strstr(raw, &HC_HN);
    if p < 0 { return 0 - 1; }
    strcpy(out, raw + p + strlen(&HC_HN));
    let e: i64 = strstr(out, "\r");
    if e < 0 { e = strstr(out, "\n"); }
    if e >= 0 { store8(out + e, 0); }
    return strlen(out);
}

# v1.260:原始响应(含状态行+头)——ETag/Location 等头级检查用
fn tcp_http_req_raw(method: ptr, path: ptr, host: ptr, port: i64, body: ptr, blen: i64, out: ptr, bufsize: i64, status: ptr) -> i64 {
    let hlen: i64 = 0;
    let got: i64 = 0;
    let r: i64 = 0;
    let he: i64 = 0 - 1;
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    strcpy(&HC_REQ, method);
    strcat(&HC_REQ, " ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nAccept-Encoding: gzip\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: close\r\n");
    if blen > 0 {
        strcat(&HC_REQ, "Content-Length: ");
        strcat_i64(&HC_REQ, blen);
        strcat(&HC_REQ, "\r\n");
    }
    strcat(&HC_REQ, "\r\n");
    hlen = strlen(&HC_REQ);
    if body != 0 { memcpy(&HC_REQ + hlen, body, blen); }
    let fd: i64 = tcp_connect(HC_IP, port);
    if fd < 0 { return 0 - 2; }
    if tcp_send(fd, &HC_REQ, hlen + blen) != hlen + blen { tcp_close(fd); return 0 - 2; }
    HC_GOT = 0;
    while he < 0 && HC_GOT < 31000 {
        r = tcp_recv(fd, &HC_RB + HC_GOT, 4096);
        if r <= 0 { break; }
        HC_GOT = HC_GOT + r;
        store8(&HC_RB + HC_GOT, 0);
        he = strstr(&HC_RB, "\r\n\r\n");
    }
    if he < 0 { tcp_close(fd); return 0 - 3; }
    # 按 Content-Length 收 body(或无 CL 收到连接关)
    let cl: i64 = 0 - 1;
    let dp: i64 = strstr(&HC_RB, "Content-Length: ");
    if dp >= 0 {
        dp = dp + 16;
        while 1 {
            r = load8(&HC_RB + dp);
            if r < 48 || r > 57 { break; }
            cl = cl * 10 + (r - 48);
            dp = dp + 1;
        }
    }
    if cl >= 0 {
        while HC_GOT - he - 4 < cl && HC_GOT < 31000 {
            r = tcp_recv(fd, &HC_RB + HC_GOT, 4096);
            if r <= 0 { break; }
            HC_GOT = HC_GOT + r;
            store8(&HC_RB + HC_GOT, 0);
        }
    }
    if status != 0 { store64(status, http_status(&HC_RB)); }
    tcp_close(fd);
    let cp: i64 = 0;
    while cp < HC_GOT && cp < bufsize - 1 {
        store8(out + cp, load8(&HC_RB + cp));
        cp = cp + 1;
    }
    store8(out + cp, 0);
    return cp;
}

fn tcp_http_post_gzip(path: ptr, host: ptr, port: i64, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr) -> i64 {
    if blen > 32 {
        HCG_FD = fopen("/tmp/hcg_in.bin", 577, 438);
        if HCG_FD >= 0 {
            fwrite(HCG_FD, body, blen);
            fclose(HCG_FD);
            if gzip_write("/tmp/hcg_in.bin", "/tmp/hcg_out.gz") == 0 {
                HCG_FD = fopen("/tmp/hcg_out.gz", 0, 0);
                if HCG_FD >= 0 {
                    HCG_N = fread(HCG_FD, &HC_REQ + 4096, 61000);
                    fclose(HCG_FD);
                    if HCG_N > 0 {
                        # 用 tcp_http_ka 发,但 body 用压缩数据+头
                        return tcp_http_ka_raw("POST", path, host, port, &HC_REQ + 4096, HCG_N, buf, bufsize, status, 1);
                    }
                }
            }
        }
    }
    return tcp_http_ka("POST", path, host, port, body, blen, buf, bufsize, status);
}

# 原始 KA 请求(带 gzip 头开关)
var HCG_REQLEN: i64 = 0;
fn tcp_http_ka_raw(method: ptr, path: ptr, host: ptr, port: i64, body: ptr, blen: i64, buf: i64, bufsize: i64, status: ptr, gz: i64) -> i64 {
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    let ki: i64 = 0 - 1;
    let kk: i64 = 0;
    let ki0: i64 = 0;
    while kk < 4 {
        if HCK_FD[kk] > 0 && HCK_IP[kk] == HC_IP && HCK_PORT[kk] == port { ki = kk; }
        if HCK_FD[kk] <= 0 && ki < 0 { ki0 = kk; ki = ki0; }
        kk = kk + 1;
    }
    if ki < 0 {
        ki = 0;
        if HCK_FD[0] > 0 { tcp_close(HCK_FD[0]); HCK_FD[0] = 0; }
    } else if HCK_FD[ki] <= 0 {
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        HCK_IP[ki] = HC_IP; HCK_PORT[ki] = port;
    }
    strcpy(&HC_REQ, method);
    strcat(&HC_REQ, " ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nAccept-Encoding: gzip\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: keep-alive\r\n");
    if blen > 0 {
        if gz == 1 { strcat(&HC_REQ, "Content-Encoding: gzip\r\n"); }
        strcat(&HC_REQ, "Content-Length: ");
        strcat_i64(&HC_REQ, blen);
        strcat(&HC_REQ, "\r\n");
    }
    strcat(&HC_REQ, "\r\n");
    let hl: i64 = strlen(&HC_REQ);
    if body != 0 { memcpy(&HC_REQ + hl, body, blen); }
    HCK_N = hl + blen;
    if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
    }
    HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    if HCK_RC == 0 - 9 {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
        HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    }
    return HCK_RC;
}

# ETag 条件请求: If-None-Match: <etag> → 304 时返 0 body + status 304
fn tcp_http_if_none(path: ptr, host: ptr, port: i64, etag: ptr, buf: i64, bufsize: i64, status: ptr) -> i64 {
    # 先塞头:借用 HC_REQ 拼接在 path 后不行——直接 KA 发,后接自定义头?简单法:请求后 server 判;这里带 If-None-Match 头的 GET
    HC_IP = ip_parse(host);
    if HC_IP < 0 { return 0 - 1; }
    let ki: i64 = 0 - 1;
    let kk: i64 = 0;
    let ki0: i64 = 0;
    while kk < 4 {
        if HCK_FD[kk] > 0 && HCK_IP[kk] == HC_IP && HCK_PORT[kk] == port { ki = kk; }
        if HCK_FD[kk] <= 0 && ki < 0 { ki0 = kk; ki = ki0; }
        kk = kk + 1;
    }
    if ki < 0 {
        ki = 0;
        if HCK_FD[0] > 0 { tcp_close(HCK_FD[0]); HCK_FD[0] = 0; }
    } else if HCK_FD[ki] <= 0 {
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        HCK_IP[ki] = HC_IP; HCK_PORT[ki] = port;
    }
    strcpy(&HC_REQ, "GET ");
    strcat(&HC_REQ, path);
    strcat(&HC_REQ, " HTTP/1.1\r\nHost: ");
    strcat(&HC_REQ, host);
    strcat(&HC_REQ, "\r\nConnection: keep-alive\r\nIf-None-Match: ");
    strcat(&HC_REQ, etag);
    strcat(&HC_REQ, "\r\n\r\n");
    HCK_N = strlen(&HC_REQ);
    if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
    HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    if HCK_RC == 0 - 9 {
        tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0;
        HCK_FD[ki] = tcp_connect(HC_IP, port);
        if HCK_FD[ki] < 0 { HCK_FD[ki] = 0; return 0 - 2; }
        if tcp_send(HCK_FD[ki], &HC_REQ, HCK_N) != HCK_N { tcp_close(HCK_FD[ki]); HCK_FD[ki] = 0; return 0 - 2; }
        HCK_RC = tcp_http_ka_read(ki, port, buf, bufsize, status);
    }
    return HCK_RC;
}
