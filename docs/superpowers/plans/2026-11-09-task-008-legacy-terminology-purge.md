# TASK-008: Legacy Terminology Purge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate all legacy terminology (`VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core`, and legacy `VAC` references) from specifications, runtime code, and test suites, backed by automated regression tests in `test_terminology_guard.py` and `verify_all_specs.py`.

**Architecture:** TDD-first terminology enforcement. Add strict regular expression patterns (`(?<![A-Za-z0-9])TERM(?![A-Za-z0-9])`) to `tests/harness/test_terminology_guard.py` and `tools/verify_all_specs.py` Rule 8 (verifying Red status), systematically substitute legacy identifiers with canonical names (`VAS`, `Alignment`), and verify Green across all test suites.

**Tech Stack:** Python 3 (unittest, regex CLI tools), CC:Tweaked Lua 5.2, Markdown (GitHub Flavored).

**Spec:** `TASK.md` (TASK-008 specification and acceptance criteria), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`.

## Global Constraints

- **Zero-Tolerance Terminology**: Zero occurrences of `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core` in `docs/` (excluding plan archives), `src/`, `tests/`.
- **Word Boundary Lookaround**: Use ASCII boundary lookaround `(?<![A-Za-z0-9])` and `(?![A-Za-z0-9])` to reliably handle adjacent Korean particles (e.g. `VAS-Align은`, `VAS-Core의`).
- **No Broken Links / Unbalanced Tables**: Specification edits must preserve Markdown table structure, relative links, and Mermaid blocks.
- **Zero-Fallback**: Direct replacement without dual-key or legacy aliases.
- **Regression Integrity**: All existing unit tests (293/293), E2E scenarios (6/6), mutation tests (20/20), and harness tests (33+3=36) must pass after purge.

## Review Focus

1. **Adjacent Korean particles**: `VAS-Align은`, `VAS-Core의` failing word boundary `\b`: covered by lookaround `(?<![A-Za-z0-9])` and `(?![A-Za-z0-9])`.
2. **Test suite naming vs legacy terminology**: preserve test file name convention `test_<subsystem>_core.lua` while purging legacy hyphenated `VAS-Core` from content.
3. **Preflight BIT node identifier**: replace `result.node = "VAS_CORE"` in `src/1_control/vas/modules/preflight_bit.lua` with `"VAS"` without breaking callers.
4. **Hangar binding & simulation files**: replace `VAC-Core` / `VAC-Align` in `node_core_sim.lua` and `channel_rebind_handler.lua` with canonical `VAS` / `Alignment`.
5. **Specification Mermaid diagrams**: ensure packet labels like `VAS-Align -> VAS` or `VAS-Core` in sequence diagrams remain valid Mermaid syntax after substitution.

---

### Task 1: Regression Guard Red-State Setup

**Files:**
- Modify: `tests/harness/test_terminology_guard.py:10-68`
- Modify: `tools/verify_all_specs.py:215-240`

**Interfaces:**
- Consumes: Existing test patterns in `TestTerminologyGuard` and `verify_all_specs.py` Rule 8.
- Produces: 3 new test methods in `TestTerminologyGuard` and 4 new pattern checks in Rule 8.

- [ ] **Step 1: Write the failing tests in `tests/harness/test_terminology_guard.py`**

Add patterns and tests for `VAS-Core`, `VAS-Align`, `VAC-Align`, and `VAC-Core`:
```python
    VAS_CORE_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)
    VAS_ALIGN_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
    VAC_ALIGN_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
    VAC_CORE_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)

    def test_no_vas_core_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAS-Core 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAS_CORE_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAS-Core occurrences:\n" + "\n".join(violations[:10]))

    def test_no_vas_align_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAS-Align 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAS_ALIGN_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAS-Align occurrences:\n" + "\n".join(violations[:10]))

    def test_no_vac_align_or_core_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAC-Align 및 VAC-Core 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAC_ALIGN_PATTERN, ['.md', '.lua', '.json']))
                violations.extend(self._collect_violations(d, self.VAC_CORE_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAC-Align/VAC-Core occurrences:\n" + "\n".join(violations[:10]))
```

- [ ] **Step 2: Add legacy terminology checks to Rule 8 in `tools/verify_all_specs.py`**

In `tools/verify_all_specs.py` (Rule 8):
```python
        vas_core_pat = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)
        vas_align_pat = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
        vac_align_pat = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
        vac_core_pat = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)

        # Inside lines loop:
        if vas_core_pat.search(line):
            term_violations.append((i, 'VAS-Core', line.strip()))
        if vas_align_pat.search(line):
            term_violations.append((i, 'VAS-Align', line.strip()))
        if vac_align_pat.search(line):
            term_violations.append((i, 'VAC-Align', line.strip()))
        if vac_core_pat.search(line):
            term_violations.append((i, 'VAC-Core', line.strip()))
