@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================================
rem  NetTune.bat - evidence-based Windows network tuning for online games
rem
rem  Goal: lower and steadier in-game ping, fewer lag spikes and less packet
rem  loss on Windows 10 (version 2004 or newer) and Windows 11, without
rem  spending CPU time that would cost framerate or frametime consistency.
rem
rem  Only changes that measurements or documented vendor fixes show to work
rem  on current Windows are applied. Adapters, Wi-Fi, VPNs, installed software
rem  and the Windows build are detected at runtime and every step adapts.
rem
rem  Writes no logs, exports, backups or restore points. Does not flush or
rem  delete DNS, ARP or any other network data, and does not touch power
rem  plans, powercfg, temp files or disk cleanup. NetTune.md explains every
rem  change, the evidence behind it and how to undo it.
rem
rem  The PowerShell code for the adapter, routing, marking and test steps is
rem  at the end of this file, after the batch code. Batch never runs it;
rem  each of those steps starts it.
rem ==========================================================================

rem ---- Options -------------------------------------------------------------
rem  ADAPTER_MODE           on or keep
rem      Ethernet and Wi-Fi driver settings. Changed adapters restart once,
rem      so the connection drops for a few seconds.
rem  WIFI_LOCATION_MODE     auto or keep
rem      auto turns off Location services when Wi-Fi is your connection,
rem      because location requests make Windows scan for networks, which
rem      stalls the connection for a moment.
rem  ROUTE_MODE             on or keep
rem      Sends traffic over Ethernet when Wi-Fi is connected at the same time.
rem  DSCP_MODE              on or keep
rem      Marks game packets with DSCP 46, Expedited Forwarding.
rem  QOS_UDP_APPS           programs separated by semicolons
rem      Their UDP traffic is marked. Most online games use UDP.
rem  QOS_ALL_APPS           programs separated by semicolons
rem      Their UDP and TCP traffic is marked, for games that use TCP.
rem  DO_BACKGROUND_PERCENT  1 to 90, or keep
rem      Cap for background Windows Update and Store downloads, as a
rem      percentage of measured bandwidth.
rem  ONEDRIVE_MODE          on or keep
rem      OneDrive uploads only with spare bandwidth, using Windows LEDBAT.
rem  SOCKET_BUFFER_MODE     on or keep
rem      Larger Winsock default receive buffer, so a game that stalls for a
rem      moment does not lose the packets queued meanwhile.
rem  DIAG_MODE              on or off
rem      Latency, jitter and packet-loss test at the end, about 20 seconds.
rem --------------------------------------------------------------------------
set "ADAPTER_MODE=on"
set "WIFI_LOCATION_MODE=auto"
set "ROUTE_MODE=on"
set "DSCP_MODE=on"
set "QOS_UDP_APPS=cs2.exe;VALORANT-Win64-Shipping.exe;FortniteClient-Win64-Shipping.exe;r5apex.exe;r5apex_dx12.exe;League of Legends.exe;Overwatch.exe;cod.exe;dota2.exe;RocketLeague.exe;TslGame.exe;RainbowSix.exe;RainbowSix_Vulkan.exe;EscapeFromTarkov.exe;EscapeFromTarkovArena.exe;Marvel-Win64-Shipping.exe;Discovery.exe;project8.exe;destiny2.exe;GTA5.exe;GTA5_Enhanced.exe;RDR2.exe;bf6.exe;BF2042.exe;bfv.exe;bf1.exe;HaloInfinite.exe;RustClient.exe;DeadByDaylight-Win64-Shipping.exe;HuntGame.exe;tf_win64.exe;Minecraft.Windows.exe;RobloxPlayerBeta.exe;NarakaBladepoint.exe;aces.exe;enlisted.exe;WorldOfTanks.exe;WorldOfWarships64.exe;DeltaForceClient-Win64-Shipping.exe;SoTGame.exe;helldivers2.exe;Palworld-Win64-Shipping.exe;FallGuys_client_game.exe;Brawlhalla.exe;StreetFighter6.exe;Polaris-Win64-Shipping.exe;FC25.exe;FC26.exe;SquadGame.exe;HLL-Win64-Shipping.exe;InsurgencyClient-Win64-Shipping.exe;Chivalry2-Win64-Shipping.exe;Warframe.x64.exe;eldenring.exe;nightreign.exe;MonsterHunterWilds.exe;Albion-Online.exe"
set "QOS_ALL_APPS=Wow.exe;WowClassic.exe;ffxiv_dx11.exe;PathOfExile.exe;PathOfExile_x64.exe;PathOfExileSteam.exe;PathOfExile_x64Steam.exe;Diablo IV.exe;LOSTARK.exe;BlackDesert64.exe;Gw2-64.exe;eso64.exe;osclient.exe;MapleStory.exe;TL.exe"
set "DO_BACKGROUND_PERCENT=20"
set "ONEDRIVE_MODE=on"
set "SOCKET_BUFFER_MODE=on"
set "DIAG_MODE=on"

rem A user variable named ERRORLEVEL would hide the real exit codes.
set "ERRORLEVEL="

rem ---- Run as a native 64-bit process: avoids registry/System32 redirection
if defined PROCESSOR_ARCHITEW6432 if exist "%SystemRoot%\Sysnative\cmd.exe" (
    "%SystemRoot%\Sysnative\cmd.exe" /d /c ""%~f0" %*"
    exit /b
)

rem ---- Known-good tool resolution, independent of the user's PATH ---------
set "SYS32=%SystemRoot%\System32"
set "PATH=%SYS32%;%SystemRoot%;%SYS32%\Wbem;%SYS32%\WindowsPowerShell\v1.0"
set "PATHEXT=.COM;.EXE;.BAT;.CMD"
set "PS=%SYS32%\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS="
set "NT_SELF=%~f0"
rem Loads the PowerShell section between the two marker lines at the end of
rem this file and runs the step named in NT_STEP.
set "NT_PSRUN=$t=[IO.File]::ReadAllText($env:NT_SELF);$m='#'+'NTPS';$i=$t.IndexOf($m);$j=$t.LastIndexOf($m);if($i -lt 0 -or $j -le $i){exit 3};& ([scriptblock]::Create($t.Substring($i,$j-$i)))"

rem ---- Administrator rights (self-elevates) --------------------------------
rem Exit codes are compared with "0" rather than "if errorlevel 1" throughout,
rem because some tools (fltmc among them) report errors as negative numbers.
fltmc >nul 2>&1
if not "%errorlevel%"=="0" goto :elevate

:main
title NetTune
echo.
echo  ==============================================================
echo   NetTune - Windows network tuning for ping, jitter and loss
echo  ==============================================================
echo.
echo  Detecting network...

