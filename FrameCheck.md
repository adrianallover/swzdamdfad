# FrameCheck

`FrameCheck.bat` finds what holds back FPS and makes the 1% and 0.1% lows dip on your
PC. It changes nothing: it reads the hardware, Windows settings and performance
counters, and tells you what to fix and how much each fix is worth.

It writes no files, logs or exports. Everything it finds is shown in its window. (It
compiles a small C# helper when it starts; Windows' compiler creates and removes its
own temporary files for that.)

The biggest causes of low FPS and dips are often hardware setup, not Windows:

- memory running in one channel, or without its XMP or EXPO profile;
- a monitor set to 60 Hz, or plugged into the motherboard instead of the graphics
  card;
- a graphics card on a narrow PCIe link;
- games on a hard drive;
- full video memory.

No tweak script can fix these, and each costs more than every Windows setting
together. [`GameTune.bat`](README.md) handles the Windows side,
[`NetTune.bat`](NetTune.md) the network.

## Usage

1. Double-click `FrameCheck.bat`. It asks for administrator rights, which some checks
   need. It changes nothing.
2. Read the check (part 1). The list at the end sums up what to fix.
3. Optionally press **Y** to start the in-game monitor (part 2), then start your game.
   Play normally for at least 10 minutes, ideally where your FPS dips.
4. Switch back to the FrameCheck window and press **Q**. The monitor reports what
   happened while you played. Don't press Ctrl+C: that closes FrameCheck before it
   reports.

The monitor stops on its own after `MONITOR_MINUTES` (60 by default; set at the top of
the script, 1 to 240). It is light: it reads the counters once a second and the
per-program CPU use every 2 seconds.

## Part 1: the check

### Processor

- **Two-CCD Ryzen X3D (7900X3D, 7950X3D, 9900X3D, 9950X3D).** AMD's driver parks the
  cores without the extra cache while a game runs. It relies on Game Bar to recognise
  the game, so it needs all three of these; FrameCheck checks each:
  - the AMD 3D V-Cache Performance Optimizer service, from the chipset driver;
  - Xbox Game Bar;
  - Game Mode.

  Without them, games also run on the slower cores.
- **Intel Core 13th and 14th gen desktop.** The microcode revision is checked against
  0x12B, Intel's fix for the voltage problem that crashes and slowly damages these
  CPUs. It doesn't change FPS; it protects the CPU. 0x12F is the latest.
- **Windows 10.**
  - Intel 12th gen and newer: Windows 10 lacks Thread Director, so game threads can
    land on E-cores.
  - Ryzen 5000 and newer: Windows 10 lacks the branch-prediction changes that gave
    about 10% more FPS in Windows 11 24H2.

### Memory

- **Channels.** One stick, or all sticks in the same channel (slots A1 and A2), means
  the CPU uses one memory channel instead of two. Hardware Unboxed measured about
  12% lower average FPS and about 16% lower 1% lows with one stick, across 13 games.
  X3D CPUs lose much less, about 3%. The channel comes from the slot labels the
  firmware reports ("ChannelA", "DIMM_A1", "P0 CHANNEL A"). When the firmware doesn't
  label them, FrameCheck says so: check CPU-Z, where the Memory tab should show
  "Dual" for DDR4 or "4 x 32-bit" for DDR5.
- **XMP or EXPO.** FrameCheck reads the rated speed from the part number (G.Skill,
  Corsair, Kingston FURY and HyperX, Crucial, TeamGroup, Patriot, ADATA) and compares
  it with the speed the memory runs at. A kit running below its rating has its
  profile off.
  - With the profile, Hardware Unboxed measured about 17 to 20% more FPS and about
    30% better 1% lows (Hogwarts Legacy, Ryzen 7 7700X and Core i7-12700K).
  - X3D CPUs gained only about 4%.
  - When the part number doesn't give the rating and the memory runs at the standard
    speed (DDR4-2666 or lower, DDR5-4800 or lower), FrameCheck tells you to compare
    with the label on the sticks.
- **Amount.** Below 16 GB, current games page to disk, which is stutter.
- **Mixed kits**, which often can't run their rated speed.

