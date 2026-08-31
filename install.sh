#!/usr/bin/env bash
# Unwall kurulumu / installation
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
LIBDIR="$PREFIX/lib/unwall"
ETCDIR="/etc/unwall"
OPTDIR="/opt/unwall"
LOGDIR="/var/log/unwall"
UNITDIR="/etc/systemd/system"
POLKITDIR="/usr/share/polkit-1/actions"
DESKTOPDIR="/usr/share/applications"
ICONDIR="/usr/share/icons/hicolor/scalable/apps"

SRC="$(cd "$(dirname "$0")" && pwd)"
CTL="$BINDIR/unwallctl"

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

# Tek yetki istemi: root değilsek kendimizi bir kez yükseltip aynı
# argümanlarla yeniden çalışıyoruz. Böylece parola bir defa sorulur ve
# bütün adımlar aynı root oturumunda koşar.
if [ "$(id -u)" -ne 0 ]; then
	SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
	if command -v sudo >/dev/null 2>&1; then
		echo "Yönetici yetkisi gerekiyor, parola bir kez sorulacak."
		exec sudo -- "$SELF" "$@"
	elif command -v pkexec >/dev/null 2>&1; then
		exec pkexec "$SELF" "$@"
	fi
	echo "root olarak çalıştırın: sudo $0 $*" >&2
	exit 1
