# regserver256.mo —— registry server（v1.256:+token 鉴权+index sha256）
# GET  /pkg/:file   -> registry/<file>
# GET  /search?kw=  -> index 过滤
# POST /publish/:file?name=&version=&token= -> 入库+index(name version sha256)
import "io.mo";
import "net.mo";
import "str.mo";
import "fs.mo";
import "httpsrv.mo";
import "crypto.mo";

var RS_ROOT: [256] byte = "/tmp/regtest/registry/";
var RS_BUF: [65536] byte = 0;
var REG_MAXPK: i64 = 32;
var REG_MAXPKSZ: i64 = 16000;
var RS_IDXF: [128] byte = "/tmp/regtest/registry/index.txt";
var RS_EPOCH_BUF: [24] byte = 0;
var RS_TV: [16] byte = 0;
var RS_TIME_BUF: [32] byte = 0;
var RS_PATH: [512] byte = 0;
var RS_HDR: [256] byte = 0;
var RS_IDX: [32768] byte = 0;
var RS_OUT: [32768] byte = 0;
var RS_FD: i64 = 0;
var RS_N: i64 = 0;
var RS_I: i64 = 0;
var RS_LP: i64 = 0;
var RS_KW: [128] byte = 0;
var RS_LINE: [512] byte = 0;
var RS_NAME: [128] byte = 0;
var RS_VER: [64] byte = 0;
var RS_SHA: [80] byte = 0;

# 鉴权:POST 请求 query 里必须 token=secret256
fn mw_token() -> i64 {
    if streq(&HS_METHOD, "POST") != 1 { return 0; }
    if http_query_param("token") < 0 { return 1; }
    if streq(&HS_HVAL, "secret256") != 1 { return 1; }
    return 0;
}

fn h_pkg(u: i64, a: i64) -> i64 {
    strcpy(&RS_PATH, RS_ROOT);
    strcat(&RS_PATH, &HS_PARAM);
    RS_FD = fopen(&RS_PATH, 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_BUF, 65536);
    fclose(RS_FD);
    if RS_N <= 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    # v1.302:Content-Disposition 让浏览器保存为正确文件名
    strcpy(&RS_HDR, "Content-Disposition: attachment; filename=\"");
    strcat(&RS_HDR, &HS_PARAM);
    strcat(&RS_HDR, "\"");
    strcpy(&HS_XHDR, &RS_HDR);
    let rlen: i64 = http_make_resp(200, "OK", "application/gzip", &RS_BUF, RS_N);
    strcpy(&HS_XHDR, "");
    return rlen;
}

# v1.277:epoch 秒 → UTC "YYYY-MM-DD HH:MM:SS"
var RS_D: i64 = 0;
var RS_Y: i64 = 0;
var RS_MO: i64 = 0;
var RS_DAY: i64 = 0;
var RS_HH: i64 = 0;
var RS_MM: i64 = 0;
var RS_SS: i64 = 0;
var RS_LEAP: i64 = 0;
var RS_HTML: [32768] byte = 0;
var RS_OFF: [64] i64 = 0;
var RS_TS: [64] i64 = 0;
var RS_NUM_BUF: [24] byte = 0;

fn rs_utc(e: i64, buf: i64) -> i64 {
    RS_D = e / 86400;
    let secs: i64 = e % 86400;
    RS_Y = 1970;
    while 1 == 1 {
        RS_LEAP = 0;
        if RS_Y % 4 == 0 && (RS_Y % 100 != 0 || RS_Y % 400 == 0) { RS_LEAP = 1; }
        let yd: i64 = 365;
        if RS_LEAP == 1 { yd = 366; }
        if RS_D < yd { break; }
        RS_D = RS_D - yd;
        RS_Y = RS_Y + 1;
    }
    # 月天数表(if 链,mo 函数内不支持数组赋值)
    RS_MO = 0;
    let done_m: i64 = 0;
    while RS_MO < 12 && done_m == 0 {
        let mlen: i64 = 31;
        if RS_MO == 1 {
            mlen = 28;
            if RS_Y % 4 == 0 && (RS_Y % 100 != 0 || RS_Y % 400 == 0) { mlen = 29; }
        }
        if RS_MO == 3 || RS_MO == 5 || RS_MO == 8 || RS_MO == 10 { mlen = 30; }
        if RS_D >= mlen {
            RS_D = RS_D - mlen;
            RS_MO = RS_MO + 1;
        } else {
            done_m = 1;
        }
    }
    RS_DAY = RS_D + 1;
    RS_HH = secs / 3600;
    RS_MM = (secs % 3600) / 60;
    RS_SS = secs % 60;
    let nb: [24] byte = 0;
    utoa(RS_Y, &nb, 10);
    strcpy(buf, &nb);
    strcat(buf, "-");
    utoa(RS_MO + 1, &nb, 10);
    if RS_MO + 1 < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, "-");
    utoa(RS_DAY, &nb, 10);
    if RS_DAY < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, " ");
    utoa(RS_HH, &nb, 10);
    if RS_HH < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, ":");
    utoa(RS_MM, &nb, 10);
    if RS_MM < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    strcat(buf, ":");
    utoa(RS_SS, &nb, 10);
    if RS_SS < 10 { strcat(buf, "0"); }
    strcat(buf, &nb);
    return 0;
}

