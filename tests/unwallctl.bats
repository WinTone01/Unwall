#!/usr/bin/env bats
#
# bin/unwallctl icindeki saf (yan etkisiz) yardimci fonksiyonlarin
# testleri. Kok yetkisi, ag ya da calisan bir servis gerektirmez:
# fonksiyonlar dosyadan tek tek cikarilip kabuga yukleniyor.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CTL="$REPO/bin/unwallctl"
}

# Verilen fonksiyonu unwallctl'den cikarip mevcut kabuga yukler.
load_fn() {
  # shellcheck disable=SC1090
  source <(sed -n "/^$1() {/,/^}/p" "$CTL")
}

@test "cidr_to_netmask yaygin onekleri dogru cevirir" {
  load_fn cidr_to_netmask
  [ "$(cidr_to_netmask 24)" = "255.255.255.0" ]
  [ "$(cidr_to_netmask 16)" = "255.255.0.0" ]
  [ "$(cidr_to_netmask 8)"  = "255.0.0.0" ]
  [ "$(cidr_to_netmask 32)" = "255.255.255.255" ]
  [ "$(cidr_to_netmask 0)"  = "0.0.0.0" ]
}

@test "cidr_to_netmask sinir disi degerlerde 24'e duser" {
  load_fn cidr_to_netmask
  [ "$(cidr_to_netmask 99)"  = "255.255.255.0" ]
  [ "$(cidr_to_netmask -1)"  = "255.255.255.0" ]
  [ "$(cidr_to_netmask abc)" = "255.255.255.0" ]
}

@test "cidr_to_netmask bayt siniri olmayan onekleri hesaplar" {
  load_fn cidr_to_netmask
  [ "$(cidr_to_netmask 25)" = "255.255.255.128" ]
  [ "$(cidr_to_netmask 30)" = "255.255.255.252" ]
}

@test "version_gt surumleri sayisal karsilastirir" {
  load_fn version_gt
  version_gt 1.10.0 1.9.0     # sozluksel olsaydi yanlis olurdu
  version_gt 2.0.0  1.99.99
  version_gt 1.3.16 1.3.9
  ! version_gt 1.0.0 1.0.0
  ! version_gt 1.0.0 1.0.1
}

@test "asn_to_strategy eslemeyi strategies.conf'tan okur" {
  load_fn asn_to_strategy
  STRATEGY_FILE="$REPO/lib/strategies.conf"
  [ "$(asn_to_strategy 47524)" = "kablonet" ]
  [ "$(asn_to_strategy 9121)"  = "turk-telekom" ]
  [ -z "$(asn_to_strategy 99999)" ]
}

@test "asn_to_strategy strategies.conf yoksa patlamaz" {
  load_fn asn_to_strategy
  STRATEGY_FILE="/nonexistent/strategies.conf"
  run asn_to_strategy 47524
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "hostlist_file bilinen listeleri cozer, bilinmeyeni reddeder" {
  load_fn hostlist_file
  UW_ETC=/etc/unwall
  [ "$(hostlist_file manual)"  = "/etc/unwall/hostlist.txt" ]
  [ "$(hostlist_file auto)"    = "/etc/unwall/autohostlist.txt" ]
  [ "$(hostlist_file exclude)" = "/etc/unwall/excludelist.txt" ]
  run hostlist_file bogus
  [ "$status" -ne 0 ]
}

@test "parse_blockcheck_all calisan stratejileri tekrarsiz cikarir" {
  load_fn parse_blockcheck_all
  log="$BATS_TEST_TMPDIR/bc.log"
  cat > "$log" <<'LOG'
nfqws2 --qnum=200 --filter-tcp=80 --dpi-desync=fake
* try 1
!!!!! AVAILABLE !!!!!
nfqws2 --qnum=200 --hostlist=/x --dpi-desync=split2
!!!!! AVAILABLE !!!!!
nfqws2 --qnum=200 --dpi-desync=fake
!!!!! AVAILABLE !!!!!
LOG
  run parse_blockcheck_all "$log" zapret2
  [ "$status" -eq 0 ]
  # --qnum/--filter/--hostlist temizlenmis, tekrar eden "fake" bir kez
  [ "$(printf '%s\n' "$output" | grep -c 'dpi-desync=fake')"   -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'dpi-desync=split2')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c -- '--qnum')"         -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c -- '--hostlist')"     -eq 0 ]
}

