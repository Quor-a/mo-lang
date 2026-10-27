# csp.mo —— CSP 并发：M:N 协程调度器 + channel
#
# 概念：Hoare 的 Communicating Sequential Processes（1978）。
# Go 的 goroutine/channel 是它的工程化形态；本库用 ucontext 在墨语言里
# 实现同样的语义：轻量协程 + 阻塞式 channel（缓冲 / 无缓冲 rendezvous）。
#
# 需要链接 libc + pthread：
#   ./bin/moc prog.mo -c prog.o && bash tools/molink.sh prog.o -o prog
#
# 🔴 设计要点
#   1. 协程**绑定**到创建它的 worker（不做工作窃取）——因为 makecontext
#      的 uc_link 写死了该 worker 的调度上下文，跨线程恢复会跑到别的线程栈上。
#   2. 状态机：1=new 2=running 3=wait 4=done 6=yielded/可运行。
#      swapcontext 返回后：2 → 协程 return 了（uc_link 生效）；6 → 主动让出。
#      这是区分"return"与"yield"的唯一手段，两者都从同一处恢复。
#   3. 唤醒用"惊群"：channel 操作成功后把所有等在该 channel 上的协程
#      置为可运行，它们各自重新检查条件。正确但非最优（多 worker 下会有
#      无谓的调度），换来的是不需要精确的等待队列。
#
# 🔴 已知限制
#   - 协程函数必须**无参**（C 视角 void(void)）；参数用 csp_go(f, arg) +
#     协程内 csp_arg() 取。
#   - heap.mo 的 malloc 非线程安全，多 worker 下不要 malloc。
#   - 全局数组上限：MAXC=32 协程、NCH=16 channel、缓冲容量 64。

import "io.mo";
import "thread.mo";
import "shm.mo";

extern fn getcontext(p: ptr) -> i32;
extern fn setcontext(p: ptr) -> i32;
extern fn swapcontext(a: ptr, b: ptr) -> i32;
extern fn makecontext(p: ptr, f: ptr, argc: i64) -> i32;

# ------------------------------------------------------------------ 常量
var CSP_UCW: i64 = 128;      # ucontext 按 i64 计的宽度（1024 字节，glibc 实为 936）
var CSP_STKSZ: i64 = 131072; # 每协程栈 128KB
var CSP_MAXC: i64 = 128;     # v1.123：32 → 128（异步 I/O 需要高并发度）
var CSP_MAXW: i64 = 4;
var CSP_RQN: i64 = 64;       # v1.123：32 → 64（128 协程 / 4 worker，32 会刚好溢出）
var CSP_NCH: i64 = 64;      # v1.126：16 → 64（定时器每个 tm_after 都要一个 channel）
var CSP_CHCAP: i64 = 64;

# ------------------------------------------------------------------ 状态
var CSP_NW: i64 = 0;
var CSP_NC: i64 = 0;
var CSP_FIN: i64 = 0;
var CSP_STOP: i64 = 0;
var CSP_DEAD: i64 = 0;
var CSP_BOOTW: i64 = 0;

var CSP_CTX: [16384] i64 = 0;  # 128 * 128
var CSP_SP: [128] i64 = 0;      # mmap 出来的栈
var CSP_ST: [128] i64 = 0;
var CSP_WK: [128] i64 = 0;      # 绑定的 worker
var CSP_FN: [128] i64 = 0;
var CSP_ARGV: [128] i64 = 0;
var CSP_WCH: [128] i64 = 0;     # 等待的 channel，-1 表示无
var CSP_WOP: [128] i64 = 0;     # 0=send 1=recv
var CSP_WV: [128] i64 = 0;      # send 待发值 / recv 收到的值
var CSP_WR: [128] i64 = 0;      # 无缓冲交接标记：1=接收方已收到 2=发送方已被取走

var CSP_SCHED: [512] i64 = 0;  # 4 * 128
var CSP_CUR: [4] i64 = 0;      # 每 worker 正在跑的协程，-1 空闲
var CSP_TIDR: [4] i64 = 0;     # worker 的真实 tid（gettid）
var CSP_OK: [4] i64 = 0;       # worker 启动确认
var CSP_TID: [4] i64 = 0;      # pthread_t

var CSP_RQ: [256] i64 = 0;     # 4 * 64
var CSP_RQH: [4] i64 = 0;
var CSP_RQT: [4] i64 = 0;
var CSP_RQM: [32] i64 = 0;     # 4 * 8 mutex

