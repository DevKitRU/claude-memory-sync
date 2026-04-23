# Безопасность: как НЕ слить токены в git

Claude пишет память в git-репо. Если в одной из memory-записей окажется строка типа `API_KEY=sk-abc123...` — она уедет на GitHub и останется там навсегда (даже если потом удалишь файл — в истории коммитов она будет).

Приватный репо это не страховка:
- Любой коллаборатор увидит.
- GitHub может индексировать публичные копии (форки).
- Утечка пароля одного контрибьютора — все секреты в истории становятся доступны.
- Если случайно сделаешь репо публичным — всё сразу в паблике.

Это реальный инцидент, не гипотетика: на старой системе (до этого кита) у автора два Telegram-токена уехали в git через memory-файл, пришлось отзывать и всё ротировать.

---

## Правило

**В файлах памяти (`memory/*.md`) НЕ должно быть реальных секретов.**

Хранить можно:
- Описания *что за ключ* и *зачем нужен*: «OpenAI API key для бота ретрансляции».
- **Где** ключ лежит: `~/.claude/secrets/api-keys.env`, `1Password vault "Dev"`.
- Какой у ключа scope/назначение: `только read-only, только для метрик`.

**Нельзя:**
- Сам ключ: `sk-proj-abc123...`, `ghp_xxx...`, `xoxb-...`, `Bearer eyJhbG...`.
- Пароли в любом виде.
- Приватные ключи (SSH private, PEM).
- TLS-сертификаты содержащие приватную часть.

---

## Где хранить ключи правильно

**Рекомендация:** `~/.claude/secrets/api-keys.env` — обычный `.env`-файл, **вне** git-репо памяти.

```bash
# ~/.claude/secrets/api-keys.env
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-proj-...
GITHUB_TOKEN=ghp_...
TELEGRAM_BOT_TOKEN=123456:AAA...
```

Дополни в зависимости от ОС:

| Платформа | Разрешение | Почему |
|---|---|---|
| macOS | `chmod 600 ~/.claude/secrets/api-keys.env` | Только твой пользователь читает |
| Linux | `chmod 600 ~/.claude/secrets/api-keys.env` | То же |
| Windows | Правый клик → Свойства → Безопасность → оставить только SYSTEM + текущий пользователь | NTFS ACL |

Бэкапы — через 1Password / Bitwarden / Keychain / любой парольник. Не бэкап'ом `api-keys.env` на Dropbox.

### Альтернативы если не хочешь plain-text файл

- **1Password CLI** (`op read "op://Private/github-token/credential"`) — ключи читаются из 1Password on-demand.
- **macOS Keychain** (`security find-generic-password -a $USER -s myservice -w`).
- **Linux secret-tool** (gnome-keyring) — аналогично.
- **Bitwarden CLI** (`bw get password myservice`).

Все эти варианты решают главную задачу: **ключ никогда не попадает в файл который потенциально пушится в git**.

---

## Как Claude должен обращаться с секретами

В `CLAUDE.md` твоего приватного memory-репо (или в глобальном `~/.claude/CLAUDE.md`) пропиши:

```markdown
## Секреты

Ключи хранятся в `~/.claude/secrets/api-keys.env`. В memory-файлах (`memory/*.md`)
упоминается ТОЛЬКО *где* лежит ключ, никогда сам ключ.

Когда нужно использовать ключ в скрипте/программе — читай из env-файла:
  source ~/.claude/secrets/api-keys.env && python run.py

Если пользователь прислал новый ключ в чат — НЕ сохранять его в memory.md файлы.
Добавить в ~/.claude/secrets/api-keys.env (или соответствующий secret manager)
и в memory-файле отметить только *что ключ добавлен*, без самого значения.
```

Это особенно важно если у тебя несколько машин — Claude может «творчески» решить сохранить ключ «для удобства» в memory если инструкция нечёткая.

---

## Pre-commit hook: автоматическая защита

В комплекте кита есть `hooks/pre-commit` — скрипт который сканирует staged изменения на типичные паттерны секретов **перед** коммитом и отклоняет коммит если что-то нашёл.

### Установка

```bash
# macOS / Linux
cd <твой-memory-репо>
mkdir -p .git/hooks
cp <path-to>/claude-memory-sync/hooks/pre-commit .git/hooks/
chmod +x .git/hooks/pre-commit

# Windows (PowerShell)
cd <твой-memory-репо>
Copy-Item "<path-to>\claude-memory-sync\hooks\pre-commit" ".git\hooks\pre-commit"
# chmod не нужен на Windows — git сам сделает исполняемым
```

### Что он ловит

Regex'ы на типичные форматы:
- OpenAI: `sk-[a-zA-Z0-9]{20,}`, `sk-proj-...`
- Anthropic: `sk-ant-...`
- GitHub: `ghp_...`, `ghs_...`, `github_pat_...`
- Slack: `xox[bpoa]-...`
- Telegram: `\d{8,10}:[A-Za-z0-9_-]{35}`
- Generic: `Bearer eyJ...`, `Authorization: ...`
- AWS: `AKIA[0-9A-Z]{16}`
- SSH private key headers
- Password=/APIKey=/Token= с реальными значениями (>20 символов)

### Если нашёл — что делать

Hook выведет проблемные строки и откажет в коммите. Ты:
1. Убери секрет из файла (замени на `см. ~/.claude/secrets/api-keys.env`).
2. Проверь что ключ ещё не уехал в предыдущий коммит (`git log -S <часть_ключа>`).
3. Если уехал — **отзови ключ** в соответствующем сервисе и ротируй. История git-репо остаётся скомпрометированной даже если удалишь файл.

### Если ложное срабатывание

Если hook блокирует коммит в котором секрета на самом деле нет (например пример в доке):
```bash
git commit --no-verify -m 'docs: fix false positive'
```
Но в 99% случаев лучше перепроверить — hook работает по консервативным паттернам.

---

## .gitignore в memory-репо

Хотя твой memory-репо должен быть приватным, добавь в его `.gitignore`:

```
*.env
*.env.*
secrets/
.secrets/
.credentials/
*.pem
*.key
id_rsa*
id_ed25519*
*.pfx
*.p12
```

Это second line of defence — даже если случайно сохранил `api-keys.env` в memory-репо, git его не проиндексирует.

---

## Ротация: что делать если секрет уже уехал

Если нашёл утечку:

1. **Срочно отозви ключ** в соответствующем сервисе (Anthropic, OpenAI, GitHub, BotFather...).
2. **Создай новый ключ.**
3. Сохрани новый в `~/.claude/secrets/api-keys.env`.
4. Удали упоминание старого из всех memory-файлов. В индексе `MEMORY.md` добавь запись `feedback_<date>_leak_<service>.md` — что был инцидент, какой ключ, как предотвратить.
5. История git остаётся скомпрометированной, но хотя бы активные ключи защищены. `git filter-branch` для очистки истории работает, но GitHub кеширует — не надейся на 100% удаление.

---

## Чеклист для нового memory-репо

- [ ] `.gitignore` содержит `*.env`, `secrets/`, `*.pem`, `*.key`
- [ ] `.git/hooks/pre-commit` установлен из этого кита
- [ ] В `CLAUDE.md` прописано правило про секреты
- [ ] Ключи хранятся **вне** репо (`~/.claude/secrets/` или secret manager)
- [ ] Репо на GitHub помечен **Private**, проверено в Settings → Visibility
- [ ] 2FA включён на GitHub-аккаунте
