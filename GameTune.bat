@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================================
rem  GameTune.bat - evidence-based Windows tuning for in-game frame delivery
rem
rem  Goal: better 0.1 / 1 percent lows, average FPS and frametime consistency
rem  on Windows 10 (version 2004 or newer) and Windows 11.
rem
rem  Only changes that current community benchmarking shows to have a real,
rem  measurable effect are applied. Hardware, installed components and the
rem  Windows build are detected at runtime and each step adapts to them.
rem
rem  Writes no logs, exports, backups or restore points. Does not touch
rem  network settings, power plans / powercfg, temp files or disk cleanup.
rem  README.md explains every change, the evidence behind it and how to
rem  undo it.
rem ==========================================================================

rem ---- Options -------------------------------------------------------------
rem  Change a value below to change what the script does.
rem
rem  Applied by default:
rem  VBS_MODE              auto, disable or keep
rem      Virtualization-Based Security and Memory Integrity. auto turns them
rem      off unless FACEIT or Riot Vanguard is installed, because both can
rem      refuse to run without them.
rem  DIAGTRACK_MODE        auto, disable or keep
rem      The Connected User Experiences and Telemetry service. auto turns it
rem      off unless Xbox Gaming Services is installed, because Xbox
rem      achievements in PC games are reported through it.
rem  HAGS_MODE             on or keep
rem      Hardware-accelerated GPU scheduling.
rem  AUTOHDR_MODE          off or keep
rem      Auto HDR costs 2 to 3 percent of GPU time while it is active.
rem  POWERTHROTTLING_MODE  auto, off or keep
rem      Power throttling of background processes. auto turns it off on
rem      desktops with hybrid P-core and E-core CPUs, and keeps it on laptops.
rem
rem  Off by default, because they cost security or break something:
rem  CPU_MITIGATIONS_MODE        keep or off
rem      Spectre v2 and Meltdown mitigations. Gains are mainly on Intel CPUs
rem      from before 2019.
rem  DEFENDER_EXCLUSIONS_MODE    keep or add
rem      Excludes game libraries and shader caches from real-time scanning.
rem  STORE_APPS_BACKGROUND_MODE  keep or off
rem      Stops Microsoft Store apps from running in the background.
rem  HYPERVISOR_MODE             keep or off
rem      Stops the hypervisor from loading. WSL2, Hyper-V, Windows Sandbox
rem      and Docker stop working until it is set back.
rem --------------------------------------------------------------------------
set "VBS_MODE=auto"
set "DIAGTRACK_MODE=auto"
set "HAGS_MODE=on"
set "AUTOHDR_MODE=off"
set "POWERTHROTTLING_MODE=auto"
set "CPU_MITIGATIONS_MODE=keep"
set "DEFENDER_EXCLUSIONS_MODE=keep"
set "STORE_APPS_BACKGROUND_MODE=keep"
set "HYPERVISOR_MODE=keep"

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
set "SVC=HKLM\SYSTEM\CurrentControlSet\Services"
set "DG=HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard"
set "DGP=HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"

rem ---- Administrator rights (self-elevates) --------------------------------
rem Exit codes are compared with "0" rather than "if errorlevel 1" throughout,
rem because some tools (fltmc among them) report errors as negative numbers.
fltmc >nul 2>&1
if not "%errorlevel%"=="0" goto :elevate

:main
title GameTune
echo.
echo  ==============================================================
echo   GameTune - Windows tuning for frametimes and 0.1 / 1%% lows
echo  ==============================================================
echo.
echo  Detecting system...

