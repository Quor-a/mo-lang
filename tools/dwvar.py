#!/usr/bin/env python3
# dwvar —— 验证 -g 生成的**变量位置**真的对得上机器码
#
# 为什么需要它：readelf 能把 DIE 打出来，但打出来"有变量"不等于
# "位置正确"。gdb 才是最终裁判，可本机没有 gdb。
#
# 所以这里做一件更硬的事：
#   1. 从 .debug_info 读出每个局部变量的 fbreg 偏移
#   2. 反汇编该函数，找出所有 [rbp+off] 形式的访问
#   3. 断言：DWARF 里记的每个偏移，都能在**该函数的机器码**里
#      找到对应的 [rbp+off] 访问
#
# 这一步能抓住"偏移算错 / 变量归错函数 / sleb 编码错"这类错误，
# 它们都会让 gdb 读出垃圾值。

import re
import subprocess
import sys
import os
import tempfile
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MOC = os.path.join(ROOT, "bin", "moc")

PASS = 0
FAIL = 0


def check(name, cond, info=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  \u2713 %s" % name)
    else:
        FAIL += 1
        print("  \u2717 %s %s" % (name, info))


SRC = '''import "io.mo";

struct Point { x: i64; y: i64; }

var TOTAL: i64 = 0;
var LIMIT: i64 = 100;

fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn addup(a: i64, b: i64) -> i64 {
    let t: i64 = a;
    let fl: f64 = 1.5;
    let bl: bool = true;
    let sp: ptr = "hi";
    let bf: [4] i64 = 0;
    let p: Point;
    return t + b;
}

fn main() -> i64 {
    let i: i64 = 0;
    let s: i64 = 0;
    while i < 10 {
        s = s + fib(i);
        i = i + 1;
    }
    return s + addup(1, 2);
}
'''


def parse_info(elf):
    """从 readelf 输出里解析 (函数名, [(变量名, fbreg偏移, 行号)])。"""
    out = subprocess.run(["readelf", "--debug-dump=info", elf],
                         capture_output=True, text=True).stdout
    funcs = []
    cur = None
    for line in out.split("\n"):
        m = re.search(r"DW_TAG_subprogram", line)
        if m:
            cur = {"name": None, "vars": []}
            funcs.append(cur)
            continue
        m = re.search(r"DW_TAG_variable", line)
        if m:
            # 全局变量是 CU 的直接子 DIE —— 前面没有 subprogram。
            # 第一版只在遇到 subprogram 时才建 cur，于是 TOTAL/LIMIT
            # 要么被吞进上一个函数、要么整个漏掉，
            # 表现为"断言找不到全局变量"，而 DIE 其实生成了。
            if cur is None:
                cur = {"name": None, "vars": []}
                funcs.append(cur)
            cur["vars"].append({"name": None, "fb": None, "line": None})
            continue
        m = re.search(r"DW_AT_name\s*:\s*(\S+)", line)
        if m and cur is not None:
            if cur["vars"] and cur["vars"][-1]["name"] is None:
                cur["vars"][-1]["name"] = m.group(1)
            elif cur["name"] is None:
                cur["name"] = m.group(1)
            continue
        m = re.search(r"DW_OP_fbreg:\s*(-?\d+)", line)
        if m and cur["vars"]:
            cur["vars"][-1]["fb"] = int(m.group(1))
            continue
        m = re.search(r"DW_AT_decl_line\s*:\s*(\d+)", line)
        if m and cur["vars"] and cur["vars"][-1]["name"]:
            cur["vars"][-1]["line"] = int(m.group(1))
    return funcs


def rbp_offsets(elf, lo, hi):
    """反汇编 [lo,hi) 区间的代码，收集所有 rbp 相对偏移。"""
    # .text 的 vaddr 是 0x400000+176=0x4000b0，文件偏移 176
    base = 0x4000b0
    foff = 176
    text = open(elf, "rb").read()
    start = foff + (lo - base)
    end = foff + (hi - base)
    blob = text[start:end]
    tmp = tempfile.mktemp(suffix=".bin")
    open(tmp, "wb").write(blob)
    out = subprocess.run(
        ["objdump", "-D", "-b", "binary", "-m", "i386:x86-64",
         "--adjust-vma=0x%x" % lo, tmp],
        capture_output=True, text=True).stdout
    os.unlink(tmp)
    offs = set()
    for m in re.finditer(r"-0x([0-9a-f]+)\(%rbp\)", out):
        offs.add(-int(m.group(1), 16))
    for m in re.finditer(r"0x([0-9a-f]+)\(%rbp\)", out):
        offs.add(int(m.group(1), 16))
    return offs


def parse_frames(elf):
    """解析 readelf --debug-dump=frames 的输出。"""
    out = subprocess.run(["readelf", "--debug-dump=frames", elf],
                         capture_output=True, text=True).stdout
    fdes = []
    cur = None
    for line in out.split("\n"):
        m = re.search(r"FDE cie=\S+ pc=([0-9a-f]+)\.\.([0-9a-f]+)", line)
        if m:
            cur = {"lo": int(m.group(1), 16), "hi": int(m.group(2), 16),
                   "cfa_reg": None}
            fdes.append(cur)
            continue
        if cur is not None:
            m = re.search(r"DW_CFA_def_cfa_register:\s*r\d+\s*\((\w+)\)", line)
            if m:
                cur["cfa_reg"] = m.group(1)
            m = re.search(r"DW_CFA_def_cfa:\s*r\d+\s*\((\w+)\)", line)
            if m and cur["cfa_reg"] is None:
                cur["cfa_reg"] = m.group(1)
    return fdes


def die_blocks(elf):
    """把 readelf --debug-dump=info 的输出切成 DIE 块。

    返回 [(off, tag, {attr: value})]。
    按 DIE 块切分而不是靠逐行状态机 —— 后者在遇到
    "没有 DW_AT_name 的 DIE"（pointer/array/subrange）时会串味。
    """
    out = subprocess.run(["readelf", "--debug-dump=info", elf],
                         capture_output=True, text=True).stdout
    blocks = []
    cur = None
    for line in out.split("\n"):
        m = re.search(r"<\d+><([0-9a-f]+)>: Abbrev Number: \d+ \((DW_TAG_\w+)\)",
                      line)
        if m:
            cur = (m.group(1), m.group(2), {})
            blocks.append(cur)
            continue
        if cur is None:
            continue
        m = re.search(r"DW_AT_(\w+)\s*:\s*(.*?)\s*$", line)
        if m:
            cur[2][m.group(1)] = m.group(2)
    return blocks


def parse_types(elf):
    """[(类型名, tag)]，按出现顺序。"""
    res = []
    for off, tag, at in die_blocks(elf):
        if tag in ("DW_TAG_base_type", "DW_TAG_structure_type"):
            if "name" in at:
                res.append((at["name"], tag))
    return res


def parse_var_types(elf):
    """{变量名: 引用到的类型名或 tag}。

    只记**第一次**出现 —— 同名局部变量以先出现的（声明在前的函数）为准。
    """
    blocks = die_blocks(elf)
    # 偏移 -> 类型展示名
    off2ty = {}
    for off, tag, at in blocks:
        if tag in ("DW_TAG_base_type", "DW_TAG_structure_type"):
            off2ty[off] = at.get("name", tag)
        elif tag in ("DW_TAG_pointer_type", "DW_TAG_array_type"):
            off2ty[off] = tag
    res = {}
    for off, tag, at in blocks:
        if tag != "DW_TAG_variable":
            continue
        nm = at.get("name")
        ty = at.get("type", "")
        m = re.match(r"<0x([0-9a-f]+)>", ty)
        if not (nm and m):
            continue
        key = m.group(1).lstrip("0") or "0"
        # 目标可能是 base/struct（有名）或 pointer/array（无名）
        if key in off2ty:
            res.setdefault(nm, off2ty[key])
        else:
            res.setdefault(nm, "?" + key)
    return res


def parse_members(elf):
    """{结构体名: [(成员名, 偏移)]}。"""
    blocks = die_blocks(elf)
    res = {}
    cur_struct = None
    for off, tag, at in blocks:
        if tag == "DW_TAG_structure_type":
            cur_struct = at.get("name")
            res[cur_struct] = []
        elif tag == "DW_TAG_member":
            if cur_struct:
                loc = at.get("data_member_location", "0")
                m = re.match(r"(\d+)", loc)
                res[cur_struct].append((at.get("name"),
                                        int(m.group(1)) if m else 0))
        elif tag in ("DW_TAG_subprogram", "DW_TAG_compile_unit"):
            cur_struct = None
    return res


def main():
    tmp = tempfile.mkdtemp(prefix="dwvar-")
    try:
        src = os.path.join(tmp, "test.mo")
        open(src, "w").write(SRC)
        for f in os.listdir(os.path.join(ROOT, "lib")):
            pass
        os.symlink(os.path.join(ROOT, "lib"), os.path.join(tmp, "lib"))
        elf = os.path.join(tmp, "test.elf")
        r = subprocess.run([MOC, "test.mo", "-g", "test.elf"],
                           cwd=tmp, capture_output=True, text=True)
        if not os.path.exists(elf):
            print("编译失败:", r.stdout[-300:], r.stderr[-300:])
            return 1
        subprocess.run(["chmod", "+x", elf])

        funcs = parse_info(elf)
        names = [f["name"] for f in funcs]
        print("== 函数表 ==")
        for want in ["fib", "addup", "main"]:
            check("函数 %s" % want, want in names, str(names))

        print("== 变量归属与位置 ==")
        by_name = {}
        for f in funcs:
            by_name[f["name"]] = f

        # addup 有局部变量 t
        addup = by_name.get("addup")
        check("addup 有变量", bool(addup and addup["vars"]))
        if addup and addup["vars"]:
            # 🔴 1.103 起**形参也有 DIE**（此前只有 let 声明的局部变量）。
            #    于是 addup 的变量是 [a, b, t]，按名字取，不能取 vars[0] ——
            #    取第一个拿到的是形参 a，看起来像"DWARF 错了"。
            #    这里顺带把形参本身也钉住：声明行应是函数签名那一行（13）。
            vn = {v["name"]: v for v in addup["vars"]}
            check("addup 含形参 a/b 与局部变量 t",
                  set(vn) == {"a", "b", "t"}, str(sorted(vn)))
            check("形参 a 声明行 = 13（函数签名行）",
                  "a" in vn and vn["a"]["line"] == 13,
                  str(vn["a"]["line"]) if "a" in vn else "无")
            if "t" in vn:
                v = vn["t"]
                check("t 的偏移为负（栈上）",
                      v["fb"] is not None and v["fb"] < 0, str(v["fb"]))
                check("t 的声明行 = 14", v["line"] == 14, str(v["line"]))

        main_f = by_name.get("main")
        check("main 有两个变量",
              bool(main_f and len(main_f["vars"]) == 2),
              str([v["name"] for v in main_f["vars"]]) if main_f else "无")
        if main_f and len(main_f["vars"]) == 2:
            vs = {v["name"]: v for v in main_f["vars"]}
            check("main 含 i 与 s", set(vs) == {"i", "s"}, str(set(vs)))
            check("i 声明行 = 24", vs["i"]["line"] == 24, str(vs["i"]["line"]))
            check("s 声明行 = 25", vs["s"]["line"] == 25, str(vs["s"]["line"]))
            # i 先声明，应在较高地址（偏移更接近 0）
            check("i 在 s 之后分配（i 偏移 > s 偏移）",
                  vs["i"]["fb"] > vs["s"]["fb"],
                  "i=%s s=%s" % (vs["i"]["fb"], vs["s"]["fb"]))

        print("== 全局变量 ==")
        # 全局变量是 CU 的直接子 DIE，出现在第一个 subprogram 之前
        # 🔴 全局变量所在容器的 **name 是 None**（那个 name 属性属于
        #    variable DIE 而不是 subprogram），所以要到 vars 里取名字。
        #    第一版按 `f["name"] in (...)` 找，永远为空 ——
        #    看起来像"全局变量没生成"，其实早就生成了。
        gvars = []
        for f in funcs:
            if f["name"] is None:
                for v in f["vars"]:
                    gvars.append(v["name"])
        gnames = gvars
        check("全局变量 TOTAL", "TOTAL" in gnames, str(gnames))
        check("全局变量 LIMIT", "LIMIT" in gnames, str(gnames))

        # 地址应落在数据段（0x10000000 起）
        addrs = []
        for line in subprocess.run(["readelf", "--debug-dump=info", elf],
                                   capture_output=True, text=True).stdout.split("\n"):
            m = re.search(r"DW_OP_addr:\s*(?:0x)?([0-9a-f]+)", line)
            if m:
                addrs.append(int(m.group(1), 16))
        check("全局变量有地址", len(addrs) >= 2, str(addrs))
        check("地址落在数据段(>=0x10000000)",
              bool(addrs) and all(a >= 0x10000000 for a in addrs),
              str([hex(a) for a in addrs]))

        print("== 位置与机器码比对（最关键）==")
        # 需要函数的 low_pc / high_pc，重新解析一次带地址的
        out = subprocess.run(["readelf", "--debug-dump=info", elf],
                             capture_output=True, text=True).stdout
        blocks = []
        cur = None
        for line in out.split("\n"):
            if "DW_TAG_subprogram" in line:
                cur = {"lo": None, "hi": None, "vars": []}
                blocks.append(cur)
            elif cur is not None:
                m = re.search(r"DW_AT_name\s*:\s*(\S+)", line)
                if m and cur.get("nm") is None:
                    cur["nm"] = m.group(1)
                m = re.search(r"DW_AT_low_pc\s*:\s*0x([0-9a-f]+)", line)
                if m:
                    cur["lo"] = int(m.group(1), 16)
                m = re.search(r"DW_AT_high_pc\s*:\s*0x([0-9a-f]+)", line)
                if m:
                    cur["hi"] = int(m.group(1), 16)
                m = re.search(r"DW_OP_fbreg:\s*(-?\d+)", line)
                if m:
                    cur["vars"].append(int(m.group(1)))

        for b in blocks:
            if not b.get("nm") or b["lo"] is None or b["hi"] is None:
                continue
            if not b["vars"]:
                continue
            offs = rbp_offsets(elf, b["lo"], b["hi"])
            miss = [v for v in b["vars"] if v not in offs]
            check("%s: DWARF 偏移 %s 都能在机器码里找到"
                  % (b["nm"], b["vars"]),
                  not miss,
                  "机器码里有 %s，缺 %s" % (sorted(offs), miss))

        print("== 类型 ==")
        types = parse_types(elf)
        tnames = [t[0] for t in types]
        for want in ["i64", "byte", "f64", "bool"]:
            check("基础类型 %s" % want, want in tnames, str(tnames))
        check("有结构体类型", "Point" in tnames, str(tnames))

        # 关键：每个变量引用的类型必须**各不相同且正确**。
        # 曾出现所有 f64/bool/ptr 变量的 DW_AT_type 都指向同一个
        # （类型 id 判断写错），readelf 看着"每个变量都有类型"，
        # 其实全指向 byte*。所以这里逐个比对名字。
        vty = parse_var_types(elf)
        check("fl 是 f64", vty.get("fl") == "f64", str(vty.get("fl")))
        check("bl 是 bool", vty.get("bl") == "bool", str(vty.get("bl")))
        check("sp 是 pointer_type", vty.get("sp") == "DW_TAG_pointer_type",
              str(vty.get("sp")))
        check("bf 是 array_type", vty.get("bf") == "DW_TAG_array_type",
              str(vty.get("bf")))
        check("i 是 i64", vty.get("i") == "i64", str(vty.get("i")))
        check("p 是 Point", vty.get("p") == "Point", str(vty.get("p")))
        # 类型不得重复生成（同一个结构体只应有一个 DIE）
        check("类型 DIE 无重复",
              len(tnames) == len(set(tnames)), str(tnames))
        # 结构体成员
        members = parse_members(elf)
        check("Point 成员 x @0, y @8",
              members.get("Point") == [("x", 0), ("y", 8)],
              str(members.get("Point")))

        print("== .debug_frame（栈帧展开规则）==")
        fde = parse_frames(elf)
        check("至少一条 FDE", len(fde) >= 2, str(len(fde)))
        check("FDE 数 == 函数数", len(fde) == len([f for f in funcs
                                                   if f["name"]]),
              "fde=%d funcs=%d" % (len(fde),
                                   len([f for f in funcs if f["name"]])))

        # 关键：CFI 描述的位置必须和**真实序言**对得上。
        # 序言固定为 push rbp(1) + mov rbp,rsp(3) + sub rsp,imm32(7)。
        # CFI 说 "advance_loc 1 后 CFA=rsp+16"、"advance_loc 3 后 CFA=rbp+16"
        # —— 于是 low+1 处必须是 push rbp，low+4 处必须是 mov rbp,rsp。
        blob = open(elf, "rb").read()
        base = 0x4000b0
        foff = 176
        for f in fde:
            lo = f["lo"]
            o = foff + (lo - base)
            check("FDE %#x: low+0 是 push rbp (0x55)" % lo,
                  blob[o] == 0x55, hex(blob[o]))
            check("FDE %#x: low+1..4 是 mov rbp,rsp" % lo,
                  blob[o + 1] == 0x48 and blob[o + 2] == 0x89
                  and blob[o + 3] == 0xe5,
                  "%02x %02x %02x" % (blob[o + 1], blob[o + 2], blob[o + 3]))
        # CFA 规则应当以 def_cfa_register rbp 收尾（函数体内 CFA = rbp+16）
        check("CFA 最终基于 rbp",
              all(f.get("cfa_reg") == "rbp" for f in fde),
              str([f.get("cfa_reg") for f in fde]))

        print("\n通过 %d / 失败 %d" % (PASS, FAIL))
        return 1 if FAIL else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
