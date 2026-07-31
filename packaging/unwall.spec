# Fedora/RHEL-family spec. openSUSE users: package names below follow
# Fedora naming; on openSUSE the equivalents are typically
# libadwaita-1-0 (runtime) / libadwaita-devel, libnetfilter_queue-devel,
# libnfnetlink-devel, libmnl-devel, libluajit-2_1-2 / luajit-devel.

Name:           unwall
Version:        1.3.2
Release:        1%{?dist}
Summary:        GTK4 control panel for the zapret/nfqws DPI bypass engine

License:        GPL-3.0-or-later
URL:             https://github.com/WinTone01/Unwall
Source0:        https://github.com/WinTone01/Unwall/archive/refs/tags/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

BuildArch:      noarch

Requires:       nftables
Requires:       iproute
Requires:       python3-gobject
Requires:       libadwaita
Requires:       gtk4
Requires:       polkit
Requires:       bind-utils
Requires:       gcc
Requires:       make
Requires:       pkgconf
Requires:       git
Requires:       curl
Requires:       luajit-devel
Requires:       libcap-devel
Requires:       libnetfilter_queue-devel
Requires:       libnfnetlink-devel
Requires:       libmnl-devel
Requires:       zlib-devel
Recommends:     dnscrypt-proxy

%description
Unwall is a Linux control panel for zapret and zapret2, the DPI (Deep
Packet Inspection) bypass engines by bol-van. It wraps the engine with a
systemd service, nftables rules, encrypted DNS (DoH/DoT), gateway mode
for consoles and smart TVs, and ready-made carrier presets, driven by a
GTK4 interface that never runs as root.

After installing this package, build the engines once with:
    sudo unwallctl build

%prep
%autosetup -n Unwall-%{version}

%build
# Derlenecek bir şey yok: bash + Python. Motorlar (nfqws/nfqws2) kurulum
# sonrası "unwallctl build" ile kaynaktan derlenir.
:

%install
install -Dm755 bin/unwallctl %{buildroot}%{_bindir}/unwallctl
sed -i \
	-e 's|^UW_LIB=.*|UW_LIB="${UW_LIB:-/usr/lib/unwall}"|' \
	-e 's|^UW_ETC=.*|UW_ETC="${UW_ETC:-%{_sysconfdir}/unwall}"|' \
	-e 's|^UW_OPT=.*|UW_OPT="${UW_OPT:-/opt/unwall}"|' \
	-e 's|^UW_LOG=.*|UW_LOG="${UW_LOG:-/var/log/unwall}"|' \
	%{buildroot}%{_bindir}/unwallctl

install -Dm755 bin/unwall %{buildroot}%{_bindir}/unwall
sed -i 's|^UW_LIB=.*|UW_LIB="${UW_LIB:-/usr/lib/unwall}"|' \
	%{buildroot}%{_bindir}/unwall

install -Dm644 gui/unwall_gui.py %{buildroot}/usr/lib/unwall/unwall_gui.py
install -Dm644 lib/strategies.conf %{buildroot}/usr/lib/unwall/strategies.conf

install -Dm644 etc/unwall.conf %{buildroot}%{_sysconfdir}/unwall/unwall.conf
install -Dm644 hostlist.txt %{buildroot}%{_sysconfdir}/unwall/hostlist.txt
install -Dm644 excludelist.txt %{buildroot}%{_sysconfdir}/unwall/excludelist.txt
install -Dm644 autohostlist.txt %{buildroot}%{_sysconfdir}/unwall/autohostlist.txt

sed -e 's|@BINDIR@|%{_bindir}|g' -e 's|@ETCDIR@|%{_sysconfdir}/unwall|g' \
	-e 's|@LOGDIR@|/var/log/unwall|g' systemd/unwall.service \
	> %{_builddir}/unwall.service
install -Dm644 %{_builddir}/unwall.service \
	%{buildroot}/usr/lib/systemd/system/unwall.service

sed 's|@BINDIR@|%{_bindir}|g' polkit/io.github.WinTone01.Unwall.policy \
	> %{_builddir}/io.github.WinTone01.Unwall.policy
install -Dm644 %{_builddir}/io.github.WinTone01.Unwall.policy \
	%{buildroot}%{_datadir}/polkit-1/actions/io.github.WinTone01.Unwall.policy

