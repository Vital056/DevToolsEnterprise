<#
.SYNOPSIS
    Запуск тестовой базы в режиме 1С:Предприятие; с -OpenReport сразу открывает собранный отчёт.

.DESCRIPTION
    Базы берутся из реестра .v8-project.json в корне проекта (в git не попадает, образец —
    .v8-project.json.example): -Base принимает id или алиас, без него берётся default.

    С ключом -OpenReport клиент запускается с /Execute build\launcher\DevToolsLauncher.epf
    и /C "<путь к build\DevToolsEnterprise.erf>": служебная обработка подключает отчёт
    и открывает его стартовую форму. Скрипт при этом сам:
      - закрывает окно входа в Интернет-поддержку (крестиком, данные ИТС не вводятся);
      - подтверждает «Да» в предупреждении безопасности об открытии обработки — только
        для окна, которое появилось у запущенного скриптом клиента.

    В конфигурациях с 1С:CRM закрытый модуль лицензирования может при каждом старте клиента
    показывать окно «К сожалению, возникла непредвиденная ошибка» (не инициализирован параметр
    сеанса CRM_ВариантПоставки). Ошибка не мешает работе; скрипт закрывает это окно: сначала
    Escape, если окно осталось — щелчок по OK, и только когда точка щелчка лежит внутри окна.
    Окно узнаётся по классу V8TopLevelFrameSDIsec, заголовку «1С:Предприятие» и размеру
    (655x295 при масштабе экрана 125%).

.PARAMETER Base
    id или алиас базы из .v8-project.json.

.PARAMETER OpenReport
    Открыть собранный отчёт build\DevToolsEnterprise.erf (собирается scripts\build.bat).

.PARAMETER URL
    Навигационная ссылка, которую открыть после запуска, например e1cib/list/Справочник.Контрагенты.

.PARAMETER Extra
    Дополнительные параметры командной строки клиента как есть.

.PARAMETER WatchSeconds
    Сколько секунд следить за окнами клиента после запуска.

.EXAMPLE
    scripts\run-1c.bat -Base zup -OpenReport
#>
param(
    [string]$Base,
    [switch]$OpenReport,
    [string]$URL,
    [string]$Extra,
    [int]$WatchSeconds = 240
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

#region Окна процесса

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace RunOneC -Name Win32 -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int maxCount);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder text, int maxCount);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
[RunOneC.Win32]::SetProcessDPIAware() | Out-Null

# Размеры ниже сняты при масштабе экрана 125% (120 DPI); после SetProcessDPIAware координаты физические.
$Scale = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 120

$GA_ROOT = 2
$MOUSEEVENTF_LEFTDOWN = 0x0002
$MOUSEEVENTF_LEFTUP = 0x0004

