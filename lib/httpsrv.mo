import "net.mo";
import "str.mo";
import "archive.mo";
import "io.mo";
import "fs.mo";
# 同步 HTTP server 框架（fork-per-conn）——v1.249
# 用法：http_route("GET", "/x", handler_fn_idx)；handler(req, resp)——req 内含 method/path/headers/body 全局可读；resp 拼装。
# 函数指针走 call2（moc 内建）。

var HS_METHOD: [16] byte = 0;
var HS_PATH: [512] byte = 0;
var HS_QUERY: [512] byte = 0;
var HS_BODY: [16384] byte = 0;
var HS_HVAL: [512] byte = 0;      # 最近一次查的头值
var HS_HOSTBUF: [256] byte = 0;   # v1.296:请求 Host 头
var HS_XHDR: [256] byte = "";      # v1.302:附加响应头(如 Content-Disposition)
var HS_DATEB: [64] byte = 0;      # v1.307:Date 头缓冲
var HS_TV: [16] byte = 0;          # v1.280:gettimeofday 结果
var HS_UTCD: i64 = 0;
var HS_UTCY: i64 = 0;
var HS_UTCMO: i64 = 0;
var HS_UTCDAY: i64 = 0;
var HS_UTCHH: i64 = 0;
var HS_UTCMM: i64 = 0;
var HS_UTCSS: i64 = 0;
var HS_UTCLEAP: i64 = 0;

# v1.307:HTTP Date 头(RFC 1123,如 Tue, 27 Oct 2026 19:09:25 GMT)
fn http_date_rfc1123() -> i64 {
    http_log_ts(&HS_DATEB);
    # 星期:1970-01-01 是周四,wd=(days+4)%7,0=Sun..6=Sat
    let e0: i64 = load64(&HS_TV);
    let wd: i64 = (e0 / 86400 + 4) % 7;
    if wd == 0 { strcpy(&HS_DATEB, "Sun, "); }
    if wd == 1 { strcpy(&HS_DATEB, "Mon, "); }
    if wd == 2 { strcpy(&HS_DATEB, "Tue, "); }
    if wd == 3 { strcpy(&HS_DATEB, "Wed, "); }
    if wd == 4 { strcpy(&HS_DATEB, "Thu, "); }
    if wd == 5 { strcpy(&HS_DATEB, "Fri, "); }
    if wd == 6 { strcpy(&HS_DATEB, "Sat, "); }
    let nb: [24] byte = 0;
    utoa(HS_UTCDAY, &nb, 10);
    if HS_UTCDAY < 10 { strcat(&HS_DATEB, "0"); }
    strcat(&HS_DATEB, &nb);
    strcat(&HS_DATEB, " ");
    if HS_UTCMO == 0 { strcat(&HS_DATEB, "Jan"); }
    if HS_UTCMO == 1 { strcat(&HS_DATEB, "Feb"); }
    if HS_UTCMO == 2 { strcat(&HS_DATEB, "Mar"); }
    if HS_UTCMO == 3 { strcat(&HS_DATEB, "Apr"); }
    if HS_UTCMO == 4 { strcat(&HS_DATEB, "May"); }
    if HS_UTCMO == 5 { strcat(&HS_DATEB, "Jun"); }
    if HS_UTCMO == 6 { strcat(&HS_DATEB, "Jul"); }
    if HS_UTCMO == 7 { strcat(&HS_DATEB, "Aug"); }
    if HS_UTCMO == 8 { strcat(&HS_DATEB, "Sep"); }
    if HS_UTCMO == 9 { strcat(&HS_DATEB, "Oct"); }
    if HS_UTCMO == 10 { strcat(&HS_DATEB, "Nov"); }
    if HS_UTCMO == 11 { strcat(&HS_DATEB, "Dec"); }
    strcat(&HS_DATEB, " ");
    utoa(HS_UTCY, &nb, 10);
    strcat(&HS_DATEB, &nb);
    strcat(&HS_DATEB, " ");
    utoa(HS_UTCHH, &nb, 10);
    if HS_UTCHH < 10 { strcat(&HS_DATEB, "0"); }
    strcat(&HS_DATEB, &nb);
    strcat(&HS_DATEB, ":");
    utoa(HS_UTCMM, &nb, 10);
    if HS_UTCMM < 10 { strcat(&HS_DATEB, "0"); }
    strcat(&HS_DATEB, &nb);
    strcat(&HS_DATEB, ":");
    utoa(HS_UTCSS, &nb, 10);
    if HS_UTCSS < 10 { strcat(&HS_DATEB, "0"); }
    strcat(&HS_DATEB, &nb);
    strcat(&HS_DATEB, " GMT");
    return 0;
}