rem ---- Windows version -----------------------------------------------------
set "CV=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
set "GT_BUILD="
set "GT_UBR=0"
set "GT_VER="
set "GT_EDITION="
set "GT_INSTTYPE="
for /f "tokens=3" %%A in ('reg query "%CV%" /v CurrentBuildNumber 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_BUILD=%%A"
for /f "tokens=3" %%A in ('reg query "%CV%" /v UBR 2^>nul ^| findstr /c:"REG_DWORD"') do set /a "GT_UBR=%%A"
for /f "tokens=2,*" %%A in ('reg query "%CV%" /v DisplayVersion 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_VER=%%B"
for /f "tokens=2,*" %%A in ('reg query "%CV%" /v EditionID 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_EDITION=%%B"
for /f "tokens=2,*" %%A in ('reg query "%CV%" /v InstallationType 2^>nul ^| findstr /c:"REG_SZ"') do set "GT_INSTTYPE=%%B"
if not defined GT_BUILD goto :unsupported
if %GT_BUILD% LSS 19041 goto :unsupported
if /i "%GT_INSTTYPE%"=="Server" goto :unsupported
set "GT_OS=Windows 10"
if %GT_BUILD% GEQ 22000 set "GT_OS=Windows 11"

rem ---- Hardware, VBS state and the signed-in user (one PowerShell call) ----
set "GT_RAMGB=0"
set "GT_CPU=unknown"
set "GT_CORES=0"
set "GT_THREADS=0"
set "GT_HYBRID=?"
set "GT_BATTERY=?"
set "GT_GPU=unknown"
set "GT_VBS=?"
set "GT_VBSRUN=,"
set "GT_USERSID="
set "GT_GAMEBAR=?"
if not defined PS goto :detect_done
set "Q=$ErrorActionPreference='SilentlyContinue';"
set "Q=%Q%$cs=Get-CimInstance Win32_ComputerSystem;"
set "Q=%Q%$m=(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum;"
set "Q=%Q%if(-not $m){$m=$cs.TotalPhysicalMemory};"
set "Q=%Q%'GT_RAMGB='+[int][math]::Round($m/1GB);"
rem $x strips characters that cmd treats specially from hardware names: double
rem quote, percent, exclamation mark, caret, ampersand, pipe and angle brackets.
rem The first four are built from char codes, as they cannot appear literally
rem inside this command line.
set "Q=%Q%$x={param($t)(([string]$t -replace ('['+[char]34+[char]37+[char]33+[char]94+'&|<>]'),'') -replace '\s+',' ').Trim()};"
set "Q=%Q%$c=@(Get-CimInstance Win32_Processor)[0];"
set "Q=%Q%$n=& $x $c.Name;if($n){'GT_CPU='+$n};"
set "Q=%Q%'GT_CORES='+[int]$c.NumberOfCores;"
set "Q=%Q%'GT_THREADS='+[int]$c.NumberOfLogicalProcessors;"
rem Hybrid CPUs (separate performance and efficiency cores): Intel 12th to
rem 14th gen, Core Ultra and Core 3/5/7 series 1 and 2, and Ryzen AI 5/7/9
rem with Zen 5c cores.
set "Q=%Q%'GT_HYBRID='+[int]([string]$c.Name -match '1[234]th Gen|Core\(TM\) Ultra|Core Ultra|Core\(TM\) [3579] [12][0-9]{2}|Ryzen AI [579] ');"
set "Q=%Q%'GT_BATTERY='+[int][bool](Get-CimInstance Win32_Battery);"
set "Q=%Q%$g=(@(Get-CimInstance Win32_VideoController) | Where-Object {$_.Name} | ForEach-Object {& $x $_.Name}) -join ' + ';if($g){'GT_GPU='+$g};"
set "Q=%Q%$d=Get-CimInstance -Namespace root/Microsoft/Windows/DeviceGuard -ClassName Win32_DeviceGuard;"
set "Q=%Q%if($d){'GT_VBS='+[int]$d.VirtualizationBasedSecurityStatus;'GT_VBSRUN=,'+(@($d.SecurityServicesRunning) -join ',')+','};"
set "Q=%Q%$s=(Get-Process -Id $PID).SessionId;"
set "Q=%Q%$p=@(Get-CimInstance Win32_Process -Filter 'Name=''explorer.exe''' | Where-Object {$_.SessionId -eq $s})[0];"
set "Q=%Q%if($p){$o=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid;if($o.Sid){'GT_USERSID='+$o.Sid}};"
set "Q=%Q%if($c.Name -match 'X3D'){'GT_GAMEBAR='+[int][bool]((Get-AppxPackage -Name Microsoft.XboxGamingOverlay) -or (Get-AppxPackage -AllUsers -Name Microsoft.XboxGamingOverlay))}"
for /f "usebackq tokens=1,* delims==" %%A in (`%PS% -NoProfile -NonInteractive -Command "%Q%" 2^>nul ^| findstr /b /c:"GT_"`) do set "%%A=%%B"
:detect_done

rem Per-user settings go to the signed-in user's hive, even when the script
rem was elevated with a different administrator account.
set "UROOT=HKCU"
if not defined GT_USERSID goto :uroot_done
reg query "HKU\%GT_USERSID%" >nul 2>&1
if "%errorlevel%"=="0" set "UROOT=HKU\%GT_USERSID%"
:uroot_done

rem ---- AMD Ryzen X3D: dual-CCD parts rely on Game Mode for CCD parking -----
set "IS_X3D="
set "IS_X3D2="
echo %GT_CPU%| findstr /i /c:"X3D" >nul
if "%errorlevel%"=="0" set "IS_X3D=1"
if defined IS_X3D if %GT_CORES% GTR 8 set "IS_X3D2=1"
rem X3D2 parts carry V-Cache on both CCDs, so nothing needs parking.
echo %GT_CPU%| findstr /i /c:"X3D2" >nul
if "%errorlevel%"=="0" set "IS_X3D2="

rem ---- Anti-cheats that can require VBS / Memory Integrity ----------------
set "AC_FACEIT="
set "AC_VANGUARD="
set "AC_JAVELIN="
for %%S in (FACEITService FACEIT) do (reg query "%SVC%\%%S" >nul 2>&1 & if not errorlevel 1 set "AC_FACEIT=1")
for %%S in (vgc vgk) do (reg query "%SVC%\%%S" >nul 2>&1 & if not errorlevel 1 set "AC_VANGUARD=1")
reg query "%SVC%\EAAntiCheatService" >nul 2>&1
if "%errorlevel%"=="0" set "AC_JAVELIN=1"
set "GT_AC=none found"
set "AC_NEEDVBS="
if defined AC_FACEIT set "GT_AC=FACEIT" & set "AC_NEEDVBS=1"
if defined AC_VANGUARD set "GT_AC=Riot Vanguard" & set "AC_NEEDVBS=1"
if defined AC_FACEIT if defined AC_VANGUARD set "GT_AC=FACEIT and Riot Vanguard"

rem ---- Xbox Gaming Services: achievements are reported through DiagTrack ---
set "HAS_XBOX="
reg query "%SVC%\GamingServices" >nul 2>&1
if "%errorlevel%"=="0" set "HAS_XBOX=1"

rem ---- Decisions ------------------------------------------------------------
set "VBS_TXT=unknown"
if "%GT_VBS%"=="0" set "VBS_TXT=off"
if "%GT_VBS%"=="1" set "VBS_TXT=configured, not running"
if "%GT_VBS%"=="2" set "VBS_TXT=running"
if "%GT_VBS%"=="2" if not "%GT_VBSRUN:,2,=%"=="%GT_VBSRUN%" set "VBS_TXT=running, Memory Integrity on"

set "DO_VBS=1"
set "VBS_WHY="
if /i "%VBS_MODE%"=="keep" set "DO_VBS=" & set "VBS_WHY=VBS_MODE is set to keep"
if /i not "%VBS_MODE%"=="keep" if /i not "%VBS_MODE%"=="disable" if defined AC_NEEDVBS set "DO_VBS=" & set "VBS_WHY=required by %GT_AC%"

set "DO_DIAG=1"
set "DIAG_WHY="
if /i "%DIAGTRACK_MODE%"=="keep" set "DO_DIAG=" & set "DIAG_WHY=DIAGTRACK_MODE is set to keep"
if /i not "%DIAGTRACK_MODE%"=="keep" if /i not "%DIAGTRACK_MODE%"=="disable" if defined HAS_XBOX set "DO_DIAG=" & set "DIAG_WHY=Xbox achievements in PC games are reported through it"

set "DO_PT="
if /i "%POWERTHROTTLING_MODE%"=="off" set "DO_PT=1"
if /i "%POWERTHROTTLING_MODE%"=="auto" if "%GT_HYBRID%"=="1" if "%GT_BATTERY%"=="0" set "DO_PT=1"

set "MEM_TXT=pagefile checked"
if %GT_RAMGB% GEQ 16 set "MEM_TXT=page combining off, pagefile checked"
if %GT_RAMGB% GEQ 32 set "MEM_TXT=page combining and memory compression off, pagefile checked"

set "OPT_TXT="
if /i "%CPU_MITIGATIONS_MODE%"=="off" set "OPT_TXT=%OPT_TXT%, Spectre/Meltdown mitigations off"
if /i "%DEFENDER_EXCLUSIONS_MODE%"=="add" set "OPT_TXT=%OPT_TXT%, Defender game exclusions"
if /i "%STORE_APPS_BACKGROUND_MODE%"=="off" set "OPT_TXT=%OPT_TXT%, Store apps in background off"
if /i "%HYPERVISOR_MODE%"=="off" set "OPT_TXT=%OPT_TXT%, hypervisor off"
if not defined OPT_TXT set "OPT_TXT=, none enabled - see the options at the top of GameTune.bat"
set "OPT_TXT=%OPT_TXT:~2%"

rem ---- Summary and confirmation ---------------------------------------------
set "SH_ED=%GT_EDITION%"
if /i "%GT_EDITION%"=="Core" set "SH_ED=Home"
if /i "%GT_EDITION%"=="CoreSingleLanguage" set "SH_ED=Home Single Language"
if /i "%GT_EDITION%"=="Professional" set "SH_ED=Pro"
set "SH_CPU=%GT_CPU%"
if not "%GT_CORES%"=="0" set "SH_CPU=%GT_CPU%   %GT_CORES% cores / %GT_THREADS% threads"
if "%GT_HYBRID%"=="1" set "SH_CPU=%SH_CPU%, hybrid"
set "SH_RAM=unknown"
if not "%GT_RAMGB%"=="0" set "SH_RAM=%GT_RAMGB% GB"
set "SH_TYPE=unknown"
if "%GT_BATTERY%"=="0" set "SH_TYPE=desktop"
if "%GT_BATTERY%"=="1" set "SH_TYPE=laptop"
echo.
echo  System
echo   OS          %GT_OS% %GT_VER%   build %GT_BUILD%.%GT_UBR%   %SH_ED%
echo   PC          %SH_TYPE%
echo   CPU         %SH_CPU%
echo   RAM         %SH_RAM%
echo   GPU         %GT_GPU%
echo   VBS         %VBS_TXT%
echo   Anti-cheat that needs VBS: %GT_AC%
if "%GT_CPU%"=="unknown" echo   Note: hardware detection failed, so hardware-specific steps are skipped.
echo.
echo  Planned changes
if defined DO_VBS echo   - VBS and Memory Integrity: off
if not defined DO_VBS echo   - VBS and Memory Integrity: unchanged, %VBS_WHY%
echo   - Game Mode: on.  Game Bar background recording: off
if /i not "%HAGS_MODE%"=="keep" echo   - Hardware-accelerated GPU scheduling: on
if %GT_BUILD% GEQ 22621 echo   - Optimizations for windowed games: on
if /i not "%AUTOHDR_MODE%"=="keep" if %GT_BUILD% GEQ 22000 echo   - Auto HDR: off
echo   - Fault Tolerant Heap: off, per-game list cleared
echo   - Memory: %MEM_TXT%
echo   - Forced HPET clock: removed, if present
if defined DO_PT echo   - Power throttling of background processes: off
if defined IS_X3D echo   - AMD 3D V-Cache optimizer: checked
echo   - Widgets and Edge running in the background: off
if defined DO_DIAG echo   - Windows telemetry: DiagTrack, collectors and appraiser/CEIP/census tasks off
if not defined DO_DIAG echo   - Windows telemetry: collectors and tasks off. DiagTrack unchanged, %DIAG_WHY%
echo   - NVIDIA, AMD, Intel and Office telemetry: off where installed
echo   - SSD TRIM: checked
echo   - Optional extras: %OPT_TXT%
echo.
echo  A restart is needed afterwards. README.md shows how to undo each change.
echo.
choice /c YN /n /m "  Apply these changes now? [Y/N] "
if errorlevel 2 goto :cancelled

set "STEPN=0"
set "STEPS=17"
call :step_vbs
call :step_gamebar
call :step_hags
call :step_windowed
call :step_autohdr
call :step_fth
call :step_memory
call :step_hpet
call :step_powerthrottling
call :step_x3d
call :step_background
call :step_telemetry
call :step_vendor
call :step_trim
call :step_mitigations
call :step_defender
call :step_hypervisor

echo.
echo  ==============================================================
echo   Done. Restart Windows so every change takes effect.
echo  ==============================================================
echo.
choice /c YN /n /m "  Restart now? [Y/N] "
if errorlevel 2 goto :no_restart
shutdown /r /t 5 /c "GameTune: restarting to apply changes"
exit /b 0

:no_restart
echo.
echo  Restart before you benchmark: most of these changes only take effect
echo  after a reboot.
echo.
pause
exit /b 0


rem ==========================================================================
rem  Steps
rem ==========================================================================

:step_vbs
rem Memory Integrity (HVCI) costs about 5 percent on average and more in the
rem 1 percent lows of CPU-bound games. Microsoft's own gaming guidance lists
rem turning it off. Windows enables it automatically from the October 2026
rem update on, but respects a value that was turned off explicitly.
call :hdr "Virtualization-Based Security / Memory Integrity"
if defined DO_VBS goto :vbs_apply
echo   [SKIP] Unchanged: %VBS_WHY%.
if defined AC_NEEDVBS echo          It can refuse to start with VBS off. Set VBS_MODE=disable to override.
exit /b 0

:vbs_apply
call :getdw "%DG%" Locked V1
call :getdw "%DG%\Scenarios\HypervisorEnforcedCodeIntegrity" Locked V2
set "VBS_LOCK="
if "%V1%"=="1" set "VBS_LOCK=1"
if "%V2%"=="1" set "VBS_LOCK=1"
set "VBS_FAIL="
reg add "%DG%\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "VBS_FAIL=1"
reg add "%DG%" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "VBS_FAIL=1"
if defined VBS_FAIL echo   [FAIL] Could not write the DeviceGuard registry values.& exit /b 0
if defined VBS_LOCK echo   [WARN] Set to off, but VBS is UEFI-locked and stays on until the lock is cleared. See README.md.
if not defined VBS_LOCK if "%GT_VBS%"=="0" echo   [ OK ] Already off. Now set explicitly, so automatic enablement by Windows Update leaves it off.
if not defined VBS_LOCK if not "%GT_VBS%"=="0" echo   [ OK ] Turned off. Takes effect after a restart.
rem Group Policy values override the settings above when present.
for %%P in (EnableVirtualizationBasedSecurity HypervisorEnforcedCodeIntegrity LsaCfgFlags) do call :vbs_policy %%P
rem Credential Guard keeps VBS running: default-on for Enterprise/Education.
set "CG="
call :getdw "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" LsaCfgFlags V3
if defined V3 if not "%V3%"=="0" set "CG=1"
if not "%GT_VBSRUN:,1,=%"=="%GT_VBSRUN%" set "CG=1"
echo %GT_EDITION%| findstr /i "Enterprise Education" >nul
if "%errorlevel%"=="0" set "CG=1"
if not defined CG goto :vbs_cg_done
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" echo   [ OK ] Credential Guard: off, because it keeps VBS running.
:vbs_cg_done
call :getdw "%DG%\Scenarios\SecureBiometrics" Enabled V4
if "%V4%"=="1" echo   [WARN] Windows Hello Enhanced Sign-in Security needs VBS: face/fingerprint sign-in stops working, your PIN still works.
if defined AC_NEEDVBS echo   [WARN] %GT_AC% may refuse to start until Memory Integrity is turned back on.
if defined AC_JAVELIN echo   [INFO] EA Javelin asks for VBS-capable hardware but does not enforce VBS. If an EA game reports a security error, turn Memory Integrity back on.
exit /b 0

:vbs_policy
call :getdw "%DGP%" %1 VP
if not defined VP exit /b 0
if "%VP%"=="0" exit /b 0
reg add "%DGP%" /v %1 /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" echo   [ OK ] Group Policy value %1 set to 0.
exit /b 0


:step_gamebar
rem Game Mode: better 1 percent lows under background load, and the signal
rem the AMD driver uses to park the non-V-Cache CCD on dual-CCD X3D parts.
rem Background recording continuously encodes gameplay video.
call :hdr "Game Mode and Game Bar background recording"
set "GB=%UROOT%\Software\Microsoft\GameBar"
set "DVR=%UROOT%\Software\Microsoft\Windows\CurrentVersion\GameDVR"
call :getdw "%GB%" AutoGameModeEnabled V1
call :getdw "%DVR%" HistoricalCaptureEnabled V2
reg add "%GB%" /v AutoGameModeEnabled /t REG_DWORD /d 1 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write the Game Mode setting.& goto :gamebar_dvr
if "%V1%"=="0" (echo   [ OK ] Game Mode was off - turned on.) else (echo   [ OK ] Game Mode is on.)
if defined IS_X3D2 echo   [INFO] Dual-CCD X3D: Game Mode lets the AMD driver keep games on the V-Cache CCD.
:gamebar_dvr
reg add "%DVR%" /v HistoricalCaptureEnabled /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write the background recording setting.& exit /b 0
if "%V2%"=="1" (echo   [ OK ] Background recording was on - turned off. It encodes video the whole time you play.) else (echo   [ OK ] Background recording is off.)
exit /b 0


:step_hags
rem The GPU schedules its own work instead of the CPU-side scheduler. Measured
rem gains are small and mostly in the 1 percent lows; DLSS and FSR frame
rem generation need it. Windows ignores the value when the GPU or driver
rem cannot do it.
call :hdr "Hardware-accelerated GPU scheduling"
if /i "%HAGS_MODE%"=="keep" echo   [SKIP] HAGS_MODE is set to keep.& exit /b 0
set "GDK=HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
call :getdw "%GDK%" HwSchMode V1
if "%V1%"=="2" echo   [ OK ] Already on.& exit /b 0
reg add "%GDK%" /v HwSchMode /t REG_DWORD /d 2 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write HwSchMode.& exit /b 0
if "%V1%"=="1" (echo   [ OK ] Was off - turned on.) else (echo   [ OK ] Turned on.)
echo          Unsupported GPUs and drivers simply keep the old scheduler.
exit /b 0


:step_windowed
rem Moves DX10/DX11 games that run windowed or borderless with the legacy
rem blt presentation model to the flip model: lower presentation latency,
rem independent flip and VRR. Off by default. Windows 11 22H2 and newer.
call :hdr "Optimizations for windowed games"
if %GT_BUILD% LSS 22621 echo   [SKIP] Needs Windows 11 22H2 or newer.& exit /b 0
call :dx_read
call :dx_get SwapEffectUpgradeEnable V1
if "%V1%"=="1" echo   [ OK ] Already on.& exit /b 0
call :dx_set SwapEffectUpgradeEnable 1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write DirectXUserGlobalSettings.& exit /b 0
echo   [ OK ] Turned on: windowed and borderless DX10/DX11 games use the flip model.
exit /b 0


:step_autohdr
rem Auto HDR runs a tone-mapping pass over every frame of SDR games while HDR
rem is on, about 2 to 3 percent of GPU time. Bit 0 of AutoHDREnable is the
rem switch; the other bits are kept.
call :hdr "Auto HDR"
if /i "%AUTOHDR_MODE%"=="keep" echo   [SKIP] AUTOHDR_MODE is set to keep.& exit /b 0
if %GT_BUILD% LSS 22000 echo   [SKIP] Auto HDR exists only on Windows 11.& exit /b 0
call :dx_read
call :dx_get AutoHDREnable AH
if not defined AH set "AH=1"
set /a "AHB=AH %% 2" >nul 2>&1
if "%AHB%"=="0" echo   [ OK ] Already off.& exit /b 0
set /a "AH=AH - AHB"
call :dx_set AutoHDREnable %AH%
if not "%errorlevel%"=="0" echo   [FAIL] Could not write DirectXUserGlobalSettings.& exit /b 0
echo   [ OK ] Turned off. It only ever ran with HDR on; Settings, Display, HDR turns it back on.
exit /b 0


:step_fth
rem After repeated crashes Windows silently moves a program onto the Fault
rem Tolerant Heap, which is much slower than the normal heap. Programs on it
rem are listed under FTH\State. Turning FTH off only stops new entries, so
rem the list is reset as well: Microsoft's documented reset runs first and FTH
rem is switched off afterwards, so the reset cannot turn it back on.
call :hdr "Fault Tolerant Heap"
set "FTHS=HKLM\SOFTWARE\Microsoft\FTH\State"
call :count_values "%FTHS%" FTHN
if exist "%SYS32%\fthsvc.dll" rundll32.exe fthsvc.dll,FthSysprepSpecialize
reg add "HKLM\SOFTWARE\Microsoft\FTH" /v Enabled /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write HKLM\SOFTWARE\Microsoft\FTH.& exit /b 0
echo   [ OK ] Turned off: crash-prone games are no longer moved to the slow heap.
if "%FTHN%"=="0" exit /b 0
call :count_values "%FTHS%" FTHA
if not "%FTHA%"=="0" reg delete "%FTHS%" /va /f >nul 2>&1
call :count_values "%FTHS%" FTHA
if "%FTHA%"=="0" (echo   [ OK ] %FTHN% program^(s^) had been moved to the slow heap - list cleared.) else (echo   [WARN] %FTHA% program^(s^) still listed under %FTHS%.)
exit /b 0


:step_memory
rem Page combining periodically scans RAM for identical pages and can hold a
rem core at 100 percent for seconds; with 16 GB or more the memory it saves is
rem not worth that. Memory compression spends CPU time compressing pages that
rem fit in RAM anyway once there are 32 GB. A disabled pagefile, left over
rem from old tweak guides, makes games crash or stutter when the commit limit
rem runs out, so it is set back to Windows-managed. A custom pagefile is kept.
call :hdr "Memory manager"
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
set "GT_PCW=0"
set "GT_MCW=0"
if %GT_RAMGB% GEQ 16 set "GT_PCW=1"
if %GT_RAMGB% GEQ 32 set "GT_MCW=1"
set "PC=" & set "MC=" & set "PF="
set "Q=$ErrorActionPreference='SilentlyContinue';"
set "Q=%Q%$sm=(Get-Service SysMain).Status -eq 'Running';"
set "Q=%Q%if($sm){$a=Get-MMAgent};"
set "Q=%Q%if($env:GT_PCW -eq '1'){if(-not $sm){'PC=NOSYSMAIN'}elseif(-not $a){'PC=FAIL'}elseif(-not $a.PageCombining){'PC=ALREADY'}else{try{Disable-MMAgent -PageCombining -ErrorAction Stop;'PC=DONE'}catch{'PC=FAIL'}}};"
set "Q=%Q%if($env:GT_MCW -eq '1'){if(-not $sm){'MC=NOSYSMAIN'}elseif(-not $a){'MC=FAIL'}elseif(-not $a.MemoryCompression){'MC=ALREADY'}else{try{Disable-MMAgent -MemoryCompression -ErrorAction Stop;'MC=DONE'}catch{'MC=FAIL'}}};"
set "Q=%Q%$cs=Get-CimInstance Win32_ComputerSystem;"
set "Q=%Q%if(-not $cs){'PF=FAIL'}elseif($cs.AutomaticManagedPagefile){'PF=AUTO'}elseif(@(Get-CimInstance Win32_PageFileSetting).Count){'PF=CUSTOM'}else{try{Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -ErrorAction Stop;'PF=FIXED'}catch{'PF=FAIL'}}"
for /f "usebackq tokens=1,* delims==" %%A in (`%PS% -NoProfile -NonInteractive -Command "%Q%" 2^>nul ^| findstr /b /c:"PC=" /c:"MC=" /c:"PF="`) do set "%%A=%%B"
if "%GT_RAMGB%"=="0" echo   [SKIP] Page combining and memory compression: installed RAM size unknown.& goto :mem_pagefile
if "%GT_PCW%"=="0" echo   [SKIP] Page combining: kept on, because it saves useful memory below 16 GB.
if "%PC%"=="DONE" echo   [ OK ] Page combining: turned off.
if "%PC%"=="ALREADY" echo   [ OK ] Page combining: already off.
if "%PC%"=="NOSYSMAIN" echo   [SKIP] Page combining: not active, because the SysMain service is not running.
if "%PC%"=="FAIL" echo   [FAIL] Page combining: could not change the setting.
if "%GT_PCW%"=="1" if not defined PC echo   [FAIL] Page combining: could not query the memory manager.
if "%GT_MCW%"=="0" echo   [SKIP] Memory compression: kept on, because below 32 GB it prevents paging.
if "%MC%"=="DONE" echo   [ OK ] Memory compression: turned off.
if "%MC%"=="ALREADY" echo   [ OK ] Memory compression: already off.
if "%MC%"=="NOSYSMAIN" echo   [SKIP] Memory compression: not active, because the SysMain service is not running.
if "%MC%"=="FAIL" echo   [FAIL] Memory compression: could not change the setting.
if "%GT_MCW%"=="1" if not defined MC echo   [FAIL] Memory compression: could not query the memory manager.
:mem_pagefile
if "%PF%"=="AUTO" echo   [ OK ] Pagefile: managed by Windows.
if "%PF%"=="CUSTOM" echo   [ OK ] Pagefile: custom size kept.
if "%PF%"=="FIXED" echo   [ OK ] Pagefile: was disabled - set back to Windows-managed.
if "%PF%"=="FAIL" echo   [FAIL] Pagefile: could not read or change the setting.
if not defined PF echo   [FAIL] Pagefile: could not read the setting.
exit /b 0


:step_hpet
rem "bcdedit /set useplatformclock true" is a leftover from old tweak guides.
rem It forces HPET as the QueryPerformanceCounter source, which makes every
rem timer query far slower and costs FPS. Removing it restores the default.
call :hdr "Forced HPET clock"
bcdedit /enum {current} >nul 2>&1
if not "%errorlevel%"=="0" echo   [SKIP] Could not read the boot configuration.& exit /b 0
bcdedit /enum {current} 2>nul | findstr /i /c:"useplatformclock" >nul
if not "%errorlevel%"=="0" echo   [ OK ] Not forced: Windows picks its timer source itself.& exit /b 0
bcdedit /deletevalue {current} useplatformclock >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not remove useplatformclock.& exit /b 0
echo   [ OK ] Removed useplatformclock. Timer queries go back to the fast default source.
exit /b 0


:step_powerthrottling
rem On hybrid CPUs Windows moves processes it considers background work to
rem the E-cores at reduced clocks (EcoQoS). That catches game helper
rem processes, shader compilers and games on a second monitor. This is a
rem scheduler setting, not a power plan.
call :hdr "Power throttling of background processes"
if /i "%POWERTHROTTLING_MODE%"=="keep" echo   [SKIP] POWERTHROTTLING_MODE is set to keep.& exit /b 0
if defined DO_PT goto :pt_apply
if "%GT_HYBRID%"=="?" echo   [SKIP] CPU type unknown.& exit /b 0
if not "%GT_HYBRID%"=="1" echo   [SKIP] Only matters on CPUs with separate P-cores and E-cores.& exit /b 0
echo   [SKIP] Laptop: kept for battery life. Set POWERTHROTTLING_MODE=off to apply it anyway.
exit /b 0
:pt_apply
set "PT=HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
call :getdw "%PT%" PowerThrottlingOff V1
if "%V1%"=="1" echo   [ OK ] Already off.& exit /b 0
reg add "%PT%" /v PowerThrottlingOff /t REG_DWORD /d 1 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write PowerThrottlingOff.& exit /b 0
echo   [ OK ] Turned off: game helpers and games on a second monitor keep P-cores and full clocks.
exit /b 0


:step_x3d
rem Dual-CCD X3D parts need the AMD 3D V-Cache Performance Optimizer service
rem plus Game Mode and Game Bar, or games spread over both CCDs and stutter.
call :hdr "AMD 3D V-Cache scheduling"
if "%GT_CPU%"=="unknown" echo   [SKIP] CPU model unknown.& exit /b 0
if not defined IS_X3D echo   [SKIP] No Ryzen X3D processor detected.& exit /b 0
reg query "%SVC%\amd3dvcacheSvc" >nul 2>&1
if not "%errorlevel%"=="0" goto :x3d_nosvc
call :getdw "%SVC%\amd3dvcacheSvc" Start V1
if "%V1%"=="4" sc config amd3dvcacheSvc start= auto >nul 2>&1
sc start amd3dvcacheSvc >nul 2>&1
set "SCRC=%errorlevel%"
set "X3D_RUN="
if "%SCRC%"=="0" set "X3D_RUN=1"
if "%SCRC%"=="1056" set "X3D_RUN=1"
if not defined X3D_RUN echo   [FAIL] AMD 3D V-Cache Performance Optimizer service did not start, error %SCRC%.& goto :x3d_gamebar
if "%V1%"=="4" (echo   [ OK ] AMD 3D V-Cache Performance Optimizer was disabled - re-enabled and started.) else (echo   [ OK ] AMD 3D V-Cache Performance Optimizer is running.)
goto :x3d_gamebar
:x3d_nosvc
if defined IS_X3D2 (echo   [WARN] AMD 3D V-Cache Performance Optimizer is not installed. Install the current AMD chipset driver.) else (echo   [ OK ] Single-CCD X3D: no CCD parking needed.)
:x3d_gamebar
if defined IS_X3D2 if "%GT_GAMEBAR%"=="0" echo   [WARN] Xbox Game Bar is not installed. Dual-CCD X3D parking relies on it to recognise games: reinstall it from the Microsoft Store.
exit /b 0


:step_background
rem Programs that start with Windows and keep running without being opened.
rem Widgets keeps a web view of 50 to 150 MB loaded and refreshing; Edge's
rem startup boost and background mode keep browser processes alive after the
rem last window closes. This matters most on 8 and 16 GB systems.
call :hdr "Apps that run in the background on their own"
if %GT_BUILD% GEQ 22000 goto :bg_widgets11
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] News and Interests: off.) else (echo   [FAIL] Could not turn off News and Interests.)
goto :bg_edge
:bg_widgets11
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Widgets: off.) else (echo   [FAIL] Could not turn off Widgets.)
:bg_edge
set "EDGE="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "EDGE=1"
if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "EDGE=1"
if not defined EDGE echo   [SKIP] Microsoft Edge is not installed.& goto :bg_store
set "EDGEP=HKLM\SOFTWARE\Policies\Microsoft\Edge"
reg add "%EDGEP%" /v StartupBoostEnabled /t REG_DWORD /d 0 /f >nul 2>&1
set "EDGE_RC=%errorlevel%"
reg add "%EDGEP%" /v BackgroundModeEnabled /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "EDGE_RC=1"
if "%EDGE_RC%"=="0" (echo   [ OK ] Edge startup boost and background mode: off. Edge now exits with its last window.) else (echo   [FAIL] Could not write the Edge policies.)
:bg_store
if /i not "%STORE_APPS_BACKGROUND_MODE%"=="off" echo   [SKIP] Store apps in the background: unchanged. Optional, see STORE_APPS_BACKGROUND_MODE.& exit /b 0
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write the background apps policy.& exit /b 0
echo   [ OK ] Store apps can no longer run in the background; their notifications stop while they are closed.
exit /b 0


