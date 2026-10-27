# aio.mo —— 异步 I/O：epoll reactor 驱动 CSP 协程
#
# 概念：Reactor 模式 + 协程（Schmidt / "reactor vs proactor"）。
# 主流形态是 Go 的 netpoller、Rust tokio、Node 的 libuv —— 都是
# 「I/O 就绪通知 + 用户态调度」。本库把它接到 lib/csp.mo 的 ucontext
# 协程上：协程里写阻塞式代码，底层不阻塞线程。
#
# 为什么必须有它：csp 的协程绑死在 worker 上（uc_link 写死调度上下文），
# 任何一个协程做阻塞 read()，整个 worker 连同它上面**所有**协程一起卡住。
# 有协程没 reactor，等于没有并发。
#
# 设计：
#   - 一个**专用 poller 线程**跑 epoll_wait（不占 csp worker，也不改
#     csp_loop 的死锁检测逻辑）
#   - 协程在 I/O 未就绪时 aio_wait() → 注册 fd → csp_park() 挂起
#   - poller 收到就绪事件 → csp_enq(slot) 把协程还给它的 worker
#   - EPOLLONESHOT：事件只投递一次，避免"协程已取走但 epoll 仍报就绪"
#     导致 poller 100% CPU 空转
#
# 需要链接 libc + pthread（thread_create / mutex_*）：
#   ./bin/moc prog.mo -c prog.o && bash tools/molink.sh prog.o -o prog
#
# 🔴 已知限制
#   - 一个 fd 同时只允许**一个**协程等待（注册以 fd 为键）。多协程等同一
#     fd 会返回 -2 并置 AIO_PERR=1。服务场景（一连接一协程）够用。
#   - 最多 128 个并发等待者。
#   - 只做 read/write/accept；connect 仍是阻塞的。

import "io.mo";
import "csp.mo";
import "thread.mo";
import "net.mo";

# ------------------------------------------------------------------ 常量
var EPOLLIN: i64 = 1;
var EPOLLOUT: i64 = 4;
var EPOLLONESHOT: i64 = 1073741824;   # 0x40000000
var EPOLL_CTL_ADD: i64 = 1;
var EPOLL_CTL_DEL: i64 = 2;
var EPOLL_CTL_MOD: i64 = 3;
var O_NONBLOCK: i64 = 2048;           # 0x800
var F_GETFL: i64 = 3;
var F_SETFL: i64 = 4;
var EAGAIN: i64 = 11;

var AIO_MAXW: i64 = 128;
var AIO_MAXEV: i64 = 128;

# ------------------------------------------------------------------ 状态
var AIO_EP: i64 = 0;
var AIO_ON: i64 = 0;
var AIO_TID: i64 = 0;
var AIO_N: i64 = 0;          # 当前等待者数
var AIO_WOKE: i64 = 0;       # 累计唤醒次数
var AIO_PERR: i64 = 0;
var AIO_TICK: i64 = 0;     # 诊断：poller 循环次数（心跳）
var AIO_NEV: i64 = 0;      # 诊断：累计收到事件数
var AIO_SKP: i64 = 0;      # 诊断：被跳过的事件数（代次不符 / 已释放）
var AIO_EVFD: i64 = 0;
var AIO_BAD: i64 = 0;
var AIO_D0: i64 = 0;
var AIO_D1: i64 = 0; # 诊断：最近一次收到事件的 fd       # 最近一次错误码（诊断用，0 = 无）
var AIO_INIT: i64 = 0;

