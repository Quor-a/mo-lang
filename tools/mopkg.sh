#!/bin/bash
# mopkg —— 墨语言包管理器
#
#   bash tools/mopkg.sh init <名字>
#   bash tools/mopkg.sh install <git-url> [ref] [版本约束]
#   bash tools/mopkg.sh fetch              # 按 mo.toml 拉取全部依赖（递归）
#   bash tools/mopkg.sh tree               # 依赖树（含循环检测）
#   bash tools/mopkg.sh verify             # 校验 mo.lock 与 mo.toml 一致且可复现
#   bash tools/mopkg.sh update [名字]      # 重新解析依赖并更新锁
#   bash tools/mopkg.sh list
#   bash tools/mopkg.sh remove <名字>
#
# 设计取舍：
#   - 依赖就是 git 仓库，不做中心仓库 —— 中心仓库要维护服务端，
#     而"git 引用"已经能解决分发问题，且任何人都能当发布者。
#   - 依赖锁在 mo.lock（name/version/git/ref/commit），保证可复现构建。
#   - 依赖目录约定为 deps/<名字>/，import 时用 -I 指过去。
set +e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HERE=$PWD          # 包操作作用在**调用时**的目录
DEP=$HERE/deps
LOCK=$HERE/mo.lock

# ============================ TOML 子集解析 ============================
# 只支持本项目需要的形状：
#   [package] / [dependencies]
#   key = "value"
#   名字 = { git = "...", ref = "...", version = "..." }
#
# 为什么自己写而不依赖解析器：墨语言生态里不该为了装包先装 Python 库，
# 而且需要的只是其中极小一部分。

