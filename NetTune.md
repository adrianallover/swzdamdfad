# NetTune

`NetTune.bat` tunes Windows 10 (version 2004 or newer) and Windows 11 for online
games: lower and steadier ping, fewer lag spikes, less jitter and, above all, less
packet loss. It does this without adding CPU work, so 0.1% and 1% lows, average FPS
and frametime consistency stay where they are. A few changes even take work off the
CPU.

It applies only changes backed by measurements or by documented fixes from Intel,
Microsoft or the hardware makers, and it detects your adapters, Wi-Fi card, VPNs,
installed software and Windows build before it changes anything. Popular network
tweaks that tested as placebo, are obsolete, or do harm are left out on purpose; the
reasons are [listed below](#deliberately-not-included).

The script writes no logs, exports, backups or restore points. It never flushes or
deletes DNS, ARP or any other network data, does no Winsock or IP reset, and does not
touch power plans, `powercfg`, temp files or disk cleanup.

It doesn't overlap with [`GameTune.bat`](README.md), which leaves network settings
alone, so you can run both.

## What to expect

Most of your ping is distance and your ISP's routing, and no PC setting changes that.
What a PC can fix is everything it adds on top: power-saving delays, Wi-Fi scan
stalls, receive buffers that overflow, background downloads and uploads that fill
the line, traffic sent over the worse of two links, and driver leftovers from old
tweak tools. NetTune removes those, and marks game packets so Wi-Fi and QoS routers
send them first.

Lag spikes that appear when someone on your network downloads or uploads are
bufferbloat in the router or modem. Only Smart Queue Management (SQM) in the router
fixes that; [see below](#bufferbloat-the-fix-is-in-the-router). The test at the end of
the script tells you where your loss and jitter come from.

## Usage

1. Double-click `NetTune.bat`. It asks for administrator rights.
2. Check the detected connection and the list of planned changes, then press **Y**.
   Don't run it in the middle of a match: changed adapters restart, so the
   connection drops for a few seconds.
3. Restart Windows. The socket buffer, the packet marking and the download caps only
   take full effect after a reboot.

Re-run it after a network driver update, since driver installs reset adapter
settings, and after a Windows feature update.

## Options

Edit the values at the top of the script to change what it does.

| Option | Default | Other values | What it controls |
|---|---|---|---|
| `ADAPTER_MODE` | `on` | `keep` | Ethernet and Wi-Fi driver settings (step 1) |
| `WIFI_LOCATION_MODE` | `auto`: Location services off when your games run over Wi-Fi | `keep` | The Wi-Fi scans that Location triggers (step 2) |
| `ROUTE_MODE` | `on` | `keep` | Ethernet preferred when Wi-Fi is connected too (step 4) |
| `DSCP_MODE` | `on` | `keep` | Priority marking for game traffic (step 5) |
| `QOS_UDP_APPS` | about 50 popular online games (57 executables) | any `.exe` names, separated by `;` | Games whose UDP traffic is marked |
| `QOS_ALL_APPS` | MMOs and other games that use TCP (15 executables) | any `.exe` names, separated by `;` | Games whose UDP and TCP traffic is marked |
| `DO_BACKGROUND_PERCENT` | `20` | `1` to `90`, `keep` | Cap for background Windows Update and Store downloads (step 6) |
| `ONEDRIVE_MODE` | `on` | `keep` | OneDrive uploads only with spare bandwidth (step 7) |
| `SOCKET_BUFFER_MODE` | `on` | `keep` | Larger Winsock default receive buffer (step 3) |
| `DIAG_MODE` | `on` | `off` | The latency, jitter and packet-loss test (step 9) |

To mark a game that isn't on the list, add its executable name to `QOS_UDP_APPS`.
Task Manager's **Details** tab shows the name while the game runs. Re-running the
script rewrites NetTune's own marking policies, so removing a name from the list also
removes its policy.

## What it changes

### 1. Ethernet and Wi-Fi adapter settings

Values are picked from each driver's own list of allowed values, so they work in any
display language. Settings a driver doesn't have are skipped. Every change is printed
with its old and new value, and adapters that changed restart once. A disabled
adapter keeps its new settings but isn't restarted, so it stays disabled.

**Ethernet**

| Change | Why it helps | When it applies |
|---|---|---|
| **Energy-Efficient Ethernet off** (`*EEE`), plus vendor power saving: Advanced EEE, Green Ethernet, Power Saving Mode, Gigabit Lite, Auto Disable Gigabit, Ultra Low Power Mode, System Idle Power Saver, Link Speed Battery Saver | EEE puts the link to sleep between packets. Intel's documented fix for the stutter and disconnects of the I225-V and I226-V is turning it off. On other chips it removes the wake-up delay and the link drops. The vendor settings do the same, or drop the link to 100 Mbps. | Every physical Ethernet adapter that has the setting. |
| **USB selective suspend off** (`*SelectiveSuspend`) | USB adapters otherwise suspend between packets and wake late. | USB Ethernet adapters. |
| **Receive buffers raised to 2048**, or the driver's maximum if lower (`*ReceiveBuffers`) | When a burst arrives while the CPU is busy, a small ring of receive buffers overflows and the adapter drops packets. Intel documents raising the count for exactly this. It costs about 4 MB of memory and no CPU time. | When the current value is lower. It is never lowered. |
| **Checksum offloads back on** (`*TCPChecksumOffloadIPv4` and the like) | Old tweak tools turn them off, which makes the CPU checksum every packet. | Only when one was set to Disabled. |
| **Intel interrupt moderation rate: High or Extreme lowered to Medium** (`ITR`) | High and Extreme hold incoming packets longest before interrupting the CPU. In djdallmann's xperf measurements, Medium had the least impact on gaming. Adaptive, the default, is kept, and moderation itself is never turned off (see [below](#deliberately-not-included)). | Intel adapters set to High or Extreme. |
| **Half duplex fixed** (`*SpeedDuplex`) | A link forced to half duplex collides and loses packets. It goes back to auto-negotiation. | Only when forced to 10, 100 or 1000 Mbps half duplex. |
| **Receive Side Scaling on** | RSS spreads receive processing over several cores instead of one. | Only when it was turned off. |

Jumbo frames that are on are reported, not changed.

**Wi-Fi**

| Change | Why it helps | When it applies |
|---|---|---|
| **Roaming aggressiveness lowered**: Lowest on desktops, Medium-low on laptops | To look for a "better" access point, the card leaves its channel to scan, and each scan is a ping spike. Dell's guidance for Intel cards recommends Lowest on home networks. | Unless it's already at a low setting. Laptops keep some roaming so they can move between rooms. |
| **Background scans blocked on Intel cards** (`BgScanGlobalBlocking`): always on desktops, while the signal is good on laptops | Intel's "Global BG Scan blocking" stops the periodic background scans that cause regular spikes. Current drivers hide the setting but still read it. | Intel Wi-Fi cards. |
| **MIMO power save off** (No SMPS), **U-APSD off**, **driver power saving off** | Power-save modes switch off radio chains or let the radio sleep between packets, which adds delay to the next packet. | Cards that have these settings. |
| **5 GHz preferred** | 2.4 GHz is crowded and shared with Bluetooth and microwaves. "Prefer" still falls back to 2.4 GHz when 5 GHz isn't available. | Unless 5 or 6 GHz is already preferred. |
| **Transmit power at maximum** | A lowered transmit power causes retransmissions at the edge of coverage. | Only when it was lowered. |

### 2. Wi-Fi background scanning: Location services off

When an app asks for your location, Windows finds it by scanning nearby Wi-Fi
networks. During a scan the card leaves your network's channel, and in game that
shows up as a ping spike every minute or so. With Location services off, those
requests stop.

This only runs when your games run over Wi-Fi. When Ethernet is connected as well,
step 4 moves traffic to Ethernet and this step is skipped. Windows itself can still
ask for a scan about once a minute. Intel cards block those with step 1's setting;
on other cards, only Ethernet avoids them.

### 3. Windows network stack

| Change | Why it helps | When it applies |
|---|---|---|
| **BBR2 congestion control replaced** with CUBIC, or NewReno on the Compat template (the Windows defaults) | Tweak tools set BBR2. On Windows 11 it stalls TLS connections over loopback for 30 seconds or more, which breaks Steam, Battle.net, VS Code remote sessions and others. | Only templates that use BBR2. |
| **RSS on** (`netsh int tcp set global rss=enabled`) | Receive Side Scaling spreads receive processing over several cores; this is its global switch. | Only when it was turned off. |
| **Task offload on** (`netsh int ip set global taskoffload=enabled`, `DisableTaskOffload=0`) | With offloads off, the CPU computes every checksum and splits every large send itself. | Only when it was turned off. |
| **Winsock default receive buffer from 8 KB to 256 KB** (`AFD\Parameters\DefaultReceiveWindow`) | A game socket that keeps Windows' default buffer holds only 8 KB of queued packets. If the game thread stalls for a moment, during a load or a hitch, packets arriving meanwhile are silently dropped. Factorio's developers traced dropped UDP packets on Windows to this buffer. Games that set their own buffer size are unaffected. | Unless a value of 64 KB or more is already set. |

### 4. Ethernet over Wi-Fi

With Ethernet and Wi-Fi connected at once, Windows sends traffic over the interface
with the lower route metric. Automatic metrics are based on link speed, so a Wi-Fi 6E
or Wi-Fi 7 link that reports 2.4 Gbps can win over 1 Gbps Ethernet. Your games then
run over the noisier link. NetTune raises the Wi-Fi interface metric for IPv4 and
IPv6 just enough to put Ethernet first. Wi-Fi stays connected and takes over when
Ethernet goes down.

### 5. Priority marking for game traffic (DSCP 46)

Packets from the listed games are marked DSCP 46, Expedited Forwarding, through
Windows' policy-based QoS, the same mechanism Microsoft documents for Teams voice.

- **On Wi-Fi**, Windows sends packets marked 46 in the WMM video access category.
  That category waits less for airtime than normal traffic, so game packets get out
  ahead of a download on the same PC.
- **Routers with DSCP-aware queues** forward the packets ahead of bulk traffic. That
  includes CAKE with diffserv, fq_codel setups with DSCP classes, and many gaming
  routers.
- **Elsewhere** the mark is ignored or cleared, at no cost.

On PCs that aren't in a domain, Windows only applies QoS policies that cover every
network profile and when `Do not use NLA` is set. NetTune creates the policies with
`New-NetQosPolicy -NetworkProfile All` and sets that value. If the cmdlet isn't
available, it writes the same policies in Group Policy's registry format instead.

Windows applies the mark through the QoS Packet Scheduler, so NetTune turns that back
on where an old tweak removed it. Most games use UDP, so only UDP is marked for them.
MMOs and other games that use TCP (`QOS_ALL_APPS`) get both. Policies with other
names, such as Teams or company policies, are never touched.

### 6. Background Windows Update and Store downloads

Delivery Optimization downloads updates in the background and, unless limited, can
upload them to PCs on the internet. Either one fills the line, and game packets wait
behind it: bufferbloat caused by your own PC. NetTune sets two policies:

- **Download mode LAN** (`DODownloadMode=1`). Updates are still shared with PCs on
  your own network, but are never uploaded to PCs on the internet. A mode that is
  already more restrictive is kept.
- **Background downloads capped** at 20% of measured bandwidth
  (`DOPercentageMaxBackgroundBandwidth`). A lower cap that's already set is kept.

Updates still install; they just download more slowly in the background.

### 7. OneDrive uploads only with spare bandwidth

The `EnableAutomaticUploadBandwidthManagement` policy makes OneDrive upload through
Windows' LEDBAT congestion control. LEDBAT backs off as soon as queueing delay rises,
so a sync no longer pushes up your ping. It's skipped when OneDrive isn't installed,
or when a fixed upload rate or percentage is already set by policy.

### 8. Software in the network path (report only)

These add a hop or a filter to every packet. Each has a purpose, so nothing is
removed; you get a warning or a note:

- a VPN or other virtual adapter carrying your internet traffic;
- a Hyper-V external virtual switch;
- a network bridge;
- an active mobile hotspot or Wi-Fi Direct link, which splits the radio's time;
- running traffic shapers: Killer, SmartByte, cFosSpeed, GameFirst, NetLimiter. Killer
  and SmartByte caused UDP packet loss on Windows 11 until Microsoft patched it;
- third-party filter drivers on your internet adapter;
- an MTU below 1400 bytes.

### 9. Latency, jitter and packet loss

The script sends 50 pings each to your router, Cloudflare (1.1.1.1) and Google
(8.8.8.8), and reports loss, average, jitter and the worst ping for each. It then
tells you where the problem is:

- **Loss or jitter already at the router**: Wi-Fi signal or interference, the cable,
  or the router itself.
- **Clean to the router, loss beyond it**: the modem, the ISP line or its routing.
- **Jitter beyond the router**: congestion. If it rises while something downloads,
  that's bufferbloat.

If Windows Update is downloading during the test, the script tells you, because that
raises the numbers.

### What it detects first

- Windows version and edition. Server editions and builds older than 2004 are refused.
- Which adapter carries your internet traffic, including the physical link under a
  VPN or a Hyper-V switch. Ethernet counts as your connection when it's connected
  next to Wi-Fi.
- Ethernet link health: half duplex, a link at 100 Mbps or less, and the share of
  damaged frames since the adapter started, which points at a bad cable or port.
- Wi-Fi signal, band and standard, with a warning below 60% signal or on 2.4 GHz.
  Windows 11 24H2 and later only report these while Location services are on.
- Laptop or desktop, from the chassis type, with the battery as a fallback.
- Intel Wi-Fi, OneDrive, BBR2, and RSS or offloads that were turned off.
- The signed-in user, so per-user policies are read from the right account even when
  the script was elevated with another administrator account.

## Bufferbloat: the fix is in the router

When the line is full, the modem or router queues packets, and a badly sized queue
adds 100 ms or more to every game packet. That's the lag spike you get when someone
starts a download or a video call. A PC can't remove that queue. Steps 5 to 7 stop
your own PC from filling it, and step 5 lets DSCP-aware routers send game packets
first.

1. Test at [waveform.com/tools/bufferbloat](https://www.waveform.com/tools/bufferbloat).
   The grade is how much latency rises under load: A+ up to 5 ms, A up to 30 ms,
   B up to 60 ms, C up to 200 ms, D up to 400 ms, F above that.
2. Below A, turn on SQM (Smart Queue Management) in the router, using CAKE or
   fq_codel. Set its speeds to about 90–95% of your measured download and upload, then
   test again. OpenWrt has it as the SQM package; many other routers offer it under
   QoS.

## Deliberately not included

These appear in most "network optimizer" scripts, but they are placebo on current
Windows, obsolete, harmful, or excluded by design.

| Tweak | Why it is left out |
|---|---|
| `TcpAckFrequency`, `TCPNoDelay`, "disable Nagle" | TCP only. Real-time game traffic is UDP, and games that use TCP turn off Nagle in their own code. No current measurement shows a gain. |
| `NetworkThrottlingIndex`, `SystemResponsiveness` | They only throttle non-multimedia traffic while MMCSS media playback runs. No gaming benefit has been measured. |
| Interrupt moderation off | It saves microseconds per packet, but costs one interrupt per packet. Under a download that's tens of thousands of interrupts per second, which costs CPU time and frametime consistency. NetTune keeps moderation on and only lowers Intel's High and Extreme rates. |
| Flow control off | No rigorous measurement supports it, reports are mixed, and turning it off can trade brief pauses for dropped packets. |
| RSC, LSO, URO, checksum offload off | They save CPU time; turning them off adds work for every packet. NetTune turns checksum offload back on where it was off. |
| TCP autotuning off, heuristics, Chimney, NetDMA, timestamps, initial RTO, pacing profile | TCP-only throughput settings, removed from current Windows, or no measured gaming benefit. Autotuning off cripples downloads. |
| ECN | TCP only and needs server support. No measured gaming benefit. |
| BBR2 | On Windows 11 it breaks loopback TLS, which Steam and Battle.net use. NetTune removes it instead. |
| DNS server changes | Only affect name lookups before a match, never in-game ping. |
| Disabling IPv6, Teredo, NetBIOS, LLMNR | No effect on latency. Microsoft doesn't support disabling IPv6, which can delay startup. Xbox party chat needs Teredo. |
| MTU changes | 1500 is correct for Ethernet and Wi-Fi. A lower MTU splits larger packets. |
| `NonBestEffortLimit=0` ("reserved 20% bandwidth") | A myth: Windows doesn't reserve bandwidth for QoS. |
| `DefaultTTL`, `MaxUserPort`, `TcpTimedWaitDelay`, `IRPStackSize`, `LargeSystemCache` | No effect on game latency. |
| Disabling WLAN AutoConfig (`netsh wlan set autoconfig enabled=no`) | It stops all background scans, but Windows also stops reconnecting after any drop. That's not safe to leave on. |
| Disabling Windows Update | A security risk. Step 6 caps its bandwidth instead. |
| Wi-Fi Packet Coalescing off | It only affects broadcast and multicast packets while the PC idles, not game traffic. |
| A built-in speed test under load | Public speed-test servers rate-limit scripted use. Waveform's test is the standard. |
| Flushing DNS or ARP, Winsock or IP reset, deleting network data | Excluded by design, and no help for latency: they only clear caches or reset configuration. |
| Wireless power-saving mode in the power plan | Excluded by design (no `powercfg`). Driver-level power saving is handled in step 1. |

## Side effects

- Changed adapters restart, so the connection drops for a few seconds.
- With Location services off (Wi-Fi only), Maps, Weather, automatic time zone and
  Find my device stop working. On Windows 11 24H2 and later, apps and
  `netsh wlan show` commands can't read Wi-Fi details such as the network name
  without it. Turn it back on in **Settings > Privacy & security > Location**.
- Lower roaming and Intel background scan blocking make the card slower to switch to
  a stronger access point. On a mesh network, a desktop stays on the node it joined
  while the signal is usable.
- With power saving off, Ethernet and Wi-Fi use slightly more power. On laptops that
  means a little less battery life.
- Windows Update and Store downloads in the background are slower, and Windows no
  longer shares updates with PCs on the internet.
- OneDrive uploads slow down whenever the network is busy.
- Wi-Fi is only used when Ethernet isn't connected.
- Settings may show "Some settings are managed by your organization". This happens
  because the Delivery Optimization and OneDrive changes are made through policies.

## Undo

Run these in an elevated PowerShell window, then restart.

```powershell
# 1. Adapter settings: back to driver defaults (repeat for each adapter name)
Reset-NetAdapterAdvancedProperty -Name "Ethernet" -DisplayName "*"
Reset-NetAdapterAdvancedProperty -Name "Wi-Fi" -DisplayName "*"
#    Intel background scan blocking
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-ItemProperty -LiteralPath $_.PSPath -Name BgScanGlobalBlocking -ErrorAction SilentlyContinue }

# 2. Location services back on
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" /v Value /t REG_SZ /d Allow /f

# 3. Winsock receive buffer back to the Windows default
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" /v DefaultReceiveWindow /f

# 4. Automatic interface metric for Wi-Fi
Set-NetIPInterface -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -AutomaticMetric Enabled
Set-NetIPInterface -InterfaceAlias "Wi-Fi" -AddressFamily IPv6 -AutomaticMetric Enabled

# 5. Packet marking
Get-NetQosPolicy -PolicyStore localhost | Where-Object Name -like 'NetTune *' |
    ForEach-Object { Remove-NetQosPolicy -Name $_.Name -PolicyStore localhost -Confirm:$false }
Get-ChildItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS' -ErrorAction SilentlyContinue |
    Where-Object PSChildName -like 'NetTune *' | Remove-Item -Recurse
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\QoS" /v "Do not use NLA" /f

# 6. Delivery Optimization policies
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DOPercentageMaxBackgroundBandwidth /f

# 7. OneDrive policy
reg delete "HKLM\SOFTWARE\Policies\Microsoft\OneDrive" /v EnableAutomaticUploadBandwidthManagement /f
```

The rest of step 3 (BBR2 removed, RSS and task offload back on), the QoS Packet
Scheduler and the checksum offloads restore Windows or driver defaults, so none of
them needs undoing.

## Sources

- Intel I225-V / I226-V and Energy-Efficient Ethernet:
  [Intel support article](https://www.intel.com/content/www/us/en/support/articles/000093989/ethernet-products.html),
  [TechPowerUp](https://www.techpowerup.com/305356/intel-releases-windows-workaround-and-patch-for-ethernet-stuttering-and-disconnects),
  [Tom's Hardware](https://www.tomshardware.com/news/intel-patches-stuttering-ethernet-issues-but-its-just-a-workaround-for-now).
- Receive buffers: [Intel Ethernet adapter user guide](https://edc.intel.com/content/www/us/en/design/products/ethernet/adapters-and-devices-user-guide/receive-buffers/).
- Interrupt moderation rate: [Intel user guide](https://edc.intel.com/content/www/us/en/design/products/ethernet/adapters-and-devices-user-guide/interrupt-moderation-rate/),
  [djdallmann GamingPCSetup network research](https://djdallmann.github.io/GamingPCSetup/CONTENT/RESEARCH/NETWORK/) and
  [configuration notes](https://github.com/djdallmann/GamingPCSetup/blob/master/CONTENT/DOCS/NETWORK/README.md).
- Intel Wi-Fi settings: [Dell knowledge base](https://www.dell.com/support/kbdoc/en-us/000132395/change-the-intel-advanced-wi-fi-adapter-settings-to-improve-slow-performance-and-intermittent-connections);
  background scan blocking: [Intel community](https://community.intel.com/t5/Wireless/What-is-Global-BG-Scan-blocking/m-p/651076),
  [Intel community, hidden in current drivers](https://community.intel.com/t5/Wireless/Please-bring-back-Global-BG-Scan-blocking-setting/m-p/1623942),
  [Coxxs: fixing Intel Wi-Fi stuttering on the latest driver](https://dev.moe/en/3183).
- Wi-Fi scan spikes: [Microsoft WlanScan documentation](https://learn.microsoft.com/windows/desktop/api/wlanapi/nf-wlanapi-wlanscan),
  [Moonlight issue 1368](https://github.com/moonlight-stream/moonlight-qt/issues/1368),
  [maxofs2d on background scans](https://blog.maxofs2d.net/post/159975555413/my-quest-to-disable-wi-fi-background-scan-on-the);
  Wi-Fi details need Location on 24H2: [Eleven Forum](https://www.elevenforum.com/t/netsh-wlan-query-access-is-denied.45302/).
- BBR2 on Windows 11: [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/3879946/fix-bbr2-bugs-on-windows-11),
  [Blizzard bug report](https://us.forums.blizzard.com/en/blizzard/t/bbr2-congestion-provider-stalls-loopback-tls-ipc/58112),
  [Sunshine issue 4692](https://github.com/LizardByte/Sunshine/issues/4692).
- Winsock receive buffer: [Factorio bug report](https://forums.factorio.com/viewtopic.php?t=72946),
  [smallvoid: Winsock buffer sizes](https://smallvoid.com/article/winnt-winsock-buffer.html),
  [MediaMTX packet-loss guide](https://github.com/bluenviron/mediamtx/discussions/3737).
- Route metrics: [Microsoft: the Automatic Metric feature](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/automatic-metric-for-ipv4-routes).
- DSCP and QoS policies: [Wi-Fi Nigel: Windows WMM user priority](http://wifinigel.blogspot.com/2019/01/the-windows-wmm-user-priority-issue-fix.html),
  [Microsoft: how QoS policy works](https://learn.microsoft.com/en-us/windows-server/networking/technologies/qos/qos-policy-works),
  [New-NetQosPolicy](https://learn.microsoft.com/en-us/powershell/module/netqos/new-netqospolicy),
  [Microsoft Q&A: NetworkProfile All outside a domain](https://learn.microsoft.com/en-us/answers/questions/2277295/qos-dscp-problems),
  [Microsoft: "Do not use NLA"](https://learn.microsoft.com/en-us/skypeforbusiness/manage/network-management/qos/configuring-port-ranges-for-your-skype-clients),
  [Cisco: DSCP tagging on Windows](https://www.cisco.com/c/en/us/support/docs/quality-of-service-qos/qos-configuration-monitoring/221868-enable-dscp-qos-tagging-on-windows-machi.html),
  [Microsoft Teams QoS](https://learn.microsoft.com/en-us/microsoftteams/qos-in-teams-clients).
- Delivery Optimization: [Microsoft reference](https://learn.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization-reference).
- OneDrive and LEDBAT: [policy reference](https://admx.help/?Category=OneDrive&Policy=Microsoft.Policies.OneDriveNGSC::EnableAutomaticUploadBandwidthManagement),
  [Anoop C Nair](https://www.anoopcnair.com/onedrive-upload-speed-windows-ledbat-in-intune/).
- Killer and SmartByte UDP bug: [PC Gamer](https://www.pcgamer.com/windows-11-killer-nic-udp-bug/).
- Bufferbloat: [Waveform test](https://www.waveform.com/tools/bufferbloat),
  [grade thresholds](https://bufferspeed.com/compare/waveform).
- Left out: flow control, [How2Shout](https://www.how2shout.com/technology/flow-control-in-gaming-should-you-turn-it-on-or-off.html);
  scripted speed tests, [Cloudflare rate limiting](https://github.com/omacom/omarchy/pull/10473).
