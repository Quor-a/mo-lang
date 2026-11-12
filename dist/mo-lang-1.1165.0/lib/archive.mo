# archive —— tar 打包/解包 与 gzip（用墨语言自己写的）
#
# tar 是纯字节格式，gzip 的 stored 模式也是纯字节 + CRC32 ——
# 两者都不需要真正的压缩算法就能产出**标准工具能读**的文件：
#
#   tar 打包后 → 系统 tar 能解
#   gzip 后    → 系统 gunzip 能解
#
# 这是刻意的选择：优先保证「与现有生态互操作」，
# 而不是自己发明一个压缩格式（那会让产物没人能读）。
import "fs.mo";
import "str.mo";
import "crypto.mo";
import "io.mo";

var zeros: [512] byte = 0;   # 数据补齐必须用真零，不能拿头缓冲凑（会污染下一个头）
var TAR_CHK: i64 = 0;
var gz_buf: [65536] byte = 0;

# ---- 八进制字段写入（tar 头里数字都是八进制 ASCII）----
# 写 n 位宽的八进制数，前面补 '0'，最后一位是空格或 NUL
fn oct_field(buf: i64, off: i64, val: i64, width: i64) -> i64 {
    let i: i64 = width - 2;
    while i >= 0 {
        let d: i64 = val % 8;
        store8(buf + off + i, 48 + d);
        val = val / 8;
        i = i - 1;
    }
    store8(buf + off + width - 1, 32);   # 末位空格（tar 传统）
    return 0;
}

fn oct_read(buf: i64, off: i64, width: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while i < width {
        let c: i64 = load8(buf + off + i);
        if c < 48 { return v; }
        if c > 55 { return v; }
        v = v * 8 + (c - 48);
        i = i + 1;
    }
    return v;
}

# 头校验和：全部字节之和（chksum 字段按 8 个空格算）
fn tar_checksum(buf: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 512 {
        if i >= 148 {
            if i < 156 {
                s = s + 32;
            } else {
                s = s + load8(buf + i);
            }
        } else {
            s = s + load8(buf + i);
        }
        i = i + 1;
    }
    return s;
}

# 写一个 tar 头（512 字节）。size 为文件字节数
fn tar_hdr(buf: i64, name: i64, size: i64, mode: i64) -> i64 {
    let i: i64 = 0;
    while i < 512 { store8(buf + i, 0); i = i + 1; }
    strcpy(buf, name);
    oct_field(buf, 100, mode, 8);
    oct_field(buf, 108, 0, 8);      # uid
    oct_field(buf, 116, 0, 8);      # gid
    oct_field(buf, 124, size, 12);
    oct_field(buf, 136, 0, 12);     # mtime
    # 148..156 先填空格，算完校验和再覆盖
    i = 148;
    while i < 156 { store8(buf + i, 32); i = i + 1; }
    store8(buf + 156, 48);          # typeflag '0' = 普通文件
    strcpy(buf + 257, "ustar");
    store8(buf + 263, 48);
    # chksum 字段是 6 位八进制 + NUL + 空格（共 8 字节）。
    # 早先用 width=8 调用 oct_field，它写的是 7 位数字（148..154），
    # 又被我后面那句 store8(154, 0) 把最低位覆盖成 0 ——
    # 校验和凭空少一位，系统 tar 直接拒绝，报 "not a tar archive"。
    let c: i64 = tar_checksum(buf);
    oct_field(buf, 148, c, 7);
    store8(buf + 154, 0);
    store8(buf + 155, 32);
    return 512;
}

# 打包：把若干文件写进 tar。files 是路径数组，n 是个数
# 返回写入的字节数；失败返回负值
fn tar_pack(out: i64, files: i64, n: i64) -> i64 {
    let fd: i64 = fopen(out, 577, 420);
    if fd < 0 { return -1; }
    let hdr: [512] byte = 0;
    let body: [65536] byte = 0;
    let i: i64 = 0;
    while i < n {
        let path: i64 = load64(files + i * 8);
        let sz: i64 = read_file(path, &body, 65536);
        if sz < 0 { fclose(fd); return -2; }
        tar_hdr(&hdr, path, sz, 420);
        fwrite(fd, &hdr, 512);
        if sz > 0 { fwrite(fd, &body, sz); }
        # 数据补齐到 512 的倍数
        let pad: i64 = (512 - (sz & 511)) & 511;
        if pad > 0 { fwrite(fd, &zeros, pad); }
        i = i + 1;
    }
    # 结尾两个全零块
    let z: i64 = 0;
    while z < 512 { store8(&hdr + z, 0); z = z + 1; }
    fwrite(fd, &hdr, 512);
    fwrite(fd, &hdr, 512);
    fclose(fd);
    return 0;
}

