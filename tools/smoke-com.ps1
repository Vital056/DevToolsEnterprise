<#
.SYNOPSIS
    Быстрая проверка собранного отчёта без интерфейса: вызывает его экспортные методы через COM.

.DESCRIPTION
    Подключается к тестовой базе (V83.COMConnector, внешнее соединение), создаёт объект
    отчёта из build\DevToolsEnterprise.erf и вызывает:
      - ОбъектыРасширений()            — объекты, которые меняют расширения базы;
      - ИзмененияОбъекта(<объект>)      — что расширения меняют в первом из них;
      - ПраваРолей(<объект>)            — матрица прав ролей сеанса на этот объект (и с отбором RLS);
      - ВывестиИзмененияВРасширениях / ВывестиПраваРолей — табличные документы вкладок;
      - РасширенияБазы() и ВывестиИзмененияРасширения(<первое расширение>) — отчёт по расширению.
    Проверяет код модуля объекта; формы и клиентский код проверяются только в клиенте
    (scripts\test.bat).

.EXAMPLE
    powershell -NoProfile -File tools\smoke-com.ps1 -Base zup
#>
param(
    [string]$Base,
    [string]$Object
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $ProjectRoot 'scripts\common.ps1')

function M($o, [string]$n, $a = @()) { , [System.__ComObject].InvokeMember($n, [Reflection.BindingFlags]::InvokeMethod, $null, $o, $a) }
function P($o, [string]$n) { [System.__ComObject].InvokeMember($n, [Reflection.BindingFlags]::GetProperty, $null, $o, $null) }
function SetP($o, [string]$n, $v) { [System.__ComObject].InvokeMember($n, [Reflection.BindingFlags]::SetProperty, $null, $o, @($v)) | Out-Null }

$erf = (Join-Path $ProjectRoot 'build\DevToolsEnterprise.erf').ToString()
if (-not (Test-Path $erf)) { throw "Нет $erf - сначала scripts\build.bat" }

$db = Get-TestBase $Base
$connection = "File=`"$($db.path)`";Usr=`"$($db.user)`";"
if ($db.password) { $connection += "Pwd=`"$($db.password)`";" }
Write-Host "База: $($db.id) - $($db.path)"
$started = Get-Date
$c = (New-Object -ComObject V83.COMConnector).Connect($connection)
Write-Host ("Подключение: {0:N0} с" -f ((Get-Date) - $started).TotalSeconds)

# Без описания защиты платформа по внешнему соединению выбрасывает предупреждение об опасных действиях.
$protection = M $c 'NewObject' @('ОписаниеЗащитыОтОпасныхДействий')
SetP $protection 'ПредупреждатьОбОпасныхДействиях' $false
$report = M (P $c 'ВнешниеОтчеты') 'Создать' @($erf, $false, $protection)

$failed = 0
function Step([string]$Name, [scriptblock]$Body) {
    $t = Get-Date
    try {
        $result = & $Body
        Write-Host ("OK    {0}: {1} ({2:N1} с)" -f $Name, $result, ((Get-Date) - $t).TotalSeconds)
    } catch {
        $script:failed++
        $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-Host "FAIL  ${Name}: $msg"
    }
}

$objects = $null
Step 'ОбъектыРасширений' {
    $script:objects = M $report 'ОбъектыРасширений'
    "$(M $script:objects 'Количество') объектов"
}
if (-not $Object -and $objects -and (M $objects 'Количество') -gt 0) {
    $first = M $objects 'Получить' @(0)
    $Object = if ($first -is [string]) { $first } else { "$(P $first 'Значение')" }
}
if (-not $Object) { $Object = 'Справочник.Пользователи' }
Write-Host "Объект для проверки: $Object"

Step 'ИзмененияОбъекта' { "$(M (M $report 'ИзмененияОбъекта' @($Object, $true)) 'Количество') строк" }
Step 'ИзмененияОбъекта (все объекты)' { "$(M (M $report 'ИзмененияОбъекта' @('', $true)) 'Количество') строк" }
Step 'ПраваРолей' { "$(M (M $report 'ПраваРолей' @($Object, $true, $true)) 'Количество') строк" }
Step 'ОбъектыМетаданных' { "$(M (M $report 'ОбъектыМетаданных') 'Количество') строк" }
Step 'ВывестиИзмененияВРасширениях' {
    $doc = M $c 'NewObject' @('ТабличныйДокумент')
    M $report 'ВывестиИзмененияВРасширениях' @($doc, $Object, $true) | Out-Null
    "$(P $doc 'ВысотаТаблицы') строк макета"
}
Step 'ВывестиПраваРолей' {
    $doc = M $c 'NewObject' @('ТабличныйДокумент')
    M $report 'ВывестиПраваРолей' @($doc, $Object, $true, $true) | Out-Null
    "$(P $doc 'ВысотаТаблицы') строк макета"
}
Step 'ВывестиПраваРолей (только роли с RLS)' {
    $doc = M $c 'NewObject' @('ТабличныйДокумент')
    M $report 'ВывестиПраваРолей' @($doc, $Object, $true, $false, $true) | Out-Null
    "$(P $doc 'ВысотаТаблицы') строк макета"
}

$extension = $null
Step 'РасширенияБазы' {
    $list = M $report 'РасширенияБазы'
    if ((M $list 'Количество') -gt 0) { $script:extension = "$(P (M $list 'Получить' @(0)) 'Значение')" }
    "$(M $list 'Количество') расширений"
}
if ($extension) {
    foreach ($onlyChanges in $true, $false) {
        Step "ВывестиИзмененияРасширения (без заимствованных: $onlyChanges)" {
            $doc = M $c 'NewObject' @('ТабличныйДокумент')
            M $report 'ВывестиИзмененияРасширения' @($doc, $extension, $onlyChanges) | Out-Null
            "$(P $doc 'ВысотаТаблицы') строк макета"
        }
    }
}

"Ошибок: $failed"
if ($failed) { exit 1 }