fi

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
		      gcc make pkgconf git curl luajit libcap libnetfilter_queue libnfnetlink
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
		      dnsutils build-essential pkg-config git curl libluajit-5.1-dev libcap-dev
		      libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev
		      dnscrypt-proxy)
		;;
	dnf)
		todo=(nftables iproute python3-gobject libadwaita gtk4 polkit bind-utils
		      gcc make pkgconf git curl luajit-devel libcap-devel libnetfilter_queue-devel
		      libnfnetlink-devel libmnl-devel zlib-devel dnscrypt-proxy)
		;;
	zypper)
		todo=(nftables iproute2 python3-gobject libadwaita-1-0 gtk4-tools polkit
		      bind-utils gcc make pkg-config git curl luajit-devel libcap-devel
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

# =====================================================================
# 1b. Eski kurulumdan taşıma (zapret-turkey -> unwall)
# =====================================================================

LEGACY_ETC="/etc/zapret-turkey"
LEGACY_OPT="/opt/zapret-turkey"

if [ -e "$LEGACY_ETC" ] || [ -e "$LEGACY_OPT" ] ||
   [ -e /etc/systemd/system/zapret-turkey.service ] ||
   [ -x /usr/local/bin/zapret-turkeyctl ] || [ -x /usr/bin/zapret-turkeyctl ]; then
	step "eski kurulum (zapret-turkey) taşınıyor"

	# eski servis ve kuralları kapat
	systemctl disable --now zapret-turkey.service >/dev/null 2>&1 || true
	nft delete table ip zapret_turkey 2>/dev/null || true
	nft delete table inet zapret_turkey 2>/dev/null || true

	# ayarlar ve listeler
	if [ -d "$LEGACY_ETC" ] && [ ! -d "$ETCDIR" ]; then
		mv "$LEGACY_ETC" "$ETCDIR"
		[ -f "$ETCDIR/zapret-turkey.conf" ] && mv "$ETCDIR/zapret-turkey.conf" "$ETCDIR/unwall.conf"
		note "ayarlar taşındı: $LEGACY_ETC -> $ETCDIR"
	fi

	# derlenmiş motorlar ve kaynak ağacı (yeniden derlemeye gerek kalmasın)
	if [ -d "$LEGACY_OPT" ] && [ ! -d "$OPTDIR" ]; then
		mv "$LEGACY_OPT" "$OPTDIR"
		note "motorlar taşındı: $LEGACY_OPT -> $OPTDIR"
	fi

	# eski program dosyaları
	rm -f /usr/local/bin/zapret-turkeyctl /usr/bin/zapret-turkeyctl \
	      /usr/local/bin/zapret-turkey /usr/bin/zapret-turkey
	rm -rf /usr/local/lib/zapret-turkey /usr/lib/zapret-turkey
	rm -f /etc/systemd/system/zapret-turkey.service /usr/lib/systemd/system/zapret-turkey.service
	rm -f /usr/share/polkit-1/actions/org.zapret.turkey.policy
	rm -f /usr/share/applications/org.zapret.turkey.desktop /usr/share/applications/zapret-turkey.desktop
	rm -f /usr/share/icons/hicolor/scalable/apps/zapret-turkey.svg
	rm -f /etc/modules-load.d/zapret-turkey.conf
	rm -rf /var/log/zapret-turkey
	systemctl daemon-reload >/dev/null 2>&1 || true

	# şifreli DNS drop-in'i yeni adla yaz
	if [ -f /etc/systemd/resolved.conf.d/90-zapret-turkey.conf ]; then
		mv /etc/systemd/resolved.conf.d/90-zapret-turkey.conf \
		   /etc/systemd/resolved.conf.d/90-unwall.conf
		sed -i 's/zapret-turkey/unwall/g' /etc/systemd/resolved.conf.d/90-unwall.conf
		note "şifreli DNS ayarı korundu"
	fi
	if [ -f /etc/dnscrypt-proxy/dnscrypt-proxy.toml.zapret-turkey.bak ]; then
		mv /etc/dnscrypt-proxy/dnscrypt-proxy.toml.zapret-turkey.bak \
		   /etc/dnscrypt-proxy/dnscrypt-proxy.toml.unwall.bak
	fi

	note "taşıma tamam; servisi arayüzden yeniden etkinleştirin"
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
# Ağ geçidi modunda unwall.service, systemd-resolved'e LAN adresinde
# ikinci bir stub dinleyicisi açtırmak için buraya bir drop-in yazıyor
# (bkz. ensure_resolved_lan_stub() in bin/unwallctl). Servis
# ProtectSystem=strict altında çalıştığından dizinin ÖNCEDEN var olması
# gerekiyor: ReadWritePaths olmayan bir yolu sessizce atlar.
install -d /etc/systemd/resolved.conf.d

# unwallctl'i doğrudan $CTL üzerine yazmıyoruz: `unwallctl self-update` bu
# betiği tam olarak $CTL'den (hâlâ çalışan bir bash sürecinden) çağırıyor.
# `install`/`cp` hedefi yerinde kesip yeniden yazdığından, kendi kendini
# güncelleyen bir süreç için bu, dosyayı çalışırken bozuk offset'lerle
# okumasına yol açar ("unbound variable" gibi anlamsız hatalar). Aynı
# dizinde geçici bir dosyaya yazıp atomik `mv` ile yerine koyuyoruz; bu
# şekilde hâlâ çalışan eski süreç eski inode'u okumaya devam eder.
CTL_TMP="$(mktemp "$BINDIR/.unwallctl.XXXXXX")"
install -m 0755 "$SRC/bin/unwallctl" "$CTL_TMP"
sed -i \
	-e "s|^UW_LIB=.*|UW_LIB=\"\${UW_LIB:-$LIBDIR}\"|" \
	-e "s|^UW_ETC=.*|UW_ETC=\"\${UW_ETC:-$ETCDIR}\"|" \
	-e "s|^UW_OPT=.*|UW_OPT=\"\${UW_OPT:-$OPTDIR}\"|" \
	-e "s|^UW_LOG=.*|UW_LOG=\"\${UW_LOG:-$LOGDIR}\"|" \
	"$CTL_TMP"
mv -f "$CTL_TMP" "$CTL"

install -m 0755 "$SRC/bin/unwall" "$BINDIR/unwall"
sed -i "s|^UW_LIB=.*|UW_LIB=\"\${UW_LIB:-$LIBDIR}\"|" "$BINDIR/unwall"

install -m 0644 "$SRC/gui/unwall_gui.py" "$LIBDIR/unwall_gui.py"
install -m 0644 "$SRC/lib/strategies.conf" "$LIBDIR/strategies.conf"

if [ -f "$ETCDIR/unwall.conf" ]; then
	note "mevcut config korunuyor: $ETCDIR/unwall.conf"
	install -m 0644 "$SRC/etc/unwall.conf" "$ETCDIR/unwall.conf.new"
else
	install -m 0644 "$SRC/etc/unwall.conf" "$ETCDIR/unwall.conf"
fi
for f in hostlist.txt excludelist.txt autohostlist.txt; do
	if [ -f "$ETCDIR/$f" ]; then
		note "mevcut $f korunuyor"
	else
		install -m 0644 "$SRC/$f" "$ETCDIR/$f"
	fi
done

sed -e "s|@BINDIR@|$BINDIR|g" -e "s|@ETCDIR@|$ETCDIR|g" -e "s|@LOGDIR@|$LOGDIR|g" \
	"$SRC/systemd/unwall.service" > "$UNITDIR/unwall.service"
chmod 0644 "$UNITDIR/unwall.service"

install -d "$POLKITDIR"
sed -e "s|@BINDIR@|$BINDIR|g" \
	"$SRC/polkit/io.github.WinTone01.Unwall.policy" > "$POLKITDIR/io.github.WinTone01.Unwall.policy"
chmod 0644 "$POLKITDIR/io.github.WinTone01.Unwall.policy"

# Uygulama menüsü girdisi ve ikon (KDE/GNOME ortak hicolor teması)
install -d "$DESKTOPDIR" "$ICONDIR"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.desktop" "$DESKTOPDIR/io.github.WinTone01.Unwall.desktop"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.svg" "$ICONDIR/io.github.WinTone01.Unwall.svg"
# eski isimle kurulmuş girdi kaldıysa temizle
rm -f "$DESKTOPDIR/unwall.desktop"

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
echo "nfnetlink_queue" > /etc/modules-load.d/unwall.conf
note "kuruldu: $CTL"
note "uygulama menüsüne eklendi: Unwall"

# =====================================================================
# 3. Çakışan kurulum
# =====================================================================

if systemctl is-enabled --quiet zapret.service 2>/dev/null ||
   systemctl is-active --quiet zapret.service 2>/dev/null; then
	step "çakışma saptandı"
	note "sistemde upstream zapret.service etkin. İkisi aynı anda çalışırsa"
	note "NFQUEUE kuralları çakışır."
	note "Arayüzdeki uyarı çubuğundaki 'Kapat' düğmesiyle ya da şu komutla"
	note "kapatabilirsiniz:  sudo unwallctl disable-conflicts"
fi

# =====================================================================
# 4. Motorlar
# =====================================================================

if [ "$DO_BUILD" = 1 ]; then
	step "motorlar derleniyor (internet gerekir, birkaç dakika sürebilir)"
	if "$CTL" build all; then
		note "motorlar hazır"
	else
		warn "derleme başarısız oldu; 'sudo unwallctl build' ile tekrar deneyin"
	fi
else
	step "motor derlemesi atlandı (--no-build)"
fi

step "durum"
"$CTL" doctor || true

cat <<EOF

Kurulum tamamlandı. Hiçbir servis başlatılmadı, sistem ayarlarınıza
dokunulmadı.

Buradan sonrası arayüzden: uygulama menüsünde "Unwall"
(Ağ / Internet kategorisi) ya da terminalden:

    unwall

Arayüzden strateji seçip başlatabilir, şifreli DNS'i açabilir, açılışta
otomatik başlatmayı etkinleştirebilirsiniz.

Kaldırmak için: sudo ./uninstall.sh   (ayarları da silmek için --purge)

EOF
