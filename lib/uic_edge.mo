# lib/uic_edge.mo —— 边缘计算画布组件（v1.681+）
# 依赖 uic.mo（uc_set/颜色常量）与 str.mo（strlen）。
import "uic.mo";
import "str.mo";

# ============ v1.681 边缘节点行 ============

# uc_edge_node_row：绘制边缘节点行 [N]  edge-node-01  Online  2 cores
# name 为节点名，state 0=离线 1=在线，spec 为规格。
# 用于边缘节点管理。
fn uc_edge_node_row(x: i64, y: i64, name: ptr, state: i64, spec: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(spec);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'N', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, spec[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.682 边缘设备行 ============

# uc_edge_device_row：绘制边缘设备行 [D]  sensor-01  Connected  temperature
# name 为设备名，type 为类型，state 0=断开 1=已连接。
# 用于边缘设备管理。
fn uc_edge_device_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 't', UC_RED, bg);
    }
    return 0;
}

# ============ v1.683 边缘应用行 ============

# uc_edge_app_row：绘制边缘应用行 [A]  face-recog  1.0.3  Running
# name 为应用名，version 为版本，state 0=停止 1=运行。
# 用于边缘应用管理。
fn uc_edge_app_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'A', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'S', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 't', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'o', UC_RED, bg);
        uc_set(x + 15 + nlen + vlen, y, 'p', UC_RED, bg);
        uc_set(x + 16 + nlen + vlen, y, 'p', UC_RED, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + nlen + vlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.684 边缘函数行 ============

# uc_edge_function_row：绘制边缘函数行 [F]  image-resize  256MB  12ms
# name 为函数名，memory 为内存，duration 为耗时。
# 用于边缘函数管理。
fn uc_edge_function_row(x: i64, y: i64, name: ptr, memory: ptr, duration: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(memory);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'F', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, memory[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 12 + nlen + mlen + i, y, duration[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.685 边缘流规则行 ============

# uc_edge_stream_row：绘制边缘流规则行 [S]  temp-alert  > 50C  Active
# name 为规则名，condition 为条件，state 0=停用 1=启用。
# 用于边缘流规则管理。
fn uc_edge_stream_row(x: i64, y: i64, name: ptr, condition: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(condition);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, condition[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + clen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.686 边缘模型行 ============

# uc_edge_model_row：绘制边缘模型行 [M]  yolov5  2.1.0  Deployed
# name 为模型名，version 为版本，state 0=未部署 1=已部署。
# 用于边缘模型管理。
fn uc_edge_model_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'D', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'y', UC_GREEN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + vlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'N', UC_CYAN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 14 + nlen + vlen, y, 't', UC_CYAN, bg);
        uc_set(x + 15 + nlen + vlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'D', UC_CYAN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'p', UC_CYAN, bg);
        uc_set(x + 19 + nlen + vlen, y, 'l', UC_CYAN, bg);
        uc_set(x + 20 + nlen + vlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 21 + nlen + vlen, y, 'y', UC_CYAN, bg);
        uc_set(x + 22 + nlen + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 23 + nlen + vlen, y, 'd', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.687 边缘模型版本行 ============

# uc_edge_model_version_row：绘制边缘模型版本行 [V]  yolov5  2.1.0  Active
# name 为模型名，version 为版本，state 0=归档 1=激活。
# 用于边缘模型版本管理。
fn uc_edge_model_version_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'V', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_CYAN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'c', UC_CYAN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'h', UC_CYAN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'v', UC_CYAN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 19 + nlen + vlen, y, 'd', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.688 边缘部署行 ============

# uc_edge_deployment_row：绘制边缘部署行 [D]  cam-01-deploy  Running  5 devices
# name 为部署名，state 0=停止 1=运行，devices 为设备数。
# 用于边缘部署管理。
fn uc_edge_deployment_row(x: i64, y: i64, name: ptr, state: i64, devices: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'D', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + devices, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.689 边缘调度行 ============

# uc_edge_schedule_row：绘制边缘调度行 [S]  daily-sync  Every 1h  Active
# name 为调度名，schedule 为调度，state 0=停用 1=启用。
# 用于边缘调度管理。
fn uc_edge_schedule_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'S', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', fg, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', fg, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', fg, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', fg, bg);
        uc_set(x + 16 + nlen + slen, y, 't', fg, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', fg, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', fg, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', fg, bg);
    }
    return 0;
}

# ============ v1.690 边缘遥测行 ============

# uc_edge_telemetry_row：绘制边缘遥测行 [T]  temp-01  23.5C  1s interval
# name 为遥测点，value 为值，interval 为间隔。
# 用于边缘遥测管理。
fn uc_edge_telemetry_row(x: i64, y: i64, name: ptr, value: ptr, interval: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'T', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 12 + nlen + vlen + i, y, interval[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.691 边缘告警行 ============

# uc_edge_alert_row：绘制边缘告警行 [A]  high-temp  Critical  2024-01-15
# name 为告警名，severity 为级别，state 0=已解决 1=活动。
# 用于边缘告警管理。
fn uc_edge_alert_row(x: i64, y: i64, name: ptr, severity: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(severity);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'A', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, severity[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_RED, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_RED, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_RED, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_RED, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_RED, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_RED, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'K', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.692 边缘设备影子行 ============

# uc_device_shadow_row：绘制边缘设备影子行 [S]  sensor-01  desired-temp 25  reported 24
# name 为设备名，desired 为期望状态，reported 为报告状态。
# 用于边缘设备影子管理。
fn uc_device_shadow_row(x: i64, y: i64, name: ptr, desired: ptr, reported: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(desired);
    rlen = strlen(reported);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, desired[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 12 + nlen + dlen + i, y, reported[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.693 边缘 OTA 更新行 ============

# uc_ota_update_row：绘制边缘 OTA 更新行 [O]  fw-1.0.3  5 devices  Updating
# name 为更新名，devices 为设备数，state 0=失败 1=更新中。
# 用于边缘 OTA 更新管理。
fn uc_ota_update_row(x: i64, y: i64, name: ptr, devices: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'O', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + devices, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'U', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'p', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'd', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 't', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'g', UC_CYAN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.694 边缘遥测数据行 ============

# uc_edge_telemetry_data_row：绘制边缘遥测数据行 [D]  temp-01  23.5C  normal
# name 为数据点，value 为值，state 0=异常 1=正常。
# 用于边缘遥测数据监控。
fn uc_edge_telemetry_data_row(x: i64, y: i64, name: ptr, value: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'D', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'N', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'l', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 'b', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen + vlen, y, 'o', UC_RED, bg);
        uc_set(x + 16 + nlen + vlen, y, 'r', UC_RED, bg);
        uc_set(x + 17 + nlen + vlen, y, 'm', UC_RED, bg);
        uc_set(x + 18 + nlen + vlen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + vlen, y, 'l', UC_RED, bg);
    }
    return 0;
}

# ============ v1.695 边缘模型监控行 ============

# uc_edge_model_monitor_row：绘制边缘模型监控行 [M]  yolov5  acc 0.95  Healthy
# name 为监控项，metric 为指标，state 0=异常 1=健康。
# 用于边缘模型监控。
fn uc_edge_model_monitor_row(x: i64, y: i64, name: ptr, metric: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(metric);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, metric[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 18 + nlen + mlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + mlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + mlen, y, 'g', UC_RED, bg);
        uc_set(x + 15 + nlen + mlen, y, 'r', UC_RED, bg);
        uc_set(x + 16 + nlen + mlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen + mlen, y, 'd', UC_RED, bg);
        uc_set(x + 18 + nlen + mlen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + nlen + mlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.696 边缘规则引擎行 ============

# uc_edge_rule_engine_row：绘制边缘规则引擎行 [E]  temp-rule  active  12 rules
# name 为引擎名，rules 为规则数，state 0=停止 1=运行。
# 用于边缘规则引擎管理。
fn uc_edge_rule_engine_row(x: i64, y: i64, name: ptr, rules: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + rules / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + rules % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.697 边缘数据清洗行 ============

# uc_edge_clean_row：绘制边缘数据清洗行 [C]  temp-clean  input 1000  output 980
# name 为清洗任务名，input 为输入量，output 为输出量。
# 用于边缘数据清洗任务管理。
fn uc_edge_clean_row(x: i64, y: i64, name: ptr, input: i64, output: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, ':', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, '0' + input / 1000, UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, '0' + (input / 100) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, '0' + (input / 10) % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, '0' + input % 10, UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ':', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, '0' + output / 1000, UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, '0' + (output / 100) % 10, UC_WHITE, bg);
    uc_set(x + 24 + nlen, y, '0' + (output / 10) % 10, UC_WHITE, bg);
    uc_set(x + 25 + nlen, y, '0' + output % 10, UC_WHITE, bg);
    return 0;
}

# ============ v1.698 边缘联邦学习行 ============

# uc_federated_row：绘制边缘联邦学习行 [F]  fed-round-1  5 clients  Aggregated
# name 为任务名，clients 为客户端数，state 0=聚合中 1=已聚合。
# 用于边缘联邦学习管理。
fn uc_federated_row(x: i64, y: i64, name: ptr, clients: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'F', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + clients, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'g', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'g', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 29 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'A', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 't', UC_CYAN, bg);
        uc_set(x + 28 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 29 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 30 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.699 边缘缓存行 ============

# uc_edge_cache_row：绘制边缘缓存行 [C]  img-cache  512MB  Hit 89%
# name 为缓存名，size 为大小，state 0=异常 1=健康。
# 用于边缘缓存管理。
fn uc_edge_cache_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'C', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, 'H', UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, '8', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, '9', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, '%', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen + slen, y, 'O', UC_GREEN, bg);
        uc_set(x + 22 + nlen + slen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen + slen, y, 'E', UC_RED, bg);
        uc_set(x + 22 + nlen + slen, y, 'R', UC_RED, bg);
        uc_set(x + 23 + nlen + slen, y, 'R', UC_RED, bg);
    }
    return 0;
}

# ============ v1.700 边缘负载均衡行 ============

# uc_edge_lb_row：绘制边缘负载均衡行 [L]  edge-lb-1  3 nodes  Healthy
# name 为均衡器名，nodes 为节点数，state 0=异常 1=健康。
# 用于边缘负载均衡管理。
fn uc_edge_lb_row(x: i64, y: i64, name: ptr, nodes: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'L', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + nodes, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'R', UC_RED, bg);
    }
    return 0;
}

# ============ v1.701 边缘证书行 ============

# uc_edge_cert_row：绘制边缘证书行 [C]  edge-cert-01  Valid  30 days
# name 为证书名，state 0=过期 1=有效，days 为剩余天数。
# 用于边缘证书管理。
fn uc_edge_cert_row(x: i64, y: i64, name: ptr, state: i64, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'V', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'E', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'x', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + days / 10, UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, '0' + days % 10, UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, 'y', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.702 边缘密钥行 ============

# uc_edge_key_row：绘制边缘密钥行 [K]  device-key  Active  ed25519
# name 为密钥名，type 为类型，state 0=吊销 1=启用。
# 用于边缘密钥管理。
fn uc_edge_key_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'K', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'R', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'v', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'k', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.703 边缘访问策略行 ============

# uc_edge_access_policy_row：绘制边缘访问策略行 [P]  edge-readonly  Allow  read
# name 为策略名，effect 为效果，action 为动作。
# 用于边缘访问策略管理。
fn uc_edge_access_policy_row(x: i64, y: i64, name: ptr, effect: ptr, action: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(effect);
    alen = strlen(action);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + nlen + i, y, effect[i], UC_GREEN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + elen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 12 + nlen + elen + i, y, action[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.704 边缘设备组行 ============

# uc_edge_device_group_row：绘制边缘设备组行 [G]  factory-a  12 devices  Active
# name 为设备组名，devices 为设备数，state 0=停用 1=启用。
# 用于边缘设备组管理。
fn uc_edge_device_group_row(x: i64, y: i64, name: ptr, devices: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'G', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + devices / 10, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, '0' + devices % 10, UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 'v', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.705 边缘设备模板行 ============

# uc_edge_device_template_row：绘制边缘设备模板行 [T]  sensor-template  3 fields  Published
# name 为模板名，fields 为字段数，state 0=草稿 1=已发布。
# 用于边缘设备模板管理。
fn uc_edge_device_template_row(x: i64, y: i64, name: ptr, fields: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'T', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + fields, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'f', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'D', UC_CYAN, bg);
        uc_set(x + 20 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'f', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 't', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.706 边缘数据源行 ============

# uc_edge_datasource_row：绘制边缘数据源行 [S]  temp-sensor  MQTT  Connected
# name 为数据源名，type 为类型，state 0=断开 1=已连接。
# 用于边缘数据源管理。
fn uc_edge_datasource_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 't', UC_RED, bg);
    }
    return 0;
}

# ============ v1.707 边缘数据管道行 ============

# uc_edge_pipeline_row：绘制边缘数据管道行 [P]  temp-pipe  Running  5 stages
# name 为管道名，stages 为阶段数，state 0=停止 1=运行。
# 用于边缘数据管道管理。
fn uc_edge_pipeline_row(x: i64, y: i64, name: ptr, stages: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + stages, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.708 边缘数据目标行 ============

# uc_edge_data_sink_row：绘制边缘数据目标行 [T]  cloud-upload  InfluxDB  Healthy
# name 为目标名，type 为类型，state 0=异常 1=健康。
# 用于边缘数据目标管理。
fn uc_edge_data_sink_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'T', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'E', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'R', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'R', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'O', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'R', UC_RED, bg);
    }
    return 0;
}

# ============ v1.709 边缘仪表盘行 ============

# uc_edge_dashboard_row：绘制边缘仪表盘行 [D]  factory-dash  5 widgets  Active
# name 为仪表盘名，widgets 为组件数，state 0=停用 1=启用。
# 用于边缘仪表盘管理。
fn uc_edge_dashboard_row(x: i64, y: i64, name: ptr, widgets: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'D', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + widgets, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'w', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.710 边缘报告行 ============

# uc_edge_report_row：绘制边缘报告行 [R]  monthly-report  12 pages  Generated
# name 为报告名，pages 为页数，state 0=生成中 1=已生成。
# 用于边缘报告管理。
fn uc_edge_report_row(x: i64, y: i64, name: ptr, pages: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + pages / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + pages % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'G', UC_CYAN, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 28 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.711 边缘工作负载行 ============

# uc_edge_workload_row：绘制边缘工作负载行 [W]  cam-app  Running  3 replicas
# name 为工作负载名，replicas 为副本数，state 0=停止 1=运行。
# 用于边缘工作负载管理。
fn uc_edge_workload_row(x: i64, y: i64, name: ptr, replicas: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'W', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + replicas, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.712 边缘副本集行 ============

# uc_edge_replicaset_row：绘制边缘副本集行 [R]  cam-rs  3/3 ready
# name 为副本集名，state 0=异常 1=就绪，ready 为就绪数。
# 用于边缘副本集管理。
fn uc_edge_replicaset_row(x: i64, y: i64, name: ptr, state: i64, ready: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, '0' + ready, UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, '/', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, '3', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, '0', UC_RED, bg);
        uc_set(x + 10 + nlen, y, '/', UC_RED, bg);
        uc_set(x + 11 + nlen, y, '3', UC_RED, bg);
        uc_set(x + 12 + nlen, y, ' ', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'd', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'y', UC_RED, bg);
    }
    return 0;
}

# ============ v1.713 边缘服务行 ============

# uc_edge_service_row：绘制边缘服务行 [S]  cam-svc  ClusterIP  8080
# name 为服务名，type 为类型，port 为端口。
# 用于边缘服务管理。
fn uc_edge_service_row(x: i64, y: i64, name: ptr, type: ptr, port: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + tlen, y, '0' + port / 1000, UC_CYAN, bg);
    uc_set(x + 13 + nlen + tlen, y, '0' + (port / 100) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + tlen, y, '0' + (port / 10) % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + tlen, y, '0' + port % 10, UC_CYAN, bg);
    return 0;
}

# ============ v1.714 边缘任务行 ============

# uc_edge_task_row：绘制边缘任务行 [T]  image-process  Succeeded  2m 12s
# name 为任务名，state 0=运行 1=成功，duration 为耗时。
# 用于边缘任务管理。
fn uc_edge_task_row(x: i64, y: i64, name: ptr, state: i64, duration: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 20 + nlen + i, y, duration[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.715 边缘定时任务行 ============

# uc_edge_cron_row：绘制边缘定时任务行 [C]  cleanup-cron  Every 6h  Active
# name 为任务名，schedule 为调度，state 0=暂停 1=启用。
# 用于边缘定时任务管理。
fn uc_edge_cron_row(x: i64, y: i64, name: ptr, schedule: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(schedule);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, schedule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'P', UC_RED, bg);
        uc_set(x + 13 + nlen + slen, y, 'a', UC_RED, bg);
        uc_set(x + 14 + nlen + slen, y, 'u', UC_RED, bg);
        uc_set(x + 15 + nlen + slen, y, 's', UC_RED, bg);
        uc_set(x + 16 + nlen + slen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + slen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.716 边缘命名空间行 ============

# uc_edge_namespace_row：绘制边缘命名空间行 [N]  edge-prod  Active  12 workloads
# name 为命名空间名，workloads 为工作负载数，state 0=停用 1=启用。
# 用于边缘命名空间管理。
fn uc_edge_namespace_row(x: i64, y: i64, name: ptr, workloads: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'N', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + workloads / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + workloads % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'w', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'k', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 23 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 23 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 29 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 30 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.717 边缘配置映射行 ============

# uc_edge_configmap_row：绘制边缘配置映射行 [M]  app-config  5 keys  Active
# name 为配置映射名，keys 为键数，state 0=停用 1=启用。
# 用于边缘配置映射管理。
fn uc_edge_configmap_row(x: i64, y: i64, name: ptr, keys: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'M', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + keys, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'k', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'y', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 17 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 17 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.718 边缘密钥引用行 ============

# uc_edge_secret_ref_row：绘制边缘密钥引用行 [K]  db-secret  db-password  Active
# name 为密钥名，key 为键，state 0=停用 1=启用。
# 用于边缘密钥引用管理。
fn uc_edge_secret_ref_row(x: i64, y: i64, name: ptr, key: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let klen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    klen = strlen(key);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'K', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < klen {
        uc_set(x + 9 + nlen + i, y, key[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + klen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + klen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + klen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + klen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + klen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + klen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + klen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + klen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + klen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + klen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + klen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + klen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + klen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + klen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + klen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.719 边缘服务账户行 ============

# uc_edge_service_account_row：绘制边缘服务账户行 [A]  deploy-bot  Active  read-only
# name 为账户名，role 为角色，state 0=停用 1=启用。
# 用于边缘服务账户管理。
fn uc_edge_service_account_row(x: i64, y: i64, name: ptr, role: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(role);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'A', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, role[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + rlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + rlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + rlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + rlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + rlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + rlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + rlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + rlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + rlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + rlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + rlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + rlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + rlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + rlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.720 边缘 RBAC 行 ============

# uc_edge_rbac_row：绘制边缘 RBAC 行 [R]  edge-admin  cluster-admin  Active
# name 为角色名，binding 为绑定，state 0=停用 1=启用。
# 用于边缘 RBAC 管理。
fn uc_edge_rbac_row(x: i64, y: i64, name: ptr, binding: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    blen = strlen(binding);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 9 + nlen + i, y, binding[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + blen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + blen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + blen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + blen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + blen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + blen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + blen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + blen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + blen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + blen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + blen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + blen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + blen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + blen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + blen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.721 边缘存储行 ============

# uc_edge_storage_row：绘制边缘存储行 [S]  edge-data  500GB  60% used
# name 为存储名，size 为大小，state 0=异常 1=正常。
# 用于边缘存储管理。
fn uc_edge_storage_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '6', UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, '%', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 's', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 22 + nlen + slen, y, 'O', UC_GREEN, bg);
        uc_set(x + 23 + nlen + slen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 22 + nlen + slen, y, 'E', UC_RED, bg);
        uc_set(x + 23 + nlen + slen, y, 'R', UC_RED, bg);
        uc_set(x + 24 + nlen + slen, y, 'R', UC_RED, bg);
    }
    return 0;
}

# ============ v1.722 边缘持久卷行 ============

# uc_edge_pv_row：绘制边缘持久卷行 [P]  edge-pv-1  50Gi  Bound
# name 为持久卷名，size 为大小，state 0=挂起 1=已绑定。
# 用于边缘持久卷管理。
fn uc_edge_pv_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'B', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'u', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen + slen, y, 'e', UC_CYAN, bg);
        uc_set(x + 14 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen + slen, y, 'd', UC_CYAN, bg);
        uc_set(x + 16 + nlen + slen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 18 + nlen + slen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.723 边缘存储类行 ============

# uc_edge_storage_class_row：绘制边缘存储类行 [C]  fast-storage  ssd  Active
# name 为存储类名，type 为类型，state 0=停用 1=启用。
# 用于边缘存储类管理。
fn uc_edge_storage_class_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.724 边缘卷快照行 ============

# uc_edge_volume_snapshot_row：绘制边缘卷快照行 [S]  snap-01  10Gi  Ready
# name 为快照名，size 为大小，state 0=创建中 1=就绪。
# 用于边缘卷快照管理。
fn uc_edge_volume_snapshot_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'R', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'e', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'd', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'C', UC_CYAN, bg);
        uc_set(x + 13 + nlen + slen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + slen, y, 'e', UC_CYAN, bg);
        uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
        uc_set(x + 16 + nlen + slen, y, 't', UC_CYAN, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', UC_CYAN, bg);
        uc_set(x + 18 + nlen + slen, y, 'n', UC_CYAN, bg);
        uc_set(x + 19 + nlen + slen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.725 边缘备份行 ============

# uc_edge_backup_row：绘制边缘备份行 [B]  config-backup  Completed  12:00
# name 为备份名，state 0=失败 1=完成，time 为时间。
# 用于边缘备份管理。
fn uc_edge_backup_row(x: i64, y: i64, name: ptr, state: i64, time: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(time);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'B', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 20 + nlen + i, y, time[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.726 边缘恢复点行 ============

# uc_edge_restore_point_row：绘制边缘恢复点行 [P]  rp-20240115  Available  50GB
# name 为恢复点名，size 为大小，state 0=不可用 1=可用。
# 用于边缘恢复点管理。
fn uc_edge_restore_point_row(x: i64, y: i64, name: ptr, size: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'a', UC_GREEN, bg);
        uc_set(x + 18 + nlen + slen, y, 'b', UC_GREEN, bg);
        uc_set(x + 19 + nlen + slen, y, 'l', UC_GREEN, bg);
        uc_set(x + 20 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'U', UC_RED, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + slen, y, 'v', UC_RED, bg);
        uc_set(x + 16 + nlen + slen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + slen, y, 'l', UC_RED, bg);
        uc_set(x + 19 + nlen + slen, y, 'a', UC_RED, bg);
        uc_set(x + 20 + nlen + slen, y, 'b', UC_RED, bg);
        uc_set(x + 21 + nlen + slen, y, 'l', UC_RED, bg);
        uc_set(x + 22 + nlen + slen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.727 边缘保留策略行 ============

# uc_edge_retention_row：绘制边缘保留策略行 [R]  backup-retention  7 days  Active
# name 为策略名，days 为天数，state 0=停用 1=启用。
# 用于边缘保留策略管理。
fn uc_edge_retention_row(x: i64, y: i64, name: ptr, days: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'R', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + days, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'y', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 17 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 17 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.728 边缘复制任务行 ============

# uc_edge_replication_task_row：绘制边缘复制任务行 [R]  sync-data  Running  3/5
# name 为任务名，state 0=停止 1=运行，progress 为进度。
# 用于边缘复制任务管理。
fn uc_edge_replication_task_row(x: i64, y: i64, name: ptr, state: i64, progress: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + progress, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '/', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '5', UC_WHITE, bg);
    return 0;
}

# ============ v1.729 边缘迁移任务行 ============

# uc_edge_migration_task_row：绘制边缘迁移任务行 [M]  migrate-app  Running  60%
# name 为任务名，state 0=停止 1=运行，progress 为进度。
# 用于边缘迁移任务管理。
fn uc_edge_migration_task_row(x: i64, y: i64, name: ptr, state: i64, progress: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + progress / 10, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '0' + progress % 10, UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '%', UC_WHITE, bg);
    return 0;
}

# ============ v1.730 边缘归档任务行 ============

# uc_edge_archive_task_row：绘制边缘归档任务行 [A]  archive-logs  Completed  2GB
# name 为任务名，state 0=失败 1=完成，size 为大小。
# 用于边缘归档任务管理。
fn uc_edge_archive_task_row(x: i64, y: i64, name: ptr, state: i64, size: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'A', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 20 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.731 边缘告警规则行 ============

# uc_edge_alert_rule_row：绘制边缘告警规则行 [R]  high-temp-rule  temp > 50  Active
# name 为规则名，condition 为条件，state 0=停用 1=启用。
# 用于边缘告警规则管理。
fn uc_edge_alert_rule_row(x: i64, y: i64, name: ptr, condition: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(condition);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'R', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, condition[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + clen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.732 边缘通知渠道行 ============

# uc_edge_notify_channel_row：绘制边缘通知渠道行 [C]  email-alert  Email  Active
# name 为渠道名，type 为类型，state 0=停用 1=启用。
# 用于边缘通知渠道管理。
fn uc_edge_notify_channel_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.733 边缘告警抑制行 ============

# uc_edge_alert_inhibit_row：绘制边缘告警抑制行 [I]  inhibit-maintenance  30m  Active
# name 为抑制名，duration 为时长，state 0=停用 1=启用。
# 用于边缘告警抑制管理。
fn uc_edge_alert_inhibit_row(x: i64, y: i64, name: ptr, duration: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'I', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, duration[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + dlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + dlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + dlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + dlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + dlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + dlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + dlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + dlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + dlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + dlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + dlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + dlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + dlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + dlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.734 边缘告警静默行 ============

# uc_edge_alert_silence_row：绘制边缘告警静默行 [S]  silence-01  until 14:00  Active
# name 为静默名，until 为截止时间，state 0=停用 1=启用。
# 用于边缘告警静默管理。
fn uc_edge_alert_silence_row(x: i64, y: i64, name: ptr, until: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(until);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ulen {
        uc_set(x + 9 + nlen + i, y, until[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ulen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + ulen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + ulen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + ulen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + ulen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + ulen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + ulen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + ulen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + ulen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + ulen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + ulen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + ulen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + ulen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + ulen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + ulen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.735 边缘事件总线行 ============

# uc_edge_event_bus_row：绘制边缘事件总线行 [E]  edge-events  Running  1200 msg/s
# name 为总线名，state 0=停止 1=运行，rate 为速率。
# 用于边缘事件总线管理。
fn uc_edge_event_bus_row(x: i64, y: i64, name: ptr, state: i64, rate: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'E', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + rate / 1000, UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, '0' + (rate / 100) % 10, UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, '0' + (rate / 10) % 10, UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, '0' + rate % 10, UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 24 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 25 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 26 + nlen, y, '/', UC_WHITE, bg);
    uc_set(x + 27 + nlen, y, 's', UC_WHITE, bg);
    return 0;
}

# ============ v1.736 边缘消息队列行 ============

# uc_edge_mq_row：绘制边缘消息队列行 [Q]  edge-queue  5000 pending  Active
# name 为队列名，pending 为积压数，state 0=停用 1=启用。
# 用于边缘消息队列管理。
fn uc_edge_mq_row(x: i64, y: i64, name: ptr, pending: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'Q', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + pending / 1000, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (pending / 100) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + (pending / 10) % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, '0' + pending % 10, UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 23 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 23 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 29 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 30 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.737 边缘流处理器行 ============

# uc_edge_stream_processor_row：绘制边缘流处理器行 [P]  temp-stream  Running  10 ms
# name 为处理器名，state 0=停止 1=运行，latency 为延迟。
# 用于边缘流处理器管理。
fn uc_edge_stream_processor_row(x: i64, y: i64, name: ptr, state: i64, latency: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 18 + nlen + i, y, latency[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.738 边缘连接器行 ============

# uc_edge_connector_row：绘制边缘连接器行 [C]  cloud-connector  AWS IoT  Connected
# name 为连接器名，target 为目标，state 0=断开 1=已连接。
# 用于边缘连接器管理。
fn uc_edge_connector_row(x: i64, y: i64, name: ptr, target: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, target[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'i', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 21 + nlen + tlen, y, 't', UC_RED, bg);
    }
    return 0;
}

# ============ v1.739 边缘数据湖行 ============

# uc_edge_lake_row：绘制边缘数据湖行 [L]  edge-lake  5TB  3 tables
# name 为数据湖名，size 为大小，tables 为表数。
# 用于边缘数据湖管理。
fn uc_edge_lake_row(x: i64, y: i64, name: ptr, size: ptr, tables: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'L', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + tables, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'b', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'l', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.740 边缘数据仓库行 ============

# uc_edge_warehouse_row：绘制边缘数据仓库行 [W]  edge-wh  2TB  50 queries
# name 为仓库名，size 为大小，queries 为查询数。
# 用于边缘数据仓库管理。
fn uc_edge_warehouse_row(x: i64, y: i64, name: ptr, size: ptr, queries: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(size);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'W', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + queries / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + queries % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'q', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.741 边缘 ML 管道行 ============

# uc_edge_ml_pipeline_row：绘制边缘 ML 管道行 [M]  train-pipe  Running  5 stages
# name 为管道名，stages 为阶段数，state 0=停止 1=运行。
# 用于边缘 ML 管道管理。
fn uc_edge_ml_pipeline_row(x: i64, y: i64, name: ptr, stages: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + stages, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.742 边缘模型注册表行 ============

# uc_edge_model_registry_row：绘制边缘模型注册表行 [R]  model-registry  12 models  Active
# name 为注册表名，models 为模型数，state 0=停用 1=启用。
# 用于边缘模型注册表管理。
fn uc_edge_model_registry_row(x: i64, y: i64, name: ptr, models: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + models / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + models % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.743 边缘模型版本行 ============

# uc_edge_ml_model_version_row：绘制边缘模型版本行 [V]  yolov5  2.1.0  Active
# name 为模型名，version 为版本，state 0=归档 1=激活。
# 用于边缘模型版本管理。
fn uc_edge_ml_model_version_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'V', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_CYAN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen + vlen, y, 'c', UC_CYAN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'h', UC_CYAN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'v', UC_CYAN, bg);
        uc_set(x + 18 + nlen + vlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 19 + nlen + vlen, y, 'd', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.744 边缘推理端点行 ============

# uc_edge_inference_endpoint_row：绘制边缘推理端点行 [E]  detect-endpoint  Running  15ms
# name 为端点名，state 0=停止 1=运行，latency 为延迟。
# 用于边缘推理端点管理。
fn uc_edge_inference_endpoint_row(x: i64, y: i64, name: ptr, state: i64, latency: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'E', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 18 + nlen + i, y, latency[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.745 边缘批处理任务行 ============

# uc_edge_batch_job_row：绘制边缘批处理任务行 [B]  batch-infer  1000 items  Succeeded
# name 为任务名，items 为条目数，state 0=运行 1=成功。
# 用于边缘批处理任务管理。
fn uc_edge_batch_job_row(x: i64, y: i64, name: ptr, items: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'B', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + items / 1000, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (items / 100) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + (items / 10) % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, '0' + items % 10, UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 29 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'g', UC_CYAN, bg);
    }
    return 0;
}

# ============ v1.746 边缘数据标注行 ============

# uc_edge_label_job_row：绘制边缘数据标注行 [L]  label-cam  5000 images  In Progress
# name 为标注任务名，items 为条目数，state 0=完成 1=进行中。
# 用于边缘数据标注管理。
fn uc_edge_label_job_row(x: i64, y: i64, name: ptr, items: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'L', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + items / 1000, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (items / 100) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + (items / 10) % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, '0' + items % 10, UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 22 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 28 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 29 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 30 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 31 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 32 + nlen, y, 's', UC_CYAN, bg);
    } else {
        uc_set(x + 22 + nlen, y, 'D', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.747 边缘训练任务行 ============

# uc_edge_train_job_row：绘制边缘训练任务行 [T]  train-yolo  Running  epoch 5/50
# name 为训练任务名，epoch 为轮次，state 0=停止 1=运行。
# 用于边缘训练任务管理。
fn uc_edge_train_job_row(x: i64, y: i64, name: ptr, epoch: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 13 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_RED, bg);
    }
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 'c', UC_CYAN, bg);
    uc_set(x + 22 + nlen, y, 'h', UC_CYAN, bg);
    uc_set(x + 23 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 24 + nlen, y, '0' + epoch / 10, UC_CYAN, bg);
    uc_set(x + 25 + nlen, y, '0' + epoch % 10, UC_CYAN, bg);
    uc_set(x + 26 + nlen, y, '/', UC_CYAN, bg);
    uc_set(x + 27 + nlen, y, '5', UC_CYAN, bg);
    uc_set(x + 28 + nlen, y, '0', UC_CYAN, bg);
    return 0;
}

# ============ v1.748 边缘评估任务行 ============

# uc_edge_eval_job_row：绘制边缘评估任务行 [E]  eval-yolo  Completed  acc 0.92
# name 为评估任务名，state 0=运行 1=完成，metric 为指标。
# 用于边缘评估任务管理。
fn uc_edge_eval_job_row(x: i64, y: i64, name: ptr, state: i64, metric: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(metric);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'C', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'm', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'p', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'R', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'u', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'i', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
    }
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 20 + nlen + i, y, metric[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.749 边缘特征存储行 ============

# uc_edge_feature_store_row：绘制边缘特征存储行 [F]  edge-features  500 features  Active
# name 为存储名，features 为特征数，state 0=停用 1=启用。
# 用于边缘特征存储管理。
fn uc_edge_feature_store_row(x: i64, y: i64, name: ptr, features: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'F', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + features / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (features / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + features % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'f', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 23 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 23 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 29 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 30 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.750 边缘模型监控告警行 ============

# uc_edge_model_alert_row：绘制边缘模型监控告警行 [A]  drift-alert  Data Drift  Warning
# name 为告警名，type 为类型，state 0=已解决 1=活动。
# 用于边缘模型监控告警管理。
fn uc_edge_model_alert_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'A', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'W', UC_YELLOW, bg);
        uc_set(x + 13 + nlen + tlen, y, 'a', UC_YELLOW, bg);
        uc_set(x + 14 + nlen + tlen, y, 'r', UC_YELLOW, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 16 + nlen + tlen, y, 'i', UC_YELLOW, bg);
        uc_set(x + 17 + nlen + tlen, y, 'n', UC_YELLOW, bg);
        uc_set(x + 18 + nlen + tlen, y, 'g', UC_YELLOW, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'K', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.751 边缘数字孪生行 ============

# uc_edge_digital_twin_row：绘制边缘数字孪生行 [T]  turbine-01  3D Model  Synced
# name 为孪生名，type 为类型，state 0=不同步 1=已同步。
# 用于边缘数字孪生管理。
fn uc_edge_digital_twin_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'T', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'S', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'y', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'y', UC_RED, bg);
        uc_set(x + 16 + nlen + tlen, y, 'n', UC_RED, bg);
        uc_set(x + 17 + nlen + tlen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + nlen + tlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.752 边缘设备孪生行 ============

# uc_edge_device_twin_row：绘制边缘设备孪生行 [D]  sensor-01-twin  temperature  Synced
# name 为孪生名，property 为属性，state 0=不同步 1=已同步。
# 用于边缘设备孪生管理。
fn uc_edge_device_twin_row(x: i64, y: i64, name: ptr, property: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(property);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, property[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'S', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'y', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 'n', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen + plen, y, 'e', UC_GREEN, bg);
        uc_set(x + 17 + nlen + plen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + plen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + plen, y, 's', UC_RED, bg);
        uc_set(x + 15 + nlen + plen, y, 'y', UC_RED, bg);
        uc_set(x + 16 + nlen + plen, y, 'n', UC_RED, bg);
        uc_set(x + 17 + nlen + plen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen + plen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + nlen + plen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.753 边缘数字线程行 ============

# uc_edge_digital_thread_row：绘制边缘数字线程行 [T]  product-xyz  5 stages  Active
# name 为线程名，stages 为阶段数，state 0=停用 1=启用。
# 用于边缘数字线程管理。
fn uc_edge_digital_thread_row(x: i64, y: i64, name: ptr, stages: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'T', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + stages, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.754 边缘资产层次行 ============

# uc_edge_asset_hierarchy_row：绘制边缘资产层次行 [H]  factory  plant-a  12 assets
# name 为层次名，parent 为父级，assets 为资产数。
# 用于边缘资产层次管理。
fn uc_edge_asset_hierarchy_row(x: i64, y: i64, name: ptr, parent: ptr, assets: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(parent);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'H', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, parent[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + plen, y, '0' + assets / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + plen, y, '0' + assets % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + plen, y, ' ', UC_CYAN, bg);
    uc_set(x + 15 + nlen + plen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + plen, y, 's', UC_CYAN, bg);
    uc_set(x + 17 + nlen + plen, y, 's', UC_CYAN, bg);
    uc_set(x + 18 + nlen + plen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + plen, y, 't', UC_CYAN, bg);
    uc_set(x + 20 + nlen + plen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.755 边缘资产健康行 ============

# uc_edge_asset_health_row：绘制边缘资产健康行 [H]  turbine-01  92%  Healthy
# name 为资产名，score 为健康分，state 0=异常 1=健康。
# 用于边缘资产健康管理。
fn uc_edge_asset_health_row(x: i64, y: i64, name: ptr, score: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'H', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + score / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + score % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'H', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'h', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'y', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'D', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'g', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'r', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'd', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.756 边缘预测性维护行 ============

# uc_edge_predictive_maintenance_row：绘制边缘预测性维护行 [P]  bearing-wear  85%  Risk Low
# name 为预测项，probability 为概率，state 0=高风险 1=低风险。
# 用于边缘预测性维护管理。
fn uc_edge_predictive_maintenance_row(x: i64, y: i64, name: ptr, probability: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + probability / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + probability % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'L', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'w', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'k', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'H', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'g', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'h', UC_RED, bg);
        uc_set(x + 18 + nlen, y, ' ', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'R', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'k', UC_RED, bg);
    }
    return 0;
}

# ============ v1.757 边缘维护工单行 ============

# uc_edge_maintenance_order_row：绘制边缘维护工单行 [O]  WO-1001  In Progress  turbine-01
# name 为工单号，state 0=完成 1=进行中，asset 为资产。
# 用于边缘维护工单管理。
fn uc_edge_maintenance_order_row(x: i64, y: i64, name: ptr, state: i64, asset: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(asset);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'O', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 10 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 11 + nlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 12 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 13 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 14 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 15 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 16 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 17 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 19 + nlen, y, 's', UC_CYAN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'D', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'e', UC_GREEN, bg);
    }
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 22 + nlen + i, y, asset[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.758 边缘备件库存行 ============

# uc_edge_spare_part_row：绘制边缘备件库存行 [P]  bearing-6205  50 units  Low Stock
# name 为备件名，units 为数量，state 0=缺货 1=有货。
# 用于边缘备件库存管理。
fn uc_edge_spare_part_row(x: i64, y: i64, name: ptr, units: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + units / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + units % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'O', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'K', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'L', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'w', UC_RED, bg);
        uc_set(x + 22 + nlen, y, ' ', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'k', UC_RED, bg);
    }
    return 0;
}

# ============ v1.759 边缘维护计划行 ============

# uc_edge_maintenance_plan_row：绘制边缘维护计划行 [P]  PM-001  Monthly  Scheduled
# name 为计划名，frequency 为频率，state 0=已取消 1=已排期。
# 用于边缘维护计划管理。
fn uc_edge_maintenance_plan_row(x: i64, y: i64, name: ptr, frequency: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    flen = strlen(frequency);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + nlen + i, y, frequency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + flen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + flen, y, 'S', UC_GREEN, bg);
        uc_set(x + 13 + nlen + flen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + flen, y, 'h', UC_GREEN, bg);
        uc_set(x + 15 + nlen + flen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen + flen, y, 'd', UC_GREEN, bg);
        uc_set(x + 17 + nlen + flen, y, 'u', UC_GREEN, bg);
        uc_set(x + 18 + nlen + flen, y, 'l', UC_GREEN, bg);
        uc_set(x + 19 + nlen + flen, y, 'e', UC_GREEN, bg);
        uc_set(x + 20 + nlen + flen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + flen, y, 'C', UC_RED, bg);
        uc_set(x + 13 + nlen + flen, y, 'a', UC_RED, bg);
        uc_set(x + 14 + nlen + flen, y, 'n', UC_RED, bg);
        uc_set(x + 15 + nlen + flen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + flen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + flen, y, 'l', UC_RED, bg);
        uc_set(x + 18 + nlen + flen, y, 'e', UC_RED, bg);
        uc_set(x + 19 + nlen + flen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.760 边缘停机事件行 ============

# uc_edge_downtime_event_row：绘制边缘停机事件行 [D]  DT-001  Resolved  45 min
# name 为事件号，state 0=未解决 1=已解决，duration 为时长。
# 用于边缘停机事件管理。
fn uc_edge_downtime_event_row(x: i64, y: i64, name: ptr, state: i64, duration: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'D', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 9 + nlen, y, 'R', UC_GREEN, bg);
        uc_set(x + 10 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 11 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 12 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 13 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 9 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 10 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 11 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 12 + nlen, y, 'n', UC_RED, bg);
    }
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 19 + nlen + i, y, duration[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.761 边缘能源计量行 ============

# uc_edge_energy_meter_row：绘制边缘能源计量行 [M]  meter-01  12.5 kWh  15:00
# name 为计量点，value 为读数，time 为时间。
# 用于边缘能源计量管理。
fn uc_edge_energy_meter_row(x: i64, y: i64, name: ptr, value: ptr, time: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    tlen = strlen(time);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 12 + nlen + vlen + i, y, time[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.762 边缘能耗仪表盘行 ============

# uc_edge_energy_dashboard_row：绘制边缘能耗仪表盘行 [D]  plant-dash  3 widgets  Active
# name 为仪表盘名，widgets 为组件数，state 0=停用 1=启用。
# 用于边缘能耗仪表盘管理。
fn uc_edge_energy_dashboard_row(x: i64, y: i64, name: ptr, widgets: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + widgets, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'w', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.763 边缘碳排放行 ============

# uc_edge_carbon_row：绘制边缘碳排放行 [C]  plant-emission  2.3 tCO2  Today
# name 为排放源，value 为排放量，period 为周期。
# 用于边缘碳排放管理。
fn uc_edge_carbon_row(x: i64, y: i64, name: ptr, value: ptr, period: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    plen = strlen(period);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 12 + nlen + vlen + i, y, period[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.764 边缘能源优化建议行 ============

# uc_edge_energy_opt_row：绘制边缘能源优化建议行 [O]  reduce-idle  Save 5%  3 actions
# name 为建议名，effect 为效果，actions 为动作数。
# 用于边缘能源优化建议管理。
fn uc_edge_energy_opt_row(x: i64, y: i64, name: ptr, effect: ptr, actions: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let elen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    elen = strlen(effect);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'O', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < elen {
        uc_set(x + 9 + nlen + i, y, effect[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + elen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + elen, y, '0' + actions, UC_CYAN, bg);
    uc_set(x + 13 + nlen + elen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + elen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen + elen, y, 'c', UC_CYAN, bg);
    uc_set(x + 16 + nlen + elen, y, 't', UC_CYAN, bg);
    uc_set(x + 17 + nlen + elen, y, 'i', UC_CYAN, bg);
    uc_set(x + 18 + nlen + elen, y, 'o', UC_CYAN, bg);
    uc_set(x + 19 + nlen + elen, y, 'n', UC_CYAN, bg);
    uc_set(x + 20 + nlen + elen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.765 边缘功率调节行 ============

# uc_edge_power_adjust_row：绘制边缘功率调节行 [P]  turbine-01  85%  Adjusting
# name 为调节点，power 为功率，state 0=停止 1=调节中。
# 用于边缘功率调节管理。
fn uc_edge_power_adjust_row(x: i64, y: i64, name: ptr, power: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'P', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + power / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + power % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'j', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'u', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'g', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'S', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'o', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'p', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.766 边缘需求响应行 ============

# uc_edge_demand_response_row：绘制边缘需求响应行 [D]  DR-001  50 kW  Enrolled
# name 为响应名，capacity 为容量，state 0=未参与 1=已参与。
# 用于边缘需求响应管理。
fn uc_edge_demand_response_row(x: i64, y: i64, name: ptr, capacity: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(capacity);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, capacity[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'E', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 'r', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'o', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'l', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'l', UC_GREEN, bg);
        uc_set(x + 18 + nlen + clen, y, 'e', UC_GREEN, bg);
        uc_set(x + 19 + nlen + clen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'N', UC_RED, bg);
        uc_set(x + 13 + nlen + clen, y, 'o', UC_RED, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_RED, bg);
        uc_set(x + 15 + nlen + clen, y, ' ', UC_RED, bg);
        uc_set(x + 16 + nlen + clen, y, 'J', UC_RED, bg);
        uc_set(x + 17 + nlen + clen, y, 'o', UC_RED, bg);
        uc_set(x + 18 + nlen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 19 + nlen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 20 + nlen + clen, y, 'e', UC_RED, bg);
        uc_set(x + 21 + nlen + clen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.767 边缘电网交互行 ============

# uc_edge_grid_interaction_row：绘制边缘电网交互行 [G]  grid-01  Buying  1.2 MW
# name 为交互点，mode 为模式，power 为功率。
# 用于边缘电网交互管理。
fn uc_edge_grid_interaction_row(x: i64, y: i64, name: ptr, mode: ptr, power: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(mode);
    plen = strlen(power);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'G', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, mode[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 12 + nlen + mlen + i, y, power[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.768 边缘微网行 ============

# uc_edge_microgrid_row：绘制边缘微网行 [M]  microgrid-1  5 sources  Islanded
# name 为微网名，sources 为电源数，state 0=并网 1=孤岛。
# 用于边缘微网管理。
fn uc_edge_microgrid_row(x: i64, y: i64, name: ptr, sources: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + sources, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'a', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'd', UC_CYAN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'G', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'r', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'd', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, ' ', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'T', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'd', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.769 边缘储能行 ============

# uc_edge_storage_battery_row：绘制边缘储能行 [B]  battery-01  80%  200 kWh
# name 为储能名，soc 为电量，capacity 为容量。
# 用于边缘储能管理。
fn uc_edge_storage_battery_row(x: i64, y: i64, name: ptr, soc: i64, capacity: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(capacity);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'B', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + soc / 10, UC_GREEN, bg);
    uc_set(x + 10 + nlen, y, '0' + soc % 10, UC_GREEN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 14 + nlen + i, y, capacity[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.770 边缘充电桩行 ============

# uc_edge_charger_row：绘制边缘充电桩行 [C]  charger-01  50 kW  In Use
# name 为充电桩名，power 为功率，state 0=空闲 1=使用中。
# 用于边缘充电桩管理。
fn uc_edge_charger_row(x: i64, y: i64, name: ptr, power: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(power);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 9 + nlen + i, y, power[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + plen, y, 'I', UC_CYAN, bg);
        uc_set(x + 13 + nlen + plen, y, 'n', UC_CYAN, bg);
        uc_set(x + 14 + nlen + plen, y, ' ', UC_CYAN, bg);
        uc_set(x + 15 + nlen + plen, y, 'U', UC_CYAN, bg);
        uc_set(x + 16 + nlen + plen, y, 's', UC_CYAN, bg);
        uc_set(x + 17 + nlen + plen, y, 'e', UC_CYAN, bg);
    } else {
        uc_set(x + 12 + nlen + plen, y, 'I', UC_GREEN, bg);
        uc_set(x + 13 + nlen + plen, y, 'd', UC_GREEN, bg);
        uc_set(x + 14 + nlen + plen, y, 'l', UC_GREEN, bg);
        uc_set(x + 15 + nlen + plen, y, 'e', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.771 边缘安全管理行 ============

# uc_edge_security_row：绘制边缘安全管理行 [S]  edge-sec  5 policies  Active
# name 为管理名，policies 为策略数，state 0=停用 1=启用。
# 用于边缘安全管理。
fn uc_edge_security_row(x: i64, y: i64, name: ptr, policies: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'S', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + policies, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.772 边缘漏洞行 ============

# uc_edge_vulnerability_row：绘制边缘漏洞行 [V]  CVE-2024-1234  High  Open
# name 为漏洞号，severity 为严重性，state 0=已修复 1=开放。
# 用于边缘漏洞管理。
fn uc_edge_vulnerability_row(x: i64, y: i64, name: ptr, severity: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(severity);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'V', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, severity[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'O', UC_RED, bg);
        uc_set(x + 13 + nlen + slen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen + slen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen + slen, y, 'n', UC_RED, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'F', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 'x', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'e', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'd', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.773 边缘补丁管理行 ============

# uc_edge_patch_row：绘制边缘补丁管理行 [P]  patch-20240115  Applied  50 devices
# name 为补丁名，state 为状态，devices 为设备数。
# 用于边缘补丁管理。
fn uc_edge_patch_row(x: i64, y: i64, name: ptr, state: ptr, devices: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + devices / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + devices % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'v', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.774 边缘合规审计行 ============

# uc_edge_compliance_audit_row：绘制边缘合规审计行 [A]  audit-001  Compliant  12 checks
# name 为审计名，state 为状态，checks 为检查数。
# 用于边缘合规审计管理。
fn uc_edge_compliance_audit_row(x: i64, y: i64, name: ptr, state: ptr, checks: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'A', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + checks / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + checks % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'h', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'k', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.775 边缘威胁检测行 ============

# uc_edge_threat_row：绘制边缘威胁检测行 [T]  threat-01  Malware  Blocked
# name 为威胁名，type 为类型，state 0=未处理 1=已阻断。
# 用于边缘威胁检测管理。
fn uc_edge_threat_row(x: i64, y: i64, name: ptr, type: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'T', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + tlen, y, 'B', UC_GREEN, bg);
        uc_set(x + 13 + nlen + tlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 14 + nlen + tlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 15 + nlen + tlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen + tlen, y, 'k', UC_GREEN, bg);
        uc_set(x + 17 + nlen + tlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 18 + nlen + tlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + tlen, y, 'O', UC_RED, bg);
        uc_set(x + 13 + nlen + tlen, y, 'p', UC_RED, bg);
        uc_set(x + 14 + nlen + tlen, y, 'e', UC_RED, bg);
        uc_set(x + 15 + nlen + tlen, y, 'n', UC_RED, bg);
    }
    return 0;
}

# ============ v1.776 边缘防火墙规则行 ============

# uc_edge_firewall_rule_row：绘制边缘防火墙规则行 [F]  fw-rule-01  Allow  80/tcp
# name 为规则名，action 为动作，target 为目标。
# 用于边缘防火墙规则管理。
fn uc_edge_firewall_rule_row(x: i64, y: i64, name: ptr, action: ptr, target: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(action);
    tlen = strlen(target);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'F', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + nlen + i, y, action[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    i = 0;
    while i < tlen {
        uc_set(x + 12 + nlen + alen + i, y, target[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.777 边缘入侵检测行 ============

# uc_edge_ids_row：绘制边缘入侵检测行 [I]  ids-01  Monitoring  3 alerts
# name 为检测器名，state 为状态，alerts 为告警数。
# 用于边缘入侵检测管理。
fn uc_edge_ids_row(x: i64, y: i64, name: ptr, state: ptr, alerts: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'I', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + alerts, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, 'a', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, 'l', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.778 边缘加密管理行 ============

# uc_edge_encryption_row：绘制边缘加密管理行 [E]  key-rotator  AES-256  Rotating
# name 为管理项，algorithm 为算法，state 0=停止 1=运行。
# 用于边缘加密管理。
fn uc_edge_encryption_row(x: i64, y: i64, name: ptr, algorithm: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(algorithm);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'E', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + nlen + i, y, algorithm[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + alen, y, 'R', UC_CYAN, bg);
        uc_set(x + 13 + nlen + alen, y, 'o', UC_CYAN, bg);
        uc_set(x + 14 + nlen + alen, y, 't', UC_CYAN, bg);
        uc_set(x + 15 + nlen + alen, y, 'a', UC_CYAN, bg);
        uc_set(x + 16 + nlen + alen, y, 't', UC_CYAN, bg);
        uc_set(x + 17 + nlen + alen, y, 'i', UC_CYAN, bg);
        uc_set(x + 18 + nlen + alen, y, 'n', UC_CYAN, bg);
        uc_set(x + 19 + nlen + alen, y, 'g', UC_CYAN, bg);
    } else {
        uc_set(x + 12 + nlen + alen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + alen, y, 'd', UC_RED, bg);
        uc_set(x + 14 + nlen + alen, y, 'l', UC_RED, bg);
        uc_set(x + 15 + nlen + alen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.779 边缘证书管理行 ============

# uc_edge_cert_mgmt_row：绘制边缘证书管理行 [C]  cert-01  Valid  30 days
# name 为证书名，state 为状态，days 为剩余天数。
# 用于边缘证书管理。
fn uc_edge_cert_mgmt_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + days / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + days % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, 'd', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'y', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.780 边缘身份认证行 ============

# uc_edge_identity_row：绘制边缘身份认证行 [I]  identity-01  OAuth2  Active
# name 为身份名，method 为认证方式，state 0=停用 1=启用。
# 用于边缘身份认证管理。
fn uc_edge_identity_row(x: i64, y: i64, name: ptr, method: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(method);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'I', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, method[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + mlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + mlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + mlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + mlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + mlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + mlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + mlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + mlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + mlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + mlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + mlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + mlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + mlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + mlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.781 边缘日志管理行 ============

# uc_edge_log_management_row：绘制边缘日志管理行 [L]  log-center  2.3 GB  Active
# name 为管理名，storage 为存储量，state 0=停用 1=启用。
# 用于边缘日志管理。
fn uc_edge_log_management_row(x: i64, y: i64, name: ptr, storage: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(storage);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'L', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, storage[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + slen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + slen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + slen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + slen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + slen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + slen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + slen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + slen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + slen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + slen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + slen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + slen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + slen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.782 边缘日志流行 ============

# uc_edge_log_stream_row：绘制边缘日志流行 [S]  syslog-stream  Streaming  200 eps
# name 为流名，state 为状态，eps 为事件率。
# 用于边缘日志流管理。
fn uc_edge_log_stream_row(x: i64, y: i64, name: ptr, state: ptr, eps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'S', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + eps / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (eps / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + eps % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.783 边缘审计日志行 ============

# uc_edge_audit_log_row：绘制边缘审计日志行 [A]  audit-log-01  500 entries  Retained
# name 为日志名，entries 为条数，state 为状态。
# 用于边缘审计日志管理。
fn uc_edge_audit_log_row(x: i64, y: i64, name: ptr, entries: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'A', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + entries / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (entries / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + entries % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 22 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.784 边缘指标采集行 ============

# uc_edge_metric_collector_row：绘制边缘指标采集行 [M]  node-exporter  Collecting  100 sps
# name 为采集器名，state 为状态，sps 为采样率。
# 用于边缘指标采集管理。
fn uc_edge_metric_collector_row(x: i64, y: i64, name: ptr, state: ptr, sps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + sps / 100, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (sps / 10) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + sps % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 's', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.785 边缘监控仪表盘行 ============

# uc_edge_monitor_dashboard_row：绘制边缘监控仪表盘行 [D]  edge-monitor  5 panels  Live
# name 为仪表盘名，panels 为面板数，state 0=离线 1=在线。
# 用于边缘监控仪表盘管理。
fn uc_edge_monitor_dashboard_row(x: i64, y: i64, name: ptr, panels: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + panels, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'L', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'O', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'f', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.786 边缘告警路由行 ============

# uc_edge_alert_route_row：绘制边缘告警路由行 [R]  route-01  3 targets  Active
# name 为路由名，targets 为目标数，state 0=停用 1=启用。
# 用于边缘告警路由管理。
fn uc_edge_alert_route_row(x: i64, y: i64, name: ptr, targets: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'R', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + targets, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.787 边缘告警升级行 ============

# uc_edge_alert_escalation_row：绘制边缘告警升级行 [E]  esc-01  3 levels  Enabled
# name 为升级名，levels 为级别数，state 0=禁用 1=启用。
# 用于边缘告警升级管理。
fn uc_edge_alert_escalation_row(x: i64, y: i64, name: ptr, levels: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'E', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + levels, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'E', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'b', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'l', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'e', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'd', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'D', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 's', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'b', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.788 边缘健康检查行 ============

# uc_edge_health_check_row：绘制边缘健康检查行 [H]  hc-01  Healthy  5 checks
# name 为检查名，state 为状态，checks 为检查数。
# 用于边缘健康检查管理。
fn uc_edge_health_check_row(x: i64, y: i64, name: ptr, state: ptr, checks: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'H', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + checks, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'h', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'k', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.789 边缘性能基准行 ============

# uc_edge_perf_benchmark_row：绘制边缘性能基准行 [B]  bench-01  1200 ops  Pass
# name 为基准名，ops 为操作数，state 0=失败 1=通过。
# 用于边缘性能基准管理。
fn uc_edge_perf_benchmark_row(x: i64, y: i64, name: ptr, ops: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'B', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + ops / 1000, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (ops / 100) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + (ops / 10) % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, '0' + ops % 10, UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 19 + nlen, y, 'P', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 's', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 's', UC_GREEN, bg);
    } else {
        uc_set(x + 19 + nlen, y, 'F', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'l', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.790 边缘遥测流行 ============

# uc_edge_telemetry_stream_row：绘制边缘遥测流行 [S]  telemetry-01  Streaming  500 dps
# name 为流名，state 为状态，dps 为数据率。
# 用于边缘遥测流管理。
fn uc_edge_telemetry_stream_row(x: i64, y: i64, name: ptr, state: ptr, dps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + dps / 100, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (dps / 10) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + dps % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'd', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.791 边缘 API 网关行 ============

# uc_edge_api_gateway_row：绘制边缘 API 网关行 [G]  edge-gw  500 rpm  Active
# name 为网关名，rpm 为请求率，state 0=停用 1=启用。
# 用于边缘 API 网关管理。
fn uc_edge_api_gateway_row(x: i64, y: i64, name: ptr, rpm: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'G', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + rpm / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (rpm / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + rpm % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.792 边缘 API 策略行 ============

# uc_edge_api_policy_row：绘制边缘 API 策略行 [P]  rate-limit  100 rpm  Applied
# name 为策略名，limit 为限额，state 为状态。
# 用于边缘 API 策略管理。
fn uc_edge_api_policy_row(x: i64, y: i64, name: ptr, limit: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(limit);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 9 + nlen + i, y, limit[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + llen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.793 边缘 API 版本行 ============

# uc_edge_api_version_row：绘制边缘 API 版本行 [V]  devices-api  v2.1  Active
# name 为 API 名，version 为版本，state 0=弃用 1=活动。
# 用于边缘 API 版本管理。
fn uc_edge_api_version_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'V', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + vlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + vlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + vlen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + vlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + vlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + vlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + vlen, y, 'D', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'p', UC_RED, bg);
        uc_set(x + 15 + nlen + vlen, y, 'r', UC_RED, bg);
        uc_set(x + 16 + nlen + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 17 + nlen + vlen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen + vlen, y, 'a', UC_RED, bg);
        uc_set(x + 19 + nlen + vlen, y, 't', UC_RED, bg);
        uc_set(x + 20 + nlen + vlen, y, 'e', UC_RED, bg);
        uc_set(x + 21 + nlen + vlen, y, 'd', UC_RED, bg);
    }
    return 0;
}

# ============ v1.794 边缘 API 键行 ============

# uc_edge_api_key_row：绘制边缘 API 键行 [K]  api-key-01  Active  5000 calls
# name 为键名，state 为状态，calls 为调用数。
# 用于边缘 API 键管理。
fn uc_edge_api_key_row(x: i64, y: i64, name: ptr, state: ptr, calls: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'K', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + calls / 1000, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (calls / 100) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + (calls / 10) % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, '0' + calls % 10, UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'c', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 19 + nlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 20 + nlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.795 边缘服务发现行 ============

# uc_edge_service_discovery_row：绘制边缘服务发现行 [D]  consul-edge  5 services  Healthy
# name 为发现名，services 为服务数，state 为状态。
# 用于边缘服务发现管理。
fn uc_edge_service_discovery_row(x: i64, y: i64, name: ptr, services: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'D', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + services, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 21 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.796 边缘服务网格行 ============

# uc_edge_service_mesh_row：绘制边缘服务网格行 [M]  edge-mesh  3 namespaces  Active
# name 为网格名，namespaces 为命名空间数，state 0=停用 1=启用。
# 用于边缘服务网格管理。
fn uc_edge_service_mesh_row(x: i64, y: i64, name: ptr, namespaces: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'M', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + namespaces, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 22 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 23 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 23 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 29 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 30 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.797 边缘流量路由行 ============

# uc_edge_traffic_route_row：绘制边缘流量路由行 [R]  route-v1  80%  Stable
# name 为路由名，weight 为权重，state 为状态。
# 用于边缘流量路由管理。
fn uc_edge_traffic_route_row(x: i64, y: i64, name: ptr, weight: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + weight / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + weight % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 14 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.798 边缘熔断器行 ============

# uc_edge_circuit_breaker_row：绘制边缘熔断器行 [B]  cb-01  Closed  5 errors
# name 为熔断器名，state 为状态，errors 为错误数。
# 用于边缘熔断器管理。
fn uc_edge_circuit_breaker_row(x: i64, y: i64, name: ptr, state: ptr, errors: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'B', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + errors, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.799 边缘重试策略行 ============

# uc_edge_retry_policy_row：绘制边缘重试策略行 [P]  retry-01  3 retries  500ms
# name 为策略名，retries 为重试数，interval 为间隔。
# 用于边缘重试策略管理。
fn uc_edge_retry_policy_row(x: i64, y: i64, name: ptr, retries: i64, interval: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ilen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ilen = strlen(interval);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + retries, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < ilen {
        uc_set(x + 20 + nlen + i, y, interval[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.800 边缘负载均衡行 ============

# uc_edge_load_balancer_row：绘制边缘负载均衡行 [L]  lb-01  3 backends  Active
# name 为均衡器名，backends 为后端数，state 0=停用 1=启用。
# 用于边缘负载均衡管理。
fn uc_edge_load_balancer_row(x: i64, y: i64, name: ptr, backends: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'L', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + backends, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'b', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'k', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 21 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 26 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 21 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.801 边缘代码仓库行 ============

# uc_edge_repo_row：绘制边缘代码仓库行 [R]  edge-app  master  120 commits
# name 为仓库名，branch 为分支，commits 为提交数。
# 用于边缘代码仓库管理。
fn uc_edge_repo_row(x: i64, y: i64, name: ptr, branch: ptr, commits: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    blen = strlen(branch);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 9 + nlen + i, y, branch[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + blen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + blen, y, '0' + commits / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + blen, y, '0' + (commits / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + blen, y, '0' + commits % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + blen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + blen, y, 'c', UC_CYAN, bg);
    uc_set(x + 17 + nlen + blen, y, 'o', UC_CYAN, bg);
    uc_set(x + 18 + nlen + blen, y, 'm', UC_CYAN, bg);
    uc_set(x + 19 + nlen + blen, y, 'm', UC_CYAN, bg);
    uc_set(x + 20 + nlen + blen, y, 'i', UC_CYAN, bg);
    uc_set(x + 21 + nlen + blen, y, 't', UC_CYAN, bg);
    uc_set(x + 22 + nlen + blen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.802 边缘构建任务行 ============

# uc_edge_build_task_row：绘制边缘构建任务行 [B]  build-001  Succeeded  2.5 min
# name 为任务名，state 为状态，duration 为时长。
# 用于边缘构建任务管理。
fn uc_edge_build_task_row(x: i64, y: i64, name: ptr, state: ptr, duration: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let dlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    dlen = strlen(duration);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'B', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < dlen {
        uc_set(x + 12 + nlen + slen + i, y, duration[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.803 边缘部署流水线行 ============

# uc_edge_deploy_pipeline_row：绘制边缘部署流水线行 [P]  deploy-pipe  Running  stage 2/5
# name 为流水线名，state 为状态，stage 为阶段。
# 用于边缘部署流水线管理。
fn uc_edge_deploy_pipeline_row(x: i64, y: i64, name: ptr, state: ptr, stage: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'P', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, 's', UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, '0' + stage, UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, '/', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, '5', UC_CYAN, bg);
    return 0;
}

# ============ v1.804 边缘发布行 ============

# uc_edge_release_row：绘制边缘发布行 [R]  v1.0.0  Published  5 assets
# name 为发布名，state 为状态，assets 为资产数。
# 用于边缘发布管理。
fn uc_edge_release_row(x: i64, y: i64, name: ptr, state: ptr, assets: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + assets, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 's', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 's', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.805 边缘环境配置行 ============

# uc_edge_env_config_row：绘制边缘环境配置行 [C]  production  5 vars  Applied
# name 为配置名，vars 为变量数，state 为状态。
# 用于边缘环境配置管理。
fn uc_edge_env_config_row(x: i64, y: i64, name: ptr, vars: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + vars, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 17 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.806 边缘配置管理行 ============

# uc_edge_config_mgmt_row：绘制边缘配置管理行 [C]  config-server  10 configs  Active
# name 为管理名，configs 为配置数，state 0=停用 1=启用。
# 用于边缘配置管理。
fn uc_edge_config_mgmt_row(x: i64, y: i64, name: ptr, configs: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'C', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + configs, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'f', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.807 边缘密钥管理行 ============

# uc_edge_key_mgmt_row：绘制边缘密钥管理行 [K]  kms-01  3 keys  Rotated
# name 为管理名，keys 为密钥数，state 为状态。
# 用于边缘密钥管理。
fn uc_edge_key_mgmt_row(x: i64, y: i64, name: ptr, keys: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'K', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + keys, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'k', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'y', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 17 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.808 边缘镜像仓库行 ============

# uc_edge_image_repo_row：绘制边缘镜像仓库行 [I]  edge-images  50 images  Active
# name 为仓库名，images 为镜像数，state 0=停用 1=启用。
# 用于边缘镜像仓库管理。
fn uc_edge_image_repo_row(x: i64, y: i64, name: ptr, images: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'I', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + images / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + images % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.809 边缘容器注册表行 ============

# uc_edge_registry_row：绘制边缘容器注册表行 [R]  registry-01  5 repos  Active
# name 为注册表名，repos 为仓库数，state 0=停用 1=启用。
# 用于边缘容器注册表管理。
fn uc_edge_registry_row(x: i64, y: i64, name: ptr, repos: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'R', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + repos, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 18 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 18 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.810 边缘镜像扫描行 ============

# uc_edge_image_scan_row：绘制边缘镜像扫描行 [S]  scan-01  No Issues  25 layers
# name 为扫描名，state 为状态，layers 为层数。
# 用于边缘镜像扫描管理。
fn uc_edge_image_scan_row(x: i64, y: i64, name: ptr, state: ptr, layers: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + layers, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'l', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'y', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.811 边缘云连接行 ============

# uc_edge_cloud_conn_row：绘制边缘云连接行 [C]  aws-conn  Connected  20 ms
# name 为连接名，state 为状态，latency 为延迟。
# 用于边缘云连接管理。
fn uc_edge_cloud_conn_row(x: i64, y: i64, name: ptr, state: ptr, latency: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    llen = strlen(latency);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 12 + nlen + slen + i, y, latency[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.812 边缘私有网络行 ============

# uc_edge_private_net_row：绘制边缘私有网络行 [N]  vpc-edge  10.0.0.0/16  Active
# name 为网络名，cidr 为网段，state 0=停用 1=启用。
# 用于边缘私有网络管理。
fn uc_edge_private_net_row(x: i64, y: i64, name: ptr, cidr: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(cidr);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'N', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, cidr[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 12 + nlen + clen, y, 'A', UC_GREEN, bg);
        uc_set(x + 13 + nlen + clen, y, 'c', UC_GREEN, bg);
        uc_set(x + 14 + nlen + clen, y, 't', UC_GREEN, bg);
        uc_set(x + 15 + nlen + clen, y, 'i', UC_GREEN, bg);
        uc_set(x + 16 + nlen + clen, y, 'v', UC_GREEN, bg);
        uc_set(x + 17 + nlen + clen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 12 + nlen + clen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + clen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + clen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + clen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + clen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + clen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + clen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + clen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.813 边缘 VPN 行 ============

# uc_edge_vpn_row：绘制边缘 VPN 行 [V]  vpn-01  Connected  2 tunnels
# name 为 VPN 名，state 为状态，tunnels 为隧道数。
# 用于边缘 VPN 管理。
fn uc_edge_vpn_row(x: i64, y: i64, name: ptr, state: ptr, tunnels: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'V', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + tunnels, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'n', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'n', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'l', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.814 边缘 DNS 行 ============

# uc_edge_dns_row：绘制边缘 DNS 行 [D]  edge-dns  5 records  Active
# name 为 DNS 名，records 为记录数，state 0=停用 1=启用。
# 用于边缘 DNS 管理。
fn uc_edge_dns_row(x: i64, y: i64, name: ptr, records: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'D', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + records, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 20 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 24 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 25 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 23 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 24 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 25 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 26 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 27 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.815 边缘负载均衡策略行 ============

# uc_edge_lb_policy_row：绘制边缘负载均衡策略行 [P]  round-robin  3 backends  Applied
# name 为策略名，backends 为后端数，state 为状态。
# 用于边缘负载均衡策略管理。
fn uc_edge_lb_policy_row(x: i64, y: i64, name: ptr, backends: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + backends, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'b', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'k', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 21 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.816 边缘云同步行 ============

# uc_edge_cloud_sync_row：绘制边缘云同步行 [S]  cloud-sync-01  Synced  10 min ago
# name 为同步名，state 为状态，last 为上次时间。
# 用于边缘云同步管理。
fn uc_edge_cloud_sync_row(x: i64, y: i64, name: ptr, state: ptr, last: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    llen = strlen(last);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'S', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 12 + nlen + slen + i, y, last[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.817 边缘离线数据行 ============

# uc_edge_offline_data_row：绘制边缘离线数据行 [O]  offline-buffer  2 GB  Buffering
# name 为数据名，size 为大小，state 为状态。
# 用于边缘离线数据管理。
fn uc_edge_offline_data_row(x: i64, y: i64, name: ptr, size: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let sizlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    sizlen = strlen(size);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'O', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < sizlen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + sizlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + sizlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.818 边缘数据同步行 ============

# uc_edge_data_sync_row：绘制边缘数据同步行 [S]  data-sync  500 records  Synced
# name 为同步名，records 为记录数，state 为状态。
# 用于边缘数据同步管理。
fn uc_edge_data_sync_row(x: i64, y: i64, name: ptr, records: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'S', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + records / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (records / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + records % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 22 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.819 边缘数据压缩行 ============

# uc_edge_data_compress_row：绘制边缘数据压缩行 [C]  zstd-01  75% ratio  Active
# name 为压缩器名，ratio 为比率，state 0=停用 1=启用。
# 用于边缘数据压缩管理。
fn uc_edge_data_compress_row(x: i64, y: i64, name: ptr, ratio: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'C', UC_CYAN, bg);
    uc_set(x + 2, y, ']', UC_CYAN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + ratio / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + ratio % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '%', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 14 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 15 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 14 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 15 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.820 边缘数据加密行 ============

# uc_edge_data_encrypt_row：绘制边缘数据加密行 [E]  encrypt-01  AES-256  At Rest
# name 为加密器名，algorithm 为算法，state 为状态。
# 用于边缘数据加密管理。
fn uc_edge_data_encrypt_row(x: i64, y: i64, name: ptr, algorithm: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(algorithm);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'E', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < alen {
        uc_set(x + 9 + nlen + i, y, algorithm[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + alen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}
