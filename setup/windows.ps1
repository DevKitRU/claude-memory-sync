#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Memory Sync — Windows setup.

.DESCRIPTION
    Превращает локальную папку памяти Claude в Junction на git-репо с твоей памятью.
    Идемпотентен: повторный запуск не ломает.

    Использование:
        cd E:\projects\claude-memory-sync    (или где клонирован этот кит)
        .\setup\windows.ps1

    Что делает:
    1. Находит активную папку памяти Claude (discovery — не хардкод).
    2. Бэкапит её в %USERPROFILE%\claude-memory-backup-<timestamp>.
    3. Мержит уникальные/новые файлы в git-репо.
    4. Заменяет папку Junction'ом на git-репо.
    5. Настраивает Task Scheduler для auto-pull каждые 5 мин.
    6. Тестирует запись через Junction.

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

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $env:USERPROFILE "claude-memory-backup-$Timestamp"

# ——— Discovery активной папки памяти Claude
# Claude Code создаёт %USERPROFILE%\.claude\projects\<encoded-path>\memory под каждую
# рабочую директорию. Имя папки генерируется из абсолютного пути. Мы находим её
# через перебор, а не хардкодим.
function Find-ClaudeMemory {
    $projectsDir = Join-Path $env:USERPROFILE ".claude\projects"

    if (-not (Test-Path $projectsDir)) {
        Write-Err "Папка проектов Claude не найдена: $projectsDir"
        Write-Err ""
        Write-Err "Это значит что Claude Code ещё не запускался на этой машине."
        Write-Err "Запусти Claude Code хотя бы раз:"
        Write-Err "  cd <куда будешь работать с памятью>"
        Write-Err "  claude"
        Write-Err "Потом запусти этот скрипт снова."
        exit 1
    }

    $candidates = @(Get-ChildItem $projectsDir -Directory -ErrorAction SilentlyContinue)

    if ($candidates.Count -eq 0) {
        Write-Err "В $projectsDir нет ни одного проекта Claude."
        Write-Err "Запусти Claude Code хотя бы раз, потом этот скрипт снова."
        exit 1
    }

    if ($candidates.Count -eq 1) {
        return (Join-Path $candidates[0].FullName "memory")
    }

    # Несколько — спрашиваем
    Write-Host ""
    Write-Host "Claude Code запускался из нескольких директорий." -ForegroundColor Yellow
    Write-Host "Выбери ту из которой хочешь синхронизировать память:" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $name = $candidates[$i].Name
        $decoded = $name -replace '^-', '' -replace '-', '\'
        Write-Host ("  {0}) {1}" -f ($i + 1), $name)
        Write-Host ("       = {0}" -f $decoded) -ForegroundColor DarkGray
    }
    Write-Host ""
    $choice = Read-Host "Номер (1-$($candidates.Count))"

    $choiceInt = 0
    if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $candidates.Count) {
        Write-Err "Неверный выбор: $choice"
        exit 1
    }

    return (Join-Path $candidates[$choiceInt - 1].FullName "memory")
}

Write-Info "Windows setup для Claude Memory Sync"
Write-Info "Репо-кит: $RepoDir"
Write-Info "Git-память: $GitMemory"

if (-not (Test-Path $GitMemory)) {
    Write-Err "Папки $GitMemory не существует."
    Write-Err "Попробуй: git clone https://github.com/DevKitRU/claude-memory-sync.git"
    exit 1
}

$ClaudeMemory = Find-ClaudeMemory
Write-Info "Claude-память: $ClaudeMemory"
Write-Host ""

# ——— Шаг 0: уже Junction в правильное место?
$JunctionReady = $false
if (Test-Path $ClaudeMemory) {
    $item = Get-Item $ClaudeMemory -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        if ($item.Target -eq $GitMemory) {
            Write-Ok "Junction уже настроен: $ClaudeMemory -> $GitMemory"
            Write-Info "Пропускаю шаги 1-4, проверю скил и Task Scheduler..."
            $JunctionReady = $true
        } else {
            Write-WarnMsg "Junction ведёт в другое место: $($item.Target)"
            Write-WarnMsg "Пересоздаю..."
            Remove-Item $ClaudeMemory -Force
        }
    }
}