# v1.271:根路径 / 入口页——HTML 包列表
fn h_root(u: i64, a: i64) -> i64 {
    RS_FD = fopen("/tmp/regtest/registry/index.txt", 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_IDX, 32768);
    fclose(RS_FD);
    strcpy(&RS_OUT, "<html><head><title>mo registry</title></head><body><h1>mo registry</h1><form action=\"/search\" method=\"get\"><input type=\"text\" name=\"kw\" placeholder=\"search packages\"/><input type=\"hidden\" name=\"fmt\" value=\"html\"/><input type=\"submit\" value=\"Search\"/></form><p><a href=\"/rss.xml\">RSS</a> | <a href=\"/?sort=name\">按名称</a> | <a href=\"/\">按时间</a></p><table border=1><tr><th>name</th><th>version</th><th>sha256 (16)</th><th>link</th></tr>");
    # v1.281:解析每行偏移+时间戳,按时间戳降序输出
    let nrow: i64 = 0;
    RS_I = 0;
    while RS_I < RS_N && nrow < 64 {
        RS_LP = strstr(&RS_IDX + RS_I, "\n");
        if RS_LP < 0 { RS_LP = RS_N - RS_I; }
        if RS_LP > 0 {
            store8(&RS_IDX + RS_I + RS_LP, 0);
            let c1: i64 = strstr(&RS_IDX + RS_I, " ");
            if c1 > 0 {
                # v1.288:兼容 3 列旧行(无时间戳→0)
                let ts: i64 = 0;
                let tm2: i64 = strstr(&RS_IDX + RS_I + c1 + 1, " ");
                if tm2 >= 0 {
                    let tm3: i64 = strstr(&RS_IDX + RS_I + c1 + 1 + tm2 + 1, " ");
                    if tm3 >= 0 {
                        ts = atoi(&RS_IDX + RS_I + c1 + 1 + tm2 + 1 + tm3 + 1);
                    }
                }
                RS_OFF[nrow] = RS_I;
                RS_TS[nrow] = ts;
                nrow = nrow + 1;
            }
        }
        RS_I = RS_I + RS_LP + 1;
    }
    # v1.288:表格上方显示包总数
    strcat(&RS_OUT, "<caption>共 ");
    utoa(nrow, &RS_NUM_BUF, 10);
    strcat(&RS_OUT, &RS_NUM_BUF);
    strcat(&RS_OUT, " 个包</caption>");
    # v1.300:?sort=name 按名称升序,默认时间倒序
    let sort_name: i64 = 0;
    if http_query_param("sort") >= 0 {
        if streq(&HS_HVAL, "name") == 1 { sort_name = 1; }
    }
    # 选择排序:时间戳降序(新在前)或名称升序
    let si: i64 = 0;
    while si < nrow {
        let best: i64 = si;
        let sj: i64 = si + 1;
        while sj < nrow {
            if sort_name == 1 {
                if strcmp(&RS_IDX + RS_OFF[sj], &RS_IDX + RS_OFF[best]) < 0 { best = sj; }
            } else {
                if RS_TS[sj] > RS_TS[best] { best = sj; }
            }
            sj = sj + 1;
        }
        if best != si {
            let to: i64 = RS_OFF[si];
            let tt: i64 = RS_TS[si];
            RS_OFF[si] = RS_OFF[best];
            RS_TS[si] = RS_TS[best];
            RS_OFF[best] = to;
            RS_TS[best] = tt;
        }
        si = si + 1;
    }
    # 按排序输出
    let oi: i64 = 0;
    while oi < nrow {
        let ri: i64 = RS_OFF[oi];
        let c1: i64 = strstr(&RS_IDX + ri, " ");
        if c1 > 0 {
            store8(&RS_IDX + ri + c1, 0);
            let nm: i64 = &RS_IDX + ri;
            let rest: i64 = &RS_IDX + ri + c1 + 1;
            let c2: i64 = strstr(rest, " ");
            store8(rest + c2, 0);
            let ver: i64 = rest;
            let sha: i64 = rest + c2 + 1;
            strcat(&RS_OUT, "<tr");
            if oi == 0 && nrow > 1 {
                strcat(&RS_OUT, " style=\"background:#ffe0b0\"");
            }
            strcat(&RS_OUT, "><td>");
            strcat(&RS_OUT, nm);
            strcat(&RS_OUT, "</td><td>");
            strcat(&RS_OUT, ver);
            store8(sha + 16, 0);
            strcat(&RS_OUT, "</td><td><code>");
            strcat(&RS_OUT, sha);
            strcat(&RS_OUT, "</code></td><td><a href=\"/pkg/");
            strcat(&RS_OUT, nm);
            strcat(&RS_OUT, "-");
            strcat(&RS_OUT, ver);
            strcat(&RS_OUT, ".tar.gz\">download</a></td><td>");
            # v1.274:包大小(字节)——读文件统计
            strcpy(&RS_PATH, "/tmp/regtest/registry/");
            strcat(&RS_PATH, nm);
            strcat(&RS_PATH, "-");
            strcat(&RS_PATH, ver);
            strcat(&RS_PATH, ".tar.gz");
            let sfd: i64 = fopen(&RS_PATH, 0, 0);
            if sfd >= 0 {
                let ssz: i64 = fread(sfd, &RS_BUF, 65500);
                fclose(sfd);
                let sbu: [24] byte = 0;
                # v1.285:人性化大小
                if ssz >= 1048576 {
                    utoa(ssz / 1048576, &sbu, 10);
                    strcat(&RS_OUT, sbu);
                    strcat(&RS_OUT, " MB");
                } else if ssz >= 1024 {
                    utoa(ssz / 1024, &sbu, 10);
                    strcat(&RS_OUT, sbu);
                    strcat(&RS_OUT, " KB");
                } else {
                    utoa(ssz, &sbu, 10);
                    strcat(&RS_OUT, sbu);
                    strcat(&RS_OUT, " B");
                }
            } else {
                strcat(&RS_OUT, "?");
            }
            # v1.277:第 4 列时间戳 → 可读时间
            let tm: i64 = rest + c2 + 1;
            let tmsp: i64 = strstr(tm, " ");
            if tmsp > 0 {
                let tv: i64 = atoi(tm + tmsp + 1);
                strcat(&RS_OUT, "</td><td>");
                rs_utc(tv, &RS_TIME_BUF);
                strcat(&RS_OUT, &RS_TIME_BUF);
            }
            strcat(&RS_OUT, "</td></tr>");
        }
        oi = oi + 1;
    }
    strcat(&RS_OUT, "</table></body></html>");
    return http_make_resp(200, "OK", "text/html", &RS_OUT, strlen(&RS_OUT));
}