var HS_RT_M: [32] i64 = 0;        # method ptr 数组
var HS_RT_P: [32] i64 = 0;        # path ptr
var HS_RT_F: [32] i64 = 0;        # fn idx
var HS_RTN: i64 = 0;
var HS_RTSM: [512] byte = 0;      # 静态字符串池：method 16B x32
var HS_RTSP: [16384] byte = 0;     # path 512B x32
var HS_RTSO: i64 = 0;
var HS_REQ: [32768] byte = 0;
var HS_GOT: i64 = 0;
var HS_HE: i64 = 0;
var HS_R: i64 = 0;
var HS_CL: i64 = 0;
var HS_DP: i64 = 0;
var HS_RESP: [32768] byte = 0;
var HS_PI: i64 = 0;
var HS_MI: i64 = 0;
var HS_C: i64 = 0;
var HS_BLEN: i64 = 0;
var HS_MAXBODY: i64 = 16000;
var HS_REJ413: i64 = 0;
var HS_KV: [512] byte = 0;
var HS_PARAM: [256] byte = 0;    # :param 值
var HS_ISHEAD: i64 = 0;
var HS_H2: i64 = 0;
var HS_L2: i64 = 0;
var HS_PARAM_K: [64] byte = 0;   # 参数名

# handler: fn(req_hdr_end_ptr_unused, body_ptr) -> i64 返回 body 长度;HS_RESP 前部状态行+头由框架拼
var HS_HFN: i64 = 0;

fn http_route(method: ptr, path: ptr, fnidx: i64) -> i64 {
    strcpy(&HS_RTSM + HS_RTN * 16, method);
    HS_RT_M[HS_RTN] = &HS_RTSM + HS_RTN * 16;
    strcpy(&HS_RTSP + HS_RTN * 512, path);
    HS_RT_P[HS_RTN] = &HS_RTSP + HS_RTN * 512;
    HS_RT_F[HS_RTN] = fnidx;
    HS_RTN = HS_RTN + 1;
    return HS_RTN;
}

# 查头（大小写敏感简化）：name: value
fn http_header(name: ptr) -> i64 {
    HS_DP = strstr(&HS_REQ, name);
    if HS_DP < 0 || HS_DP > HS_HE { return 0 - 1; }
    HS_DP = HS_DP + strlen(name) + 2;   # ": "
    HS_R = 0;
    while 1 {
        HS_C = load8(&HS_REQ + HS_DP);
        if HS_C == 13 || HS_C == 0 { break; }
        store8(&HS_HVAL + HS_R, HS_C);
        HS_R = HS_R + 1;
        HS_DP = HS_DP + 1;
    }
    store8(&HS_HVAL + HS_R, 0);
    return HS_R;
}

# 查询串参数：?k=v 里取 k → HS_HVAL
fn http_query_param(key: ptr) -> i64 {
    HS_DP = strstr(&HS_QUERY, key);
    if HS_DP < 0 { return 0 - 1; }
    HS_DP = HS_DP + strlen(key) + 1;
    HS_R = 0;
    while 1 {
        HS_C = load8(&HS_QUERY + HS_DP);
        if HS_C == 0 || HS_C == 38 { break; }
        if HS_C == 37 {
            HS_H2 = parse_nib(load8(&HS_QUERY + HS_DP + 1));
            HS_L2 = parse_nib(load8(&HS_QUERY + HS_DP + 2));
            if HS_H2 >= 0 && HS_L2 >= 0 {
                store8(&HS_HVAL + HS_R, HS_H2 * 16 + HS_L2);
                HS_R = HS_R + 1;
                HS_DP = HS_DP + 3;
                continue;
            }
        }
        store8(&HS_HVAL + HS_R, HS_C);
        HS_R = HS_R + 1;
        HS_DP = HS_DP + 1;
    }
    store8(&HS_HVAL + HS_R, 0);
    return HS_R;
}