```

- [ ] **Step 3: Run tests to verify Red failure**

Run: `python -m unittest tests/harness/test_terminology_guard.py`
Expected: FAIL with multiple `VAS-Core`, `VAS-Align`, and `VAC-Align` violations found.

Run: `python tools/verify_all_specs.py`
Expected: FAIL with legacy terminology violations reported across specs.

- [ ] **Step 4: Commit test guards**

```bash
git add tests/harness/test_terminology_guard.py tools/verify_all_specs.py
git commit -m "test: add VAS-Core, VAS-Align, and VAC-Align terminology regression guards"
```

---

### Task 2: Runtime Codebase Purge (`src/1_control/`)

**Files:**
- Modify: `src/1_control/vas/modules/preflight_bit.lua:190`
- Modify: `src/1_control/tca/modules/channel_rebind_handler.lua:9`
- Modify: `src/1_control/tca/modules/tca_daemon.lua:28`
- Modify: `src/1_control/tca/modules/tui_dashboard.lua:88-125`
- Modify: `src/1_control/tca/node_core_sim.lua:1`

**Interfaces:**
- Consumes: Internal status strings and module header comments.
- Produces: Updated status identifiers (`result.node = "VAS"`, `VAS LINK`, `Ping VAS`).

- [ ] **Step 1: Replace legacy terms in `src/1_control/vas/modules/preflight_bit.lua`**

Line 190:
```lua
-    result.node = "VAS_CORE"
+    result.node = "VAS"
```

- [ ] **Step 2: Replace legacy terms in `src/1_control/tca/` modules and simulator**

In `src/1_control/tca/modules/channel_rebind_handler.lua:9`:
```lua
-    --- Handle dynamic hangar bay binding from VAC-Core
+    --- Handle dynamic hangar bay binding from VAS
```

In `src/1_control/tca/modules/tca_daemon.lua:28`:
```lua
-    logBuffer = { "TCA Daemon initialized", "Awaiting VAC telemetry..." }
+    logBuffer = { "TCA Daemon initialized", "Awaiting VAS telemetry..." }
```

In `src/1_control/tca/modules/tui_dashboard.lua:88, 120, 121`:
```lua
-    --- Render full TUI dashboard with VAC link status and live log stream
+    --- Render full TUI dashboard with VAS link status and live log stream

-    [7] = "[S] Setup/Profile   [D] Ping VAC   [T] Terminate",
+    [7] = "[S] Setup/Profile   [D] Ping VAS   [T] Terminate",

-    [8] = "+-- [VAC LINK LOG STREAM (LAST 5)] " .. string.rep("-", math.max(0, width - 37)) .. "+"
+    [8] = "+-- [VAS LINK LOG STREAM (LAST 5)] " .. string.rep("-", math.max(0, width - 37)) .. "+"
```

In `src/1_control/tca/node_core_sim.lua:1`:
```lua
-    -- Simulator for VAC-Core and VAC-Align (Node 0) - Raw Modem ICD v1.9.5 (v1.4.0)
+    -- Simulator for VAS and Alignment (Node 0) - Raw Modem ICD v1.9.5 (v1.4.0)
```

- [ ] **Step 3: Run syntax validation on modified files**

Run: `python tools/validate_lua_syntax.py`
Expected: PASS with 126/126 files valid.

- [ ] **Step 4: Commit runtime code changes**

```bash
git add src/1_control/vas/modules/preflight_bit.lua src/1_control/tca/modules/ src/1_control/tca/node_core_sim.lua
git commit -m "fix(control): purge legacy VAS_CORE and VAC references from runtime modules"
```

---

### Task 3: Test Suite Updates and Verification (`tests/1_control/tca/`)

**Files:**
- Modify: `tests/1_control/tca/test_tca_core.lua:359-366`

**Interfaces:**
- Consumes: TUI mock assertions and log pushes.
- Produces: Updated assertions testing `"VAS LINK NOMINAL"`.

- [ ] **Step 1: Update assertions in `tests/1_control/tca/test_tca_core.lua`**

Lines 359, 366:
```lua
-    daemon:push_log("VAC LINK NOMINAL")
+    daemon:push_log("VAS LINK NOMINAL")