# v1.295:包详情页 /pkg/:file/info
fn h_pkg_info(u: i64, a: i64) -> i64 {
    strcpy(&RS_PATH, RS_ROOT);
    strcat(&RS_PATH, &HS_PARAM);
    let ifd: i64 = fopen(&RS_PATH, 0, 0);
    if ifd < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    let isz: i64 = fread(ifd, &RS_BUF, 65500);
    fclose(ifd);
    sha256_hex(&RS_BUF, isz, &RS_SHA);
    strcpy(&RS_OUT, "<html><head><title>package info</title></head><body><h1>package: ");
    strcat(&RS_OUT, &HS_PARAM);
    strcat(&RS_OUT, "</h1><p>size: ");
    utoa(isz, &RS_NUM_BUF, 10);
    strcat(&RS_OUT, &RS_NUM_BUF);
    strcat(&RS_OUT, " B</p><p>sha256: <code>");
    strcat(&RS_OUT, &RS_SHA);
    strcat(&RS_OUT, "</code></p><p><a href=\"/pkg/");
    strcat(&RS_OUT, &HS_PARAM);
    strcat(&RS_OUT, "\">download</a></p><p><a href=\"/\">back</a></p></body></html>");
    return http_make_resp(200, "OK", "text/html", &RS_OUT, strlen(&RS_OUT));
}

