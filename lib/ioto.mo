# ioto.mo —— 带**超时**的异步 I/O（select { I/O 就绪, 定时器 }）
#
# ── 它是什么 ────────────────────────────────────────────────
#   把"I/O 就绪"和"超时"都做成 channel，然后一个 select 二选一：
#       sel_case(ioch, 1, 0);
#       sel_case(tm_after(ms), 1, 0);
#       k = sel_go(0);          # 0 = 就绪，1 = 超时
#   这正是 Go 的 `select { case <-ch: case <-time.After(d): }`，
#   也就是 RFC 793 以来每个网络程序都需要的**读超时**。
#
# ── 为什么必须有 cancel ─────────────────────────────────────
#   两个分支只有一个会赢，赢的那个必须把输的那个**取消**：
#     · I/O 先就绪 → 定时器还在，到期后会往一个即将被别人复用的
#       channel 里投递 → **下一个请求一上来就"超时"**（幽灵超时）
#     · 超时先到   → fd 还留在 epoll 里、槽还占着 →
#       fd 号被复用后会收到别人的事件
#   两条都只在特定时序下发作，绝大多数请求完全正常 —— 正是最难查的一类。
#   详见 docs/ioto.md 的实测。
#
# ── 形态分布 ────────────────────────────────────────────────
#   Go          netpoller + time.After，语言级
#   Rust        tokio::time::timeout(...)，库级
#   C/C++       libuv / asio 的 deadline_timer；裸 epoll 要自己算
#   墨语言      reactor(lib/aio.mo) + 时间轮(lib/timer.mo) + select
#
# 🔴 已知限制
#   - 超时精度 = 时间轮 tick（16ms）
#   - I/O channel 池 32 个；并发 I/O 超过它会返回 -3 并置 IOTO_OVF
#     （响出来，不静默退化成阻塞）
#   - 一个 fd 同时只能有一个等待者（继承自 aio.mo）
#   - ms <= 0 表示**无限等待**（退化为不带超时的 aio_*）
#   - 必须 molink + libc

import "io.mo";
import "cstd.mo";
import "csp.mo";
import "select.mo";
import "timer.mo";
import "aio.mo";
import "thread.mo";
import "net.mo";

var IOTO_MAXC: i64 = 32;
var IOTO_PC: [32] i64 = 0;    # I/O channel 回收池
var IOTO_PN: i64 = 0;

var IOTO_OK: i64 = 0;         # 走"I/O 就绪"分支的次数
var IOTO_TO: i64 = 0;         # 走"超时"分支的次数
var IOTO_ARM: i64 = 0;        # arm 次数
var IOTO_ERR: i64 = 0;        # 出错次数
var IOTO_OVF: i64 = 0;        # channel 池耗尽次数（正常必须恒为 0）
var IOTO_DRN: i64 = 0;        # 取池时排空掉的残留值 —— 幽灵就绪的证据
var IOTO_PERR: i64 = 0;       # 最近一次错误码

# ------------------------------------------------------------------ channel 池
# 与 timer 的池同一个道理：channel 总数只有 64，用完就没了。
fn ioto_take() -> i64 {
    let c: i64 = 0;
    if IOTO_PN > 0 {
        IOTO_PN = IOTO_PN - 1;
        c = IOTO_PC[IOTO_PN];
        # 🔴 取出来也要排空：上一个用户可能在超时后没取走就绪值。
        #    留着它，这次 select 会在 arm 之前就"就绪"，
        #    表现为明明没数据却立刻返回 0 字节（假 EOF）。
        while chan_tryrecv(c) == 1 { IOTO_DRN = IOTO_DRN + 1; }
        return c;
    }
    c = chan_make(1);
    while chan_tryrecv(c) == 1 { IOTO_DRN = IOTO_DRN + 1; }
    return c;
}

fn ioto_give(c: i64) -> i64 {
    if c < 0 { return 0; }
    while chan_tryrecv(c) == 1 { IOTO_DRN = IOTO_DRN + 1; }
    IOTO_PC[IOTO_PN] = c;
    IOTO_PN = IOTO_PN + 1;
    return 0;
}