:step_telemetry
rem The compatibility appraiser (CompatTelRunner.exe) can hold CPU and disk
rem at 100 percent for up to 20 minutes; the CEIP, census and feedback tasks
rem add smaller bursts. DiagTrack itself is light but always running. None of
rem it raises average FPS; it removes background bursts that land in the 0.1
rem percent lows.
call :hdr "Windows telemetry background activity"
if not defined DO_DIAG echo   [INFO] DiagTrack unchanged: %DIAG_WHY%.& goto :tel_common
reg query "%SVC%\DiagTrack" >nul 2>&1
if not "%errorlevel%"=="0" echo   [SKIP] DiagTrack service not present.& goto :tel_policy
sc stop DiagTrack >nul 2>&1
sc config DiagTrack start= disabled >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Connected User Experiences and Telemetry service: stopped and disabled.) else (echo   [FAIL] Could not disable the DiagTrack service.)
:tel_policy
set "AL=HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener"
reg query "%AL%" >nul 2>&1
if not "%errorlevel%"=="0" goto :tel_allow
reg add "%AL%" /v Start /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" echo   [ OK ] DiagTrack boot-time trace session: off.
:tel_allow
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f >nul 2>&1
if "%errorlevel%"=="0" echo   [ OK ] Diagnostic data: lowest level this edition allows.
:tel_common
rem Collectors that feed the appraiser and CEIP, and activity history. None of
rem these is involved in Xbox achievements.
set "TEL_RC=0"
set "ACP=HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
reg add "%ACP%" /v DisableInventory /t REG_DWORD /d 1 /f >nul 2>&1
if not "%errorlevel%"=="0" set "TEL_RC=1"
reg add "%ACP%" /v AITEnable /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "TEL_RC=1"
reg add "HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "TEL_RC=1"
if "%TEL_RC%"=="0" (echo   [ OK ] Inventory collector, application telemetry and CEIP: off.) else (echo   [FAIL] Could not write the AppCompat/CEIP policies.)
set "TEL_RC=0"
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v PublishUserActivities /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "TEL_RC=1"
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v UploadUserActivities /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "TEL_RC=1"
if "%TEL_RC%"=="0" (echo   [ OK ] Activity history: off.) else (echo   [FAIL] Could not write the activity history policies.)
set "TASKN=0"
for %%T in (
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp"
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
    "\Microsoft\Windows\Application Experience\MareBackup"
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
    "\Microsoft\Windows\Device Information\Device"
    "\Microsoft\Windows\Device Information\Device User"
    "\Microsoft\Windows\Autochk\Proxy"
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    "\Microsoft\Windows\Feedback\Siuf\DmClient"
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
    "\Microsoft\Windows\PI\Sqm-Tasks"
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
) do call :task_off %%T
if "%TASKN%"=="0" echo   [SKIP] None of the telemetry tasks exist on this build.
exit /b 0


