# wavobj —— 用**类**封装 WAV 头（wavinfo.mo 的面向对象版）
#
#   ./wavobj <file.wav>
#
# 为什么写它：wavinfo.mo 用 8 个全局变量存头字段，字段之间没有任何
# 联系，读起来靠命名约定（CHANNELS / RATE / BITS ...）才看得出是一组。
#
# 这里改成 class Wav + 方法：
#     w.parse(path);
#     w.describe(&OUT);
#
# 这是方法语法 obj.method() 的**实战检验** —— 单元测试只能证明它能跑，
# 只有写真实程序才知道好不好用。
import "io.mo";
import "str.mo";
import "fs.mo";
import "pack.mo";
import "dir.mo";   # exists()
import "err.mo";

var BUF: [65536] byte = 0;
var OUT: [4096] byte = 0;
var NREAD: i64 = 0;
var HEAD_CAP: i64 = 65535;

class Wav {
    fmt: i64;
    channels: i64;
    rate: i64;
    byterate: i64;
    blockalign: i64;
    bits: i64;
    data_off: i64;
    data_len: i64;
    fsize: i64;
}

# 解析。返回 0 成功，负数失败（错误已进 err.mo）。
fn Wav_parse(self: Wav, path: ptr) -> i64 {
    let real: i64 = stat_size(path);
    if real <= 0 {
        if exists(path) == 0 { return err_wrap(E_FOUND, "no such file", "Wav_parse"); }
        return err_wrap(E_IO, "cannot stat file", "Wav_parse");
    }
    self.fsize = real;

    let n: i64 = read_file(path, &BUF, HEAD_CAP);
    if n < 0 {
        if exists(path) == 0 { return err_wrap(E_FOUND, "no such file", "Wav_parse"); }
        return err_wrap(E_IO, "cannot read file", "Wav_parse");
    }
    store8(&BUF + n, 0);
    NREAD = n;

    if memcmp(&BUF, "RIFF", 4) != 0 { return err_wrap(E_FORMAT, "not a RIFF file", "Wav_parse"); }
    if memcmp(&BUF + 8, "WAVE", 4) != 0 { return err_wrap(E_FORMAT, "not a WAVE file", "Wav_parse"); }
    let riff_size: i64 = unpack_u32le(&BUF + 4);
    if riff_size + 8 > self.fsize {
        return err_wrap(E_RANGE, "RIFF size exceeds file size (truncated?)", "Wav_parse");
    }

    let p: i64 = 12;
    while p + 8 <= NREAD {
        let size: i64 = unpack_u32le(&BUF + p + 4);
        if p + 8 + size > self.fsize {
            return err_wrap(E_RANGE, "chunk exceeds file size (truncated?)", "Wav_parse");
        }
        if memcmp(&BUF + p, "fmt ", 4) == 0 {
            if size < 16 { return err_wrap(E_FORMAT, "fmt chunk too small", "Wav_parse"); }
            let f: i64 = &BUF + p + 8;
            self.fmt        = unpack_u16le(f);
            self.channels   = unpack_u16le(f + 2);
            self.rate       = unpack_u32le(f + 4);
            self.byterate   = unpack_u32le(f + 8);
            self.blockalign = unpack_u16le(f + 12);
            self.bits       = unpack_u16le(f + 14);
        }
        if memcmp(&BUF + p, "data", 4) == 0 {
            self.data_off = p + 8;
            self.data_len = size;
        }
        # chunk 按 2 字节对齐：奇数长度要跳过 1 个填充字节
        p = p + 8 + size;
        if (size & 1) == 1 { p = p + 1; }
    }
    if self.rate == 0 { return err_wrap(E_FORMAT, "no fmt chunk found", "Wav_parse"); }
    return 0;
}

# 时长，单位**百分秒**（避免浮点）。byterate 为 0 时返回 -1。
fn Wav_duration_cs(self: Wav) -> i64 {
    if self.byterate <= 0 { return 0 - 1; }
    if self.data_len <= 0 { return 0 - 1; }
    let sec: i64 = self.data_len / self.byterate;
    let rem: i64 = self.data_len - sec * self.byterate;
    return sec * 100 + rem * 100 / self.byterate;
}

fn fmt_name(c: i64) -> i64 {
    if c == 1 { return "PCM"; }
    if c == 3 { return "IEEE float"; }
    if c == 6 { return "A-law"; }
    if c == 7 { return "mu-law"; }
    return "unknown";
}

# 用 sfmt 一次性拼好整段描述 —— 这正是 sfmt 存在的理由。
fn Wav_describe(self: Wav, dst: ptr) -> i64 {
    sfmt(dst, f"size      : {self.fsize} bytes\n");
    sfmt(dst, f"format    : {ptr(fmt_name(self.fmt))}\n");
    sfmt(dst, f"channels  : {self.channels}\n");
    sfmt(dst, f"rate      : {self.rate} Hz\n");
    sfmt(dst, f"bits      : {self.bits}-bit\n");
    sfmt(dst, f"byterate  : {self.byterate} B/s\n");
    if self.data_len > 0 {
        sfmt(dst, f"data      : {self.data_len} bytes @ offset {self.data_off}\n");
        let d: i64 = self.duration_cs();
        if d >= 0 {
            let cs: i64 = d - (d / 100) * 100;
            # 补零：`1.0 s` 看着像 1 秒 0 分，实际是 1.00 秒
            if cs < 10 { sfmt(dst, f"duration  : {d / 100}.0{cs} s\n"); }
            else { sfmt(dst, f"duration  : {d / 100}.{cs} s\n"); }
        }
    } else {
        strcat(dst, "data      : (empty)\n");
    }
    return 0;
}

fn main() -> i64 {
    if argc() < 2 {
        print("usage: wavobj <file.wav>\n");
        return 2;
    }
    heap_init();
    err_clear();

    let w: Wav;
    # 方法调用在 **if 条件里**（表达式位置）—— 返回值可直接判断
    if w.parse(argv(1)) < 0 {
        err_print();
        return 1;
    }
    sfmt(&OUT, f"file      : {ptr(argv(1))}\n");
    w.describe(&OUT + strlen(&OUT));
    print(&OUT);
    return 0;
}
