---
name: pr-review-toolkit
description: >-
  Multi-dimension high-signal code review for CC:Tweaked Lua changes (confidence
  >= 80 filter). USE ONLY WHEN the user asks for a code review/audit, or during
  a pre-commit / pre-PR quality check on modified .lua or harness code. NEVER
  invoke during simple chat, initial planning, mid-authoring, or doc-only edits.
---

# PR Review Toolkit (CC:Tweaked Lua Edition)

Adapted from Anthropic's `pr-review-toolkit` into a focused 5-dimension audit with strict noise filtering.

## Confidence Threshold (Anti-Nitpick Filter)

Score every candidate finding from `0` to `100` and **report ONLY findings with confidence >= 80**:
- **90–100 (Critical)**: Runtime crash (`Too long without yielding`, nil peripheral call, Lua 5.3 syntax in Lua 5.2), `prohibited-mods` violation, swallowed failure corrupting control state, broken contract.
- **80–89 (Important)**: Missing edge-case test for new branch, stale comment contradicting code logic, global `_G` leak, unguarded `pcall`.
- **< 80**: Suppress minor stylistic nitpicks.

## Five Review Dimensions

1. **Rule & Runtime Compliance (`code-reviewer`)**:
   - Check adherence to `cc-tweaked-runtime.md` (no `//` or bitwise `&|~<<>>`, no host `os.execute`/`io.popen`/`os.exit`, yield inside unbounded loops, < 200 locals) and `domain-aeronautics.md` (no VS/VS2 symbols or `kontraption:` prefix).
2. **Silent Failure Hunting (`silent-failure-hunter`)**:
   - Flag `pcall(...)` calls whose `ok, err` return values are ignored, empty fallback branches hiding peripheral disconnects, or functions returning `nil` without an error reason when callers expect a table.
3. **Test Coverage Gaps (`pr-test-analyzer`)**:
   - Identify untested branches, missing disconnect/timeout edge cases, or mocks that diverge from real CC/Avionics peripheral return shapes.
4. **Comment Accuracy (`comment-analyzer`)**:
   - Flag comments, units (deg vs rad, kN vs pN, mB vs FE), or docstrings that contradict the actual implementation.
5. **Module & Table Contract Design (`type-design-analyzer`)**:
   - Check table schema consistency, module encapsulation (`local M = {}`), and mutable state exposure across modules.

## Output Format

Group findings into **Critical (90–100)** and **Important (80–89)** with `file:line`, confidence score, concrete cause, and minimal fix. If zero issues score >= 80, state concisely what files were audited and that no high-confidence defects were found.