:step_vendor
rem Telemetry that hardware and software vendors install next to their
rem drivers and apps. Intel's System Usage Report service is documented to
rem hold a full CPU core at times. NVIDIA's crash and telemetry reporter, AMD's
rem User Experience Program and Office's telemetry agent run on schedules.
rem Nothing here is needed by the drivers themselves.
call :hdr "Hardware and software vendor telemetry"
set "TASKN=0"
set "VSVC=0"
call :svc_off ESRV_SVC_QUEENCREEK "Intel System Usage Report"
call :svc_off SystemUsageReportSvc_QUEENCREEK "Intel System Usage Report helper"
call :svc_off AUEPLauncher "AMD User Experience Program"
for /f "tokens=1 delims=," %%T in ('schtasks /query /fo csv /nh 2^>nul ^| findstr /i /c:"NvTmRep" /c:"AUEP" /c:"OfficeTelemetryAgent"') do call :task_off %%T
if "%TASKN%"=="0" if "%VSVC%"=="0" echo   [SKIP] No NVIDIA, AMD, Intel or Office telemetry components found.
exit /b 0


:step_trim
rem With TRIM off, an SSD has to erase blocks while it writes, so writes
rem slow down over time: asset streaming and shader-cache writes stutter.
rem NTFS enables it by default; old tweak guides sometimes turned it off.
call :hdr "SSD TRIM"
set "TRIM_OFF="
call :getdw "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" DisableDeleteNotification V1
if "%V1%"=="1" set "TRIM_OFF=1"
fsutil behavior query DisableDeleteNotify 2>nul | findstr /i /c:"NTFS DisableDeleteNotify = 1" >nul
if "%errorlevel%"=="0" set "TRIM_OFF=1"
if not defined TRIM_OFF echo   [ OK ] TRIM is enabled.& exit /b 0
fsutil behavior set DisableDeleteNotify NTFS 0 >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not re-enable TRIM.& exit /b 0
echo   [ OK ] TRIM was disabled - re-enabled.
exit /b 0


