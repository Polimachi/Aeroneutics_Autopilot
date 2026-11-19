# TASK-019: Specification Lightweighting, Peer-Badge Abolition & 18-Spec Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (locked via `R5`) inside isolated worktree `.worktrees/feat-task-019-spec-hygiene`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate inline peer-spec version badge churn across all 18 active specifications, perform in-place `Extract` compression on `VAS` (`144.9 KB`), `AMM` (`116.0 KB`), and `FCP` (`115.9 KB`), resolve the 6 `Implemented`-spec message drifts plus `TASK-017/018` carryover doc drift, and expand `tools/verify_all_specs.py` to enforce 18 specs and fail on newly introduced inline peer version badges.

**Architecture:** All specification edits preserve the Permanent Unified Path invariant (`0` file moves or renames) and zero runtime code mutations (`0 diff` under `src/` and Lua test suites). Packet schema bodies duplicated between subsystem specs (`VAS §8`, `AMM §4`, `FCP §8`) and Master ICD `§3` are replaced by compact Packet Reference Matrices linking to Master ICD `§3` while retaining every canonical `MSG_*` identifier required by `tools/verify_contracts.py` and preserving node-specific runtime rules, timeouts, and FSM triggers; `verify_all_specs.py` then gains Rule 10 (table-aware `### Revision History` and Master ICD `§5.1` exempt) backed by `tests/harness/test_verify_all_specs.py` TDD.

**Tech Stack:** Markdown / GFM, Mermaid, Python 3.10+ (`unittest`, `re`, `pathlib`), `tools/verify_all_specs.py`, `tools/verify_contracts.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`, `tools/audit/specs_analysis.py`, `tools/audit/guard.py`.

**Spec:** [Architecture_Efficiency_Audit_1_11182026.md](../../../reports/underReview/Architecture_Efficiency_Audit_1_11182026.md) §3 (`E-L4-01`, `E-L4-03`, `E-L4-04`) · §4.3 · §7 (`Gate A3`/`A5`) and [TASK.md](../../../TASK.md) (`TASK-019-1`, `TASK-019-2`).

---

## Locked Rulings (Confirmed via `/grill-me` on 2026-11-20)

- **`R1` — 18-Spec Peer-Badge Abolition + Rule 10 Fail Guard + Governance Sync:**
  - Remove inline peer-spec version badges across **all 18 active specs** (including frozen `ASA_PROGRAM_SPECIFICATION.md` and deferred `DOCKING_ARM_SPECIFICATION_AND_ICD.md` documentation headers only; `src/**`, `tests/1_control/asa/**`, `config/gdrive_mapping.json` strictly `0 diff`).
  - Version SSOT rests solely in each specification's own top metadata table and Master ICD `§5.1`.
  - Add **Rule 10 (`FAIL`)** to `tools/verify_all_specs.py` rejecting any line outside `### Revision History` and Master ICD `### 5.1` that pairs a peer spec link or filename (`*.md`) with a peer version badge (`vX.Y.Z`).
  - Sync `.agent/skills/specification-lifecycle-manager/SKILL.md` and `.agent/rules/skill-workflows.md` to match single-SSOT versioning without cross-spec badge propagation.
- **`R2` — In-Place `Extract` Depth on `VAS`, `AMM`, and `FCP`:**
  - Replace redundant packet Lua dump examples and duplicated field tables in `VAS §8` (`29,480 B`, `L835-1448`), `AMM §4` (`21,127 B`, `L221-498`), and `FCP §8` (`23,435 B`, `L510-852`, sharing `819` shingles with ICD) with compact **Packet Reference Matrices** linking to [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) `§3` (`[Interface I-*]`).
  - Preserve **every canonical `MSG_*` token** required by `config/protocol_contracts.json`, every `[DEPRECATED]` badge (`[DEPRECATED]`), and all node-specific behavioral rules, channel offsets, timeouts, and FSM triggers.
  - Replace `FCP §11` pseudocode (`11,310 B`, `L964-1229`) with a brief module implementation pointer while retaining the `## 11.` and `## 12.` section numbers so existing references remain valid.
- **`R3` — `Revision History` Rollup across the 5 Large Specs:**
  - Compress `### Revision History` in `VAS` (`11,945 B`, `15` rows), `AMM` (`12,960 B`, `14` rows), `FCP` (`8,492 B`, `13` rows), Master ICD (`14,314 B`, `22` rows), and System Diagram (`13,717 B`, `22` rows) to keep only the **5 most recent version rows** (with the new `2026-11-20` `Patch +0.0.1` row at the top) plus **1 consolidated rollup row** covering earlier versions (`git log` reference).
- **`R4` — `Implemented` Spec Drift (6 Messages) + `TASK-017/018` Carryover Polish:**
  - Fix obsolete/typo 2 messages: `Diagram:504-505` (remove deprecated `MSG_ATC_RUNWAY_CLEAR` `CH 50002`, align `MSG_RUNWAY_VACATED` to `CH 50212` `U->>F` + `G->>F: MSG_ATC_FACILITY_UPDATE (CH 50202)`) and `LANDING_PAD:529` (`MSG_GAC_DEPARTURE_COMPLETE` → canonical `MSG_ATC_DEPARTURE_COMPLETE`).
  - Annotate unimplemented Tower ATC / taxiway messages with explicit `[DEFERRED: TASK-108]`: `MSG_TAXI_CMD` (`Diagram:508`, `Runway:104,304,426`, `ICD:900`) and Tower ATC messages in `GAC`/`Diagram`/`LandingPad`/`Runway` (`MSG_ATC_HANDOFF_CLEARANCE`, `MSG_ATC_ENROUTE_CHECKIN`, `MSG_ATC_ENROUTE_ACK`, `MSG_ATC_EMERGENCY_ALERT`).
  - Resolve `TASK-017/018` carryover doc drift: `ICD:1016` (`tacticalChannel` → `assignedTacticalChannel`), `ICD:1036` (`MSG_GAC_DISPATCH` add `activeSectors`), `AMM:872` (`§10.2` JSON add `"uiFrequencyHz": 5`), `GAC:248` (`sectorStatus` comment `"OPERATIONAL" | "DECK_DANGEROUS"`), `GAC:413` & `LANDING_PAD:427` (`recommendedClimbAltitude` `[DEPRECATED]`), and `VAS:56-58` stale baseline note.
- **`R5` — Uniform `Patch (+0.0.1)` Version Bump & Isolated Subagent-Driven Execution:**
  - Increment **all 18 active specifications** by `Patch (+0.0.1)`, set `최종 수정일 (Date)` to `2026-11-20`, and prepend 1 `Revision History` row per spec.
  - Because `src/**` has **`0 diff`**, all 18 specs **preserve their current `Status` (`14 Implemented, 4 Approved`)** without an `Approved` detour (`skill-workflows.md` §3).
  - Execute inside isolated git worktree `.worktrees/feat-task-019-spec-hygiene` (branch `feat/task-019-spec-hygiene` from `main`) via `superpowers:subagent-driven-development`.

---

## Global Constraints

1. **Zero Runtime / Asset Mutations:** `src/**`, `tests/0_development/**`, `tests/0_infra/**`, `tests/1_control/**`, `tests/2_guidance/**`, `tests/3_planning/**`, `tests/e2e/**`, `config/gdrive_mapping.json`, `config/audit_baselines.json`, `config/protocol_contracts.json`, and `tools/amm_mission_editor.html` MUST remain `0 diff` against `main` (`3781f0a`).
2. **Mission Editor Spec Parity Lock:** Do **NOT** alter `AMM_MISSION_EDITOR_SPECIFICATION.md` Zone 3 `20..29` references (`L63, 93, 113`); `tools/amm_mission_editor.html:1113,1649,1653` still validates `20..29` until its UI is updated separately.
3. **Permanent Unified Path:** Never move or rename any spec file; `python tools/verify_all_specs.py --check-readmes` and `python tools/verify_contracts.py --specs-only` must end with `0 Errors, 0 Warnings`.
4. **Overclaim Ban (`verify_context_docs.py` R2):** Avoid all banned unverified superlatives and absolute-assurance wording listed in `AGENTS.md` / `tools/verify_context_docs.py` (`BANNED_TERMS` & `GUARANTEE_RE`) across all edited specs, `README.md`, `GEMINI.md`, `TASK.md`, and `.agent/memory/workspace-root.md`.
5. **Windows PowerShell 5.1 Tooling:** Always run chained commands with `; if ($?) { ... }`, git via `& "C:\Program Files\Git\cmd\git.exe"`, and search via `Select-String`.
6. **Exact 18-Spec `Patch (+0.0.1)` Target Table (`Date: 2026-11-20`):**

