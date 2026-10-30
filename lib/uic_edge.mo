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

# ============ v1.821 边缘业务应用行 ============

# uc_edge_biz_app_row：绘制边缘业务应用行 [A]  erp-app  Running  5 nodes
# name 为应用名，state 为状态，nodes 为节点数。
# 用于边缘业务应用管理。
fn uc_edge_biz_app_row(x: i64, y: i64, name: ptr, state: ptr, nodes: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + nodes, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'n', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'o', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.822 边缘行业解决方案行 ============

# uc_edge_solution_row：绘制边缘行业解决方案行 [S]  smart-factory  5 modules  Deployed
# name 为方案名，modules 为模块数，state 为状态。
# 用于边缘行业解决方案管理。
fn uc_edge_solution_row(x: i64, y: i64, name: ptr, modules: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + modules, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'm', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 20 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.823 边缘模板行 ============

# uc_edge_template_row：绘制边缘模板行 [T]  factory-plant  5 steps  Published
# name 为模板名，steps 为步骤数，state 为状态。
# 用于边缘模板管理。
fn uc_edge_template_row(x: i64, y: i64, name: ptr, steps: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + steps, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.824 边缘许可证行 ============

# uc_edge_license_row：绘制边缘许可证行 [L]  edge-license  Valid  25 devices
# name 为许可证名，state 为状态，devices 为设备数。
# 用于边缘许可证管理。
fn uc_edge_license_row(x: i64, y: i64, name: ptr, state: ptr, devices: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + devices, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'v', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.825 边缘计费行 ============

# uc_edge_billing_row：绘制边缘计费行 [B]  billing-01  120 USD  Current
# name 为计费名，amount 为金额，state 为状态。
# 用于边缘计费管理。
fn uc_edge_billing_row(x: i64, y: i64, name: ptr, amount: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(amount);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'B', UC_GREEN, bg);
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
        uc_set(x + 9 + nlen + i, y, amount[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + alen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.826 边缘工单行 ============

# uc_edge_ticket_row：绘制边缘工单行 [T]  TC-2001  Open  High priority
# name 为工单号，state 为状态，priority 为优先级。
# 用于边缘工单管理。
fn uc_edge_ticket_row(x: i64, y: i64, name: ptr, state: ptr, priority: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    plen = strlen(priority);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 12 + nlen + slen + i, y, priority[i], UC_RED, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.827 边缘服务等级协议行 ============

# uc_edge_sla_row：绘制边缘服务等级协议行 [S]  sla-gold  99.9%  Met
# name 为协议名，uptime 为可用率，state 为状态。
# 用于边缘服务等级协议管理。
fn uc_edge_sla_row(x: i64, y: i64, name: ptr, uptime: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let ulen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    ulen = strlen(uptime);
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
    while i < ulen {
        uc_set(x + 9 + nlen + i, y, uptime[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + ulen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + ulen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.828 边缘知识库行 ============

# uc_edge_kb_row：绘制边缘知识库行 [K]  edge-kb  50 articles  Active
# name 为知识库名，articles 为文章数，state 0=停用 1=启用。
# 用于边缘知识库管理。
fn uc_edge_kb_row(x: i64, y: i64, name: ptr, articles: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
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
    uc_set(x + 9 + nlen, y, '0' + articles, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'l', UC_WHITE, bg);
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

# ============ v1.829 边缘文档行 ============

# uc_edge_doc_row：绘制边缘文档行 [D]  user-guide  20 pages  Published
# name 为文档名，pages 为页数，state 为状态。
# 用于边缘文档管理。
fn uc_edge_doc_row(x: i64, y: i64, name: ptr, pages: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + pages, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.830 边缘反馈行 ============

# uc_edge_feedback_row：绘制边缘反馈行 [F]  feedback-01  4.5 rating  Reviewed
# name 为反馈名，rating 为评分，state 为状态。
# 用于边缘反馈管理。
fn uc_edge_feedback_row(x: i64, y: i64, name: ptr, rating: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(rating);
    slen = strlen(state);
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
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, rating[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + rlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.831 边缘设备画像行 ============

# uc_edge_device_profile_row：绘制边缘设备画像行 [P]  device-01  industrial  3 tags
# name 为设备名，type 为类型，tags 为标签数。
# 用于边缘设备画像管理。
fn uc_edge_device_profile_row(x: i64, y: i64, name: ptr, type: ptr, tags: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(type);
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
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, type[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + tlen, y, '0' + tags, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + tlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + tlen, y, 't', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + tlen, y, 'a', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + tlen, y, 'g', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + tlen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.832 边缘设备行为分析行 ============

# uc_edge_device_behavior_row：绘制边缘设备行为分析行 [B]  device-01  Normal  98% conf
# name 为设备名，state 为状态，confidence 为置信度。
# 用于边缘设备行为分析管理。
fn uc_edge_device_behavior_row(x: i64, y: i64, name: ptr, state: ptr, confidence: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + confidence / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + confidence % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, '%', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'c', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'o', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 'n', UC_GREEN, bg);
    uc_set(x + 19 + nlen + slen, y, 'f', UC_GREEN, bg);
    return 0;
}

# ============ v1.833 边缘设备生命周期行 ============

# uc_edge_device_lifecycle_row：绘制边缘设备生命周期行 [L]  device-01  Active  200 days
# name 为设备名，state 为状态，days 为天数。
# 用于边缘设备生命周期管理。
fn uc_edge_device_lifecycle_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + days / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (days / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + days % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'y', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.834 边缘设备维修记录行 ============

# uc_edge_device_repair_row：绘制边缘设备维修记录行 [R]  repair-001  Completed  2 days
# name 为记录号，state 为状态，days 为天数。
# 用于边缘设备维修记录管理。
fn uc_edge_device_repair_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + days, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'y', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.835 边缘设备保养记录行 ============

# uc_edge_device_service_row：绘制边缘设备保养记录行 [S]  service-001  Scheduled  30 days
# name 为记录号，state 为状态，days 为天数。
# 用于边缘设备保养记录管理。
fn uc_edge_device_service_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 12 + nlen + slen, y, '0' + days / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + days % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, 'd', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'y', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.836 边缘设备固件版本行 ============

# uc_edge_device_firmware_row：绘制边缘设备固件版本行 [F]  fw-2.1.0  50 devices  Stable
# name 为固件名，devices 为设备数，state 为状态。
# 用于边缘设备固件版本管理。
fn uc_edge_device_firmware_row(x: i64, y: i64, name: ptr, devices: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'F', UC_MAGENTA, bg);
    uc_set(x + 2, y, ']', UC_MAGENTA, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + devices / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + devices % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 21 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.837 边缘设备配置漂移行 ============

# uc_edge_device_drift_row：绘制边缘设备配置漂移行 [D]  device-01  Detected  2 changes
# name 为设备名，state 为状态，changes 为变更数。
# 用于边缘设备配置漂移管理。
fn uc_edge_device_drift_row(x: i64, y: i64, name: ptr, state: ptr, changes: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + changes, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, 'c', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, 'h', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'a', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'n', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, 'g', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.838 边缘设备升级批次行 ============

# uc_edge_device_upgrade_row：绘制边缘设备升级批次行 [U]  batch-01  10 devices  In Progress
# name 为批次名，devices 为设备数，state 0=完成 1=进行中。
# 用于边缘设备升级批次管理。
fn uc_edge_device_upgrade_row(x: i64, y: i64, name: ptr, devices: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'U', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
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
        uc_set(x + 20 + nlen, y, 'I', UC_CYAN, bg);
        uc_set(x + 21 + nlen, y, 'n', UC_CYAN, bg);
        uc_set(x + 22 + nlen, y, ' ', UC_CYAN, bg);
        uc_set(x + 23 + nlen, y, 'P', UC_CYAN, bg);
        uc_set(x + 24 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 25 + nlen, y, 'o', UC_CYAN, bg);
        uc_set(x + 26 + nlen, y, 'g', UC_CYAN, bg);
        uc_set(x + 27 + nlen, y, 'r', UC_CYAN, bg);
        uc_set(x + 28 + nlen, y, 'e', UC_CYAN, bg);
        uc_set(x + 29 + nlen, y, 's', UC_CYAN, bg);
        uc_set(x + 30 + nlen, y, 's', UC_CYAN, bg);
    } else {
        uc_set(x + 20 + nlen, y, 'D', UC_GREEN, bg);
        uc_set(x + 21 + nlen, y, 'o', UC_GREEN, bg);
        uc_set(x + 22 + nlen, y, 'n', UC_GREEN, bg);
        uc_set(x + 23 + nlen, y, 'e', UC_GREEN, bg);
    }
    return 0;
}

# ============ v1.839 边缘设备运行统计行 ============

# uc_edge_device_stats_row：绘制边缘设备运行统计行 [S]  device-01  98% uptime  30 days
# name 为设备名，uptime 为可用率，days 为天数。
# 用于边缘设备运行统计管理。
fn uc_edge_device_stats_row(x: i64, y: i64, name: ptr, uptime: i64, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
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
    uc_set(x + 9 + nlen, y, '0' + uptime / 10, UC_GREEN, bg);
    uc_set(x + 10 + nlen, y, '0' + uptime % 10, UC_GREEN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    uc_set(x + 14 + nlen, y, '0' + days, UC_MAGENTA, bg);
    uc_set(x + 15 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen, y, 'd', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen, y, 'a', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen, y, 'y', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.840 边缘设备能耗行 ============

# uc_edge_device_energy_row：绘制边缘设备能耗行 [E]  device-01  5.2 kWh  Today
# name 为设备名，value 为能耗，period 为周期。
# 用于边缘设备能耗管理。
fn uc_edge_device_energy_row(x: i64, y: i64, name: ptr, value: ptr, period: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
    plen = strlen(period);
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
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 12 + nlen + vlen + i, y, period[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.841 边缘事件处理行 ============

# uc_edge_event_processor_row：绘制边缘事件处理行 [P]  event-proc-01  Running  500 ev/s
# name 为处理器名，state 为状态，rate 为速率。
# 用于边缘事件处理管理。
fn uc_edge_event_processor_row(x: i64, y: i64, name: ptr, state: ptr, rate: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + rate / 100, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (rate / 10) % 10, UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + rate % 10, UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'v', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, '/', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.842 边缘事件源行 ============

# uc_edge_event_source_row：绘制边缘事件源行 [S]  sensor-01  1000 events  Active
# name 为事件源名，events 为事件数，state 0=停用 1=启用。
# 用于边缘事件源管理。
fn uc_edge_event_source_row(x: i64, y: i64, name: ptr, events: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
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
    uc_set(x + 9 + nlen, y, '0' + events / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (events / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + events % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'v', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 't', UC_WHITE, bg);
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

# ============ v1.843 边缘事件目标行 ============

# uc_edge_event_target_row：绘制边缘事件目标行 [T]  sink-01  5 targets  Active
# name 为目标名，targets 为目标数，state 0=停用 1=启用。
# 用于边缘事件目标管理。
fn uc_edge_event_target_row(x: i64, y: i64, name: ptr, targets: i64, state: i64, fg: i64, bg: i64) -> i64 {
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

# ============ v1.844 边缘事件转换行 ============

# uc_edge_event_transform_row：绘制边缘事件转换行 [T]  transform-01  3 rules  Applied
# name 为转换名，rules 为规则数，state 为状态。
# 用于边缘事件转换管理。
fn uc_edge_event_transform_row(x: i64, y: i64, name: ptr, rules: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + rules, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.845 边缘事件规则行 ============

# uc_edge_event_rule_row：绘制边缘事件规则行 [R]  rule-01  Active  5 triggers
# name 为规则名，state 为状态，triggers 为触发数。
# 用于边缘事件规则管理。
fn uc_edge_event_rule_row(x: i64, y: i64, name: ptr, state: ptr, triggers: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 12 + nlen + slen, y, '0' + triggers, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.846 边缘事件告警行 ============

# uc_edge_event_alert_row：绘制边缘事件告警行 [A]  ev-alert-01  Triggered  5 events
# name 为告警名，state 为状态，events 为事件数。
# 用于边缘事件告警管理。
fn uc_edge_event_alert_row(x: i64, y: i64, name: ptr, state: ptr, events: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'A', UC_RED, bg);
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
    uc_set(x + 12 + nlen + slen, y, '0' + events, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, 'v', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'n', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.847 边缘事件回放行 ============

# uc_edge_event_replay_row：绘制边缘事件回放行 [R]  replay-01  Playing  500 events
# name 为回放名，state 为状态，events 为事件数。
# 用于边缘事件回放管理。
fn uc_edge_event_replay_row(x: i64, y: i64, name: ptr, state: ptr, events: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + events / 100, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (events / 10) % 10, UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + events % 10, UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'v', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + slen, y, 'n', UC_MAGENTA, bg);
    uc_set(x + 20 + nlen + slen, y, 't', UC_MAGENTA, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.848 边缘事件模式检测行 ============

# uc_edge_event_pattern_row：绘制边缘事件模式检测行 [P]  pattern-01  Detected  2 matches
# name 为检测器名，state 为状态，matches 为匹配数。
# 用于边缘事件模式检测管理。
fn uc_edge_event_pattern_row(x: i64, y: i64, name: ptr, state: ptr, matches: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 12 + nlen + slen, y, '0' + matches, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'm', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'h', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.849 边缘事件审计行 ============

# uc_edge_event_audit_row：绘制边缘事件审计行 [A]  ev-audit-01  1000 logs  Retained
# name 为审计名，logs 为日志数，state 为状态。
# 用于边缘事件审计管理。
fn uc_edge_event_audit_row(x: i64, y: i64, name: ptr, logs: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + logs / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (logs / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + logs % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.850 边缘事件存档行 ============

# uc_edge_event_archive_row：绘制边缘事件存档行 [A]  archive-01  5 GB  Active
# name 为存档名，size 为大小，state 0=停用 1=启用。
# 用于边缘事件存档管理。
fn uc_edge_event_archive_row(x: i64, y: i64, name: ptr, size: i64, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
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
    uc_set(x + 9 + nlen, y, '0' + size, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'G', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'B', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    if state != 0 {
        uc_set(x + 15 + nlen, y, 'A', UC_GREEN, bg);
        uc_set(x + 16 + nlen, y, 'c', UC_GREEN, bg);
        uc_set(x + 17 + nlen, y, 't', UC_GREEN, bg);
        uc_set(x + 18 + nlen, y, 'i', UC_GREEN, bg);
        uc_set(x + 19 + nlen, y, 'v', UC_GREEN, bg);
        uc_set(x + 20 + nlen, y, 'e', UC_GREEN, bg);
    } else {
        uc_set(x + 15 + nlen, y, 'I', UC_RED, bg);
        uc_set(x + 16 + nlen, y, 'n', UC_RED, bg);
        uc_set(x + 17 + nlen, y, 'a', UC_RED, bg);
        uc_set(x + 18 + nlen, y, 'c', UC_RED, bg);
        uc_set(x + 19 + nlen, y, 't', UC_RED, bg);
        uc_set(x + 20 + nlen, y, 'i', UC_RED, bg);
        uc_set(x + 21 + nlen, y, 'v', UC_RED, bg);
        uc_set(x + 22 + nlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.851 边缘指标阈值行 ============

# uc_edge_metric_threshold_row：绘制边缘指标阈值行 [T]  temp-threshold  50°C  Active
# name 为阈值名，value 为阈值，state 0=停用 1=启用。
# 用于边缘指标阈值管理。
fn uc_edge_metric_threshold_row(x: i64, y: i64, name: ptr, value: ptr, state: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(value);
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
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, value[i], UC_WHITE, bg);
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
        uc_set(x + 12 + nlen + vlen, y, 'I', UC_RED, bg);
        uc_set(x + 13 + nlen + vlen, y, 'n', UC_RED, bg);
        uc_set(x + 14 + nlen + vlen, y, 'a', UC_RED, bg);
        uc_set(x + 15 + nlen + vlen, y, 'c', UC_RED, bg);
        uc_set(x + 16 + nlen + vlen, y, 't', UC_RED, bg);
        uc_set(x + 17 + nlen + vlen, y, 'i', UC_RED, bg);
        uc_set(x + 18 + nlen + vlen, y, 'v', UC_RED, bg);
        uc_set(x + 19 + nlen + vlen, y, 'e', UC_RED, bg);
    }
    return 0;
}

# ============ v1.852 边缘指标聚合行 ============

# uc_edge_metric_agg_row：绘制边缘指标聚合行 [A]  avg-temp  avg  10 devices
# name 为聚合名，op 为操作，devices 为设备数。
# 用于边缘指标聚合管理。
fn uc_edge_metric_agg_row(x: i64, y: i64, name: ptr, op: ptr, devices: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let olen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    olen = strlen(op);
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
    while i < olen {
        uc_set(x + 9 + nlen + i, y, op[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + olen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + olen, y, '0' + devices, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + olen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + olen, y, 'd', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + olen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + olen, y, 'v', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + olen, y, 'i', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + olen, y, 'c', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + olen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 20 + nlen + olen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.853 边缘指标预测行 ============

# uc_edge_metric_forecast_row：绘制边缘指标预测行 [F]  temp-forecast  +2°C  24h
# name 为预测名，trend 为趋势，period 为周期。
# 用于边缘指标预测管理。
fn uc_edge_metric_forecast_row(x: i64, y: i64, name: ptr, trend: ptr, period: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(trend);
    plen = strlen(period);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'F', UC_MAGENTA, bg);
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
        uc_set(x + 9 + nlen + i, y, trend[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < plen {
        uc_set(x + 12 + nlen + tlen + i, y, period[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.854 边缘指标异常检测行 ============

# uc_edge_metric_anomaly_row：绘制边缘指标异常检测行 [A]  anomaly-01  Normal  0 alerts
# name 为检测器名，state 为状态，alerts 为告警数。
# 用于边缘指标异常检测管理。
fn uc_edge_metric_anomaly_row(x: i64, y: i64, name: ptr, state: ptr, alerts: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'A', UC_RED, bg);
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

# ============ v1.855 边缘指标导出行 ============

# uc_edge_metric_export_row：绘制边缘指标导出行 [E]  prom-export  Active  10 targets
# name 为导出器名，state 为状态，targets 为目标数。
# 用于边缘指标导出管理。
fn uc_edge_metric_export_row(x: i64, y: i64, name: ptr, state: ptr, targets: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + targets, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.856 边缘日志清洗行 ============

# uc_edge_log_clean_row：绘制边缘日志清洗行 [C]  log-clean-01  1000 lines  Cleaning
# name 为清洗器名，lines 为行数，state 为状态。
# 用于边缘日志清洗管理。
fn uc_edge_log_clean_row(x: i64, y: i64, name: ptr, lines: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + lines / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (lines / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + lines % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'n', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 20 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.857 边缘日志解析行 ============

# uc_edge_log_parse_row：绘制边缘日志解析行 [P]  json-parse  3 fields  Active
# name 为解析器名，fields 为字段数，state 为状态。
# 用于边缘日志解析管理。
fn uc_edge_log_parse_row(x: i64, y: i64, name: ptr, fields: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + fields, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'f', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.858 边缘日志索引行 ============

# uc_edge_log_index_row：绘制边缘日志索引行 [I]  log-index-01  5 GB  Indexed
# name 为索引名，size 为大小，state 为状态。
# 用于边缘日志索引管理。
fn uc_edge_log_index_row(x: i64, y: i64, name: ptr, size: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'I', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + size, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'G', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'B', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 15 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.859 边缘日志搜索行 ============

# uc_edge_log_search_row：绘制边缘日志搜索行 [S]  search-01  50 queries  Active
# name 为搜索名，queries 为查询数，state 为状态。
# 用于边缘日志搜索管理。
fn uc_edge_log_search_row(x: i64, y: i64, name: ptr, queries: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    while i < nlen
    {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + queries, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'q', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 20 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.860 边缘日志留存行 ============

# uc_edge_log_retention_row：绘制边缘日志留存行 [R]  retention-01  30 days  Active
# name 为留存名，days 为天数，state 0=停用 1=启用。
# 用于边缘日志留存管理。
fn uc_edge_log_retention_row(x: i64, y: i64, name: ptr, days: i64, state: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + days / 10, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + days % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'd', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'y', UC_WHITE, bg);
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

# ============ v1.861 边缘流程编排行 ============

# uc_edge_workflow_orch_row：绘制边缘流程编排行 [O]  orch-01  Running  5 flows
# name 为编排器名，state 为状态，flows 为流程数。
# 用于边缘流程编排管理。
fn uc_edge_workflow_orch_row(x: i64, y: i64, name: ptr, state: ptr, flows: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'O', UC_CYAN, bg);
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
    uc_set(x + 12 + nlen + slen, y, '0' + flows, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, 'f', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, 'l', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + slen, y, 'o', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + slen, y, 'w', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.862 边缘流程实例行 ============

# uc_edge_workflow_instance_row：绘制边缘流程实例行 [I]  inst-001  Running  2 steps
# name 为实例名，state 为状态，steps 为步骤数。
# 用于边缘流程实例管理。
fn uc_edge_workflow_instance_row(x: i64, y: i64, name: ptr, state: ptr, steps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + steps, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 's', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.863 边缘流程定义行 ============

# uc_edge_workflow_def_row：绘制边缘流程定义行 [D]  order-flow  5 steps  Published
# name 为定义名，steps 为步骤数，state 为状态。
# 用于边缘流程定义管理。
fn uc_edge_workflow_def_row(x: i64, y: i64, name: ptr, steps: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + steps, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.864 边缘人工审批行 ============

# uc_edge_manual_approval_row：绘制边缘人工审批行 [M]  appr-001  Pending  owner
# name 为审批名，state 为状态，assignee 为审批人。
# 用于边缘人工审批管理。
fn uc_edge_manual_approval_row(x: i64, y: i64, name: ptr, state: ptr, assignee: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    alen = strlen(assignee);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
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
    i = 0;
    while i < alen {
        uc_set(x + 12 + nlen + slen + i, y, assignee[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.865 边缘自动审批行 ============

# uc_edge_auto_approval_row：绘制边缘自动审批行 [A]  auto-appr-01  Approved  100 rules
# name 为审批名，state 为状态，rules 为规则数。
# 用于边缘自动审批管理。
fn uc_edge_auto_approval_row(x: i64, y: i64, name: ptr, state: ptr, rules: i64, fg: i64, bg: i64) -> i64 {
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + rules, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'l', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.866 边缘流程通知行 ============

# uc_edge_workflow_notify_row：绘制边缘流程通知行 [N]  notify-01  5 subscribers  Active
# name 为通知名，subscribers 为订阅者数，state 为状态。
# 用于边缘流程通知管理。
fn uc_edge_workflow_notify_row(x: i64, y: i64, name: ptr, subscribers: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + subscribers, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'b', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 'b', UC_WHITE, bg);
    uc_set(x + 19 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 21 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 23 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 24 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.867 边缘流程 SLA 行 ============

# uc_edge_workflow_sla_row：绘制边缘流程 SLA 行 [S]  sla-001  24h target  Met
# name 为 SLA 名，target 为目标，state 为状态。
# 用于边缘流程 SLA 管理。
fn uc_edge_workflow_sla_row(x: i64, y: i64, name: ptr, target: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(target);
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
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, target[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + tlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.868 边缘流程审计行 ============

# uc_edge_workflow_audit_row：绘制边缘流程审计行 [A]  audit-001  500 logs  Clean
# name 为审计名，logs 为日志数，state 为状态。
# 用于边缘流程审计管理。
fn uc_edge_workflow_audit_row(x: i64, y: i64, name: ptr, logs: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + logs / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (logs / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + logs % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.869 边缘流程版本行 ============

# uc_edge_workflow_version_row：绘制边缘流程版本行 [V]  order-flow  v2  Active
# name 为流程名，version 为版本，state 0=弃用 1=活动。
# 用于边缘流程版本管理。
fn uc_edge_workflow_version_row(x: i64, y: i64, name: ptr, version: ptr, state: i64, fg: i64, bg: i64) -> i64 {
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

# ============ v1.870 边缘流程指标行 ============

# uc_edge_workflow_metric_row：绘制边缘流程指标行 [M]  order-flow  95% success  100 runs
# name 为流程名，success 为成功率，runs 为运行数。
# 用于边缘流程指标管理。
fn uc_edge_workflow_metric_row(x: i64, y: i64, name: ptr, success: i64, runs: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + success / 10, UC_GREEN, bg);
    uc_set(x + 10 + nlen, y, '0' + success % 10, UC_GREEN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 13 + nlen, y, ' ', fg, bg);
    uc_set(x + 14 + nlen, y, '0' + runs / 100, UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, '0' + (runs / 10) % 10, UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, '0' + runs % 10, UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 'u', UC_CYAN, bg);
    uc_set(x + 20 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.871 边缘应用性能行 ============

# uc_edge_app_perf_row：绘制边缘应用性能行 [A]  app-01  250ms latency  99% success
# name 为应用名，latency 为延迟，success 为成功率。
# 用于边缘应用性能管理。
fn uc_edge_app_perf_row(x: i64, y: i64, name: ptr, latency: ptr, success: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
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
    while i < llen {
        uc_set(x + 9 + nlen + i, y, latency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + llen, y, '0' + success / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + llen, y, '0' + success % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + llen, y, '%', UC_GREEN, bg);
    uc_set(x + 15 + nlen + llen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + llen, y, 's', UC_GREEN, bg);
    uc_set(x + 17 + nlen + llen, y, 'u', UC_GREEN, bg);
    uc_set(x + 18 + nlen + llen, y, 'c', UC_GREEN, bg);
    uc_set(x + 19 + nlen + llen, y, 'c', UC_GREEN, bg);
    uc_set(x + 20 + nlen + llen, y, 'e', UC_GREEN, bg);
    uc_set(x + 21 + nlen + llen, y, 's', UC_GREEN, bg);
    uc_set(x + 22 + nlen + llen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.872 边缘数据库性能行 ============

# uc_edge_db_perf_row：绘制边缘数据库性能行 [D]  db-01  5ms query  1000 qps
# name 为数据库名，latency 为延迟，qps 为查询率。
# 用于边缘数据库性能管理。
fn uc_edge_db_perf_row(x: i64, y: i64, name: ptr, latency: ptr, qps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
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
    while i < llen {
        uc_set(x + 9 + nlen + i, y, latency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + llen, y, '0' + qps / 100, UC_GREEN, bg);
    uc_set(x + 13 + nlen + llen, y, '0' + (qps / 10) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + llen, y, '0' + qps % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + llen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + llen, y, 'q', UC_GREEN, bg);
    uc_set(x + 17 + nlen + llen, y, 'p', UC_GREEN, bg);
    uc_set(x + 18 + nlen + llen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.873 边缘网络性能行 ============

# uc_edge_net_perf_row：绘制边缘网络性能行 [N]  net-01  10ms latency  1Gbps
# name 为网络名，latency 为延迟，bandwidth 为带宽。
# 用于边缘网络性能管理。
fn uc_edge_net_perf_row(x: i64, y: i64, name: ptr, latency: ptr, bandwidth: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
    blen = strlen(bandwidth);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'N', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 9 + nlen + i, y, latency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 12 + nlen + llen + i, y, bandwidth[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.874 边缘存储性能行 ============

# uc_edge_storage_perf_row：绘制边缘存储性能行 [S]  storage-01  0.5ms IO  500 IOPS
# name 为存储名，latency 为延迟，iops 为 IOPS。
# 用于边缘存储性能管理。
fn uc_edge_storage_perf_row(x: i64, y: i64, name: ptr, latency: ptr, iops: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
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
    while i < llen {
        uc_set(x + 9 + nlen + i, y, latency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + llen, y, '0' + iops / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + llen, y, '0' + (iops / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + llen, y, '0' + iops % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + llen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + llen, y, 'I', UC_CYAN, bg);
    uc_set(x + 17 + nlen + llen, y, 'O', UC_CYAN, bg);
    uc_set(x + 18 + nlen + llen, y, 'P', UC_CYAN, bg);
    uc_set(x + 19 + nlen + llen, y, 'S', UC_CYAN, bg);
    return 0;
}

# ============ v1.875 边缘用户体验行 ============

# uc_edge_user_exp_row：绘制边缘用户体验行 [U]  ux-01  4.5 score  92% satis
# name 为体验名，score 为评分，satisfaction 为满意度。
# 用于边缘用户体验管理。
fn uc_edge_user_exp_row(x: i64, y: i64, name: ptr, score: ptr, satisfaction: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(score);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'U', UC_YELLOW, bg);
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
        uc_set(x + 9 + nlen + i, y, score[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + satisfaction / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + satisfaction % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, '%', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 's', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_GREEN, bg);
    uc_set(x + 19 + nlen + slen, y, 'i', UC_GREEN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.876 边缘资源利用率行 ============

# uc_edge_resource_util_row：绘制边缘资源利用率行 [R]  node-01  75% CPU  60% MEM
# name 为节点名，cpu 为 CPU 使用率，mem 为内存使用率。
# 用于边缘资源利用率管理。
fn uc_edge_resource_util_row(x: i64, y: i64, name: ptr, cpu: i64, mem: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + cpu / 10, UC_MAGENTA, bg);
    uc_set(x + 10 + nlen, y, '0' + cpu % 10, UC_MAGENTA, bg);
    uc_set(x + 11 + nlen, y, '%', UC_MAGENTA, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 13 + nlen, y, 'C', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen, y, 'P', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen, y, 'U', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    uc_set(x + 18 + nlen, y, '0' + mem / 10, UC_GREEN, bg);
    uc_set(x + 19 + nlen, y, '0' + mem % 10, UC_GREEN, bg);
    uc_set(x + 20 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 21 + nlen, y, ' ', UC_GREEN, bg);
    uc_set(x + 22 + nlen, y, 'M', UC_GREEN, bg);
    uc_set(x + 23 + nlen, y, 'E', UC_GREEN, bg);
    uc_set(x + 24 + nlen, y, 'M', UC_GREEN, bg);
    return 0;
}

# ============ v1.877 边缘容量规划行 ============

# uc_edge_capacity_plan_row：绘制边缘容量规划行 [P]  plan-01  80% used  20% headroom
# name 为规划名，used 为使用率，headroom 为余量。
# 用于边缘容量规划管理。
fn uc_edge_capacity_plan_row(x: i64, y: i64, name: ptr, used: i64, headroom: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + used / 10, UC_MAGENTA, bg);
    uc_set(x + 10 + nlen, y, '0' + used % 10, UC_MAGENTA, bg);
    uc_set(x + 11 + nlen, y, '%', UC_MAGENTA, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 13 + nlen, y, 'u', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen, y, 's', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen, y, 'd', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    uc_set(x + 19 + nlen, y, '0' + headroom / 10, UC_GREEN, bg);
    uc_set(x + 20 + nlen, y, '0' + headroom % 10, UC_GREEN, bg);
    uc_set(x + 21 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 22 + nlen, y, ' ', UC_GREEN, bg);
    uc_set(x + 23 + nlen, y, 'h', UC_GREEN, bg);
    uc_set(x + 24 + nlen, y, 'e', UC_GREEN, bg);
    uc_set(x + 25 + nlen, y, 'a', UC_GREEN, bg);
    uc_set(x + 26 + nlen, y, 'd', UC_GREEN, bg);
    uc_set(x + 27 + nlen, y, 'r', UC_GREEN, bg);
    uc_set(x + 28 + nlen, y, 'o', UC_GREEN, bg);
    uc_set(x + 29 + nlen, y, 'o', UC_GREEN, bg);
    uc_set(x + 30 + nlen, y, 'm', UC_GREEN, bg);
    return 0;
}

# ============ v1.878 边缘成本分析行 ============

# uc_edge_cost_analysis_row：绘制边缘成本分析行 [C]  cost-01  120 USD  5 services
# name 为分析名，cost 为成本，services 为服务数。
# 用于边缘成本分析管理。
fn uc_edge_cost_analysis_row(x: i64, y: i64, name: ptr, cost: ptr, services: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(cost);
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
    while i < clen {
        uc_set(x + 9 + nlen + i, y, cost[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + clen, y, '0' + services, UC_CYAN, bg);
    uc_set(x + 13 + nlen + clen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + clen, y, 's', UC_CYAN, bg);
    uc_set(x + 15 + nlen + clen, y, 'e', UC_CYAN, bg);
    uc_set(x + 16 + nlen + clen, y, 'r', UC_CYAN, bg);
    uc_set(x + 17 + nlen + clen, y, 'v', UC_CYAN, bg);
    uc_set(x + 18 + nlen + clen, y, 'i', UC_CYAN, bg);
    uc_set(x + 19 + nlen + clen, y, 'c', UC_CYAN, bg);
    uc_set(x + 20 + nlen + clen, y, 'e', UC_CYAN, bg);
    uc_set(x + 21 + nlen + clen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.879 边缘性能基准对比行 ============

# uc_edge_perf_compare_row：绘制边缘性能基准对比行 [C]  bench-a  +15%  vs bench-b
# name 为基准名，delta 为差异，baseline 为基线。
# 用于边缘性能基准对比管理。
fn uc_edge_perf_compare_row(x: i64, y: i64, name: ptr, delta: ptr, baseline: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let dlen: i64 = 0;
    let blen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    dlen = strlen(delta);
    blen = strlen(baseline);
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
    while i < dlen {
        uc_set(x + 9 + nlen + i, y, delta[i], UC_GREEN, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + dlen, y, ' ', fg, bg);
    i = 0;
    while i < blen {
        uc_set(x + 12 + nlen + dlen + i, y, baseline[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.880 边缘性能调优建议行 ============

# uc_edge_perf_tuning_row：绘制边缘性能调优建议行 [T]  tune-01  Reduce IO  3 actions
# name 为建议名，area 为领域，actions 为动作数。
# 用于边缘性能调优建议管理。
fn uc_edge_perf_tuning_row(x: i64, y: i64, name: ptr, area: ptr, actions: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let alen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    alen = strlen(area);
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
    while i < alen {
        uc_set(x + 9 + nlen + i, y, area[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + alen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + alen, y, '0' + actions, UC_CYAN, bg);
    uc_set(x + 13 + nlen + alen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + alen, y, 'a', UC_CYAN, bg);
    uc_set(x + 15 + nlen + alen, y, 'c', UC_CYAN, bg);
    uc_set(x + 16 + nlen + alen, y, 't', UC_CYAN, bg);
    uc_set(x + 17 + nlen + alen, y, 'i', UC_CYAN, bg);
    uc_set(x + 18 + nlen + alen, y, 'o', UC_CYAN, bg);
    uc_set(x + 19 + nlen + alen, y, 'n', UC_CYAN, bg);
    uc_set(x + 20 + nlen + alen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.881 边缘机器学习训练行 ============

# uc_edge_ml_train_row：绘制边缘机器学习训练行 [T]  train-yolo  85% acc  Running
# name 为训练名，accuracy 为准确率，state 为状态。
# 用于边缘机器学习训练管理。
fn uc_edge_ml_train_row(x: i64, y: i64, name: ptr, accuracy: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + accuracy / 10, UC_GREEN, bg);
    uc_set(x + 10 + nlen, y, '0' + accuracy % 10, UC_GREEN, bg);
    uc_set(x + 11 + nlen, y, '%', UC_GREEN, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_GREEN, bg);
    uc_set(x + 13 + nlen, y, 'a', UC_GREEN, bg);
    uc_set(x + 14 + nlen, y, 'c', UC_GREEN, bg);
    uc_set(x + 15 + nlen, y, 'c', UC_GREEN, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.882 边缘模型推理行 ============

# uc_edge_model_infer_row：绘制边缘模型推理行 [I]  infer-yolo  20ms infer  500 fps
# name 为推理名，latency 为延迟，fps 为帧率。
# 用于边缘模型推理管理。
fn uc_edge_model_infer_row(x: i64, y: i64, name: ptr, latency: ptr, fps: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    llen = strlen(latency);
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
    while i < llen {
        uc_set(x + 9 + nlen + i, y, latency[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + llen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + llen, y, '0' + fps / 100, UC_GREEN, bg);
    uc_set(x + 13 + nlen + llen, y, '0' + (fps / 10) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + llen, y, '0' + fps % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + llen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + llen, y, 'f', UC_GREEN, bg);
    uc_set(x + 17 + nlen + llen, y, 'p', UC_GREEN, bg);
    uc_set(x + 18 + nlen + llen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.883 边缘模型优化行 ============

# uc_edge_model_opt_row：绘制边缘模型优化行 [O]  opt-yolo  INT8  40% smaller
# name 为优化名，precision 为精度，size 为大小。
# 用于边缘模型优化管理。
fn uc_edge_model_opt_row(x: i64, y: i64, name: ptr, precision: ptr, size: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let sizlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(precision);
    sizlen = strlen(size);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'O', UC_GREEN, bg);
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
        uc_set(x + 9 + nlen + i, y, precision[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    i = 0;
    while i < sizlen {
        uc_set(x + 12 + nlen + plen + i, y, size[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.884 边缘模型转换行 ============

# uc_edge_model_convert_row：绘制边缘模型转换行 [C]  convert-01  ONNX→TFLite  Done
# name 为转换名，format 为格式，state 为状态。
# 用于边缘模型转换管理。
fn uc_edge_model_convert_row(x: i64, y: i64, name: ptr, format: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let flen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    flen = strlen(format);
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
    while i < flen {
        uc_set(x + 9 + nlen + i, y, format[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + flen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + flen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.885 边缘模型部署行 ============

# uc_edge_model_deploy_row：绘制边缘模型部署行 [D]  deploy-yolo  Deployed  10 devices
# name 为部署名，state 为状态，devices 为设备数。
# 用于边缘模型部署管理。
fn uc_edge_model_deploy_row(x: i64, y: i64, name: ptr, state: ptr, devices: i64, fg: i64, bg: i64) -> i64 {
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + devices, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'v', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'c', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.886 边缘模型监控行 ============

# uc_edge_model_monitor_row：绘制边缘模型监控行 [M]  monitor-yolo  Healthy  99% up
# name 为监控名，state 为状态，uptime 为可用率。
# 用于边缘模型监控管理。
fn uc_edge_model_monitor_row2(x: i64, y: i64, name: ptr, state: ptr, uptime: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'M', UC_GREEN, bg);
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
    uc_set(x + 12 + nlen + slen, y, '0' + uptime / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + uptime % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, '%', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_CYAN, bg);
    return 0;
}

# ============ v1.887 边缘模型漂移检测行 ============

# uc_edge_model_drift_row：绘制边缘模型漂移检测行 [D]  drift-yolo  Detected  0.05
# name 为检测名，state 为状态，score 为分数。
# 用于边缘模型漂移检测管理。
fn uc_edge_model_drift_row(x: i64, y: i64, name: ptr, state: ptr, score: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0', UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + slen, y, '.', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + slen, y, '0', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + slen, y, '0' + score, UC_MAGENTA, bg);
    return 0;
}

# ============ v1.888 边缘模型版本管理行 ============

# uc_edge_model_version_row：绘制边缘模型版本管理行 [V]  yolo  v3.1  5 versions
# name 为模型名，version 为版本，versions 为版本数。
# 用于边缘模型版本管理。
fn uc_edge_model_version_row2(x: i64, y: i64, name: ptr, version: ptr, versions: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    uc_set(x, y, '[', UC_CYAN, bg);
    uc_set(x + 1, y, 'V', UC_CYAN, bg);
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
    uc_set(x + 12 + nlen + vlen, y, '0' + versions, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + vlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + vlen, y, 'v', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + vlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + vlen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + vlen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.889 边缘模型回滚行 ============

# uc_edge_model_rollback_row：绘制边缘模型回滚行 [R]  rollback-01  v3.0  Completed
# name 为回滚名，version 为版本，state 为状态。
# 用于边缘模型回滚管理。
fn uc_edge_model_rollback_row(x: i64, y: i64, name: ptr, version: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
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
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + vlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.890 边缘模型 A/B 测试行 ============

# uc_edge_model_abtest_row：绘制边缘模型 A/B 测试行 [A]  ab-yolo  A wins  60% traffic
# name 为测试名，winner 为获胜方，traffic 为流量。
# 用于边缘模型 A/B 测试管理。
fn uc_edge_model_abtest_row(x: i64, y: i64, name: ptr, winner: ptr, traffic: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let wlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    wlen = strlen(winner);
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
    while i < wlen {
        uc_set(x + 9 + nlen + i, y, winner[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + wlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + wlen, y, '0' + traffic / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + wlen, y, '0' + traffic % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + wlen, y, '%', UC_CYAN, bg);
    uc_set(x + 15 + nlen + wlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + wlen, y, 't', UC_CYAN, bg);
    uc_set(x + 17 + nlen + wlen, y, 'r', UC_CYAN, bg);
    uc_set(x + 18 + nlen + wlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 19 + nlen + wlen, y, 'f', UC_CYAN, bg);
    uc_set(x + 20 + nlen + wlen, y, 'f', UC_CYAN, bg);
    uc_set(x + 21 + nlen + wlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 22 + nlen + wlen, y, 'c', UC_CYAN, bg);
    return 0;
}

# ============ v1.891 边缘数据湖行 ============

# uc_edge_data_lake_row：绘制边缘数据湖行 [L]  lake-01  500GB  Raw  10 datasets
# name 为数据湖名，size 为大小，format 为格式，datasets 为数据集数。
# 用于边缘数据湖管理。
fn uc_edge_data_lake_row(x: i64, y: i64, name: ptr, size: ptr, format: ptr, datasets: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let sizlen: i64 = 0;
    let flen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    sizlen = strlen(size);
    flen = strlen(format);
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
    while i < sizlen {
        uc_set(x + 9 + nlen + i, y, size[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + sizlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 12 + nlen + sizlen + i, y, format[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + sizlen + flen, y, ' ', fg, bg);
    uc_set(x + 15 + nlen + sizlen + flen, y, '0' + datasets, UC_CYAN, bg);
    uc_set(x + 16 + nlen + sizlen + flen, y, ' ', UC_CYAN, bg);
    uc_set(x + 17 + nlen + sizlen + flen, y, 'd', UC_CYAN, bg);
    uc_set(x + 18 + nlen + sizlen + flen, y, 'a', UC_CYAN, bg);
    uc_set(x + 19 + nlen + sizlen + flen, y, 't', UC_CYAN, bg);
    uc_set(x + 20 + nlen + sizlen + flen, y, 'a', UC_CYAN, bg);
    uc_set(x + 21 + nlen + sizlen + flen, y, 's', UC_CYAN, bg);
    uc_set(x + 22 + nlen + sizlen + flen, y, 'e', UC_CYAN, bg);
    uc_set(x + 23 + nlen + sizlen + flen, y, 't', UC_CYAN, bg);
    uc_set(x + 24 + nlen + sizlen + flen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.892 边缘数据仓库行 ============

# uc_edge_data_warehouse_row：绘制边缘数据仓库行 [W]  wh-01  100GB  Clean  50 tables
# name 为仓库名，size 为大小，state 为状态，tables 为表数。
# 用于边缘数据仓库管理。
fn uc_edge_data_warehouse_row(x: i64, y: i64, name: ptr, size: ptr, state: ptr, tables: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let sizlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    sizlen = strlen(size);
    slen = strlen(state);
    uc_set(x, y, '[', UC_MAGENTA, bg);
    uc_set(x + 1, y, 'W', UC_MAGENTA, bg);
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
        uc_set(x + 12 + nlen + sizlen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + sizlen + slen, y, ' ', fg, bg);
    uc_set(x + 15 + nlen + sizlen + slen, y, '0' + tables, UC_GREEN, bg);
    uc_set(x + 16 + nlen + sizlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 17 + nlen + sizlen + slen, y, 't', UC_GREEN, bg);
    uc_set(x + 18 + nlen + sizlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 19 + nlen + sizlen + slen, y, 'b', UC_GREEN, bg);
    uc_set(x + 20 + nlen + sizlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 21 + nlen + sizlen + slen, y, 'e', UC_GREEN, bg);
    uc_set(x + 22 + nlen + sizlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.893 边缘数据血缘行 ============

# uc_edge_data_lineage_row：绘制边缘数据血缘行 [G]  lineage-01  5 hops  3 sources
# name 为血缘名，hops 为跳数，sources 为源数。
# 用于边缘数据血缘管理。
fn uc_edge_data_lineage_row(x: i64, y: i64, name: ptr, hops: i64, sources: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + hops, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'h', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'o', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 'p', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, ' ', fg, bg);
    uc_set(x + 17 + nlen, y, '0' + sources, UC_MAGENTA, bg);
    uc_set(x + 18 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen, y, 's', UC_MAGENTA, bg);
    uc_set(x + 20 + nlen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 21 + nlen, y, 'c', UC_MAGENTA, bg);
    uc_set(x + 22 + nlen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.894 边缘数据掩码行 ============

# uc_edge_data_mask_row：绘制边缘数据掩码行 [M]  mask-01  SSN  100 fields  Active
# name 为掩码名，field 为字段，count 为数量，state 为状态。
# 用于边缘数据掩码管理。
fn uc_edge_data_mask_row(x: i64, y: i64, name: ptr, field: ptr, count: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let flen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    flen = strlen(field);
    slen = strlen(state);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'M', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < flen {
        uc_set(x + 9 + nlen + i, y, field[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + flen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + flen, y, '0' + count / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + flen, y, '0' + (count / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + flen, y, '0' + count % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + flen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + flen, y, 'f', UC_CYAN, bg);
    uc_set(x + 17 + nlen + flen, y, 'i', UC_CYAN, bg);
    uc_set(x + 18 + nlen + flen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen + flen, y, 'l', UC_CYAN, bg);
    uc_set(x + 20 + nlen + flen, y, 'd', UC_CYAN, bg);
    uc_set(x + 21 + nlen + flen, y, 's', UC_CYAN, bg);
    uc_set(x + 23 + nlen + flen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 24 + nlen + flen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.895 边缘数据访问策略行 ============

# uc_edge_data_policy_row：绘制边缘数据访问策略行 [P]  policy-01  10 rules  Enforced
# name 为策略名，rules 为规则数，state 为状态。
# 用于边缘数据访问策略管理。
fn uc_edge_data_policy_row(x: i64, y: i64, name: ptr, rules: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    uc_set(x + 9 + nlen, y, '0' + rules, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 'r', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'u', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 18 + nlen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.896 边缘数据质量评分行 ============

# uc_edge_data_quality_row：绘制边缘数据质量评分行 [Q]  ds-01  95 score  Good
# name 为数据集名，score 为评分，state 为状态。
# 用于边缘数据质量评分管理。
fn uc_edge_data_quality_row(x: i64, y: i64, name: ptr, score: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'Q', UC_GREEN, bg);
    uc_set(x + 2, y, ']', UC_GREEN, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + score / 10, UC_MAGENTA, bg);
    uc_set(x + 10 + nlen, y, '0' + score % 10, UC_MAGENTA, bg);
    uc_set(x + 11 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 12 + nlen, y, 's', UC_MAGENTA, bg);
    uc_set(x + 13 + nlen, y, 'c', UC_MAGENTA, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen, y, 'r', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.897 边缘数据校验规则行 ============

# uc_edge_data_validate_row：绘制边缘数据校验规则行 [V]  rule-01  NOT_NULL  100 pass
# name 为规则名，rule 为规则类型，pass 为通过数。
# 用于边缘数据校验规则管理。
fn uc_edge_data_validate_row(x: i64, y: i64, name: ptr, rule: ptr, pass: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(rule);
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
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, rule[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + rlen, y, '0' + pass / 100, UC_GREEN, bg);
    uc_set(x + 13 + nlen + rlen, y, '0' + (pass / 10) % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + rlen, y, '0' + pass % 10, UC_GREEN, bg);
    uc_set(x + 15 + nlen + rlen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + rlen, y, 'p', UC_GREEN, bg);
    uc_set(x + 17 + nlen + rlen, y, 'a', UC_GREEN, bg);
    uc_set(x + 18 + nlen + rlen, y, 's', UC_GREEN, bg);
    uc_set(x + 19 + nlen + rlen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.898 边缘数据目录行 ============

# uc_edge_data_catalog_row：绘制边缘数据目录行 [C]  catalog-01  20 tables  Indexed
# name 为目录名，tables 为表数，state 为状态。
# 用于边缘数据目录管理。
fn uc_edge_data_catalog_row(x: i64, y: i64, name: ptr, tables: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + tables, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, 'a', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'b', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'e', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.899 边缘数据订阅行 ============

# uc_edge_data_subscription_row：绘制边缘数据订阅行 [S]  sub-01  100 topics  Active
# name 为订阅名，topics 为主题数，state 为状态。
# 用于边缘数据订阅管理。
fn uc_edge_data_subscription_row(x: i64, y: i64, name: ptr, topics: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + topics / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (topics / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + topics % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 't', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'p', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 'i', UC_WHITE, bg);
    uc_set(x + 17 + nlen, y, 'c', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 21 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.900 边缘数据导出任务行 ============

# uc_edge_data_export_row：绘制边缘数据导出任务行 [E]  export-01  S3  500MB  Done
# name 为任务名，target 为目标，size 为大小，state 为状态。
# 用于边缘数据导出任务管理。
fn uc_edge_data_export_row(x: i64, y: i64, name: ptr, target: ptr, size: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let tlen: i64 = 0;
    let sizlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    tlen = strlen(target);
    sizlen = strlen(size);
    slen = strlen(state);
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
    while i < tlen {
        uc_set(x + 9 + nlen + i, y, target[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + tlen, y, ' ', fg, bg);
    i = 0;
    while i < sizlen {
        uc_set(x + 12 + nlen + tlen + i, y, size[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + tlen + sizlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 15 + nlen + tlen + sizlen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.901 边缘证书行 ============

# uc_edge_certificate_row：绘制边缘证书行 [C]  cert-01  Valid  30d expiry
# name 为证书名，state 为状态，days 为剩余天数。
# 用于边缘证书管理。
fn uc_edge_certificate_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + days / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + days % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'x', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'p', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 'i', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, 'y', UC_CYAN, bg);
    return 0;
}

# ============ v1.902 边缘密钥行 ============

# uc_edge_secret_row：绘制边缘密钥行 [S]  secret-01  Rotated  10d ago
# name 为密钥名，state 为状态，days 为天数。
# 用于边缘密钥管理。
fn uc_edge_secret_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 12 + nlen + slen, y, '0' + days / 10, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + days % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'a', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'g', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'o', UC_CYAN, bg);
    return 0;
}

# ============ v1.903 边缘访问令牌行 ============

# uc_edge_token_row：绘制边缘访问令牌行 [T]  token-01  Active  15d left
# name 为令牌名，state 为状态，days 为剩余天数。
# 用于边缘访问令牌管理。
fn uc_edge_token_row(x: i64, y: i64, name: ptr, state: ptr, days: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + days / 10, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + days % 10, UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, 'd', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'e', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 'f', UC_GREEN, bg);
    uc_set(x + 19 + nlen + slen, y, 't', UC_GREEN, bg);
    return 0;
}

# ============ v1.904 边缘身份提供商行 ============

# uc_edge_identity_provider_row：绘制边缘身份提供商行 [I]  idp-01  AzureAD  Active
# name 为提供商名，provider 为提供商类型，state 为状态。
# 用于边缘身份提供商管理。
fn uc_edge_identity_provider_row(x: i64, y: i64, name: ptr, provider: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(provider);
    slen = strlen(state);
    uc_set(x, y, '[', UC_GREEN, bg);
    uc_set(x + 1, y, 'I', UC_GREEN, bg);
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
        uc_set(x + 9 + nlen + i, y, provider[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + plen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.905 边缘角色绑定行 ============

# uc_edge_role_binding_row：绘制边缘角色绑定行 [B]  bind-01  admin  user-01  Active
# name 为绑定名，role 为角色，subject 为主体，state 为状态。
# 用于边缘角色绑定管理。
fn uc_edge_role_binding_row(x: i64, y: i64, name: ptr, role: ptr, subject: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let slen: i64 = 0;
    let stlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(role);
    slen = strlen(subject);
    stlen = strlen(state);
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
    i = 0;
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, role[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + rlen + i, y, subject[i], UC_CYAN, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + rlen + slen, y, ' ', fg, bg);
    i = 0;
    while i < stlen {
        uc_set(x + 15 + nlen + rlen + slen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.906 边缘安全审计日志行 ============

# uc_edge_audit_log_row：绘制边缘安全审计日志行 [A]  audit-01  500 logs  Clean
# name 为日志名，count 为数量，state 为状态。
# 用于边缘安全审计日志管理。
fn uc_edge_security_audit_row(x: i64, y: i64, name: ptr, count: i64, state: ptr, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + count / 100, UC_WHITE, bg);
    uc_set(x + 10 + nlen, y, '0' + (count / 10) % 10, UC_WHITE, bg);
    uc_set(x + 11 + nlen, y, '0' + count % 10, UC_WHITE, bg);
    uc_set(x + 12 + nlen, y, ' ', UC_WHITE, bg);
    uc_set(x + 13 + nlen, y, 'l', UC_WHITE, bg);
    uc_set(x + 14 + nlen, y, 'o', UC_WHITE, bg);
    uc_set(x + 15 + nlen, y, 'g', UC_WHITE, bg);
    uc_set(x + 16 + nlen, y, 's', UC_WHITE, bg);
    uc_set(x + 18 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 19 + nlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.907 边缘入侵检测行 ============

# uc_edge_intrusion_detect_row：绘制边缘入侵检测行 [I]  ids-01  Normal  0 alerts
# name 为检测名，state 为状态，alerts 为告警数。
# 用于边缘入侵检测管理。
fn uc_edge_intrusion_detect_row(x: i64, y: i64, name: ptr, state: ptr, alerts: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + alerts, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'e', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'r', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_GREEN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.908 边缘漏洞扫描行 ============

# uc_edge_vulnerability_row：绘制边缘漏洞扫描行 [V]  vuln-01  5 critical  20 open
# name 为扫描名，critical 为严重数，open 为开放数。
# 用于边缘漏洞扫描管理。
fn uc_edge_vuln_scan_row(x: i64, y: i64, name: ptr, critical: i64, open: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    uc_set(x, y, '[', UC_YELLOW, bg);
    uc_set(x + 1, y, 'V', UC_YELLOW, bg);
    uc_set(x + 2, y, ']', UC_YELLOW, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    uc_set(x + 9 + nlen, y, '0' + critical, UC_RED, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_RED, bg);
    uc_set(x + 11 + nlen, y, 'c', UC_RED, bg);
    uc_set(x + 12 + nlen, y, 'r', UC_RED, bg);
    uc_set(x + 13 + nlen, y, 'i', UC_RED, bg);
    uc_set(x + 14 + nlen, y, 't', UC_RED, bg);
    uc_set(x + 15 + nlen, y, 'i', UC_RED, bg);
    uc_set(x + 16 + nlen, y, 'c', UC_RED, bg);
    uc_set(x + 17 + nlen, y, 'a', UC_RED, bg);
    uc_set(x + 18 + nlen, y, 'l', UC_RED, bg);
    uc_set(x + 20 + nlen, y, ' ', fg, bg);
    uc_set(x + 21 + nlen, y, '0' + open / 10, UC_MAGENTA, bg);
    uc_set(x + 22 + nlen, y, '0' + open % 10, UC_MAGENTA, bg);
    uc_set(x + 23 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 24 + nlen, y, 'o', UC_MAGENTA, bg);
    uc_set(x + 25 + nlen, y, 'p', UC_MAGENTA, bg);
    uc_set(x + 26 + nlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 27 + nlen, y, 'n', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.909 边缘安全补丁行 ============

# uc_edge_patch_row：绘制边缘安全补丁行 [P]  patch-01  10 installed  2 pending
# name 为补丁名，installed 为已装数，pending 为待装数。
# 用于边缘安全补丁管理。
fn uc_edge_patch_manage_row(x: i64, y: i64, name: ptr, installed: i64, pending: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 9 + nlen, y, '0' + installed, UC_CYAN, bg);
    uc_set(x + 10 + nlen, y, ' ', UC_CYAN, bg);
    uc_set(x + 11 + nlen, y, 'i', UC_CYAN, bg);
    uc_set(x + 12 + nlen, y, 'n', UC_CYAN, bg);
    uc_set(x + 13 + nlen, y, 's', UC_CYAN, bg);
    uc_set(x + 14 + nlen, y, 't', UC_CYAN, bg);
    uc_set(x + 15 + nlen, y, 'a', UC_CYAN, bg);
    uc_set(x + 16 + nlen, y, 'l', UC_CYAN, bg);
    uc_set(x + 17 + nlen, y, 'l', UC_CYAN, bg);
    uc_set(x + 18 + nlen, y, 'e', UC_CYAN, bg);
    uc_set(x + 19 + nlen, y, 'd', UC_CYAN, bg);
    uc_set(x + 21 + nlen, y, ' ', fg, bg);
    uc_set(x + 22 + nlen, y, '0' + pending, UC_MAGENTA, bg);
    uc_set(x + 23 + nlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 24 + nlen, y, 'p', UC_MAGENTA, bg);
    uc_set(x + 25 + nlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 26 + nlen, y, 'n', UC_MAGENTA, bg);
    uc_set(x + 27 + nlen, y, 'd', UC_MAGENTA, bg);
    uc_set(x + 28 + nlen, y, 'i', UC_MAGENTA, bg);
    uc_set(x + 29 + nlen, y, 'n', UC_MAGENTA, bg);
    uc_set(x + 30 + nlen, y, 'g', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.910 边缘合规检查行 ============

# uc_edge_compliance_row：绘制边缘合规检查行 [C]  gdpr-01  Compliant  100%
# name 为检查名，standard 为标准，state 为状态，percent 为合规率。
# 用于边缘合规检查管理。
fn uc_edge_compliance_row(x: i64, y: i64, name: ptr, standard: ptr, state: ptr, percent: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let stlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    stlen = strlen(standard);
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
    while i < stlen {
        uc_set(x + 9 + nlen + i, y, standard[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + stlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + stlen + i, y, state[i], UC_MAGENTA, bg);
        i = i + 1;
    }
    uc_set(x + 14 + nlen + stlen + slen, y, ' ', fg, bg);
    uc_set(x + 15 + nlen + stlen + slen, y, '0' + percent / 10, UC_GREEN, bg);
    uc_set(x + 16 + nlen + stlen + slen, y, '0' + percent % 10, UC_GREEN, bg);
    uc_set(x + 17 + nlen + stlen + slen, y, '%', UC_GREEN, bg);
    return 0;
}

# ============ v1.911 边缘 API 端点行 ============

# uc_edge_api_endpoint_row：绘制边缘 API 端点行 [E]  /v1/status  GET  Active
# name 为端点名，method 为方法，state 为状态。
# 用于边缘 API 端点管理。
fn uc_edge_api_endpoint_row(x: i64, y: i64, name: ptr, method: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let mlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    mlen = strlen(method);
    slen = strlen(state);
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
    i = 0;
    while i < mlen {
        uc_set(x + 9 + nlen + i, y, method[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + mlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + mlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.912 边缘 API 请求行 ============

# uc_edge_api_request_row：绘制边缘 API 请求行 [R]  req-01  200 OK  5ms
# name 为请求名，code 为状态码，latency 为延迟。
# 用于边缘 API 请求管理。
fn uc_edge_api_request_row(x: i64, y: i64, name: ptr, code: ptr, latency: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let llen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(code);
    llen = strlen(latency);
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
    while i < clen {
        uc_set(x + 9 + nlen + i, y, code[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    i = 0;
    while i < llen {
        uc_set(x + 12 + nlen + clen + i, y, latency[i], UC_CYAN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.913 边缘 API 错误行 ============

# uc_edge_api_error_row：绘制边缘 API 错误行 [X]  err-001  500 Internal  10 times
# name 为错误名，code 为错误码，count 为次数。
# 用于边缘 API 错误管理。
fn uc_edge_api_error_row(x: i64, y: i64, name: ptr, code: ptr, count: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let clen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    clen = strlen(code);
    uc_set(x, y, '[', UC_RED, bg);
    uc_set(x + 1, y, 'X', UC_RED, bg);
    uc_set(x + 2, y, ']', UC_RED, bg);
    uc_set(x + 5, y, ' ', fg, bg);
    i = 0;
    while i < nlen {
        uc_set(x + 6 + i, y, name[i], UC_YELLOW, bg);
        i = i + 1;
    }
    uc_set(x + 8 + nlen, y, ' ', fg, bg);
    i = 0;
    while i < clen {
        uc_set(x + 9 + nlen + i, y, code[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + clen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + clen, y, '0' + count / 10, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + clen, y, '0' + count % 10, UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + clen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + clen, y, 't', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + clen, y, 'i', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + clen, y, 'm', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + clen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + clen, y, 's', UC_MAGENTA, bg);
    return 0;
}

# ============ v1.914 边缘 API 版本行 ============

# uc_edge_api_version_row：绘制边缘 API 版本行 [V]  v1.0  Stable  5 endpoints
# name 为版本名，state 为状态，endpoints 为端点数。
# 用于边缘 API 版本管理。
fn uc_edge_api_ver_row(x: i64, y: i64, name: ptr, state: ptr, endpoints: i64, fg: i64, bg: i64) -> i64 {
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
    uc_set(x + 12 + nlen + slen, y, '0' + endpoints, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, 'n', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'd', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'p', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.915 边缘 API 密钥行 ============

# ============ v1.916 边缘 API 限流行 ============

# uc_edge_api_rate_limit_row：绘制边缘 API 限流行 [L]  limit-01  100 req/s  Active
# name 为限流名，rate 为速率，state 为状态。
# 用于边缘 API 限流管理。
fn uc_edge_api_rate_limit_row(x: i64, y: i64, name: ptr, rate: ptr, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let rlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    rlen = strlen(rate);
    slen = strlen(state);
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
    while i < rlen {
        uc_set(x + 9 + nlen + i, y, rate[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + rlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 12 + nlen + rlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}

# ============ v1.917 边缘 API 熔断行 ============

# uc_edge_api_breaker_row：绘制边缘 API 熔断行 [B]  breaker-01  Closed  0 fails
# name 为熔断器名，state 为状态，fails 为失败数。
# 用于边缘 API 熔断管理。
fn uc_edge_api_breaker_row(x: i64, y: i64, name: ptr, state: ptr, fails: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    i = 0;
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + fails, UC_GREEN, bg);
    uc_set(x + 13 + nlen + slen, y, ' ', UC_GREEN, bg);
    uc_set(x + 14 + nlen + slen, y, 'f', UC_GREEN, bg);
    uc_set(x + 15 + nlen + slen, y, 'a', UC_GREEN, bg);
    uc_set(x + 16 + nlen + slen, y, 'i', UC_GREEN, bg);
    uc_set(x + 17 + nlen + slen, y, 'l', UC_GREEN, bg);
    uc_set(x + 18 + nlen + slen, y, 's', UC_GREEN, bg);
    return 0;
}

# ============ v1.918 边缘 API 网关行 ============

# uc_edge_api_gateway_row：绘制边缘 API 网关行 [G]  gateway-01  Healthy  500 routes
# name 为网关名，state 为状态，routes 为路由数。
# 用于边缘 API 网关管理。
fn uc_edge_api_gateway_row2(x: i64, y: i64, name: ptr, state: ptr, routes: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    slen = strlen(state);
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
    while i < slen {
        uc_set(x + 9 + nlen + i, y, state[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + slen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + slen, y, '0' + routes / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + slen, y, '0' + (routes / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + slen, y, '0' + routes % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + slen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + slen, y, 'r', UC_CYAN, bg);
    uc_set(x + 17 + nlen + slen, y, 'o', UC_CYAN, bg);
    uc_set(x + 18 + nlen + slen, y, 'u', UC_CYAN, bg);
    uc_set(x + 19 + nlen + slen, y, 't', UC_CYAN, bg);
    uc_set(x + 20 + nlen + slen, y, 'e', UC_CYAN, bg);
    uc_set(x + 21 + nlen + slen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.919 边缘 API 订阅行 ============

# uc_edge_api_subscription_row：绘制边缘 API 订阅行 [S]  sub-01  Basic  100 calls
# name 为订阅名，plan 为套餐，calls 为调用数。
# 用于边缘 API 订阅管理。
fn uc_edge_api_subscription_row(x: i64, y: i64, name: ptr, plan: ptr, calls: i64, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let plen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    plen = strlen(plan);
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
    while i < plen {
        uc_set(x + 9 + nlen + i, y, plan[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + plen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + plen, y, '0' + calls / 100, UC_CYAN, bg);
    uc_set(x + 13 + nlen + plen, y, '0' + (calls / 10) % 10, UC_CYAN, bg);
    uc_set(x + 14 + nlen + plen, y, '0' + calls % 10, UC_CYAN, bg);
    uc_set(x + 15 + nlen + plen, y, ' ', UC_CYAN, bg);
    uc_set(x + 16 + nlen + plen, y, 'c', UC_CYAN, bg);
    uc_set(x + 17 + nlen + plen, y, 'a', UC_CYAN, bg);
    uc_set(x + 18 + nlen + plen, y, 'l', UC_CYAN, bg);
    uc_set(x + 19 + nlen + plen, y, 'l', UC_CYAN, bg);
    uc_set(x + 20 + nlen + plen, y, 's', UC_CYAN, bg);
    return 0;
}

# ============ v1.920 边缘 API 文档行 ============

# uc_edge_api_doc_row：绘制边缘 API 文档行 [D]  api-doc  v2  100 pages  Published
# name 为文档名，version 为版本，pages 为页数，state 为状态。
# 用于边缘 API 文档管理。
fn uc_edge_api_doc_row(x: i64, y: i64, name: ptr, version: ptr, pages: i64, state: ptr, fg: i64, bg: i64) -> i64 {
    let nlen: i64 = 0;
    let vlen: i64 = 0;
    let slen: i64 = 0;
    let i: i64 = 0;
    nlen = strlen(name);
    vlen = strlen(version);
    slen = strlen(state);
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
    i = 0;
    while i < vlen {
        uc_set(x + 9 + nlen + i, y, version[i], UC_WHITE, bg);
        i = i + 1;
    }
    uc_set(x + 11 + nlen + vlen, y, ' ', fg, bg);
    uc_set(x + 12 + nlen + vlen, y, '0' + pages / 100, UC_MAGENTA, bg);
    uc_set(x + 13 + nlen + vlen, y, '0' + (pages / 10) % 10, UC_MAGENTA, bg);
    uc_set(x + 14 + nlen + vlen, y, '0' + pages % 10, UC_MAGENTA, bg);
    uc_set(x + 15 + nlen + vlen, y, ' ', UC_MAGENTA, bg);
    uc_set(x + 16 + nlen + vlen, y, 'p', UC_MAGENTA, bg);
    uc_set(x + 17 + nlen + vlen, y, 'a', UC_MAGENTA, bg);
    uc_set(x + 18 + nlen + vlen, y, 'g', UC_MAGENTA, bg);
    uc_set(x + 19 + nlen + vlen, y, 'e', UC_MAGENTA, bg);
    uc_set(x + 20 + nlen + vlen, y, 's', UC_MAGENTA, bg);
    uc_set(x + 22 + nlen + vlen, y, ' ', fg, bg);
    i = 0;
    while i < slen {
        uc_set(x + 23 + nlen + vlen + i, y, state[i], UC_GREEN, bg);
        i = i + 1;
    }
    return 0;
}
