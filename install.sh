#!/usr/bin/env bash
# Zapret Linux Türkiye kurulumu
#
# Tek komutla her şeyi yapar: paketleri kurar, dosyaları yerleştirir,
# motorları derler, isterseniz şifreli DNS'i açar ve servisi etkinleştirir.
#
#   sudo ./install.sh                 # sorular sorarak tam kurulum
#   sudo ./install.sh --yes           # hiçbir şey sormadan hepsini yap
#   sudo ./install.sh --no-deps       # paket kurulumunu atla
#   sudo ./install.sh --no-build      # motor derlemeyi atla
#   sudo ./install.sh --no-dns        # şifreli DNS'e hiç dokunma
#   sudo ./install.sh --dns=quad9     # şifreli DNS'i bu sağlayıcıyla aç
#   sudo ./install.sh --no-autostart  # servisi etkinleştirme
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

SRC="$(cd "$(dirname "$0")" && pwd)"
CTL="$BINDIR/zapret-turkeyctl"

# --- seçenekler ---
ASSUME_YES=0
DO_DEPS=1
DO_BUILD=1
DO_DNS=ask          # ask | no | <sağlayıcı>
DO_AUTOSTART=ask    # ask | no | yes

for arg in "$@"; do
	case "$arg" in
	--yes|-y)       ASSUME_YES=1 ;;
	--no-deps)      DO_DEPS=0 ;;
	--no-build)     DO_BUILD=0 ;;
	--no-dns)       DO_DNS=no ;;
	--dns)          DO_DNS=cloudflare ;;
	--dns=*)        DO_DNS="${arg#--dns=}" ;;
	--no-autostart) DO_AUTOSTART=no ;;
	--autostart)    DO_AUTOSTART=yes ;;
	-h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
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

install_packages() {
	case "$PKG_MGR" in
	pacman)
		pacman -S --needed --noconfirm \
			nftables iproute2 python-gobject libadwaita gtk4 polkit bind \
			gcc make pkgconf git curl luajit libnetfilter_queue libnfnetlink \
			libmnl zlib dnscrypt-proxy
		;;
	apt-get)
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq
		apt-get install -y --no-install-recommends \
			nftables iproute2 python3-gi gir1.2-adw-1 gir1.2-gtk-4.0 policykit-1 \
			dnsutils build-essential pkg-config git curl libluajit-5.1-dev \
			libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev \
			dnscrypt-proxy
		;;
	dnf)
		dnf install -y \
			nftables iproute python3-gobject libadwaita gtk4 polkit bind-utils \
			gcc make pkgconf git curl luajit-devel libnetfilter_queue-devel \
			libnfnetlink-devel libmnl-devel zlib-devel dnscrypt-proxy
		;;
	zypper)
		zypper --non-interactive install \
			nftables iproute2 python3-gobject libadwaita-1-0 gtk4-tools polkit \
			bind-utils gcc make pkg-config git curl luajit-devel \
			libnetfilter_queue-devel libnfnetlink-devel libmnl-devel zlib-devel \
			dnscrypt-proxy
		;;
	*)
		warn "paket yöneticisi tanınmadı; bağımlılıkları elle kurmanız gerekebilir"
		return 0
		;;
	esac
}

if [ "$DO_DEPS" = 1 ]; then
	step "bağımlılıklar kuruluyor ($PKG_MGR)"
	# dnscrypt-proxy isteğe bağlıdır; deposunda yoksa kurulum durmasın
	if ! install_packages; then
		warn "toplu kurulum başarısız, dnscrypt-proxy olmadan tekrar deneniyor"
		{
			case "$PKG_MGR" in
			pacman)  pacman -S --needed --noconfirm nftables python-gobject libadwaita gtk4 polkit bind gcc make pkgconf git curl luajit libnetfilter_queue libnfnetlink libmnl zlib ;;
			apt-get) apt-get install -y --no-install-recommends nftables python3-gi gir1.2-adw-1 policykit-1 dnsutils build-essential pkg-config git curl libluajit-5.1-dev libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev ;;
			dnf)     dnf install -y nftables python3-gobject libadwaita polkit bind-utils gcc make pkgconf git curl luajit-devel libnetfilter_queue-devel libnfnetlink-devel libmnl-devel zlib-devel ;;
			esac
		} || warn "paket kurulumu tamamlanamadı; aşağıdaki doğrulamaya bakın"
	fi
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

install -d "$DESKTOPDIR"
install -m 0644 "$SRC/share/zapret-turkey.desktop" "$DESKTOPDIR/zapret-turkey.desktop"

systemctl daemon-reload
modprobe nfnetlink_queue 2>/dev/null || true
echo "nfnetlink_queue" > /etc/modules-load.d/zapret-turkey.conf
note "kuruldu: $CTL"

# =====================================================================
# 3. Çakışan kurulum
# =====================================================================

if systemctl is-enabled --quiet zapret.service 2>/dev/null ||
   systemctl is-active --quiet zapret.service 2>/dev/null; then
	step "çakışma saptandı"
	note "sistemde upstream zapret.service etkin. İkisi aynı anda çalışırsa"
	note "NFQUEUE kuralları çakışır."
	if ask_yn "upstream zapret.service durdurulup devre dışı bırakılsın mı?" y; then
		systemctl disable --now zapret.service || true
		note "devre dışı bırakıldı"
	else
		warn "açık bırakıldı; bu projeyi başlatmadan önce kendiniz durdurun"
	fi
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

# =====================================================================
# 5. Şifreli DNS
# =====================================================================

dns_provider=""
case "$DO_DNS" in
no) step "şifreli DNS atlandı (--no-dns)" ;;
ask)
	step "şifreli DNS"
	note "ISS DNS'e müdahale ediyorsa zapret tek başına yetmez."
	note "dnscrypt-proxy varsa DoH (443), yoksa DoT (853) kullanılır."
	ask_yn "şifreli DNS açılsın mı?" y && dns_provider=cloudflare
	;;
*) dns_provider="$DO_DNS" ;;
esac

if [ -n "$dns_provider" ]; then
	step "şifreli DNS açılıyor ($dns_provider)"
	"$CTL" dns enable "$dns_provider" auto || warn "şifreli DNS açılamadı"
fi

# =====================================================================
# 6. Otomatik başlatma
# =====================================================================

start_now=0
case "$DO_AUTOSTART" in
no)  step "servis etkinleştirme atlandı (--no-autostart)" ;;
yes) start_now=1 ;;
ask)
	step "otomatik başlatma"
	note "seçili strateji: $("$CTL" config get STRATEGY) (motor: $("$CTL" config get ENGINE))"
	note "arayüzden istediğiniz zaman değiştirebilirsiniz."
	ask_yn "zapret şimdi başlatılıp açılışta otomatik açılsın mı?" y && start_now=1
	;;
esac

if [ "$start_now" = 1 ]; then
	step "servis etkinleştiriliyor"
	if "$CTL" enable; then
		note "çalışıyor ve açılışta otomatik başlayacak"
	else
		warn "başlatılamadı: journalctl -u zapret-turkey -n 30"
	fi
fi

# =====================================================================

step "durum"
"$CTL" doctor || true

cat <<EOF

Kurulum tamamlandı.

    zapret-turkey                    grafik arayüz (uygulama menüsünde de var)
    sudo zapret-turkeyctl start      motoru başlat
    sudo zapret-turkeyctl blockcheck ISS'niz için strateji ara
    zapret-turkeyctl doctor          ortam teşhisi

Kaldırmak için: sudo ./uninstall.sh   (ayarları da silmek için --purge)

EOF
