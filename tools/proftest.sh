#!/bin/bash
# proftest —— 验证 -p 自动插桩与 prof.mo
#
# 关键设计：**必须有可测量的耗时**。若工作负载太小，所有耗时都是 0，
# 那么"报告格式正确"和"计时真的在工作"根本区分不开 —— 1.59.0 就栽在这。
set +e
HERE=$(cd "$(dirname "$0")/.." && pwd)
W=/tmp/proftest
rm -rf $W && mkdir -p $W/lib
cp $HERE/lib/*.mo $W/lib/
cd $W
PASS=0; FAIL=0
ck() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  ✓ $3"; else FAIL=$((FAIL+1)); echo "  ✗ $3 (得到 '$1' 想要 '$2')"; fi; }

cat > t.mo <<'MO'
import "io.mo";
import "prof.mo";

fn leaf(n: i64) -> i64 {
    let s: i64 = 0;
    let i: i64 = 0;
    while i < n {
        s = s + i * 7;
        i = i + 1;
    }
    return s;
}

fn mid(n: i64) -> i64 {
    let t: i64 = 0;
    let k: i64 = 0;
    while k < 20 {
        t = t + leaf(n);
        k = k + 1;
    }
    return t;
}

fn main() -> i64 {
    print_i64(mid(2000000));
    print("\n");
    return 0;
}
MO

# ---- 1. 基线：不开 -p 时结果必须完全一致 ----
$HERE/bin/moc t.mo t0.elf >/dev/null 2>&1
$HERE/bin/moc t.mo -p t.elf >/dev/null 2>&1
A=$(./t0.elf 2>/dev/null | head -1)
B=$(./t.elf 2>/dev/null | head -1)
ck "$B" "$A" "开 -p 后程序结果不变（插桩不改变语义）"

# ---- 2. 三个函数都被自动插桩 ----
OUT=$(./t.elf 2>/dev/null)
echo "$OUT" | grep -q "^main " && ck 1 1 "main 被插桩"
echo "$OUT" | grep -q "^mid " && ck 1 1 "mid 被插桩"
echo "$OUT" | grep -q "^leaf " && ck 1 1 "leaf 被插桩"

# ---- 3. 调用次数必须正确（mid 里 20 次循环 → leaf 20 次）----
CNT=$(echo "$OUT" | awk '$1=="leaf"{print $2}')
ck "$CNT" "20" "leaf 调用次数 = 20（自动插桩计数正确）"
CNT2=$(echo "$OUT" | awk '$1=="mid"{print $2}')
ck "$CNT2" "1" "mid 调用次数 = 1"

# ---- 4. 计时必须真的在工作（不是全 0）----
MS=$(echo "$OUT" | awk '$1=="leaf"{print $3}')
MS_I=${MS%%.*}
[ "${MS_I:-0}" -gt 0 ] && ck 1 1 "leaf 累计耗时 > 0（clock_gettime 真的在工作）" || ck 0 1 "leaf 累计耗时 > 0"

# ---- 5. 自身耗时剥离：leaf 自身≈累计，mid 自身≈0 ----
LS=$(echo "$OUT" | awk '$1=="leaf"{print $4}'); LI=${LS%%.*}
MSF=$(echo "$OUT" | awk '$1=="mid"{print $4}'); MI=${MSF%%.*}
[ "${LI:-0}" -gt 0 ] && ck 1 1 "leaf 自身耗时 > 0（它没有子调用）" || ck 0 1 "leaf 自身耗时 > 0"
[ "${MI:-0}" -eq 0 ] && ck 1 1 "mid 自身耗时 = 0（时间全在 leaf 里）" || ck 0 1 "mid 自身耗时 = 0"

# ---- 6. 库函数不被插桩（否则报告会被 strlen/print 淹没）----
echo "$OUT" | grep -q "^strlen" && ck 0 1 "库函数不被插桩" || ck 1 1 "库函数不被插桩"

# ---- 7. 缺 import 时必须明确报错，不能静默产出空报告 ----
cat > bad.mo <<'MO'
import "io.mo";
fn main() -> i64 { print("x\n"); return 0; }
MO
$HERE/bin/moc bad.mo -p bad.elf >/tmp/proftest_bad 2>&1
grep -q "requires" /tmp/proftest_bad && ck 1 1 "缺 import prof.mo → 明确报错" || ck 0 1 "缺 import prof.mo → 明确报错"

# ---- 8. 手工插桩仍然可用 ----
cat > man.mo <<'MO'
import "io.mo";
import "prof.mo";
fn main() -> i64 {
    prof_enter("alpha");
    let s: i64 = 0;
    let i: i64 = 0;
    while i < 500000 { s = s + i; i = i + 1; }
    prof_leave();
    prof_report();
    return 0;
}
MO
$HERE/bin/moc man.mo man.elf >/dev/null 2>&1
./man.elf 2>/dev/null | grep -q "^alpha " && ck 1 1 "手工插桩可用" || ck 0 1 "手工插桩可用"

echo ""
echo "通过 $PASS / 失败 $FAIL"
[ "$FAIL" = "0" ]