# v1.299:RFC822 日期 "Mon, 27 Oct 2026 15:19:22 +0000"
fn rss_date(e: i64, buf: i64) -> i64 {
    rs_utc(e, &RS_TIME_BUF);
    let wd: i64 = (e / 86400 + 4) % 7;
    # wd=0 对应 1970-01-04(Sun)?不——直接按 (epoch0=Thu, wd=4) 映射:
    if wd == 0 { strcpy(buf, "Sun, "); }
    if wd == 1 { strcpy(buf, "Mon, "); }
    if wd == 2 { strcpy(buf, "Tue, "); }
    if wd == 3 { strcpy(buf, "Wed, "); }
    if wd == 4 { strcpy(buf, "Thu, "); }
    if wd == 5 { strcpy(buf, "Fri, "); }
    if wd == 6 { strcpy(buf, "Sat, "); }
    utoa(RS_DAY, &RS_NUM_BUF, 10);
    if RS_DAY < 10 { strcat(buf, "0"); }
    strcat(buf, &RS_NUM_BUF);
    strcat(buf, " ");
    if RS_MO == 0 { strcat(buf, "Jan"); }
    if RS_MO == 1 { strcat(buf, "Feb"); }
    if RS_MO == 2 { strcat(buf, "Mar"); }
    if RS_MO == 3 { strcat(buf, "Apr"); }
    if RS_MO == 4 { strcat(buf, "May"); }
    if RS_MO == 5 { strcat(buf, "Jun"); }
    if RS_MO == 6 { strcat(buf, "Jul"); }
    if RS_MO == 7 { strcat(buf, "Aug"); }
    if RS_MO == 8 { strcat(buf, "Sep"); }
    if RS_MO == 9 { strcat(buf, "Oct"); }
    if RS_MO == 10 { strcat(buf, "Nov"); }
    if RS_MO == 11 { strcat(buf, "Dec"); }
    strcat(buf, " ");
    utoa(RS_Y, &RS_NUM_BUF, 10);
    strcat(buf, &RS_NUM_BUF);
    strcat(buf, " ");
    utoa(RS_HH, &RS_NUM_BUF, 10);
    if RS_HH < 10 { strcat(buf, "0"); }
    strcat(buf, &RS_NUM_BUF);
    strcat(buf, ":");
    utoa(RS_MM, &RS_NUM_BUF, 10);
    if RS_MM < 10 { strcat(buf, "0"); }
    strcat(buf, &RS_NUM_BUF);
    strcat(buf, ":");
    utoa(RS_SS, &RS_NUM_BUF, 10);
    if RS_SS < 10 { strcat(buf, "0"); }
    strcat(buf, &RS_NUM_BUF);
    strcat(buf, " +0000");
    return 0;
}

# v1.296:RSS 订阅 /rss.xml——最新 20 个包
fn h_rss(u: i64, a: i64) -> i64 {
    RS_FD = fopen(RS_IDXF, 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_IDX, 32768);
    fclose(RS_FD);
    strcpy(&RS_OUT, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\"><channel><title>mo registry</title><link>http://");
    strcat(&RS_OUT, &HS_HOSTBUF);
    strcat(&RS_OUT, "</link><description>mo package registry</description>");
    if strlen(&HS_HOSTBUF) == 0 { strcpy(&HS_HOSTBUF, "127.0.0.1:18910"); }
    # 复用入口页的倒序解析(最新在前)
    let nrow: i64 = 0;
    RS_I = 0;
    while RS_I < RS_N && nrow < 20 {
        RS_LP = strstr(&RS_IDX + RS_I, "\n");
        if RS_LP < 0 { RS_LP = RS_N - RS_I; }
        if RS_LP > 0 {
            store8(&RS_IDX + RS_I + RS_LP, 0);
            let c1: i64 = strstr(&RS_IDX + RS_I, " ");
            if c1 > 0 {
                # v1.296:兼容 3 列旧行(无时间戳→0)
                let ts: i64 = 0;
                let tm2: i64 = strstr(&RS_IDX + RS_I + c1 + 1, " ");
                if tm2 >= 0 {
                    let tm3: i64 = strstr(&RS_IDX + RS_I + c1 + 1 + tm2 + 1, " ");
                    if tm3 >= 0 {
                        ts = atoi(&RS_IDX + RS_I + c1 + 1 + tm2 + 1 + tm3 + 1);
                    }
                }
                RS_OFF[nrow] = RS_I;
                RS_TS[nrow] = ts;
                nrow = nrow + 1;
            }
        }
        RS_I = RS_I + RS_LP + 1;
    }
    let si: i64 = 0;
    while si < nrow {
        let best: i64 = si;
        let sj: i64 = si + 1;
        while sj < nrow {
            if RS_TS[sj] > RS_TS[best] { best = sj; }
            sj = sj + 1;
        }
        if best != si {
            let to: i64 = RS_OFF[si];
            let tt: i64 = RS_TS[si];
            RS_OFF[si] = RS_OFF[best];
            RS_TS[si] = RS_TS[best];
            RS_OFF[best] = to;
            RS_TS[best] = tt;
        }
        si = si + 1;
    }
    let oi: i64 = 0;
    while oi < nrow {
        let ri: i64 = RS_OFF[oi];
        let c1: i64 = strstr(&RS_IDX + ri, " ");
        if c1 > 0 {
            store8(&RS_IDX + ri + c1, 0);
            let nm: i64 = &RS_IDX + ri;
            let rest: i64 = &RS_IDX + ri + c1 + 1;
            let c2: i64 = strstr(rest, " ");
            store8(rest + c2, 0);
            let ver: i64 = rest;
            strcat(&RS_OUT, "<item><title>");
            strcat(&RS_OUT, nm);
            strcat(&RS_OUT, " ");
            strcat(&RS_OUT, ver);
            strcat(&RS_OUT, "</title><link>http://");
            strcat(&RS_OUT, &HS_HOSTBUF);
            strcat(&RS_OUT, "/pkg/");
            strcat(&RS_OUT, nm);
            strcat(&RS_OUT, "-");
            strcat(&RS_OUT, ver);
            strcat(&RS_OUT, ".tar.gz</link><guid>");
            strcat(&RS_OUT, nm);
            strcat(&RS_OUT, "-");
            strcat(&RS_OUT, ver);
            strcat(&RS_OUT, "</guid><pubDate>");
            rss_date(RS_TS[oi], &RS_TIME_BUF);
            strcat(&RS_OUT, &RS_TIME_BUF);
            strcat(&RS_OUT, "</pubDate></item>");
        }
        oi = oi + 1;
    }
    strcat(&RS_OUT, "</channel></rss>");
    return http_make_resp(200, "OK", "application/rss+xml", &RS_OUT, strlen(&RS_OUT));
}

