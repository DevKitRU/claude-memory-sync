# claude-memory-sync

Синхронизация памяти [Claude Code](https://claude.com/claude-code) между Mac, Windows и Linux через приватный git-репозиторий.

Claude Code хранит память (`MEMORY.md` + заметки) в локальной папке на каждой машине. Между устройствами она сама не переносится. Запомнил на Mac, на Windows этого нет.

Этот репозиторий делает из папки памяти симлинк на рабочую копию git-репо. Дальше всё работает через обычный git: на одной машине сохранил, на другой подтянул.

---

## Что внутри

```
claude-memory-sync/
├── README.md                  # этот файл
├── LICENSE                    # MIT
├── CLAUDE.md.template         # шаблон глобальных инструкций Claude
├── memory/
│   ├── MEMORY.md              # шаблон индекса
│   └── EXAMPLE.md             # как оформлять записи памяти
├── skills/
│   ├── setup-memory-sync/
│   │   └── SKILL.md           # /setup-memory-sync, разворачивает кит на новой машине
│   └── claude-memory-sync/
│       └── SKILL.md           # save/pull/status/resolve, работа с memory-репо
├── setup/
│   ├── README.md              # пошаговая инструкция для человека
│   ├── mac.sh                 # установка на macOS
│   ├── linux.sh               # установка на Linux / VPS
│   ├── windows.ps1            # установка на Windows
│   ├── health-check.{sh,ps1}  # проверить, что всё работает
│   └── rollback.{sh,ps1}      # откат, если что-то сломалось
├── hooks/
│   └── pre-commit             # детектор API-ключей, отклоняет коммит с секретом
└── docs/
    ├── architecture.md        # как это устроено внутри
    ├── secrets.md             # как НЕ слить токены в git
    └── troubleshooting.md     # FAQ по граблям
```

---

## Проблема

Claude Code пишет память в локальную папку:

| Платформа | Куда |
|---|---|
| macOS / Linux | `~/.claude/projects/<хеш>/memory/` |
| Windows | `%USERPROFILE%\.claude\projects\<хеш>\memory\` |

Если работаешь с Claude Code с нескольких машин, память не синкается. Mac, Windows и VPS живут отдельно. Запомнил на Mac важную деталь по проекту, на Windows Claude этого не знает.

## Решение

1. Заводишь приватный репозиторий для памяти.
2. На каждой машине делаешь симлинк из локальной папки Claude в рабочую копию этого репозитория.
3. Настраиваешь периодический pull через cron, launchd или Task Scheduler.

По умолчанию setup ставит pull раз в 5 минут. На рабочем ПК это лучше подстроить под себя. Если играешь или держишь тяжёлые задачи, увеличь интервал или запускай pull вручную перед работой.

```
Mac (симлинк)     \
Linux (симлинк)    -> GitHub (приватный claude-memory) <- git pull
Windows (Junction) /
```

Симлинк означает, что запись Claude в локальную папку физически попадает в рабочую копию git-репо. Дальше обычный git.

---

## Установка

### 1. Заведи приватный репо для своей памяти

На GitHub создай пустой приватный репо, например `<твой-ник>/claude-memory`. Склонируй его:

```bash
# macOS
git clone git@github.com:<твой-ник>/claude-memory.git ~/Documents/claude-memory

# Linux (на VPS)
git clone git@github.com:<твой-ник>/claude-memory.git ~/claude-memory

# Windows (PowerShell)
git clone https://github.com/<твой-ник>/claude-memory.git E:\projects\claude-memory
```

Если ты только начинаешь и у тебя ещё нет папки памяти, клонируй сразу этот кит и положи файлы `CLAUDE.md.template`, `memory/MEMORY.md`, `memory/EXAMPLE.md` в свой новый репо. Так у тебя будет стартовый набор.

### 2. Склонируй этот кит рядом

```bash
# macOS / Linux
git clone https://github.com/DevKitRU/claude-memory-sync.git ~/Documents/claude-memory-sync

# Windows (PowerShell)
git clone https://github.com/DevKitRU/claude-memory-sync.git E:\projects\claude-memory-sync
```

Скрипты автоматически определят путь к твоему **приватному memory-репо** (ищут по дефолтным путям либо спросят).

### 3. Запусти setup-скрипт

```bash
# macOS
cd ~/Documents/claude-memory-sync && ./setup/mac.sh

# Linux
cd ~/claude-memory-sync && ./setup/linux.sh

# Windows (PowerShell, запускай из той же папки)
cd E:\projects\claude-memory-sync
.\setup\windows.ps1
```

Скрипт:
1. Сделает бэкап текущей папки памяти Claude (`~/claude-memory-backup-<timestamp>`).
2. Смержит локальные уникальные файлы в твой memory-репо.
3. Заменит локальную папку на симлинк или Junction к memory-репо.
4. Настроит auto-pull по расписанию.
5. Протестирует запись через симлинк.

Повторный запуск безопасен. Скрипт идемпотентен.

### Проверь что всё ок

```bash
./setup/health-check.sh    # Mac/Linux
.\setup\health-check.ps1   # Windows
```

Пять пунктов должны быть зелёными: симлинк, git-репо, up-to-date с GitHub, auto-pull работает, файлы совпадают.

---

## Безопасность

Память Claude становится файлами в git. Если туда попадёт API-ключ, он уедет в историю коммитов. Приватный репозиторий снижает риск, но не отменяет его.

**Три правила:**

1. **Ключи храни вне memory-файлов.** Например в `~/.claude/secrets/api-keys.env` или secret manager. В памяти оставляй только путь.
2. **Установи pre-commit hook** в свой memory-репо:
   ```bash
   # Mac/Linux
   cp <этот-репо>/hooks/pre-commit <твой-memory-репо>/.git/hooks/
   chmod +x <твой-memory-репо>/.git/hooks/pre-commit
   ```
   Hook ловит 15+ форматов: Anthropic, OpenAI, GitHub PAT, Slack, Telegram, AWS, JWT, SSH private keys. Если найдёт секрет, коммит не пройдёт.
3. **Пропиши правило в `CLAUDE.md`** (шаблон в [CLAUDE.md.template](CLAUDE.md.template#L38)):
   > Ключи хранятся в `~/.claude/secrets/api-keys.env`. В memory-файлах упоминается только *где*, никогда сам ключ.

Полный гайд: [docs/secrets.md](docs/secrets.md).

---

## Команды на каждый день

| Хочу | Команда |
|---|---|
| Сохранить свежую память на GitHub | `cd <memory-repo> && git add -A && git commit -m '...' && git push` |
| Подтянуть свежее с GitHub вручную | `cd <memory-repo> && git pull` |
| Проверить что всё работает | `./setup/health-check.sh` / `.ps1` |
| Откатиться если что-то сломалось | `./setup/rollback.sh` / `.ps1` |

Удобно в CLAUDE.md прописать команды `save` и `pull` как слова. Тогда в чате говоришь «сохрани», и Claude делает commit и push.

---

## Частые вопросы

**А если я захочу чтобы Claude на всех машинах видел одинаковые глобальные инструкции?**
Скопируй `CLAUDE.md.template` как `CLAUDE.md` в корень своего приватного memory-репо. Потом настрой `~/.claude/CLAUDE.md` или `%USERPROFILE%\.claude\CLAUDE.md` как симлинк на эту же копию. Теперь одна правка видна на всех машинах.

**Что если я не хочу хранить память на GitHub?**
Используй self-hosted git: Gitea или GitLab. Скрипты не привязаны к GitHub, они просто делают `git pull`.

**Безопасно ли хранить память в GitHub?**
Репо должен быть приватным. Секреты храни вне git-репо памяти, например в `~/.claude/secrets/api-keys.env`. В памяти оставляй только ссылки вроде «ключ лежит там-то».

Подробный гайд: [docs/secrets.md](docs/secrets.md). Поставь `hooks/pre-commit` в свой memory-репо сразу. Он ловит 15+ форматов API-ключей и отклоняет коммит, если что-то утекает.

**Windows PowerShell ругается на скрипт с кучей ошибок.**
Скрипты используют кириллицу. PowerShell 5.1 без UTF-8 BOM читает `.ps1` как cp1251, и парсер падает. Скрипты в этом ките уже с BOM. Если переписываешь, сохраняй как UTF-8 with BOM.

**Работает ли в WSL?**
WSL2 работает как обычный Linux. WSL1 лучше не использовать для этой схемы.

**А как на iPad / iPhone?**
На телефонах Claude Code нет. Если нужен доступ к своей памяти с телефона, посмотри [claude-telegram-bot](https://github.com/DevKitRU/claude-telegram-bot).

---

## Архитектура

Детали: [docs/architecture.md](docs/architecture.md). FAQ по граблям: [docs/troubleshooting.md](docs/troubleshooting.md).

---

## Лицензия

[MIT](LICENSE).