@test "parse_blockcheck_all AVAILABLE yoksa bos doner" {
  load_fn parse_blockcheck_all
  log="$BATS_TEST_TMPDIR/empty.log"
  printf 'nfqws2 --dpi-desync=fake\nnothing worked\n' > "$log"
  run parse_blockcheck_all "$log" zapret2
  [ -z "$output" ]
}

@test "detect_local_resolver resolv.conf'taki ilk nameserver'i alir" {
  load_fn detect_local_resolver
  # fonksiyon /etc/resolv.conf'a sabit bagli; en azindan cikti tek satir
  # ve bosluk icermemeli (birden fazla nameserver varsa ilki alinmali)
  run detect_local_resolver
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | wc -l)" -eq 0 ]
}

# --- ogrenilen alan adlarinin dogrulanmasi (v1.5) ---

@test "is_ip_literal ham IP'leri tanir, alan adlarini tanimaz" {
  load_fn is_ip_literal
  run is_ip_literal 192.168.1.1
  [ "$status" -eq 0 ]
  run is_ip_literal 102.67.167.245
  [ "$status" -eq 0 ]
  run is_ip_literal 2001:db8::1
  [ "$status" -eq 0 ]
  run is_ip_literal example.com
  [ "$status" -ne 0 ]
  # rakamla baslayan alan adi IP degildir
  run is_ip_literal 35212.ms.vk.ru
  [ "$status" -ne 0 ]
}

@test "hostlist_file karantina listesini de bilir" {
  load_fn hostlist_file
  UW_ETC=/tmp/uwtest
  [ "$(hostlist_file pending)" = "/tmp/uwtest/autohostlist-pending.txt" ]
  [ "$(hostlist_file auto)"    = "/tmp/uwtest/autohostlist.txt" ]
  run hostlist_file yok
  [ "$status" -ne 0 ]
}

@test "hostlist_append ayni alan adini iki kez yazmaz" {
  load_fn hostlist_append
  f="$BATS_TEST_TMPDIR/list.txt"
  hostlist_append "$f" example.com
  hostlist_append "$f" example.com
  hostlist_append "$f" other.com
  [ "$(grep -c . "$f")" -eq 2 ]
}

@test "hostlist_drop yalnizca tam eslesen satiri siler" {
  load_fn hostlist_drop
  f="$BATS_TEST_TMPDIR/list.txt"
  printf 'example.com\nwww.example.com\nother.com\n' > "$f"
  hostlist_drop "$f" example.com
  [ "$(grep -c . "$f")" -eq 2 ]
  grep -qx 'www.example.com' "$f"
  grep -qx 'other.com' "$f"
}

@test "hostlist_drop dosyanin kendisini korur (mv degil, icerik kopyalanir)" {
  load_fn hostlist_drop
  f="$BATS_TEST_TMPDIR/list.txt"
  printf 'a.com\nb.com\n' > "$f"
  before="$(stat -c %i "$f")"
  hostlist_drop "$f" a.com
  # ayni inode: motorun acik tuttugu dosya/sahiplik bozulmamali
  [ "$(stat -c %i "$f")" = "$before" ]
}

@test "cleared_count/cleared_bump temizlenme sayisini takip eder" {
  load_fn cleared_count
  load_fn cleared_bump
  CLEARED_STATE="$BATS_TEST_TMPDIR/cleared"
  [ "$(cleared_count example.com)" = "0" ]
  [ "$(cleared_bump example.com)" = "1" ]
  [ "$(cleared_bump example.com)" = "2" ]
  [ "$(cleared_count example.com)" = "2" ]
  # baska bir alan adi etkilenmez
  [ "$(cleared_count other.com)" = "0" ]
  [ "$(cleared_bump other.com)" = "1" ]
  [ "$(cleared_count example.com)" = "2" ]
}
