#!/usr/bin/env bash
# Claude Memory Sync — health check для Mac/Linux
#
# Проверяет:
#   1. Симлинк на месте и указывает на git-репо
#   2. Git статус (чисто или с uncommitted)
#   3. Синхронизация с GitHub (ahead/behind)
#   4. Auto-pull работает (по логу)
#   5. Количество файлов совпадает

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

# ——— Discovery: находим симлинк который ведёт в наш git-репо
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

# Определяем платформу для путей auto-pull лога
if [[ "$(uname)" == "Darwin" ]]; then
    LOG_PATH="$HOME/Library/Logs/claude-memory-autopull.log"
else
    LOG_PATH="$HOME/logs/claude-memory-autopull.log"
fi

ISSUES=0
echo "========== Claude Memory Sync Health Check =========="
echo ""

# ——— 1. Симлинк
info "1) Симлинк"
CLAUDE_MEMORY=""
if CLAUDE_MEMORY=$(find_installed_symlink); then
    ok "   Симлинк корректный: $CLAUDE_MEMORY -> $GIT_MEMORY"
else
    err "   Не нашёл симлинк в ~/.claude/projects/*/memory ведущий в $GIT_MEMORY"
    err "   Запусти ./setup/mac.sh (или linux.sh)"
    ISSUES=$((ISSUES + 1))
fi

# ——— 2. Git статус
info "2) Git статус"
cd "$REPO_DIR"
DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
if [[ "$DIRTY" == "0" ]]; then
    ok "   Чисто (всё закоммичено)"
else
    warn "   $DIRTY несохранённых изменений:"
    git status --short | head -5 | sed 's/^/     /'
    warn "   Сохранить: cd $REPO_DIR && git add -A && git commit -m '...' && git push"
fi

# ——— 3. Синхронизация с GitHub
info "3) Синхронизация с GitHub"
git fetch --quiet 2>/dev/null || warn "   Не удалось fetch (нет интернета / прокси / auth?)"
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "?")
if [[ "$AHEAD" == "0" && "$BEHIND" == "0" ]]; then
    ok "   Up to date с origin"
elif [[ "$AHEAD" != "0" && "$BEHIND" == "0" ]]; then
    warn "   Впереди origin на $AHEAD коммитов (не запушено)"
elif [[ "$AHEAD" == "0" && "$BEHIND" != "0" ]]; then
    warn "   Отстаёт от origin на $BEHIND коммитов (сделай git pull)"
else
    warn "   Расходится: впереди $AHEAD, позади $BEHIND"
fi

# ——— 4. Auto-pull лог
info "4) Auto-pull"
if [[ -f "$LOG_PATH" ]]; then
    # BSD (macOS) stat -f "%m", GNU (Linux) stat -c "%Y" — пробуем оба безопасно
    LAST_MOD=""
    LAST_MOD=$(stat -f "%m" "$LOG_PATH" 2>/dev/null || true)
    if [[ -z "$LAST_MOD" ]]; then
        LAST_MOD=$(stat -c "%Y" "$LOG_PATH" 2>/dev/null || echo "0")
    fi
    NOW=$(date +%s)
    DIFF=$((NOW - LAST_MOD))
    if [[ $DIFF -lt 600 ]]; then
        ok "   Лог обновлялся $((DIFF/60)) мин назад — auto-pull работает"
    elif [[ $DIFF -lt 3600 ]]; then
        warn "   Лог обновлялся $((DIFF/60)) мин назад (ожидали <10 мин)"
    else
        err "   Лог не обновлялся $((DIFF/3600)) часов — auto-pull не работает"
        ISSUES=$((ISSUES + 1))
    fi
else
    warn "   Лог не найден: $LOG_PATH"
    warn "   Возможно auto-pull ни разу не запускался. Проверь:"
    if [[ "$(uname)" == "Darwin" ]]; then
        warn "     launchctl list | grep claudememory"
    else
        warn "     crontab -l | grep claude-memory"
    fi
fi

# ——— 5. Количество файлов
info "5) Файлы"
FILES_IN_GIT=$(find "$GIT_MEMORY" -maxdepth 1 -type f | wc -l | tr -d ' ')
if [[ -n "$CLAUDE_MEMORY" ]]; then
    FILES_VIA_LINK=$(find -L "$CLAUDE_MEMORY" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$FILES_IN_GIT" == "$FILES_VIA_LINK" ]]; then
        ok "   $FILES_IN_GIT файлов (git и симлинк совпадают)"
    else
        err "   git=$FILES_IN_GIT, через симлинк=$FILES_VIA_LINK — РАСХОЖДЕНИЕ"
        ISSUES=$((ISSUES + 1))
    fi
else
    warn "   Симлинк не найден — пропускаю"
fi

echo ""
if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}========== Всё ок ==========${NC}"
    exit 0
else
    echo -e "${RED}========== Найдено проблем: $ISSUES ==========${NC}"
    exit 1
fi
