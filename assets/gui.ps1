<#
  gui.ps1 — 屏幕读取与鼠标键盘控制（Windows / PowerShell 5.1+）

  用法示例：
    .\gui.ps1 windows                        列出可见顶层窗口
    .\gui.ps1 shot out.png                   截全屏（虚拟桌面）
    .\gui.ps1 shot out.png -window "记事本"   截指定窗口
    .\gui.ps1 shot out.png -region 0,0,800,600
    .\gui.ps1 shot out.png -cursor           截图并标出光标位置
    .\gui.ps1 pos                            打印光标当前坐标
    .\gui.ps1 move 800 500                   移动光标
    .\gui.ps1 click 800 500                  左键单击
    .\gui.ps1 click 800 500 -button right -count 2
    .\gui.ps1 drag 100 100 400 300           左键拖拽
    .\gui.ps1 scroll 800 500 3               滚轮（正=上，负=下，1=120单位）
    .\gui.ps1 type "hello 中文"              逐字符 Unicode 输入
    .\gui.ps1 key "ctrl+s"                   组合键
    .\gui.ps1 key "enter"
    .\gui.ps1 activate "DeepSeek"            激活窗口到前台

  约定：所有坐标都是物理像素（脚本内部开启 per-monitor DPI v2），
  与 `shot` 输出的图片像素一一对应，可放心把图上的像素坐标直接当参数用。
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]] $Argv
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