var CSP_QOVF: i64 = 0;         # v1.123：运行队列溢出次数（正常必须恒为 0）
var CSP_GLK: [8] i64 = 0;      # 全局锁（计数、唤醒扫描）
var CSP_TRYV: i64 = 0;         # chan_tryrecv 取到的值
# v1.125：多通道等待（select）表。
#   一个 select 要同时等 N 个 channel，而 CSP_WCH[] 每协程只有一个槽。
#   🔴 这张表必须在 csp.mo 里：唤醒路径只有调度器走得到，而且墨语言
#      不支持函数指针调用（`CSP_WKCB(c)` 直接报 undefined symbol），
#      做不成回调钩子。数组全 0 时本表不生效，csp.mo 单独使用不受影响。
var CSP_SELK: i64 = 8;         # 每 select 最多 case 数
var CSP_SN: [128] i64 = 0;     # 该协程这次 select 有几个 case
var CSP_SLC: [1024] i64 = 0;   # 128 * 8：第 i 协程第 k 个 case 的 channel
var CSP_SACT: [128] i64 = 0;   # 0=不在 select  1=已注册  2=已被 claim
var CSP_SWIN: [128] i64 = 0;   # 命中的 case 下标，-1 = 未定
var CSP_SLK: [8] i64 = 0;

# ------------------------------------------------------------------ channel
var CH_BUF: [4096] i64 = 0;    # 64 * 64
var CH_H: [64] i64 = 0;
var CH_T: [64] i64 = 0;
var CH_N: [64] i64 = 0;
var CH_CAP: [64] i64 = 0;
var CH_CL: [64] i64 = 0;
var CH_M: [512] i64 = 0;       # 64 * 8 mutex
var CH_NC: i64 = 0;
var CH_OK: i64 = 0;            # 最近一次 chan_recv 是否拿到值

# ------------------------------------------------------------------ 辅助
fn gettid() -> i64 {
    return syscall(186, 0, 0, 0, 0, 0, 0);
}

# 当前协程所在 worker（用 tid 反查，避免多 worker 抢写全局）
fn csp_myworker() -> i64 {
    let t: i64 = gettid();
    let w: i64 = 0;
    while w < CSP_MAXW {
        if CSP_TIDR[w] == t {
            if CSP_CUR[w] >= 0 { return w; }
        }
        w = w + 1;
    }
    return -1;
}

fn csp_self() -> i64 {
    let w: i64 = csp_myworker();
    if w < 0 { return -1; }
    return CSP_CUR[w];
}

fn csp_arg() -> i64 {
    let s: i64 = csp_self();
    if s < 0 { return 0; }
    return CSP_ARGV[s];
}

# 入队到该协程绑定的 worker
# 🔴 v1.123：队列满时**必须**报错，不能静默回绕覆盖。
#    原实现 `if T >= RQN { T = 0 }` 会把最老的未运行协程悄悄丢掉 ——
#    表现为"某个协程再也没被调度"，不崩溃、不报错，只有计数少一个。
fn csp_enq(slot: i64) -> i64 {
    let w: i64 = CSP_WK[slot];
    let b: i64 = w * CSP_RQN;
    mutex_lock(&CSP_RQM + w * 64);
    let nt: i64 = CSP_RQT[w] + 1;
    if nt >= CSP_RQN { nt = 0; }
    if nt == CSP_RQH[w] {
        CSP_QOVF = CSP_QOVF + 1;
        mutex_unlock(&CSP_RQM + w * 64);
        return 0 - 1;
    }
    CSP_RQ[b + CSP_RQT[w]] = slot;
    CSP_RQT[w] = nt;
    mutex_unlock(&CSP_RQM + w * 64);
    return 0;
}

# 主动让出（协程仍在可运行状态）
fn csp_yield() -> i64 {
    let w: i64 = csp_myworker();
    if w < 0 { return -1; }
    let s: i64 = CSP_CUR[w];
    if s < 0 { return -1; }
    CSP_ST[s] = 6;
    swapcontext(&CSP_CTX + s * 1024, &CSP_SCHED + w * 1024);
    return 0;
}

# 阻塞让出（等 channel 唤醒）：与 yield 的区别只是状态，
# 调度器看到 3 不会重新入队，必须由唤醒者显式入队。
fn csp_block() -> i64 {
    let w: i64 = csp_myworker();
    if w < 0 { return -1; }
    let s: i64 = CSP_CUR[w];
    if s < 0 { return -1; }
    CSP_ST[s] = 3;
    swapcontext(&CSP_CTX + s * 1024, &CSP_SCHED + w * 1024);
    return 0;
}