# 解包：把 tar 里的文件提取到当前目录；返回提取个数
# ---------- v1.245 tar_unpack：typeflag/mode/目录支持（全局缓冲，清循环内 let） ----------
var TU_HDR: [512] byte = 0;
var TU_FD: i64 = 0;
var TU_CNT: i64 = 0;
var TU_N: i64 = 0;
var TU_SZ: i64 = 0;
var TU_REMAIN: i64 = 0;
var TU_OFD: i64 = 0;
var TU_CHUNK: i64 = 0;
var TU_M: i64 = 0;
var TU_PAD: i64 = 0;
var TU_MODE: i64 = 0;
var TU_TYPE: i64 = 0;

fn tar_unpack(path: i64) -> i64 {
    TU_FD = fopen(path, 0, 0);
    if TU_FD < 0 { return -1; }
    TU_CNT = 0;
    while 1 {
        TU_N = fread(TU_FD, &TU_HDR, 512);
        if TU_N < 512 { break; }
        if load8(&TU_HDR) == 0 { break; }
        TU_SZ = oct_read(&TU_HDR, 124, 12);
        TU_TYPE = load8(&TU_HDR + 156);      # typeflag：'0'/'\0'=文件 '5'=目录
        TU_MODE = oct_read(&TU_HDR, 100, 8); # "0000644\0"
        if TU_TYPE == 53 {                   # '5' 目录
            syscall(83, &TU_HDR, 493, 0, 0, 0, 0);   # mkdir（mo2x → mkdirat）
        } else {
            # mode：低 3 位八进制（7=755 之类）→ fopen mode 传 420(644) 或 493(755)
            let fmode: i64 = 420;
            if (TU_MODE & 17) != 0 { fmode = 493; }   # 位 0x11 = 用户/组执行位粗判
            TU_OFD = fopen(&TU_HDR, 577, fmode);
            if TU_OFD >= 0 {
                TU_REMAIN = TU_SZ;
                while TU_REMAIN > 0 {
                    TU_CHUNK = 65536;
                    if TU_REMAIN < TU_CHUNK { TU_CHUNK = TU_REMAIN; }
                    TU_M = fread(TU_FD, &gz_buf, TU_CHUNK);
                    if TU_M <= 0 { break; }
                    fwrite(TU_OFD, &gz_buf, TU_M);
                    TU_REMAIN = TU_REMAIN - TU_M;
                }
                fclose(TU_OFD);
            }
        }
        TU_PAD = (512 - (TU_SZ & 511)) & 511;
        if TU_PAD > 0 { fread(TU_FD, &gz_buf, TU_PAD); }
        TU_CNT = TU_CNT + 1;
    }
    fclose(TU_FD);
    return TU_CNT;
}

# 列出 tar 内容（打印名字与大小），返回条目数
fn tar_list(path: i64) -> i64 {
    let fd: i64 = fopen(path, 0, 0);
    if fd < 0 { return -1; }
    let hdr: [512] byte = 0;
    let cnt: i64 = 0;
    while 1 {
        let n: i64 = fread(fd, &hdr, 512);
        if n < 512 { break; }
        if load8(&hdr) == 0 { break; }
        let sz: i64 = oct_read(&hdr, 124, 12);
        print_i64(sz);
        print("  ");
        print(&hdr);
        print_nl();
        # 必须跳过「数据本身 + 补齐」，只跳补齐的话会停在数据中段，
        # 下一个头就读成零块（表现为只列出第一个文件）
        let skip: i64 = sz + ((512 - (sz & 511)) & 511);
        while skip > 0 {
            let chunk: i64 = 65536;
            if skip < chunk { chunk = skip; }
            fread(fd, &gz_buf, chunk);
            skip = skip - chunk;
        }
        cnt = cnt + 1;
    }
    fclose(fd);
    return cnt;
}

# ---- gzip：只实现 stored（不压缩）模式 ----
#
# 为什么不直接实现 deflate：deflate 需要 Huffman + LZ77，
# 单轮时间做不完且极易出错。stored 模式格式完全合法，
# 系统 gunzip 能正常解开 —— 互操作性优先，压缩率留待后续。
# gzip_file(src, dst)：v1.243 起统一走 fixed Huffman deflate（原 stored 版有
# 局部数组违禁隐患且压缩比 1:1）——直接委托 gzip_write。
fn gzip_file(src: i64, dst: i64) -> i64 {
    return gzip_write(src, dst);
}

# 解 gzip（只支持 stored 模式的数据块）
# ---------- v1.241 fixed-Huffman inflate ----------
var GZ_DAT: [65536] byte = 0;
var GZ_OUT: [131072] byte = 0;
var GZ_POS: i64 = 0;
var GZ_BIT: i64 = 0;
var GZ_OLEN: i64 = 0;
var GZ_N: i64 = 0;
# 长度 base/extra（idx 0..27 → 码 257..284，285 特判 258）
var GZ_LBASE: [29] i64 = 0;
var GZ_LEXTRA: [29] i64 = 0;
# 距离 base/extra（0..29）
var GZ_DBASE: [30] i64 = 0;
var GZ_DEXTRA: [30] i64 = 0;
var GZ_INIT: i64 = 0;

