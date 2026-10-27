# regserver253.mo —— mopkg registry server（httpsrv 版,v1.253）
# GET /pkg/:file  → registry/<file>（tar.gz 原样）
# GET /search?kw= → index.txt 按关键词过滤
# registry 目录:/tmp/regtest/registry
import "io.mo";
import "net.mo";
import "str.mo";
import "fs.mo";
import "httpsrv.mo";

var RS_ROOT: [256] byte = "/tmp/regtest/registry/";
var RS_BUF: [65536] byte = 0;
var RS_PATH: [512] byte = 0;
var RS_IDX: [32768] byte = 0;
var RS_OUT: [32768] byte = 0;
var RS_FD: i64 = 0;
var RS_N: i64 = 0;
var RS_I: i64 = 0;
var RS_LP: i64 = 0;
var RS_KW: [128] byte = 0;

fn h_pkg(u: i64, a: i64) -> i64 {
    strcpy(&RS_PATH, RS_ROOT);
    strcat(&RS_PATH, &HS_PARAM);
    RS_FD = fopen(&RS_PATH, 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_BUF, 65536);
    fclose(RS_FD);
    if RS_N <= 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    return http_make_resp(200, "OK", "application/gzip", &RS_BUF, RS_N);
}

fn h_search(u: i64, a: i64) -> i64 {
    RS_FD = fopen("/tmp/regtest/registry/index.txt", 0, 0);
    if RS_FD < 0 { return http_make_resp(404, "Not Found", "text/plain", "404", 3); }
    RS_N = fread(RS_FD, &RS_IDX, 32768);
    fclose(RS_FD);
    strcpy(&RS_OUT, "");
    if http_query_param("kw") >= 0 {
        strcpy(&RS_KW, &HS_HVAL);
        RS_I = 0;
        while RS_I < RS_N {
            # 行 [RS_I, RS_LP)
            RS_LP = strstr(&RS_IDX + RS_I, "\n");
            if RS_LP < 0 { RS_LP = RS_N - RS_I; }
            if RS_LP > 0 {
                store8(&RS_IDX + RS_I + RS_LP, 0);
                if strstr(&RS_IDX + RS_I, &RS_KW) >= 0 {
                    strcat(&RS_OUT, &RS_IDX + RS_I);
                    strcat(&RS_OUT, "\n");
                }
            }
            RS_I = RS_I + RS_LP + 1;
        }
        if strlen(&RS_OUT) == 0 { strcpy(&RS_OUT, "none"); }
    } else {
        strcpy(&RS_OUT, &RS_IDX);
    }
    return http_make_resp(200, "OK", "text/plain", &RS_OUT, strlen(&RS_OUT));
}

fn main() -> i64 {
    http_route("GET", "/pkg/:file", &h_pkg);
    http_route("GET", "/search", &h_search);
    print("reg253 listening 18910\n");
    http_serve(18910, 8);
    return 0;
}
