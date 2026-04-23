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

if [[ "$(uname)" == "Darwin" ]]; then
    CLAUDE_MEMORY="$HOME/.claude/projects/-Users-$(whoami)/memory"
else
    CLAUDE_MEMORY="$HOME/.claude/projects/-home-$(whoami)/memory"
fi

# ——— Поиск бэкапа
if [[ $# -ge 1 ]]; then
    BACKUP="$1"
    if [[ ! -d "$BACKUP" ]]; then
        err "Бэкап не найден: $BACKUP"
        exit 1
    fi
else
    # Находим последний бэкап
    BACKUP=$(ls -dt "$HOME"/claude-memory-backup-* 2>/dev/null | head -1 || echo "")
    if [[ -z "$BACKUP" ]]; then
        err "Бэкапы не найдены в $HOME/claude-memory-backup-*"
        err "Укажи путь явно: $0 /path/to/backup"
        exit 1
    fi
    info "Последний бэкап: $BACKUP"
fi

echo
warn "Rollback восстановит папку памяти Claude из бэкапа."
warn "Текущее состояние $CLAUDE_MEMORY будет УДАЛЕНО."
echo
read -p "Продолжить? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    info "Отмена"
    exit 0
fi

# ——— Удалить текущее (может быть симлинк или папка)
if [[ -e "$CLAUDE_MEMORY" || -L "$CLAUDE_MEMORY" ]]; then
    rm -rf "$CLAUDE_MEMORY"
    ok "Удалено: $CLAUDE_MEMORY"
fi

# ——— Восстановить из бэкапа
cp -a "$BACKUP" "$CLAUDE_MEMORY"
ok "Восстановлено из: $BACKUP"

# ——— Проверить auto-pull — остановить если был запущен
if [[ "$(uname)" == "Darwin" ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.claudememory.autopull.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm "$PLIST"
        ok "Auto-pull (launchd) остановлен и удалён"
    fi
else
    if crontab -l 2>/dev/null | grep -q "claude-memory.*git pull"; then
        crontab -l 2>/dev/null | grep -v "claude-memory.*git pull" | crontab -
        ok "Auto-pull (cron) удалён"
    fi
fi

echo
ok "Откат завершён"
info "Теперь можно снова запустить ./setup/mac.sh (или linux.sh) когда будешь готов"
