#!/usr/bin/env python3
"""Unwall - GTK4/libadwaita control panel for the zapret/nfqws DPI bypass engine.

Arayüz normal kullanıcı olarak çalışır. Ayrıcalık gerektiren her iş
`pkexec unwallctl ...` üzerinden yapılır; bu betik hiçbir zaman
root olarak çalıştırılmamalıdır.
"""

import json
import logging
import os
import shutil
import subprocess
import sys
import time
import traceback

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

APP_ID = "io.github.WinTone01.Unwall"
VERSION = "1.3.0"

POLL_TIMEOUT = 6  # yoklama çağrıları için kısa zaman aşımı

CONFIG_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "unwall",
)
CONFIG_FILE = os.path.join(CONFIG_DIR, "gui.conf")

# GitHub sürüm kontrolü: sonuç günde bir kez taze tutulur, aradaki
# başlatmalarda ağa çıkılmaz.
UPDATE_CACHE_FILE = os.path.join(CONFIG_DIR, "update-check.json")
UPDATE_CHECK_INTERVAL = 24 * 3600


def _detect_lang():
    """Dil sırası: UW_LANG > kayıtlı seçim > yerel ayar > İngilizce."""
    env = os.environ.get("UW_LANG", "").lower()
    if env.startswith(("tr", "en")):
        return env[:2]
    try:
        with open(CONFIG_FILE) as fh:
            for line in fh:
                if line.startswith("lang="):
                    v = line.split("=", 1)[1].strip().lower()
                    if v in ("tr", "en"):
                        return v
    except OSError:
        pass
    loc = (
        os.environ.get("LC_ALL")
        or os.environ.get("LC_MESSAGES")
        or os.environ.get("LANG")
        or ""
    ).lower()
    return "tr" if loc.startswith("tr") else "en"


LANG = _detect_lang()


def save_lang(lang):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w") as fh:
        fh.write(f"lang={lang}\n")