install -Dm644 share/io.github.WinTone01.Unwall.desktop \
	%{buildroot}%{_datadir}/applications/io.github.WinTone01.Unwall.desktop
install -Dm644 share/io.github.WinTone01.Unwall.svg \
	%{buildroot}%{_datadir}/icons/hicolor/scalable/apps/io.github.WinTone01.Unwall.svg
install -Dm644 share/io.github.WinTone01.Unwall.metainfo.xml \
	%{buildroot}%{_datadir}/metainfo/io.github.WinTone01.Unwall.metainfo.xml

echo 'nfnetlink_queue' > %{_builddir}/unwall-modules.conf
install -Dm644 %{_builddir}/unwall-modules.conf \
	%{buildroot}%{_prefix}/lib/modules-load.d/unwall.conf

%post
# Kasıtlı olarak %%systemd_post kullanmıyoruz: o makro preset politikasına
# göre servisi etkinleştirebilir. Bu paket hiçbir servisi kendiliğinden
# başlatmaz/etkinleştirmez; hepsi arayüzden ya da elle yapılır.
systemctl daemon-reload >/dev/null 2>&1 || :
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q %{_datadir}/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -qtf %{_datadir}/icons/hicolor || :
fi
if [ "$1" -eq 1 ]; then
	cat <<-EOF

	Unwall kuruldu. Motorlar henüz derlenmedi:

	    sudo unwallctl build

	Ardından uygulama menüsünden "Unwall" açılabilir ya da:

	    unwallctl doctor
	    sudo unwallctl start

	EOF
fi

%preun
if [ "$1" -eq 0 ]; then
	systemctl disable --now unwall.service >/dev/null 2>&1 || :
	if [ -x %{_bindir}/unwallctl ]; then
		unwallctl nft-flush >/dev/null 2>&1 || :
		unwallctl dns disable >/dev/null 2>&1 || :
	fi
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :
if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database -q %{_datadir}/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
	gtk-update-icon-cache -qtf %{_datadir}/icons/hicolor || :
fi
if [ "$1" -eq 0 ]; then
	rm -rf %{_sysconfdir}/unwall /opt/unwall /var/log/unwall
	rm -f %{_sysconfdir}/systemd/resolved.conf.d/90-unwall.conf
fi

%files
%license LICENSE
%doc README.md README.tr.md
%{_bindir}/unwallctl
%{_bindir}/unwall
/usr/lib/unwall/
%config(noreplace) %{_sysconfdir}/unwall/unwall.conf
%config(noreplace) %{_sysconfdir}/unwall/hostlist.txt
%config(noreplace) %{_sysconfdir}/unwall/excludelist.txt
%config(noreplace) %{_sysconfdir}/unwall/autohostlist.txt
/usr/lib/systemd/system/unwall.service
%{_datadir}/polkit-1/actions/io.github.WinTone01.Unwall.policy
%{_datadir}/applications/io.github.WinTone01.Unwall.desktop
%{_datadir}/icons/hicolor/scalable/apps/io.github.WinTone01.Unwall.svg
%{_datadir}/metainfo/io.github.WinTone01.Unwall.metainfo.xml
%{_prefix}/lib/modules-load.d/unwall.conf

%changelog
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.3.2-1
- Fix silent blockcheck failure under set -e/pipefail; make dnscrypt-proxy setup reliable on Fedora (static stamps, no external fetch needed at startup).
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.3.1-1
- Add libcap-devel build dependency, fix DNS-poisoning false positive, add gateway-mode DNS redirect.
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.3.0-1
- Added AppImage packaging (packaging/build-appimage.sh).
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.2.1-1
- Hardcode _unitdir/_libdir instead of relying on macros not defined outside Fedora.
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.2.0-1
- Added .deb and .rpm packaging and a GUI-only Flatpak, fixed the desktop
  entry's toolkit category (was Qt/KDE, is GTK).
* Fri Jul 31 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.1.0-1
- Licensed under GPLv3, credited the author, added the GitHub update checker.
* Thu Jul 30 2026 WinTone01 <wintone01@users.noreply.github.com> - 1.0.0-1
- Initial release.