if (-not ('GuiNative' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class GuiNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT
    {
        [FieldOffset(0)] public uint type;
        [FieldOffset(4)] public MOUSEINPUT mi;
        [FieldOffset(4)] public KEYBDINPUT ki;
    }

    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);

    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    const uint MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    const uint MOUSEEVENTF_WHEEL = 0x0800;
    const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint KEYEVENTF_UNICODE = 0x0004;

    public static void EnableDpiAwareness()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { }
    }

    static INPUT MouseInput(uint flags, int dx, int dy, uint data)
    {
        INPUT i = new INPUT();
        i.type = 0;
        i.mi.dx = dx;
        i.mi.dy = dy;
        i.mi.mouseData = data;
        i.mi.dwFlags = flags;
        return i;
    }

    static INPUT KeyInput(ushort vk, ushort scan, uint flags)
    {
        INPUT i = new INPUT();
        i.type = 1;
        i.ki.wVk = vk;
        i.ki.wScan = scan;
        i.ki.dwFlags = flags;
        return i;
    }

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SendInput")]
    static extern uint SendRaw(uint nInputs, IntPtr pInputs, int cbSize);
    [DllImport("user32.dll")]
    static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    static int Cb() { return Marshal.SizeOf(typeof(INPUT)); }

    static uint SendAll(INPUT[] arr)
    {
        int size = Cb();
        IntPtr buf = Marshal.AllocHGlobal(size * arr.Length);
        try
        {
            for (int i = 0; i < arr.Length; i++)
                Marshal.StructureToPtr(arr[i], new IntPtr(buf.ToInt64() + (long)i * size), false);
            return SendRaw((uint)arr.Length, buf, size);
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    public static bool MoveTo(int x, int y)
    {
        if (SetCursorPos(x, y))
        {
            POINT p;
            if (GetCursorPos(out p) && Math.Abs(p.X - x) <= 2 && Math.Abs(p.Y - y) <= 2) return true;
        }
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77);
        int vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
        if (vw <= 1) vw = 2;
        if (vh <= 1) vh = 2;
        int ax = (int)Math.Round((double)(x - vx) * 65535.0 / (vw - 1));
        int ay = (int)Math.Round((double)(y - vy) * 65535.0 / (vh - 1));
        mouse_event(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE, ax, ay, 0, UIntPtr.Zero);
        POINT q;
        return GetCursorPos(out q) && Math.Abs(q.X - x) <= 2 && Math.Abs(q.Y - y) <= 2;
    }

    public static void MouseButton(string button, bool down)
    {
        string b = (button ?? "left").ToLowerInvariant();
        uint mf;
        if (b.StartsWith("r")) mf = down ? 0x0008u : 0x0010u;
        else if (b.StartsWith("m")) mf = down ? 0x0020u : 0x0040u;
        else mf = down ? 0x0002u : 0x0004u;
        mouse_event(mf, 0, 0, 0, UIntPtr.Zero);
    }

    public static void Scroll(int notches)
    {
        uint data = (uint)(int)(notches * 120);
        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, data, UIntPtr.Zero);
    }

    public static void KeyDown(ushort vk) { keybd_event((byte)vk, 0, 0, UIntPtr.Zero); }
    public static void KeyUp(ushort vk) { keybd_event((byte)vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero); }

    public static void TypeText(string s)
    {
        if (string.IsNullOrEmpty(s)) return;
        List<INPUT> list = new List<INPUT>();
        foreach (char c in s)
        {
            ushort scan = (ushort)c;
            list.Add(KeyInput(0, scan, KEYEVENTF_UNICODE));
            list.Add(KeyInput(0, scan, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
        }
        SendAll(list.ToArray());
    }

    public static POINT Cursor()
    {
        POINT p;
        GetCursorPos(out p);
        return p;
    }

    public static string[] ListWindows()
    {
        List<string> rows = new List<string>();
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(1024);
            GetWindowText(h, sb, sb.Capacity);
            string title = sb.ToString();
            if (title.Trim().Length == 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            int w = r.Right - r.Left, ht = r.Bottom - r.Top;
            if (w < 40 || ht < 40) return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            string proc = "";
            try { proc = Process.GetProcessById((int)pid).ProcessName; } catch { }
            rows.Add(string.Format("{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}",
                h.ToInt64(), title, r.Left, r.Top, w, ht, pid, proc));
            return true;
        }, IntPtr.Zero);
        return rows.ToArray();
    }

    public static IntPtr FindWindow(string needle)
    {
        if (string.IsNullOrEmpty(needle)) return IntPtr.Zero;
        string n = needle.ToLowerInvariant();
        IntPtr best = IntPtr.Zero;
        int bestScore = 0;
        foreach (string row in ListWindows())
        {
            string[] p = row.Split('\t');
            if (p.Length < 8) continue;
            string title = p[1].ToLowerInvariant();
            string proc = p[7].ToLowerInvariant();
            int score = 0;
            if (title == n) score = 100;
            else if (title.StartsWith(n)) score = 80;
            else if (title.Contains(n)) score = 60;
            else if (proc == n) score = 50;
            else if (proc.Contains(n)) score = 40;
            if (score > bestScore)
            {
                bestScore = score;
                best = new IntPtr(long.Parse(p[0]));
            }
        }
        return best;
    }

    public static bool ForceForeground(IntPtr h)
    {
        if (h == IntPtr.Zero) return false;
        if (IsIconic(h)) ShowWindow(h, 9);
        uint pid;
        uint tid = GetWindowThreadProcessId(h, out pid);
        uint cur = GetCurrentThreadId();
        bool ok;
        if (tid != cur)
        {
            AttachThreadInput(cur, tid, true);
            BringWindowToTop(h);
            ok = SetForegroundWindow(h);
            AttachThreadInput(cur, tid, false);
        }
        else
        {
            BringWindowToTop(h);
            ok = SetForegroundWindow(h);
        }
        if (!ok) { ShowWindow(h, 9); ShowWindow(h, 5); ok = SetForegroundWindow(h); }
        return ok;
    }

    public static bool GetRect(IntPtr h, out int left, out int top, out int width, out int height)
    {
        RECT r;
        left = top = width = height = 0;
        if (h == IntPtr.Zero || !GetWindowRect(h, out r)) return false;
        left = r.Left; top = r.Top;
        width = r.Right - r.Left; height = r.Bottom - r.Top;
        return true;
    }
}
'@
}

[GuiNative]::EnableDpiAwareness()

# ---- 参数解析：位置参数 + -name value ----
$pos = New-Object System.Collections.ArrayList
$opt = @{}
$literal = $false
for ($i = 0; $i -lt $Argv.Count; $i++) {
    $a = $Argv[$i]
    if (-not $literal -and $a -is [string] -and $a -eq '--') { $literal = $true; continue }
    if (-not $literal -and $a -is [string] -and $a.Length -gt 1 -and $a.StartsWith('-') -and $a -notmatch '^-?\d') {
        $name = $a.TrimStart('-').ToLowerInvariant()
        $val = $null
        if ($i + 1 -lt $Argv.Count) {
            $nxt = $Argv[$i + 1]
            if (-not ($nxt -is [string] -and $nxt.Length -gt 1 -and $nxt.StartsWith('-') -and $nxt -notmatch '^-?\d')) {
                $val = $nxt; $i++
            }
        }
        if ($null -eq $val) { $opt[$name] = $true } else { $opt[$name] = $val }
    }
    else { [void]$pos.Add($a) }
}

