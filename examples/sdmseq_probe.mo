import "sdm.mo";
import "sdmseq.mo";

var N: i64 = 0;
var STEPS: i64 = 0;
var OKC: i64 = 0;
var OKN: i64 = 0;
var F1: i64 = 0;

fn trial(n: i64) -> i64 {
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(n);
    sq_rand_all();
    sq_store_trans();
    sq_store_clean();
    STEPS = n * 2;

    sq_recall(0, STEPS, 0);
    OKN = SQOK;
    F1 = SQFIRST;

    sq_recall(0, STEPS, 1);
    OKC = SQOK;

    print("n=");
    print_i64(n);
    print("  无清洗 正确=");
    print_i64(OKN);
    print("/");
    print_i64(STEPS);
    print(" 首次出错@");
    print_i64(F1);
    print(" | 有清洗 正确=");
    print_i64(OKC);
    print_nl();
    return 0;
}

# 叠加污染：两种写进同一组计数器
fn trial_both(n: i64) -> i64 {
    sdm_dim(4, 512);
    sdm_init(12345);
    sq_init(n);
    sq_rand_all();
    sq_store_both();

    sq_recall(0, n, 0);
    print("n=");
    print_i64(n);
    print("  单bank混合 正确=");
    print_i64(SQOK);
    print("/");
    print_i64(n);
    print_nl();
    return 0;
}

fn main() -> i64 {
    trial(10);
    trial(20);
    trial(40);
    trial(80);
    trial_both(40);
    return 0;
}