fn gz_setup() -> i64 {
    if GZ_INIT == 1 { return 0; }
    # 长度表
    GZ_LBASE[0] = 3;  GZ_LEXTRA[0] = 0;
    GZ_LBASE[1] = 4;  GZ_LEXTRA[1] = 0;
    GZ_LBASE[2] = 5;  GZ_LEXTRA[2] = 0;
    GZ_LBASE[3] = 6;  GZ_LEXTRA[3] = 0;
    GZ_LBASE[4] = 7;  GZ_LEXTRA[4] = 0;
    GZ_LBASE[5] = 8;  GZ_LEXTRA[5] = 0;
    GZ_LBASE[6] = 9;  GZ_LEXTRA[6] = 0;
    GZ_LBASE[7] = 10; GZ_LEXTRA[7] = 0;
    GZ_LBASE[8] = 11; GZ_LEXTRA[8] = 1;
    GZ_LBASE[9] = 13; GZ_LEXTRA[9] = 1;
    GZ_LBASE[10] = 15; GZ_LEXTRA[10] = 1;
    GZ_LBASE[11] = 17; GZ_LEXTRA[11] = 1;
    GZ_LBASE[12] = 19; GZ_LEXTRA[12] = 2;
    GZ_LBASE[13] = 23; GZ_LEXTRA[13] = 2;
    GZ_LBASE[14] = 27; GZ_LEXTRA[14] = 2;
    GZ_LBASE[15] = 31; GZ_LEXTRA[15] = 2;
    GZ_LBASE[16] = 35; GZ_LEXTRA[16] = 3;
    GZ_LBASE[17] = 43; GZ_LEXTRA[17] = 3;
    GZ_LBASE[18] = 51; GZ_LEXTRA[18] = 3;
    GZ_LBASE[19] = 59; GZ_LEXTRA[19] = 3;
    GZ_LBASE[20] = 67; GZ_LEXTRA[20] = 4;
    GZ_LBASE[21] = 83; GZ_LEXTRA[21] = 4;
    GZ_LBASE[22] = 99; GZ_LEXTRA[22] = 4;
    GZ_LBASE[23] = 115; GZ_LEXTRA[23] = 4;
    GZ_LBASE[24] = 131; GZ_LEXTRA[24] = 5;
    GZ_LBASE[25] = 163; GZ_LEXTRA[25] = 5;
    GZ_LBASE[26] = 195; GZ_LEXTRA[26] = 5;
    GZ_LBASE[27] = 227; GZ_LEXTRA[27] = 5;
    # 距离表
    GZ_DBASE[0] = 1; GZ_DEXTRA[0] = 0;
    GZ_DBASE[1] = 2; GZ_DEXTRA[1] = 0;
    GZ_DBASE[2] = 3; GZ_DEXTRA[2] = 0;
    GZ_DBASE[3] = 4; GZ_DEXTRA[3] = 0;
    GZ_DBASE[4] = 5; GZ_DEXTRA[4] = 1;
    GZ_DBASE[5] = 7; GZ_DEXTRA[5] = 1;
    GZ_DBASE[6] = 9; GZ_DEXTRA[6] = 2;
    GZ_DBASE[7] = 13; GZ_DEXTRA[7] = 2;
    GZ_DBASE[8] = 17; GZ_DEXTRA[8] = 3;
    GZ_DBASE[9] = 25; GZ_DEXTRA[9] = 3;
    GZ_DBASE[10] = 33; GZ_DEXTRA[10] = 4;
    GZ_DBASE[11] = 49; GZ_DEXTRA[11] = 4;
    GZ_DBASE[12] = 65; GZ_DEXTRA[12] = 5;
    GZ_DBASE[13] = 97; GZ_DEXTRA[13] = 5;
    GZ_DBASE[14] = 129; GZ_DEXTRA[14] = 6;
    GZ_DBASE[15] = 193; GZ_DEXTRA[15] = 6;
    GZ_DBASE[16] = 257; GZ_DEXTRA[16] = 7;
    GZ_DBASE[17] = 385; GZ_DEXTRA[17] = 7;
    GZ_DBASE[18] = 513; GZ_DEXTRA[18] = 8;
    GZ_DBASE[19] = 769; GZ_DEXTRA[19] = 8;
    GZ_DBASE[20] = 1025; GZ_DEXTRA[20] = 9;
    GZ_DBASE[21] = 1537; GZ_DEXTRA[21] = 9;
    GZ_DBASE[22] = 2049; GZ_DEXTRA[22] = 10;
    GZ_DBASE[23] = 3073; GZ_DEXTRA[23] = 10;
    GZ_DBASE[24] = 4097; GZ_DEXTRA[24] = 11;
    GZ_DBASE[25] = 6145; GZ_DEXTRA[25] = 11;
    GZ_DBASE[26] = 8193; GZ_DEXTRA[26] = 12;
    GZ_DBASE[27] = 12289; GZ_DEXTRA[27] = 12;
    GZ_DBASE[28] = 16385; GZ_DEXTRA[28] = 13;
    GZ_DBASE[29] = 24577; GZ_DEXTRA[29] = 13;
    GZ_INIT = 1;
    return 0;
}

