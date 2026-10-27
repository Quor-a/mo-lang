#!/bin/bash
# pkgserver —— 把墨语言程序打成"服务器软件包"
#
#   bash tools/pkgserver.sh app.mo <服务名> [--deb] [--rpm] [--systemd] [--docker]
#
# 产出（默认全出）：
#   dist/<服务名>/usr/bin/<服务名>         原生 x86-64 ELF
#   dist/<服务名>/lib/systemd/system/*.service
#   dist/<服务名>/DEBIAN/control           dpkg-deb 可直接打包
#   dist/<服务名>/*.spec                   rpmbuild 可直接打包
#   dist/<服务名>/Dockerfile               容器镜像
#
# 为什么做这个：一门语言要能"写服务器软件"，不只是能跑起来，
# 还得能**交付** —— 装成服务、能被包管理器管起来、能进容器。
set +e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=${1:-examples/httpd.mo}
SVC=${2:-moapp}
VER=${VER:-1.0.0}
DO_ALL=1; DO_DEB=0; DO_RPM=0; DO_SYS=0; DO_DOCK=0
for a in "$@"; do
  case "$a" in
    --deb) DO_ALL=0; DO_DEB=1;; --rpm) DO_ALL=0; DO_RPM=1;;
    --systemd) DO_ALL=0; DO_SYS=1;; --docker) DO_ALL=0; DO_DOCK=1;;
  esac
done
[ $DO_ALL -eq 1 ] && { DO_DEB=1; DO_RPM=1; DO_SYS=1; DO_DOCK=1; }

[ -f "$SRC" ] || { echo "找不到源文件: $SRC"; exit 2; }
D=$ROOT/dist/$SVC
rm -rf $D; mkdir -p $D/usr/bin $D/lib/systemd/system

# 1) 原生编译
W=/tmp/mosrv; rm -rf $W; mkdir -p $W/lib
cp $ROOT/lib/*.mo $W/lib/ 2>/dev/null
cp "$SRC" $W/test.mo
( cd $W && $ROOT/bin/moc >/dev/null 2>&1 )
[ -x $W/out.elf ] || { echo "编译失败"; exit 1; }
cp $W/out.elf $D/usr/bin/$SVC
chmod +x $D/usr/bin/$SVC

# 2) systemd unit
if [ $DO_SYS -eq 1 ]; then
cat > $D/lib/systemd/system/${SVC}.service <<UNIT
[Unit]
Description=$SVC (built with the Mo language)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/$SVC
Restart=on-failure
RestartSec=3
# 墨语言程序静态链接、不依赖 libc，攻击面小：直接给最小权限
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT
fi

# 3) deb
if [ $DO_DEB -eq 1 ]; then
mkdir -p $D/DEBIAN
cat > $D/DEBIAN/control <<CTRL
Package: $SVC
Version: $VER
Section: net
Priority: optional
Architecture: amd64
Maintainer: mo <mo@localhost>
Description: $SVC, built with the Mo language
 A native service compiled from Mo source. Statically linked, no libc.
CTRL
cat > $D/DEBIAN/postinst <<'PI'
#!/bin/sh
set -e
systemctl daemon-reload || true
exit 0
PI
chmod +x $D/DEBIAN/postinst
fi

# 4) rpm spec
if [ $DO_RPM -eq 1 ]; then
cat > $D/${SVC}.spec <<SPEC
Name:       $SVC
Version:    $VER
Release:    1
Summary:    $SVC built with the Mo language
License:    MIT
BuildArch:  x86_64

%description
A native service compiled from Mo source. Statically linked, no libc.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/lib/systemd/system
install -m 755 $SVC %{buildroot}/usr/bin/$SVC

%files
/usr/bin/$SVC

%changelog
* $(date +'%a %b %d %Y') mo <mo@localhost> - $VER-1
- initial package
SPEC
fi

# 5) Docker
if [ $DO_DOCK -eq 1 ]; then
cat > $D/Dockerfile <<DOC
FROM scratch
# 墨语言产物是静态 ELF、不依赖 libc —— 所以 FROM scratch 就行，
# 镜像里除了这一个二进制什么都没有。
COPY usr/bin/$SVC /$SVC
EXPOSE 8080
ENTRYPOINT ["/$SVC"]
DOC
fi

echo "pkgserver: dist/$SVC"
find $D -type f | sed "s|$D|  |" | sort
echo
echo "  安装: sudo cp -r dist/$SVC/* /"
echo "  打包: dpkg-deb --build dist/$SVC ${SVC}_${VER}_amd64.deb"
echo "  容器: docker build -t $SVC dist/$SVC"
