# ds —— 标准数据结构库（用墨语言自己写的）
# expect: 253
# tests/348_ds.mo —— lib/ds 标准数据结构：set/deque/pq/ll/stack
# （16381 mod 256 = 253）
import "mem.mo";

fn set_new() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let h: i64 = alloc(24);
    let c: i64 = 8;
    let s: i64 = alloc8(c * 16);
    store64(h, s);
    store64(h + 8, c);
    store64(h + 16, 0);
    return h;
}

fn set_slot_used(s: i64, i: i64) -> i64 {
    return load64(s + i * 16 + 8);
}

fn set_grow(h: i64) -> i64 {
    let os: i64 = load64(h);
    let oc: i64 = load64(h + 8);
    let nc: i64 = oc * 2;
    let ns: i64 = alloc8(nc * 16);
    store64(h, ns);
    store64(h + 8, nc);
    store64(h + 16, 0);
    let i: i64 = 0;
    while i < oc {
        if set_slot_used(os, i) == 1 {
            set_add(h, load64(os + i * 16));
        }
        i = i + 1;
    }
    return 0;
}

fn set_add(h: i64, key: i64) -> i64 {
    let count: i64 = load64(h + 16);
    let cap: i64 = load64(h + 8);
    if count * 10 >= cap * 7 {
        set_grow(h);
    }
    let s: i64 = load64(h);
    let c: i64 = load64(h + 8);
    let m: i64 = key % c;
    if m < 0 {
        m = m + c;
    }
    let i: i64 = 0;
    while i < c {
        let j: i64 = m + i;
        if j >= c {
            j = j - c;
        }
        if set_slot_used(s, j) == 0 {
            store64(s + j * 16, key);
            store64(s + j * 16 + 8, 1);
            store64(h + 16, load64(h + 16) + 1);
            return 1;
        }
        if load64(s + j * 16) == key {
            return 0;
        }
        i = i + 1;
    }
    return 0;
}

fn set_has(h: i64, key: i64) -> i64 {
    let s: i64 = load64(h);
    let c: i64 = load64(h + 8);
    let m: i64 = key % c;
    if m < 0 {
        m = m + c;
    }
    let i: i64 = 0;
    while i < c {
        let j: i64 = m + i;
        if j >= c {
            j = j - c;
        }
        if set_slot_used(s, j) == 0 {
            return 0;
        }
        if load64(s + j * 16) == key {
            return 1;
        }
        i = i + 1;
    }
    return 0;
}

fn set_len(h: i64) -> i64 {
    return load64(h + 16);
}

fn deque_new() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let h: i64 = alloc(32);
    let d: i64 = alloc8(8 * 8);
    store64(h, d);
    store64(h + 8, 8);
    store64(h + 16, 0);
    store64(h + 24, 0);
    return h;
}

fn deque_grow(h: i64) -> i64 {
    let od: i64 = load64(h);
    let oc: i64 = load64(h + 8);
    let n: i64 = load64(h + 16);
    let hd: i64 = load64(h + 24);
    let nc: i64 = oc * 2;
    let nd: i64 = alloc8(nc * 8);
    let i: i64 = 0;
    while i < n {
        store64(nd + i * 8, load64(od + ((hd + i) % oc) * 8));
        i = i + 1;
    }
    store64(h, nd);
    store64(h + 8, nc);
    store64(h + 24, 0);
    return 0;
}

fn deque_push_back(h: i64, v: i64) -> i64 {
    let n: i64 = load64(h + 16);
    let c: i64 = load64(h + 8);
    if n == c {
        deque_grow(h);
    }
    let d: i64 = load64(h);
    let c2: i64 = load64(h + 8);
    let hd: i64 = load64(h + 24);
    let tail: i64 = (hd + n) % c2;
    store64(d + tail * 8, v);
    store64(h + 16, n + 1);
    return 0;
}

fn deque_push_front(h: i64, v: i64) -> i64 {
    let n: i64 = load64(h + 16);
    let c: i64 = load64(h + 8);
    if n == c {
        deque_grow(h);
    }
    let c2: i64 = load64(h + 8);
    let hd: i64 = load64(h + 24);
    let nh: i64 = hd - 1;
    if nh < 0 {
        nh = nh + c2;
    }
    store64(load64(h) + nh * 8, v);
    store64(h + 24, nh);
    store64(h + 16, load64(h + 16) + 1);
    return 0;
}

