# 99 —— 梯度流审计：抓"静默的梯度断裂"
#
# 背景：本项目 1.39 踩过一次 —— ad_set() 不记 tape，用它拼装的多通道
# 池化让卷积层收不到任何梯度，而结果**照样 8/8，毫无异常**。
#
# 社区观点（arXiv:2007.05282v2 的解读，"AD correctness is a semantics
# problem"）：tape 方案里没有反向公式的算子会被当作零导数，**静默**地
# 给出错误梯度。所以必须把可疑之处报出来。
#
# 本测试用最小的场景复现那类断裂，确认审计能抓到。
import "autodiff.mo";

var F: i64 = 0;
fn eq(g: i64, w: i64) -> i64 { if g != w { F = F + 1; } return 0; }

# --- 场景 A：正常。w 直接进图，梯度非零 ---
fn good() -> i64 {
    ad_reset();
    ad_audit_reset();
    let x: i64 = ad_input(65536);      # 1.0
    let w: i64 = ad_weight(32768);     # 0.5
    let p: i64 = ad_mul(w, x);
    let y: i64 = ad_sigmoid(p);
    ad_backward(y);
    return ad_audit();
}

# --- 场景 B：断裂。w 的值被 ad_set 拷进块，w 本身从不进图 ---
#     这正是 1.39 的真实形态：程序照常收敛，卷积核却一次都没更新。
fn broken() -> i64 {
    ad_reset();
    ad_audit_reset();
    let w: i64 = ad_weight(32768);     # 权重槽，但从不参与任何 ad_* 运算
    let blk: i64 = ad_block(1);
    ad_set(blk, ad_val(w));            # 值拷过去，梯度不跟着走
    let x: i64 = ad_input(65536);
    let y: i64 = ad_mul(blk, x);       # 图里用的是 blk，不是 w
    ad_backward(y);
    return ad_audit();
}

# --- 场景 C：未知算子。手工往 tape 里塞一条 op=0 ---
#     backward 会静默跳过它 —— 必须被报出来。
fn badop() -> i64 {
    ad_reset();
    ad_audit_reset();
    let x: i64 = ad_input(65536);
    let w: i64 = ad_weight(32768);
    let y: i64 = ad_mul(w, x);
    # 手工塞一条未初始化的 tape 记录（op=0）
    store64(&AD_TOP + AD_TN * 8, 0);
    store64(&AD_TA + AD_TN * 8, w);
    store64(&AD_TB + AD_TN * 8, x);
    store64(&AD_TO + AD_TN * 8, y);
    AD_TN = AD_TN + 1;
    ad_backward(y);
    return ad_audit();
}

fn main() -> i64 {
    print("--- A 正常 ---\n");
    let na: i64 = good();
    print("--- B 断裂（权重不进图）---\n");
    let nb: i64 = broken();
    print("--- C 未知算子 ---\n");
    let nc: i64 = badop();
    print("\n");

    # A 必须 0 问题；B、C 必须抓到
    eq(na, 0);
    if nb < 1 { F = F + 1; }      # B 至少要报"从未进图"
    if nc < 1 { F = F + 1; }      # C 至少要报未知算子

    print("A问题="); print_i64(na);
    print("  B问题="); print_i64(nb);
    print("  C问题="); print_i64(nc);
    print("\n");

    if F == 0 { return 0; }
    print("FAILED="); print_i64(F); print("\n");
    return 1;
}
