#!/usr/bin/env bash
# Zapret Linux Türkiye kaldırma betiği
#
#   sudo ./uninstall.sh          -> program dosyalarını siler, ayarları bırakır
#   sudo ./uninstall.sh --purge  -> ayarları ve derlenmiş motorları da siler
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BINDIR="$PREFIX/bin"
LIBDIR="$PREFIX/lib/zapret-turkey"
ETCDIR="/etc/zapret-turkey"
OPTDIR="/opt/zapret-turkey"
LOGDIR="/var/log/zapret-turkey"

[ "$(id -u)" -eq 0 ] || { echo "root olarak çalıştırın" >&2; exit 1; }

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

echo "==> servis durduruluyor"
systemctl disable --now zapret-turkey.service 2>/dev/null || true
"$BINDIR/zapret-turkeyctl" nft-flush 2>/dev/null || true

echo "==> şifreli DNS ayarları geri alınıyor"
"$BINDIR/zapret-turkeyctl" dns disable 2>/dev/null || true

echo "==> dosyalar siliniyor"
rm -f "$BINDIR/zapret-turkeyctl" "$BINDIR/zapret-turkey"
rm -rf "$LIBDIR"
rm -f /etc/systemd/system/zapret-turkey.service
rm -f /usr/share/polkit-1/actions/org.zapret.turkey.policy
rm -f /usr/share/applications/zapret-turkey.desktop
rm -f /etc/modules-load.d/zapret-turkey.conf
systemctl daemon-reload

if [ "$PURGE" = 1 ]; then
	echo "==> ayarlar ve motorlar siliniyor"
	rm -rf "$ETCDIR" "$OPTDIR" "$LOGDIR"
else
	echo "    ayarlar korundu: $ETCDIR"
	echo "    motorlar korundu: $OPTDIR"
fi

echo "Kaldırma tamam."
