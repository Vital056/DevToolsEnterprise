<#
.SYNOPSIS
    Проверка вкладки «Выгрузка расширений»: сравнивает выгруженные .cfe с данными расширений базы.

.DESCRIPTION
    Подключается к тестовой базе через COM (V83.COMConnector), берёт двоичные данные каждого
    расширения (РасширенияКонфигурации.Получить() -> ПолучитьДанные()) и сравнивает хеш
    с файлом <Имя>.cfe в каталоге выгрузки.

.EXAMPLE
    powershell -NoProfile -File tools\compare-cfe.ps1 -OutDir C:\Temp\cfe -Base dogovor
#>
param(
    [Parameter(Mandatory)] [string]$OutDir,
    [string]$Base
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $ProjectRoot 'scripts\common.ps1')

# PowerShell не связывает члены COM-объектов 1С динамически: только через InvokeMember.
# Запятая перед вызовом не даёт PowerShell развернуть коллекции 1С.
function M($o, [string]$n, $a = @()) { , [System.__ComObject].InvokeMember($n, [Reflection.BindingFlags]::InvokeMethod, $null, $o, $a) }
function P($o, [string]$n) { [System.__ComObject].InvokeMember($n, [Reflection.BindingFlags]::GetProperty, $null, $o, $null) }

$db = Get-TestBase $Base
$connection = "File=`"$($db.path)`";Usr=`"$($db.user)`";"
if ($db.password) { $connection += "Pwd=`"$($db.password)`";" }
$c = (New-Object -ComObject V83.COMConnector).Connect($connection)

$list = M (P $c 'РасширенияКонфигурации') 'Получить'
$n = M $list 'Количество'
$diff = 0
for ($i = 0; $i -lt $n; $i++) {
    $e = M $list 'Получить' @($i)
    $name = P $e 'Имя'
    $tmp = (Join-Path $env:TEMP "compare-cfe-$i.cfe").ToString()
    M (M $e 'ПолучитьДанные') 'Записать' @($tmp) | Out-Null
    $file = Join-Path $OutDir "$name.cfe"
    $h1 = (Get-FileHash $tmp).Hash
    $h2 = if (Test-Path -LiteralPath $file) { (Get-FileHash -LiteralPath $file).Hash } else { '' }
    $state = if ($h1 -eq $h2) { 'совпадает' } elseif ($h2) { 'РАЗЛИЧИЕ' } else { 'НЕТ ФАЙЛА' }
    if ($h1 -ne $h2) { $diff++ }
    '{0}: {1}' -f $name, $state
    Remove-Item $tmp
}
"Расширений в базе: $n, расхождений: $diff"
if ($diff) { exit 1 }
