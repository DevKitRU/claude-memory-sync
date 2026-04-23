#!/usr/bin/env bash
# Claude Memory Sync — rollback для Mac/Linux
#
# Восстанавливает папку памяти из последнего бэкапа.
# Использовать если скрипт установки что-то сломал.
#
# Использование:
#   ./setup/rollback.sh              # найдёт последний бэкап автоматом
#   ./setup/rollback.sh PATH         # указать конкретный бэкап

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

# ——— Discovery: ищем симлинк установленный нашим скриптом
find_installed_symlink() {
    local projects_dir="$HOME/.claude/projects"
    if [[ ! -d "$projects_dir" ]]; then
        return 1
    fi
    while IFS= read -r -d '' dir; do
        local mem="$dir/memory"
        if [[ -L "$mem" ]]; then
            local target
            target=$(readlink "$mem")
            if [[ "$target" == "$GIT_MEMORY" ]]; then
                echo "$mem"
                return 0
            fi
        fi
    done < <(find "$projects_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    return 1
}

CLAUDE_MEMORY=""
if ! CLAUDE_MEMORY=$(find_installed_symlink); then
    warn "Не нашёл симлинк ведущий в $GIT_MEMORY."
    warn "Вероятно setup-скрипт не выполнялся до конца, или симлинк уже удалён."
    warn ""
    warn "Попробуй один из вариантов:"
    warn "  1. Восстановить бэкап вручную:  cp -a <backup> <target>"
    warn "  2. Запустить setup заново:       ./setup/mac.sh  (или linux.sh)"
    warn "     — он сам найдёт/создаст нужную папку и предложит мерж."
    exit 1
fi

# ——— Поиск бэкапа
BACKUP=""
if [[ $# -ge 1 ]]; then
    BACKUP="$1"
    if [[ ! -d "$BACKUP" ]]; then
        err "Бэкап не найден: $BACKUP"
        exit 1
    fi
else
    # find + sort: переживает пробелы в именах директорий
    BACKUP=$(find "$HOME" -maxdepth 1 -type d -name "claude-memory-backup-*" -print0 2>/dev/null \
        | xargs -0 -I{} sh -c 'printf "%s\t%s\n" "$(stat -f %m "{}" 2>/dev/null || stat -c %Y "{}")" "{}"' \
        | sort -rn | head -1 | cut -f2-)
    if [[ -z "$BACKUP" ]]; then
        err "Бэкапы не найдены в $HOME/claude-memory-backup-*"
        err "Укажи путь явно: $0 /path/to/backup"
        exit 1
    fi
    info "Последний бэкап: $BACKUP"
fi

echo ""
warn "Rollback восстановит папку памяти Claude из бэкапа."
warn "Текущее состояние $CLAUDE_MEMORY будет УДАЛЕНО."
echo ""
read -p "Продолжить? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    info "Отмена"
    exit 0
fi

# ——— Удалить текущее (симлинк или папка)
if [[ -e "$CLAUDE_MEMORY" || -L "$CLAUDE_MEMORY" ]]; then
    rm -rf "$CLAUDE_MEMORY"
    ok "Удалено: $CLAUDE_MEMORY"
fi

# Убедиться что родительская директория существует
mkdir -p "$(dirname "$CLAUDE_MEMORY")"

# ——— Восстановить из бэкапа
cp -a "$BACKUP" "$CLAUDE_MEMORY"
ok "Восстановлено из: $BACKUP"

# ——— Остановить auto-pull
if [[ "$(uname)" == "Darwin" ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.claudememory.autopull.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm "$PLIST"
        ok "Auto-pull (launchd) остановлен и удалён"
    fi
else
    if crontab -l 2>/dev/null | grep -q "claude-memory"; then
        crontab -l 2>/dev/null | grep -v "claude-memory" | crontab -
        ok "Auto-pull (cron) удалён"
    fi
fi

echo ""
ok "Откат завершён"
info "Теперь можно снова запустить ./setup/mac.sh (или linux.sh) когда будешь готов"
