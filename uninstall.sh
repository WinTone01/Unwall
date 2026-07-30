#!/usr/bin/env bash
# Zapret Linux Türkiye kaldırma betiği
#
# Varsayılan olarak HER ŞEYİ siler: servis, nftables kuralları, şifreli DNS
# yapılandırması, program dosyaları, ayarlar, listeler, derlenmiş motorlar,
# kaynak ağacı ve günlükler.
#
#   sudo ./uninstall.sh                # sor ve tamamen kaldır
#   sudo ./uninstall.sh --yes          # sormadan tamamen kaldır
#   sudo ./uninstall.sh --keep-config  # ayarları ve listeleri koru
#   sudo ./uninstall.sh --purge-deps   # dnscrypt-proxy paketini de kaldır
#
set -euo pipefail

ETCDIR="/etc/zapret-turkey"
OPTDIR="/opt/zapret-turkey"
LOGDIR="/var/log/zapret-turkey"
RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/90-zapret-turkey.conf"
DNSCRYPT_CONF="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
DNSCRYPT_BAK="/etc/dnscrypt-proxy/dnscrypt-proxy.toml.zapret-turkey.bak"

ASSUME_YES=0
KEEP_CONFIG=0
PURGE_DEPS=0

for arg in "$@"; do
	case "$arg" in
	--yes|-y)      ASSUME_YES=1 ;;
	--keep-config) KEEP_CONFIG=1 ;;
	--purge-deps)  PURGE_DEPS=1 ;;
	--purge)       ASSUME_YES=1 ;;   # eski isim, artık varsayılan davranış
	-h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
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

# Betik hem /usr/local hem /usr önekine kurulmuş olabilir (install.sh ve
# PKGBUILD farklı yerlere koyar); ikisini de süpürüyoruz.
PREFIXES="/usr/local /usr"

# --- ne silineceğini göster ---
step "kaldırılacaklar"
note "servis        : zapret-turkey.service (durdurulur, devre dışı bırakılır)"
note "ağ kuralları  : nftables tablosu zapret_turkey"
note "şifreli DNS   : $RESOLVED_DROPIN ve dnscrypt-proxy yapılandırması geri alınır"
note "program       : {/usr,/usr/local}/bin/zapret-turkey{,ctl}, lib, polkit, .desktop, ikon"
if [ "$KEEP_CONFIG" = 1 ]; then
	note "ayarlar       : KORUNUYOR ($ETCDIR)"
else
	note "ayarlar       : $ETCDIR (config, hostlist, excludelist, autohostlist)"
fi
note "motorlar      : $OPTDIR (derlenmiş ikililer ve kaynak ağacı)"
note "günlükler     : $LOGDIR"
[ "$PURGE_DEPS" = 1 ] && note "paketler      : dnscrypt-proxy"

if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
	printf '\n    Devam edilsin mi? [e/H] '
	read -r ans || ans=""
	case "$ans" in
	e|E|y|Y|evet|yes) ;;
	*) echo "    vazgeçildi"; exit 0 ;;
	esac
fi

# --- 1. servis ve ağ kuralları ---
step "servis durduruluyor"
systemctl disable --now zapret-turkey.service >/dev/null 2>&1 || true
systemctl reset-failed zapret-turkey.service >/dev/null 2>&1 || true

# kuralları doğrudan kaldır (ctl'ye ihtiyaç yok, zaten root'uz)
nft delete table ip zapret_turkey 2>/dev/null || true
nft delete table inet zapret_turkey 2>/dev/null || true

# bu kurulumdan kalan motor süreçleri
for pid in $(pgrep -f "$OPTDIR/(engines|src)/.*/nfqws" 2>/dev/null || true); do
	note "süreç sonlandırılıyor: $pid"
	kill "$pid" 2>/dev/null || true
done

# --- 2. şifreli DNS ---
step "şifreli DNS ayarları geri alınıyor"
if [ -f "$RESOLVED_DROPIN" ]; then
	rm -f "$RESOLVED_DROPIN"
	note "silindi: $RESOLVED_DROPIN"
fi
rmdir /etc/systemd/resolved.conf.d 2>/dev/null || true

if [ -f "$DNSCRYPT_BAK" ]; then
	mv -f "$DNSCRYPT_BAK" "$DNSCRYPT_CONF"
	note "dnscrypt-proxy yapılandırması geri yüklendi"
	systemctl try-restart dnscrypt-proxy >/dev/null 2>&1 || true
