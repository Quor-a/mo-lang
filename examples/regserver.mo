# regserver.mo —— mopkg 网络 registry server（v1.201.0）
# GET /pkg/<name-ver>.tar.gz -> 文件内容（HTTP/1.0 + Content-Length）
# GET /search[?kw=...]       -> index.txt 文本
# registry 目录：/tmp/regtest/registry（index.txt + <name>/<file>）
import "io.mo";
import "csp.mo";
import "aio.mo";
import "lf.mo";
import "net.mo";
import "fs.mo";
import "str.mo";

var PORT: i64 = 18900;
var LFD: i64 = 0;
# v1.215 并发化：per-conn 槽缓冲（4 槽 × 128KB），serve_conn 走协程
var SLOTS: [4] i64 = 0;          # 忙标志 0/1（fd 占用标记用 CAS）
var SRBUF: [524288] byte = 0;    # 8 × 65536 RBUF（v1.221：槽随 csp_init 扩到 8，4 槽 + slot>3 = 越界踩内存）
var SFBUF: [524288] byte = 0;    # 8 × 65536 FBUF
var RBUF: [65536] byte = 0;      # 兼容保留（槽 0 别名由调用方保证）——不再直接用
var FBUF: [65536] byte = 0;
var PATHB: [512] byte = 0;
var REGDIR: [256] byte = 0;

fn send_all(fd: i64, buf: i64, n: i64) -> i64 {
    let off: i64 = 0;
    while off < n {
        let w: i64 = aio_send(fd, buf + off, n - off);
        if w < 0 { return 0 - 1; }
        off = off + w;
    }
    return 0;
}