fn h_search(u: i64, a: i64) -> i64 {
    RS_FD = fopen("/tmp/regtest/registry/index.txt", 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_IDX, 32768);
    fclose(RS_FD);
    strcpy(&RS_OUT, "");
    # v1.259:分页 page=N size=M(默认 0/20)
    let pg: i64 = 0;
    let sz: i64 = 20;
    if http_query_param("page") >= 0 { pg = atoi(&HS_HVAL); }
    if http_query_param("size") >= 0 { sz = atoi(&HS_HVAL); }
    if sz <= 0 { sz = 20; }
    if pg < 0 { pg = 0; }
    let skip: i64 = pg * sz;
    let shown: i64 = 0;
    let hit: i64 = 0;
    if http_query_param("kw") >= 0 {
        strcpy(&RS_KW, &HS_HVAL);
        RS_I = 0;
        while RS_I < RS_N {
            RS_LP = strstr(&RS_IDX + RS_I, "\n");
            if RS_LP < 0 { RS_LP = RS_N - RS_I; }
            if RS_LP > 0 {
                store8(&RS_IDX + RS_I + RS_LP, 0);
                if strstr(&RS_IDX + RS_I, &RS_KW) >= 0 {
                    if hit >= skip && shown < sz {
                        strcat(&RS_OUT, &RS_IDX + RS_I);
                        strcat(&RS_OUT, "\n");
                        shown = shown + 1;
                    }
                    hit = hit + 1;
                }
            }
            RS_I = RS_I + RS_LP + 1;
        }
        if strlen(&RS_OUT) == 0 { strcpy(&RS_OUT, "none"); }
    } else {
        strcpy(&RS_OUT, &RS_IDX);
    }
    # v1.279:fmt=html → 网页版结果
    let is_html: i64 = 0;
    if http_query_param("fmt") >= 0 {
        if streq(&HS_HVAL, "html") == 1 { is_html = 1; }
    }
    if is_html == 1 {
        strcpy(&RS_HTML, "<html><head><title>search</title></head><body><h1>search: ");
        strcat(&RS_HTML, &RS_KW);
        strcat(&RS_HTML, "</h1><table border=1><tr><th>name</th><th>version</th><th>sha256 (16)</th></tr>");
        # RS_OUT 是纯文本行(空格分隔),逐行转表格
        let hi: i64 = 0;
        let hlen: i64 = strlen(&RS_OUT);
        while hi < hlen {
            let he: i64 = strstr(&RS_OUT + hi, "\n");
            if he < 0 { he = hlen - hi; }
            if he > 0 {
                store8(&RS_OUT + hi + he, 0);
                let hc1: i64 = strstr(&RS_OUT + hi, " ");
                if hc1 > 0 {
                    store8(&RS_OUT + hi + hc1, 0);
                    let hc2: i64 = strstr(&RS_OUT + hi + hc1 + 1, " ");
                    # v1.297:兼容 3 列旧行(无 sha)
                    if hc2 < 0 {
                        strcat(&RS_HTML, "<tr><td>");
                        let kh: i64 = strstr(&RS_OUT + hi, &RS_KW);
                        if kh >= 0 && strlen(&RS_KW) > 0 {
                            store8(&RS_OUT + hi + kh + strlen(&RS_KW), 0);
                            strcat(&RS_HTML, &RS_OUT + hi);
                            strcat(&RS_HTML, "<mark>");
                            strcat(&RS_HTML, &RS_KW);
                            strcat(&RS_HTML, "</mark>");
                            strcat(&RS_HTML, &RS_OUT + hi + kh + strlen(&RS_KW));
                        } else {
                            strcat(&RS_HTML, &RS_OUT + hi);
                        }
                        strcat(&RS_HTML, "</td><td>");
                        strcat(&RS_HTML, &RS_OUT + hi + hc1 + 1);
                        strcat(&RS_HTML, "</td><td><code>(old)</code></td></tr>");
                        hi = hi + he + 1;
                        break;
                    }
                    if hc2 > 0 {
                        store8(&RS_OUT + hi + hc1 + 1 + hc2, 0);
                        # 第 3 空格截断:sha 列只到第 3 空格,再截 16
                        let hc3: i64 = strstr(&RS_OUT + hi + hc1 + 1 + hc2 + 1, " ");
                        if hc3 > 0 { store8(&RS_OUT + hi + hc1 + 1 + hc2 + 1 + hc3, 0); }
                        store8(&RS_OUT + hi + hc1 + 1 + hc2 + 1 + 16, 0);
                        strcat(&RS_HTML, "<tr><td>");
                        # v1.297:关键词高亮
                        let kh: i64 = strstr(&RS_OUT + hi, &RS_KW);
                        if kh >= 0 && strlen(&RS_KW) > 0 {
                            store8(&RS_OUT + hi + kh + strlen(&RS_KW), 0);
                            strcat(&RS_HTML, &RS_OUT + hi);
                            strcat(&RS_HTML, "<mark>");
                            strcat(&RS_HTML, &RS_KW);
                            strcat(&RS_HTML, "</mark>");
                            strcat(&RS_HTML, &RS_OUT + hi + kh + strlen(&RS_KW));
                        } else {
                            strcat(&RS_HTML, &RS_OUT + hi);
                        }
                        strcat(&RS_HTML, "</td><td>");
                        strcat(&RS_HTML, &RS_OUT + hi + hc1 + 1);
                        strcat(&RS_HTML, "</td><td><code>");
                        strcat(&RS_HTML, &RS_OUT + hi + hc1 + 1 + hc2 + 1);
                        strcat(&RS_HTML, "</code></td></tr>");
                    }
                }
            }
            hi = hi + he + 1;
        }
        strcat(&RS_HTML, "</table>");
        # v1.304:分页导航
        if hit > sz {
            strcat(&RS_HTML, "<p>");
            if pg > 0 {
                strcat(&RS_HTML, "<a href=\"/search?kw=");
                strcat(&RS_HTML, &RS_KW);
                strcat(&RS_HTML, "&fmt=html&page=");
                let pbu: [24] byte = 0;
                utoa(pg - 1, &pbu, 10);
                strcat(&RS_HTML, pbu);
                strcat(&RS_HTML, "\">上一页</a> ");
            }
            if (pg + 1) * sz < hit {
                let pbu2: [24] byte = 0;
                utoa(pg + 1, &pbu2, 10);
                strcat(&RS_HTML, "<a href=\"/search?kw=");
                strcat(&RS_HTML, &RS_KW);
                strcat(&RS_HTML, "&fmt=html&page=");
                strcat(&RS_HTML, pbu2);
                strcat(&RS_HTML, "\">下一页</a>");
            }
            strcat(&RS_HTML, "</p>");
        }
        strcat(&RS_HTML, "<p><a href=\"/\">back</a></p></body></html>");
        return http_make_resp(200, "OK", "text/html", &RS_HTML, strlen(&RS_HTML));
    }
    return http_make_resp(200, "OK", "text/plain", &RS_OUT, strlen(&RS_OUT));
}

