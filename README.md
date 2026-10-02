# GameTune

`GameTune.bat` tunes Windows 10 (version 2004 or newer) and Windows 11 for in-game
frame delivery: 0.1% and 1% lows, average FPS and frametime consistency.

It applies only changes that current community benchmarking shows to have a real,
measurable effect on up-to-date Windows. Common tweaks that tested as placebo or
outdated are left out on purpose; the reasons are [listed below](#deliberately-not-included).

The script writes no logs, exports, backups or restore points. It does not touch
network settings, power plans or `powercfg`, temp files, or disk cleanup.

## Usage

1. Double-click `GameTune.bat`. It asks for administrator rights.
2. Check the detected system and the list of planned changes, then press **Y**.
3. Restart. VBS, the Fault Tolerant Heap, page combining and the boot clock setting
   only change after a reboot.

Re-run the script after a Windows feature update, because feature updates can reset
services and scheduled tasks.

Two options at the top of the script control the trade-offs:

| Option | `auto` (default) | `disable` | `keep` |
|---|---|---|---|
| `VBS_MODE` | Turn VBS / Memory Integrity off, unless FACEIT or Riot Vanguard is installed | Turn it off anyway | Never touch it |
| `DIAGTRACK_MODE` | Turn the DiagTrack service off, unless Xbox Gaming Services is installed | Turn it off anyway | Never touch it |

## What it changes

| # | Change | Why it helps | When it applies |
|---|---|---|---|
| 1 | **VBS and Memory Integrity (HVCI) off**, plus Credential Guard and any Group Policy values that would keep VBS on | Memory Integrity costs about 5% average FPS in Tom's Hardware's tests, and more in the 1% lows of CPU-bound games. Microsoft's own gaming guidance lists turning it off. | Skipped when FACEIT or Riot Vanguard is installed, because both can refuse to run without it. The explicit "off" value also opts the PC out of the automatic Memory Integrity enablement that starts with the October 13, 2026 Windows update. |
| 2 | **Game Mode on, Game Bar background recording off** | Game Mode measurably improves 1% lows when apps run in the background. Dual-CCD Ryzen X3D chips need it to park the non-V-Cache CCD. Background recording ("Record what happened") encodes video the whole time you play. | Always. Applied to the signed-in user, even when elevated with another admin account. |
| 3 | **Optimizations for windowed games on** | Moves DX10/DX11 games that run windowed or borderless with the old "blt" presentation model to the flip model. That lowers presentation latency and enables independent flip and VRR. It is off by default. | Windows 11 22H2 and newer. Your other entries in the same setting, such as VRR and Auto HDR, are kept. |
| 4 | **Fault Tolerant Heap off, and its program list cleared** | After repeated crashes, Windows silently moves a program onto the fault-tolerant heap, which is much slower. Turning FTH off only stops new entries, so the list is cleared too. The script prints how many programs were on it. | Always. |
| 5 | **Memory page combining off** | Page combining periodically scans RAM for identical pages and can hold a core at 100% for seconds, causing stalls and latency spikes. | 16 GB of RAM or more, and only when the SysMain service is running. Below 16 GB the memory it saves is worth keeping. |
| 6 | **Forced HPET removed** (`bcdedit useplatformclock`) | Old tweak guides set this. It forces HPET as the QueryPerformanceCounter source, which makes every timer query far slower, costs FPS and causes stutter. | Only if it is set. Otherwise nothing changes. |
| 7 | **AMD 3D V-Cache Performance Optimizer checked** | Dual-CCD X3D chips (7900X3D, 7950X3D, 9900X3D, 9950X3D) need this AMD service, Game Mode and Xbox Game Bar. Without them, games spread across both CCDs and stutter. | Ryzen X3D CPUs. The service is re-enabled if a debloat tool disabled it. You get a warning if the service or Game Bar is missing on a dual-CCD chip. |
| 8 | **Telemetry background activity off**: Compatibility Appraiser, CEIP and Feedback tasks; the DiagTrack service, its boot-time trace session, and diagnostic data at the lowest level your edition allows | The appraiser (`CompatTelRunner.exe`) can hold CPU and disk at 100% for up to 20 minutes, and the other tasks add smaller bursts. None of this raises average FPS. It removes background bursts that show up in the 0.1% lows. | Only tasks that exist on your build. DiagTrack is kept when Xbox Gaming Services is installed, because Xbox achievements in PC games are reported through it. |

### What it detects first

- Windows build, edition and installation type. Server and builds older than 2004 are refused.
- CPU, core count, RAM, GPUs and VBS state, through one read-only PowerShell/CIM query.
  If PowerShell is unavailable, steps that depend on hardware are skipped.
- Anti-cheats that need VBS (FACEIT, Riot Vanguard) and EA Javelin, which asks for
  VBS-capable hardware but does not enforce VBS.
- VBS UEFI lock, Group Policy overrides, Credential Guard, and Windows Hello Enhanced
  Sign-in Security.
- Hyper-V or Virtual Machine Platform, which keep the hypervisor running. These are
  reported but not removed, because WSL2, Docker and VMs depend on them.
- Xbox Gaming Services, the AMD 3D V-Cache optimizer, the Xbox Game Bar app, the
  SysMain service, and which telemetry tasks exist on this build.
- The account that is signed in, so per-user settings land in the right registry hive.
- 32-bit launchers: the script restarts itself as a 64-bit process to avoid registry
  redirection.

## Deliberately not included

| Tweak | Why it is left out |
|---|---|
| Memory compression off | No controlled benchmark shows a frametime gain. Below 16 GB it increases paging, which causes stutter. |
| SysMain / Superfetch off | On SSD systems with enough RAM, the difference is within measurement noise. |
| Hardware-accelerated GPU scheduling | Results range from about −2% to +3% depending on the game. It is already the default on Windows 11 and is required for DLSS/FSR frame generation, so it is left as is. |
| Disable MPO (`OverlayTestMode`) | It is a fix for flicker, not a performance tweak, and Windows 11 24H2 and later reportedly ignore the value. |
| `Win32PrioritySeparation` | `0x26` is identical to the client default `2`. Other values measure within noise. |
| Timer resolution (`GlobalTimerResolutionRequests`) | Does nothing without a background process that requests a higher resolution, and games already request 1 ms themselves. |
| Spectre / Meltdown mitigations off | Gains about 1% on current CPUs, and reopens real attack paths. |
| Removing Game Bar | Breaks CCD parking on dual-CCD X3D CPUs. |
| Removing Hyper-V / Virtual Machine Platform | About 1% in CPU-bound games, and it breaks WSL2, Docker and VMs. The script reports it instead. |
| `DisablePagingExecutive`, `LargeSystemCache`, `SvcHostSplitThresholdInKB`, IRQ priorities, MMCSS "Games" profile, fullscreen-optimization keys | Outdated, or no measurable effect on current Windows. |
| Network tweaks, power plans, core parking, temp/disk cleanup | Excluded by design. |

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
- With DiagTrack off, Xbox achievements in PC games do not unlock. That is why `auto`
  keeps it when Xbox Gaming Services is installed.
- If VBS is UEFI-locked, the registry change cannot turn it off. Use the UEFI-lock
  procedure in [Microsoft's memory integrity documentation](https://learn.microsoft.com/en-us/windows/security/hardware-security/enable-virtualization-based-protection-of-code-integrity).

## Undo

Run these from an elevated Command Prompt, then restart.

```bat
:: 1. VBS / Memory Integrity back on (or: Windows Security > Device security > Core isolation)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
::    Credential Guard back to the edition default
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LsaCfgFlags /f

:: 2. Background recording: Settings > Gaming > Captures > "Record what happened"

:: 3. Windowed-game optimizations: Settings > System > Display > Graphics
::    (per game, or the default graphics settings)

:: 4. Fault Tolerant Heap back on
reg add "HKLM\SOFTWARE\Microsoft\FTH" /v Enabled /t REG_DWORD /d 1 /f

:: 5. Page combining back on
powershell -NoProfile -Command "Enable-MMAgent -PageCombining"

:: 8. Telemetry back on
sc config DiagTrack start= auto
sc start DiagTrack
reg add "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener" /v Start /t REG_DWORD /d 1 /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable
::    ...and the same /enable for the other tasks the script listed as "Task off".
```

Step 6 restores the Windows default, and step 7 restores AMD's default, so neither
needs undoing. Group Policy values that the script set to `0` are listed in its output.

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
- Windowed-game optimizations: [DirectX developer blog](https://devblogs.microsoft.com/directx/updates-in-graphics-and-gaming/),
  [BleepingComputer](https://www.bleepingcomputer.com/news/microsoft/windows-11-gaming-gets-significant-latency-and-hdr-improvements/).
- Fault Tolerant Heap: [Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/win7appqual/fault-tolerant-heap),
  [Chaos support](https://support.chaos.com/hc/en-us/articles/4528347128593--Fault-Tolerant-Heap-errors-and-solutions-3ds-Max).
- Page combining stalls: [Microsoft TechNet thread](https://learn.microsoft.com/en-us/archive/msdn-technet-forums/f866e5a5-d7f8-43bb-a210-99b8738b62b9).
- Forced HPET: [Blur Busters forum](https://forums.blurbusters.com/viewtopic.php?t=13284&start=30).
- Telemetry: [CompatTelRunner CPU/disk use](https://www.thewindowsclub.com/what-is-compattelrunner-exe-on-windows-10),
  [DiagTrack and Xbox achievements](https://www.thewindowsclub.com/xbox-achievements-not-showing).
- Excluded tweaks: [SysMain on NVMe](https://www.elevenforum.com/t/does-disabling-sysmain-superfetch-make-any-sense-with-an-nvme-system-drive.6625/),
  [HAGS in 2026](https://www.digitnaut.com/2026/05/hardware-accelerated-gpu-scheduling-on-or-off.html),
  [MPO on 24H2](https://www.minitool.com/news/disable-windows-mpo.html),
  [Win32PrioritySeparation](https://www.tenforums.com/performance-maintenance/130775-win32priorityseparation-value-decimal-26-a.html),
  [timer resolution research](https://github.com/valleyofdoom/PC-Tuning/blob/main/docs/research.md),
  [Spectre/Meltdown guidance](https://support.microsoft.com/en-us/topic/kb4073119-windows-client-guidance-for-it-pros-to-protect-against-silicon-based-microarchitectural-and-speculative-execution-side-channel-vulnerabilities-35820a8a-ae13-1299-88cc-357f104f5b11),
  [Hyper-V overhead](https://linustechtips.com/topic/1022616-the-real-world-impact-of-hyper-v-on-gaming/),
  [Gaming Copilot FPS impact](https://www.techradar.com/computing/windows/pc-gamers-claim-windows-11s-gaming-copilot-is-capturing-gameplay-for-ai-training-by-default-but-what-its-actually-doing-is-spoiling-performance).