fn serve_conn(fd: i64, slot: i64) -> i64 {
    # v1.215：每请求清槽缓冲头部（防上一请求残留干扰 strstr 切分）
    let zc: i64 = 0;
    while zc < 8192 {
        store8(&SRBUF + slot * 65536 + zc, 0);
        zc = zc + 1;
    }
    let n: i64 = aio_recv(fd, &SRBUF + slot * 65536, 4096);
    if n <= 0 { tcp_close(fd); return 0; }
    store8(&SRBUF + slot * 65536 + n, 0);
    # PUT /pkg/<file>：收 CL body 存 registry（v1.203.0）
    if strstr(&SRBUF + slot * 65536, "PUT /pkg/") == 0 {
        let clp: i64 = strstr(&SRBUF + slot * 65536, "Content-Length: ");
        if clp < 0 { tcp_close(fd); return 0; }
        let cl: i64 = atoi(&SRBUF + slot * 65536 + clp + 16);
        # 头尾
        let bb: i64 = strstr(&SRBUF + slot * 65536, "\r\n\r\n");
        if bb < 0 { tcp_close(fd); return 0; }
        # 路径 = RBUF+4 .. 空格
        let pe: i64 = 4;
        while load8(&SRBUF + slot * 65536 + pe) != 32 { pe = pe + 1; }
        store8(&SRBUF + slot * 65536 + pe, 0);
        # 截掉 query（'?' 之后）；query 先拷到 RBUF+2000 供 name/ver 解析
        let qm: i64 = strstr(&SRBUF + slot * 65536 + 4, "?");
        if qm >= 0 {
            strcpy(&SRBUF + slot * 65536 + 2000, &SRBUF + slot * 65536 + 4 + qm + 1);   # name=...&ver=...
            store8(&SRBUF + slot * 65536 + 4 + qm, 0);
        }
        strcpy(&PATHB, "/tmp/regtest/registry/pkg");
        syscall(83, &PATHB, 493, 0, 0, 0, 0);   # mkdir(2)，已存在则忽略
        strcpy(&PATHB, "/tmp/regtest/registry");
        strcat(&PATHB, &SRBUF + slot * 65536 + 4);
        # 头里已有的 body 部分
        let have: i64 = n - bb - 4;
        if have < 0 { have = 0; }
        let ofd: i64 = fopen(&PATHB, 577, 438);
        if ofd < 0 { tcp_close(fd); return 0; }
        if have > 0 { syscall(1, ofd, &SRBUF + slot * 65536 + bb + 4, have, 0, 0, 0); }
        if cl > 65000 {   # FBUF[65536] 越界加固（v1.205.0）
            strcpy(&SFBUF + slot * 65536, "HTTP/1.0 413 Too Large\r\nContent-Length: 0\r\n\r\n");
            send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
            tcp_close(fd);
            return 0;
        }
        while have < cl {
            let room: i64 = 65000 - have;
            let want: i64 = 8192;
            if want > room { want = room; }
            let r: i64 = aio_recv(fd, &SFBUF + slot * 65536, want);
            if r <= 0 { break; }
            syscall(1, ofd, &SFBUF + slot * 65536, r, 0, 0, 0);
            have = have + r;
        }
        fclose(ofd);
        # 更新 index.txt：O_APPEND 追加一行（v1.203.0）
        let ifd: i64 = fopen("/tmp/regtest/registry/index.txt", 1601, 438);
        if ifd >= 0 {
            # 文件名（去 query）：从 RBUF+9（跳 "PUT /pkg/"）到 '?' 或 ' '
            let fn0: i64 = &SRBUF + slot * 65536 + 9;
            let fe0: i64 = fn0;
            while load8(fe0) != 0 && load8(fe0) != 63 && load8(fe0) != 32 { fe0 = fe0 + 1; }
            let fnlen: i64 = fe0 - fn0;
            let cp2: i64 = 0;
            while cp2 < fnlen { store8(&SFBUF + slot * 65536 + 500 + cp2, load8(fn0 + cp2)); cp2 = cp2 + 1; }
            store8(&SFBUF + slot * 65536 + 500 + fnlen, 0);
            # name/ver 从 query：?name=X&ver=Y
            let q: i64 = strstr(&SRBUF + slot * 65536 + 2000, "name=");
            let qv: i64 = strstr(&SRBUF + slot * 65536 + 2000, "ver=");
            if q >= 0 && qv >= 0 {
                strcpy(&SFBUF + slot * 65536 + 700, &SRBUF + slot * 65536 + 2000 + q + 5);
                # 截到 '&'
                let amp: i64 = strstr(&SFBUF + slot * 65536 + 700, "&");
                if amp >= 0 { store8(&SFBUF + slot * 65536 + 700 + amp, 0); }
                let vl: i64 = strlen(&SRBUF + slot * 65536 + 2000 + qv + 4);
                let ve0: i64 = &SRBUF + slot * 65536 + 2000 + qv + 4;
                let ve1: i64 = ve0;
                while load8(ve1) != 0 && load8(ve1) != 32 && load8(ve1) != 13 && load8(ve1) != 10 { ve1 = ve1 + 1; }
                store8(ve1, 0);
                strcat(&SFBUF + slot * 65536 + 700, "\t");
                strcat(&SFBUF + slot * 65536 + 700, ve0);
                strcat(&SFBUF + slot * 65536 + 700, "\t/tmp/regtest/registry/pkg/");
                strcat(&SFBUF + slot * 65536 + 700, &SFBUF + slot * 65536 + 500);
                store8(&SFBUF + slot * 65536 + 500, 0);
                strcpy(&SFBUF + slot * 65536 + 500, &SFBUF + slot * 65536 + 700);
            } else {
                strcat(&SFBUF + slot * 65536 + 500, "\t0.0.0\t/tmp/regtest/registry/pkg/");
                # 文件名再接一遍（无 query 兼容 curl 裸 PUT）
                let cp3: i64 = 0;
                while cp3 < fnlen { store8(&SFBUF + slot * 65536 + 600 + cp3, load8(fn0 + cp3)); cp3 = cp3 + 1; }
                store8(&SFBUF + slot * 65536 + 600 + fnlen, 0);
                strcat(&SFBUF + slot * 65536 + 500, &SFBUF + slot * 65536 + 600);
            }
            strcat(&SFBUF + slot * 65536 + 500, "\n");
            syscall(1, ifd, &SFBUF + slot * 65536 + 500, strlen(&SFBUF + slot * 65536 + 500), 0, 0, 0);
            fclose(ifd);
        }
        strcpy(&SFBUF + slot * 65536, "HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok");
        send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
        tcp_close(fd);
        return 0;
    }
    # 请求行：GET <path> HTTP/1.x
    if strstr(&SRBUF + slot * 65536, "GET ") != 0 { tcp_close(fd); return 0; }
    let sp1: i64 = 4;
    let sp2: i64 = strstr(&SRBUF + slot * 65536 + 4, " ");
    if sp2 < 0 { tcp_close(fd); return 0; }
    store8(&SRBUF + slot * 65536 + 4 + sp2, 0);
    strcpy(&PATHB, &SRBUF + slot * 65536 + 4);
    # /pkg/<file>
    if strstr(&PATHB, "/pkg/") == 0 {
        strcpy(&SFBUF + slot * 65536, "HTTP/1.0 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: ");
        # 读文件
        strcpy(&REGDIR, "/tmp/regtest/registry");
        # PATHB 形如 /pkg/deplib-1.0.0.tar.gz（可能有 query）
        let q: i64 = strstr(&PATHB, "?");
        if q >= 0 { store8(&PATHB + q, 0); }
        strcpy(&SRBUF + slot * 65536 + 2000, &REGDIR);
        strcat(&SRBUF + slot * 65536 + 2000, "/pkg");
        strcat(&SRBUF + slot * 65536 + 2000, &PATHB + 4);
        let fd2: i64 = fopen(&SRBUF + slot * 65536 + 2000, 0, 0);
        if fd2 < 0 {
            strcpy(&SFBUF + slot * 65536, "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
            tcp_close(fd);
            return 0;
        }
        let sz: i64 = 0;
        let r: i64 = 0;
        while sz < 60000 {
            r = syscall(0, fd2, &SFBUF + slot * 65536 + 200 + sz, 8192, 0, 0, 0);
            if r <= 0 { break; }
            sz = sz + r;
        }
        fclose(fd2);
        strcat_i64(&SFBUF + slot * 65536, sz);
        strcat(&SFBUF + slot * 65536, "\r\nConnection: close\r\n\r\n");
        send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
        if sz > 0 { send_all(fd, &SFBUF + slot * 65536 + 200, sz); }
        tcp_close(fd);
        return 0;
    }
    # /search（可带 ?kw= 子串过滤）
    if strstr(&PATHB, "/search") == 0 {
        strcpy(&SRBUF + slot * 65536 + 2000, "/tmp/regtest/registry/index.txt");
        let fd2: i64 = fopen(&SRBUF + slot * 65536 + 2000, 0, 0);
        if fd2 < 0 {
            strcpy(&SFBUF + slot * 65536, "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");
            send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
            tcp_close(fd);
            return 0;
        }
        let sz: i64 = 0;
        let r: i64 = 0;
        while sz < 60000 {
            r = syscall(0, fd2, &SFBUF + slot * 65536 + 200 + sz, 8192, 0, 0, 0);
            if r <= 0 { break; }
            sz = sz + r;
        }
        fclose(fd2);
        # kw 过滤：把 FBUF+200 缓冲按行过滤到 FBUF+32000
        let kw: i64 = strstr(&PATHB, "kw=");
        if kw >= 0 {
            store8(&PATHB + kw, 0);   # 临时截断 URL，kw 值从 kw+3 起（到行尾/空格）
            # 恢复：kw 值可能含空格前的截断——curl/客户端不会发空格，OK
            let src: i64 = &SFBUF + slot * 65536 + 200;
            let dst: i64 = &SFBUF + slot * 65536 + 32000;
            let sent: i64 = 0;
            let line: i64 = src;
            let se: i64 = src + sz;
            while line < se {
                # 行尾
                let le: i64 = line;
                while le < se && load8(le) != 10 { le = le + 1; }
                # 行内容 [line, le)（含尾 10 检查含 kw）
                let slen: i64 = le - line + 1;
                # 在行内找 kw（PATHB+kw 指向 'kw='，值 = +3）
                let hit: i64 = strstr(line, &PATHB + kw + 3);
                if hit >= 0 && hit < slen {
                    let cp: i64 = 0;
                    while cp < slen {
                        store8(dst + sent + cp, load8(line + cp));
                        cp = cp + 1;
                    }
                    sent = sent + slen;
                }
                line = le + 1;
            }
            sz = sent;
            strcpy(&SFBUF + slot * 65536 + 200, &SFBUF + slot * 65536 + 32000);
        }
        strcpy(&SFBUF + slot * 65536, "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ");
        strcat_i64(&SFBUF + slot * 65536, sz);
        strcat(&SFBUF + slot * 65536, "\r\nConnection: close\r\n\r\n");
        send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
        if sz > 0 { send_all(fd, &SFBUF + slot * 65536 + 200, sz); }
        tcp_close(fd);
        return 0;
    }
    strcpy(&SFBUF + slot * 65536, "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");
    send_all(fd, &SFBUF + slot * 65536, strlen(&SFBUF + slot * 65536));
    tcp_close(fd);
    return 0;
}

# v1.218：真并发 —— accept 协程 aio_accept 后每连接 csp_go(serve_csp, c|slot<<32)，
# serve_conn 内 IO 已 aio 化（aio_recv/aio_send park 让出 worker，不饿死）。
# fd 与槽号打包：fd 低 32 位、slot 高 32 位（csp_arg 单 i64）。
fn serve_csp() -> i64 {
    let a: i64 = csp_arg();
    let fd: i64 = a & 4294967295;
    let slot: i64 = a >> 32;
    serve_conn(fd, slot);
    # v1.222：循环消化 PENDING 队列 —— 一个协程服务多个连接，槽不再闲置
    while 1 {
        let c2: i64 = pend_pop();
        if c2 < 0 { break; }
        serve_conn(c2, slot);
    }
    return 0;
}

# v1.222：槽满排队 —— PENDING 环形队列（lf_cas 锁）暂存超槽连接；
# serve_csp 服务完当前连接后从队列取下一个，常驻消化，不再 503。
var PEND: [64] i64 = 0;
var PH: i64 = 0;
var PT: i64 = 0;
var PLK: i64 = 0;

fn pend_push(c: i64) -> i64 {
    while lf_cas(0, &PLK, 0, 1) != 1 { }
    let nt: i64 = PT + 1;
    if nt >= 64 { nt = 0; }
    if nt == PH {
        PLK = 0;
        return 0 - 1;
    }
    PEND[PT] = c;
    PT = nt;
    PLK = 0;
    return 0;
}

fn pend_pop() -> i64 {
    while lf_cas(0, &PLK, 0, 1) != 1 { }
    if PH == PT {
        PLK = 0;
        return 0 - 1;
    }
    let c: i64 = PEND[PH];
    PH = PH + 1;
    if PH >= 64 { PH = 0; }
    PLK = 0;
    return c;
}

fn serve_loop_aio() -> i64 {
    let next: i64 = 0;
    while 1 {
        let c: i64 = aio_accept(LFD);
        if c <= 0 { continue; }
        let gd: i64 = csp_go(&serve_csp, c + next * 4294967296);
        if gd < 0 {
            # v1.222：槽满入 PENDING 队列排队（serve_csp 空出来会来取），
            # 不再 503 —— 客户端无感，吞吐受 backlog+64 深度限制。
            if pend_push(c) < 0 {
                strcpy(&SFBUF, "HTTP/1.0 503 Busy\r\nContent-Length: 0\r\n\r\n");
                send_all(c, &SFBUF, strlen(&SFBUF));
                aio_close(c);
            }
        }
        next = next + 1;
        if next > 3 { next = 0; }
    }
    return 0;
}

fn main() -> i64 {
    heap_init();
    net_nosigpipe();
    aio_init();
    LFD = tcp_listen(PORT, 16);
    if LFD < 0 { print("listen fail\n"); return 1; }
    aio_nbio(LFD);
    print("regserver aio on 18900\n");
    csp_init(4);
    csp_go(&serve_loop_aio, 0);
    # main 空转让出（不抢 worker CPU）
    while 1 {
        usleep(100000);
    }
    return 0;
}