# 读 n 位（LSB 优先）
var GZ_TB: i64 = 0;
var GZ_TB2: i64 = 0;

fn gz_bits(n: i64) -> i64 {
    let v: i64 = 0;
    let i: i64 = 0;
    while i < n {
        GZ_TB = load8(&GZ_DAT + GZ_POS);
        GZ_TB2 = (GZ_TB >> GZ_BIT) & 1;
        v = v + (GZ_TB2 << i);
        GZ_BIT = GZ_BIT + 1;
        if GZ_BIT == 8 { GZ_BIT = 0; GZ_POS = GZ_POS + 1; }
        i = i + 1;
    }
    return v;
}

# fixed 字面/长度码解码（Huffman 码 MSB 优先）。返 -1 = EOB/流尾。
fn gz_decode_lit() -> i64 {
    # 逐位构建 MSB 优先码值，按固定长度边界判定
    let code: i64 = 0;
    let len: i64 = 0;
    while len < 9 {
        code = code * 2 + gz_bits(1);
        len = len + 1;
        # 7 位段：256..279 → 0000000..0010111
        if len == 7 {
            if code < 24 { return 256 + code; }
        }
        # 8 位段：0..143(00110000..10111111) 与 280..287(11000000..11000111)
        if len == 8 {
            if code >= 48 {
                if code <= 191 { return code - 48; }
            }
            if code >= 192 {
                if code <= 199 { return 280 + code - 192; }
            }
        }
        # 9 位段：144..255 → 110010000..111111111
        if len == 9 {
            if code >= 400 { return 144 + code - 400; }
            return 0 - 1;   # 非法
        }
    }
    return 0 - 1;
}

# fixed 距离码：5 位 MSB 优先 → 码 0..29
fn gz_decode_dist() -> i64 {
    let code: i64 = 0;
    let i: i64 = 0;
    while i < 5 {
        code = code * 2 + gz_bits(1);
        i = i + 1;
    }
    if code > 29 { return 0 - 1; }
    return code;
}

# ---------- v1.241b dynamic Huffman ----------
var GZ_CLORD: [19] i64 = 0;   # 码长码顺序
var GZ_CLLEN: [19] i64 = 0;   # 码长码长
var GZ_LLEN: [288] i64 = 0;   # 字面码长
var GZ_DLEN: [30] i64 = 0;    # 距离码长
var GZ_HCNT: [16] i64 = 0;    # 每长度计数(复用)
var GZ_HNEXT: [16] i64 = 0;
var GZ_INIT2: i64 = 0;
var GZ_SYM2: i64 = 0;

fn gz_setup2() -> i64 {
    if GZ_INIT2 == 1 { return 0; }
    GZ_CLORD[0] = 16; GZ_CLORD[1] = 17; GZ_CLORD[2] = 18; GZ_CLORD[3] = 0;
    GZ_CLORD[4] = 8; GZ_CLORD[5] = 7; GZ_CLORD[6] = 9; GZ_CLORD[7] = 6;
    GZ_CLORD[8] = 10; GZ_CLORD[9] = 5; GZ_CLORD[10] = 11; GZ_CLORD[11] = 4;
    GZ_CLORD[12] = 12; GZ_CLORD[13] = 3; GZ_CLORD[14] = 13; GZ_CLORD[15] = 2;
    GZ_CLORD[16] = 14; GZ_CLORD[17] = 1; GZ_CLORD[18] = 15;
    GZ_INIT2 = 1;
    return 0;
}

# 规范哈夫曼解码:给 n 个 (len[i]) ,逐位扫。返 sym 或 -1。
var GZ_L: i64 = 0;
var GZ_WANT: i64 = 0;
var GZ_I2: i64 = 0;