:step_mitigations
rem Optional. Microsoft's documented override for the Spectre v2 and Meltdown
rem mitigations. CPUs from 2019 on have hardware fixes and gain about 1
rem percent; older Intel CPUs lose around 4 percent in frametimes to them.
call :hdr "Spectre and Meltdown mitigations - optional"
if /i not "%CPU_MITIGATIONS_MODE%"=="off" echo   [SKIP] Unchanged. Optional: set CPU_MITIGATIONS_MODE=off, see README.md.& exit /b 0
set "MMK=HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
reg add "%MMK%" /v FeatureSettingsOverride /t REG_DWORD /d 3 /f >nul 2>&1
set "MIT_RC=%errorlevel%"
reg add "%MMK%" /v FeatureSettingsOverrideMask /t REG_DWORD /d 3 /f >nul 2>&1
if not "%errorlevel%"=="0" set "MIT_RC=1"
if not "%MIT_RC%"=="0" echo   [FAIL] Could not write the mitigation override.& exit /b 0
echo   [ OK ] Spectre v2 and Meltdown mitigations: off after a restart.
echo   [WARN] This reopens those attacks to any program that runs on this PC, including web pages.
exit /b 0


:step_defender
rem Optional. Real-time scanning inspects every file a game opens and every
rem shader-cache file a driver writes, which lengthens loads and can stutter
rem asset streaming. Only launcher-defined libraries, the launchers' default
rem game folders and the GPU shader caches are excluded.
call :hdr "Microsoft Defender exclusions for games - optional"
if /i not "%DEFENDER_EXCLUSIONS_MODE%"=="add" echo   [SKIP] Unchanged. Optional: set DEFENDER_EXCLUSIONS_MODE=add, see README.md.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
set "Q=$ErrorActionPreference='SilentlyContinue';"
set "Q=%Q%$st=Get-MpComputerStatus;"
set "Q=%Q%if(-not $st -or $st.AMRunningMode -ne 'Normal'){'DEFOFF=1';return};"
set "Q=%Q%$L=New-Object System.Collections.Generic.List[string];$q=[char]34;"
set "Q=%Q%$pr=(Get-CimInstance Win32_UserProfile -Filter ('SID='''+$env:GT_USERSID+'''')).LocalPath;if(-not $pr){$pr=$env:USERPROFILE};"
set "Q=%Q%foreach($k in 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam'){$s=(Get-ItemProperty $k).InstallPath;if($s){$L.Add((Join-Path $s 'steamapps'));$v=Join-Path $s 'steamapps\libraryfolders.vdf';if(Test-Path $v){foreach($ln in Get-Content $v){if($ln -match ($q+'path'+$q)){$L.Add((Join-Path ($ln.Split($q)[3] -replace '\\\\','\') 'steamapps'))}}}}};"
set "Q=%Q%foreach($f in Get-ChildItem (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests') -Filter *.item){$j=Get-Content $f.FullName -Raw | ConvertFrom-Json;if($j.InstallLocation){$L.Add($j.InstallLocation)}};"
set "Q=%Q%foreach($r in (Get-PSDrive -PSProvider FileSystem).Root){foreach($n in 'XboxGames','Program Files\EA Games','Program Files\Epic Games','Program Files\Riot Games','Riot Games','Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games','Program Files (x86)\GOG Galaxy\Games','GOG Games'){$L.Add((Join-Path $r $n))}};"
set "Q=%Q%foreach($n in 'NVIDIA\DXCache','NVIDIA\GLCache','AMD\DxCache','AMD\DxcCache','AMD\VkCache','D3DSCache','Intel\ShaderCache'){$L.Add((Join-Path $pr ('AppData\Local\'+$n)))};"
set "Q=%Q%$h=@((Get-MpPreference).ExclusionPath);$c=0;"
set "Q=%Q%foreach($p in ($L | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Sort-Object -Unique)){$c++;if($h -contains $p){'DEFHAVE='+$p}else{try{Add-MpPreference -ExclusionPath $p -ErrorAction Stop;'DEFADD='+$p}catch{'DEFFAIL='+$p}}};"
set "Q=%Q%if(-not $c){'DEFNONE=1'}"
set "DEFOUT="
for /f "usebackq tokens=1,* delims==" %%A in (`%PS% -NoProfile -NonInteractive -Command "%Q%" 2^>nul ^| findstr /b /c:"DEF"`) do (
    set "DEFOUT=1"
    if "%%A"=="DEFADD" echo   [ OK ] Excluded: %%B
    if "%%A"=="DEFHAVE" echo   [ OK ] Already excluded: %%B
    if "%%A"=="DEFFAIL" echo   [FAIL] Could not exclude: %%B
    if "%%A"=="DEFOFF" echo   [SKIP] Microsoft Defender is not the active antivirus, so there is nothing to exclude.
    if "%%A"=="DEFNONE" echo   [SKIP] No game libraries or shader caches found.
)
if not defined DEFOUT echo   [FAIL] Could not query Microsoft Defender.
exit /b 0


