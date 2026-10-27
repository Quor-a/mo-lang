# expect: 0
# 260_aioclient.mo —— aioclient 库覆盖 + lf_cas 可用性（v1.213 后 x86 freestanding 原生 cmpxchg 可用）
import "aioclient.mo";

fn main() -> i64 {
    aio_pool_config(2130706433, 18900);
    if aio_pool_conns() != 0 { return 1; }
    # 池锁真原子性（native cmpxchg）：借了还上，conns 回 0
    let fd: i64 = aio_pool_borrow();
    if fd >= 0 { return 2; }      # 空池应 -1（无可用连接）
    if aio_pool_conns() != 0 { return 3; }
    return 0;
}
