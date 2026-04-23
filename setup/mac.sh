#!/usr/bin/env bash
# Claude Memory Sync — macOS setup
#
# Превращает локальную папку памяти Claude в симлинк на git-репо claude-memory.
# Идемпотентен: повторный запуск не ломает.
#
# Использование:
#   cd ~/Documents/claude-memory-sync    (или где клонирован репо)
#   ./setup/mac.sh
#
# Что делает:
#   1. Проверяет что git-репо на месте
#   2. Находит реальную папку памяти Claude (~/.claude/projects/-Users-<user>/memory)
#   3. Бэкапит её в ~/claude-memory-sync-backup-<timestamp>
#   4. Мержит уникальные файлы в git-репо
#   5. Заменяет папку симлинком на git-репо
#   6. Настраивает auto-pull через launchd (каждые 5 мин)
#   7. Тестирует запись через симлинк

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

USER_HOME_ENCODED="-Users-$(whoami)"
CLAUDE_MEMORY="$HOME/.claude/projects/$USER_HOME_ENCODED/memory"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/claude-memory-backup-$TIMESTAMP"

# ——— Проверки
info "macOS setup для Claude Memory Sync"
info "Репо: $REPO_DIR"
info "Git-память: $GIT_MEMORY"
info "Claude-память: $CLAUDE_MEMORY"
echo

if [[ ! -d "$GIT_MEMORY" ]]; then
    err "Git-репо не найден: $GIT_MEMORY"
    err "Сначала: git clone https://github.com/DevKitRU/claude-memory-sync.git $REPO_DIR"
    exit 1
fi

# ——— Шаг 0: уже симлинк?
SYMLINK_READY=0
if [[ -L "$CLAUDE_MEMORY" ]]; then
    CURRENT_TARGET=$(readlink "$CLAUDE_MEMORY")
    if [[ "$CURRENT_TARGET" == "$GIT_MEMORY" ]]; then
        ok "Симлинк уже настроен: $CLAUDE_MEMORY → $GIT_MEMORY"
        info "Пропускаю шаги 1-4, проверю только скил и auto-pull..."
        SYMLINK_READY=1
    else
        warn "Симлинк есть, но ведёт в другое место: $CURRENT_TARGET"
        warn "Пересоздаю..."
        rm "$CLAUDE_MEMORY"
    fi
fi

if [[ $SYMLINK_READY -eq 0 ]]; then
# ——— Шаг 1: бэкап
info "Шаг 1/7: бэкап текущей памяти"
if [[ -d "$CLAUDE_MEMORY" ]]; then
    cp -a "$CLAUDE_MEMORY" "$BACKUP_DIR"
    ok "Бэкап: $BACKUP_DIR"
else
    info "Папки памяти Claude не существует — бэкап не нужен"
    mkdir -p "$(dirname "$CLAUDE_MEMORY")"
fi

# ——— Шаг 2: мерж
info "Шаг 2/7: мерж уникальных файлов в git-репо"
MERGED=0
if [[ -d "$CLAUDE_MEMORY" ]]; then
    while IFS= read -r -d '' file; do
        name=$(basename "$file")
        target="$GIT_MEMORY/$name"
        if [[ ! -e "$target" ]]; then
            cp "$file" "$target"
            echo "  + $name (уникальный, перенесён в git)"
            ((MERGED++))
        elif [[ "$file" -nt "$target" ]]; then
            cp "$file" "$target"
            echo "  ↑ $name (Mac свежее, обновлён)"
            ((MERGED++))
        fi
    done < <(find "$CLAUDE_MEMORY" -maxdepth 1 -type f -print0)
fi
if [[ $MERGED -eq 0 ]]; then
    ok "Всё уже в git-репо или актуальнее"
else
    ok "Смержено файлов: $MERGED"
fi

# ——— Шаг 3: удалить папку и создать симлинк
info "Шаг 3/7: замена папки симлинком"
if [[ -d "$CLAUDE_MEMORY" && ! -L "$CLAUDE_MEMORY" ]]; then
    rm -rf "$CLAUDE_MEMORY"
fi
ln -s "$GIT_MEMORY" "$CLAUDE_MEMORY"
ok "Симлинк: $CLAUDE_MEMORY → $GIT_MEMORY"

# ——— Шаг 4: тест записи
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

# ——— Шаг 5: скил
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
    ok "Скил установлен: $SKILL_DST → $SKILL_SRC"
else
    warn "Скил не найден в репо (будет работать через setup/*.sh напрямую)"
fi

info "Шаг 6/7: auto-pull (каждые 5 мин)"
PLIST="$HOME/Library/LaunchAgents/com.claudememory.autopull.plist"
LOG_FILE="$HOME/Library/Logs/claude-memory-autopull.log"

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
        <string>cd "$REPO_DIR" &amp;&amp; git pull --quiet 2&gt;&amp;1 | tee -a "$LOG_FILE"</string>
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
ok "Auto-pull установлен: $PLIST (лог: $LOG_FILE)"

# ——— Шаг 7: итог
info "Шаг 7/7: готово"
echo
ok "Всё настроено. Теперь:"
echo "  • Claude пишет память напрямую в $GIT_MEMORY"
echo "  • Auto-pull каждые 5 мин обновляет репо с GitHub"
echo "  • Чтобы сохранить изменения: cd $REPO_DIR && git add -A && git commit -m '...' && git push"
echo "  • Бэкап: $BACKUP_DIR (удали через пару дней когда убедишься что всё работает)"
echo
info "Проверка: ./setup/health-check.sh"
info "Откат: ./setup/rollback.sh"
