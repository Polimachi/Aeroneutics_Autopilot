---
name: ponytail
description: >-
  YAGNI and minimal-diff discipline ("lazy senior developer"): solve the whole
  task with the smallest complete code change. USE ONLY WHEN authoring new code
  (preventing speculative abstractions/wrappers) or refactoring/reviewing code
  (pruning dead or over-engineered code). NEVER invoke during simple chat, Q&A,
  /grill-me interviews, or markdown/config edits.
---

# Ponytail — Minimal Working Code Discipline

Adapted from `DietrichGebert/ponytail`. The best code is the code you never had to write.

## Role-Specific Focus

- **Authoring Mode (New Features & Fixes)**: Build the smallest version that solves the requested task completely. Add zero unrequested options, wrappers, config layers, or `"for later"` abstractions.
- **Review / Pruning Mode (Refactoring)**: Identify and delete unused helpers, pass-through wrappers, and speculative indirection. Deletion beats addition.

## Decision Ladder (Take the First Option That Works)

1. **Does it need to exist?** Skip unrequested flexibility and name skipped extras in one line if relevant.
2. **Already in this codebase?** Reuse the existing helper or module convention.
3. **Standard Lua / CraftOS built-in API?** Use native `table`, `math`, `string`, `bit32`, `textutils`, `fs` before inventing custom utilities.
4. **Already-installed project module?** Reuse it; never add new dependencies for a few lines of logic.
5. **Minimum clear code**: Write the shortest diff a human reads in one glance (a cryptic one-liner that requires decoding is not short).

## Non-Negotiable Floors (Never Cut These)

- Boundary validation, peripheral `nil`/disconnect checks, yield safety in loops, and error handling that prevents state corruption.
- Updating all callers, mocks, and tests touched by a signature change.
- If taking an intentional shortcut with a known physical/scale limit, mark it inline: `-- shortcut: <limit>, <when to upgrade>`.
