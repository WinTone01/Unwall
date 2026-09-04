<p align="center">
  <img src="docs/logo.png" width="112" alt="Unwall">
</p>

<h1 align="center">Unwall</h1>

<p align="center">
  <code>zapret</code> / <code>zapret2</code> DPI atlatma motorları için Linux kontrol paneli —
  systemd servisi, nftables kuralları, şifreli DNS, ağ geçidi modu ve hiçbir zaman
  root olarak çalışmayan bir GTK4 arayüz.
</p>

<p align="center">
  <a href="https://github.com/WinTone01/Unwall/releases/latest"><img src="https://img.shields.io/github/v/release/WinTone01/Unwall?label=s%C3%BCr%C3%BCm" alt="Son sürüm"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/lisans-GPLv3-blue.svg" alt="Lisans: GPLv3"></a>
  <a href="https://github.com/WinTone01/Unwall/actions/workflows/ci.yml"><img src="https://github.com/WinTone01/Unwall/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/platform-Linux-informational" alt="Platform: Linux">
</p>

<p align="center">
  <b>Türkçe</b> · <a href="README.md">English</a>
</p>

<p align="center">
  <img src="docs/screenshots/gui-tr.png" alt="Unwall — durum, motor/strateji, filtreleme, şifreli DNS, ağ geçidi modu ve servis" width="360">
</p>

---