fn gz_canon(lens: ptr, n: i64) -> i64 {
    let i: i64 = 0;
    while i < 16 { GZ_HCNT[i] = 0; i = i + 1; }
    i = 0;
    while i < n {
        GZ_L = load64(lens + i * 8);
        if GZ_L > 0 { GZ_HCNT[GZ_L] = GZ_HCNT[GZ_L] + 1; }
        i = i + 1;
    }
    # code = (code + count[len-1]) << 1
    let code: i64 = 0;
    let L2: i64 = 1;
    while L2 < 16 {
        code = (code + GZ_HCNT[L2 - 1]) << 1;
        GZ_HNEXT[L2] = code;
        L2 = L2 + 1;
    }
    # 解码:逐位,valid 范围 [next[len], next[len]+count[len])
    code = 0;
    let len2: i64 = 0;
    while len2 < 16 {
        code = code * 2 + gz_bits(1);
        len2 = len2 + 1;
        if code < GZ_HNEXT[len2] + GZ_HCNT[len2] {
            if code >= GZ_HNEXT[len2] {
                GZ_WANT = code - GZ_HNEXT[len2];
                GZ_I2 = 0;
                while GZ_I2 < n {
                    if load64(lens + GZ_I2 * 8) == len2 {
                        if GZ_WANT == 0 { return GZ_I2; }
                        GZ_WANT = GZ_WANT - 1;
                    }
                    GZ_I2 = GZ_I2 + 1;
                }
                return 0 - 1;
            }
        }
    }
    return 0 - 1;
}

fn gz_read_codes() -> i64 {
    gz_setup2();
    let hlit: i64 = gz_bits(5) + 257;
    let hdist: i64 = gz_bits(5) + 1;
    let hclen: i64 = gz_bits(4) + 4;
    let i: i64 = 0;
    while i < 19 { GZ_CLLEN[i] = 0; i = i + 1; }
    i = 0;
    while i < hclen {
        GZ_TB = GZ_CLORD[i];
        GZ_CLLEN[GZ_TB] = gz_bits(3);
        i = i + 1;
    }
    # 解码 hlit+hdist 个码长(带 16/17/18 RLE)
    let total: i64 = hlit + hdist;
    let idx: i64 = 0;
    # 先写进 LLEN(288 够 hlit+hdist? hlit≤288,hdist≤30 → 318>288!用 GZ_OUT 暂存区,后面解析)
    while idx < total {
        GZ_SYM2 = gz_canon(&GZ_CLLEN, 19);
        if GZ_SYM2 < 0 { return 0 - 1; }
        if GZ_SYM2 < 16 {
            store8(&GZ_OUT + idx, GZ_SYM2);
            idx = idx + 1;
        } else {
            if GZ_SYM2 == 16 {
                if idx == 0 { return 0 - 1; }
                GZ_L = load8(&GZ_OUT + idx - 1);
                GZ_I2 = 3 + gz_bits(2);
                GZ_TB2 = 0;
                while GZ_TB2 < GZ_I2 {
                    store8(&GZ_OUT + idx, GZ_L);
                    idx = idx + 1;
                    GZ_TB2 = GZ_TB2 + 1;
                }
            } else {
                if GZ_SYM2 == 17 {
                    GZ_I2 = 3 + gz_bits(3);
                    GZ_TB2 = 0;
                    while GZ_TB2 < GZ_I2 {
                        store8(&GZ_OUT + idx, 0);
                        idx = idx + 1;
                        GZ_TB2 = GZ_TB2 + 1;
                    }
                } else {
                    GZ_I2 = 11 + gz_bits(7);
                    GZ_TB2 = 0;
                    while GZ_TB2 < GZ_I2 {
                        store8(&GZ_OUT + idx, 0);
                        idx = idx + 1;
                        GZ_TB2 = GZ_TB2 + 1;
                    }
                }
            }
        }
    }
    # 拆:LLEN = GZ_OUT[0..hlit), DLEN = GZ_OUT[hlit..hlit+hdist)
    i = 0;
    while i < hlit { GZ_LLEN[i] = load8(&GZ_OUT + i); i = i + 1; }
    i = 0;
    while i < hdist { GZ_DLEN[i] = load8(&GZ_OUT + hlit + i); i = i + 1; }
    return 0;
}

var GZ_RN: i64 = 0;
var GZ_FLG: i64 = 0;
var GZ_P: i64 = 0;
var GZ_XL: i64 = 0;
var GZ_DI: i64 = 0;
var GZ_OUTFD: i64 = 0;
var GZ_BF: i64 = 0;
var GZ_BT: i64 = 0;
var GZ_LN: i64 = 0;
var GZ_FI: i64 = 0;
var GZ_FJ: i64 = 0;
var GZ_SYM: i64 = 0;
var GZ_LI: i64 = 0;
var GZ_LN2: i64 = 0;
var GZ_DC: i64 = 0;
var GZ_DIST: i64 = 0;
var GZ_I3: i64 = 0;

# ---------- v1.242 deflate 压缩（fixed Huffman,全字面） ----------
var GZW_OUT: [131072] byte = 0;
var GZW_LEN: i64 = 0;
var GZW_ACC: i64 = 0;      # 位累积器（LSB 先出）
var GZW_NB: i64 = 0;       # 已累积位数

# 写 n 位,value 的低位先出（gzip 位序）
fn gzw_bits(v: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if (v >> i) & 1 == 1 {
            GZW_ACC = GZW_ACC | (1 << GZW_NB);
        }
        GZW_NB = GZW_NB + 1;
        if GZW_NB == 8 {
            GZW_OUT[GZW_LEN] = GZW_ACC;
            GZW_LEN = GZW_LEN + 1;
            GZW_ACC = 0;
            GZW_NB = 0;
        }
        i = i + 1;
    }
    return 0;
}

