---
name: test-driven-development
description: >-
  Red-Green-Refactor workflow for production code changes. USE ONLY WHEN about
  to create or edit production code files (.lua modules or established harness
  core logic) to implement a feature or bugfix. NEVER invoke during simple
  conversation, concept/API Q&A, inline chat code examples, /plan or /grill-me
  design sessions, markdown/JSON/config edits, or initial Phase 0 bootstrapping
  of the test runner itself before a runner exists.
---

# Test-Driven Development (Scoped Override)

Workspace override of global `test-driven-development` with strict negative scope guards to prevent false activation during chat, planning, or non-code tasks.

## Scope Gate (Check Before Acting)

- **STOP and DO NOT apply this skill if**:
  - You are answering a question, explaining a concept, or showing an inline snippet in chat.
  - You are in `/plan` or `/grill-me` before implementation approval.
  - You are editing documentation (`.md`), rules/skills (`.agent/`), or static configuration (`.json`, `.gitignore`).
  - No test runner exists yet in the workspace and you are bootstrapping the runner executable itself (verify the bootstrap runner via a direct smoke execution instead).

## The Iron Law (For Production Code Features & Bugfixes)

```text
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

## Red-Green-Refactor Cycle

1. **RED — Write One Minimal Failing Test**:
   - Test one clear behavior using real module interfaces (mocking CC:Tweaked peripherals via project mocks when external hardware is absent).
2. **VERIFY RED — Run and Confirm Failure**:
   - Execute the test command and confirm it fails because the feature/fix is missing (not due to syntax/path typos).
3. **GREEN — Write Minimal Passing Code**:
   - Write the simplest code that satisfies the test (`ponytail` principle: no speculative extras).
4. **VERIFY GREEN — Run Full Relevant Suite**:
   - Confirm exit code 0 and zero regressions.
5. **REFACTOR — Clean Up**:
   - Remove duplication or deep nesting while keeping tests green (invoke `code-simplifier` only if structural cleanup is needed).