rem ---- Windows version -----------------------------------------------------
set "CV=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
set "GT_BUILD="
set "GT_UBR=0"
set "GT_VER="
set "GT_INSTTYPE="
for /f "tokens=3" %%A in ('reg query "%CV%" /v CurrentBuildNumber 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_BUILD=%%A"
for /f "tokens=3" %%A in ('reg query "%CV%" /v UBR 2^>nul ^| findstr /c:"REG_DWORD"') do set /a "GT_UBR=%%A"
for /f "tokens=2,*" %%A in ('reg query "%CV%" /v DisplayVersion 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_VER=%%B"
for /f "tokens=2,*" %%A in ('reg query "%CV%" /v InstallationType 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_INSTTYPE=%%B"
if not defined GT_BUILD goto :unsupported
if %GT_BUILD% LSS 19041 goto :unsupported
if /i "%GT_INSTTYPE%"=="Server" goto :unsupported
set "GT_OS=Windows 10"
if %GT_BUILD% GEQ 22000 set "GT_OS=Windows 11"
echo.
echo   Windows       %GT_OS% %GT_VER%, build %GT_BUILD%.%GT_UBR%

rem ---- Network detection (PowerShell prints the summary itself) -----------
set "NT_PSOK="
set "NT_INET=unknown"
set "NT_INTELWIFI=0"
set "NT_ONEDRIVE=?"
set "NT_RSS=?"
set "NT_TASKOFFLOAD=?"
set "NT_BBR2="
set "NT_USERSID="
if not defined PS goto :detect_done
set "NT_STEP=detect"
for /f "usebackq tokens=1,* delims==" %%A in (`%PS% -NoProfile -NonInteractive -Command "%NT_PSRUN%" ^| findstr /b /c:"NT_"`) do set "%%A=%%B"
:detect_done
if not defined NT_PSOK echo   [WARN] PowerShell detection failed: the adapter, routing, marking and test steps will be skipped.

rem Per-user settings are read from the signed-in user's hive, even when the
rem script was elevated with a different administrator account.
set "UROOT=HKCU"
if not defined NT_USERSID goto :uroot_done
reg query "HKU\%NT_USERSID%" >nul 2>&1
if "%errorlevel%"=="0" set "UROOT=HKU\%NT_USERSID%"
:uroot_done

rem ---- Plan and confirmation -----------------------------------------------
echo.
echo  Planned changes
if /i not "%ADAPTER_MODE%"=="keep" echo   - Ethernet and Wi-Fi driver settings: power saving, receive buffers, offloads, roaming, scans
if /i not "%WIFI_LOCATION_MODE%"=="keep" if "%NT_INET%"=="Wi-Fi" echo   - Location services off, to stop the Wi-Fi scans behind periodic ping spikes
if /i not "%SOCKET_BUFFER_MODE%"=="keep" echo   - Network stack: undo known-harmful leftovers, larger Winsock receive buffer
if /i "%SOCKET_BUFFER_MODE%"=="keep" echo   - Network stack: undo known-harmful leftovers
if /i not "%ROUTE_MODE%"=="keep" echo   - Prefer Ethernet over Wi-Fi when both are connected
if /i not "%DSCP_MODE%"=="keep" echo   - Mark game packets DSCP 46, so Wi-Fi and QoS routers send them first
if /i not "%DO_BACKGROUND_PERCENT%"=="keep" echo   - Background Windows Update and Store downloads: capped, no uploads to internet peers
if /i not "%ONEDRIVE_MODE%"=="keep" if not "%NT_ONEDRIVE%"=="0" echo   - OneDrive uploads only with spare bandwidth
echo   - Check for VPNs, virtual switches, bridges and traffic shapers in the path
if /i not "%DIAG_MODE%"=="off" echo   - Latency, jitter and packet-loss test
echo.
if /i not "%ADAPTER_MODE%"=="keep" echo  Adapters that change restart, so the connection drops for a few seconds.
if /i not "%ADAPTER_MODE%"=="keep" echo  Don't run this in the middle of a match.
echo  A restart of Windows is needed afterwards. NetTune.md shows how to undo each change.
echo.
choice /c YN /n /m "  Apply these changes now? [Y/N] "
if errorlevel 2 goto :cancelled

set "STEPN=0"
set "STEPS=9"
call :step_adapters
call :step_wifiscan
call :step_stack
call :step_route
call :step_dscp
call :step_do
call :step_onedrive
call :step_conflicts
call :step_diag

echo.
echo  ==============================================================
echo   Done. Restart Windows so every change takes effect.
echo  ==============================================================
echo.
choice /c YN /n /m "  Restart now? [Y/N] "
if errorlevel 2 goto :no_restart
shutdown /r /t 5 /c "NetTune: restarting to apply changes"
exit /b 0

:no_restart
echo.
echo  Restart before you test in game: the socket buffer, packet marking and
echo  download-cap changes only take full effect after a reboot.
echo.
pause
exit /b 0


rem ==========================================================================
rem  Steps
rem ==========================================================================

:step_adapters
rem Ethernet: Energy-Efficient Ethernet and vendor power saving off (Intel's
rem documented fix for I225/I226 stutter and drops), USB selective suspend
rem off, receive buffers raised so bursts are not dropped, checksum offloads
rem back on where an optimizer turned them off, an Intel interrupt rate of
rem High or Extreme lowered to Medium (Adaptive, the default, is kept), half
rem duplex fixed. Wi-Fi: less roaming, no MIMO or U-APSD power save, 5 GHz
rem preferred, full transmit power, and Intel background scan blocking.
call :hdr "Ethernet and Wi-Fi adapter settings"
if /i "%ADAPTER_MODE%"=="keep" echo   [SKIP] ADAPTER_MODE is set to keep.& exit /b 0
if not defined NT_PSOK echo   [SKIP] Needs Windows PowerShell.& exit /b 0
call :ps adapters
exit /b 0


:step_wifiscan
rem Location requests make Windows scan for Wi-Fi networks; a scan takes
rem the radio off its channel for a moment, which shows up in game as a
rem ping spike every minute or so.
call :hdr "Wi-Fi background scanning"
if /i "%WIFI_LOCATION_MODE%"=="keep" echo   [SKIP] WIFI_LOCATION_MODE is set to keep.& exit /b 0
if not "%NT_INET%"=="Wi-Fi" echo   [SKIP] Your connection is not Wi-Fi, so there are no Wi-Fi scan spikes.& exit /b 0
set "LOCK=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
set "LOCV="
for /f "tokens=2,*" %%A in ('reg query "%LOCK%" /v Value 2^>nul ^| findstr /c:"REG_SZ"') do set "LOCV=%%B"
if /i "%LOCV%"=="Deny" echo   [ OK ] Location services are already off.& goto :wifi_tail
reg add "%LOCK%" /v Value /t REG_SZ /d Deny /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not turn off Location services.& goto :wifi_tail
echo   [ OK ] Location services: off. Location lookups no longer trigger Wi-Fi scans.
echo          Maps, weather, automatic time zone and Find my device need them:
echo          Settings, Privacy and security, Location.
:wifi_tail
if not "%NT_INTELWIFI%"=="1" echo   [INFO] Windows itself can still scan about once a minute. Intel cards have a setting that blocks it; on others, Ethernet avoids it.
exit /b 0


:step_stack
rem Undoes leftovers that measurably hurt: BBR2 congestion control (stalls
rem loopback TLS on Windows 11, breaking Steam and Battle.net), RSS off (all
rem network work lands on one core) and task offload off (the CPU computes
rem every checksum). Then raises the Winsock default receive buffer from
rem 8 KB, which a game that relies on the default overflows during a short
rem stall, silently dropping the packets that arrive meanwhile.
call :hdr "Windows network stack"
set "STK=0"
for %%T in (%NT_BBR2%) do call :bbr_fix %%T
if defined NT_BBR2 goto :stk_bbr_done
netsh int tcp show supplemental 2>nul | findstr /i /c:"bbr2" >nul
if "%errorlevel%"=="0" call :bbr_fix Internet
:stk_bbr_done
if /i not "%NT_RSS%"=="Disabled" goto :stk_rss_done
netsh int tcp set global rss=enabled >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Receive Side Scaling: was off - turned on, so network work spreads over several cores.) else (echo   [FAIL] Could not turn on Receive Side Scaling.)
set /a STK+=1
:stk_rss_done
set "TOFF="
if /i "%NT_TASKOFFLOAD%"=="Disabled" set "TOFF=1"
call :getdw "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" DisableTaskOffload V1
if "%V1%"=="1" set "TOFF=1"
if not defined TOFF goto :stk_off_done
netsh int ip set global taskoffload=enabled >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DisableTaskOffload /t REG_DWORD /d 0 /f >nul 2>&1
echo   [ OK ] Checksum and segmentation offload: was off - turned back on, so the CPU stops checksumming every packet.
set /a STK+=1
:stk_off_done
if "%STK%"=="0" echo   [ OK ] No harmful leftovers: congestion control, RSS and offloads are at their defaults.
if /i "%SOCKET_BUFFER_MODE%"=="keep" echo   [SKIP] Winsock receive buffer: SOCKET_BUFFER_MODE is set to keep.& exit /b 0
set "AFDK=HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
call :getdw "%AFDK%" DefaultReceiveWindow V1
if not defined V1 set "V1=0"
if %V1% GEQ 65536 echo   [ OK ] Winsock default receive buffer: already %V1% bytes.& exit /b 0
reg add "%AFDK%" /v DefaultReceiveWindow /t REG_DWORD /d 262144 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not set the Winsock default receive buffer.& exit /b 0
echo   [ OK ] Winsock default receive buffer: 8 KB to 256 KB. Games that keep the default no longer overflow it during a brief stall.
exit /b 0

:bbr_fix
rem bbr_fix template - back to the Windows default congestion control
set "CC=CUBIC"
if /i "%~1"=="Compat" set "CC=NewReno"
netsh int tcp set supplemental template=%~1 congestionprovider=%CC% >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] TCP congestion control, %~1 template: BBR2 replaced with %CC%. BBR2 stalls Steam and Battle.net on Windows 11.) else (echo   [FAIL] Could not reset congestion control on the %~1 template.)
set /a STK+=1
exit /b 0


