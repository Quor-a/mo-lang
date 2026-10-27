#!/bin/bash
# sitetest —— 用真实内容验证 examples/site.mo
#
#   bash tools/sitetest.sh
#
# 为什么单独做这个测试：site.mo 是本项目最大的真实应用，
# 它压到目录遍历、front-matter 解析、Markdown 渲染、排序、
# HTML 转义、RSS 生成六条链路。这些用单元测试覆盖不到——
# 只有真生成一次站点才知道对不对。
#
# 本测试里每个断言都对应一个**实际出现过**的 bug，不是凭空想的。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
W=/tmp/mosite
rm -rf $W; mkdir -p $W/lib $W/posts
cp lib/*.mo $W/lib/
cp examples/site.mo $W/test.mo

# --- 素材：故意包含会触发各条 bug 的内容 ---
cat > $W/posts/2026-10-01-hello.md <<'MD'
---
title: 第一篇：从汇编开始
date: 2026-10-01
---

## 小节

优点是自举链条干净，代价是每改一处要**改两遍**。

```
mov rax, 1
syscall
```

- 第一条：写输出
MD
cat > $W/posts/2026-10-05-boot.md <<'MD'
---
title: 自举闭环
date: 2026-10-05
---

三级一致，`a = b` 这样的行内代码要完整。
MD
cat > $W/posts/2026-10-09-esc.md <<'MD'
---
title: 转义与安全
date: 2026-10-09
---

注意 < 与 & 这类字符必须被转义，不能原样输出。
MD

fail=0
chk() { # chk <描述> <条件命令...>
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "  ✓ $d"; else echo "  ✗ $d"; fail=$((fail+1)); fi
}

( cd $W && "$ROOT/bin/moc" >/dev/null 2>&1 )
[ -x $W/out.elf ] || { echo "编译失败"; exit 1; }
( cd $W && ./out.elf posts out >/dev/null 2>&1 )
[ $? -ne 0 ] && { echo "运行失败"; exit 1; }

echo "sitetest:"
chk "生成 index.html"        test -f $W/out/index.html
chk "生成 rss.xml"           test -f $W/out/rss.xml
chk "三篇文章各一页"          test -f $W/out/posts/2026-10-01-hello.html -a -f $W/out/posts/2026-10-05-boot.html -a -f $W/out/posts/2026-10-09-esc.html

# bug1：目录遍历顺序不等于日期顺序，倒着遍历也不等于排序。
#        实测曾把 10-05 排到 10-09 后面。这里验证真排序（倒序）。
order=$(grep -o '<small>[^<]*</small>' $W/out/index.html | sed 's/<[^>]*>//g' | head -3 | tr '\n' ' ')
chk "索引按日期倒序（实际：$order）" test "$order" = "2026-10-09 2026-10-05 2026-10-01 "

# bug2：行内代码偏移算错，`a = b` 被渲染成 `a = ` 丢字
chk "行内代码完整不丢字"      grep -q '<code>a = b</code>' $W/out/posts/2026-10-05-boot.html

# bug3：HTML 不转义会破坏页面结构（真实安全问题）
chk "< 被转义"               grep -q '&lt;' $W/out/posts/2026-10-09-esc.html
chk "& 被转义"               grep -q '&amp;' $W/out/posts/2026-10-09-esc.html
chk "原文 < 不裸奔"          grep -qv '[^&]lt; ' $W/out/posts/2026-10-09-esc.html

# 其余渲染链路
chk "粗体渲染"               grep -q '<strong>改两遍</strong>' $W/out/posts/2026-10-01-hello.html
chk "代码块渲染"             grep -q '<pre><code>' $W/out/posts/2026-10-01-hello.html
chk "代码块正确闭合"         grep -q '</code></pre>' $W/out/posts/2026-10-01-hello.html
chk "列表渲染"               grep -q '<li>第一条：写输出</li>' $W/out/posts/2026-10-01-hello.html
chk "标题渲染"               grep -q '<h2>小节</h2>' $W/out/posts/2026-10-01-hello.html
chk "front-matter 生效"      grep -q '第一篇：从汇编开始' $W/out/index.html
chk "RSS 含条目"             grep -q '<item>' $W/out/rss.xml

if [ $fail -eq 0 ]; then echo "sitetest: OK（全部通过）"; else echo "sitetest: $fail 项未通过"; exit 1; fi
