# wavinfo —— 解析 WAV 文件头并打印信息
#
#   ./wavinfo <file.wav>
#
# 为什么写它：这是 lib/pack.mo 的**实战验证**。
# WAV 是一个真实的二进制格式，字段是小端、定长、有 chunk 嵌套——
# 正好是"没有 pack 就只能手拼 load8，还容易把字节序写反"的那类活。
#
# 顺带它也验证了 lib/err.mo：读不到文件、魔数不对、chunk 截断，
# 三种情况都要给出**具体**原因，而不是一句 "error"。
import "io.mo";
import "str.mo";
import "fs.mo";
import "pack.mo";
import "dir.mo";   # exists()
import "err.mo";

var BUF: [65536] byte = 0;
var FSIZE: i64 = 0;      # 磁盘上的真实大小（stat 取）
var NREAD: i64 = 0;      # 实际读进缓冲的字节数（受缓冲容量限制）
var HEAD_CAP: i64 = 65535;

# ---- WAV 头字段 ----
var AUDIO_FMT: i64 = 0;
var CHANNELS: i64 = 0;
var RATE: i64 = 0;
var BYTERATE: i64 = 0;
var BLOCKALIGN: i64 = 0;
var BITS: i64 = 0;
var DATA_OFF: i64 = 0;
var DATA_LEN: i64 = 0;

fn die_at(msg: i64, code: i64, where: i64) -> i64 {
    err_set(code, msg, where);
    err_print();
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}

# 校验 4 字节标记
fn tag_eq(p: i64, t: i64) -> i64 {
    if memcmp(p, t, 4) == 0 { return 1; }
    return 0;
}

# 遍历 chunk。返回 0 表示成功。
# 这里最能体现 pack 的价值：chunk 头就是 id(4) + size(u32 LE)，
# 一行 unpack_u32le 搞定，不用手拼四个 load8。
fn walk() -> i64 {
    if tag_eq(&BUF, "RIFF") == 0 {
        return err_wrap(E_FORMAT, "not a RIFF file", "walk");
    }
    if tag_eq(&BUF + 8, "WAVE") == 0 {
        return err_wrap(E_FORMAT, "not a WAVE file", "walk");
    }
    let riff_size: i64 = unpack_u32le(&BUF + 4);
    if riff_size + 8 > FSIZE {
        # 截断文件：声明的 size 比实际文件还大
        return err_wrap(E_RANGE, "RIFF size exceeds file size (truncated?)", "walk");
    }
    let p: i64 = 12;
    # 用 NREAD 而不是 FSIZE 限制循环：只解析缓冲里能看到的 chunk 头。
    # 用 FSIZE 校验长度：文件大小是真实的，与读进来多少无关。
    while p + 8 <= NREAD {
        let size: i64 = unpack_u32le(&BUF + p + 4);
        if p + 8 + size > FSIZE {
            return err_wrap(E_RANGE, "chunk exceeds file size (truncated?)", "walk");
        }
        if tag_eq(&BUF + p, "fmt ") == 1 {
            if size < 16 {
                return err_wrap(E_FORMAT, "fmt chunk too small", "walk");
            }
            let f: i64 = &BUF + p + 8;
            AUDIO_FMT = unpack_u16le(f);
            CHANNELS = unpack_u16le(f + 2);
            RATE = unpack_u32le(f + 4);
            BYTERATE = unpack_u32le(f + 8);
            BLOCKALIGN = unpack_u16le(f + 12);
            BITS = unpack_u16le(f + 14);
        }
        if tag_eq(&BUF + p, "data") == 1 {
            DATA_OFF = p + 8;
            DATA_LEN = size;
        }
        # chunk 数据按 2 字节对齐：奇数长度要跳过 1 个填充字节。
        # 少了这一步，遇到奇数长度 chunk 就会把填充字节当成下一个 chunk id。
        p = p + 8 + size;
        if (size & 1) == 1 { p = p + 1; }
    }
    if RATE == 0 {
        return err_wrap(E_FORMAT, "no fmt chunk found", "walk");
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: wavinfo <file.wav>\n");
        return 2;
    }
    heap_init();
    err_clear();

    let path: i64 = argv(1);
    # 先取真实大小：解析头部不需要整个文件，但校验需要知道它有多大
    let real: i64 = stat_size(path);
    if real <= 0 {
        if exists(path) == 0 {
            return die_at("no such file", E_FOUND, "stat_size");
        }
        return die_at("cannot stat file", E_IO, "stat_size");
    }
    FSIZE = real;

    let n: i64 = read_file(path, &BUF, HEAD_CAP);
    if n < 0 {
        # 区分"文件不存在"和"读失败"：errno 不同，给的信息也不同
        if exists(path) == 0 {
            return die_at("no such file", E_FOUND, "read_file");
        }
        return die_at("cannot read file", E_IO, "read_file");
    }
    store8(&BUF + n, 0);
    NREAD = n;

    if walk() < 0 {
        err_print();
        return 1;
    }

    print("file      : ");
    print(path);
    print_nl();
    print("size      : ");
    print_i64(FSIZE);
    print(" bytes");
    print_nl();

    print("format    : ");
    if AUDIO_FMT == 1 { print("PCM"); }
    else {
        if AUDIO_FMT == 3 { print("IEEE float"); }
        else {
            if AUDIO_FMT == 6 { print("A-law"); }
            else {
                if AUDIO_FMT == 7 { print("mu-law"); }
                else { print("unknown ("); print_i64(AUDIO_FMT); print(")"); }
            }
        }
    }
    print_nl();

    print("channels  : ");
    print_i64(CHANNELS);
    print_nl();
    print("rate      : ");
    print_i64(RATE);
    print(" Hz");
    print_nl();
    print("bits      : ");
    print_i64(BITS);
    print("-bit");
    print_nl();
    print("byterate  : ");
    print_i64(BYTERATE);
    print(" B/s");
    print_nl();

    if DATA_LEN > 0 {
        # 时长 = 数据字节数 / 每秒字节数。整数除法会截断，
        # 所以先算秒再算百分秒，避免浮点。
        print("data      : ");
        print_i64(DATA_LEN);
        print(" bytes @ offset ");
        print_i64(DATA_OFF);
        print_nl();
        if BYTERATE > 0 {
            let sec: i64 = DATA_LEN / BYTERATE;
            let rem: i64 = DATA_LEN - sec * BYTERATE;
            let cs: i64 = rem * 100 / BYTERATE;
            print("duration  : ");
            print_i64(sec);
            print(".");
            if cs < 10 { print("0"); }
            print_i64(cs);
            print(" s");
            print_nl();
        }
    } else {
        print("data      : (empty)\n");
    }
    return 0;
}