-    assert_true(termMock:_contains("VAC LINK NOMINAL"))
+    assert_true(termMock:_contains("VAS LINK NOMINAL"))
```

- [ ] **Step 2: Run unit tests for TCA and VAS**

Run: `python tools/run_unit_tests.py -t 1_control/tca --clean-orphans`
Expected: PASS (31/31 passed)

Run: `python tools/run_unit_tests.py -t 1_control/vas --clean-orphans`
Expected: PASS (31/31 passed)

- [ ] **Step 3: Commit test suite changes**

```bash
git add tests/1_control/tca/test_tca_core.lua
git commit -m "test(tca): update test assertions for VAS link stream naming"
```

---

### Task 4: Specification Documents Purge

**Files:**
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`

**Interfaces:**
- Consumes: Specification text, markdown tables, Mermaid diagrams.
- Produces: Fully aligned specification text using `Alignment` and `VAS` exclusively.

- [ ] **Step 1: Purge legacy terms in `ALIGNMENT_PROGRAM_SPECIFICATION.md`**

Replace:
- `VAS-Align` -> `Alignment`
- `VAS-Core` -> `VAS`
- `VAC-Align` -> `Alignment`
- `projects/vac_align` -> `src/0_development/alignment`
- `vac_align_bundle.lua` -> `alignment_bundle.lua` (and Package ID: `alignment`)
- `vac_align_station` -> `alignment_station`

- [ ] **Step 2: Purge legacy terms in `ASA_PROGRAM_SPECIFICATION.md`**

Replace:
- `VAS-Core` -> `VAS`
- `VAS-Align` -> `Alignment`

- [ ] **Step 3: Purge legacy terms in `TCA_PROGRAM_SPECIFICATION.md`**

Replace:
- `VAS-Align` -> `Alignment`
- `VAC_TAP_Integration` -> `VAS_TCA_Integration`

- [ ] **Step 4: Purge legacy terms in `VAS_PROGRAM_SPECIFICATION.md`**

Replace:
- `VAS-Align` -> `Alignment`
- `projects/vac_core` -> `src/1_control/vas`
- `vac_core_bundle.lua` -> `vas_bundle.lua`
- `VAC_TAP_Integration` -> `VAS_TCA_Integration`

- [ ] **Step 5: Purge legacy terms in `FCP_PROGRAM_SPECIFICATION.md`**

Replace:
- `node_vac_core.lua` -> `node_vas.lua`

- [ ] **Step 6: Purge legacy terms in `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`**

Replace:
- `VAS-Core` -> `VAS`
- `VAS-Align` -> `Alignment`
- `VAC-Align` -> `Alignment`
- `vac_core` -> `vas`
- `vac_align` -> `alignment`

- [ ] **Step 7: Purge legacy terms in `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`**

Replace:
- `VAS-Core` -> `VAS`

- [ ] **Step 8: Run specification verification tool to verify Green**

Run: `python tools/verify_all_specs.py`
Expected: `SCAN RESULT: ALL 14 SPECS 100% CLEAN (0 Errors, 0 Warnings)` with zero legacy terminology violations.

- [ ] **Step 9: Commit specification changes**

```bash
git add docs/specs/ docs/system/
git commit -m "docs(specs): purge legacy VAS-Core, VAS-Align, and VAC-Align terminology across all specs"
```

---

### Task 5: Full Regression Verification and Task Tracking Sync

**Files:**
- Modify: `TASK.md`

**Interfaces:**
- Consumes: Verification commands output.
- Produces: Updated `TASK.md` marking TASK-008 as complete `[x]` and moving it to Completed Tasks Archive.

- [ ] **Step 1: Run full Python harness test suite**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: Ran 36 tests in ~3.5s, OK. All terminology tests pass.

- [ ] **Step 2: Run universal Lua unit test suite**

Run: `python tools/run_unit_tests.py --require-tests --clean-orphans`
Expected: 12 targets, 293/293 tests PASS.

- [ ] **Step 3: Run multi-node E2E simulation test suite**

Run: `python tools/run_e2e_tests.py --clean-orphans`
Expected: 6 suites, 6/6 tests PASS.

- [ ] **Step 4: Run mutation test suite**

Run: `python tools/run_mutation_tests.py`
Expected: 20/20 mutants KILLED (100.0% kill rate).

- [ ] **Step 5: Run Lua syntax validation and spec status check**

Run: `python tools/validate_lua_syntax.py`
Expected: 126/126 files PASS.

Run: `python tools/verify_spec_status.py`
Expected: 8 Implemented, 6 Approved.

- [ ] **Step 6: Update `TASK.md` status**

Update `TASK.md`:
- Mark TASK-008 subtasks TASK-008-1 through TASK-008-5 as `[x]`.
- Move TASK-008 to `## 3. 완료된 작업 이력` top position.
- Prune completed tasks archive to retain strictly the 10 most recent entries.

- [ ] **Step 7: Commit task completion**

```bash
git add TASK.md
git commit -m "chore: complete TASK-008 legacy terminology purge and regression guard"
```