# 写 Huffman 码（MSB 先出——decoders 端 code*2+bit,所以发送按 code 位从高到低）
fn gzw_code(code: i64, n: i64) -> i64 {
    let i: i64 = n - 1;
    while i >= 0 {
        gzw_bits((code >> i) & 1, 1);
        i = i - 1;
    }
    return 0;
}

# ---- v1.244 LZ77 匹配（hash 链 3 字节）----
var GZM_HEAD: [65536] i64 = 0;    # hash -> 最近位置（-1 空）
var GZM_PREV: [65536] i64 = 0;    # 位置 -> 前一同 hash 位置
var GZM_MINMATCH: i64 = 3;
var GZM_MAXMATCH: i64 = 258;
var GZM_WIN: i64 = 32768;
var GZM_NICE: i64 = 96;           # 找到即收的长度

# 值 -> 距离码（线性扫 base 表，从大到小）
fn gzm_dist_code(d: i64) -> i64 {
    let i: i64 = 29;
    while i >= 0 {
        if d >= GZ_DBASE[i] { return i; }
        i = i - 1;
    }
    return 0;
}

# 长度 -> 长度码（258 特判 285，3..257 线性从大到小）
fn gzm_len_code(l: i64) -> i64 {
    if l == 258 { return 28; }   # 表下标（符号 285 在主循环由 lc 推出）
    let i: i64 = 27;
    while i >= 0 {
        if l >= GZ_LBASE[i] { return i; }
        i = i - 1;
    }
    return 0;
}

# hash 3 字节
fn gzm_hash(p: i64) -> i64 {
    let a: i64 = load8(&gz_buf + p);
    let b: i64 = load8(&gz_buf + p + 1);
    let c: i64 = load8(&gz_buf + p + 2);
    return ((a * 33 + b) * 33 + c) & 65535;
}

# 找最长匹配（扫描 hash 链,最多 32 节点）。返长度,距离存 GZM_DIST;0=无匹配。
var GZM_DIST: i64 = 0;

fn gzm_find(pos: i64, n: i64) -> i64 {
    let h: i64 = gzm_hash(pos);
    let cand: i64 = GZM_HEAD[h];
    let best: i64 = 0;
    GZM_DIST = 0;
    let hops: i64 = 0;
    while cand >= 0 {
        if hops >= 32 { break; }
        hops = hops + 1;
        if cand >= pos { cand = GZM_PREV[cand & 65535]; continue; }   # 跳过自身
        if pos - cand > GZM_WIN { break; }
        # 比较长度
        let l: i64 = 0;
        let lim: i64 = n - pos;
        if lim > GZM_MAXMATCH { lim = GZM_MAXMATCH; }
        while l < lim {
            if load8(&gz_buf + cand + l) != load8(&gz_buf + pos + l) { break; }
            l = l + 1;
        }
        if l > best {
            best = l;
            GZM_DIST = pos - cand;
            if l >= GZM_NICE { break; }
        }
        cand = GZM_PREV[cand & 65535];
    }
    if best < GZM_MINMATCH { return 0; }
    return best;
}

# 登记位置进 hash 链
fn gzm_insert(pos: i64) -> i64 {
    let h: i64 = gzm_hash(pos);
    GZM_PREV[pos & 65535] = GZM_HEAD[h];
    GZM_HEAD[h] = pos;
    return 0;
}