| Spec Path | Status (Preserved) | Old Ver | New Ver | Owning Task |
| :--- | :---: | :---: | :---: | :---: |
| `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` | `Implemented` | `v2.9.0` | `v2.9.1` | Task 1 |
| `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` | `Implemented` | `v0.5.0` | `v0.5.1` | Task 1 |
| `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` | `Implemented` | `v1.3.0` | `v1.3.1` | Task 1 |
| `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` | `Implemented` | `v0.1.0` | `v0.1.1` | Task 1 |
| `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` | `Approved` | `v1.12.0` | `v1.12.1` | Task 1 |
| `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` | `Implemented` | `v1.4.0` | `v1.4.1` | Task 1 |
| `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` | `Implemented` | `v2.4.0` | `v2.4.1` | Task 1 |
| `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` | `Approved` | `v1.8.0` | `v1.8.1` | Task 1 |
| `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` | `Implemented` | `v1.15.0` | `v1.15.1` | Task 1 |
| `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` | `Implemented` | `v0.6.0` | `v0.6.1` | Task 1 |
| `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` | `Implemented` | `v1.26.0` | `v1.26.1` | Task 2 |
| `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` | `Implemented` | `v2.7.0` | `v2.7.1` | Task 3 |
| `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` | `Implemented` | `v2.6.0` | `v2.6.1` | Task 4 |
| `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` | `Implemented` | `v1.7.0` | `v1.7.1` | Task 5 |
| `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` | `Implemented` | `v2.6.0` | `v2.6.1` | Task 5 |
| `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` | `Implemented` | `v1.13.0` | `v1.13.1` | Task 5 |
| `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` | `Approved` | `v2.22.0` | `v2.22.1` | Task 5 |
| `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` | `Approved` | `v1.39.0` | `v1.39.1` | Task 5 |

---

## Review Focus

1. **`### Revision History` without `---` separator:** Five specs (`VAS:35`, `LANDING_PAD:30`, `RUNWAY:27`, `GAC:28`, `DOCKING_ARM:26`) jump directly from the Revision History Markdown table to `> **연관 문서**` / `> **연관 규격서**` without a `---` rule; stripping history via `---` / `## ` alone would swallow and blind Rule 10 on the peer-link block immediately below it. **Pinned in Task 6** via table-aware history boundary parsing and an explicit unit test.
2. **Contract Token Preservation During `Extract`:** Removing packet dumps from `VAS §8`, `AMM §4`, and `FCP §8` will fail `verify_contracts.py --specs-only` if any canonical `MSG_*` token (`38` in `VAS`, `47` in `AMM`, `21` in `FCP`) or `[DEPRECATED]` annotation is dropped. **Pinned in Tasks 2, 3, and 4** with explicit required-token checklists and `verify_contracts.py --specs-only` per task.
3. **Rule 10 Precision vs Wire/Schema Versions:** Wire envelope `ver = "1.9.5"`, mission schema `v2.0.0`, `[DEPRECATED - v1.12.0]` tokens, a spec's own header metadata/history, and Master ICD `§5.1` status table MUST pass cleanly while catching all 177 `.md`-link+version patterns (including `GPS:30-40` prose gap and `AMM_MISSION_EDITOR:43` backticked filename). **Pinned in Task 6** with positive and negative test cases.
4. **Context Doc R5/R7/R9 Coupling:** `tests/harness/test_context_docs.py` cross-checks `README.md` (`"17대"` vs `len(SPEC_FILES)` in `verify_all_specs.py`), `TASK.md` inline spec versions (`R5`), `TASK.md §3` `ARCHIVE_CAP = 10` (`R7`), and `.agent/memory/*.md` coverage (`R8`). **Pinned in Tasks 6 and 7**.
5. **Freeze & Parity Boundaries:** Changing `AMM_MISSION_EDITOR_SPECIFICATION.md` Zone 3 `20..29`, changing any spec's `Status` away from `14 Implemented, 4 Approved`, or modifying any file under `src/**` / `config/gdrive_mapping.json` violates `R5` / `Global Constraints`. **Pinned in Task 1 and Task 7** diff guard.

---

## File Structure

| Task | Owned Files (Strictly Disjoint Across Tasks) | Responsibility |
|---|---|---|
| Setup | `.worktrees/feat-task-019-spec-hygiene` (worktree only) | Isolated execution workspace branched from `main` |
| Task 1 | 10 peer specs (`ALIGNMENT`, `FDR`, `INSTALLER`, `OTA`, `DOCKING_ARM`, `GCS`, `GPS`, `ASA`, `TCA`, `AMM_MISSION_EDITOR`) + `.agent/skills/specification-lifecycle-manager/SKILL.md` + `.agent/rules/skill-workflows.md` | Remove peer badges across the 10 peer specs, bump `Patch +0.0.1`, codify single-SSOT version governance |
| Task 2 | `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` | Remove peer badges, compress `§8` via matrix + ICD `§3` ref, rollup Revision History (`5 + 1`), bump `v1.26.1` |
| Task 3 | `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` | Remove peer badges, compress `§4` via matrix + ICD `§3` ref, add `uiFrequencyHz: 5`, rollup history (`5 + 1`), bump `v2.7.1` |
| Task 4 | `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` | Remove peer badges, compress `§8` via matrix + ICD `§3` ref, replace `§11` pseudocode with pointer, rollup history (`5 + 1`), bump `v2.6.1` |
| Task 5 | `GAC`, `LANDING_PAD`, `RUNWAY`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM`, `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD` | Remove peer badges (including ICD `§1 TIP`), rollup ICD & Diagram history (`5 + 1`), fix 6 drift messages + carryover polish, sync ICD `§5.1` (`18` versions), bump `+0.0.1` |
| Task 6 | `tests/harness/test_verify_all_specs.py` (new), `tools/verify_all_specs.py`, `README.md` | TDD Rule 10 (`find_inline_peer_version_badges`) + expand `SPEC_FILES`/`REVISION_HISTORY_SPECS` to 18 specs + update `README.md` (`18대`) |
| Task 7 | `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` | Finalize context docs (`R5`/`R7`/`R8`/`R9`), measure post-`TASK-019` `audit specs`, run full verification & `0 diff` runtime guard |

---

## Pre-Execution Worktree Setup (Run at Execution Start)

- [ ] **Step 1: Record pre-`TASK-019` `audit specs` baseline & create isolated worktree**

Run in `c:\Users\sjmik\Desktop\Create_Aeroneutics`:
```powershell
python -c "from pathlib import Path; from tools.audit.specs_analysis import analyze_specs; d=analyze_specs(Path('.')); print('cochange:', d['cochange']); print('trace:', d['traceability']); print('large:', {Path(x['id']).name: x['bytes'] for x in d['documents'][:5]})"
& "C:\Program Files\Git\cmd\git.exe" worktree add .worktrees/feat-task-019-spec-hygiene -b feat/task-019-spec-hygiene
```
Expected baseline recorded (`avg_specs_per_spec_commit = 6.04`, `VAS = 144,918 B`, `AMM = 116,038 B`, `FCP = 115,930 B`, `ICD = 146,991 B`, `Diagram = 112,683 B`) and worktree created cleanly on `feat/task-019-spec-hygiene`. All subsequent Tasks 1–7 run inside `.worktrees/feat-task-019-spec-hygiene`.

---

### Task 1: Purge Peer Badges in 10 Peer Specs, Apply `R5` Patch Bump & Sync Governance Rules

**Files:**
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`L8-24, L27-38, L891`)
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`L9-25, L29-36`)
- Modify: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md` (`L8-20, L24-31`)
- Modify: `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` (`L10-25, L29-32`)
- Modify: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (`L8-24, L26-35`)
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`L8-21, L25-34`)
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`L8-13, L17-28, L30-40`)
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (`L8-23, L27-35`)
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (`L8-24, L28-40, L685`)
- Modify: `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`L8-21, L25-35, L43`)
- Modify: `.agent/skills/specification-lifecycle-manager/SKILL.md` (`L95-110, L130-138`)
- Modify: `.agent/rules/skill-workflows.md` (`L45-56`)

**Interfaces:**
- Consumes: Preserved `Status` & `Patch +0.0.1` table from `Global Constraints #6` and `R1`/`R5`.
- Produces: Zero inline peer version badges across all 10 listed specs and updated `specification-lifecycle-manager` / `skill-workflows.md` removing peer-badge propagation rules; Task 5 will sync these 10 new versions into Master ICD `§5.1`.