# 取 [package] 段里的 key
pkg_field() {
  awk -v k="$1" '
    /^\[/ { sec = $0; gsub(/[][]/, "", sec); next }
    sec == "package" && $1 == k { sub(/^[^=]*= */, ""); gsub(/"/, ""); print; exit }
  ' "$2" 2>/dev/null
}

# 列出 [dependencies] 段里的包名（每行一个）
dep_names() {
  awk '
    /^\[/ { sec = $0; gsub(/[][]/, "", sec); next }
    sec == "dependencies" {
      line = $0
      sub(/#.*/, "", line)
      if (line ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=/) {
        n = line; sub(/[ \t]*=.*/, "", n); gsub(/[ \t]/, "", n)
        if (n != "") print n
      }
    }
  ' "$1" 2>/dev/null
}

# 取某个依赖的字段（git / ref / version）
dep_field() {
  awk -v want="$1" -v key="$2" '
    /^\[/ { sec = $0; gsub(/[][]/, "", sec); next }
    sec == "dependencies" {
      line = $0
      sub(/#.*/, "", line)
      n = line; sub(/[ \t]*=.*/, "", n); gsub(/[ \t]/, "", n)
      if (n == want) {
        if (line ~ /\{/) {                      # name = { git = "...", ... }
          body = line; sub(/^[^{]*\{/, "", body); sub(/\}[ \t]*$/, "", body)
          n2 = split(body, parts, ",")
          for (i = 1; i <= n2; i++) {
            kv = parts[i]; gsub(/^[ \t]+|[ \t]+$/, "", kv)
            k = kv; sub(/[ \t]*=.*/, "", k); gsub(/[ \t]/, "", k)
            v = kv; sub(/^[^=]*= */, "", v); gsub(/"/, "", v); gsub(/[ \t]+$/, "", v)
            if (k == key) { print v; exit }
          }
        } else {                                # name = "1.2.3"
          v = line; sub(/^[^=]*= */, "", v); gsub(/"/, "", v); gsub(/[ \t]+$/, "", v)
          if (key == "version") { print v; exit }
        }
      }
    }
  ' "$3" 2>/dev/null
}

# ============================ 版本（semver 子集） ============================
# 转成可比较的整数：1.2.3 -> 1002003
ver_num() {
  local v=$(echo "$1" | sed 's/[^0-9.].*//')
  local a b c
  IFS=. read -r a b c <<< "$v"
  echo $(( ${a:-0} * 1000000 + ${b:-0} * 1000 + ${c:-0} ))
}

ver_major() { local v=$(echo "$1" | sed 's/[^0-9.].*//'); echo "${v%%.*}"; }
ver_minor() { local v=$(echo "$1" | sed 's/[^0-9.].*//'); local r="${v#*.}"; echo "${r%%.*}"; }

# ver_match <实际版本> <约束>
#   "" | "*"        任意
#   =1.2.3          相等
#   >=1.0.0  <2.0.0 比较
#   ^1.2.3          >=1.2.3 且 <2.0.0（主版本不变）
#   ~1.2.3          >=1.2.3 且 <1.3.0（次版本不变）
ver_match() {
  local have="$1" c="$2"
  [ -z "$c" ] && return 0
  [ "$c" = "*" ] && return 0
  local n=$(ver_num "$have")
  case "$c" in
    '>='*) [ "$n" -ge "$(ver_num "${c#>=}")" ] && return 0; return 1 ;;
    '<='*) [ "$n" -le "$(ver_num "${c#<=}")" ] && return 0; return 1 ;;
    '>'*)  [ "$n" -gt "$(ver_num "${c#>}")" ] && return 0; return 1 ;;
    '<'*)  [ "$n" -lt "$(ver_num "${c#<}")" ] && return 0; return 1 ;;
    '='*)  [ "$n" -eq "$(ver_num "${c#=}")" ] && return 0; return 1 ;;
    '^'*)
      local b="${c#^}"; local bn=$(ver_num "$b")
      local hi=$(( ($(ver_major "$b") + 1) * 1000000 ))
      [ "$n" -ge "$bn" ] && [ "$n" -lt "$hi" ] && return 0; return 1 ;;
    '~'*)
      # 🔴 不能写 ${c#~} —— `~` 在 pattern 位置会被 bash 做 **tilde 展开**
      #    （变成 $HOME），于是前缀根本不匹配、什么都删不掉，
      #    b 仍是 "~1.2.0"，ver_major/minor 全空 → 算术表达式报
      #    "operand expected"。这个报错离真正的原因很远。
      local b=$(printf '%s' "$c" | sed 's/^~//'); local bn=$(ver_num "$b")
      local hi=$(( $(ver_major "$b") * 1000000 + ($(ver_minor "$b") + 1) * 1000 ))
      [ "$n" -ge "$bn" ] && [ "$n" -lt "$hi" ] && return 0; return 1 ;;
    *)
      [ "$n" -eq "$(ver_num "$c")" ] && return 0; return 1 ;;
  esac
}

# ============================ 锁文件 ============================
lock_get() {   # lock_get <name> <field>
  awk -v want="$1" -v key="$2" '
    /^\[\[package\]\]/ { cur = ""; next }
    /^[a-z]+ = / {
      k = $1; v = $0; sub(/^[^=]*= */, "", v); gsub(/"/, "", v);
      if (k == "name") cur = v;
      if (cur == want && k == key) { print v; exit }
    }
  ' "$LOCK" 2>/dev/null
}

lock_names() {
  awk '/^name = /{ v=$0; sub(/^[^=]*= */,"",v); gsub(/"/,"",v); print v }' "$LOCK" 2>/dev/null
}

# 写/更新一条锁记录
#
# 🔴 不能用 `python3 <<'PY' ... || awk ...` 这种写法：
#    heredoc 的内容从**下一行**开始，于是整段 awk 被当成 Python 脚本吃掉，
#    `PY` 结束符直到后面才出现 —— 中间所有的 shell 代码全部消失，
#    bash -n 报的语法错误位置离真正的原因很远。
lock_set() {   # lock_set <name> <version> <git> <ref> <commit>
  local name="$1" ver="$2" git="$3" ref="$4" cm="$5"
  [ -f "$LOCK" ] || printf '# mopkg lockfile v2 — 由 mopkg 生成，请勿手工编辑\n' > "$LOCK"
  python3 - "$LOCK" "$name" "$ver" "$git" "$ref" "$cm" <<'PY'
import sys, re
path, name, ver, git, ref, cm = sys.argv[1:7]
try:
    s = open(path).read()
except Exception:
    s = ''
head, _, rest = s.partition('[[package]]')
blocks = [b for b in rest.split('[[package]]') if b.strip()]
blocks = [b for b in blocks
          if not re.search(r'^\s*name\s*=\s*"%s"' % re.escape(name), b, re.M)]
out = head if head.strip() else '# mopkg lockfile v2 — 由 mopkg 生成，请勿手工编辑\n'
for b in blocks:
    out += '[[package]]' + b
out += ('\n[[package]]\nname = "%s"\nversion = "%s"\ngit = "%s"\nref = "%s"\n'
        'commit = "%s"\n' % (name, ver, git, ref, cm))
open(path, 'w').write(out)
PY
}

# ============================ 安装 ============================
install_pkg() {
  local url="$1" ref="${2:-}" want="${3:-}"
  [ -z "$url" ] && { echo "用法: mopkg install <git-url> [ref] [版本约束]"; exit 2; }
  local name=$(basename "$url" .git)
  mkdir -p "$DEP"

  local locked=""
  if [ -f "$LOCK" ]; then locked=$(lock_get "$name" commit); fi

  if [ -d "$DEP/$name" ]; then
    # 已装：若锁里记了 commit，就**检出到锁定版本**（可复现）
    if [ -n "$locked" ]; then
      (cd "$DEP/$name" && git checkout -q "$locked" 2>/dev/null) || true
    fi
  else
    local refarg=""
    [ -n "$ref" ] && refarg="--branch $ref"
    git clone -q --depth 20 $refarg "$url" "$DEP/$name" 2>&1 | tail -2
    [ -d "$DEP/$name" ] || { echo "克隆失败: $url"; exit 1; }
    if [ -n "$locked" ]; then
      (cd "$DEP/$name" && git fetch -q origin "$locked" 2>/dev/null; git checkout -q "$locked" 2>/dev/null) || true
    fi
  fi

  local ver=$(pkg_field version "$DEP/$name/mo.toml" 2>/dev/null)
  [ -z "$ver" ] && ver="0.0.0"
  if [ -n "$want" ]; then
    if ! ver_match "$ver" "$want"; then
      echo "✗ $name 版本 $ver 不满足约束 $want"
      return 1
    fi
  fi
  local cm=$(cd "$DEP/$name" && git rev-parse HEAD 2>/dev/null)
  [ -z "$ref" ] && ref=$(cd "$DEP/$name" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
  lock_set "$name" "$ver" "$url" "$ref" "$cm"
  echo "已安装 $name @ $ver (${cm:0:8})"

  # 递归：拉它自己的依赖
  if [ -f "$DEP/$name/mo.toml" ]; then
    local d
    for d in $(dep_names "$DEP/$name/mo.toml"); do
      local du=$(dep_field "$d" git "$DEP/$name/mo.toml")
      local dr=$(dep_field "$d" ref "$DEP/$name/mo.toml")
      local dv=$(dep_field "$d" version "$DEP/$name/mo.toml")
      if [ -n "$du" ]; then
        [ -d "$DEP/$d" ] || install_pkg "$du" "$dr" "$dv"
      fi
    done
  fi
  return 0
}

# ============================ 依赖树 + 循环检测 ============================
# 为什么需要：依赖装多了以后，"这个包是怎么被引入的"靠 list 看不出来。
# 循环依赖在墨语言里尤其致命 —— import 会无限展开。
tree_visit() {   # tree_visit <name> <tomlfile> <depth> <path>
  local name="$1" f="$2" d="$3" path="$4"
  local i=0 pad=""
  while [ $i -lt "$d" ]; do pad="$pad  "; i=$((i+1)); done
  local ver=$(pkg_field version "$f" 2>/dev/null)
  echo "${pad}${name} ${ver:-?}"
  local child
  for child in $(dep_names "$f"); do
    # 环检测：如果已在路径里，报出来而不是无限递归
    case " $path " in
      *" $child "*) echo "${pad}  ✗ 循环依赖: $child -> ... -> $name -> $child"; continue ;;
    esac
    local cf=""
    [ -f "$DEP/$child/mo.toml" ] && cf="$DEP/$child/mo.toml"
    if [ -z "$cf" ]; then
      echo "${pad}  $child (未安装)"
    else
      tree_visit "$child" "$cf" $((d+1)) "$path $name"
    fi
  done
}

cmd_tree() {
  [ -f mo.toml ] || { echo "当前目录没有 mo.toml"; exit 2; }
  local me=$(pkg_field name mo.toml)
  echo "${me:-<root>} $(pkg_field version mo.toml)"
  local d
  for d in $(dep_names mo.toml); do
    if [ -f "$DEP/$d/mo.toml" ]; then
      tree_visit "$d" "$DEP/$d/mo.toml" 1 "$d"
    else
      echo "  $d (未安装)"
    fi
  done
}

# ============================ verify ============================
cmd_verify() {
  [ -f mo.toml ] || { echo "当前目录没有 mo.toml"; exit 2; }
  [ -f "$LOCK" ] || { echo "✗ 没有 mo.lock（先跑 mopkg fetch）"; exit 1; }
  local bad=0

  # 1) mo.toml 里声明的每个依赖都必须已安装、且版本满足约束
  local d
  for d in $(dep_names mo.toml); do
    if [ ! -d "$DEP/$d" ]; then
      echo "✗ 依赖未安装: $d"; bad=1; continue
    fi
    local want=$(dep_field "$d" version mo.toml)
    local have=$(pkg_field version "$DEP/$d/mo.toml"); [ -z "$have" ] && have="0.0.0"
    if [ -n "$want" ] && ! ver_match "$have" "$want"; then
      echo "✗ $d: 版本 $have 不满足约束 $want"; bad=1
    fi
    # 2) 锁里的 commit 必须与实际检出的 HEAD 一致（可复现性）
    local lc=$(lock_get "$d" commit)
    local ac=$(cd "$DEP/$d" && git rev-parse HEAD 2>/dev/null)
    if [ -n "$lc" ] && [ "$lc" != "$ac" ]; then
      echo "✗ $d: 锁记录 ${lc:0:8} ≠ 实际 ${ac:0:8}（不可复现）"; bad=1
    fi
    if [ -z "$lc" ]; then echo "✗ $d: mo.lock 里没有记录"; bad=1; fi
  done

  # 3) 锁里不应有多余的包（装过又删掉的）
  #
  # 🔴 不能只比对 mo.toml 的**直接**依赖：间接依赖（c 是 b 的依赖）
  #    本来就不写在 app 的 mo.toml 里，却必须出现在锁中 ——
  #    第一版只比直接依赖，于是正常项目永远报"锁里有未声明的包"。
  #    正确做法是比"依赖闭包"（直接依赖 + 递归展开它们的依赖）。
  local closure=""
  closure_collect() {   # closure_collect <name>
    local nm="$1"
    case " $closure " in *" $nm "*) return 0 ;; esac
    closure="$closure $nm"
    local f="$DEP/$nm/mo.toml"
    [ -f "$f" ] || return 0
    local ch
    for ch in $(dep_names "$f"); do closure_collect "$ch"; done
  }
  for d in $(dep_names mo.toml); do closure_collect "$d"; done
  local ln
  for ln in $(lock_names); do
    case " $closure " in
      *" $ln "*) ;;
      *) echo "✗ mo.lock 里有不属于依赖闭包的多余包: $ln"; bad=1 ;;
    esac
  done

  # 4) 循环依赖
  if cmd_tree 2>/dev/null | grep -q "循环依赖"; then
    echo "✗ 存在循环依赖"; bad=1
  fi

  if [ "$bad" = "0" ]; then echo "✓ verify: 依赖完整、版本满足约束、锁可复现"; return 0; fi
  return 1
}

# ============================ 其余命令 ============================
fetch_all() {
  [ -f mo.toml ] || { echo "当前目录没有 mo.toml"; exit 2; }
  local d
  for d in $(dep_names mo.toml); do
    local u=$(dep_field "$d" git mo.toml)
    local r=$(dep_field "$d" ref mo.toml)
    local v=$(dep_field "$d" version mo.toml)
    [ -z "$u" ] && { echo "✗ $d 缺少 git 字段"; continue; }
    [ -d "$DEP/$d" ] || install_pkg "$u" "$r" "$v"
  done
  echo "依赖就绪"
}

cmd_update() {
  [ -f mo.toml ] || { echo "当前目录没有 mo.toml"; exit 2; }
  local only="$1"
  local d
  for d in $(dep_names mo.toml); do
    [ -n "$only" ] && [ "$d" != "$only" ] && continue
    local u=$(dep_field "$d" git mo.toml)
    local r=$(dep_field "$d" ref mo.toml)
    [ -z "$u" ] && continue
    if [ -d "$DEP/$d" ]; then (cd "$DEP/$d" && git fetch -q 2>/dev/null; git checkout -q "$r" 2>/dev/null; git pull -q 2>/dev/null) || true; fi
  done
  fetch_all
  echo "已更新"
}

cmd_init() {
  local name="$1"
  [ -z "$name" ] && { echo "用法: mopkg init <名字>"; exit 2; }
  mkdir -p src
  cat > mo.toml <<TOML
[package]
name = "$name"
version = "0.1.0"
mo = ">=1.16"

[dependencies]
# 两种写法：
#   名字 = { git = "https://...", ref = "main", version = "^1.0.0" }
#   名字 = { git = "https://..." }
TOML
  cat > src/main.mo <<'MO'
fn main() -> i64 {
    print("hello from a Mo package\n");
    return 0;
}
MO
  echo "已创建包 $name（mo.toml + src/main.mo）"
}

cmd_list() {
  if [ ! -d "$DEP" ]; then echo "（无依赖）"; exit 0; fi
  local d
  for d in "$DEP"/*/; do
    local n=$(basename "$d")
    local v=$(pkg_field version "$d/mo.toml")
    local c=$(cd "$d" && git rev-parse HEAD 2>/dev/null)
    echo "  $n ${v:-?} (${c:0:8})"
  done
}

cmd_remove() {
  local n="$1"
  [ -d "$DEP/$n" ] || { echo "未安装: $n"; exit 1; }
  rm -rf "$DEP/$n"
  if [ -f "$LOCK" ]; then
    python3 - "$LOCK" "$n" <<'PY'
import sys, re
p, want = sys.argv[1], sys.argv[2]
s = open(p).read()
blocks = s.split('[[package]]')
head = blocks[0]
keep = [b for b in blocks[1:] if re.search(r'^\s*name\s*=\s*"%s"' % re.escape(want), b, re.M) is None]
open(p, 'w').write(head + ''.join('[[package]]' + b for b in keep))
PY
  fi
  echo "已移除 $n"
}

cmd=$1; shift || true
case "$cmd" in
  init)    cmd_init "$@" ;;
  install) install_pkg "$@" ;;
  fetch)   fetch_all ;;
  tree)    cmd_tree ;;
  verify)  cmd_verify ;;
  update)  cmd_update "$@" ;;
  list)    cmd_list ;;
  remove)  cmd_remove "$@" ;;
  *) echo "用法: mopkg {init|install|fetch|tree|verify|update|list|remove}"; exit 2 ;;
esac