fn deque_pop_front(h: i64) -> i64 {
    let n: i64 = load64(h + 16);
    if n == 0 {
        return 0;
    }
    let d: i64 = load64(h);
    let c: i64 = load64(h + 8);
    let hd: i64 = load64(h + 24);
    let v: i64 = load64(d + hd * 8);
    store64(h + 24, (hd + 1) % c);
    store64(h + 16, n - 1);
    return v;
}

fn deque_pop_back(h: i64) -> i64 {
    let n: i64 = load64(h + 16);
    if n == 0 {
        return 0;
    }
    let d: i64 = load64(h);
    let c: i64 = load64(h + 8);
    let hd: i64 = load64(h + 24);
    let tail: i64 = (hd + n - 1) % c;
    let v: i64 = load64(d + tail * 8);
    store64(h + 16, n - 1);
    return v;
}

fn deque_len(h: i64) -> i64 {
    return load64(h + 16);
}

fn pq_new() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let h: i64 = alloc(24);
    let d: i64 = alloc8(8 * 16);
    store64(h, d);
    store64(h + 8, 16);
    store64(h + 16, 0);
    return h;
}

fn pq_grow(h: i64) -> i64 {
    let od: i64 = load64(h);
    let oc: i64 = load64(h + 8);
    let nc: i64 = oc * 2;
    let nd: i64 = alloc8(nc * 8);
    let i: i64 = 0;
    while i < oc {
        store64(nd + i * 8, load64(od + i * 8));
        i = i + 1;
    }
    store64(h, nd);
    store64(h + 8, nc);
    return 0;
}

fn pq_up(h: i64, i0: i64) -> i64 {
    let d: i64 = load64(h);
    let i: i64 = i0;
    while i > 0 {
        let p: i64 = (i - 1) / 2;
        if load64(d + p * 8) <= load64(d + i * 8) {
            break;
        }
        let t: i64 = load64(d + p * 8);
        store64(d + p * 8, load64(d + i * 8));
        store64(d + i * 8, t);
        i = p;
    }
    return 0;
}

fn pq_push(h: i64, v: i64) -> i64 {
    let n: i64 = load64(h + 16);
    let c: i64 = load64(h + 8);
    if n == c {
        pq_grow(h);
    }
    let d: i64 = load64(h);
    let n2: i64 = load64(h + 16);
    store64(d + n2 * 8, v);
    store64(h + 16, n2 + 1);
    pq_up(h, n2);
    return 0;
}

fn pq_down(h: i64, i0: i64) -> i64 {
    let d: i64 = load64(h);
    let n: i64 = load64(h + 16);
    let i: i64 = i0;
    while 1 {
        let l: i64 = i * 2 + 1;
        let r: i64 = i * 2 + 2;
        let s: i64 = i;
        if l < n {
            if load64(d + l * 8) < load64(d + s * 8) {
                s = l;
            }
        }
        if r < n {
            if load64(d + r * 8) < load64(d + s * 8) {
                s = r;
            }
        }
        if s == i {
            break;
        }
        let t: i64 = load64(d + i * 8);
        store64(d + i * 8, load64(d + s * 8));
        store64(d + s * 8, t);
        i = s;
    }
    return 0;
}

fn pq_pop(h: i64) -> i64 {
    let n: i64 = load64(h + 16);
    if n == 0 {
        return 0;
    }
    let d: i64 = load64(h);
    let top: i64 = load64(d);
    let last: i64 = load64(d + (n - 1) * 8);
    store64(d, last);
    store64(h + 16, n - 1);
    pq_down(h, 0);
    return top;
}

fn pq_len(h: i64) -> i64 {
    return load64(h + 16);
}

fn ll_new() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let h: i64 = alloc(24);
    store64(h, 0);
    store64(h + 8, 0);
    store64(h + 16, 0);
    return h;
}

fn ll_push_back(h: i64, v: i64) -> i64 {
    let nd: i64 = alloc(24);
    store64(nd, v);
    store64(nd + 8, load64(h + 8));
    store64(nd + 16, 0);
    if load64(h + 8) != 0 {
        store64(load64(h + 8) + 16, nd);
    } else {
        store64(h, nd);
    }
    store64(h + 8, nd);
    store64(h + 16, load64(h + 16) + 1);
    return 0;
}

