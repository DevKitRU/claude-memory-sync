# claude-memory-sync

Синхронизация памяти [Claude Code](https://claude.com/claude-code) между Mac, Windows и Linux через приватный git-репозиторий.

**TL;DR.** Claude Code хранит память (`MEMORY.md` + заметки) в локальной папке на каждой машине. Между устройствами ничего не синхронизируется — на Маке запомнил, на Windows не видно. Этот кит делает из локальной папки **симлинк на git-репо**, `git push` → `git pull` разносит память между всеми машинами автоматически.

Репо — комплект скриптов и Claude Skill, готовый к установке за 3 шага. MIT, приватная память остаётся у тебя.

---

## Что внутри

```
claude-memory-sync/
├── README.md                  ← этот файл
├── LICENSE                    ← MIT
├── CLAUDE.md.template         ← шаблон глобальных инструкций Claude
├── memory/
│   ├── MEMORY.md              ← шаблон индекса
│   └── EXAMPLE.md             ← как оформлять записи памяти
├── skills/
│   ├── setup-memory-sync/
│   │   └── SKILL.md           ← /setup-memory-sync — разворачивает кит на новой машине
│   └── claude-memory-sync/
│       └── SKILL.md           ← save/pull/status/resolve — повседневная работа с memory-репо
├── setup/
│   ├── README.md              ← пошаговая инструкция для человека
│   ├── mac.sh                 ← установка на macOS
│   ├── linux.sh               ← установка на Linux / VPS
│   ├── windows.ps1            ← установка на Windows
│   ├── health-check.{sh,ps1}  ← проверить что всё работает
│   └── rollback.{sh,ps1}      ← откат если что-то сломалось
├── hooks/
│   └── pre-commit             ← детектор API-ключей, отклоняет коммит с секретом
└── docs/
    ├── architecture.md        ← как это устроено внутри
    ├── secrets.md             ← как НЕ слить токены в git
    └── troubleshooting.md     ← FAQ по граблям
```

---

## Проблема

Claude Code пишет память в локальную папку:

| Платформа | Куда |
|---|---|
| macOS / Linux | `~/.claude/projects/<хеш>/memory/` |
| Windows | `%USERPROFILE%\.claude\projects\<хеш>\memory\` |

Если работаешь с Claude Code с нескольких машин (Mac + Windows + VPS для удалённой сессии), память **не синкается** — каждая машина живёт в своём мирке. Запомнил на Маке «клиент предпочитает тесты на реальной БД» — на Windows Claude этого не знает, придётся рассказывать заново.

## Решение

1. Заводишь **приватный репо** на GitHub (например `github.com/<ТЫ>/claude-memory`) — туда будет падать твоя память.
2. На каждой машине делаешь **симлинк** из локальной папки памяти в рабочую копию этого репо.
3. Настраиваешь **auto-pull каждые 5 минут** (cron / launchd / Task Scheduler). На Mac запомнил → `git push` → через 5 мин на Windows уже видно.

```
Mac (симлинк)    ↘
Linux (симлинк)   → GitHub (приватный claude-memory)  ← git pull каждые 5 мин
Windows (Junction)↗
```

Симлинк означает, что запись Claude в локальную папку **физически попадает** в рабочую копию git-репо. Дальше обычный git.

---

## Установка — 3 шага

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

Если ты только начинаешь и у тебя ещё нет папки памяти, **клонируй сразу этот кит** и положи файлы `CLAUDE.md.template`, `memory/MEMORY.md`, `memory/EXAMPLE.md` в свой новый репо — так у тебя будет стартовый набор.

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
1. Сделает **бэкап** текущей папки памяти Claude (`~/claude-memory-backup-<timestamp>`).
2. Смержит локальные уникальные файлы в твой memory-репо.
3. Заменит локальную папку на **симлинк/Junction** к memory-репо.
4. Настроит **auto-pull** каждые 5 минут (cron/launchd/Task Scheduler).
5. Протестирует запись через симлинк.

Повторный запуск безопасен — скрипт идемпотентен.

### Проверь что всё ок

```bash
./setup/health-check.sh    # Mac/Linux
.\setup\health-check.ps1   # Windows
```

Пять пунктов должны быть зелёными: симлинк, git-репо, up-to-date с GitHub, auto-pull работает, файлы совпадают.

---

## Безопасность: не слейте токены в git

Память Claude = файлы в git. Если Claude «поможет» и запишет API-ключ в memory-файл — он уедет на GitHub и останется в истории коммитов навсегда. Приватный репо это не страховка — коллаборатор / случайный публичный форк / кеш GitHub его увидят.

**Три правила:**

1. **Ключи — в `~/.claude/secrets/api-keys.env` (или secret manager), а не в memory-файлах.** В памяти храни только *где* лежит ключ, не сам ключ.
2. **Установи pre-commit hook** в свой memory-репо:
   ```bash
   # Mac/Linux
   cp <этот-репо>/hooks/pre-commit <твой-memory-репо>/.git/hooks/
   chmod +x <твой-memory-репо>/.git/hooks/pre-commit
   ```
   Hook ловит 15+ форматов (Anthropic, OpenAI, GitHub PAT, Slack, Telegram, AWS, JWT, SSH private keys). Если что-то нашёл — откажет в коммите.
3. **Пропиши правило в `CLAUDE.md`** (шаблон в [CLAUDE.md.template](CLAUDE.md.template#L38)):
   > Ключи хранятся в `~/.claude/secrets/api-keys.env`. В memory-файлах упоминается только *где*, никогда сам ключ.

Полный гайд с паттернами, ротацией, чеклистом для нового репо — [docs/secrets.md](docs/secrets.md).

---

## Команды на каждый день

| Хочу | Команда |
|---|---|
| Сохранить свежую память на GitHub | `cd <memory-repo> && git add -A && git commit -m '...' && git push` |
| Подтянуть свежее с GitHub вручную | `cd <memory-repo> && git pull` (auto-pull делает это сам каждые 5 мин) |
| Проверить что всё работает | `./setup/health-check.sh` / `.ps1` |
| Откатиться если что-то сломалось | `./setup/rollback.sh` / `.ps1` |

Удобно в CLAUDE.md прописать команды `save` и `pull` как слова — тогда в чате можно сказать «сохрани» и Claude сам всё сделает.

---

## Частые вопросы

**А если я захочу чтобы Claude на всех машинах видел одинаковые глобальные инструкции?**
Скопируй `CLAUDE.md.template` как `CLAUDE.md` в корень **своего приватного memory-репо**. Потом настрой `~/.claude/CLAUDE.md` (Mac/Linux) или `%USERPROFILE%\.claude\CLAUDE.md` (Windows) как симлинк на эту же копию. Теперь одна правка — все машины видят.

**Что если я не хочу хранить память на GitHub?**
Можно использовать self-hosted git (Gitea / Gitlab) — скрипты не привязаны к GitHub, они просто делают `git pull`. Хост меняешь в своём remote.

**Безопасно ли хранить память в GitHub?**
Репо должен быть **приватным**. Секреты (API-ключи, токены) храни **вне** git-репо памяти — например в `~/.claude/secrets/api-keys.env`. В памяти оставляй только ссылки типа «ключ в `secrets/xxx.env`».

Подробный гайд с паттерном хранения и pre-commit hook — [docs/secrets.md](docs/secrets.md). **Поставь `hooks/pre-commit` в свой memory-репо сразу** — он ловит 15+ форматов API-ключей и отклоняет коммит если что-то утекает. Это не паранойя: история git-репо живёт вечно, даже если удалить файл.

**Windows PowerShell ругается на скрипт с кучей ошибок.**
Скрипты используют кириллицу. PowerShell 5.1 (дефолт Win10/11) без UTF-8 BOM читает `.ps1` как cp1251 — парсер падает. Скрипты в этом ките уже с BOM. Если переписываешь — сохраняй как **UTF-8 with BOM**.

**Работает ли в WSL?**
WSL2 — да, как обычный Linux. WSL1 — симлинки не пересекают границу с Windows, лучше не пытаться.

**А как на iPad / iPhone?**
На телефонах Claude Code нет — только Claude.ai в браузере (он память не видит). Если нужен доступ к своей памяти с телефона — заведи простого Telegram-бота на VPS, который будет читать файлы из своей копии репо. Скоро выпущу отдельный кит для этого — следи за обновлениями.

---

## Архитектура

Детали — в [docs/architecture.md](docs/architecture.md). FAQ по граблям — в [docs/troubleshooting.md](docs/troubleshooting.md).

---

## Лицензия

[MIT](LICENSE). Пользуйтесь, форкайте, адаптируйте под свою систему памяти. Issues и PR приветствуются.
