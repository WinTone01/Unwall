#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=zapret\zapret-winws\winws2.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=Zapret Multi-Engine Windows Türkiye - Zapret v1 & v2 Kontrol Aracı
#AutoIt3Wrapper_Res_Fileversion=3.5.0.0
#AutoIt3Wrapper_Res_ProductVersion=3.5
#AutoIt3Wrapper_Res_LegalCopyright=Ali Mali
#AutoIt3Wrapper_Res_Language=1055
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <File.au3>
#include <MsgBoxConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <ProgressConstants.au3>
#include <TrayConstants.au3>
#include <ComboConstants.au3>

; --- ZIP / TEMP KLASÖRÜ KONTROLÜ ---
Local $currentDir = @ScriptDir
If StringInStr($currentDir, @TempDir) Or StringInStr($currentDir, "Temporary Internet Files") Or StringInStr($currentDir, "vfs") Then
    MsgBox(16, "Hata: Arşivden Çalıştırma Saptandı", _
            "Programı ZIP dosyasının içinden doğrudan çalıştırmayın!" & @CRLF & @CRLF & _
            "1. ZIP dosyasındaki tüm dosyaları normal bir klasöre çıkarın." & @CRLF & _
            "2. Ardından programı o klasörden tekrar başlatın.")
    Exit
EndIf