# 响应组装：status text ctype body blen；若请求带 Accept-Encoding: gzip 且 body>32 → 压缩
var HS_AE: i64 = 0;
var HS_GZB: [16384] byte = 0;
var HS_GZT: [24] byte = "/tmp/hs_gzXXXXXX.gz";
fn http_make_resp(code: i64, text: ptr, ctype: ptr, body: ptr, blen: i64) -> i64 {
    HS_AE = strstr(&HS_REQ, "Accept-Encoding: gzip");
    if HS_AE >= 0 && blen > 32 {
        # gzip_write 走文件——把 body 落临时文件再压
        store64(&HS_GZT, 0);
        strcpy(&HS_GZT, "/tmp/hs_gz_in.bin");
        let dfd: i64 = fopen(&HS_GZT, 577, 438);
        if dfd >= 0 {
            fwrite(dfd, body, blen);
            fclose(dfd);
            strcpy(&HS_GZT, "/tmp/hs_gz_out.gz");
            if gzip_write(&HS_GZT, "/tmp/hs_gz_out.gz") == 0 {
                let rfd: i64 = fopen("/tmp/hs_gz_out.gz", 0, 0);
                if rfd >= 0 {
                    let rn: i64 = fread(rfd, &HS_GZB, 16384);
                    fclose(rfd);
                    if rn > 0 && rn < blen {
                        strcpy(&HS_RESP, "HTTP/1.1 ");
                        strcat_i64(&HS_RESP, code);
                        strcat(&HS_RESP, " ");
                        strcat(&HS_RESP, text);
                        strcat(&HS_RESP, "\r\nContent-Type: ");
                        strcat(&HS_RESP, ctype);
                        strcat(&HS_RESP, "\r\nContent-Encoding: gzip\r\nContent-Length: ");
                        strcat_i64(&HS_RESP, rn);
                        strcat(&HS_RESP, "\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'\r\n");
                        if strlen(&HS_XHDR) > 0 {
                            strcat(&HS_RESP, &HS_XHDR);
                            strcat(&HS_RESP, "\r\n");
                        }
                        strcat(&HS_RESP, "\r\n");
                        memcpy(&HS_RESP + strlen(&HS_RESP), &HS_GZB, rn);
                        return strlen(&HS_RESP) + rn;
                    }
                }
            }
        }
    }
    strcpy(&HS_RESP, "HTTP/1.1 ");
    strcat_i64(&HS_RESP, code);
    strcat(&HS_RESP, " ");
    strcat(&HS_RESP, text);
    strcat(&HS_RESP, "\r\nContent-Type: ");
    strcat(&HS_RESP, ctype);
    strcat(&HS_RESP, "\r\nContent-Length: ");
    strcat_i64(&HS_RESP, blen);
    strcat(&HS_RESP, "\r\nServer: mo-httpsrv");
    strcat(&HS_RESP, "\r\nDate: ");
    http_date_rfc1123();
    strcat(&HS_RESP, &HS_DATEB);
    strcat(&HS_RESP, "\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'\r\n");
    if strlen(&HS_XHDR) > 0 {
        strcat(&HS_RESP, &HS_XHDR);
        strcat(&HS_RESP, "\r\n");
    }
    strcat(&HS_RESP, "\r\n");
    memcpy(&HS_RESP + strlen(&HS_RESP), body, blen);
    return strlen(&HS_RESP) + blen;
}

# handler 收到：写 HS_KV，返回 blen —— 由 call2 调
# 框架 serve 一连接
# ---------- v1.254 中间件钩子 + POST gzip 上传透明解 + ETag ----------
# 钩子:请求路由前调用(可拒绝:返回非 0 → 403);fnidx 走 call0
var HS_MW: i64 = 0;   # 0 = 无
var HS_SCR: i64 = 0;
var HS_LOGFD: i64 = 0;
var HS_LOGLINE: [512] byte = 0;
var HS_LOGPATH: [256] byte = 0;
var HS_LOGON: i64 = 0;

fn http_middleware(fnidx: i64) -> i64 {
    HS_MW = fnidx;
    return 0;
}