:step_route
rem With Ethernet and Wi-Fi connected at once, Windows picks the route with
rem the lower metric; a fast Wi-Fi 6 or 7 link can win over Ethernet and
rem send game traffic over the slower, noisier link.
call :hdr "Ethernet over Wi-Fi"
if /i "%ROUTE_MODE%"=="keep" echo   [SKIP] ROUTE_MODE is set to keep.& exit /b 0
if not defined NT_PSOK echo   [SKIP] Needs Windows PowerShell.& exit /b 0
call :ps route
exit /b 0


:step_dscp
rem DSCP 46 makes Windows send the packet in a higher Wi-Fi access category
rem (WMM), and routers with smart queue management (CAKE, fq_codel diffserv,
rem most gaming routers) forward it ahead of downloads. Windows ignores QoS
rem policies on PCs outside a domain unless they apply to every network
rem profile and "Do not use NLA" is set.
call :hdr "Priority marking for game traffic"
if /i "%DSCP_MODE%"=="keep" echo   [SKIP] DSCP_MODE is set to keep.& exit /b 0
if not defined NT_PSOK echo   [SKIP] Needs Windows PowerShell.& exit /b 0
call :ps qos
exit /b 0


:step_do
rem Delivery Optimization downloads Windows and Store updates in the
rem background and, unless limited, can upload them to PCs on the internet.
rem Either fills the line and queues game packets behind it (bufferbloat).
call :hdr "Background Windows Update and Store downloads"
if /i "%DO_BACKGROUND_PERCENT%"=="keep" echo   [SKIP] DO_BACKGROUND_PERCENT is set to keep.& exit /b 0
set "DOK=HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
call :getdw "%DOK%" DODownloadMode V1
set "DOP="
if "%V1%"=="0" set "DOP=1"
if "%V1%"=="1" set "DOP=1"
if "%V1%"=="99" set "DOP=1"
if "%V1%"=="100" set "DOP=1"
if defined DOP echo   [ OK ] Peer-to-peer: already limited to your own network, or off.& goto :do_pct
reg add "%DOK%" /v DODownloadMode /t REG_DWORD /d 1 /f >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Peer-to-peer: your own network only. Windows no longer uploads updates to PCs on the internet.) else (echo   [FAIL] Could not set the Delivery Optimization download mode.)
:do_pct
set "PCTN=0"
set /a "PCTN=DO_BACKGROUND_PERCENT" >nul 2>&1
if %PCTN% LSS 1 echo   [SKIP] DO_BACKGROUND_PERCENT must be a number from 1 to 90.& exit /b 0
if %PCTN% GTR 90 set "PCTN=90"
call :getdw "%DOK%" DOPercentageMaxBackgroundBandwidth V2
if not defined V2 set "V2=0"
if not "%V2%"=="0" if %V2% LEQ %PCTN% echo   [ OK ] Background download cap: already %V2%%%.& exit /b 0
reg add "%DOK%" /v DOPercentageMaxBackgroundBandwidth /t REG_DWORD /d %PCTN% /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not set the background download cap.& exit /b 0
echo   [ OK ] Background download cap: %PCTN%%% of measured bandwidth, so an update cannot fill the line mid-game.
exit /b 0


:step_onedrive
rem With automatic upload bandwidth management OneDrive uploads through
rem Windows LEDBAT: it backs off as soon as queueing delay rises, so file
rem sync no longer pushes up ping.
call :hdr "OneDrive uploads"
if /i "%ONEDRIVE_MODE%"=="keep" echo   [SKIP] ONEDRIVE_MODE is set to keep.& exit /b 0
if "%NT_ONEDRIVE%"=="0" echo   [SKIP] OneDrive is not installed.& exit /b 0
set "ODK=HKLM\SOFTWARE\Policies\Microsoft\OneDrive"
call :getdw "%ODK%" AutomaticUploadBandwidthPercentage V1
if defined V1 echo   [SKIP] A fixed OneDrive upload percentage is already set by policy; left alone.& exit /b 0
call :getdw "%UROOT%\SOFTWARE\Policies\Microsoft\OneDrive" UploadBandwidthLimit V1
if defined V1 echo   [SKIP] A fixed OneDrive upload rate is already set by policy; left alone.& exit /b 0
call :getdw "%ODK%" EnableAutomaticUploadBandwidthManagement V1
if "%V1%"=="1" echo   [ OK ] OneDrive already uploads only with spare bandwidth.& exit /b 0
reg add "%ODK%" /v EnableAutomaticUploadBandwidthManagement /t REG_DWORD /d 1 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write the OneDrive policy.& exit /b 0
echo   [ OK ] OneDrive now uploads only with spare bandwidth and backs off when latency rises.
exit /b 0


:step_conflicts
rem Report only: a VPN, a Hyper-V external switch, a bridge, an active
rem hotspot or traffic-shaping software adds a hop or a filter to every
rem packet. They usually have a purpose, so nothing is removed.
call :hdr "Software in the network path"
if not defined NT_PSOK echo   [SKIP] Needs Windows PowerShell.& exit /b 0
call :ps conflicts
exit /b 0


:step_diag
rem 50 pings each to the router and two public anycast servers. Loss or
rem jitter at the router points at Wi-Fi or cabling; loss only beyond it
rem points at the ISP line or route.
call :hdr "Latency, jitter and packet loss"
if /i "%DIAG_MODE%"=="off" echo   [SKIP] DIAG_MODE is set to off.& exit /b 0
if not defined NT_PSOK echo   [SKIP] Needs Windows PowerShell.& exit /b 0
call :ps diag
exit /b 0


