# VERIFICATION

Что проверить перед финалом.

## Docs-only

```bash
git diff --check
./scripts/check-ai-context.sh .
```

## Shell scripts

```bash
bash -n setup/mac.sh
bash -n setup/linux.sh
bash -n setup/health-check.sh
bash -n setup/rollback.sh
bash -n hooks/pre-commit
```

## PowerShell

Если `pwsh` установлен:

```bash
pwsh -NoProfile -Command '$errors=$null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw setup/windows.ps1), [ref]$errors) > $null; if ($errors) { $errors; exit 1 }'
pwsh -NoProfile -Command '$errors=$null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw setup/health-check.ps1), [ref]$errors) > $null; if ($errors) { $errors; exit 1 }'
pwsh -NoProfile -Command '$errors=$null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw setup/rollback.ps1), [ref]$errors) > $null; if ($errors) { $errors; exit 1 }'
```

Если `pwsh` не установлен, не утверждай что Windows scripts проверены полностью.

## Safety checklist

- Setup scripts не запускались как побочный эффект docs-задачи.
- Реальные memory files, tokens, private paths не попали в diff.
- Public docs clearly separate this kit from user's private memory repo.
- В `SESSION_SUMMARY.md` записано, что изменилось.