:step_hypervisor
rem Optional. Hyper-V, Virtual Machine Platform (WSL2), Sandbox and Docker
rem keep the hypervisor loaded even with VBS off, which costs about 1 percent
rem in CPU-bound games.
call :hdr "Hypervisor - optional"
set "HV_FEAT="
for %%S in (vmms vmcompute) do (reg query "%SVC%\%%S" >nul 2>&1 & if not errorlevel 1 set "HV_FEAT=1")
if /i "%HYPERVISOR_MODE%"=="off" goto :hv_off
if not defined HV_FEAT echo   [ OK ] No Hyper-V or Virtual Machine Platform installed, so nothing keeps it loaded.& exit /b 0
bcdedit /enum {current} 2>nul | findstr /i /c:"hypervisorlaunchtype" | findstr /i /c:"Auto" >nul
if not "%errorlevel%"=="0" echo   [ OK ] The hypervisor is not set to load at boot.& exit /b 0
echo   [INFO] Hyper-V / Virtual Machine Platform keeps the hypervisor running, about 1%% in CPU-bound games.
echo          Kept because WSL2, Docker and VMs need it. Optional: set HYPERVISOR_MODE=off.
exit /b 0
:hv_off
if defined AC_NEEDVBS if /i not "%VBS_MODE%"=="disable" echo   [SKIP] %GT_AC% needs VBS, and VBS needs the hypervisor.& exit /b 0
bcdedit /set {current} hypervisorlaunchtype off >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not change the boot configuration.& exit /b 0
echo   [ OK ] The hypervisor no longer loads after a restart.
echo   [WARN] WSL2, Hyper-V, Windows Sandbox and Docker stop working until you run:
echo          bcdedit /set hypervisorlaunchtype auto
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