rem ==========================================================================
rem  Helpers and exits
rem ==========================================================================

:hdr
rem hdr "title" - prints the numbered step heading
set /a STEPN+=1
echo.
echo  [%STEPN%/%STEPS%] %~1
exit /b 0

:ps
rem ps step - runs one step of the PowerShell section at the end of this file
set "NT_STEP=%~1"
"%PS%" -NoProfile -NonInteractive -Command "%NT_PSRUN%"
if "%errorlevel%"=="3" echo   [FAIL] The PowerShell section of this file is missing or damaged.
exit /b 0

:getdw
rem getdw "key" valueName outVar - reads a REG_DWORD into outVar (decimal),
rem leaves outVar undefined when the value does not exist.
set "%~3="
for /f "tokens=3" %%V in ('reg query "%~1" /v %~2 2^>nul ^| findstr /c:"REG_DWORD"') do set /a "%~3=%%V"
exit /b 0

:elevate
if not defined PS goto :needadmin
echo Requesting administrator rights...
"%PS%" -NoProfile -NonInteractive -Command "try { Start-Process -FilePath $env:NT_SELF -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if not "%errorlevel%"=="0" goto :needadmin
exit /b 0

:needadmin
echo.
echo  Administrator rights are required and were not granted.
echo  Right-click NetTune.bat and choose "Run as administrator".
echo  Nothing was changed.
echo.
pause
exit /b 1

:unsupported
echo.
echo  Supported: Windows 10 version 2004 or newer and Windows 11, client editions.
echo  Detected build "%GT_BUILD%", installation type "%GT_INSTTYPE%". Nothing was changed.
echo.
pause
exit /b 1

:cancelled
echo.
echo  Cancelled. Nothing was changed.
echo.
pause
exit /b 0

rem ==========================================================================
rem  PowerShell section. Everything below runs only through the ps helper.
rem ==========================================================================
#NTPS
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Human-readable output goes to the console through stderr, so that NT_ lines
# on stdout stay machine-readable for the batch code.
function Say([string]$t)  { [Console]::Error.WriteLine($t) }
function Ok([string]$t)   { Say ('  [ OK ] ' + $t) }
function Skip([string]$t) { Say ('  [SKIP] ' + $t) }
function Info([string]$t) { Say ('  [INFO] ' + $t) }
function Warn([string]$t) { Say ('  [WARN] ' + $t) }
function Fail([string]$t) { Say ('  [FAIL] ' + $t) }

# Physical Ethernet (NDIS medium 14) and Wi-Fi (9, or 1 on old drivers).
function Get-PhysicalAdapters {
    @(Get-NetAdapter -Physical | Where-Object { @(1, 9, 14) -contains [int]$_.NdisPhysicalMedium })
}
function Test-Wifi($a) { @(1, 9) -contains [int]$a.NdisPhysicalMedium }

# The IPv4 default route Windows uses: lowest route plus interface metric
# among connected interfaces. -Physical limits the search to Ethernet and
# Wi-Fi, which finds the real link underneath a VPN.
function Get-InternetRoute([switch]$Physical) {
    $allowed = @()
    if ($Physical) { $allowed = @(Get-PhysicalAdapters | ForEach-Object { [int]$_.ifIndex }) }
    $best = $null
    $bestMetric = [int]::MaxValue
    foreach ($r in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore)) {
        if ($Physical -and $allowed -notcontains [int]$r.ifIndex) { continue }
        $ip = @(Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore)[0]
        if (-not $ip -or [string]$ip.ConnectionState -ne 'Connected') { continue }
        $m = [int]$r.RouteMetric + [int]$ip.InterfaceMetric
        if ($m -lt $bestMetric) { $best = $r; $bestMetric = $m }
    }
    $best
}

# The physical adapter that carries internet traffic. Behind a Hyper-V
# external switch that is the adapter the switch is bound to.
function Get-InternetAdapter {
    $r = Get-InternetRoute -Physical
    if ($r) { return (Get-NetAdapter -InterfaceIndex $r.ifIndex) }
    $r = Get-InternetRoute
    if (-not $r) { return $null }
    $a = Get-NetAdapter -InterfaceIndex $r.ifIndex
    if ([string]$a.InterfaceDescription -match 'Hyper-V Virtual Ethernet') {
        $ext = @(Get-NetAdapterBinding -ComponentID 'vms_pp' | Where-Object { $_.Enabled })
        if ($ext.Count -eq 1) {
            $p = Get-NetAdapter -Name $ext[0].Name
            if ($p) { return $p }
        }
    }
    $a
}

# Laptop or desktop, from the chassis type; the battery only decides when the
# chassis type says neither (a UPS can show up as a battery on desktops).
function Test-Laptop {
    $types = @(Get-CimInstance Win32_SystemEnclosure | ForEach-Object { $_.ChassisTypes } | ForEach-Object { [int]$_ })
    foreach ($c in $types) { if (@(8, 9, 10, 11, 14, 30, 31, 32) -contains $c) { return $true } }
    foreach ($c in $types) { if (@(3, 4, 5, 6, 7, 13, 15, 16, 24, 35, 36) -contains $c) { return $false } }
    [bool](Get-CimInstance Win32_Battery)
}

# Signal, band and radio type from netsh. Only language-neutral parts are
# parsed: the percentage, "GHz" and "802.11". Windows 11 24H2 and newer
# answer only while Location services are on.
function Get-WifiInfo {
    $o = @{}
    foreach ($l in @(netsh wlan show interfaces 2>$null)) {
        if (-not $o.Signal -and $l -match '\s(\d{1,3})\s*%') { $o.Signal = [int]$Matches[1] }
        if (-not $o.Radio -and $l -match '(802\.11[a-z]+)') { $o.Radio = $Matches[1] }
        if (-not $o.Band -and $l -match ':\s*(\d(?:\.\d+)?)\s*GHz') { $o.Band = $Matches[1] + ' GHz' }
    }
    $o
}

function Test-OneDrive {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )
    foreach ($u in @(Get-ChildItem -Path (Join-Path $env:SystemDrive 'Users') -Directory)) {
        $paths += (Join-Path $u.FullName 'AppData\Local\Microsoft\OneDrive\OneDrive.exe')
    }
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } }
    $false
}

function Get-SignedInSid {
    $s = (Get-Process -Id $PID).SessionId
    $p = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object { $_.SessionId -eq $s })[0]
    if ($p) { (Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid).Sid }
}

