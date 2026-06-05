#RequireAdmin
#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=zapret\zapret-winws\winws2.ico
#AutoIt3Wrapper_UseX64=y
#AutoIt3Wrapper_Res_Description=Zapret2 Windows Türkiye - Zapret Kullanmayı Kolaylaştıran Araç
#AutoIt3Wrapper_Res_Fileversion=2.4.0.0
#AutoIt3Wrapper_Res_ProductVersion=2.4
#AutoIt3Wrapper_Res_LegalCopyright=Ali Mali
#AutoIt3Wrapper_Res_Language=1055
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#Region ; **** Directives created by AutoIt3Wrapper_GUI ****
#EndRegion ; **** Directives created by AutoIt3Wrapper_GUI ****

#include <File.au3>
#include <MsgBoxConstants.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WindowsConstants.au3>
#include <ProgressConstants.au3>
#include <TrayConstants.au3>


; --- ZIP / TEMP KLASÖRÜ KONTROLÜ ---
Local $currentDir = @ScriptDir
If StringInStr($currentDir, @TempDir) Or StringInStr($currentDir, "Temporary Internet Files") Or StringInStr($currentDir, "vfs") Then
    MsgBox(16, "Hata: Arşivden Çalıştırma Saptandı", _
            "Programı ZIP dosyasının içinden doğrudan çalıştırmayın!" & @CRLF & @CRLF & _
            "1. ZIP dosyasındaki tüm dosyaları normal bir klasöre çıkarın." & @CRLF & _
            "2. Ardından programı o klasörden tekrar başlatın." & @CRLF & @CRLF & _
            "Geçici klasörlerden çalıştırıldığında sürücü izinleri alınamaz.")
    Exit
EndIf

; --- GÜVENLİK UYARILARINI (SMARTSCREEN) KALDIR ---
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

; --- Tepsi Menüsü Ayarları ---
Opt("TrayMenuMode", 3)
Opt("TrayOnEventMode", 1)

; --- Ayarlar ve Dosya Yolları ---
Local $serviceName = "ZapretService"
Local $strategyFile = @ScriptDir & "\strategy.txt"
Local $winwsPath = @ScriptDir & "\zapret\zapret-winws\winws2.exe"
Local $hostlistPath = @ScriptDir & "\autohostlist.txt"
Local $normalHostlistPath = @ScriptDir & "\hostlist.txt"
Local $blockcheckPath = @ScriptDir & "\zapret\blockcheck\blockcheck2.cmd"
Local $logPath = @ScriptDir & "\zapret\blockcheck\blockcheck2.log"

; --- Global Değişkenler ---
Global $isZapretRunning = False
Global $zapretPID = 0

; --- GUI Tasarımı ---
Local $hGUI = GUICreate("Zapret2 Windows Türkiye v2.4", 400, 480) ; Yükseklik grup için ideal boyuta getirildi
GUISetBkColor(0xFFFFFF)

; --- Tepsi Menüsü Öğeleri ---
Local $trayShow = TrayCreateItem("Göster")
TrayItemSetOnEvent(-1, "ShowGUI")
TrayCreateItem("")
Local $trayExit = TrayCreateItem("Kapat")
TrayItemSetOnEvent(-1, "ExitApp")
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

Local $lblStrategyInfo = GUICtrlCreateLabel("Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil"), 15, 55, 370, 20, $SS_CENTER)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x666666)

; --- Butonlar (BAŞLANGIÇTA DISABLED) ---
Local $btnRunZapret = GUICtrlCreateButton("ZAPRET'İ BAŞLAT", 50, 105, 300, 55)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 11, 800, 0, "Segoe UI")

; --- HOSTLIST HİBRİT PANELİ (YENİ) ---
Local $chkAutoHost = GUICtrlCreateCheckbox(" Hostlist (Filtre listesi) Kullanımını Aktifleştir", 55, 170, 290, 25)
GUICtrlSetState(-1, BitOR($GUI_CHECKED, $GUI_DISABLE))
GUICtrlSetFont(-1, 9, 800, 0, "Segoe UI")

GUICtrlCreateGroup(" Filtreleme Modu ", 45, 195, 310, 75)
Local $rdoAutoHost = GUICtrlCreateRadio(" Auto hostlist (Zapret oluşturur)", 58, 215, 280, 20)
GUICtrlSetState(-1, BitOR($GUI_CHECKED, $GUI_DISABLE))
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")

Local $rdoNormalHost = GUICtrlCreateRadio(" Manuel hostlist ('hostlist.txt' İçeriği)", 58, 240, 280, 20)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlCreateGroup("", -1, -1, 1, 1)

