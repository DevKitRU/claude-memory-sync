# Claude Memory Sync Kit

Синхронизация памяти Claude Code между Mac, Windows и Linux-сервером через Git.

## Зачем это

Claude Code хранит память (`MEMORY.md` + заметки) в локальной папке на каждой машине:

| Платформа | Где хранит |
|---|---|
| macOS | `~/.claude/projects/<project-path>/memory/` |
| Linux | `~/.claude/projects/<project-path>/memory/` |
| Windows | `%USERPROFILE%\.claude\projects\<project-path>\memory\` |

**Проблема:** папки локальные, между машинами ничего не синхронизируется. На Маке запомнил — на Windows не видно.

**Решение:** делаем из локальной папки **симлинк** на git-репозиторий. Теперь:
- Claude пишет память → файл сразу попадает в git-репо.
- `git push` → изменения на GitHub.
- Другая машина делает `git pull` (сама, через auto-pull) → видит свежую память.

## Как это выглядит после установки

```
┌─────────────┐    git push     ┌─────────────┐    git pull    ┌─────────────┐
│     Mac     │ ───────────────▶│   GitHub    │ ──────────────▶│     VPS     │
│  (symlink)  │                 │ claude-memory│                │  (symlink)  │
└─────────────┘                 └─────────────┘                 └─────────────┘
                                       ▲
                                       │ git pull (auto)
                                       │
                                ┌─────────────┐
                                │   Windows   │
                                │ (Junction)  │
                                └─────────────┘
```

## Установка на новой машине — 3 шага

### 1. Клонируй этот репо

```bash
# Mac/Linux
git clone https://github.com/DevKitRU/claude-memory-sync.git ~/Documents/claude-memory-sync

# Windows (PowerShell)
git clone https://github.com/DevKitRU/claude-memory-sync.git E:\projects\claude-memory-sync
```

### 2. Запусти скрипт под свою платформу

```bash
# macOS
cd ~/Documents/claude-memory-sync
./setup/mac.sh

# Linux (VPS)
cd ~/claude-memory-sync
./setup/linux.sh

# Windows (PowerShell)
cd E:\projects\claude-memory
.\setup\windows.ps1
```

Скрипт сам:
1. Сделает бэкап текущей папки памяти Claude (если была).
2. Смержит уникальные файлы в git-репо (чтобы не потерять локальные заметки).
3. Заменит папку памяти на симлинк/Junction к git-репо.
4. Настроит auto-pull (cron на Linux/Mac, Task Scheduler на Windows).
5. Протестирует запись через симлинк.

### 3. Проверь

```bash
./setup/health-check.sh    # Mac/Linux
.\setup\health-check.ps1   # Windows
```

Скрипт скажет всё ли ок: симлинк на месте, auto-pull работает, git в порядке.

## Команды

После установки:

| Что хочу | Команда |
|---|---|
| Сохранить свежую память на GitHub | `cd claude-memory && git add -A && git commit -m "update" && git push` |
| Подтянуть свежее с GitHub | `cd claude-memory && git pull` (или auto-pull сам — каждые 5 мин) |
| Проверить что всё работает | `./setup/health-check.sh` |
| Откатить если что-то сломалось | `./setup/rollback.sh` |

## Если что-то пошло не так

**Скрипт сломал память?**
```bash
./setup/rollback.sh    # Mac/Linux
.\setup\rollback.ps1   # Windows
```
Скрипт восстановит папку из бэкапа (`~/claude-memory-sync-backup-<timestamp>`).

**Симлинк сломался (папка памяти стала обычной)?**
Запусти скрипт установки ещё раз — он идемпотентен.

**Файлы разошлись между машинами?**
Git разрулит через обычный merge. Если конфликт — `git pull`, reset и заново.

## Архитектура

См. [project_memory_sync_kit.md](../memory/project_memory_sync_kit.md) в этом же репо.

## Безопасность

- Бэкап делается **до** любой деструктивной операции.
- Скрипты идемпотентны — повторный запуск не ломает.
- Скрипты не требуют root/admin (кроме Windows Task Scheduler — но Junction и без админа работает).
- В git-репо коммитится **только публичная структура памяти** — чувствительные файлы (пароли, токены) лучше хранить не здесь.

## Публичная версия

Этот репо — приватный (авторская память Сергея). Готовится публичный форк с шаблонами и обезличенной документацией для community — следи за обновлениями на GitHub.
