# Mo 语言开发交接（2026-11）

本文件供接手开发者快速恢复上下文。工作目录：`/home/agentuser/mo-proj/mo`（GitHub: Quor-a/mo-lang）。

## 当前版本：v1.1154.0（已发布）

- **GitHub Release**：v1.1154.0（RID 437977440），11 资产全 uploaded；
  守恒规则：远端恒 2 个 Release，发新版删最老（当前 = v1.1154.0 + v1.1153.0）。
- **commit 链**：master = `e566911`（v1.1154.0）→ `763b9ed`（README v1.1153）→ `c6b6d7e`（v1.1153 修复）→ `679a6da`（v1.1152）…
- **release 分支**：`release/v1.1154-bundle` = `572c552`（含签名 bundle zip + sha256 + BUNDLE 说明）。
- **tag**：`v1.1154.0` 已推送。
- **门禁**：485/0 全绿（tests/ 下 485 个测试）。

### 最近版本特性
- **v1.1154**：全局 enum 变量。`var g: Sh;`（带数据变体）+ `g = Sh.Circle(5);` 赋值。
  - `parse_global` 识别 enum 名登记 i64 槽；赋值特判（右侧 variant struct 地址直接存槽）。
  - **地址语义**：enum 变量（全局/局部）槽内存 variant 对象地址，`match g { Circle(x) => ... }`
    变体绑定臂解引用取数据。
  - **已知限制**：enum 变量的数字/区间臂（`match g { 0 => ... }`）按地址比较不命中；
    数字臂只对 enum 构造表达式直接可用（v1.1152）。
  - 测试：`tests/334_enum_global.mo`（RC=21）。
  - 文档：`docs/enum-global.md`。
- **v1.1153**：enum 形参值语义修复。
  - `enum_type_exists` 双表（O_ENAME 简单 enum + EV_E 带数据变体）。
  - 跨函数双数据变体值传递修复。测试：`tests/333_enum_param_value.mo`（RC=6）。
  - 文档：`docs/enum-param-value.md`。

## 构建 / 测试

```bash
./bin/moc prog.mo prog.elf   # 编译（自举编译器）
./prog.elf                    # 运行
make test                     # 跑全部测试（tests/*.mo）
make boot                     # 自举校验
```

改 `src/mo/compiler_part*.mo` 后**必须重拼**：
```bash
cat src/mo/compiler_part*.mo > src/compiler.mo
./bin/moc src/compiler.mo /tmp/mocNEW
```

## 发布流程（每版本）

```bash
# 1. 门禁（后台，一次只能跑一个）
nohup bash -c 'timeout 700 bash tests/run.sh /tmp/mocNEW > /tmp/run.log 2>&1' > /dev/null 2>&1 &
# 判定用最后一行 "通过 X / 失败 Y"，期望全绿。

# 2. 生成发布资产
bash release/build-release.sh 1.1154.0   # → dist/mo-lang-1.1154.0/

# 3. 签名（8 个产物）
bash release/sign.sh dist/mo-lang-1.1154.0/checksums.txt dist/mo-lang-1.1154.0/moc ...（8 个）

# 4. 验签（必须 stdin 管道，不是 -h <file>）
cat FILE | ssh-keygen -Y check-novalidate -n mo-release -s FILE.sig   # 期望 "Good"

# 5. 打 bundle zip（python zipfile，zip 未装）：产物+签名+公钥+VERIFY.txt
# 6. 建 GitHub Release（RID），传 11 资产（8 产物+checksums+checksums.sig+bundle+sha256）
# 7. 守恒删最老 Release + tag
# 8. 建 release/v1.XXXX-bundle 分支，提交 bundle 资产并推送
```

**签名要点**：
- 私钥 `~/.ssh/mo-release-signing-key`（不入库），公钥 `release/SIGNING_KEY.pub`。
- 验签必须 `cat <file> | ssh-keygen -Y check-novalidate -n mo-release -s <file>.sig`
  （`-h <file>` 会永远 incorrect signature —— v1.1153 实锤）。

## 编译器架构要点

- 编译器是自举的 Mo 程序，拆成 5 个 part：`src/mo/compiler_part1..5.mo`，拼成 `src/compiler.mo`。
- 关键全局槽（编译器内部）：
  - `O_ENAME`/`O_ECNT`：简单 enum 常量表（`enum_add_const` 填充）。
  - `EV_E`/`EVCNT`/`EV_TAG`：带数据变体表（`parse_enum` 填充）。
  - `O_CFA`/`O_CFB`/`O_CFF`：const fn 求值（单参数）。
  - `K_` 槽：2496=K_RUN、2504=K_NRUNA、2512=K_EIM 已用；新增槽前正则扫空闲。
- 编译器可用探针（`emit_dec` + `syscall`）打印调试信息，但用完必须清理。

## 下一步候选（社区调研排序）

1. **const fn 多参数扩展**（正在进行）：
   - 当前限制：`const fn` 只支持**单参数**、体仅纯算术表达式。
   - 探索：`cfn_eval(fid, arg)` 单值传递；`cfn_atom` 只认识 O_CFA 一个参数名。
   - 计划：参数栈（O_CFA 区域按深度帧）、多参数名表、调用点循环求值实参。
   - 测试样例：`const fn max(a: i64, b: i64) -> i64 { if a > b { return a; } return b; }`
     （注意：当前 const fn 体不支持 if/分支，需同时扩展）。
2. **moc 跨平台**（mo2x syscall 表转译，覆盖更多目标）。
3. **comptime 扩展**（Zig 风格编译期求值，社区热点）。

## 社区调研热点（2026-11）

- C++ P2688 pattern matching、Mojo 1.2 comptime match、Zig comptime。
- 语言趋势：编译期求值、模式匹配类型化、错误处理改进。

## 关键经验 / 坑

- 门禁**一次只能跑一个**（并发抢 /tmp/mot 会假象）。
- 跑 elf 前 `rm -f xx.elf` 重编再跑（陈旧 elf 假象）。
- 改 part 后必须重拼 + grep 验证关键字符串。
- 发布上传 GitHub API 必须 retry 循环（网络极不稳）。
- bundle zip 用 python zipfile（zip 命令未装）。
- 消费端下载大文件极慢（bundle 14.8MB），可用 `git show release/v1.XXXX-bundle:dist/...` 本地验证 sha256 一致性替代。