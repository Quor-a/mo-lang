# try / catch（v1.1172）

```mo
try {
    r = a[i];          # 越界 panic 被捕获
} catch(e) {
    # e = 错误码（越界 = 1）
}
```

- catch 只捕获**同函数内**的越界 panic。跨函数（被调函数越界）不经过
  调用者的 catch —— 栈帧未清理，仍走全局 panic 例程打印并 exit(1)。⚠️
- catch 进入时先从数据段槽恢复 rsp（进入 try 时保存），所以异常路径
  上未清的 push 不会污染 catch 块。
- `catch(e)` 的 e 可省略（写 `catch` 即可）。
- 嵌套 try：检查点跳最近（最内层）catch。
- `try` 是上下文关键字：变量名 try 不受影响（后面不跟 `{` 即可）。