# 挂起，等待**非 channel** 的事件唤醒（供 lib/aio.mo 的 epoll reactor 用）。
#
# 与 csp_block() 的唯一区别是状态值 7 而不是 3：调度器对 3 和 7 都不重新
# 入队，唤醒必须由外部显式 csp_enq()。分开两个状态是为了调试时能区分
# "卡在 channel 上" 和 "卡在 I/O 上"。
fn csp_park() -> i64 {
    let w: i64 = csp_myworker();
    if w < 0 { return -1; }
    let s: i64 = CSP_CUR[w];
    if s < 0 { return -1; }
    CSP_ST[s] = 7;
    swapcontext(&CSP_CTX + s * 1024, &CSP_SCHED + w * 1024);
    return 0;
}


# 协程正常结束：切回调度器并计入完成数。
#
# 🔴 必须用 csp_exit() 结束协程，不能靠 return。
#    原因：glibc 的 __start_context（协程 return 后跑到那里）从 **%rbx**
#    取 uc_link，而墨语言生成的代码用 rbx 做表达式求值中转
#    （`mov %rax,%rbx`）且**不保存恢复** —— rbx 是 callee-saved 寄存器，
#    这违反 System V ABI。实测：空协程 return 正常，但只要协程里调用过
#   任何用了 rbx 的墨函数（比如 print），return 就会 SIGSEGV。
#    本库因此让协程在 csp_exit() 里切走，永不执行到 ret。
fn csp_exit() -> i64 {
    let w: i64 = csp_myworker();
    if w < 0 { return 0 - 1; }
    let s: i64 = CSP_CUR[w];
    if s < 0 { return 0 - 1; }
    CSP_ST[s] = 4;
    mutex_lock(&CSP_GLK);
    CSP_FIN = CSP_FIN + 1;
    mutex_unlock(&CSP_GLK);
    swapcontext(&CSP_CTX + s * 1024, &CSP_SCHED + w * 1024);
    # 不该回到这里。若回来了就空转 —— 绝不能 ret。
    while 1 { usleep(1000000); }
    return 0;
}

# ------------------------------------------------------------------ 启动
fn csp_init(nw: i64) -> i64 {
    if nw < 1 { nw = 1; }
    if nw > CSP_MAXW { nw = CSP_MAXW; }
    CSP_NW = nw;
    let w: i64 = 0;
    while w < nw {
        let b: i64 = w * CSP_RQN;
        CSP_RQH[w] = 0;
        CSP_RQT[w] = 0;
        CSP_CUR[w] = 0 - 1;
        CSP_TIDR[w] = 0;
        CSP_OK[w] = 0;
        mutex_lock(&CSP_GLK);
        CSP_BOOTW = w;
        mutex_unlock(&CSP_GLK);
        if thread_create(&CSP_TID + w * 8, &csp_workerfn, 0) != 0 { return -1; }
        # 等 worker 报 tid —— 否则下一个 worker 会读到同一个 CSP_BOOTW
        let spin: i64 = 0;
        while CSP_OK[w] == 0 {
            usleep(200);
            spin = spin + 1;
            if spin > 50000 { return -1; }
        }
        w = w + 1;
    }
    return 0;
}

# 创建协程。f 必须无参；arg 通过 csp_arg() 取。
#
# 🔴 v1.128：拆成 csp_go_hold() + csp_start() 两步。
#    原实现在返回前就 csp_enq(s)，于是**协程可能在调用方拿到槽号之前
#    就已经开始跑、甚至已经结束**。lib/scope.mo 需要在协程跑起来之前
#    先登记「它属于哪个 scope」，否则子协程读到的归属是默认值 0 ——
#    而 0 恰好是一个合法的 scope 下标，于是它去递减**别的** scope 的
#    存活计数，自己 scope 的计数永远归不了零 → sc_close() 永久挂住。
#    症状是"卡住"，不是崩溃，而且只在多 worker 下间歇出现。
fn csp_go_hold(f: ptr, arg: i64) -> i64 {
    if CSP_NC >= CSP_MAXC { return -1; }
    let s: i64 = CSP_NC;
    CSP_FN[s] = f;
    CSP_ARGV[s] = arg;
    CSP_ST[s] = 1;
    CSP_WCH[s] = 0 - 1;
    CSP_WOP[s] = 0;
    CSP_WV[s] = 0;
    CSP_WK[s] = s % CSP_NW;      # 轮流绑到各 worker
    let sp: i64 = mmap(0, CSP_STKSZ, 3, 34, 0 - 1, 0);   # RW, PRIVATE|ANON
    if sp < 0 { return -1; }
    CSP_SP[s] = sp;
    CSP_NC = CSP_NC + 1;
    return s;
}

