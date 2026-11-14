---
name: web-design-guidelines
description: Review HTML/CSS/JS UI code for Web Interface Guidelines compliance (accessibility, focus states, forms, keyboard navigation). USE ONLY WHEN auditing, reviewing, or refining tools/amm_mission_editor.html or docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md. NEVER invoke for Lua, Python, or unrelated project files.
metadata:
  author: vercel
  version: "1.0.0"
  argument-hint: <file-or-pattern>
---

> **Project Scope Lock**: This skill is strictly restricted to `tools/amm_mission_editor.html` and `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`TASK-402`). Do NOT apply to `.lua`, `.py`, or other project documents.

# Web Interface Guidelines

Review files for compliance with Web Interface Guidelines.

## How It Works

1. Read the cached local guidelines in `references/command.md` inside this skill directory (offline-safe SSOT; never inject network requests into generated HTML).
2. Read `tools/amm_mission_editor.html` (or target section in `AMM_MISSION_EDITOR_SPECIFICATION.md`).
3. Check against all applicable rules in `references/command.md` (Accessibility, Focus States, Forms, Animation, Typography, Dark Mode & Contrast).
4. Output findings in the terse `file:line` format.

## Guidelines Source

- Local cached ruleset: `.agent/skills/web-design-guidelines/references/command.md`
- Upstream origin: `https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md`
