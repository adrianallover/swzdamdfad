@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================================
rem  GameTune.bat - evidence-based Windows tuning for in-game frame delivery
rem
rem  Goal: better 0.1 / 1 percent lows, average FPS and frametime consistency
rem  on Windows 10 (version 2004 or newer) and Windows 11.
rem
rem  Only changes that current community benchmarking or vendor documentation
rem  shows to have a real, measurable effect are applied. Hardware, monitors,
rem  graphics drivers, installed games and the Windows build are detected at
rem  runtime and each step adapts to them. At the end it lists the hardware
rem  and setup problems that only you can fix, biggest gain first.
rem
rem  Writes no logs, exports, backups or restore points, and deletes no
rem  files. Does not touch network settings or power plans / powercfg. Its
rem  only disk cleanup change keeps the DirectX shader cache out of the
rem  automatic cleanup. README.md explains every change, the evidence behind
rem  it and how to undo it.
rem ==========================================================================

rem ---- Options -------------------------------------------------------------
rem  Nothing needs changing: every value below is already the setting with
rem  the most benefit for FPS and 1 percent lows. Each option also takes keep,
rem  which leaves that part of Windows as it is.
rem
rem  VBS_MODE              auto, disable or keep
rem      Virtualization-Based Security and Memory Integrity. auto turns them
rem      off unless FACEIT or Riot Vanguard is installed, because both refuse
rem      to run without them.
rem  DIAGTRACK_MODE        auto, disable or keep
rem      The Connected User Experiences and Telemetry service. auto turns it
rem      off unless Xbox Gaming Services is installed, because Xbox
rem      achievements in PC games are reported through it.
rem  HAGS_MODE             on, off or keep
rem      Hardware-accelerated GPU scheduling. Its effect is within a few
rem      percent either way and differs per game, so if your 1 percent lows
rem      got worse, test once with off. DLSS frame generation needs it on.
rem  AUTOHDR_MODE          off or keep
rem      Auto HDR costs 2 to 3 percent of GPU time while it is active.
rem  POWERTHROTTLING_MODE  off, auto or keep
rem      Power throttling of background processes. auto applies it only to
rem      desktops with hybrid P-core and E-core CPUs.
rem  REFRESH_MODE          max or keep
rem      Each monitor at the highest refresh rate it offers at its current
rem      resolution. You confirm the new rate; without an answer within 15
rem      seconds it switches back by itself.
rem  VRR_MODE              on or keep
rem      Lets DX11 games without their own support use G-SYNC or FreeSync,
rem      so frame rate drops below the refresh rate do not judder.
rem  GPU_PREFERENCE_MODE   auto or keep
rem      On PCs with two GPUs, every installed game goes to the
rem      high-performance GPU in Windows graphics settings.
rem  NVIDIA_MODE           fix or keep
rem      NVIDIA global settings that cost FPS or cause stutter go back to
rem      NVIDIA's defaults: shader cache off or smaller than the driver
rem      default, threaded optimization forced off, integrated graphics
rem      preferred, a Max Frame Rate well below the refresh rate.
rem  AMD_MODE              fix or keep
rem      AMD shader cache back on when it was off, Radeon Chill off.
rem  SHADER_CACHE_MODE     protect or keep
rem      Stops Windows' automatic disk cleanup from deleting the DirectX
rem      shader cache, after which games compile shaders again and stutter.
rem
rem  On by default for the most FPS, with a cost README.md describes:
rem  CPU_MITIGATIONS_MODE        off or keep
rem      Spectre v2 and Meltdown mitigations. About 1 percent on CPUs from
rem      2019 on, about 4 percent on older Intel CPUs. Reopens those attacks.
rem  DEFENDER_EXCLUSIONS_MODE    add or keep
rem      Excludes game libraries and shader caches from real-time scanning.
rem  STORE_APPS_BACKGROUND_MODE  off or keep
rem      Stops Microsoft Store apps from running in the background.
rem  HYPERVISOR_MODE             off or keep
rem      Stops the hypervisor from loading. WSL2, Hyper-V, Windows Sandbox
rem      and Docker stop working until it is set back.
rem --------------------------------------------------------------------------
set "VBS_MODE=auto"
set "DIAGTRACK_MODE=auto"
set "HAGS_MODE=on"
set "AUTOHDR_MODE=off"
set "POWERTHROTTLING_MODE=off"
set "REFRESH_MODE=max"
set "VRR_MODE=on"
set "GPU_PREFERENCE_MODE=auto"
set "NVIDIA_MODE=fix"
set "AMD_MODE=fix"
set "SHADER_CACHE_MODE=protect"
set "CPU_MITIGATIONS_MODE=off"
set "DEFENDER_EXCLUSIONS_MODE=add"
set "STORE_APPS_BACKGROUND_MODE=off"
set "HYPERVISOR_MODE=off"

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
set "GT_SELF=%~f0"
rem Loads the PowerShell section between the two marker lines at the end of
rem this file and runs the step named in GT_STEP.
set "GT_PSRUN=$t=[IO.File]::ReadAllText($env:GT_SELF);$m='#'+'GTPS';$i=$t.IndexOf($m);$j=$t.LastIndexOf($m);if($i -lt 0 -or $j -le $i){exit 3};& ([scriptblock]::Create($t.Substring($i,$j-$i)))"
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

rem ---- NVIDIA and AMD graphics: their driver settings get their own steps --
set "HAS_NV="
echo %GT_GPU%| findstr /i /c:"NVIDIA" >nul
if "%errorlevel%"=="0" set "HAS_NV=1"
set "HAS_AMD="
echo %GT_GPU%| findstr /i /c:"Radeon" /c:"AMD" >nul
if "%errorlevel%"=="0" set "HAS_AMD=1"

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
if /i "%HAGS_MODE%"=="on" echo   - Hardware-accelerated GPU scheduling: on
if /i "%HAGS_MODE%"=="off" echo   - Hardware-accelerated GPU scheduling: off, for an A/B test
if %GT_BUILD% GEQ 22621 echo   - Optimizations for windowed games: on
if /i "%VRR_MODE%"=="on" echo   - Variable refresh rate for games without their own support: on
if /i not "%AUTOHDR_MODE%"=="keep" if %GT_BUILD% GEQ 22000 echo   - Auto HDR: off
if /i "%REFRESH_MODE%"=="max" echo   - Monitors: highest refresh rate, kept only when you confirm it
if /i "%GPU_PREFERENCE_MODE%"=="auto" echo   - Installed games: high-performance GPU, on PCs with two GPUs
if defined HAS_NV if /i "%NVIDIA_MODE%"=="fix" echo   - NVIDIA settings that cost FPS or cause stutter: back to defaults
if defined HAS_AMD if /i "%AMD_MODE%"=="fix" echo   - AMD shader cache back on if it was off, Radeon Chill off
if /i "%SHADER_CACHE_MODE%"=="protect" echo   - DirectX shader cache: kept out of automatic disk cleanup
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
if /i "%STORE_APPS_BACKGROUND_MODE%"=="off" echo   - Store apps running in the background: off
if /i "%CPU_MITIGATIONS_MODE%"=="off" echo   - Spectre v2 and Meltdown mitigations: off, a security cost - see README.md
if /i "%DEFENDER_EXCLUSIONS_MODE%"=="add" echo   - Defender: game libraries and shader caches excluded from real-time scanning
if /i "%HYPERVISOR_MODE%"=="off" if not defined AC_NEEDVBS echo   - Hypervisor: off. WSL2, Hyper-V, Windows Sandbox and Docker stop working
echo   - Last: a list of hardware and setup problems only you can fix
echo.
echo  A restart is needed afterwards. README.md shows how to undo each change.
echo.
choice /c YN /n /m "  Apply these changes now? [Y/N] "
if errorlevel 2 goto :cancelled

set "STEPN=0"
set "STEPS=24"
call :step_vbs
call :step_gamebar
call :step_hags
call :step_windowed
call :step_vrr
call :step_autohdr
call :step_refresh
call :step_gpupref
call :step_nvidia
call :step_amd
call :step_shadercache
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
call :step_findings

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
if /i "%HAGS_MODE%"=="off" goto :hags_off
if /i not "%HAGS_MODE%"=="on" echo   [SKIP] HAGS_MODE must be on, off or keep.& exit /b 0
if "%V1%"=="2" echo   [ OK ] Already on.& exit /b 0
reg add "%GDK%" /v HwSchMode /t REG_DWORD /d 2 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write HwSchMode.& exit /b 0
if "%V1%"=="1" (echo   [ OK ] Was off - turned on.) else (echo   [ OK ] Turned on.)
echo          Unsupported GPUs and drivers simply keep the old scheduler.
exit /b 0

:hags_off
if "%V1%"=="1" echo   [ OK ] Already off.& exit /b 0
reg add "%GDK%" /v HwSchMode /t REG_DWORD /d 1 /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write HwSchMode.& exit /b 0
echo   [ OK ] Turned off. DLSS frame generation needs it on, and FSR 3 frame generation paces worse without it.
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


:step_vrr
rem Windows' variable refresh rate setting for games: DX11 games that do not
rem support VRR themselves then present in a way G-SYNC and FreeSync monitors
rem can follow. Without VRR, a frame rate below the refresh rate is shown
rem with judder or tearing. Only has an effect on a VRR monitor with G-SYNC
rem or FreeSync turned on in the graphics driver.
call :hdr "Variable refresh rate for games without their own support"
if /i "%VRR_MODE%"=="keep" echo   [SKIP] VRR_MODE is set to keep.& exit /b 0
if /i not "%VRR_MODE%"=="on" echo   [SKIP] VRR_MODE must be on or keep.& exit /b 0
call :dx_read
call :dx_get VRROptimizeEnable V1
if "%V1%"=="1" echo   [ OK ] Already on.& exit /b 0
call :dx_set VRROptimizeEnable 1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write DirectXUserGlobalSettings.& exit /b 0
echo   [ OK ] Turned on: DX11 games without VRR support can use G-SYNC or FreeSync too.
echo          It needs a VRR monitor with G-SYNC or FreeSync turned on in the NVIDIA or AMD software.
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


:step_refresh
rem Windows often leaves a new monitor at 60 Hz, and drivers can reset it
rem after a cable or driver change. A frame cap or V-Sync tied to the refresh
rem rate then holds games at 60 FPS, and each frame reaches the screen later.
rem The new rate is kept only when you confirm it within 15 seconds.
call :hdr "Monitor refresh rate"
if /i "%REFRESH_MODE%"=="keep" echo   [SKIP] REFRESH_MODE is set to keep.& exit /b 0
if /i not "%REFRESH_MODE%"=="max" echo   [SKIP] REFRESH_MODE must be max or keep.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
call :ps refresh
exit /b 0


:step_gpupref
rem On a PC with two GPUs, a game the graphics driver does not recognise can
rem start on the integrated GPU at a fraction of the frame rate. The
rem per-program choice in Windows graphics settings takes precedence over the
rem NVIDIA and AMD ones, so every installed game is set to the
rem high-performance GPU there. A program set to power saving is kept.
call :hdr "Installed games on the high-performance GPU"
if /i "%GPU_PREFERENCE_MODE%"=="keep" echo   [SKIP] GPU_PREFERENCE_MODE is set to keep.& exit /b 0
if /i not "%GPU_PREFERENCE_MODE%"=="auto" echo   [SKIP] GPU_PREFERENCE_MODE must be auto or keep.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
call :ps gpupref
exit /b 0


:step_nvidia
rem NVIDIA Control Panel settings in the global profile that old tweak guides
rem change and that cost FPS or cause stutter: shader cache off or smaller
rem than 4 GB, threaded optimization forced off, integrated graphics
rem preferred. Each goes back to NVIDIA's default; game profiles are kept.
call :hdr "NVIDIA driver settings"
if /i "%NVIDIA_MODE%"=="keep" echo   [SKIP] NVIDIA_MODE is set to keep.& exit /b 0
if /i not "%NVIDIA_MODE%"=="fix" echo   [SKIP] NVIDIA_MODE must be fix or keep.& exit /b 0
if not defined HAS_NV echo   [SKIP] No NVIDIA graphics card.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
call :ps nvidia
exit /b 0