Local $btnAnalyze = GUICtrlCreateButton("ISS Analizi (Blockcheck) Yap", 50, 280, 300, 40)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnInstallService = GUICtrlCreateButton("Servis Olarak Yükle (Otomatik Başlat)", 50, 330, 300, 40)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $btnRemoveService = GUICtrlCreateButton("Servis ve Kalıntıları Temizle", 50, 380, 300, 35)
GUICtrlSetFont(-1, 10, 600, 0, "Segoe UI")

Local $lblFooter = GUICtrlCreateLabel("Zapret2 v0.9.5.2", 0, 455, 400, 20, $SS_CENTER)
GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0xBDC3C7)

; Dizi tanımlamaları güncellendi
Local $aCriticalButtons[6] = [$btnRunZapret, $btnAnalyze, $btnInstallService, $chkAutoHost, $rdoAutoHost, $rdoNormalHost]
Local $aOtherButtons[6] = [$btnAnalyze, $btnInstallService, $btnRemoveService, $chkAutoHost, $rdoAutoHost, $rdoNormalHost]

GUISetState(@SW_SHOW)

; --- GÜVENLİ AÇILIŞ AKIŞI ---
RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
GUICtrlSetData($lblStatusText, "DNS KONTROL EDİLİYOR...")

Local $isPoisoned = CheckDnsPoisoningSilent()

If $isPoisoned Then
    _SetButtonsState($aCriticalButtons, $GUI_DISABLE)
    GUICtrlSetData($lblStatusText, "DNS ZEHİRLENMESİ SAPTANDI!")
    GUICtrlSetColor($lblStatusText, 0xC0392B)
    MsgBox(16, "Kritik Uyarı", "ISS tarafından DNS Zehirlenmesi saptandı!" & @CRLF & @CRLF & _
            "Bu şartlarda Zapret doğru çalışmayacaktır." & @CRLF & @CRLF & _
            "Lütfen DNS değiştirin veya YogaDNS, NextDNS gibi DNS istemcileri kullanın.")
Else
    CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
EndIf

; --- Ana Döngü ---
While 1
    Local $nMsg = GUIGetMsg()
    Switch $nMsg
        Case $GUI_EVENT_CLOSE
            ExitApp()

        Case $GUI_EVENT_MINIMIZE
            GUISetState(@SW_HIDE, $hGUI)
            TraySetToolTip("Zapret Windows Türkiye Çalışıyor")

        ; --- CHECKBOX'A TIKLANDIĞINDA RADYOLARI TETİKLE ---
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

                RunBlockcheck($btnAnalyze)

                _SendMessage(GUICtrlGetHandle($pBar), $PBM_SETMARQUEE, False, 0)
                GUICtrlSetState($pBar, $GUI_HIDE)

                _SetButtonsState($aCriticalButtons, $GUI_ENABLE)
                GUICtrlSetState($btnRemoveService, $GUI_ENABLE)
                CheckServiceStatus($btnRunZapret, $lblStatusText, $aCriticalButtons, $chkAutoHost)
                GUICtrlSetData($lblStatusText, "ANALİZ TAMAMLANDI")
                GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil"))
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
            GUICtrlSetData($lblStrategyInfo, "Strateji Durumu: " & (HasValidStrategy() ? "Mevcut" : "Mevcut Değil"))
            MsgBox(64, "Bilgi", "Temizlik tamamlandı.")
    EndSwitch