# gzip_write(src_file, dst_file)：读 src → deflate(fixed,全字面) → gzip 容器写 dst。
#   返回 0 / 负错。输入 ≤ 130000 字节。
fn gzip_write(src: i64, dst: i64) -> i64 {
    if GZ_INIT == 0 { gz_setup(); }
    let n: i64 = read_file(src, &gz_buf, 65500);
    if n < 0 { return -1; }
    GZW_LEN = 0; GZW_ACC = 0; GZW_NB = 0;
    # gzip 头：1f 8b 08 00 00 00 00 00 00 03
    GZW_OUT[0] = 31; GZW_OUT[1] = 139; GZW_OUT[2] = 8; GZW_OUT[3] = 0;
    GZW_OUT[4] = 0; GZW_OUT[5] = 0; GZW_OUT[6] = 0; GZW_OUT[7] = 0;
    GZW_OUT[8] = 0; GZW_OUT[9] = 3;
    GZW_LEN = 10;
    # deflate 流：BFINAL=1 BTYPE=01(fixed)
    gzw_bits(1, 1);
    gzw_bits(1, 2);
    # hash 链清零（-1 空）
    let zi: i64 = 0;
    while zi < 65536 { GZM_HEAD[zi] = 0 - 1; GZM_PREV[zi] = 0 - 1; zi = zi + 1; }
    let i: i64 = 0;
    while i < n {
        # 登记前面 2 字节的 hash（窗口前进时逐个 insert）
        if i + 2 < n {
            # 找匹配
            let ml: i64 = 0;
            if i >= 3 {
                # 需要把 i-1 与 i-2 的 hash 插过——用惰性:每步插 i-3?简化:插 i(当前),找 i 时链里只有 <i
                ml = 0;
            }
            # 主路径:insert(i),find(i) 会在下一轮才命中——改为:先 find 再 insert
        }
        gzm_insert(i);
        let ml2: i64 = gzm_find(i, n);
        if ml2 == 0 {
            let sym: i64 = load8(&gz_buf + i);
            if sym < 144 {
                gzw_code(48 + sym, 8);
            } else {
                gzw_code(400 + sym - 144, 9);
            }
            i = i + 1;
        } else {
            # <长度,距离> 对
            let lc: i64 = gzm_len_code(ml2);
            # fixed 长度码:257..279 → 7 位码值=符号本身(0000001..0010111);280..287 → 8 位;
            # 280..287 8 位。lc 0..28 → 符号 257+lc
            let LSYM: i64 = 257 + lc;
            if LSYM < 280 {
                gzw_code(LSYM - 256, 7);
            } else {
                gzw_code(192 + LSYM - 280, 8);
            }
            # extra bits（长度）
            if GZ_LEXTRA[lc] > 0 {
                gzw_bits(ml2 - GZ_LBASE[lc], GZ_LEXTRA[lc]);
            }
            let dc: i64 = gzm_dist_code(GZM_DIST);
            gzw_code(dc, 5);
            if GZ_DEXTRA[dc] > 0 {
                gzw_bits(GZM_DIST - GZ_DBASE[dc], GZ_DEXTRA[dc]);
            }
            # 匹配内部位置全部 insert
            let k: i64 = 1;
            while k < ml2 {
                if i + k + 2 < n { gzm_insert(i + k); }
                k = k + 1;
            }
            i = i + ml2;
        }
    }
    # EOB（256 → 7 位码 0）
    gzw_code(0, 7);
    # 尾部补齐
    if GZW_NB > 0 {
        GZW_OUT[GZW_LEN] = GZW_ACC;
        GZW_LEN = GZW_LEN + 1;
        GZW_ACC = 0; GZW_NB = 0;
    }
    # 尾：CRC32(4) + isize(4)——先写 0 占位?gzip -d 会校验 CRC。mo 端 gunzip_file 不查 CRC ✓,
    # 但生态互操作(系统 gunzip)需要真 CRC。实现 CRC32:
    #   crc = crc ^ byte 表驱动
    let crc: i64 = 0 - 1;
    i = 0;
    while i < n {
        crc = crc ^ load8(&gz_buf + i);
        let k: i64 = 0;
        while k < 8 {
            let m: i64 = 0 - (crc & 1);
            # 🔴 >> 是 sar:负 crc 右移 bit31 补 1,CRC32 需要 0 —— & 0x7FFFFFFF 清位
            crc = ((crc >> 1) & 2147483647) ^ (m & 3988292384);
            k = k + 1;
        }
        i = i + 1;
    }
    crc = (crc ^ 0 - 1) & 4294967295;
    let isz: i64 = n;
    # 写 CRC32(LE)
    GZW_OUT[GZW_LEN] = crc & 255;
    GZW_OUT[GZW_LEN + 1] = (crc >> 8) & 255;
    GZW_OUT[GZW_LEN + 2] = (crc >> 16) & 255;
    GZW_OUT[GZW_LEN + 3] = (crc >> 24) & 255;
    GZW_OUT[GZW_LEN + 4] = isz & 255;
    GZW_OUT[GZW_LEN + 5] = (isz >> 8) & 255;
    GZW_OUT[GZW_LEN + 6] = (isz >> 16) & 255;
    GZW_OUT[GZW_LEN + 7] = (isz >> 24) & 255;
    GZW_LEN = GZW_LEN + 8;
    let out: i64 = fopen(dst, 577, 420);
    if out < 0 { return -2; }
    fwrite(out, &GZW_OUT, GZW_LEN);
    fclose(out);
    return 0;
}

