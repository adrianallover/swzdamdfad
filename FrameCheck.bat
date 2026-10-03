@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================================
rem  FrameCheck.bat - finds what holds back FPS and causes 1 percent low dips
rem
rem  Read-only: changes nothing and writes no files, logs or exports.
rem
rem  Part 1 checks the hardware and Windows for things that cap FPS or cause
rem  stutter: memory channels and speed, the refresh rate, which GPU drives
rem  the monitor, the graphics card's PCIe link and Resizable BAR, Memory
rem  Integrity, background game capture, drive space, games on hard drives
rem  and running software that is known to cause stutter.
rem
rem  Part 2 is an optional monitor that runs while you play. It notes, with
rem  the time of day, what happened on the PC at moments that cost frames:
rem  CPU clock limits, driver interrupt load, full video memory, memory
rem  pressure, disk stalls, background programs using the CPU and network
rem  bursts. It also tells whether the game was limited by the graphics card
rem  or by the CPU. Come back to this window and press Q to see the result.
rem
rem  The PowerShell code is at the end of this file, after the batch code.
rem ==========================================================================

rem ---- Options -------------------------------------------------------------
rem  MONITOR_MINUTES   1 to 240
rem      The monitor stops on its own after this many minutes.
rem --------------------------------------------------------------------------
set "MONITOR_MINUTES=60"

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
set "FC_SELF=%~f0"
rem Loads the PowerShell section between the two marker lines at the end of
rem this file and runs the part named in FC_STEP.
set "FC_PSRUN=$t=[IO.File]::ReadAllText($env:FC_SELF);$m='#'+'FCPS';$i=$t.IndexOf($m);$j=$t.LastIndexOf($m);if($i -lt 0 -or $j -le $i){exit 3};& ([scriptblock]::Create($t.Substring($i,$j-$i)))"

rem ---- Administrator rights (self-elevates) --------------------------------
rem Some checks (Memory Integrity, disks, other users' processes) need them.
fltmc >nul 2>&1
if not "%errorlevel%"=="0" goto :elevate

:main
title FrameCheck
echo.
echo  ==============================================================
echo   FrameCheck - what limits FPS and causes stutter on this PC
echo  ==============================================================
echo   Read-only: nothing is changed.
if not defined PS goto :nops
call :ps audit
echo.
echo  --------------------------------------------------------------
echo   In-game monitor
echo  --------------------------------------------------------------
echo   Start the monitor, then start your game and play normally for at least
echo   10 minutes, ideally where your FPS dips. Then come back to this window
echo   and press Q. The monitor stops on its own after %MONITOR_MINUTES% minutes.
echo   Press Q to stop - Ctrl+C would close FrameCheck before it can report.
echo.
choice /c YN /n /m "  Start the in-game monitor now? [Y/N] "
if errorlevel 2 goto :done
call :ps monitor
:done
echo.
pause
exit /b 0


rem ==========================================================================
rem  Helpers and exits
rem ==========================================================================

:ps
rem ps part - runs one part of the PowerShell section at the end of this file
set "FC_STEP=%~1"
"%PS%" -NoProfile -NonInteractive -Command "%FC_PSRUN%"
if "%errorlevel%"=="3" echo   [FAIL] The PowerShell section of this file is missing or damaged.
exit /b 0

:elevate
if not defined PS goto :needadmin
echo Requesting administrator rights...
"%PS%" -NoProfile -NonInteractive -Command "try { Start-Process -FilePath $env:FC_SELF -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if not "%errorlevel%"=="0" goto :needadmin
exit /b 0

:needadmin
echo.
echo  Administrator rights are required and were not granted.
echo  Right-click FrameCheck.bat and choose "Run as administrator".
echo.
pause
exit /b 1

:nops
echo.
echo  FrameCheck needs Windows PowerShell, which was not found.
echo.
pause
exit /b 1

rem ==========================================================================
rem  PowerShell section. Everything below runs only through the ps helper.
rem ==========================================================================
#FCPS
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$t)  { [Console]::Out.WriteLine($t) }
function Ok([string]$t)   { Say ('  [ OK ] ' + $t) }
function Info([string]$t) { Say ('  [INFO] ' + $t) }
function Fail([string]$t) { Say ('  [FAIL] ' + $t) }
function More([string]$t) { Say ('         ' + $t) }
# A finding worth fixing. $short goes into the list at the end.
function Warn([string]$t, [string]$short) {
    Say ('  [WARN] ' + $t)
    if ($short) { $script:found.Add($short) } else { $script:found.Add($t) }
}
$script:found = New-Object 'System.Collections.Generic.List[string]'
$script:part = 0
function Part([string]$t) {
    $script:part++
    Say ''
    Say (' [' + $script:part + '/8] ' + $t)
}