- [ ] **Step 1: Verify exact badge lines in the 10 Task-1 specs (read-only baseline check)**

Run:
```powershell
Select-String -Path `
  docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md, `
  docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md, `
  docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md, `
  docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md, `
  docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md, `
  docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md, `
  docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md, `
  docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md, `
  docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md, `
  docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md `
  -Pattern "\[.*v\d+\.\d+\.\d+|\(v\d+\.\d+\.\d+|v\d+\.\d+\.\d+\)"
```
Expected: Matches the peer badge lines in header reference lists (`> - ...`), `GPS:30-40`, `ALIGNMENT:891`, `TCA:685`, and `AMM_MISSION_EDITOR:43`.

- [ ] **Step 2: Strip inline peer version badges & apply `Patch +0.0.1` + `2026-11-20` + 1 Revision History row across all 10 specs**

For each of the 10 specs:
1. Keep `**문서 상태 (Status)**` unchanged (`Approved` for `DOCKING_ARM` and `ASA`; `Implemented` for the other 8).
2. Update `**문서 버전 (Version)**` per Global Constraints #6 (`ALIGNMENT v2.9.1`, `FDR v0.5.1`, `INSTALLER v1.3.1`, `OTA v0.1.1`, `DOCKING_ARM v1.12.1`, `GCS v1.4.1`, `GPS v2.4.1`, `ASA v1.8.1`, `TCA v1.15.1`, `AMM_MISSION_EDITOR v0.6.1`) and set `**최종 수정일 (Date)**` to `2026-11-20`.
3. Prepend 1 concise row at the top of `### Revision History` summarizing `TASK-019` inline peer version badge abolition (`문서 버전 SSOT를 각 문서 헤더 및 마스터 ICD §5.1로 일원화`, keeping existing rows intact on these 10 specs).
4. Remove version numbers from `> - [PEER.md](...) (...)` lists in all 10 files (e.g., `(마스터 ICD)` / `(비행 제어 코어)` without `vX.Y.Z`, and in `GPS:30-40` omit `(vX.Y.Z 동기화)`), and clean non-header peer badges:
   - `ALIGNMENT:891`: remove `v1.30.0`, `v2.15.0`, `v1.20.0`, `v1.12.0`, `v2.1.0`, `v1.8.0`, `v2.3.3` after each `[*.md](...)` link in the closing italicized note.
   - `TCA:685`: remove `v1.30.0`, `v2.0.1`, `v1.20.0`, `v2.1.0`, `v1.8.0`, `v2.7.0`, `v2.3.3`, `v2.15.0` after each `[*.md](...)` link in the closing italicized note.
   - `AMM_MISSION_EDITOR:43`: change `` `AMM_PROGRAM_SPECIFICATION.md` (`v2.5.0 Implemented`) §6·§9 `` → `` [AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md) §6·§9 `` (do **NOT** touch `"v2.0.0"` mission schema strings or Zone 3 `20..29` at `L63, L93, L113`).

- [ ] **Step 3: Sync governance rules in `.agent/skills/specification-lifecycle-manager/SKILL.md` and `.agent/rules/skill-workflows.md`**

Update both files so peer specifications are NEVER edited solely for cross-spec version badge synchronization:
- In `.agent/skills/specification-lifecycle-manager/SKILL.md`: update `L98` (`Patch +0.0.1`: remove "Cross-sync link/badge alignment" wording, state that version SSOT is each spec's top metadata table + Master ICD `§5.1`, and prohibit inline peer version badges outside `### Revision History` and Master ICD `§5.1`), `L101` (no `Revision History` or version badge churn on unaffected peer specs), and `§1`/`§3` sync wording so cross-sync checks schema/links/ICD `§5.1` instead of peer version badges.
- In `.agent/rules/skill-workflows.md`: update `L49` to remove `"또는 참조 버전 배지만 갱신된 연관 사양서"` ambiguity and explicitly state that inline peer version badges are prohibited outside `### Revision History` and Master ICD `§5.1` (`tools/verify_all_specs.py` Rule 10).

- [ ] **Step 4: Run spec & contract checks and verify zero peer badges remain in the 10 Task-1 specs**

Run:
```powershell
python tools/verify_contracts.py --specs-only; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_spec_status.py }
```
Expected: `verify_contracts.py --specs-only` exits `0` (`0 errors`), `verify_all_specs.py` reports `0 Errors, 0 Warnings`, `verify_spec_status.py` reports `[PASS] All 18 specs have valid statuses (14 Implemented, 4 Approved)!`, and a Python check for `link_re + ver_re` outside `### Revision History` hits `0` lines across all 10 specs.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md .agent/skills/specification-lifecycle-manager/SKILL.md .agent/rules/skill-workflows.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): abolish peer version badges in 10 specs and sync governance rules" }
```

---

### Task 2: In-Place `Extract` on `VAS_PROGRAM_SPECIFICATION.md` (`v1.26.0 -> v1.26.1`)

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`L8-48, L56-58, L835-1448, L1786`)

**Interfaces:**
- Consumes: `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` `§3` (`I-1..I-4`, `I-6`, `I-7`, `I-9`, `I-10`, `I-13`) and canonical packet list in `config/protocol_contracts.json` (`38` packets for `VAS`).
- Produces: `VAS_PROGRAM_SPECIFICATION.md` `v1.26.1` (`Implemented`, `2026-11-20`), target size `<= 112,000 B` (down from `144,918 B`), `0` inline peer badges, `5 + 1` Revision History rows, and 100% presence of all `38` required `MSG_*` tokens.

**Required Canonical `MSG_*` Tokens Preserved in `VAS_PROGRAM_SPECIFICATION.md` (`38` packets — all must remain present in body outside Revision History):**
- `[I-1]`: `MSG_FLIGHT_TELEMETRY`, `MSG_PBIT_REPORT`
- `[I-2]`: `MSG_ATTITUDE_CMD`, `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`
- `[I-3]`: `MSG_THRUST_CMD`, `MSG_ACTUATOR_STATUS`, `MSG_ACTUATOR_DISCOVER_REQ`, `MSG_ACTUATOR_DISCOVER_ACK`, `MSG_CALIB_PULSE`
- `[I-4]`: `MSG_CALIBRATION_INIT`, `MSG_CALIBRATION_INIT_ACK`, `MSG_CALIB_BAY_BIND`, `MSG_CALIB_START`, `MSG_PROFILE_SYNC`, `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`, `MSG_CALIB_ACK`, `MSG_CALIBRATION_CLOSE`, `MSG_CALIBRATION_CLOSE_ACK`
- `[I-6]`: `MSG_MFD_STATE`
- `[I-7]`: `MSG_NAV_QUALITY`
- `[I-9]`: `MSG_CHANNEL_REBIND`, `MSG_CHANNEL_REBIND_ACK`
- `[I-10]`: `MSG_AERO_CMD`, `MSG_AERO_STATUS`, `MSG_SURFACE_DISCOVER_REQ`, `MSG_SURFACE_DISCOVER_ACK`
- `[I-13]`: `MSG_OTA_DISCOVER_REQ`, `MSG_OTA_DISCOVER_ACK`, `MSG_OTA_BEGIN`, `MSG_OTA_CHUNK`, `MSG_OTA_COMMIT`, `MSG_OTA_ABORT`, `MSG_OTA_REBOOT`, `MSG_OTA_ACK`, `MSG_OTA_NACK`, `MSG_OTA_BOOT_STATUS`

- [ ] **Step 1: Update `VAS` metadata table, remove peer badges (`L36-45`, `L1786`), fix `L56-58` baseline note, and apply `R3` Revision History rollup**

- Metadata (`L8-11`): keep `Status = Implemented`, bump `Version = v1.26.1`, set `Date = 2026-11-20`.
- `### Revision History` (`L15-34`): prepend `v1.26.1 | 2026-11-20` row (`TASK-019`: `§8` 패킷 매트릭스·마스터 ICD `§3` 참조 치환, 연관 버전 배지 제거, 이력 롤업 압축), keep 4 preceding latest rows (`v1.26.0`, `v1.25.0`, `v1.24.0`, `v1.23.0` — total `5` latest rows), and replace `v1.22.0`..`v1.12.0` (`10` older rows) with 1 rollup row: `` | `v1.12.0 ~ v1.22.0` | `2026-11-07 ~ 2026-11-15` | **(과거 개정 이력 일괄 요약)**: 40채널 확장, `QUATERNION_RATE`·`ADVANCED_VTOL` `B†`·`telemetryDiag`·`OTA`·Wave 1 정합 누적 | 상세 이력은 `git log` 참조 | ``.
- Remove peer version badges on `L36-45` (`> - [PEER.md](...)`) and closing italic footer (`L1786`), and trim the stale `Baseline v1.19.0 -> v1.20.0` note (`L56-58`) so §1 summarizes current `v1.26.1` architecture concisely without stale `v1.20.0 Approved` phrasing.

