# sort2 —— 补充排序算法（用墨语言自己写的）
# radix_i64：LSD 基数排序（8 位一桶 × 8 趟，桶计数用 k & 255）。
# 🔴 坑：有符号数 sar 后 k % 256 可为负 → base 表负偏移越界写
# （gdb 下偶现正常、直接跑 SIGSEGV）—— 必须用 k & 255。
# 排序前先整体 ^ (i64 最小值) 翻转符号位，使无符号序 = 有符号序。
# msort_i64：自顶向下归并，稳定 O(n log n)。is_sorted_i64：单调检查。
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



