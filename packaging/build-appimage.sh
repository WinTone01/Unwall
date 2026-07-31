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
# NOT: Bu, yalnızca GTK4 arayüzünü paketler (bkz. AppRun içindeki not).
# unwallctl'in host'ta native olarak kurulu olması hâlâ gerekir.
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

OUT="$SRC/packaging/Unwall-${VERSION}-x86_64.AppImage"
echo "==> paketleniyor: $OUT"
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUT"

echo
echo "Çalıştırmak için:  chmod +x '$OUT' && '$OUT'"
echo "(unwallctl'in host'ta native kurulu olması gerekir: sudo $SRC/install.sh)"
