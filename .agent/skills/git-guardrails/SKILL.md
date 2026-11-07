---
name: git-guardrails
description: >-
  Configure or customize destructive Git command blocking rules and PreToolUse
  hooks. Baseline git safety blocking is already active via skill-workflows.md.
  USE ONLY WHEN the user explicitly asks to enable, disable, test, or customize
  git safety hooks or blocked git patterns. NEVER invoke automatically during
  normal coding or git status/diff/commit operations.
---

# Git Guardrails Configuration Skill

Adapted from `mattpocock/skills@git-guardrails-claude-code` for Antigravity on Windows.

## Blocked Destructive Patterns

- `git push` (all variants including `--force` / `-f`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

## Dual Enforcement Architecture

1. **Always-On Zero-Latency Rule**: `.agent/rules/skill-workflows.md` forbids executing any pattern above without explicit user authorization.
2. **Optional Deterministic `PreToolUse` Hook**: `.agent/hooks/block_dangerous_git.py` inspects `run_command` payloads (`toolCall.args.CommandLine`) and outputs `{"decision": "deny", "reason": "..."}` when matched.

## Enabling Hardware-Level `PreToolUse` Hook (When Requested by User)

Create or merge into `.agent/hooks.json`:

```json
{
  "git-safety-gate": {
    "enabled": true,
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {
            "type": "command",
            "command": "python hooks/block_dangerous_git.py",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Verification Command

```powershell
'{"toolCall":{"name":"run_command","args":{"CommandLine":"git reset --hard"}}}' | python .agent/hooks/block_dangerous_git.py
```
Expected stdout: JSON containing `"decision": "deny"`.
