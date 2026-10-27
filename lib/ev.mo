# ev.mo —— 极简事件总线（v1.230）
# 回调注册表：on(type, fn) 注册，emit(type, arg) 经 call1 分派。
# fn 签名统一 fn(arg: i64) -> i64（call1）；多值打包用全局或 ptr。
# 数组只能全局（moc 铁律）。

var EV_FN: [64] i64 = 0;      # EV_FN[type*8+k] 最多 8 个/type，8 type
var EV_FN_TYPE: [64] i64 = 0; # 平铺 (type,k) -> fn
var EV_N: [8] i64 = 0;        # 每 type 已注册数
var EV_ONCE: [64] i64 = 0;    # slot -> 1 = 触发后摘除（v1.231 once）
var EV_MAXT: i64 = 8;
var EV_MAXH: i64 = 8;

# 注册。返回全局面板下标，-1 = 满。type < 8。
fn ev_on(etype: i64, f: ptr) -> i64 {
    if etype < 0 { return 0 - 1; }
    if etype >= EV_MAXT { return 0 - 1; }
    let k: i64 = EV_N[etype];
    if k >= EV_MAXH { return 0 - 1; }
    EV_FN_TYPE[etype * 8 + k] = f;
    EV_N[etype] = k + 1;
    return etype * 8 + k;
}

# 触发。依次调所有回调，全收尾后返回累计返回值。
fn ev_emit(etype: i64, arg: i64) -> i64 {
    if etype < 0 { return 0 - 1; }
    if etype >= EV_MAXT { return 0 - 1; }
    let n: i64 = EV_N[etype];
    let acc: i64 = 0;
    let i: i64 = 0;
    while i < n {
        let slot: i64 = etype * 8 + i;
        if EV_FN_TYPE[slot] != 0 {
            acc = acc + call1(EV_FN_TYPE[slot], arg);
            if EV_ONCE[slot] == 1 { EV_ONCE[slot] = 0; EV_FN_TYPE[slot] = 0; }
        }
        i = i + 1;
    }
    return acc;
}

fn ev_once(etype: i64, f: ptr) -> i64 {
    let s: i64 = ev_on(etype, f);
    if s >= 0 { EV_ONCE[s] = 1; }
    return s;
}

# 注销单条
fn ev_off(slot: i64) -> i64 {
    if slot < 0 { return 0 - 1; }
    EV_FN_TYPE[slot] = 0;
    return 0;
}