# Kaynak dizeler İngilizce; Türkçe karşılıkları burada.
TR = {
    'Only the domains in the list go through the engine; the rest of your traffic is untouched.': 'Yalnızca listedeki alan adları motordan geçer; normal trafiğiniz etkilenmez.',
    'If your ISP tampers with DNS, zapret alone is not enough. Queries are carried over an encrypted channel.': "ISS'niz DNS'e müdahale ediyorsa zapret tek başına yetmez. Sorgular şifreli kanaldan taşınır.",
    'Blockcheck tries dozens of strategies; it can take several minutes and the engine is stopped while it runs. The result is written to the blockcheck strategy automatically.': "Blockcheck onlarca strateji dener; birkaç dakika sürebilir ve bu sırada motor geçici olarak durdurulur. Sonuç otomatik olarak 'Analiz Sonucu' stratejisine yazılır.",
    'Language': 'Dil',
    'diagnostics': 'ortam teşhisi',
    '(could not read the strategy list)': '(strateji listesi okunamadı)',
    'A conflicting DPI tool is running': 'Çakışan bir DPI aracı çalışıyor',
    'ACTIVE': 'AKTİF',
    'APPLY SETTINGS': 'AYARLARI UYGULA',
    'About': 'Hakkında',
    'Analyze': 'Analiz Et',
    'Another operation is in progress': 'Başka bir işlem sürüyor',
    'Authorisation was not given': 'Yetki verilmedi',
    'Blockcheck result: {}': 'Analiz sonucu: {}',
    'Build / update engines': 'Motorları derle / güncelle',
    'CHECKING…': 'KONTROL EDİLİYOR…',
    'Cancel': 'Vazgeç',
    'Checks the encrypted channel and interference': 'Şifreli kanal ve müdahale kontrolü',
    'Conflicting DPI tool running: {}': 'Çakışan DPI aracı çalışıyor: {}',
    'DNS check': 'DNS kontrolü',
    'DNS is being tampered with - use DoH/DoT': 'DNS müdahalesi var — DoH/DoT kullanın',
    'DNS is encrypted and clean': 'DNS şifreli ve temiz',
    'DNS looks clean': 'DNS temiz görünüyor',
    'DNS result: {}': 'DNS sonucu: {}',
    'DNS test': 'DNS sınaması',
    'Diagnostics': 'Ortam teşhisi',
    'Diagnostics finished': 'Teşhis tamamlandı',
    'ENGINE NOT BUILT': 'MOTOR DERLENMEMİŞ',
    'Edit lists': 'Listeleri düzenle',
    'Enables the systemd unit': 'systemd birimi olarak etkinleştirir',
    'Encrypted DNS': 'Şifreli DNS',
    'Encrypted DNS is off': 'Şifreli DNS kapalı',
    'Encrypted, but interference result: {}': 'Şifreli, ama müdahale sonucu: {}',
    'Engine': 'Motor',
    'Engine and strategy': 'Motor ve Strateji',
    'Filtering': 'Filtreleme',
    'For DoH: install the dnscrypt-proxy package': 'DoH için: dnscrypt-proxy paketini kurun',
    'Gateway mode': 'Ağ geçidi modu',
    'Hostlist mode': 'Hostlist modu',
    'How do I configure the device?': 'Cihaz ayarları nasıl yapılır?',
    'INSTALLATION INCOMPLETE': 'KURULUM EKSİK',
    'ISP analysis (blockcheck)': 'ISS Analizi (blockcheck)',
    'LAN address': 'LAN adresi',
    'Looks for a strategy that works on your ISP (can take a while)': 'Operatörünüz için çalışan stratejiyi arar (uzun sürebilir)',
    'Method': 'Yöntem',
    'Open folder': 'Klasörü Aç',
    'Output': 'Çıktı',
    'Problems found, see the output': 'Sorun bulundu, çıktıya bakın',
    'Provider': 'Sağlayıcı',
    'READY': 'HAZIR',
    'Refresh': 'Yenile',
    'Route console, TV and similar devices through this machine': 'Konsol, TV vb. cihazları bu makine üzerinden geçir',
    'SERVICE MODE ACTIVE': 'SERVİS MODU AKTİF',
    'START': 'BAŞLAT',
    'STOP': 'DURDUR',
    'Service': 'Servis',
    'Share with devices on your network': 'Ağdaki Cihazlarla Paylaş',
    'Shut down': 'Kapat',
    'Start': 'Başlat',
    'Start at boot': 'Açılışta otomatik başlat',
    'Start the ISP analysis?': 'ISS analizi başlatılsın mı?',
    'Strategy': 'Strateji',
    'Test': 'Sına',
    'The operation failed (see the output)': 'İşlem hata ile bitti (çıktıya bakın)',
    'Unwall': 'Unwall',
    'A new version is available: {}': 'Yeni bir sürüm var: {}',
    'View release': 'Sürümü görüntüle',
    'Check for updates': 'Güncellemeleri denetle',
    "You're up to date ({})": 'Güncelsiniz ({})',
    'Could not check for updates (offline?)': "Güncelleme kontrolü yapılamadı (çevrimdışı olabilir)",
    'build engines': 'motorları derle',
    'disable encrypted DNS': 'şifreli DNS kapat',
    'enable encrypted DNS': 'şifreli DNS aç',
    'gateway mode': 'ağ geçidi',
    'install service': 'servis kur',
    'none yet (run blockcheck)': 'yok (önce blockcheck)',
    'not applied → {}   (currently: {})': 'uygulanmadı → {}   (şu an: {})',
    'off · currently: {}': 'kapalı · şu an: {}',
    'remove service': 'servisi kaldır',
    'restart': 'yeniden başlat',
    'shut down conflicting tools': 'çakışanları kapat',
    'start': 'başlat',
    'stop': 'durdur',
    '{} is configured but not active': '{} yapılandırıldı ama etkin değil',
    '{} not found. Run install.sh.': '{} bulunamadı. install.sh çalıştırın.',
}


def T(text):
    """Kaynak dizeyi geçerli dile çevirir. Ad '_' olamaz: kod içinde '_'
    kullanılmayan değişken olarak da geçiyor ve fonksiyonu gölgeliyordu."""
    return TR.get(text, text) if LANG == "tr" else text