# POST body gzip:请求带 Content-Encoding: gzip → gunzip 后 HS_BODY 为明文
var HS_BFD: i64 = 0;
var HS_BRN: i64 = 0;
var HS_GFD: i64 = 0;
var HS_GRN: i64 = 0;

fn http_body_decode() -> i64 {
    if strstr(&HS_REQ, "Content-Encoding: gzip") >= 0 && HS_BLEN > 0 {
        HS_BFD = fopen("/tmp/hs_up.gz", 577, 438);
        if HS_BFD >= 0 {
            fwrite(HS_BFD, &HS_BODY, HS_BLEN);
            fclose(HS_BFD);
            let gr: i64 = gunzip_file("/tmp/hs_up.gz", "/tmp/hs_up.bin");
            if gr >= 0 {
                HS_GFD = fopen("/tmp/hs_up.bin", 0, 0);
                if HS_GFD >= 0 {
                    HS_GRN = fread(HS_GFD, &HS_BODY, 16384);
                    fclose(HS_GFD);
                    store8(&HS_BODY + HS_GRN, 0);
                    HS_BLEN = HS_GRN;
                }
            }
        }
    }
    return HS_BLEN;
}



# ETag:FNV-1a → 8 hex;If-None-Match 命中 → 304
var HS_ET: [64] byte = 0;
var HS_ETV: i64 = 0;
var HS_ETI: i64 = 0;
var HS_ETD: [17] byte = "0123456789abcdef";
var HS_SC: [2] byte = 0;

fn strcat_c(dst: ptr, c: i64) -> i64 {
    store8(&HS_SC, c);
    store8(&HS_SC + 1, 0);
    return strcat(dst, &HS_SC);
}

fn http_etag(body: ptr, blen: i64) -> i64 {
    HS_ETV = 2166136261;
    HS_ETI = 0;
    while HS_ETI < blen {
        HS_ETV = HS_ETV ^ load8(body + HS_ETI);
        HS_ETV = HS_ETV * 16777619;
        HS_ETV = HS_ETV & 4294967295;
        HS_ETI = HS_ETI + 1;
    }
    strcpy(&HS_ET, "W/\"");
    HS_ETI = 7;
    while HS_ETI >= 0 {
        strcat_c(&HS_ET, load8(&HS_ETD + ((HS_ETV >> (HS_ETI * 4)) & 15)));
        HS_ETI = HS_ETI - 1;
    }
    strcat(&HS_ET, "\"");
    return &HS_ET;
}

fn http_make_resp_etag(code: i64, text: ptr, ctype: ptr, body: ptr, blen: i64) -> i64 {
    http_etag(body, blen);
    if strstr(&HS_REQ, "If-None-Match: ") >= 0 && strstr(&HS_REQ, &HS_ET) >= 0 {
        # v1.260:304 必须回带 ETag 头(规范);无 body
        strcpy(&HS_RESP, "HTTP/1.1 304 Not Modified\r\nContent-Type: ");
        strcat(&HS_RESP, ctype);
        strcat(&HS_RESP, "\r\nETag: ");
        strcat(&HS_RESP, &HS_ET);
        strcat(&HS_RESP, "\r\nContent-Length: 0\r\nServer: mo-httpsrv\r\nDate: ");
    http_date_rfc1123();
    strcat(&HS_RESP, &HS_DATEB);
    strcat(&HS_RESP, "\r\nConnection: close\r\n\r\n");
        return strlen(&HS_RESP);
    }
    strcpy(&HS_RESP, "HTTP/1.1 ");
    strcat_i64(&HS_RESP, code);
    strcat(&HS_RESP, " ");
    strcat(&HS_RESP, text);
    strcat(&HS_RESP, "\r\nContent-Type: ");
    strcat(&HS_RESP, ctype);
    strcat(&HS_RESP, "\r\nETag: ");
    strcat(&HS_RESP, &HS_ET);
    strcat(&HS_RESP, "\r\nContent-Length: ");
    strcat_i64(&HS_RESP, blen);
    strcat(&HS_RESP, "\r\nConnection: close\r\n");
    if strlen(&HS_XHDR) > 0 {
        strcat(&HS_RESP, &HS_XHDR);
        strcat(&HS_RESP, "\r\n");
    }
    strcat(&HS_RESP, "\r\n");
    memcpy(&HS_RESP + strlen(&HS_RESP), body, blen);
    return strlen(&HS_RESP) + blen;
}


