#!/usr/bin/env bash
# Unwall AppImage'ını kurar (build eder). Root gerekmez.
#
#   ./packaging/build-appimage.sh
#
# appimagetool sistemde değilse APPIMAGETOOL ile yolunu belirtin:
#   APPIMAGETOOL=/path/to/appimagetool ./packaging/build-appimage.sh
#
# Çıktı: packaging/Unwall-<sürüm>-x86_64.AppImage
#
# NOT: Arayüz GTK4'ü host'tan kullanır (bkz. AppRun içindeki not).
# Backend (unwallctl, systemd birimi) host'ta kurulu değilse arayüz onu
# AppImage'ın içindeki install.sh ile kurmayı önerir.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SRC/bin/unwallctl")"
[ -n "$VERSION" ] || { echo "sürüm bin/unwallctl içinden okunamadı" >&2; exit 1; }

APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
command -v "$APPIMAGETOOL" >/dev/null 2>&1 || {
	echo "appimagetool bulunamadı. İndirin:" >&2
	echo "  curl -fsSL -o appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" >&2
	echo "  chmod +x appimagetool" >&2
	echo "sonra: APPIMAGETOOL=./appimagetool $0" >&2
	exit 1
}

APPDIR="$(mktemp -d)"
trap 'rm -rf "$APPDIR"' EXIT
# mktemp -d dizini 0700 açar; bu, squashfs'in kök dizini olur ve AppImage
# başka bir kullanıcı (ya da firejail) altında açıldığında AppRun'a
# ulaşılamaz ("Permission denied"). Kökü herkes okuyabilsin.
chmod 0755 "$APPDIR"

echo "==> $VERSION için AppDir hazırlanıyor: $APPDIR"

install -d "$APPDIR/usr/bin" "$APPDIR/usr/lib/unwall" \
	"$APPDIR/usr/share/applications" \
	"$APPDIR/usr/share/icons/hicolor/scalable/apps" \
	"$APPDIR/usr/share/metainfo"

install -m 0755 "$SRC/packaging/appimage/AppRun" "$APPDIR/AppRun"

install -m 0644 "$SRC/gui/unwall_gui.py" "$APPDIR/usr/lib/unwall/unwall_gui.py"

# unwallctl'i de taşıyoruz: AppImage'ı native kurulum olmadan, elle bir
# yere koyup UW_CTL ile göstererek de kullanmak isteyenler için (varsayılan
# davranış hâlâ host PATH'indeki unwallctl'i bulmaktır).
install -m 0755 "$SRC/bin/unwallctl" "$APPDIR/usr/bin/unwallctl"

install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.desktop" \
	"$APPDIR/usr/share/applications/io.github.WinTone01.Unwall.desktop"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.desktop" \
	"$APPDIR/io.github.WinTone01.Unwall.desktop"

install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.svg" \
	"$APPDIR/usr/share/icons/hicolor/scalable/apps/io.github.WinTone01.Unwall.svg"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.svg" \
	"$APPDIR/io.github.WinTone01.Unwall.svg"
ln -sf io.github.WinTone01.Unwall.svg "$APPDIR/.DirIcon"

install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.metainfo.xml" \
	"$APPDIR/usr/share/metainfo/io.github.WinTone01.Unwall.metainfo.xml"

# Backend kurulumu: install.sh ve kurduğu dosyalar, kaynak ağacındaki
# yerleriyle. Arayüz backend'i bulamazsa bunları geçici bir dizine
# kopyalayıp install.sh'i pkexec ile oradan çalıştırır (bkz.
# _on_install_backend in gui/unwall_gui.py).
BACKEND="$APPDIR/usr/share/unwall/backend"
for f in install.sh uninstall.sh bin/unwallctl bin/unwall packaging/nm-dispatcher/90-unwall; do
	install -Dm 0755 "$SRC/$f" "$BACKEND/$f"
done
for f in gui/unwall_gui.py lib/strategies.conf etc/unwall.conf \
	hostlist.txt excludelist.txt autohostlist.txt \
	systemd/unwall.service systemd/unwall-verify.service systemd/unwall-verify.timer \
	systemd/unwall-watchdog.service systemd/unwall-watchdog.timer \
	polkit/io.github.WinTone01.Unwall.policy \
	share/io.github.WinTone01.Unwall.desktop share/io.github.WinTone01.Unwall.svg; do
	install -Dm 0644 "$SRC/$f" "$BACKEND/$f"
done

OUT="$SRC/packaging/Unwall-${VERSION}-x86_64.AppImage"
echo "==> paketleniyor: $OUT"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUT"

echo
echo "Çalıştırmak için:  chmod +x '$OUT' && '$OUT'"
echo "(backend kurulu değilse arayüz üstteki Kur düğmesiyle kurar)"
