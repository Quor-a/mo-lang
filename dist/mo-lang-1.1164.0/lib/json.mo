# json —— 轻量 JSON 解析（用墨语言自己写的）
#
# 网络协议里几乎绕不开 JSON，而我们 1.3.0 已经有了 HTTP。
# 这里做最小可用集：按路径取值、遍历对象键、区分类型。
# 不做序列化（写出）——那需要动态缓冲区，先不做。
#
# 线程安全（v1.190.0）：解析结果不再经 J_* 全局游标传递
# （多线程同时 json_* 会互踩——kvjson 实测 ji 出现 699392 之类巨值）。
# 核心 vt_span(s,p,&pos,&end) 纯参数传递；J_* 与 val_type 保留为
# 单线程兼容包装（旧代码仍可用，但多线程请只用 json_* 接口）。
import "str.mo";

var J_TYPE: i64 = 0;    # 0=未找到 1=字符串 2=数字 3=true 4=false 5=null
var J_POS: i64 = 0;     # 命中值的起始下标
var J_END: i64 = 0;     # 命中值的结束下标

fn skip_ws(s: ptr, i: i64) -> i64 {
    while s[i] == 32 || s[i] == 10 || s[i] == 9 || s[i] == 13 {
        i = i + 1;
    }
    return i;
}

# 在对象里找 key，返回值的起始下标；找不到返回 -1
# 只扫描顶层（嵌套对象内部不查），够覆盖绝大多数响应
fn find_key(s: ptr, key: ptr, from: i64) -> i64 {
    let i: i64 = from;
    let n: i64 = strlen(s);
    while i < n {
        if s[i] == 34 {
            let ks: i64 = i + 1;
            let j: i64 = 0;
            while s[ks + j] == load8(key + j) {
                j = j + 1;
                if load8(key + j) == 0 { break; }
            }
            if load8(key + j) == 0 {
                if s[ks + j] == 34 {
                    # 匹配到 key，跳到冒号后的值
                    let p: i64 = ks + j + 1;
                    p = skip_ws(s, p);
                    if s[p] == 58 {
                        p = p + 1;
                        p = skip_ws(s, p);
                        return p;
                    }
                }
            }
        }
        i = i + 1;
    }
    return -1;
}

# 判断 p 处值的类型；区间经 pos/end 指针回写（线程安全核心）
fn vt_span(s: ptr, p: i64, pos: ptr, end: ptr) -> i64 {
    let c: i64 = s[p];
    if c == 34 {
        let e: i64 = p + 1;
        while s[e] != 34 {
            if s[e] == 92 { e = e + 1; }   # 反斜杠：跳过转义字符（\" \\ \n ...）
            e = e + 1;
        }
        store64(pos, p + 1); store64(end, e);
        return 1;
    }
    if c == 116 { store64(pos, p); store64(end, p + 4); return 3; }
    if c == 102 { store64(pos, p); store64(end, p + 5); return 4; }
    if c == 110 { store64(pos, p); store64(end, p + 4); return 5; }
    if c == 45 {
        let e: i64 = p + 1;
        while s[e] >= 48 && s[e] <= 57 { e = e + 1; }
        store64(pos, p); store64(end, e);
        return 2;
    }
    if c >= 48 {
        if c <= 57 {
            let e: i64 = p;
            while s[e] >= 48 && s[e] <= 57 { e = e + 1; }
            store64(pos, p); store64(end, e);
            return 2;
        }
    }
    return 0;
}

# 兼容包装：老代码用 J_*。多线程程序不要用这个。
fn val_type(s: ptr, p: i64) -> i64 {
    let t: i64 = vt_span(s, p, &J_POS, &J_END);
    J_TYPE = t;
    return t;
}