WEnd

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

		#cs		*****************************DOH KONTROLÜ YERİNE SABİT DISCORD IP ADRESİ YAZIYORUM*******************
    ; GÜVENLİ DoH SORGUSU (Cloudflare)
    Local $sDoH = _
        'powershell -NoProfile -Command "' & _
        '$r = Invoke-RestMethod ''https://1.1.1.1/dns-query?name=' & $testDomain & '&type=A'' ' & _
        '-Headers @{Accept=''application/dns-json''} -ErrorAction SilentlyContinue; ' & _
        '$r.Answer.data"'

    Local $iPidSafe = Run($sDoH, "", @SW_HIDE, $STDOUT_CHILD)
    ProcessWaitClose($iPidSafe)

    Local $sSafeOut = StringStripWS(StdoutRead($iPidSafe), 3)

    If $sSafeOut <> "" Then
        Local $aSafeIPs = StringSplit($sSafeOut, @CRLF, 1)
        $safeIP = $aSafeIPs[1]
    EndIf
	#ce

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

        ; Servis durumuna göre Checkbox ve Radyo buton senkronizasyonu
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

        ; Sistem açıkken checkbox durumuna göre radyoları ayarla
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
    Local $savedStrategy = StringStripWS(FileRead($strategyFile), 3)
    If $savedStrategy = "" Then Return MsgBox(48, "Hata", "Önce analiz yapın.")

    Local $luaBaseDir = StringRegExpReplace($winwsPath, "\\[^\\]+$", "") & "\lua\"
    Local $luaParams = ' --lua-init="@' & $luaBaseDir & 'zapret-lib.lua"' & _
                       ' --lua-init="@' & $luaBaseDir & 'zapret-antidpi.lua"' & _
                       ' --lua-init="@' & $luaBaseDir & 'zapret-auto.lua"'

    Local $fullCommand = '"' & $winwsPath & '" --wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 ' & $savedStrategy & $luaParams

    ; --- HİBRİT KONTROL MEKANİZMASI ---
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
    While ProcessExists("winws2.exe")
        ProcessClose("winws2.exe")
    WEnd
    RunWait(@ComSpec & " /c sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
    $isZapretRunning = False
    GUICtrlSetData($ctrlID, "ZAPRET'İ BAŞLAT")
    CheckServiceStatus($ctrlID, $statusID, $aBtns, $chkAutoHost)
EndFunc

Func InstallServiceClean($chkID)
    Local $savedStrategy = StringStripWS(FileRead($strategyFile), 3)
    If $savedStrategy = "" Then Return MsgBox(48, "Hata", "Önce analiz yapın.")

    Local $luaBaseDir = StringRegExpReplace($winwsPath, "\\[^\\]+$", "") & "\lua\"
    Local $luaParams = ' --lua-init="@' & $luaBaseDir & 'zapret-lib.lua"' & _
                       ' --lua-init="@' & $luaBaseDir & 'zapret-antidpi.lua"' & _
                       ' --lua-init="@' & $luaBaseDir & 'zapret-auto.lua"'

    Local $binArgs = '--wf-l3=ipv4 --wf-tcp-out=0-65535 --wf-udp-out=0-65535 ' & $savedStrategy & $luaParams

    ; --- SERVİS İÇİN HİBRİT KONTROL ---
    If GUICtrlRead($chkID) = $GUI_CHECKED Then
        If GUICtrlRead($rdoAutoHost) = $GUI_CHECKED Then
            If Not FileExists($hostlistPath) Then FileWrite($hostlistPath, "")
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
        MsgBox(64, "Başarılı", "Servis kuruldu." & @CRLF & @CRLF & "Zapret bu programı açmasanız da seçtiğiniz modda çalışacaktır.")
    EndIf
EndFunc

Func RemoveService()
    RunWait(@ComSpec & " /c sc stop " & $serviceName & " & sc delete " & $serviceName & " & sc stop WinDivert & sc delete WinDivert & sc stop WinDivert14 & sc delete WinDivert14", "", @SW_HIDE)
EndFunc

Func RunBlockcheck($ctrlID)
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

    ; --- LOG TAKİP DÖNGÜSÜ ---
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

            ; --- SANSÜRSÜZ / DPI UYGULANMAYAN HAT KONTROLÜ ---
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

    ; --- SONUCU BİLDİRİRKEN ---
    If $strategyFound <> "" Then
        Local $hStore = FileOpen($strategyFile, 2)
        FileWrite($hStore, $strategyFound)
        FileClose($hStore)
        MsgBox(64, "Başarılı", "Analiz tamamlandı. Uygun strateji ayıklandı.")
    ElseIf $isNoBypassNeeded Then
        MsgBox(64, "Bilgi: Analiz Tamamlandı", _
                "İnternet hattınızda herhangi bir DPI / Sansür kısıtlaması saptanmadı!" & @CRLF & @CRLF & _
                "Zapret gibi araçları kullanmanıza gerek yoktur." & @CRLF & _
                "Discord veya diğer engelli servislere erişmek için sadece güvenli bir DNS (NextDNS, YogaDNS, Cloudflare vb.) kullanmanız yeterlidir.")
    Else
        MsgBox(16, "Başarısız", "10 dakika boyunca strateji bulunamadı veya işlem zaman aşımına uğradı.")
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

                    ; =========================================================================
                    ; --- DİNAMİK ÇİFT TIRNAK PAKETLEME MEKANİZMASI ---
                    ; =========================================================================
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

                    $sFormattedStrategy = StringStripWS($sFormattedStrategy, 3)
                    ; =========================================================================

                    Return $sFormattedStrategy
                EndIf
            EndIf
        EndIf
    Next
    Return ""
EndFunc

Func HasValidStrategy()
    If Not FileExists($strategyFile) Then Return False
    Local $sContent = StringStripWS(FileRead($strategyFile), 3)
    Return ($sContent <> "")
EndFunc