# ------------------------------------------------------------------ 等待原语
# 等到 fd 就绪或超时。返回 0 = 就绪；1 = 超时；负数 = 出错。
fn ioto_waitfd(fd: i64, ev: i64, ms: i64) -> i64 {
    let c: i64 = ioto_take();
    if c < 0 { IOTO_OVF = IOTO_OVF + 1; IOTO_PERR = 3; return 0 - 3; }
    if aio_arm(fd, ev, c) != 0 {
        ioto_give(c);
        IOTO_ERR = IOTO_ERR + 1;
        IOTO_PERR = 4;
        return 0 - 4;
    }
    IOTO_ARM = IOTO_ARM + 1;
    let t: i64 = tm_after(ms);
    if t < 0 {
        aio_disarm(fd);
        ioto_give(c);
        IOTO_ERR = IOTO_ERR + 1;
        IOTO_PERR = 5;
        return 0 - 5;
    }
    sel_reset();
    sel_case(c, 1, 0);
    sel_case(t, 1, 0);
    let k: i64 = sel_go(0);

    # 🔴 无论谁赢，都要把输的那一方清干净。
    #    · 不 disarm：fd 留在 epoll 里、槽还占着，fd 号复用后串事件
    #    · 不 cancel：定时器到期后往已归还池的 channel 里投递（幽灵超时）
    aio_disarm(fd);
    tm_cancel(t);
    ioto_give(c);

    if k == 0 { IOTO_OK = IOTO_OK + 1; return 0; }
    if k == 1 { IOTO_TO = IOTO_TO + 1; return 1; }
    IOTO_ERR = IOTO_ERR + 1;
    IOTO_PERR = 6;
    return 0 - 6;
}

# ------------------------------------------------------------------ 对外接口
# 返回值：>=0 读到的字节数（0 = 对端关闭）
#         -1 = 超时；其它负数 = 出错（见 IOTO_PERR）
fn ioto_recv(fd: i64, buf: i64, n: i64, ms: i64) -> i64 {
    let t0: i64 = clock_ms();
    let rem: i64 = ms;
    let r: i64 = 0;
    let w: i64 = 0;
    while 1 {
        r = syscall(0, fd, buf, n, 0, 0, 0);
        if r >= 0 { return r; }
        if r != 0 - EAGAIN { IOTO_PERR = 1; return r; }
        if ms <= 0 {
            if aio_wait(fd, 1) < 0 { IOTO_ERR = IOTO_ERR + 1; IOTO_PERR = 2; return 0 - 2; }
            continue;
        }
        rem = ms - (clock_ms() - t0);
        if rem <= 0 { IOTO_TO = IOTO_TO + 1; return 0 - 1; }
        w = ioto_waitfd(fd, 1, rem);
        if w == 1 { return 0 - 1; }
        if w < 0 { return w; }
    }
    return 0;
}

fn ioto_send(fd: i64, buf: i64, n: i64, ms: i64) -> i64 {
    let t0: i64 = clock_ms();
    let rem: i64 = ms;
    let off: i64 = 0;
    let r: i64 = 0;
    let w: i64 = 0;
    while off < n {
        r = syscall(1, fd, buf + off, n - off, 0, 0, 0);
        if r > 0 { off = off + r; continue; }
        if r != 0 - EAGAIN { IOTO_PERR = 1; return r; }
        if ms <= 0 {
            if aio_wait(fd, 4) < 0 { IOTO_ERR = IOTO_ERR + 1; IOTO_PERR = 2; return 0 - 2; }
            continue;
        }
        rem = ms - (clock_ms() - t0);
        if rem <= 0 { IOTO_TO = IOTO_TO + 1; return 0 - 1; }
        w = ioto_waitfd(fd, 4, rem);
        if w == 1 { return 0 - 1; }
        if w < 0 { return w; }
    }
    return off;
}

fn ioto_accept(fd: i64, ms: i64) -> i64 {
    let t0: i64 = clock_ms();
    let rem: i64 = ms;
    let c: i64 = 0;
    let w: i64 = 0;
    while 1 {
        c = syscall(43, fd, 0, 0, 0, 0, 0);
        if c >= 0 { aio_nbio(c); return c; }
        if c != 0 - EAGAIN { IOTO_PERR = 1; return c; }
        if ms <= 0 {
            if aio_wait(fd, 1) < 0 { IOTO_ERR = IOTO_ERR + 1; IOTO_PERR = 2; return 0 - 2; }
            continue;
        }
        rem = ms - (clock_ms() - t0);
        if rem <= 0 { IOTO_TO = IOTO_TO + 1; return 0 - 1; }
        w = ioto_waitfd(fd, 1, rem);
        if w == 1 { return 0 - 1; }
        if w < 0 { return w; }
    }
    return 0;
}