function Get-ProcessWindows([int[]]$ProcessIds) {
    $windows = New-Object System.Collections.Generic.List[object]
    $callback = [RunOneC.Win32+EnumWindowsProc] {
        param($hWnd, $lParam)
        $owner = 0
        [RunOneC.Win32]::GetWindowThreadProcessId($hWnd, [ref]$owner) | Out-Null
        if ($ProcessIds -contains $owner -and [RunOneC.Win32]::IsWindowVisible($hWnd)) {
            $rect = New-Object RunOneC.Win32+RECT
            [RunOneC.Win32]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            $title = New-Object System.Text.StringBuilder 256
            [RunOneC.Win32]::GetWindowText($hWnd, $title, 256) | Out-Null
            $class = New-Object System.Text.StringBuilder 256
            [RunOneC.Win32]::GetClassName($hWnd, $class, 256) | Out-Null
            $windows.Add([pscustomobject]@{
                Handle = $hWnd
                Class  = $class.ToString()
                Title  = $title.ToString()
                Rect   = $rect
                Width  = $rect.Right - $rect.Left
                Height = $rect.Bottom - $rect.Top
            })
        }
        $true
    }
    [RunOneC.Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    $windows
}

function Test-Size($Window, [int]$Width, [int]$Height, [int]$DeltaW = 60, [int]$DeltaH = 40) {
    [math]::Abs($Window.Width - $Width * $Scale) -le $DeltaW * $Scale -and
        [math]::Abs($Window.Height - $Height * $Scale) -le $DeltaH * $Scale
}

# Окно «непредвиденная ошибка» CRM: заголовок «1С:Предприятие», 655x295 при 125%.
# Вопросы конфигурации («Завершить работу?» и т.п.) идут с заголовком приложения и сюда не попадают.
function Test-ErrorDialog($Window) {
    $Window.Class -eq 'V8TopLevelFrameSDIsec' -and $Window.Title -eq '1С:Предприятие' -and (Test-Size $Window 655 295)
}

# Вход в Интернет-поддержку: 467x538 при 125%.
function Test-ItsDialog($Window) {
    $Window.Class -eq 'V8TopLevelFrameSDIsec' -and (Test-Size $Window 467 538 10 10)
}

# Предупреждение безопасности об открытии внешней обработки: высота 342 при 125%,
# ширина зависит от длины пути к файлу (1100-1500).
function Test-SecurityWarning($Window) {
    $Window.Class -eq 'V8TopLevelFrameSDIsec' -and
        [math]::Abs($Window.Height - 342 * $Scale) -le 10 * $Scale -and $Window.Width -ge 900 * $Scale
}

# Главное окно клиента загружено: большая рамка V8TopLevelFrameSDI с заголовком конфигурации.
# Окно «Загрузка конфигурационной информации...» того же класса, но маленькое.
function Test-MainWindow($Window) {
    $Window.Class -eq 'V8TopLevelFrameSDI' -and $Window.Title -ne '' -and $Window.Title -notlike 'Загрузка*' -and
        $Window.Width -ge 900 * $Scale -and $Window.Height -ge 500 * $Scale
}

function Test-WindowVisible($Window) {
    [RunOneC.Win32]::IsWindowVisible($Window.Handle)
}

# Щелчок в точке, отсчитанной от правого нижнего угла окна, — только если точка лежит в этом окне.
function Click-FromCorner($Window, [int]$FromRight, [int]$FromBottom) {
    [RunOneC.Win32]::SetForegroundWindow($Window.Handle) | Out-Null
    Start-Sleep -Milliseconds 400
    $point = New-Object RunOneC.Win32+POINT
    $point.X = $Window.Rect.Right - [int]($FromRight * $Scale)
    $point.Y = $Window.Rect.Bottom - [int]($FromBottom * $Scale)
    $rootUnderPoint = [RunOneC.Win32]::GetAncestor([RunOneC.Win32]::WindowFromPoint($point), $GA_ROOT)
    if ($rootUnderPoint -ne $Window.Handle) { return $false }
    [RunOneC.Win32]::SetCursorPos($point.X, $point.Y) | Out-Null
    Start-Sleep -Milliseconds 100
    [RunOneC.Win32]::mouse_event($MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    [RunOneC.Win32]::mouse_event($MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    -not (Test-WindowVisible $Window)
}

function Close-ErrorDialog($Window) {
    # Escape: безопасно для окна ошибки (отмена, а не подтверждение).
    [RunOneC.Win32]::SetForegroundWindow($Window.Handle) | Out-Null
    Start-Sleep -Milliseconds 400
    if ([RunOneC.Win32]::GetForegroundWindow() -eq $Window.Handle) {
        [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        Start-Sleep -Milliseconds 800
        if (-not (Test-WindowVisible $Window)) { return 'Escape' }
    }
    # Щелчок по OK: кнопка в правом нижнем углу окна.
    if (Click-FromCorner $Window 55 65) { return 'OK' }
    $null
}

#endregion

$db = Get-TestBase $Base
$platform = Resolve-Platform $db
$arguments = "ENTERPRISE /F `"$($db.path)`" /DisableStartupMessages"
if ($db.user) { $arguments += " /N `"$($db.user)`"" }
if ($db.password) { $arguments += " /P `"$($db.password)`"" }
if ($URL) { $arguments += " /URL `"$URL`"" }
if ($OpenReport) {
    $erf = Join-Path $ProjectRoot 'build\DevToolsEnterprise.erf'
    $launcher = Join-Path $ProjectRoot 'build\launcher\DevToolsLauncher.epf'
    foreach ($file in $erf, $launcher) {
        if (-not (Test-Path $file)) { throw "Нет файла $file - сначала соберите: scripts\build.bat" }
    }
    $arguments += " /Execute `"$launcher`" /C `"$erf`""
}
if ($Extra) { $arguments += " $Extra" }

Write-Host "Платформа: $platform"
Write-Host "База: $($db.id) - $($db.path)$(if ($URL) { ", ссылка: $URL" })"
$started = Get-Date
$process = Start-Process -FilePath $platform -ArgumentList $arguments -PassThru
Write-Host "Клиент запущен, PID $($process.Id). Слежу за служебными окнами до $WatchSeconds с..."

# Окна клиента принадлежат не процессу, который вернул Start-Process, а 1cv8, запущенным после старта.
$quietSince = $null
$handled = @{}
$warningAccepted = $false
while (((Get-Date) - $started).TotalSeconds -lt $WatchSeconds) {
    Start-Sleep -Seconds 2
    $ids = @(Get-Process 1cv8, 1cv8c -ErrorAction SilentlyContinue |
        Where-Object { $_.StartTime -ge $started.AddSeconds(-2) } | ForEach-Object Id)
    if (-not $ids) { $process.Refresh(); if ($process.HasExited) { Write-Host 'Клиент завершился.'; break }; continue }

    $windows = @(Get-ProcessWindows $ids)
    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds)
    $acted = $false
    foreach ($window in $windows) {
        if ($handled.ContainsKey($window.Handle)) { continue }
        if (Test-ErrorDialog $window) {
            $how = Close-ErrorDialog $window
            if ($how) { Write-Host "[$elapsed с] Окно ошибки CRM закрыто ($how)." }
            else { Write-Host "[$elapsed с] Окно похожего размера не удалось закрыть - оставлено пользователю." }
        } elseif ($OpenReport -and (Test-ItsDialog $window)) {
            # Крестик в заголовке: 19 px от правого края, 519 px от нижнего (467x538 при 125%).
            if (Click-FromCorner $window 19 519) { Write-Host "[$elapsed с] Окно Интернет-поддержки закрыто." }
            else { Write-Host "[$elapsed с] Окно Интернет-поддержки не удалось закрыть." }
        } elseif ($OpenReport -and -not $warningAccepted -and (Test-SecurityWarning $window)) {
            # «Да» — левая из двух кнопок справа внизу: 168 px от правого, 34 px от нижнего края.
            if (Click-FromCorner $window 168 34) { $warningAccepted = $true; Write-Host "[$elapsed с] Открытие служебной обработки подтверждено." }
            else { Write-Host "[$elapsed с] Предупреждение безопасности оставлено пользователю." }
        } else { continue }
        $handled[$window.Handle] = $true
        $acted = $true
    }
    if ($acted) { $quietSince = $null; continue }

    # Главное окно загрузилось и 15 секунд нет новых служебных окон — следить дальше незачем.
    $mainWindow = $windows | Where-Object { Test-MainWindow $_ } | Select-Object -First 1
    if ($mainWindow -and (-not $OpenReport -or $warningAccepted)) {
        if (-not $quietSince) { $quietSince = Get-Date }
        if (((Get-Date) - $quietSince).TotalSeconds -ge 15) { Write-Host "Клиент готов: $($mainWindow.Title), PID $($ids -join ',')"; break }
    }
}
if (((Get-Date) - $started).TotalSeconds -ge $WatchSeconds) {
    Write-Host "Время ожидания ($WatchSeconds с) вышло; оставшиеся окна клиента - пользователю."
    if ($OpenReport -and -not $warningAccepted) { Write-Host 'Предупреждение безопасности не было подтверждено: отчёт мог не открыться.' }
}