- [ ] **Step 2: Compress `## 8. 데이터 패킷 인터페이스 명세` (`L835-1448`, `29,480 B`) into a Packet Reference Matrix + Node-Specific `VAS` Rules**

Replace the 10 repetitive JSON/Lua packet code dumps and field-by-field copies inside `L835-1448` (`8.1`..`8.10`) with:
1. A compact summary header referencing [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) `§3` (`[Interface I-1..I-13]`, 공통 엔벨로프 `ver = "1.9.5"`, Zero-Fallback).
2. One structured **VAS Wire Interface Matrix** listing every `[I-*]` subsection (`8.1`..`8.10`), channel (`Base+1/2/3/8/9/10/11`, `Base_hangar+0..5`), direction, frequency, every canonical `MSG_*` name from the `38`-packet checklist above, and explicit `[DEPRECATED]` markers (`MSG_REBIND_ACK [DEPRECATED]`, `MSG_SURFACE_CMD/STATUS [DEPRECATED]`, `Base+6/7 [DEPRECATED]`, `currentFsmState [DEPRECATED]`, etc. — verify against `verify_contracts.py`).
3. Concise bullet subsections (**`§8.1`..`§8.5` or preserved `§8.1`..`§8.10` rules**) retaining **VAS-specific behavioral contracts** (NOT duplicated wire field tables): `telemetryDiag == true` opt-in `diag`/`satFlags`, `E_STOP > MFD_ACRO > FCP` preemption + `acroTimeoutMs = 250ms` + `Base+3` ownership handoff, `MSG_CALIBRATION_INIT` `targetCraftDomain`/`targetThruster` filter, `MSG_PROFILE_SYNC` backup + `controllabilityStatus` (`"FULL_6DOF_PASS"` / `"AERO_ASSISTED_PASS"` -> `"ACCEPTED"` else `"REJECTED"`), `MSG_CALIBRATION_CLOSE(saveProfile=false)` disk + mixer rollback + `DISARMED` (`R2`/`R3`), `PBIT` 5-check summary rules (`Base+8`/`Base+2`), `peripheralManifest` topology hash & `> 5%` mass latch, `FCP_TIMEOUT` 1,500ms & `AIRBORNE_RECOVERY_HOLD` `Base+3` 5Hz fallback, `Option A` 500ms `MSG_CHANNEL_REBIND_ACK` (`status = "READY"`/`"COMMITTED"`/`"ROLLED_BACK"`/`"FAILED"`), and `[I-13]` `OTA` `DISARMED`/`BOOT`/`IDLE_ARMED` + `isAirborne ~= true` gate.

- [ ] **Step 3: Verify `VAS` byte reduction, contract completeness & spec scanner**

Run:
```powershell
python tools/verify_contracts.py --specs-only; if ($?) { python tools/verify_all_specs.py }; if ($?) { (Get-Item docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md).Length }
```
Expected: `verify_contracts.py --specs-only` exits `0` (`0 errors` — confirming all 38 `MSG_*` tokens and deprecation markers remain intact), `verify_all_specs.py` reports `0 Errors, 0 Warnings`, file size `<= 112,000 B` (saving `>= 32 KB`).

- [ ] **Step 4: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): extract VAS packet matrix and roll up revision history" }
```

---

### Task 3: In-Place `Extract` on `AMM_PROGRAM_SPECIFICATION.md` (`v2.7.0 -> v2.7.1`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`L8-48, L221-498, L806, L872`)

**Interfaces:**
- Consumes: Master ICD `§3` (`I-1`, `I-2`, `I-4`, `I-5`, `I-6`, `I-7`, `I-8`, `I-9`, `I-11`, `I-12`, `I-13`) and canonical packet list in `config/protocol_contracts.json` (`47` packets for `AMM`).
- Produces: `AMM_PROGRAM_SPECIFICATION.md` `v2.7.1` (`Implemented`, `2026-11-20`), target size `<= 92,000 B` (down from `116,038 B`), `0` inline peer badges, `5 + 1` Revision History rows, `§10.2` JSON synced (`uiFrequencyHz: 5`), and all `47` required `MSG_*` tokens preserved.

**Required Canonical `MSG_*` Tokens Preserved in `AMM_PROGRAM_SPECIFICATION.md` (`47` packets):**
- `[I-1]`: `MSG_FLIGHT_TELEMETRY`, `MSG_PBIT_REPORT`
- `[I-2]`: `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`
- `[I-4]`: `MSG_PBIT_REQ`, `MSG_PBIT_REPORT`
- `[I-5]`: `MSG_FACILITY_BEACON`, `MSG_FACILITY_STATIC_GUIDE`, `MSG_FACILITY_DYNAMIC_GUIDE`, `MSG_GAC_ABORT_CLEAR`, `MSG_GAC_CHECKIN_REQ`, `MSG_GAC_APPROACH_CLEARANCE`, `MSG_TOUCHDOWN_COMPLETE`, `MSG_ABORT_APPROACH`, `MSG_ATC_APPROACH_REQ`, `MSG_ATC_DEPARTURE_COMPLETE`, `MSG_GAC_DEPARTURE_REQ`, `MSG_GAC_DISPATCH`
- `[I-6]`: `MSG_OPERATOR_CMD`, `MSG_MISSION_CMD`, `MSG_MISSION_ACK`, `MSG_MFD_STATE`
- `[I-7]`: `MSG_GPS_REQUEST`, `MSG_GPS_RESPONSE`, `MSG_NAV_QUALITY`, `MSG_GPS_STATUS_REQ`, `MSG_GPS_STATUS_RESP`
- `[I-8]`: `MSG_BLOCK_REQUEST`, `MSG_BLOCK_ASSIGN`
- `[I-9]`: `MSG_CHANNEL_PROBE`, `MSG_CHANNEL_PROBE_ACK`, `MSG_CHANNEL_REBIND`, `MSG_CHANNEL_REBIND_ACK`
- `[I-11]`: `MSG_PAYLOAD_REQ`, `MSG_PAYLOAD_ACK`
- `[I-12]`: `MSG_TRAJECTORY_SETPOINT`, `MSG_OUTER_LOOP_STATUS`
- `[I-13]`: `MSG_OTA_DISCOVER_REQ`, `MSG_OTA_DISCOVER_ACK`, `MSG_OTA_BEGIN`, `MSG_OTA_CHUNK`, `MSG_OTA_COMMIT`, `MSG_OTA_ABORT`, `MSG_OTA_REBOOT`, `MSG_OTA_ACK`, `MSG_OTA_NACK`, `MSG_OTA_BOOT_STATUS`

- [ ] **Step 1: Update `AMM` metadata table, remove peer badges (`L15-26`, `L806`), sync `§10.2` (`L872`), and apply `R3` Revision History rollup**

- Metadata (`L8-11`): keep `Status = Implemented`, bump `Version = v2.7.1`, set `Date = 2026-11-20`.
- `### Revision History` (`L29-48`): prepend `v2.7.1 | 2026-11-20` row (`TASK-019`), retain 4 preceding latest rows (`v2.7.0`, `v2.6.0`, `v2.5.0`, `v2.4.0`), and compress `v2.3.0`..`v1.0.0` (`9` older rows) into 1 rollup row referencing `git log`.
- Remove peer version badges in `L15-26` (`> - [PEER.md](...)`) and at `L806` (`[AMM_MISSION_EDITOR_SPECIFICATION.md](AMM_MISSION_EDITOR_SPECIFICATION.md) `v0.6.0 Implemented`` → `[AMM_MISSION_EDITOR_SPECIFICATION.md](AMM_MISSION_EDITOR_SPECIFICATION.md)`).
- `R4` carryover fix at `L872` (`§10.2` `config/amm_config.json`): add `"uiFrequencyHz": 5,` right after `"loopFrequencyHz": 20,`.

- [ ] **Step 2: Compress `## 4. 패킷 스키마 및 프로토콜 규격` (`L221-498`, `21,127 B`) into an AMM Interface Reference Matrix + Gateway Rules**