fn ll_push_front(h: i64, v: i64) -> i64 {
    let nd: i64 = alloc(24);
    store64(nd, v);
    store64(nd + 8, 0);
    store64(nd + 16, load64(h));
    if load64(h) != 0 {
        store64(load64(h) + 8, nd);
    } else {
        store64(h + 8, nd);
    }
    store64(h, nd);
    store64(h + 16, load64(h + 16) + 1);
    return 0;
}

fn ll_head_val(h: i64) -> i64 {
    if load64(h) == 0 {
        return 0;
    }
    return load64(load64(h));
}

fn ll_pop_front(h: i64) -> i64 {
    let hd: i64 = load64(h);
    if hd == 0 {
        return 0;
    }
    let v: i64 = load64(hd);
    let nx: i64 = load64(hd + 16);
    store64(h, nx);
    if nx != 0 {
        store64(nx + 8, 0);
    } else {
        store64(h + 8, 0);
    }
    store64(h + 16, load64(h + 16) - 1);
    return v;
}

fn ll_len(h: i64) -> i64 {
    return load64(h + 16);
}

fn stack_new() -> i64 {
    if heap_ready() == 0 {
        heap_init();
    }
    let h: i64 = alloc(24);
    let d: i64 = alloc8(8 * 16);
    store64(h, d);
    store64(h + 8, 16);
    store64(h + 16, 0);
    return h;
}

fn stack_push(h: i64, v: i64) -> i64 {
    let n: i64 = load64(h + 16);
    let c: i64 = load64(h + 8);
    if n == c {
        let od: i64 = load64(h);
        let nd: i64 = alloc8(c * 2 * 8);
        let i: i64 = 0;
        while i < n {
            store64(nd + i * 8, load64(od + i * 8));
            i = i + 1;
        }
        store64(h, nd);
        store64(h + 8, c * 2);
    }
    let d: i64 = load64(h);
    let n2: i64 = load64(h + 16);
    store64(d + n2 * 8, v);
    store64(h + 16, n2 + 1);
    return 0;
}

fn stack_pop(h: i64) -> i64 {
    let n: i64 = load64(h + 16);
    if n == 0 {
        return 0;
    }
    let d: i64 = load64(h);
    let v: i64 = load64(d + (n - 1) * 8);
    store64(h + 16, n - 1);
    return v;
}

fn stack_len(h: i64) -> i64 {
    return load64(h + 16);
}

# 测试主程序（追加在库后单文件测）
fn main() -> i64 {
    # set
    let s: i64 = set_new();
    set_add(s, 5);
    set_add(s, 7);
    set_add(s, 5);
    let acc: i64 = set_has(s, 7) * 1 + set_has(s, 9) * 2 + (set_len(s) == 2) * 4;
    # set 扩容（>0.7*8=5 个）
    let k: i64 = 0;
    while k < 20 {
        set_add(s, 100 + k);
        k = k + 1;
    }
    acc = acc + (set_has(s, 119)) * 8 + (set_has(s, 100)) * 16;
    # deque
    let d: i64 = deque_new();
    deque_push_back(d, 1);
    deque_push_back(d, 2);
    deque_push_front(d, 3);
    let f1: i64 = deque_pop_front(d);   # 3
    let f2: i64 = deque_pop_back(d);    # 2
    acc = acc + (f1 == 3) * 32 + (f2 == 2) * 64;
    # deque 扩容
    let j: i64 = 0;
    while j < 30 {
        deque_push_back(d, j);
        j = j + 1;
    }
    acc = acc + (deque_len(d) == 31) * 128 + (deque_pop_front(d) == 2) * 256;
    # pq
    let q: i64 = pq_new();
    pq_push(q, 5);
    pq_push(q, 1);
    pq_push(q, 3);
    let p1: i64 = pq_pop(q);            # 1
    let p2: i64 = pq_pop(q);            # 3
    acc = acc + (p1 == 1) * 512 + (p2 == 3) * 1024;
    # ll
    let l: i64 = ll_new();
    ll_push_back(l, 10);
    ll_push_front(l, 4);
    let lv: i64 = ll_head_val(l);       # 4
    let lv2: i64 = ll_pop_front(l);     # 4
    acc = acc + (lv == 4) * 2048 + (lv2 == 4) * 4096;
    # stack
    let st: i64 = stack_new();
    stack_push(st, 8);
    stack_push(st, 9);
    let sv: i64 = stack_pop(st);        # 9
    acc = acc + (sv == 9) * 8192;
    return acc;
}
