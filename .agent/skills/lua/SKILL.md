---
name: lua
description: >-
  Idiomatic Lua 5.2 language patterns covering tables, metatables, modular
  design, pcall/xpcall error handling, and memory/local variable optimization.
  USE ONLY WHEN writing, refactoring, or reviewing .lua code structure, data
  models, error propagation, or loop/table performance. NEVER invoke during
  simple conversation, verbal Q&A, Python (.py) scripting, or markdown/JSON edits.
---

# Idiomatic Lua Development (`lua`)

Adapted from `mindrally/skills@lua` and aligned with CC:Tweaked's Lua 5.2 Cobalt runtime. Complements `computercraft-lua` (which covers CC/Avionics/Propulsion APIs).

## 1. Core Language Practices (Authoring & Review)

- **Local Variables First**: Prefer `local` variables and `local function` declarations over globals for speed and scope isolation (respecting Lua's 200-local and 60-upvalue limits).
- **1-Based Indexing & Tables**: Separate contiguous array sequences (`1..n`) from hash maps cleanly; avoid sparse holes (`nil` gaps) in arrays iterated with `ipairs` or `#t`.
- **Module Pattern**: Encapsulate state inside a local module table `local M = {}` and end with `return M` via `require()`, avoiding `_G` pollution.

## 2. Naming Conventions

- `snake_case` for variables, fields, and functions.
- `PascalCase` for class/prototype tables or constructors when OOP is used.
- `UPPER_SNAKE_CASE` for module constants.
- `_leading_underscore` for module-private fields or unused loop variables (`_`).

## 3. Error Handling

- Validate preconditions at module boundaries with `assert(cond, "informative message")` or explicit `nil, err` returns.
- Wrap untrusted peripheral/network calls in `pcall` or `xpcall` and **always inspect both `ok` and `err`** (never swallow failures silently).

## 4. Memory & Control-Loop Optimization

- Cache hot globals/table lookups outside tight control loops (`local abs, max = math.abs, math.max`).
- Minimize temporary table allocations inside high-frequency flight/telemetry loops; reuse state buffers where safe.
- Use metatables (`__index`) judiciously when prototype sharing clarifies design without obscuring control flow.
