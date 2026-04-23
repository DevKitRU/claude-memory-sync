#!/usr/bin/env bash
# Claude Memory Sync — macOS setup
#
# Превращает локальную папку памяти Claude в симлинк на git-репо с твоей памятью.
# Идемпотентен: повторный запуск не ломает.
#
# Использование:
#   cd ~/Documents/claude-memory-sync    (или где клонирован этот кит)
#   ./setup/mac.sh

set -euo pipefail

# ——— Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

# ——— Пути
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_MEMORY="$REPO_DIR/memory"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/claude-memory-backup-$TIMESTAMP"

# ——— Discovery активной папки памяти Claude
# Claude Code создаёт ~/.claude/projects/<encoded-path>/memory под каждую рабочую
# директорию. Имя папки = абсолютный путь с '/' заменёнными на '-'. Мы находим её,
# а не хардкодим по имени пользователя.
discover_claude_memory() {
    local projects_dir="$HOME/.claude/projects"

    if [[ ! -d "$projects_dir" ]]; then
        err "Папка проектов Claude не найдена: $projects_dir"
        err ""
        err "Это значит что Claude Code ещё не запускался на этой машине."
        err "Запусти Claude Code хотя бы раз:"
        err "  cd <куда будешь работать с памятью>"
        err "  claude"
        err "Потом запусти этот скрипт снова."
        exit 1
    fi

    local candidates=()
    while IFS= read -r -d '' dir; do
        candidates+=("$dir")
    done < <(find "$projects_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    if [[ ${#candidates[@]} -eq 0 ]]; then
        err "В $projects_dir нет ни одного проекта Claude."
        err "Запусти Claude Code хотя бы раз, потом этот скрипт снова."
        exit 1
    fi

    if [[ ${#candidates[@]} -eq 1 ]]; then
        echo "${candidates[0]}/memory"
        return 0
    fi

    # Несколько проектов — пусть пользователь выберет
    echo "" >&2
    echo "Claude Code запускался из нескольких директорий." >&2
    echo "Выбери ту из которой ты хочешь синхронизировать память:" >&2
    echo "" >&2
    local i=1
    for dir in "${candidates[@]}"; do
        local name
        name=$(basename "$dir")
        local decoded
        decoded=$(echo "$name" | sed 's|^-||; s|-|/|g')
        echo "  $i) $name" >&2
        echo "       = /$decoded" >&2
        i=$((i+1))
    done
    echo "" >&2
    printf "Номер (1-%d): " "${#candidates[@]}" >&2
    local choice
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#candidates[@]} ]]; then
        err "Неверный выбор: $choice"
        exit 1
    fi

    echo "${candidates[$((choice-1))]}/memory"
}

# ——— Проверки
info "macOS setup для Claude Memory Sync"
info "Репо-кит: $REPO_DIR"
info "Git-память: $GIT_MEMORY"

if [[ ! -d "$GIT_MEMORY" ]]; then
    err "Папки $GIT_MEMORY не существует."
    err "Похоже клонирован не полный репо. Попробуй:"
    err "  git clone https://github.com/DevKitRU/claude-memory-sync.git"
    exit 1
fi

CLAUDE_MEMORY="$(discover_claude_memory)"
info "Claude-память: $CLAUDE_MEMORY"
echo ""

# ——— Шаг 0: уже симлинк в правильное место?
SYMLINK_READY=0
if [[ -L "$CLAUDE_MEMORY" ]]; then
    CURRENT_TARGET=$(readlink "$CLAUDE_MEMORY")
    if [[ "$CURRENT_TARGET" == "$GIT_MEMORY" ]]; then
        ok "Симлинк уже настроен: $CLAUDE_MEMORY → $GIT_MEMORY"
        info "Пропускаю шаги 1-4, проверю скил и auto-pull..."
        SYMLINK_READY=1
    else
        warn "Симлинк есть, но ведёт в другое место: $CURRENT_TARGET"
        warn "Пересоздаю..."
        rm "$CLAUDE_MEMORY"
    fi
fi

if [[ $SYMLINK_READY -eq 0 ]]; then

# ——— Шаг 1: бэкап
info "Шаг 1/7: бэкап текущей папки памяти"
if [[ -d "$CLAUDE_MEMORY" ]]; then
    cp -a "$CLAUDE_MEMORY" "$BACKUP_DIR"
    ok "Бэкап: $BACKUP_DIR"
else
    info "Папки памяти Claude ещё нет — бэкап не нужен"
    mkdir -p "$(dirname "$CLAUDE_MEMORY")"
fi

# ——— Шаг 2: мерж уникальных и более свежих файлов
info "Шаг 2/7: мерж уникальных/новых файлов в git-репо"
MERGED_NEW=0
MERGED_OVERWRITE=0
OVERWRITTEN_FILES=()
if [[ -d "$CLAUDE_MEMORY" ]]; then
    while IFS= read -r -d '' file; do
        name=$(basename "$file")
        target="$GIT_MEMORY/$name"
        if [[ ! -e "$target" ]]; then
            cp "$file" "$target"
            echo "  + $name (новый, добавлен в git)"
            MERGED_NEW=$((MERGED_NEW + 1))
        elif [[ "$file" -nt "$target" ]]; then
            cp "$file" "$target"
            echo "  ↑ $name (локальная версия свежее, перезаписана в git)"
            OVERWRITTEN_FILES+=("$name")
            MERGED_OVERWRITE=$((MERGED_OVERWRITE + 1))
        fi
    done < <(find "$CLAUDE_MEMORY" -maxdepth 1 -type f -print0)
fi
if [[ $MERGED_NEW -eq 0 && $MERGED_OVERWRITE -eq 0 ]]; then
    ok "Все файлы уже в git-репо или актуальнее"
else
    ok "Новых: $MERGED_NEW, перезаписано: $MERGED_OVERWRITE"
    if [[ $MERGED_OVERWRITE -gt 0 ]]; then
        warn "Перезаписаны более новой локальной версией:"
        for n in "${OVERWRITTEN_FILES[@]}"; do
            warn "  - $n"
        done
        warn "Если локальный mtime был неправильный — проверь git log и откати если надо."
    fi
fi

# ——— Шаг 3: удалить папку и создать симлинк
info "Шаг 3/7: замена папки симлинком"
if [[ -d "$CLAUDE_MEMORY" && ! -L "$CLAUDE_MEMORY" ]]; then
    rm -rf "$CLAUDE_MEMORY"
fi
ln -s "$GIT_MEMORY" "$CLAUDE_MEMORY"
ok "Симлинк: $CLAUDE_MEMORY → $GIT_MEMORY"

# ——— Шаг 4: тест записи через симлинк
info "Шаг 4/7: тест записи через симлинк"
TEST_FILE="$CLAUDE_MEMORY/_symlink_test.tmp"
echo "test $(date)" > "$TEST_FILE"
if [[ -f "$GIT_MEMORY/_symlink_test.tmp" ]]; then
    ok "Запись через симлинк работает"
    rm "$TEST_FILE"
else
    err "Симлинк не работает — файл не виден в git-репо"
    exit 1
fi

fi   # end of SYMLINK_READY block

# ——— Шаг 5: установка скила (идемпотентно)
info "Шаг 5/7: установка скила /setup-memory-sync"
SKILL_SRC="$REPO_DIR/skills/setup-memory-sync"
SKILL_DST="$HOME/.claude/skills/setup-memory-sync"
if [[ -d "$SKILL_SRC" ]]; then
    mkdir -p "$HOME/.claude/skills"
    if [[ -L "$SKILL_DST" ]]; then
        rm "$SKILL_DST"
    elif [[ -d "$SKILL_DST" ]]; then
        mv "$SKILL_DST" "${SKILL_DST}.backup-$TIMESTAMP"
    fi
    ln -s "$SKILL_SRC" "$SKILL_DST"
    ok "Скил: $SKILL_DST → $SKILL_SRC"
else
    warn "Скил не найден в репо (пропущу, работать будет без него)"
fi

# ——— Шаг 6: LaunchAgent для auto-pull каждые 5 мин (идемпотентно)
info "Шаг 6/7: auto-pull каждые 5 мин (LaunchAgent)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOGS_DIR="$HOME/Library/Logs"
mkdir -p "$LAUNCH_AGENTS_DIR" "$LOGS_DIR"

PLIST="$LAUNCH_AGENTS_DIR/com.claudememory.autopull.plist"
LOG_FILE="$LOGS_DIR/claude-memory-autopull.log"

# git путь — launchd не наследует $PATH
GIT_BIN=$(command -v git || echo "/usr/bin/git")

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudememory.autopull</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>cd "$REPO_DIR" &amp;&amp; "$GIT_BIN" pull --quiet 2&gt;&amp;1 | tee -a "$LOG_FILE"</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
ok "LaunchAgent: $PLIST"
ok "Лог: $LOG_FILE"

# ——— Шаг 7: итог
info "Шаг 7/7: готово"
echo ""
ok "Всё настроено. Теперь:"
echo "  • Claude пишет память напрямую в $GIT_MEMORY"
echo "  • Auto-pull каждые 5 мин обновляет репо с GitHub"
echo "  • Сохранить изменения: cd $REPO_DIR && git add -A && git commit -m '...' && git push"
if [[ $SYMLINK_READY -eq 0 ]]; then
    echo "  • Бэкап: $BACKUP_DIR (удали через пару дней когда убедишься что всё работает)"
fi
echo ""
info "Проверка: ./setup/health-check.sh"
info "Откат: ./setup/rollback.sh"