:step_amd
rem AMD Software keeps its global graphics settings in the display adapter's
rem registry key. A shader cache turned off makes every game compile its
rem shaders again at each start, which stutters, so it goes back to the
rem default, AMD optimized. Nothing else in AMD Software is changed.
call :hdr "AMD driver settings"
if /i "%AMD_MODE%"=="keep" echo   [SKIP] AMD_MODE is set to keep.& exit /b 0
if /i not "%AMD_MODE%"=="fix" echo   [SKIP] AMD_MODE must be fix or keep.& exit /b 0
if not defined HAS_AMD echo   [SKIP] No AMD Radeon graphics.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
call :ps amd
exit /b 0


:step_shadercache
rem The DirectX shader cache holds compiled shaders, so games skip compiling
rem them at the next start. Windows' automatic cleanup, which runs when a
rem drive gets low on space, may delete it, and games then stutter again
rem while they recompile. The cleanup reads the Autorun value of each handler
rem in both the 64-bit and the 32-bit registry view; 0 in both leaves the
rem cache out of it. Disk Cleanup can still clear it by hand.
call :hdr "DirectX shader cache"
if /i "%SHADER_CACHE_MODE%"=="keep" echo   [SKIP] SHADER_CACHE_MODE is set to keep.& exit /b 0
if /i not "%SHADER_CACHE_MODE%"=="protect" echo   [SKIP] SHADER_CACHE_MODE must be protect or keep.& exit /b 0
set "SC_N=0"
set "SC_SET=0"
set "SC_FAIL="
for %%K in ("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\D3D Shader Cache" "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\D3D Shader Cache") do call :sc_key %%K
if "%SC_N%"=="0" echo   [SKIP] This Windows has no automatic cleanup for it.& exit /b 0
if defined SC_FAIL echo   [FAIL] Could not write the cleanup setting.& exit /b 0
if "%SC_SET%"=="0" echo   [ OK ] Already kept out of automatic disk cleanup.& exit /b 0
echo   [ OK ] Kept out of automatic disk cleanup: games keep their compiled shaders instead of
echo          compiling them again, with stutter, after Windows frees up space.
exit /b 0

:sc_key
rem sc_key "key" - sets Autorun to 0 for one cleanup handler, if it exists
reg query "%~1" >nul 2>&1
if not "%errorlevel%"=="0" exit /b 0
set /a SC_N+=1
call :getdw "%~1" Autorun V1
if "%V1%"=="0" exit /b 0
reg add "%~1" /v Autorun /t REG_DWORD /d 0 /f >nul 2>&1
if not "%errorlevel%"=="0" set "SC_FAIL=1"& exit /b 0
set /a SC_SET+=1
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
rem not worth that. Memory compression stays on: when memory runs short it is
rem faster than paging to disk, and benchmarks show no consistent gain from
rem turning it off. A disabled pagefile, left over from old tweak guides,
rem makes games crash or stutter when the commit limit runs out, so it is set
rem back to Windows-managed. A custom pagefile is kept.
call :hdr "Memory manager"
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
set "GT_PCW=0"
if %GT_RAMGB% GEQ 16 set "GT_PCW=1"
set "PC=" & set "PF="
set "Q=$ErrorActionPreference='SilentlyContinue';"
set "Q=%Q%$sm=(Get-Service SysMain).Status -eq 'Running';"
set "Q=%Q%if($sm){$a=Get-MMAgent};"
set "Q=%Q%if($env:GT_PCW -eq '1'){if(-not $sm){'PC=NOSYSMAIN'}elseif(-not $a){'PC=FAIL'}elseif(-not $a.PageCombining){'PC=ALREADY'}else{try{Disable-MMAgent -PageCombining -ErrorAction Stop;'PC=DONE'}catch{'PC=FAIL'}}};"
set "Q=%Q%$cs=Get-CimInstance Win32_ComputerSystem;"
set "Q=%Q%if(-not $cs){'PF=FAIL'}elseif($cs.AutomaticManagedPagefile){'PF=AUTO'}elseif(@(Get-CimInstance Win32_PageFileSetting).Count){'PF=CUSTOM'}else{try{Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -ErrorAction Stop;'PF=FIXED'}catch{'PF=FAIL'}}"
for /f "usebackq tokens=1,* delims==" %%A in (`%PS% -NoProfile -NonInteractive -Command "%Q%" 2^>nul ^| findstr /b /c:"PC=" /c:"PF="`) do set "%%A=%%B"
if "%GT_RAMGB%"=="0" echo   [SKIP] Page combining: installed RAM size unknown.& goto :mem_pagefile
if "%GT_PCW%"=="0" echo   [SKIP] Page combining: kept on, because it saves useful memory below 16 GB.
if "%PC%"=="DONE" echo   [ OK ] Page combining: turned off.
if "%PC%"=="ALREADY" echo   [ OK ] Page combining: already off.
if "%PC%"=="NOSYSMAIN" echo   [SKIP] Page combining: not active, because the SysMain service is not running.
if "%PC%"=="FAIL" echo   [FAIL] Page combining: could not change the setting.
if "%GT_PCW%"=="1" if not defined PC echo   [FAIL] Page combining: could not query the memory manager.
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
echo   [ OK ] Turned off: game helpers, shader compilers and games on a second monitor keep full clocks.
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
if /i not "%STORE_APPS_BACKGROUND_MODE%"=="off" echo   [SKIP] Store apps in the background: unchanged, STORE_APPS_BACKGROUND_MODE is set to keep.& exit /b 0
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
rem Microsoft's documented override for the Spectre v2 and Meltdown
rem mitigations. CPUs from 2019 on have hardware fixes and gain about 1
rem percent; older Intel CPUs lose around 4 percent in frametimes to them.
call :hdr "Spectre and Meltdown mitigations"
if /i not "%CPU_MITIGATIONS_MODE%"=="off" echo   [SKIP] CPU_MITIGATIONS_MODE is set to keep.& exit /b 0
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
rem Real-time scanning inspects every file a game opens and every
rem shader-cache file a driver writes, which lengthens loads and can stutter
rem asset streaming. Only launcher-defined libraries, the launchers' default
rem game folders and the GPU shader caches are excluded.
call :hdr "Microsoft Defender exclusions for games"
if /i not "%DEFENDER_EXCLUSIONS_MODE%"=="add" echo   [SKIP] DEFENDER_EXCLUSIONS_MODE is set to keep.& exit /b 0
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
rem Hyper-V, Virtual Machine Platform (WSL2), Sandbox and Docker
rem keep the hypervisor loaded even with VBS off, which costs about 1 percent
rem in CPU-bound games.
call :hdr "Hypervisor"
set "HV_FEAT="
for %%S in (vmms vmcompute) do (reg query "%SVC%\%%S" >nul 2>&1 & if not errorlevel 1 set "HV_FEAT=1")
if /i "%HYPERVISOR_MODE%"=="off" goto :hv_off
if not defined HV_FEAT echo   [ OK ] No Hyper-V or Virtual Machine Platform installed, so nothing keeps it loaded.& exit /b 0
bcdedit /enum {current} 2>nul | findstr /i /c:"hypervisorlaunchtype" | findstr /i /c:"Auto" >nul
if not "%errorlevel%"=="0" echo   [ OK ] The hypervisor is not set to load at boot.& exit /b 0
echo   [INFO] Hyper-V / Virtual Machine Platform keeps the hypervisor running, about 1%% in CPU-bound games.
echo          Kept, because HYPERVISOR_MODE is set to keep.
exit /b 0
:hv_off
if defined AC_NEEDVBS if /i not "%VBS_MODE%"=="disable" echo   [SKIP] %GT_AC% needs VBS, and VBS needs the hypervisor.& exit /b 0
bcdedit /set {current} hypervisorlaunchtype off >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not change the boot configuration.& exit /b 0
echo   [ OK ] The hypervisor no longer loads after a restart.
echo   [WARN] WSL2, Hyper-V, Windows Sandbox and Docker stop working until you run:
echo          bcdedit /set hypervisorlaunchtype auto
exit /b 0


:step_findings
rem Problems that cost FPS or 1 percent lows and that no script can fix:
rem BIOS settings, memory slots, cables, drives and running software.
call :hdr "Hardware and setup: what only you can change"
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
call :ps findings
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

:ps
rem ps step - runs one step of the PowerShell section at the end of this file
set "GT_STEP=%~1"
"%PS%" -NoProfile -NonInteractive -Command "%GT_PSRUN%"
if "%errorlevel%"=="3" echo   [FAIL] The PowerShell section of this file is missing or damaged.
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

rem ==========================================================================
rem  PowerShell section. Everything below runs only through the ps helper.
rem ==========================================================================
#GTPS
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$t)  { [Console]::Out.WriteLine($t) }
function Ok([string]$t)   { Say ('  [ OK ] ' + $t) }
function Skip([string]$t) { Say ('  [SKIP] ' + $t) }
function Info([string]$t) { Say ('  [INFO] ' + $t) }
function Warn([string]$t) { Say ('  [WARN] ' + $t) }
function Fail([string]$t) { Say ('  [FAIL] ' + $t) }
function More([string]$t) { Say ('         ' + $t) }