:getdw
rem getdw "key" valueName outVar - reads a REG_DWORD into outVar (decimal),
rem leaves outVar undefined when the value does not exist.
set "%~3="
for /f "tokens=3" %%V in ('reg query "%~1" /v %~2 2^>nul ^| findstr /c:"REG_DWORD"') do set /a "%~3=%%V"
exit /b 0

:count_values
rem count_values "key" outVar - number of values directly under a key
set "%~2=0"
for /f "delims=" %%L in ('reg query "%~1" 2^>nul ^| findstr /c:"    REG_"') do set /a "%~2+=1"
exit /b 0

:task_off
rem task_off "\path\task" - disables a scheduled task if it exists
schtasks /query /tn %1 >nul 2>&1
if not "%errorlevel%"=="0" exit /b 0
set /a TASKN+=1
schtasks /change /tn %1 /disable >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Task off: %~n1) else (echo   [FAIL] Could not disable task: %~n1)
exit /b 0

:svc_off
rem svc_off serviceName "label" - stops and disables a service if it exists
reg query "%SVC%\%~1" >nul 2>&1
if not "%errorlevel%"=="0" exit /b 0
set /a VSVC+=1
sc stop "%~1" >nul 2>&1
sc config "%~1" start= disabled >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Service off: %~2) else (echo   [FAIL] Could not disable service: %~2)
exit /b 0