### Graphics card

- Each GPU with its video memory, driver version and driver date. FrameCheck tells you
  if the driver is more than a year old.
- **8 GB of video memory or less** is flagged as tight for current games at high
  texture settings.
- **NVIDIA PCIe link**, through `nvidia-smi`:
  - a link running narrower than the card and slot allow, such as x8 instead of x16;
  - a card on only 4 lanes.

  Causes are a chipset slot, a riser, or an M.2 drive sharing the lanes. The penalty
  is small on a fast card with enough video memory, but large once video memory
  overflows.
- **Resizable BAR** for NVIDIA, from the BAR1 size: 256 MB means it's off.
  - NVIDIA uses it only in games it has tested, which run about 2 to 4% faster.
  - AMD's Smart Access Memory added 7 to 16% at 1080p in Hardware Unboxed's test.
  - Intel Arc cards lose about a quarter of their speed without it.
  - It needs "Above 4G Decoding" and "Re-Size BAR" in the BIOS, with UEFI boot and
    CSM off.

### Monitors

- **Refresh rate.** Each monitor's current refresh rate against the highest it offers
  at its resolution. A 165 Hz monitor left at 60 Hz is the most common big loss of
  smoothness.
- **Main monitor on the motherboard.** On a desktop with a graphics card, a main
  monitor plugged into the motherboard runs on the integrated GPU, and every frame is
  copied across first.
- **Laptops (Optimus).** The screen normally runs on the integrated GPU. With a MUX
  switch or Advanced Optimus, the discrete-only mode gave about 10 to 17% more FPS
  in tests.
- **Mixed refresh rates.** Monitors with different refresh rates can stutter when a
  video plays on the second screen during a game.

### Windows settings

- **Game Mode.** It holds back Windows Update installs during games and steadied 1%
  lows under background load in testing. Two-CCD X3D CPUs need it.
- **Background recording.** Game Bar's "Record what happened" encodes the last minutes
  of every game continuously.
- **Hardware-accelerated GPU scheduling.** Reported for A/B testing: measured effects
  are a few percent either way and differ per game. If your lows got worse after
  GameTune turned it on, run GameTune with `HAGS_MODE=off`, restart and compare. DLSS
  frame generation needs it on.
- **Optimizations for windowed games** (Windows 11 22H2 and later). They move windowed
  and borderless DX10 and DX11 games to the flip model, with lower latency.
- **Memory Integrity.** In Tom's Hardware's tests it cost most games 2 to 5% and some
  about 10%. FACEIT and Riot Vanguard can require it. From the October 2026 updates,
  Windows turns it on for more PCs; a deliberate off is kept, but check after
  updates.
- **Page file.** Without one, games that reserve a lot of memory crash or stutter when
  it runs short.

### Storage

- **Free space.** Every drive with less than 10% or 15 GB free is flagged. A full SSD
  writes slower, shader caches can't grow, and when the system drive runs low,
  Windows' automatic cleanup can delete the DirectX shader cache. Games then compile
  their shaders again, which shows up as stutter.
- **Game libraries.** Steam libraries, from `libraryfolders.vdf`, and Epic install
  folders are checked for the kind of drive: hard drive, SATA SSD, NVMe or USB.
  Games stream textures and levels while you play, so a hard drive causes hitches.

### Software running now

- **Lighting software** (Corsair iCUE, ASUS Armoury Crate and Aura, SignalRGB, MSI
  Center, NZXT CAM, Razer Synapse, OpenRGB, Gigabyte RGB Fusion). It polls the
  motherboard's SMBus and can cause periodic stutter; SignalRGB and ASUS'
  LightingService were measured doing so. Save the lighting to the devices, then
  test once with it closed.
- **HWiNFO together with lighting software.** Both read the SMBus at once, and the
  collisions cause stutter. Turn off HWiNFO's support for those devices, or close one
  of them.
- **MSI Afterburner.** Monitoring Power with a short polling period causes stutter
  every few seconds; keep the polling period at 1000 ms.
- **The NVIDIA overlay.** NVIDIA confirmed that its Game Filters and Photo Mode cost up
  to 15% FPS. Turn them off in the NVIDIA App under **Settings > Features** if you
  don't use them.
