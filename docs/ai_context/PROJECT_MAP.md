# PROJECT_MAP

Короткая карта `claude-memory-sync` для Codex, Claude и других AI-агентов.

Это роутер, а не архив.

## Что это за проект

Публичный DevKitRU kit для синхронизации памяти Claude Code через git.

Идея: локальная папка памяти Claude становится symlink/Junction на private memory repo. Дальше sync идет через обычный git и auto-pull.

## Быстрый вход

1. Прочитай этот файл.
2. Если задача касается секретов, setup scripts, symlink/Junction, hooks или auto-pull, прочитай `DANGER_ZONES.md`.
3. Открой только нужную платформенную папку или doc.
4. Перед финалом смотри `VERIFICATION.md`.

## Карта файлов

| Путь | Роль | Читать когда |
| --- | --- | --- |
| `README.md` | Главная витрина проекта | Меняем общую подачу |
| `setup/README.md` | Пошаговая установка | Меняем onboarding |
| `setup/mac.sh` | macOS setup | Меняем symlink/launchd behavior |
| `setup/linux.sh` | Linux/VPS setup | Меняем symlink/cron behavior |
| `setup/windows.ps1` | Windows setup | Меняем Junction/Task Scheduler behavior |
| `setup/health-check.*` | Проверка установки | Меняем diagnostics |
| `setup/rollback.*` | Откат | Меняем recovery path |
| `hooks/pre-commit` | Secret detector | Меняем secret policy |
| `CLAUDE.md.template` | Global Claude instruction template | Меняем memory behavior |
| `memory/MEMORY.md` | Memory index template | Меняем memory structure |
| `memory/EXAMPLE.md` | Memory entry example | Меняем examples |
| `skills/*/SKILL.md` | Claude skill docs | Меняем agent workflows |
| `docs/secrets.md` | Secret hygiene | Меняем security docs |
| `docs/architecture.md` | Internal architecture | Меняем design explanation |

## Главные потоки

- New machine -> clone private memory repo -> run setup script -> backup existing Claude memory -> merge files -> replace local memory with symlink/Junction -> configure auto-pull -> health check.
- Daily work -> Claude writes memory files -> user/agent commits and pushes -> other machines auto-pull.
- Safety -> secrets must stay outside memory repo -> pre-commit hook blocks common key patterns.

## Точки поиска

```bash
rg -n "symlink|Junction|auto-pull|cron|Task Scheduler|pre-commit|secret|MEMORY.md|CLAUDE.md" .
rg -n "private|public|claude-memory|backup|rollback|health-check" .
```

## Правило контекста

Не читать настоящие private memory repos, `.env`, secret files или локальные Claude memory folders.

Сначала карта. Потом danger zones. Потом конкретный setup/doc/hook.
