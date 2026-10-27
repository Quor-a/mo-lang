# ambA / ambB 各自定义同名 helper()，返回不同的值。
# 这是 nscheck 的哨兵：证明「调用点所在文件没有自己的定义时，
# 绑定到最后被处理的那个 import 文件」—— 改 import 顺序就换实现，
# 且不报错、不崩溃。
fn helper() -> i64 { return 111; }