rem DirectXUserGlobalSettings holds several "Key=Value;" entries, such as VRR,
rem Auto HDR and windowed-game optimizations. These helpers change one entry
rem and keep the rest.
:dx_read
set "DXK=%UROOT%\Software\Microsoft\DirectX\UserGpuPreferences"
set "DXV="
for /f "tokens=2,*" %%A in ('reg query "%DXK%" /v DirectXUserGlobalSettings 2^>nul ^| findstr /c:"REG_SZ"') do set "DXV=%%B"
if not defined DXV set "DXV=;"
exit /b 0

:dx_get
rem dx_get key outVar - value of one entry, undefined when absent
set "%~2="
set "DXGK=%~1"
set "DXGO=%~2"
for %%I in ("%DXV:;=" "%") do call :dx_get_item "%%~I"
exit /b 0
:dx_get_item
if "%~1"=="" exit /b 0
for /f "tokens=1,* delims==" %%K in ("%~1") do if /i "%%K"=="%DXGK%" set "%DXGO%=%%L"
exit /b 0

:dx_set
rem dx_set key value - writes the entry, keeping all other entries
set "DXSK=%~1"
set "DXN="
for %%I in ("%DXV:;=" "%") do call :dx_set_item "%%~I"
set "DXV=%DXN%%~1=%~2;"
reg add "%DXK%" /v DirectXUserGlobalSettings /t REG_SZ /d "%DXV%" /f >nul 2>&1
exit /b %errorlevel%
:dx_set_item
if "%~1"=="" exit /b 0
for /f "tokens=1 delims==" %%K in ("%~1") do if /i "%%K"=="%DXSK%" exit /b 0
set "DXN=%DXN%%~1;"
exit /b 0

:elevate
if not defined PS goto :needadmin
echo Requesting administrator rights...
set "GT_SELF=%~f0"
"%PS%" -NoProfile -NonInteractive -Command "try { Start-Process -FilePath $env:GT_SELF -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if not "%errorlevel%"=="0" goto :needadmin
exit /b 0

:needadmin
echo.
echo  Administrator rights are required and were not granted.
echo  Right-click GameTune.bat and choose "Run as administrator".
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