Replace duplicated Lua packet dumps in `L221-498` (`§4.1`..`§4.7`) with:
1. Header referencing [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) `§3` (`ver = "1.9.5"`, Zero-Fallback).
2. Structured **AMM Packet Reference Matrix** mapping `§4.1`..`§4.7` (`[I-1, I-2, I-4, I-5, I-6, I-7, I-8, I-9, I-11, I-12, I-13]`) with channel (`Base+0/2/3/4/5/8/9/20..39`, `CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base_hangar+4/+5`), every canonical `MSG_*` name from the `47`-packet checklist above, and required `[DEPRECATED]` markers (`emergencyAction [DEPRECATED]`, `10045 [DEPRECATED]`, `MSG_ATC_ABORT_CLEAR [DEPRECATED]`, etc.).
3. Concise **AMM-Specific Behavioral Rules** bullets retaining: `Base+0` single ingress & `GCS_OVERRIDE` > `PILOT_PRIMARY` arbitration (`MSG_OPERATOR_CMD`, `MSG_MISSION_CMD` `"CONFIRM"`/`"LOAD"`/`"RUN"` + `PRECONDITION_FAILED`), `Zone 3 Base+20..39` dynamic payload bus + `BASE_PLUS_5_INFRA_RESPONSES` strict allowlist (`14` legacy keys pruned; `MSG_DOCK_CAPTURE_STAGE` & `MSG_UMBILICAL_STATUS` kept), `PBIT` `FAIL` takeoff interlock (`R2`), `MSG_GAC_APPROACH_CLEARANCE` `status == "DIVERT"` + `divertChannel` switch (`R3`), `Base+3` 5Hz downlink yield (`MFD_ACRO`/`AIRBORNE_RECOVERY_HOLD` + `acroRecoveryHoldMs = 300ms`), `Base+8` `MSG_PBIT_REQ` / `Base+9` `E_STOP` wiring, and GPS phase dispersion (`computerId % interval`) + `nav_engine` DR bounds.

- [ ] **Step 3: Verify `AMM` byte reduction, contract completeness & spec scanner**

Run:
```powershell
python tools/verify_contracts.py --specs-only; if ($?) { python tools/verify_all_specs.py }; if ($?) { (Get-Item docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md).Length }
```
Expected: `verify_contracts.py --specs-only` exits `0` (`0 errors` — confirming all 47 `MSG_*` tokens remain intact), `verify_all_specs.py` reports `0 Errors, 0 Warnings`, file size `<= 92,000 B` (saving `>= 24 KB`).

- [ ] **Step 4: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): extract AMM packet matrix, sync uiFrequencyHz, and roll up history" }
```

---

### Task 4: In-Place `Extract` on `FCP_PROGRAM_SPECIFICATION.md` (`v2.6.0 -> v2.6.1`)

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`L8-50, L510-852, L964-1229, L1309`)

**Interfaces:**
- Consumes: Master ICD `§3` (`I-1`, `I-2`, `I-7`, `I-9`, `I-12`, `I-13`), `config/protocol_contracts.json` (`21` packets for `FCP`), and `src/2_guidance/fcp/` module layout.
- Produces: `FCP_PROGRAM_SPECIFICATION.md` `v2.6.1` (`Implemented`, `2026-11-20`), target size `<= 80,000 B` (down from `115,930 B`), `0` inline peer badges, `5 + 1` Revision History rows, `§11` pseudocode replaced by concise module pointer (`L964-1229`), and all `21` required `MSG_*` tokens preserved.

**Required Canonical `MSG_*` Tokens Preserved in `FCP_PROGRAM_SPECIFICATION.md` (`21` packets):**
- `[I-1]`: `MSG_FLIGHT_TELEMETRY`
- `[I-2]`: `MSG_ATTITUDE_CMD`, `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`
- `[I-7]`: `MSG_NAV_QUALITY`
- `[I-9]`: `MSG_CHANNEL_PROBE`, `MSG_CHANNEL_PROBE_ACK`, `MSG_CHANNEL_REBIND`, `MSG_CHANNEL_REBIND_ACK`
- `[I-12]`: `MSG_TRAJECTORY_SETPOINT`, `MSG_OUTER_LOOP_STATUS`
- `[I-13]`: `MSG_OTA_DISCOVER_REQ`, `MSG_OTA_DISCOVER_ACK`, `MSG_OTA_BEGIN`, `MSG_OTA_CHUNK`, `MSG_OTA_COMMIT`, `MSG_OTA_ABORT`, `MSG_OTA_REBOOT`, `MSG_OTA_ACK`, `MSG_OTA_NACK`, `MSG_OTA_BOOT_STATUS`

- [ ] **Step 1: Update `FCP` metadata table, remove peer badges (`L15-28`, `L1309`), and apply `R3` Revision History rollup**

- Metadata (`L8-11`): keep `Status = Implemented`, bump `Version = v2.6.1`, set `Date = 2026-11-20`.
- `### Revision History` (`L31-48`): prepend `v2.6.1 | 2026-11-20` row (`TASK-019`), retain 4 preceding latest rows (`v2.6.0`, `v2.5.0`, `v2.4.0`, `v2.3.0`), and compress `v2.2.0`..`v1.0.0` (`8` older rows) into 1 rollup row referencing `git log`.
- Remove peer version badges in `L15-28` (`> - [PEER.md](...)`) and closing italic footer (`L1309`).

- [ ] **Step 2: Compress `## 8. 통신 패킷 규격 및 인터페이스 제어 명세` (`L510-852`, `23,435 B`) into an FCP Interface Reference Matrix**

Replace the duplicated field tables and Lua dumps in `L510-852` (`§8.1`..`§8.4`) with:
1. Reference to [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) `§3` (`ver = "1.9.5"`, single `top` modem 4 flight channels `Base+4/+2/+1/+9` + `[I-13]` OTA `Base_hangar+4/+5`).
2. Compact **FCP Packet Reference Matrix** covering `§8.1`..`§8.3` (`21` canonical `MSG_*` packets listed above, including `MSG_OUTER_LOOP_STATUS.coreTelemetryTimedOut` optional key) plus preserved `§8.4 [DEPRECATED — Migrated to AMM]` condensed table keeping every required `[DEPRECATED]` annotation (`Base+6/7 [DEPRECATED]`, `MSG_REBIND_ACK [DEPRECATED]`, `CH_NAV_SENSOR [DEPRECATED]`, `angleTargets`/`targetThrottle`/`targetClimbRate` `[DEPRECATED]`).
3. Concise **FCP Control/Timeout/Failover Rules** retaining `state_propagator` velocity integration, `navStale` (`500ms`), `coreTelemetryTimeoutMs` (`500ms` integrator freeze without forcing `EMERGENCY_HOLD`), `AMM_TIMEOUT_HOLD` (`500ms` -> `10s` -> `EMERGENCY_LAND`, `18°` bank hold vs `75°` `emergencyMaxBankDeg`), `PASSIVE_TRACKING` `2.0s` bumpless ramp, `HOLD_LEVEL` 1,500ms DR holdover, `rebindAckTimeoutMs` 500ms cascade, and `Base+9` `EMERGENCY_HOLD` transition.

- [ ] **Step 3: Replace `## 11. 핵심 모듈별 의사코드` (`L964-1229`, `11,310 B`) per `R2` while preserving `## 11.` & `## 12.` anchors**

Replace the 266 lines of Lua pseudocode (`§11.1`–`§11.4`) inside `L964-1229` with a concise 15-line **Implementation Module Map** table pointing directly to `src/2_guidance/fcp/main.lua`, `modules/state_propagator.lua`, `modules/outer_loop_controller.lua`, `modules/flight_fsm.lua`, `modules/network_manager.lua`, and `modules/ui_renderer.lua` plus their key entrypoints and invariants (referencing `§4`, `§5`, `§6`, `§7` where exact formulas and FSM transitions live). Keep `## 12. 검증 및 시뮬레이션 프로토콜` intact.

- [ ] **Step 4: Verify `FCP` byte reduction, contract completeness & spec scanner**

Run:
```powershell
python tools/verify_contracts.py --specs-only; if ($?) { python tools/verify_all_specs.py }; if ($?) { (Get-Item docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md).Length }
```
Expected: `verify_contracts.py --specs-only` exits `0` (`0 errors` — confirming all 21 `MSG_*` tokens and deprecation hygiene pass), `verify_all_specs.py` reports `0 Errors, 0 Warnings`, file size `<= 80,000 B` (saving `>= 36 KB`).