# ---- Advanced-property helpers ---------------------------------------------
# Values are always written as registry values chosen from the driver's own
# list, so the result does not depend on the display language.
function Find-Prop([string]$keyword) {
    $script:props | Where-Object { $_.RegistryKeyword -eq $keyword } | Select-Object -First 1
}
function Find-PropsByName([string]$pattern) {
    @($script:props | Where-Object { $_.DisplayName -and $_.DisplayName -match $pattern })
}
function Show-Value($p, [string]$regValue) {
    $vr = @($p.ValidRegistryValues)
    $vd = @($p.ValidDisplayValues)
    for ($i = 0; $i -lt $vr.Count; $i++) {
        if ([string]$vr[$i] -eq $regValue -and $i -lt $vd.Count) { return [string]$vd[$i] }
    }
    $regValue
}
# Registry value of the first display value that matches one of $patterns.
function Pick-Value($p, [string[]]$patterns, [string]$exclude) {
    $vr = @($p.ValidRegistryValues)
    $vd = @($p.ValidDisplayValues)
    foreach ($pat in $patterns) {
        for ($i = 0; $i -lt $vd.Count -and $i -lt $vr.Count; $i++) {
            $d = [string]$vd[$i]
            if ($d -match $pat -and (-not $exclude -or $d -notmatch $exclude)) { return [string]$vr[$i] }
        }
    }
    $null
}
function Set-Prop($p, [string]$value, [string]$label) {
    $cur = [string](@($p.RegistryValue)[0])
    if ($cur -eq $value) { return }
    $before = Show-Value $p $cur
    $after = Show-Value $p $value
    try {
        Set-NetAdapterAdvancedProperty -Name $script:adName -RegistryKeyword $p.RegistryKeyword -RegistryValue $value -NoRestart -ErrorAction Stop
        Ok ($label + ': ' + $before + ' -> ' + $after)
        $script:changed = $true
    } catch {
        Fail ($label + ': could not change it (' + $_.Exception.Message + ')')
    }
}
# Every property whose name matches: set to the first value matching
# $valuePatterns, unless the current value already matches $keep.
function Set-PropByName([string]$namePattern, [string[]]$valuePatterns, [string]$label, [string]$exclude, [string]$keep) {
    foreach ($p in (Find-PropsByName $namePattern)) {
        if ($script:handled -contains $p.RegistryKeyword) { continue }
        if ($exclude -and [string]$p.DisplayName -match $exclude) { continue }
        $script:handled += $p.RegistryKeyword
        if ($keep -and [string]$p.DisplayValue -match $keep) { continue }
        $v = Pick-Value $p $valuePatterns
        if ($null -ne $v) { Set-Prop $p $v ($label + ' (' + $p.DisplayName + ')') }
    }
}

function Tune-Ethernet($a) {
    # Energy-Efficient Ethernet, standard keyword: 0 = off.
    $p = Find-Prop '*EEE'
    if ($p) { $script:handled += '*EEE'; Set-Prop $p '0' 'Energy-Efficient Ethernet' }
    # Vendor power-saving features that drop or slow the link, or delay wake-up.
    Set-PropByName 'Energy.?Efficient|Advanced EEE|Green Ethernet|Power Saving Mode|Ultra Low Power|System Idle Power Saver|Idle Power Sav|Gigabit Lite|Auto Disable Gigabit|Battery Saver' @('^(Disabled?|Off)$', '^(Disable|Off)') 'Power saving' '' '^(Disable|Off)'
    # USB adapters: no selective suspend between packets.
    $p = Find-Prop '*SelectiveSuspend'
    if ($p) { Set-Prop $p '0' 'USB selective suspend' }
    # Receive buffers: raised toward 2048, so a burst that arrives while the
    # CPU is busy is not dropped. Never lowered.
    $p = Find-Prop '*ReceiveBuffers'
    if ($p) {
        $cur = 0
        [void][int]::TryParse([string](@($p.RegistryValue)[0]), [ref]$cur)
        $target = 0
        $valid = @(@($p.ValidRegistryValues) | ForEach-Object { $n = 0; if ([int]::TryParse([string]$_, [ref]$n)) { $n } })
        if ($valid.Count) {
            foreach ($n in $valid) { if ($n -le 2048 -and $n -gt $target) { $target = $n } }
        } elseif ([int]$p.NumericParameterMaxValue -gt 0) {
            $max = [int]$p.NumericParameterMaxValue
            $min = [int]$p.NumericParameterMinValue
            $step = [int]$p.NumericParameterStepValue
            $target = [Math]::Min($max, 2048)
            if ($step -gt 1) { $target = $min + [int][Math]::Floor(($target - $min) / $step) * $step }
        }
        if ($target -gt $cur) { Set-Prop $p ([string]$target) 'Receive buffers' }
    }
    # Checksum offloads: back on (Rx and Tx) where an optimizer turned them off.
    foreach ($k in @('*IPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv6', '*UDPChecksumOffloadIPv4', '*UDPChecksumOffloadIPv6')) {
        $p = Find-Prop $k
        if ($p -and [string](@($p.RegistryValue)[0]) -eq '0' -and @($p.ValidRegistryValues) -contains '3') { Set-Prop $p '3' ([string]$p.DisplayName) }
    }
    # Intel interrupt moderation rate: High and Extreme hold packets longest;
    # Medium is the measured best for games. Adaptive, the default, is kept.
    $im = Find-Prop '*InterruptModeration'
    $itr = Find-Prop 'ITR'
    if ($itr -and -not ($im -and [string](@($im.RegistryValue)[0]) -eq '0') -and [string]$itr.DisplayValue -match '^(Extreme|High)$') {
        $v = Pick-Value $itr @('^Medium$')
        if ($null -ne $v) { Set-Prop $itr $v 'Interrupt moderation rate' }
    }
    # Half duplex collides and loses packets: back to auto-negotiation.
    $sd = Find-Prop '*SpeedDuplex'
    if ($sd -and @('1', '3', '5') -contains [string](@($sd.RegistryValue)[0])) {
        Set-Prop $sd '0' 'Speed and duplex'
        Warn 'The adapter was forced to half duplex, which causes collisions and packet loss.'
    }
    $j = Find-Prop '*JumboPacket'
    if ($j) {
        $jv = 0
        [void][int]::TryParse([string](@($j.RegistryValue)[0]), [ref]$jv)
        if ($jv -gt 1514) { Info ('Jumbo frames are on (' + $j.DisplayValue + '). Keep them only if every device on your network supports them.') }
    }
    # Receive Side Scaling spreads receive work over several cores.
    $rss = Get-NetAdapterRss -Name $a.Name
    if ($rss -and $rss.Enabled -eq $false) {
        Enable-NetAdapterRss -Name $a.Name -NoRestart
        Ok 'Receive Side Scaling: was off - turned on'
        $script:changed = $true
    }
}

