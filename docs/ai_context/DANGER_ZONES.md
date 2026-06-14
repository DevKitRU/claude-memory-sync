# DANGER_ZONES

Куда агенту нельзя лезть без явной причины.

## Реальная память и секреты

- Не читать и не печатать реальные private memory repos.
- Не добавлять API keys, passwords, tokens, private keys или реальные `.env`.
- В docs использовать только placeholders и examples.
- `memory/` в этом repo является public template, не личной памятью пользователя.

## Setup scripts

- `setup/mac.sh`, `setup/linux.sh`, `setup/windows.ps1` меняют локальную память Claude через symlink/Junction.
- Они делают backup, merge, замену папок и настройку auto-pull.
- Не запускать setup scripts как обычную проверку на машине пользователя.
- Любые изменения setup/rollback требуют careful review и dry-run reasoning.

## Git hooks

- `hooks/pre-commit` блокирует коммит при secret-like patterns.
- Не ослаблять secret patterns без причины.
- Если добавляешь allowlist для docs examples, помечай ее явно и не разрешай реальные ключи.

## Public docs

- Не писать, что repo private, если речь о публичном DevKitRU kit.
- Не добавлять локальные пути автора, названия личных проектов, VPS/IP, tokens или incident details сверх уже обезличенной истории.
- Отделять private memory repo пользователя от public setup kit.
