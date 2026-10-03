# GameTune

`GameTune.bat` tunes Windows 10 (version 2004 or newer) and Windows 11 for in-game
frame delivery: 0.1% and 1% lows, average FPS and frametime consistency.

It applies only changes that current community benchmarking or vendor documentation
shows to have a real, measurable effect on up-to-date Windows, including small or
situational gains. Popular tweaks that tested as placebo or are outdated are left out
on purpose; the reasons are [listed below](#deliberately-not-included).

Besides Windows settings, it fixes the setup problems a script can reach: monitors left
at 60 Hz, games starting on the integrated GPU, and NVIDIA or AMD driver settings that
cause shader stutter. At the end it lists, biggest gain first, the problems only you
can fix, such as XMP or EXPO turned off, memory in one channel, a monitor plugged into
the motherboard, or a graphics card on a narrow PCIe link. Those usually matter more
than any Windows setting.

The script writes no logs, exports, backups or restore points. It does not touch
network settings, power plans or `powercfg`, and it deletes no files. Its only disk
cleanup change keeps the DirectX shader cache out of Windows' automatic cleanup.

[`NetTune.bat`](NetTune.md) is the companion script for ping, jitter, lag spikes,
bufferbloat and packet loss. It changes only network settings, so it doesn't overlap
with GameTune.

## Usage

1. Double-click `GameTune.bat`. It asks for administrator rights.
2. Check the detected system and the list of planned changes, then press **Y**.
3. If a monitor is switched to a higher refresh rate, press **Y** within 15 seconds to
   keep it. Without an answer, or if the screen stays black, it switches back by itself.
4. Read the list at the end: those fixes are yours to make.
5. Restart. Most changes only take effect after a reboot.

Re-run the script after a Windows feature update, a GPU driver update or new game
installs, because updates can reset services, scheduled tasks and driver settings, and
new games need their GPU preference.

## Options

Edit the values at the top of the script to change what it does.

| Option | Default | Other values | What it controls |
|---|---|---|---|
| `VBS_MODE` | `auto`: off unless FACEIT or Riot Vanguard is installed | `disable`, `keep` | VBS and Memory Integrity |
| `DIAGTRACK_MODE` | `auto`: off unless Xbox Gaming Services is installed | `disable`, `keep` | The DiagTrack telemetry service |
| `HAGS_MODE` | `on` | `off`, `keep` | Hardware-accelerated GPU scheduling. Its effect is a few percent either way and differs per game: if your 1% lows got worse, test once with `off` |
| `AUTOHDR_MODE` | `off` | `keep` | Auto HDR |
| `POWERTHROTTLING_MODE` | `auto`: off on desktops with hybrid CPUs | `off`, `keep` | Power throttling of background processes |
| `REFRESH_MODE` | `max` | `keep` | Each monitor at the highest refresh rate it offers at its current resolution, kept only when you confirm it |
| `VRR_MODE` | `on` | `keep` | Windows' variable refresh rate for DX11 games without their own VRR support |
| `GPU_PREFERENCE_MODE` | `auto`: only on PCs with two GPUs | `keep` | Installed games set to the high-performance GPU in Windows graphics settings |
| `NVIDIA_MODE` | `fix` | `keep` | NVIDIA global settings that cost FPS or cause stutter, set back to NVIDIA's defaults |
| `AMD_MODE` | `fix` | `keep` | AMD shader cache set back to its default when it was turned off |
| `SHADER_CACHE_MODE` | `protect` | `keep` | The DirectX shader cache kept out of Windows' automatic disk cleanup |
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
| 3 | **Hardware-accelerated GPU scheduling on** | Effects are small and go both ways. One 2025 overview found about +1.6% in 1% lows, while PC Games Hardware found stutter in Red Dead Redemption 2 on Vulkan. DLSS frame generation needs it, and FSR 3 frame generation paces better with it. If your lows got worse, test with `HAGS_MODE=off`. | Windows ignores the setting when the GPU or driver cannot do it. |
| 4 | **Optimizations for windowed games on** | Moves DX10/DX11 games that run windowed or borderless from the old "blt" presentation model to the flip model, lowering latency and enabling independent flip and VRR. It is off by default. | Windows 11 22H2 and newer. Other entries in the same setting are kept. |
| 5 | **Variable refresh rate for games without their own support on** | Since the Windows 10 May 2019 Update, Windows can give full-screen DX11 games that don't support VRR natively G-SYNC or FreeSync. Without VRR, a frame rate below the refresh rate is shown with judder or tearing. | Has an effect only with a VRR monitor, G-SYNC or FreeSync turned on in the driver, and a WDDM 2.6 or newer driver. Other entries in the same setting are kept. |
| 6 | **Auto HDR off** | Auto HDR tone-maps every frame of SDR games while HDR is on, costing about 2–3% (3–6 FPS on an RTX 4070). | Windows 11. It only ever ran with HDR on; the other Auto HDR flags are kept. |
| 7 | **Each monitor at its highest refresh rate** | Windows doesn't always pick a monitor's highest refresh rate, and driver reinstalls can drop it back to 60 Hz. At 60 Hz, V-Sync or a refresh-tied cap holds games at 60 FPS, and every frame reaches the screen later. | Monitors whose current resolution and colour depth offer a higher rate. The driver tests the mode first, then you confirm it within 15 seconds; without an answer it switches back. Interlaced modes are never used. |
| 8 | **Installed games on the high-performance GPU** | On a PC with two GPUs, a game the driver doesn't recognise can start on the integrated GPU at a fraction of the frame rate; Minecraft: Java Edition is the classic case. The per-program choice in Windows graphics settings takes precedence over the NVIDIA and AMD ones. | PCs where Windows ranks a different GPU for power saving than for high performance: laptops with two GPUs, and desktops with the processor's graphics enabled. Games are found through Steam (every library), Epic, GOG, Ubisoft, the installed-program records of EA, Battle.net, Riot, Rockstar and other publishers, Minecraft's Java runtime, and Windows' own list of recognised games. Installers, crash reporters, anti-cheat services, launchers and updaters are left out. A program someone set to power saving is kept and reported. Other entries of each program's setting are kept. |
| 9 | **NVIDIA settings that cost FPS or cause stutter, back to NVIDIA's defaults**: shader cache turned off; shader cache size below the driver default; threaded optimization forced off; preferred graphics processor set to integrated | With the shader cache off, games compile their shaders again at every start and stutter while they do. With a cache smaller than the default, the driver throws compiled shaders away and games compile them again mid-game; NVIDIA says reducing it "may negatively impact performance". The default grew with the drivers: 4 GB up to R565, 8 GB in R570, 12 GB in R580, 16 GB from R590. Threaded optimization forced off makes CPU-bound OpenGL games (Minecraft: Java Edition, emulators) do all driver work on one thread. "Integrated graphics" as the preferred processor puts every game without its own NVIDIA profile on the integrated GPU. | NVIDIA graphics. Only the global profile, and only these settings; per-game profiles and everything else stay as they are. A larger or unlimited cache is kept. |
| 10 | **AMD shader cache back on** | Same effect as on NVIDIA: with it off, games compile their shaders again at every start. It goes back to AMD optimized, the default. | AMD graphics, only when the cache is set to Off. The value keeps the type the driver stored it in. |
| 11 | **DirectX shader cache kept out of automatic disk cleanup** | Microsoft's shader cache specification says the cache can be cleared by disk cleanup. Windows' automatic cleanup runs when a drive gets low on space, and games then compile their shaders again, with stutter. | Sets the cleanup handler's `Autorun` value to 0 in the 64-bit and 32-bit registry views. Disk Cleanup can still clear the cache by hand. NVIDIA's and AMD's own caches aren't part of Windows' cleanup. |
| 12 | **Fault Tolerant Heap off, and its program list cleared** | After repeated crashes, Windows silently moves a program onto the fault-tolerant heap, which is much slower. The script prints how many programs were on it. | Always. |
| 13 | **Memory manager**: page combining off, and the pagefile restored if it was disabled | Page combining periodically scans RAM and can hold a core at 100% for seconds. A disabled pagefile, left over from old tweak guides, makes games crash or stutter when the commit limit runs out. | Page combining at 16 GB or more. A custom pagefile is kept. |
| 14 | **Forced HPET removed** (`bcdedit useplatformclock`) | Forced HPET makes every timer query far slower, which costs FPS and causes stutter. | Only if an old tweak set it. |
| 15 | **Power throttling off** | On hybrid CPUs, Windows moves "background" processes to E-cores at reduced clocks. That catches game helper processes, shader compilers and games on a second monitor. This is a scheduler setting, not a power plan. | Desktops with hybrid CPUs: Intel 12th–14th gen, Core Ultra, Core 3/5/7, Ryzen AI 5/7/9. Laptops keep it for battery life unless you set `POWERTHROTTLING_MODE=off`. |
| 16 | **AMD 3D V-Cache Performance Optimizer checked** | Dual-CCD X3D chips need this service, Game Mode and Xbox Game Bar, or games spread across both CCDs and stutter. | Ryzen X3D CPUs. The service is re-enabled if something disabled it, and you get a warning if it or Game Bar is missing. |
| 17 | **Widgets and Edge background running off** | Widgets keeps a 50–150 MB web view loaded and refreshing. Edge's startup boost and background mode keep browser processes running after you close it. This matters most on 8–16 GB systems. | Windows 11 Widgets, or Windows 10 News and Interests. The Edge part only runs if Edge is installed. |
| 18 | **Windows telemetry background activity off**: Compatibility Appraiser, CEIP, Device Census, Feedback, SQM and error-report upload tasks; the inventory collector, application telemetry, CEIP and activity history; the DiagTrack service and its trace session; diagnostic data at the lowest level your edition allows | The appraiser (`CompatTelRunner.exe`) can hold CPU and disk at 100% for up to 20 minutes, and the other tasks add smaller bursts. This doesn't raise average FPS; it removes background bursts that show up in the 0.1% lows. | Only tasks that exist on your build. DiagTrack is kept when Xbox Gaming Services is installed, because Xbox achievements in PC games are reported through it. |
| 19 | **Vendor telemetry off** | Intel's System Usage Report service is documented to hold a full CPU core at times. NVIDIA's crash and telemetry reporter, AMD's User Experience Program and Office's telemetry agent run on schedules. The drivers don't need any of them. | Only the ones installed. NVIDIA's profile updater and driver tasks are left alone. |
| 20 | **SSD TRIM checked** | With TRIM off, SSD writes slow down over time, and asset streaming and shader-cache writes stutter. | Re-enabled only if something turned it off. |

### Optional (off by default)

| Step | Change | Gain | Cost |
|---|---|---|---|
| 17 | **Store apps can't run in the background** (`STORE_APPS_BACKGROUND_MODE=off`) | Fewer background processes. | Store apps such as WhatsApp or Phone Link stop notifying you while closed. |
| 21 | **Spectre v2 / Meltdown mitigations off** (`CPU_MITIGATIONS_MODE=off`) | Measured at about 4% in frametimes on Skylake and Kaby Lake. CPUs from 2019 on have hardware fixes and gain about 1%. | Any program that runs on the PC, including web pages, could use those attacks to read memory it shouldn't. |
| 22 | **Defender exclusions for games** (`DEFENDER_EXCLUSIONS_MODE=add`) | Faster loads and less asset-streaming and shader-compilation stutter. It excludes launcher libraries (Steam, including extra libraries; Epic; EA; Xbox; Ubisoft; GOG; Riot) and GPU shader caches. | Malware placed in those folders is not scanned in real time. Skipped when another antivirus is active. |
| 23 | **Hypervisor off** (`HYPERVISOR_MODE=off`) | About 1% in CPU-bound games when Hyper-V or Virtual Machine Platform is installed. | WSL2, Hyper-V, Windows Sandbox and Docker stop working. Refused when an anti-cheat needs VBS. |

Without its option, step 23 only reports whether Hyper-V or Virtual Machine Platform
is keeping the hypervisor loaded.

### What it lists for you to fix (step 24)

These cost FPS or 1% lows, but no script can or should change them. GameTune checks
each one and lists the problems it finds, biggest gain first.

| Problem | How it is found | What it costs |
|---|---|---|
| Monitor plugged into the motherboard | A desktop monitor driven by the GPU Windows ranks for power saving | Every frame is copied from the graphics card to the processor's graphics first |
| Laptop on battery | Battery discharging | Laptops cut CPU and GPU power; NVIDIA Battery Boost caps games at 30 FPS |
| XMP or EXPO off | Memory running below the speed in its part number | 17–20% average FPS and about 30% of the 1% lows in Hardware Unboxed's test |
| One memory channel | One stick, or all sticks in the same channel | About 12% average FPS and 16% of the 1% lows in Hardware Unboxed's test; under 3% on X3D CPUs |
| Monitor connection limits the refresh rate | The monitor's EDID reports 100 Hz or more, but the connection offers 75 Hz or less at the current resolution | Games held at 60 FPS with V-Sync. Often an HDMI 1.4 port, an old cable or an adapter |
| A frame rate cap in the driver | NVIDIA's global Max Frame Rate well below the refresh rate, or Radeon Chill on for all games | Every game capped, or slowed whenever little moves |
| Less than 16 GB of memory | Installed memory | Current games page to disk, which shows up as stutter |
| Graphics card on fewer PCIe lanes | `nvidia-smi` link width below the card's maximum, or x4 on a desktop | Lower FPS, most of all on cards with 8 GB or less when video memory runs full |
| Games on a hard drive | Steam and Epic library drives | Hitches while textures and levels stream in |
| No MUX switch mode on a laptop | Laptop screen driven by the integrated GPU | 10–17% more FPS in tests with the GPU mode set to discrete, where the laptop has a MUX switch or Advanced Optimus |
| Missing Windows scheduling updates | Windows 10 on hybrid Intel CPUs (no Thread Director), or a Ryzen without the branch-prediction update of Windows 11 24H2 (23H2 got it with KB5041587) | Ryzen: 10–11% average FPS in Hardware Unboxed's test |
| Nearly full drive | Less than 10% or 15 GB free | Slow SSD writes; shader caches can't grow |
| 8 GB of video memory or less | DXGI | 1% lows collapse when textures don't fit: one step below the highest texture setting helps |
| HWiNFO and RGB software together | Running processes | Both poll the motherboard's SMBus; the collisions cause periodic stutter |
| Graphics driver older than a year | Driver date | New games get their performance fixes in newer drivers |
| Intel 13th/14th gen microcode before 0x12B | CPU microcode revision | Not FPS: the crashes and CPU degradation Intel fixed |
| Resizable BAR off (NVIDIA) | `nvidia-smi` BAR1 size | 2–4% in the games NVIDIA enables it for. For AMD (7–16% at 1080p) and Intel Arc (about 25%) it shows where to check |

It also notes software known to cost FPS while you play: the NVIDIA overlay's Game
Filters, clip recorders such as Medal and Overwolf, and short polling periods in MSI
Afterburner.

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
- Monitors, their modes and EDID, which GPU drives each one, and how Windows ranks the
  GPUs for power saving and high performance (DXGI).
- NVIDIA driver settings through NVAPI, AMD driver settings in the display adapter's
  registry key, and the installed games.
- The account that is signed in, so per-user settings land in the right registry hive.
- 32-bit launchers: the script restarts itself as a 64-bit process to avoid registry
  redirection.

## Deliberately not included

These appear in most "ultimate" tweak scripts, but they either measure as placebo on
current Windows, are outdated, or are excluded by design.

| Tweak | Why it is left out |
|---|---|
| SysMain / Superfetch off | On SSD systems with enough RAM, the difference is within measurement noise. |
| Memory compression off | No consistent benchmark gain, and when memory runs short it is faster than paging to disk. GameTune versions before this one turned it off at 32 GB or more; the undo section turns it back on. |
| Disable MPO (`OverlayTestMode`) | It is a fix for flicker, not a performance tweak, and Windows 11 24H2 and later reportedly ignore the value. |
| Fullscreen-optimization keys (`GameDVR_FSEBehavior...`) | Flip-model fullscreen optimizations measure the same as exclusive fullscreen. |
| `Win32PrioritySeparation` | `0x26` is identical to the client default `2`. Other values measure within noise. |
| MMCSS "Games" profile, `SystemResponsiveness` | Only threads registered with MMCSS use them, and most games don't register. |
| Timer resolution (`GlobalTimerResolutionRequests`, 0.5 ms tools) | Does nothing without a resident background process, and games already request 1 ms themselves. |
| `DisablePagingExecutive`, `LargeSystemCache`, `SvcHostSplitThresholdInKB`, IRQ priorities, `IoPageLockLimit` | Outdated, or no measurable effect on current Windows. |
| Disabling idle services (Fax, Print Spooler, Remote Registry, ...) | They don't run unless used, so turning them off changes nothing. |
| Removing Game Bar | Breaks CCD parking on dual-CCD X3D CPUs. |
| MSI-mode or interrupt-affinity changes | Modern GPU drivers already use MSI. Wrong values can stop a PC from booting. |
| NVIDIA "Prefer maximum performance", every app on the NVIDIA GPU | The first is GPU power management, the second keeps the discrete GPU awake for every program. Games get the high-performance GPU per program instead. |
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
- A higher refresh rate draws a little more power, more so on laptops on battery; with
  several monitors, some graphics cards then keep their memory clock up at idle.
- Settings > System > Display > Graphics lists every game GameTune set to the
  high-performance GPU.
- The NVIDIA shader cache can grow to the driver default (16 GB with current drivers),
  and the DirectX shader cache stays on disk until you clear it by hand.
- The monitor, GPU and NVIDIA steps compile a small C# helper when they run. Windows'
  C# compiler writes its temporary files to `%TEMP%` while it runs and removes them
  afterwards.
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

:: 4. 5. and 6. Windowed-game optimizations, variable refresh rate and Auto HDR:
::    Settings > System > Display > Graphics, and Settings > System > Display > HDR

:: 7. Refresh rate: Settings > System > Display > Advanced display > Choose a refresh rate

:: 8. GPU preference per game: Settings > System > Display > Graphics, pick the game,
::    then Options > Let Windows decide, or Remove

:: 9. NVIDIA: NVIDIA Control Panel > Manage 3D settings > Global Settings
:: 10. AMD: AMD Software > Gaming > Graphics > Shader Cache

:: 11. DirectX shader cache back in automatic disk cleanup
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\D3D Shader Cache" /v Autorun /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\D3D Shader Cache" /v Autorun /t REG_DWORD /d 1 /f

:: 12. Fault Tolerant Heap back on
reg add "HKLM\SOFTWARE\Microsoft\FTH" /v Enabled /t REG_DWORD /d 1 /f

:: 13. Page combining back on; memory compression, if an older GameTune turned it off
powershell -NoProfile -Command "Enable-MMAgent -PageCombining; Enable-MMAgent -MemoryCompression"

:: 15. Power throttling back on
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v PowerThrottlingOff /f

:: 17. Widgets / News and Interests, Edge background running, Store apps in the background
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v StartupBoostEnabled /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v BackgroundModeEnabled /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /f

:: 18. Windows telemetry back on
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

:: 19. Vendor telemetry: re-enable the services and tasks the script listed, for example
sc config ESRV_SVC_QUEENCREEK start= auto

:: 21. Spectre / Meltdown mitigations back on
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverride /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v FeatureSettingsOverrideMask /f

:: 22. Defender exclusions: Windows Security > Virus & threat protection > Manage settings > Exclusions

:: 23. Hypervisor back on
bcdedit /set hypervisorlaunchtype auto
```

Steps 14, 16 and 20 restore Windows or AMD defaults, and a re-enabled pagefile is
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
- HAGS: [PC Games Hardware benchmark](https://www.pcgameshardware.de/Windows-Software-277633/Specials/HAGS-Benchmark-Test-1352947/),
  [Gamers Nexus](https://gamersnexus.net/guides/3599-windows-10-hardware-accelerated-gpu-scheduling-benchmarks),
  [2026 overview of 2025 test data](https://www.techbusinessnews.com.au/hardware-accelerated-gpu-scheduling-the-2025-2026-truth-nobodys-telling-you/),
  [digitnaut](https://www.digitnaut.com/2026/05/hardware-accelerated-gpu-scheduling-on-or-off.html),
  [NVIDIA Streamline, DLSS frame generation requirements](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md).
- Windowed-game optimizations: [DirectX developer blog](https://devblogs.microsoft.com/directx/updates-in-graphics-and-gaming/),
  [BleepingComputer](https://www.bleepingcomputer.com/news/microsoft/windows-11-gaming-gets-significant-latency-and-hdr-improvements/).
- Variable refresh rate for DX11 games: [Tom's Hardware](https://www.tomshardware.com/news/windows-10-variable-refresh-rate-vrr-dx11,39582.html),
  [Eleven Forum, the `VRROptimizeEnable` entry](https://www.elevenforum.com/t/enable-or-disable-variable-refresh-rate-for-games-in-windows-11.12052/).
- Auto HDR cost: [HardForum](https://hardforum.com/threads/does-hdr-impact-fps.2018942/),
  [fpscalculator](https://fpscalculator.net/blog/windows-11/best-windows-11-settings-for-gaming/).
- Refresh rate: [TechSpot](https://www.techspot.com/article/2423-how-to-change-refresh-rate/),
  [How-To Geek on Windows dropping to 60 Hz](https://www.howtogeek.com/windows-is-automatically-kicking-your-high-refresh-monitor-back-to-60hz-without-telling-you/),
  [Blur Busters](https://blurbusters.com/oh-no-im-at-the-wrong-refresh-rate/),
  [Tom's Hardware, DisplayPort vs HDMI](https://www.tomshardware.com/features/displayport-vs-hdmi-better-for-gaming);
  mode changes: [`ChangeDisplaySettingsEx`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexw),
  [`EnumDisplayDevices`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaydevicesw);
  EDID range limits: [VESA E-EDID](https://github.com/glenwing/glenwing.github.io/blob/master/docs/VESA-EEDID-A2.pdf),
  [Linux `drm_edid.c`](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_edid.c).
- GPU preference: Microsoft, [build 17093 announcement](https://blogs.windows.com/windows-insider/2018/02/07/announcing-windows-10-insider-preview-build-17093-pc/)
  ("will take precedence over the other control panel settings"),
  [`EnumAdapterByGpuPreference`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_6/nf-dxgi1_6-idxgifactory6-enumadapterbygpupreference),
  [AMD GPU-110](https://www.amd.com/en/resources/support-articles/faqs/GPU-110.html),
  [value format in 3D Slicer's installer](https://github.com/Slicer/Slicer/blob/main/CMake/SlicerCPack.cmake),
  [MultiMC FAQ on Java games and switchable graphics](https://github.com/MultiMC/MultiMC5/wiki/FAQ),
  [NotebookCheck, integrated vs discrete GPU](https://www.notebookcheck.net/AMD-Dynamic-Switchable-Graphics-vs-Nvidia-Optimus.64378.0.html).
- NVIDIA driver settings: [NVAPI SDK, setting IDs and defaults](https://github.com/NVIDIA/nvapi/blob/main/NvApiDriverSettings.h),
  [NVIDIA Profile Inspector, cache size values in MB](https://github.com/Orbmu2k/nvidiaProfileInspector/blob/master/nvidiaProfileInspector/CustomSettingNames.xml),
  [NVIDIA KB 5735, default 16 GB](https://nvidia.custhelp.com/app/answers/detail/a_id/5735),
  [NVIDIA Customer Care on lowering it](https://x.com/nvidiacc/status/2022096208987304343),
  [Optimus profile settings](https://github.com/opengl-tutorials/ogl/blob/master/distrib/selectoptimus.cpp).
- AMD shader cache values: [MPO-GPU-FIX](https://github.com/RedDot-3ND7355/MPO-GPU-FIX/blob/master/AMDGPUFIX/AMDGPUFIX/SHADERCACHE.cs),
  [shoober420 AMD GPU tweaks](https://github.com/shoober420/windows11-scripts/blob/main/AMDGPUTweaks.bat);
  Radeon Chill: [AutoOS](https://github.com/tinodin/AutoOS/blob/master/src/AutoOS.Core/Helpers/GPU/AmdHelper.cs).
- DirectX shader cache and cleanup: [Microsoft DirectX-Specs, shader cache](https://github.com/microsoft/DirectX-Specs/blob/master/d3d/ShaderCache.md),
  [Microsoft Q&A: DX cache cleared](https://learn.microsoft.com/en-us/answers/questions/4111991/why-windows-is-clearing-my-dx-cache-everytime),
  [`Autorun` and automatic cleanup](https://www.tenforums.com/tutorials/103762-prevent-windows-10-deleting-thumbnail-cache.html),
  [disk cleanup handlers](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/lwef/disk-cleanup.md).
- Fault Tolerant Heap: [Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/win7appqual/fault-tolerant-heap),
  [Chaos support](https://support.chaos.com/hc/en-us/articles/4528347128593--Fault-Tolerant-Heap-errors-and-solutions-3ds-Max).
- Page combining stalls: [Microsoft TechNet thread](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/f866e5a5-d7f8-43bb-a210-99b8738b62b9).
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
- Findings:
  memory channels: [TechSpot / Hardware Unboxed](https://www.techspot.com/article/3066-single-stick-vs-dual-channel-ram/),
  [Tom's Hardware, single DDR5 DIMM on X3D](https://www.tomshardware.com/pc-components/ddr5/single-dimm-ddr5-gaming-works-better-than-you-probably-think-amds-3d-v-cache-chips-drop-less-than-3-percent-one-ddr5-dimm-beats-dual-channel-ddr4-ram);
  XMP and EXPO: [TechSpot / Hardware Unboxed](https://www.techspot.com/review/2866-ddr5-ram-stock-vs-xmp-expo/);
  Intel microcode: [Intel root-cause statement](https://community.intel.com/t5/Blogs/Tech-Innovation/Client/Intel-Core-13th-and-14th-Gen-Desktop-Instability-Root-Cause/post/1633239);
  Thread Director: [Intel](https://www.intel.com/content/www/us/en/support/articles/000091284/processors.html),
  [TechSpot](https://www.techspot.com/review/2358-intel-alder-lake-windows-11-benchmark/);
  Ryzen branch prediction: [TechSpot / Hardware Unboxed](https://www.techspot.com/review/2888-ryzen-9700-vs-7700-windows-24h2/),
  [AMD community update](https://www.elevenforum.com/t/amd-ryzen-9000-series-community-update-on-gaming-performance.27841/),
  [KB5041587](https://support.microsoft.com/en-us/servicing/os/windows-11/2024/08/august-27-2024-kb5041587-os-builds-22621-4112-and-22631-4112-preview),
  [Tom's Hardware on the 23H2 backport](https://www.tomshardware.com/software/windows/microsoft-backports-branch-prediction-improvements-to-windows-11-23h2-more-users-will-see-ryzen-performance-improvements);
  Resizable BAR: [TechPowerUp, NVIDIA](https://www.techpowerup.com/review/nvidia-pci-express-resizable-bar-performance-test/),
  [TechSpot, AMD Smart Access Memory](https://www.techspot.com/article/2178-amd-smart-access-memory/),
  [Tom's Hardware, Arc without ReBAR](https://www.tomshardware.com/news/arc-a770-loses-25-percent-performance-without-resizable-bar);
  PCIe link width: [TechSpot, RTX 5060 Ti PCIe](https://www.techspot.com/review/3004-nvidia-rtx-5060-ti-pcie-benchmark/);
  video memory: [TechSpot, 8 GB vs 16 GB](https://www.techspot.com/article/2661-vram-8gb-vs-16gb/);
  laptops: [Jarrod's Tech, MUX switch](https://jarrods.tech/what-is-a-mux-switch-for-gaming-laptops/),
  [NVIDIA Battery Boost](https://www.notebookcheck.net/Nvidia-Battery-Boost-Review.116939.0.html);
  RGB software and SMBus: [How-To Geek](https://www.howtogeek.com/microstutter-in-games-your-rgb-software-might-be-at-fault/),
  [ROG forum, iCUE and HWiNFO](https://rog-forum.asus.com/t5/amd-600-series/icue-hwinfo64-causing-issues/td-p/900264);
  MSI Afterburner polling: [ResetEra](https://www.resetera.com/threads/psa-msi-afterburner-may-be-the-cause-for-stutters-in-your-games.1072485/);
  NVIDIA App Game Filters: [Tom's Hardware](https://www.tomshardware.com/pc-components/gpu-drivers/nvidia-has-a-fix-for-up-to-15-percent-gaming-performance-loss-caused-by-the-nvidia-app-disabling-feature-restores-performance),
  [BleepingComputer](https://www.bleepingcomputer.com/news/software/nvidia-shares-fix-for-game-performance-issues-with-new-nvidia-app/);
  G-SYNC frame rate cap: [Blur Busters](https://blurbusters.com/gsync/gsync101-input-lag-tests-and-settings/14/).
- Excluded tweaks: [SysMain on NVMe](https://www.elevenforum.com/t/does-disabling-sysmain-superfetch-make-any-sense-with-an-nvme-system-drive.6625/),
  [MPO on 24H2](https://www.minitool.com/news/disable-windows-mpo.html),
  [Win32PrioritySeparation](https://www.tenforums.com/performance-maintenance/130775-win32priorityseparation-value-decimal-26-a.html),
  [timer resolution research](https://github.com/valleyofdoom/PC-Tuning/blob/main/docs/research.md),
  [Gaming Copilot FPS impact](https://www.techradar.com/computing/windows/pc-gamers-claim-windows-11s-gaming-copilot-is-capturing-gameplay-for-ai-training-by-default-but-what-its-actually-doing-is-spoiling-performance).