# ---- Native code -----------------------------------------------------------
# Performance counters, graphics adapters and monitor modes are read through
# Windows APIs; this C# is compiled when FrameCheck starts.
$script:NativeCs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace FrameCheck
{
    // Performance counters through PDH with English counter paths, so they
    // work whatever the display language of Windows.
    public sealed class Pdh : IDisposable
    {
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhOpenQueryW(string source, IntPtr user, out IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhAddEnglishCounterW(IntPtr query, string path, IntPtr user, out IntPtr counter);
        [DllImport("pdh.dll")]
        static extern uint PdhCollectQueryData(IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhGetFormattedCounterArrayW(IntPtr counter, uint format, ref uint size, out uint count, IntPtr buffer);
        [DllImport("pdh.dll")]
        static extern uint PdhCloseQuery(IntPtr query);

        const uint FormatDouble = 0x00000200 | 0x00008000;
        const uint MoreData = 0x800007D2;
        IntPtr query;
        readonly Dictionary<string, IntPtr> counters = new Dictionary<string, IntPtr>();

        public Pdh()
        {
            if (PdhOpenQueryW(null, IntPtr.Zero, out query) != 0) query = IntPtr.Zero;
        }

        public bool Add(string key, string path)
        {
            if (query == IntPtr.Zero) return false;
            IntPtr c;
            if (PdhAddEnglishCounterW(query, path, IntPtr.Zero, out c) != 0) return false;
            counters[key] = c;
            return true;
        }

        public bool Collect()
        {
            return query != IntPtr.Zero && PdhCollectQueryData(query) == 0;
        }

        // Instance name -> value. Instances with the same name (several
        // copies of one program) are added up.
        public Dictionary<string, double> Read(string key)
        {
            Dictionary<string, double> r = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            IntPtr c;
            if (!counters.TryGetValue(key, out c)) return r;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                uint size = 0;
                uint count;
                uint s = PdhGetFormattedCounterArrayW(c, FormatDouble, ref size, out count, IntPtr.Zero);
                if (s != MoreData || size == 0) return r;
                IntPtr buf = Marshal.AllocHGlobal((int)size);
                try
                {
                    s = PdhGetFormattedCounterArrayW(c, FormatDouble, ref size, out count, buf);
                    if (s == MoreData) continue;
                    if (s != 0) return r;
                    // PDH_FMT_COUNTERVALUE_ITEM_W: name pointer, then the status
                    // at offset 8 and the value at offset 16, 24 bytes per item.
                    for (int i = 0; i < count; i++)
                    {
                        IntPtr item = new IntPtr(buf.ToInt64() + 24L * i);
                        int status = Marshal.ReadInt32(item, 8);
                        if (status != 0 && status != 1) continue;
                        string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(item)) ?? "";
                        double v = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item, 16));
                        double old;
                        r[name] = r.TryGetValue(name, out old) ? old + v : v;
                    }
                    return r;
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            return r;
        }

        public void Dispose()
        {
            if (query != IntPtr.Zero) { PdhCloseQuery(query); query = IntPtr.Zero; }
        }
    }

    // GPU engine load from the "GPU Engine" counter instances, named like
    // pid_1234_luid_0x00000000_0x0000C3D8_phys_0_eng_0_engtype_3D.
    public sealed class GpuLoad
    {
        public readonly Dictionary<string, double> Busy = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        public readonly Dictionary<int, double> Pid3D = new Dictionary<int, double>();
        public readonly Dictionary<int, string> PidLuid = new Dictionary<int, string>();

        static readonly Regex Name = new Regex(@"^pid_(\d+)_luid_(0x[0-9a-fA-F]+_0x[0-9a-fA-F]+)_phys_(\d+)_eng_(\d+)_engtype_(.*)$", RegexOptions.Compiled);

        public static GpuLoad Parse(Dictionary<string, double> engines)
        {
            GpuLoad g = new GpuLoad();
            Dictionary<string, double> engine = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            Dictionary<string, double> best = new Dictionary<string, double>();
            foreach (KeyValuePair<string, double> kv in engines)
            {
                Match m = Name.Match(kv.Key);
                if (!m.Success) continue;
                int pid = int.Parse(m.Groups[1].Value);
                string luid = "luid_" + m.Groups[2].Value.ToUpperInvariant().Replace("0X", "0x");
                string type = m.Groups[5].Value;
                bool render = type == "3D" || type.StartsWith("Graphics", StringComparison.OrdinalIgnoreCase);
                bool busy = render || type.StartsWith("Compute", StringComparison.OrdinalIgnoreCase) || type == "Cuda";
                if (busy)
                {
                    string key = luid + "_" + m.Groups[3].Value + "_" + m.Groups[4].Value;
                    double e;
                    engine[key] = (engine.TryGetValue(key, out e) ? e : 0) + kv.Value;
                    double b;
                    double now = engine[key];
                    if (!g.Busy.TryGetValue(luid, out b) || now > b) g.Busy[luid] = Math.Min(100, now);
                }
                if (render)
                {
                    double p;
                    g.Pid3D[pid] = (g.Pid3D.TryGetValue(pid, out p) ? p : 0) + kv.Value;
                    string pk = pid + "|" + luid;
                    double q;
                    best[pk] = (best.TryGetValue(pk, out q) ? q : 0) + kv.Value;
                }
            }
            Dictionary<int, double> top = new Dictionary<int, double>();
            foreach (KeyValuePair<string, double> kv in best)
            {
                int bar = kv.Key.IndexOf('|');
                int pid = int.Parse(kv.Key.Substring(0, bar));
                double t;
                if (!top.TryGetValue(pid, out t) || kv.Value > t)
                {
                    top[pid] = kv.Value;
                    g.PidLuid[pid] = kv.Key.Substring(bar + 1);
                }
            }
            return g;
        }
    }

    public sealed class GpuInfo
    {
        public string Name;
        public uint Vendor;
        public ulong Vram;
        public string Luid;
        public bool Software;
    }

    // Graphics adapters with their video memory, through DXGI.
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

        [DllImport("dxgi.dll")]
        static extern int CreateDXGIFactory1([In] ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 factory);

        public static GpuInfo[] List()
        {
            List<GpuInfo> list = new List<GpuInfo>();
            try
            {
                Guid iid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
                IDXGIFactory1 f;
                if (CreateDXGIFactory1(ref iid, out f) != 0 || f == null) return list.ToArray();
                for (uint i = 0; i < 16; i++)
                {
                    IDXGIAdapter1 a;
                    if (f.EnumAdapters1(i, out a) != 0 || a == null) break;
                    Desc1 d;
                    if (a.GetDesc1(out d) == 0)
                    {
                        GpuInfo g = new GpuInfo();
                        g.Name = (d.Description ?? "").Trim();
                        g.Vendor = d.VendorId;
                        g.Vram = d.DedicatedVideoMemory.ToUInt64();
                        g.Luid = string.Format("luid_0x{0:X8}_0x{1:X8}", d.LuidHigh, d.LuidLow);
                        g.Software = (d.Flags & 2) != 0;
                        list.Add(g);
                    }
                    Marshal.ReleaseComObject(a);
                }
                Marshal.ReleaseComObject(f);
            }
            catch (Exception) { }
            return list.ToArray();
        }
    }

    public sealed class DisplayInfo
    {
        public string Device;
        public string Adapter;
        public bool Primary;
        public int Width;
        public int Height;
        public int Hz;
        public int MaxHz;
    }

    // Monitors attached to the desktop, the GPU that drives each one, and the
    // highest refresh rate it offers at its current resolution.
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

        static DevMode NewMode()
        {
            DevMode m = new DevMode();
            m.dmSize = (ushort)Marshal.SizeOf(typeof(DevMode));
            return m;
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
                    d.Hz = (int)cur.dmDisplayFrequency;
                    d.MaxHz = d.Hz;
                    for (int m = 0; m < 4096; m++)
                    {
                        DevMode dm = NewMode();
                        if (!EnumDisplaySettingsW(dd.DeviceName, m, ref dm)) break;
                        if (dm.dmPelsWidth == cur.dmPelsWidth && dm.dmPelsHeight == cur.dmPelsHeight && (int)dm.dmDisplayFrequency > d.MaxHz)
                            d.MaxHz = (int)dm.dmDisplayFrequency;
                    }
                    list.Add(d);
                }
            }
            catch (Exception) { }
            return list.ToArray();
        }
    }

    public static class Win
    {
        [DllImport("user32.dll")]
        static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);

        public static int ForegroundPid()
        {
            try
            {
                IntPtr h = GetForegroundWindow();
                if (h == IntPtr.Zero) return 0;
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                return (int)pid;
            }
            catch (Exception) { return 0; }
        }
    }
}
'@

function Import-Native {
    if ('FrameCheck.Pdh' -as [type]) { return $true }
    try {
        Add-Type -TypeDefinition $script:NativeCs -Language CSharp -IgnoreWarnings -WarningAction SilentlyContinue -ErrorAction Stop
        return $true
    } catch {
        Fail ('The measuring code could not be compiled: ' + ([string]$_.Exception.Message).Split("`n")[0].Trim())
        return $false
    }
}

# ---- Helpers ---------------------------------------------------------------
# An integer setting from the environment, or $default when it is missing
# or not a number.
function Get-IntSetting([string]$name, [int]$default) {
    $v = 0
    if ([int]::TryParse([string][Environment]::GetEnvironmentVariable($name), [ref]$v)) { return $v }
    $default
}

# A registry value; the comma keeps binary values in one piece.
function Get-Reg([string]$key, [string]$name) {
    $p = Get-ItemProperty -LiteralPath $key -Name $name
    if ($p) { ,$p.$name }
}

# The user signed in to this session, also when FrameCheck was elevated with
# a different administrator account.
function Get-SignedInSid {
    $s = (Get-Process -Id $PID).SessionId
    $p = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object { $_.SessionId -eq $s })[0]
    if ($p) { (Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid).Sid }
}

# Laptop or desktop, from the chassis type; the battery only decides when the
# chassis type says neither.
function Test-Laptop {
    $types = @(Get-CimInstance Win32_SystemEnclosure | ForEach-Object { $_.ChassisTypes } | ForEach-Object { [int]$_ })
    foreach ($c in $types) { if (@(8, 9, 10, 11, 14, 30, 31, 32) -contains $c) { return $true } }
    foreach ($c in $types) { if (@(3, 4, 5, 6, 7, 13, 15, 16, 24, 35, 36) -contains $c) { return $false } }
    [bool](Get-CimInstance Win32_Battery)
}

