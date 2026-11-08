<#
.SYNOPSIS
    Сборка build\DevToolsEnterprise.erf из src и служебной обработки build\launcher\DevToolsLauncher.epf.

.DESCRIPTION
    Сборка идёт через Конфигуратор (/LoadExternalDataProcessorOrReportFromFiles) на пустой
    файловой базе build\stub-ib: отчёт не ссылается на объекты конфигурации, поэтому рабочая
    база для сборки не нужна и тестовые базы соседних проектов не блокируются.
    Пустая база создаётся при первом запуске.

.PARAMETER Only
    report - только отчёт, launcher - только служебная обработка; по умолчанию оба.
#>
param(
    [ValidateSet('all', 'report', 'launcher')]
    [string]$Only = 'all'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

$build = Join-Path $ProjectRoot 'build'
$stub = Join-Path $build 'stub-ib'
$log = Join-Path $build 'build.log'
New-Item -ItemType Directory -Force $build, (Join-Path $build 'launcher') | Out-Null

$platform = Resolve-Platform $null
Write-Host "Платформа: $platform"

function Invoke-Designer([string]$Arguments) {
    if (Test-Path $log) { Remove-Item $log }
    $p = Start-Process -FilePath $platform -ArgumentList "$Arguments /DisableStartupDialogs /DisableStartupMessages /Out `"$log`"" -Wait -PassThru -WindowStyle Hidden
    $text = if (Test-Path $log) { (Get-Content $log -Raw -Encoding Default) } else { '' }
    if ($p.ExitCode -ne 0) { throw "Конфигуратор завершился с кодом $($p.ExitCode):`n$text" }
    if ($text -and $text.Trim()) { Write-Host $text.Trim() }
}

if (-not (Test-Path (Join-Path $stub '1Cv8.1CD'))) {
    Write-Host "Создаю пустую базу для сборки: $stub"
    Invoke-Designer "CREATEINFOBASE File=`"$stub`""
}

$targets = @()
if ($Only -in 'all', 'report') {
    $targets += , @((Join-Path $ProjectRoot 'src\DevToolsEnterprise.xml'), (Join-Path $build 'DevToolsEnterprise.erf'))
}
if ($Only -in 'all', 'launcher') {
    $targets += , @((Join-Path $ProjectRoot 'tools\launcher\DevToolsLauncher.xml'), (Join-Path $build 'launcher\DevToolsLauncher.epf'))
}

foreach ($t in $targets) {
    $source, $out = $t
    if (Test-Path $out) { Remove-Item $out }
    Invoke-Designer "DESIGNER /F `"$stub`" /LoadExternalDataProcessorOrReportFromFiles `"$source`" `"$out`""
    if (-not (Test-Path $out)) { throw "Файл $out не создан, см. $log" }
    Write-Host ("Собрано: {0} ({1:N0} байт)" -f $out, (Get-Item $out).Length)
}
