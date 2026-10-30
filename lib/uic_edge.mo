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
