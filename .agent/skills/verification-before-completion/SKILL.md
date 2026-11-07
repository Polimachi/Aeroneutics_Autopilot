---
name: verification-before-completion
description: >-
  Final evidence gate before claiming implementation work is complete, fixed, or
  passing. USE ONLY WHEN you have modified code, configs, or tests and are about
  to report completion, success, or create a commit/PR. NEVER invoke during
  simple conversation, Q&A, codebase exploration summaries, /grill-me interviews,
  or /plan proposal turns where no implementation claim is made.
---

# Verification Before Completion (Scoped Override)

Extracted from `Lua-Harness` with workspace scope guards so general conversation is never interrupted by unnecessary verification runs.

## The Iron Law

```text
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not executed the verification command in the current state, do not claim that code works, passes, or is fixed.

## 5-Step Gate Function

Before claiming any task completion or fix:

1. **IDENTIFY**: Determine the exact command that proves the claim (e.g., harness runner, unit test script, syntax/file check).
2. **RUN**: Execute the full command freshly against the current workspace state.
3. **READ**: Inspect full output, exit code (`0` vs non-zero), and failure counts.
4. **VERIFY**: Confirm the output directly proves the requirement:
   - If **NO**: Report actual failure status and log output honestly.
   - If **YES**: Proceed to step 5.
5. **PROMOTE SPEC (Lightweight Exception, If Applicable)**: When the verified implementation fulfills a specification in `docs/specs/approved/<subpath>.md`:
   - Move the specification file to `docs/specs/implemented/<subpath>.md` (preserving directory hierarchy).
   - Update affected relative markdown links (`approved/<subpath>` ↔ `implemented/<subpath>`) across `docs/system/*.md` and `docs/specs/{approved,implemented}/**/*.md` and re-verify markdown link integrity (`scratch/verify_all.py` if present).
   - **Scope Boundary**: This promotion involves no specification contract change; it is exempt from Mixed-Scope Hard Stop and does **not** invoke `specification-lifecycle-manager`.
6. **CLAIM**: State the result alongside concrete command output evidence.

## Red Flags — Never Say Without Fresh Evidence

- Speculative assertions: "작동할 것입니다", "아마 해결되었을 것입니다", "should pass", "seems fixed".
- Premature celebration before running checks.
- Trusting a subagent's verbal report without checking file diffs and command output.