function Tune-Wifi($a, [bool]$laptop) {
    # Roaming: scanning for a "better" access point interrupts traffic.
    # Laptops keep some roaming so they can still move between rooms.
    if ($laptop) {
        Set-PropByName 'Roam' @('Medium.?low', 'Lowest', '^(\d\.\s*)?Low', 'Conservative') 'Roaming' '' 'Low|Disable|Off|Conservative'
    } else {
        Set-PropByName 'Roam' @('Lowest', '^(\d\.\s*)?Low', 'Conservative') 'Roaming' '' 'Low|Disable|Off|Conservative'
    }
    # Power save modes that make the radio sleep between packets.
    Set-PropByName 'MIMO Power Save' @('No SMPS') 'MIMO power save' '' 'No SMPS'
    Set-PropByName 'U-?APSD' @('^(Disable|Off)') 'U-APSD power save' '' '^(Disable|Off)'
    Set-PropByName 'Power ?Sav|Power Management|PS Mode' @('^(Disable|Off)', 'Max(imum)?.?Perf', '^CAM') 'Power saving' 'MIMO|Transmit' '^(Disable|Off)|Max(imum)?.?Perf|^CAM'
    # Prefer 5 GHz: far less crowded than 2.4 GHz. A 5 or 6 GHz preference is kept.
    foreach ($p in (Find-PropsByName 'Preferred Band|Band Preference|Prefer.*Band')) {
        $script:handled += $p.RegistryKeyword
        if ([string]$p.DisplayValue -match '5|6') { continue }
        $v = Pick-Value $p @('5\s?GHz', '5G') '6'
        if ($null -ne $v) { Set-Prop $p $v 'Preferred band' }
    }
    Set-PropByName 'Transmit Power|Tx Power' @('Highest', '^100') 'Transmit power' '' 'Highest|^100'
    # Intel: block background scans. The setting is hidden in current drivers
    # but still read from the adapter's registry key: 2 = always, 1 = while
    # the signal is good (kept for laptops, which need to roam).
    if ([string]$a.DriverProvider -match 'Intel' -or [string]$a.InterfaceDescription -match 'Intel') {
        $want = if ($laptop) { '1' } else { '2' }
        $label = if ($laptop) { 'blocked while the signal is good' } else { 'always blocked' }
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
        $key = $null
        foreach ($k in @(Get-ChildItem -Path $base)) {
            $id = (Get-ItemProperty -LiteralPath $k.PSPath -Name NetCfgInstanceId).NetCfgInstanceId
            if ($id -and [string]$id -eq [string]$a.InterfaceGuid) { $key = $k.PSPath; break }
        }
        if (-not $key) {
            Info 'Background scan blocking: the adapter registry key was not found.'
        } elseif ([string](Get-ItemProperty -LiteralPath $key -Name BgScanGlobalBlocking).BgScanGlobalBlocking -eq $want) {
            Ok ('Background scans: already ' + $label)
        } else {
            try {
                Set-ItemProperty -LiteralPath $key -Name BgScanGlobalBlocking -Value $want -Type String -ErrorAction Stop
                Ok ('Background scans: ' + $label + ' - stops the scan spikes')
                $script:changed = $true
            } catch { Fail 'Background scan blocking: could not write the setting.' }
        }
    }
}

function Wait-Internet([int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Get-InternetRoute) { return $true }
        Start-Sleep -Seconds 1
    }
    [bool](Get-InternetRoute)
}

# After a restart: wait until the adapters that were up are up again and an
# internet route is back.
function Wait-Adapters([string[]]$names, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        Start-Sleep -Seconds 1
        $down = @($names | Where-Object { [string](Get-NetAdapter -Name $_).Status -ne 'Up' })
        if (-not $down.Count -and (Get-InternetRoute)) { return $true }
    }
    $false
}

# Packet statistics for one target. RoundtripTime has 1 ms resolution.
function Measure-Target([string]$name, [string]$address, [int]$count) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $count; $i++) {
        $reply = $null
        try { $reply = $ping.Send($address, 1000) } catch { }
        if ($reply -and [string]$reply.Status -eq 'Success') { $rtts.Add([double]$reply.RoundtripTime) } else { $lost++ }
        Start-Sleep -Milliseconds 100
    }
    $r = [pscustomobject]@{ Name = $name; Loss = 100.0 * $lost / $count; Avg = $null; Jitter = $null; Worst = $null }
    if ($rtts.Count) {
        $r.Avg = ($rtts | Measure-Object -Average).Average
        $r.Worst = ($rtts | Measure-Object -Maximum).Maximum
        $d = 0.0
        for ($i = 1; $i -lt $rtts.Count; $i++) { $d += [Math]::Abs($rtts[$i] - $rtts[$i - 1]) }
        $r.Jitter = if ($rtts.Count -gt 1) { $d / ($rtts.Count - 1) } else { 0.0 }
    }
    $line = '  {0,-26} loss {1,5:0.0}%' -f $r.Name, $r.Loss
    if ($null -ne $r.Avg) { $line += ('   avg {0,5:0.0} ms   jitter {1,4:0.0} ms   worst {2,4:0} ms' -f $r.Avg, $r.Jitter, $r.Worst) }
    Say $line
    $r
}

