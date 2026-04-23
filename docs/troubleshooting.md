# Troubleshooting

Собранные грабли с реальной установки на Mac + Windows + VPS.

## Windows

### `windows.ps1` падает с кучей `Missing closing '}'` и кракозябрами

**Симптом:** запускаешь скрипт, на выходе строки типа `Р¤Р°Р№Р»С‹` и парсер ругается на незакрытые скобки в файле где синтаксис очевидно корректный.

**Причина:** Windows PowerShell 5.1 (дефолт на Win 10 / 11) без **UTF-8 BOM** читает `.ps1` как cp1251 (русская ANSI). Кириллические байты UTF-8 превращаются в мусор, парсер спотыкается на первом же символе который стал синтаксически некорректным.

`chcp 65001` **не помогает** — проблема в том *как* PowerShell читает файл, а не как консоль выводит.

**Решение:**
- В ките все `.ps1` уже с UTF-8 BOM. Если видишь ошибку — проверь: `Get-Content -Encoding Byte file.ps1 | Select-Object -First 3` должно дать `239 187 191`.
- Если переписываешь скрипт — сохраняй как **UTF-8 with BOM**. В VS Code: правый нижний угол → `UTF-8` → `Save with Encoding` → `UTF-8 with BOM`.
- Альтернатива — перейти на PowerShell 7 (`pwsh`), он по умолчанию читает UTF-8. Но для дистрибуции лучше держать совместимость с 5.1.

### `Register-ScheduledTask` падает на `[TimeSpan]::MaxValue`

**Симптом:** при установке Task Scheduler — `XML содержит значение в неправильном формате: Duration:P99999999DT23H59M59S`.

**Причина:** XML-схема Task Scheduler ограничивает поле Days максимум 9 цифрами, а `TimeSpan.MaxValue.TotalDays ≈ 10 675 199` — 8 цифр, но формат XML Duration для MaxValue выкидывает `P99999999DT23H59M59S` который в сумме не проходит валидацию.

**Решение:** использовать разумное большое значение:
```powershell
-RepetitionDuration (New-TimeSpan -Days 3650)   # 10 лет
```
В ките уже исправлено.

### Junction создаётся, но Claude не видит память

**Симптом:** симлинк `%USERPROFILE%\.claude\projects\<...>\memory` существует и ведёт куда нужно, но Claude при старте сессии не показывает память.