# 取字符串值：把结果拷进 dst，返回 1 表示成功（线程安全）
fn json_str(s: ptr, key: ptr, dst: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    let vp: i64 = 0;
    let ve: i64 = 0;
    if vt_span(s, p, &vp, &ve) != 1 { return 0; }
    let i: i64 = vp;
    let o: i64 = 0;
    while i < ve {
        store8(dst + o, s[i]);
        o = o + 1;
        i = i + 1;
    }
    store8(dst + o, 0);
    return 1;
}

# 取整数值（线程安全）
fn json_int(s: ptr, key: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    let vp: i64 = 0;
    let ve: i64 = 0;
    if vt_span(s, p, &vp, &ve) != 2 { return 0; }
    let v: i64 = 0;
    let neg: i64 = 0;
    let i: i64 = vp;
    if s[i] == 45 { neg = 1; i = i + 1; }
    while i < ve {
        v = v * 10 + (s[i] - 48);
        i = i + 1;
    }
    if neg == 1 { return 0 - v; }
    return v;
}

# 判断布尔 / null（线程安全）
# json_has(s, key)：key 存在返 1。
fn json_has(s: ptr, key: ptr) -> i64 {
    if find_key(s, key, 0) >= 0 { return 1; }
    return 0;
}

# json_num(s, key, dst_f64)：取 key 对应数值写 *dst_f64（手工小数解析：
#   整数部分 + 小数部分，无指数支持）。成功返 1。
# 🔴 注意：f64 直接运算在 mo 可用（io.print_f64 存在）；这里用整数+两位
#    小数的「定点」折中，避免依赖 libc strtod——精度 1e-4 足够元数据。
# 返回值=放大 10000 倍的 i64 定点数；-9223372036854775807 表示无值。
fn json_num(s: ptr, key: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);   # 已是值起点（冒号后）
    if p < 0 { return 0 - 9223372036854775807; }
    let neg: i64 = 1;
    if load8(s + p) == 45 { neg = 0 - 1; p = p + 1; }
    let ip: i64 = 0;
    while load8(s + p) >= 48 && load8(s + p) <= 57 {
        ip = ip * 10 + (load8(s + p) - 48);
        p = p + 1;
    }
    let fp: i64 = 0;
    let scale: i64 = 1;
    if load8(s + p) == 46 {
        p = p + 1;
        while load8(s + p) >= 48 && load8(s + p) <= 57 {
            if scale < 10000 {
                fp = fp * 10 + (load8(s + p) - 48);
                scale = scale * 10;
            }
            p = p + 1;
        }
    }
    # 归一化到 4 位小数定点
    while scale < 10000 { fp = fp * 10; scale = scale * 10; }
    return neg * (ip * 10000 + fp);
}

# json_escape(dst, src)：JSON 字符串转义（\" \\ \n \r \t 控制字符），
#   首尾不加引号。返回 dst。
var JE_B: [16] byte = 0;

fn json_escape(dst: ptr, src: ptr) -> i64 {
    let i: i64 = 0;
    let o: i64 = 0;
    while load8(src + i) != 0 {
        let c: i64 = load8(src + i);
        if c == 34 { store8(dst + o, 92); store8(dst + o + 1, 34); o = o + 2; }
        else if c == 92 { store8(dst + o, 92); store8(dst + o + 1, 92); o = o + 2; }
        else if c == 10 { store8(dst + o, 92); store8(dst + o + 1, 110); o = o + 2; }
        else if c == 13 { store8(dst + o, 92); store8(dst + o + 1, 114); o = o + 2; }
        else if c == 9 { store8(dst + o, 92); store8(dst + o + 1, 116); o = o + 2; }
        else { store8(dst + o, c); o = o + 1; }
        i = i + 1;
    }
    store8(dst + o, 0);
    return dst;
}

fn json_true(s: ptr, key: ptr) -> i64 {
    let p: i64 = find_key(s, key, 0);
    if p < 0 { return 0; }
    let vp: i64 = 0;
    let ve: i64 = 0;
    if vt_span(s, p, &vp, &ve) == 3 { return 1; }
    return 0;
}
