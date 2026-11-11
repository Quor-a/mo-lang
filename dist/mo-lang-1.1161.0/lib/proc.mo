# proc —— 进程分配与管理（用墨语言自己写的）
#
# 一个"进程分配"系统需要这些能力，本库逐个提供：
#   1. 进程标识与关系：pid / ppid / pgid / 会话
#   2. 调度控制：nice 优先级
#   3. 资源：getrusage（自身与子进程）、rlimit
#   4. 等待：waitpid 带选项（WNOHANG 非阻塞探活）
#   5. 守护化：fork + setsid + 重定向
#   6. **进程池**：把 N 个任务分配给 M 个 worker 进程并行处理
#
# 全部是系统调用，不依赖 libc。
#
# 设计说明：进程池的"回调"怎么办？
# 墨语言没有函数指针，所以 worker 里不能直接调"传进来的函数"。
# 但墨语言所有函数都在全局符号表里 —— 于是约定
# **使用进程池的程序自己定义 pool_work(task) -> i64**，
# worker 循环里直接调用它。这不是函数指针，是"约定的全局函数"。
import "io.mo";
import "str.mo";
import "err.mo";

# ---------------------------------------------------------------- 标识

fn proc_pid() -> i64  { return syscall(39, 0, 0, 0, 0, 0, 0); }
fn proc_ppid() -> i64 { return syscall(110, 0, 0, 0, 0, 0, 0); }
fn proc_fork() -> i64 { return syscall(57, 0, 0, 0, 0, 0, 0); }

fn proc_getpgid(pid: i64) -> i64 { return syscall(121, pid, 0, 0, 0, 0, 0); }
fn proc_setpgid(pid: i64, pgid: i64) -> i64 { return syscall(109, pid, pgid, 0, 0, 0, 0); }
fn proc_setsid() -> i64 { return syscall(112, 0, 0, 0, 0, 0, 0); }

fn proc_exit(code: i64) -> i64 {
    syscall(60, code, 0, 0, 0, 0, 0);
    return 0;
}

# ---------------------------------------------------------------- 调度

# nice(34)：增量，范围 -20..19。返回系统调用原始结果，失败是 -1。
fn proc_nice(inc: i64) -> i64 { return syscall(34, inc, 0, 0, 0, 0, 0); }

# setpriority(141) / getpriority(140)：which=0 表示按进程
fn proc_setprio(pid: i64, prio: i64) -> i64 {
    return syscall(141, 0, pid, prio, 0, 0, 0);
}
fn proc_getprio(pid: i64) -> i64 {
    return syscall(140, 0, pid, 0, 0, 0, 0);
}

# ---------------------------------------------------------------- 资源

var RU: [16] i64 = 0;

# getrusage(98)：who=0 自身，who=-1(RUSAGE_CHILDREN) 已终止子进程
# 结果写进 &RU：[0]=用户秒 [1]=用户微秒 [2]=系统秒 [3]=系统微秒 [4]=最大驻留集(KB)
fn proc_rusage(who: i64) -> i64 {
    return syscall(98, who, &RU, 0, 0, 0, 0);
}
fn proc_utime_ms() -> i64 {
    proc_rusage(0);
    return RU[0] * 1000 + RU[1] / 1000;
}
fn proc_stime_ms() -> i64 {
    proc_rusage(0);
    return RU[2] * 1000 + RU[3] / 1000;
}
fn proc_maxrss() -> i64 {
    # ru_maxrss 是 struct rusage 的第 5 个 long（偏移 32）。
    # 实测提示：在部分容器 / 沙盒环境里内核不填这个字段，恒为 0。
    proc_rusage(0);
    return RU[4];
}
# 子进程累计 CPU（回收后才有意义）
fn proc_child_utime_ms() -> i64 {
    proc_rusage(0 - 1);
    return RU[0] * 1000 + RU[1] / 1000;
}

# setrlimit(160)：res=0 是 RLIMIT_CPU（秒），res=7 是 RLIMIT_NOFILE
var RL: [16] byte = 0;
fn proc_setrlimit(res: i64, cur: i64, max: i64) -> i64 {
    store64(&RL, cur);
    store64(&RL + 8, max);
    return syscall(160, res, &RL, 0, 0, 0, 0);
}

# ---------------------------------------------------------------- 等待

