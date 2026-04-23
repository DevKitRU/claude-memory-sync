#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Memory Sync — rollback для Windows.

.DESCRIPTION
    Восстанавливает папку памяти из последнего бэкапа.
    Использовать если скрипт установки что-то сломал.

    Использование:
        .\setup\rollback.ps1                    # последний бэкап автоматом
        .\setup\rollback.ps1 -Backup C:\path    # конкретный бэкап
#>

param(
    [string]$Backup
)

$ErrorActionPreference = "Stop"

function Write-Info    { param($m) Write-Host "i $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "+ $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host "x $m" -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir   = Split-Path -Parent $ScriptDir
$GitMemory = Join-Path $RepoDir "memory"

# ——— Discovery: ищем Junction установленный нашим скриптом
function Find-InstalledJunction {
    $projectsDir = Join-Path $env:USERPROFILE ".claude\projects"
    if (-not (Test-Path $projectsDir)) { return $null }
    foreach ($d in (Get-ChildItem $projectsDir -Directory -ErrorAction SilentlyContinue)) {
        $mem = Join-Path $d.FullName "memory"
        if (Test-Path $mem) {
            $item = Get-Item $mem -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and ($item.Target -eq $GitMemory)) {
                return $mem
            }
        }
    }
    return $null
}

$ClaudeMemory = Find-InstalledJunction
if (-not $ClaudeMemory) {
    Write-WarnMsg "Не нашёл установленный Junction — восстановлю в папку с одним проектом Claude."
    $projectsDir = Join-Path $env:USERPROFILE ".claude\projects"
    $dirs = @(Get-ChildItem $projectsDir -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 1) {
        $ClaudeMemory = Join-Path $dirs[0].FullName "memory"
        Write-Info "Путь восстановления: $ClaudeMemory"
    } else {
        Write-Err "Не могу определить куда восстанавливать: проектов $($dirs.Count)."
        Write-Err "Восстанови вручную из $Backup в нужную папку."
        exit 1
    }
}

# ——— Поиск бэкапа
if (-not $Backup) {
    $backups = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter "claude-memory-backup-*" -ErrorAction SilentlyContinue `
        | Sort-Object LastWriteTime -Descending
    if (-not $backups) {
        Write-Err "Бэкапы не найдены в $env:USERPROFILE\claude-memory-backup-*"
        Write-Err "Укажи путь явно: .\rollback.ps1 -Backup C:\path"
        exit 1
    }
    $Backup = $backups[0].FullName
    Write-Info "Последний бэкап: $Backup"
}

if (-not (Test-Path $Backup)) {
    Write-Err "Бэкап не найден: $Backup"
    exit 1
}

Write-Host ""
Write-WarnMsg "Rollback восстановит папку памяти Claude из бэкапа."
Write-WarnMsg "Текущее состояние $ClaudeMemory будет УДАЛЕНО."
Write-Host ""
$confirm = Read-Host "Продолжить? (yes/no)"
if ($confirm -ne "yes") {
    Write-Info "Отмена"
    exit 0
}

# ——— Удалить текущее (Junction или папка)
if (Test-Path $ClaudeMemory) {
    Remove-Item $ClaudeMemory -Recurse -Force
    Write-Ok "Удалено: $ClaudeMemory"
}

# Убедиться что родительская директория существует
$parent = Split-Path $ClaudeMemory -Parent
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

# ——— Восстановить
Copy-Item -Path $Backup -Destination $ClaudeMemory -Recurse -Force
Write-Ok "Восстановлено из: $Backup"

# ——— Остановить auto-pull task
$task = Get-ScheduledTask -TaskName "ClaudeMemoryAutoPull" -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName "ClaudeMemoryAutoPull" -Confirm:$false
    Write-Ok "Auto-pull task удалён"
}

Write-Host ""
Write-Ok "Откат завершён"
Write-Info "Теперь можно снова запустить .\setup\windows.ps1 когда будешь готов"