var AIO_FD: [128] i64 = 0;
var AIO_SL: [128] i64 = 0;
var AIO_EV: [128] i64 = 0;
# v1.127：就绪通知的**目标 channel**。-1 = 旧模式（直接 enq 协程）；
# >=0 = channel 模式，就绪时 trysend 到该 channel。
# 有它才能把"I/O 就绪"和"超时"放进同一个 select —— 带超时的 I/O
# 本质上就是两个 channel 二选一。
var AIO_CH: [128] i64 = 0;
var AIO_GEN: [128] i64 = 0;   # 代次：防止复用槽位时误认旧事件
var AIO_USED: [128] i64 = 0;
var AIO_REG: [128] i64 = 0;   # 该 fd 是否已在 epoll 中
# 🔴 v1.124：等待者表**必须**加锁。两个 worker 线程上的协程会并发调用
#    aio_wait，无锁时会分到**同一个**空闲槽 —— 后写的把先写的覆盖掉，
#    前一个协程就此"带着没有槽的 park"永久挂起（实测 pk = wk + 1 且无槽）。
var AIO_LK: [8] i64 = 0;      # 保护上面整张表
var AIO_EVS: [256] i64 = 0;   # 128 * 16 字节

# ------------------------------------------------------------------ epoll 原语
var AIO_EE: [2] i64 = 0;   # 🔴 v1.218：局部数组违禁（events 掩码变垃圾 → ADD 注册成
                           #    events=0 的死项，epoll_wait 永不报）—— 改全局。
fn aio_ctl(op: i64, fd: i64, ev: i64, data: i64) -> i64 {
    # 🔴 v1.221：AIO_EE 是全局（局部数组违禁），但 aio_ctl 会被多协程
    #    并发调用（aio_wait 注册 vs fire 的 DEL/重挂）——无锁则 events/data
    #    混写 → epoll 注册损坏 → 服务瘫。mutex 保护短临界区。
    AIO_EE[0] = ev;
    AIO_EE[1] = data;
    return syscall(233, AIO_EP, op, fd, &AIO_EE, 0, 0);
}

fn epoll_create1() -> i64 {
    return syscall(291, 0, 0, 0, 0, 0, 0);
}