**Причины/решения:**
1. **Claude запускается из неправильной рабочей директории.** Claude Code создаёт путь проекта по hash от `cwd`. Если запускаешь `claude` из `C:\Users\Ты` — это один проект, из `E:\projects\...` — другой, папки памяти у них разные. Проверь хеш в `%USERPROFILE%\.claude\projects\` — их может быть несколько.
2. **Закрытый антивирус/Defender заблокировал reparse point.** `Get-Item -Force <путь>` должен показать атрибут `ReparsePoint`. Если его нет — создай Junction заново.
3. **Файл `MEMORY.md` в репо пустой.** Claude не показывает память если индекс пуст. Добавь хотя бы одну строку.

### `Get-ScheduledTask ClaudeMemoryAutoPull` показывает `Disabled`

Windows иногда отключает задачи если «слишком часто падают». Посмотри историю:

```powershell
Get-ScheduledTaskInfo ClaudeMemoryAutoPull
```

Если `LastTaskResult -ne 0` — скорее всего git не может сделать pull (например, нужен SSH-ключ, или кончились credentials). Запусти вручную:

```powershell
cd E:\projects\<memory-repo>
git pull
```

Разберись с ошибкой git, потом:

```powershell
Enable-ScheduledTask ClaudeMemoryAutoPull
```

---

## macOS

### После `mac.sh` auto-pull не работает

**Симптом:** LaunchAgent зарегистрирован (`launchctl list | grep claude-memory`), но `git pull` не срабатывает.

**Причины:**
1. **Network.framework нужен shell env.** LaunchAgent не наследует `$PATH` — `git` может быть не найден. Решение: в plist прописать абсолютные пути (`/usr/bin/git` или `/opt/homebrew/bin/git`).
2. **LaunchAgent без `$HOME` не найдёт SSH-ключи.** Для `git@github.com:` нужен `~/.ssh/id_*`. Либо переключайся на HTTPS с токеном, либо добавь `EnvironmentVariables` в plist.

Запусти вручную и посмотри что пишет:

```bash
launchctl unload ~/Library/LaunchAgents/com.claude-memory.autopull.plist
launchctl load -w ~/Library/LaunchAgents/com.claude-memory.autopull.plist
tail -f ~/Library/Logs/claude-memory-autopull.log
```

### Симлинк сломался после миграции на новый Mac

**Симптом:** Migration Assistant перенёс профиль, но `~/.claude/projects/<...>/memory` теперь — обычная папка с старым содержимым, а не симлинк.

**Причина:** Migration Assistant копирует симлинки как плоские папки — это по дизайну, чтобы не потерять данные если симлинк вёл в никуда.

**Решение:** запусти `./setup/mac.sh` ещё раз — скрипт идемпотентен, пересоздаст симлинк.

---

## Linux / VPS

### Cron не стартует `git pull`

**Симптом:** в `~/logs/claude-memory-autopull.log` пусто, cron вроде бы настроен.

**Причины:**
1. **Cron не видит `git` из non-login shell.** В cron `$PATH` минимальный. Решение: в cron-записи использовать `/usr/bin/git` явно, или в начало команды добавить `source ~/.bashrc;`.
2. **SSH-агент не доступен в cron.** Если git использует SSH — нужен либо HTTPS-токен в credential helper, либо `SSH_AUTH_SOCK` прописан в cron env (непросто).
   - Проще: `git remote set-url origin https://oauth2:<TOKEN>@github.com/<USER>/<REPO>.git`. Токен создать на GitHub как fine-grained с доступом только к этому репо.

Проверь: `grep claude-memory-autopull /var/log/cron.log` или `journalctl -u cron --since "10 min ago"`.

### `git pull` пишет `You have divergent branches`

**Симптом:** after auto-pull lost работает, в логе — «Not possible to fast-forward, aborting».

**Причина:** локально был сделан коммит, удалённо тоже — ветви разошлись.

**Решение:** один раз руками:

```bash
cd <memory-repo>
git pull --rebase
# если конфликт — разреши вручную, git add, git rebase --continue
```

Настрой глобально чтобы не спрашивало:

```bash
git config --global pull.rebase true
```

---

## Общие

### Две машины правили одну и ту же запись — конфликт

Неизбежно при активной работе с двух машин. Решение:

1. Откатить на обоих машинах на `origin/main`.
2. Слить изменения вручную через `git merge` или переписать спорный файл.
3. Запушить один раз.

Чтобы реже сталкиваться:
- **Держи `MEMORY.md` коротким** — самые частые конфликты в нём. Объёмные записи — в отдельных файлах.
- **Не редактируй один файл одновременно с двух машин**. Привычка «сохраняй перед переходом на другую машину» решает 95% случаев.

### Память «проехала» — в репо другая версия чем локально

**Симптом:** Claude на Mac показал одну память, перезашёл в сессию — показывает старую.

**Причина:** auto-pull подтянул изменения с другой машины, которая ушла вперёд.

**Решение:** это не баг, это фича. Именно ради этого всё и настраивалось. Если конкретный файл перетёрло неправильно — откатись через `git log <file>` → `git checkout <hash> -- <file>`.

---

## Если ничего не помогает

```bash
./setup/rollback.sh    # Mac/Linux
.\setup\rollback.ps1   # Windows
```

Всё вернётся на место из бэкапа. Потом — открой issue в репо с логами, постараемся разобраться.