- [ ] **Step 5: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): extract FCP packet matrix, prune §11 pseudocode, and roll up history" }
```

---

### Task 5: Purge Remaining Peer Badges, Fix `R4` Spec Drifts, Roll Up `ICD`/`Diagram` History & Sync `ICD §5.1` (`5` Specs)

**Files:**
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`L8-37, L122, L248, L255-268, L413, L498-505, L563, L632-633, L693`)
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (`L8-39, L427, L489, L529-532`)
- Modify: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (`L8-36, L104, L304-319, L390, L426`)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`L8-60, L292, L460, L504-508`)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`L8-43, L50-63, L872-875, L900, L1016, L1036, L1193, L1689-1706`)

**Interfaces:**
- Consumes: All 18 new `+0.0.1` versions from `Global Constraints #6` and Tasks 1–4.
- Produces: Zero inline peer badges across the final 5 specs (leaving **all 18 specs at `0` Rule 10 violations**), resolved `R4` drifts, `5 + 1` Revision History rollups on `ICD` & `Diagram`, and synchronized `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md §5.1` (`L1689-1706`) with all 18 updated `vX.Y.Z` versions (`14 Implemented, 4 Approved`).

- [ ] **Step 1: Update `GAC`, `LANDING_PAD`, and `RUNWAY` specs (`R1`, `R4`, `R5`)**

1. **All 3 files**: bump metadata `Version` (`GAC v1.7.1`, `LANDING_PAD v2.6.1`, `RUNWAY v1.13.1`), set `Date = 2026-11-20`, preserve `Status = Implemented`, prepend 1 `Revision History` row (`TASK-019`), and strip peer version badges from `> - [PEER.md](...)` lines (`GAC:29-37`, `LANDING_PAD:31-39`, `RUNWAY:28-36`).
2. **`GAC` (`R4`)**:
   - `L248`: change `sectorStatus = "OPERATIONAL" -- "OPERATIONAL", "DECK_DANGEROUS", "MAINTENANCE"` comment to `-- "OPERATIONAL" | "DECK_DANGEROUS"` (matching enum contract).
   - `L413`: annotate `recommendedClimbAltitude = 100.0` with `-- [DEPRECATED]`.
   - Annotate `[DEFERRED: TASK-108]` explicitly on unimplemented Tower ATC items: `L122` (`MSG_ATC_HANDOFF_CLEARANCE` `[DEFERRED: TASK-108]`), `L255` heading (`MSG_ATC_HANDOFF_CLEARANCE` `[DEFERRED: TASK-108]`), `L498` (`MSG_ATC_ENROUTE_CHECKIN` `[DEFERRED: TASK-108]`), `L563`, `L632-633` (`MSG_ATC_ENROUTE_CHECKIN`, `MSG_ATC_ENROUTE_ACK` `[DEFERRED: TASK-108]`), and `L693` (`MSG_ATC_EMERGENCY_ALERT` `[DEFERRED: TASK-108]`). *(Keep all canonical token spellings verbatim for `verify_contracts.py` compatibility.)*
3. **`LANDING_PAD` (`R4`)**:
   - `L529`: replace `A->>GAC: MSG_GAC_DEPARTURE_COMPLETE (CH 50201)` with `A->>GAC: MSG_ATC_DEPARTURE_COMPLETE (CH 50201)` (matching `src/0_infra/gac/modules/gac_fsm.lua:333` & `protocol_contracts.json:1178`).
   - `L427`: annotate `recommendedClimbAltitude = 100.0 -- [DEPRECATED] 안전 복행 권장 고도 (m)`.
   - `L489`: annotate `MSG_ATC_HANDOFF_CLEARANCE` `[DEFERRED: TASK-108]` note right above/in the Tower ATC step.
4. **`RUNWAY` (`R4`)**:
   - Annotate `MSG_TAXI_CMD` as `[DEFERRED: TASK-108]` at `L104`, `L304`, and `L426` (and note `[DEFERRED: TASK-108]` on `L390` `MSG_ATC_HANDOFF_CLEARANCE` Mermaid interaction).

- [ ] **Step 2: Update `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.22.0 -> v2.22.1`)**

1. Metadata (`L8-10`): keep `Status = Approved`, bump `Version = v2.22.1`, set `Date = 2026-11-20`.
2. `### Revision History` (`L15-41`): prepend `v2.22.1 | 2026-11-20` row (`TASK-019`), retain 4 preceding latest rows (`v2.22.0`, `v2.21.0`, `v2.20.1`, `v2.20.0`), and collapse `v2.19.0`..`v2.7.0` (`17` older rows) into 1 summary rollup row referencing `git log`.
3. `> **연관 규격서**` (`L42-59`): strip all `( ... vX.Y.Z)` peer version badges.
4. Drift fixes (`R4`):
   - `L504-505`: change `U->>A: MSG_RUNWAY_VACATED (CH 50001)` + deprecated `A->>F: MSG_ATC_RUNWAY_CLEAR (CH 50002)` to `U->>F: MSG_RUNWAY_VACATED (CH 50212) [exitTaxiway, runwayCleared: true]` and `G->>F: MSG_ATC_FACILITY_UPDATE (CH 50202) [facilityId: RWY_01, status: FREE]` (do NOT leave an unannotated raw `MSG_ATC_RUNWAY_CLEAR`!).
   - `L292`, `L460`, `L506`, `L508`: tag `MSG_ATC_HANDOFF_CLEARANCE` and `MSG_TAXI_CMD` `[DEFERRED: TASK-108]`.

- [ ] **Step 3: Update `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.39.0 -> v1.39.1`)**

1. Metadata (`L8-10`): keep `Status = Approved`, bump `Version = v1.39.1`, set `Date = 2026-11-20`.
2. `### Revision History` (`L15-42`): prepend `v1.39.1 | 2026-11-20` row (`TASK-019`), retain 4 preceding latest rows (`v1.39.0`, `v1.38.0`, `v1.37.0`, `v1.36.0`), and compress `v1.35.0`..`v1.11.0` (`17` older rows) into 1 summary rollup row referencing `git log`.
3. Strip **all 18** inline peer version badges outside `§5.1`:
   - `L50-63` (`> [!TIP]` block): remove `(vX.Y.Z)` from all 13 linked program bullets (also clean the stale `(구 Base+7 [DEPRECATED])` cleanly per deprecation rules).
   - `L872-875`: remove `v1.7.0 - `, `v2.6.0 - `, `v1.13.0 - `, `v1.12.0 - ` prefixes inside the `[TIP]` facility links.
   - `L1193`: remove `(v2.4.0)` after `[GPS_PROGRAM_SPECIFICATION_AND_ICD.md](...)`.
4. `R4` drift fixes in `§3`:
   - `L900`: annotate `MSG_TAXI_CMD` as `[DEFERRED: TASK-108]`.
   - `L1016`: change `tacticalChannel = 50211` in the `MSG_GAC_APPROACH_CLEARANCE` Lua example to `assignedTacticalChannel = 50211` (and retain legacy note if needed? No, `gac_fsm`/`facility_client` use `assignedTacticalChannel`; keep clean standard field name).
   - `L1036`: update `MSG_GAC_DISPATCH` summary description to include `activeSectors` (`활성 섹터 디렉터리 브로드캐스트 (activeSectors)`).
5. `R1`/`R5` SSOT Version Table Sync (`L1689-1706` `### 5.1`):
   - Update ALL 15 `§5.1` subsystem rows to their new `+0.0.1` versions (`AMM v2.7.1`, `FCP v2.6.1`, `VAS v1.26.1`, `TCA 클러스터 v1.15.1`, `ASA 클러스터 v1.8.1`, `Alignment v2.9.1`, `Installer v1.3.1`, `OTA v0.1.1`, `FDR v0.5.1`, `GAC v1.7.1`, `LANDING_PAD v2.6.1`, `RUNWAY v1.13.1`, `DOCKING_ARM v1.12.1`, `GCS v1.4.1`, `GPS v2.4.1`), preserving each row's exact `(Implemented)` or `(Approved)` status (`ASA` and `DOCKING_ARM` stay `(Approved)`).
   - Also check `AMM` note inside `L1691` (`WebUI 에디터 v0.6.1 (Implemented)`) — sync to `v0.6.1`!

- [ ] **Step 4: Run spec & contract checks across all 18 specs**

Run:
```powershell
python tools/verify_contracts.py --specs-only; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_spec_status.py }
```
Expected: `0 errors` in `verify_contracts.py`, `0 Errors, 0 Warnings` in `verify_all_specs.py`, and `[PASS] All 18 specs have valid statuses (14 Implemented, 4 Approved)!`. Also verify all 18 specs produce `0` hits when scanning `(md_link + ver)` outside `### Revision History` & `ICD §5.1`.