- **OBS, Medal, Overwolf** (background recording) and **Wallpaper Engine**.

### Frame pacing

The check ends with the settings that give the steadiest frame times. Blur Busters
measured these for G-SYNC; FreeSync works the same way:

- With a G-SYNC or FreeSync monitor:
  - V-Sync on in the NVIDIA or AMD driver, and off in the game.
  - A frame cap at least 3 FPS below the refresh rate, such as 141 at 144 Hz. At the
    refresh rate, VRR behaves like plain V-Sync and adds a frame or two of lag.
  - NVIDIA Reflex or AMD Anti-Lag 2 on, where the game offers it. Reflex sets its own
    cap below the refresh rate.
- An in-game frame limiter gives the lowest latency. RTSS gives steadier frame times
  at up to one frame more latency.
- Without VRR, cap at the refresh rate (or an exact divisor of it) with V-Sync on.

## Part 2: the in-game monitor

### Finding the game

The monitor finds the game by itself: it is the program in front that uses the
graphics card's 3D engine, or else the program using it most. Browsers, Discord, the
desktop and overlays never count as the game. Notes are only taken while a game
runs.

### What it watches

All counters are read through Windows' performance-counter API with English counter
names, so the monitor works in any display language.

| Note | When it is taken | What it means |
|---|---|---|
| CPU held back by its power or temperature limit | Windows' "% Performance Limit" counter at 5% or more | The CPU or the board limits clocks: heat, a power limit, or a laptop on battery |
| CPU below its base clock while busy | Even the fastest core under 90% of its base clock while the busiest core is at least half busy | Throttling or a power-saving setting |
| Driver interrupt work | One core spending 10% or more on DPCs and interrupts | A driver is busy at the wrong time. LatencyMon names it (network, audio, USB and storage drivers are common) |
| Video memory full | The game's GPU at 95% of its video memory | Textures spill into system memory over PCIe, and frames stall. Lower texture quality one step |
| Memory nearly full | Free memory under 5%, or under 800 MB | Paging follows |
| Windows read memory back from disk | 300 or more pages a second read from disk while free memory is under 15% | Hard page faults: stutter |
| Committed memory near its limit | 90% or more of the commit limit | Allocations can fail; keep the page file system-managed |
| A disk took over 100 ms to answer | Average time per disk transfer over 100 ms | Games that stream from that disk hitch |
| Other programs used a lot of CPU | A program other than the game at 10% of the whole CPU or 80% of one core | It competes with the game for CPU time. Antivirus scans and updaters are common |
| This PC uploaded while you played | Over 1 Mbps sent for 3 seconds or more | With bufferbloat this raises ping: NetTune's upload limit or SQM in the router |
| This PC downloaded at high speed | Over 20 Mbps received for 3 seconds or more | Usually an update or a game download |
| Network adapter discarded packets | Its discard counter rose | Receive buffers full: NetTune raises them |
| Windows dropped UDP packets | The UDP receive-error counter rose | A program, often the game, did not read its packets in time |

Moments of the same kind less than 3 seconds apart count as one. The report gives
each kind with:

- how often it happened and for how long in total;
- the worst value;
- the clock time of each occurrence.

### What limited the game

The report also says what limited the game, and for what share of the time:

- **The graphics card**, when its busiest engine was at 95% or more. Graphics settings
  and resolution set your FPS. Upscaling (DLSS, FSR, XeSS) or lower settings raise
  it; CPU, memory and Windows tweaks won't raise the average.
- **The CPU**, when the graphics card was below 85% while a CPU core was at 80% or
  more. Those are the moments the 1% lows dip. There the memory speed and channels,
  background programs and CPU-heavy game settings (view distance, crowds, physics)
  matter most.
- **Neither**: a frame cap, V-Sync or the game engine set the FPS. With a cap, that's
  ideal for steady frame times.

### Lining notes up with frame drops

