---
name: using-git-worktrees
description: >-
  Set up isolated git worktrees for parallel or risky feature branches. USE ONLY
  WHEN a .git repository is initialized AND starting multi-file feature work
  that requires branch isolation from the current working tree, or when the user
  explicitly requests a worktree. NEVER invoke during general chat, /plan
  drafting, routine in-place edits, simple git status/diff/commit commands, or
  when .git does not exist in the workspace.
---

# Using Git Worktrees (Scoped Override)

Workspace override ensuring worktree checks only run when `.git` exists and true workspace isolation is required.

## Step 0: Pre-Flight Guard

1. Check whether `.git` exists at the workspace root (`Test-Path .git`).
   - **If `.git` does NOT exist**: Stop immediately. Do not run git worktree commands; work in place unless the user asks to run `git init`.
2. Check if the user already asked to work directly in the current workspace root.
   - **If in-place work was requested**: Honor it and skip worktree creation.

## Step 1: Detect Existing Worktree Isolation

```powershell
$gitDir = (git rev-parse --git-dir 2>$null)
$gitCommon = (git rev-parse --git-common-dir 2>$null)
$branch = (git branch --show-current 2>$null)
```

- If `$gitDir -ne $gitCommon` (and `git rev-parse --show-superproject-working-tree` is empty), you are already inside a linked worktree. Do not create a nested worktree.

## Step 2: Consent & Creation

1. Ask the user before creating a new worktree unless explicitly requested.
2. Prefer platform subagent isolation (`invoke_subagent` with `Workspace: "branch"` or `"share"`) when delegating isolated tasks, or `git worktree add <path> -b <branch-name>` (ensuring any local worktree folder is listed in `.gitignore`).
3. Run baseline tests in the new worktree to confirm a clean starting state.