# 循环 send(处理部分写)
var HSS_OFF: i64 = 0;
var HSS_W: i64 = 0;
fn tcp_send_all(fd: i64, buf: i64, n: i64) -> i64 {
    HSS_OFF = 0;
    while HSS_OFF < n {
        HSS_W = tcp_send(fd, buf + HSS_OFF, n - HSS_OFF);
        if HSS_W <= 0 { return 0 - 1; }
        HSS_OFF = HSS_OFF + HSS_W;
    }
    return HSS_OFF;
}

fn http_serve_conn(fd: i64) -> i64 {
    HS_GOT = 0;
    HS_HE = 0 - 1;
    while HS_HE < 0 && HS_GOT < 31000 {
        HS_R = tcp_recv(fd, &HS_REQ + HS_GOT, 4096);
        if HS_R <= 0 { break; }
        HS_GOT = HS_GOT + HS_R;
        store8(&HS_REQ + HS_GOT, 0);
        HS_HE = strstr(&HS_REQ, "\r\n\r\n");
    }
    if HS_HE < 0 { tcp_close(fd); return 0 - 1; }
    # method/path/query；HEAD → 记标志并按 GET 路由
    HS_ISHEAD = 0;
    HS_MI = 0;
    while 1 {
        HS_C = load8(&HS_REQ + HS_MI);
        if HS_C == 32 { break; }
        store8(&HS_METHOD + HS_MI, HS_C);
        HS_MI = HS_MI + 1;
    }
    store8(&HS_METHOD + HS_MI, 0);
    if streq(&HS_METHOD, "HEAD") == 1 {
        HS_ISHEAD = 1;
        strcpy(&HS_METHOD, "GET");
    }
    HS_PI = 0;
    HS_DP = HS_MI + 1;
    strcpy(&HS_QUERY, "");
    while 1 {
        HS_C = load8(&HS_REQ + HS_DP);
        if HS_C == 32 || HS_C == 63 { break; }
        store8(&HS_PATH + HS_PI, HS_C);
        HS_PI = HS_PI + 1;
        HS_DP = HS_DP + 1;
    }
    store8(&HS_PATH + HS_PI, 0);
    if HS_C == 63 {
        strcpy(&HS_QUERY, &HS_REQ + HS_DP + 1);
        HS_DP = HS_DP + strlen(&HS_QUERY) + 1;
        HS_R = strstr(&HS_QUERY, " ");
        if HS_R >= 0 { store8(&HS_QUERY + HS_R, 0); }
    }
    # body（Content-Length）
    HS_BLEN = 0;
    HS_DP = strstr(&HS_REQ, "Content-Length: ");
    if HS_DP >= 0 && HS_DP < HS_HE {
        HS_DP = HS_DP + 16;
        while 1 {
            HS_C = load8(&HS_REQ + HS_DP);
            if HS_C < 48 || HS_C > 57 { break; }
            HS_BLEN = HS_BLEN * 10 + (HS_C - 48);
            HS_DP = HS_DP + 1;
        }
        while HS_GOT - HS_HE - 4 < HS_BLEN && HS_GOT < 31000 {
            HS_R = tcp_recv(fd, &HS_REQ + HS_GOT, 4096);
            if HS_R <= 0 { break; }
            HS_GOT = HS_GOT + HS_R;
            store8(&HS_REQ + HS_GOT, 0);
        }
    }
    # v1.259:body 大小上限——超限 413 拒收(防 16K 池越界)
    if HS_BLEN > HS_MAXBODY {
        HS_R = http_make_resp(413, "Payload Too Large", "text/plain", "413", 3);
        tcp_send_all(fd, &HS_RESP, HS_R);
        return 0;
    }
    # v1.296:提取 Host 头(供 RSS/链接用)
    strcpy(&HS_HOSTBUF, "");
    HS_DP = strstr(&HS_REQ, "Host: ");
    if HS_DP >= 0 && HS_DP < HS_HE {
        HS_DP = HS_DP + 6;
        let hh: i64 = 0;
        while 1 {
            HS_C = load8(&HS_REQ + HS_DP + hh);
            if HS_C == 13 || HS_C == 10 || HS_C == 0 { break; }
            store8(&HS_HOSTBUF + hh, HS_C);
            hh = hh + 1;
            if hh >= 250 { break; }
        }
        store8(&HS_HOSTBUF + hh, 0);
    }
    # body 拷出 + POST gzip 透明解
    if HS_BLEN > 0 { memcpy(&HS_BODY, &HS_REQ + HS_HE + 4, HS_BLEN); store8(&HS_BODY + HS_BLEN, 0); }
    http_body_decode();
    # 中间件钩子:非 0 拒绝
    if HS_MW != 0 {
        if call0(HS_MW) != 0 {
            HS_R = http_make_resp(403, "Forbidden", "text/plain", "403", 3);
            tcp_send_all(fd, &HS_RESP, HS_R);
            tcp_close(fd);
            return HS_R;
        }
    }
    http_log_tick();
    # 路由
    HS_R = 0 - 404;
    HS_DP = 0;
    while HS_DP < HS_RTN {
        if streq(&HS_METHOD, HS_RT_M[HS_DP]) == 1 && streq(&HS_PATH, HS_RT_P[HS_DP]) == 1 {
            HS_R = call2(HS_RT_F[HS_DP], 0, &HS_BODY);
            break;
        }
        # 参数化匹配：路由含 ':name' → 提取对应段到 HS_PARAM
        if streq(&HS_METHOD, HS_RT_M[HS_DP]) == 1 {
            # 前缀检查：'：' 之前的部分必须与 path 前缀一致
            HS_SCR = strstr(HS_RT_P[HS_DP], ":");
            if HS_SCR >= 0 {
                if str_ncmp(HS_RT_P[HS_DP], &HS_PATH, HS_SCR) == 1 {
            HS_MI = 0;
            strcpy(&HS_PARAM, "");
            strcpy(&HS_PARAM_K, "");
            while 1 {
                HS_C = load8(HS_RT_P[HS_DP] + HS_MI);
                if HS_C == 0 { break; }
                if HS_C == 58 {   # ':' 参数开始
                    HS_PI = HS_MI;   # 路径里同偏移 = 段首
                    HS_SCR = 0;
                    while 1 {
                        HS_C = load8(HS_RT_P[HS_DP] + HS_MI + 1);
                        if HS_C == 47 || HS_C == 0 { break; }
                        store8(&HS_PARAM_K + HS_SCR, HS_C);
                        HS_SCR = HS_SCR + 1;
                        HS_MI = HS_MI + 1;
                    }
                    store8(&HS_PARAM_K + HS_SCR, 0);
                    # 提取 HS_PATH 对应段
                    HS_SCR = 0;
                    while 1 {
                        HS_C = load8(&HS_PATH + HS_PI);
                        if HS_C == 47 || HS_C == 0 { break; }
                        store8(&HS_PARAM + HS_SCR, HS_C);
                        HS_SCR = HS_SCR + 1;
                        HS_PI = HS_PI + 1;
                    }
                    store8(&HS_PARAM + HS_SCR, 0);
                    # v1.295:参数段后 path 必须已结束(否则是更深路径,不匹配)
                    if load8(&HS_PATH + HS_PI) == 0 {
                        HS_R = call2(HS_RT_F[HS_DP], 0, &HS_BODY);
                        break;
                    }
                }
                HS_MI = HS_MI + 1;
            }
            if HS_R != 0 - 404 { break; }
            }
            }
        }
        HS_DP = HS_DP + 1;
    }
    if HS_R == 0 - 404 {
        HS_R = http_make_resp(404, "Not Found", "text/plain", "404", 3);
    }
    if HS_ISHEAD == 1 {
        # 掐 body:找 \r\n\r\n 后截断(响应头里有 CL,HEAD 无 body)
        HS_R = strstr(&HS_RESP, "\r\n\r\n");
        if HS_R >= 0 { HS_R = HS_R + 4; tcp_send_all(fd, &HS_RESP, HS_R); tcp_close(fd); return HS_R; }
    }
    tcp_send_all(fd, &HS_RESP, HS_R);
    tcp_close(fd);
    return HS_R;
}

