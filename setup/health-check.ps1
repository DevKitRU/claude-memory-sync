#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Memory Sync — health check для Windows.

.DESCRIPTION
    Проверяет:
    1. Junction на месте и указывает на git-репо
    2. Git-репо чистый или с известными uncommitted изменениями
    3. Auto-pull task работает (когда последний раз запускался)
    4. Количество файлов совпадает с локальным и git
#>

function Write-Info    { param($m) Write-Host "i $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "+ $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host "x $m" -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir   = Split-Path -Parent $ScriptDir
$GitMemory = Join-Path $RepoDir "memory"
$ClaudeMemory = Join-Path $env:USERPROFILE ".claude\projects\e--projects\memory"
$LogPath   = Join-Path $env:LOCALAPPDATA "claude-memory-autopull.log"

$Issues = 0

Write-Host "========== Claude Memory Sync Health Check =========="
Write-Host ""

# 1. Junction
Write-Info "1) Проверка Junction"
if (-not (Test-Path $ClaudeMemory)) {
    Write-Err "   Папка памяти не существует: $ClaudeMemory"
    $Issues++
} else {
    $item = Get-Item $ClaudeMemory -Force
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        Write-Err "   Это обычная папка, не Junction: $ClaudeMemory"
        Write-Err "   Запусти .\setup\windows.ps1"
        $Issues++
    } elseif ($item.Target -ne $GitMemory) {
        Write-Err "   Junction ведёт не туда: $($item.Target)"
        Write-Err "   Ожидали: $GitMemory"
        $Issues++
    } else {
        Write-Ok "   Junction корректный: $($item.Target)"
    }
}

# 2. Git статус
Write-Info "2) Git статус"
Push-Location $RepoDir
$dirty = (git status --porcelain) | Measure-Object -Line
if ($dirty.Lines -eq 0) {
    Write-Ok "   Чисто"
} else {
    Write-WarnMsg "   $($dirty.Lines) несохранённых изменений:"
    git status --short | Select-Object -First 5 | ForEach-Object { Write-Host "     $_" }
    Write-WarnMsg "   Сохранить: cd $RepoDir ; git add -A ; git commit -m '...' ; git push"
}

# 3. Синхронизация
Write-Info "3) Синхронизация с GitHub"
try {
    git fetch --quiet 2>$null
    $ahead  = (git rev-list --count '@{u}..HEAD' 2>$null)
    $behind = (git rev-list --count 'HEAD..@{u}' 2>$null)
    if ($ahead -eq "0" -and $behind -eq "0") {
        Write-Ok "   Up to date с origin/main"
    } elseif ($ahead -ne "0" -and $behind -eq "0") {
        Write-WarnMsg "   Впереди origin на $ahead коммитов (не запушено)"
    } elseif ($ahead -eq "0" -and $behind -ne "0") {
        Write-WarnMsg "   Отстаёт от origin на $behind коммитов (git pull)"
    } else {
        Write-WarnMsg "   Расходится: впереди $ahead, позади $behind"
    }
} catch {
    Write-WarnMsg "   Не удалось проверить (нет интернета или прокси?)"
}
Pop-Location

# 4. Auto-pull
Write-Info "4) Auto-pull"
$task = Get-ScheduledTask -TaskName "ClaudeMemoryAutoPull" -ErrorAction SilentlyContinue
if (-not $task) {
    # Старое имя для обратной совместимости
    $task = Get-ScheduledTask -TaskName "ClaudeMemoryAutoSync" -ErrorAction SilentlyContinue
}
if (-not $task) {
    Write-WarnMsg "   Task Scheduler задача не найдена. Запусти .\setup\windows.ps1"
} else {
    $info = Get-ScheduledTaskInfo $task.TaskName
    $lastRun = $info.LastRunTime
    $diff = (Get-Date) - $lastRun
    if ($diff.TotalMinutes -lt 10) {
        Write-Ok "   Последний запуск: $([int]$diff.TotalMinutes) мин назад"
    } elseif ($diff.TotalHours -lt 1) {
        Write-WarnMsg "   Последний запуск: $([int]$diff.TotalMinutes) мин назад (ожидали <10)"
    } else {
        Write-Err "   Последний запуск: $([int]$diff.TotalHours) часов назад — не работает"
        $Issues++
    }
    if ($info.LastTaskResult -ne 0) {
        Write-WarnMsg "   Последний результат: $($info.LastTaskResult) (не 0)"
    }
}

# 5. Файлы
Write-Info "5) Файлы"
$filesInGit   = (Get-ChildItem $GitMemory -File).Count
$filesViaLink = (Get-ChildItem $ClaudeMemory -File -ErrorAction SilentlyContinue).Count
if ($filesInGit -eq $filesViaLink) {
    Write-Ok "   $filesInGit файлов (git и Junction совпадают)"
} else {
    Write-Err "   git=$filesInGit, через Junction=$filesViaLink — РАСХОЖДЕНИЕ"
    $Issues++
}

Write-Host ""
if ($Issues -eq 0) {
    Write-Host "========== Всё ок ==========" -ForegroundColor Green
    exit 0
} else {
    Write-Host "========== Проблем: $Issues ==========" -ForegroundColor Red
    exit 1
}
