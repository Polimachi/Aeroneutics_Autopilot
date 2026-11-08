# TASK-006: Tooling Migration & Subsystem Spec Links Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permanently migrate active validation scripts (`verify_all_specs.py`, `validate_lua_syntax.py`, `verify_spec_status.py`) from `scratch/` into `tools/`, enhance them with dynamic CraftOS-PC resolution and full-codebase scanning (90 Lua files), clean up obsolete one-off migration scripts, fix legacy `docs/specs/approved/...` links in `src/**/README.md`, and synchronize root documentation.

**Architecture:** Active validation tools are promoted to first-class developer tooling under `tools/` with workspace-root agnostic path resolution (`Path(__file__).resolve().parents[1]`). Dynamic Lua 5.2 syntax validation leverages `harness.unit.config.resolve_craftos_paths()` across all production Lua files in `src/` and `installer.lua`. Obsolete 2026-11-07 migration scripts in `scratch/` are safely removed, leaving `scratch/` as a designated temporary developer scratchpad with a dedicated `README.md`.

**Tech Stack:** Python 3.10+ (`unittest`, `ctypes`, `re`, `pathlib`), CraftOS-PC `lua52.dll`, CC:Tweaked Lua 5.2 Cobalt VM, Markdown link validation.

**Spec:** [TASK.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/TASK.md) lines 25–29 (`TASK-006: 검증 스크립트 정식 도구화(scratch/ → tools/) 및 하위 문서 구 경로 정리`), [GEMINI.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/GEMINI.md) Section 2 (`Confirmed Architecture & Paths`).

## Global Constraints

