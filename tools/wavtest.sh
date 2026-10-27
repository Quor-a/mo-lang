#!/bin/bash
# wavtest —— 端到端验证 examples/wavinfo.mo
#
#   bash tools/wavtest.sh
#
# 为什么单独做：wavinfo 是 lib/pack.mo 的实战验证，
# 它压到字节序解析、chunk 遍历、对齐填充、以及**三种错误路径**。
# 单元测试测不到"给一个真文件能不能解析对"。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/mowav
rm -rf $W; mkdir -p $W/lib
cp lib/*.mo $W/lib/
cp examples/wavinfo.mo $W/test.mo
( cd $W && "$ROOT/bin/moc" >/dev/null 2>&1 )
[ -x $W/out.elf ] || { echo "编译失败"; exit 1; }

fail=0
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  ✓ $d"; else echo "  ✗ $d"; fail=$((fail+1)); fi; }

# 用 python 生成一个已知参数的 WAV：立体声 / 44100Hz / 16bit / 1 秒
python3 - <<'PY'
import wave, struct, math
w = wave.open('/tmp/mowav/a.wav','w')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
fr = bytearray()
for i in range(44100):
    v = int(20000*math.sin(2*math.pi*440*i/44100))
    fr += struct.pack('<hh', v, v)
w.writeframes(bytes(fr)); w.close()
PY
[ -f $W/a.wav ] || { echo "生成测试文件失败（需要 python3）"; exit 1; }

out=$( cd $W && ./out.elf a.wav 2>&1 ); rc=$?
echo "wavtest:"
chk "正常解析退出码 0"    test $rc -eq 0
chk "格式 = PCM"          grep -q 'format    : PCM' <<< "$out"
chk "声道 = 2"            grep -q 'channels  : 2' <<< "$out"
chk "采样率 = 44100"      grep -q 'rate      : 44100 Hz' <<< "$out"
chk "位深 = 16"           grep -q 'bits      : 16-bit' <<< "$out"
chk "字节率 = 176400"     grep -q 'byterate  : 176400' <<< "$out"
chk "时长 = 1.00 s"       grep -q 'duration  : 1.00 s' <<< "$out"
chk "data 偏移 = 44"      grep -q 'data      : 176400 bytes @ offset 44' <<< "$out"

# --- 三种错误路径：必须给出**具体**原因，不能一句 "error" ---
( cd $W && ./out.elf nope.wav >e1.txt 2>&1 ); e1=$(cat $W/e1.txt)
chk "缺文件 → E_FOUND(6)"  grep -q 'error\[6\]' <<< "$e1"
chk "缺文件 → 位置可追溯"  grep -q 'stat_size' <<< "$e1"

printf 'this is definitely not a wav file' > $W/bad.txt
( cd $W && ./out.elf bad.txt >e2.txt 2>&1 ); e2=$(cat $W/e2.txt)
chk "非 WAV → E_FORMAT(3)" grep -q 'error\[3\]' <<< "$e2"
chk "非 WAV → 说明是魔数"  grep -q 'not a RIFF' <<< "$e2"

head -c 100 $W/a.wav > $W/trunc.wav
( cd $W && ./out.elf trunc.wav >e3.txt 2>&1 ); e3=$(cat $W/e3.txt)
chk "截断 → E_RANGE(2)"    grep -q 'error\[2\]' <<< "$e3"
chk "截断 → 说明被截断"    grep -q 'truncated' <<< "$e3"

if [ $fail -eq 0 ]; then echo "wavtest: OK（全部通过）"; else echo "wavtest: $fail 项未通过"; exit 1; fi
