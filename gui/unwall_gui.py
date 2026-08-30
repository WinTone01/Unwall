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
VERSION = "1.4.0"

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
UPDATE_REPO = "WinTone01/Unwall"

# "Şimdi güncelle" düğmesinin çalıştırdığı betik. $1 = repo, $2 = sürüm.
# unwallctl'in kendi self-update komutuyla aynı işi yapar ama ondan
# tamamen bağımsızdır: kurulu unwallctl eski (self-update'ten önceki bir
# sürüm) olsa bile çalışır.
UPDATE_BOOTSTRAP_SCRIPT = r"""
set -e
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "==> v$2 indiriliyor"
curl -fsSL "https://github.com/$1/archive/refs/tags/v$2.tar.gz" -o "$tmp/u.tar.gz"
tar -xzf "$tmp/u.tar.gz" -C "$tmp"
srcdir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
if [ -z "$srcdir" ] || [ ! -x "$srcdir/install.sh" ]; then
	echo "indirilen arşivde install.sh bulunamadı" >&2
	exit 1
fi
echo "==> v$2 kuruluyor"
"$srcdir/install.sh" --yes --no-deps --no-build
"""


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
    'Automatic (zapret learns)': 'Otomatik (zapret öğrenir)',
    'Manual (hostlist.txt)': 'Elle (hostlist.txt)',
    'Off (all traffic)': 'Kapalı (tüm trafik)',
    'Automatic': 'Otomatik',
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
    'Update now': 'Şimdi güncelle',
    'Update installed': 'Güncelleme kuruldu',
    'Restart Unwall now to use the new version?': "Yeni sürümü kullanmak için Unwall'ı şimdi yeniden başlatmak ister misiniz?",
    'Later': 'Sonra',
    'Restart now': 'Şimdi yeniden başlat',
    'Could not restart automatically; please reopen Unwall yourself.': 'Otomatik yeniden başlatılamadı; lütfen Unwall\'ı elle yeniden açın.',
    'update to {}': "{}'e güncelle",
    'Check for updates': 'Güncellemeleri denetle',
    "You're up to date ({})": 'Güncelsiniz ({})',
    'Could not check for updates (offline?)': "Güncelleme kontrolü yapılamadı (çevrimdışı olabilir)",
    'build engines': 'motorları derle',
    'disable encrypted DNS': 'şifreli DNS kapat',
    'enable encrypted DNS': 'şifreli DNS aç',
    'gateway mode: on': 'ağ geçidi modu: açık',
    'gateway mode: off': 'ağ geçidi modu: kapalı',
    # sayfalar
    'Status': 'Durum',
    'Settings': 'Ayarlar',
    'Lists': 'Listeler',
    'Log': 'Günlük',
    'Connection': 'Bağlantı',
    'Clear': 'Temizle',
    'Open config folder': 'Ayar klasörünü aç',
    # listeler
    'Add a domain': 'Alan adı ekle',
    'Subdomains are covered automatically: adding example.com also covers www.example.com.': 'Alt alan adları kendiliğinden kapsanır: example.com eklemek www.example.com\'u da kapsar.',
    'List': 'Liste',
    'example.com': 'ornek.com',
    'Add': 'Ekle',
    'Remove': 'Sil',
    '(empty)': '(boş)',
    'Manual list (hostlist.txt)': 'Elle liste (hostlist.txt)',
    'Auto-learned (autohostlist.txt)': 'Otomatik öğrenilen (autohostlist.txt)',
    'Excluded (excludelist.txt)': 'Hariç tutulan (excludelist.txt)',
    'add domain': 'alan adı ekle',
    'remove domain': 'alan adı sil',
    'Add or remove domains from the Lists tab': 'Alan adlarını "Listeler" sekmesinden ekleyip silin',
    # operatör tespiti
    'Detect carrier automatically': 'Operatörü otomatik algıla',
    'Looks up your ASN over encrypted DNS and suggests a profile': 'ASN bilginizi şifreli DNS üzerinden sorgulayıp profil önerir',
    'Detect': 'Algıla',
    'Detected carrier': 'Algılanan operatör',
    'carrier detection': 'operatör tespiti',
    'network changed': 'ağ değişti',
    'Detection failed': 'Tespit başarısız',
    'could not reach the lookup service': 'sorgu servisine ulaşılamadı',
    'No ready-made profile for this carrier': 'Bu operatör için hazır profil yok',
    'No ready-made profile for this carrier; use ISP analysis (blockcheck).': 'Bu operatör için hazır profil yok; ISS Analizi (blockcheck) kullanın.',
    'Already using the matching profile': 'Zaten uygun profil kullanılıyor',
    'Already using the matching profile: {}': 'Zaten uygun profil kullanılıyor: {}',
    'Network changed, switching to: {}': 'Ağ değişti, geçiliyor: {}',
    'Carrier detected': 'Operatör algılandı',
    'Switch to the {} profile?': '{} profiline geçilsin mi?',
    'Apply': 'Uygula',
    'Re-detect carrier when the network changes': 'Ağ değişince operatörü yeniden algıla',
    'When you move to another network, look the carrier up again and switch to its profile': 'Başka bir ağa geçtiğinizde operatörü yeniden sorgulayıp profiline geçer',
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