- [ ] **Step 5: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): sync ground/system specs, resolve 6-msg drift, and update ICD 5.1 SSOT" }
```

---

### Task 6: TDD Expand `tools/verify_all_specs.py` (`17 -> 18` Specs + Rule 10 Badge Guard) & Update `README.md`

**Files:**
- Create: `tests/harness/test_verify_all_specs.py`
- Modify: `tools/verify_all_specs.py` (`L16-54`, add `find_inline_peer_version_badges` & Rule 10 check in `verify_all`)
- Modify: `README.md` (`L101, L185`: `17대` → `18대`)

**Interfaces:**
- Consumes: `SPEC_FILES`, `REVISION_HISTORY_SPECS`, `verify_all(repo_root: Path, check_readmes: bool = False) -> int` in `tools/verify_all_specs.py`.
- Produces: New exported helper `find_inline_peer_version_badges(content: str, rel_path: str) -> list[tuple[int, str]]`, `18`-spec `SPEC_FILES` & `REVISION_HISTORY_SPECS` (including `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md`), Rule 10 `[FAIL]` gate inside `verify_all`, `README.md` synced to `18대`, and unit tests in `tests/harness/test_verify_all_specs.py`.

- [ ] **Step 1: Write failing unit tests in `tests/harness/test_verify_all_specs.py`**

Create `tests/harness/test_verify_all_specs.py` testing:
```python
import tempfile
import unittest
from pathlib import Path

from tools import verify_all_specs as vas
from tools.verify_spec_status import TARGET_APPROVED, TARGET_IMPLEMENTED


def _write_minimal_spec(path: Path, body: str, status: str = "Implemented", version: str = "v1.0.0") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = (
        "# Sample Spec\n\n"
        "| 항목 | 내용 |\n"
        "| :--- | :--- |\n"
        f"| **문서 상태 (Status)** | `{status}` |\n"
        f"| **문서 버전 (Version)** | `{version}` |\n"
        "| **최종 수정일 (Date)** | `2026-11-20` |\n"
        "| **구현 코드 (Source)** | `src/sample/` |\n"
        "| **주관 도메인 (Domain)** | Sample |\n\n"
        "### Revision History\n\n"
        "| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |\n"
        "| :---: | :---: | :--- | :--- |\n"
        f"| `{version}` | `2026-11-20` | `[VAS v1.26.0](peer.md)` 역사 행 허용 | 동기화 |\n\n"
        f"{body}\n"
    )
    path.write_text(content, encoding="utf-8")


