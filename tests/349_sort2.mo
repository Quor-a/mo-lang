# expect: 127
# tests/349_sort2.mo —— lib/sort2：radix(LSD 8位桶)/msort(归并)/is_sorted
# sort2 —— 补充排序算法 v1（用墨语言自己写的）
#
#   radix_i64   —— LSD 基数排序（8 位一桶，4 趟），稳定，O(n)
#   msort_i64   —— 自顶向下归并排序，稳定，O(n log n)
#   is_sorted_i64 —— 单调性检查（非严格递增）
#
# 数组参数是裸地址（与 lib/sort.mo 的 qsort_i64 一致），元素 i64。
import "mem.mo";

var G_PROG: i64 = 0;

fn radix_i64(a: i64, n: i64) -> i64 {
    let tmp: i64 = alloc8(n);
    let base: i64 = alloc8(256);
    let shift: i64 = 0;
    while shift < 64 {
        let j: i64 = 0;
        while j < 256 {
            store64(base + j * 8, 0);
            j = j + 1;
        }
        let i: i64 = 0;
        while i < n {
            let k: i64 = (load64(a + i * 8) ^ (-9223372036854775807 - 1)) >> shift;
            let b: i64 = k & 255;
            store64(base + b * 8, load64(base + b * 8) + 1);
            i = i + 1;
        }
        let sum: i64 = 0;
        j = 0;
        while j < 256 {
            let c: i64 = load64(base + j * 8);
            store64(base + j * 8, sum);
            sum = sum + c;
            j = j + 1;
        }
        i = 0;
        while i < n {
            let k: i64 = (load64(a + i * 8) ^ (-9223372036854775807 - 1)) >> shift;
            let b: i64 = k & 255;
            let p: i64 = load64(base + b * 8);
            store64(tmp + p * 8, load64(a + i * 8));
            store64(base + b * 8, p + 1);
            i = i + 1;
        }
        i = 0;
        while i < n {
            store64(a + i * 8, load64(tmp + i * 8));
            i = i + 1;
        }
        G_PROG = G_PROG + 1;
        shift = shift + 8;
    }
    return 0;
}

fn is_sorted_i64(a: i64, n: i64) -> i64 {
    let i: i64 = 0;
    while i + 1 < n {
        if load64(a + i * 8) > load64(a + (i + 1) * 8) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

fn msort_merge(a: i64, tmp: i64, lo: i64, mid: i64, hi: i64) -> i64 {
    let i: i64 = lo;
    let j: i64 = mid;
    let k: i64 = lo;
    while i < mid {
        if j >= hi {
            store64(tmp + k * 8, load64(a + i * 8));
            k = k + 1;
            i = i + 1;
        } else {
            if load64(a + j * 8) < load64(a + i * 8) {
                store64(tmp + k * 8, load64(a + j * 8));
                k = k + 1;
                j = j + 1;
            } else {
                store64(tmp + k * 8, load64(a + i * 8));
                k = k + 1;
                i = i + 1;
            }
        }
    }
    while j < hi {
        store64(tmp + k * 8, load64(a + j * 8));
        k = k + 1;
        j = j + 1;
    }
    i = lo;
    while i < hi {
        store64(a + i * 8, load64(tmp + i * 8));
        i = i + 1;
    }
    return 0;
}

fn msort_range(a: i64, tmp: i64, lo: i64, hi: i64) -> i64 {
    if hi - lo <= 1 {
        return 0;
    }
    let mid: i64 = (lo + hi) / 2;
    msort_range(a, tmp, lo, mid);
    msort_range(a, tmp, mid, hi);
    msort_merge(a, tmp, lo, mid, hi);
    return 0;
}

fn msort_i64(a: i64, n: i64) -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let tmp: i64 = alloc8(n);
    msort_range(a, tmp, 0, n);
    return 0;
}



# ---------- 库接口自检（v1.1170 tests/349） ----------
fn main() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    # radix：乱序含负数与 i64 边界
    let a: i64 = alloc8(10);
    store64(a, 5);
    store64(a + 8, -3);
    store64(a + 16, 9223372036854775807);
    store64(a + 24, 0);
    store64(a + 32, -9223372036854775807 - 1);
    store64(a + 40, 7);
    store64(a + 48, -3);
    store64(a + 56, 100);
    store64(a + 64, 1);
    store64(a + 72, -50);
    radix_i64(a, 10);
    let acc: i64 = is_sorted_i64(a, 10);
    if load64(a) != -9223372036854775807 - 1 { acc = acc + 64; }
    if load64(a + 72) != 9223372036854775807 { acc = acc + 128; }
    acc = acc + (load64(a + 8) == -50) * 2;
    # msort：另一组乱序
    let b: i64 = alloc8(10);
    store64(b, 3); store64(b + 8, -1); store64(b + 16, 4);
    store64(b + 24, 1); store64(b + 32, 5); store64(b + 40, -9);
    store64(b + 48, 2); store64(b + 56, 6); store64(b + 64, -5);
    store64(b + 72, 3);
    msort_i64(b, 10);
    acc = acc + is_sorted_i64(b, 10) * 4;
    acc = acc + (load64(b) == -9) * 8 + (load64(b + 72) == 6) * 16;
    # 1000 伪随机数两算法一致性
    let c: i64 = alloc8(1000);
    let seed: i64 = 12345;
    let i: i64 = 0;
    while i < 1000 {
        seed = seed * 6364136223846793005 + 1442695040888963407;
        store64(c + i * 8, seed % 100000 - 50000);
        i = i + 1;
    }
    radix_i64(c, 1000);
    acc = acc + is_sorted_i64(c, 1000) * 32;
    msort_i64(c, 1000);
    acc = acc + is_sorted_i64(c, 1000) * 64;
    return acc;
}
