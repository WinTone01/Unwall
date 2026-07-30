#!/usr/bin/env python3
"""Zapret Linux Türkiye - GTK4/libadwaita kontrol paneli.

Arayüz normal kullanıcı olarak çalışır. Ayrıcalık gerektiren her iş
`pkexec zapret-turkeyctl ...` üzerinden yapılır; bu betik hiçbir zaman
root olarak çalıştırılmamalıdır.
"""

import logging
import os
import shutil
import subprocess
import sys
import traceback

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

APP_ID = "org.zapret.turkey"
VERSION = "1.0.0"

# Terminalden çalıştırıldığında her şey konsola aksın. Ayrıntı için:
#   ZT_DEBUG=1 zapret-turkey
logging.basicConfig(
    level=logging.DEBUG if os.environ.get("ZT_DEBUG") else logging.INFO,
    format="%(asctime)s %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
log = logging.getLogger("zapret-turkey")


def _excepthook(exc_type, exc, tb):
    """Yakalanmamış hatalar sessizce yutulmasın."""
    log.error("YAKALANMAMIŞ HATA:\n%s", "".join(traceback.format_exception(exc_type, exc, tb)))


sys.excepthook = _excepthook

CTL = os.environ.get("ZT_CTL", shutil.which("zapret-turkeyctl") or "/usr/local/bin/zapret-turkeyctl")

HOSTLIST_MODES = [
    ("auto", "Otomatik (zapret öğrenir)"),
    ("manual", "Manuel (hostlist.txt)"),
    ("off", "Kapalı (tüm trafik)"),
]

ENGINES = [
    ("zapret2", "Zapret2 (yeni LUA motoru)"),
    ("zapret", "Zapret (klasik motor)"),
]

DNS_PROVIDERS = [
    ("cloudflare", "Cloudflare (1.1.1.1)"),
    ("google", "Google (8.8.8.8)"),
    ("quad9", "Quad9 (9.9.9.9)"),
]

DNS_BACKENDS = [
    ("auto", "Otomatik"),
    ("dnscrypt", "DoH — dnscrypt-proxy (443, fark edilmez)"),
    ("resolved", "DoT — systemd-resolved (853)"),
]

GATEWAY_HELP = (
    "Bu makine yerel ağdaki cihazlar için NAT yapan bir yönlendiriciye dönüşür; "
    "konsol/TV trafiği de zapret'ten geçer.\n\n"
    "Cihazın ağ ayarlarına elle şunları girin:\n"
    "  • Ağ geçidi (Gateway): bu bilgisayarın LAN IP adresi\n"
    "  • Alt ağ maskesi: ağınızla aynı (genelde 255.255.255.0)\n"
    "  • DNS: 1.1.1.1 / 8.8.8.8\n\n"
    "Windows sürümündeki go-pcap2socks + Npcap katmanına gerek yoktur; "
    "yönlendirme ve NAT çekirdek tarafından yapılır."
)


def ctl(*args, timeout=15):
    """Yetki gerektirmeyen ctl çağrısı. (çıkış kodu, çıktı) döner."""
    try:
        p = subprocess.run(
            [CTL, *args], capture_output=True, text=True, timeout=timeout
        )
        out = (p.stdout or "") + (p.stderr or "")
        if p.returncode == 0:
            log.debug("ctl %s -> 0", " ".join(args))
        else:
            log.warning("ctl %s -> %s\n%s", " ".join(args), p.returncode, out.strip())
        return p.returncode, out
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.error("ctl %s çalıştırılamadı: %s", " ".join(args), exc)
        return 1, str(exc)


def parse_kv(text):
    out = {}
    for line in text.splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out


class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Zapret Türkiye")
        self.set_default_size(520, 760)
        self.status = {}
        self.config = {}
        self.strategies = []
        self._busy = False
        self._loading = True
        # Kullanıcı bir seçim değiştirip henüz uygulamadıysa, periyodik durum
        # yenilemesi kontrolleri config'teki eski değerlere geri çevirmesin.
        self._dirty = False

        self.toasts = Adw.ToastOverlay()
        self.set_content(self.toasts)

        toolbar = Adw.ToolbarView()
        self.toasts.set_child(toolbar)

        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        menu = Gio.Menu()
        menu.append("Ortam teşhisi", "win.doctor")
        menu.append("DNS kontrolü", "win.dnscheck")
        menu.append("Motorları derle / güncelle", "win.build")
        menu.append("Hakkında", "win.about")
        btn_menu = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu)
        header.pack_end(btn_menu)

        btn_refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Yenile")
        btn_refresh.connect("clicked", lambda *_: self.refresh())
        header.pack_start(btn_refresh)

        for name, cb in (
            ("doctor", self.on_doctor),
            ("dnscheck", self.on_dnscheck),
            ("build", self.on_build),
            ("about", self.on_about),
        ):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)

        # Çakışan başka bir DPI aracı varsa üstte uyarı çubuğu
        self.banner = Adw.Banner(
            title="Çakışan bir DPI aracı çalışıyor",
            button_label="Kapat",
            revealed=False,
        )
        self.banner.connect(
            "button-clicked",
            lambda *_: self.run_privileged(
                ["disable-conflicts"], title="çakışanları kapat"
            ),
        )
        toolbar.add_top_bar(self.banner)

        page = Adw.PreferencesPage()
        toolbar.set_content(page)

        # --- Durum ---
        g_status = Adw.PreferencesGroup()
        page.add(g_status)

        self.lbl_state = Gtk.Label(label="KONTROL EDİLİYOR…")
        self.lbl_state.add_css_class("title-1")
        self.lbl_sub = Gtk.Label(label="")
        self.lbl_sub.add_css_class("dim-label")
        self.lbl_sub.set_wrap(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_top(8)
        box.set_margin_bottom(12)
        box.append(self.lbl_state)
        box.append(self.lbl_sub)

        self.btn_main = Gtk.Button(label="ZAPRET'İ BAŞLAT")
        self.btn_main.add_css_class("suggested-action")
        self.btn_main.add_css_class("pill")
        self.btn_main.set_size_request(-1, 48)
        self.btn_main.connect("clicked", self.on_main_clicked)
        box.append(self.btn_main)

        self.progress = Gtk.ProgressBar()
        self.progress.set_visible(False)
        box.append(self.progress)

        g_status.add(box)

        # --- Motor / strateji ---
        g_engine = Adw.PreferencesGroup(title="Motor ve Strateji")
        page.add(g_engine)

        self.row_engine = Adw.ComboRow(title="Motor")
        self.row_engine.set_model(Gtk.StringList.new([label for _, label in ENGINES]))
        self.row_engine.connect("notify::selected", self.on_engine_changed)
        g_engine.add(self.row_engine)

        self.row_strategy = Adw.ComboRow(title="Strateji")
        self.row_strategy.connect("notify::selected", lambda *_: self.mark_dirty())
        g_engine.add(self.row_strategy)

        self.row_blockcheck = Adw.ActionRow(
            title="ISS Analizi (blockcheck)",
            subtitle="Operatörünüz için çalışan stratejiyi arar (uzun sürebilir)",
        )
        btn_bc = Gtk.Button(label="Analiz Et", valign=Gtk.Align.CENTER)
        btn_bc.connect("clicked", self.on_blockcheck)
        self.row_blockcheck.add_suffix(btn_bc)
        self.row_blockcheck.set_activatable_widget(btn_bc)
        g_engine.add(self.row_blockcheck)

        # --- Filtreleme ---
        g_filter = Adw.PreferencesGroup(
            title="Filtreleme",
            description="Yalnızca listedeki alan adları motordan geçer; "
            "normal trafiğiniz etkilenmez.",
        )
        page.add(g_filter)

        self.row_hostlist = Adw.ComboRow(title="Hostlist modu")
        self.row_hostlist.set_model(Gtk.StringList.new([l for _, l in HOSTLIST_MODES]))
        self.row_hostlist.connect("notify::selected", lambda *_: self.mark_dirty())
        g_filter.add(self.row_hostlist)

        row_edit = Adw.ActionRow(
            title="Listeleri düzenle", subtitle="/etc/zapret-turkey"
        )
        btn_open = Gtk.Button(label="Klasörü Aç", valign=Gtk.Align.CENTER)
        btn_open.connect("clicked", self.on_open_conf_dir)
        row_edit.add_suffix(btn_open)
        g_filter.add(row_edit)

        # --- Şifreli DNS ---
        g_dns = Adw.PreferencesGroup(
            title="Şifreli DNS",
            description="ISS'niz DNS'e müdahale ediyorsa zapret tek başına yetmez. "
            "Sorgular şifreli kanaldan taşınır.",
        )
        page.add(g_dns)

        self.row_dns = Adw.SwitchRow(title="Şifreli DNS", subtitle="—")
        self.row_dns.connect("notify::active", lambda *_: self.on_dns_toggled())
        g_dns.add(self.row_dns)

        self.row_dns_provider = Adw.ComboRow(title="Sağlayıcı")
        self.row_dns_provider.set_model(Gtk.StringList.new([l for _, l in DNS_PROVIDERS]))
        self.row_dns_provider.connect("notify::selected", lambda *_: self.on_dns_reapply())
        g_dns.add(self.row_dns_provider)

        self.row_dns_backend = Adw.ComboRow(title="Yöntem")
        self.row_dns_backend.set_model(Gtk.StringList.new([l for _, l in DNS_BACKENDS]))
        self.row_dns_backend.connect("notify::selected", lambda *_: self.on_dns_reapply())
        g_dns.add(self.row_dns_backend)

        row_dns_test = Adw.ActionRow(
            title="DNS sınaması", subtitle="Şifreli kanal ve müdahale kontrolü"
        )
        btn_dns_test = Gtk.Button(label="Sına", valign=Gtk.Align.CENTER)
        btn_dns_test.connect("clicked", self.on_dns_test)
        row_dns_test.add_suffix(btn_dns_test)
        row_dns_test.set_activatable_widget(btn_dns_test)
        g_dns.add(row_dns_test)

        # --- Ağ geçidi ---
        g_gw = Adw.PreferencesGroup(title="Ağdaki Cihazlarla Paylaş")
        page.add(g_gw)

        self.row_gateway = Adw.SwitchRow(
            title="Ağ geçidi modu",
            subtitle="Konsol, TV vb. cihazları bu makine üzerinden geçir",
        )
        self.row_gateway.connect("notify::active", lambda *_: self.on_gateway_toggled())
        g_gw.add(self.row_gateway)

        self.row_gw_info = Adw.ActionRow(title="LAN adresi", subtitle="—")
        g_gw.add(self.row_gw_info)

        exp = Adw.ExpanderRow(title="Cihaz ayarları nasıl yapılır?")
        lbl = Gtk.Label(label=GATEWAY_HELP, wrap=True, xalign=0)
        lbl.set_margin_start(12)
        lbl.set_margin_end(12)
        lbl.set_margin_top(8)
        lbl.set_margin_bottom(8)
        exp.add_row(lbl)
        g_gw.add(exp)

        # --- Otomatik başlatma ---
        g_svc = Adw.PreferencesGroup(title="Servis")
        page.add(g_svc)

        self.row_autostart = Adw.SwitchRow(
            title="Açılışta otomatik başlat",
            subtitle="systemd birimi olarak etkinleştirir",
        )
        self.row_autostart.connect("notify::active", lambda *_: self.on_autostart_toggled())
        g_svc.add(self.row_autostart)

        # --- Konsol ---
        g_log = Adw.PreferencesGroup(title="Çıktı")
        page.add(g_log)

        self.buf = Gtk.TextBuffer()
        tv = Gtk.TextView(buffer=self.buf, editable=False, monospace=True)
        tv.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.scroller = Gtk.ScrolledWindow(min_content_height=180, vexpand=False)
        self.scroller.set_child(tv)
        self.scroller.add_css_class("card")
        g_log.add(self.scroller)

        self.refresh()
        GLib.timeout_add_seconds(4, self._tick)

    # -----------------------------------------------------------------
    # yardımcılar
    # -----------------------------------------------------------------

    def log(self, text):
        for line in text.rstrip("\n").splitlines():
            if line.strip():
                log.info("%s", line)
        end = self.buf.get_end_iter()
        self.buf.insert(end, text if text.endswith("\n") else text + "\n")
        GLib.idle_add(
            lambda: self.scroller.get_vadjustment().set_value(
                self.scroller.get_vadjustment().get_upper()
            )
        )

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast.new(text))

    def mark_dirty(self):
        if self._loading:
            return
        self._dirty = True
        log.debug("bekleyen değişiklik: %s", " ".join(self.pending_config()))
        self.btn_main.set_label(
            "AYARLARI UYGULA" if self.status.get("running") == "1" else "ZAPRET'İ BAŞLAT"
        )

    def pending_config(self):
        """Arayüzdeki seçimleri KEY=VALUE listesine çevirir."""
        engine = ENGINES[self.row_engine.get_selected()][0]
        idx = self.row_strategy.get_selected()
        strategy = (
            self.strategies[idx][0] if 0 <= idx < len(self.strategies) else "analiz"
        )
        hostlist = HOSTLIST_MODES[self.row_hostlist.get_selected()][0]
        return [
            f"ENGINE={engine}",
            f"STRATEGY={strategy}",
            f"HOSTLIST_MODE={hostlist}",
            f"GATEWAY_MODE={'1' if self.row_gateway.get_active() else '0'}",
        ]

    def run_privileged(self, args, done=None, title=None):
        """pkexec ile ctl çalıştırır, çıktıyı konsola akıtır."""
        if self._busy:
            self.toast("Başka bir işlem sürüyor")
            return
        self._busy = True
        self.progress.set_visible(True)
        self.progress.pulse()
        self._pulse_id = GLib.timeout_add(120, self._pulse)
        if title:
            self.log(f"\n=== {title} ===")

        try:
            proc = Gio.Subprocess.new(
                ["pkexec", CTL, *args],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
            )
        except GLib.Error as exc:
            self._finish_busy()
            self.log(f"başlatılamadı: {exc.message}")
            return

        stream = Gio.DataInputStream.new(proc.get_stdout_pipe())
        self._read_line(stream, proc, done)

    def _pulse(self):
        self.progress.pulse()
        return self._busy

    def _finish_busy(self):
        self._busy = False
        self.progress.set_visible(False)

    def _read_line(self, stream, proc, done):
        def on_line(src, res):
            try:
                line, _ = src.read_line_finish_utf8(res)
            except GLib.Error as exc:
                line = None
                self.log(f"okuma hatası: {exc.message}")
            if line is None:
                proc.wait_async(None, on_wait)
                return
            self.log(line)
            src.read_line_async(GLib.PRIORITY_DEFAULT, None, on_line)

        def on_wait(p, res):
            try:
                p.wait_finish(res)
                code = p.get_exit_status()
            except GLib.Error:
                code = 1
            self._finish_busy()
            if code == 126 or code == 127:
                self.toast("Yetki verilmedi")
            elif code != 0:
                self.toast("İşlem hata ile bitti (çıktıya bakın)")
            log.info("işlem bitti (çıkış kodu %s)", code)
            if code == 0:
                self._dirty = False
            if done:
                done(code)
            self.refresh()

        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, on_line)

    # -----------------------------------------------------------------
    # durum yenileme
    # -----------------------------------------------------------------

    def _tick(self):
        if not self._busy:
            self.refresh()
        return True

    def refresh(self):
        code, out = ctl("status")
        if code != 0 and not out.strip():
            self.lbl_state.set_label("KURULUM EKSİK")
            self.lbl_sub.set_label(f"{CTL} bulunamadı. install.sh çalıştırın.")
            self.btn_main.set_sensitive(False)
            return
        self.status = parse_kv(out)
        _, cfg_out = ctl("config", "get")
        self.config = parse_kv(cfg_out)

        # Bekleyen (henüz uygulanmamış) bir seçim varsa kontrollere dokunma;
        # yoksa periyodik yenileme kullanıcının seçimini geri alırdı.
        self._loading = True
        if self._dirty:
            engine = ENGINES[self.row_engine.get_selected()][0]
            log.debug("bekleyen değişiklik var, kontroller yenilenmiyor")
        else:
            engine = self.config.get("ENGINE", "zapret2")
            self.row_engine.set_selected(
                next((i for i, (e, _) in enumerate(ENGINES) if e == engine), 0)
            )
            self._load_strategies(engine, self.config.get("STRATEGY", "analiz"))
            mode = self.config.get("HOSTLIST_MODE", "auto")
            self.row_hostlist.set_selected(
                next((i for i, (m, _) in enumerate(HOSTLIST_MODES) if m == mode), 0)
            )
            self.row_gateway.set_active(self.config.get("GATEWAY_MODE") == "1")
        self.row_autostart.set_active(self.status.get("enabled") == "1")
        self._refresh_dns()
        self._loading = False

        running = self.status.get("running") == "1"
        enabled = self.status.get("enabled") == "1"
        ready = self.status.get("engine_ready") == "1"

        if running and enabled:
            self.lbl_state.set_label("SERVİS MODU AKTİF")
        elif running:
            self.lbl_state.set_label("AKTİF")
        elif not ready:
            self.lbl_state.set_label("MOTOR DERLENMEMİŞ")
        else:
            self.lbl_state.set_label("HAZIR")

        strat = self.config.get("STRATEGY", "?")
        if strat == "analiz":
            custom = self.config.get("CUSTOM_ARGS", "")
            strat = f"Analiz sonucu: {custom or 'yok (önce blockcheck)'}"
        sub = f"{engine} · {strat} · hostlist: {self.config.get('HOSTLIST_MODE', '?')}"
        if self._dirty:
            idx = self.row_strategy.get_selected()
            pend = self.strategies[idx][1] if 0 <= idx < len(self.strategies) else "?"
            sub = f"uygulanmadı → {pend}   (şu an: {sub})"
        self.lbl_sub.set_label(sub)

        self.btn_main.set_sensitive(ready)
        if self._dirty:
            self.btn_main.set_label(
                "AYARLARI UYGULA" if running else "ZAPRET'İ BAŞLAT"
            )
        else:
            self.btn_main.set_label("DURDUR" if running else "ZAPRET'İ BAŞLAT")
        if running:
            self.btn_main.remove_css_class("suggested-action")
            self.btn_main.add_css_class("destructive-action")
        else:
            self.btn_main.remove_css_class("destructive-action")
            self.btn_main.add_css_class("suggested-action")

        _, conf_out = ctl("conflicts")
        conflicts = parse_kv(conf_out).get("conflicts", "")
        self.banner.set_revealed(bool(conflicts))
        if conflicts:
            self.banner.set_title(f"Çakışan DPI aracı çalışıyor: {conflicts}")

        _, gw = ctl("gateway-info")
        gwd = parse_kv(gw)
        self.row_gw_info.set_subtitle(
            f"{gwd.get('lan') or gwd.get('wan_ip') or '—'}  (WAN: {gwd.get('wan_iface') or '—'})"
        )

    def _refresh_dns(self):
        _, out = ctl("dns", "status")
        d = parse_kv(out)
        self.dns = d
        backend = d.get("backend", "none")
        on = backend != "none"
        self.row_dns.set_active(on)

        if on and d.get("encrypted") != "1":
            sub = f"{backend} yapılandırıldı ama etkin değil"
        elif on:
            sub = f"{backend} · {d.get('servers', '').strip() or '—'}"
        else:
            sub = f"kapalı · şu an: {d.get('servers', '').strip() or '—'}"
        self.row_dns.set_subtitle(sub)

        prov = d.get("provider") or "cloudflare"
        self.row_dns_provider.set_selected(
            next((i for i, (p, _) in enumerate(DNS_PROVIDERS) if p == prov), 0)
        )
        if on:
            self.row_dns_backend.set_selected(
                next((i for i, (b, _) in enumerate(DNS_BACKENDS) if b == backend), 0)
            )

        # dnscrypt-proxy kurulu değilse DoH seçeneği anlamsız
        if d.get("dnscrypt_available") == "0":
            self.row_dns_backend.set_subtitle(
                "DoH için: dnscrypt-proxy paketini kurun"
            )
        else:
            self.row_dns_backend.set_subtitle("")

        self.row_dns_provider.set_sensitive(on)
        self.row_dns_backend.set_sensitive(on)

    def _load_strategies(self, engine, selected):
        code, out = ctl("strategies", engine)
        self.strategies = []
        labels = []
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                self.strategies.append((parts[0], parts[1]))
                labels.append(parts[1])
        if not labels:
            labels = ["(strateji listesi okunamadı)"]
            self.strategies = [("analiz", labels[0])]
        self.row_strategy.set_model(Gtk.StringList.new(labels))
        self.row_strategy.set_selected(
            next((i for i, (s, _) in enumerate(self.strategies) if s == selected), 0)
        )

    # -----------------------------------------------------------------
    # eylemler
    # -----------------------------------------------------------------

    def on_engine_changed(self, *_):
        if self._loading:
            return
        engine = ENGINES[self.row_engine.get_selected()][0]
        self._loading = True
        self._load_strategies(engine, "analiz")
        self._loading = False
        self.mark_dirty()

    def on_main_clicked(self, *_):
        if self.status.get("running") == "1":
            if self.btn_main.get_label() == "AYARLARI UYGULA":
                self.run_privileged(["restart", *self.pending_config()], title="yeniden başlat")
            else:
                self.run_privileged(["stop"], title="durdur")
        else:
            self.run_privileged(["start", *self.pending_config()], title="başlat")

    def on_autostart_toggled(self):
        if self._loading:
            return
        if self.row_autostart.get_active():
            self.run_privileged(["enable", *self.pending_config()], title="servis kur")
        else:
            self.run_privileged(["disable"], title="servisi kaldır")

    def on_gateway_toggled(self):
        if self._loading:
            return
        self.mark_dirty()
        if self.status.get("running") == "1":
            self.run_privileged(["restart", *self.pending_config()], title="ağ geçidi")

    def on_dns_toggled(self):
        if self._loading:
            return
        if self.row_dns.get_active():
            provider = DNS_PROVIDERS[self.row_dns_provider.get_selected()][0]
            backend = DNS_BACKENDS[self.row_dns_backend.get_selected()][0]
            self.run_privileged(
                ["dns", "enable", provider, backend], title="şifreli DNS aç"
            )
        else:
            self.run_privileged(["dns", "disable"], title="şifreli DNS kapat")

    def on_dns_reapply(self):
        # Sağlayıcı/yöntem yalnızca DNS açıkken anlamlı; açıkken değişiklik
        # doğrudan yeniden uygulanır.
        if self._loading or not self.row_dns.get_active():
            return
        self.on_dns_toggled()

    def on_dns_test(self, *_):
        self.log("\n=== DNS sınaması ===")
        code, out = ctl("dns", "test", timeout=30)
        self.log(out.strip())
        d = parse_kv(out)
        if d.get("encrypted") == "1" and d.get("poisoning") == "ok":
            self.toast("DNS şifreli ve temiz")
        elif d.get("encrypted") == "1":
            self.toast(f"Şifreli, ama müdahale sonucu: {d.get('poisoning')}")
        else:
            self.toast("Şifreli DNS kapalı")

    def on_blockcheck(self, *_):
        engine = ENGINES[self.row_engine.get_selected()][0]
        heading = "ISS analizi başlatılsın mı?"
        body = (
            "Blockcheck onlarca strateji dener; birkaç dakika sürebilir ve "
            "bu sırada motor geçici olarak durdurulur. Sonuç otomatik "
            "olarak 'Analiz Sonucu' stratejisine yazılır."
        )

        def on_resp(_d, resp):
            if resp == "run":
                self.run_privileged(["blockcheck", engine], title=f"blockcheck ({engine})")

        # libadwaita 1.5+ AlertDialog, eski sürümlerde MessageDialog
        if hasattr(Adw, "AlertDialog"):
            dlg = Adw.AlertDialog(heading=heading, body=body)
            dlg.add_response("cancel", "Vazgeç")
            dlg.add_response("run", "Başlat")
            dlg.set_response_appearance("run", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present(self)
        else:
            dlg = Adw.MessageDialog(transient_for=self, heading=heading, body=body)
            dlg.add_response("cancel", "Vazgeç")
            dlg.add_response("run", "Başlat")
            dlg.set_response_appearance("run", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present()

    def on_build(self, *_):
        self.run_privileged(["build", "all"], title="motorları derle")

    def on_doctor(self, *_):
        code, out = ctl("doctor", timeout=40)
        self.log("\n=== ortam teşhisi ===")
        self.log(out.strip())
        self.toast("Teşhis tamamlandı" if code == 0 else "Sorun bulundu, çıktıya bakın")

    def on_dnscheck(self, *_):
        code, out = ctl("dnscheck", timeout=20)
        d = parse_kv(out)
        self.log("\n=== DNS kontrolü ===")
        self.log(out.strip())
        result = d.get("result")
        if result == "ok":
            self.toast("DNS temiz görünüyor")
        elif result == "poisoned":
            self.toast("DNS müdahalesi var — DoH/DoT kullanın")
        else:
            self.toast(f"DNS sonucu: {result}")

    def on_open_conf_dir(self, *_):
        Gio.AppInfo.launch_default_for_uri("file:///etc/zapret-turkey", None)

    def on_about(self, *_):
        kwargs = dict(
            application_name="Zapret Türkiye",
            version=VERSION,
            comments=(
                "bol-van/zapret ve zapret2 motorları için Linux kontrol paneli.\n"
                "Windows sürümünün (zapret-win-bundle + AutoIt) Linux karşılığı."
            ),
            website="https://github.com/bol-van/zapret",
            license_type=Gtk.License.MIT_X11,
            developers=["Zapret Linux Türkiye katkıcıları"],
        )
        if hasattr(Adw, "AboutDialog"):
            Adw.AboutDialog(**kwargs).present(self)
        else:
            Adw.AboutWindow(transient_for=self, **kwargs).present()


class App(Adw.Application):
    def __init__(self):
        flags = Gio.ApplicationFlags.DEFAULT_FLAGS
        # ZT_NO_UNIQUE=1 ile her çalıştırma kendi penceresini açar; hata
        # ayıklarken çalışan örneğe devredilmesini istemediğimizde işe yarar.
        if os.environ.get("ZT_NO_UNIQUE"):
            flags |= Gio.ApplicationFlags.NON_UNIQUE
        super().__init__(application_id=APP_ID, flags=flags)

    def do_activate(self):
        log.debug("uygulama etkinleştirildi")
        win = self.props.active_window or Window(self)
        win.present()


def main():
    if os.geteuid() == 0:
        log.error("Bu arayüzü root olarak çalıştırmayın; yetki gerektiren "
                  "işlemler pkexec ile yapılır.")
        return 1

    log.info("Zapret Türkiye %s başlıyor (ctl: %s)", VERSION, CTL)
    if not os.path.exists(CTL):
        log.error("%s bulunamadı. Önce: sudo ./install.sh", CTL)

    app = App()
    try:
        app.register(None)
    except GLib.Error as exc:
        log.error("uygulama kaydedilemedi: %s", exc.message)
        return 1
    if app.get_is_remote():
        log.warning(
            "zaten çalışan bir Zapret Türkiye penceresi var; o pencere öne "
            "getirilecek. Bu terminalde log görmek için önce onu kapatın ya da "
            "ZT_NO_UNIQUE=1 zapret-turkey ile başlatın."
        )
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
