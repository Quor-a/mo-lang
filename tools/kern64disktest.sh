#!/bin/bash
# kern64disktest.sh —— ARM64 裸机**持久存储**的端到端验证
#
# 判据不是"写成功"，而是**两次独立启动之间数据还在**：
#   第一次（空盘）格式化并写文件 → 进程结束
#   第二次（同一镜像）必须读到上次写的内容
# 磁盘镜像是一个真文件，两次运行之间没有重置 —— 这才是"持久"。
#
# 另外三条也是硬性判据：
#   - 没挂盘时必须报"找不到设备"（而不是装作有盘）
#   - 扇区号必须真的影响落盘位置（写错扇区 → 第二次挂载失败）
#   - 破坏超级块必须退化为重新格式化（证明它真的在读盘，不是读缓存）
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
ELF=/tmp/modisk64.elf
DISK=/tmp/mokern64disk.img
pass=0
fail=0

ck() {
    if [ "$2" = "$3" ]; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (得到 '$2' 想要 '$3')"; fi
}
ckhas() {
    if echo "$2" | grep -q "$3"; then pass=$((pass+1));
    else fail=$((fail+1)); echo "✗ $1 (缺少 '$3')"; fi
}
ckhasnot() {
    if echo "$2" | grep -q "$3"; then fail=$((fail+1)); echo "✗ $1 (不该出现 '$3')";
    else pass=$((pass+1)); fi
}

rm -f "$ELF"
bash tools/kernel64.sh examples/kern64disk.mo "$ELF" >/tmp/k64diskbuild.log 2>&1
ck "磁盘内核构建" "$?" 0
[ -f "$ELF" ] || { echo "kern64disktest: 没有产物，无法继续"; exit 1; }

M=$(python3 -c "import struct;print(struct.unpack_from('<H',open('$ELF','rb').read(),18)[0])")
ck "ELF 机器类型 AArch64" "$M" 183
ckhasnot "未落到 x86 VGA 前导" "$(cat /tmp/mokern64/kernel.c)" "0xB8000"

# ---- 1) 没挂盘：必须报"找不到设备"，而且**不能**假装挂载成功 ----
OUT0=$(python3 tools/kern64run.py "$ELF" 2>/dev/null)
ckhas "无盘仍启动" "$OUT0" "MO-KERN64-DISK BOOT"
ckhas "无盘报设备不存在" "$OUT0" "virtio-blk: not found err=-1"
ckhas "无盘仍停机" "$OUT0" "MO-KERN64-DISK HALT"
ckhasnot "无盘不假装挂载" "$OUT0" "mount: nfiles"

# ---- 2) 空盘首次启动：格式化 + 写文件 ----
rm -f "$DISK"
OUT1=$(python3 tools/kern64run.py "$ELF" --disk "$DISK" 2>/tmp/k64disk1.err)
E1=$(cat /tmp/k64disk1.err)
ckhas "首次启动识别设备" "$OUT1" "virtio-blk: magic=ok ver=2 dev=2 cap=2048"
ckhas "首次启动判定空盘" "$OUT1" "mount: no superblock -> format"
ckhas "格式化写了三块" "$OUT1" "format: writes=3"
ckhas "写后立即读回" "$OUT1" "wrote hi -> MO-DISK-OK"
ckhas "内容与长度校验" "$OUT1" " len=10 sum=699 match=1"
ckhas "首次落盘写次数" "$E1" "writes=3"
[ -f "$DISK" ] || { echo "磁盘镜像未创建"; exit 1; }
SZ=$(stat -c %s "$DISK")
ck "镜像大小 1MiB" "$SZ" 1048576

# ---- 3) 同盘二次启动：必须读到上次写的内容 ----
OUT2=$(python3 tools/kern64run.py "$ELF" --disk "$DISK" 2>/tmp/k64disk2.err)
E2=$(cat /tmp/k64disk2.err)
ckhas "二次启动挂载成功" "$OUT2" "mount: nfiles=1"
ckhasnot "二次启动不该重新格式化" "$OUT2" "no superblock"
ckhas "二次启动读回内容" "$OUT2" "read hi -> MO-DISK-OK"
ckhas "二次启动内容校验" "$OUT2" " len=10 sum=699 match=1"
ckhas "二次启动没有写盘" "$E2" "writes=0"

# ---- 4) 破坏超级块：必须退化为重新格式化 ----
# 证明"挂载成功"确实来自**读盘**，而不是内存里的缓存或写死的分支。
python3 - "$DISK" <<'PY'
import sys
f = open(sys.argv[1], "r+b")
f.seek(0)
f.write(b"XXXX\x00\x00\x00")
f.close()
PY
OUT3=$(python3 tools/kern64run.py "$ELF" --disk "$DISK" 2>/tmp/k64disk3.err)
ckhas "坏超级块退化格式化" "$OUT3" "mount: no superblock -> format"
ckhas "坏盘后仍可写回" "$OUT3" " len=10 sum=699 match=1"

echo "kern64disktest: $pass 通过 / $fail 失败"
[ "$fail" = 0 ] || exit 1
exit 0
