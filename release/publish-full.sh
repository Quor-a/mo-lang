#!/bin/bash
# publish-full.sh —— 给已存在的 Release 补全资产 + 替换说明
# 用法: bash release/publish-full.sh <tag> <dist-dir>
set -uo pipefail
cd "$(dirname "$0")/.."
TAG="$1"
DIST="$2"
VER="${TAG#v}"   # 资产文件名用无 v 前缀的版本号 (mo-lang-1.1150.0-src.tar.gz)
TOK=$(git remote get-url origin | sed -n 's|https://[^:]*:\([^@]*\)@.*|\1|p')
[ -z "$TOK" ] && { echo "无法从 remote url 提取 token"; exit 1; }
AUTH="Authorization: token $TOK"
API="https://api.github.com/repos/Quor-a/mo-lang"
UPL="https://uploads.github.com/repos/Quor-a/mo-lang"

RID=$(curl -s -H "$AUTH" "$API/releases/tags/$TAG" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
[ -z "$RID" ] && { echo "Release $TAG 不存在"; exit 1; }
echo "RID=$RID"

# 已有资产名集合（避免重复上传）
EXISTING=$(curl -s -H "$AUTH" "$API/releases/$RID/assets" | python3 -c '
import json,sys
print(" ".join(a["name"] for a in json.load(sys.stdin)))')
echo "已有资产: $EXISTING"

# 上传 dist 下全部资产（含 demo/，资产名用 demo- 前缀）
upload() {
  local f="$1" name="$2"
  if echo " $EXISTING " | grep -q " $name "; then
    echo "  跳过(已存在): $name"; return 0
  fi
  local r got try
  for try in 1 2 3 4 5; do
    r=$(curl -s --max-time 120 -H "$AUTH" -H "Content-Type: application/octet-stream" \
         --data-binary @"$f" "$UPL/releases/$RID/assets?name=$name")
    got=$(echo "$r" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(d.get("name",""), d.get("size",""))
except Exception: print("FAIL", "")')
    echo "  ASSET(try$try): $name -> $got"
    if echo "$got" | grep -q "^$name "; then return 0; fi
    sleep 5
  done
  return 1
}

OK=0
for f in "$DIST"/moc "$DIST"/mo-lang-$VER-src.tar.gz "$DIST"/mo-lang-$VER-src.zip \
         "$DIST"/demo/fib-* "$DIST"/checksums.txt "$DIST"/checksums.txt.sig; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  case "$f" in
    */demo/*) name="demo-$base" ;;
    *)        name="$base" ;;
  esac
  upload "$f" "$name" && OK=$((OK+1)) || echo "  ⚠️ 上传失败: $name"
done
echo "上传成功 $OK 个资产"

# 说明正文（用 Python 拼 JSON，防注入）
python3 - "$TAG" "$RID" "$AUTH" <<'PY'
import json, sys, urllib.request
tag, rid, auth = sys.argv[1], sys.argv[2], sys.argv[3]
body = f"""# Mo 语言 {tag}

## 下载
每个资产都有 SHA256 校验和（`checksums.txt`）与 SSH 签名（`checksums.txt.sig`）。

| 资产 | 说明 |
|------|------|
| `moc` | 自举编译器（x86-64 Linux，静态链接） |
| `mo-lang-{tag}-src.tar.gz` / `.zip` | **完整源码包**（1162 文件，与 tag 一致） |
| `demo-fib-x86_64-linux` | 演示程序 x86-64 Linux（实测运行 ✓） |
| `demo-fib-aarch64-linux` | 演示程序 ARM64 Linux（qemu 实测运行 ✓） |
| `demo-fib-aarch64-macos` | 演示程序 Apple Silicon macOS |
| `demo-fib-x86_64-windows.exe` | 演示程序 Windows x64 |

## 校验
```bash
sha256sum -c checksums.txt
```

## 验签
公钥在仓库 `release/SIGNING_KEY.pub`（ED25519，指纹见下）。
```bash
curl -sO https://raw.githubusercontent.com/Quor-a/mo-lang/master/release/SIGNING_KEY.pub
ssh-keygen -Y check-novalidate -n mo-release -s checksums.txt.sig < checksums.txt
# 期望输出: Good "mo-release" signature with ED25519 key SHA256:AdobzqZKRPHDJ3YJWjFP1uVg1Ax18EHHn96ozo/Tr4U
```

## 平台支持
- **编译器 (`moc`)**：自举编译器当前生成 x86-64 Linux 原生二进制（已知边界，
  源码依赖原生后端 syscall 表，`mo2x` 暂不能把它转译到 C）。
- **用户程序**：经 C 后端 `mo2x` + zig 交叉编译，覆盖 x86-64/ARM64 Linux、
  macOS、Windows x64、WASM —— Release 里的 demo 产物即按此流水线产出，
  ARM64 版经 qemu 实测输出与原生一致。
- 详见 `docs/cross-compile.md`；复现构建：`bash release/build-release.sh <ver>`。
"""
data = json.dumps({"body": body}).encode()
for attempt in range(5):
    try:
        req = urllib.request.Request(f"https://api.github.com/repos/Quor-a/mo-lang/releases/{rid}",
            data=data, method="PATCH",
            headers={"Authorization": auth, "Content-Type": "application/json", "User-Agent": "mo-release"})
        print("NOTES:", urllib.request.urlopen(req, timeout=60).status)
        break
    except Exception as e:
        print("NOTES retry", attempt + 1, ":", e)
        import time; time.sleep(5)
PY
echo "PUB-FULL-DONE"