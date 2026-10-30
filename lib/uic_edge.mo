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