# 主循环：port, backlog；每连接 fork handler
fn http_serve(port: i64, backlog: i64) -> i64 {
    let lst: i64 = tcp_listen(port, backlog);
    if lst < 0 { return 0 - 1; }
    while 1 {
        let fd: i64 = tcp_accept(lst);
        if fd < 0 { continue; }
        let pid: i64 = fork();
        if pid == 0 {
            tcp_close(lst);
            http_serve_conn(fd);
            exit(0);
        }
        tcp_close(fd);
    }
    return 0;
}

# ---------- v1.252 静态文件服务 ----------
var HS_RT_ROOT: [256] byte = "./";
var HS_FBUF: [65536] byte = 0;
var HS_FPATH: [512] byte = 0;
var HS_MIME: [64] byte = 0;
var HS_FN: i64 = 0;
var HS_FI: i64 = 0;

# 扩展名 → MIME（.html .css .js .json .txt .png .gz）
fn http_mime(path: ptr) -> i64 {
    strcpy(&HS_MIME, "application/octet-stream");
    HS_FI = strlen(path) - 1;
    while HS_FI >= 0 && load8(path + HS_FI) != 46 { HS_FI = HS_FI - 1; }   # '.'
    if HS_FI < 0 { return &HS_MIME; }
    if str_ncmp(path + HS_FI, ".html", 5) == 1 { strcpy(&HS_MIME, "text/html"); }
    else if str_ncmp(path + HS_FI, ".css", 4) == 1 { strcpy(&HS_MIME, "text/css"); }
    else if str_ncmp(path + HS_FI, ".js", 3) == 1 { strcpy(&HS_MIME, "text/javascript"); }
    else if str_ncmp(path + HS_FI, ".json", 5) == 1 { strcpy(&HS_MIME, "application/json"); }
    else if str_ncmp(path + HS_FI, ".txt", 4) == 1 { strcpy(&HS_MIME, "text/plain"); }
    else if str_ncmp(path + HS_FI, ".png", 4) == 1 { strcpy(&HS_MIME, "image/png"); }
    else if str_ncmp(path + HS_FI, ".gz", 3) == 1 { strcpy(&HS_MIME, "application/gzip"); }
    return &HS_MIME;
}

