<#
.SYNOPSIS
    Помощник для ручной проверки форм в клиенте 1С: список окон, щелчок, клавиши, снимок экрана.

.EXAMPLE
    tools\ui.ps1 -Action list                       # окна всех процессов 1cv8/1cv8c
    tools\ui.ps1 -Action click -X 860 -Y 757         # щелчок в физических координатах экрана
    tools\ui.ps1 -Handle 123456 -Keys '{ENTER}'      # вывести окно вперёд и послать клавиши
    tools\ui.ps1 -Shot build\shots\s1.png            # снимок основного экрана

.NOTES
    Координаты физические (процесс помечен DPI-aware). Escape в предупреждении безопасности
    означает «Нет»; кириллицу в поля 1С надёжнее вставлять через буфер обмена, чем SendKeys.
#>
param(
    [ValidateSet('list', 'click', 'none')] [string]$Action = 'none',
    [int]$X, [int]$Y,
    [long]$Handle = 0,
    [string]$Keys,
    [string]$Shot
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace DevToolsUi -Name W -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder t, int n);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder t, int n);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
[DevToolsUi.W]::SetProcessDPIAware() | Out-Null

if ($Action -eq 'list') {
    $ids = @(Get-Process 1cv8, 1cv8c -ErrorAction SilentlyContinue | ForEach-Object Id)
    $wins = New-Object System.Collections.Generic.List[object]
    $cb = [DevToolsUi.W+EnumWindowsProc] {
        param($h, $l)
        $o = 0
        [DevToolsUi.W]::GetWindowThreadProcessId($h, [ref]$o) | Out-Null
        if ($ids -contains $o -and [DevToolsUi.W]::IsWindowVisible($h)) {
            $r = New-Object DevToolsUi.W+RECT
            [DevToolsUi.W]::GetWindowRect($h, [ref]$r) | Out-Null
            $t = New-Object System.Text.StringBuilder 256
            [DevToolsUi.W]::GetWindowText($h, $t, 256) | Out-Null
            $c = New-Object System.Text.StringBuilder 256
            [DevToolsUi.W]::GetClassName($h, $c, 256) | Out-Null
            # Узкие полосы V8Window — тени окон, они не нужны.
            if ($c.ToString() -ne 'V8Window') {
                $wins.Add([pscustomobject]@{ Pid = $o; Handle = $h; Class = $c.ToString(); Title = $t.ToString(); L = $r.Left; T = $r.Top; W = $r.Right - $r.Left; H = $r.Bottom - $r.Top })
            }
        }
        $true
    }
    [DevToolsUi.W]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    $wins | Format-Table Pid, Handle, Class, Title, L, T, W, H -AutoSize | Out-String -Width 220
}
if ($Handle -ne 0) { [DevToolsUi.W]::SetForegroundWindow([IntPtr]$Handle) | Out-Null; Start-Sleep -Milliseconds 400 }
if ($Keys) { [System.Windows.Forms.SendKeys]::SendWait($Keys); Start-Sleep -Milliseconds 500; 'keys sent' }
if ($Action -eq 'click') {
    [DevToolsUi.W]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 200
    [DevToolsUi.W]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [DevToolsUi.W]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    'clicked'
}
if ($Shot) {
    $dir = Split-Path -Parent $Shot
    if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "shot $($b.Width)x$($b.Height) -> $Shot"
}