switch ($env:NT_STEP) {

'detect' {
    $ads = Get-PhysicalAdapters
    $inet = Get-InternetAdapter
    $type = 'none'
    if ($inet) {
        if ([int]$inet.NdisPhysicalMedium -eq 14) { $type = 'Ethernet' }
        elseif (Test-Wifi $inet) { $type = 'Wi-Fi' }
        else { $type = 'other' }
        Say ('  Connection    ' + $type + ': ' + $inet.Name + ' - ' + $inet.InterfaceDescription + ', ' + $inet.LinkSpeed)
    } else {
        Say '  Connection    no active internet connection found'
    }
    $eth = $null
    if ($type -eq 'Ethernet') { $eth = $inet }
    if ($type -eq 'Wi-Fi') {
        $w = Get-WifiInfo
        $parts = @()
        if ($w.Signal) { $parts += ('signal ' + $w.Signal + '%') }
        if ($w.Band) { $parts += $w.Band }
        if ($w.Radio) { $parts += $w.Radio }
        if ($parts.Count) { Say ('  Wi-Fi         ' + ($parts -join ', ')) }
        # Ethernet connected at the same time takes over in step 4, so the
        # Wi-Fi-only changes are not needed.
        if ([string]$env:ROUTE_MODE -ne 'keep') {
            foreach ($e in @($ads | Where-Object { [int]$_.NdisPhysicalMedium -eq 14 -and [string]$_.Status -eq 'Up' })) {
                if (@(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore | Where-Object { [int]$_.ifIndex -eq [int]$e.ifIndex }).Count) {
                    Info ('Ethernet (' + $e.Name + ') is connected too. Step 4 makes Windows send traffic over it instead of Wi-Fi.')
                    $type = 'Ethernet'
                    $eth = $e
                    break
                }
            }
        }
        if ($type -eq 'Wi-Fi') {
            if ($w.Signal -and $w.Signal -lt 60) { Warn 'Weak Wi-Fi signal: expect retransmissions and packet loss whatever the settings.' }
            if ($w.Band -eq '2.4 GHz') { Info 'Connected on 2.4 GHz. If the router has a 5 GHz network, use it: far less interference.' }
        }
    }
    if ($eth) {
        if ($eth.FullDuplex -eq $false) { Warn 'The Ethernet link runs at half duplex, which loses packets. Check the cable and the router or switch port.' }
        if ($eth.Speed -and [double]$eth.Speed -le 100000000) { Warn ('The Ethernet link runs at only ' + $eth.LinkSpeed + '. A damaged or old cable, or a 100 Mbps port, is the usual cause.') }
        # Damaged frames since the adapter started point at the cable or port.
        $st = Get-NetAdapterStatistics -Name $eth.Name
        if ($st) {
            $rx = [double]$st.ReceivedUnicastPackets + [double]$st.ReceivedMulticastPackets + [double]$st.ReceivedBroadcastPackets
            $err = [double]$st.ReceivedPacketErrors
            if ($rx -ge 10000 -and $err -ge 10 -and $err / $rx -ge 0.0001) {
                Warn ($eth.Name + ': ' + [string]$err + ' damaged packets received since the adapter started (' + ('{0:0.00}' -f (100 * $err / $rx)) + '%). Check or replace the cable.')
            }
        }
    }
    foreach ($a in $ads) {
        if ($inet -and $a.ifIndex -eq $inet.ifIndex) { continue }
        Say ('  Also present  ' + $a.Name + ' - ' + $a.InterfaceDescription + ', ' + $a.Status)
    }
    $laptop = Test-Laptop
    Say ('  PC            ' + $(if ($laptop) { 'laptop' } else { 'desktop' }))
    $intelWifi = $inet -and (Test-Wifi $inet) -and ([string]$inet.DriverProvider -match 'Intel' -or [string]$inet.InterfaceDescription -match 'Intel')
    $off = Get-NetOffloadGlobalSetting
    $bbr = @(Get-NetTCPSetting | Where-Object { [string]$_.CongestionProvider -match 'BBR' } | ForEach-Object { [string]$_.SettingName } | Sort-Object -Unique)
    'NT_INET=' + $type
    'NT_INTELWIFI=' + [int][bool]$intelWifi
    'NT_ONEDRIVE=' + [int](Test-OneDrive)
    if ($off) { 'NT_RSS=' + $off.ReceiveSideScaling; 'NT_TASKOFFLOAD=' + $off.TaskOffload }
    if ($bbr.Count) { 'NT_BBR2=' + ($bbr -join ' ') }
    $sid = Get-SignedInSid
    if ($sid) { 'NT_USERSID=' + $sid }
    'NT_PSOK=1'
}

'adapters' {
    $laptop = Test-Laptop
    $ads = Get-PhysicalAdapters
    if (-not $ads.Count) { Skip 'No physical Ethernet or Wi-Fi adapter found.'; return }
    $restart = @()
    foreach ($a in $ads) {
        $wifi = Test-Wifi $a
        Say ('  ' + $(if ($wifi) { 'Wi-Fi' } else { 'Ethernet' }) + ': ' + $a.Name + ' - ' + $a.InterfaceDescription)
        $script:adName = $a.Name
        $script:props = @(Get-NetAdapterAdvancedProperty -Name $a.Name)
        $script:changed = $false
        $script:handled = @()
        if ($wifi) { Tune-Wifi $a $laptop } else { Tune-Ethernet $a }
        if (-not $script:changed) { Ok 'Nothing to change.' }
        elseif ([string]$a.Status -eq 'Disabled') { Info 'The adapter is disabled, so it is not restarted; the changes apply when it is enabled.' }
        else { $restart += $a }
    }
    if ($restart.Count) {
        $wasUp = @($restart | Where-Object { [string]$_.Status -eq 'Up' } | ForEach-Object { [string]$_.Name })
        $hadNet = [bool](Get-InternetRoute)
        Info ('Restarting ' + (($restart | ForEach-Object { $_.Name }) -join ', ') + ' to apply the changes...')
        foreach ($a in $restart) { Restart-NetAdapter -Name $a.Name -Confirm:$false }
        if ($wasUp.Count -or $hadNet) {
            if (Wait-Adapters $wasUp 45) { Ok 'Connection is back.' } else { Warn 'The connection is not back yet; Wi-Fi in particular can take a little longer.' }
        }
    }
}

'route' {
    $up = @(Get-PhysicalAdapters | Where-Object { [string]$_.Status -eq 'Up' })
    $eth = @($up | Where-Object { [int]$_.NdisPhysicalMedium -eq 14 })
    $wifi = @($up | Where-Object { Test-Wifi $_ })
    if (-not $eth.Count -or -not $wifi.Count) { Ok 'Only one kind of connection is active, so there is nothing to choose.'; return }
    $done = 0
    foreach ($fam in @('IPv4', 'IPv6')) {
        $prefix = if ($fam -eq 'IPv4') { '0.0.0.0/0' } else { '::/0' }
        $routes = @(Get-NetRoute -DestinationPrefix $prefix -AddressFamily $fam -PolicyStore ActiveStore)
        $eff = @{}
        foreach ($ad in ($eth + $wifi)) {
            $rt = $routes | Where-Object { $_.ifIndex -eq $ad.ifIndex } | Sort-Object RouteMetric | Select-Object -First 1
            $ip = @(Get-NetIPInterface -InterfaceIndex $ad.ifIndex -AddressFamily $fam -PolicyStore ActiveStore)[0]
            if ($rt -and $ip) { $eff[[int]$ad.ifIndex] = [int]$rt.RouteMetric + [int]$ip.InterfaceMetric }
        }
        $ethMetrics = @($eth | ForEach-Object { $eff[[int]$_.ifIndex] } | Where-Object { $null -ne $_ })
        if (-not $ethMetrics.Count) { continue }
        $best = ($ethMetrics | Measure-Object -Minimum).Minimum
        foreach ($w in $wifi) {
            $we = $eff[[int]$w.ifIndex]
            if ($null -eq $we -or $we -gt $best) { continue }
            $ip = @(Get-NetIPInterface -InterfaceIndex $w.ifIndex -AddressFamily $fam -PolicyStore ActiveStore)[0]
            $new = [int]$ip.InterfaceMetric + ($best - $we) + 25
            try {
                Set-NetIPInterface -InterfaceIndex $w.ifIndex -AddressFamily $fam -InterfaceMetric $new -ErrorAction Stop
                Ok ($fam + ': ' + $w.Name + ' metric ' + $ip.InterfaceMetric + ' -> ' + $new + ', so traffic uses Ethernet.')
                $done++
            } catch { Fail ($fam + ': could not change the metric of ' + $w.Name + '.') }
        }
    }
    if (-not $done) { Ok 'Ethernet is already preferred over Wi-Fi.' }
}

'qos' {
    # Windows applies QoS policies on PCs outside a domain only with this
    # value; the policies below also apply to every network profile.
    # Keys are created only when missing, so nothing already there is lost.
    $nla = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\QoS'
    if (-not (Test-Path -LiteralPath $nla)) { New-Item -Path $nla -Force | Out-Null }
    Set-ItemProperty -LiteralPath $nla -Name 'Do not use NLA' -Value '1' -Type String
    # Windows sets the DSCP value through the QoS Packet Scheduler (pacer.sys).
    foreach ($a in (Get-PhysicalAdapters)) {
        $b = Get-NetAdapterBinding -Name $a.Name -ComponentID 'ms_pacer'
        if ($b -and -not $b.Enabled) {
            Enable-NetAdapterBinding -Name $a.Name -ComponentID 'ms_pacer'
            Ok ('QoS Packet Scheduler on ' + $a.Name + ': was off - turned back on, marking goes through it.')
        }
    }
    $apps = @()
    foreach ($x in ([string]$env:QOS_UDP_APPS).Split(';')) { if ($x.Trim()) { $apps += [pscustomobject]@{ App = $x.Trim(); Proto = 'UDP' } } }
    foreach ($x in ([string]$env:QOS_ALL_APPS).Split(';')) { if ($x.Trim()) { $apps += [pscustomobject]@{ App = $x.Trim(); Proto = 'Both' } } }
    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS'
    $cmdlet = [bool](Get-Command New-NetQosPolicy)
    # Rewrite NetTune's own policies, so programs removed from the lists do
    # not linger. Policies with other names are never touched.
    if ($cmdlet) {
        foreach ($q in @(Get-NetQosPolicy -PolicyStore localhost | Where-Object { [string]$_.Name -like 'NetTune *' })) {
            Remove-NetQosPolicy -Name $q.Name -PolicyStore localhost -Confirm:$false
        }
    }
    if (Test-Path -LiteralPath $base) {
        Get-ChildItem -LiteralPath $base | Where-Object { $_.PSChildName -like 'NetTune *' } | Remove-Item -Recurse -Force
    }
    if (-not $apps.Count) { Skip 'QOS_UDP_APPS and QOS_ALL_APPS are empty.'; return }
    $n = 0
    $failed = @()
    foreach ($e in $apps) {
        $name = 'NetTune ' + $e.App
        $done = $false
        if ($cmdlet) {
            try {
                New-NetQosPolicy -Name $name -AppPathNameMatchCondition $e.App -IPProtocolMatchCondition $e.Proto -DSCPAction 46 -NetworkProfile All -PolicyStore localhost -ErrorAction Stop | Out-Null
                $done = $true
            } catch { }
        }
        if (-not $done) {
            # The same policy, written in the format Group Policy uses.
            try {
                if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force -ErrorAction Stop | Out-Null }
                $key = $base + '\' + $name
                if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
                $values = [ordered]@{
                    'Version' = '1.0'; 'Application Name' = $e.App; 'Protocol' = $(if ($e.Proto -eq 'UDP') { 'UDP' } else { '*' })
                    'Local Port' = '*'; 'Local IP' = '*'; 'Local IP Prefix Length' = '*'
                    'Remote Port' = '*'; 'Remote IP' = '*'; 'Remote IP Prefix Length' = '*'
                    'DSCP Value' = '46'; 'Throttle Rate' = '-1'
                }
                foreach ($kv in $values.GetEnumerator()) {
                    New-ItemProperty -LiteralPath $key -Name $kv.Key -Value $kv.Value -PropertyType String -Force -ErrorAction Stop | Out-Null
                }
                $done = $true
            } catch { }
        }
        if ($done) { $n++ } else { $failed += $e.App }
    }
    if ($n) {
        Ok ([string]$n + ' games marked DSCP 46 (Expedited Forwarding): UDP for most, UDP and TCP for games that use TCP.')
        Ok 'Marking applies on every network type, also on PCs outside a domain.'
        Info 'Helps on Wi-Fi and with routers that honour DSCP; elsewhere the mark is simply ignored.'
    }
    if ($failed.Count) { Fail ('Could not create a policy for: ' + ($failed -join ', ')) }
}

