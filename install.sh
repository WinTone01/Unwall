#!/usr/bin/env bash
# Zapret Linux Türkiye kurulumu
#
#   sudo ./install.sh            -> /usr/local altına kurar
#   sudo PREFIX=/usr ./install.sh
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BINDIR="$PREFIX/bin"
LIBDIR="$PREFIX/lib/zapret-turkey"
ETCDIR="/etc/zapret-turkey"
OPTDIR="/opt/zapret-turkey"
LOGDIR="/var/log/zapret-turkey"
UNITDIR="/etc/systemd/system"
POLKITDIR="/usr/share/polkit-1/actions"
DESKTOPDIR="/usr/share/applications"

SRC="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştırın: sudo ./install.sh" >&2; exit 1; }

echo "==> bağımlılık kontrolü"
missing=""
for c in nft systemctl python3 git make cc pkexec curl; do
	command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
python3 -c "import gi; gi.require_version('Adw','1')" 2>/dev/null || missing="$missing python-gobject/libadwaita"
[ -n "$missing" ] && {
	echo "eksik bağımlılıklar:$missing"
	echo
	echo "  Arch/CachyOS : pacman -S --needed nftables python-gobject libadwaita gtk4 base-devel git curl luajit libnetfilter_queue libnfnetlink libmnl zlib polkit bind"
	echo "  Debian/Ubuntu: apt install nftables python3-gi gir1.2-adw-1 build-essential git curl libluajit-5.1-dev libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev policykit-1 dnsutils"
	echo "  Fedora       : dnf install nftables python3-gobject libadwaita gcc make git curl luajit-devel libnetfilter_queue-devel libnfnetlink-devel libmnl-devel zlib-devel polkit bind-utils"
	echo
	exit 1
}

echo "==> dosyalar kopyalanıyor"
install -d "$BINDIR" "$LIBDIR" "$ETCDIR" "$OPTDIR" "$LOGDIR"

install -m 0755 "$SRC/bin/zapret-turkeyctl" "$BINDIR/zapret-turkeyctl"
sed -i \
	-e "s|^ZT_LIB=.*|ZT_LIB=\"\${ZT_LIB:-$LIBDIR}\"|" \
	-e "s|^ZT_ETC=.*|ZT_ETC=\"\${ZT_ETC:-$ETCDIR}\"|" \
	-e "s|^ZT_OPT=.*|ZT_OPT=\"\${ZT_OPT:-$OPTDIR}\"|" \
	-e "s|^ZT_LOG=.*|ZT_LOG=\"\${ZT_LOG:-$LOGDIR}\"|" \
	"$BINDIR/zapret-turkeyctl"

install -m 0755 "$SRC/bin/zapret-turkey" "$BINDIR/zapret-turkey"
sed -i "s|^ZT_LIB=.*|ZT_LIB=\"\${ZT_LIB:-$LIBDIR}\"|" "$BINDIR/zapret-turkey"

install -m 0644 "$SRC/gui/zapret_turkey_gui.py" "$LIBDIR/zapret_turkey_gui.py"
install -m 0644 "$SRC/lib/strategies.conf" "$LIBDIR/strategies.conf"

echo "==> yapılandırma"
if [ -f "$ETCDIR/zapret-turkey.conf" ]; then
	echo "    mevcut config korunuyor: $ETCDIR/zapret-turkey.conf"
	install -m 0644 "$SRC/etc/zapret-turkey.conf" "$ETCDIR/zapret-turkey.conf.new"
else
	install -m 0644 "$SRC/etc/zapret-turkey.conf" "$ETCDIR/zapret-turkey.conf"
fi
for f in hostlist.txt excludelist.txt autohostlist.txt; do
	if [ -f "$ETCDIR/$f" ]; then
		echo "    mevcut $f korunuyor"
	else
		install -m 0644 "$SRC/$f" "$ETCDIR/$f"
	fi
done

echo "==> systemd / polkit / masaüstü"
sed -e "s|@BINDIR@|$BINDIR|g" -e "s|@ETCDIR@|$ETCDIR|g" -e "s|@LOGDIR@|$LOGDIR|g" \
	"$SRC/systemd/zapret-turkey.service" > "$UNITDIR/zapret-turkey.service"
chmod 0644 "$UNITDIR/zapret-turkey.service"

install -d "$POLKITDIR"
sed -e "s|@BINDIR@|$BINDIR|g" \
	"$SRC/polkit/org.zapret.turkey.policy" > "$POLKITDIR/org.zapret.turkey.policy"
chmod 0644 "$POLKITDIR/org.zapret.turkey.policy"

install -d "$DESKTOPDIR"
install -m 0644 "$SRC/share/zapret-turkey.desktop" "$DESKTOPDIR/zapret-turkey.desktop"

systemctl daemon-reload

echo "==> çekirdek modülleri"
modprobe nfnetlink_queue 2>/dev/null || true
echo "nfnetlink_queue" > /etc/modules-load.d/zapret-turkey.conf

cat <<EOF

Kurulum tamam.

Sıradaki adım — motorları derleyin (internet gerekir):

    sudo zapret-turkeyctl build

Şifreli DNS (isteğe bağlı, DoH için):

    sudo pacman -S dnscrypt-proxy       # ya da apt/dnf karşılığı
    sudo zapret-turkeyctl dns enable cloudflare auto

Sonra:

    zapret-turkey                 # grafik arayüz
    sudo zapret-turkeyctl doctor  # ortam teşhisi
    sudo zapret-turkeyctl start   # motoru başlat

EOF
