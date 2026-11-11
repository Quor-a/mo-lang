# sort —— 排序与查找（用墨语言自己写的）
#
# 对标 C 的 qsort / bsearch。
#
# **诚实的重要限制**：C 的 qsort 靠**函数指针**传比较器，
# 墨语言目前没有函数指针类型，所以做不到"传任意比较函数"。
#
# 因此提供：
#   1) 常用类型的专用版本（i64 升序/降序、字符串字典序）
#   2) qsort_i64_range：对 i64 数组排序（就地，快排 + 插入排序兜底）
#
# 等语言支持函数指针后，可以补上真正的 qsort(buf, n, size, cmp)。
# 这个限制写在这里，不假装已经解决。

var SORT_SWAPS: i64 = 0;    # 交换次数，便于观察算法行为

# ---------------------------------------------------------------- i64 数组

# 分段插入排序：小区间用它比快排快，也是快排递归的兜底
fn ins_sort_i64(a: i64, lo: i64, hi: i64) -> i64 {
    let i: i64 = lo + 1;
    while i <= hi {
        let k: i64 = load64(a + i * 8);
        let j: i64 = i - 1;
        while j >= lo {
            if load64(a + j * 8) <= k { break; }
            store64(a + (j + 1) * 8, load64(a + j * 8));
            j = j - 1;
        }
        store64(a + (j + 1) * 8, k);
        i = i + 1;
    }
    return 0;
}

# Hoare 分区
fn partition_i64(a: i64, lo: i64, hi: i64) -> i64 {
    let mid: i64 = lo + (hi - lo) / 2;
    let piv: i64 = load64(a + mid * 8);
    let i: i64 = lo - 1;
    let j: i64 = hi + 1;
    while 1 {
        while 1 {
            i = i + 1;
            if load64(a + i * 8) >= piv { break; }
        }
        while 1 {
            j = j - 1;
            if load64(a + j * 8) <= piv { break; }
        }
        if i >= j { return j; }
        let t: i64 = load64(a + i * 8);
        store64(a + i * 8, load64(a + j * 8));
        store64(a + j * 8, t);
        SORT_SWAPS = SORT_SWAPS + 1;
    }
    return j;
}

fn qsort_i64_range(a: i64, lo: i64, hi: i64) -> i64 {
    while lo < hi {
        # 小区间用插入排序：递归开销反而更大
        if hi - lo < 12 {
            ins_sort_i64(a, lo, hi);
            return 0;
        }
        let p: i64 = partition_i64(a, lo, hi);
        # 先递归小的一侧，把大的一侧留在循环里 ——
        # 这样递归深度最坏也是 O(log n)，不会栈溢出
        if p - lo < hi - (p + 1) {
            qsort_i64_range(a, lo, p);
            lo = p + 1;
        } else {
            qsort_i64_range(a, p + 1, hi);
            hi = p;
        }
    }
    return 0;
}

# 就地对 n 个 i64 升序排序
fn qsort_i64(a: i64, n: i64) -> i64 {
    if n <= 1 { return 0; }
    return qsort_i64_range(a, 0, n - 1);
}

# 降序：排完反转
fn qsort_i64_desc(a: i64, n: i64) -> i64 {
    qsort_i64(a, n);
    let i: i64 = 0;
    let j: i64 = n - 1;
    while i < j {
        let t: i64 = load64(a + i * 8);
        store64(a + i * 8, load64(a + j * 8));
        store64(a + j * 8, t);
        i = i + 1;
        j = j - 1;
    }
    return 0;
}

# ---------------------------------------------------------------- 查找

# 二分查找：要求数组已升序。找到返回下标，否则返回 -1。
# 注意：返回 -1 表示没找到 —— 与 strchr 一致，
# **不要**把 0 当失败（0 是合法下标）。
fn bsearch_i64(a: i64, n: i64, key: i64) -> i64 {
    let lo: i64 = 0;
    let hi: i64 = n - 1;
    while lo <= hi {
        let mid: i64 = lo + (hi - lo) / 2;
        let v: i64 = load64(a + mid * 8);
        if v == key { return mid; }
        if v < key { lo = mid + 1; } else { hi = mid - 1; }
    }
    return 0 - 1;
}