For frame times themselves, record with [CapFrameX](https://www.capframex.com/) or
[PresentMon](https://github.com/GameTechDev/PresentMon) during the same session and
compare the clock times.

- Capture the same scene at least 3 times, 60 seconds or longer each, and compare
  like with like.
- At 100 FPS, a 60-second run has only 6 frames in its 0.1% low.
- Discard the first run after a driver or game update, because of shader compilation.

## Sources

- Memory channels: [TechSpot / Hardware Unboxed, single stick vs dual channel](https://www.techspot.com/article/3066-single-stick-vs-dual-channel-ram/),
  [Tom's Hardware, single DDR5 DIMM on X3D](https://www.tomshardware.com/pc-components/ddr5/single-dimm-ddr5-gaming-works-better-than-you-probably-think-amds-3d-v-cache-chips-drop-less-than-3-percent-one-ddr5-dimm-beats-dual-channel-ddr4-ram),
  [CPU-Z channel display](https://www.elektroda.com/qa,cpuz-dual-channel-memory-check.html).
- XMP and EXPO: [TechSpot / Hardware Unboxed, DDR5 stock vs XMP/EXPO](https://www.techspot.com/review/2866-ddr5-ram-stock-vs-xmp-expo/).
- X3D core parking: [VRChat wiki: AMD X3D processors](https://wiki.vrchat.com/wiki/Guides:AMD_X3D_Series_Processors),
  [Hardware Times: Game Bar on the 7900X3D and 7950X3D](https://hardwaretimes.com/amd-enable-the-xbox-game-bar-on-the-ryzen-9-7900x3d-7950x3d-processors-for-better-performance/),
  [valleyofdoom PC-Tuning: registering a game](https://github.com/valleyofdoom/PC-Tuning#register-game).
- Intel microcode: [Intel root-cause statement](https://community.intel.com/t5/Blogs/Tech-Innovation/Client/Intel-Core-13th-and-14th-Gen-Desktop-Instability-Root-Cause/post/1633239),
  [Intel performance statement](https://community.intel.com/t5/Mobile-and-Desktop-Processors/Intel-Core-13th-and-14th-Gen-Vmin-Shift-Instabilty-Update-New/m-p/1686948),
  [PC Guide on 0x12F](https://www.pcguide.com/news/intel-13th-14th-gen-cpus-running-for-multiple-days-benefit-from-new-stability-patch-8-months-since-the-last-one/).
- Windows 10 vs 11 on hybrid CPUs: [Intel](https://www.intel.com/content/www/us/en/support/articles/000091284/processors.html),
  [TechSpot](https://www.techspot.com/review/2358-intel-alder-lake-windows-11-benchmark/);
  Ryzen branch prediction: [PCGamesN / Hardware Unboxed](https://www.pcgamesn.com/amd/kb5041587-windows-11-update),
  [Tom's Hardware](https://www.tomshardware.com/software/windows/microsoft-backports-branch-prediction-improvements-to-windows-11-23h2-more-users-will-see-ryzen-performance-improvements).
- Resizable BAR: [TechPowerUp, NVIDIA](https://www.techpowerup.com/review/nvidia-pci-express-resizable-bar-performance-test/),
  [TechSpot, AMD Smart Access Memory](https://www.techspot.com/article/2178-amd-smart-access-memory/),
  [Intel Arc](https://www.intel.com/content/www/us/en/support/articles/000092416/graphics.html),
  [Tom's Hardware, Arc without ReBAR](https://www.tomshardware.com/news/arc-a770-loses-25-percent-performance-without-resizable-bar).
- PCIe link width: [TechPowerUp, RTX 5090 PCIe scaling](https://www.techpowerup.com/review/nvidia-geforce-rtx-5090-pci-express-scaling/33.html),
  [TechSpot, RTX 5060 Ti PCIe](https://www.techspot.com/review/3004-nvidia-rtx-5060-ti-pcie-benchmark/).
- Video memory: [TechSpot, 8 GB vs 16 GB](https://www.techspot.com/article/2661-vram-8gb-vs-16gb/).
- Laptops: [Jarrod's Tech, MUX switch](https://jarrods.tech/what-is-a-mux-switch-for-gaming-laptops/),
  [ASUS ROG, MUX switch](https://rog.asus.com/articles/rog-gaming-laptops/maximize-your-rog-laptops-performance-with-a-mux-switch/),
  [NVIDIA Battery Boost](https://www.notebookcheck.net/Nvidia-Battery-Boost-Review.116939.0.html).
- Mixed refresh rates: [Blur Busters](https://blurbusters.com/new-windows-update-fixes-mixed-hz-multimonitor/).
- Game Mode: [MakeUseOf month-long test](https://www.makeuseof.com/i-tested-windows-game-mode-for-month-what-benchmarks-actually-showed/).
- HAGS: [Microsoft](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/),
  [PC Games Hardware](https://www.pcgameshardware.de/Windows-Software-277633/Specials/HAGS-Benchmark-Test-1352947/),
  [Gamers Nexus](https://gamersnexus.net/guides/3599-windows-10-hardware-accelerated-gpu-scheduling-benchmarks),
  [NVIDIA Streamline, DLSS frame generation requirements](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md).
- Optimizations for windowed games: [DirectX developer blog](https://devblogs.microsoft.com/directx/updates-in-graphics-and-gaming/).
- Memory Integrity: [Tom's Hardware, 2023](https://www.tomshardware.com/news/windows-vbs-harms-performance-rtx-4090),
  [Tom's Hardware, October 2026 rollout](https://www.tomshardware.com/software/windows/microsoft-will-expand-windows-11-memory-integrity-feature-to-more-pcs-starting-in-october-security-feature-reduces-gaming-performance-on-some-systems).
- Shader caches and cleanup: [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/3801278/does-the-directx-shader-cache-itself-which-improve?forum=windows-all),
  [Microsoft Q&A: DX cache cleared](https://learn.microsoft.com/en-us/answers/questions/4111991/why-windows-is-clearing-my-dx-cache-everytime).
- Lighting software and SMBus: [How-To Geek, RGB software microstutter](https://www.howtogeek.com/microstutter-in-games-your-rgb-software-might-be-at-fault/),
  [ROG forum, LightingService](https://rog-forum.asus.com/t5/armoury-crate/lightingservice-exe-causing-stuttering/td-p/932099),
  [ROG forum, iCUE and HWiNFO](https://rog-forum.asus.com/t5/amd-600-series/icue-hwinfo64-causing-issues/td-p/900264),
  [HWiNFO forum](https://www.hwinfo.com/forum/threads/icue-flickering-with-corsair-support-enabled.9027/).
- Afterburner polling: [ResetEra](https://www.resetera.com/threads/psa-msi-afterburner-may-be-the-cause-for-stutters-in-your-games.1072485/).
- NVIDIA overlay: [Tom's Hardware](https://www.tomshardware.com/pc-components/gpu-drivers/nvidia-has-a-fix-for-up-to-15-percent-gaming-performance-loss-caused-by-the-nvidia-app-disabling-feature-restores-performance).
- Wallpaper Engine: [help page](https://help.wallpaperengine.io/en/performance/game.html).
- Frame pacing: [Blur Busters G-SYNC 101](https://blurbusters.com/gsync/gsync101-input-lag-tests-and-settings/14/),
  [frame limiters compared](https://forums.blurbusters.com/viewtopic.php?t=9764),
  [RTSS](https://forums.blurbusters.com/viewtopic.php?t=7819),
  [NVIDIA Reflex](https://www.nvidia.com/en-us/geforce/news/reflex-low-latency-platform/),
  [AMD Anti-Lag 2 SDK](https://github.com/GPUOpen-LibrariesAndSDKs/AntiLag2-SDK).
- Throttling counters: [Microsoft power and performance tuning](https://learn.microsoft.com/en-us/windows-server/administration/performance-tuning/hardware/power/power-performance-tuning);
  DPC latency: [LatencyMon](https://www.resplendence.com/latencymon_using).
- Measuring: [CapFrameX](https://github.com/CXWorld/CapFrameX),
  [PresentMon](https://github.com/GameTechDev/PresentMon/blob/main/README-CaptureApplication.md),
  [Gamers Nexus: 1% and 0.1% lows](https://gamersnexus.net/site-news/2513-testing-methodology-explained-1percent-lows-and-delta-t).