# "Listeler" sayfasındaki gruplar; kimlikler `unwallctl hostlist` komutunun
# beklediği adlarla birebir aynı olmalı.
LIST_TARGETS = [
    ("manual", T("Manual list (hostlist.txt)")),
    ("auto", T("Auto-learned (autohostlist.txt)")),
    ("exclude", T("Excluded (excludelist.txt)")),
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

# Ağ geçidi yardım sayfasındaki her bölüm: (başlık, {ip}/{mask} yer
# tutucularıyla gerçek değerlerin gireceği açıklama metni). Menü adları
# üreticiden üreticiye küçük farklar gösterebilir (Samsung/Xiaomi vb.);
# yol her zaman Wi-Fi ağının gelişmiş/statik IP ayarları altındadır.
GATEWAY_SECTIONS_EN = [
    (
        "Console / TV (PlayStation, Xbox, Switch, …)",
        "Enter these manually in the device's network settings:\n"
        "  • IP address: any free address on your network, e.g. 192.168.1.50\n"
        "  • Subnet mask: {mask}\n"
        "  • Gateway: {ip}\n"
        "  • DNS: any valid-looking value, e.g. 1.1.1.1 — most devices refuse "
        "an empty field, but the real value is overridden by Unwall's own "
        "redirect.",
    ),
    (
        "Android",
        "Settings → Network & Internet → Wi-Fi → tap your connected network "
        "→ edit (pencil icon) → IP settings: Static\n"
        "  • Gateway: {ip}\n"
        "  • Network prefix length: 24 (equivalent to subnet mask {mask})\n"
        "  • DNS 1: 1.1.1.1\n\n"
        "Menu wording varies by manufacturer, but the Static/Manual IP "
        "option is always under the Wi-Fi network's advanced settings.",
    ),
    (
        "iPhone / iPad",
        "Settings → Wi-Fi → tap the ⓘ next to your connected network → "
        "Configure IP → Manual\n"
        "  • IP Address: any free address on your network, e.g. 192.168.1.50\n"
        "  • Subnet Mask: {mask}\n"
        "  • Router: {ip}\n\n"
        "Then tap Configure DNS → Manual and add a DNS server, e.g. 1.1.1.1.",
    ),
]

GATEWAY_SECTIONS_TR = [
    (
        "Konsol / TV (PlayStation, Xbox, Switch, …)",
        "Cihazın ağ ayarlarına elle şunları girin:\n"
        "  • IP adresi: ağınızda boş bir adres, örn. 192.168.1.50\n"
        "  • Alt ağ maskesi: {mask}\n"
        "  • Ağ geçidi (Gateway): {ip}\n"
        "  • DNS: geçerli görünen herhangi bir değer, örn. 1.1.1.1 — çoğu "
        "cihaz DNS alanı boşken devam etmiyor, ama gerçek değer Unwall'ın "
        "kendi yönlendirmesiyle zaten geçersiz kılınıyor.",
    ),
    (
        "Android",
        "Ayarlar → Ağ ve İnternet → Wi-Fi → bağlı olduğunuz ağa dokunun "
        "→ düzenle (kalem simgesi) → IP ayarları: Statik\n"
        "  • Ağ geçidi (Gateway): {ip}\n"
        "  • Ağ öneki uzunluğu: 24 ({mask} alt ağ maskesine karşılık gelir)\n"
        "  • DNS 1: 1.1.1.1\n\n"
        "Menü adları üreticiye göre değişebilir, ama Statik/Manuel IP "
        "seçeneği her zaman Wi-Fi ağının gelişmiş ayarları altındadır.",
    ),
    (
        "iPhone / iPad",
        "Ayarlar → Wi-Fi → bağlı olduğunuz ağın yanındaki ⓘ simgesine "
        "dokunun → IP'yi Yapılandır → Manuel\n"
        "  • IP Adresi: ağınızda boş bir adres, örn. 192.168.1.50\n"
        "  • Alt Ağ Maskesi: {mask}\n"
        "  • Yönlendirici (Router): {ip}\n\n"
        "Ardından DNS'i Yapılandır → Manuel'e dokunup bir DNS sunucusu "
        "ekleyin, örn. 1.1.1.1.",
    ),
]

GATEWAY_SECTIONS = GATEWAY_SECTIONS_TR if LANG == "tr" else GATEWAY_SECTIONS_EN


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
        self._gw_ip = ""
        self._gw_mask = "255.255.255.0"
        self._carrier = ""
        # Ağ parmak izi: değiştiğinde (başka bir Wi-Fi'ye geçmek gibi)
        # operatör yeniden algılanır - bkz. _refresh().
        self._netfp = None
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
        menu.append(T("Open config folder"), "win.open-conf")
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
            ("open-conf", self.on_open_conf_dir),
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
            button_label=T("Update now"),
            revealed=False,
        )
        self._update_url = ""
        self._update_latest = ""
        self.update_banner.connect("button-clicked", self._on_update_banner_clicked)
        toolbar.add_top_bar(self.update_banner)

        # Sayfalar: Durum / Ayarlar / Listeler / Günlük. Tek uzun kaydırma
        # yerine ViewStack; başlıktaki ViewSwitcher geniş pencerede, alttaki
        # ViewSwitcherBar dar pencerede görünür (bkz. _on_resize).
        self.stack = Adw.ViewStack(vexpand=True)
        toolbar.set_content(self.stack)

        self.switcher = Adw.ViewSwitcher(
            stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE
        )
        header.set_title_widget(self.switcher)

        self.switcher_bar = Adw.ViewSwitcherBar(stack=self.stack, reveal=False)
        toolbar.add_bottom_bar(self.switcher_bar)

        # Dar pencerede sekmeler başlıktan alta iner. Pencere genişliğini elle
        # yoklamak yerine libadwaita'nın kendi breakpoint'i: koşul sağlanmadığı
        # anda ayarları kendiliğinden geri alıyor.
        bp = Adw.Breakpoint.new(Adw.BreakpointCondition.parse("max-width: 560px"))
        bp.add_setter(self.switcher, "visible", False)
        bp.add_setter(self.switcher_bar, "reveal", True)
        self.add_breakpoint(bp)

        # --- Durum sayfası ---
        page = self._page_status()

        # --- Ayarlar sayfası ---
        settings = Adw.PreferencesPage()

        # --- Motor / strateji ---
        g_engine = Adw.PreferencesGroup(title=T("Engine and strategy"))
        settings.add(g_engine)

        self.row_engine = Adw.ComboRow(title=T("Engine"))
        self.row_engine.set_model(Gtk.StringList.new([label for _, label in ENGINES]))
        self.row_engine.connect("notify::selected", self.on_engine_changed)
        g_engine.add(self.row_engine)

        self.row_strategy = Adw.ComboRow(title=T("Strategy"))
        self.row_strategy.connect("notify::selected", lambda *_: self.mark_dirty())
        g_engine.add(self.row_strategy)

        self.row_detect = Adw.ActionRow(
            title=T("Detect carrier automatically"),
            subtitle=T("Looks up your ASN over encrypted DNS and suggests a profile"),
        )
        btn_detect = Gtk.Button(label=T("Detect"), valign=Gtk.Align.CENTER)
        btn_detect.connect("clicked", self.on_detect_isp)
        self.row_detect.add_suffix(btn_detect)
        self.row_detect.set_activatable_widget(btn_detect)
        g_engine.add(self.row_detect)

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
        settings.add(g_filter)

        self.row_hostlist = Adw.ComboRow(title=T("Hostlist mode"))
        self.row_hostlist.set_model(Gtk.StringList.new([l for _, l in HOSTLIST_MODES]))
        self.row_hostlist.connect("notify::selected", lambda *_: self.mark_dirty())
        g_filter.add(self.row_hostlist)

        row_edit = Adw.ActionRow(
            title=T("Edit lists"),
            subtitle=T("Add or remove domains from the Lists tab"),
            activatable=True,
        )
        row_edit.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
        row_edit.connect(
            "activated", lambda *_: self.stack.set_visible_child_name("lists")
        )
        g_filter.add(row_edit)

        # --- Şifreli DNS ---
        g_dns = Adw.PreferencesGroup(
            title=T("Encrypted DNS"),
            description=T(
                "If your ISP tampers with DNS, zapret alone is not enough. "
                "Queries are carried over an encrypted channel."
            ),
        )
        settings.add(g_dns)

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
        settings.add(g_gw)

        self.row_gateway = Adw.SwitchRow(
            title=T("Gateway mode"),
            subtitle=T("Route console, TV and similar devices through this machine"),
        )
        self.row_gateway.connect("notify::active", lambda *_: self.on_gateway_toggled())
        g_gw.add(self.row_gateway)

        self.row_gw_info = Adw.ActionRow(title=T("LAN address"), subtitle="—")
        g_gw.add(self.row_gw_info)

        row_gw_help = Adw.ActionRow(
            title=T("How do I configure the device?"), activatable=True
        )
        row_gw_help.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
        row_gw_help.connect("activated", self.on_show_gateway_help)
        g_gw.add(row_gw_help)

        # --- Otomatik başlatma ---
        g_svc = Adw.PreferencesGroup(title=T("Service"))
        settings.add(g_svc)

        self.row_autostart = Adw.SwitchRow(
            title=T("Start at boot"),
            subtitle=T("Enables the systemd unit"),
        )
        self.row_autostart.connect("notify::active", lambda *_: self.on_autostart_toggled())
        g_svc.add(self.row_autostart)

        self.row_autodetect = Adw.SwitchRow(
            title=T("Re-detect carrier when the network changes"),
            subtitle=T(
                "When you move to another network, look the carrier up again "
                "and switch to its profile"
            ),
            active=self._autodetect_enabled(),
        )
        self.row_autodetect.connect(
            "notify::active", lambda *_: self._save_autodetect()
        )
        g_svc.add(self.row_autodetect)

        # --- Sayfaları kaydet ---
        self.stack.add_titled_with_icon(
            page, "status", T("Status"), "security-high-symbolic")
        self.stack.add_titled_with_icon(
            settings, "settings", T("Settings"), "preferences-system-symbolic")
        self.stack.add_titled_with_icon(
            self._page_lists(), "lists", T("Lists"), "view-list-symbolic")
        self.stack.add_titled_with_icon(
            self._page_log(), "log", T("Log"), "utilities-terminal-symbolic")

        self.refresh()
        self._refresh_lists()
        GLib.timeout_add_seconds(4, self._tick)
        # Sürüm kontrolü ilk yenilemeyi bekletmesin diye biraz sonra başlar.
        GLib.timeout_add_seconds(2, self._start_update_check)

    # -----------------------------------------------------------------
    # sayfalar
    # -----------------------------------------------------------------

    def _clamped(self, child):
        """Geniş ekranda satırlar okunamayacak kadar uzamasın."""
        clamp = Adw.Clamp(maximum_size=680, child=child)
        return Gtk.ScrolledWindow(child=clamp, vexpand=True)

    def _page_status(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                      margin_top=24, margin_bottom=24,
                      margin_start=12, margin_end=12)

        # İkon + üstünde dönen gösterge: bir işlem sürerken ikonun yerini
        # almak yerine üstüne biniyor, böylece yer değişmiyor.
        icon = Gtk.Image(icon_name=APP_ID, pixel_size=112,
                         halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.status_spinner = Gtk.Spinner(
            width_request=112, height_request=112,
            halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER, visible=False)
        overlay = Gtk.Overlay(width_request=112, height_request=112,
                              halign=Gtk.Align.CENTER)
        overlay.set_child(icon)
        overlay.add_overlay(self.status_spinner)
        box.append(overlay)

        self.lbl_state = Gtk.Label(label=T("CHECKING…"), halign=Gtk.Align.CENTER)
        self.lbl_state.add_css_class("title-1")
        box.append(self.lbl_state)

        self.lbl_sub = Gtk.Label(label="", halign=Gtk.Align.CENTER, wrap=True,
                                 justify=Gtk.Justification.CENTER)
        self.lbl_sub.add_css_class("dim-label")
        box.append(self.lbl_sub)

        self.btn_main = Gtk.Button(label=T("START"), halign=Gtk.Align.CENTER)
        self.btn_main.add_css_class("suggested-action")
        self.btn_main.add_css_class("pill")
        self.btn_main.set_size_request(200, 48)
        self.btn_main.connect("clicked", self.on_main_clicked)
        box.append(self.btn_main)

        self.progress = Gtk.ProgressBar(visible=False)
        box.append(self.progress)

        # Özet bilgiler: monospace alt başlıklı "property" satırları.
        g_info = Adw.PreferencesGroup(title=T("Connection"))
        self.info_rows = {}
        for key, title in (
            ("engine", T("Engine")),
            ("strategy", T("Strategy")),
            ("hostlist", T("Hostlist mode")),
            ("carrier", T("Detected carrier")),
        ):
            row = Adw.ActionRow(title=title, subtitle="—")
            row.add_css_class("property")
            self.info_rows[key] = row
            g_info.add(row)
        box.append(g_info)

        return self._clamped(box)

    def _page_lists(self):
        page = Adw.PreferencesPage()

        g_add = Adw.PreferencesGroup(
            title=T("Add a domain"),
            description=T(
                "Subdomains are covered automatically: adding example.com also "
                "covers www.example.com."
            ),
        )
        page.add(g_add)

        self.row_list_target = Adw.ComboRow(title=T("List"))
        self.row_list_target.set_model(
            Gtk.StringList.new([label for _, label in LIST_TARGETS]))
        g_add.add(self.row_list_target)

        self.entry_domain = Adw.EntryRow(title=T("example.com"))
        self.entry_domain.connect("entry-activated", lambda *_: self.on_add_domain())
        btn_add = Gtk.Button(icon_name="list-add-symbolic",
                             valign=Gtk.Align.CENTER,
                             tooltip_text=T("Add"))
        btn_add.add_css_class("flat")
        btn_add.connect("clicked", lambda *_: self.on_add_domain())
        self.entry_domain.add_suffix(btn_add)
        g_add.add(self.entry_domain)

        # Her liste için ayrı grup; içerikleri _refresh_lists() dolduruyor.
        self.list_groups = {}
        self.list_rows = {}
        for key, label in LIST_TARGETS:
            group = Adw.PreferencesGroup(title=label)
            self.list_groups[key] = group
            self.list_rows[key] = []
            page.add(group)

        return page

    def _page_log(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        self.buf = Gtk.TextBuffer()
        tv = Gtk.TextView(buffer=self.buf, editable=False, monospace=True,
                          cursor_visible=False,
                          wrap_mode=Gtk.WrapMode.WORD_CHAR,
                          top_margin=8, bottom_margin=8,
                          left_margin=12, right_margin=12)
        self.scroller = Gtk.ScrolledWindow(child=tv, vexpand=True)
        box.append(self.scroller)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8,
                      halign=Gtk.Align.END, margin_top=8, margin_bottom=8,
                      margin_start=12, margin_end=12)
        btn_clear = Gtk.Button(label=T("Clear"))
        btn_clear.connect("clicked", lambda *_: self.buf.set_text(""))
        bar.append(btn_clear)
        box.append(bar)

        return box

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

    def run_privileged(self, args, done=None, title=None, raw_argv=None):
        """pkexec ile ctl (ya da raw_argv verilmişse başka bir komut)
        çalıştırır, çıktıyı konsola akıtır."""
        if self._busy:
            self.toast(T("Another operation is in progress"))
            return
        self._busy = True
        self.progress.set_visible(True)
        self.progress.pulse()
        self.status_spinner.set_visible(True)
        self.status_spinner.start()
        self._pulse_id = GLib.timeout_add(120, self._pulse)
        if title:
            self.log(f"\n=== {title} ===")

        try:
            # Sandbox içinde pkexec'in kendisi de host'ta çalışmalı: sistemin
            # gerçek polkit ajanı böyle devreye girer. Sandbox'ın kendi
            # pkexec'i (varsa) host polkit'e erişemez.
            argv = (
                [*HOST_PREFIX, "pkexec", *raw_argv]
                if raw_argv is not None
                else [*HOST_PREFIX, "pkexec", CTL, f"--lang={LANG}", *args]
            )
            proc = Gio.Subprocess.new(
                argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
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
        self.status_spinner.stop()
        self.status_spinner.set_visible(False)

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

    def _installed_ctl_version(self):
        """unwallctl'in şu an raporladığı sürüm. Ağa çıkmaz, hızlıdır."""
        try:
            p = subprocess.run(
                [*HOST_PREFIX, CTL, "version"],
                capture_output=True, text=True, timeout=5,
            )
            return p.stdout.strip() or None
        except (OSError, subprocess.TimeoutExpired):
            return None

    def _start_update_check(self, force=False, notify=False):
        """Günde bir kez ağa çıkar; aradaki başlatmalarda önbelleği kullanır."""
        if not force:
            cached = self._load_update_cache()
            if cached and (time.time() - cached.get("checked_at", 0)) < UPDATE_CHECK_INTERVAL:
                installed = self._installed_ctl_version()
                # Kurulu unwallctl önbellekteki "current" ile uyuşmuyorsa
                # (self-update ya da elle install.sh ile güncellendi),
                # önbellek bayatlamış demektir - süresi dolmasa da atla.
                if installed is None or installed == cached.get("current"):
                    log.debug("update check: using cached result from %s", cached.get("checked_at"))
                    self._apply_update_result(cached)
                    return False
                log.debug(
                    "installed unwallctl changed (%s -> %s), cache invalidated",
                    cached.get("current"), installed,
                )

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
        self._update_latest = info["latest"]
        self.update_banner.set_title(
            T("A new version is available: {}").format(info["latest"])
        )
        self.update_banner.set_revealed(True)
        log.info("update available: %s -> %s", info.get("current"), info["latest"])

    def _on_update_banner_clicked(self, *_):
        if not self._update_latest:
            if self._update_url:
                Gio.AppInfo.launch_default_for_uri(self._update_url, None)
            return
        self.update_banner.set_revealed(False)
        # `unwallctl self-update` DEĞİL: eski bir kuruluma sahip birinin
        # düğmeye ilk bastığında kurulu unwallctl'de self-update henüz
        # olmayabilir (tam da güncellemesi gereken şey). Bu yüzden GUI
        # kendi indirme+kurulum betiğini doğrudan pkexec ile çalıştırır -
        # kurulu unwallctl'in sürümünden tamamen bağımsız, her zaman işler.
        self.run_privileged(
            [],
            title=T("update to {}").format(self._update_latest),
            raw_argv=["bash", "-c", UPDATE_BOOTSTRAP_SCRIPT, "bash",
                      UPDATE_REPO, self._update_latest],
            done=self._on_self_update_done,
        )

    def _on_self_update_done(self, code):
        if code != 0:
            return
        # Dosyalar diskte güncellendi ama bu pencere hâlâ eskiden yüklenmiş
        # Python kodunu belleğinde çalıştırıyor - Firefox/VSCode gibi, dosya
        # değişikliği kendiliğinden devreye girmez. unwallctl her komutta
        # yeni bir süreç olarak çalıştığı için o taraf zaten güncel; arayüz
        # tarafının güncellenmesi için yeniden başlatma gerekir.
        self._start_update_check(force=True)
        heading = T("Update installed")
        body = T("Restart Unwall now to use the new version?")

        def on_resp(_d, resp):
            if resp == "restart":
                self._restart_app()

        if hasattr(Adw, "AlertDialog"):
            dlg = Adw.AlertDialog(heading=heading, body=body)
            dlg.add_response("later", T("Later"))
            dlg.add_response("restart", T("Restart now"))
            dlg.set_response_appearance("restart", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present(self)
        else:
            dlg = Adw.MessageDialog(transient_for=self, heading=heading, body=body)
            dlg.add_response("later", T("Later"))
            dlg.add_response("restart", T("Restart now"))
            dlg.set_response_appearance("restart", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present()

    def _restart_app(self):
        # Bu, tekil örnekli (single-instance) bir GtkApplication: D-Bus'ta
        # APP_ID adını tutar. Önce yeni bir süreç başlatıp SONRA bunu
        # quit() etmek bir yarış durumuydu - eski süreç adı henüz
        # bırakmamışken yeni süreç başlarsa, GApplication onu ayrı bir
        # örnek olarak açmak yerine sadece eski (hâlâ eski kodu belleğinde
        # çalıştıran) örneği öne getiriyordu; kullanıcı elle kapatıp
        # tekrar açtığında eski süreç gerçekten sonlanmış olduğundan sorun
        # yaşanmıyordu. execvp mevcut süreç görüntüsünü yerinde
        # değiştirdiği için (D-Bus bağlantısı dahil) bu yarışı tamamen
        # ortadan kaldırıyor: "unwall" PATH üzerinden çözülür - Flatpak
        # içindeyken de bu, sandbox'ın kendi /app/bin/unwall'ına çözülür.
        try:
            os.execvp("unwall", ["unwall"])
        except OSError as exc:
            log.error("could not restart: %s", exc)
            self.toast(T("Could not restart automatically; please reopen Unwall yourself."))

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
        self._gw_ip = gwd.get("lan_ip") or gwd.get("wan_ip") or ""
        self._gw_mask = gwd.get("lan_mask") or "255.255.255.0"

        # Durum sayfasındaki özet satırları
        self.info_rows["engine"].set_subtitle(engine)
        self.info_rows["strategy"].set_subtitle(
            self.config.get("STRATEGY", "?"))
        self.info_rows["hostlist"].set_subtitle(
            self.config.get("HOSTLIST_MODE", "?"))
        self.info_rows["carrier"].set_subtitle(self._carrier or "—")

        # Ağ değişti mi? (arayüz + router + WAN IP)
        netfp = f"{gwd.get('wan_iface','')}|{gwd.get('router','')}|{gwd.get('wan_ip','')}"
        if self._netfp is None:
            self._netfp = netfp
        elif netfp != self._netfp:
            self._netfp = netfp
            log.info("network changed: %s", netfp)
            if self.row_autodetect.get_active() and not self._busy:
                self.log("\n=== " + T("network changed") + " ===")
                self._detect_isp(apply_silently=True)

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
            title = T("gateway mode: on") if self.row_gateway.get_active() \
                else T("gateway mode: off")
            self.run_privileged(["restart", *self.pending_config()], title=title)

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
                self.run_privileged(["blockcheck", engine], title=f"blockcheck ({engine})")

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

    # -----------------------------------------------------------------
    # operatör tespiti
    # -----------------------------------------------------------------

    def _autodetect_enabled(self):
        try:
            with open(CONFIG_FILE) as fh:
                return "autodetect=1" in fh.read()
        except OSError:
            return False

    def _save_autodetect(self):
        """gui.conf'u dil ayarını bozmadan güncelle."""
        want = self.row_autodetect.get_active()
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            lines = []
            try:
                with open(CONFIG_FILE) as fh:
                    lines = [l for l in fh.read().splitlines()
                             if not l.startswith("autodetect=")]
            except OSError:
                pass
            lines.append(f"autodetect={'1' if want else '0'}")
            with open(CONFIG_FILE, "w") as fh:
                fh.write("\n".join(lines) + "\n")
        except OSError as exc:
            log.warning("could not save autodetect setting: %s", exc)

    def on_detect_isp(self, *_):
        self.stack.set_visible_child_name("log")
        self.log("\n=== " + T("carrier detection") + " ===")
        self._detect_isp(apply_silently=False)

    def _detect_isp(self, apply_silently):
        """ASN'den operatörü bulur. apply_silently=True ise (ağ değişimi)
        bulunan profili doğrudan uygular; aksi halde kullanıcıya sorar."""
        code, out = ctl("detect-isp", timeout=20)
        d = parse_kv(out)
        if code != 0 or d.get("result") != "ok":
            reason = d.get("reason") or T("could not reach the lookup service")
            self.log(f"{T('Detection failed')}: {reason}")
            if not apply_silently:
                self.toast(T("Detection failed"))
            return

        asn, as_name = d.get("asn", "?"), d.get("as_name", "?")
        strategy, current = d.get("strategy", ""), d.get("current", "")
        self._carrier = f"AS{asn} · {as_name}"
        self.info_rows["carrier"].set_subtitle(self._carrier)
        self.log(f"AS{asn} · {as_name}")

        if not strategy:
            # Bilinen bir operatör değil: elle seçim ya da blockcheck gerekir.
            self.log(T("No ready-made profile for this carrier; "
                       "use ISP analysis (blockcheck)."))
            if not apply_silently:
                self.toast(T("No ready-made profile for this carrier"))
            return

        label = next((l for i, l in self.strategies if i == strategy), strategy)
        if strategy == current:
            self.log(T("Already using the matching profile: {}").format(label))
            if not apply_silently:
                self.toast(T("Already using the matching profile"))
            return

        if apply_silently:
            self.log(T("Network changed, switching to: {}").format(label))
            self._select_strategy(strategy)
            self.run_privileged(
                ["restart", *self.pending_config()],
                title=T("carrier detection"))
            return

        self._confirm_strategy_switch(strategy, label)

    def _confirm_strategy_switch(self, strategy, label):
        heading = T("Carrier detected")
        body = T("Switch to the {} profile?").format(label)

        def on_resp(_d, resp):
            if resp != "apply":
                return
            self._select_strategy(strategy)
            if self.status.get("running") == "1":
                self.run_privileged(["restart", *self.pending_config()],
                                    title=T("carrier detection"))
            else:
                self.mark_dirty()
                self.refresh()

        if hasattr(Adw, "AlertDialog"):
            dlg = Adw.AlertDialog(heading=heading, body=body)
            dlg.add_response("cancel", T("Cancel"))
            dlg.add_response("apply", T("Apply"))
            dlg.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present(self)
        else:
            dlg = Adw.MessageDialog(transient_for=self, heading=heading, body=body)
            dlg.add_response("cancel", T("Cancel"))
            dlg.add_response("apply", T("Apply"))
            dlg.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)
            dlg.connect("response", on_resp)
            dlg.present()

    def _select_strategy(self, strategy):
        idx = next((i for i, (sid, _) in enumerate(self.strategies)
                    if sid == strategy), None)
        if idx is None:
            log.warning("strategy %s not in the current engine's list", strategy)
            return
        self._loading = True
        self.row_strategy.set_selected(idx)
        self._loading = False
        self.mark_dirty()

    # -----------------------------------------------------------------
    # listeler
    # -----------------------------------------------------------------

    def on_add_domain(self, *_):
        domain = self.entry_domain.get_text().strip().lower()
        if not domain:
            return
        which = LIST_TARGETS[self.row_list_target.get_selected()][0]
        self.entry_domain.set_text("")
        self.run_privileged(
            ["hostlist", "add", which, domain],
            title=T("add domain"),
            done=lambda code: self._refresh_lists(),
        )

    def on_remove_domain(self, which, domain):
        self.run_privileged(
            ["hostlist", "remove", which, domain],
            title=T("remove domain"),
            done=lambda code: self._refresh_lists(),
        )

    def _refresh_lists(self):
        for key, _label in LIST_TARGETS:
            group = self.list_groups[key]
            for row in self.list_rows[key]:
                group.remove(row)
            self.list_rows[key] = []

            _, out = ctl("hostlist", "show", key, timeout=POLL_TIMEOUT)
            domains = [d.strip() for d in out.splitlines() if d.strip()]
            if not domains:
                row = Adw.ActionRow(title=T("(empty)"), sensitive=False)
                group.add(row)
                self.list_rows[key].append(row)
                continue

            for domain in domains:
                row = Adw.ActionRow(title=domain)
                btn = Gtk.Button(icon_name="user-trash-symbolic",
                                 valign=Gtk.Align.CENTER,
                                 tooltip_text=T("Remove"))
                btn.add_css_class("flat")
                btn.connect("clicked",
                            lambda _b, k=key, d=domain: self.on_remove_domain(k, d))
                row.add_suffix(btn)
                group.add(row)
                self.list_rows[key].append(row)

    def on_show_gateway_help(self, *_):
        ip = self._gw_ip or "192.168.1.1"
        mask = self._gw_mask or "255.255.255.0"

        page = Adw.PreferencesPage()
        for title, body in GATEWAY_SECTIONS:
            # GATEWAY_SECTIONS zaten seçili dile göre (EN/TR) hazırlanmış,
            # burada ayrıca T() ile çevirmeye gerek yok.
            group = Adw.PreferencesGroup(title=title)
            lbl = Gtk.Label(
                label=body.format(ip=ip, mask=mask), wrap=True, xalign=0,
                selectable=True,
            )
            row = Adw.ActionRow()
            row.set_child(lbl)
            row.set_margin_top(4)
            row.set_margin_bottom(4)
            group.add(row)
            page.add(group)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar(title_widget=Adw.WindowTitle(
            title=T("How do I configure the device?")
        )))
        toolbar.set_content(page)

        win = Adw.Window(
            transient_for=self, modal=True,
            default_width=440, default_height=560,
        )
        win.set_content(toolbar)
        win.present()

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
            issue_url="https://github.com/WinTone01/Unwall/issues",
            license_type=Gtk.License.GPL_3_0,
            developer_name="WinTone01",
            developers=["WinTone01 https://github.com/WinTone01"],
        )
        credit_section = (
            T("Based on / inspired by"),
            [
                "alimali54 (zapret-win-turkey) https://github.com/alimali54",
                "bol-van (zapret, zapret2) https://github.com/bol-van",
                "cagritaskn (splitwire-turkey) https://github.com/cagritaskn",
                "DaniilSokolyuk (go-pcap2socks) https://github.com/DaniilSokolyuk",
            ],
        )
        if hasattr(Adw, "AboutDialog"):
            dialog = Adw.AboutDialog(**kwargs)
            dialog.add_credit_section(*credit_section)
            dialog.present(self)
        else:
            window = Adw.AboutWindow(transient_for=self, **kwargs)
            window.add_credit_section(*credit_section)
            window.present()


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