var WST: i64 = 0;

# waitpid 带选项：opts=1 是 WNOHANG（没有子进程退出就立刻返回 0）
# 返回：>0 退出的 pid，0 表示还有子进程在跑，-1 出错/没有子进程了
fn proc_wait_opt(pid: i64, opts: i64) -> i64 {
    let p: i64 = &WST;
    return syscall(61, pid, p, opts, 0, 0, 0);
}

# 把退出状态解成"退出码"；被信号杀死则返回 128+signo（与 shell 一致）
fn proc_status() -> i64 {
    if (WST & 127) == 0 { return (WST >> 8) & 255; }
    return 128 + (WST & 127);
}
fn proc_signal() -> i64 { return WST & 127; }

fn proc_wait(pid: i64) -> i64 {
    let r: i64 = proc_wait_opt(pid, 0);
    if r < 0 { return 0 - 1; }
    return proc_status();
}

# 非阻塞探活：返回 pid（>0 表示这个子进程刚退出），0 表示都还在跑
#
# 注意：waitpid 是**裸系统调用**，出错时返回**负的 errno**而不是 -1。
# 没有子进程时是 -10（-ECHILD）。这与 C 库封装后的行为不同，容易误判。
fn proc_poll() -> i64 { return proc_wait_opt(0 - 1, 1); }

fn proc_kill(pid: i64, sig: i64) -> i64 { return syscall(62, pid, sig, 0, 0, 0, 0); }

# ---------------------------------------------------------------- 守护化

# 经典 daemonize：fork → 父退出 → 子进程 setsid → 再 fork → 关标准流
# 返回：父进程直接 exit(0) 不返回；子进程返回 0
fn daemonize() -> i64 {
    let pid: i64 = proc_fork();
    if pid < 0 { err_set(E_IO, "fork failed", "daemonize"); return 0 - 1; }
    if pid != 0 { proc_exit(0); }
    let s: i64 = proc_setsid();
    if s < 0 { return 0 - 1; }
    let pid2: i64 = proc_fork();
    if pid2 != 0 { proc_exit(0); }
    # 把 0/1/2 指向 /dev/null
    let dn: [16] byte = 0;
    store8(&dn, 47);  store8(&dn + 1, 100); store8(&dn + 2, 101);
    store8(&dn + 3, 118); store8(&dn + 4, 47); store8(&dn + 5, 110);
    store8(&dn + 6, 117); store8(&dn + 7, 108); store8(&dn + 8, 108);
    store8(&dn + 9, 0);
    let fd: i64 = syscall(2, &dn, 2, 0, 0, 0);
    if fd >= 0 {
        let a: i64 = syscall(33, fd, 0, 0, 0, 0, 0);
        let b: i64 = syscall(33, fd, 1, 0, 0, 0, 0);
        let c: i64 = syscall(33, fd, 2, 0, 0, 0, 0);
    }
    return 0;
}

# ---------------------------------------------------------------- 进程池
#
# 布局：每个 worker 一对管道
#   下发：父写 TO_W[i]  → 子读 TO_R[i]
#   回传：子写 BK_W[i]  → 父读 BK_R[i]
#
# 任务是一个 i64（任务号），结果也是一个 i64。
# 约定：**使用进程池的程序必须自己定义**
#
#   fn pool_work(task: i64) -> i64 { ... }
#
# worker 循环会调用它。这不是函数指针，是"约定的全局函数"。

var P_NW: i64 = 0;
var P_TO_W: [32] i64 = 0;
var P_TO_R: [32] i64 = 0;
var P_BK_R: [32] i64 = 0;
var P_BK_W: [32] i64 = 0;
var P_PID: [32] i64 = 0;

fn pool_pipe(out: i64) -> i64 {
    let raw: [8] byte = 0;
    let r: i64 = syscall(22, &raw, 0, 0, 0, 0, 0);
    if r < 0 { return 0 - 1; }
    let v: i64 = load64(&raw);
    store64(out, v & 4294967295);
    store64(out + 8, (v / 4294967296) & 4294967295);
    return 0;
}