# 让 hold 出来的协程真正可被调度。
fn csp_start(slot: i64) -> i64 {
    if slot < 0 { return -1; }
    if slot >= CSP_NC { return -1; }
    return csp_enq(slot);
}

fn csp_go(f: ptr, arg: i64) -> i64 {
    let s: i64 = csp_go_hold(f, arg);
    if s < 0 { return -1; }
    csp_start(s);
    return s;
}

# ------------------------------------------------------------------ 调度循环
fn csp_workerfn(arg: ptr) -> i64 {
    mutex_lock(&CSP_GLK);
    let w: i64 = CSP_BOOTW;
    mutex_unlock(&CSP_GLK);
    CSP_TIDR[w] = gettid();
    CSP_OK[w] = 1;
    getcontext(&CSP_SCHED + w * 1024);
    csp_loop(w);
    return 0;
}

fn csp_loop(w: i64) -> i64 {
    let base: i64 = w * CSP_UCW;
    let rqb: i64 = w * CSP_RQN;
    let idle: i64 = 0;
    while 1 {
        if CSP_STOP == 1 { return 0; }
        let slot: i64 = 0 - 1;
        mutex_lock(&CSP_RQM + w * 64);
        if CSP_RQH[w] != CSP_RQT[w] {
            slot = CSP_RQ[rqb + CSP_RQH[w]];
            CSP_RQH[w] = CSP_RQH[w] + 1;
            if CSP_RQH[w] >= CSP_RQN { CSP_RQH[w] = 0; }
            idle = 0;
        }
        mutex_unlock(&CSP_RQM + w * 64);

        if slot < 0 {
            # 队列空：所有协程都结束了就退出；否则可能是在等别的 worker 唤醒
            if CSP_FIN >= CSP_NC {
                if CSP_NC > 0 { return 0; }
            }
            idle = idle + 1;
            # 🔴 v1.218 根修：worker 不再因空队自杀（idle>30000 → CSP_DEAD）。
            #    常驻 server 场景 worker 6 秒后全部自杀 → poller 唤醒入队没人跑，
    #            服务假死（curl 先通后死、协程 E2E 一批后瘫）。批处理程序由
            #    csp_sched 的 CSP_FIN 计数收口，与 worker 退出解耦。
            usleep(200);
        } else {
            let cb: i64 = slot * CSP_UCW;
            CSP_CUR[w] = slot;
            if CSP_ST[slot] == 1 {
                getcontext(&CSP_CTX + cb * 8);
                # ucontext_t: uc_flags(0) uc_link(8) ss_sp(16) ss_flags(24) ss_size(32)
                CSP_CTX[cb + 1] = &CSP_SCHED + base * 8;
                CSP_CTX[cb + 2] = CSP_SP[slot];
                CSP_CTX[cb + 3] = 0;
                CSP_CTX[cb + 4] = CSP_STKSZ;
                makecontext(&CSP_CTX + cb * 8, CSP_FN[slot], 0);
            }
            CSP_ST[slot] = 2;
            swapcontext(&CSP_SCHED + base * 8, &CSP_CTX + cb * 8);

            # 回到这里：协程 yield 了 / 阻塞了 / return 了
            if CSP_ST[slot] == 6 {
                csp_enq(slot);                 # 主动让出：重新排队
            } else {
                if CSP_ST[slot] == 2 {
                    CSP_ST[slot] = 4;          # running → 说明是 return（uc_link 生效）
                    mutex_lock(&CSP_GLK);
                    CSP_FIN = CSP_FIN + 1;
                    mutex_unlock(&CSP_GLK);
                }
            }
            CSP_CUR[w] = 0 - 1;
        }
    }
    return 0;
}

# 等待所有协程结束并回收 worker
fn csp_sched() -> i64 {
    let spin: i64 = 0;
    while CSP_FIN < CSP_NC {
        if CSP_DEAD == 1 { return -1; }
        usleep(300);
        spin = spin + 1;
        if spin > 200000 { CSP_DEAD = 1; return -1; }
    }
    CSP_STOP = 1;
    let w: i64 = 0;
    while w < CSP_NW {
        thread_join(CSP_TID[w]);
        w = w + 1;
    }
    return 0;
}