Unwall, [@bol-van](https://github.com/bol-van)'ın DPI (Deep Packet Inspection)
atlatma motorları [zapret](https://github.com/bol-van/zapret) ve
[zapret2](https://github.com/bol-van/zapret2)'yi masaüstünde gerçekten
kullanılabilir hale getirir. Linux'ta motor yerli çalışır: WinDivert benzeri
bir sürücü yerine çekirdeğin **netfilter/NFQUEUE** altyapısı paketleri
yakalar, işi `nfqws` yapar. Unwall bu motorun etrafına operatör presetleri,
hostlist yönetimi, şifreli DNS ve teşhis araçları ekler.

Şu an hazır operatör presetleri **Türkiye** içindir (proje
[zapret-win-turkey](https://github.com/alimali54/zapret-win-turkey)
uygulamasından doğdu); başka bir ülke eklemek
[`lib/strategies.conf`](lib/strategies.conf) dosyasına tek satır eklemekten
ibarettir — bkz. [CONTRIBUTING.md](CONTRIBUTING.md) (İngilizce).

## İçindekiler

- [Özellikler](#özellikler)
- [Kurulum](#kurulum)
- [Kullanım](#kullanım)
- [Şifreli DNS](#şifreli-dns-yogadns-karşılığı)
- [Ağdaki cihazlarla paylaşım](#ağdaki-cihazlarla-paylaş-konsol-tv)
- [Windows sürümünden farklar](#windows-sürümünden-farklar)
- [Proje yapısı](#proje-yapısı)
- [Sorun giderme](#sorun-giderme)
- [Katkıda bulunma](#katkıda-bulunma)
- [Lisans](#lisans)
- [Teşekkürler](#teşekkürler)

## Özellikler

| | |
|---|---|
| **Çoklu motor** | klasik `nfqws` (zapret) ve yeni LUA tabanlı `nfqws2` (zapret2) |
| **Hazır stratejiler** | operatör presetleri (şimdilik `TR ·` Türk Telekom, Superonline, Kablonet, Vodafone, Turkcell/Telekom mobil) ve operatörden bağımsız genel profiller — blockcheck beklemeden denenebilir |
| **Blockcheck** | operatörünüz için çalışan stratejiyi otomatik arar, sonucu doğrudan yapılandırmaya yazar |
| **Hostlist / excludelist** | yalnızca engellenen alan adları motordan geçer, normal trafiğiniz etkilenmez; `com.tr` ve `gov.tr` varsayılan olarak hariç |
| **systemd servisi** | açılışta otomatik başlatma, arayüz kapalıyken de çalışır |
| **Ağ geçidi modu** | konsol, akıllı TV gibi cihazların trafiğini bu makine üzerinden geçirir (Windows'taki `go-pcap2socks` + Npcap'in karşılığı) |
| **Şifreli DNS** | tek anahtarla DoH (`dnscrypt-proxy`, 443) veya DoT (`systemd-resolved`, 853) — YogaDNS önerisinin yerine geçer, geri alınabilir |
| **Operatör otomatik tespiti** | ASN'nizi şifreli DNS üzerinden sorgulayıp uygun profili seçer; istenirse başka bir ağa geçtiğinizde yeniden algılar |
| **Teşhis** | DNS müdahalesi kontrolü, çakışan araç/kuyruk tespiti |
| **Türkçe ve İngilizce** | arayüz dili yerel ayardan seçilir, menüden değiştirilebilir (`UW_LANG=tr`/`en` ile de zorlanır) |
| **Yetki ayrımı** | arayüz normal kullanıcı olarak çalışır, ayrıcalıklı işler polkit üzerinden tek bir yardımcı betiğe gider |

## Kurulum

```bash
./install.sh
```

Betik kendini bir kez yükseltir (`sudo`, yoksa `pkexec`), yani parola yalnızca
bir defa sorulur. Bu tek komut her şeyi yapar:

1. Dağıtımınızı tanır (`pacman` / `apt` / `dnf` / `zypper`) ve **gerekli +
   isteğe bağlı tüm paketleri kurar** (`dnscrypt-proxy` dahil)
2. Dosyaları, systemd birimini, polkit politikasını, ikonu ve uygulama menüsü
   girdisini yerleştirir
3. `nfqws` ve `nfqws2` motorlarını kaynaktan derler

Kurulum **hiçbir servisi başlatmaz ve hiçbir sistem ayarını değiştirmez**.
DNS, otomatik başlatma, strateji seçimi, ağ geçidi — hepsi arayüzden yapılır.

Seçenekler: `--yes` (soru sorma), `--no-deps`, `--no-build`, `PREFIX=/usr`.

Kurulumdan sonra uygulama menüsünde **Unwall** (Ağ kategorisi) belirir;
oradan ya da `unwall` komutuyla açabilirsiniz.

### Dağıtım paketleri

| Dağıtım | Komut |
|---|---|
| Arch / CachyOS | `cd packaging && makepkg -si` |
| Debian / Ubuntu | `./packaging/build-deb.sh && sudo apt install ./packaging/unwall_*.deb` |
| Fedora / openSUSE | `./packaging/build-rpm.sh && sudo dnf install ./packaging/RPMS/*.rpm` |
| Flatpak (yalnızca arayüz) | bkz. [`flatpak/README.md`](flatpak/README.md) |
| AppImage (yalnızca arayüz) | `./packaging/build-appimage.sh` |

`.deb` ve `.rpm` derleme betikleri sırasıyla `dpkg-dev` ve `rpm-build`
(`rpmbuild`) gerektirir; bu depodan gerçek bir paket üretirler, hazır bir
şey indirmezler. İki paket de tıpkı `install.sh` gibi davranır: siz
arayüzden ya da `unwallctl` ile yapmadıkça hiçbir servis başlamaz, hiçbir
sistem ayarına dokunulmaz.

Flatpak ve AppImage ayrı bir durum: ikisi de yalnızca GTK4 arayüzünü
içerebilir, nftables/systemd/NFQUEUE kısmını değil; bu yüzden host'ta
yukarıdaki paketlerden biri (ya da `install.sh`) zaten kurulu olmalı.

- **Flatpak** sandbox'lıdır; host'un `unwallctl`/`pkexec`'ine
  `flatpak-spawn --host` ile ulaşır. Nedenini ve nasıl çalıştığını
  [`flatpak/README.md`](flatpak/README.md) dosyasında bulabilirsiniz.
- **AppImage** sandbox'lı *değildir* — normal kullanıcı yetkinizle, diğer
  ikili dosyalar gibi çalışır; `unwallctl`/`pkexec`'i doğrudan çağırır,
  köprüye gerek yoktur. `appimagetool` gerektirir
  (`PATH`'inizde değilse `APPIMAGETOOL=/araç/yolu ./packaging/build-appimage.sh`);
  ortaya çıkan `Unwall-<sürüm>-x86_64.AppImage`, Flatpak gibi hâlâ
  çalıştığı makinede native motoru bekleyen, taşınabilir tek dosyalık bir
  arayüzdür.

<details>
<summary><b>Yükseltme / kaldırma</b></summary>
<br>

**`zapret-turkey`'den yükseltme** (projenin eski adı): `./install.sh` yeterli.
Eski servisi kapatır, `/etc/zapret-turkey` ve `/opt/zapret-turkey` dizinlerini
yeni yollara taşır (motorlar yeniden derlenmez), şifreli DNS ayarınızı korur,
eski ikilileri, birimi, polkit politikasını ve menü girdisini siler.

Her şeyi kaldırmak için: `./uninstall.sh` (parolayı o da yalnızca bir kez
sorar). Servisi durdurup devre dışı bırakır, nftables kurallarını siler,
şifreli DNS yapılandırmasını geri alır (değiştirdiği `dnscrypt-proxy.toml`
varsa yedekten geri yükler), program dosyalarını, ayarları ve listeleri,
derlenmiş motorları ve kaynak ağacını, günlükleri siler; sonunda geriye iz
kalmadığını doğrular. `--yes` onay sormaz, `--keep-config` `/etc/unwall`
dizinini korur, `--purge-deps` `dnscrypt-proxy` paketini de kaldırır. Diğer
bağımlılıklar (nftables, gtk4, luajit …) başka yazılımlar kullanabileceği
için sistemde bırakılır.

</details>

<details>
<summary><b>Bağımlılıkları elle kurmak isterseniz</b></summary>
<br>

```bash
sudo pacman -S --needed nftables python-gobject libadwaita gtk4 polkit bind gcc make pkgconf git curl luajit libnetfilter_queue libnfnetlink libmnl zlib dnscrypt-proxy
```

```bash
sudo apt install nftables python3-gi gir1.2-adw-1 gir1.2-gtk-4.0 policykit-1 dnsutils build-essential pkg-config git curl libluajit-5.1-dev libnetfilter-queue-dev libnfnetlink-dev libmnl-dev zlib1g-dev dnscrypt-proxy
```

```bash
sudo dnf install nftables python3-gobject libadwaita gtk4 polkit bind-utils gcc make pkgconf git curl luajit-devel libnetfilter_queue-devel libnfnetlink-devel libmnl-devel zlib-devel dnscrypt-proxy
```

`build` komutu `bol-van/zapret` ve `bol-van/zapret2` depolarını
`/opt/unwall/src` altına klonlayıp `nfqws` / `nfqws2` ikililerini derler;
sonradan `sudo unwallctl build` ile motorları güncelleyebilirsiniz.

</details>

## Kullanım

Grafik arayüzden motoru, stratejiyi ve hostlist modunu seçip **ZAPRET'İ BAŞLAT**
demeniz yeterli. Seçimleriniz siz düğmeye basana kadar uygulanmaz; o ana kadar
durum satırında `uygulanmadı → ...` şeklinde görünür ve düğme
**AYARLARI UYGULA** olur. "Açılışta otomatik başlat" anahtarı systemd birimini
etkinleştirir; arayüz kapalıyken de çalışmaya devam eder.

Arayüz normal kullanıcı olarak çalışır; yalnızca yetki gerektiren işlemler
(başlatma, servis, DNS, ağ kuralları) polkit üzerinden parola sorar.

Terminalden:

```bash
sudo unwallctl start STRATEGY=superonline ENGINE=zapret2
```

| Komut | İş |
|---|---|
| `unwallctl status` | durum (key=value) |
| `unwallctl strategies [motor]` | hazır strateji listesi |
| `unwallctl config get\|set` | ayarları oku / yaz |
| `sudo unwallctl start\|stop\|restart` | motoru çalıştır / durdur |
| `sudo unwallctl enable\|disable` | açılışta otomatik başlatma |
| `sudo unwallctl blockcheck [motor]` | ISS analizi |
| `unwallctl dnscheck [domain]` | DNS müdahalesi kontrolü |
| `unwallctl detect-isp` | operatörü ASN'den algıla, profil öner |
| `unwallctl hostlist show LİSTE` | listeyi yazdır (`manual`/`auto`/`exclude`) |
| `sudo unwallctl hostlist add\|remove LİSTE ALAN` | alan adı ekle / sil |
| `sudo unwallctl dns enable\|disable` | şifreli DNS (DoT/DoH) aç / kapat |
| `unwallctl dns status\|test` | şifreli DNS durumu / sınaması |
| `unwallctl doctor` | ortam / çakışma teşhisi |
| `sudo unwallctl disable-conflicts` | çakışan DPI araçlarını kapat |
| `unwallctl print-cmd`, `print-nft` | üretilen komutu ve kuralları göster |
| `unwallctl conncheck [domainler]` | birkaç hedefe gerçek TLS el sıkışması dener |
| `unwallctl blockcheck-results [motor]` | son blockcheck'teki tüm çalışan stratejileri listeler |
| `unwallctl update-check` | GitHub'da yeni sürüm var mı bak (key=value) |
| `sudo unwallctl self-update [sürüm]` | bir sürümü indirip kur (varsayılan: en son) |

**Ayar dosyası**: `/etc/unwall/unwall.conf`
**Listeler**: `/etc/unwall/{hostlist,excludelist,autohostlist}.txt`
**Günlükler**: `journalctl -u unwall -f` ve `/var/log/unwall/`

Arayüz günde bir kez arka planda GitHub'da yeni sürüm olup olmadığına bakar
(aksi halde hiç ağa çıkmaz) ve bulursa kapatılabilir bir bant içinde sürüm
bağlantısını gösterir. Menüden (**Güncellemeleri denetle**) ya da terminalden
elle tetiklenebilir:

```bash
unwallctl update-check
```

Banttaki **Şimdi güncelle** düğmesine basmak (ya da `sudo unwallctl
self-update`'i elle çalıştırmak) o sürümün kaynak arşivini indirip
`install.sh --no-deps --no-build`'ini çalıştırır: CLI, GUI, systemd birimi,
polkit politikası, ikon ve menü girdisi yenilenir; paketlere ve derlenmiş
motorlara dokunulmaz, işlem sırasında hiçbir şey başlatılmaz/durdurulmaz —
`install.sh`'i elle çalıştırmakla aynı garantiler. Bu yalnızca `install.sh`
ile kurduysanız işe yarar; bir dağıtım paketiyle (`.deb`/`.rpm`/AUR)
kurduysanız güncellemeyi paket yöneticinizden yapın, çünkü `self-update`
bir sonraki `apt`/`dnf`/`pacman` yükseltmesinde zaten üzerine yazılır.

## Şifreli DNS (YogaDNS karşılığı)

ISS'niz DNS'e müdahale ediyorsa zapret tek başına yetmez. Arayüzdeki **Şifreli
DNS** anahtarı ya da `unwallctl dns` komutu bunu kurar; elle dosya
düzenlemenize gerek yoktur.

| Yöntem | Taşıma | Not |
|---|---|---|
| **DoH** — `dnscrypt-proxy` | 443/tcp | Normal HTTPS'ten ayırt edilemez, engellenmesi zor. `dnscrypt-proxy` paketi gerekir. |
| **DoT** — `systemd-resolved` | 853/tcp | Ek paket gerektirmez, ama 853 ayrı bir port olduğu için bazı ISS'ler kapatabilir. |

```bash
sudo unwallctl dns enable cloudflare auto
```

`auto`, `dnscrypt-proxy` kuruluysa DoH'u, değilse DoT'u seçer. Sağlayıcı olarak
`cloudflare`, `google` veya `quad9` verilebilir.

```bash
unwallctl dns test
sudo unwallctl dns disable
```

<details>
<summary>Perde arkasında ne oluyor</summary>
<br>

- **DoT**: `/etc/systemd/resolved.conf.d/90-unwall.conf` içine
  `DNSOverTLS=yes` + sağlayıcı sunucuları yazılır. `Domains=~.` sayesinde
  DHCP ile gelen ISS DNS'i yerine bunlar kullanılır; kendi arama alanı olan
  bağlantılar (VPN, Tailscale) etkilenmez.
- **DoH**: `dnscrypt-proxy` `127.0.0.1:5300`'de DoH istemcisi olarak çalışır,
  `systemd-resolved` upstream olarak oraya bakar. Mevcut
  `dnscrypt-proxy.toml` üzerine yazmadan önce `.unwall.bak` olarak
  yedeklenir; `dns disable` yedeği geri yükler.

`dns disable` her iki değişikliği de geri alır — kaldırma betiği de bunu çağırır.

</details>

## Ağdaki Cihazlarla Paylaş (konsol, TV)

Arayüzdeki **Ağ geçidi modu** anahtarını açın. Bu makine yerel ağ için NAT yapan
bir yönlendiriciye dönüşür (`ip_forward` + `nft masquerade`) ve yönlendirilen
trafik de zapret'ten geçer. Windows'taki Npcap + `go-pcap2socks` katmanına gerek
yoktur; yönlendirme çekirdek tarafından yapılır.

DNS de Windows sürümündeki `go-pcap2socks`'un yaptığı işi görür, sadece gömülü
bir proxy yerine bir nftables kuralıyla: LAN'dan gelen her DNS sorgusu (TCP ve
UDP, port 53) bu makinedeki çözümleyiciye şeffafça yönlendirilir (`dnat`).
**Cihazın DNS alanına ne yazdığınızın önemi yoktur** — cihazın paketleri o
adrese hiç gerçekten çıkmaz, çıkmadan önce bu makineye yeniden yazılır.

Bu, Türk Telekom / TT Mobil gibi **port 53'e giden her paketi ele geçirip kendi
yanıtını döndüren** ağlarda tek çözümdür: konsolun kendi DNS'i ISS'ye çıktığı
sürece engelli sitelerin gerçek IP'sini asla öğrenemez, DPI atlatma çalışsa bile
bağlantı yanlış adrese kurulur. Superonline/Turkcell gibi 53'e dokunmayan
ağlarda ise cihaz kendi DNS'iyle de idare edebilir.

Yönlendirmenin hedefi otomatik seçilir:

- **Şifreli DNS (DoH/dnscrypt-proxy) açıksa** sorgular doğrudan
  `127.0.0.1:5300`'e, yani şifreli kanala gider. Konsol/TV için önerilen kurulum
  budur: `unwallctl dns enable cloudflare dnscrypt` (ya da arayüzden Şifreli DNS
  + Yöntem: DoH).
- **Şifreli DNS kapalıysa ya da DoT (systemd-resolved) kullanılıyorsa**
  `systemd-resolved`'in LAN adresinde ikinci bir dinleyicisi açılır
  (`DNSStubListenerExtra`, `/etc/systemd/resolved.conf.d/91-unwall-gateway.conf`)
  ve sorgular oraya yönlendirilir. resolved'in asıl `127.0.0.53` stub'ı yalnızca
  yerel adreslerden gelen sorgulara yanıt verdiği için LAN'dan gelen paketleri
  sessizce atar; bu yüzden doğrudan oraya yönlendirmek işe yaramaz. Ağ geçidi
  modu kapatılınca bu dinleyici geri alınır.
- **Kullanılabilir bir hedef yoksa** yönlendirme kuralı hiç yazılmaz: DNS'i kara
  deliğe göndermektense cihazın kendi ayarıyla çalışması yeğdir. Bu durumda
  arayüzün Durum sayfasındaki "Ağ geçidi modu" satırında *cihaz DNS'i
  yönlendirilmiyor* yazar, `unwallctl doctor` da "ağ geçidi DNS" satırında SORUN
  gösterir.

Cihazın (PlayStation, Xbox, Switch, TV) manuel ağ ayarlarına:

| Alan | Değer |
|---|---|
| IP adresi | ağınızda boş bir adres, örn. `192.168.1.50` |
| Alt ağ maskesi | ağınızla aynı, genelde `255.255.255.0` |
| Ağ geçidi | bu bilgisayarın LAN IP adresi (arayüzde "LAN adresi" satırında yazar) |
| DNS | geçerli görünen herhangi bir değer, örn. `1.1.1.1` — çoğu cihaz DNS alanı boşken devam etmiyor, ama gerçek değer yukarıdaki yönlendirmeyle zaten geçersiz kılınıyor |

> [!NOTE]
> `firewalld`/`ufw` gibi bir güvenlik duvarı `forward` zincirinde varsayılan
> olarak paket düşürüyorsa (birçok dağıtımda ufw'nin `DEFAULT_FORWARD_POLICY`
> ayarı kutudan çıktığı gibi `DROP`'tur) ağ geçidi modundaki cihazlar
> "bağlandım ama internet yok" ile karşılaşır. v1.3.14'ten beri
> `unwallctl` bunu kendisi tespit edip ağ geçidi modu her uygulandığında
> hedefli bir `ufw route allow` kuralı (firewalld'de `firewall-cmd
> --add-forward`) otomatik ekliyor — elle güvenlik duvarı ayarı gerekmez.
> Ne tespit edildiğini `unwallctl doctor` ya da arayüzün Teşhis
> menüsünden "ağ geçidi yönlendirme" satırında görebilirsiniz.

> [!NOTE]
> DNS yönlendirmesi için ufw'de ikinci bir kural daha gerekiyor:
> yönlendirilen paketin hedefi artık bu makinenin kendisi olduğu için paket
> `forward` zincirinden değil `INPUT`'tan geçer ve `ufw route allow`
> kuralının kapsamına girmez - ufw'nin varsayılan gelen politikası DROP
> olduğundan sorgu `[UFW BLOCK] ... DST=127.0.0.1 DPT=5300` ile düşer.
> v1.4.2'den beri `unwallctl` yönlendirme hedefine gelen bağlantı için de
> nokta atışı bir izin ekliyor (`# unwall dns redirect` yorumuyla
> görünür) ve ağ geçidi kapatılınca geri alıyor. `doctor`, kural yerinde
> ama izin yoksa "ağ geçidi DNS" satırında uyarır.

## Windows sürümünden farklar

| Windows | Linux karşılığı |
|---|---|
| `winws.exe` / `winws2.exe` | `nfqws` / `nfqws2` |
| WinDivert sürücüsü | netfilter NFQUEUE (`nfnetlink_queue`) |
| `--wf-tcp` / `--wf-udp` / `--wf-l3` | nftables kuralları (`queue num ... bypass`) |
| `sc create ZapretService` | `unwall.service` (systemd) |
| UAC / `#RequireAdmin` | polkit + `pkexec` (yalnızca yardımcı betik yükselir) |
| Npcap + `go-pcap2socks` | `ip_forward` + `nft masquerade` |
| YogaDNS (elle kurulur) | `dns enable` ile tümleşik DoH/DoT (`dnscrypt-proxy` / `systemd-resolved`) |
| `nslookup`, `ipconfig /flushdns` | `dig`, `resolvectl flush-caches` |
| GoodbyeDPI çakışma kontrolü | `nfqws`/`tpws`/`byedpi`/TUN ve kuyruk çakışması (`doctor`) |
| `config.ini` | `/etc/unwall/unwall.conf` |
| AutoIt GUI | GTK4 + libadwaita (Python) |

Strateji parametreleri (`--dpi-desync=…`, `--lua-desync=…`, `--hostlist…`) her iki
platformda aynıdır; yalnızca trafiği motora yönlendirme katmanı değişir.

## Proje yapısı

```
bin/unwallctl          ayrıcalıklı işlerin tamamı (CLI + polkit hedefi)
bin/unwall             GUI başlatıcı
gui/unwall_gui.py      GTK4 / libadwaita arayüzü (host-farkında: Flatpak'tan da çalışır)
lib/strategies.conf    hazır strateji profilleri
etc/unwall.conf        varsayılan yapılandırma
systemd/unwall.service systemd birimi
polkit/…policy         yetki yükseltme politikası
packaging/PKGBUILD     Arch paketi
packaging/debian/      .deb kontrol dosyaları (bkz. build-deb.sh)
packaging/unwall.spec  Fedora/openSUSE .rpm spec (bkz. build-rpm.sh)
flatpak/                Arayüz için Flatpak manifesti (bkz. flatpak/README.md)
packaging/appimage/     AppImage için AppRun (bkz. build-appimage.sh)
docs/screenshots/      arayüz görselleri
```

## Sorun giderme

```bash
unwallctl doctor
```

Arayüzü terminalden çalıştırırsanız her şey konsola akar; ayrıntı için:

```bash
UW_DEBUG=1 unwall
```

Uygulama tek örnekli çalışır: menüden açılmış bir pencere varken terminalden
başlatmak yalnızca o pencereyi öne getirir ve terminale log gelmez. Hata
ayıklarken ayrı bir örnek isterseniz:

```bash
UW_NO_UNIQUE=1 UW_DEBUG=1 unwall
```

<details open>
<summary><b>Sık karşılaşılan sorunlar</b></summary>
<br>

- **Motor başlamıyor**: `journalctl -u unwall -n 50`
- **Seçtiğim strateji geri dönüyor**: seçim "AYARLARI UYGULA" / "ZAPRET'İ
  BAŞLAT" düğmesine basılana kadar yalnızca beklemededir; durum satırında
  `uygulanmadı → ...` şeklinde görünür.
- **Hiçbir şey değişmedi**: `sudo nft list table ip unwall` ile kuralların
  yüklendiğini doğrulayın; hostlist modu `manual` ise alan adının listede olduğundan
  emin olun.
- **QUIC/HTTP3 siteleri bozuldu**: config'te `PORTS_UDP=` (boş) yapın.
- **"Otomatik (zapret öğrenir)" hostlist modu yeni domain eklemiyor**: bir
  domain yalnızca *henüz desync edilmemişken* tanınabilir bir "bağlantı
  engellendi" örüntüsü (v1.3.8'den beri: tek bir başarısız deneme — motorun
  kendi varsayılanı 60 saniyede 3'tür, `--hostlist-auto-fail-threshold=1`
  ile düşürüyoruz ki tek bir kötü yükleme yetsin; tek bir deneme hâlâ
  varsayılan olarak 3 TCP retransmit gerektirdiğinden rastgele bir ağ
  sıçraması sayılmaz) görülürse eklenir. Stratejiniz zaten sorunsuz
  çalışıyorsa bu örüntü hiç oluşmaz ve domain haklı olarak eklenmez.
  v1.3.6 öncesinde, gerçekten engellenen
  domainler de öğrenilemeyebiliyordu, çünkü yalnızca giden trafik motora
  kuyruklanıyordu — zapret2'nin kendi otomatik-hostlist algılayıcısı gelen
  yönü de (enjekte edilmiş bir RST ya da engel sayfasına HTTP yönlendirmesi)
  görmesi gerekiyor; v1.3.6'daki nftables kuralları artık bunu da
  kuyruklar. Hâlâ eski bir sürümdeyseniz önce güncelleyin. Motorun gerçekte
  ne gördüğünü görmek için engellenen bir siteye girerken
  `sudo tail -f /var/log/unwall/hostlist-auto.log` komutunu izleyin — birkaç
  başarısız denemeden sonra log tamamen boşsa, gelen yön hâlâ motora
  ulaşmıyor demektir.
- **Başka bir DPI aracı çalışıyor**: `byedpi`, `tpws`, upstream `zapret.service`
  veya TUN kuran bir VPN aynı anda açıksa kuyruk çakışır.
- **Sistemde zaten upstream zapret kurulu** (`/opt/zapret`, `zapret.service`):
  ikisini aynı anda çalıştırmayın — `sudo systemctl disable --now zapret`.
  Bu projenin varsayılan kuyruk numarası çakışmayı azaltmak için `210`'dur
  (upstream `200` kullanır). Ayrıca `build` adımını atlayıp mevcut
  `/opt/zapret` ve `/opt/zapret2` ikilileri doğrudan kullanılabilir; motor
  bulunamazsa oralara da bakılır.

</details>

Hâlâ takıldıysanız [hata bildirimi şablonunu](https://github.com/WinTone01/Unwall/issues/new/choose)
kullanarak bir issue açın — istediği ortam tablosunu (sürüm, kurulum yöntemi,
dağıtım, motor, strateji, hostlist modu) önceden doldurmak en büyük zaman
kazancı.

## Katkıda bulunma

Hata bildirimleri, başka ülkeler için strateji presetleri ve pull request'ler
memnuniyetle karşılanır — projenin nasıl düzenlendiği, her push'ta CI'ın neyi
kontrol ettiği ve bir PR açmadan önce yerelde neyi doğrulamanız gerektiği için
[CONTRIBUTING.md](CONTRIBUTING.md) dosyasına (İngilizce) bakın.

## Lisans

Unwall [GNU Genel Kamu Lisansı v3.0](LICENSE) ya da sonraki bir sürümü ile
lisanslanmıştır. Çalıştırmakta, incelemekte, paylaşmakta ve değiştirmekte
serbestsiniz; değiştirilmiş bir sürümü dağıtırsanız aynı lisans altında
kalmalı ve kaynak koduyla birlikte gelmelidir.

## Teşekkürler

- [@WinTone01](https://github.com/WinTone01) — Unwall'ı yazdı: Linux tarafının
  tamamı (`unwallctl`, systemd/nftables/polkit entegrasyonu, GTK4 arayüz,
  şifreli DNS, ağ geçidi modu, güncelleme denetleyicisi) ve projeyi sürdürüyor.
- Bu projenin temelini oluşturan Windows sürümü
  [zapret-win-turkey](https://github.com/alimali54/zapret-win-turkey) için
  geliştiricisi [@alimali54](https://github.com/alimali54)
- Zapret ve zapret2 motorları için [@bol-van](https://github.com/bol-van)
- Otomatik blockcheck mantığı ve ilhamı için
  [splitwire-turkey](https://github.com/cagritaskn/splitwire-turkey) geliştiricisi
  [@cagritaskn](https://github.com/cagritaskn)
- Windows sürümündeki LAN paylaşımı fikri için
  [go-pcap2socks](https://github.com/DaniilSokolyuk/go-pcap2socks) geliştiricisi
  [@DaniilSokolyuk](https://github.com/DaniilSokolyuk)
