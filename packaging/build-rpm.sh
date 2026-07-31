#!/usr/bin/env bash
# Unwall .rpm paketini kurar (build eder). Root gerekmez.
#
#   ./packaging/build-rpm.sh
#
# Çıktı: packaging/unwall-<sürüm>-1.*.noarch.rpm
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SRC/bin/unwallctl")"
[ -n "$VERSION" ] || { echo "sürüm bin/unwallctl içinden okunamadı" >&2; exit 1; }

for c in rpmbuild git; do
	command -v "$c" >/dev/null 2>&1 || { echo "gerekli: $c" >&2; exit 1; }
done

TOPDIR="$(mktemp -d)"
trap 'rm -rf "$TOPDIR"' EXIT
mkdir -p "$TOPDIR"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

# %prep içindeki `%autosetup -n Unwall-%{version}` GitHub'ın tag
# tarball'larının açıldığı dizin adıyla eşleşsin diye aynı önekle
# arşivliyoruz.
echo "==> kaynak arşivi hazırlanıyor"
git -C "$SRC" archive --prefix="Unwall-$VERSION/" HEAD \
	-o "$TOPDIR/SOURCES/unwall-$VERSION.tar.gz"

cp "$SRC/packaging/unwall.spec" "$TOPDIR/SPECS/unwall.spec"

echo "==> rpmbuild çalışıyor"
rpmbuild --define "_topdir $TOPDIR" -bb "$TOPDIR/SPECS/unwall.spec"

mkdir -p "$SRC/packaging/RPMS"
find "$TOPDIR/RPMS" -name '*.rpm' -exec cp -v {} "$SRC/packaging/RPMS/" \;

echo
echo "Kurmak için:  sudo dnf install packaging/RPMS/unwall-$VERSION-1.*.noarch.rpm"
echo "openSUSE için: sudo zypper install packaging/RPMS/unwall-$VERSION-1.*.noarch.rpm"
