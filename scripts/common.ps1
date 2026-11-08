# Общие функции скриптов: реестр тестовых баз (.v8-project.json) и поиск платформы.
# Подключается через dot-source; ожидает переменную $ProjectRoot.

function Read-ProjectRegistry {
    $path = Join-Path $ProjectRoot '.v8-project.json'
    if (-not (Test-Path $path)) {
        throw "Нет реестра баз $path - скопируйте .v8-project.json.example в .v8-project.json и укажите базы"
    }
    Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# База по id или алиасу; без имени — база default.
function Get-TestBase([string]$Name) {
    $registry = Read-ProjectRegistry
    if (-not $Name) { $Name = $registry.default }
    $db = $registry.databases | Where-Object { $_.id -eq $Name -or @($_.aliases) -contains $Name } | Select-Object -First 1
    if (-not $db) {
        $known = ($registry.databases | ForEach-Object { $_.id }) -join ', '
        throw "База '$Name' не найдена в .v8-project.json (есть: $known)"
    }
    if ($db.type -ne 'file') { throw "База '$($db.id)': поддерживаются только файловые базы" }
    if (-not $db.v8path -and $registry.v8path) { $db | Add-Member v8path $registry.v8path -Force }
    $db
}

# 1cv8.exe: v8path базы или реестра, иначе самая новая установленная платформа.
function Resolve-Platform($Db) {
    $v8path = if ($Db -and $Db.v8path) { $Db.v8path } else { (Read-ProjectRegistry).v8path }
    if ($v8path) {
        $exe = if ($v8path -like '*.exe') { $v8path } else { Join-Path $v8path '1cv8.exe' }
        if (Test-Path $exe) { return $exe }
        Write-Warning "Платформа $exe не найдена, беру самую новую установленную"
    }
    $newest = Get-ChildItem "$env:ProgramFiles\1cv8\*\bin\1cv8.exe", "${env:ProgramFiles(x86)}\1cv8\*\bin\1cv8.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
    if (-not $newest) { throw 'Не найдена установленная платформа 1С' }
    $newest.FullName
}
