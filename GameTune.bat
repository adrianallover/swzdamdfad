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
rem  VBS_MODE: Virtualization-Based Security and Memory Integrity (HVCI)
rem    auto    = turn off, unless FACEIT or Riot Vanguard is installed,
rem              because both can refuse to run without it
rem    disable = turn off even if one of those anti-cheats is installed
rem    keep    = leave VBS and Memory Integrity alone
rem
rem  DIAGTRACK_MODE: "Connected User Experiences and Telemetry" service
rem    auto    = turn off, unless Xbox Gaming Services is installed,
rem              because Xbox achievements in PC games are reported
rem              through this service
rem    disable = turn off even if Gaming Services is installed
rem    keep    = leave the service alone
rem --------------------------------------------------------------------------
set "VBS_MODE=auto"
set "DIAGTRACK_MODE=auto"

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

rem ---- Summary and confirmation ---------------------------------------------
set "SH_ED=%GT_EDITION%"
if /i "%GT_EDITION%"=="Core" set "SH_ED=Home"
if /i "%GT_EDITION%"=="CoreSingleLanguage" set "SH_ED=Home Single Language"
if /i "%GT_EDITION%"=="Professional" set "SH_ED=Pro"
set "SH_CPU=%GT_CPU%"
if not "%GT_CORES%"=="0" set "SH_CPU=%GT_CPU%   %GT_CORES% cores / %GT_THREADS% threads"
set "SH_RAM=unknown"
if not "%GT_RAMGB%"=="0" set "SH_RAM=%GT_RAMGB% GB"
echo.
echo  System
echo   OS          %GT_OS% %GT_VER%   build %GT_BUILD%.%GT_UBR%   %SH_ED%
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
if %GT_BUILD% GEQ 22621 echo   - Optimizations for windowed games: on
echo   - Fault Tolerant Heap: off, per-game list cleared
if %GT_RAMGB% GEQ 16 echo   - Memory page combining: off
echo   - Forced HPET clock: removed, if present
if defined IS_X3D echo   - AMD 3D V-Cache optimizer: checked
if defined DO_DIAG echo   - Telemetry: DiagTrack service and appraiser/CEIP tasks off
if not defined DO_DIAG echo   - Telemetry: appraiser/CEIP tasks off. DiagTrack unchanged, %DIAG_WHY%
echo.
echo  A restart is needed afterwards. README.md shows how to undo each change.
echo.
choice /c YN /n /m "  Apply these changes now? [Y/N] "
if errorlevel 2 goto :cancelled

call :step_vbs
call :step_gamebar
call :step_windowed
call :step_fth
call :step_pagecombining
call :step_hpet
call :step_x3d
call :step_telemetry

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
echo  Restart before you benchmark: VBS, FTH, page combining and the boot
echo  clock setting only change after a reboot.
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
echo.
echo  [1/8] Virtualization-Based Security / Memory Integrity
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
rem Hyper-V, Virtual Machine Platform (WSL2), Sandbox and Docker keep the
rem hypervisor loaded even with VBS off. Report it, but leave those alone.
set "HV_FEAT="
for %%S in (vmms vmcompute) do (reg query "%SVC%\%%S" >nul 2>&1 & if not errorlevel 1 set "HV_FEAT=1")
if not defined HV_FEAT exit /b 0
bcdedit /enum {current} 2>nul | findstr /i /c:"hypervisorlaunchtype" | findstr /i /c:"Auto" >nul
if "%errorlevel%"=="0" echo   [INFO] Hyper-V / Virtual Machine Platform keeps the hypervisor running, roughly 1%% in CPU-bound games. Left alone because WSL2, Docker and VMs need it.
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
echo.
echo  [2/8] Game Mode and Game Bar background recording
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


:step_windowed
rem Moves DX10/DX11 games that run windowed or borderless with the legacy
rem blt presentation model to the flip model: lower presentation latency,
rem independent flip and VRR. Off by default. Windows 11 22H2 and newer.
echo.
echo  [3/8] Optimizations for windowed games
if %GT_BUILD% LSS 22621 echo   [SKIP] Needs Windows 11 22H2 or newer.& exit /b 0
set "DXK=%UROOT%\Software\Microsoft\DirectX\UserGpuPreferences"
set "DXV="
for /f "tokens=2,*" %%A in ('reg query "%DXK%" /v DirectXUserGlobalSettings 2^>nul ^| findstr /c:"REG_SZ"') do set "DXV=%%B"
if not defined DXV set "DXV=;"
set "DXN="
set "DXON="
rem Keep the other entries of this value (VRR, Auto HDR, ...) untouched.
for %%I in ("%DXV:;=" "%") do call :dx_item "%%~I"
reg add "%DXK%" /v DirectXUserGlobalSettings /t REG_SZ /d "%DXN%SwapEffectUpgradeEnable=1;" /f >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not write DirectXUserGlobalSettings.& exit /b 0
if defined DXON (echo   [ OK ] Already on.) else (echo   [ OK ] Turned on: windowed and borderless DX10/DX11 games use the flip model.)
exit /b 0

:dx_item
set "IT=%~1"
if not defined IT exit /b 0
if /i "%IT%"=="SwapEffectUpgradeEnable=1" set "DXON=1"
if /i "%IT:~0,24%"=="SwapEffectUpgradeEnable=" exit /b 0
set "DXN=%DXN%%IT%;"
exit /b 0


