#!/bin/bash
# sysnocheck —— 核对 mo2x 的 x86→asm-generic 系统调用号翻译表
#
#   bash tools/sysnocheck.sh
#
# 为什么需要它
# ------------
# fs_sysno_generic() 这张表此前**全靠人肉对照**，而人肉对照会漏。
# 实测抓到过：getdents64 写成 217→217，而 217 是 x86-64 的号，
# ARM64（asm-generic）的 getdents64 = **61**，ARM64 的 217 是 add_key。
#
# 后果的形态正是本项目最警惕的那一种：不报错、不崩溃、不链接失败，
# 只是在手机上发了一个完全不相干的系统调用。所以只能靠**与内核头文件
# 逐条比对**把它钉住。
#
# 判据
# ----
# 表内每一项 (x86号 → 通用号, 名字) 必须与 asm-generic/unistd.h 里
# 该名字的定义一致。任何不一致 → 非 0 退出。
# 头文件不存在时**明确报错退出**，不静默跳过（静默跳过 = 检查恒绿）。

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)

GEN=/usr/include/asm-generic/unistd.h
if [ ! -f "$GEN" ]; then
    echo "FAIL 找不到 $GEN —— 无法核对（不静默跳过）"
    exit 1
fi

python3 - "$ROOT" "$GEN" <<'PY'
import re, sys

root, hdr = sys.argv[1], sys.argv[2]

# 1) 从 mo2x.mo 里抽出 fs_sysno_generic 的映射表
src = open(root + "/tools/mo2x.mo").read()
i = src.index("fn fs_sysno_generic(n: i64) -> i64 {")
j = src.index("\n}\n", i)
body = src[i:j]

rows = []
for mm in re.finditer(
        r"if n == (\d+)\s*\{(?:\s*FS_ATINS = 1;)?(?:\s*FS_ATTAIL = 1;)?\s*"
        r"return (-?\d+);\s*\}\s*#[ \t]*([^\n]+)", body):
    x86, gen, comment = int(mm.group(1)), int(mm.group(2)), mm.group(3)
    # 注释形如 "open   → openat"：目标名在箭头之后；没有箭头就是它自己
    if "→" in comment:
        name = comment.split("→", 1)[1]
    else:
        name = comment
    name = name.strip()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        print("  ? 注释里的目标名无法解析: %r" % comment)
        continue
    if gen < 0:          # -1/-2 = 明确报错的条目，不参与号核对
        continue
    rows.append((x86, gen, name))

# 2) 从内核头文件读出 asm-generic 的号
h = open(hdr).read()
num = {}
for mm in re.finditer(r"#define __NR_(\w+)\s+(?:__NR3264_(\w+)|(\d+))", h):
    name = mm.group(1)
    if mm.group(3):
        num[name] = int(mm.group(3))
    else:
        # __NR3264_xxx 在文件里另有定义（如 __NR3264_lseek = 62）
        alias = mm.group(2)
        m2 = re.search(r"#define __NR3264_%s\s+(\d+)" % alias, h)
        if m2:
            num[name] = int(m2.group(1))

if not rows:
    print("FAIL 未能从 mo2x.mo 抽出翻译表 —— 检查器自己失效了")
    sys.exit(1)

bad = 0
print("x86-64  通用号  表内  头文件  名字")
for x86, gen, name in rows:
    real = num.get(name)
    if real is None:
        print("  ? 头文件里没有 %s —— 无法核对（不静默放行）" % name)
        bad += 1
        continue
    ok = (real == gen)
    if not ok:
        bad += 1
    print("%6d  %5d  %5d  %s  %s%s"
          % (x86, gen, real, name, "OK" if ok else "*** 不一致 ***", ""))

print()
if bad:
    print("FAIL 翻译表 %d 处与内核头文件不一致" % bad)
    sys.exit(1)
print("OK 翻译表 %d 项与 asm-generic/unistd.h 逐条一致" % len(rows))
PY