- Python scripts must resolve repository root dynamically via `Path(__file__).resolve().parents[1]`, permitting invocation from any working directory.
- `tools/validate_lua_syntax.py` must dynamically resolve `lua52.dll` via `harness.unit.config.resolve_craftos_paths()` with fallback to common paths, rather than a single hardcoded machine path.
- `tools/validate_lua_syntax.py` must validate all `.lua` files in `src/` and root `installer.lua` by default (90 files), returning exit code 0 on success and 1 on syntax error.
- All markdown links must use forward slashes (`/`), never Windows backslashes (`\`).
- Permanent Unified Spec Path rule: specs remain permanently at `docs/specs/<domain>/<subsystem>/` without status-based directory movement; no links may point to `docs/specs/approved/...` or `docs/specs/implemented/...`.
- Overclaim Ban (`AGENTS.md`): Zero unmeasured superlatives in docstrings, tool outputs, or commits.
- `GEMINI.md` line count must strictly remain $\le 80$ lines.

## Review Focus

1. **Invocation from arbitrary working directory**: Running `python tools/verify_all_specs.py` from outside workspace root (e.g. from `tools/` or `src/`) should successfully locate specs via relative anchor.
2. **Missing `lua52.dll` environment error handling**: If CraftOS-PC or `lua52.dll` cannot be located, `validate_lua_syntax.py` should exit with a clear, descriptive diagnostic message rather than an unhandled traceback.
3. **Markdown link target existence**: Every relative markdown link in `README.md`, `src/README.md`, and all `src/**/README.md` must resolve to an existing file on disk.
4. **Clean `scratch/` directory preservation**: Deleting obsolete one-off scripts must not break git tracking of `scratch/` (preserved via `scratch/README.md`).
5. **Python harness test coverage**: `tests/harness/test_tools_integrity.py` must verify that all tooling commands run successfully and catch broken links or syntax regressions.

---

### Task 1: Migrate & Enhance Validation Tools in `tools/` and Clean `scratch/` (`TASK-006-1A`)

**Files:**
- Create: `tools/verify_all_specs.py`
- Create: `tools/validate_lua_syntax.py`
- Create: `tools/verify_spec_status.py`
- Create: `scratch/README.md`
- Delete: `scratch/apply_0_ground_consolidation.py`
- Delete: `scratch/fix_last_6.py`
- Delete: `scratch/fix_remaining_undeprecated.py`
- Delete: `scratch/sync_all_specs_40ch.py`
- Delete: `scratch/sync_fcp_links.py`
- Delete: `scratch/sync_fcp_text_and_versions.py`
- Delete: `scratch/test_modules_smoke.py`
- Delete: `scratch/update_approved_specs.py`
- Delete: `scratch/update_codebase_fcp.py`
- Delete: `scratch/update_master_icd.py`
- Delete: `scratch/update_system_diagram.py`
- Delete: `scratch/verify_specs_40ch.py`
- Delete: `scratch/validate_lua_syntax.py`
- Delete: `scratch/verify_all_specs.py`
- Delete: `scratch/verify_spec_status.py`

**Interfaces:**
- `tools/verify_all_specs.py`: Command-line tool verifying 12 active specifications (link integrity, mermaid blocks, revision history, deprecation hygiene, base channel formula). Supports `--root` override and optional `--check-readmes`.
- `tools/validate_lua_syntax.py`: Command-line tool loading `lua52.dll` dynamically via `harness.unit.config.resolve_craftos_paths()`, scanning all `.lua` files in `src/` and `installer.lua` (or specific files if passed via CLI args).
- `tools/verify_spec_status.py`: Command-line tool asserting exact specification metadata status distribution (5 `Implemented`, 7 `Approved`).

- [ ] **Step 1: Write `tools/validate_lua_syntax.py` with dynamic DLL resolution and recursive file discovery**

Implement `tools/validate_lua_syntax.py`:
- Use `pathlib.Path` to find repo root: `REPO_ROOT = Path(__file__).resolve().parents[1]`.
- Add `sys.path.insert(0, str(REPO_ROOT))` to import `harness.unit.config.resolve_craftos_paths`.
- Locate `lua52.dll`: check `paths.lua52_dll`, environment variable `LUA52_DLL`, and common installation paths (`Antigravity_Workspace\Lua_Harness\bin\lua52.dll`, `CraftOS-PC\lua52.dll`).
- If DLL not found, print diagnostic guide and exit with code 2.
- Scan files: if `sys.argv[1:]` provided, test those files; otherwise test `sorted(REPO_ROOT.glob("src/**/*.lua")) + [REPO_ROOT / "installer.lua"]`.
- Report total count (e.g., `Total Lua files validated: 90`), list any failures, and exit with code 0 or 1.

- [ ] **Step 2: Write `tools/verify_all_specs.py` and `tools/verify_spec_status.py` with workspace-root agnostic paths**

1. In `tools/verify_all_specs.py`:
   - Anchor paths relative to `REPO_ROOT = Path(__file__).resolve().parents[1]`.
   - Keep the 12 active specification paths and revision history checks.
   - Add optional `--check-readmes` flag to validate relative links in `README.md`, `src/README.md`, and all `src/**/README.md`.
2. In `tools/verify_spec_status.py`:
   - Anchor paths relative to `REPO_ROOT`.
   - Maintain strict assertion for the 5 `Implemented` and 7 `Approved` specs.

- [ ] **Step 3: Create `scratch/README.md` and delete obsolete one-off scripts**

1. Create `scratch/README.md` explaining:
   - Purpose: Temporary developer scratchpad for disposable scripts, experimental prototypes, and ad-hoc investigations.
   - Policy: Files in `scratch/` are not production code and should not be referenced by CI or production workflows. Regular tools belong in `tools/`.
2. Remove obsolete scripts via `git rm`:
   - `scratch/apply_0_ground_consolidation.py`
   - `scratch/fix_last_6.py`
   - `scratch/fix_remaining_undeprecated.py`
   - `scratch/sync_all_specs_40ch.py`
   - `scratch/sync_fcp_links.py`
   - `scratch/sync_fcp_text_and_versions.py`
   - `scratch/test_modules_smoke.py`
   - `scratch/update_approved_specs.py`
   - `scratch/update_codebase_fcp.py`
   - `scratch/update_master_icd.py`
   - `scratch/update_system_diagram.py`
   - `scratch/verify_specs_40ch.py`
   - `scratch/validate_lua_syntax.py`
   - `scratch/verify_all_specs.py`
   - `scratch/verify_spec_status.py`

- [ ] **Step 4: Execute migrated tools and verify clean execution**

Run:
```powershell
python tools/verify_all_specs.py
python tools/verify_spec_status.py
python tools/validate_lua_syntax.py
```
Expected:
- `verify_all_specs.py`: `ALL 12 SPECS 100% CLEAN (0 Errors, 0 Warnings)`
- `verify_spec_status.py`: `All 12 specs have valid statuses (5 Implemented, 7 Approved)!`
- `validate_lua_syntax.py`: `All 90 Lua files passed Lua 5.2 compilation successfully!`

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/ scratch/
& "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(tools): migrate core verification tools from scratch to tools"
```

---

### Task 2: Subsystem Documentation Legacy Path Cleanup & Relative Link Audit (`TASK-006-2`)

**Files:**
- Modify: `src/1_control/asa/README.md`
- Modify: `src/0_infra/gac/README.md`
- Modify: `.agent/skills/verification-before-completion/SKILL.md`

**Interfaces:**
- Consumes: Permanent Unified Spec Path policy (`docs/specs/<domain>/<subsystem>/`)
- Produces: 100% clean relative markdown links across all subsystem READMEs and skill guides

- [ ] **Step 1: Fix stale `docs/specs/approved/...` links in `src/` subsystem READMEs**

1. In `src/1_control/asa/README.md`:
   - Replace `[ASA_PROGRAM_SPECIFICATION.md](../../../docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md)` with `[ASA_PROGRAM_SPECIFICATION.md](../../../docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md)`.
2. In `src/0_infra/gac/README.md`:
   - Replace `[GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../../docs/specs/approved/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md)` with `[GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../../../docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md)`.
3. In `.agent/skills/verification-before-completion/SKILL.md`:
   - Remove references to `docs/specs/{approved,implemented}/**/*.md` and replace with permanent path `docs/specs/**/*.md`. Update command reference from `scratch/` to `tools/`.

- [ ] **Step 2: Run markdown link audit across all `src/**/README.md` and root `README.md`**

Run:
```powershell
python tools/verify_all_specs.py --check-readmes
```
Expected: Zero broken relative links across all scanned markdown documents.

- [ ] **Step 3: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/1_control/asa/README.md src/0_infra/gac/README.md .agent/skills/verification-before-completion/SKILL.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs: remove legacy approved spec path remnants from subsystem readmes"
```

---

### Task 3: Harness Integrity Test, Root Documentation & Context Sync (`TASK-006-1B`)

**Files:**
- Create: `tests/harness/test_tools_integrity.py`
- Modify: `README.md`
- Modify: `GEMINI.md`
- Modify: `TASK.md`

**Interfaces:**
- Consumes: `tools/verify_all_specs.py`, `tools/validate_lua_syntax.py`, `tools/verify_spec_status.py`, `tools/run_unit_tests.py`
- Produces: Automated Python test asserting tool integrity, synchronized root documentation and living memory ($\le 80$ lines).

- [ ] **Step 1: Write `tests/harness/test_tools_integrity.py`**

Write a Python `unittest.TestCase` in `tests/harness/test_tools_integrity.py` testing:
1. `test_tools_exist_and_scratch_is_clean`:
   - Asserts `tools/verify_all_specs.py`, `tools/validate_lua_syntax.py`, `tools/verify_spec_status.py`, and `tools/run_unit_tests.py` exist.
   - Asserts no obsolete Python scripts remain tracked in `scratch/` (only `scratch/README.md` allowed).
2. `test_verify_all_specs_execution`:
   - Runs `tools/verify_all_specs.py` as a subprocess and asserts returncode 0 with 0 Errors and 0 Warnings.
3. `test_verify_spec_status_execution`:
   - Runs `tools/verify_spec_status.py` as a subprocess and asserts returncode 0 (5 Implemented, 7 Approved).
4. `test_validate_lua_syntax_execution`:
   - Runs `tools/validate_lua_syntax.py` as a subprocess and asserts returncode 0 with all files passing.
5. `test_all_subsystem_readmes_have_valid_relative_links`:
   - Scans all `README.md` files in `src/` and asserts every markdown link target resolves to an existing file on disk.

- [ ] **Step 2: Run Python harness tests to verify GREEN**

Run:
```powershell
python -m unittest tests/harness/test_tools_integrity.py -v
python -m unittest discover -s tests/harness -p "test_*.py" -v
```
Expected: All 19 harness tests PASS.

- [ ] **Step 3: Update `README.md`, `GEMINI.md`, and `TASK.md`**

1. In `README.md`:
   - Update directory tree: reflect `tools/` with full suite of validation CLI tools, and update `scratch/` description.
   - Update verification commands in Section 6: replace `scratch/` with `tools/`.
2. In `GEMINI.md`:
   - Section 1: mark `TASK-006` completed; set next active candidate to `TASK-102` (`Landing Pad`).
   - Section 2: update standard tool paths (`tools/verify_all_specs.py`, `tools/validate_lua_syntax.py`, `tools/verify_spec_status.py`).
   - Section 3: update standard verification commands.
   - Verify line count $\le 80$ lines using `(Get-Content GEMINI.md).Count`.
3. In `TASK.md`:
   - Mark `TASK-006`, `TASK-006-1`, `TASK-006-2` as completed (`[x]`).
   - Move `TASK-006` entry to `## ✅ 3. 완료된 작업 이력`.
   - Set active immediate task to `TASK-102: Landing Pad 지상 착륙 패드 제어기 구현`.

- [ ] **Step 4: Run full regression battery (`verification-before-completion`)**

Run:
```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans
python -m unittest discover -s tests/harness -p "test_*.py"
python tools/validate_lua_syntax.py
python tools/verify_all_specs.py
python tools/verify_spec_status.py
```
Expected: All 7 unit test targets PASS (71/71), all 19 harness tests PASS, all 90 Lua syntax validations PASS, all 12 specs clean.

- [ ] **Step 5: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/harness/test_tools_integrity.py README.md GEMINI.md TASK.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs: complete TASK-006 tooling migration and update root documentation"
```