:step_fth
rem After repeated crashes Windows silently moves a program onto the Fault
rem Tolerant Heap, which is much slower than the normal heap. Programs on it
rem are listed under FTH\State. Turning FTH off only stops new entries, so
rem the list is reset as well: Microsoft's documented reset runs first and FTH
rem is switched off afterwards, so the reset cannot turn it back on.
echo.
echo  [4/8] Fault Tolerant Heap
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

:count_values
rem count_values "key" outVar  - number of values directly under a key
set "%~2=0"
for /f "delims=" %%L in ('reg query "%~1" 2^>nul ^| findstr /c:"    REG_"') do set /a "%~2+=1"
exit /b 0


:step_pagecombining
rem Page combining periodically scans RAM for identical pages to merge; the
rem scan can hold a core at 100 percent for seconds. With 16 GB or more the
rem memory it saves is not worth that. Needs the SysMain service running.
echo.
echo  [5/8] Memory page combining
if "%GT_RAMGB%"=="0" echo   [SKIP] Could not read the installed RAM size.& exit /b 0
if %GT_RAMGB% LSS 16 echo   [SKIP] %GT_RAMGB% GB RAM: page combining saves useful memory here, so it stays on.& exit /b 0
if not defined PS echo   [SKIP] Windows PowerShell is not available.& exit /b 0
set "R="
for /f "usebackq delims=" %%X in (`%PS% -NoProfile -NonInteractive -Command "try { if ((Get-Service SysMain -ErrorAction Stop).Status -ne 'Running') { 'NOSYSMAIN' } elseif (-not (Get-MMAgent -ErrorAction Stop).PageCombining) { 'ALREADY' } else { Disable-MMAgent -PageCombining -ErrorAction Stop; 'DONE' } } catch { 'FAIL' }" 2^>nul`) do set "R=%%X"
if "%R%"=="DONE" echo   [ OK ] Turned off.
if "%R%"=="ALREADY" echo   [ OK ] Already off.
if "%R%"=="NOSYSMAIN" echo   [SKIP] The SysMain service is not running, so page combining is not active.
if "%R%"=="FAIL" echo   [FAIL] Could not change the setting.
if not defined R echo   [FAIL] Could not query the memory manager.
exit /b 0


:step_hpet
rem "bcdedit /set useplatformclock true" is a leftover from old tweak guides.
rem It forces HPET as the QueryPerformanceCounter source, which makes every
rem timer query far slower and costs FPS. Removing it restores the default.
echo.
echo  [6/8] Forced HPET clock
bcdedit /enum {current} >nul 2>&1
if not "%errorlevel%"=="0" echo   [SKIP] Could not read the boot configuration.& exit /b 0
bcdedit /enum {current} 2>nul | findstr /i /c:"useplatformclock" >nul
if not "%errorlevel%"=="0" echo   [ OK ] Not forced: Windows picks its timer source itself.& exit /b 0
bcdedit /deletevalue {current} useplatformclock >nul 2>&1
if not "%errorlevel%"=="0" echo   [FAIL] Could not remove useplatformclock.& exit /b 0
echo   [ OK ] Removed useplatformclock. Timer queries go back to the fast default source.
exit /b 0


:step_x3d
rem Dual-CCD X3D parts need the AMD 3D V-Cache Performance Optimizer service
rem plus Game Mode and Game Bar, or games spread over both CCDs and stutter.
echo.
echo  [7/8] AMD 3D V-Cache scheduling
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


:step_telemetry
rem The compatibility appraiser (CompatTelRunner.exe) can hold CPU and disk
rem at 100 percent for up to 20 minutes; the CEIP/feedback tasks add smaller
rem bursts. DiagTrack itself is light but always running. None of it raises
rem average FPS; it removes background bursts that land in the 0.1 percent lows.
echo.
echo  [8/8] Telemetry background activity
if not defined DO_DIAG echo   [INFO] DiagTrack unchanged: %DIAG_WHY%.& goto :tel_tasks
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
:tel_tasks
set "TASKN=0"
for %%T in (
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp"
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
    "\Microsoft\Windows\Application Experience\MareBackup"
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
    "\Microsoft\Windows\Autochk\Proxy"
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
    "\Microsoft\Windows\Feedback\Siuf\DmClient"
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
) do call :task_off %%T
if "%TASKN%"=="0" echo   [SKIP] None of the telemetry tasks exist on this build.
exit /b 0

:task_off
schtasks /query /tn %1 >nul 2>&1
if not "%errorlevel%"=="0" exit /b 0
set /a TASKN+=1
schtasks /change /tn %1 /disable >nul 2>&1
if "%errorlevel%"=="0" (echo   [ OK ] Task off: %~n1) else (echo   [FAIL] Could not disable task: %~n1)
exit /b 0


rem ==========================================================================
rem  Helpers and exits
rem ==========================================================================

:getdw
rem getdw "key" valueName outVar  - reads a REG_DWORD into outVar (decimal),
rem leaves outVar undefined when the value does not exist.
set "%~3="
for /f "tokens=3" %%V in ('reg query "%~1" /v %~2 2^>nul ^| findstr /c:"REG_DWORD"') do set /a "%~3=%%V"
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
