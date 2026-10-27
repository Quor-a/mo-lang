#!/usr/bin/env bash
# wavobjtest —— 类的实战检验：wavobj（类版）与 wavinfo（全局变量版）输出比对
#
# 为什么单独做：方法语法 obj.method() 的单元测试只能证明它能跑，
# 只有写真实程序才知道好不好用。而"能跑"也不等于"结果对" ——
# 所以让两个**独立实现**在同一份真 WAV 上跑，除 file 行外逐字节比对。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

W=/tmp/mowavobj; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/

python3 - <<'PY' || { echo "wavobjtest: 需要 python3 生成测试文件"; exit 1; }
import wave, struct, math
w = wave.open('/tmp/mowavobj/a.wav','w')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
fr = bytearray()
for i in range(44100):
    v = int(20000*math.sin(2*math.pi*440*i/44100))
    fr += struct.pack('<hh', v, v)
w.writeframes(bytes(fr)); w.close()
PY

fail=0
run() {   # run <源码> <输出文件>
    cp $ROOT/examples/$1 $W/test.mo
    ( cd $W && rm -f out.elf && timeout 600 $ROOT/bin/moc >/dev/null 2>&1 )
    if [ ! -f $W/out.elf ]; then echo "  ✗ $1 编译失败"; fail=$((fail+1)); return 1; fi
    ( cd $W && timeout 60 ./out.elf /tmp/mowavobj/a.wav > $2 2>&1 )
    return 0
}

run wavinfo.mo $W/info.out
run wavobj.mo  $W/obj.out

if [ $fail -eq 0 ]; then
    # file 行不同（wavobj 用 sfmt 拼了路径，wavinfo 是 print(path)），去掉后比对
    grep -v '^file' $W/info.out > $W/i2.out
    grep -v '^file' $W/obj.out  > $W/o2.out
    if diff -q $W/i2.out $W/o2.out >/dev/null 2>&1; then
        echo "  ✓ 类版输出 == 全局变量版输出（逐字节）"
    else
        echo "  ✗ 两版输出不一致："
        diff $W/i2.out $W/o2.out | head -12
        fail=$((fail+1))
    fi
    # 关键字段抽查
    for k in "format    : PCM" "channels  : 2" "rate      : 44100 Hz" \
             "bits      : 16-bit" "byterate  : 176400 B/s" "duration  : 1.00 s"; do
        if grep -q "$k" $W/obj.out; then echo "  ✓ $k";
        else echo "  ✗ 缺: $k"; fail=$((fail+1)); fi
    done
fi

# 错误路径：类版也要给出**具体**原因（err.mo 的承诺）
for bad in /tmp/mowavobj/nope.wav; do
    O=$( cd $W && timeout 60 ./out.elf $bad 2>&1 )
    if [ -n "$O" ]; then echo "  ✓ 不存在的文件有错误信息: $O";
    else echo "  ✗ 不存在的文件无错误信息"; fail=$((fail+1)); fi
done
RC=$( cd $W && timeout 60 ./out.elf /tmp/mowavobj/nope.wav >/dev/null 2>&1; echo $? )
if [ "$RC" = "1" ]; then echo "  ✓ 错误时退出码 1"; else echo "  ✗ 错误时退出码 $RC"; fail=$((fail+1)); fi

# 坏魔数
printf 'notawav' > $W/bad.wav
O2=$( cd $W && timeout 60 ./out.elf $W/bad.wav 2>&1 )
if [ -n "$O2" ]; then echo "  ✓ 坏魔数有错误信息: $O2";
else echo "  ✗ 坏魔数无错误信息"; fail=$((fail+1)); fi

if [ $fail -eq 0 ]; then echo "wavobjtest: OK（类的实战检验通过）"; exit 0; fi
echo "wavobjtest: FAILED（$fail 项）"; exit 1