# Terminalden çalıştırıldığında her şey konsola aksın. Ayrıntı için:
#   UW_DEBUG=1 unwall
logging.basicConfig(
    level=logging.DEBUG if os.environ.get("UW_DEBUG") else logging.INFO,
    format="%(asctime)s %(levelname)-7s %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
log = logging.getLogger("unwall")


def _excepthook(exc_type, exc, tb):
    """Yakalanmamış hatalar sessizce yutulmasın."""
    log.error("UNCAUGHT ERROR:\n%s", "".join(traceback.format_exception(exc_type, exc, tb)))


sys.excepthook = _excepthook

# Flatpak paketi yalnızca bu arayüzü içerir; unwallctl, systemd birimi ve
# nftables kuralları host sistemde native olarak kurulu olmalıdır (bkz.
# install.sh / .deb / .rpm / PKGBUILD). Sandbox içindeysek her komutu
# `flatpak-spawn --host` ile host'a yolluyoruz; UW_FORCE_FLATPAK=1 bu
# davranışı sandbox dışında da test etmek için kullanılabilir.
IN_FLATPAK = os.path.exists("/.flatpak-info") or os.environ.get("UW_FORCE_FLATPAK") == "1"
HOST_PREFIX = ["flatpak-spawn", "--host"] if IN_FLATPAK else []

if IN_FLATPAK:
    # Sandbox içinde shutil.which() ve varsayılan mutlak yollar host'u
    # göremez; komut adını host'un PATH'ine bırakıyoruz.
    CTL = os.environ.get("UW_CTL", "unwallctl")
else:
    CTL = os.environ.get("UW_CTL", shutil.which("unwallctl") or "/usr/local/bin/unwallctl")
ETC_DIR = os.environ.get("UW_ETC", "/etc/unwall")

HOSTLIST_MODES = [
    ("auto", T("Automatic (zapret learns)")),
    ("manual", T("Manual (hostlist.txt)")),
    ("off", T("Off (all traffic)")),
]

ENGINES = [
    ("zapret2", T("Zapret2 (new LUA engine)")),
    ("zapret", T("Zapret (classic engine)")),
]

DNS_PROVIDERS = [
    ("cloudflare", "Cloudflare (1.1.1.1)"),
    ("google", "Google (8.8.8.8)"),
    ("quad9", "Quad9 (9.9.9.9)"),
]

DNS_BACKENDS = [
    ("auto", T("Automatic")),
    ("dnscrypt", T("DoH - dnscrypt-proxy (443, blends in)")),
    ("resolved", T("DoT - systemd-resolved (853)")),
]

GATEWAY_HELP_EN = (
    "This machine becomes a NAT router for your local network, so console and "
    "TV traffic goes through zapret as well.\n\n"
    "Enter these manually in the device's network settings:\n"
    "  • Gateway: this computer's LAN IP address\n"
    "  • Subnet mask: same as your network (usually 255.255.255.0)\n"
    "  • DNS: 1.1.1.1 / 8.8.8.8\n\n"
    "The go-pcap2socks + Npcap layer used on Windows is not needed; routing "
    "and NAT are done by the kernel."
)

GATEWAY_HELP_TR = (
    "Bu makine yerel ağdaki cihazlar için NAT yapan bir yönlendiriciye dönüşür; "
    "konsol/TV trafiği de zapret'ten geçer.\n\n"
    "Cihazın ağ ayarlarına elle şunları girin:\n"
    "  • Ağ geçidi (Gateway): bu bilgisayarın LAN IP adresi\n"
    "  • Alt ağ maskesi: ağınızla aynı (genelde 255.255.255.0)\n"
    "  • DNS: 1.1.1.1 / 8.8.8.8\n\n"
    "Windows sürümündeki go-pcap2socks + Npcap katmanına gerek yoktur; "
    "yönlendirme ve NAT çekirdek tarafından yapılır."
)

GATEWAY_HELP = GATEWAY_HELP_TR if LANG == "tr" else GATEWAY_HELP_EN


def ctl(*args, timeout=15):
    """Yetki gerektirmeyen ctl çağrısı. (çıkış kodu, çıktı) döner."""
    try:
        env = dict(os.environ, UW_LANG=LANG)
        p = subprocess.run(
            [*HOST_PREFIX, CTL, f"--lang={LANG}", *args],
            capture_output=True, text=True, timeout=timeout, env=env,
        )
        out = (p.stdout or "") + (p.stderr or "")
        if p.returncode == 0:
            log.debug("ctl %s -> 0", " ".join(args))
        else:
            log.warning("ctl %s -> %s\n%s", " ".join(args), p.returncode, out.strip())
        return p.returncode, out
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.error("could not run ctl %s: %s", " ".join(args), exc)
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
        super().__init__(application=app, title=T("Unwall"))
        self.set_default_size(520, 760)
        self.status = {}
        self.config = {}
        self.strategies = []
        self._busy = False
        self._refreshing = False
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
        menu.append(T("Diagnostics"), "win.doctor")
        menu.append(T("DNS check"), "win.dnscheck")
        menu.append(T("Build / update engines"), "win.build")
        menu.append(T("Check for updates"), "win.check-updates")
        menu.append(T("About"), "win.about")

        lang_menu = Gio.Menu()
        lang_menu.append("English", "win.lang-en")
        lang_menu.append("Türkçe", "win.lang-tr")
        menu.append_submenu(T("Language"), lang_menu)
        btn_menu = Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu)
        header.pack_end(btn_menu)

        btn_refresh = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text=T("Refresh"))
        btn_refresh.connect("clicked", lambda *_: self.refresh())
        header.pack_start(btn_refresh)

        for name, cb in (
            ("doctor", self.on_doctor),
            ("dnscheck", self.on_dnscheck),
            ("build", self.on_build),
            ("about", self.on_about),
            ("check-updates", self.on_check_updates),
            ("lang-en", lambda *_a: self.set_language("en")),
            ("lang-tr", lambda *_a: self.set_language("tr")),
        ):
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)

        # Çakışan başka bir DPI aracı varsa üstte uyarı çubuğu
        self.banner = Adw.Banner(
            title=T("A conflicting DPI tool is running"),
            button_label=T("Shut down"),
            revealed=False,
        )
        self.banner.connect(
            "button-clicked",
            lambda *_: self.run_privileged(
                ["disable-conflicts"], title=T("shut down conflicting tools")
            ),
        )
        toolbar.add_top_bar(self.banner)

        # Yeni sürüm çıktıysa üstte ikinci bir bant (çakışma bandından ayrı,
        # ikisi aynı anda görünebilir)
        self.update_banner = Adw.Banner(
            title="",
            button_label=T("View release"),
            revealed=False,
        )
        self._update_url = ""
        self.update_banner.connect("button-clicked", self._on_update_banner_clicked)
        toolbar.add_top_bar(self.update_banner)

        page = Adw.PreferencesPage()
        toolbar.set_content(page)

        # --- Durum ---
        g_status = Adw.PreferencesGroup()
        page.add(g_status)

        self.lbl_state = Gtk.Label(label=T("CHECKING…"))
        self.lbl_state.add_css_class("title-1")
        self.lbl_sub = Gtk.Label(label="")
        self.lbl_sub.add_css_class("dim-label")
        self.lbl_sub.set_wrap(True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_top(8)
        box.set_margin_bottom(12)
        box.append(self.lbl_state)
        box.append(self.lbl_sub)

        self.btn_main = Gtk.Button(label=T("START"))
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
        g_engine = Adw.PreferencesGroup(title=T("Engine and strategy"))
        page.add(g_engine)

        self.row_engine = Adw.ComboRow(title=T("Engine"))
        self.row_engine.set_model(Gtk.StringList.new([label for _, label in ENGINES]))
        self.row_engine.connect("notify::selected", self.on_engine_changed)
        g_engine.add(self.row_engine)

        self.row_strategy = Adw.ComboRow(title=T("Strategy"))
        self.row_strategy.connect("notify::selected", lambda *_: self.mark_dirty())
        g_engine.add(self.row_strategy)

        self.row_blockcheck = Adw.ActionRow(
            title=T("ISP analysis (blockcheck)"),
            subtitle=T("Looks for a strategy that works on your ISP (can take a while)"),
        )
        btn_bc = Gtk.Button(label=T("Analyze"), valign=Gtk.Align.CENTER)
        btn_bc.connect("clicked", self.on_blockcheck)
        self.row_blockcheck.add_suffix(btn_bc)
        self.row_blockcheck.set_activatable_widget(btn_bc)
        g_engine.add(self.row_blockcheck)

        # --- Filtreleme ---
        g_filter = Adw.PreferencesGroup(
            title=T("Filtering"),
            description=T(
                "Only the domains in the list go through the engine; the rest "
                "of your traffic is untouched."
            ),
        )
        page.add(g_filter)

        self.row_hostlist = Adw.ComboRow(title=T("Hostlist mode"))
        self.row_hostlist.set_model(Gtk.StringList.new([l for _, l in HOSTLIST_MODES]))
        self.row_hostlist.connect("notify::selected", lambda *_: self.mark_dirty())
        g_filter.add(self.row_hostlist)

        row_edit = Adw.ActionRow(title=T("Edit lists"), subtitle=ETC_DIR)
        btn_open = Gtk.Button(label=T("Open folder"), valign=Gtk.Align.CENTER)
        btn_open.connect("clicked", self.on_open_conf_dir)
        row_edit.add_suffix(btn_open)
        g_filter.add(row_edit)

        # --- Şifreli DNS ---
        g_dns = Adw.PreferencesGroup(
            title=T("Encrypted DNS"),
            description=T(
                "If your ISP tampers with DNS, zapret alone is not enough. "
                "Queries are carried over an encrypted channel."
            ),
        )
        page.add(g_dns)

        self.row_dns = Adw.SwitchRow(title=T("Encrypted DNS"), subtitle="—")
        self.row_dns.connect("notify::active", lambda *_: self.on_dns_toggled())
        g_dns.add(self.row_dns)

        self.row_dns_provider = Adw.ComboRow(title=T("Provider"))
        self.row_dns_provider.set_model(Gtk.StringList.new([l for _, l in DNS_PROVIDERS]))
        self.row_dns_provider.connect("notify::selected", lambda *_: self.on_dns_reapply())
        g_dns.add(self.row_dns_provider)

        self.row_dns_backend = Adw.ComboRow(title=T("Method"))
        self.row_dns_backend.set_model(Gtk.StringList.new([l for _, l in DNS_BACKENDS]))
        self.row_dns_backend.connect("notify::selected", lambda *_: self.on_dns_reapply())
        g_dns.add(self.row_dns_backend)

        row_dns_test = Adw.ActionRow(
            title=T("DNS test"), subtitle=T("Checks the encrypted channel and interference")
        )
        btn_dns_test = Gtk.Button(label=T("Test"), valign=Gtk.Align.CENTER)
        btn_dns_test.connect("clicked", self.on_dns_test)
        row_dns_test.add_suffix(btn_dns_test)
        row_dns_test.set_activatable_widget(btn_dns_test)
        g_dns.add(row_dns_test)

        # --- Ağ geçidi ---
        g_gw = Adw.PreferencesGroup(title=T("Share with devices on your network"))
        page.add(g_gw)

        self.row_gateway = Adw.SwitchRow(
            title=T("Gateway mode"),
            subtitle=T("Route console, TV and similar devices through this machine"),
        )
        self.row_gateway.connect("notify::active", lambda *_: self.on_gateway_toggled())
        g_gw.add(self.row_gateway)

        self.row_gw_info = Adw.ActionRow(title=T("LAN address"), subtitle="—")
        g_gw.add(self.row_gw_info)

        exp = Adw.ExpanderRow(title=T("How do I configure the device?"))
        lbl = Gtk.Label(label=GATEWAY_HELP, wrap=True, xalign=0)
        lbl.set_margin_start(12)
        lbl.set_margin_end(12)
        lbl.set_margin_top(8)
        lbl.set_margin_bottom(8)
        exp.add_row(lbl)
        g_gw.add(exp)

        # --- Otomatik başlatma ---
        g_svc = Adw.PreferencesGroup(title=T("Service"))
        page.add(g_svc)

        self.row_autostart = Adw.SwitchRow(
            title=T("Start at boot"),
            subtitle=T("Enables the systemd unit"),
        )
        self.row_autostart.connect("notify::active", lambda *_: self.on_autostart_toggled())
        g_svc.add(self.row_autostart)

        # --- Konsol ---
        g_log = Adw.PreferencesGroup(title=T("Output"))
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
        # Sürüm kontrolü ilk yenilemeyi bekletmesin diye biraz sonra başlar.
        GLib.timeout_add_seconds(2, self._start_update_check)

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
        log.debug("pending change: %s", " ".join(self.pending_config()))
        self.btn_main.set_label(
            T("APPLY SETTINGS") if self.status.get("running") == "1" else T("START")
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
            self.toast(T("Another operation is in progress"))
            return
        self._busy = True
        self.progress.set_visible(True)
        self.progress.pulse()
        self._pulse_id = GLib.timeout_add(120, self._pulse)
        if title:
            self.log(f"\n=== {title} ===")

        try:
            # Sandbox içinde pkexec'in kendisi de host'ta çalışmalı: sistemin
            # gerçek polkit ajanı böyle devreye girer. Sandbox'ın kendi
            # pkexec'i (varsa) host polkit'e erişemez.
            proc = Gio.Subprocess.new(
                [*HOST_PREFIX, "pkexec", CTL, f"--lang={LANG}", *args],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
            )
        except GLib.Error as exc:
            self._finish_busy()
            self.log(f"could not start: {exc.message}")
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
                self.log(f"read error: {exc.message}")
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
                self.toast(T("Authorisation was not given"))
            elif code != 0:
                self.toast(T("The operation failed (see the output)"))
            log.info("operation finished (exit code %s)", code)
            if code == 0:
                self._dirty = False
            if done:
                done(code)
            self.refresh()

        stream.read_line_async(GLib.PRIORITY_DEFAULT, None, on_line)

    # -----------------------------------------------------------------
    # GitHub sürüm kontrolü
    # -----------------------------------------------------------------

    def _start_update_check(self, force=False, notify=False):
        """Günde bir kez ağa çıkar; aradaki başlatmalarda önbelleği kullanır."""
        if not force:
            cached = self._load_update_cache()
            if cached and (time.time() - cached.get("checked_at", 0)) < UPDATE_CHECK_INTERVAL:
                log.debug("update check: using cached result from %s", cached.get("checked_at"))
                self._apply_update_result(cached)
                return False

        try:
            proc = Gio.Subprocess.new(
                [*HOST_PREFIX, CTL, "update-check", "8"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
            )
        except GLib.Error as exc:
            log.debug("update check could not start: %s", exc.message)
            if notify:
                self.toast(T("Could not check for updates (offline?)"))
            return False

        proc.communicate_utf8_async(None, None, self._on_update_check_done, notify)
        return False

    def _on_update_check_done(self, proc, res, notify=False):
        try:
            ok, stdout, _stderr = proc.communicate_utf8_finish(res)
        except GLib.Error as exc:
            log.debug("update check failed: %s", exc.message)
            if notify:
                self.toast(T("Could not check for updates (offline?)"))
            return
        if not ok:
            if notify:
                self.toast(T("Could not check for updates (offline?)"))
            return
        info = parse_kv(stdout)
        info["checked_at"] = time.time()
        self._save_update_cache(info)
        self._apply_update_result(info)
        if notify and info.get("update_available") != "1":
            self.toast(T("You're up to date ({})").format(info.get("current", VERSION)))

    def on_check_updates(self, *_a):
        self._start_update_check(force=True, notify=True)

    def _load_update_cache(self):
        try:
            with open(UPDATE_CACHE_FILE) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None

    def _save_update_cache(self, info):
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(UPDATE_CACHE_FILE, "w") as fh:
                json.dump(info, fh)
        except OSError as exc:
            log.debug("could not write update cache: %s", exc)

    def _apply_update_result(self, info):
        if info.get("update_available") != "1" or not info.get("latest"):
            return
        self._update_url = info.get(
            "url", "https://github.com/WinTone01/Unwall/releases/latest"
        )
        self.update_banner.set_title(
            T("A new version is available: {}").format(info["latest"])
        )
        self.update_banner.set_revealed(True)
        log.info("update available: %s -> %s", info.get("current"), info["latest"])

    def _on_update_banner_clicked(self, *_):
        if self._update_url:
            Gio.AppInfo.launch_default_for_uri(self._update_url, None)
        self.update_banner.set_revealed(False)

    # -----------------------------------------------------------------
    # durum yenileme
    # -----------------------------------------------------------------

    def _tick(self):
        # Yenileme hâlâ sürüyorsa üstüne binme: ctl çağrıları ana döngüde
        # çalışıyor, takılan bir çağrı arayüzü dondurur.
        if not self._busy and not self._refreshing:
            self.refresh()
        return True

    def refresh(self):
        self._refreshing = True
        try:
            self._refresh()
        finally:
            self._refreshing = False

    def _refresh(self):
        code, out = ctl("status", timeout=POLL_TIMEOUT)
        if code != 0 and not out.strip():
            self.lbl_state.set_label(T("INSTALLATION INCOMPLETE"))
            self.lbl_sub.set_label(T("{} not found. Run install.sh.").format(CTL))
            self.btn_main.set_sensitive(False)
            return
        self.status = parse_kv(out)
        _, cfg_out = ctl("config", "get", timeout=POLL_TIMEOUT)
        self.config = parse_kv(cfg_out)

        # Bekleyen (henüz uygulanmamış) bir seçim varsa kontrollere dokunma;
        # yoksa periyodik yenileme kullanıcının seçimini geri alırdı.
        self._loading = True
        if self._dirty:
            engine = ENGINES[self.row_engine.get_selected()][0]
            log.debug("pending change, not refreshing the controls")
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
            self.lbl_state.set_label(T("SERVICE MODE ACTIVE"))
        elif running:
            self.lbl_state.set_label(T("ACTIVE"))
        elif not ready:
            self.lbl_state.set_label(T("ENGINE NOT BUILT"))
        else:
            self.lbl_state.set_label(T("READY"))

        strat = self.config.get("STRATEGY", "?")
        if strat == "analiz":
            custom = self.config.get("CUSTOM_ARGS", "")
            strat = T("Blockcheck result: {}").format(custom or T("none yet (run blockcheck)"))
        sub = f"{engine} · {strat} · hostlist: {self.config.get('HOSTLIST_MODE', '?')}"
        if self._dirty:
            idx = self.row_strategy.get_selected()
            pend = self.strategies[idx][1] if 0 <= idx < len(self.strategies) else "?"
            sub = T("not applied → {}   (currently: {})").format(pend, sub)
        self.lbl_sub.set_label(sub)

        self.btn_main.set_sensitive(ready)
        if self._dirty:
            self.btn_main.set_label(
                T("APPLY SETTINGS") if running else T("START")
            )
        else:
            self.btn_main.set_label(T("STOP") if running else T("START"))
        if running:
            self.btn_main.remove_css_class("suggested-action")
            self.btn_main.add_css_class("destructive-action")
        else:
            self.btn_main.remove_css_class("destructive-action")
            self.btn_main.add_css_class("suggested-action")

        _, conf_out = ctl("conflicts", timeout=POLL_TIMEOUT)
        conflicts = parse_kv(conf_out).get("conflicts", "")
        self.banner.set_revealed(bool(conflicts))
        if conflicts:
            self.banner.set_title(T("Conflicting DPI tool running: {}").format(conflicts))

        _, gw = ctl("gateway-info", timeout=POLL_TIMEOUT)
        gwd = parse_kv(gw)
        self.row_gw_info.set_subtitle(
            f"{gwd.get('lan') or gwd.get('wan_ip') or '—'}  (WAN: {gwd.get('wan_iface') or '—'})"
        )

    def _refresh_dns(self):
        _, out = ctl("dns", "status", timeout=POLL_TIMEOUT)
        d = parse_kv(out)
        self.dns = d
        backend = d.get("backend", "none")
        on = backend != "none"
        self.row_dns.set_active(on)

        if on and d.get("encrypted") != "1":
            sub = T("{} is configured but not active").format(backend)
        elif on:
            sub = f"{backend} · {d.get('servers', '').strip() or '—'}"
        else:
            sub = T("off · currently: {}").format(d.get("servers", "").strip() or "—")
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
                T("For DoH: install the dnscrypt-proxy package")
            )
        else:
            self.row_dns_backend.set_subtitle("")

        self.row_dns_provider.set_sensitive(on)
        self.row_dns_backend.set_sensitive(on)

    def _load_strategies(self, engine, selected):
        code, out = ctl("strategies", engine, timeout=POLL_TIMEOUT)
        self.strategies = []
        labels = []
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                self.strategies.append((parts[0], parts[1]))
                labels.append(parts[1])
        if not labels:
            labels = [T("(could not read the strategy list)")]
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
            if self.btn_main.get_label() == T("APPLY SETTINGS"):
                self.run_privileged(["restart", *self.pending_config()], title=T("restart"))
            else:
                self.run_privileged(["stop"], title=T("stop"))
        else:
            self.run_privileged(["start", *self.pending_config()], title=T("start"))

    def on_autostart_toggled(self):
        if self._loading:
            return
        if self.row_autostart.get_active():
            self.run_privileged(["enable", *self.pending_config()], title=T("install service"))
        else:
            self.run_privileged(["disable"], title=T("remove service"))

    def on_gateway_toggled(self):
        if self._loading:
            return
        self.mark_dirty()
        if self.status.get("running") == "1":
            self.run_privileged(["restart", *self.pending_config()], title=T("gateway mode"))

    def on_dns_toggled(self):
        if self._loading:
            return
        if self.row_dns.get_active():
            provider = DNS_PROVIDERS[self.row_dns_provider.get_selected()][0]
            backend = DNS_BACKENDS[self.row_dns_backend.get_selected()][0]
            self.run_privileged(
                ["dns", "enable", provider, backend], title=T("enable encrypted DNS")
            )
        else:
            self.run_privileged(["dns", "disable"], title=T("disable encrypted DNS"))

    def on_dns_reapply(self):
        # Sağlayıcı/yöntem yalnızca DNS açıkken anlamlı; açıkken değişiklik
        # doğrudan yeniden uygulanır.
        if self._loading or not self.row_dns.get_active():
            return
        self.on_dns_toggled()

    def on_dns_test(self, *_):
        self.log("\n=== " + T("DNS test") + " ===")
        code, out = ctl("dns", "test", timeout=30)
        self.log(out.strip())
        d = parse_kv(out)
        if d.get("encrypted") == "1" and d.get("poisoning") == "ok":
            self.toast(T("DNS is encrypted and clean"))
        elif d.get("encrypted") == "1":
            self.toast(T("Encrypted, but interference result: {}").format(d.get("poisoning")))
        else:
            self.toast(T("Encrypted DNS is off"))

    def on_blockcheck(self, *_):
        engine = ENGINES[self.row_engine.get_selected()][0]
        heading = T("Start the ISP analysis?")
        body = T(
            "Blockcheck tries dozens of strategies; it can take several "
            "minutes and the engine is stopped while it runs. The result is "
            "written to the blockcheck strategy automatically."
        )

        def on_resp(_d, resp):
            if resp == "run":
                self.run_privileged(["blockcheck", engine], title=f_("blockcheck ({engine})"))

        # libadwaita 1.5+ AlertDialog, eski sürümlerde MessageDialog
        if hasattr(Adw, "AlertDialog"):
            dlg = Adw.AlertDialog(heading=heading, body=body)
            dlg.add_response("cancel", T("Cancel"))
            dlg.add_response("run", T("Start"))
            dlg.set_response_appearance("run", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present(self)
        else:
            dlg = Adw.MessageDialog(transient_for=self, heading=heading, body=body)
            dlg.add_response("cancel", T("Cancel"))
            dlg.add_response("run", T("Start"))
            dlg.set_response_appearance("run", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present()

    def on_build(self, *_):
        self.run_privileged(["build", "all"], title=T("build engines"))

    def on_doctor(self, *_):
        code, out = ctl("doctor", timeout=40)
        self.log("\n=== " + T("diagnostics") + " ===")
        self.log(out.strip())
        self.toast(T("Diagnostics finished") if code == 0 else T("Problems found, see the output"))

    def on_dnscheck(self, *_):
        code, out = ctl("dnscheck", timeout=20)
        d = parse_kv(out)
        self.log("\n=== " + T("DNS check") + " ===")
        self.log(out.strip())
        result = d.get("result")
        if result == "ok":
            self.toast(T("DNS looks clean"))
        elif result == "poisoned":
            self.toast(T("DNS is being tampered with - use DoH/DoT"))
        else:
            self.toast(T("DNS result: {}").format(result))

    def set_language(self, lang):
        """Dili kaydeder ve pencereyi yeni dille yeniden kurar."""
        global LANG
        if lang == LANG:
            return
        save_lang(lang)
        LANG = lang
        log.info("language switched to %s", lang)
        app = self.get_application()
        self.close()
        Window(app).present()

    def on_open_conf_dir(self, *_):
        # ETC_DIR sandbox dışında (host'ta) bir yol; içeriden doğrudan
        # file:// açmak Flatpak'ta portal reddiyle sonuçlanır. Host'un kendi
        # dosya yöneticisini flatpak-spawn ile tetikliyoruz.
        if IN_FLATPAK:
            try:
                subprocess.Popen([*HOST_PREFIX, "xdg-open", ETC_DIR])
            except OSError as exc:
                log.warning("could not open %s on host: %s", ETC_DIR, exc)
        else:
            Gio.AppInfo.launch_default_for_uri(f"file://{ETC_DIR}", None)

    def on_about(self, *_):
        kwargs = dict(
            application_name=T("Unwall"),
            application_icon=APP_ID,
            version=VERSION,
            comments=T(
                "Linux control panel for the bol-van/zapret and zapret2 engines.\n"
                "The Linux counterpart of the Windows version "
                "(zapret-win-bundle + AutoIt)."
            ),
            website="https://github.com/WinTone01/unwall",
            license_type=Gtk.License.GPL_3_0,
            developers=["Unwall contributors"],
        )
        if hasattr(Adw, "AboutDialog"):
            Adw.AboutDialog(**kwargs).present(self)
        else:
            Adw.AboutWindow(transient_for=self, **kwargs).present()


class App(Adw.Application):
    def __init__(self):
        flags = Gio.ApplicationFlags.DEFAULT_FLAGS
        # UW_NO_UNIQUE=1 ile her çalıştırma kendi penceresini açar; hata
        # ayıklarken çalışan örneğe devredilmesini istemediğimizde işe yarar.
        if os.environ.get("UW_NO_UNIQUE"):
            flags |= Gio.ApplicationFlags.NON_UNIQUE
        super().__init__(application_id=APP_ID, flags=flags)

    def do_activate(self):
        log.debug("application activated")
        win = self.props.active_window or Window(self)
        win.present()


def main():
    if os.geteuid() == 0:
        log.error("Do not run this GUI as root; privileged actions go "
                  "through pkexec.")
        return 1

    log.info("Unwall %s starting (lang: %s, ctl: %s)", VERSION, LANG, CTL)
    if IN_FLATPAK:
        # CTL burada host PATH'inde aranacak çıplak bir komut adı; sandbox
        # içinden os.path.exists() ile denetlemek anlamsız, hep yanlış
        # "bulunamadı" sonucu verir. Varlığını flatpak-spawn ile kontrol
        # ediyoruz.
        found = subprocess.run(
            [*HOST_PREFIX, "sh", "-c", f"command -v {CTL}"],
            capture_output=True,
        ).returncode == 0
        if not found:
            log.error(
                "%s not found on the host. Install the native backend first "
                "(install.sh or one of the packages under packaging/).", CTL
            )
    elif not os.path.exists(CTL):
        log.error("%s not found. Run: sudo ./install.sh", CTL)

    app = App()
    try:
        app.register(None)
    except GLib.Error as exc:
        log.error("could not register the application: %s", exc.message)
        return 1
    if app.get_is_remote():
        pid = ""
        try:
            pid = subprocess.run(
                ["pgrep", "-f", r"python.*unwall_gui\.py"], capture_output=True, text=True
            ).stdout.split()
            pid = pid[0] if pid else ""
        except OSError:
            pass
        log.warning(
            "an Unwall window is already running%s; it will be raised instead.",
            f" (pid {pid})" if pid else "",
        )
        log.warning(
            "if no window appears, that instance is stuck: kill %s  "
            "(or: pkill -f unwall_gui.py), then start again. For a separate "
            "instance with logs in this terminal: UW_NO_UNIQUE=1 unwall",
            pid or "<pid>",
        )
    return app.run(None)


if __name__ == "__main__":
    raise SystemExit(main())
