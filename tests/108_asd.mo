# 108 —— ASD：自动稀疏微分（1.80）
#
# 概念来源（"还在 PDF 里躺着"的技术）：
#   Gebremedhin, Manne & Pothen, "What Color Is Your Jacobian?" SIAM Review 2005
#   Griewank & Walther, "Evaluating Derivatives" 第 8 章
#   ICLR 2025 blogpost "An Illustrated Guide to Automatic Sparse Differentiation"
#
# 🔴 核心悖论：要判断哪些列可合并，得先知道稀疏模式；
#    可要用传统 AD 算出矩阵才知道模式 —— 那 ASD 就没意义了。
#    解法：只传播**索引集**，不做数值计算。
import "autodiff.mo";
import "assert.mo";

fn main() -> i64 {
    print("=== ASD 自动稀疏微分 ===\n");
    let fail: i64 = 0;

    # ---- 场景：1→4 通道 3×3 卷积，输入 8×8 ----
    #  J 是 4×36（gmax 后每通道一个数，对 36 个核元素）
    #  每个输出只依赖**本通道**的 9 个核元素 ⇒ 每行 9 个非零
    #  不同通道的列永不同行 ⇒ 可同色 ⇒ 颜色数应为 9 而非 36
    ad_reset();
    let img: i64 = ad_block(64);
    let i: i64 = 0;
    while i < 64 { ad_set(img + i, nn_rand_fp(30000)); i = i + 1; }
    let KW: i64 = ad_wblock(36);
    ad_wconv_init(KW, 4, 1);
    let KB: i64 = ad_wblock(4);
    ad_bzero(KB, 4);
    let c1: i64 = ad_conv_mc(img, KW, 8, 8, 1, 4);
    let c2: i64 = ad_vadd_bcast(c1, KB, 4, 36);
    let rel: i64 = ad_vrelu(c2, 144);
    let pl: i64 = ad_pool_mc(rel, 4, 6, 6);
    let gm: i64 = ad_gmax_mc(pl, 4, 9);

    # 第 1 步：Detection
    let nz: i64 = ad_asd_detect(KW, 36, gm, 4);
    print("-- 第1步 Detection --\n");
    print("  非零个数 = "); print_i64(nz); print("  （稠密 4×36=144）\n");
    # 4 个输出 × 每通道 9 个 = 36
    if nz != 36 { fail = fail + 1; print("  ✗ 非零数应为 36\n"); }
    else { print("  ✓ 稀疏度正确（每行只有 9 个）\n"); }

    # 第 2 步：Coloring
    let nc: i64 = ad_asd_color();
    print("-- 第2步 Coloring --\n");
    print("  颜色数 = "); print_i64(nc); print("  （稠密需 36 次传播）\n");
    if nc != 9 { fail = fail + 1; print("  ✗ 颜色数应为 9\n"); }
    else { print("  ✓ 压缩 4×\n"); }

    # 第 3、4 步：压缩 AD + 解压
    ad_asd_jac();
    print("-- 第3/4步 Compressed AD + Decompression --\n");

    # ---- 正确性：与逐列稠密 JVP **逐值对照** ----
    let bad: i64 = 0;
    let o: i64 = 0;
    let j: i64 = 0;
    let ncmp: i64 = 0;
    let nzero: i64 = 0;
    while o < 4 {
        j = 0;
        while j < 36 {
            # 稠密：只播种第 j 列，跑一次前向
            let k: i64 = 0;
            while k < AD_N { store64(&AD_DOT + k * 8, 0); k = k + 1; }
            store64(&AD_DOT + (KW + j) * 8, 65536);
            ad_forward();
            let dense: i64 = load64(&AD_DOT + (gm + o) * 8);
            let comp: i64 = ad_asd_get(o, j);
            ncmp = ncmp + 1;
            if dense != comp {
                # 只在"模式说非零"时应相等；零处允许定点噪声
                if dense != 0 { bad = bad + 1; }
                else {
                    if comp < 0 { comp = 0 - comp; }
                    if comp > 256 { bad = bad + 1; }
                }
            } else {
                if dense == 0 { nzero = nzero + 1; }
            }
            j = j + 1;
        }
        o = o + 1;
    }
    print("  比较 "); print_i64(ncmp); print(" 项，不一致 "); print_i64(bad); print("\n");
    print("  其中精确为 0 的项 "); print_i64(nzero); print(" 个\n");
    if bad != 0 { fail = fail + 1; print("  ✗ 压缩结果与稠密不一致\n"); }
    else { print("  ✓ 逐值一致\n"); }

    # ---- 稀疏性验证：非本通道的列必须为 0 ----
    print("-- 稀疏性：跨通道必须为 0 --\n");
    let xbad: i64 = 0;
    o = 0;
    while o < 4 {
        j = 0;
        while j < 36 {
            let jch: i64 = j / 9;
            if jch != o {
                if ad_asd_get(o, j) != 0 { xbad = xbad + 1; }
            }
            j = j + 1;
        }
        o = o + 1;
    }
    print("  跨通道非零项 = "); print_i64(xbad); print("\n");
    if xbad != 0 { fail = fail + 1; print("  ✗ 跨通道不该非零\n"); }
    else { print("  ✓ 跨通道全为 0\n"); }

    # ---- 场景 2：全连接层（验证 matmul 的逐元素精确传播）----
    #  J 是 2×8（2 个输出，8 个权重）；行 i 只依赖 W[i][*] 的 4 个
    #  ⇒ 每行 4 个非零；W[0][k] 与 W[1][k] 不冲突 ⇒ 颜色数 4 而非 8
    print("-- 场景2：全连接 matmul --\n");
    ad_reset();
    let X: i64 = ad_block(4);
    i = 0;
    while i < 4 { ad_set(X + i, 20000); i = i + 1; }
    let W2: i64 = ad_wblock(8);
    ad_wdense_init(W2, 2, 4);
    let B2: i64 = ad_wblock(2);
    ad_bzero(B2, 2);
    let h2: i64 = ad_vadd(ad_matmul(W2, X, 2, 4), B2, 2);
    let y2: i64 = ad_vsig(h2, 2);

    let nz2: i64 = ad_asd_detect(W2, 8, y2, 2);
    print("  非零个数 = "); print_i64(nz2); print("  （稠密 2×8=16）\n");
    if nz2 != 8 { fail = fail + 1; print("  ✗ 应为 8\n"); }
    else { print("  ✓ 每行只有 4 个\n"); }
    let nc2: i64 = ad_asd_color();
    print("  颜色数 = "); print_i64(nc2); print("  （稠密需 8 次）\n");
    if nc2 != 4 { fail = fail + 1; print("  ✗ 应为 4\n"); }
    else { print("  ✓ 压缩 2×\n"); }
    ad_asd_jac();
    let bad2: i64 = 0;
    o = 0;
    while o < 2 {
        j = 0;
        while j < 8 {
            let k2: i64 = 0;
            while k2 < AD_N { store64(&AD_DOT + k2 * 8, 0); k2 = k2 + 1; }
            store64(&AD_DOT + (W2 + j) * 8, 65536);
            ad_forward();
            let d2: i64 = load64(&AD_DOT + (y2 + o) * 8);
            let c2v: i64 = ad_asd_get(o, j);
            if d2 != c2v {
                let df: i64 = d2 - c2v;
                if df < 0 { df = 0 - df; }
                if df > 256 { bad2 = bad2 + 1; }
            }
            j = j + 1;
        }
        o = o + 1;
    }
    print("  不一致 = "); print_i64(bad2); print("\n");
    if bad2 != 0 { fail = fail + 1; print("  ✗ 与稠密不一致\n"); }
    else { print("  ✓ 逐值一致\n"); }

    print("\nfail: "); print_i64(fail); print("\n");
    if fail == 0 { print("asd: ALL PASS\n"); return 0; }
    return 1;
}
