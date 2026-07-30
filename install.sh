#!/usr/bin/env bash
# Zapret Linux Türkiye kurulumu
#
# Yalnızca uygulamayı kurar: paketleri kurar, dosyaları yerleştirir ve
# motorları derler. Hiçbir servisi başlatmaz, hiçbir sistem ayarını
# (DNS, otomatik başlatma, ağ kuralları) değiştirmez -- bunların hepsi
# grafik arayüzden yapılır.
#
#   sudo ./install.sh                 # kur
#   sudo ./install.sh --yes           # soru sormadan kur
#   sudo ./install.sh --no-deps       # paket kurulumunu atla
#   sudo ./install.sh --no-build      # motor derlemeyi atla
#   sudo PREFIX=/usr ./install.sh     # farklı önek
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
ICONDIR="/usr/share/icons/hicolor/scalable/apps"

SRC="$(cd "$(dirname "$0")" && pwd)"
CTL="$BINDIR/zapret-turkeyctl"

# --- seçenekler ---
ASSUME_YES=0
DO_DEPS=1
DO_BUILD=1

for arg in "$@"; do
	case "$arg" in
	--yes|-y)       ASSUME_YES=1 ;;
	--no-deps)      DO_DEPS=0 ;;
	--no-build)     DO_BUILD=0 ;;
	-h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
	*) echo "bilinmeyen seçenek: $arg" >&2; exit 1 ;;
	esac
done

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştırın: sudo ./install.sh" >&2; exit 1; }

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    uyarı: %s\n' "$*" >&2; }

ask_yn() { # soru, varsayılan(y/n)
	local q="$1" def="${2:-y}" ans
	if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
		[ "$def" = y ]
		return
	fi
	printf '    %s [%s] ' "$q" "$([ "$def" = y ] && echo 'E/h' || echo 'e/H')"
	read -r ans || ans=""
	case "${ans:-$def}" in
	e|E|y|Y|evet|yes) return 0 ;;
	*) return 1 ;;
	esac
}

# =====================================================================
# 1. Paketler
# =====================================================================

PKG_MGR=""
for m in pacman apt-get dnf zypper; do
	command -v "$m" >/dev/null 2>&1 && { PKG_MGR="$m"; break; }
done

# Paketleri tek tek kurar: biri deposunda yoksa ya da çakışırsa diğerleri
# yine de kurulur (toplu işlem tek bir çakışmada tamamen düşerdi).
pkg_install_each() {
	local p rc=0
	for p in "$@"; do
		case "$PKG_MGR" in
		pacman)  pacman -S --needed --noconfirm "$p" ;;
		apt-get) apt-get install -y --no-install-recommends "$p" ;;
		dnf)     dnf install -y "$p" ;;
		zypper)  zypper --non-interactive install "$p" ;;
		esac || { warn "kurulamadı, atlanıyor: $p"; rc=1; }
	done
	return $rc
}

install_packages() {
	local todo=()
	case "$PKG_MGR" in
	pacman)
		todo=(nftables iproute2 python-gobject libadwaita gtk4 polkit bind
		      gcc make pkgconf git curl luajit libnetfilter_queue libnfnetlink
		      libmnl zlib dnscrypt-proxy)
		# Zaten sağlanmış olanları listeden düşür. pacman -T "provides"
		# ilişkisini de görür: örn. zlib'i zlib-ng-compat sağlıyorsa zlib
		# istenmez ve çakışma hiç doğmaz.
		mapfile -t todo < <(pacman -T "${todo[@]}" 2>/dev/null || true)
		;;
	apt-get)
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq || warn "apt-get update başarısız"
		todo=(nftables iproute2 python3-gi gir1.2-adw-1 gir1.2-gtk-4.0 policykit-1
		      dnsutils build-essential pkg-config git curl libluajit-5.1-dev
		      libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev
		      dnscrypt-proxy)
		;;
	dnf)
		todo=(nftables iproute python3-gobject libadwaita gtk4 polkit bind-utils
		      gcc make pkgconf git curl luajit-devel libnetfilter_queue-devel
		      libnfnetlink-devel libmnl-devel zlib-devel dnscrypt-proxy)
		;;
	zypper)
		todo=(nftables iproute2 python3-gobject libadwaita-1-0 gtk4-tools polkit
		      bind-utils gcc make pkg-config git curl luajit-devel
		      libnetfilter_queue-devel libnfnetlink-devel libmnl-devel zlib-devel
		      dnscrypt-proxy)
		;;
	*)
		warn "paket yöneticisi tanınmadı; bağımlılıkları elle kurmanız gerekebilir"
		return 0
		;;
	esac

	if [ "${#todo[@]}" -eq 0 ]; then
		note "gerekli paketlerin tamamı zaten kurulu"
		return 0
	fi
	note "kurulacak: ${todo[*]}"
	pkg_install_each "${todo[@]}"
}

if [ "$DO_DEPS" = 1 ]; then
	step "bağımlılıklar kuruluyor ($PKG_MGR)"
	install_packages || warn "bazı paketler kurulamadı; aşağıdaki doğrulamaya bakın"
else
	step "bağımlılık kurulumu atlandı (--no-deps)"
fi

step "ortam doğrulanıyor"
missing=""
for c in nft systemctl python3 git make cc pkexec curl; do
	command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
python3 -c "import gi; gi.require_version('Adw','1')" 2>/dev/null \
	|| missing="$missing python-gobject/libadwaita"
if [ -n "$missing" ]; then
	warn "hâlâ eksik:$missing"
	warn "kurulum sürüyor, ama bu bileşenler olmadan program çalışmayabilir"
else
	note "tüm bileşenler yerinde"
fi

# =====================================================================
# 2. Dosyalar
# =====================================================================