elif [ -f "$DNSCRYPT_CONF" ] && grep -qs "zapret-turkey" "$DNSCRYPT_CONF"; then
	# yedek yok ama dosya bize aitse bırakmayalım
	rm -f "$DNSCRYPT_CONF"
	systemctl disable --now dnscrypt-proxy >/dev/null 2>&1 || true
	note "bize ait dnscrypt-proxy yapılandırması silindi (yedek yoktu)"
fi

systemctl restart systemd-resolved >/dev/null 2>&1 || true
resolvectl flush-caches >/dev/null 2>&1 || true

# --- 3. program dosyaları ---
step "program dosyaları siliniyor"
for p in $PREFIXES; do
	rm -f  "$p/bin/zapret-turkeyctl" "$p/bin/zapret-turkey"
	rm -rf "$p/lib/zapret-turkey"
done
rm -f /etc/systemd/system/zapret-turkey.service
rm -f /usr/lib/systemd/system/zapret-turkey.service
rm -f /usr/share/polkit-1/actions/org.zapret.turkey.policy
rm -f /usr/share/applications/org.zapret.turkey.desktop
rm -f /usr/share/applications/zapret-turkey.desktop
rm -f /usr/share/icons/hicolor/scalable/apps/zapret-turkey.svg
rm -f /etc/modules-load.d/zapret-turkey.conf
rm -f /usr/lib/modules-load.d/zapret-turkey.conf
rm -rf /usr/share/doc/zapret-turkey

systemctl daemon-reload >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
if [ -n "${SUDO_USER:-}" ] && command -v kbuildsycoca6 >/dev/null 2>&1; then
	runuser -u "$SUDO_USER" -- kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

# --- 4. veri ---
step "veri siliniyor"
if [ "$KEEP_CONFIG" = 1 ]; then
	note "ayarlar korundu: $ETCDIR"
else
	rm -rf "$ETCDIR"
	note "silindi: $ETCDIR"
fi
rm -rf "$OPTDIR"
note "silindi: $OPTDIR (motorlar ve kaynak ağacı)"
rm -rf "$LOGDIR"
note "silindi: $LOGDIR"

# --- 5. isteğe bağlı paketler ---
if [ "$PURGE_DEPS" = 1 ]; then
	step "dnscrypt-proxy kaldırılıyor"
	if command -v pacman >/dev/null 2>&1; then
		pacman -Rns --noconfirm dnscrypt-proxy || note "kaldırılamadı (başka paketler bağımlı olabilir)"
	elif command -v apt-get >/dev/null 2>&1; then
		apt-get purge -y dnscrypt-proxy || note "kaldırılamadı"
	elif command -v dnf >/dev/null 2>&1; then
		dnf remove -y dnscrypt-proxy || note "kaldırılamadı"
	fi
	note "diğer bağımlılıklar (nftables, gtk4, luajit vb.) sistemde bırakıldı;"
	note "başka paketler onlara ihtiyaç duyabilir."
fi

# --- 6. doğrulama ---
step "kalan iz kontrolü"
leftovers=""
for f in \
	/usr/local/bin/zapret-turkeyctl /usr/bin/zapret-turkeyctl \
	/usr/local/bin/zapret-turkey /usr/bin/zapret-turkey \
	/usr/local/lib/zapret-turkey /usr/lib/zapret-turkey \
	/etc/systemd/system/zapret-turkey.service \
	/usr/lib/systemd/system/zapret-turkey.service \
	/usr/share/polkit-1/actions/org.zapret.turkey.policy \
	/usr/share/applications/org.zapret.turkey.desktop \
	/usr/share/icons/hicolor/scalable/apps/zapret-turkey.svg \
	/etc/modules-load.d/zapret-turkey.conf \
	"$RESOLVED_DROPIN" "$OPTDIR" "$LOGDIR"
do
	[ -e "$f" ] && leftovers="$leftovers $f"
done
[ "$KEEP_CONFIG" = 1 ] || { [ -e "$ETCDIR" ] && leftovers="$leftovers $ETCDIR"; }

if nft list table ip zapret_turkey >/dev/null 2>&1 || nft list table inet zapret_turkey >/dev/null 2>&1; then
	leftovers="$leftovers nftables:zapret_turkey"
fi

if [ -n "$leftovers" ]; then
	note "silinemeyenler:$leftovers"
else
	note "hiçbir iz kalmadı"
fi

cat <<EOF

Kaldırma tamamlandı.

DNS ayarlarınız sistem varsayılanına döndü. Kurulum sırasında kurulan
paketler (nftables, gtk4, python-gobject, luajit ...) sistemde bırakıldı;
gerekmiyorsa paket yöneticinizden kendiniz kaldırabilirsiniz.

EOF