# 线性查找（无需有序）
fn lsearch_i64(a: i64, n: i64, key: i64) -> i64 {
    let i: i64 = 0;
    while i < n {
        if load64(a + i * 8) == key { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

# 找最小值 / 最大值的下标
fn argmin_i64(a: i64, n: i64) -> i64 {
    let bi: i64 = 0;
    let bv: i64 = load64(a);
    let i: i64 = 1;
    while i < n {
        if load64(a + i * 8) < bv { bv = load64(a + i * 8); bi = i; }
        i = i + 1;
    }
    return bi;
}
fn argmax_i64(a: i64, n: i64) -> i64 {
    let bi: i64 = 0;
    let bv: i64 = load64(a);
    let i: i64 = 1;
    while i < n {
        if load64(a + i * 8) > bv { bv = load64(a + i * 8); bi = i; }
        i = i + 1;
    }
    return bi;
}

# ---------------------------------------------------------------- 字符串数组

# 对 vec 里的字符串按字典序排序（vec 元素是堆字符串地址）
import "vec.mo";
import "str.mo";

# ---------- 比较器快排（v1.228）----------
# qsort_cmp(a, n, cmp)：cmp(x, y) <0/ =0 / >0。a 是 i64 数组地址。
# 内建类型（i64/byte）qsort 已覆盖；字符串/结构体键排序用此通用版。
fn partition_cmp(a: i64, lo: i64, hi: i64, cmp: ptr) -> i64 {
    let pv: i64 = load64(a + hi * 8);
    let i: i64 = lo - 1;
    let j: i64 = lo;
    while j < hi {
        let r: i64 = call2(cmp, load64(a + j * 8), pv);
        if r <= 0 {
            i = i + 1;
            let t: i64 = load64(a + i * 8);
            store64(a + i * 8, load64(a + j * 8));
            store64(a + j * 8, t);
        }
        j = j + 1;
    }
    let t2: i64 = load64(a + (i+1) * 8);
    store64(a + (i+1) * 8, load64(a + hi * 8));
    store64(a + hi * 8, t2);
    return i + 1;
}

fn qsort_cmp_range(a: i64, lo: i64, hi: i64, cmp: ptr) -> i64 {
    if lo >= hi { return 0; }
    let p: i64 = partition_cmp(a, lo, hi, cmp);
    qsort_cmp_range(a, lo, p - 1, cmp);
    qsort_cmp_range(a, p + 1, hi, cmp);
    return 0;
}

fn qsort_cmp(a: i64, n: i64, cmp: ptr) -> i64 {
    if n < 2 { return 0; }
    return qsort_cmp_range(a, 0, n - 1, cmp);
}

# 逆序比较器现成件：cmp_desc(x, y) = y - x
fn cmp_desc(x: i64, y: i64) -> i64 {
    return y - x;
}

fn qsort_str_vec(v: i64) -> i64 {
    let n: i64 = vec_len(v);
    let i: i64 = 1;
    while i < n {
        let k: i64 = vec_get(v, i);
        let j: i64 = i - 1;
        while j >= 0 {
            if strcmp(vec_get(v, j), k) <= 0 { break; }
            vec_set(v, j + 1, vec_get(v, j));
            j = j - 1;
        }
        vec_set(v, j + 1, k);
        i = i + 1;
    }
    return 0;
}

# 有序数组里二分查找字符串
fn bsearch_str_vec(v: i64, key: ptr) -> i64 {
    let lo: i64 = 0;
    let hi: i64 = vec_len(v) - 1;
    while lo <= hi {
        let mid: i64 = lo + (hi - lo) / 2;
        let c: i64 = strcmp(vec_get(v, mid), key);
        if c == 0 { return mid; }
        if c < 0 { lo = mid + 1; } else { hi = mid - 1; }
    }
    return 0 - 1;
}
