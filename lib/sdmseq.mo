import "sdm.mo";

# ── 序列存储层（Kanerva 1988, Ch.8；无主流框架实现）───────────────
#
#   转移记忆（bank 0）：address = a_i,  content = a_{i+1}
#   清洗记忆（bank 1）：address = a_i,  content = a_i   （自联想）
#
#   两条**必须**分在两个 bank。若塞进同一组计数器，读 a_i 得到的是
#   a_{i+1} 与 a_i 的叠加，既不是后继也不是自身 —— 见 sq_store_both。
#
# ── 全局临时一律 SQ* 前缀 ──────────────────────────────────────────
#   本项目已多次因「库内共享临时被嵌套调用抹掉」而静默出错
#   （HDC 的 _h0、CaW、多轮调试器）。这里每个函数只用 SQ* 变量。

var SQIT: i64 = 0;      # 项池基址
var SQN: i64 = 0;       # 项数
var SQW: i64 = 0;       # 每项字数（= SDW）
var SQX: i64 = 0;       # 当前地址
var SQY: i64 = 0;       # 读出缓冲
var SQZ: i64 = 0;       # 备用

var SQI: i64 = 0;      # sq_recall / 存储函数专用
var SQJ: i64 = 0;
var SQK: i64 = 0;
var SQNI: i64 = 0;     # sq_nearest 专用 —— 绝不能与 SQI 共用
var SQH: i64 = 0;
var SQD: i64 = 0;

var SQBEST: i64 = 0;    # 最近项下标
var SQBESTH: i64 = 0;   # 最近项距离
var SQEXPECT: i64 = 0;  # 期望下标
var SQOK: i64 = 0;      # 连续正确步数
var SQFIRST: i64 = 0;   # 首次出错的步号（0 = 全程正确）
var SQTIE: i64 = 0;     # 本步读出的平局位数（分支歧义的信号）
var SQITER: i64 = 0;    # 实际执行步数 —— 用于抓「循环变量被抹掉」这类静默错

fn sq_init(n: i64) -> i64 {
    SQW = SDW;
    SQN = n;
    SQIT = sdm_new_n(n);
    SQX = sdm_new();
    SQY = sdm_new();
    SQZ = sdm_new();
    SQD = SDD;
    return SQIT;
}

fn sq_item(i: i64) -> i64 {
    return SQIT + i * SQW;
}

fn sq_rand_all() -> i64 {
    SQI = 0;
    while SQI < SQN {
        sdm_rand(sq_item(SQI));
        SQI = SQI + 1;
    }
    return 0;
}

# 环形序列：a_0 → a_1 → … → a_{n-1} → a_0
fn sq_store_trans() -> i64 {
    sdm_bank(0);
    SQI = 0;
    while SQI < SQN {
        SQJ = SQI + 1;
        if SQJ >= SQN { SQJ = SQJ - SQN; }
        sdm_write(sq_item(SQI), sq_item(SQJ));
        SQI = SQI + 1;
    }
    return 0;
}

# 自联想清洗记忆：a_i → a_i，写在**独立**的 bank 1
fn sq_store_clean() -> i64 {
    sdm_bank(1);
    SQI = 0;
    while SQI < SQN {
        sdm_write(sq_item(SQI), sq_item(SQI));
        SQI = SQI + 1;
    }
    sdm_bank(0);
    return 0;
}

# 反例：把两种写进**同一组**计数器（bank 0）。用来演示叠加污染。
fn sq_store_both() -> i64 {
    sdm_bank(0);
    SQI = 0;
    while SQI < SQN {
        SQJ = SQI + 1;
        if SQJ >= SQN { SQJ = SQJ - SQN; }
        sdm_write(sq_item(SQI), sq_item(SQJ));
        sdm_write(sq_item(SQI), sq_item(SQI));
        SQI = SQI + 1;
    }
    return 0;
}

# 最近项下标（清洗的基准；也是判定「读出来到底是哪项」的手段）
fn sq_nearest(v: i64) -> i64 {
    SQBEST = 0 - 1;
    SQBESTH = SQD + 1;
    SQNI = 0;
    while SQNI < SQN {
        SQH = sdm_ham(v, sq_item(SQNI));
        if SQH < SQBESTH {
            SQBESTH = SQH;
            SQBEST = SQNI;
        }
        SQNI = SQNI + 1;
    }
    return SQBEST;
}

# 一步：bank0 读转移，可选地经 bank1 清洗
fn sq_step() -> i64 {
    sdm_bank(0);
    sdm_read(SQX, SQY);
    SQTIE = SDTIE;
    return 0;
}

# 最近邻清洗：把读出吸附到**显式项表**中最接近的一项。
# 这是 HDC 里 cleanup memory 的标准做法；吸引域由项间距离决定，
# 远宽于 SDM 自联想清洗（见 sq_step_clean）。
fn sq_clean_nn() -> i64 {
    SQBEST = sq_nearest(SQY);
    sdm_copy(SQY, sq_item(SQBEST));
    return 0;
}

fn sq_step_clean() -> i64 {
    sdm_bank(0);
    sdm_read(SQX, SQY);
    SQTIE = SDTIE;
    sdm_bank(1);
    sdm_read(SQY, SQY);
    sdm_bank(0);
    return 0;
}

# 从 start 项出发走 steps 步，返回**正确步数**；
# SQFIRST 记首次出错的步号（0 = 全程正确）。
#   mode 0 = 不清洗（读出直接当下一地址）
#   mode 1 = SDM 自联想清洗（独立 bank 1）
#   mode 2 = 最近邻清洗（显式项表）
fn sq_recall(start: i64, steps: i64, mode: i64) -> i64 {
    sdm_copy(SQX, sq_item(start));
    SQOK = 0;
    SQFIRST = 0;
    SQITER = 0;
    SQI = 0;
    while SQI < steps {
        if mode == 0 { sq_step(); }
        if mode == 1 { sq_step_clean(); }
        if mode == 2 { sq_step(); sq_clean_nn(); }
        SQBEST = sq_nearest(SQY);
        SQEXPECT = start + SQI + 1;
        while SQEXPECT >= SQN { SQEXPECT = SQEXPECT - SQN; }
        if SQBEST == SQEXPECT {
            SQOK = SQOK + 1;
        }
        if SQBEST != SQEXPECT {
            if SQFIRST == 0 { SQFIRST = SQI + 1; }
        }
        sdm_copy(SQX, SQY);
        SQITER = SQITER + 1;
        SQI = SQI + 1;
    }
    return SQOK;
}
