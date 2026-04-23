#!/usr/bin/env bash
# Claude Memory Sync — Linux (VPS) setup
#
# Превращает локальную папку памяти Claude в симлинк на git-репо claude-memory.
# Идемпотентен: повторный запуск не ломает.
#
# Использование:
#   cd ~/claude-memory-sync      (или где клонирован репо)
#   ./setup/linux.sh
#
# Что делает:
#   1. Проверяет что git-репо на месте
#   2. Находит реальную папку памяти Claude (~/.claude/projects/-home-<user>/memory)
#   3. Бэкапит её в ~/claude-memory-sync-backup-<timestamp>
#   4. Мержит уникальные файлы в git-репо
#   5. Заменяет папку симлинком на git-репо
#   6. Настраивает auto-pull через cron (каждые 5 мин)
#   7. Тестирует запись через симлинк

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_MEMORY="$REPO_DIR/memory"

USER_HOME_ENCODED="-home-$(whoami)"
CLAUDE_MEMORY="$HOME/.claude/projects/$USER_HOME_ENCODED/memory"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/claude-memory-backup-$TIMESTAMP"

info "Linux setup для Claude Memory Sync"
info "Репо: $REPO_DIR"
info "Git-память: $GIT_MEMORY"
info "Claude-память: $CLAUDE_MEMORY"
echo

if [[ ! -d "$GIT_MEMORY" ]]; then
    err "Git-репо не найден: $GIT_MEMORY"
    err "Сначала: git clone https://github.com/DevKitRU/claude-memory-sync.git $REPO_DIR"
    exit 1
fi

# Если уже симлинк
if [[ -L "$CLAUDE_MEMORY" ]]; then
    CURRENT_TARGET=$(readlink "$CLAUDE_MEMORY")
    if [[ "$CURRENT_TARGET" == "$GIT_MEMORY" ]]; then
        ok "Симлинк уже настроен: $CLAUDE_MEMORY → $GIT_MEMORY"
        exit 0
    else
        warn "Симлинк ведёт в другое место: $CURRENT_TARGET"
        warn "Пересоздаю..."
        rm "$CLAUDE_MEMORY"
    fi
fi

info "Шаг 1/6: бэкап"
if [[ -d "$CLAUDE_MEMORY" ]]; then
    cp -a "$CLAUDE_MEMORY" "$BACKUP_DIR"
    ok "Бэкап: $BACKUP_DIR"
else
    info "Папки памяти Claude не существует — бэкап не нужен"
    mkdir -p "$(dirname "$CLAUDE_MEMORY")"
fi

info "Шаг 2/6: мерж"
MERGED=0
if [[ -d "$CLAUDE_MEMORY" ]]; then
    while IFS= read -r -d '' file; do
        name=$(basename "$file")
        target="$GIT_MEMORY/$name"
        if [[ ! -e "$target" ]]; then
            cp "$file" "$target"
            echo "  + $name"
            ((MERGED++))
        elif [[ "$file" -nt "$target" ]]; then
            cp "$file" "$target"
            echo "  ↑ $name"
            ((MERGED++))
        fi
    done < <(find "$CLAUDE_MEMORY" -maxdepth 1 -type f -print0)
fi
ok "Смержено: $MERGED файлов"

info "Шаг 3/6: симлинк"
if [[ -d "$CLAUDE_MEMORY" && ! -L "$CLAUDE_MEMORY" ]]; then
    rm -rf "$CLAUDE_MEMORY"
fi
ln -s "$GIT_MEMORY" "$CLAUDE_MEMORY"
ok "$CLAUDE_MEMORY → $GIT_MEMORY"

info "Шаг 4/6: тест записи"
TEST_FILE="$CLAUDE_MEMORY/_symlink_test.tmp"
echo "test $(date)" > "$TEST_FILE"
if [[ -f "$GIT_MEMORY/_symlink_test.tmp" ]]; then
    ok "Работает"
    rm "$TEST_FILE"
else
    err "Симлинк не работает"
    exit 1
fi

info "Шаг 5/7: установка скила /setup-memory-sync"
SKILL_SRC="$REPO_DIR/skills/setup-memory-sync"
SKILL_DST="$HOME/.claude/skills/setup-memory-sync"
if [[ -d "$SKILL_SRC" ]]; then
    mkdir -p "$HOME/.claude/skills"
    if [[ -L "$SKILL_DST" ]]; then rm "$SKILL_DST"
    elif [[ -d "$SKILL_DST" ]]; then mv "$SKILL_DST" "${SKILL_DST}.backup-$TIMESTAMP"
    fi
    ln -s "$SKILL_SRC" "$SKILL_DST"
    ok "Скил: $SKILL_DST → $SKILL_SRC"
fi

info "Шаг 6/7: auto-pull через cron (каждые 5 мин)"
CRON_CMD="*/5 * * * * cd $REPO_DIR && git pull --quiet >> $HOME/logs/claude-memory-autopull.log 2>&1"
mkdir -p "$HOME/logs"

# Убираем старую запись если была, добавляем новую
(crontab -l 2>/dev/null | grep -v "claude-memory.*git pull" || true; echo "$CRON_CMD") | crontab -
ok "Cron установлен (лог: $HOME/logs/claude-memory-autopull.log)"

info "Шаг 7/7: готово"
echo
ok "Всё настроено."
echo "  • Claude пишет память напрямую в $GIT_MEMORY"
echo "  • Cron тянет свежее с GitHub каждые 5 мин"
echo "  • Сохранить: cd $REPO_DIR && git add -A && git commit -m '...' && git push"
echo "  • Бэкап: $BACKUP_DIR"
echo
info "Проверка: ./setup/health-check.sh"
info "Откат: ./setup/rollback.sh"