step "dosyalar kopyalanıyor"
install -d "$BINDIR" "$LIBDIR" "$ETCDIR" "$OPTDIR" "$LOGDIR"

install -m 0755 "$SRC/bin/zapret-turkeyctl" "$CTL"
sed -i \
	-e "s|^ZT_LIB=.*|ZT_LIB=\"\${ZT_LIB:-$LIBDIR}\"|" \
	-e "s|^ZT_ETC=.*|ZT_ETC=\"\${ZT_ETC:-$ETCDIR}\"|" \
	-e "s|^ZT_OPT=.*|ZT_OPT=\"\${ZT_OPT:-$OPTDIR}\"|" \
	-e "s|^ZT_LOG=.*|ZT_LOG=\"\${ZT_LOG:-$LOGDIR}\"|" \
	"$CTL"

install -m 0755 "$SRC/bin/zapret-turkey" "$BINDIR/zapret-turkey"
sed -i "s|^ZT_LIB=.*|ZT_LIB=\"\${ZT_LIB:-$LIBDIR}\"|" "$BINDIR/zapret-turkey"

install -m 0644 "$SRC/gui/zapret_turkey_gui.py" "$LIBDIR/zapret_turkey_gui.py"
install -m 0644 "$SRC/lib/strategies.conf" "$LIBDIR/strategies.conf"

if [ -f "$ETCDIR/zapret-turkey.conf" ]; then
	note "mevcut config korunuyor: $ETCDIR/zapret-turkey.conf"
	install -m 0644 "$SRC/etc/zapret-turkey.conf" "$ETCDIR/zapret-turkey.conf.new"
else
	install -m 0644 "$SRC/etc/zapret-turkey.conf" "$ETCDIR/zapret-turkey.conf"
fi
for f in hostlist.txt excludelist.txt autohostlist.txt; do
	if [ -f "$ETCDIR/$f" ]; then
		note "mevcut $f korunuyor"
	else
		install -m 0644 "$SRC/$f" "$ETCDIR/$f"
	fi
done

sed -e "s|@BINDIR@|$BINDIR|g" -e "s|@ETCDIR@|$ETCDIR|g" -e "s|@LOGDIR@|$LOGDIR|g" \
	"$SRC/systemd/zapret-turkey.service" > "$UNITDIR/zapret-turkey.service"
chmod 0644 "$UNITDIR/zapret-turkey.service"

install -d "$POLKITDIR"
sed -e "s|@BINDIR@|$BINDIR|g" \
	"$SRC/polkit/org.zapret.turkey.policy" > "$POLKITDIR/org.zapret.turkey.policy"
chmod 0644 "$POLKITDIR/org.zapret.turkey.policy"

# Uygulama menüsü girdisi ve ikon (KDE/GNOME ortak hicolor teması)
install -d "$DESKTOPDIR" "$ICONDIR"
install -m 0644 "$SRC/share/org.zapret.turkey.desktop" "$DESKTOPDIR/org.zapret.turkey.desktop"
install -m 0644 "$SRC/share/zapret-turkey.svg" "$ICONDIR/zapret-turkey.svg"
# eski isimle kurulmuş girdi kaldıysa temizle
rm -f "$DESKTOPDIR/zapret-turkey.desktop"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$DESKTOPDIR" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
# KDE'nin menü önbelleği: kullanıcının oturumunda yenilensin
if [ -n "${SUDO_USER:-}" ] && command -v kbuildsycoca6 >/dev/null 2>&1; then
	runuser -u "$SUDO_USER" -- kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
elif [ -n "${SUDO_USER:-}" ] && command -v kbuildsycoca5 >/dev/null 2>&1; then
	runuser -u "$SUDO_USER" -- kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
fi

systemctl daemon-reload || true
modprobe nfnetlink_queue 2>/dev/null || true
echo "nfnetlink_queue" > /etc/modules-load.d/zapret-turkey.conf
note "kuruldu: $CTL"
note "uygulama menüsüne eklendi: Zapret Türkiye"

# =====================================================================
# 3. Çakışan kurulum
# =====================================================================

if systemctl is-enabled --quiet zapret.service 2>/dev/null ||
   systemctl is-active --quiet zapret.service 2>/dev/null; then
	step "çakışma saptandı"
	note "sistemde upstream zapret.service etkin. İkisi aynı anda çalışırsa"
	note "NFQUEUE kuralları çakışır."
	note "Arayüzdeki uyarı çubuğundaki 'Kapat' düğmesiyle ya da şu komutla"
	note "kapatabilirsiniz:  sudo zapret-turkeyctl disable-conflicts"
fi

# =====================================================================
# 4. Motorlar
# =====================================================================

if [ "$DO_BUILD" = 1 ]; then
	step "motorlar derleniyor (internet gerekir, birkaç dakika sürebilir)"
	if "$CTL" build all; then
		note "motorlar hazır"
	else
		warn "derleme başarısız oldu; 'sudo zapret-turkeyctl build' ile tekrar deneyin"
	fi
else
	step "motor derlemesi atlandı (--no-build)"
fi

step "durum"
"$CTL" doctor || true

cat <<EOF

Kurulum tamamlandı. Hiçbir servis başlatılmadı, sistem ayarlarınıza
dokunulmadı.

Buradan sonrası arayüzden: uygulama menüsünde "Zapret Türkiye"
(Ağ / Internet kategorisi) ya da terminalden:

    zapret-turkey

Arayüzden strateji seçip başlatabilir, şifreli DNS'i açabilir, açılışta
otomatik başlatmayı etkinleştirebilirsiniz.

Kaldırmak için: sudo ./uninstall.sh   (ayarları da silmek için --purge)

EOF