# 静态路由 handler：前缀 root + HS_PARAM(文件名)；404 不存在
fn h_static(u: i64, a: i64) -> i64 {
    strcpy(&HS_FPATH, HS_RT_ROOT);
    strcat(&HS_FPATH, &HS_PARAM);
    let fd: i64 = fopen(&HS_FPATH, 0, 0);
    if fd < 0 {
        return http_make_resp(404, "Not Found", "text/plain", "404", 3);
    }
    HS_FN = fread(fd, &HS_FBUF, 65536);
    fclose(fd);
    if HS_FN < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    return http_make_resp(200, "OK", http_mime(&HS_FPATH), &HS_FBUF, HS_FN);
}



# ---------- v1.253 目录列表（基于 fs.list_dir） ----------
var HS_DL: [16384] byte = 0;
var HS_DNAMES: [128] i64 = 0;
var HS_DN: i64 = 0;
var HS_DI: i64 = 0;

fn h_dirlist(u: i64, a: i64) -> i64 {
    strcpy(&HS_FPATH, HS_RT_ROOT);
    HS_DN = list_dir(&HS_FPATH, &HS_DNAMES, 128);
    strcpy(&HS_DL, "<html><body><ul>");
    if HS_DN <= 0 {
        strcat(&HS_DL, "<li>empty</li>");
    } else {
        HS_DI = 0;
        while HS_DI < HS_DN {
            strcat(&HS_DL, "<li>");
            strcat(&HS_DL, HS_DNAMES[HS_DI]);
            strcat(&HS_DL, "</li>");
            HS_DI = HS_DI + 1;
        }
    }
    strcat(&HS_DL, "</ul></body></html>");
    return http_make_resp(200, "OK", "text/html", &HS_DL, strlen(&HS_DL));
}

fn http_static_route(root: ptr) -> i64 {
    strcpy(&HS_RT_ROOT, root);
    http_route("GET", "/static/:file", &h_static);
    http_route("GET", "/static", &h_dirlist);
    http_route("GET", "/static/", &h_dirlist);
    return 0;
}

