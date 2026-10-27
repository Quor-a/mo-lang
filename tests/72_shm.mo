# 共享内存：mmap / shm 数组 / 跨进程可见性
# expect: 1
import "shm.mo";
import "proc.mo";
import "assert.mo";
import "io.mo";
import "str.mo";

fn pool_work(task: i64) -> i64 { return task; }

var SHARED: i64 = 0;

fn main() -> i64 {
    # --- 基本 mmap ---
    let p: i64 = shm_alloc(4096);
    assert_true("mmap 返回有效地址", p > 0);
    store64(p, 12345);
    assert_eq("读写共享内存", load64(p), 12345);

    # 映射区域按页对齐可用（写完能读回）
    store64(p + 4088, 999);
    assert_eq("页内末尾可写", load64(p + 4088), 999);

    let u: i64 = munmap(p, 4096);
    assert_eq("munmap", u, 0);

    # --- shm 数组 ---
    let a: i64 = shm_array_new(8);
    assert_true("shm_array_new", a > 0);
    assert_eq("长度", shm_array_len(a), 8);

    let i: i64 = 0;
    while i < 8 {
        shm_array_set(a, i, i * 100);
        i = i + 1;
    }
    assert_eq("元素 0", shm_array_get(a, 0), 0);
    assert_eq("元素 3", shm_array_get(a, 3), 300);
    assert_eq("元素 7", shm_array_get(a, 7), 700);
    assert_eq("求和", shm_array_sum(a), 2800);

    # 累加
    shm_array_add(a, 0, 5);
    assert_eq("累加后元素 0", shm_array_get(a, 0), 5);

    # 越界要置错误码，而不是静默写坏邻居
    err_clear();
    let r: i64 = shm_array_set(a, 100, 1);
    assert_true("越界返回失败", r != 0);
    assert_true("越界置了错误码", err_code() != 0);

    # --- 关键：fork 后子进程写入，父进程可见 ---
    SHARED = shm_array_new(4);
    shm_array_set(SHARED, 0, 0);

    let pid: i64 = proc_fork();
    if pid == 0 {
        # 子进程：往共享数组里写（不通过管道，直接写内存）
        shm_array_set(SHARED, 0, 4242);
        shm_array_set(SHARED, 1, 77);
        proc_exit(0);
    }
    let rc: i64 = proc_wait(pid);
    assert_eq("子进程退出码", rc, 0);

    # 父进程必须能看到子进程写的值 —— 这是 MAP_SHARED 的核心语义
    assert_eq("子进程写入可见 [0]", shm_array_get(SHARED, 0), 4242);
    assert_eq("子进程写入可见 [1]", shm_array_get(SHARED, 1), 77);
    assert_eq("共享求和", shm_array_sum(SHARED), 4319);

    # --- 多进程各自累加同一共享数组 ---
    shm_array_zero(SHARED);
    let k: i64 = 0;
    while k < 3 {
        let q: i64 = proc_fork();
        if q == 0 {
            let j: i64 = 0;
            while j < 4 {
                shm_array_add(SHARED, j, k + 1);
                j = j + 1;
            }
            proc_exit(0);
        }
        k = k + 1;
    }
    k = 0;
    while k < 3 { let w: i64 = proc_wait(0 - 1); k = k + 1; }
    # 3 个子进程各给 4 个槽加 (k+1)，即每槽 = 1+2+3 = 6
    assert_eq("多进程累加 [0]=6", shm_array_get(SHARED, 0), 6);
    assert_eq("多进程累加 [3]=6", shm_array_get(SHARED, 3), 6);
    assert_eq("多进程累加总和", shm_array_sum(SHARED), 24);

    # --- 共享字节缓冲 ---
    let b: i64 = shm_buf_new(64);
    assert_true("shm_buf_new", b > 0);
    let n: i64 = shm_buf_set(b, "hello shared memory");
    assert_eq("写入长度", n, 19);
    assert_eq("读回内容", streq(shm_buf_get(b), "hello shared memory"), 1);

    shm_array_free(SHARED);
    shm_array_free(a);
    shm_buf_free(b);

    let t_failed: i64 = test_done();
    if t_failed != 0 { return 2; }
    return 1;
}
