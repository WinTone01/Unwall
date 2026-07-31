#!/usr/bin/env bash
# Sürüm için .deb, .rpm ve AppImage'ı build eder, GitHub'da etiket + release
# oluşturur (yoksa) ve dördünü (Flatpak dahil, önceden build edilmişse)
# release asset'i olarak yükler. `gh` ile kimlik doğrulaması yapılmış
# olmalı.
#
#   ./packaging/release.sh
#   APPIMAGETOOL=/path/to/appimagetool ./packaging/release.sh
#
# Flatpak build'i ayrı: flatpak/README.md içindeki adımlarla
# flatpak/unwall.flatpak üretin, bu betik varsa onu da yükler.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SRC/bin/unwallctl")"
[ -n "$VERSION" ] || { echo "sürüm bin/unwallctl içinden okunamadı" >&2; exit 1; }
TAG="v$VERSION"

command -v gh >/dev/null 2>&1 || { echo "gerekli: gh (GitHub CLI)" >&2; exit 1; }

echo "==> $TAG için paketler build ediliyor"
"$SRC/packaging/build-deb.sh"
"$SRC/packaging/build-rpm.sh"
"$SRC/packaging/build-appimage.sh"

ASSETS=(
	"$SRC/packaging/unwall_${VERSION}_all.deb"
	"$SRC/packaging/RPMS/unwall-${VERSION}-1.noarch.rpm"
	"$SRC/packaging/Unwall-${VERSION}-x86_64.AppImage"
)
[ -f "$SRC/flatpak/unwall.flatpak" ] && ASSETS+=("$SRC/flatpak/unwall.flatpak") || \
	echo "uyarı: flatpak/unwall.flatpak yok, atlanıyor (bkz. flatpak/README.md)" >&2

if ! git -C "$SRC" rev-parse "$TAG" >/dev/null 2>&1; then
	echo "==> etiketleniyor: $TAG"
	git -C "$SRC" tag "$TAG"
	git -C "$SRC" push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
	echo "==> mevcut release'e asset'ler yükleniyor: $TAG"
	gh release upload "$TAG" "${ASSETS[@]}" --clobber
else
	echo "==> release oluşturuluyor: $TAG"
	gh release create "$TAG" "${ASSETS[@]}" --title "$TAG" --generate-notes
fi

echo
echo "https://github.com/WinTone01/Unwall/releases/tag/$TAG"
