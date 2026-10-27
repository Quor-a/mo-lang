# kernel.mo —— 用墨语言写的 32 位内核（Multiboot，可被 GRUB/QEMU 加载）
#
#   bash tools/kernel.sh examples/kernel.mo /tmp/mokernel.elf
#
# 这是一个**真内核**：运行在 ring0，直接写 VGA 缓冲 0xB8000，
# 通过 in/out 端口读键盘，没有任何 libc、没有任何系统调用 ——
# 因为它自己就是提供系统调用的那一层。
#
# 它演示的正是"墨语言能写系统"这件事：
#   同一个 print_i64()，编成用户态程序是 write(1,...)，
#   编成内核就是往 0xB8000 写字符。

# 端口 I/O：由**内核后端的前导**提供（内联汇编 inb / outb / hlt / cli / sti）。
# 这里写成普通函数定义，链接时由前导里的实现接管。
# 用这种写法而不是"前向声明"，是因为墨语言目前没有 extern 声明语法。

# 键盘扫描码 → ASCII（只处理主键盘区，足够跑一个最小 shell）
# mo-target: kern   # 非原生后端，projcheck 跳过原生编译
fn sc_to_ascii(sc: i64) -> i64 {
    if sc == 2 { return 49; }
    if sc == 3 { return 50; }
    if sc == 4 { return 51; }
    if sc == 5 { return 52; }
    if sc == 6 { return 53; }
    if sc == 7 { return 54; }
    if sc == 8 { return 55; }
    if sc == 9 { return 56; }
    if sc == 10 { return 57; }
    if sc == 11 { return 48; }
    if sc == 12 { return 45; }
    if sc == 13 { return 61; }
    if sc == 16 { return 113; }
    if sc == 17 { return 119; }
    if sc == 18 { return 101; }
    if sc == 19 { return 114; }
    if sc == 20 { return 116; }
    if sc == 21 { return 121; }
    if sc == 22 { return 117; }
    if sc == 23 { return 105; }
    if sc == 24 { return 111; }
    if sc == 25 { return 112; }
    if sc == 26 { return 91; }
    if sc == 27 { return 93; }
    if sc == 30 { return 97; }
    if sc == 31 { return 115; }
    if sc == 32 { return 100; }
    if sc == 33 { return 102; }
    if sc == 34 { return 103; }
    if sc == 35 { return 104; }
    if sc == 36 { return 106; }
    if sc == 37 { return 107; }
    if sc == 38 { return 108; }
    if sc == 39 { return 59; }
    if sc == 40 { return 39; }
    if sc == 41 { return 96; }
    if sc == 44 { return 122; }
    if sc == 45 { return 120; }
    if sc == 46 { return 99; }
    if sc == 47 { return 118; }
    if sc == 48 { return 98; }
    if sc == 49 { return 110; }
    if sc == 50 { return 109; }
    if sc == 51 { return 44; }
    if sc == 52 { return 46; }
    if sc == 53 { return 47; }
    if sc == 57 { return 32; }
    return 0;
}

# 轮询键盘：0x64 状态端口的第 0 位表示数据可读
fn kbd_poll() -> i64 {
    let st: i64 = inb(100);
    if (st & 1) == 0 { return 0; }
    return inb(96);
}

var TICKS: i64 = 0;
var CUR: i64 = 0;
var LINE: [128] byte = 0;

# 累加器：演示"内核里也有全局状态"
var SUM: i64 = 0;

fn do_cmd() -> i64 {
    if streq(&LINE, "help") == 1 {
        print("\ncommands: help, echo, add, ticks, clear, halt");
        return 0;
    }
    if streq(&LINE, "ticks") == 1 {
        print("\nticks=");
        print_i64(TICKS);
        return 0;
    }
    if streq(&LINE, "sum") == 1 {
        print("\nsum=");
        print_i64(SUM);
        return 0;
    }
    if streq(&LINE, "clear") == 1 {
        vga_clear();
        return 0;
    }
    if streq(&LINE, "halt") == 1 {
        print("\nhalting...");
        cli();
        hlt();
        return 0;
    }
    # 形如 "add 3 4"：解析两个一位数相加
    #
    # 这里必须**校验格式**。之前没校验，于是 "add 34" 会被读成
    # a=LINE[4]='3'、b=LINE[6]=字符串结尾的 0，算出 3 + (0-48) = **-45**。
    # 这是典型的"安静地给出错的结果"——不崩不报错，只是答案离谱。
    # 内核里更危险：用户可能据此做判断。
    if str_starts_with(&LINE, "add") == 1 {
        if strlen(&LINE) == 7 {
            if load8(&LINE + 5) == 32 {          # 第 5 位必须是空格
                let ca: i64 = load8(&LINE + 4);
                let cb: i64 = load8(&LINE + 6);
                if ca >= 48 {
                    if ca <= 57 {
                        if cb >= 48 {
                            if cb <= 57 {
                                let a: i64 = ca - 48;
                                let b: i64 = cb - 48;
                                SUM = SUM + a + b;
                                print("\n= ");
                                print_i64(a + b);
                                return 0;
                            }
                        }
                    }
                }
            }
        }
        print("\nusage: add <digit> <digit>   (e.g. add 3 4)");
        return 0;
    }
    if strlen(&LINE) > 0 {
        print("\n? ");
        print(&LINE);
        return 0;
    }
    return 0;
}

fn main() -> i64 {
    vga_clear();
    print("Mo Kernel v1.16 -- written in the Mo language\n");
    print("no libc, no syscalls: direct VGA + port I/O\n");
    print("type 'help' then Enter. Ctrl-Alt-Del to reboot.\n");
    print("\nmo> ");

    while 1 {
        TICKS = TICKS + 1;
        let sc: i64 = kbd_poll();
        if sc > 0 {
            # 只处理按下（最高位为 1 是松开）
            if (sc & 128) == 0 {
                if sc == 28 {                     # Enter
                    print("\n");
                    do_cmd();
                    CUR = 0;
                    store8(&LINE, 0);
                    print("\nmo> ");
                } else {
                    if sc == 14 {                 # Backspace
                        if CUR > 0 {
                            CUR = CUR - 1;
                            store8(&LINE + CUR, 0);
                            print("\b \b");
                        }
                    } else {
                        let c: i64 = sc_to_ascii(sc);
                        if c > 0 {
                            if CUR < 120 {
                                store8(&LINE + CUR, c);
                                store8(&LINE + CUR + 1, 0);
                                CUR = CUR + 1;
                                # 回显
                                let one: [2] byte = 0;
                                store8(&one, c);
                                print(&one);
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}