fn h_publish(u: i64, a: i64) -> i64 {
    if HS_BLEN <= 0 { return http_make_resp(400, "Bad Request", "text/plain", "empty", 5); }
    # v1.264:单包字节配额
    if HS_BLEN > REG_MAXPKSZ {
        return http_make_resp(413, "Payload Too Large", "text/plain", "pksize", 6);
    }
    # v1.263:包数配额——index 行数 ≥ REG_MAXPK → 507 Insufficient Storage
    RS_FD = fopen(RS_IDXF, 0, 0);
    if RS_FD >= 0 {
        RS_N = fread(RS_FD, &RS_BUF, 65500);
        fclose(RS_FD);
        let lc: i64 = 0;
        let li: i64 = 0;
        while li < RS_N {
            if load8(RS_BUF + li) == 10 { lc = lc + 1; }
            li = li + 1;
        }
        if lc >= REG_MAXPK {
            return http_make_resp(507, "Insufficient Storage", "text/plain", "quota", 5);
        }
    }
    strcpy(&RS_PATH, RS_ROOT);
    strcat(&RS_PATH, &HS_PARAM);
    RS_FD = fopen(&RS_PATH, 577, 438);
    if RS_FD < 0 { return http_make_resp(500, "Server Error", "text/plain", "open", 4); }
    fwrite(RS_FD, &HS_BODY, HS_BLEN);
    fclose(RS_FD);
    strcpy(&RS_NAME, "");
    strcpy(&RS_VER, "");
    if http_query_param("name") >= 0 { strcpy(&RS_NAME, &HS_HVAL); }
    if http_query_param("version") >= 0 { strcpy(&RS_VER, &HS_HVAL); }
    # v1.272:同名同版本已存在 → 409 Conflict(避免静默覆盖)
    RS_FD = fopen(RS_IDXF, 0, 0);
    if RS_FD >= 0 {
        RS_N = fread(RS_FD, &RS_IDX, 32768);
        fclose(RS_FD);
        let ci: i64 = 0;
        let dup: i64 = 0;
        while ci < RS_N {
            let nl3: i64 = strstr(&RS_IDX + ci, "\n");
            if nl3 < 0 { nl3 = RS_N - ci; }
            if nl3 > 0 {
                store8(&RS_IDX + ci + nl3, 0);
                if strstr(&RS_IDX + ci, RS_NAME) == 0 && strstr(&RS_IDX + ci + strlen(RS_NAME) + 1, RS_VER) == 0 {
                    dup = 1;
                }
            }
            ci = ci + nl3 + 1;
        }
        if dup == 1 {
            return http_make_resp(409, "Conflict", "text/plain", "exists", 6);
        }
    }
    sha256_hex(&HS_BODY, HS_BLEN, &RS_SHA);
    # v1.258:index 去重——先过滤掉同名旧行,再追加
    RS_FD = fopen(RS_IDXF, 0, 0);
    if RS_FD >= 0 {
        RS_N = fread(RS_FD, &RS_BUF, 65536);
        fclose(RS_FD);
        if RS_N > 0 {
            store8(&RS_BUF + RS_N, 0);
            # 新 index 写临时(重建:跳过首列==RS_NAME 的行)
            let w: i64 = 0;      # 写位置
            let cur: i64 = 0;
            while cur < RS_N {
                let nl2: i64 = strstr(&RS_BUF + cur, "\n");
                if nl2 < 0 { nl2 = RS_N - cur; }
                # 行首列 == RS_NAME?
                let match: i64 = 0;
                if strstr(&RS_BUF + cur, RS_NAME) == 0 {
                    # 确认首列完整(下一个字符是空格)
                    if load8(RS_BUF + cur + strlen(&RS_NAME)) == 32 { match = 1; }
                }
                if match == 0 {
                    # 保留该行:memcpy 到 &RS_BUF + w…… 同缓冲前移安全(w<=cur)
                    let k: i64 = 0;
                    while k <= nl2 {
                        store8(&RS_BUF + w + k, load8(RS_BUF + cur + k));
                        k = k + 1;
                    }
                    w = w + nl2 + 1;
                }
                cur = cur + nl2 + 1;
            }
            RS_FD = fopen(RS_IDXF, 577, 438);   # 重建截断
            if RS_FD >= 0 {
                fwrite(RS_FD, &RS_BUF, w);
                fclose(RS_FD);
            }
        }
    }
    strcpy(&RS_LINE, &RS_NAME);
    strcat(&RS_LINE, " ");
    strcat(&RS_LINE, &RS_VER);
    strcat(&RS_LINE, " ");
    strcat(&RS_LINE, &RS_SHA);
    # v1.275:第 4 列发布时间戳(epoch)——gettimeofday(x86 96→arm 169),秒在 timeval.tv_sec
    strcat(&RS_LINE, " ");
    syscall(96, &RS_TV, 0, 0, 0, 0, 0);
    let now: i64 = load64(&RS_TV);
    let nx: i64 = now;
    if nx < 0 { nx = 0 - nx; }
    if nx == 0 { strcpy(&RS_EPOCH_BUF, "0"); } else {
        let wi: i64 = 0;
        while nx > 0 {
            store8(&RS_EPOCH_BUF + wi, (nx % 10) + 48);
            nx = nx / 10;
            wi = wi + 1;
        }
        store8(&RS_EPOCH_BUF + wi, 0);
        let a: i64 = 0;
        let b: i64 = wi - 1;
        while a < b {
            let t: i64 = load8(&RS_EPOCH_BUF + a);
            store8(&RS_EPOCH_BUF + a, load8(&RS_EPOCH_BUF + b));
            store8(&RS_EPOCH_BUF + b, t);
            a = a + 1;
            b = b - 1;
        }
    }
    strcat(&RS_LINE, &RS_EPOCH_BUF);
    strcat(&RS_LINE, "\n");
    RS_FD = fopen("/tmp/regtest/registry/index.txt", 1089, 438);
    if RS_FD >= 0 {
        fwrite(RS_FD, &RS_LINE, strlen(&RS_LINE));
        fclose(RS_FD);
    }
    return http_make_resp(201, "Created", "text/plain", "ok", 2);
}

