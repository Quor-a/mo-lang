# examples/uic_messages.mo —— 消息中心示例
# 用画布组件组合一个聊天消息中心：
# 窗口 + 会话标签 + 消息气泡 + 输入框 + 状态栏。
# 展示墨语言画布标准库的聊天 UI 能力。
#
# 编译：./bin/moc examples/uic_messages.mo uic_messages.elf && ./uic_messages.elf

import "uic.mo";

fn main() -> i64 {
    uc_init(44, 14);
    uc_clear(UC_WHITE, UC_BLUE);

    # 消息中心窗口
    uc_window(2, 1, 40, 12, "Messages", UC_WHITE, UC_BLUE);

    # 会话标签页
    uc_tabs(4, 3, "Chats|Calls|Archived", 0, UC_WHITE, UC_BLUE);

    # 消息气泡（对方 / 自己）
    uc_text(4, 5, "Alice", UC_YELLOW, UC_BLUE);
    uc_chat_bubble(4, 6, 12, "hi, are you there?", 0, UC_GREEN, UC_BLUE);
    uc_chat_bubble(24, 7, 8, "yes!", 1, UC_CYAN, UC_BLUE);

    # 输入框
    uc_text(4, 10, "Reply:", UC_YELLOW, UC_BLUE);
    uc_field(4, 11, 30, "R", "ok, sounds good", 1, UC_WHITE, UC_BLUE);

    # 状态栏
    uc_status_bar(4, 12, 36, "2 messages", 5, 5, 66, UC_WHITE, UC_BLUE);

    uc_render();
    return 0;
}