#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Memory Sync — Windows setup.

.DESCRIPTION
    Превращает локальную папку памяти Claude в Junction на git-репо claude-memory.
    Идемпотентен: повторный запуск не ломает.

    Использование:
        cd E:\projects\claude-memory    (или где клонирован репо)
        .\setup\windows.ps1

    Что делает:
    1. Проверяет что git-репо на месте
    2. Находит папку памяти Claude (%USERPROFILE%\.claude\projects\e--projects\memory)
    3. Бэкапит её в %USERPROFILE%\claude-memory-backup-<timestamp>
    4. Мержит уникальные файлы в git-репо
    5. Заменяет папку Junction'ом на git-репо
    6. Настраивает Task Scheduler для auto-pull каждые 5 мин
    7. Тестирует запись через Junction

    Junction не требует прав администратора (в отличие от Symbolic Link).
#>

$ErrorActionPreference = "Stop"

function Write-Info    { param($m) Write-Host "i $m" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "+ $m" -ForegroundColor Green }
function Write-WarnMsg { param($m) Write-Host "! $m" -ForegroundColor Yellow }
function Write-Err     { param($m) Write-Host "x $m" -ForegroundColor Red }

# ——— Пути
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir   = Split-Path -Parent $ScriptDir
$GitMemory = Join-Path $RepoDir "memory"

$ClaudeMemory = Join-Path $env:USERPROFILE ".claude\projects\e--projects\memory"
$Timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir    = Join-Path $env:USERPROFILE "claude-memory-backup-$Timestamp"

Write-Info "Windows setup для Claude Memory Sync"
Write-Info "Репо: $RepoDir"
Write-Info "Git-память: $GitMemory"
Write-Info "Claude-память: $ClaudeMemory"
Write-Host ""

if (-not (Test-Path $GitMemory)) {
    Write-Err "Git-репо не найден: $GitMemory"
    Write-Err "Сначала: git clone https://github.com/DevKitRU/claude-memory-sync.git $RepoDir"
    exit 1
}

# ——— Шаг 0: уже Junction?
if (Test-Path $ClaudeMemory) {
    $item = Get-Item $ClaudeMemory -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        if ($item.Target -eq $GitMemory) {
            Write-Ok "Junction уже настроен: $ClaudeMemory -> $GitMemory"
            exit 0
        } else {
            Write-WarnMsg "Junction ведёт в другое место: $($item.Target)"
            Write-WarnMsg "Пересоздаю..."
            Remove-Item $ClaudeMemory -Force
        }
    }
}

# ——— Шаг 1: бэкап
Write-Info "Шаг 1/6: бэкап"
if (Test-Path $ClaudeMemory) {
    Copy-Item -Path $ClaudeMemory -Destination $BackupDir -Recurse -Force
    Write-Ok "Бэкап: $BackupDir"
} else {
    Write-Info "Папки памяти Claude не существует"
    $parent = Split-Path $ClaudeMemory -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
}

# ——— Шаг 2: мерж
Write-Info "Шаг 2/6: мерж"
$merged = 0
if (Test-Path $ClaudeMemory) {
    Get-ChildItem $ClaudeMemory -File | ForEach-Object {
        $target = Join-Path $GitMemory $_.Name
        if (-not (Test-Path $target)) {
            Copy-Item $_.FullName $target
            Write-Host "  + $($_.Name)"
            $merged++
        } elseif ($_.LastWriteTime -gt (Get-Item $target).LastWriteTime) {
            Copy-Item $_.FullName $target -Force
            Write-Host "  > $($_.Name)"
            $merged++
        }
    }
}
Write-Ok "Смержено: $merged файлов"

# ——— Шаг 3: удалить и создать Junction
Write-Info "Шаг 3/6: Junction"
if (Test-Path $ClaudeMemory) {
    Remove-Item $ClaudeMemory -Recurse -Force
}
New-Item -ItemType Junction -Path $ClaudeMemory -Target $GitMemory | Out-Null
Write-Ok "$ClaudeMemory -> $GitMemory"

# ——— Шаг 4: тест записи
Write-Info "Шаг 4/6: тест записи"
$testFile = Join-Path $ClaudeMemory "_junction_test.tmp"
"test $(Get-Date)" | Out-File $testFile -Encoding UTF8
if (Test-Path (Join-Path $GitMemory "_junction_test.tmp")) {
    Write-Ok "Работает"
    Remove-Item $testFile
} else {
    Write-Err "Junction не работает"
    exit 1
}

# ——— Шаг 5: скил
Write-Info "Шаг 5/7: установка скила /setup-memory-sync"
$SkillSrc = Join-Path $RepoDir "skills\setup-memory-sync"
$SkillDst = Join-Path $env:USERPROFILE ".claude\skills\setup-memory-sync"
if (Test-Path $SkillSrc) {
    $skillsParent = Join-Path $env:USERPROFILE ".claude\skills"
    if (-not (Test-Path $skillsParent)) { New-Item -ItemType Directory -Path $skillsParent -Force | Out-Null }
    if (Test-Path $SkillDst) {
        $skItem = Get-Item $SkillDst -Force
        if ($skItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Remove-Item $SkillDst -Force
        } else {
            Move-Item $SkillDst "$SkillDst.backup-$Timestamp"
        }
    }
    New-Item -ItemType Junction -Path $SkillDst -Target $SkillSrc | Out-Null
    Write-Ok "Скил: $SkillDst -> $SkillSrc"
}

# ——— Шаг 6: Task Scheduler
Write-Info "Шаг 6/7: Task Scheduler (auto-pull каждые 5 мин)"
$TaskName = "ClaudeMemoryAutoPull"
$LogPath  = Join-Path $env:LOCALAPPDATA "claude-memory-autopull.log"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$psArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"cd '$RepoDir'; git pull --quiet *>> '$LogPath'`""
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs

$startTime = (Get-Date).AddMinutes(1)
$trigger = New-ScheduledTaskTrigger -Once -At $startTime `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Auto-pull Claude памяти с GitHub каждые 5 мин" | Out-Null

Write-Ok "Task '$TaskName' создана (лог: $LogPath)"

# ——— Шаг 7: итог
Write-Info "Шаг 7/7: готово"
Write-Host ""
Write-Ok "Всё настроено."
Write-Host "  - Claude пишет память напрямую в $GitMemory"
Write-Host "  - Task Scheduler тянет свежее с GitHub каждые 5 мин"
Write-Host "  - Сохранить: cd $RepoDir ; git add -A ; git commit -m '...' ; git push"
Write-Host "  - Бэкап: $BackupDir"
Write-Host ""
Write-Info "Проверка: .\setup\health-check.ps1"
Write-Info "Откат:    .\setup\rollback.ps1"
