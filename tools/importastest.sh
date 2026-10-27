#!/bin/bash
# import "x.mo" as N; —— 模块命名空间
#
# 正例全部给**具体数字**，不是"能编译就行"：
#   123 = A.calla()*100 + B.callb()*10 + (A.helper()+B.helper())
#       = 1*100 + 2*10 + 3
#   其中 calla/callb 是各库内部对自己 helper 的调用 —— 若内部自调用绑错
#   （都绑到后导入的那个），A.calla() 会得 2，结果变成 223。
#   只看"两个库都能编译"完全分不出这两种情况。
#
# 负例必须检查**退出码非 0 且报错含期望片段**。只看退出码的话，
# "因为别的原因编译失败"也会被算作通过。
cd "$(dirname "$0")/.." || exit 1
MOC=${MOC:-bin/moc}
# 转绝对路径：下面每个用例都要 cd 到 /tmp/mot 里跑（编译产物、文件系统类
# 用例必须在那里），相对路径一 cd 就失效 —— 症状是"全部编译失败"。
MOC="$(cd "$(dirname "$MOC")" && pwd)/$(basename "$MOC")"
pass=0; fail=0

# 运行用例：期望退出码 = $2
run_case() {
  local dir=$1 exp=$2
  rm -rf /tmp/mot && mkdir -p /tmp/mot || exit 1
  cp lib/*.mo /tmp/mot/ 2>/dev/null
  cp tests/"$dir"/*.mo /tmp/mot/ || exit 1
  mv /tmp/mot/main.mo /tmp/mot/test.mo
  ( cd /tmp/mot && "$MOC" ) >/tmp/iat.log 2>&1
  local crc=$?
  if [ $crc -ne 0 ]; then
    echo "FAIL $dir 编译失败：$(head -2 /tmp/iat.log | tr '\n' ' ')"
    fail=$((fail+1)); return
  fi
  ( cd /tmp/mot && ./out.elf ); local got=$?
  if [ "$got" = "$exp" ]; then echo "PASS $dir = $got"; pass=$((pass+1));
  else echo "FAIL $dir 期望 $exp 实得 $got"; fail=$((fail+1)); fi
}

# 编译错误用例：必须编译失败，且报错包含 $2
err_case() {
  local name=$1 frag=$2 src=$3
  rm -rf /tmp/mot && mkdir -p /tmp/mot || exit 1
  cp lib/*.mo /tmp/mot/ 2>/dev/null
  printf '%s\n' "$src" > /tmp/mot/test.mo
  for f in $4; do cp "$f" /tmp/mot/; done
  local out
  out=$( cd /tmp/mot && "$MOC" 2>&1 ); local rc=$?
  if [ $rc -eq 0 ]; then
    echo "FAIL $name 应报错但编译通过"; fail=$((fail+1)); return
  fi
  if ! echo "$out" | grep -q "$frag"; then
    echo "FAIL $name 报错不含 '$frag'（实得：$out）"; fail=$((fail+1)); return
  fi
  echo "PASS $name 已拦下：$frag"; pass=$((pass+1))
}

echo "--- 正例 ---"
run_case 143_importas        123
run_case 144_importas_rev    123
run_case 145_importas_mix     15
run_case 146_importas_global   8

echo "--- 负例 ---"
# 模块名未定义：必须回退到"未定义变量"路径报错，而不是静默通过
err_case "未定义模块名" "undefined symbol 'X'" \
  'fn main() -> i64 { return X.helper(); }' ""
# 模块存在但函数不在其中
err_case "模块内无此函数" "undefined symbol 'nosuch'" \
  'import "ambA.mo" as A;
fn main() -> i64 { return A.nosuch(); }' "tests/143_importas/ambA.mo"
# 隔离生效：带 as 之后裸名不再可见（只测正向"能调用"证明不了隔离）
err_case "带 as 后裸调用" "undefined symbol 'helper'" \
  'import "ambA.mo" as A;
fn main() -> i64 { return helper(); }' "tests/143_importas/ambA.mo"
# 同一文件先裸 import 再带 as：会得到一个"空模块"，
# A.anything() 会静默回退到全局 —— 必须拦下
err_case "重复 import as" "already imported" \
  'import "ambA.mo";
import "ambA.mo" as A;
fn main() -> i64 { return 1; }' "tests/143_importas/ambA.mo"

echo "通过 $pass / 失败 $fail"
[ "$fail" = 0 ] || exit 1
exit 0