class TestVerifyAllSpecsRule10(unittest.TestCase):
    def test_spec_files_and_revision_history_cover_all_18_active_specs(self) -> None:
        expected = set(TARGET_IMPLEMENTED) | set(TARGET_APPROVED)
        self.assertEqual(len(expected), 18)
        self.assertEqual(set(vas.SPEC_FILES), expected)
        self.assertEqual(set(vas.REVISION_HISTORY_SPECS), expected)
        self.assertIn("docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md", vas.SPEC_FILES)

    def test_rule10_flags_peer_badges_immediately_after_revision_history_without_divider(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_minimal_spec(
                root / "docs/specs/0_infra/gps/PEER.md",
                "> - [OTHER.md](PEER.md) 연계 (v1.38.0 동기화)\n",
            )
            text = (root / "docs/specs/0_infra/gps/PEER.md").read_text(encoding="utf-8")
            hits = vas.find_inline_peer_version_badges(text, "docs/specs/0_infra/gps/PEER.md")
            self.assertEqual(len(hits), 1)
            self.assertIn("v1.38.0", hits[0][1])

    def test_rule10_flags_all_inline_badge_variants(self) -> None:
        sample_body = (
            "> - **[FCP.md](FCP.md)** (v2.6.0)\n"
            "> - [AMM.md](AMM.md) (임무 관리자 v2.7.0)\n"
            "> - `VAS_PROGRAM_SPECIFICATION.md` (`v1.26.0` 참조)\n"
            "*참고: ([TCA.md](TCA.md) v1.15.0)*\n"
        )
        hits = vas.find_inline_peer_version_badges(
            "### Revision History\n\n| v |\n|---|\n| `v1.0.0` | x | y | z |\n\n" + sample_body,
            "docs/specs/1_control/vas/VAS.md",
        )
        self.assertEqual(len(hits), 4)

    def test_rule10_allows_icd_section_5_1_and_wire_or_schema_versions(self) -> None:
        icd_body = (
            "## 1. 개요\n"
            "공통 엔벨로프 `ver = \"1.9.5\"`, 미션 스키마 `v2.0.0`, 구 `Base+6 [DEPRECATED - v1.12.0]`.\n"
            "> - [VAS.md](../specs/1_control/vas/VAS.md) (비행 제어 코어)\n\n"
            "### 5.1 온보드 및 인프라 프로그램 사양·구현 현황\n"
            "| 프로그램 명 | 사양 버전 / 상태 |\n"
            "| :--- | :---: |\n"
            "| [VAS.md](../specs/1_control/vas/VAS.md) | `v1.26.1` (`Implemented`) |\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md"
            _write_minimal_spec(p, icd_body, status="Approved", version="v1.39.1")
            hits = vas.find_inline_peer_version_badges(
                p.read_text(encoding="utf-8"),
                "docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md",
            )
            self.assertEqual(hits, [])

    def test_repository_all_18_specs_and_readmes_pass(self) -> None:
        self.assertEqual(vas.verify_all(vas.REPO_ROOT, check_readmes=True), 0)
```

- [ ] **Step 2: Run new unit test to verify Red failure**

Run:
```powershell
python -m unittest tests/harness/test_verify_all_specs.py -v
```
Expected: **FAIL** with `AttributeError: module 'tools.verify_all_specs' has no attribute 'find_inline_peer_version_badges'` and `17 != 18`.

- [ ] **Step 3: Implement `18`-spec lists + Rule 10 in `tools/verify_all_specs.py` and sync `README.md`**

1. In `tools/verify_all_specs.py`:
   - Add `'docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md'` to `SPEC_FILES` and `REVISION_HISTORY_SPECS` (`18` items each).
   - Add `find_inline_peer_version_badges(content: str, rel_path: str) -> list[tuple[int, str]]`:
     - Track `in_rev` with `rev_saw_table` so Revision History ends cleanly as soon as a non-table line appears after table rows (even with zero blank lines and zero `---` before `> **연관 문서**`), as well as at `---`, `## `, or another `### `.
     - When `rel_path.replace("\\", "/") == "docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md"`, exempt lines inside `### 5.1` until the next `---`, `## `, or `### `.
     - Flag any remaining non-Revision-History, non-§5.1 line containing BOTH a peer `.md` reference (`\[[^\]]+\.md\]\([^)]+\.md(?:#[^)]*)?\)` OR `` `[A-Z0-9_]+\.md` ``) AND a version token (`\bv\d+\.\d+\.\d+\b`, excluding `[DEPRECATED[^]]*v\d+\.\d+\.\d+` annotations).
   - Add **Check #10 (Rule 10)** in `verify_all`: call `find_inline_peer_version_badges(content, rel_path)`; print `[FAIL]` + up to 5 sample lines and add to `total_errors` if non-empty, else `[PASS] Peer version badge hygiene clean (zero inline peer badges)`.
2. In `README.md`:
   - `L101`: `# 17대 사양서 전수 무결성 검증기` → `# 18대 사양서 전수 무결성 검증기`.
   - `L185`: `17대 활성 사양서(\`AMM_MISSION_EDITOR_SPECIFICATION.md\` 제외 — 에디터는 \`test_amm_mission_editor.py\`로 검증)` → `18대 활성 사양서 전수` (`check_readme_spec_and_e2e_counts` R9 compares this against `len(SPEC_FILES)`).

- [ ] **Step 4: Run `test_verify_all_specs.py`, `test_context_docs.py` (R9 check) & `verify_all_specs.py --check-readmes`**

Run:
```powershell
python -m unittest tests/harness/test_verify_all_specs.py tests/harness/test_tools_integrity.py -v; if ($?) { python tools/verify_all_specs.py --check-readmes }
```
Expected: `test_verify_all_specs.py` & `test_tools_integrity.py` **PASS**, `verify_all_specs.py --check-readmes` outputs `Inspecting 18 active specifications...` and **`SCAN RESULT: ALL 18 SPECS 100% CLEAN (0 Errors, 0 Warnings)`**.

- [ ] **Step 5: Commit Task 6**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/harness/test_verify_all_specs.py tools/verify_all_specs.py README.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(task-019): enforce 18 specs and zero inline peer badges in verify_all_specs" }
```

---

### Task 7: Sync Context Docs (`TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md`), Measure `audit specs` Improvement & Run Full Gate Sweep

**Files:**
- Modify: `TASK.md` (`L4-5, L25-30, L103, L113, L122, L146, L149, L151, L179-229`)
- Modify: `GEMINI.md` (`L5-10, L21, L37-38`)
- Modify: `.agent/memory/workspace-root.md` (prepend `2026-11-20` `TASK-019` entry below `---`)

**Interfaces:**
- Consumes: Final spec versions (`+0.0.1` on all 18 specs), new `verify_all_specs` (`18 specs`), measured post-`TASK-019` `audit specs` numbers, and full harness test count (`unittest discover -s tests/harness`).
- Produces: Synchronized `TASK.md` (`R5`, `R6`, `R7` 10-item §3 cap), `GEMINI.md` (`<= 80` lines, exact 4 `## ` sections), `.agent/memory/workspace-root.md` (`R8`), and complete `TASK-019` verification proof with `0 diff` on frozen paths.

- [ ] **Step 1: Measure post-`TASK-019` `audit specs` & run harness unit discovery first so exact verified metrics go into context docs**

Run:
```powershell
python -c "from pathlib import Path; from tools.audit.specs_analysis import analyze_specs; d=analyze_specs(Path('.')); print('cochange:', d['cochange']); print('trace:', d['traceability']['spec_msg_total'], d['traceability']['in_contracts'], len(d['traceability']['spec_only_msgs']), d['traceability']['spec_only_msgs'][:15]); print('large:', {Path(x['id']).name: x['bytes'] for x in d['documents'][:5]})"
python -m unittest discover -s tests/harness -p "test_*.py"
```
Record exact measured byte sizes (`VAS`, `AMM`, `FCP`, `ICD`, `Diagram`) and harness test count (`157` + new `test_verify_all_specs.py` tests). Note that `TestRepositoryBaseline` in `test_context_docs.py` will fail only on `TASK.md` `R5`/`R7` until Step 2 updates `TASK.md`.

- [ ] **Step 2: Update `TASK.md`, `GEMINI.md`, and `.agent/memory/workspace-root.md`**

1. **`TASK.md`**:
   - `L4-5`: `최종 갱신일: 2026-11-20`, update `직전 완료` (`TASK-019, TASK-018, TASK-017, TASK-016, TASK-128, TASK-131, TASK-136, TASK-406, TASK-405, TASK-130`) and `활성 대기` (remove `019`).
   - `L25-30`: remove `TASK-019` from priority list & remove `- [ ] **TASK-019: ...**` active block from §1.
   - Sync all `[R5]` spec version references in `TASK-105`/`210`/`132`/`129`/`104`/`108`/`401` (`L103-151`: `TCA v1.15.1`, `ALIGNMENT v2.9.1`, `ASA v1.8.1`, `VAS v1.26.1`, `FCP v2.6.1`, `AMM v2.7.1`, `DOCKING_ARM v1.12.1`, `ICD v1.39.1`, `Diagram v2.22.1`, keeping statuses unchanged).
   - `§3` (`L179-229`): prepend `- [x] **TASK-019: ...** (완료일: 2026-11-20)` at the top of §3 citing `docs/superpowers/plans/2026-11-20-task-019-spec-lightweighting-and-sync-cost.md`, `R1~R5`, measured byte reductions, Rule 10, `18대` specs, and verified gate outputs; delete the oldest entry (`TASK-125`, `L226-229`) so §3 keeps exact **10** entries (`ARCHIVE_CAP = 10`).
2. **`GEMINI.md`** (strictly `<= 80` lines, exact 4 `## ` headings, `18종 14 Implemented, 4 Approved PASS`):
   - `§1`: lead `직전 완료` with `TASK-019` (`18종 인라인 피어 배지 폐지·Rule 10 차단·VAS/AMM/FCP 제자리 Extract·6메시지 드리프트 해소·verify_all_specs 18종 확장; 2026-11-20`); remove `TASK-019` from `다음 액션` #2 (`TASK-140 / TASK-015`).
   - `§2`: update `amm_mission_editor.html` version `v0.6.0` → `v0.6.1 Implemented`.
   - `§3`: update `verify_all_specs.py --check-readmes` (`17대 사양서` → `18대 사양서`) and updated `tests/harness` test count matching Step 1 (`PASS`).
3. **`.agent/memory/workspace-root.md`**:
   - Prepend directly below `---`: `## 2026-11-20 — 사양 경량화·피어 배지 폐지·18종 검증 확장 (TASK-019)` documenting `R1~R5`, measured `audit specs` deltas, all 18 bumped versions, and exact verified gate counts (zero R2 overclaim terms).

- [ ] **Step 3: Commit Task 7**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md .agent/memory/workspace-root.md; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task-019): sync context docs and archive TASK-019" }
```

- [ ] **Step 4: Run Full Cross-Gate Verification & Frozen-Diff Check Against Final HEAD**

Run inside `.worktrees/feat-task-019-spec-hygiene`:
```powershell
python tools/verify_context_docs.py; if ($?) { python tools/verify_spec_status.py }; if ($?) { python tools/verify_all_specs.py --check-readmes }; if ($?) { python tools/verify_contracts.py }; if ($?) { python tools/verify_manifest_sync.py --strict-gdrive-packages }; if ($?) { python tools/verify_runtime_wiring.py }; if ($?) { python tools/validate_lua_syntax.py }; if ($?) { python -m tools.audit guard }; if ($?) { python tools/run_boot_smoke.py --clean-orphans }; if ($?) { python tools/run_unit_tests.py --require-tests --clean-orphans }; if ($?) { python tools/run_e2e_tests.py --clean-orphans --check-baseline }; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python -m unittest tests/3_planning/amm/test_amm_mission_editor.py }
```
And verify frozen `0 diff`:
```powershell
(& "C:\Program Files\Git\cmd\git.exe" diff main..HEAD -- src config/gdrive_mapping.json config/protocol_contracts.json config/audit_baselines.json tools/amm_mission_editor.html tests/0_development tests/0_infra tests/1_control tests/2_guidance tests/3_planning tests/e2e | Out-String).Trim().Length
```
Expected: EVERY verification gate exits `0` (`ALL 18 SPECS 100% CLEAN (0 Errors, 0 Warnings)`, `18 specs (14 Implemented, 4 Approved)`, `context docs: 0 findings`, `contracts 0 errors`, `guard errors=0/warnings=0`, `139/139 Lua syntax`, `13/13 boot smoke`, `656/656 unit`, `23/23 E2E / 566 packets 0 violations`, full `tests/harness` OK, `30/30` editor OK) and frozen runtime/test diff length is strictly **`0`**.

---

## Self-Review Results (per `writing-plans/SKILL.md`)

1. **Spec coverage:** `E-L4-01` (`111/210` badges & `6.04` co-change) → Tasks 1–6 + governance rules; `E-L4-03` (`6`-message drift + carryover polish) → Tasks 3 & 5; `E-L4-04` (`17 -> 18` spec verifier) → Task 6; §4.3 `Extract` (`VAS`, `AMM`, `FCP` + 5-spec `Revision History` rollup) → Tasks 2–5; `TASK-019` roadmap & `GEMINI.md` sync → Task 7. Zero unmapped items.
2. **Step scan:** Every step specifies exact target files, exact lines/sections, exact canonical `MSG_*` checklists (`38`/`47`/`21`), exact unit tests for Task 6 (`test_verify_all_specs.py`), exact verification commands, and commit messages. Zero `TBD` or open placeholders.
3. **Type & version consistency:** All 18 spec filenames and target `Patch +0.0.1` versions match verbatim across `Global Constraints #6`, Tasks 1–5, Task 5 `§5.1`, and Task 7 `TASK.md`. Preserved `14 Implemented, 4 Approved` statuses match `tools/verify_spec_status.py` exactly (`14 + 4 = 18`).
4. **Review Focus:** All 5 failure modes (`Revision History` table without `---`, `MSG_*` preservation, Rule 10 false positives, `R5`/`R7`/`R9` context-doc coupling, Mission Editor `20..29` / frozen `src/` guard) are pinned to tests/checks in Tasks 1–7.
5. **Proportion:** Concise task plan focused strictly on file boundaries, exact canonical checklists, interfaces, TDD assertions, and verification gates.