if ($pos.Count -eq 0) { Get-Help $PSCommandPath -ErrorAction SilentlyContinue; Write-Host "`n没有参数。用 'shot out.png' 或 'windows' 开始。" ; return }

$cmd = ([string]$pos[0]).ToLowerInvariant()
$rest = @()
if ($pos.Count -gt 1) { $rest = $pos[1..($pos.Count - 1)] }

function Get-RectFromString([string]$s) {
    $p = $s -split ','
    if ($p.Count -ne 4) { throw "region 需要 x,y,w,h 四段，例如 0,0,800,600" }
    @{ X = [int]$p[0]; Y = [int]$p[1]; W = [int]$p[2]; H = [int]$p[3] }
}

switch ($cmd) {

    'windows' {
        $rows = [GuiNative]::ListWindows()
        "{0,-14} {1,-10} {2,-26} {3}" -f 'HWND', 'PID', 'RECT', 'TITLE'
        foreach ($row in $rows) {
            $p = $row -split "`t"
            $hw = [long]$p[0]
            "{0,-14} {1,-10} {2,-26} {3}" -f ('0x' + $hw.ToString('X')), $p[6], ("{0},{1} {2}x{3}" -f $p[2], $p[3], $p[4], $p[5]), ($p[1] + "  [" + $p[7] + "]")
        }
    }

    'pos' {
        $pt = [GuiNative]::Cursor()
        "{0},{1}" -f $pt.X, $pt.Y
    }

    'fg' {
        $h = [GuiNative]::GetForegroundWindow()
        $sb = New-Object System.Text.StringBuilder 512
        [void][GuiNative]::GetWindowText($h, $sb, 512)
        [pscustomobject]@{ hwnd = ('0x' + $h.ToInt64().ToString('X')); title = $sb.ToString() } | ConvertTo-Json -Compress
    }

    'shot' {
        $out = if ($rest.Count -ge 1) { [string]$rest[0] } else { 'shot.png' }
        if (-not [System.IO.Path]::IsPathRooted($out)) { $out = Join-Path (Get-Location).Path $out }
        $dir = [System.IO.Path]::GetDirectoryName($out)
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

        $hwnd = [IntPtr]::Zero
        if ($opt.ContainsKey('window')) { $hwnd = [GuiNative]::FindWindow([string]$opt['window']) }
        elseif ($opt.ContainsKey('hwnd')) { $hwnd = [IntPtr]([long]$opt['hwnd']) }

        if ($hwnd -ne [IntPtr]::Zero) {
            $l = 0; $t = 0; $w = 0; $h = 0
            if (-not [GuiNative]::GetRect($hwnd, [ref]$l, [ref]$t, [ref]$w, [ref]$h)) { throw "拿不到窗口矩形" }
            $x = $l; $y = $t; $width = $w; $height = $h
        }
        elseif ($opt.ContainsKey('region')) {
            $r = Get-RectFromString ([string]$opt['region'])
            $x = $r.X; $y = $r.Y; $width = $r.W; $height = $r.H
        }
        else {
            $x = [GuiNative]::GetSystemMetrics(76)
            $y = [GuiNative]::GetSystemMetrics(77)
            $width = [GuiNative]::GetSystemMetrics(78)
            $height = [GuiNative]::GetSystemMetrics(79)
        }
        if ($width -le 0 -or $height -le 0) { throw "截图区域无效: ${width}x${height}" }

        $bmp = New-Object System.Drawing.Bitmap $width, $height
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                if ($hwnd -ne [IntPtr]::Zero -and $opt.ContainsKey('print')) {
                    $hdc = $g.GetHdc()
                    try { [void][GuiNative]::PrintWindow($hwnd, $hdc, 2) }
                    finally { $g.ReleaseHdc($hdc) }
                }
                else {
                    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $width, $height))
                }
            }
            finally { $g.Dispose() }

            if ($opt.ContainsKey('cursor')) {
                $pt = [GuiNative]::Cursor()
                $cx = $pt.X - $x; $cy = $pt.Y - $y
                if ($cx -ge 0 -and $cy -ge 0 -and $cx -lt $width -and $cy -lt $height) {
                    $g2 = [System.Drawing.Graphics]::FromImage($bmp)
                    try {
                        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red), 3
                        $g2.DrawEllipse($pen, $cx - 14, $cy - 14, 28, 28)
                        $g2.DrawLine($pen, $cx - 22, $cy, $cx + 22, $cy)
                        $g2.DrawLine($pen, $cx, $cy - 22, $cx, $cy + 22)
                        $pen.Dispose()
                    }
                    finally { $g2.Dispose() }
                }
            }

            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $bmp.Dispose() }

        [pscustomobject]@{
            path   = $out
            x      = $x
            y      = $y
            width  = $width
            height = $height
            bytes  = (Get-Item $out).Length
        } | ConvertTo-Json -Compress
    }

    'activate' {
        if ($rest.Count -lt 1) { throw "activate 需要窗口标题关键字" }
        $h = [GuiNative]::FindWindow([string]$rest[0])
        if ($h -eq [IntPtr]::Zero) { throw "找不到窗口: $($rest[0])" }
        $ok = [GuiNative]::ForceForeground($h)
        [pscustomobject]@{ ok = $ok; hwnd = ('0x' + $h.ToInt64().ToString('X')) } | ConvertTo-Json -Compress
    }

    'move' {
        if ($rest.Count -lt 2) { throw "move 需要 x y" }
        $x = [int]$rest[0]; $y = [int]$rest[1]
        [GuiNative]::MoveTo($x, $y)
        Start-Sleep -Milliseconds 40
        $pt = [GuiNative]::Cursor()
        "{0},{1}" -f $pt.X, $pt.Y
    }

    'click' {
        if ($rest.Count -ge 2) {
            [GuiNative]::MoveTo([int]$rest[0], [int]$rest[1])
            Start-Sleep -Milliseconds 60
        }
        $button = if ($opt.ContainsKey('button')) { [string]$opt['button'] } else { 'left' }
        $count = if ($opt.ContainsKey('count')) { [int]$opt['count'] } else { 1 }
        $gap = if ($opt.ContainsKey('gap')) { [int]$opt['gap'] } else { 90 }
        for ($k = 0; $k -lt $count; $k++) {
            [GuiNative]::MouseButton($button, $true)
            Start-Sleep -Milliseconds 40
            [GuiNative]::MouseButton($button, $false)
            if ($k -lt $count - 1) { Start-Sleep -Milliseconds $gap }
        }
        $pt = [GuiNative]::Cursor()
        "click {0} x{1} @ {2},{3}" -f $button, $count, $pt.X, $pt.Y
    }

    'drag' {
        if ($rest.Count -lt 4) { throw "drag 需要 x1 y1 x2 y2" }
        $button = if ($opt.ContainsKey('button')) { [string]$opt['button'] } else { 'left' }
        [GuiNative]::MoveTo([int]$rest[0], [int]$rest[1])
        Start-Sleep -Milliseconds 60
        [GuiNative]::MouseButton($button, $true)
        Start-Sleep -Milliseconds 80
        $x1 = [int]$rest[0]; $y1 = [int]$rest[1]; $x2 = [int]$rest[2]; $y2 = [int]$rest[3]
        for ($s = 1; $s -le 10; $s++) {
            $mx = [int]($x1 + ($x2 - $x1) * $s / 10.0)
            $my = [int]($y1 + ($y2 - $y1) * $s / 10.0)
            [GuiNative]::MoveTo($mx, $my)
            Start-Sleep -Milliseconds 15
        }
        Start-Sleep -Milliseconds 80
        [GuiNative]::MouseButton($button, $false)
        "drag {0} ({1},{2}) -> ({3},{4})" -f $button, $x1, $y1, $x2, $y2
    }

    'scroll' {
        if ($rest.Count -ge 3) { [GuiNative]::MoveTo([int]$rest[0], [int]$rest[1]); Start-Sleep -Milliseconds 40 }
        $d = if ($rest.Count -ge 3) { [int]$rest[2] } else { [int]$rest[0] }
        [GuiNative]::Scroll($d)
        "scroll $d"
    }

    'type' {
        $text = [string]::Join(' ', ($rest | ForEach-Object { [string]$_ }))
        if ($text -eq '') { throw "type 需要文本" }
        $text = $text -replace '\\n', "`n" -replace '\\t', "`t"

        if ($opt.ContainsKey('raw')) {
            [GuiNative]::TypeText($text)
            "typed {0} chars (raw)" -f $text.Length
            break
        }

        # 默认走剪贴板粘贴：对中文/任意 Unicode 都可靠，且结束后还原原剪贴板
        $old = $null
        try { $old = Get-Clipboard -Raw -ErrorAction Stop } catch { }
        try { Set-Clipboard -Value $text -ErrorAction Stop }
        catch { [System.Windows.Forms.Clipboard]::SetText($text) }
        Start-Sleep -Milliseconds 120

        [GuiNative]::KeyDown(0x11)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyDown(0x56)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyUp(0x56)
        Start-Sleep -Milliseconds 30
        [GuiNative]::KeyUp(0x11)
        Start-Sleep -Milliseconds 180

        if ($null -ne $old -and $old -ne '') {
            try { Set-Clipboard -Value $old -ErrorAction Stop }
            catch { try { [System.Windows.Forms.Clipboard]::SetText($old) } catch { } }
        }
        "pasted {0} chars" -f $text.Length
    }

    'key' {
        if ($rest.Count -lt 1) { throw "key 需要组合键，例如 ctrl+s" }
        $combo = [string]::Join('+', ($rest | ForEach-Object { [string]$_ }))

        $map = @{
            'ctrl' = 0x11; 'control' = 0x11; 'shift' = 0x10; 'alt' = 0x12; 'win' = 0x5B; 'lwin' = 0x5B; 'rwin' = 0x5C
            'enter' = 0x0D; 'return' = 0x0D; 'esc' = 0x1B; 'escape' = 0x1B; 'space' = 0x20; 'tab' = 0x09
            'backspace' = 0x08; 'bs' = 0x08; 'delete' = 0x2E; 'del' = 0x2E; 'insert' = 0x2D; 'ins' = 0x2D
            'home' = 0x24; 'end' = 0x23; 'pageup' = 0x21; 'pgup' = 0x21; 'pagedown' = 0x22; 'pgdn' = 0x22
            'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27
            'capslock' = 0x14; 'printscreen' = 0x2C; 'pause' = 0x13; 'apps' = 0x5D
        }
        for ($n = 1; $n -le 24; $n++) { $map["f$n"] = 0x6F + $n }

        function Resolve-Vk([string]$t) {
            $t = $t.Trim().ToLowerInvariant()
            if ($map.ContainsKey($t)) { return [int]$map[$t] }
            if ($t -match '^[a-z]$') { return [int][char]([char]::ToUpperInvariant($t)) }
            if ($t -match '^\d$') { return 0x30 + [int]$t }
            $aliases = @{
                '-' = 0xBD; '=' = 0xBB; '[' = 0xDB; ']' = 0xDD; '\' = 0xDC; ';' = 0xBA; "'" = 0xDE
                ',' = 0xBC; '.' = 0xBE; '/' = 0xBF; '`' = 0xC0
            }
            if ($aliases.ContainsKey($t)) { return [int]$aliases[$t] }
            throw "无法识别的按键: $t"
        }

        $parts = $combo -split '\+'
        $vks = @()
        foreach ($p in $parts) { if ($p.Trim() -ne '') { $vks += (Resolve-Vk $p) } }
        if ($vks.Count -eq 0) { throw "组合键为空" }

        $mods = @()
        foreach ($v in $vks[0..($vks.Count - 2)]) { $mods += [uint16]$v }
        $last = [uint16]$vks[$vks.Count - 1]

        foreach ($m in $mods) { [GuiNative]::KeyDown($m); Start-Sleep -Milliseconds 25 }
        [GuiNative]::KeyDown($last)
        Start-Sleep -Milliseconds 35
        [GuiNative]::KeyUp($last)
        for ($k = $mods.Count - 1; $k -ge 0; $k--) { [GuiNative]::KeyUp($mods[$k]); Start-Sleep -Milliseconds 25 }
        "key $combo"
    }

    'wait' {
        $ms = if ($rest.Count -ge 1) { [int]$rest[0] } else { 500 }
        Start-Sleep -Milliseconds $ms
        "waited $ms ms"
    }

    default {
        Write-Host "未知命令: $cmd"
        Write-Host "可用: windows | pos | shot | activate | move | click | drag | scroll | type | key | wait"
        exit 1
    }
}
