---
name: md-management
description: >-
  Manage 3-tier project context across AGENTS.md (immutable charter), GEMINI.md
  (<= 80 lines living snapshot), and .agent/memory/<dir>.md (per-directory
  historical archive). USE ONLY WHEN (1) a milestone completes that changes
  architecture, directories, standard commands, or project phase, or (2) the
  user explicitly asks to update, audit, or sync project context memory files.
  NEVER invoke during general chat, Q&A, mid-planning (/plan, /grill-me),
  specification/ICD edits (docs/system/**, docs/specs/** — owned by
  specification-lifecycle-manager), report edits (reports/**), CHANGELOG.md
  edits, or trivial changes that do not alter project structure or workflow.
---

# Project Markdown & Context Management (`md-management`)

Adapted from Anthropic's `claude-md-management` (`claude-md-improver` + `/revise-claude-md`) for Antigravity's 3-tier memory architecture. Owns **only** `AGENTS.md`, `GEMINI.md`, and `.agent/memory/*.md` (never `docs/system/`, `docs/specs/`, `reports/`, or `CHANGELOG.md`).

## 1. Three-Tier Architecture & Asymmetric Governance

Antigravity loads **both** root `AGENTS.md` and `GEMINI.md` into `<user_rules>` on every turn. Never duplicate content between them.

| Tier | File Path | Role | Update Policy |
| :--- | :--- | :--- | :--- |
| **Tier 1** | `./AGENTS.md` | Immutable Behavioral Charter (`attention-span`, `caveman` hybrid, `no-overclaim`) | **Approval Required**: Output diff and wait for explicit user approval before editing. |
| **Tier 2** | `./GEMINI.md` | Living Project Snapshot (**strictly <= 80 lines**, in-place replace only) | **Milestone Direct Sync**: Update immediately upon milestone completion; report in 1 line. |
| **Tier 3** | `./.agent/memory/<dir-slug>.md` | On-demand per-directory decision & history archive (0 always-on tokens; keeps `src/` clean for CraftOS mounts) | **Milestone Append**: Prepend newest ISO-dated entry when a directory's architecture or contract changes. |

## 2. Mode A — Milestone Context Sync (Automatic on Structural Milestones)

Run after **every TASK-ID completion** (append one `.agent/memory/<dir-slug>.md` entry whose heading contains the TASK-ID; enforced by `tools/verify_context_docs.py` rule R8). Update `GEMINI.md` only when phases, directory layout, standard CLI/harness commands, or key architectural gotchas change:

1. **Update `./GEMINI.md` (In-Place Replace, <= 80 lines)**:
   - Keep strictly the 4 fixed sections:
     1. `## 1. Current Phase & Active Handover` (current phase, just-finished milestone, next 1-3 concrete actions in <= 5 lines)
     2. `## 2. Confirmed Architecture & Paths`
     3. `## 3. Standard Commands` (copy-pasteable verified commands only)
     4. `## 4. Gotchas & Invariants` (non-obvious pitfalls only)
   - Prune superseded handover notes so total length stays at or below 80 lines.
2. **Append History to `./.agent/memory/<dir-slug>.md`**:
   - Use `workspace-root.md` for root/harness governance, or `<dir-slug>.md` (e.g., `src-flight.md`, `tools-harness.md`) for specific directories.
   - Prepend a concise entry (`## YYYY-MM-DD — <Milestone Title>`) recording *why* the decision was made and *what* shipped.
3. **Report**: Mention the context sync in a single bullet line in your completion reply.

## 3. Mode B — Quality Audit & `AGENTS.md` Revision (User Approval Mandatory)

When the user asks to audit `.md` files or modify `AGENTS.md`:

1. **Evaluate Quality (100-Point Rubric)**:
   - Commands/Workflows accuracy (20)
   - Architecture clarity (20)
   - Non-obvious gotchas captured (15)
   - Conciseness & line-cap compliance (`GEMINI.md` <= 80 lines, zero duplication with `AGENTS.md`) (15)
   - Currency against actual filesystem (15)
   - Actionability (15)
2. **Present Report & Proposed Diff First**:
   - Show scores, stale/missing items, and exact `diff` blocks before touching `AGENTS.md` or performing bulk rewrites.
3. **Apply Only After Approval**: Use `edit_file` once the user confirms.
