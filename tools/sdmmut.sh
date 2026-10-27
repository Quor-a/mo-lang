#!/bin/bash
# sdmmut —— SDM 的变异验证
#   只跑测试证明"没坏"不够：必须证明**改坏了测试会红**。
#   三个变异各自对应本轮真实踩到/预防的缺陷。
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MOC="$HERE/bin/moc"
SRC="$HERE/lib/sdm.mo"
cp -f "$SRC" /tmp/sdm.bak
restore() { if [ -f /tmp/sdm.bak ]; then cp -f /tmp/sdm.bak "$SRC"; fi; }
trap restore EXIT

run() {
  rm -rf /tmp/mot && mkdir -p /tmp/mot
  cp "$HERE"/lib/*.mo /tmp/mot/
  cp "$HERE"/tests/124_sdm.mo /tmp/mot/test.mo
  ( cd /tmp/mot && "$MOC" ) >/dev/null 2>&1 || { echo "编译失败"; return; }
  chmod +x /tmp/mot/out.elf 2>/dev/null
  ( cd /tmp/mot && ./out.elf )
}

# 开工前先验源码干净：上一轮的污染会一路传染 —— 备份备份了污染版本，
# 于是三个变异的"还原"全都还原成污染版本，脚本却照样打印全绿。
if grep -q "SDSBM \* 255" "$SRC" || grep -q "SDCNT\[SDI\] = 0;" "$SRC" || grep -q "SDVP\[loc \* SDW" "$SRC"; then
  echo "[!!] 开工前发现源码已有变异痕迹，先手动恢复 lib/sdm.mo"; exit 1
fi

echo "== 基线（未变异）=="
run | tail -3

echo ""
echo "== M1 硬位置比错数组：sdm_ham_loc 退回比 SDVP =="
python3 - <<'EOF'
p='/data/workspace/mo/lib/sdm.mo'
s=open(p).read()
s=s.replace("SDPJ = SDPJ + sdm_popcnt(SDVP[a + SDPI] ^ SDLOC[loc * SDW + SDPI]);",
            "SDPJ = SDPJ + sdm_popcnt(SDVP[a + SDPI] ^ SDVP[loc * SDW + SDPI]);")
open(p,'w').write(s)
EOF
run | grep -E "^FAIL|通过|failed" | tail -5
restore

echo ""
echo "== M2 SWAR 加减合并成一个 delta 字（跨字节进位）=="
python3 - <<'EOF'
p='/data/workspace/mo/lib/sdm.mo'
s=open(p).read()
s=s.replace("""                SDT = SDT + SDADM;
                SDT = SDT - SDSBM;""",
"""                SDT = SDT + SDADM - (SDSBM * 255);""")
open(p,'w').write(s)
EOF
run | grep -E "^FAIL|通过|failed" | tail -5
restore

echo ""
echo "== M3 内容区初始化为 0 而非偏移 0x80 =="
python3 - <<'EOF'
p='/data/workspace/mo/lib/sdm.mo'
s=open(p).read()
s=s.replace("        SDCNT[SDI] = SDMSB;","        SDCNT[SDI] = 0;")
open(p,'w').write(s)
EOF
run | grep -E "^FAIL|通过|failed" | tail -5
restore

# 还原后必须确认源码里不再有变异痕迹 —— 上一轮的 modmut 就是还原失败却仍报全绿
if grep -q "SDSBM \* 255" "$SRC" || grep -q "SDCNT\[SDI\] = 0;" "$SRC"; then
  echo "[!!] 还原失败：源码里仍有变异痕迹"
fi
echo ""
echo "== 还原后复跑 =="
run | tail -2
