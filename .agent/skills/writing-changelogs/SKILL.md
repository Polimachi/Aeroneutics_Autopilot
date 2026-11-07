---
name: writing-changelogs
description: >-
  Write formal CHANGELOG.md entries, version release notes, or operator handover
  summaries. USE ONLY WHEN shipping a versioned release or when the user
  explicitly asks to write/update CHANGELOG.md or release notes. NEVER invoke
  for routine milestone context updates (use md-management instead),
  specification SemVer/Revision History updates in docs/system/** or
  docs/specs/** (use specification-lifecycle-manager instead), reports/**
  analysis documents, general chat summaries, or trivial edits across 1-3 files.
---

# Writing Changelogs (`writing-changelogs`)

Adapted from `riekelt/technical-writer@writing-changelogs`. Distinct from `md-management` (`GEMINI.md` / `.agent/memory/`) and `specification-lifecycle-manager` (`docs/system/` & `docs/specs/` SemVer / `Revision History`): `CHANGELOG.md` is exclusively for external/release-level change tracking.

## Core Rules

- **Historical Append-Only**: Never rewrite or delete past entries; prepend newest entries first with ISO dates (`YYYY-MM-DD`), grouped by version.
- **Standard Categories**: `Added` / `Changed` / `Deprecated` (state replacement & removal target) / `Fixed` / `Removed` / `Security`.
- **Breaking Changes First**: Place breaking changes above standard categories with explicit migration steps.
- **User-Visible Impact Over Diff Noise**: Present tense, active voice, clear engineering terms.

## Entry Shape

Lead with a **bold outcome statement**, then root cause, then fix with exact symbol names inline:

```markdown
- **Gimbal pitch sign inversion fixed.** `readAttitude()` mapped nose-up angles
  to negative pitch, causing pitch oscillation under climb. Inverted pitch axis
  normalization in `src/sensors/gimbal.lua`.
```

## Honesty Conventions

- Name **Known issues**, **Deferred items**, and **Deliberate omissions** explicitly when relevant.
- Distinguish **implemented** (in repo) from **verified in CraftOS-PC** from **tested in-game**. Never claim a verification level that was not executed.