fn gunzip_file(src: i64, dst: i64) -> i64 {
    GZ_RN = read_file(src, &gz_buf, 65536);
    if GZ_RN < 18 { return -1; }
    if load8(&gz_buf) != 31 { return -2; }
    if load8(&gz_buf + 1) != 139 { return -2; }
    # 复制进全局 inflate 输入（跳过 10 字节 gzip 头；FLG.FEXTRA/FNAME 可能在,
    # 简化:检查 FLG 低 3 位,有 FEXTRA/FNAME/FHCRC 则跳过 FNAME 的 \0 结尾）
    GZ_FLG = load8(&gz_buf + 3);
    GZ_P = 10;
    if (GZ_FLG & 4) != 0 {
        GZ_XL = load8(&gz_buf + GZ_P) + load8(&gz_buf + GZ_P + 1) * 256;
        GZ_P = GZ_P + 2 + GZ_XL;
    }
    if (GZ_FLG & 8) != 0 {
        while load8(&gz_buf + GZ_P) != 0 { GZ_P = GZ_P + 1; }
        GZ_P = GZ_P + 1;
    }
    if (GZ_FLG & 16) != 0 {
        while load8(&gz_buf + GZ_P) != 0 { GZ_P = GZ_P + 1; }
        GZ_P = GZ_P + 1;
    }
    if (GZ_FLG & 2) != 0 { GZ_P = GZ_P + 2; }
    gz_setup();
    GZ_POS = GZ_P; GZ_BIT = 0; GZ_OLEN = 0;
    # 读入数据段（n-8 尾:8= crc32+isize;够用即可,inflate 按 EOB 停）
    GZ_DI = 0;
    while GZ_DI < GZ_RN {
        GZ_DAT[GZ_DI] = load8(&gz_buf + GZ_DI);
        GZ_DI = GZ_DI + 1;
    }
    GZ_N = GZ_RN;
    GZ_OUTFD = fopen(dst, 577, 420);
    if GZ_OUTFD < 0 { return -3; }
    GZ_BF = 0;
    while GZ_BF == 0 {
        GZ_BF = gz_bits(1);
        GZ_BT = gz_bits(2);
        if GZ_BT == 0 {
            if GZ_BIT != 0 { GZ_BIT = 0; GZ_POS = GZ_POS + 1; }
            GZ_LN = load8(&GZ_DAT + GZ_POS) + load8(&GZ_DAT + GZ_POS + 1) * 256;
            GZ_POS = GZ_POS + 4;
            GZ_I2 = 0;
            while GZ_I2 < GZ_LN {
                GZ_OUT[GZ_OLEN] = load8(&GZ_DAT + GZ_POS);
                GZ_OLEN = GZ_OLEN + 1;
                GZ_POS = GZ_POS + 1;
                GZ_I2 = GZ_I2 + 1;
            }
        } else {
            if GZ_BT == 2 {
                if gz_read_codes() != 0 { fclose(GZ_OUTFD); return -8; }
            } else {
                if GZ_BT != 1 { fclose(GZ_OUTFD); return -4; }
                GZ_FI = 0;
                while GZ_FI < 288 {
                    if GZ_FI < 144 { GZ_LLEN[GZ_FI] = 8; } else {
                        if GZ_FI < 256 { GZ_LLEN[GZ_FI] = 9; } else {
                            if GZ_FI < 280 { GZ_LLEN[GZ_FI] = 7; } else { GZ_LLEN[GZ_FI] = 8; }
                        }
                    }
                    GZ_FI = GZ_FI + 1;
                }
                GZ_FJ = 0;
                while GZ_FJ < 30 { GZ_DLEN[GZ_FJ] = 5; GZ_FJ = GZ_FJ + 1; }
            }
            GZ_SYM = gz_canon(&GZ_LLEN, 288);
            while GZ_SYM >= 0 {
                if GZ_SYM < 256 {
                    GZ_OUT[GZ_OLEN] = GZ_SYM;
                    GZ_OLEN = GZ_OLEN + 1;
                } else {
                    if GZ_SYM == 256 { GZ_SYM = 0 - 2; break; }
                    GZ_LI = GZ_SYM - 257;
                    if GZ_LI > 28 { fclose(GZ_OUTFD); return -5; }
                    GZ_LN2 = GZ_LBASE[GZ_LI] + gz_bits(GZ_LEXTRA[GZ_LI]);
                    if GZ_SYM == 285 { GZ_LN2 = 258; }
                    GZ_DC = gz_canon(&GZ_DLEN, 30);
                    if GZ_DC < 0 { fclose(GZ_OUTFD); return -6; }
                    GZ_DIST = GZ_DBASE[GZ_DC] + gz_bits(GZ_DEXTRA[GZ_DC]);
                    GZ_I3 = 0;
                    while GZ_I3 < GZ_LN2 {
                        GZ_OUT[GZ_OLEN] = load8(&GZ_OUT + GZ_OLEN - GZ_DIST);
                        GZ_OLEN = GZ_OLEN + 1;
                        GZ_I3 = GZ_I3 + 1;
                    }
                }
                GZ_SYM = gz_canon(&GZ_LLEN, 288);
                if GZ_SYM == 0 - 1 { break; }
            }
            if GZ_SYM == 0 - 1 { fclose(GZ_OUTFD); return -7; }
        }
    }
    fwrite(GZ_OUTFD, &GZ_OUT, GZ_OLEN);
    fclose(GZ_OUTFD);
    return 0;
}
