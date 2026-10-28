# mopkgcli —— 包管理器命令行入口（用墨语言自己写的）
#
# 为什么单独放一个入口文件而不是写在 lib/mopkg.mo 里：
#   库被别的文件 import 时也会带上 main，两个 main 会冲突。
#   库只提供 pkg_dispatch，可执行入口单独一层。
#
# 这一个是「自包含生态」的关键一步：包管理器此前是 shell+awk+python3
# 写的，属于"借别人的手"。现在它由墨语言写成、由墨语言编译器编译。
import "mopkg.mo";
import "aio.mo";
import "csp.mo";
import "io.mo";
import "str.mo";

fn mopkg_usage() -> i64 {
    print("mopkg —— 墨语言包管理器（墨语言实现）\n");
    print("\n");
    print("用法: mopkg <命令>\n");
    print("\n");
    print("  list     列出 mo.lock 里锁定的包\n");
    print("  tree     显示依赖树（含循环检测）\n");
    print("  verify   校验 mo.lock 与 mo.toml 一致且可复现\n");
    print("  fetch    按 mo.toml 拉取全部依赖\n");
    print("  pack     打包目录为 .mo.tar.gz\n");
    print("  remove   删除已安装的包\n");
    print("  update   更新包到最新 commit\n");
    print("  hex      十六进制转储文件（xxd 风格）\n");
    print("  rev      字节反转文件并写回\n");
    print("  base64   base64 编码/解码（--decode 解码）\n");
    print("  cmp      比较两个文件（首个不同偏移）\n");
    print("  sha256   输出文件 sha256 校验和\n");
    print("  wc       行数/词数/字节数统计\n");
    print("  size     文件大小（B/KB/MB 可读格式）\n");
    print("  head     显示文件前 n 行（默认 10）\n");
    print("  tail     显示文件末尾 n 行（默认 10）\n");
    print("  cat      输出文件全部内容\n");
    print("  cp       复制文件 <src> <dst>\n");
    print("  mv       移动文件 <src> <dst>\n");
    print("  touch    创建空文件（存在则更新时间）\n");
    print("  rm       删除文件\n");
    print("\n");
    return 2;
}

var MRC: i64 = 0;
var MDONE: i64 = 0;
var MCMD: [64] byte = 0;

fn disp_csp() -> i64 {
    MRC = pkg_dispatch(&MCMD);
    MDONE = 1;
    return 0;
}

fn main() -> i64 {
    if argc() < 2 { return mopkg_usage(); }
    let cmd: i64 = argv(1);
    if streq(cmd, "-h") == 1 { return mopkg_usage(); }
    if streq(cmd, "--help") == 1 { return mopkg_usage(); }
    if streq(cmd, "help") == 1 { return mopkg_usage(); }
    # 网络命令走 aio 协程（fetch/publish http=/search http=）；先探测 arg 里的 http://
    let net: i64 = 0;
    let ai: i64 = 2;
    while ai < argc() {
        if strstr(argv(ai), "http://") == 0 {
            # v1.255/256:publish/search 走同步 httpcli,不进 aio 上下文
            if streq(cmd, "publish") != 1 { if streq(cmd, "search") != 1 { if streq(cmd, "remove") != 1 { if streq(cmd, "fetch") != 1 { net = 1; } } } }
        }
        ai = ai + 1;
    }
    if net == 1 {
        PKG_AIO = 1;   # v1.217：aio 路径全链验收通过（publish/search/fetch）
        strcpy(&MCMD, cmd);
        heap_init();
        net_nosigpipe();
        aio_init();
        csp_init(2);
        csp_go(&disp_csp, 0);
        let waitn: i64 = 0;
        while MDONE < 1 && waitn < 600 {
            usleep(50000);
            waitn = waitn + 1;
        }
        aio_stop();
        if MDONE < 1 { print("mopkg: aio 超时\n"); return 3; }
        return MRC;
    }
    return pkg_dispatch(cmd);
}
