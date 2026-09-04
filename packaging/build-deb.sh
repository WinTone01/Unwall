#!/usr/bin/env bash
# Unwall .deb paketini kurar (build eder). Root gerekmez.
#
#   ./packaging/build-deb.sh
#
# Çıktı: packaging/unwall_<sürüm>_all.deb
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$SRC/bin/unwallctl")"
[ -n "$VERSION" ] || { echo "sürüm bin/unwallctl içinden okunamadı" >&2; exit 1; }

# shellcheck disable=SC2043 # tek bağımlılık şimdilik, ileride genişleyebilir
for c in dpkg-deb; do
	command -v "$c" >/dev/null 2>&1 || { echo "gerekli: $c (apt install dpkg-dev)" >&2; exit 1; }
done

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

echo "==> $VERSION için ağaç hazırlanıyor: $ROOT"

install -d "$ROOT/DEBIAN" \
	"$ROOT/usr/bin" "$ROOT/usr/lib/unwall" \
	"$ROOT/etc/unwall" \
	"$ROOT/usr/lib/systemd/system" \
	"$ROOT/usr/share/polkit-1/actions" \
	"$ROOT/usr/share/applications" \
	"$ROOT/usr/share/icons/hicolor/scalable/apps" \
	"$ROOT/usr/share/metainfo" \
	"$ROOT/usr/share/doc/unwall" \
	"$ROOT/usr/lib/modules-load.d"

sed "s/__VERSION__/$VERSION/" "$SRC/packaging/debian/control" > "$ROOT/DEBIAN/control"
install -m 0755 "$SRC/packaging/debian/postinst" "$ROOT/DEBIAN/postinst"
install -m 0755 "$SRC/packaging/debian/prerm" "$ROOT/DEBIAN/prerm"
install -m 0755 "$SRC/packaging/debian/postrm" "$ROOT/DEBIAN/postrm"
cat > "$ROOT/DEBIAN/conffiles" <<EOF
/etc/unwall/unwall.conf
/etc/unwall/hostlist.txt
/etc/unwall/excludelist.txt
/etc/unwall/autohostlist.txt
/etc/unwall/autohostlist-pending.txt
EOF

install -m 0755 "$SRC/bin/unwallctl" "$ROOT/usr/bin/unwallctl"
sed -i \
	-e 's|^UW_LIB=.*|UW_LIB="${UW_LIB:-/usr/lib/unwall}"|' \
	-e 's|^UW_ETC=.*|UW_ETC="${UW_ETC:-/etc/unwall}"|' \
	-e 's|^UW_OPT=.*|UW_OPT="${UW_OPT:-/opt/unwall}"|' \
	-e 's|^UW_LOG=.*|UW_LOG="${UW_LOG:-/var/log/unwall}"|' \
	"$ROOT/usr/bin/unwallctl"

install -m 0755 "$SRC/bin/unwall" "$ROOT/usr/bin/unwall"
sed -i 's|^UW_LIB=.*|UW_LIB="${UW_LIB:-/usr/lib/unwall}"|' "$ROOT/usr/bin/unwall"

install -m 0644 "$SRC/gui/unwall_gui.py" "$ROOT/usr/lib/unwall/unwall_gui.py"
install -m 0644 "$SRC/lib/strategies.conf" "$ROOT/usr/lib/unwall/strategies.conf"

install -m 0644 "$SRC/etc/unwall.conf" "$ROOT/etc/unwall/unwall.conf"
install -m 0644 "$SRC/hostlist.txt" "$ROOT/etc/unwall/hostlist.txt"
install -m 0644 "$SRC/excludelist.txt" "$ROOT/etc/unwall/excludelist.txt"
install -m 0644 "$SRC/autohostlist.txt" "$ROOT/etc/unwall/autohostlist.txt"
: > "$ROOT/etc/unwall/autohostlist-pending.txt"
chmod 0644 "$ROOT/etc/unwall/autohostlist-pending.txt"

sed -e "s|@BINDIR@|/usr/bin|g" -e "s|@ETCDIR@|/etc/unwall|g" -e "s|@LOGDIR@|/var/log/unwall|g" \
	"$SRC/systemd/unwall.service" > "$ROOT/usr/lib/systemd/system/unwall.service"
sed -e 's|@BINDIR@|/usr/bin|g' \
	"$SRC/systemd/unwall-verify.service" > "$ROOT/usr/lib/systemd/system/unwall-verify.service"
install -m 0644 "$SRC/systemd/unwall-verify.timer" "$ROOT/usr/lib/systemd/system/unwall-verify.timer"

sed "s|@BINDIR@|/usr/bin|g" "$SRC/polkit/io.github.WinTone01.Unwall.policy" \
	> "$ROOT/usr/share/polkit-1/actions/io.github.WinTone01.Unwall.policy"

install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.desktop" \
	"$ROOT/usr/share/applications/io.github.WinTone01.Unwall.desktop"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.svg" \
	"$ROOT/usr/share/icons/hicolor/scalable/apps/io.github.WinTone01.Unwall.svg"
install -m 0644 "$SRC/share/io.github.WinTone01.Unwall.metainfo.xml" \
	"$ROOT/usr/share/metainfo/io.github.WinTone01.Unwall.metainfo.xml"

install -m 0644 "$SRC/README.md" "$ROOT/usr/share/doc/unwall/README.md"
install -m 0644 "$SRC/README.tr.md" "$ROOT/usr/share/doc/unwall/README.tr.md"
install -m 0644 "$SRC/packaging/debian/copyright" "$ROOT/usr/share/doc/unwall/copyright"
gzip -9n -c "$SRC/LICENSE" > "$ROOT/usr/share/doc/unwall/LICENSE.gz" 2>/dev/null || \
	install -m 0644 "$SRC/LICENSE" "$ROOT/usr/share/doc/unwall/LICENSE"

echo "nfnetlink_queue" > "$ROOT/usr/lib/modules-load.d/unwall.conf"

find "$ROOT" -mindepth 1 -not -path "$ROOT/DEBIAN*" -exec touch -d "$(date -R)" {} + 2>/dev/null || true

OUT="$SRC/packaging/unwall_${VERSION}_all.deb"
echo "==> paketleniyor: $OUT"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT"

echo
echo "Kurmak için:  sudo apt install $OUT   (ya da: sudo dpkg -i $OUT)"