# ---------- HEAD：路由同 GET,响应去 body ----------
var HS_HM: [16] byte = 0;
fn http_head_norm() -> i64 {
    # serve_conn 中 HEAD 请求 → 实际路由用 GET,发响应时按 CL 掐掉 body
    strcpy(&HS_HM, "GET");
    return 0;
}

# ---------- v1.255 访问日志中间件 ----------
# http_log(path)：注册后每请求路由前向 path 追加一行
#   METHOD PATH BLEN -> RESP_LEN/CODE；配合 http_middleware 用（返回 0 放行）
# v1.259:POST body 上限(默认 16000,防 HS_BODY 池越界)
fn http_max_body(n: i64) -> i64 {
    HS_MAXBODY = n;
    return 0;
}

fn http_log(path: ptr) -> i64 {
    strcpy(&HS_LOGPATH, path);
    HS_LOGON = 1;
    return 0;
}

var HS_TSB: [32] byte = 0;

# v1.280:epoch 秒 → UTC "YYYY-MM-DD HH:MM:SS"(日志可读时间)
fn http_log_ts(buf: i64) -> i64 {
    syscall(96, &HS_TV, 0, 0, 0, 0, 0);
    let e: i64 = load64(&HS_TV);
    HS_UTCD = e / 86400;
    let secs: i64 = e % 86400;
    HS_UTCY = 1970;
    while 1 == 1 {
        HS_UTCLEAP = 0;
        if HS_UTCY % 4 == 0 && (HS_UTCY % 100 != 0 || HS_UTCY % 400 == 0) { HS_UTCLEAP = 1; }
        let yd: i64 = 365;
        if HS_UTCLEAP == 1 { yd = 366; }
        if HS_UTCD < yd { break; }
        HS_UTCD = HS_UTCD - yd;
        HS_UTCY = HS_UTCY + 1;
    }
    HS_UTCMO = 0;
    let done_m: i64 = 0;
    while HS_UTCMO < 12 && done_m == 0 {
        let mlen: i64 = 31;
        if HS_UTCMO == 1 {
            mlen = 28;
            if HS_UTCY % 4 == 0 && (HS_UTCY % 100 != 0 || HS_UTCY % 400 == 0) { mlen = 29; }
        }
        if HS_UTCMO == 3 || HS_UTCMO == 5 || HS_UTCMO == 8 || HS_UTCMO == 10 { mlen = 30; }
        if HS_UTCD >= mlen {
            HS_UTCD = HS_UTCD - mlen;
            HS_UTCMO = HS_UTCMO + 1;
        } else {
            done_m = 1;
        }
    }
    HS_UTCDAY = HS_UTCD + 1;
    HS_UTCHH = secs / 3600;
    HS_UTCMM = (secs % 3600) / 60;
    HS_UTCSS = secs % 60;
    let nb: [24] byte = 0;
    utoa(HS_UTCY, &nb, 10);
    strcpy(buf, &nb);
    strcat(buf, "-");
    utoa(HS_UTCMO + 1, &nb, 10);
    if HS_UTCMO + 1 < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, "-");
    utoa(HS_UTCDAY, &nb, 10);
    if HS_UTCDAY < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, " ");
    utoa(HS_UTCHH, &nb, 10);
    if HS_UTCHH < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, ":");
    utoa(HS_UTCMM, &nb, 10);
    if HS_UTCMM < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, ":");
    utoa(HS_UTCSS, &nb, 10);
    if HS_UTCSS < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    return 0;
}

fn http_log_tick() -> i64 {
    if HS_LOGON == 0 { return 0; }
    http_log_ts(&HS_TSB);
    strcpy(&HS_LOGLINE, &HS_TSB);
    strcat(&HS_LOGLINE, " ");
    strcat(&HS_LOGLINE, &HS_METHOD);
    strcat(&HS_LOGLINE, " ");
    strcat(&HS_LOGLINE, &HS_PATH);
    strcat(&HS_LOGLINE, " b=");
    strcat_i64(&HS_LOGLINE, HS_BLEN);
    strcat(&HS_LOGLINE, "\n");
    HS_LOGFD = fopen(&HS_LOGPATH, 1089, 438);
    if HS_LOGFD >= 0 {
        fwrite(HS_LOGFD, &HS_LOGLINE, strlen(&HS_LOGLINE));
        fclose(HS_LOGFD);
    }
    return 0;
}