; --- GÜVENLİK UYARILARINI KALDIR ---
RunWait('powershell -Command "Get-ChildItem -Path ''' & @ScriptDir & ''' -Recurse | Unblock-File"', "", @SW_HIDE)

; --- ÇAKIŞMA KONTROLÜ (GoodbyeDPI) ---
If ProcessExists("goodbyedpi.exe") Then
    Local $iResponse = MsgBox(52, "Çakışma Saptandı", "GoodbyeDPI aktif gözüküyor, Zapret'in çalışması için GoodbyeDPI sonlandırılmalı." & @CRLF & @CRLF & _
            "GoodbyeDPI'ı kapatmak ve varsa servisini kaldırmak istiyor musunuz?")
    If $iResponse = 6 Then
        ProcessClose("goodbyedpi.exe")
        While ProcessExists("goodbyedpi.exe")
            Sleep(100)
        WEnd
        RunWait(@ComSpec & ' /c sc stop "GoodbyeDPI" & sc delete "GoodbyeDPI" & sc stop "WinDivert" & sc delete "WinDivert" & sc stop "WinDivert14" & sc delete "WinDivert14"', "", @SW_HIDE)
		MsgBox(64, "Bilgi", "GoodbyeDPI ve servisleri başarıyla kaldırıldı. Program başlatılıyor.")
	Else
        Exit
    EndIf
EndIf

Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

; --- Ayarlar ve Dosya Yolları ---
Local $serviceName = "ZapretService"
Local $hostlistPath = @ScriptDir & "\autohostlist.txt"
Local $normalHostlistPath = @ScriptDir & "\hostlist.txt"
Local $iniPath = @ScriptDir & "\config.ini"

; --- CONFIG DOSYASINDAN AYARLARI OKU ---
Local $iniEngine = IniRead($iniPath, "Settings", "ActiveEngine", "0") ; 0 = Zapret2, 1 = Zapret1
Local $iniStrategy = IniRead($iniPath, "Settings", "ActiveStrategy", "Analiz Sonucu")
Local $iniHostlistEnabled = IniRead($iniPath, "Settings", "HostlistEnabled", "1")
Local $iniHostlistMode = IniRead($iniPath, "Settings", "HostlistMode", "0")

; --- DİNAMİK MOTOR DEĞİŞKENLERİ ---
Global $strategyFile = ""
Global $winwsPath = ""
Global $blockcheckPath = ""
Global $logPath = ""
Global $currentEngine = "Zapret2"

; --- Global Durum Değişkenleri ---
Global $isZapretRunning = False
Global $zapretPID = 0
Global $pcapPID = 0

; --- GUI Tasarımı ---
Local $hGUI = GUICreate("Zapret Windows Türkiye v3.5", 400, 540) ; Strateji Combo alanı için boyutu 590 yaptık
GUISetBkColor(0xFFFFFF)

; --- Tepsi Menüsü ---
Local $trayShow = TrayCreateItem("Göster")
TrayItemSetOnEvent(-1, "ShowGUI")
TrayCreateItem("")
Local $trayExit = TrayCreateItem("Kapat")
TrayItemSetOnEvent(-1, "_SaveConfigAndExit")
TraySetOnEvent($TRAY_EVENT_PRIMARYDOUBLE, "ShowGUI")
TraySetClick(16)

; --- Üst Durum Paneli ---
Local $lblStatusBg = GUICtrlCreateLabel("", 15, 15, 370, 75)
GUICtrlSetBkColor(-1, 0xF2F4F7)
Local $lblStatusText = GUICtrlCreateLabel("SİSTEM HAZIRLANIYOR...", 15, 30, 370, 25, $SS_CENTER)
GUICtrlSetFont(-1, 12, 800, 0, "Segoe UI")
GUICtrlSetColor(-1, 0xE67E22)

Local $pBar = GUICtrlCreateProgress(15, 75, 370, 15, $PBS_MARQUEE)
GUICtrlSetState(-1, $GUI_HIDE)

Local $lblStrategyInfo = GUICtrlCreateLabel("Strateji Durumu: Kontrol Ediliyor...", 15, 55, 370, 20, $SS_CENTER)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x666666)

; --- MOTOR SEÇİM DROPDOWN ---
GUICtrlCreateLabel("Motor:", 50, 113, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Local $cmbEngine = GUICtrlCreateCombo("Zapret2 (Yeni LUA Motoru)", 175, 110, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetData(-1, "Zapret (Eski Klasik Motor)")
If $iniEngine == "1" Then
    GUICtrlSetData($cmbEngine, "Zapret (Eski Klasik Motor)", "Zapret (Eski Klasik Motor)")
EndIf
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; --- STRATEJİ SEÇİM DROPDOWN (YENİ EKLEME) ---
GUICtrlCreateLabel("Strateji:", 50, 148, 120, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
Global $cmbStrategy = GUICtrlCreateCombo("Analiz Sonucu", 175, 145, 175, 25, $CBS_DROPDOWNLIST)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetState(-1, $GUI_DISABLE)

; --- Butonlar (Koordinatları aşağı kaydırıldı) ---
Local $btnRunZapret = GUICtrlCreateButton("ZAPRET'İ BAŞLAT", 50, 185, 300, 55)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 11, 800, 0, "Segoe UI")

; --- LAN PAYLAŞIM CHECKBOX (YENİ) ---
; ISS Analizi butonunun hemen üstüne, butonlarla aynı X hizasına (50) yerleşti.
Global $chkLanShare = GUICtrlCreateCheckbox(" Ağdaki Cihazlarla Paylaş", 55, 240, 290, 25)
GUICtrlSetState(-1, $GUI_DISABLE) ; <--- İlk açılışta kilitli başlasın
GUICtrlSetFont(-1, 9, 800, 0, "Segoe UI")

; --- HOSTLIST HİBRİT PANELİ ---
Local $chkAutoHost = GUICtrlCreateCheckbox(" Hostlist (Filtre listesi) Kullanımını Aktifleştir", 55, 265, 290, 25)
Local $chkState = ($iniHostlistEnabled == "1") ? $GUI_CHECKED : $GUI_UNCHECKED
GUICtrlSetState(-1, BitOR($chkState, $GUI_DISABLE))
GUICtrlSetFont(-1, 9, 800, 0, "Segoe UI")

GUICtrlCreateGroup(" Filtreleme Modu ", 51, 290, 298, 75)
Local $rdoAutoHost = GUICtrlCreateRadio(" Auto hostlist (Zapret oluşturur)", 58, 310, 280, 20)
If $iniHostlistMode == "0" Then GUICtrlSetState(-1, $GUI_CHECKED)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

Local $rdoNormalHost = GUICtrlCreateRadio(" Manuel hostlist ('hostlist.txt' İçeriği)", 58, 335, 280, 20)
If $iniHostlistMode == "1" Then GUICtrlSetState(-1, $GUI_CHECKED)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlCreateGroup("", -1, -1, 1, 1)

Local $btnAnalyze = GUICtrlCreateButton("ISS Analizi (Blockcheck) Yap", 50, 370, 300, 40)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnInstallService = GUICtrlCreateButton("Servis Olarak Yükle (Otomatik Başlat)", 50, 420, 300, 40)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnRemoveService = GUICtrlCreateButton("Servis ve Kalıntıları Temizle", 50, 470, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Global $lblFooter = GUICtrlCreateLabel("Zapret Multi-Engine v2.7.0", 0, 515, 400, 20, $SS_CENTER)
GUICtrlSetFont(-1, 10, 400, 0, "Consolas")
GUICtrlSetColor(-1, 0xBDC3C7)

Local $aCriticalButtons[8] = [$btnRunZapret, $btnAnalyze, $btnInstallService, $chkAutoHost, $rdoAutoHost, $rdoNormalHost, $cmbEngine, $cmbStrategy]
Local $aOtherButtons[8] = [$btnAnalyze, $btnInstallService, $btnRemoveService, $chkAutoHost, $rdoAutoHost, $rdoNormalHost, $cmbEngine, $cmbStrategy]

GUISetState(@SW_SHOW)

; --- İLK YOLLARI VE STRATEJİ LİSTESİNİ DOĞRULA ---
_UpdateEnginePaths(GUICtrlRead($cmbEngine))
_LoadStrategyList($iniStrategy)

; --- GÜVENLİ AÇILIŞ AKIŞI ---
RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
GUICtrlSetData($lblStatusText, "DNS KONTROL EDİLİYOR...")

Local $isPoisoned = CheckDnsPoisoningSilent()

If $isPoisoned Then
    _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
    GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
    GUICtrlSetColor($lblStatusText, 0xC0392B)
    MsgBox(16 + 8192, "Kritik Uyarı", "ISS tarafından DNS Zehirlenmesi saptandı! Lütfen DNS değiştirin.")
Else
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
    _RefreshStrategyLabel()
EndIf

; --- Ana Döngü ---
While 1
    Local $nMsg = GUIGetMsg()

	; --- LAN PAYLAŞIM CHECKBOX AKTİFLİK VE TİK KONTROLÜ ---
    If ProcessExists("winws.exe") Or ProcessExists("winws2.exe") Then
        ; Zapret çalışıyorsa ve kutu kilitliyse, kilidi aç
        If BitAND(GUICtrlGetState($chkLanShare), $GUI_DISABLE) Then GUICtrlSetState($chkLanShare, $GUI_ENABLE)
    Else
        ; Zapret çalışmıyorsa kutuyu kilitle
        If BitAND(GUICtrlGetState($chkLanShare), $GUI_ENABLE) Then
            GUICtrlSetState($chkLanShare, $GUI_DISABLE)

            ; EĞER TİK VARSA: Tiki kaldır ve go-pcap2socks çalışıyorsa onu da kapat
            If GUICtrlRead($chkLanShare) = $GUI_CHECKED Then
                GUICtrlSetState($chkLanShare, $GUI_UNCHECKED)
                If ProcessExists("go-pcap2socks.exe") Then
                    ProcessClose("go-pcap2socks.exe")
                    $pcapPID = 0
                EndIf
            EndIf
        EndIf
    EndIf

    Switch $nMsg
        Case $GUI_EVENT_CLOSE
            _SaveConfigAndExit()

        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)
            TraySetToolTip("Zapret Windows Türkiye Çalışıyor")

        Case $cmbEngine
            _UpdateEnginePaths(GUICtrlRead($cmbEngine))
            _LoadStrategyList("Analiz Sonucu") ; Motor değişince listeyi yenile
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
            _RefreshStrategyLabel()

        Case $cmbStrategy
            _RefreshStrategyLabel()

        Case $chkAutoHost
            If GUICtrlRead($chkAutoHost) = $GUI_CHECKED Then
                GUICtrlSetState($rdoAutoHost, $GUI_ENABLE)
                GUICtrlSetState($rdoNormalHost, $GUI_ENABLE)
            Else
                GUICtrlSetState($rdoAutoHost, $GUI_DISABLE)
                GUICtrlSetState($rdoNormalHost, $GUI_DISABLE)
            EndIf

		Case $btnAnalyze
            Local $iConfirm = MsgBox(33, "Bilgi", "Analiz işlemi 5-10 dakika sürebilir." & @CRLF & "Lütfen bitene kadar bekleyin.")
            If $iConfirm = 1 Then
                _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
                GUICtrlSetState($btnRemoveService, $GUI_DISABLE)
                GUICtrlSetData($lblStatusText, "ANALİZ YAPILIYOR...")
                GUICtrlSetState($pBar, $GUI_SHOW)
                GUICtrlSetData($lblStrategyInfo, "")
                _SendMessage(GUICtrlGetHandle($pBar), $PBM_SETMARQUEE, True, 50)

                If $currentEngine = "Zapret2" Then
                    RunBlockcheck2($btnAnalyze)
                Else
                    RunBlockcheck($btnAnalyze)
                EndIf

                _SendMessage(GUICtrlGetHandle($pBar), $PBM_SETMARQUEE, False, 0)
                GUICtrlSetState($pBar, $GUI_HIDE)
                _SetButtonsState($aCriticalButtons, $GUI_ENABLE)
                GUICtrlSetState($btnRemoveService, $GUI_ENABLE)
                CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
                GUICtrlSetData($lblStatusText, "ANALİZ TAMAMLANDI")
                _RefreshStrategyLabel()
            EndIf

		Case $chkLanShare
            If GUICtrlRead($chkLanShare) = $GUI_CHECKED Then
                ; --- ADIM 1: NPCAP KONTROLÜ ---
                If Not FileExists(@SystemDir & "\Packet.dll") Then
                    GUICtrlSetState($chkLanShare, $GUI_UNCHECKED)
                    MsgBox(8208, "Eksik Bileşen", "HATA: Sistemde Npcap sürücüsü bulunamadı!" & @CRLF & @CRLF & _
                            "go-pcap2socks motorunun çalışabilmesi için Npcap kurulmalıdır." & @CRLF & _
                            "Lütfen npcap.com adresinden indirip kurun.")
                    ContinueLoop
                EndIf

                ; --- SPLASH SCREEN BAŞLANGICI ---
                Local $hSplash = GUICreate("Lütfen Bekleyin", 280, 80, -1, -1, $WS_POPUP, $WS_EX_TOPMOST)
                GUISetBkColor(0xF2F4F7, $hSplash)
                GUICtrlCreateLabel("Güvenlik Duvarı" & @CRLF & "Kontrolleri Yapılıyor...", 10, 20, 260, 40, $SS_CENTER)
                GUICtrlSetFont(-1, 10, 800, 0, "Segoe UI")
                GUICtrlSetColor(-1, 0x2C3E50)
                GUISetState(@SW_SHOW, $hSplash)

                Local $targetPcapExe = @ScriptDir & '\go-pcap2socks\go-pcap2socks.exe'

                If Not HasFirewallRule($targetPcapExe) Then
                    GUISetState(@SW_HIDE, $hSplash)

                    RunWait('powershell -NoProfile -Command "Remove-NetFirewallRule -Program ''' & $targetPcapExe & ''' -ErrorAction SilentlyContinue"', "", @SW_HIDE)
                    RunWait(@ComSpec & ' /c netsh advfirewall firewall delete rule name=all program="' & $targetPcapExe & '"', "", @SW_HIDE)

                    MsgBox(8256, "Güvenlik Duvarı İzni", "go-pcap2socks için ağ izni gerekiyor." & @CRLF & @CRLF & _
                            "1. Birazdan Windows Güvenlik Duvarı uyarısı gelecektir." & @CRLF & _
                            "2. Lütfen gelen ekranda kutucukları işaretleyip 'Erişime izin ver' (Allow) butonuna basın.")

                    Local $tmpPID = Run('"' & $targetPcapExe & '"', @ScriptDir & '\go-pcap2socks', @SW_HIDE)
                    MsgBox(8256, "Onay", "Güvenlik duvarı iznini onayladıysanız Tamam'a basın.")
                    ProcessClose($tmpPID)

                    GUISetState(@SW_SHOW, $hSplash)
                EndIf

                ; --- ADIM 3: SÜRECİ BAŞLATMA ---
                If Not ProcessExists("go-pcap2socks.exe") Then
                    $pcapPID = Run('"' & $targetPcapExe & '"', @ScriptDir & '\go-pcap2socks', @SW_HIDE)
                EndIf

                ; --- YENİ: GERÇEKTEN ÇALIŞIYOR MU KONTROLÜ (SİGORTA) ---
                ; Sürecin ayağa kalkıp kararlı hale gelmesi için çok kısa bir süre (yarım saniye) avans veriyoruz
                Sleep(500)

                If Not ProcessExists("go-pcap2socks.exe") Then
                    ; Eğer exe ayağa kalkamadıysa veya anında çöktüyse
                    GUIDelete($hSplash) ; Önce splash ekranını kapat
                    GUICtrlSetState($chkLanShare, $GUI_UNCHECKED) ; Tiki hemen geri çek
                    $pcapPID = 0
                    MsgBox(16 + 8192, "Başlatma Hatası", "HATA: go-pcap2socks başlatılamadı!" & @CRLF & @CRLF & _
                            "• Sanal bir ağ kartı oluşturan VPN vb program kullanıyorsanız kapatın.")
                    ContinueLoop ; Döngüyü başa sar, aşağıdaki ağ şemasını gösterme
                EndIf

                ; Her şey yolundaysa splash'ı sil ve devam et
                GUIDelete($hSplash)

                MsgBox(8256, "go-pcap2socks Ağ Yapılandırması", _
                        "Ağdaki diğer cihazınızda şu IP ayarlarını giriniz:" & @CRLF & @CRLF & _
                        "• IP Aralığı: 172.24.2.10 - 172.24.2.255" & @CRLF & _
                        "• Ağ Geçidi (Gateway): 172.24.2.1" & @CRLF & _
                        "• Alt Ağ Maskesi (Maske): 255.255.0.0" & @CRLF & _
                        "• DNS 1: 1.1.1.1" & @CRLF & _
                        "• DNS 2: 8.8.8.8")
            Else
                ; --- TİK KALDIRILDI: go-pcap2socks.exe KAPATILIYOR ---
                If ProcessExists("go-pcap2socks.exe") Then
                    ProcessClose("go-pcap2socks.exe")
                    $pcapPID = 0
                EndIf
            EndIf

        Case $btnRunZapret
            If $isZapretRunning = False Then
                StartWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            Else
                StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
            EndIf

        Case $btnInstallService
            InstallServiceClean($chkAutoHost)
            CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)

        Case $btnRemoveService
            RemoveService()
            $isPoisoned = CheckDnsPoisoningSilent()
            If Not $isPoisoned Then CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
            _RefreshStrategyLabel()
            MsgBox(64, "Bilgi", "Temizlik tamamlandı.")
    EndSwitch
WEnd

; --- MOTORA GÖRE HAZIR STRATEJİ LİSTESİNİ DOLDURAN FONKSİYON ---
Func _LoadStrategyList($sDefaultToSelect)
    GUICtrlSetData($cmbStrategy, "") ; İçeriği sıfırla
    If $currentEngine == "Zapret2" Then
        GUICtrlSetData($cmbStrategy, "Analiz Sonucu|Turk Telekom|Superonline|Vodafone|Vodafone (TT Altyapı)", $sDefaultToSelect)
    Else
        GUICtrlSetData($cmbStrategy, "Analiz Sonucu|Turk Telekom|TT Alternatif|Superonline|SOL Alternatif|Turkcell Mobil|Vodafone Mobil", $sDefaultToSelect)
    EndIf
EndFunc

; --- SEÇİLEN PROFILE GÖRE PARAMETRE DÖNDÜREN SİHİRBAZ ---
Func _GetActiveStrategyString()
    Local $sel = GUICtrlRead($cmbStrategy)
    If $sel == "Analiz Sonucu" Then
        Return StringStripWS(FileRead($strategyFile), 3)
    EndIf

    If $currentEngine == "Zapret2" Then
        Switch $sel
            Case "Turk Telekom"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
            Case "Superonline"
                Return "--payload=tls_client_hello --lua-desync=multidisorder:pos=2:seqovl=1"
            Case "Vodafone"
                Return '--lua-init=fake_default_tls="tls_mod(fake_default_tls,''rnd'')" --lua-desync="multisplit:pos=10,sniext+1:seqovl=#fake_default_tls"'
			Case "Vodafone (TT Altyapı)"
                Return '--lua-desync="wssize:wsize=1:scale=6" --lua-desync="luaexec:code=desync.patmod=tls_mod(fake_default_tls,''rnd,dupsid,padencap'',desync.reasm_data)" --lua-desync="tcpseg:pos=0,-1:seqovl=#patmod:seqovl_pattern=patmod" --lua-desync="drop"'
        EndSwitch
    Else ; Zapret1 Sürümü
        Switch $sel
            Case "Turk Telekom"
                Return "--dpi-desync=fake --dpi-desync-ttl=4"
            Case "TT Alternatif"
                Return "--dpi-desync=fake --dpi-desync-ttl=3"
            Case "Superonline"
                Return "--dpi-desync=fake --dpi-desync-fooling=md5sig"
            Case "SOL Alternatif"
                Return "--dpi-desync=fake --dpi-desync-fooling=md5sig --dpi-desync-ttl=3"
            Case "Turkcell Mobil"
                Return "--dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=3"
            Case "Vodafone Mobil"
                Return "--dpi-desync=multisplit --dpi-desync-split-pos=2"
        EndSwitch
    EndIf
    Return ""
EndFunc

Func _RefreshStrategyLabel()
    Local $sel = GUICtrlRead($cmbStrategy)
    If $sel == "Analiz Sonucu" Then
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil (Analiz Gerekli)"))
    Else
        GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: Hazır Profil (" & $sel & ")")
    EndIf
EndFunc

Func _SaveConfigAndExit()
    Local $engineVal = ($currentEngine == "Zapret2") ? "0" : "1"
    Local $hostlistEnabledVal = (GUICtrlRead($chkAutoHost) == $GUI_CHECKED) ? "1" : "0"
    Local $hostlistModeVal = (GUICtrlRead($rdoNormalHost) == $GUI_CHECKED) ? "1" : "0"
    Local $stratVal = GUICtrlRead($cmbStrategy)

    IniWrite($iniPath, "Settings", "ActiveEngine", $engineVal)
    IniWrite($iniPath, "Settings", "ActiveStrategy", $stratVal)
    IniWrite($iniPath, "Settings", "HostlistEnabled", $hostlistEnabledVal)
    IniWrite($iniPath, "Settings", "HostlistMode", $hostlistModeVal)
    ExitApp()
EndFunc

Func _UpdateEnginePaths($sEngineSelected)
    If StringInStr($sEngineSelected, "Zapret2") Then
        $currentEngine = "Zapret2"
        $strategyFile = @ScriptDir & "\strategy2.txt"
        $winwsPath = @ScriptDir & "\zapret\zapret-winws\winws2.exe"
        $blockcheckPath = @ScriptDir & "\zapret\blockcheck\blockcheck2.cmd"
        $logPath = @ScriptDir & "\zapret\blockcheck\blockcheck2.log"
        GUICtrlSetData($lblFooter, "Zapret2 v0.9.5.2")
    Else
        $currentEngine = "Zapret1"
        $strategyFile = @ScriptDir & "\strategy.txt"
        $winwsPath = @ScriptDir & "\zapret\zapret-winws\winws.exe"
        $blockcheckPath = @ScriptDir & "\zapret\blockcheck\blockcheck.cmd"
        $logPath = @ScriptDir & "\zapret\blockcheck\blockcheck.log"
        GUICtrlSetData($lblFooter, "Zapret v72.12")
    EndIf
EndFunc

Func _SendMessage($hWnd, $iMsg, $wParam = 0, $lParam = 0)
    Local $aResult = DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hWnd, "uint", $iMsg, "wparam", $wParam, "lparam", $lParam)
    Return $aResult[0]
EndFunc

Func ShowGUI()
    GUISetState(@SW_SHOW, $hGUI)
    GUISetState(@SW_RESTORE, $hGUI)
EndFunc

Func ExitApp()
    If $isZapretRunning Then StopWinws($btnRunZapret, $lblStatusText, $aOtherButtons)
	; --- PROGRAM KAPATILIRKEN PCAP MOTORUNU DA ÖLDÜR ---
    If ProcessExists("go-pcap2socks.exe") Then ProcessClose("go-pcap2socks.exe")
    Exit
EndFunc

Func _SetButtonsState(ByRef $aBtnArray, $iState)
    For $i = 0 To UBound($aBtnArray) - 1
        GUICtrlSetState($aBtnArray[$i], $iState)
    Next
EndFunc

Func CheckDnsPoisoningSilent()
    Local $testDomain = "updates.discord.com"
    Local $localIP = "", $safeIP = ""
    Local $sPSCommand = 'powershell -NoProfile -Command "(Resolve-DnsName ' & $testDomain & ' -Type A -ErrorAction SilentlyContinue).IPAddress"'
    Local $iPidLocal = Run($sPSCommand, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPidLocal)
    Local $sLocalOut = StringStripWS(StdoutRead($iPidLocal), 3)
    If $sLocalOut <> "" Then
        Local $aIPs = StringSplit($sLocalOut, @CRLF, 1)
        $localIP = $aIPs[1]
    EndIf
    $safeIP = "162.159.137.232"
    If $localIP = "" Then Return True
    If $safeIP = "" Then Return True
    Local $localPrefix = StringRegExpReplace($localIP, "^(\d+\.\d+).*", "$1")
    Local $safePrefix = StringRegExpReplace($safeIP, "^(\d+\.\d+).*", "$1")
    Return ($localPrefix <> $safePrefix)
EndFunc

Func CheckServiceStatus($manualBtn, $statusID, $lockArray, $chkID)
    Local $iPid = Run(@ComSpec & " /c sc query " & $serviceName, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPid)
    Local $sOutput = StdoutRead($iPid)
    If StringInStr($sOutput, "SERVICE_NAME") Then
        Local $iPidCfg = Run(@ComSpec & " /c sc qc " & $serviceName, "", @SW_HIDE, $STDOUT_CHILD)
        ProcessWaitClose($iPidCfg)
        Local $sCfgOut = StdoutRead($iPidCfg)

        If StringInStr($sCfgOut, "--hostlist-auto") Then
            GUICtrlSetState($chkID, $GUI_CHECKED)
            GUICtrlSetState($rdoAutoHost, $GUI_CHECKED)
        ElseIf StringInStr($sCfgOut, "--hostlist=") Then
            GUICtrlSetState($chkID, $GUI_CHECKED)
            GUICtrlSetState($rdoNormalHost, $GUI_CHECKED)
        Else
            GUICtrlSetState($chkID, $GUI_UNCHECKED)
            GUICtrlSetState($rdoAutoHost, $GUI_DISABLE)
            GUICtrlSetState($rdoNormalHost, $GUI_DISABLE)
        EndIf

        GUICtrlSetState($manualBtn, $GUI_DISABLE)
        _SetButtonsState($lockArray, $GUI_DISABLE)
        GUICtrlSetData($statusID, "SERVİS MODU AKTİF")
        GUICtrlSetColor($statusID, 0x27AE60)
    Else
        GUICtrlSetState($manualBtn, $GUI_ENABLE)
        _SetButtonsState($lockArray, $GUI_ENABLE)

		; --- LAN PAYLAŞIM TUŞUNU BURADA AKTİF EDİYORUZ ---
        GUICtrlSetState($chkLanShare, $GUI_ENABLE)

        If GUICtrlRead($chkID) = $GUI_CHECKED Then
            GUICtrlSetState($rdoAutoHost, $GUI_ENABLE)
            GUICtrlSetState($rdoNormalHost, $GUI_ENABLE)
        Else
            GUICtrlSetState($rdoAutoHost, $GUI_DISABLE)
            GUICtrlSetState($rdoNormalHost, $GUI_DISABLE)
        EndIf
        GUICtrlSetData($statusID, "SİSTEM HAZIR")
        GUICtrlSetColor($statusID, 0x2C3E50)
    EndIf
EndFunc

Func StartWinws($ctrlID, $statusID, $aBtns)
    ; --- DİNAMİK STRATEJİ SEÇİCİ TETİKLENDİ ---
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    Local $fullCommand = ""

    If $currentEngine = "Zapret2" Then
        Local $luaBaseDir = StringRegExpReplace($winwsPath, "\\[^\\]+$", "") & "\lua\"
        Local $luaParams = ' --lua-init="@' & $luaBaseDir & 'zapret-lib.lua"' & _
                           ' --lua-init="@' & $luaBaseDir & 'zapret-antidpi.lua"' & _
                           ' --lua-init="@' & $luaBaseDir & 'zapret-auto.lua"'
        $fullCommand = '"' & $winwsPath & '" --wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 ' & $activeStrategy & $luaParams
    Else
        $fullCommand = '"' & $winwsPath & '" --wf-tcp=0-65535 --wf-udp=0-65535 ' & $activeStrategy
    EndIf

    If GUICtrlRead($chkAutoHost) = $GUI_CHECKED Then
        If GUICtrlRead($rdoAutoHost) = $GUI_CHECKED Then
            $fullCommand &= ' --hostlist-auto="' & $hostlistPath & '"'
        ElseIf GUICtrlRead($rdoNormalHost) = $GUI_CHECKED Then
            If Not FileExists($normalHostlistPath) Then FileWrite($normalHostlistPath, "discord.com" & @CRLF & "updates.discord.com")
            $fullCommand &= ' --hostlist="' & $normalHostlistPath & '"'
        EndIf
    EndIf

    ClipPut($fullCommand)
    $zapretPID = Run($fullCommand, @ScriptDir & "\zapret\zapret-winws\", @SW_HIDE)

    If $zapretPID > 0 Then
        $isZapretRunning = True
        GUICtrlSetData($ctrlID, "DURDUR")
        GUICtrlSetData($statusID, "MANUEL MOD AKTİF")
        GUICtrlSetColor($statusID, 0xE67E22)
        _SetButtonsState($aBtns, $GUI_DISABLE)
    EndIf
EndFunc

Func StopWinws($ctrlID, $statusID, $aBtns)
    If ProcessExists($zapretPID) Then ProcessClose($zapretPID)
    While ProcessExists("winws2.exe") Or ProcessExists("winws.exe")
        ProcessClose("winws2.exe")
        ProcessClose("winws.exe")
    WEnd
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
    $isZapretRunning = False
    GUICtrlSetData($ctrlID, "ZAPRET'İ BAŞLAT")
    CheckServiceStatus($ctrlID, $statusID, $aBtns, $chkAutoHost)
EndFunc

Func InstallServiceClean($chkID)
    Local $activeStrategy = _GetActiveStrategyString()
    If $activeStrategy = "" Then Return MsgBox(48 + 8192, "Hata", "Strateji bulunamadı. Önce analiz yapın.")

    Local $binArgs = ""

    If $currentEngine = "Zapret2" Then
        Local $luaBaseDir = StringRegExpReplace($winwsPath, "\\[^\\]+$", "") & "\lua\"
        Local $luaParams = ' --lua-init="@' & $luaBaseDir & 'zapret-lib.lua"' & _
                           ' --lua-init="@' & $luaBaseDir & 'zapret-antidpi.lua"' & _
                           ' --lua-init="@' & $luaBaseDir & 'zapret-auto.lua"'
        $binArgs = '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 ' & $activeStrategy & $luaParams
    Else
        $binArgs = '--wf-tcp=0-65535 --wf-udp=0-65535 ' & $activeStrategy
    EndIf

    If GUICtrlRead($chkID) = $GUI_CHECKED Then
        If GUICtrlRead($rdoAutoHost) = $GUI_CHECKED Then
            if Not FileExists($hostlistPath) Then FileWrite($hostlistPath, "")
            $binArgs &= ' --hostlist-auto="' & $hostlistPath & '"'
        ElseIf GUICtrlRead($rdoNormalHost) = $GUI_CHECKED Then
            If Not FileExists($normalHostlistPath) Then FileWrite($normalHostlistPath, "discord.com" & @CRLF & "updates.discord.com")
            $binArgs &= ' --hostlist="' & $normalHostlistPath & '"'
        EndIf
    EndIf

    Local $fullBinPath = '"' & $winwsPath & '" ' & $binArgs
    $fullBinPath = StringReplace($fullBinPath, '"', '\"')

    RemoveService()
    Sleep(500)

    If RunWait(@ComSpec & " /c sc create " & $serviceName & ' binPath= "' & $fullBinPath & '" start= auto', "", @SW_HIDE) = 0 Then
        RunWait(@ComSpec & " /c sc start " & $serviceName, "", @SW_HIDE)
        MsgBox(64 + 8192, "Başarılı", "Seçilen profil servis olarak kuruldu.")
    EndIf
EndFunc

Func RemoveService()
    RunWait(@ComSpec & " /c sc stop " & $serviceName & " & sc delete " & $serviceName & " & sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
EndFunc

; =========================================================================
; --- ZAPRET 1 ANALİZ FONKSİYONLARI ---
; =========================================================================
Func RunBlockcheck($ctrlID)
    Local $isNoBypassNeeded = False
    If FileExists($logPath) Then FileDelete($logPath)
    Local $bashPath = @ScriptDir & "\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\zapret\blockcheck\zapret\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\zapret\blockcheck", @SW_HIDE)
    Local $hWaitTimer = TimerInit()
    While Not FileExists($logPath)
        Sleep(100)
        If TimerDiff($hWaitTimer) > 10000 Then ExitLoop
    WEnd
    While ProcessExists("bash.exe")
        Sleep(1000)
        Local $hFile = FileOpen($logPath, 0)
        If $hFile <> -1 Then
            Local $sContent = FileRead($hFile)
            FileClose($hFile)
            If StringInStr($sContent, "working without bypass") Or StringInStr($sContent, "not blocked") Then
                $isNoBypassNeeded = True
                ExitLoop
            EndIf
        EndIf
    WEnd
    If $isNoBypassNeeded Then
        MsgBox(64 + 8192, "Bilgi: Zapret1 Analiz Tamamlandı", _
                "İnternet hattınızda herhangi bir DPI / Sansür kısıtlaması saptanmadı!")
    Else
        ExtractSummary($logPath)
    EndIf
EndFunc

Func ExtractSummary($filePath)
    Local $aLogContent
    If Not _FileReadToArray($filePath, $aLogContent) Then Return
    Local $found = False, $strategy = ""
    For $i = $aLogContent[0] To 1 Step -1
        If StringInStr($aLogContent[$i], "SUMMARY") Then
            Local $fullLine = $aLogContent[$i + 1]
            Local $pos = StringInStr($fullLine, "--dpi")
            If $pos > 0 Then
                $strategy = StringStripWS(StringMid($fullLine, $pos), 3)
                $found = True
                ExitLoop
            EndIf
        EndIf
    Next
    If $found And $strategy <> "" Then
        Local $sFormatted = _FormatStrategyQuotes($strategy)
        Local $hFile = FileOpen($strategyFile, 2)
        If $hFile <> -1 Then
            FileWrite($hFile, $sFormatted)
            FileClose($hFile)
            MsgBox(64 + 8192, "Başarılı", "Analiz tamamlandı. Zapret1 için strateji ayıklandı.")
        EndIf
    Else
        MsgBox(16 + 8192, "Başarısız", "Strateji bulunamadı.")
    EndIf
EndFunc

; =========================================================================
; --- ZAPRET 2 ANALİZ FONKSİYONU ---
; =========================================================================
Func RunBlockcheck2($ctrlID)
    Local $strategyFound = ""
    Local $isNoBypassNeeded = False
    If FileExists($logPath) Then FileDelete($logPath)
    Local $bashPath = @ScriptDir & "\zapret\cygwin\bin\bash.exe"
    Local $shScriptPath = @ScriptDir & "\zapret\blockcheck\zapret2\blog.sh"
    Local $sCommand = '"' & $bashPath & '" -i "' & $shScriptPath & '"'
    Local $iPidBash = Run($sCommand, @ScriptDir & "\zapret\blockcheck", @SW_HIDE)
    Local $hWaitTimer = TimerInit()
    While Not FileExists($logPath)
        Sleep(500)
        If TimerDiff($hWaitTimer) > 10000 Then ExitLoop
    WEnd
    Local $hTimer = TimerInit()
    While ProcessExists("bash.exe")
        Sleep(1000)
        Local $hFile = FileOpen($logPath, 0)
        If $hFile <> -1 Then
            Local $sContent = FileRead($hFile)
            FileClose($hFile)
            Local $sFiltered = StringReplace($sContent, "iana.org", "IGNORE")
            If StringInStr($sFiltered, "!!!!! AVAILABLE !!!!!") Then
                $strategyFound = _GetLastStrategyFromText($sContent)
                If $strategyFound <> "" Then ExitLoop
            EndIf
            If StringInStr($sContent, "working without bypass") Or StringInStr($sContent, "not blocked") Then
                $isNoBypassNeeded = True
            EndIf
        EndIf
        If TimerDiff($hTimer) > 600000 Then ExitLoop
    WEnd
    Local $aProcesses = ["bash.exe", "sh.exe", "tee.exe", "winws2.exe"]
    For $sProc In $aProcesses
        RunWait(@ComSpec & " /c taskkill /F /IM " & $sProc & " /T", "", @SW_HIDE)
    Next
    If $strategyFound <> "" Then
        Local $hStore = FileOpen($strategyFile, 2)
        FileWrite($hStore, $strategyFound)
        FileClose($hStore)
        MsgBox(64 + 8192, "Başarılı", "Analiz tamamlandı. Zapret2 için strateji ayıklandı.")
    ElseIf $isNoBypassNeeded Then
        MsgBox(64 + 8192, "Bilgi: Zapret2 Analiz Tamamlandı", _
                "İnternet hattınızda herhangi bir DPI / Sansür kısıtlaması saptanmadı!")
    Else
        MsgBox(16 + 8192, "Başarısız", "Zaman aşımı.")
    EndIf
EndFunc

Func _GetLastStrategyFromText($sText)
    Local $aLines = StringSplit(StringStripCR($sText), @LF)
    For $i = $aLines[0] To 1 Step -1
        If StringInStr($aLines[$i], "iana.org") Then ContinueLoop
        If StringInStr($aLines[$i], "!!!!! AVAILABLE !!!!!") Then
            If $i > 1 Then
                Local $sPrevLine = $aLines[$i - 1]
                Local $targetStr = "--wf-tcp-out=443"
                Local $startPos = StringInStr($sPrevLine, $targetStr)
                If $startPos > 0 Then
                    Local $cutPoint = $startPos + StringLen($targetStr)
                    Local $sRawStrategy = StringStripWS(StringMid($sPrevLine, $cutPoint), 3)
                    Return _FormatStrategyQuotes($sRawStrategy)
                EndIf
            EndIf
        EndIf
    Next
    Return ""
EndFunc

Func _FormatStrategyQuotes($sRawStrategy)
    Local $aParams = StringSplit($sRawStrategy, " ", 1)
    Local $sFormattedStrategy = ""
    For $j = 1 To $aParams[0]
        Local $sCurrentParam = $aParams[$j]
        Local $iFirstEq = StringInStr($sCurrentParam, "=")
        If $iFirstEq > 0 Then
            Local $sParamName = StringLeft($sCurrentParam, $iFirstEq)
            Local $sParamValue = StringMid($sCurrentParam, $iFirstEq + 1)
            $sCurrentParam = $sParamName & '"' & $sParamValue & '"'
        EndIf
        $sFormattedStrategy &= $sCurrentParam & " "
    Next
    Return StringStripWS($sFormattedStrategy, 3)
EndFunc

Func HasValidStrategy()
    If Not FileExists($strategyFile) Then Return False
    Local $sContent = StringStripWS(FileRead($strategyFile), 3)
    Return ($sContent <> "")
EndFunc

; --- Güvenlik Duvarı Sorgu Fonksiyonu (Gelişmiş İzin Kontrolü - Düzeltildi) ---
Func HasFirewallRule($fullPath)
    ; Önce exe yoluna ait olan kural filtrelerini buluyoruz, ardından bu filtrelere bağlı ana kuralların 'Allow' ve 'True' olup olmadığına bakıyoruz.
	Local $fixedPath = StringReplace($fullPath, "I", "i")
	Local $psCmd = 'powershell -NoProfile -Command "Get-NetFirewallApplicationFilter -Program ''' & $fixedPath & ''' -ErrorAction SilentlyContinue | Get-NetFirewallRule | Where-Object { $_.Action -eq ''Allow'' -and $_.Enabled -eq ''True'' }"'
	Local $iPID = Run(@ComSpec & ' /c ' & $psCmd, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPID)

    ; Eğer kural hem mevcutsa hem de durumu 'Allow' (İzin Ver) ve 'True' (Etkin) ise PowerShell çıktı üretir.
    Return (StringLen(StdoutRead($iPID)) > 10)
EndFunc
