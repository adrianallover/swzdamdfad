# GameTune

`GameTune.bat` tunes Windows 10 (version 2004 or newer) and Windows 11 for in-game
frame delivery: 0.1% and 1% lows, average FPS and frametime consistency.

It applies only changes that current community benchmarking shows to have a real,
measurable effect on up-to-date Windows, including small or situational gains.
Popular tweaks that tested as placebo or are outdated are left out on purpose; the
reasons are [listed below](#deliberately-not-included).

The script writes no logs, exports, backups or restore points. It does not touch
network settings, power plans or `powercfg`, temp files, or disk cleanup.

## Usage

1. Double-click `GameTune.bat`. It asks for administrator rights.
2. Check the detected system and the list of planned changes, then press **Y**.
3. Restart. Most changes only take effect after a reboot.

Re-run the script after a Windows feature update or a GPU driver update, because
those can reset services, scheduled tasks and vendor telemetry.

## Options

Edit the values at the top of the script to change what it does.

| Option | Default | Other values | What it controls |
|---|---|---|---|
| `VBS_MODE` | `auto`: off unless FACEIT or Riot Vanguard is installed | `disable`, `keep` | VBS and Memory Integrity |
| `DIAGTRACK_MODE` | `auto`: off unless Xbox Gaming Services is installed | `disable`, `keep` | The DiagTrack telemetry service |
| `HAGS_MODE` | `on` | `keep` | Hardware-accelerated GPU scheduling |
| `AUTOHDR_MODE` | `off` | `keep` | Auto HDR |
| `POWERTHROTTLING_MODE` | `auto`: off on desktops with hybrid CPUs | `off`, `keep` | Power throttling of background processes |
| `CPU_MITIGATIONS_MODE` | `keep` | `off` | Spectre v2 and Meltdown mitigations |
| `DEFENDER_EXCLUSIONS_MODE` | `keep` | `add` | Defender exclusions for game libraries and shader caches |
| `STORE_APPS_BACKGROUND_MODE` | `keep` | `off` | Microsoft Store apps running in the background |
| `HYPERVISOR_MODE` | `keep` | `off` | Whether the hypervisor loads at boot |

The last four are off by default because they cost security or break something.
Turn them on if you accept that cost.

## What it changes

### Applied by default

| # | Change | Why it helps | When it applies |
|---|---|---|---|
| 1 | **VBS and Memory Integrity (HVCI) off**, plus Credential Guard and any Group Policy values that would keep VBS on | Memory Integrity costs about 5% average FPS in Tom's Hardware's tests, and more in the 1% lows of CPU-bound games. Microsoft's own gaming guidance lists turning it off. | Skipped when FACEIT or Riot Vanguard is installed. The explicit "off" value also opts the PC out of the automatic Memory Integrity enablement that starts with the October 13, 2026 Windows update. |
| 2 | **Game Mode on, Game Bar background recording off** | Game Mode measurably improves 1% lows when apps run in the background. Dual-CCD Ryzen X3D chips need it to park the non-V-Cache CCD. Background recording encodes video the whole time you play. | Always. Applied to the signed-in user, even when elevated with another admin account. |
| 3 | **Hardware-accelerated GPU scheduling on** | 2025 testing measured about +1.6% in 1% lows; DLSS and FSR frame generation need it. | Windows ignores the setting when the GPU or driver cannot do it. |
| 4 | **Optimizations for windowed games on** | Moves DX10/DX11 games that run windowed or borderless from the old "blt" presentation model to the flip model, lowering latency and enabling independent flip and VRR. It is off by default. | Windows 11 22H2 and newer. Other entries in the same setting are kept. |
| 5 | **Auto HDR off** | Auto HDR tone-maps every frame of SDR games while HDR is on, costing about 2–3% (3–6 FPS on an RTX 4070). | Windows 11. It only ever ran with HDR on; the other Auto HDR flags are kept. |
| 6 | **Fault Tolerant Heap off, and its program list cleared** | After repeated crashes, Windows silently moves a program onto the fault-tolerant heap, which is much slower. The script prints how many programs were on it. | Always. |
| 7 | **Memory manager**: page combining off, memory compression off, and the pagefile restored if it was disabled | Page combining periodically scans RAM and can hold a core at 100% for seconds. Memory compression spends CPU time on pages that fit in RAM anyway. A disabled pagefile, left over from old tweak guides, makes games crash or stutter when the commit limit runs out. | Page combining at 16 GB or more, memory compression at 32 GB or more. A custom pagefile is kept. |
| 8 | **Forced HPET removed** (`bcdedit useplatformclock`) | Forced HPET makes every timer query far slower, which costs FPS and causes stutter. | Only if an old tweak set it. |
| 9 | **Power throttling off** | On hybrid CPUs, Windows moves "background" processes to E-cores at reduced clocks. That catches game helper processes, shader compilers and games on a second monitor. This is a scheduler setting, not a power plan. | Desktops with hybrid CPUs: Intel 12th–14th gen, Core Ultra, Core 3/5/7, Ryzen AI 5/7/9. Laptops keep it for battery life unless you set `POWERTHROTTLING_MODE=off`. |
| 10 | **AMD 3D V-Cache Performance Optimizer checked** | Dual-CCD X3D chips need this service, Game Mode and Xbox Game Bar, or games spread across both CCDs and stutter. | Ryzen X3D CPUs. The service is re-enabled if something disabled it, and you get a warning if it or Game Bar is missing. |
| 11 | **Widgets and Edge background running off** | Widgets keeps a 50–150 MB web view loaded and refreshing. Edge's startup boost and background mode keep browser processes running after you close it. This matters most on 8–16 GB systems. | Windows 11 Widgets, or Windows 10 News and Interests. The Edge part only runs if Edge is installed. |
| 12 | **Windows telemetry background activity off**: Compatibility Appraiser, CEIP, Device Census, Feedback, SQM and error-report upload tasks; the inventory collector, application telemetry, CEIP and activity history; the DiagTrack service and its trace session; diagnostic data at the lowest level your edition allows | The appraiser (`CompatTelRunner.exe`) can hold CPU and disk at 100% for up to 20 minutes, and the other tasks add smaller bursts. This doesn't raise average FPS; it removes background bursts that show up in the 0.1% lows. | Only tasks that exist on your build. DiagTrack is kept when Xbox Gaming Services is installed, because Xbox achievements in PC games are reported through it. |
| 13 | **Vendor telemetry off** | Intel's System Usage Report service is documented to hold a full CPU core at times. NVIDIA's crash and telemetry reporter, AMD's User Experience Program and Office's telemetry agent run on schedules. The drivers don't need any of them. | Only the ones installed. NVIDIA's profile updater and driver tasks are left alone. |
| 14 | **SSD TRIM checked** | With TRIM off, SSD writes slow down over time, and asset streaming and shader-cache writes stutter. | Re-enabled only if something turned it off. |

### Optional (off by default)

| Step | Change | Gain | Cost |
|---|---|---|---|
| 11 | **Store apps can't run in the background** (`STORE_APPS_BACKGROUND_MODE=off`) | Fewer background processes. | Store apps such as WhatsApp or Phone Link stop notifying you while closed. |
| 15 | **Spectre v2 / Meltdown mitigations off** (`CPU_MITIGATIONS_MODE=off`) | Measured at about 4% in frametimes on Skylake and Kaby Lake. CPUs from 2019 on have hardware fixes and gain about 1%. | Any program that runs on the PC, including web pages, could use those attacks to read memory it shouldn't. |
| 16 | **Defender exclusions for games** (`DEFENDER_EXCLUSIONS_MODE=add`) | Faster loads and less asset-streaming and shader-compilation stutter. It excludes launcher libraries (Steam, including extra libraries; Epic; EA; Xbox; Ubisoft; GOG; Riot) and GPU shader caches. | Malware placed in those folders is not scanned in real time. Skipped when another antivirus is active. |
| 17 | **Hypervisor off** (`HYPERVISOR_MODE=off`) | About 1% in CPU-bound games when Hyper-V or Virtual Machine Platform is installed. | WSL2, Hyper-V, Windows Sandbox and Docker stop working. Refused when an anti-cheat needs VBS. |

Without its option, step 17 only reports whether Hyper-V or Virtual Machine Platform
is keeping the hypervisor loaded.

### What it detects first

- Windows build, edition and installation type. Server and builds older than 2004 are refused.
- CPU (including hybrid designs and X3D), core count, RAM, GPUs, laptop or desktop,
  and VBS state, through one read-only PowerShell/CIM query. If PowerShell is
  unavailable, the hardware-dependent steps are skipped.
- Anti-cheats that need VBS (FACEIT, Riot Vanguard) and EA Javelin, which asks for
  VBS-capable hardware but doesn't enforce VBS.
- VBS UEFI lock, Group Policy overrides, Credential Guard, and Windows Hello Enhanced
  Sign-in Security.
- Xbox Gaming Services, Hyper-V and Virtual Machine Platform, the AMD 3D V-Cache
  optimizer, Xbox Game Bar, Edge, the SysMain service, and the current pagefile setup.
- Which Windows telemetry tasks exist on this build, and which NVIDIA, AMD, Intel and
  Office telemetry components are installed.
- The account that is signed in, so per-user settings land in the right registry hive.
- 32-bit launchers: the script restarts itself as a 64-bit process to avoid registry
  redirection.

## Deliberately not included

These appear in most "ultimate" tweak scripts, but they either measure as placebo on
current Windows, are outdated, or are excluded by design.

| Tweak | Why it is left out |
|---|---|
| SysMain / Superfetch off | On SSD systems with enough RAM, the difference is within measurement noise. |
| Disable MPO (`OverlayTestMode`) | It is a fix for flicker, not a performance tweak, and Windows 11 24H2 and later reportedly ignore the value. |
| Fullscreen-optimization keys (`GameDVR_FSEBehavior...`) | Flip-model fullscreen optimizations measure the same as exclusive fullscreen. |
| `Win32PrioritySeparation` | `0x26` is identical to the client default `2`. Other values measure within noise. |
| MMCSS "Games" profile, `SystemResponsiveness` | Only threads registered with MMCSS use them, and most games don't register. |
| Timer resolution (`GlobalTimerResolutionRequests`, 0.5 ms tools) | Does nothing without a resident background process, and games already request 1 ms themselves. |
| `DisablePagingExecutive`, `LargeSystemCache`, `SvcHostSplitThresholdInKB`, IRQ priorities, `IoPageLockLimit` | Outdated, or no measurable effect on current Windows. |
| Disabling idle services (Fax, Print Spooler, Remote Registry, ...) | They don't run unless used, so turning them off changes nothing. |
| Removing Game Bar | Breaks CCD parking on dual-CCD X3D CPUs. |
| MSI-mode or interrupt-affinity changes | Modern GPU drivers already use MSI. Wrong values can stop a PC from booting. |
| Network tweaks (Nagle, throttling index, NIC settings), power plans, core parking, `powercfg`, temp and disk cleanup | Excluded by design. |

### One manual step worth doing

Xbox Game Bar's Gaming Copilot measurably lowers FPS when its model training and
screenshot options are on, and it has no supported registry or policy setting. Press
**Win+G**, open **Gaming Copilot**, then **Settings**:

- Under **Privacy**, turn off model training.
- Under **Capture**, turn off screenshots.

## Side effects

- Windows Security shows "Memory integrity is off". Dismiss it, or use `VBS_MODE=keep`.
- With Windows Hello Enhanced Sign-in Security, face and fingerprint sign-in stop
  working while VBS is off. Your PIN still works. The script warns you when this applies.
- If you force `VBS_MODE=disable` with FACEIT or Vanguard installed, those games can
  refuse to start until Memory Integrity is back on.
- With DiagTrack off, Xbox achievements in PC games don't unlock. That's why `auto`
  keeps it when Xbox Gaming Services is installed.
- The Widgets board disappears, and Edge opens slightly slower from cold.
- Edge and Settings may show "managed by your organization". This happens because the
  changes are made through policy settings.
- If VBS is UEFI-locked, the registry change can't turn it off. Use the UEFI-lock
  procedure in [Microsoft's memory integrity documentation](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity).

## Undo

Run these from an elevated Command Prompt, then restart.

```bat
:: 1. VBS / Memory Integrity back on (or: Windows Security > Device security > Core isolation)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /f

:: 2. Background recording: Settings > Gaming > Captures > "Record what happened"

:: 3. Hardware-accelerated GPU scheduling off (or: Settings > System > Display > Graphics)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v HwSchMode /t REG_DWORD /d 1 /f

:: 4. and 5. Windowed-game optimizations and Auto HDR:
::    Settings > System > Display > Graphics, and Settings > System > Display > HDR

:: 6. Fault Tolerant Heap back on
reg add "HKLM\SOFTWARE\Microsoft\FTH" /v Enabled /t REG_DWORD /d 1 /f

:: 7. Page combining and memory compression back on
powershell -NoProfile -Command "Enable-MMAgent -PageCombining; Enable-MMAgent -MemoryCompression"

:: 9. Power throttling back on
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /f

:: 11. Widgets / News and Interests, Edge background running, Store apps in the background
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /f

:: 12. Windows telemetry back on
sc config DiagTrack start= auto
sc start DiagTrack
reg add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" /v DisableInventory /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" /v AITEnable /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows" /v CEIPEnable /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v PublishUserActivities /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v UploadUserActivities /f
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable
::    ...and the same /enable for every other task the script listed as "Task off".

:: 13. Vendor telemetry: re-enable the services and tasks the script listed, for example
sc config ESRV_SVC_QUEENCREEK start= auto

:: 15. Spectre / Meltdown mitigations back on
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverride /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverrideMask /f

:: 16. Defender exclusions: Windows Security > Virus & threat protection > Manage settings > Exclusions

:: 17. Hypervisor back on
bcdedit /set hypervisorlaunchtype auto
```

Steps 8, 10 and 14 restore Windows or AMD defaults, and a re-enabled pagefile is
Windows' default, so none of them needs undoing. Group Policy values that the script
set to `0` are listed in its output.

## Sources

- VBS / HVCI cost: [Tom's Hardware benchmarks](https://www.tomshardware.com/news/windows-11-gaming-benchmarks-performance-vbs-hvci-security);
  Microsoft's gaming guidance, as [reported by gHacks](https://www.ghacks.net/2022/10/07/microsoft-turn-off-security-features-to-improve-windows-11-gaming-performance/).
- Automatic Memory Integrity enablement from October 2026, which respects existing opt-outs:
  [Help Net Security](https://www.helpnetsecurity.com/2026/09/03/windows-memory-integrity-update/),
  [VideoCardz](https://videocardz.com/newz/microsoft-will-enable-windows-11-memory-integrity-on-more-pcs-but-not-if-you-already-disabled-it).
- Anti-cheat requirements:
  [FACEIT TPM, Secure Boot, IOMMU and VBS rollout](https://www.faceit.com/en/news/faceit-rollout-of-tpm-secure-boot-iommu-and-vbs),
  [Riot VAN: RESTRICTION 5](https://support.riotgames.com/en-us/riot/penalties/error-van-restriction-5/),
  [Vanguard On-Demand requirements](https://www.tomshardware.com/video-games/pc-gaming/riot-vanguard-adds-an-on-demand-mode-that-stops-anti-cheat-loading-at-boot-on-secured-windows-11-pcs),
  [Battlefield 6 / Javelin](https://www.tweaktown.com/guides/11201/battlefield-6-official-pc-requirements-console-performance-and-mandatory-software/index.html).
- Game Mode: [MakeUseOf month-long test](https://www.makeuseof.com/i-tested-windows-game-mode-for-month-what-benchmarks-actually-showed/);
  X3D parking: [Phoronix](https://www.phoronix.com/review/amd-3d-vcache-optimizer-9950x3d),
  [Guru3D](https://forums.guru3d.com/threads/9950x3d-and-game-bar-requiements.456043/).
- HAGS: [2026 overview of 2025 test data](https://www.techbusinessnews.com.au/hardware-accelerated-gpu-scheduling-the-2025-2026-truth-nobodys-telling-you/),
  [digitnaut](https://www.digitnaut.com/2026/05/hardware-accelerated-gpu-scheduling-on-or-off.html).
- Windowed-game optimizations: [DirectX developer blog](https://devblogs.microsoft.com/directx/updates-in-graphics-and-gaming/),
  [BleepingComputer](https://www.bleepingcomputer.com/news/microsoft/windows-11-gaming-gets-significant-latency-and-hdr-improvements/).
- Auto HDR cost: [HardForum](https://hardforum.com/threads/does-hdr-impact-fps.2018942/),
  [fpscalculator](https://fpscalculator.net/blog/windows-11/best-windows-11-settings-for-gaming/).
- Fault Tolerant Heap: [Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/win7appqual/fault-tolerant-heap),
  [Chaos support](https://support.chaos.com/hc/en-us/articles/4528347128593--Fault-Tolerant-Heap-errors-and-solutions-3ds-Max).
- Page combining stalls: [Microsoft TechNet thread](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/f866e5a5-d7f8-43bb-a210-99b8738b62b9);
  memory compression: [How-To Geek](https://www.howtogeek.com/874099/how-to-enable-or-disable-memory-compression-in-windows-11/).
- Forced HPET: [Blur Busters forum](https://forums.blurbusters.com/viewtopic.php?t=13284&start=30).
- Power throttling / EcoQoS: [TweakTown](https://www.tweaktown.com/guides/11436/windows-11-is-secretly-throttling-your-apps-heres-how-to-catch-it/index.html),
  [Winaero](https://winaero.com/disable-power-throttling/).
- Widgets resource use: [MakeUseOf](https://www.makeuseof.com/news-interests-high-memory-cpu-usage-windows/),
  [Eleven Forum](https://www.elevenforum.com/t/enable-or-disable-widgets-feature-in-windows-11.1196/);
  Edge policies: [BackgroundModeEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled).
- Telemetry: [CompatTelRunner CPU/disk use](https://www.thewindowsclub.com/what-is-compattelrunner-exe-on-windows-10),
  [DiagTrack and Xbox achievements](https://www.thewindowsclub.com/xbox-achievements-not-showing),
  [Intel System Usage Report high CPU](https://www.thewindowsclub.com/what-is-energy-server-service-queencreek-process),
  [NVIDIA telemetry tasks](https://www.ghacks.net/2016/11/07/nvidia-telemetry-tracking/),
  [AMD User Experience Program](https://malwaretips.com/blogs/amd-user-experience-program-launcher/).
- TRIM: [Microsoft fsutil behavior](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-behavior).
- Spectre / Meltdown cost on older CPUs: [PCGamesN](https://www.pcgamesn.com/intel-security-patch-performance),
  [Microsoft](https://www.microsoft.com/en-us/security/blog/2018/01/09/understanding-the-performance-impact-of-spectre-and-meltdown-mitigations-on-windows-systems/),
  [KB4073119](https://support.microsoft.com/en-us/topic/kb4073119-windows-client-guidance-for-it-pros-to-protect-against-silicon-based-microarchitectural-and-speculative-execution-side-channel-vulnerabilities-35820a8a-ae13-1299-88cc-357f104f5b11).
- Defender and game loading: [Make Tech Easier](https://maketecheasier.com/improve-game-data-loading-times-in-windows/),
  [Guru3D](https://forums.guru3d.com/threads/exclude-files-accessed-by-game-process-from-ms-defender-real-time-protection.455013/).
- Hypervisor overhead: [Linus Tech Tips](https://linustechtips.com/topic/1022616-the-real-world-impact-of-hyper-v-on-gaming/).
- Excluded tweaks: [SysMain on NVMe](https://www.elevenforum.com/t/does-disabling-sysmain-superfetch-make-any-sense-with-an-nvme-system-drive.6625/),
  [MPO on 24H2](https://www.minitool.com/news/disable-windows-mpo.html),
  [Win32PrioritySeparation](https://www.tenforums.com/performance-maintenance/130775-win32priorityseparation-value-decimal-26-a.html),
  [timer resolution research](https://github.com/valleyofdoom/PC-Tuning/blob/main/docs/research.md),
  [Gaming Copilot FPS impact](https://www.techradar.com/computing/windows/pc-gamers-claim-windows-11s-gaming-copilot-is-capturing-gameplay-for-ai-training-by-default-but-what-its-actually-doing-is-spoiling-performance).