# worker 主循环（只在子进程里调用，不返回）
fn pool_worker_loop(idx: i64) -> i64 {
    let rfd: i64 = P_TO_R[idx];
    let wfd: i64 = P_BK_W[idx];
    while 1 {
        let buf: [8] byte = 0;
        let n: i64 = syscall(0, rfd, &buf, 8, 0, 0, 0);
        if n != 8 { break; }
        let task: i64 = load64(&buf);
        let res: i64 = pool_work(task);
        let ob: [8] byte = 0;
        store64(&ob, res);
        let m: i64 = syscall(1, wfd, &ob, 8, 0, 0, 0);
        if m != 8 { break; }
    }
    let cr: i64 = syscall(3, rfd, 0, 0, 0, 0, 0);
    let cw: i64 = syscall(3, wfd, 0, 0, 0, 0, 0);
    proc_exit(0);
    return 0;
}

# 启动 n 个 worker。只在父进程里调用。
fn pool_start(n: i64) -> i64 {
    if n > 32 { n = 32; }
    P_NW = 0;
    let i: i64 = 0;
    while i < n {
        let a: [2] i64 = 0;
        let b: [2] i64 = 0;
        if pool_pipe(&a) < 0 { err_set(E_IO, "pipe failed", "pool_start"); return 0 - 1; }
        if pool_pipe(&b) < 0 { err_set(E_IO, "pipe failed", "pool_start"); return 0 - 1; }
        P_TO_W[i] = a[1];
        P_TO_R[i] = a[0];
        P_BK_R[i] = b[0];
        P_BK_W[i] = b[1];

        let pid: i64 = proc_fork();
        if pid == 0 {
            # ---- 子进程 ----
            # 只需要关掉**自己的反向端**：下发写端（那是父用的）和
            # 回传读端（那也是父用的）。
            #
            # **千万不要去关兄弟 worker 的 fd**。有两个理由：
            #  1. 兄弟此时可能还没创建，P_TO_R[j] 是 0 → close(0) 关掉 stdin
            #  2. 更要命的是 **fd 号会被复用**：父进程关掉某个 fd 后，
            #     下一次 pipe() 会拿到同一个号。于是按"记录的值"去 close
            #     会关掉**自己**的管道 —— 实测 n=2 时子进程 1 把自己
            #     的读端关掉了，立刻 EOF 退出，父进程写入得到 SIGPIPE(141)。
            #
            # 正确做法：父进程在 fork 后**立即**关掉它那两个端（见下），
            # 后续 fork 的子进程自然不会继承到，无需子进程操心。
            let y1: i64 = syscall(3, P_TO_W[i], 0, 0, 0, 0, 0);
            let y2: i64 = syscall(3, P_BK_R[i], 0, 0, 0, 0, 0);
            pool_worker_loop(i);
        }
        # ---- 父进程 ----
        # fork 后立刻关掉子专用的两个端。这一句同时保证了
        # "后续 fork 的子进程不会再继承到本轮的 fd"，是上面那段注释的前提。
        let z1: i64 = syscall(3, P_TO_R[i], 0, 0, 0, 0, 0);
        let z2: i64 = syscall(3, P_BK_W[i], 0, 0, 0, 0, 0);
        P_PID[i] = pid;
        i = i + 1;
    }
    P_NW = n;
    return n;
}

# 提交一个任务给第 i 个 worker
fn pool_send(i: i64, task: i64) -> i64 {
    let b: [8] byte = 0;
    store64(&b, task);
    let n: i64 = syscall(1, P_TO_W[i], &b, 8, 0, 0, 0);
    if n != 8 { return 0 - 1; }
    return 0;
}

# 从第 i 个 worker 读一个结果（阻塞）
fn pool_recv(i: i64) -> i64 {
    let b: [8] byte = 0;
    let n: i64 = syscall(0, P_BK_R[i], &b, 8, 0, 0, 0);
    if n != 8 { return 0 - 1; }
    return load64(&b);
}

# 关闭所有下发端（通知 worker 收工），并回收所有子进程
fn pool_stop() -> i64 {
    let i: i64 = 0;
    while i < P_NW {
        let c: i64 = syscall(3, P_TO_W[i], 0, 0, 0, 0, 0);
        i = i + 1;
    }
    i = 0;
    while i < P_NW {
        let r: i64 = proc_wait(P_PID[i]);
        let c2: i64 = syscall(3, P_BK_R[i], 0, 0, 0, 0, 0);
        i = i + 1;
    }
    return P_NW;
}
