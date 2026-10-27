#!/usr/bin/env bash
# a64xselfmut —— 证明 a64xself 的判据**真的会响**
#
# 做法：故意把实现改坏 → 重跑 a64xself → 必须有断言变红。
# 判据自己说自己有效不算数（本项目反复栽在这上面：SA_NCL=0 的克隆分支、
# CMS w=200 的无碰撞、adrp 页偏移恒为 0，都是"全绿但一条没验到"）。
#
# 每个变异都要能回答：它改坏的是**哪条因果链**。
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
TMP=/tmp/a64xselfmut
mkdir -p $TMP
PASS=0; FAILN=0

run() { timeout 900 bash $ROOT/tools/a64xself.sh 2>&1 | tail -1; }

mut() {
  NAME=$1; FILE=$2; FROM=$3; TO=$4
  cp "$FILE" $TMP/$(basename $FILE).bak
  python3 - "$FILE" "$FROM" "$TO" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(a) >= 1, "锚点未命中: %r" % a
open(p, 'w').write(s.replace(a, b))
PY
  if [ $? -ne 0 ]; then echo "✗ $NAME：锚点未命中，变异未生效"; FAILN=$((FAILN+1)); return; fi
  case "$FILE" in
    *mo2x.mo) make bin/mo2x > /dev/null 2>&1 || { echo "✗ $NAME：mo2x 重建失败"; FAILN=$((FAILN+1)); return; };;
  esac
  R=$(run)
  # 🔴 顺序：**先还原源码，再重建**。
  # 第一版写成"先 make 再 cp bak"，于是 bin/mo2x 是用**变异版**源码编出来的，
  # 而源码随后才被还原 —— 二进制里留着变异，此后的每个变异都在污染态上跑，
  # 于是 M4/M5 的"被捕获"是假的（它们只是撞上了 M3 残留的坏 mo2x）。
  # 这是「验证工具自身静默失效」的又一例，且比测试空转更隐蔽：
  # 它让验证脚本**假装验证了**，还给出"5 捕获 / 0 未捕获"的好看结论。
  cp $TMP/$(basename $FILE).bak "$FILE"
  case "$FILE" in
    *mo2x.mo) make bin/mo2x > /dev/null 2>&1 || { echo "✗ $NAME：还原后重建失败"; FAILN=$((FAILN+1)); return; };;
  esac
  case "$R" in
    *"/ 0 失败") echo "✗ $NAME：**未被捕获**（仍 $R）"; FAILN=$((FAILN+1));;
    *) echo "✓ $NAME 被捕获（$R）"; PASS=$((PASS+1));;
  esac
}

echo "a64xselfmut:"

# ── 基线 ──
B=$(run)
echo "  基线: $B"
case "$B" in *"/ 0 失败") ;; *) echo "✗ 基线就不干净，后面的结论都不可信"; exit 1;; esac

# M1：ARM64 的 write 调用号写错（64 → 63，即 read）
#   因果链：汇编器往 stdout 打印、以及把 ELF 写进文件，全靠 write。
#   号错了 ARM64 端就既没有统计输出也没有产物。
mut "M1 write 号 64→63" tools/mo2x.mo \
    'if n == 1   { return 64;  }   # write' \
    'if n == 1   { return 63;  }   # write'

# M2：模拟器对**已预置**的文件也报 -ENOENT
#   因果链：--preload 是"ARM64 端真读了输入文件"的唯一入口。
#   它失效后程序拿到空输入，却可能照样"成功"—— 这一条专门盯住它。
mut "M2 preload 失效" tools/armrun.py \
    '            if path in FS_DATA:' \
    '            if False and path in FS_DATA:'

# M3：cfs 后端 store8 写偏一个字节
#   因果链：汇编器逐字节拼 ELF，任何一处写偏都会让 ARM64 产物 ≠ x86 产物。
#   这一条专门验证「两端 md5 比对」这一层不是摆设。
mut "M3 store8 写偏" tools/mo2x.mo \
    '#define store8(p,v)  (*(unsigned char*)(p) = (unsigned char)(v))' \
    '#define store8(p,v)  (*(unsigned char*)((char*)(p)+1) = (unsigned char)(v))'

# M4：ELF 头的 e_machine 写成 x86-64 的 62
#   因果链：两端用同一份源码，所以 md5 会**一起**变、仍然相同 ——
#   md5 这一层抓不到它。能抓它的是裸机层（load_elf64 断言 machine==183）。
#   这两个变异一起证明了「只比 md5 不够，必须有裸机执行层」。
mut "M4 e_machine 写 62" examples/a64as.mo \
    'st16(18, 183);' \
    'st16(18, 62);'

# M5：**预期未被捕获** —— 改一条指令编码里不影响执行的位
#   因果链：两端同源，md5 仍相同；裸机也照样跑出正确输出（该位不影响语义）。
#   它留在这里是为了钉住一件事：a64xself 证明不了"每条编码都正确"，
#   那是 a64test 的四层判据（含独立解码对拍）负责的。
mut "M5 ELF e_flags（预期未捕获）" examples/a64as.mo \
    'st32(48, 0);' \
    'st32(48, 7);'

echo "$PASS 捕获 / $FAILN 未捕获"