if (-not $JunctionReady) {

    # ——— Шаг 1: бэкап
    Write-Info "Шаг 1/7: бэкап текущей папки памяти"
    if (Test-Path $ClaudeMemory) {
        Copy-Item -Path $ClaudeMemory -Destination $BackupDir -Recurse -Force
        Write-Ok "Бэкап: $BackupDir"
    } else {
        Write-Info "Папки памяти Claude ещё нет — бэкап не нужен"
        $parent = Split-Path $ClaudeMemory -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    # ——— Шаг 2: мерж
    Write-Info "Шаг 2/7: мерж уникальных/новых файлов"
    $mergedNew = 0
    $mergedOverwrite = 0
    $overwrittenFiles = @()
    if (Test-Path $ClaudeMemory) {
        Get-ChildItem $ClaudeMemory -File | ForEach-Object {
            $target = Join-Path $GitMemory $_.Name
            if (-not (Test-Path $target)) {
                Copy-Item $_.FullName $target
                Write-Host "  + $($_.Name) (новый)"
                $script:mergedNew++
            } elseif ($_.LastWriteTime -gt (Get-Item $target).LastWriteTime) {
                Copy-Item $_.FullName $target -Force
                Write-Host "  ^ $($_.Name) (локальная версия свежее)"
                $script:overwrittenFiles += $_.Name
                $script:mergedOverwrite++
            }
        }
    }
    if ($mergedNew -eq 0 -and $mergedOverwrite -eq 0) {
        Write-Ok "Все файлы уже в git-репо"
    } else {
        Write-Ok "Новых: $mergedNew, перезаписано: $mergedOverwrite"
        if ($mergedOverwrite -gt 0) {
            Write-WarnMsg "Перезаписаны версиями из локальной папки (новее по mtime):"
            foreach ($n in $overwrittenFiles) {
                Write-WarnMsg "  - $n"
            }
        }
    }

    # ——— Шаг 3: удалить и создать Junction
    Write-Info "Шаг 3/7: Junction"
    if (Test-Path $ClaudeMemory) {
        Remove-Item $ClaudeMemory -Recurse -Force
    }
    New-Item -ItemType Junction -Path $ClaudeMemory -Target $GitMemory | Out-Null
    Write-Ok "$ClaudeMemory -> $GitMemory"

    # ——— Шаг 4: тест записи
    Write-Info "Шаг 4/7: тест записи через Junction"
    $testFile = Join-Path $ClaudeMemory "_junction_test.tmp"
    "test $(Get-Date)" | Out-File $testFile -Encoding UTF8
    if (Test-Path (Join-Path $GitMemory "_junction_test.tmp")) {
        Write-Ok "Запись через Junction работает"
        Remove-Item $testFile
    } else {
        Write-Err "Junction не работает"
        exit 1
    }

}   # end of JunctionReady block

# ——— Шаг 5: скилы (идемпотентно — цикл по всем skills/*)
Write-Info "Шаг 5/7: установка скилов"
$SkillsSrc = Join-Path $RepoDir "skills"
$SkillsDst = Join-Path $env:USERPROFILE ".claude\skills"

if (Test-Path $SkillsSrc) {
    if (-not (Test-Path $SkillsDst)) {
        New-Item -ItemType Directory -Path $SkillsDst -Force | Out-Null
    }
    $installed = 0
    foreach ($skillDir in (Get-ChildItem $SkillsSrc -Directory)) {
        $dst = Join-Path $SkillsDst $skillDir.Name
        if (Test-Path $dst) {
            $dstItem = Get-Item $dst -Force
            if ($dstItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                Remove-Item $dst -Force
            } else {
                Move-Item $dst "$dst.backup-$Timestamp"
            }
        }
        New-Item -ItemType Junction -Path $dst -Target $skillDir.FullName | Out-Null
        Write-Host "  + /$($skillDir.Name)"
        $installed++
    }
    Write-Ok "Скилов установлено: $installed"
} else {
    Write-WarnMsg "Папка $SkillsSrc не найдена — скилы не установлены"
}

# ——— Шаг 6: Task Scheduler (идемпотентно)
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

Write-Ok "Task: $TaskName"
Write-Ok "Лог: $LogPath"

# ——— Шаг 7: итог
Write-Info "Шаг 7/7: готово"
Write-Host ""
Write-Ok "Всё настроено."
Write-Host "  - Claude пишет память напрямую в $GitMemory"
Write-Host "  - Task Scheduler тянет свежее с GitHub каждые 5 мин"
Write-Host "  - Сохранить: cd $RepoDir ; git add -A ; git commit -m '...' ; git push"
if (-not $JunctionReady) {
    Write-Host "  - Бэкап: $BackupDir (удали через пару дней когда убедишься что всё работает)"
}
Write-Host ""
Write-Info "Проверка: .\setup\health-check.ps1"
Write-Info "Откат:    .\setup\rollback.ps1"