'conflicts' {
    $n = 0
    $physIdx = @(Get-PhysicalAdapters | ForEach-Object { [int]$_.ifIndex })
    # The interface Windows really uses to reach the internet, VPN routes included.
    $via = $null
    $fr = @(Find-NetRoute -RemoteIPAddress '1.1.1.1')
    if ($fr.Count) { $via = Get-NetAdapter -InterfaceIndex ([int]$fr[$fr.Count - 1].InterfaceIndex) }
    if (-not $via) {
        $r = Get-InternetRoute
        if ($r) { $via = Get-NetAdapter -InterfaceIndex $r.ifIndex }
    }
    if ($via -and $physIdx -notcontains [int]$via.ifIndex -and [string]$via.InterfaceDescription -notmatch 'Hyper-V Virtual Ethernet') {
        Warn ('Internet traffic goes through ' + $via.InterfaceDescription + ' (' + $via.Name + '). A VPN adds a detour to every packet; disconnect it while gaming unless you need it.')
        $n++
    }
    $vs = @(Get-NetAdapterBinding -ComponentID 'vms_pp' | Where-Object { $_.Enabled })
    if ($vs.Count) {
        Warn ('A Hyper-V external virtual switch sits on ' + (($vs | ForEach-Object { $_.Name }) -join ', ') + ': every packet passes through it. Remove the switch if nothing needs it.')
        $n++
    }
    if (@(Get-NetAdapter | Where-Object { [string]$_.InterfaceDescription -match 'MAC Bridge Miniport' }).Count) {
        Warn 'A network bridge is configured: it adds a software hop. Remove it unless another device depends on it.'
        $n++
    }
    if (@(Get-NetAdapter | Where-Object { [string]$_.InterfaceDescription -match 'Wi-Fi Direct Virtual' -and [string]$_.Status -eq 'Up' }).Count) {
        Warn 'Mobile hotspot or Wi-Fi Direct is active: the Wi-Fi radio splits its time between two networks.'
        $n++
    }
    foreach ($s in @(Get-Service | Where-Object { [string]$_.Status -eq 'Running' -and [string]$_.DisplayName -match 'Killer|SmartByte|cFos|GameFirst|NetLimiter' })) {
        Info ($s.DisplayName + ' is running. It reshapes traffic; if you get lag or loss, test once with it stopped.')
        $n++
    }
    $inet = Get-InternetAdapter
    if ($inet) {
        foreach ($b in @(Get-NetAdapterBinding -Name $inet.Name | Where-Object { $_.Enabled -and [string]$_.ComponentID -notmatch '^(ms_|vms_)' })) {
            Info ('Third-party network filter on ' + $inet.Name + ': ' + $b.DisplayName + '. It handles every packet.')
            $n++
        }
        $ipif = @(Get-NetIPInterface -InterfaceIndex $inet.ifIndex -AddressFamily IPv4 -PolicyStore ActiveStore)[0]
        if ($ipif -and [int]$ipif.NlMtu -gt 0 -and [int]$ipif.NlMtu -lt 1400) {
            Info ('The MTU of ' + $inet.Name + ' is ' + $ipif.NlMtu + ' bytes. 1500 is right for Ethernet and Wi-Fi; a lower value can split large game packets in two.')
            $n++
        }
    }
    if (-not $n) { Ok 'No VPN, virtual switch, bridge, hotspot or traffic shaper in the path.' }
}

'diag' {
    if (-not (Wait-Internet 15)) { Fail 'No internet connection, so there is nothing to test.'; return }
    if (@(Get-DeliveryOptimizationStatus | Where-Object { [string]$_.Status -match 'Download' }).Count) {
        Info 'Windows Update or the Store is downloading right now, which can raise the numbers below.'
    }
    $route = Get-InternetRoute -Physical
    if (-not $route) { $route = Get-InternetRoute }
    $gw = [string]$route.NextHop
    $router = $null
    if ($gw -and $gw -ne '0.0.0.0') { $router = Measure-Target ('Router ' + $gw) $gw 50 }
    $net = @(
        (Measure-Target 'Cloudflare 1.1.1.1' '1.1.1.1' 50),
        (Measure-Target 'Google 8.8.8.8' '8.8.8.8' 50)
    )
    Say ''
    if ($router -and $router.Loss -ge 100) {
        Info 'The router does not answer pings, so the local link is not measured on its own.'
        $router = $null
    }
    $answered = @($net | Where-Object { $_.Loss -lt 100 })
    if (-not $answered.Count) {
        Warn 'Neither public server answered. Pings are probably blocked on this network, so this test says nothing about games.'
    } else {
        $netLoss = ($answered | Measure-Object -Property Loss -Maximum).Maximum
        $netJitter = ($answered | Measure-Object -Property Jitter -Maximum).Maximum
        if ($router -and ($router.Loss -ge 2 -or $router.Jitter -gt 5)) {
            Warn 'Loss or jitter already between this PC and the router: Wi-Fi signal or interference, the cable, or the router itself.'
            Info 'Ethernet, a 5 GHz channel, or moving closer to the router fixes most of this.'
        } elseif ($netLoss -ge 1) {
            Warn 'The local link is clean, but packets are lost beyond the router: the modem, the ISP line or its routing. Restart the modem; if it stays, contact the ISP.'
        } elseif ($netJitter -gt 8) {
            Warn 'Jitter beyond the router. If it rises while something downloads, that is bufferbloat: turn on SQM (CAKE or fq_codel) in the router.'
        } else {
            Ok 'No packet loss and low jitter on the path.'
        }
    }
    Info 'Routers answer pings at low priority, so an odd lost router ping is normal.'
    Info 'Bufferbloat only shows under load: test at waveform.com/tools/bufferbloat. Below grade A, turn on SQM in the router.'
}

default { Fail ('Unknown step: ' + $env:NT_STEP) }
}
#NTPS