# ------------------------------------------------------------------ channel
fn chan_make(cap: i64) -> i64 {
    if CH_NC >= CSP_NCH { return -1; }
    if cap < 0 { cap = 0; }
    if cap > CSP_CHCAP { cap = CSP_CHCAP; }
    let c: i64 = CH_NC;
    CH_CAP[c] = cap;
    CH_H[c] = 0;
    CH_T[c] = 0;
    CH_N[c] = 0;
    CH_CL[c] = 0;
    CH_NC = CH_NC + 1;
    return c;
}

fn chan_close(c: i64) -> i64 {
    CH_CL[c] = 1;
    csp_wakech(c);
    return 0;
}

# 把所有等在该 channel 上的协程标记为可运行（惊群）
fn csp_wakech(c: i64) -> i64 {
    mutex_lock(&CSP_GLK);
    let i: i64 = 0;
    while i < CSP_NC {
        if CSP_ST[i] == 3 {
            if CSP_WCH[i] == c {
                CSP_ST[i] = 6;
                CSP_WCH[i] = 0 - 1;
                csp_enq(i);
            }
        }
        i = i + 1;
    }
    mutex_unlock(&CSP_GLK);
    csp_wakesel(c);
    return 0;
}



# 唤醒"某个 case 落在 c 上"的 select 等待者（lib/select.mo 的唤醒面）。
#
# 🔴 只在协程**确实已挂起**（CSP_ST == 7）时才入队。若它还在 running，
#    只置 CSP_SWIN 让它自己重试 —— 提前 enq 会让它凭空多跑一次；
#    而协程侧是在**锁内**宣告 ST=7 再 park 的，两侧合起来才闭合。
fn csp_wakesel(c: i64) -> i64 {
    let i: i64 = 0;
    let k: i64 = 0;
    let hitk: i64 = 0 - 1;
    mutex_lock(&CSP_SLK);
    while i < CSP_NC {
        if CSP_SACT[i] == 1 {
            let b: i64 = i * CSP_SELK;
            hitk = 0 - 1;
            k = 0;
            while k < CSP_SN[i] {
                if hitk < 0 {
                    if CSP_SLC[b + k] == c { hitk = k; }
                }
                k = k + 1;
            }
            if hitk >= 0 {
                CSP_SWIN[i] = hitk;
                CSP_SACT[i] = 2;
                if CSP_ST[i] == 7 {
                    CSP_ST[i] = 6;
                    csp_enq(i);
                }
            }
        }
        i = i + 1;
    }
    mutex_unlock(&CSP_SLK);
    return 0;
}

fn chan_send(c: i64, v: i64) -> i64 {
    let me: i64 = csp_self();
    while 1 {
        mutex_lock(&CH_M + c * 64);
        if CH_CL[c] == 1 {
            mutex_unlock(&CH_M + c * 64);
            return -1;
        }
        if CH_CAP[c] == 0 {
            # 无缓冲：直接交给一个等待中的接收者
            let r: i64 = 0 - 1;
            let i: i64 = 0;
            while i < CSP_NC {
                if CSP_ST[i] == 3 {
                    if CSP_WCH[i] == c {
                        if CSP_WOP[i] == 1 { r = i; }
                    }
                }
                i = i + 1;
            }
            if r >= 0 {
                CSP_WV[r] = v;
                CSP_WR[r] = 1;
                CSP_ST[r] = 6;
                CSP_WCH[r] = 0 - 1;
                mutex_unlock(&CH_M + c * 64);
                csp_enq(r);
                return 0;
            }
        } else {
            if CH_N[c] < CH_CAP[c] {
                let b: i64 = c * CSP_CHCAP;
                CH_BUF[b + CH_T[c]] = v;
                CH_T[c] = CH_T[c] + 1;
                if CH_T[c] >= CSP_CHCAP { CH_T[c] = 0; }
                CH_N[c] = CH_N[c] + 1;
                mutex_unlock(&CH_M + c * 64);
                csp_wakech(c);
                return 0;
            }
        }
        # 阻塞
        if me >= 0 {
            CSP_WCH[me] = c;
            CSP_WOP[me] = 0;
            CSP_WV[me] = v;
        }
        mutex_unlock(&CH_M + c * 64);
        if me < 0 { usleep(1000); } else { csp_block(); if CSP_WR[me] == 2 { CSP_WR[me] = 0; return 0; } }
    }
    return 0;
}