# v1.265:DELETE /pkg/:file?token= → 删文件 + index 过滤同名行
fn h_delete(u: i64, a: i64) -> i64 {
    if http_query_param("token") < 0 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    if streq(&HS_HVAL, "secret256") != 1 { return http_make_resp(403, "Forbidden", "text/plain", "403", 3); }
    strcpy(&RS_PATH, RS_ROOT);
    strcat(&RS_PATH, &HS_PARAM);
    syscall(87, &RS_PATH, 0, 0, 0, 0);
    # index 过滤首列 == 文件名去后缀?按包名(name=参数)更稳
    if http_query_param("name") < 0 { return http_make_resp(200, "OK", "text/plain", "deleted", 7); }
    strcpy(&RS_NAME, &HS_HVAL);
    RS_FD = fopen(RS_IDXF, 0, 0);
    if RS_FD < 0 { return http_make_resp(200, "OK", "text/plain", "deleted", 7); }
    RS_N = fread(RS_FD, &RS_BUF, 65500);
    fclose(RS_FD);
    store8(&RS_BUF + RS_N, 0);
    let w: i64 = 0;
    let cur: i64 = 0;
    while cur < RS_N {
        let nl: i64 = strstr(&RS_BUF + cur, "\n");
        if nl < 0 { nl = RS_N - cur; }
        let match: i64 = 0;
        if strstr(&RS_BUF + cur, &RS_NAME) == 0 {
            if load8(RS_BUF + cur + strlen(&RS_NAME)) == 32 { match = 1; }
        }
        if match == 0 {
            let k: i64 = 0;
            while k <= nl {
                store8(&RS_BUF + w + k, load8(RS_BUF + cur + k));
                k = k + 1;
            }
            w = w + nl + 1;
        }
        cur = cur + nl + 1;
    }
    RS_FD = fopen(RS_IDXF, 577, 438);
    fwrite(RS_FD, &RS_BUF, w);
    fclose(RS_FD);
    return http_make_resp(200, "OK", "text/plain", "deleted", 7);
}

fn main() -> i64 {
    http_route("GET", "/", &h_root);
    http_route("GET", "/pkg/:file", &h_pkg);
    http_route("GET", "/pkg_info/:file", &h_pkg_info);
    http_route("GET", "/rss.xml", &h_rss);
    http_route("GET", "/search", &h_search);
    http_route("POST", "/publish/:file", &h_publish);
    http_route("DELETE", "/pkg/:file", &h_delete);
    http_middleware(&mw_token);
    http_log("/tmp/regtest/access.log");
    print("reg256 listening 18910\n");
    print("routes="); print_i64(HS_RTN); print_nl();
    print("mw="); print_i64(HS_MW); print_nl();
    print("rt0="); print(HS_RT_P[0]); print_nl();
    print("rt1="); print(HS_RT_P[1]); print_nl();
    http_max_body(16000);
    http_serve(18910, 8);
    return 0;
}
