---
name: caveman
description: >-
  Manual compression mode controller (/caveman lite|full|ultra|off|status).
  Baseline concise style is already active via AGENTS.md. USE ONLY WHEN the user
  explicitly types '/caveman', 'ultracave', 'stop caveman', or asks to change
  response compression level. NEVER invoke automatically during normal turns.
---

# Caveman Compression Controller (Manual Switch)

Baseline token-efficient prose (`attention-span` × `caveman` hybrid) is already always active in `AGENTS.md` with zero skill-load overhead. Load this skill **only** when the user explicitly changes or queries `/caveman` levels.

## Mode Levels

| Command | Behavior |
| :--- | :--- |
| **`/caveman` or `/caveman full`** | Default hybrid mode in `AGENTS.md`: answer first, zero ceremony, `→` bullets, bold key terms, exact code/paths/errors. |
| **`/caveman lite`** | Relaxed brevity: concise complete sentences while keeping `→` bullets and bold highlights. |
| **`/caveman ultra` / `/ultracave`** | Maximum compression: terse telegraphic fragments for chat prose; still keep negations, numbers, paths, and code blocks exact. |
| **`/caveman off` / `normal mode`** | Suspend caveman compression for conversational explanations while still respecting `no-overclaim`. Confirm switch-off in 1 line. |
| **`/caveman status`** | Report active compression mode in 1 line without altering it. |

## Safety Invariants Across All Levels

- Never compress security warnings, irreversible action confirmations, `ask_question` prompts, source code, comments, git commits, or markdown docs/artifacts.