# 返回值存 CH_OK：1 拿到值，0 channel 已关闭且空
fn chan_recv(c: i64) -> i64 {
    let me: i64 = csp_self();
    while 1 {
        mutex_lock(&CH_M + c * 64);
        if CH_N[c] > 0 {
            let b: i64 = c * CSP_CHCAP;
            let v: i64 = CH_BUF[b + CH_H[c]];
            CH_H[c] = CH_H[c] + 1;
            if CH_H[c] >= CSP_CHCAP { CH_H[c] = 0; }
            CH_N[c] = CH_N[c] - 1;
            mutex_unlock(&CH_M + c * 64);
            csp_wakech(c);
            CH_OK = 1;
            return v;
        }
        if CH_CAP[c] == 0 {
            # 无缓冲：从一个等待中的发送者手里取
            let s: i64 = 0 - 1;
            let i: i64 = 0;
            while i < CSP_NC {
                if CSP_ST[i] == 3 {
                    if CSP_WCH[i] == c {
                        if CSP_WOP[i] == 0 { s = i; }
                    }
                }
                i = i + 1;
            }
            if s >= 0 {
                let v: i64 = CSP_WV[s];
                CSP_WR[s] = 2;
                CSP_ST[s] = 6;
                CSP_WCH[s] = 0 - 1;
                mutex_unlock(&CH_M + c * 64);
                csp_enq(s);
                CH_OK = 1;
                return v;
            }
        }
        if CH_CL[c] == 1 {
            mutex_unlock(&CH_M + c * 64);
            CH_OK = 0;
            return 0;
        }
        if me >= 0 {
            CSP_WCH[me] = c;
            CSP_WOP[me] = 1;
        }
        mutex_unlock(&CH_M + c * 64);
        if me < 0 { usleep(1000); } else { csp_block(); if CSP_WR[me] == 1 { CSP_WR[me] = 0; CH_OK = 1; return CSP_WV[me]; } }
    }
    return 0;
}

# 非阻塞接收：有值返回 1，无值返回 0（不阻塞）
fn chan_tryrecv(c: i64) -> i64 {
    let v: i64 = 0;
    mutex_lock(&CH_M + c * 64);
    if CH_N[c] > 0 {
        let b: i64 = c * CSP_CHCAP;
        v = CH_BUF[b + CH_H[c]];
        CH_H[c] = CH_H[c] + 1;
        if CH_H[c] >= CSP_CHCAP { CH_H[c] = 0; }
        CH_N[c] = CH_N[c] - 1;
        mutex_unlock(&CH_M + c * 64);
        csp_wakech(c);
        CH_OK = 1;
        CSP_TRYV = v;
        return 1;
    }
    mutex_unlock(&CH_M + c * 64);
    CH_OK = 0;
    return 0;
}

# 非阻塞发送：成功返回 1，缓冲满 / 无缓冲且无等待接收者返回 0，已关闭返回 -1
#
# v1.125：为 lib/select.mo 的 send case 而加。与 chan_tryrecv 对称。
fn chan_trysend(c: i64, v: i64) -> i64 {
    mutex_lock(&CH_M + c * 64);
    if CH_CL[c] == 1 {
        mutex_unlock(&CH_M + c * 64);
        return 0 - 1;
    }
    if CH_CAP[c] == 0 {
        let r: i64 = 0 - 1;
        let i: i64 = 0;
        while i < CSP_NC {
            if CSP_ST[i] == 3 {
                if CSP_WCH[i] == c {
                    if CSP_WOP[i] == 1 { r = i; }
                }
            }
            i = i + 1;
        }
        if r >= 0 {
            CSP_WV[r] = v;
            CSP_WR[r] = 1;
            CSP_ST[r] = 6;
            CSP_WCH[r] = 0 - 1;
            mutex_unlock(&CH_M + c * 64);
            csp_enq(r);
            return 1;
        }
        mutex_unlock(&CH_M + c * 64);
        return 0;
    }
    if CH_N[c] < CH_CAP[c] {
        let b: i64 = c * CSP_CHCAP;
        CH_BUF[b + CH_T[c]] = v;
        CH_T[c] = CH_T[c] + 1;
        if CH_T[c] >= CSP_CHCAP { CH_T[c] = 0; }
        CH_N[c] = CH_N[c] + 1;
        mutex_unlock(&CH_M + c * 64);
        csp_wakech(c);
        return 1;
    }
    mutex_unlock(&CH_M + c * 64);
    return 0;
}