# 把 fd 设为非阻塞。🔴 不做这一步的话 read() 会真的阻塞住整个线程，
# reactor 完全失效，而且**不报错** —— 只是并发度悄悄退回 1。
fn aio_nbio(fd: i64) -> i64 {
    let fl: i64 = syscall(72, fd, F_GETFL, 0, 0, 0, 0);
    if fl < 0 { return 0 - 1; }
    let r: i64 = syscall(72, fd, F_SETFL, fl | O_NONBLOCK, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    return 0;
}

# ------------------------------------------------------------------ 注册 / 等待
# 在协程内调用：把 fd 注册进 epoll 并挂起，直到就绪被唤醒。
# 返回 0 = 被就绪事件唤醒；负数 = 出错（见 AIO_PERR）。
fn aio_wait(fd: i64, ev: i64) -> i64 {
    if AIO_INIT != 1 { AIO_PERR = 9; return 0 - 1; }
    let s: i64 = csp_self();
    if s < 0 { AIO_PERR = 8; return 0 - 1; }

    mutex_lock(&AIO_LK);

    # 找本协程已有的等待槽；顺带检查有没有别的协程占着同一个 fd
    let i: i64 = 0 - 1;
    let k: i64 = 0;
    while k < AIO_MAXW {
        if AIO_USED[k] == 1 {
            if AIO_SL[k] == s { i = k; }
            if AIO_FD[k] == fd {
                if AIO_SL[k] != s { mutex_unlock(&AIO_LK); AIO_PERR = 1; return 0 - 2; }
            }
        }
        k = k + 1;
    }
    if i < 0 {
        k = 0;
        while k < AIO_MAXW {
            if AIO_USED[k] == 0 { if i < 0 { i = k; } }
            k = k + 1;
        }
    }
    if i < 0 { mutex_unlock(&AIO_LK); AIO_PERR = 2; return 0 - 3; }

    AIO_USED[i] = 1;
    AIO_FD[i] = fd;
    AIO_SL[i] = s;
    AIO_EV[i] = ev;
    AIO_CH[i] = 0 - 1;

    # data 放 fd（理由见 aio_fire）；电平触发，不用 EPOLLONESHOT
    let r: i64 = aio_ctl(EPOLL_CTL_MOD, fd, ev, fd);
    if r < 0 { r = aio_ctl(EPOLL_CTL_ADD, fd, ev, fd); }
    if r < 0 {
        AIO_USED[i] = 0;
        mutex_unlock(&AIO_LK);
        AIO_PERR = 3;
        return 0 - 4;
    }
    AIO_REG[i] = 1;
    AIO_N = AIO_N + 1;

    # 🔴 宣告"我即将挂起"，且必须在**锁内**、在真正 park 之前。
    #    锁把 aio_fire 的扫描整个挡在外面，于是 poller 不可能看到
    #    "槽已设置但协程还没挂起"这个中间态 —— 要么槽还没建（事件被当
    #    SKP，LT 下下次还会报），要么 ST 已是 7（直接入队唤醒）。
    #    这条顺序把"事件先于 park 到达"的漏唤醒窗口彻底关掉。
    CSP_ST[s] = 7;
    mutex_unlock(&AIO_LK);

    csp_park();
    return 0;
}

# ------------------------------------------------------------------ poller
var AIO_WQ: [128] i64 = 0;   # 🔴 v1.218：fire 局部数组违禁 → 全局（poller 线程独占）
var AIO_CQ: [128] i64 = 0;
fn aio_fire(n: i64) -> i64 {
    # 待唤醒的协程（锁外再入队）；待投递的 channel
    let wn: i64 = 0;
    let cn: i64 = 0;
    let rearm: i64 = 0;
    let k: i64 = 0;
    while k < n {
        # data 字段放 fd（epoll_data.fd 惯用法），读回时**只取低 32 位**：
        #    实测高 4 字节会带垃圾（读到过 2^32+1）。
        # 电平触发，不用 EPOLLONESHOT：ONESHOT 漏处理一次 = 该 fd 永不再报，
        #    协程永久挂起且不报错。LT 下漏处理无害，靠"收到就 DEL"压住空转。
        let fd: i64 = AIO_EVS[k * 2 + 1] & 4294967295;
        AIO_EVFD = fd;
        let hit: i64 = 0;
        mutex_lock(&AIO_LK);
        let j: i64 = 0;
        while j < AIO_MAXW {
            if AIO_USED[j] == 1 {
                if AIO_FD[j] == fd {
                    hit = 1;
                    let s: i64 = AIO_SL[j];
                    AIO_REG[j] = 0;
                    AIO_USED[j] = 0;
                    AIO_N = AIO_N - 1;
                    AIO_WOKE = AIO_WOKE + 1;
                    if AIO_CH[j] >= 0 {
                        # channel 模式：投递到 channel，由它去唤醒 select。
                        # 🔴 必须在**锁内**完成投递（与 timer 的 chan_trysend
                        #    同理）：放到锁外的话，disarm 可能在"已摘槽但还没
                        #    send"之间抢到锁并把 channel 归还池，这次 send
                        #    就会落进一个已被别人复用的 channel。
                        let rc: i64 = chan_trysend(AIO_CH[j], 1);
                        if rc < 1 { AIO_PERR = 11; }
                    } else {
                        if CSP_ST[s] == 7 {
                            CSP_ST[s] = 2;
                            AIO_WQ[wn] = s;
                            wn = wn + 1;
                            aio_ctl(EPOLL_CTL_DEL, fd, 0, 0);
                        } else {
                            # v1.218：park 前窗口竞争 —— 事件先到、协程还没 park。
                            # 保留 epoll 注册（LT 再报），不吞事件不 DEL，下轮
                            # poller 会再唤醒已 park 的协程。
                            rearm = 1;
                        }
                    }
                }
            }
            j = j + 1;
        }
        mutex_unlock(&AIO_LK);
        if hit == 0 { AIO_SKP = AIO_SKP + 1; }
        if rearm == 1 { aio_ctl(EPOLL_CTL_MOD, fd, EPOLLIN | EPOLLOUT, fd); rearm = 0; }
        k = k + 1;
    }
    let q: i64 = 0;
    while q < wn { csp_enq(AIO_WQ[q]); q = q + 1; }
    return 0;
}

# ------------------------------------------------------------------ channel 模式
# 把 fd 注册进 epoll，**不挂起**。就绪时向 c 投递一个值（c 必须 cap>=1）。
# 调用方随后自己去 select { c, timer } —— 这就是带超时的 I/O 的形状。
fn aio_arm(fd: i64, ev: i64, c: i64) -> i64 {
    if AIO_INIT != 1 { AIO_PERR = 9; return 0 - 1; }
    if c < 0 { AIO_PERR = 12; return 0 - 1; }
    let s: i64 = csp_self();
    if s < 0 { AIO_PERR = 8; return 0 - 1; }

    mutex_lock(&AIO_LK);
    let i: i64 = 0 - 1;
    let k: i64 = 0;
    while k < AIO_MAXW {
        if AIO_USED[k] == 1 {
            if AIO_FD[k] == fd {
                # 同一 fd 已有等待者（可能是本协程上一次 arm 没清干净）
                mutex_unlock(&AIO_LK);
                AIO_PERR = 1;
                return 0 - 2;
            }
        }
        k = k + 1;
    }
    k = 0;
    while k < AIO_MAXW {
        if AIO_USED[k] == 0 { if i < 0 { i = k; } }
        k = k + 1;
    }
    if i < 0 { mutex_unlock(&AIO_LK); AIO_PERR = 2; return 0 - 3; }

    AIO_USED[i] = 1;
    AIO_FD[i] = fd;
    AIO_SL[i] = s;
    AIO_EV[i] = ev;
    AIO_CH[i] = 0 - 1;
    AIO_CH[i] = c;

    let r: i64 = aio_ctl(EPOLL_CTL_MOD, fd, ev, fd);
    if r < 0 { r = aio_ctl(EPOLL_CTL_ADD, fd, ev, fd); }
    if r < 0 {
        AIO_USED[i] = 0;
        AIO_CH[i] = 0 - 1;
        mutex_unlock(&AIO_LK);
        AIO_PERR = 3;
        return 0 - 4;
    }
    AIO_REG[i] = 1;
    AIO_N = AIO_N + 1;
    mutex_unlock(&AIO_LK);
    return 0;
}

# 注销 fd：从 epoll 摘掉并清槽。
# 🔴 必须调用：select 走的是另一条分支时（例如超时先到），这个 fd 的
#    槽还占着，fd 还留在 epoll 里。下次复用同一个 fd 号会收到别人的事件。
fn aio_disarm(fd: i64) -> i64 {
    mutex_lock(&AIO_LK);
    let k: i64 = 0;
    while k < AIO_MAXW {
        if AIO_USED[k] == 1 {
            if AIO_FD[k] == fd {
                aio_ctl(EPOLL_CTL_DEL, fd, 0, 0);
                AIO_REG[k] = 0;
                AIO_USED[k] = 0;
                AIO_CH[k] = 0 - 1;
                AIO_N = AIO_N - 1;
            }
        }
        k = k + 1;
    }
    mutex_unlock(&AIO_LK);
    return 0;
}

fn aio_poller(arg: ptr) -> i64 {
    while AIO_ON == 1 {
        AIO_TICK = AIO_TICK + 1;
        # v1.223：丢唤醒兜底 —— 每隔一段扫描等待槽，若槽 ST=7（已 park）
        # 但对应 fd 内核层其实已就绪而 fire 没送到（qemu-user epoll 间歇
        # 丢事件），主动重新入队唤醒。唤醒幂等：ST 已被改则跳过。
        # 无人等待时用长超时，避免空转 syscall；有人在等就 1ms，压低延迟
        let tmo: i64 = 1;
        if AIO_N == 0 { tmo = 20; }
        let n: i64 = syscall(232, AIO_EP, &AIO_EVS, AIO_MAXEV, tmo, 0, 0);
        if n > 0 { AIO_NEV = AIO_NEV + n; AIO_D0 = AIO_EVS[0]; AIO_D1 = AIO_EVS[1]; aio_fire(n); }
    }
    return 0;
}

fn aio_init() -> i64 {
    if AIO_INIT == 1 { return 0; }
    let z: i64 = 0;
    while z < AIO_MAXW { AIO_CH[z] = 0 - 1; z = z + 1; }
    AIO_EP = epoll_create1();
    if AIO_EP < 0 { AIO_PERR = 4; return 0 - 1; }
    AIO_ON = 1;
    if thread_create(&AIO_TID, &aio_poller, 0) != 0 {
        AIO_PERR = 5;
        return 0 - 2;
    }
    AIO_INIT = 1;
    return 0;
}

fn aio_stop() -> i64 {
    AIO_ON = 0;
    return 0;
}

# ------------------------------------------------------------------ 异步操作
# 全部在协程内调用。语义与阻塞版一致，但不占用线程。

fn aio_recv(fd: i64, buf: i64, n: i64) -> i64 {
    while 1 {
        let r: i64 = syscall(0, fd, buf, n, 0, 0, 0);
        if r >= 0 { return r; }
        if r == 0 - EAGAIN {
            if aio_wait(fd, EPOLLIN) < 0 { return 0 - 5; }
        } else {
            return r;
        }
    }
    return 0;
}

fn aio_send(fd: i64, buf: i64, n: i64) -> i64 {
    let off: i64 = 0;
    while off < n {
        let r: i64 = syscall(1, fd, buf + off, n - off, 0, 0, 0);
        if r > 0 { off = off + r; }
        else {
            if r == 0 - EAGAIN {
                if aio_wait(fd, EPOLLOUT) < 0 { return 0 - 5; }
            } else {
                return r;
            }
        }
    }
    return off;
}

var AEB: [8] i64 = 0;
var AIO_SA: [16] byte = 0;
var AIO_EELK: i64 = 0;
var AIO_WQ2: [128] i64 = 0;   # v1.223：兜底巡检的待唤醒表（poller 独占）

# 非阻塞 connect：协程里直呼不卡 worker（v1.209.0）
# 用法：fd = aio_connect(ip, port)；返回负数=失败。需 aio_init 先行。
fn aio_connect(ip: i64, port: i64) -> i64 {
    let fd: i64 = tcp_socket();
    if fd < 0 { return fd; }
    aio_nbio(fd);
    # 🔴 v1.218：局部数组违禁 → 全局
    sock_addr(&AIO_SA, ip, port);
    let r: i64 = syscall(42, fd, &AIO_SA, 16, 0, 0, 0);
    if r == 0 { return fd; }            # 立即连上（本机常见）
    if r != 0 - 115 {                   # 非 EINPROGRESS
        syscall(3, fd, 0, 0, 0, 0, 0);
        return 0 - 1;
    }
    if aio_wait(fd, EPOLLOUT) < 0 {
        syscall(3, fd, 0, 0, 0, 0, 0);
        return 0 - 2;
    }
    # SO_ERROR 检查：SOL_SOCKET=1, SO_ERROR=4, getsockopt=55
    syscall(55, fd, 1, 4, &AEB, 4, 0);
    if AEB[0] != 0 {
        syscall(3, fd, 0, 0, 0, 0, 0);
        return 0 - AEB[0];
    }
    return fd;
}

fn aio_accept(fd: i64) -> i64 {
    while 1 {
        let c: i64 = syscall(43, fd, 0, 0, 0, 0, 0);
        if c >= 0 {
            aio_nbio(c);
            return c;
        }
        if c == 0 - EAGAIN {
            if aio_wait(fd, EPOLLIN) < 0 { return 0 - 6; }
        } else {
            return c;
        }
    }
    return 0;
}

# 关闭并从 epoll 注销（不注销会漏内核条目，fd 号复用后收到别人的事件）
fn aio_close(fd: i64) -> i64 {
    mutex_lock(&AIO_LK);
    let k: i64 = 0;
    while k < AIO_MAXW {
        if AIO_USED[k] == 1 {
            if AIO_FD[k] == fd {
                aio_ctl(EPOLL_CTL_DEL, fd, 0, 0);
                AIO_REG[k] = 0;
                AIO_USED[k] = 0;
                AIO_CH[k] = 0 - 1;
                AIO_N = AIO_N - 1;
            }
        }
        k = k + 1;
    }
    mutex_unlock(&AIO_LK);
    return syscall(3, fd, 0, 0, 0, 0, 0);
}
