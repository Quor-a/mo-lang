import "sdm.mo";
import "sdmseq.mo";

# ── SDM 序列存储（Kanerva 1988 Ch.8）──────────────────────────
#
#   存储：address = a_i, content = a_{i+1}（环形，a_{n-1} → a_0）
#   召回：读出**直接**当下一个地址，形成链
#
#   核心问题：单步读出几乎无损，链却会崩 —— 误差沿链放大。

var N: i64 = 40;
var STEPS: i64 = 120;
var M: i64 = 0;
var R: i64 = 0;
var EI: i64 = 0;
var EO: i64 = 0;
var E: i64 = 0;

fn setup(n: i64) -> i64 {
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(n);
    sq_rand_all();
    sq_store_trans();
    sq_store_clean();
    return 0;
}

fn basin_sdm(e: i64) -> i64 {
    sdm_copy(SQX, sq_item(0));
    sdm_noise_seed(999);
    sdm_noise(SQX, e);
    EI = sdm_ham(SQX, sq_item(0));
    sdm_bank(1);
    sdm_read(SQX, SQY);
    sdm_bank(0);
    EO = sdm_ham(SQY, sq_item(0));
    print("  输入误差=");
    print_i64(EI);
    print("  → 清洗后误差=");
    print_i64(EO);
    print_nl();
    return 0;
}

fn basin_nn(e: i64) -> i64 {
    sdm_copy(SQX, sq_item(0));
    sdm_noise_seed(999);
    sdm_noise(SQX, e);
    EI = sdm_ham(SQX, sq_item(0));
    print("  输入误差=");
    print_i64(EI);
    print("  → nearest=");
    print_i64(sq_nearest(SQX));
    print_nl();
    return 0;
}

fn main() -> i64 {
    setup(N);

    print("== 三种清洗模式（n=40，走 120 步）==");
    print_nl();
    M = 0;
    while M < 3 {
        R = sq_recall(0, STEPS, M);
        print("  mode ");
        print_i64(M);
        if M == 0 { print(" 无清洗    "); }
        if M == 1 { print(" SDM自联想 "); }
        if M == 2 { print(" 最近邻    "); }
        print("  正确=");
        print_i64(R);
        print(" 首次出错@");
        print_i64(SQFIRST);
        print(" 实际步数=");
        print_i64(SQITER);
        print_nl();
        M = M + 1;
    }

    print("== SDM 自联想清洗的吸引域（bank 1）==");
    print_nl();
    basin_sdm(0);
    basin_sdm(5);
    basin_sdm(20);
    basin_sdm(60);

    print("== 最近邻清洗的吸引域==");
    print_nl();
    basin_nn(20);
    basin_nn(120);

    print("== 分支歧义：两条序列共享前缀 x0→x1，x1 后分叉 ==");
    print_nl();
    sdm_dim(4, 512);
    sdm_init(7);
    sq_init(4);
    sq_rand_all();
    sdm_bank(0);
    sdm_write(sq_item(0), sq_item(1));
    sdm_read(sq_item(0), SQY);
    print("  非分支点 x0：平局位=");
    print_i64(SDTIE);
    print("  到后继距离=");
    print_i64(sdm_ham(SQY, sq_item(1)));
    print_nl();
    sdm_write(sq_item(1), sq_item(2));
    sdm_write(sq_item(1), sq_item(3));
    sdm_read(sq_item(1), SQY);
    print("  分支点   x1：平局位=");
    print_i64(SDTIE);
    print("  到 x2=");
    print_i64(sdm_ham(SQY, sq_item(2)));
    print("  到 y2=");
    print_i64(sdm_ham(SQY, sq_item(3)));
    print_nl();

    print("== 单 bank 叠加污染（转移 + 自联想写进同一组计数器）==");
    print_nl();
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(N);
    sq_rand_all();
    sq_store_both();
    R = sq_recall(0, N, 0);
    print("  正确=");
    print_i64(R);
    print("/");
    print_i64(N);
    print_nl();
    return 0;
}
