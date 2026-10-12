# sucklesswsl — Windows-side helper for the VcXsrv session.
#   -Native -ExePath <vcxsrv.exe>   print "WxH dpi" for the primary monitor
#                                   and stop Windows from bitmap-scaling VcXsrv
#   -ProcessId <pid>                minimize that window (drops the key hook)
param(
    [int]$ProcessId = 0,
    [switch]$Native,
    [string]$ExePath = ''
)

$ErrorActionPreference = 'Stop'

if ($Native) {
    # Sizes come from the primary monitor's own DC. DESKTOPHORZRES is the
    # current mode in real pixels on any scale; HORZRES is what a DPI-unaware
    # process is told. GetDC(0) is not used: on a multi-monitor desktop that
    # is the virtual screen, not one panel.
    if (-not ('Suckless.Mon' -as [type])) {
        Add-Type -Namespace Suckless -Name Mon -MemberDefinition @'
public struct RECT { public int L, T, R, B; }
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public struct MI {
    public int cbSize;
    public RECT mon;
    public RECT work;
    public uint flags;
    [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 32)]
    public string name;
}
public delegate bool Proc(System.IntPtr h, System.IntPtr hdc, ref RECT rc, System.IntPtr data);
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool EnumDisplayMonitors(System.IntPtr a, System.IntPtr b, Proc cb, System.IntPtr d);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool GetMonitorInfo(System.IntPtr h, ref MI mi);
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr CreateDC(string drv, string dev, string output, System.IntPtr init);
[System.Runtime.InteropServices.DllImport("gdi32.dll")]
public static extern bool DeleteDC(System.IntPtr hdc);
[System.Runtime.InteropServices.DllImport("gdi32.dll")]
public static extern int GetDeviceCaps(System.IntPtr hdc, int index);
[System.Runtime.InteropServices.DllImport("shcore.dll")]
public static extern int GetDpiForMonitor(System.IntPtr h, int type, out uint x, out uint y);
public static System.Collections.Generic.List<string> Rows = new System.Collections.Generic.List<string>();
static Proc keep;
public static void Collect() {
    Rows.Clear();
    keep = OnMon;
    EnumDisplayMonitors(System.IntPtr.Zero, System.IntPtr.Zero, keep, System.IntPtr.Zero);
}
static bool OnMon(System.IntPtr h, System.IntPtr hdcMon, ref RECT rc, System.IntPtr data) {
    MI mi = new MI();
    mi.cbSize = System.Runtime.InteropServices.Marshal.SizeOf(typeof(MI));
    if (!GetMonitorInfo(h, ref mi) || string.IsNullOrEmpty(mi.name)) return true;
    System.IntPtr dc = CreateDC(mi.name, null, null, System.IntPtr.Zero);
    if (dc == System.IntPtr.Zero) return true;
    int physW = GetDeviceCaps(dc, 118); // DESKTOPHORZRES
    int physH = GetDeviceCaps(dc, 117); // DESKTOPVERTRES
    int logW = GetDeviceCaps(dc, 8);    // HORZRES
    int logPx = GetDeviceCaps(dc, 88);  // LOGPIXELSX
    DeleteDC(dc);
    uint api = 0, apiY = 0;
    GetDpiForMonitor(h, 0, out api, out apiY); // often 96 while this process is unaware
    int primary = ((mi.flags & 1) != 0) ? 1 : 0;
    Rows.Add(primary + " " + physW + " " + physH + " " + logW + " " + api + " " + logPx);
    return true;
}
'@
    }
    [Suckless.Mon]::Collect()
    $pick = $null
    foreach ($row in [Suckless.Mon]::Rows) {
        $f = $row -split ' '
        if ($f.Length -ne 6) { continue }
        if ($f[0] -eq '1') { $pick = $f; break }
        if (-not $pick) { $pick = $f }
    }
    if (-not $pick) { exit 1 }
    $physW = [int]$pick[1]
    $physH = [int]$pick[2]
    $logW = [int]$pick[3]
    $api = [int]$pick[4]
    $logPx = [int]$pick[5]
    if ($physW -lt 640 -or $physH -lt 480) { exit 1 }
    # Unaware process: physical and logical sizes differ, and both DPI
    # queries lie (96). Aware process: the sizes match and the DPI query
    # is the real one. 100% scale: sizes match and 96 is correct.
    $dpi = 96
    if ($logW -gt 0 -and $physW -gt $logW) {
        $dpi = [int][math]::Round(96.0 * $physW / $logW)
    } elseif ($api -ge 96) {
        $dpi = $api
    } elseif ($logPx -ge 96) {
        $dpi = $logPx
    }
    if ($dpi -lt 96 -or $dpi -gt 480) { $dpi = 96 }
    # Per-user, per-exe. "Application" DPI override: the next VcXsrv draws
    # real pixels instead of a bitmap Windows stretches. Any account that
    # runs the launcher gets this for its own vcxsrv.exe.
    if ($ExePath) {
        $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
        if (-not (Test-Path $layers)) { New-Item -Path $layers -Force | Out-Null }
        New-ItemProperty -Path $layers -Name $ExePath -Value '~ HIGHDPIAWARE' -PropertyType String -Force | Out-Null
    }
    Write-Output "$physW`x$physH $dpi"
    exit 0
}

if (-not ('Suckless.Win' -as [type])) {
    Add-Type -Namespace Suckless -Name Win -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
}

$proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $proc -or $proc.MainWindowHandle -eq [IntPtr]::Zero) {
    exit 1
}
# 6 = SW_MINIMIZE. The window leaves the foreground, which uninstalls the hook.
[void][Suckless.Win]::ShowWindow($proc.MainWindowHandle, 6)
exit 0