# ---- Native code -----------------------------------------------------------
# Monitor modes, graphics adapters and NVIDIA driver settings are reached
# through Windows and driver APIs; this C# is compiled when a step needs it.
$script:NativeCs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace GameTune
{
    public sealed class DisplayInfo
    {
        public string Device;
        public string Adapter;
        public bool Primary;
        public int Width;
        public int Height;
        public int Bits;
        public int Hz;
        public int MaxHz;
        public string MonitorPath;
    }

    // Monitors attached to the desktop, the GPU that drives each one, and the
    // highest refresh rate each offers at its current resolution and colour
    // depth (interlaced modes left out). Apply switches the refresh rate.
    public static class Displays
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DisplayDevice
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DevMode
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public ushort dmSpecVersion;
            public ushort dmDriverVersion;
            public ushort dmSize;
            public ushort dmDriverExtra;
            public uint dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public uint dmDisplayOrientation;
            public uint dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public ushort dmLogPixels;
            public uint dmBitsPerPel;
            public uint dmPelsWidth;
            public uint dmPelsHeight;
            public uint dmDisplayFlags;
            public uint dmDisplayFrequency;
            public uint dmICMMethod;
            public uint dmICMIntent;
            public uint dmMediaType;
            public uint dmDitherType;
            public uint dmReserved1;
            public uint dmReserved2;
            public uint dmPanningWidth;
            public uint dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevicesW(string device, uint index, ref DisplayDevice dd, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplaySettingsW(string device, int mode, ref DevMode dm);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int ChangeDisplaySettingsExW(string device, ref DevMode dm, IntPtr hwnd, uint flags, IntPtr param);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")]
        static extern int ChangeDisplaySettingsToSaved(string device, IntPtr dm, IntPtr hwnd, uint flags, IntPtr param);

        const uint Interlaced = 2;
        const uint CdsUpdateRegistry = 1;
        const uint CdsTest = 2;
        const uint CdsNoReset = 0x10000000;
        // DM_BITSPERPEL | DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY
        const uint ModeFields = 0x00040000 | 0x00080000 | 0x00100000 | 0x00400000;

        static DevMode NewMode()
        {
            DevMode m = new DevMode();
            m.dmSize = (ushort)Marshal.SizeOf(typeof(DevMode));
            return m;
        }

        static bool Same(DevMode a, DevMode b)
        {
            return a.dmPelsWidth == b.dmPelsWidth && a.dmPelsHeight == b.dmPelsHeight && a.dmBitsPerPel == b.dmBitsPerPel;
        }

        public static DisplayInfo[] List()
        {
            List<DisplayInfo> list = new List<DisplayInfo>();
            try
            {
                for (uint i = 0; i < 32; i++)
                {
                    DisplayDevice dd = new DisplayDevice();
                    dd.cb = Marshal.SizeOf(typeof(DisplayDevice));
                    if (!EnumDisplayDevicesW(null, i, ref dd, 0)) break;
                    if ((dd.StateFlags & 1) == 0) continue;
                    DevMode cur = NewMode();
                    if (!EnumDisplaySettingsW(dd.DeviceName, -1, ref cur)) continue;
                    DisplayInfo d = new DisplayInfo();
                    d.Device = dd.DeviceName;
                    d.Adapter = (dd.DeviceString ?? "").Trim();
                    d.Primary = (dd.StateFlags & 4) != 0;
                    d.Width = (int)cur.dmPelsWidth;
                    d.Height = (int)cur.dmPelsHeight;
                    d.Bits = (int)cur.dmBitsPerPel;
                    d.Hz = (int)cur.dmDisplayFrequency;
                    d.MaxHz = d.Hz;
                    // The monitor on this output; with EDD_GET_DEVICE_INTERFACE_NAME its
                    // DeviceID is the interface path, which names the monitor's device
                    // instance and with it the registry key that holds its EDID.
                    DisplayDevice mon = new DisplayDevice();
                    mon.cb = Marshal.SizeOf(typeof(DisplayDevice));
                    d.MonitorPath = EnumDisplayDevicesW(dd.DeviceName, 0, ref mon, 1) ? (mon.DeviceID ?? "") : "";
                    for (int m = 0; m < 4096; m++)
                    {
                        DevMode dm = NewMode();
                        if (!EnumDisplaySettingsW(dd.DeviceName, m, ref dm)) break;
                        if (Same(dm, cur) && (dm.dmDisplayFlags & Interlaced) == 0 && (int)dm.dmDisplayFrequency > d.MaxHz)
                            d.MaxHz = (int)dm.dmDisplayFrequency;
                    }
                    list.Add(d);
                }
            }
            catch (Exception) { }
            return list.ToArray();
        }

        // Sets a monitor to hz at its current resolution and colour depth.
        // mode 0 = only ask the driver whether the mode would work; 1 = switch
        // for this session only, so a restart or Reset undoes it; 2 = save the
        // mode, already active, as the one Windows uses from now on. Returns
        // the DISP_CHANGE code (0 = done, 1 = needs a restart), -100 when there
        // is no such mode, -101 when the monitor cannot be read.
        public static int Apply(string device, int hz, int mode)
        {
            try
            {
                DevMode cur = NewMode();
                if (!EnumDisplaySettingsW(device, -1, ref cur)) return -101;
                for (int m = 0; m < 4096; m++)
                {
                    DevMode dm = NewMode();
                    if (!EnumDisplaySettingsW(device, m, ref dm)) break;
                    if (!Same(dm, cur) || (dm.dmDisplayFlags & Interlaced) != 0 || (int)dm.dmDisplayFrequency != hz) continue;
                    dm.dmFields = ModeFields;
                    uint flags = mode == 0 ? CdsTest : mode == 1 ? 0u : CdsUpdateRegistry | CdsNoReset;
                    return ChangeDisplaySettingsExW(device, ref dm, IntPtr.Zero, flags, IntPtr.Zero);
                }
                return -100;
            }
            catch (Exception) { return -101; }
        }

        // Back to the mode saved for the monitor, undoing a session-only switch.
        public static int Reset(string device)
        {
            try { return ChangeDisplaySettingsToSaved(device, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero); }
            catch (Exception) { return -101; }
        }
    }

    public sealed class GpuInfo
    {
        public string Name;
        public uint Vendor;
        public ulong Vram;
        public bool Software;
        public long Luid;
    }

    // Graphics adapters through DXGI. List gives them in the order games see
    // them; ByPreference in the order Windows ranks them for a preference
    // (1 = power saving, 2 = high performance), the same ranking that the
    // "Power saving" and "High performance" choices in Windows graphics
    // settings use. ByPreference is empty where DXGI 1.6 is missing.
    public static class Dxgi
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct Desc1
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
            public uint VendorId;
            public uint DeviceId;
            public uint SubSysId;
            public uint Revision;
            public UIntPtr DedicatedVideoMemory;
            public UIntPtr DedicatedSystemMemory;
            public UIntPtr SharedSystemMemory;
            public uint LuidLow;
            public int LuidHigh;
            public uint Flags;
        }

        // Methods before the ones used are placeholders that keep the
        // vtable order of dxgi.h and dxgi1_6.h.
        [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IDXGIAdapter1
        {
            void SetPrivateData();
            void SetPrivateDataInterface();
            void GetPrivateData();
            void GetParent();
            void EnumOutputs();
            void GetDesc();
            void CheckInterfaceSupport();
            [PreserveSig] int GetDesc1(out Desc1 desc);
        }

        [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IDXGIFactory1
        {
            void SetPrivateData();
            void SetPrivateDataInterface();
            void GetPrivateData();
            void GetParent();
            void EnumAdapters();
            void MakeWindowAssociation();
            void GetWindowAssociation();
            void CreateSwapChain();
            void CreateSoftwareAdapter();
            [PreserveSig] int EnumAdapters1(uint index, out IDXGIAdapter1 adapter);
        }

        [ComImport, Guid("c1b6694f-ff09-44a9-b03c-77900a0a1d17"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IDXGIFactory6
        {
            void SetPrivateData();
            void SetPrivateDataInterface();
            void GetPrivateData();
            void GetParent();
            void EnumAdapters();
            void MakeWindowAssociation();
            void GetWindowAssociation();
            void CreateSwapChain();
            void CreateSoftwareAdapter();
            void EnumAdapters1();
            void IsCurrent();
            void IsWindowedStereoEnabled();
            void CreateSwapChainForHwnd();
            void CreateSwapChainForCoreWindow();
            void GetSharedResourceAdapterLuid();
            void RegisterStereoStatusWindow();
            void RegisterStereoStatusEvent();
            void UnregisterStereoStatus();
            void RegisterOcclusionStatusWindow();
            void RegisterOcclusionStatusEvent();
            void UnregisterOcclusionStatus();
            void CreateSwapChainForComposition();
            void GetCreationFlags();
            void EnumAdapterByLuid();
            void EnumWarpAdapter();
            void CheckFeatureSupport();
            [PreserveSig] int EnumAdapterByGpuPreference(uint index, uint preference, [In] ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IDXGIAdapter1 adapter);
        }

        [DllImport("dxgi.dll")]
        static extern int CreateDXGIFactory1([In] ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object factory);

        static readonly Guid FactoryId = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
        static readonly Guid AdapterId = new Guid("29038f61-3839-4626-91fd-086879011a05");

        static GpuInfo Describe(IDXGIAdapter1 a)
        {
            Desc1 d;
            if (a.GetDesc1(out d) != 0) return null;
            GpuInfo g = new GpuInfo();
            g.Name = (d.Description ?? "").Trim();
            g.Vendor = d.VendorId;
            g.Vram = d.DedicatedVideoMemory.ToUInt64();
            g.Software = (d.Flags & 2) != 0;
            g.Luid = ((long)d.LuidHigh << 32) | d.LuidLow;
            return g;
        }

        static object Factory()
        {
            Guid iid = FactoryId;
            object f;
            if (CreateDXGIFactory1(ref iid, out f) != 0) return null;
            return f;
        }

        public static GpuInfo[] List()
        {
            List<GpuInfo> list = new List<GpuInfo>();
            object o = null;
            try
            {
                o = Factory();
                IDXGIFactory1 f = o as IDXGIFactory1;
                if (f == null) return list.ToArray();
                for (uint i = 0; i < 16; i++)
                {
                    IDXGIAdapter1 a;
                    if (f.EnumAdapters1(i, out a) != 0 || a == null) break;
                    GpuInfo g = Describe(a);
                    if (g != null) list.Add(g);
                    Marshal.ReleaseComObject(a);
                }
            }
            catch (Exception) { }
            finally { if (o != null) Marshal.ReleaseComObject(o); }
            return list.ToArray();
        }

        public static GpuInfo[] ByPreference(uint preference)
        {
            List<GpuInfo> list = new List<GpuInfo>();
            object o = null;
            try
            {
                o = Factory();
                IDXGIFactory6 f = o as IDXGIFactory6;
                if (f == null) return list.ToArray();
                Guid iid = AdapterId;
                for (uint i = 0; i < 16; i++)
                {
                    IDXGIAdapter1 a;
                    if (f.EnumAdapterByGpuPreference(i, preference, ref iid, out a) != 0 || a == null) break;
                    GpuInfo g = Describe(a);
                    if (g != null) list.Add(g);
                    Marshal.ReleaseComObject(a);
                }
            }
            catch (Exception) { }
            finally { if (o != null) Marshal.ReleaseComObject(o); }
            return list.ToArray();
        }
    }

    public sealed class NvSetting
    {
        public int Status;
        public bool Found;
        public bool Predefined;
        public int Location;
        public uint Value;
    }

    // NVIDIA driver settings (the NVIDIA Control Panel's global profile)
    // through NVAPI's DRS functions. IDs and layout from NVIDIA's NVAPI SDK:
    // NVDRS_SETTING_V1 is 12320 bytes, packed to 4, version 0x13020; the
    // location is at offset 4108, isCurrentPredefined at 4112 and the DWORD
    // current value at 8220.
    public sealed class Nv
    {
        [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr Query64(uint id);
        [DllImport("nvapi.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
        static extern IntPtr Query32(uint id);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NoArgs();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int OutHandle(out IntPtr handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int WithSession(IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SessionOutHandle(IntPtr session, out IntPtr handle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetSettingFn(IntPtr session, IntPtr profile, uint id, IntPtr setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ProfileSettingFn(IntPtr session, IntPtr profile, uint id);

        const int SettingSize = 12320;
        const int SettingVersion = SettingSize | (1 << 16);
        IntPtr session = IntPtr.Zero;
        IntPtr profile = IntPtr.Zero;

        static T Fn<T>(uint id) where T : class
        {
            IntPtr p = IntPtr.Size == 8 ? Query64(id) : Query32(id);
            if (p == IntPtr.Zero) return null;
            return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
        }

        // 0 = ready; otherwise an NVAPI status, or -1000 when NVAPI is missing.
        public int Open()
        {
            try
            {
                NoArgs init = Fn<NoArgs>(0x0150E828);
                OutHandle create = Fn<OutHandle>(0x0694D52E);
                WithSession load = Fn<WithSession>(0x375DBD6B);
                SessionOutHandle global = Fn<SessionOutHandle>(0x617BFF9F);
                if (init == null || create == null || load == null || global == null) return -1000;
                int rc = init();
                if (rc != 0) return rc;
                rc = create(out session);
                if (rc != 0) return rc;
                rc = load(session);
                if (rc != 0) return rc;
                return global(session, out profile);
            }
            catch (Exception) { return -1000; }
        }

        public NvSetting Read(uint id)
        {
            NvSetting s = new NvSetting();
            IntPtr buf = Marshal.AllocHGlobal(SettingSize);
            try
            {
                Marshal.Copy(new byte[SettingSize], 0, buf, SettingSize);
                Marshal.WriteInt32(buf, 0, SettingVersion);
                GetSettingFn get = Fn<GetSettingFn>(0x73BF8338);
                s.Status = get == null ? -1000 : get(session, profile, id, buf);
                if (s.Status == 0)
                {
                    s.Found = true;
                    s.Location = Marshal.ReadInt32(buf, 4108);
                    s.Predefined = Marshal.ReadInt32(buf, 4112) != 0;
                    s.Value = (uint)Marshal.ReadInt32(buf, 8220);
                }
            }
            catch (Exception) { s.Status = -1000; }
            finally { Marshal.FreeHGlobal(buf); }
            return s;
        }

        // Puts a setting of the global profile back to NVIDIA's default.
        public int Restore(uint id)
        {
            try
            {
                ProfileSettingFn restore = Fn<ProfileSettingFn>(0x53F0381E);
                return restore == null ? -1000 : restore(session, profile, id);
            }
            catch (Exception) { return -1000; }
        }

        public int Save()
        {
            try
            {
                WithSession save = Fn<WithSession>(0xFCBC7E14);
                return save == null ? -1000 : save(session);
            }
            catch (Exception) { return -1000; }
        }

        public void Close()
        {
            try
            {
                if (session != IntPtr.Zero)
                {
                    WithSession destroy = Fn<WithSession>(0xDAD9CFF8);
                    if (destroy != null) destroy(session);
                }
            }
            catch (Exception) { }
            session = IntPtr.Zero;
        }
    }
}
'@

function Import-Native {
    if ('GameTune.Displays' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $script:NativeCs -Language CSharp -IgnoreWarnings -WarningAction SilentlyContinue -ErrorAction Stop
        return $true
    } catch {
        Fail ('The code for this step could not be compiled: ' + ([string]$_.Exception.Message).Split("`n")[0].Trim())
        return $false
    }
}

# ---- Helpers ---------------------------------------------------------------
# A registry value; the comma keeps binary values in one piece.
function Get-Reg([string]$key, [string]$name) {
    $p = Get-ItemProperty -LiteralPath $key -Name $name
    if ($p) { ,$p.$name }
}

# The signed-in user's registry hive, also when GameTune was elevated with a
# different administrator account. GT_USERSID comes from the batch code.
function Get-UserSid {
    $sid = [string]$env:GT_USERSID
    if ($sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $sid))) { return $sid }
    ''
}
function Get-UserPath {
    $sid = Get-UserSid
    if ($sid) { return ('Registry::HKEY_USERS\' + $sid) }
    'HKCU:'
}
# Opens a key of the signed-in user through .NET, which, unlike the registry
# cmdlets, takes value names with wildcard characters such as [ ] literally.
function Open-UserKey([string]$sub, [bool]$write) {
    $sid = Get-UserSid
    $root = [Microsoft.Win32.Registry]::CurrentUser
    $path = $sub
    if ($sid) { $root = [Microsoft.Win32.Registry]::Users; $path = $sid + '\' + $sub }
    try {
        if ($write) { return $root.CreateSubKey($path) }
        return $root.OpenSubKey($path)
    } catch { return $null }
}
# A key under HKLM through .NET, which reads and writes values with their
# types as they are.
function Open-MachineKey([string]$sub, [bool]$write) {
    try { return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($sub, $write) } catch { return $null }
}

# The adapter keys of the display class, where graphics drivers keep their
# global settings: one subkey per adapter, named 0000, 0001 and so on.
$script:DisplayClass = 'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
function Get-DisplayAdapterKeys {
    $root = Open-MachineKey $script:DisplayClass $false
    if (-not $root) { return @() }
    $names = @($root.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' })
    $root.Close()
    foreach ($n in $names) {
        $k = Open-MachineKey ($script:DisplayClass + '\' + $n) $false
        if (-not $k) { continue }
        [pscustomobject]@{
            Path     = $script:DisplayClass + '\' + $n
            Provider = [string]$k.GetValue('ProviderName', '')
            Name     = ([string]$k.GetValue('DriverDesc', '')).Trim()
            Chill    = $k.GetValue('KMD_ChillEnabled', $null)
        }
        $k.Close()
    }
}

# The NVIDIA driver branch, such as 591 for driver 591.86, from the Windows
# driver version (32.0.15.9186); 0 when unknown.
function Get-NvidiaBranch {
    $vc = @(Get-CimInstance Win32_VideoController | Where-Object { [string]$_.Name -match 'NVIDIA' })[0]
    $p = ([string]$vc.DriverVersion).Split('.')
    if ($p.Count -lt 4 -or $p[2] -notmatch '^\d+$' -or $p[3] -notmatch '^\d+$') { return 0 }
    # The last digit of the third field and the fourth field, padded to four
    # digits because Windows drops its leading zeros (600.12 is 32.0.16.12).
    [int](($p[2].Substring($p[2].Length - 1) + $p[3].PadLeft(4, '0')).Substring(0, 3))
}

function Format-MB([double]$mb) {
    if ($mb -lt 1024) { return ([string][int]$mb + ' MB') }
    '{0:0.#} GB' -f ($mb / 1024)
}

# The signed-in user's profile folder.
function Get-UserProfile {
    $sid = Get-UserSid
    if ($sid) {
        $p = [string](Get-CimInstance Win32_UserProfile -Filter ("SID='" + $sid + "'")).LocalPath
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    $env:USERPROFILE
}

# Laptop or desktop, from the chassis type; the battery only decides when the
# chassis type says neither.
function Test-Laptop {
    $types = @(Get-CimInstance Win32_SystemEnclosure | ForEach-Object { $_.ChassisTypes } | ForEach-Object { [int]$_ })
    foreach ($c in $types) { if (@(8, 9, 10, 11, 14, 30, 31, 32) -contains $c) { return $true } }
    foreach ($c in $types) { if (@(3, 4, 5, 6, 7, 13, 15, 16, 24, 35, 36) -contains $c) { return $false } }
    [bool](Get-CimInstance Win32_Battery)
}

# The graphics adapters, ranked by Windows for high performance and for power
# saving. Two different first entries mean a PC with two GPUs, the same choice
# Windows graphics settings offer.
function Get-GpuRanking {
    $hp = @([GameTune.Dxgi]::ByPreference(2) | Where-Object { -not $_.Software })
    $mp = @([GameTune.Dxgi]::ByPreference(1) | Where-Object { -not $_.Software })
    $two = $hp.Count -ge 2 -and $mp.Count -ge 1 -and $hp[0].Luid -ne $mp[0].Luid
    [pscustomobject]@{
        Ranked = [bool]$hp.Count
        Two    = $two
        Fast   = $(if ($hp.Count) { $hp[0] } else { $null })
        Saving = $(if ($two) { $mp[0] } else { $null })
    }
}

# Name and highest vertical refresh rate a monitor reports in its EDID. The
# interface path names the monitor's device instance, whose registry key
# holds the EDID. MaxHz comes from the Display Range Limits descriptor (tag
# 0xFD); bit 1 of its byte 4 adds 255 Hz for monitors above 255 Hz.
function Read-MonitorEdid([string]$path) {
    $r = [pscustomobject]@{ Name = ''; MaxHz = 0; MaxClockMHz = 0 }
    if ($path -notmatch '^\\\\\?\\DISPLAY#([^#]+)#([^#]+)#') { return $r }
    $b = Get-Reg ('HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\' + $Matches[1] + '\' + $Matches[2] + '\Device Parameters') 'EDID'
    if ($b -isnot [byte[]] -or $b.Count -lt 128) { return $r }
    for ($o = 54; $o -le 108; $o += 18) {
        if ($b[$o] -ne 0 -or $b[$o + 1] -ne 0 -or $b[$o + 2] -ne 0) { continue }
        if ($b[$o + 3] -eq 0xFC) {
            $n = ''
            for ($k = $o + 5; $k -lt $o + 18 -and $b[$k] -ne 0x0A; $k++) { if ($b[$k] -ge 32 -and $b[$k] -lt 127) { $n += [char]$b[$k] } }
            $r.Name = $n.Trim()
        } elseif ($b[$o + 3] -eq 0xFD) {
            $max = [int]$b[$o + 6]
            if ($b[$o + 4] -band 2) { $max += 255 }
            $r.MaxHz = $max
            if ($b[$o + 9] -gt 0 -and $b[$o + 9] -lt 255) { $r.MaxClockMHz = 10 * [int]$b[$o + 9] }
        }
    }
    $r
}

# The highest refresh rate the monitor's EDID allows at a resolution: its
# maximum vertical rate, limited by its maximum pixel clock with reduced
# blanking (160 pixels per line, about 5 percent of the lines). A monitor
# whose high rate exists only at lower resolutions then counts as 60 Hz.
function Get-EdidHzAt($e, [int]$w, [int]$h) {
    if ($e.MaxHz -le 0) { return 0 }
    if ($e.MaxClockMHz -le 0 -or $w -le 0 -or $h -le 0) { return $e.MaxHz }
    [int][Math]::Min($e.MaxHz, [Math]::Floor($e.MaxClockMHz * 1e6 / (($w + 160) * $h * 1.05)))
}

# Waits up to $sec seconds for Y or N and answers No when time runs out,
# for changes that must undo themselves when nobody can see the screen.
# It prints nothing, so a console paused by a text selection cannot hold up
# the undo. Keys pressed before the question are discarded; without a
# console to read from, the answer is No.
function Wait-Yes([int]$sec) {
    try {
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        $end = [DateTime]::UtcNow.AddSeconds($sec)
        while ([DateTime]::UtcNow -lt $end) {
            if ([Console]::KeyAvailable) {
                $k = [string][Console]::ReadKey($true).KeyChar
                if ($k -eq 'y') { return $true }
                if ($k -eq 'n') { return $false }
            }
            Start-Sleep -Milliseconds 100
        }
    } catch { }
    $false
}

# Memory channel from the firmware's slot labels: "ChannelA-DIMM0",
# "P0 CHANNEL A", "DIMM_A1", "DDR5_A1" and similar. $null when unlabelled.
function Get-Channel($m) {
    $s = ([string]$m.BankLabel + ' ' + [string]$m.DeviceLocator).ToUpper()
    if ($s -match 'CHANNEL\s*([A-H])') { return $Matches[1] }
    if ($s -match 'DIMM[_ ]?([A-H])[0-9]') { return $Matches[1] }
    if ($s -match '(?:^|[^A-Z0-9])([A-H])[0-9](?:[^0-9]|$)') { return $Matches[1] }
    $null
}

function Convert-SpeedCode([int]$c) {
    switch ($c) { 21 { 2133 } 26 { 2666 } 29 { 2933 } 34 { 3466 } 37 { 3733 } default { $c * 100 } }
}

# The speed a memory kit is sold for, from its part number (G.Skill, Corsair,
# Kingston FURY and HyperX, Crucial, TeamGroup, Patriot, ADATA and others).
# 0 when the part number does not say, as with standard JEDEC modules.
function Get-RatedSpeed([string]$pn) {
    $p = $pn.Trim().ToUpper()
    if (-not $p) { return 0 }
    if ($p -match '^(KF|HX)[45](\d\d)C') { return (Convert-SpeedCode ([int]$Matches[2])) }
    if ($p -match '^BL\d*(?:K\d+)?\d+G(\d\d)C') { return (Convert-SpeedCode ([int]$Matches[1])) }
    if ($p -match '^CP\d+G(\d\d)C') { return (Convert-SpeedCode ([int]$Matches[1])) }
    if ($p -match '^PV\w\d{3}G(\d{3})C') { return [int]$Matches[1] * 10 }
    if ($p -match '^AX[45]U(\d{4})') { return [int]$Matches[1] }
    if ($p -match '(?<!\d)(2133|2400|2666|2933|3000|3200|3333|3466|3600|3733|3800|3866|4000|4133|4266|4400|4600|4800|5200|5600|6000|6200|6400|6600|6800|7000|7200|7600|8000|8200|8400)(?!\d)') { return [int]$Matches[1] }
    0
}

# HDD, SSD or NVMe SSD for the disk that holds a folder; '' when unknown.
function Get-DriveKind([string]$path) {
    if ($path -notmatch '^([A-Za-z]):') { return '' }
    $part = @(Get-Partition -DriveLetter $Matches[1])[0]
    if (-not $part) { return '' }
    $pd = @(Get-PhysicalDisk | Where-Object { [string]$_.DeviceId -eq [string]$part.DiskNumber })[0]
    if (-not $pd) { return '' }
    $mt = [string]$pd.MediaType
    $bus = [string]$pd.BusType
    if ($mt -eq 'HDD') { return 'hard drive' }
    if ($bus -eq 'NVMe') { return 'NVMe SSD' }
    if ($mt -eq 'SSD' -and $bus -eq 'USB') { return 'SSD over USB' }
    if ($mt -eq 'SSD') { return 'SSD' }
    if ($bus -eq 'USB') { return 'USB drive' }
    ''
}

# ---- Installed games -------------------------------------------------------
# Programs in game folders that never render the game: installers, runtimes,
# crash reporters, anti-cheat services, launchers, updaters and web helpers.
$script:SkipExe = '^(unins.*|.*setup.*|.*install.*|vc_?redist.*|dxwebsetup|dotnet.*|ndp\d.*|oalinst|physx.*|.*prereq.*|.*crash.*|.*report.*|bugsplat.*|sentry.*|easyanticheat.*|start_protected_game|beservice.*|battleye.*|.*launcher.*|.*updater.*|.*update.*|.*patcher.*|.*helper.*|cef.*|.*webview.*|qtwebengineprocess|7z.*|jar|jarsigner|javac|javadoc|javap|jcmd|jconsole|jdb|jdeps|jfr|jhsdb|jimage|jinfo|jlink|jmap|jmod|jpackage|jps|jrunscript|jshell|jstack|jstat|jstatd|jwebserver|keytool|kinit|klist|ktab|orbd|pack200|unpack200|policytool|rmic|rmid|rmiregistry|serialver|servertool|tnameserv|jabswitch|jaccess.*|obs32|obs64|wallpaper32|wallpaper64|losslessscaling|vrserver|vrcompositor|vrmonitor|steam|steamservice|battle\.net|wgc|hyp|riotclientservices|riotclientux|eadesktop|eabackgroundservice|origin|galaxyclient|upc|chrome|msedge|firefox|opera|brave|discord|spotify)\.exe$'
$script:SkipDir = '^(_commonredist|commonredist|redist|redists|redistributable|redistributables|directx|dxsetup|prerequisites|prereq|prereqs|__installer|_installer|installer|installers|support|easyanticheat|easyanticheat_eos|battleye|vcredist|dotnetfx|physx|thirdparty|extras|crashreportclient|crashpad|uninstall)$'
# Steam tools that must keep the GPU they run on: Steamworks redistributables,
# Wallpaper Engine, Lossless Scaling, SteamVR and OBS Studio.
$script:SkipApp = @('228980', '431960', '993090', '250820', '1905180')

# Program files in a game folder, down to 4 folders deep (Unreal Engine games
# keep theirs in <Game>\Binaries\Win64), without following links. A folder
# with more than 24 of them keeps the 24 largest.
function Get-FolderExes([string]$root, [System.Diagnostics.Stopwatch]$clock) {
    $found = New-Object 'System.Collections.Generic.List[IO.FileInfo]'
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue(@($root, 0))
    while ($queue.Count -and $clock.Elapsed.TotalSeconds -lt 90) {
        $item = $queue.Dequeue()
        $dir = New-Object IO.DirectoryInfo ([string]$item[0])
        try {
            foreach ($f in $dir.GetFiles('*.exe')) { if ($f.Extension -eq '.exe' -and $f.Name -notmatch $script:SkipExe) { $found.Add($f) } }
            if ([int]$item[1] -ge 4) { continue }
            foreach ($d in $dir.GetDirectories()) {
                if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($d.Name -match $script:SkipDir) { continue }
                $queue.Enqueue(@($d.FullName, ([int]$item[1] + 1)))
            }
        } catch { }
    }
    @($found | Sort-Object Length -Descending | Select-Object -First 24 | ForEach-Object { $_.FullName })
}

# Every installed game's program files, from the Steam, Epic, GOG, Ubisoft,
# EA, Battle.net, Riot and Rockstar records, Minecraft: Java Edition's Java,
# and the programs Windows itself has recognised as games.
function Find-Games {
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $games = New-Object 'System.Collections.Generic.List[object]'
    $seenDir = @{}
    $addDir = {
        param([string]$name, [string]$dir, [string[]]$extra)
        if (-not $dir) { return }
        $dir = $dir.Trim().Trim('"').Replace([IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($dir -match '^[A-Za-z]:$' -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return }
        $k = $dir.ToLower()
        if ($seenDir.ContainsKey($k)) { return }
        $seenDir[$k] = 1
        $exes = @(Get-FolderExes $dir $clock)
        foreach ($x in $extra) {
            if (-not $x -or -not (Test-Path -LiteralPath $x -PathType Leaf)) { continue }
            # Full path with the system's separators: Epic writes forward slashes.
            $x = [IO.Path]::GetFullPath($x)
            if ((Split-Path -Leaf $x) -notmatch $script:SkipExe) { $exes += $x }
        }
        $exes = @($exes | Sort-Object -Unique)
        if ($exes.Count) { $games.Add([pscustomobject]@{ Name = $(if ($name) { $name } else { Split-Path -Leaf $dir }); Exes = $exes }) }
    }
    $user = Get-UserPath
    # Steam: every library, and each game's folder from its app manifest.
    $steam = [string](Get-Reg ($user + '\Software\Valve\Steam') 'SteamPath')
    if (-not $steam) { $steam = [string](Get-Reg 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath') }
    if ($steam) {
        $steam = $steam.Replace([IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar)
        $libs = @($steam)
        $vdf = [IO.Path]::Combine($steam, 'steamapps', 'libraryfolders.vdf')
        if (Test-Path -LiteralPath $vdf) {
            foreach ($l in [IO.File]::ReadAllLines($vdf)) { if ($l -match '"path"\s+"([^"]+)"') { $libs += ($Matches[1] -replace '\\\\', '\') } }
        }
        foreach ($lib in @($libs | Sort-Object -Unique)) {
            $apps = Join-Path $lib 'steamapps'
            foreach ($m in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf')) {
                $t = ''
                try { $t = [IO.File]::ReadAllText($m.FullName) } catch { }
                if ($t -notmatch '"installdir"\s+"([^"]+)"') { continue }
                $dir = [IO.Path]::Combine($apps, 'common', $Matches[1])
                $id = if ($t -match '"appid"\s+"(\d+)"') { $Matches[1] } else { '' }
                if ($script:SkipApp -contains $id) { continue }
                $name = if ($t -match '"name"\s+"([^"]+)"') { $Matches[1] } else { '' }
                & $addDir $name $dir @()
            }
        }
    }
    # Epic Games Launcher manifests, without Unreal Engine installs.
    $epic = [IO.Path]::Combine([string]$env:ProgramData, 'Epic', 'EpicGamesLauncher', 'Data', 'Manifests')
    foreach ($f in @(if (Test-Path -LiteralPath $epic) { Get-ChildItem -LiteralPath $epic -Filter '*.item' })) {
        $j = $null
        try { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { }
        if (-not $j -or -not $j.InstallLocation -or $j.bIsIncompleteInstall) { continue }
        if ([string]$j.DisplayName -match 'Unreal Engine' -or @($j.AppCategories) -contains 'engines') { continue }
        $exe = if ($j.LaunchExecutable) { [IO.Path]::Combine([string]$j.InstallLocation, [string]$j.LaunchExecutable) } else { '' }
        & $addDir ([string]$j.DisplayName) ([string]$j.InstallLocation) @($exe)
    }
    # GOG Galaxy and Ubisoft Connect record their games in HKLM.
    foreach ($k in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games')) {
        $p = Get-ItemProperty -LiteralPath $k.PSPath
        & $addDir ([string]$p.gameName) ([string]$p.path) @([string]$p.exe)
    }
    foreach ($k in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs')) {
        & $addDir '' ([string](Get-ItemProperty -LiteralPath $k.PSPath).InstallDir) @()
    }
    # EA, Battle.net, Riot, Rockstar and other publishers register their games
    # as installed programs; their launchers and anti-cheats are left out.
    $pub = '^(Electronic Arts|EA Games|Blizzard Entertainment|Activision|Riot Games|Rockstar Games|Ubisoft|Bethesda|Square Enix|BANDAI NAMCO|CAPCOM|SEGA|Warner Bros|2K|Embark Studios|Bungie|Grinding Gear Games|miHoYo|COGNOSPHERE|HoYoverse|Wargaming|Mojang)'
    $notGame = 'Launcher|Social Club|Battle\.net|EA app|^Origin|Riot Client|Vanguard|Ubisoft Connect|Uplay|Anti-?Cheat|Redistributable|Runtime|Driver|Overlay|Updater|Prerequisite'
    $un = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', ($user + '\Software\Microsoft\Windows\CurrentVersion\Uninstall'))
    foreach ($root in $un) {
        foreach ($k in @(Get-ChildItem -LiteralPath $root)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath
            if ([string]$p.Publisher -notmatch $pub -or [string]$p.DisplayName -match $notGame -or -not $p.InstallLocation) { continue }
            & $addDir ([string]$p.DisplayName) ([string]$p.InstallLocation) @()
        }
    }
    # Minecraft: Java Edition runs in javaw.exe from the launcher's own Java.
    $prof = Get-UserProfile
    $mc = @()
    foreach ($r in @([IO.Path]::Combine([string]${env:ProgramFiles(x86)}, 'Minecraft Launcher', 'runtime'), [IO.Path]::Combine([string]$prof, 'AppData', 'Roaming', '.minecraft', 'runtime'), [IO.Path]::Combine([string]$prof, 'AppData', 'Local', 'Packages', 'Microsoft.4297127D64EC6_8wekyb3d8bbwe', 'LocalCache', 'Local', 'runtime'))) {
        if (Test-Path -LiteralPath $r) { $mc += @(Get-ChildItem -LiteralPath $r -Filter 'javaw.exe' -Recurse -Depth 6 | ForEach-Object { $_.FullName }) }
    }
    if ($mc.Count) { $games.Add([pscustomobject]@{ Name = 'Minecraft: Java Edition'; Exes = $mc }) }
    # Programs Windows has recognised as games (Game Bar's list).
    $gcs = Open-UserKey 'System\GameConfigStore\Children' $false
    if ($gcs) {
        $known = @{}
        foreach ($g in $games) { foreach ($x in $g.Exes) { $known[$x.ToLower()] = 1 } }
        foreach ($n in $gcs.GetSubKeyNames()) {
            $c = $gcs.OpenSubKey($n)
            if (-not $c) { continue }
            $x = [string]$c.GetValue('MatchedExeFullPath', '')
            $c.Close()
            if (-not $x -or $known.ContainsKey($x.ToLower()) -or (Split-Path -Leaf $x) -match $script:SkipExe) { continue }
            if (-not (Test-Path -LiteralPath $x -PathType Leaf)) { continue }
            $known[$x.ToLower()] = 1
            $d = [string](Get-Item -LiteralPath $x).VersionInfo.FileDescription
            $games.Add([pscustomobject]@{ Name = $(if ($d.Trim()) { $d.Trim() } else { [IO.Path]::GetFileNameWithoutExtension($x) }); Exes = @($x) })
        }
        $gcs.Close()
    }
    [pscustomobject]@{ Games = $games.ToArray(); TimedOut = $clock.Elapsed.TotalSeconds -ge 90 }
}

# "Key=Value;" entries of a DirectX preference, as an ordered table.
function Split-DxEntries([string]$s) {
    $t = [ordered]@{}
    foreach ($e in $s.Split(';')) {
        $i = $e.IndexOf('=')
        if ($i -gt 0) { $t[$e.Substring(0, $i).Trim()] = $e.Substring($i + 1).Trim() }
    }
    $t
}
switch ($env:GT_STEP) {

'refresh' {
    # Windows often leaves a new monitor at 60 Hz, and drivers reset it after
    # a cable or driver change. A frame cap or V-Sync tied to the refresh rate
    # then holds games at 60 FPS, and every frame waits longer to be shown.
    if (-not (Import-Native)) { return }
    $disp = @([GameTune.Displays]::List() | Sort-Object { -not $_.Primary })
    if (-not $disp.Count) { Fail 'Could not read the monitor settings.'; return }
    $n = 0
    foreach ($d in $disp) {
        $n++
        $e = Read-MonitorEdid $d.MonitorPath
        $tags = @(@($e.Name, $(if ($d.Primary -and $disp.Count -gt 1) { 'main' })) | Where-Object { $_ })
        $label = 'Monitor ' + $n + $(if ($tags.Count) { ' (' + ($tags -join ', ') + ')' })
        $res = '{0} x {1}' -f $d.Width, $d.Height
        if ($d.MaxHz -gt $d.Hz + 1) {
            $test = [GameTune.Displays]::Apply($d.Device, $d.MaxHz, 0)
            if ($test -ne 0) {
                Warn ($label + ': ' + $d.Hz + ' Hz kept. It lists ' + $d.MaxHz + ' Hz, but the driver refused it (code ' + $test + ').')
                continue
            }
            # The new rate is only switched for this session, so a restart
            # brings the old one back whatever happens. It is saved only after
            # Y. The finally block switches back on No, on timeout, and when
            # the window is stopped with Ctrl+C, before anything is printed.
            Say ('  ' + $label + ': switching from ' + $d.Hz + ' Hz to ' + $d.MaxHz + ' Hz. The screen may go dark for a moment.')
            Say '  If the picture is fine, press Y within 15 seconds to keep it. Without an answer it switches back.'
            $rc = -101
            $keep = $false
            try {
                $rc = [GameTune.Displays]::Apply($d.Device, $d.MaxHz, 1)
                if ($rc -eq 0) { $keep = Wait-Yes 15 }
            } finally {
                if (-not $keep) { [void][GameTune.Displays]::Reset($d.Device) }
            }
            if ($rc -ne 0) { Fail ($label + ': could not switch to ' + $d.MaxHz + ' Hz (code ' + $rc + '); it stays at ' + $d.Hz + ' Hz.'); continue }
            if (-not $keep) { Info ($label + ': switched back to ' + $d.Hz + ' Hz.'); continue }
            $sv = [GameTune.Displays]::Apply($d.Device, $d.MaxHz, 2)
            if ($sv -eq 0) { Ok ($label + ': ' + $res + ' at ' + $d.MaxHz + ' Hz instead of ' + $d.Hz + ' Hz.'); $d.Hz = $d.MaxHz }
            else { Warn ($label + ': runs at ' + $d.MaxHz + ' Hz now, but Windows could not save it (code ' + $sv + '): after a restart it is back at ' + $d.Hz + ' Hz.') }
        } else {
            Ok ($label + ': ' + $res + ' at ' + $d.Hz + ' Hz, the highest it offers at this resolution.')
        }
        # The monitor reports a high refresh rate, but this connection carries
        # only about 60 Hz at this resolution: an HDMI 1.4 port or cable, a
        # DisplayPort-to-HDMI adapter, or a motherboard port.
        $edidHz = Get-EdidHzAt $e $d.Width $d.Height
        if ($edidHz -ge 100 -and $d.MaxHz -le 75) {
            Warn ($label + ' can do up to ' + $edidHz + ' Hz at ' + $res + ', but this connection only carries ' + $d.MaxHz + ' Hz.')
            More 'Use DisplayPort on the graphics card, or an HDMI 2.0 port and cable (HDMI 2.1 for 4K above 60 Hz).'
        }
    }
}

'gpupref' {
    # On a PC with two GPUs (a laptop with integrated and discrete graphics,
    # or a desktop with the processor's graphics enabled), a game the driver
    # does not recognise can start on the slow integrated GPU. The Windows
    # setting decides before the NVIDIA and AMD per-app settings do.
    if (-not (Import-Native)) { return }
    $r = Get-GpuRanking
    if (-not $r.Ranked) { Skip 'Windows could not rank the graphics adapters.'; return }
    if (-not $r.Two) { Ok ('One GPU for games (' + $r.Fast.Name + '), so there is nothing to choose.'); return }
    Info ('High performance: ' + $r.Fast.Name + '. Power saving: ' + $r.Saving.Name + '.')
    $found = Find-Games
    $games = @($found.Games)
    if (-not $games.Count) { Skip 'No installed games found (Steam, Epic, GOG, Ubisoft, EA, Battle.net, Riot, Rockstar, Minecraft).'; return }
    $key = Open-UserKey 'Software\Microsoft\DirectX\UserGpuPreferences' $true
    if (-not $key) { Fail 'Could not open the Windows graphics preferences.'; return }
    $set = New-Object 'System.Collections.Generic.List[string]'
    $had = 0
    $fail = 0
    $moved = New-Object 'System.Collections.Generic.List[string]'
    foreach ($g in $games) {
        $changed = $false
        foreach ($x in $g.Exes) {
            $t = Split-DxEntries ([string]$key.GetValue($x, ''))
            if ([string]$t['GpuPreference'] -eq '2') { $had++; continue }
            # 1 = power saving, 0 = let Windows decide: both can leave a game on
            # the integrated GPU, so they are changed too and reported.
            if ($t.Contains('GpuPreference') -and -not $moved.Contains($g.Name)) { $moved.Add($g.Name) }
            $t['GpuPreference'] = '2'
            $v = (@($t.Keys | ForEach-Object { $_ + '=' + $t[$_] }) -join ';') + ';'
            try { $key.SetValue($x, $v, [Microsoft.Win32.RegistryValueKind]::String); $changed = $true } catch { $fail++ }
        }
        if ($changed) { $set.Add($g.Name) }
    }
    $key.Close()
    if ($set.Count) {
        $names = @($set | Sort-Object -Unique)
        $list = ($names | Select-Object -First 12) -join ', '
        if ($names.Count -gt 12) { $list += ' and ' + ($names.Count - 12) + ' more' }
        Ok ('Set to the high-performance GPU: ' + $list + '.')
    }
    if ($had) { Ok ([string]$had + ' game program(s) were already set to it.') }
    if ($fail) { Fail ([string]$fail + ' program(s) could not be set.') }
    if ($moved.Count) { Info ('Were set to power saving or "Let Windows decide" before: ' + (@($moved | Sort-Object -Unique) -join ', ') + '.') }
    if ($found.TimedOut) { Info 'The search stopped after 90 seconds; games it did not reach keep the Windows default.' }
    Info 'Games installed later: run GameTune again, or add them under Settings > System > Display > Graphics.'
}

'nvidia' {
    # Settings in the NVIDIA Control Panel's global profile that old tweak
    # guides change and that cost FPS or cause stutter. Each is set back to
    # NVIDIA's default; per-game profiles are not touched.
    if (-not (Import-Native)) { return }
    $nv = New-Object GameTune.Nv
    $rc = $nv.Open()
    if ($rc -eq -1000) { $nv.Close(); Skip 'The NVIDIA driver is not installed.'; return }
    if ($rc -ne 0) { $nv.Close(); Fail ('Could not open the NVIDIA driver settings (NVAPI status ' + $rc + ').'); return }
    $fixed = 0
    try {
        # Shader cache: off makes every game compile its shaders again at every
        # start and whenever a new effect appears, which shows as stutter.
        $s = $nv.Read(0x00198FFF)
        if ($s.Found -and $s.Value -eq 0) {
            if ($nv.Restore(0x00198FFF) -eq 0) { $fixed++; Ok 'Shader cache was off - turned back on. With it off, games compile shaders again on every start and stutter while they do.' }
            else { Fail 'Shader cache is off and could not be turned back on.' }
        } else { Ok 'Shader cache: on.' }
        # Shader cache size, in MB. NVIDIA's default grew with its drivers: 4 GB
        # up to R565, 8 GB in R570, 12 GB in R580 and 16 GB from R590 on, and
        # NVIDIA advises against lowering it. A smaller size, often set by
        # tweak guides when the default was 4 GB, makes the driver throw
        # compiled shaders away, and games compile them again mid-game.
        $br = Get-NvidiaBranch
        $def = if ($br -ge 590) { 16384 } elseif ($br -ge 580) { 12288 } elseif ($br -ge 570) { 8192 } else { 4096 }
        $z = $nv.Read(0x00AC8497)
        $user = $z.Found -and $z.Location -eq 0 -and -not $z.Predefined
        if ($user -and $z.Value -ne [uint32]::MaxValue -and $z.Value -lt $def) {
            if ($nv.Restore(0x00AC8497) -eq 0) { $fixed++; Ok ('Shader cache size was ' + (Format-MB $z.Value) + ' - set back to the driver default' + $(if ($br) { ' (' + (Format-MB $def) + ' with driver ' + $br + ')' }) + ', so compiled shaders stop being thrown away.') }
            else { Fail ('Shader cache size is ' + (Format-MB $z.Value) + ' and could not be changed.') }
        } elseif ($user -and $z.Value -eq [uint32]::MaxValue) { Ok 'Shader cache size: unlimited.' }
        elseif ($user) { Ok ('Shader cache size: ' + (Format-MB $z.Value) + '.') }
        else { Ok ('Shader cache size: driver default' + $(if ($br) { ', ' + (Format-MB $def) + ' with driver ' + $br }) + '.') }
        # Threaded optimization forced off: OpenGL games (Minecraft: Java
        # Edition, emulators, older id Tech games) then do all driver work on
        # one thread and lose FPS when CPU-bound. Auto lets per-game profiles decide.
        $t = $nv.Read(0x20C1221E)
        if ($t.Found -and $t.Location -eq 0 -and $t.Value -eq 2) {
            if ($nv.Restore(0x20C1221E) -eq 0) { $fixed++; Ok 'Threaded optimization was forced off - set back to Auto. Forced off costs CPU-bound OpenGL games FPS.' }
            else { Fail 'Threaded optimization is forced off and could not be changed.' }
        } else { Ok 'Threaded optimization: Auto or on.' }
        # Preferred graphics processor (Optimus laptops) set to Integrated:
        # every game without its own NVIDIA profile then runs on the iGPU.
        $o = $nv.Read(0x10F9DC81)
        if ($o.Found -and $o.Location -eq 0 -and -not $o.Predefined -and ($o.Value -band 0x11) -eq 0) {
            $a = $nv.Restore(0x10F9DC81)
            [void]$nv.Restore(0x10F9DC80)
            if ($a -eq 0) { $fixed++; Ok 'Preferred graphics processor was Integrated graphics - set back to Auto-select, so games run on the NVIDIA GPU.' }
            else { Fail 'Preferred graphics processor is Integrated graphics and could not be changed.' }
        }
        # Max Frame Rate for all games, well below the refresh rate: it caps
        # every game. A cap just below the refresh rate is the usual G-SYNC
        # setting and stays.
        $f = $nv.Read(0x10835002)
        if ($f.Found -and $f.Location -eq 0 -and $f.Value -gt 0) {
            $main = @([GameTune.Displays]::List() | Where-Object { $_.Primary })[0]
            $hz = if ($main) { [int]$main.Hz } else { 0 }
            if ($hz -gt 0 -and $f.Value -lt [Math]::Floor($hz * 0.9)) {
                if ($nv.Restore(0x10835002) -eq 0) { $fixed++; Ok ('Max Frame Rate was ' + $f.Value + ' FPS for all games, well below the ' + $hz + ' Hz refresh rate - turned off.') }
                else { Fail ('Max Frame Rate caps all games at ' + $f.Value + ' FPS and could not be changed.') }
            } else { Ok ('Max Frame Rate: ' + $f.Value + ' FPS' + $(if ($hz -gt 0) { ', at or just below the ' + $hz + ' Hz refresh rate' }) + '.') }
        }
        if ($fixed) {
            $sv = $nv.Save()
            if ($sv -eq 0) { Info 'Saved. Applies to games started from now on.' }
            else { Fail ('The changes could not be saved (NVAPI status ' + $sv + ').') }
        }
    } finally { $nv.Close() }
}

'amd' {
    # AMD Software keeps its global graphics settings in the display adapter's
    # registry key. Shader cache set to Off makes every game compile its
    # shaders again at each start, which stutters; it goes back to AMD
    # optimized, the default. The value keeps the type the driver stored it
    # in: UTF-16 digits in binary on most drivers, a string or a number on
    # some newer ones. 0 is Off, 1 AMD optimized, 2 always on.
    $n = 0
    foreach ($a in @(Get-DisplayAdapterKeys)) {
        if ($a.Provider -notmatch 'Advanced Micro Devices' -and $a.Name -notmatch 'Radeon') { continue }
        $n++
        $u = Open-MachineKey ($a.Path + '\UMD') $true
        # Assigned directly: an if expression would unroll a binary value into bytes.
        $v = $null
        if ($u) { $v = $u.GetValue('ShaderCache', $null) }
        if ($null -eq $v) { Ok ($a.Name + ': shader cache at its default, AMD optimized.') }
        else {
            $off = $false
            $new = $null
            if ($v -is [byte[]]) { $off = $v.Count -ge 1 -and $v[0] -eq 0x30; $new = [byte[]](0x31, 0x00) }
            elseif ($v -is [string]) { $off = $v.Trim([char]0).Trim() -eq '0'; $new = '1' }
            elseif ($v -is [int]) { $off = $v -eq 0; $new = 1 }
            if ($off) {
                try {
                    $u.SetValue('ShaderCache', $new, $u.GetValueKind('ShaderCache'))
                    Ok ($a.Name + ': shader cache was Off - set back to AMD optimized, the default. With it off, games compile shaders again at every start and stutter while they do.')
                } catch { Fail ($a.Name + ': shader cache is Off and could not be changed.') }
            } else { Ok ($a.Name + ': shader cache on.') }
        }
        if ($u) { $u.Close() }
        # Radeon Chill for all games lowers the frame rate whenever little moves.
        if ($null -ne $a.Chill -and [int]$a.Chill -eq 1) {
            $k = Open-MachineKey $a.Path $true
            try { $k.SetValue('KMD_ChillEnabled', 0, $k.GetValueKind('KMD_ChillEnabled')); Ok ($a.Name + ': Radeon Chill was on for all games - turned off.') }
            catch { Fail ($a.Name + ': Radeon Chill is on and could not be turned off.') }
            if ($k) { $k.Close() }
        }
    }
    if (-not $n) { Skip 'No AMD graphics driver found.' }
}

'findings' {
    # Hardware and setup problems that cost FPS or 1% lows and that only the
    # owner can fix: BIOS settings, slots, cables, drives and running software.
    $native = Import-Native
    $script:fix = New-Object 'System.Collections.Generic.List[object]'
    function Need([int]$rank, [string]$text) { $script:fix.Add([pscustomobject]@{ Rank = $rank; Text = $text }) }
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = 0
    [void][int]::TryParse([string]$cv.CurrentBuildNumber, [ref]$build)
    $ubr = [int]$cv.UBR
    $laptop = Test-Laptop
    $cs = Get-CimInstance Win32_ComputerSystem

    # Power
    if ($laptop) {
        $bat = @(Get-CimInstance Win32_Battery)
        if ($bat.Count -and [int]$bat[0].BatteryStatus -eq 1) {
            Warn 'Running on battery: laptops cut CPU and GPU power on battery, and NVIDIA Battery Boost caps games at 30 FPS.'
            Need 2 'Plug the laptop in to play.'
        } else { Ok 'Laptop: plugged in.' }
    }

    # Processor
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $cname = (([string]$cpu.Name) -replace '\s+', ' ').Trim()
    # Intel 13th and 14th gen desktop: microcode 0x12B and later stop the
    # voltage problem behind crashes and degrading CPUs.
    if ($cname -match 'i[579]-1[34]\d{3}(K|KF|KS|F|T)?(\s|$)') {
        $b = Get-Reg 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' 'Update Revision'
        if ($b -is [byte[]] -and $b.Count -ge 8) {
            $rev = [BitConverter]::ToUInt32($b, 4)
            if ($rev -gt 0 -and $rev -lt 0x12B) {
                Warn ('CPU microcode 0x{0:X} predates Intel''s 0x12B fix for 13th and 14th gen instability. It does not cost FPS; it causes crashes and slowly damages the CPU.' -f $rev)
                Need 12 'Update the BIOS to one with Intel microcode 0x12F or newer.'
            } elseif ($rev -gt 0) { Ok ('CPU microcode 0x{0:X}: has Intel''s fix for 13th and 14th gen instability.' -f $rev) }
        }
    }
    if ($build -lt 22000 -and $cname -match '1[2-4]th Gen|Core\(TM\) Ultra|Core Ultra') {
        Warn 'Windows 10 has no Thread Director support, so game threads can land on the E-cores.'
        Need 9 'Move to Windows 11: it keeps game threads on the P-cores of this CPU.'
    }
    # Windows 11 24H2 changed branch prediction for Ryzen; 22H2 and 23H2 got it
    # with KB5041587 (builds 22621.4112 and 22631.4112). Hardware Unboxed
    # measured 10 to 11 percent more FPS on average with it on Ryzen 7000 and
    # 9000. Windows 10 does not get it.
    if ($cname -match 'Ryzen') {
        $hub = 'Hardware Unboxed measured 10 to 11% more FPS on average with it (Ryzen 7 7700X and 9700X).'
        if ($build -lt 22000) {
            Warn ('Windows 10 does not get the branch-prediction update that Windows 11 24H2 brought for Ryzen. ' + $hub)
            Need 9 'Move to Windows 11 24H2 or newer for the Ryzen branch-prediction update.'
        } elseif ($build -lt 22621 -or ($build -lt 26100 -and $ubr -lt 4112)) {
            Warn ('This Windows build lacks the Ryzen branch-prediction update (24H2, or 23H2 from KB5041587, August 2024). ' + $hub)
            Need 9 'Install the Windows updates: 24H2, or 23H2 with KB5041587 or later, has the Ryzen branch-prediction update.'
        }
    }

    # Memory
    $mods = @(Get-CimInstance Win32_PhysicalMemory | Where-Object { [double]$_.Capacity -gt 0 })
    $slots = [int](@(Get-CimInstance Win32_PhysicalMemoryArray | Where-Object { [int]$_.Use -eq 3 }) | Measure-Object -Property MemoryDevices -Sum).Sum
    $totalGB = [Math]::Round((($mods | Measure-Object -Property Capacity -Sum).Sum) / 1GB)
    $tnames = @{ 24 = 'DDR3'; 26 = 'DDR4'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $info = @()
    foreach ($m in $mods) {
        $type = $tnames[[int]$m.SMBIOSMemoryType]
        if (-not $type) { $type = 'memory' }
        $cfg = [int]$m.ConfiguredClockSpeed
        if ($cfg -gt 0 -and $cfg -lt 1800 -and $type -match '^DDR[45]$') { $cfg *= 2 }
        $pn = ([string]$m.PartNumber).Trim()
        $info += [pscustomobject]@{ GB = [Math]::Round([double]$m.Capacity / 1GB); Type = $type; Speed = $cfg; Rated = (Get-RatedSpeed $pn); Part = $pn; Channel = (Get-Channel $m) }
    }
    if ($mods.Count) {
        $line = 'Memory: ' + [string]$totalGB + ' GB in ' + $mods.Count + ' stick' + $(if ($mods.Count -ne 1) { 's' }) + $(if ($info[0].Speed) { ', ' + $info[0].Type + ' at ' + $info[0].Speed + ' MT/s' })
        $known = @($info | Where-Object { $_.Channel })
        $distinct = @($known | ForEach-Object { $_.Channel } | Select-Object -Unique)
        $slow = @($info | Where-Object { $_.Rated -gt 0 -and $_.Speed -gt 0 -and $_.Rated -gt $_.Speed + 150 })
        $single = $false
        if ($mods.Count -eq 1 -and $slots -ne 1) {
            $single = $true
            Warn ($line + '. One stick means one memory channel: in Hardware Unboxed''s test that cost about 12% average FPS and 16% of the 1% lows (much less on X3D CPUs).')
            Need 4 'Add a second, identical memory stick for dual channel.'
        } elseif ($known.Count -eq $mods.Count -and $mods.Count -gt 1 -and $distinct.Count -eq 1) {
            $single = $true
            Warn ($line + ', but all in channel ' + $distinct[0] + ', so the CPU uses one channel instead of two.')
            Need 4 'Move a memory stick to the other channel''s slot (the manual names the pair, usually A2 and B2).'
        }
        if ($slow.Count) {
            Warn ('Memory runs at ' + $slow[0].Speed + ' MT/s but the kit is rated ' + $slow[0].Rated + ' MT/s: XMP or EXPO is off. Hardware Unboxed measured 17 to 20% more FPS and about 30% better 1% lows with it on.')
            Need 3 ('Turn on XMP, EXPO or DOCP in the BIOS (rated ' + $slow[0].Rated + ' MT/s).')
        } elseif (-not $laptop -and @($info | Where-Object { $_.Rated -eq 0 -and (($_.Type -eq 'DDR4' -and $_.Speed -le 2666) -or ($_.Type -eq 'DDR5' -and $_.Speed -le 4800)) }).Count) {
            Info ($line + ', the standard speed without XMP or EXPO. If the sticks'' label shows a higher speed, turn XMP or EXPO on in the BIOS.')
        } elseif (-not $single) {
            Ok ($line + $(if ($distinct.Count -ge 2) { ', dual channel' }) + '.')
        }
        if ($totalGB -lt 16) {
            Warn ('Only ' + $totalGB + ' GB of memory: current games page to disk with less than 16 GB, which shows up as stutter.')
            Need 6 'Upgrade to 16 GB of memory at least, 32 GB for current games with a browser open.'
        }
        if (@($info | ForEach-Object { $_.Part } | Select-Object -Unique).Count -gt 1) {
            Info 'The sticks come from different kits. Mixed kits often cannot run their rated speed; if XMP or EXPO is unstable, that is why.'
        }
    }

    # Graphics
    $r = $null
    $gpus = @()
    if ($native) {
        $r = Get-GpuRanking
        $gpus = @([GameTune.Dxgi]::List() | Where-Object { -not $_.Software })
    }
    $dgpu = if ($r -and $r.Ranked) { $r.Fast } else { $null }
    $vcs = @(Get-CimInstance Win32_VideoController)
    if ($dgpu) {
        $vc = @($vcs | Where-Object { ([string]$_.Name).Trim() -eq $dgpu.Name })[0]
        $line = $dgpu.Name + $(if ($dgpu.Vram -ge 1GB) { ', {0:0} GB' -f ($dgpu.Vram / 1GB) })
        $old = $false
        if ($vc -and $vc.DriverDate) {
            $date = [datetime]$vc.DriverDate
            $line += ', driver from ' + $date.ToString('yyyy-MM-dd')
            $old = ((Get-Date) - $date).TotalDays -gt 365
        }
        Ok ('Graphics: ' + $line + '.')
        if ($old) {
            Warn 'That driver is more than a year old: new games get their performance fixes in newer drivers.'
            Need 11 'Install the current graphics driver.'
        }
        if ($dgpu.Vram -ge 3GB -and $dgpu.Vram -le 8.5GB) {
            Info ('{0:0} GB of video memory runs full in current games at the highest texture setting; when it does, 1% lows collapse.' -f ($dgpu.Vram / 1GB))
            Need 10 'In new games, set texture quality one step below the highest: the video memory runs full there.'
        }
    }
    if ($dgpu -and $dgpu.Vendor -eq 0x10DE) {
        $smi = [IO.Path]::Combine([string]$env:SystemRoot, 'System32', 'nvidia-smi.exe')
        if (-not (Test-Path -LiteralPath $smi)) { $smi = [IO.Path]::Combine([string]$env:ProgramFiles, 'NVIDIA Corporation', 'NVSMI', 'nvidia-smi.exe') }
        if (Test-Path -LiteralPath $smi) {
            $rows = @(& $smi '--query-gpu=name,pcie.link.width.current,pcie.link.width.max' '--format=csv,noheader,nounits' 2>$null)
            $mem = @(& $smi '-q' '-d' 'MEMORY' 2>$null)
            $caps = @(& $smi '--query-gpu=compute_cap' '--format=csv,noheader' 2>$null)
            $bar = @()
            for ($i = 0; $i -lt $mem.Count; $i++) {
                if ([string]$mem[$i] -notmatch 'BAR1 Memory Usage') { continue }
                for ($k = $i + 1; $k -lt [Math]::Min($mem.Count, $i + 4); $k++) {
                    if ([string]$mem[$k] -match 'Total\s*:\s*(\d+)\s*MiB') { $bar += [int]$Matches[1]; break }
                }
            }
            for ($i = 0; $i -lt $rows.Count; $i++) {
                $f = @(([string]$rows[$i]).Split(',') | ForEach-Object { $_.Trim() })
                if ($f.Count -lt 3) { continue }
                $cur = 0
                $max = 0
                [void][int]::TryParse($f[1], [ref]$cur)
                [void][int]::TryParse($f[2], [ref]$max)
                if ($cur -gt 0 -and $max -gt 0 -and $cur -lt $max) {
                    Warn ($f[0] + ' runs its PCIe link at x' + $cur + ' instead of x' + $max + '.')
                    Need 7 'Reseat the graphics card in the top x16 slot; a riser, or an M.2 drive sharing its lanes, can also cut the link.'
                } elseif ($cur -gt 0 -and $cur -le 4 -and -not $laptop -and $f[0] -notmatch 'GT 10[13]0|GT 7[13]0') {
                    Warn ($f[0] + ' runs on only 4 PCIe lanes: a chipset slot or a riser.')
                    Need 7 'Move the graphics card to the top x16 slot.'
                } elseif ($cur -gt 0) { Ok ('PCIe link: x' + $cur + '.') }
                # Resizable BAR exists from the RTX 30 series on (compute
                # capability 8.0 and up); on laptops only the maker can enable it.
                $cc = 0.0
                if ($i -lt $caps.Count) { [void][double]::TryParse(([string]$caps[$i]).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$cc) }
                $rebar = if ($cc -gt 0) { $cc -ge 8.0 } else { $f[0] -match 'RTX [345]\d{3}|RTX A\d{4}|RTX \d{4} Ada|RTX PRO' }
                if ($i -lt $bar.Count -and $rebar) {
                    if ($bar[$i] -gt 256) { Ok 'Resizable BAR: on.' }
                    elseif (-not $laptop) {
                        Warn 'Resizable BAR is off. NVIDIA uses it in the games it has tested, about 2 to 4% faster there.'
                        if ([int](Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType') -eq 1) {
                            Need 13 'Resizable BAR needs UEFI boot, but Windows boots in legacy BIOS mode here: convert the disk with MBR2GPT first, or Windows will not start with CSM off. Then turn on "Above 4G Decoding" and "Re-Size BAR" in the BIOS.'
                        } else { Need 13 'Turn on "Above 4G Decoding" and "Re-Size BAR" in the BIOS (needs UEFI boot with CSM off).' }
                    }
                }
            }
        }
    } elseif ($dgpu -and $dgpu.Vendor -eq 0x8086 -and $dgpu.Vram -ge 3GB) {
        Info 'Intel Arc cards lose about a quarter of their speed without Resizable BAR: Intel Graphics Software shows whether it is on.'
    } elseif ($dgpu -and $dgpu.Vendor -eq 0x1002 -and $dgpu.Name -match 'Radeon.*\b(RX|PRO|Pro|VII)\b') {
        Info 'AMD Smart Access Memory (Resizable BAR) added 7 to 16% at 1080p in Hardware Unboxed''s test: AMD Software > Performance > Tuning shows whether it is on.'
    }

    # Frame rate caps in the graphics drivers. NVIDIA's global Max Frame Rate
    # just below the refresh rate is the usual G-SYNC setting; far below it,
    # it caps every game. Radeon Chill lowers the frame rate whenever little
    # moves on screen, to save power.
    $mainHz = 0
    if ($native) { $mainHz = [int](@([GameTune.Displays]::List() | Sort-Object { -not $_.Primary })[0]).Hz }
    if ($native -and $dgpu -and $dgpu.Vendor -eq 0x10DE) {
        $nv = New-Object GameTune.Nv
        if ($nv.Open() -eq 0) {
            $f = $nv.Read(0x10835002)
            if ($f.Found -and $f.Value -gt 0) {
                if ($mainHz -gt 0 -and $f.Value -lt [Math]::Floor($mainHz * 0.9)) {
                    Warn ('NVIDIA Max Frame Rate still caps every game at ' + $f.Value + ' FPS, well below the ' + $mainHz + ' Hz of the main monitor.')
                    Need 5 ('Raise or turn off Max Frame Rate in NVIDIA Control Panel > Manage 3D settings (with G-SYNC, use ' + ($mainHz - 3) + ').')
                } elseif ($mainHz -gt 0 -and $f.Value -lt $mainHz) { Ok ('NVIDIA Max Frame Rate: ' + $f.Value + ' FPS, just below the ' + $mainHz + ' Hz refresh rate.') }
                else { Ok ('NVIDIA Max Frame Rate: ' + $f.Value + ' FPS' + $(if ($mainHz -gt 0) { ', main monitor at ' + $mainHz + ' Hz' }) + '.') }
            }
        }
        $nv.Close()
    }
    foreach ($a in @(Get-DisplayAdapterKeys)) {
        if (($a.Provider -match 'Advanced Micro Devices' -or $a.Name -match 'Radeon') -and $null -ne $a.Chill -and [int]$a.Chill -eq 1) {
            Warn ($a.Name + ': Radeon Chill is switched on for all games. It lowers the frame rate whenever little moves on screen.')
            Need 6 'Turn off Radeon Chill in AMD Software > Gaming > Graphics, unless you want it to save power.'
        }
    }

    # Monitors
    if ($native) {
        $disp = @([GameTune.Displays]::List() | Sort-Object { -not $_.Primary })
        $n = 0
        foreach ($d in $disp) {
            $n++
            $e = Read-MonitorEdid $d.MonitorPath
            $label = 'Monitor ' + $n + $(if ($e.Name) { ' (' + $e.Name + ')' })
            if ($r -and $r.Two -and $d.Adapter -eq $r.Saving.Name) {
                if (-not $laptop -and $d.Primary) {
                    Warn ($label + ' is plugged into the motherboard, so it runs on ' + $d.Adapter + ' and every frame from ' + $r.Fast.Name + ' is copied across first.')
                    Need 1 ('Plug ' + $label + ' into the graphics card instead of the motherboard.')
                } elseif (-not $laptop) {
                    Info ($label + ' is plugged into the motherboard. Fine for a second screen; games on it run slower.')
                } elseif ($d.Primary) {
                    Info ('The laptop screen runs on ' + $d.Adapter + ', so frames from ' + $r.Fast.Name + ' are copied through it.')
                    Need 8 'If the laptop has a MUX switch or Advanced Optimus, set the GPU mode to discrete (dGPU) in the maker''s app: 10 to 17% more FPS in tests.'
                }
            }
            $edidHz = Get-EdidHzAt $e $d.Width $d.Height
            if ($edidHz -ge 100 -and $d.MaxHz -le 75) {
                Warn ($label + ' can do up to ' + $edidHz + ' Hz at this resolution, but its connection only carries ' + $d.MaxHz + ' Hz.')
                Need 5 ('Connect ' + $label + ' by DisplayPort, or an HDMI 2.0 port and cable (HDMI 2.1 for 4K above 60 Hz), on the graphics card.')
            }
        }
    }

    # Storage
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $size = [double]$v.Size
        $free = [double]$v.FreeSpace
        if ($size -le 0) { continue }
        if ($free / $size -lt 0.1 -or $free -lt 15GB) {
            Warn ('{0} has {1:0} GB free of {2:0} GB. A nearly full SSD writes slowly, and shader caches cannot grow, so games compile shaders again and stutter.' -f $v.DeviceID, ($free / 1GB), ($size / 1GB))
            Need 9 ('Free up space on drive ' + $v.DeviceID + ' (keep 10 to 15% of it free).')
        }
    }
    $libs = @()
    $steam = [string](Get-Reg ((Get-UserPath) + '\Software\Valve\Steam') 'SteamPath')
    if ($steam) {
        $steam = $steam.Replace([IO.Path]::AltDirectorySeparatorChar, [IO.Path]::DirectorySeparatorChar)
        $libs += $steam
        $vdf = [IO.Path]::Combine($steam, 'steamapps', 'libraryfolders.vdf')
        if (Test-Path -LiteralPath $vdf) { foreach ($l in [IO.File]::ReadAllLines($vdf)) { if ($l -match '"path"\s+"([^"]+)"') { $libs += ($Matches[1] -replace '\\\\', '\') } } }
    }
    $epic = [IO.Path]::Combine([string]$env:ProgramData, 'Epic', 'EpicGamesLauncher', 'Data', 'Manifests')
    foreach ($f in @(if (Test-Path -LiteralPath $epic) { Get-ChildItem -LiteralPath $epic -Filter '*.item' })) {
        $j = $null
        try { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { }
        if ($j -and $j.InstallLocation) { $libs += [string]$j.InstallLocation }
    }
    $hdd = @()
    $kinds = @{}
    foreach ($l in $libs) {
        if ($l -notmatch '^([A-Za-z]):') { continue }
        $dl = $Matches[1].ToUpper()
        if (-not $kinds.ContainsKey($dl)) { $kinds[$dl] = Get-DriveKind $l }
        if ($kinds[$dl] -eq 'hard drive' -and $hdd -notcontains $dl) { $hdd += $dl }
    }
    foreach ($dl in $hdd) {
        Warn ('Games are installed on drive ' + $dl + ':, a hard drive. Games stream textures and levels while you play, and a hard drive cannot keep up: that causes hitches.')
        Need 8 ('Move the games on drive ' + $dl + ': to an SSD.')
    }
    if (-not $hdd.Count -and $kinds.Count) { Ok ('Game drives: ' + (@($kinds.Keys | Sort-Object | ForEach-Object { $_ + ': ' + $(if ($kinds[$_]) { $kinds[$_] } else { 'type unknown' }) }) -join ', ') + '.') }

    # Software running now
    $procs = @{}
    foreach ($p in @(Get-Process)) { $procs[([string]$p.ProcessName).ToLower()] = 1 }
    $has = { param([string[]]$names) foreach ($x in $names) { if ($procs.ContainsKey($x.ToLower())) { return $true } }; $false }
    $rgb = @()
    if (& $has @('iCUE')) { $rgb += 'Corsair iCUE' }
    if (& $has @('LightingService', 'ArmouryCrate', 'ArmouryCrate.Service')) { $rgb += 'ASUS Armoury Crate or Aura' }
    if (& $has @('SignalRgb', 'SignalRgbLauncher')) { $rgb += 'SignalRGB' }
    if (& $has @('MSI.CentralServer', 'MSI Center')) { $rgb += 'MSI Center' }
    if (& $has @('NZXT CAM')) { $rgb += 'NZXT CAM' }
    if (& $has @('RazerAppEngine', 'Razer Synapse 3', 'Razer Synapse Service')) { $rgb += 'Razer Synapse' }
    if (& $has @('OpenRGB')) { $rgb += 'OpenRGB' }
    if (& $has @('RGBFusion', 'GCC')) { $rgb += 'Gigabyte RGB Fusion or Control Center' }
    $hw = & $has @('HWiNFO64', 'HWiNFO32', 'HWiNFO')
    if ($rgb.Count -and $hw) {
        Warn ('HWiNFO runs together with ' + ($rgb -join ', ') + ': both read the motherboard''s SMBus, and the collisions cause periodic stutter.')
        Need 10 'Turn off HWiNFO''s support for the RGB devices, or do not run HWiNFO and the RGB software together.'
    } elseif ($rgb.Count) {
        Info ('Running: ' + ($rgb -join ', ') + '. Lighting software polls the SMBus and has been measured causing periodic stutter (SignalRGB, ASUS LightingService).')
        Need 14 ('If games stutter at regular intervals, test once with ' + ($rgb -join ' and ') + ' closed (save the lighting to the devices first).')
    }
    if (& $has @('NVIDIA Overlay', 'NVIDIA Share')) {
        Info 'The NVIDIA overlay is on. With Game Filters and Photo Mode on, games ran up to 15% slower in Tom''s Hardware''s test;'
        More 'NVIDIA App 11.0.1 and later leave them off. Check NVIDIA App > Settings > Features > Overlay > Game Filters and Photo Mode.'
    }
    if (& $has @('Medal', 'Overwolf', 'Outplayed')) {
        Info 'A clip recorder (Medal or Overwolf) is running: background recording encodes video for as long as you play.'
        Need 12 'Turn off background recording in Medal or Overwolf unless you use it.'
    }
    if (& $has @('MSIAfterburner')) { Info 'MSI Afterburner: keep its hardware polling period at 1000 ms or more; short periods with power monitoring cause stutter every few seconds.' }

    # Summary, biggest gain first
    if (-not $cpu -and -not $mods.Count) { Info 'Windows did not report the hardware details, so these checks could not run.'; return }
    if ($script:fix.Count) {
        Say ''
        Say '  Only you can change these, biggest gain first:'
        $i = 0
        $seen = @{}
        foreach ($x in @($script:fix | Sort-Object Rank)) {
            if ($seen.ContainsKey($x.Text)) { continue }
            $seen[$x.Text] = 1
            $i++
            Say ('   ' + $i + '. ' + $x.Text)
        }
    } else {
        Ok 'Nothing found in the hardware or setup that holds back FPS.'
    }
}

default { Fail ('Unknown step: ' + $env:GT_STEP) }
}
#GTPS
