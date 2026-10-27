#!/bin/bash
# timertest —— 分层时间轮 + select 超时 端到端验证
#
# 必须走 molink + libc：pthread / usleep 在 libc 里。
#
# 判据不是"有没有崩"，而是**具体数字**：
#   · 定时器早触发 / 不触发 / 漏唤醒 都不报错，只表现为数字不对
#   · 精度必须落在 [aim, aim + 2·tick + 40] 这个**闭区间**里：
#     只测"不早"会放过"永远不触发"（等不到就一直等），
#     只测"不晚"会放过"量化误差其实是错的"。
HERE=$(cd "$(dirname "$0")/.." && pwd)
MOC="$HERE/bin/moc"; LINK="$HERE/tools/molink.sh"
TMP=/tmp/motimer
rm -rf $TMP && mkdir -p $TMP/lib
cp "$HERE"/lib/*.mo $TMP/lib/
cd $TMP
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }
ckge() { if [ "$1" -ge "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 ($1 >= $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 >= '$2')"; fi; }
ckle() { if [ "$1" -le "$2" ] 2>/dev/null; then PASS=$((PASS+1)); echo "  ✓ $3 ($1 <= $2)"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 <= '$2')"; fi; }

cat > t.mo <<'MO'
import "io.mo";
import "cstd.mo";
import "thread.mo";
import "random.mo";
import "csp.mo";
import "select.mo";
import "timer.mo";

var WORK: i64 = 0;
var WORK2: i64 = 0;
var AIM: [6] i64 = 0;
var EL: [6] i64 = 0;
var HIT: [6] i64 = 0;
var OKC: i64 = 0;
var TIMK: i64 = 99;
var TIMMS: i64 = 0;
var FASTK: i64 = 99;
var FASTV: i64 = 0;
var FASTMS: i64 = 0;
var PRE: i64 = 77;
var NF: i64 = 0;
var NM: i64 = 0;
var BIG: i64 = 77;
var OVFD: i64 = 0;
var TICKD: i64 = 0;
var MSUSED: i64 = 0;
var CATCH: i64 = 0;
var BURST: i64 = 0;
var CLKD: i64 = 0;
var PHASE: i64 = 0;
var PHASEK: i64 = 99;
var PHG: i64 = 0;

# ---- A：逐个 arm 并 select，量出精度（含一个跨 L0 跨度的 1200ms） ----
fn acc_fn() -> i64 {
    let i: i64 = 0;
    let t: i64 = 0;
    let k: i64 = 0;
    let a: i64 = 0;
    let b: i64 = 0;
    while i < 6 {
        a = clock_ms();
        t = tm_after(AIM[i]);
        sel_reset();
        sel_case(t, 1, 0);
        k = sel_go(0);
        b = clock_ms();
        EL[i] = b - a;
        HIT[i] = k;
        if k == 0 { OKC = OKC + 1; }
        i = i + 1;
    }
    csp_exit();
    return 0;
}

# ---- B：纯超时分支：work 上永远没数据，必须走 timer case ----
fn to_fn() -> i64 {
    let t: i64 = tm_after(300);
    let a: i64 = clock_ms();
    let b: i64 = 0;
    sel_reset();
    sel_case(WORK, 1, 0);
    sel_case(t, 1, 0);
    TIMK = sel_go(0);
    b = clock_ms();
    TIMMS = b - a;
    csp_exit();
    return 0;
}

# ---- F：受控相位 —— 专门盯"时间轮量化的是上一个 tick 而不是 arm 时刻" ----
# 等到距上一个 tick 至少 11ms 再 arm：若不做零头补偿，400ms 的定时器
# 会提前 ~11ms 触发。这个场景让该缺陷**必然**复现，而不是碰运气。
fn phase_fn() -> i64 {
    let a: i64 = 0;
    let b: i64 = 0;
    let t: i64 = 0;
    let g: i64 = 0;
    while g < 11 {
        usleep(1000);
        g = tm_clock() - TM_LASTMS;
        if g < 0 { g = 0 - g; }
    }
    PHG = g;
    a = clock_ms();
    t = tm_after(400);
    sel_reset();
    sel_case(t, 1, 0);
    PHASEK = sel_go(0);
    b = clock_ms();
    PHASE = b - a;
    csp_exit();
    return 0;
}

# ---- C：有数据时不能走超时（超时设 5000ms，实际必须几十毫秒就返回） ----
fn fast_fn() -> i64 {
    let t: i64 = tm_after(5000);
    let a: i64 = clock_ms();
    let b: i64 = 0;
    let k: i64 = 0;
    sel_reset();
    sel_case(WORK2, 1, 0);
    sel_case(t, 1, 0);
    k = sel_go(0);
    FASTK = k;
    FASTV = sel_val();
    b = clock_ms();
    FASTMS = b - a;
    csp_exit();
    return 0;
}
fn feeder() -> i64 {
    usleep(50000);
    chan_send(WORK2, 4242);
    csp_exit();
    return 0;
}

fn main() -> i64 {
    let i: i64 = 0;
    let ms0: i64 = 0;
    let ms1: i64 = 0;
    let t0: i64 = 0;
    let f0: i64 = 0;
    let m0: i64 = 0;
    let ov0: i64 = 0;
    let r: i64 = 0;

    # tm_init 之前调用必须失败（-1），不能静默成功
    PRE = tm_after(10);

    # ---- 时钟分辨率守卫：clock_ms 若退化成 1 秒分辨率，这里会得到 0 或 1000 ----
    ms0 = clock_ms();
    usleep(50000);
    ms1 = clock_ms();
    CLKD = ms1 - ms0;

    AIM[0] = 50; AIM[1] = 100; AIM[2] = 200;
    AIM[3] = 400; AIM[4] = 800; AIM[5] = 1200;

    srand(20251013);
    if csp_init(1) != 0 { print("csp_init fail\n"); return 1; }
    sel_init();
    if tm_init(16) != 0 { print("tm_init fail\n"); return 1; }
    WORK = chan_make(4);
    WORK2 = chan_make(4);

    t0 = tm_ticks();
    ms0 = clock_ms();
    csp_go(&acc_fn, 0);
    csp_go(&to_fn, 0);
    csp_go(&fast_fn, 0);
    csp_go(&feeder, 0);
    csp_go(&phase_fn, 0);
    if csp_sched() != 0 { print("sched fail\n"); return 1; }
    ms1 = clock_ms();
    MSUSED = ms1 - ms0;
    TICKD = tm_ticks() - t0;
    CATCH = TM_CATCH;
    BURST = TM_BURST;

    # ---- D：40 个并发定时器，必须全部触发且全部投递成功 ----
    f0 = TM_FIRED;
    m0 = TM_MISS;
    i = 0;
    while i < 40 {
        r = tm_after(500);
        if r < 0 { NF = 0 - 999; }
        i = i + 1;
    }
    usleep(1400000);
    NF = TM_FIRED - f0;
    NM = TM_MISS - m0;

    # ---- E：超范围必须返回 -1 并计数，不能静默截断成一个短定时 ----
    ov0 = TM_OVF;
    BIG = tm_after(999999);
    OVFD = TM_OVF - ov0;

    tm_stop();

    print("pre=");     print_i64(PRE);     print("\n");
    print("okc=");     print_i64(OKC);     print("\n");
    print("h0=");      print_i64(HIT[0]);  print("\n");
    print("h5=");      print_i64(HIT[5]);  print("\n");
    print("e0=");      print_i64(EL[0]);   print("\n");
    print("e1=");      print_i64(EL[1]);   print("\n");
    print("e2=");      print_i64(EL[2]);   print("\n");
    print("e3=");      print_i64(EL[3]);   print("\n");
    print("e4=");      print_i64(EL[4]);   print("\n");
    print("e5=");      print_i64(EL[5]);   print("\n");
    print("timk=");    print_i64(TIMK);    print("\n");
    print("timms=");   print_i64(TIMMS);   print("\n");
    print("fastk=");   print_i64(FASTK);   print("\n");
    print("fastv=");   print_i64(FASTV);   print("\n");
    print("fastms=");  print_i64(FASTMS);  print("\n");
    print("nf=");      print_i64(NF);      print("\n");
    print("nm=");      print_i64(NM);      print("\n");
    print("big=");     print_i64(BIG);     print("\n");
    print("ovfd=");    print_i64(OVFD);    print("\n");
    print("tickd=");   print_i64(TICKD);   print("\n");
    print("msused=");  print_i64(MSUSED);  print("\n");
    print("catch=");   print_i64(CATCH);   print("\n");
    print("burst=");   print_i64(BURST);   print("\n");
    print("clkd=");    print_i64(CLKD);    print("\n");
    print("phg=");     print_i64(PHG);     print("\n");
    print("phase=");   print_i64(PHASE);   print("\n");
    print("phasek=");  print_i64(PHASEK);  print("\n");
    print("dead=");    print_i64(CSP_DEAD); print("\n");
    return 0;
}
MO

$MOC t.mo -c t.o >/dev/null 2>err.txt || { echo "  ✗ 编译失败"; cat err.txt; exit 1; }
bash $LINK t.o -o tlink >/dev/null 2>&1 || { echo "  ✗ 链接失败"; exit 1; }
timeout 120 ./tlink > out.txt 2>&1; RC=$?
if [ $RC -ne 0 ]; then echo "  ✗ 运行失败 rc=$RC"; cat out.txt; exit 1; fi

g() { grep -E "^$1=" out.txt | head -1 | cut -d= -f2; }

echo "  精度 / 命中："
ck "$(g okc)" "6" "6 个 deadline 全部命中 timer case"
ckle "$(g e0)" "$((50+32+40))"  "50ms 不晚于上界"
ckge "$(g e0)" "50"             "50ms 不早于 aim"
ckle "$(g e1)" "$((100+32+40))" "100ms 不晚于上界"
ckge "$(g e1)" "100"            "100ms 不早于 aim"
ckle "$(g e2)" "$((200+32+40))" "200ms 不晚于上界"
ckge "$(g e2)" "200"            "200ms 不早于 aim"
ckle "$(g e5)" "$((1200+32+40))" "1200ms（跨 L0 跨度，走 L1+级联）不晚于上界"
ckge "$(g e5)" "1200"            "1200ms 不早于 aim —— 级联不能让它提前"
echo "  select 超时："
ck "$(g timk)" "1" "work 无数据时走 timer case（下标 1）"
ckge "$(g timms)" "300" "超时确实等到了 300ms，不是立刻返回"
ckle "$(g timms)" "$((300+32+60))" "超时没有晚太多"
ck "$(g fastk)" "0" "有数据时走 work case，不走超时"
ck "$(g fastv)" "4242" "拿到正确的值"
ckle "$(g fastms)" "200" "有数据时几十毫秒返回，没有等 5000ms"
echo "  边界与并发："
ck "$(g pre)" "-1" "tm_init 之前 tm_after 返回 -1"
ck "$(g nf)" "40" "40 个并发定时器全部触发"
ck "$(g nm)" "0" "40 个全部投递成功（缓冲满/漏投会 >0）"
ck "$(g big)" "-1" "超范围返回 -1"
ck "$(g ovfd)" "1" "超范围计数 +1"
echo "  受控相位（时间轮量化基准是上一个 tick，不是 arm 时刻）："
ckge "$(g phg)" "11" "确实等到了距上一 tick >=11ms 的相位"
ckge "$(g phase)" "400" "相位偏移 11ms 时仍不早于 400ms（不补偿零头必然提前 ~11ms）"
ckle "$(g phase)" "$((400+32))" "相位场景不晚于 400+32"
echo "  时钟分辨率（v1.126 修的那个静默缺陷的守卫）："
ckge "$(g clkd)" "40" "间隔 50ms 的两次 clock_ms 差值 >=40"
ckle "$(g clkd)" "120" "间隔 50ms 的两次 clock_ms 差值 <=120（1 秒分辨率会得到 0 或 1000）"
echo "  线程健康："
EXPECT=$(( $(g msused) / 16 ))
ckle "$(g catch)" "0" "定时器线程没有饿死（catch 必须 0）"
ckle "$(g burst)" "4" "单次唤醒补的 tick 数 <=4（时钟退化成 1 秒分辨率时会一次补 ~62 个）"
D=$(python3 -c "print(abs(int('$(g tickd)')-int('$EXPECT')))")
ckle "$D" "5" "tick 数与 elapsed/16 相差 <=5（累积漂移会是几十个，不是 5）"
ck "$(g dead)" "0" "调度器没判定死锁"

echo
echo "通过 $PASS / 失败 $FAIL"
[ $FAIL -eq 0 ]
