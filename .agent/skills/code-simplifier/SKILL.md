---
name: code-simplifier
description: >-
  Behavior-preserving structural cleanup for Lua code. USE ONLY WHEN (1) initial
  implementation has already passed tests (TDD Refactor step) and needs
  flattening or deduplication, or (2) the user explicitly requests refactoring
  or readability cleanup. NEVER invoke during simple chat, before/during initial
  Red-Green authoring, or on markdown/JSON files.
---

# Code Simplifier (Lua Refactoring Edition)

Adapted from Anthropic's `code-simplifier` with TypeScript/React rules removed and tailored to CC:Tweaked Lua 5.2.

## Core Principles

1. **Preserve Exact Behavior**: Never change external inputs, outputs, peripheral calls, event timing, or return contracts — only simplify internal structure.
2. **Focus Scope**: Refine only code modified in the current session unless the user explicitly asks for a broader module refactor.
3. **Clarity Over Cleverness**:
   - Flatten deeply nested `if ... then ... else` pyramids using early `return` guard clauses.
   - Avoid chained `a and b or c` idioms when `b` can legitimately evaluate to `false` or `nil` in Lua; use explicit `if/else` instead.
   - Consolidate duplicated logic into a local helper only when it genuinely improves clarity.
   - Replace vague single-letter names with descriptive `snake_case` identifiers.
   - Remove redundant comments that merely restate obvious Lua syntax while preserving all `"why"` and hardware-constraint comments.
4. **Avoid Over-Simplification**:
   - Do not merge unrelated responsibilities (e.g., sensor polling + PID math + monitor rendering) into a single monolithic function.
   - Re-run the test suite immediately after refactoring to confirm behavior is unchanged.