# Integrated graphics: Intel UHD/Iris/Arc integrated, AMD Radeon Graphics in
# APUs, or any adapter with less than 2 GB of its own memory.
function Test-Integrated($g) {
    $n = [string]$g.Name
    if ([int]$g.Vendor -eq 0x10DE) { return $false }
    if ($n -match 'Arc\(TM\) [AB]\d{3}|Arc [AB]\d{3}') { return $false }
    if ($n -match 'Radeon.*\bRX\b|Radeon PRO|Radeon Pro') { return $false }
    if ($n -match 'UHD|Iris|HD Graphics|Arc\(TM\) Graphics|Arc\(TM\) \d{3}[VT]|Radeon\(TM\) Graphics|Radeon \d{3}M|Radeon Graphics|Vega') { return $true }
    [double]$g.Vram -lt 2GB
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

# Steam and Epic library folders.
function Get-GameLibraries([string]$hku) {
    $out = @()
    $seen = @{}
    $steam = [string](Get-Reg ($hku + '\Software\Valve\Steam') 'SteamPath')
    if (-not $steam) { $steam = [string](Get-Reg 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath') }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $paths = @()
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($l in [IO.File]::ReadAllLines($vdf)) {
                if ($l -match '"path"\s+"([^"]+)"') { $paths += ($Matches[1] -replace '\\\\', '\') }
            }
        }
        $paths += $steam
        foreach ($p in $paths) {
            $k = $p.TrimEnd('\').ToLower()
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = 1
            if (Test-Path -LiteralPath (Join-Path $p 'steamapps\common')) { $out += [pscustomobject]@{ Store = 'Steam'; Path = $p.TrimEnd('\') } }
        }
    }
    $epic = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $epic) {
        foreach ($f in @(Get-ChildItem -LiteralPath $epic -Filter '*.item')) {
            $j = $null
            try { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { }
            if (-not $j -or -not $j.InstallLocation) { continue }
            $d = Split-Path -Path ([string]$j.InstallLocation) -Parent
            $k = $d.TrimEnd('\').ToLower()
            if (-not $d -or $seen.ContainsKey($k)) { continue }
            $seen[$k] = 1
            $out += [pscustomobject]@{ Store = 'Epic'; Path = $d.TrimEnd('\') }
        }
    }
    $out
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

function Format-Duration([double]$s) {
    $s = [Math]::Round($s)
    if ($s -lt 60) { return ([string]$s + ' s') }
    $m = [Math]::Floor($s / 60)
    if ($m -lt 60) { return ('{0} min {1} s' -f $m, ($s % 60)) }
    '{0} h {1} min' -f [Math]::Floor($m / 60), ($m % 60)
}

# Records one moment of a kind of trouble. Moments of the same kind less
# than 3 seconds apart count as one stretch, with its length and its worst
# value: the highest, or the lowest for clock speed and free memory.
function Note([string]$type, [string]$detail, [double]$value, [int]$sec = 1) {
    $key = $type + '|' + $detail
    $now = Get-Date
    $e = $script:open[$key]
    if ($e -and ($now - $e.Last).TotalSeconds -le 3) {
        $e.Last = $now
        $e.Seconds += $sec
        if ($type -eq 'cpuclock' -or $type -eq 'ram') { if ($value -lt $e.Peak) { $e.Peak = $value } }
        elseif ($value -gt $e.Peak) { $e.Peak = $value }
        return
    }
    $e = [pscustomobject]@{ Type = $type; Detail = $detail; First = $now; Last = $now; Seconds = $sec; Peak = $value }
    $script:open[$key] = $e
    $script:events.Add($e)
}

switch ($env:FC_STEP) {

'audit' {
    $native = Import-Native
    $hku = 'HKCU:'
    $sid = Get-SignedInSid
    if ($sid -and (Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $sid))) { $hku = 'Registry::HKEY_USERS\' + $sid }
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = 0
    [void][int]::TryParse([string]$cv.CurrentBuildNumber, [ref]$build)
    $laptop = Test-Laptop
    $cs = Get-CimInstance Win32_ComputerSystem

    # ---- 1. This PC ---------------------------------------------------------
    Part 'This PC'
    $os = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
    Ok ($os + ' ' + [string]$cv.DisplayVersion + ', build ' + $build + '.' + [string]$cv.UBR + ', ' + $(if ($laptop) { 'laptop' } else { 'desktop' }) + '.')
    if ($laptop) {
        $bat = @(Get-CimInstance Win32_Battery)
        if ($bat.Count -and [int]$bat[0].BatteryStatus -eq 1) {
            Warn 'Running on battery. Laptops cut CPU and GPU power on battery, and NVIDIA Battery Boost caps games at 30 FPS by default.' 'Plug the laptop in to play'
        } else {
            Ok 'Plugged in.'
        }
    }

    # ---- 2. Processor -------------------------------------------------------
    Part 'Processor'
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $cname = (([string]$cpu.Name) -replace '\s+', ' ').Trim()
    Ok ($cname + ': ' + $cpu.NumberOfCores + ' cores, ' + $cpu.NumberOfLogicalProcessors + ' threads.')
    # Two-CCD X3D: AMD's driver parks the CCD without the extra cache while
    # Game Bar reports a game, which needs the driver, Game Bar and Game Mode.
    if ($cname -match 'Ryzen 9 (7900X3D|7950X3D|9900X3D|9950X3D)') {
        $svc = Get-Service -Name 'amd3dvcacheSvc'
        $gb = (Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay') -or (Get-AppxPackage -AllUsers -Name 'Microsoft.XboxGamingOverlay')
        $gm = Get-Reg ($hku + '\Software\Microsoft\GameBar') 'AutoGameModeEnabled'
        $miss = @()
        if (-not $svc -or [string]$svc.Status -ne 'Running') { $miss += 'the AMD 3D V-Cache Performance Optimizer service is not running (it comes with the AMD chipset driver)' }
        if (-not $gb) { $miss += 'Xbox Game Bar is not installed' }
        if ($null -ne $gm -and [int]$gm -eq 0) { $miss += 'Game Mode is off' }
        if ($miss.Count) {
            Warn ('Two-CCD X3D processor, but ' + ($miss -join '; ') + '. Games then also run on the cores without the extra cache, which costs FPS and lows.') 'X3D: restore the chipset driver, Game Bar and Game Mode'
        } else {
            Ok 'Two-CCD X3D processor: chipset driver, Game Bar and Game Mode are in place, so games are kept on the cache cores.'
        }
        More 'A game Game Bar does not recognise needs "Remember this is a game" ticked in Game Bar (Win+G).'
    }
    # Intel 13th and 14th gen desktop: microcode 0x12B and later stop the
    # voltage problem behind crashes and degrading CPUs.
    if ($cname -match 'i[579]-1[34]\d{3}(K|KF|KS|F|T)?(\s|$)') {
        $b = Get-Reg 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' 'Update Revision'
        if ($b -is [byte[]] -and $b.Count -ge 8) {
            $rev = [BitConverter]::ToUInt32($b, 4)
            if ($rev -gt 0 -and $rev -lt 0x12B) {
                Warn ('Microcode 0x{0:X} predates Intel''s 0x12B fix for 13th and 14th gen instability. Update the BIOS to one with 0x12F or newer.' -f $rev) 'Update the BIOS (CPU microcode)'
                More 'It does not change FPS; it prevents the crashes and slow CPU damage the old microcode causes.'
            } elseif ($rev -gt 0) {
                Ok ('Microcode 0x{0:X}: includes Intel''s fix for 13th and 14th gen instability.' -f $rev)
            }
        }
    }
    if ($build -lt 22000 -and $cname -match '1[2-4]th Gen|Core\(TM\) Ultra|Core Ultra') {
        Info 'Windows 10 does not support Thread Director, which Windows 11 uses to keep game threads on the P-cores.'
    }
    if ($build -lt 22000 -and $cname -match 'Ryzen \d+ (PRO )?[5789]\d{3}') {
        Info 'Windows 11 24H2 has branch-prediction changes that raised Ryzen gaming FPS by about 10 percent in Hardware Unboxed''s tests; Windows 10 does not.'
    }

    # ---- 3. Memory ----------------------------------------------------------
    Part 'Memory'
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
        $info += [pscustomobject]@{ Slot = (([string]$m.DeviceLocator) + ' ' + ([string]$m.BankLabel)).Trim(); GB = [Math]::Round([double]$m.Capacity / 1GB); Type = $type; Speed = $cfg; Rated = (Get-RatedSpeed $pn); Part = $pn; Channel = (Get-Channel $m) }
    }
    if ($totalGB -lt 16) {
        Warn ('Only ' + $totalGB + ' GB of memory. Current games often need more, and paging to disk shows up as stutter: 16 GB is the minimum, 32 GB comfortable.') 'More memory: 16 GB at least'
    } else {
        Ok ([string]$totalGB + ' GB in ' + $mods.Count + ' stick' + $(if ($mods.Count -ne 1) { 's' }) + $(if ($slots -gt 0) { ', ' + $slots + ' slots' }) + '.')
    }
    foreach ($x in $info) {
        $line = '{0}: {1} GB {2}, running at {3} MT/s' -f $x.Slot, $x.GB, $x.Type, $x.Speed
        if ($x.Rated) { $line += ', rated ' + $x.Rated }
        if ($x.Part) { $line += ' (' + $x.Part + ')' }
        More $line
    }
    # Channels
    $known = @($info | Where-Object { $_.Channel })
    $distinct = @($known | ForEach-Object { $_.Channel } | Select-Object -Unique)
    if ($mods.Count -eq 1 -and $slots -ne 1) {
        Warn 'One memory stick, so the CPU uses a single memory channel. In Hardware Unboxed''s 13-game test, one stick cost about 12 percent average FPS and 16 percent of the 1% lows (much less on X3D CPUs). Add a matching second stick.' 'Add a second, matching memory stick'
    } elseif ($mods.Count -eq 1) {
        Info 'One memory stick in the only slot: single channel, which costs FPS, but this PC has no free slot.'
    } elseif ($known.Count -eq $mods.Count -and $distinct.Count -eq 1) {
        Warn ('All sticks are in channel ' + $distinct[0] + ', so the CPU uses one channel instead of two. Move a stick to the other channel''s slot; the motherboard manual names the pair to use (usually A2 and B2).') 'Move a memory stick to the other channel'
    } elseif ($distinct.Count -ge 2) {
        Ok ('Dual channel or more: sticks in channels ' + ($distinct -join ' and ') + '.')
    } elseif ($mods.Count -gt 1) {
        Info 'The firmware does not label the memory channels. CPU-Z (Memory tab) shows Channel #: Dual for DDR4, 4 x 32-bit for DDR5.'
    }
    # Speed: XMP or EXPO off shows as a kit running below its rated speed.
    $slow = @($info | Where-Object { $_.Rated -gt 0 -and $_.Speed -gt 0 -and $_.Rated -gt $_.Speed + 150 })
    if ($slow.Count) {
        Warn ('The memory runs at ' + $slow[0].Speed + ' MT/s but is rated ' + $slow[0].Rated + ': XMP or EXPO is off. Turn it on in the BIOS (XMP, EXPO or DOCP).') 'Turn on XMP or EXPO in the BIOS'
        More 'Hardware Unboxed measured about 17 to 20 percent more FPS and about 30 percent better 1% lows with it in Hogwarts Legacy; X3D CPUs gain less.'
    } elseif (-not $laptop -and @($info | Where-Object { $_.Rated -eq 0 -and (($_.Type -eq 'DDR4' -and $_.Speed -le 2666) -or ($_.Type -eq 'DDR5' -and $_.Speed -le 4800)) }).Count) {
        Info ('The memory runs at ' + $info[0].Speed + ' MT/s, the standard speed without XMP or EXPO. If the label on the sticks shows a higher speed, turn on XMP or EXPO in the BIOS.')
    } elseif ($info.Count -and $info[0].Speed) {
        Ok ('Memory speed: ' + $info[0].Speed + ' MT/s.')
    }
    if (@($info | ForEach-Object { $_.Part } | Select-Object -Unique).Count -gt 1 -or @($info | ForEach-Object { $_.GB } | Select-Object -Unique).Count -gt 1) {
        Info 'The sticks are from different kits. Mixed kits often cannot run their rated speed; if XMP or EXPO is unstable, that is the reason.'
    }

    # ---- 4. Graphics card ---------------------------------------------------
    Part 'Graphics card'
    $gpus = @()
    if ($native) { $gpus = @([FrameCheck.Dxgi]::List() | Where-Object { -not $_.Software }) }
    $vcs = @(Get-CimInstance Win32_VideoController)
    $dgpu = $null
    foreach ($g in $gpus) {
        $igpu = Test-Integrated $g
        $vc = @($vcs | Where-Object { ([string]$_.Name).Trim() -eq $g.Name })[0]
        $line = $g.Name + $(if ($igpu) { ', integrated' } else { ', {0:0.#} GB video memory' -f ($g.Vram / 1GB) })
        if ($vc -and $vc.DriverVersion) { $line += ', driver ' + $vc.DriverVersion }
        $age = $null
        if ($vc -and $vc.DriverDate) { $age = ((Get-Date) - [datetime]$vc.DriverDate).TotalDays; $line += ' from ' + ([datetime]$vc.DriverDate).ToString('yyyy-MM-dd') }
        Ok ($line + '.')
        if (-not $igpu -and -not $dgpu) { $dgpu = $g }
        if (-not $igpu -and $null -ne $age -and $age -gt 365) {
            Info 'That driver is more than a year old; new games often get performance fixes in newer drivers.'
        }
    }
    if (-not $gpus.Count) { foreach ($vc in $vcs) { Ok ([string]$vc.Name + ', driver ' + [string]$vc.DriverVersion + '.') } }
    if ($dgpu -and [double]$dgpu.Vram -le 8.5GB -and [double]$dgpu.Vram -ge 3GB) {
        Info ('{0:0} GB of video memory is tight for current games at high texture settings; the monitor shows when it runs full.' -f ($dgpu.Vram / 1GB))
    }
    if ($dgpu -and [int]$dgpu.Vendor -eq 0x10DE) {
        $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
        if (-not (Test-Path -LiteralPath $smi)) { $smi = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
        if (Test-Path -LiteralPath $smi) {
            $rows = @(& $smi '--query-gpu=name,pcie.link.width.current,pcie.link.width.max' '--format=csv,noheader,nounits' 2>$null)
            $mem = @(& $smi '-q' '-d' 'MEMORY' 2>$null)
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
                    Warn ($f[0] + ' runs its PCIe link at x' + $cur + ' instead of x' + $max + '. Reseat the card in the top x16 slot; a riser or an M.2 drive sharing its lanes can also cause this.') 'Fix the graphics card''s PCIe link'
                } elseif ($cur -gt 0 -and $cur -le 4 -and -not $laptop -and $f[0] -notmatch 'GT 10[13]0|GT 7[13]0') {
                    Warn ($f[0] + ' runs on only 4 PCIe lanes. That is a chipset slot or a riser: move the card to the top x16 slot.') 'Move the graphics card to the x16 slot'
                } elseif ($cur -gt 0) {
                    Ok ('PCIe link: x' + $cur + '.')
                }
                if ($i -lt $bar.Count) {
                    if ($bar[$i] -le 256) {
                        Info 'Resizable BAR is off. Turn on "Above 4G Decoding" and "Re-Size BAR" in the BIOS (needs UEFI boot, CSM off).'
                        More 'NVIDIA uses it only in games it has tested, about 2 to 4 percent faster on average there.'
                    } else {
                        Ok 'Resizable BAR: on.'
                    }
                }
            }
        }
    } elseif ($dgpu -and $dgpu.Name -match 'Arc') {
        Info 'Intel Arc cards lose about a quarter of their speed without Resizable BAR: check that Intel Graphics Software shows it as on.'
    } elseif ($dgpu -and [int]$dgpu.Vendor -eq 0x1002) {
        Info 'AMD Smart Access Memory (Resizable BAR) added 7 to 16 percent at 1080p in Hardware Unboxed''s test: check that AMD Software shows it as enabled.'
    }

    # ---- 5. Monitors --------------------------------------------------------
    Part 'Monitors'
    $disp = @()
    if ($native) { $disp = @([FrameCheck.Displays]::List() | Sort-Object { -not $_.Primary }) }
    if (-not $disp.Count) { Info 'The monitor settings could not be read.' }
    $n = 0
    foreach ($d in $disp) {
        $n++
        $line = '{0}{1}: {2} x {3} at {4} Hz, on {5}' -f ('Monitor ' + $n), $(if ($d.Primary) { ' (main)' } else { '' }), $d.Width, $d.Height, $d.Hz, $d.Adapter
        if ($d.MaxHz -gt $d.Hz + 1) {
            Warn ($line + '. It offers ' + $d.MaxHz + ' Hz at this resolution: set it in Settings > System > Display > Advanced display.') ('Set monitor ' + $n + ' to ' + $d.MaxHz + ' Hz')
        } else {
            Ok ($line + '.')
        }
    }
    $mainDisp = @($disp | Where-Object { $_.Primary })[0]
    if ($mainDisp -and $dgpu) {
        $ag = @($gpus | Where-Object { $_.Name -eq $mainDisp.Adapter })[0]
        if ($ag -and (Test-Integrated $ag) -and -not $laptop) {
            Warn ('The main monitor is plugged into the motherboard: it runs on ' + $mainDisp.Adapter + ', so each frame from ' + $dgpu.Name + ' is copied across first. Plug the cable into the graphics card.') 'Plug the monitor into the graphics card'
        } elseif ($ag -and (Test-Integrated $ag)) {
            Info ('The screen runs on ' + $mainDisp.Adapter + ', so frames from ' + $dgpu.Name + ' are copied through it (Optimus).')
            More 'If the laptop has a MUX switch or Advanced Optimus, set the GPU mode to discrete in the maker''s app: about 10 to 17 percent more FPS in tests.'
        }
    }
    if ($disp.Count -gt 1 -and @($disp | ForEach-Object { $_.Hz } | Select-Object -Unique).Count -gt 1) {
        Info 'Monitors with different refresh rates: video playing on the other screen while you game can cause stutter. Pause it, or turn off hardware acceleration in the browser.'
    }

    # ---- 6. Windows settings ------------------------------------------------
    Part 'Windows settings for games'
    $gm = Get-Reg ($hku + '\Software\Microsoft\GameBar') 'AutoGameModeEnabled'
    if ($null -ne $gm -and [int]$gm -eq 0) {
        Warn 'Game Mode is off. It holds back Windows Update installs and restart prompts during games, and kept 1% lows steadier with background load in testing: Settings > Gaming > Game Mode.' 'Turn Game Mode on'
    } else {
        Ok 'Game Mode: on.'
    }
    $hist = Get-Reg ($hku + '\Software\Microsoft\Windows\CurrentVersion\GameDVR') 'HistoricalCaptureEnabled'
    if ($null -ne $hist -and [int]$hist -eq 1) {
        Warn 'Game Bar keeps recording the last minutes of every game ("Record what happened"), which costs GPU time in every game. Turn it off in Settings > Gaming > Captures unless you use it.' 'Turn off background game recording'
    } else {
        Ok 'Background game recording: off.'
    }
    $hags = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    $hs = if ($null -eq $hags) { 'Windows default' } elseif ([int]$hags -eq 2) { 'on' } else { 'off' }
    Info ('Hardware-accelerated GPU scheduling: ' + $hs + '. Measured effects are a few percent either way and differ per game.')
    More 'If your lows got worse after GameTune turned it on, test with it off: GameTune with HAGS_MODE=off, then restart.'
    More 'DLSS frame generation needs it on.'
    if ($build -ge 22621) {
        $dx = [string](Get-Reg ($hku + '\Software\Microsoft\DirectX\UserGpuPreferences') 'DirectXUserGlobalSettings')
        if ($dx -match 'SwapEffectUpgradeEnable=1') { Ok 'Optimizations for windowed games: on.' }
        else { Info 'Optimizations for windowed games: off. Windowed and borderless DX10 and DX11 games then present with more latency (Settings > System > Display > Graphics).' }
    }
    $dg = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard
    if ($dg -and @($dg.SecurityServicesRunning) -contains 2) {
        Warn 'Memory Integrity is on. In Tom''s Hardware''s tests it cost most games 2 to 5 percent and some about 10 percent. FACEIT and Riot Vanguard can require it; otherwise GameTune turns it off.' 'Memory Integrity costs FPS'
        if ($build -ge 22000) { More 'From the October 2026 updates Windows turns it on for more PCs; a deliberate off is kept, but check again after updates.' }
    } elseif ($dg) {
        Ok 'Memory Integrity: off.'
    }
    $pf = @(Get-CimInstance Win32_PageFileUsage)
    if (-not $pf.Count -and -not $cs.AutomaticManagedPagefile) {
        Warn 'There is no page file. Games that reserve a lot of memory then crash or stutter when it runs short: set it back to System managed (Settings > System > About > Advanced system settings > Performance).' 'Turn the page file back on'
    } else {
        Ok 'Page file: on.'
    }

    # ---- 7. Storage ---------------------------------------------------------
    Part 'Storage'
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $size = [double]$v.Size
        $free = [double]$v.FreeSpace
        if ($size -le 0) { continue }
        $line = '{0} {1:0} GB free of {2:0} GB' -f $v.DeviceID, ($free / 1GB), ($size / 1GB)
        if ($free / $size -lt 0.1 -or $free -lt 15GB) {
            Warn ($line + '. A nearly full SSD writes slower, and shader caches cannot grow, so games compile shaders again and stutter. Keep 10 to 15 percent free.') ('Free up space on ' + $v.DeviceID)
            if ($v.DeviceID -eq $env:SystemDrive) { More 'When the system drive runs low, Windows'' automatic cleanup can also delete the DirectX shader cache.' }
        } else {
            Ok ($line + '.')
        }
    }
    foreach ($l in @(Get-GameLibraries $hku)) {
        $kind = Get-DriveKind $l.Path
        if ($kind -eq 'hard drive') {
            Warn ($l.Store + ' library ' + $l.Path + ' is on a hard drive. Games load textures and levels while you play, so a hard drive causes hitches: move the games to an SSD.') 'Move games from the hard drive to an SSD'
        } elseif ($kind) {
            Ok ($l.Store + ' library ' + $l.Path + ': ' + $kind + '.')
        }
    }

    # ---- 8. Software running now --------------------------------------------
    Part 'Software running now'
    $procs = @{}
    foreach ($p in @(Get-Process)) { $procs[([string]$p.ProcessName).ToLower()] = 1 }
    $has = { param([string[]]$names) foreach ($x in $names) { if ($procs.ContainsKey($x.ToLower())) { return $true } }; $false }
    $hits = 0
    $rgb = @()
    if (& $has @('iCUE')) { $rgb += 'Corsair iCUE' }
    if (& $has @('LightingService', 'ArmouryCrate', 'ArmouryCrate.Service')) { $rgb += 'ASUS Armoury Crate or Aura' }
    if (& $has @('SignalRgb', 'SignalRgbLauncher')) { $rgb += 'SignalRGB' }
    if (& $has @('MSI.CentralServer', 'MSI Center')) { $rgb += 'MSI Center' }
    if (& $has @('NZXT CAM')) { $rgb += 'NZXT CAM' }
    if (& $has @('RazerAppEngine', 'Razer Synapse 3', 'Razer Synapse Service')) { $rgb += 'Razer Synapse' }
    if (& $has @('OpenRGB')) { $rgb += 'OpenRGB' }
    if (& $has @('RGBFusion', 'GCC')) { $rgb += 'Gigabyte RGB Fusion or Control Center' }
    if ($rgb.Count) {
        Info ('Running: ' + ($rgb -join ', ') + '. Lighting software polls the motherboard''s SMBus and can cause periodic stutter (measured for SignalRGB and ASUS LightingService).')
        More 'Test once with it closed: save the lighting to the devices first.'
        $hits++
    }
    if (& $has @('HWiNFO64', 'HWiNFO32', 'HWiNFO')) {
        if ($rgb.Count) {
            Warn 'HWiNFO runs together with lighting software, and both read the SMBus at once: that collision causes stutter. Turn off HWiNFO''s support for those devices (Corsair, ASUS) or close one of them.' 'Stop HWiNFO and RGB software reading the SMBus together'
        } else {
            Info 'HWiNFO is running: its sensor polling costs a little CPU. Close it for benchmarks and comparisons.'
        }
        $hits++
    }
    if (& $has @('MSIAfterburner')) {
        Info 'MSI Afterburner is running. Monitoring Power with a short polling period can cause stutter every few seconds: keep polling at 1000 ms.'
        $hits++
    }
    if (& $has @('NVIDIA Overlay', 'NVIDIA Share')) {
        Info 'The NVIDIA overlay is on. Its Game Filters and Photo Mode cost up to 15 percent FPS per NVIDIA; turn them off in the NVIDIA App (Settings > Features) if unused.'
        $hits++
    }
    if (& $has @('obs64', 'obs32')) { Info 'OBS is running: recording or streaming costs GPU time, and streaming uses upload bandwidth.'; $hits++ }
    if (& $has @('Medal', 'Overwolf', 'Outplayed')) { Info 'A clip recorder (Medal or Overwolf) is running: background recording costs GPU time in every game.'; $hits++ }
    if (& $has @('wallpaper32', 'wallpaper64')) {
        Info 'Wallpaper Engine is running. It pauses during fullscreen games; if a game stutters, set it to stop (not pause) when another app is fullscreen.'
        $hits++
    }
    if (-not $hits) { Ok 'No software known to cause stutter is running.' }

    # ---- Summary --------------------------------------------------------------
    Say ''
    Say ' --------------------------------------------------------------'
    if ($script:found.Count) {
        Say ('  To fix (' + $script:found.Count + '):')
        $i = 0
        foreach ($f in $script:found) { $i++; Say ('   ' + $i + '. ' + $f) }
    } else {
        Say '  Nothing in the setup holds back FPS. If games still stutter, run the monitor below.'
    }
    Say ''
    Say '  Frame pacing, for steady frame times: with G-SYNC or FreeSync, turn V-Sync on in the'
    Say '  NVIDIA or AMD driver and off in the game, and cap FPS 3 below the refresh rate (141 at 144 Hz).'
    Say '  Use Reflex or Anti-Lag 2 where the game offers it. Without VRR, cap at the refresh rate.'
}

'monitor' {
    if (-not (Import-Native)) { return }
    $minutes = [Math]::Max(1, [Math]::Min(240, (Get-IntSetting 'MONITOR_MINUTES' 60)))
    $cores = [Math]::Max(1, [Environment]::ProcessorCount)
    $ramMB = [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB
    $vram = @{}
    foreach ($g in @([FrameCheck.Dxgi]::List() | Where-Object { -not $_.Software })) { $vram[[string]$g.Luid] = [double]$g.Vram }
    $q = New-Object FrameCheck.Pdh
    $paths = [ordered]@{
        cpu    = '\Processor Information(_Total)\% Processor Time'
        core   = '\Processor Information(*)\% Processor Time'
        perf   = '\Processor Information(*)\% Processor Performance'
        limit  = '\Processor Information(_Total)\% Performance Limit'
        dpc    = '\Processor Information(*)\% DPC Time'
        isr    = '\Processor Information(*)\% Interrupt Time'
        eng    = '\GPU Engine(*)\Utilization Percentage'
        ded    = '\GPU Adapter Memory(*)\Dedicated Usage'
        avail  = '\Memory\Available MBytes'
        commit = '\Memory\% Committed Bytes In Use'
        pin    = '\Memory\Pages Input/sec'
        disk   = '\PhysicalDisk(*)\Avg. Disk sec/Transfer'
        rx     = '\Network Interface(*)\Bytes Received/sec'
        tx     = '\Network Interface(*)\Bytes Sent/sec'
        disc   = '\Network Interface(*)\Packets Received Discarded'
        udp    = '\UDPv4\Datagrams Received Errors'
    }
    $have = @{}
    foreach ($k in @($paths.Keys)) { $have[$k] = $q.Add($k, $paths[$k]) }
    if (-not $have['cpu']) { Fail 'The Windows performance counters cannot be read, so the monitor cannot run.'; return }
    if (-not $have['eng']) { Info 'This Windows has no GPU counters, so games cannot be detected and GPU load is not measured.' }
    $pq = New-Object FrameCheck.Pdh
    $haveProc = $pq.Add('proc', '\Process(*)\% Processor Time')
    [void]$q.Collect()
    [void]$pq.Collect()
    $self = ([string](Get-Process -Id $PID).ProcessName).ToLower()
    $notGame = '^(dwm|explorer|conhost|windowsterminal|openconsole|powershell|pwsh|cmd|shellexperiencehost|startmenuexperiencehost|searchhost|searchapp|textinputhost|applicationframehost|msedgewebview2|chrome|msedge|firefox|opera|brave|discord|steamwebhelper|wallpaper32|wallpaper64|nvidia overlay|nvidia share|obs64|medal)$'
    $notBg = '^(_total|idle|system idle process|memory compression|registry|secure system)$'

    $script:events = New-Object 'System.Collections.Generic.List[object]'
    $script:open = @{}
    $games = @{}
    $bound = @{ gpu = 0; cpu = 0; other = 0 }
    $gameSec = 0
    $bg = @{}
    $peakVram = 0.0
    $peakVramOf = 0.0
    $minAvail = [double]::MaxValue
    $prevDisc = $null
    $prevUdp = $null
    $names = @{}
    $gamePid = 0
    $game = ''
    $busy = $null
    $cpuTotal = 0.0
    $maxCore = 0.0
    $vNow = 0.0
    $vOf = 0.0
    $start = Get-Date
    $end = $start.AddMinutes($minutes)
    $lastStatus = $start
    $tick = 0

    Say ''
    Say ('  Monitor running since ' + $start.ToString('HH:mm:ss') + '. Start your game now; come back and press Q to stop.')

    while ((Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 1000
        $stop = $false
        try { while ([Console]::KeyAvailable) { if ([Console]::ReadKey($true).Key -eq 'Q') { $stop = $true } } } catch { }
        if ($stop) { break }
        if (-not $q.Collect()) { continue }
        $tick++
        $now = Get-Date

        # Processor: busiest core, clock relative to base, limits, driver load.
        $maxCore = 0.0
        foreach ($kv in $q.Read('core').GetEnumerator()) { if ($kv.Key -match '^\d+,\d+$' -and $kv.Value -gt $maxCore) { $maxCore = $kv.Value } }
        $cpuTotal = 0.0
        foreach ($v in $q.Read('cpu').Values) { $cpuTotal = $v }
        $maxPerf = $null
        foreach ($kv in $q.Read('perf').GetEnumerator()) { if ($kv.Key -match '^\d+,\d+$' -and ($null -eq $maxPerf -or $kv.Value -gt $maxPerf)) { $maxPerf = $kv.Value } }
        $limit = 0.0
        foreach ($v in $q.Read('limit').Values) { $limit = $v }
        $isr = $q.Read('isr')
        $maxDpc = 0.0
        $dpcCore = ''
        foreach ($kv in $q.Read('dpc').GetEnumerator()) {
            if ($kv.Key -notmatch '^\d+,\d+$') { continue }
            $sum = $kv.Value + [double]$isr[$kv.Key]
            if ($sum -gt $maxDpc) { $maxDpc = $sum; $dpcCore = $kv.Key }
        }

        # The game: the program in front if it renders, else the biggest 3D user.
        $gl = $null
        if ($have['eng']) { $gl = [FrameCheck.GpuLoad]::Parse($q.Read('eng')) }
        $gamePid = 0
        if ($gl) {
            $fg = [FrameCheck.Win]::ForegroundPid()
            if ($fg -and $gl.Pid3D.ContainsKey($fg) -and $gl.Pid3D[$fg] -ge 5) { $gamePid = $fg }
            else {
                $top = 0.0
                foreach ($kv in $gl.Pid3D.GetEnumerator()) { if ($kv.Value -gt $top) { $top = $kv.Value; $gamePid = $kv.Key } }
                if ($top -lt 20) { $gamePid = 0 }
            }
        }
        $game = ''
        if ($gamePid) {
            if (-not $names.ContainsKey($gamePid)) { $names[$gamePid] = [string](Get-Process -Id $gamePid).ProcessName }
            $game = $names[$gamePid]
            if (-not $game -or $game.ToLower() -match $notGame) { $game = '' }
        }
        $busy = $null
        $vNow = 0.0
        $vOf = 0.0
        if ($game) {
            $luid = [string]$gl.PidLuid[$gamePid]
            if ($gl.Busy.ContainsKey($luid)) { $busy = $gl.Busy[$luid] }
            foreach ($kv in $q.Read('ded').GetEnumerator()) {
                if ($kv.Key -match '^(luid_0x[0-9a-fA-F]+_0x[0-9a-fA-F]+)' -and $Matches[1] -eq $luid) { $vNow += $kv.Value }
            }
            if ($vram.ContainsKey($luid)) { $vOf = $vram[$luid] }
        }

        # Memory, disks, network.
        $avail = $null
        foreach ($v in $q.Read('avail').Values) { $avail = $v }
        $commit = 0.0
        foreach ($v in $q.Read('commit').Values) { $commit = $v }
        $pin = 0.0
        foreach ($v in $q.Read('pin').Values) { $pin = $v }
        $diskMax = 0.0
        $diskName = ''
        foreach ($kv in $q.Read('disk').GetEnumerator()) { if ($kv.Key -ne '_Total' -and $kv.Value -gt $diskMax) { $diskMax = $kv.Value; $diskName = $kv.Key } }
        $rx = 0.0
        foreach ($v in $q.Read('rx').Values) { if ($v -gt $rx) { $rx = $v } }
        $tx = 0.0
        foreach ($v in $q.Read('tx').Values) { if ($v -gt $tx) { $tx = $v } }
        $disc = 0.0
        foreach ($v in $q.Read('disc').Values) { $disc += $v }
        $udp = 0.0
        foreach ($v in $q.Read('udp').Values) { $udp = $v }
        $discDelta = if ($null -ne $prevDisc) { $disc - $prevDisc } else { 0 }
        $udpDelta = if ($null -ne $prevUdp) { $udp - $prevUdp } else { 0 }
        $prevDisc = $disc
        $prevUdp = $udp

        # Programs using the CPU, every 2 seconds.
        $hogs = @()
        if ($haveProc -and $tick % 2 -eq 0 -and $pq.Collect()) {
            foreach ($kv in $pq.Read('proc').GetEnumerator()) {
                $pn = ([string]$kv.Key).ToLower()
                if ($pn -match $notBg -or $pn -eq $self -or ($game -and $pn -eq $game.ToLower())) { continue }
                $share = $kv.Value / $cores
                if ($game) { $bg[$kv.Key] = [double]$bg[$kv.Key] + 2 * $kv.Value / 100 }
                if ($share -ge 10 -or $kv.Value -ge 80) { $hogs += [pscustomobject]@{ Name = $kv.Key; Share = $share } }
            }
        }

        if ($game) {
            $gameSec++
            $games[$game] = [int]$games[$game] + 1
            if ($null -ne $busy) {
                if ($busy -ge 95) { $bound.gpu++ } elseif ($busy -lt 85 -and $maxCore -ge 80) { $bound.cpu++ } else { $bound.other++ }
            }
            if ($limit -ge 5) { Note 'cpulimit' '' $limit }
            if ($maxCore -ge 50 -and $null -ne $maxPerf -and $maxPerf -gt 0 -and $maxPerf -lt 90) { Note 'cpuclock' '' $maxPerf }
            if ($maxDpc -ge 10) { Note 'dpc' $dpcCore $maxDpc }
            if ($vOf -gt 0) {
                if ($vNow -gt $peakVram) { $peakVram = $vNow; $peakVramOf = $vOf }
                if ($vNow -ge 0.95 * $vOf) { Note 'vram' '' ($vNow / 1GB) }
            }
            if ($null -ne $avail) {
                if ($avail -lt $minAvail) { $minAvail = $avail }
                if ($avail -lt [Math]::Max(800, 0.05 * $ramMB)) { Note 'ram' '' $avail }
                if ($pin -ge 300 -and $avail -lt 0.15 * $ramMB) { Note 'paging' '' $pin }
            }
            if ($commit -ge 90) { Note 'commit' '' $commit }
            if ($diskMax -ge 0.1) { Note 'disk' $diskName (1000 * $diskMax) }
            if ($tx -ge 125000) { Note 'upload' '' (8 * $tx / 1e6) }
            if ($rx -ge 2500000) { Note 'download' '' (8 * $rx / 1e6) }
            if ($discDelta -gt 0) { Note 'nicdrop' '' $discDelta }
            if ($udpDelta -gt 0) { Note 'udpdrop' '' $udpDelta }
            foreach ($h in $hogs) { Note 'bgcpu' $h.Name $h.Share 2 }
        }

        if (($now - $lastStatus).TotalSeconds -ge 30) {
            $lastStatus = $now
            $s = '  ' + $now.ToString('HH:mm:ss') + '  '
            if ($game) {
                $s += $game
                if ($null -ne $busy) { $s += (': GPU {0:0}%' -f $busy) }
                $s += (', CPU {0:0}% (busiest core {1:0}%)' -f $cpuTotal, $maxCore)
                if ($vOf -gt 0) { $s += (', video memory {0:0.0} of {1:0.0} GB' -f ($vNow / 1GB), ($vOf / 1GB)) }
            } else {
                $s += 'no game detected yet'
            }
            Say ($s + ', notes: ' + $script:events.Count)
        }
    }
    $q.Dispose()
    $pq.Dispose()

    # ---- Report ---------------------------------------------------------------
    Say ''
    Say ' --------------------------------------------------------------'
    Say ('  Monitor stopped at ' + (Get-Date).ToString('HH:mm:ss') + '.')
    if (-not $gameSec) {
        Info 'No game was detected: no program used the graphics card''s 3D engine. Start the monitor first, then the game, and play for a few minutes.'
        return
    }
    $main = @($games.GetEnumerator() | Sort-Object -Property Value -Descending)[0].Key
    Ok ('Game: ' + $main + ', watched for ' + (Format-Duration $gameSec) + '.')
    $tot = $bound.gpu + $bound.cpu + $bound.other
    if ($tot -ge 10) {
        $gp = 100.0 * $bound.gpu / $tot
        $cp = 100.0 * $bound.cpu / $tot
        $op = 100.0 - $gp - $cp
        Say ('  Limited by: the graphics card {0:0}% of the time, the CPU {1:0}%, a frame cap, V-Sync or the game {2:0}%.' -f $gp, $cp, $op)
        if ($gp -ge 60) {
            Info 'Mostly limited by the graphics card: graphics settings and resolution set your FPS. Upscaling (DLSS, FSR, XeSS) or lower settings raise it; CPU, memory and Windows tweaks will not raise the average.'
        }
        if ($cp -ge 15) {
            Info ('Limited by the CPU {0:0}% of the time, and those are the moments the 1% lows dip. There FPS depends on the CPU, the memory speed and channels (part 3 of the check) and background programs; CPU-heavy game settings (view distance, crowds, physics) matter more than graphics settings.' -f $cp)
        }
        if ($op -ge 60) {
            Info 'Mostly neither was at its limit: a frame cap, V-Sync or the game engine set the FPS. With a cap that is ideal for steady frame times.'
        }
    }
    if ($peakVramOf -gt 0) { Say ('  Video memory: at most {0:0.0} of {1:0.0} GB.' -f ($peakVram / 1GB), ($peakVramOf / 1GB)) }
    if ($minAvail -lt [double]::MaxValue) { Say ('  Free memory: at least {0:0.0} GB.' -f ($minAvail / 1024)) }
    $top = @($bg.GetEnumerator() | Where-Object { $_.Value -ge 5 } | Sort-Object -Property Value -Descending | Select-Object -First 5)
    if ($top.Count) { Say ('  Most CPU time besides the game: ' + (($top | ForEach-Object { '{0} ({1:0} s)' -f $_.Key, $_.Value }) -join ', ') + '.') }

    $texts = [ordered]@{
        cpulimit = @('The CPU was held back by its power or temperature limit', 'Check CPU temperatures (HWiNFO) and the cooler; on a laptop, plug in and use the maker''s performance mode.')
        cpuclock = @('The CPU ran below its base clock while busy', 'That is heat, a power limit or a power-saving setting: check temperatures and the cooler, and the BIOS power limits.')
        dpc      = @('A driver kept a CPU core busy with interrupt work', 'Run LatencyMon while playing: it names the driver (network, audio, USB and storage are common). Update or replace it.')
        vram     = @('Video memory was full', 'Textures then spill into system memory and frames stall: lower texture quality one step, or the resolution, and close browsers and video apps.')
        ram      = @('Memory was nearly full', 'Close other programs while playing; 32 GB avoids this in heavy games.')
        paging   = @('Windows read memory back from disk', 'Memory was short, so Windows paged: that is stutter. Close other programs; more memory fixes it.')
        commit   = @('Committed memory was near its limit', 'Keep the page file on System managed and close other programs.')
        disk     = @('A disk took over 100 ms to answer', 'Games that stream from that disk hitch: move the game to an SSD, and look for downloads or scans using the disk.')
        bgcpu    = @('Other programs used a lot of CPU', 'Close them while playing, or schedule them for another time.')
        upload   = @('This PC uploaded while you played', 'With bufferbloat that raises your ping: NetTune''s upload limit or SQM in the router fixes it.')
        download = @('This PC downloaded at high speed while you played', 'Usually an update or a game download: pause it while playing, or cap it in the launcher.')
        nicdrop  = @('The network adapter discarded incoming packets', 'NetTune raises its receive buffers; if it continues, update the network driver.')
        udpdrop  = @('Windows dropped UDP packets that a program did not read in time', 'Usually the game or another program froze for a moment; check the other notes at the same times.')
    }
    $shown = 0
    foreach ($type in @($texts.Keys)) {
        $evs = @($script:events | Where-Object { $_.Type -eq $type })
        if ($type -eq 'upload' -or $type -eq 'download') { $evs = @($evs | Where-Object { $_.Seconds -ge 3 }) }
        if (-not $evs.Count) { continue }
        $shown++
        $secs = ($evs | Measure-Object -Property Seconds -Sum).Sum
        $times = @($evs | Select-Object -First 6 | ForEach-Object { $_.First.ToString('HH:mm:ss') + $(if ($_.Detail) { ' (' + $_.Detail + ')' }) })
        $more = if ($evs.Count -gt 6) { ' and ' + ($evs.Count - 6) + ' more' } else { '' }
        $peak = ($evs | Measure-Object -Property Peak -Maximum).Maximum
        $pk = switch ($type) {
            'cpulimit' { ', up to {0:0}% limited' -f $peak }
            'cpuclock' { ', down to {0:0}% of base clock' -f ($evs | Measure-Object -Property Peak -Minimum).Minimum }
            'dpc' { ', up to {0:0}% of a core' -f $peak }
            'vram' { ', {0:0.0} GB used' -f $peak }
            'ram' { ', {0:0} MB left' -f ($evs | Measure-Object -Property Peak -Minimum).Minimum }
            'paging' { ', up to {0:0} pages/s' -f $peak }
            'commit' { ', up to {0:0}%' -f $peak }
            'disk' { ', up to {0:0} ms' -f $peak }
            'bgcpu' { ', up to {0:0}% of the CPU' -f $peak }
            'upload' { ', up to {0:0.0} Mbps' -f $peak }
            'download' { ', up to {0:0} Mbps' -f $peak }
            default { '' }
        }
        Say ''
        Say ('  [WARN] ' + $texts[$type][0] + ': ' + $evs.Count + ' time' + $(if ($evs.Count -ne 1) { 's' }) + ', ' + (Format-Duration $secs) + ' in total' + $pk + '.')
        More ('At ' + ($times -join ', ') + $more + '.')
        More $texts[$type][1]
    }
    if (-not $shown) {
        Say ''
        Ok 'Nothing on the PC side lined up with dips: no clock limits, driver spikes, full video or system memory, disk stalls or background load.'
        More 'Dips that remain come from the game itself (shader compilation, streaming) or the frame pacing settings (see above).'
    }
    Say ''
    Info 'To line notes up with frame drops, record frame times at the same time with CapFrameX or PresentMon and compare the clock times.'
}

default { Fail ('Unknown part: ' + $env:FC_STEP) }
}
#FCPS
