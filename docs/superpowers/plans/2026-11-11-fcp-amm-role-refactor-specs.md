# FCP Role Shrink & AMM Responsibility Migration Specification Refactor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the UAFS specification suite (`docs/system/*.md` and `docs/specs/**/*.md`) so that `AMM (Node 03)` owns mission planning, operator C2, external RF gateways, ATC/GAC/facility handshakes, and GPS/DR sensor fusion, while `FCP (Node 04)` shrinks to a pure onboard `SE(3)` outer-loop controller bridging `AMM` (`Base+4`) and `VAS` (`Base+1`).

**Architecture:** Reassigns external/infra RF channels (`CH 50000~50004`, `CH 60001~60002`, `Base_sec+*`, `Base+0`, `Base+3`, `Base+5`) from `FCP` to dual-modem `AMM`, repurposes `Base+4` as `CH_TRAJECTORY_CMD` (`Interface [I-12]`) carrying `[targetPos, targetVel, feedforwardAccel, targetHeading]` plus lifecycle/nav context, normalizes `Base+1` (`Interface [I-2]`) on `QUATERNION_RATE` (`targetQuaternion`, `targetAngularRates`, `collectiveThrust`), and aligns `VAS`, `ASA`, `TCA`, and all ground/hangar peer specifications with Zero-Fallback `[DEPRECATED]` hygiene. Follows Spec-First governance: zero `src/` Lua files are modified in this specification refactor plan (`FCP` and `VAS` transition `Implemented` -> `Approved` until subsequent implementation tasks complete).

**Tech Stack:** Markdown Specifications (UTF-8, GitHub Flavored Markdown, KaTeX, Mermaid), Python 3 verification scripts (`tools/verify_all_specs.py`, `tools/verify_spec_status.py`, `tools/verify_context_docs.py`), Windows PowerShell 5.1, Git.

**Spec:** User architecture specification (`AMM -> FCP` trajectory setpoints, `FCP -> VAS` quaternion/angular-rate/collective-thrust commands, `VAS -> TCA/ASA` individual thrust/surface commands, Tower ATC & GAC migration to `AMM`) plus `/grill-me` locked design decisions `Q1`–`Q6`.

---

## Global Constraints

- **Allowed & Banned Mods (`.agent/rules/domain-aeronautics.md`)**: Only reference `CC:Tweaked`, `Create`, `Create: Aeronautics`, `Create: Avionics`, `Create: Radars`, `Create Propulsion: Simulated` (including `ion_thruster`), and `Advanced Peripherals`. Zero occurrences of `Valkyrien Skies`, `vs2`, `cc_vs`, `vs_clockwork`, `eureka`, or `kontraption:`.
- **Onboard 40-Channel Formula (`verify_all_specs.py` Rule 7)**: $Base = 10000 + (N - 1) \times 40$ ($BW = 40$, $N = 1 \sim 1000$, band `10000~49999`). Sector formula $Base_{\text{sec}} = 50001 + S \times 200$.
- **Deprecation & Terminology Hygiene (`verify_all_specs.py` Rules 5, 6, 8)**: Mark retired fields, channels, and message types (`MSG_SURFACE_CMD`, `MSG_SURFACE_STATUS`, `MSG_AERO_DISCOVER_*`, `ATTITUDE_ANGLE`, `angleTargets`, `rateTargets`, `targetClimbRate`, `targetThrottle`, `translationBias.heave`, `CH_NAV_SENSOR`, `AMM -> FCP` `MSG_OPERATOR_CMD`) explicitly with `[DEPRECATED]` (Zero-Fallback at receivers). Never write un-deprecated `Base+6`, `Base+7`, `10045`, `10040`, or banned Rule 8 tokens (`UAP`, `SAS`, `WAP`, `VAS-Core`, `VAS-Align`, `VAC-Align`, `VAC-Core`), and remove lowercase standalone `fcp`.
- **Permanent Unified Path & Link Integrity (`verify_all_specs.py` Rules 1, 2)**: Never move specs across folders; never link to uncreated Lua files (e.g., future `AMM` modules like `nav_engine.lua` or `trajectory_generator.lua` must be described in prose/tables/code blocks without broken Markdown relative links).
- **Mermaid & Metadata Integrity (`verify_all_specs.py` Rules 3, 4, 8)**: Keep balanced double quotes (`"` count % 2 == 0) in every Mermaid block; update each modified spec's top metadata table (`Status`, `Version`, `Date: 2026-11-11`) and `### Revision History` table (`| 버전 | ... | 개정 요약 |`).
- **Target Spec Status Split (`verify_spec_status.py`)**: Exactly **7 `Implemented`** (`INSTALLER`, `TCA`, `ALIGNMENT`, `GPS`, `GAC`, `LANDING_PAD`, `GCS`) and **8 `Approved`** (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD`, `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM`, `AMM`, `FCP`, `VAS`, `ASA`, `RUNWAY`, `DOCKING_ARM`).
- **No Overclaims (`AGENTS.md`)**: Never write "완벽", "무결점", "100% 보장", "이하로 보장", or unmeasured timing/completeness guarantees; replace existing overclaims in modified sections with factual mechanism descriptions or measured script outputs.
- **No Code Edits in This Plan**: Do NOT edit `src/`, `tests/`, `installer.lua`, or `manifest.lua`. Code changes belong to follow-up implementation tasks registered in Task 8.

## Review Focus

1. **Zero-Fallback & Legacy Channel Hygiene Leakage (`Rules 5/6/7/8`)**: Editing `[I-2]`, `[I-6]`, `[I-10]`, `ASA`, or `TCA` without annotating retired channels (`Base+6/7`, `10045`, `10040`, `oldBase+6/7`) or legacy packet names (`MSG_SURFACE_CMD`, `MSG_AERO_DISCOVER_*`, lowercase `fcp`) triggers `verify_all_specs.py` failures -> Explicitly fixed in Tasks 1, 2, 4, 5, 6 and swept in Task 8 Step 6.
2. **Broken Relative Links & Premature Status Skew (`Rule 1` + `verify_spec_status.py`)**: Linking from `AMM`/`FCP` specs to not-yet-written Lua files (`trajectory_generator.lua`, `nav_engine.lua`) or flipping `FCP`/`VAS` to `Approved` before updating `tools/verify_spec_status.py` breaks validation gates -> Prevented by explicit no-broken-link constraint in Tasks 3–4 and tool update in Task 8 Step 1.
3. **`TASK.md` Regex Collision (`verify_context_docs.py` R5)**: `_TASK_SPEC_REF_RE` scans all sections of `TASK.md` including Section 3 completed entries (`TASK-201` on `L125-129`); changing `FCP` to `v2.0.0 Approved` breaks R5 unless active references are updated AND archived `TASK-201` citations separate historical badge prose (`(당시 v1.16.0 Implemented)`) from backticked `.md` paths -> Explicitly handled in Task 8 Step 2 and verified by `verify_context_docs.py`.
4. **Cross-Layer Interface Schema Drift (`[I-12]`, `[I-2]`, `[I-10]`)**: Any field-name drift between `AMM Base+4` (`MSG_TRAJECTORY_SETPOINT` / `MSG_OUTER_LOOP_STATUS`), `FCP SE(3)` ($g = 11.0\text{ m/s}^2$), `VAS Base+1` (`QUATERNION_RATE`: `targetQuaternion`, `targetAngularRates`, `collectiveThrust`, `flapTarget`, `translationBias {surge, sway}`), and `ASA Base+11` (`MSG_AERO_CMD`, `MSG_AERO_STATUS`, `MSG_SURFACE_DISCOVER_*`) blocks downstream Lua implementation -> Locked via explicit `Interfaces` contracts and verbatim schema definitions across Tasks 1–6.
5. **Single-Modem & `MFD_ACRO` / 3-Tier Timeout Contention**: Dual publishers on `Base+3` during `MFD_ACRO`, missing 2.0s bumpless re-entry after `PASSIVE_TRACKING`, or inverted failsafe timeouts (`AMM` 500ms vs `VAS` 1500ms) cause HUD oscillation or abrupt drops -> Explicitly specified and cross-checked in Tasks 1, 2, 3, 4, and 5.

## File Structure

| Task | Target File(s) | Responsibility in Refactor |
| :---: | :--- | :--- |
| **1** | `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.27.0` -> `v1.28.0 Approved`) | Master SSOT contract: reallocate `[I-1..I-12]`, define `Base+4` `[I-12]`, normalize `[I-2]` `QUATERNION_RATE`, unify `[I-10]` `MSG_AERO_*`, reassign `[I-5..I-9]` to `AMM`, clean pre-existing ICD defects. |
| **2** | `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.12.1` -> `v2.13.0 Approved`) | Visual/routing topology SSOT: update 9 Mermaid diagrams, Packet Exchange Matrix, Channel Matrix (`Base+4`), 6-sequence lifecycle diagrams, and fix `BW=20`/`2000`/`Base+6/7` defects. |
| **3** | `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v1.2.0` -> `v1.3.0 Approved`) | Promote `AMM (Node 03)` to dual-modem external/C2/nav/facility/trajectory owner (`20Hz` runtime + `5Hz` TUI split), `Base+4` trajectory generator, 3-tier failsafe triggers, keep `v1.2.0` mission/editor features intact. |
| **4** | `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v1.16.0 Implemented` -> `v2.0.0 Approved`) | Shrink `FCP (Node 04)` to single-modem SE(3) outer-loop controller ($g=11.0\text{ m/s}^2$, `Base+4`/`Base+2`/`Base+1` only), 6-state FSM (`PASSIVE_TRACKING` + bumpless 2.0s ramp), deprecate C2/GPS/ATC/thruster-profile duties. |
| **5** | `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.18.0 Implemented` -> `v1.19.0 Approved`) | Normalize `VAS` `[I-2]` on `QUATERNION_RATE`, strip normal climb-PI, isolate `FCP_TIMEOUT` (1500ms) failsafe, document `[I-1]` subscriber expansion (`AMM`), mute/resume `Base+3` ACRO handoff, clean `Wap/Tap/uapCmd/reserved04` defects. |
| **6** | `ASA` (`v1.7.0 Approved`), `TCA` (`v1.11.1 Implemented`), `ALIGNMENT` (`v2.6.1 Implemented`) | Align actuator & hangar specs: fix `ASA` `10007`/`oldBase+7`/`bw=20`/`newBaseChannel+7` & FCP/AMM refs, fix `TCA` `구 Base+10`/`newBaseChannel+6`/`FCP->AMM` rebind wording, clean `ALIGNMENT` `FCP-NODE-04-4402` UUID & cross-refs. |
| **7** | `RUNWAY` (`v1.10.7 Approved`), `DOCKING_ARM` (`v1.11.2 Approved`), `GAC` (`v1.4.2 Implemented`), `LANDING_PAD` (`v2.4.3 Implemented`), `GCS` (`v1.0.2 Implemented`), `GPS` (`v2.3.1 Implemented`) | Migrate airborne endpoint terminology from `FCP (Node 04)` to `AMM (Node 03)` across all 6 infrastructure ICDs (`CH 50000~50004`, `Base_sec+*`, `CH 60001/60002`, `Base+5`, `Base+0`), preserving zero wire-protocol breakage (`GCS`/`GPS` cleanups included). |
| **8** | `tools/verify_spec_status.py`, `TASK.md`, `GEMINI.md`, `.agent/memory/workspace-root.md` | Update expected `7 Implemented, 8 Approved` manifest, complete `TASK-206` & register follow-up implementation tasks (`TASK-207~210`), sync `R5` citations and context memory, execute full static & regression verification. |

---

### Task 1: Master Interface Control Document (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` `v1.27.0 -> v1.28.0 Approved`)

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:6-41` (Metadata table, Revision History, Overview tips)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:89-150` (Section 2 Interface Matrix & Mermaid block)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:155-431` (Interface `[I-1]` telemetry & `[I-2]` normalized `QUATERNION_RATE` guidance/emergency bus)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:433, 515, 560, 613, 622` (`[I-3]`/`[I-4]` header ref & `VAC` / `FCP-NODE-04-4402` / `Base+7` hygiene)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md:813-1459` (Reassign `[I-5..I-9]` to `AMM`, unify `[I-10]` `MSG_AERO_*`, add `[I-12]` `Base+4`, update Sections 4–5 watchdog & summary tables)

**Interfaces:**
- Consumes: Architecture decisions `Q1`–`Q6` (see Global Constraints & Goal).
- Produces: Authoritative wire contracts inherited verbatim by Tasks 2–7:
  - `[I-12]` (`Base+4`, `CH_TRAJECTORY_CMD`, 20Hz/event): `AMM -> FCP` `MSG_TRAJECTORY_SETPOINT` (`arm`, `flightActive`, `flightMode`, `constraintProfile`, `targetPos`, `targetVel`, `feedforwardAccel`, `targetHeading`, `currentPos`, `navValid`, `gpsTimedOut`, `hdop`, `posEpoch`, optional `flapHint`, optional `translationBiasHint`) and `MSG_CHANNEL_REBIND`; `FCP -> AMM` `MSG_OUTER_LOOP_STATUS` (`fsmState`, `posError`, `velError`, `saturated`, `navStale`, `activeConstraintProfile`, `commandedCollectiveThrust`) and `MSG_REBIND_ACK`.
  - `[I-2]` (`Base+1`, `CH_FLIGHT_GUIDANCE`, 20Hz): `FCP -> VAS` `MSG_ATTITUDE_CMD` (`commandType = "QUATERNION_RATE"`, `targetQuaternion {w,x,y,z}`, `targetAngularRates {pitchRate,rollRate,yawRate}`, `collectiveThrust`, optional `flapTarget`, optional `translationBias {surge, sway}`); `AMM/GCS/MFD -> VAS` `MSG_EMERGENCY_OVERRIDE`; `VAS -> AMM/FCP/MFD/GCS` `MSG_EMERGENCY_ALERT`.
  - `[I-10]` (`Base+11`, `CH_SURFACE_ACTUATION`, 20Hz/event): `VAS <-> ASA` `MSG_AERO_CMD` / `MSG_AERO_STATUS` (`MSG_SURFACE_CMD` / `MSG_SURFACE_STATUS` `[DEPRECATED]`), plus `MSG_SURFACE_DISCOVER_REQ` / `MSG_SURFACE_DISCOVER_ACK`.

- [ ] **Step 1: Update Metadata, Revision History, Overview (`L6-41`), and Section 2 Interface Matrix (`L89-150`)**

Update `Version` to `v1.28.0`, `Date` to `2026-11-11`, keep `Status` `Approved`, add the `v1.28.0` Revision History row, update `L38-41` summary blurbs to list `AMM (Node 03)` (`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base+0/+2/+3/+4/+5/+20~29`), `FCP (Node 04)` (`Base+4/+2/+1` pure `SE(3)` outer-loop), and `VAS (Node 01)` (`v1.19.0`). In Section 2 (`L89-150`), update `[I-1..I-11]` owners/descriptions, add `[I-12]` (`Base+4`, `CH_TRAJECTORY_CMD`), mark `CH_NAV_SENSOR` as `[DEPRECATED]`, and redraw the Section 2 Mermaid flowchart with 4 clean layers (`AMM Node 03` -> `FCP Node 04` -> `VAS Node 01` -> `TCA/ASA`) ensuring balanced double quotes (`"` count even).

- [ ] **Step 2: Revise `[I-1]` (`L155-218`) and Normalize `[I-2]` (`L219-431`) for `QUATERNION_RATE`**

Update `[I-1]` subscribers to `FCP (Node 04)`, `AMM (Node 03)` (for `nav_engine` DR, mission conditions, fuel triggers, `MFD_ACRO` yield detection, and 5Hz HUD downsample), and `Alignment (Node 05)`. Note that `Base+2` (`MSG_FLIGHT_TELEMETRY`) preserves its existing payload fields (`orientation`, `kinematics`, `dynamics`, `energy`, `actuatorHealth`, `activeSource`) as consumed by both `FCP` and `AMM`.
In `[I-2]` (`L219-431`), rewrite the primary schema for `MSG_ATTITUDE_CMD` around `commandType = "QUATERNION_RATE"` (`targetQuaternion {w, x, y, z}`, `targetAngularRates {pitchRate, rollRate, yawRate}`, `collectiveThrust`, optional `flapTarget`, optional `translationBias {surge, sway}`, `acroActive`) plus `MFD_ACRO` `"RATE_COMMAND"` preemption (`E_STOP > MFD_ACRO > FCP`). Explicitly annotate `"ATTITUDE_ANGLE"`, `angleTargets`, `rateTargets`, `targetClimbRate`, `targetThrottle`, and `translationBias.heave` with **`[DEPRECATED]`** (Zero-Fallback: `VAS` rejects or omits legacy fields rather than dual-key parsing). Also update `L347` duplicate caption `"Lua 패킷 예시 3"` and keep `MSG_EMERGENCY_OVERRIDE` emitters (`AMM (Node 03)`, `Cockpit MFD`, `GCS`) targeting `VAS (Node 01)` directly on `Base+1`.

- [ ] **Step 3: Clean `[I-3]` / `[I-4]` Defects (`L433, 515, 560, 613, 622`)**

In `L433`, rename any ambiguous `VAC_TAP_Integration` test badge/reference safely (preserving historical context as `"VAS_TCA_Integration (구 VAC_TAP_Integration)"` or factual `"VAS/TCA 클러스터 통합 테스트"` without triggering overclaims). In `L613`, change `hardwareUuid = "FCP-NODE-04-4402"` in `[I-4]` Alignment `VAS` response to `"VAS-NODE-01-4402"` because `Alignment` binds directly to `VAS (Node 01)`. Ensure `L515`, `L560`, and `L622` keep `[DEPRECATED]` labels next to `Base + 6` / `Base + 7`.

- [ ] **Step 4: Reassign `[I-5..I-9]` (`L813-1289`) from `FCP` to `AMM`**

Update Section headings, actors, Mermaid sequence participants, and Lua example comments across `[I-5]` (`Tower ATC`, `GAC`, `Facility Swarm`, `L813-966` — including lowercase `fcp` fix on `L835-836`), `[I-6]` (`MFD / GCS <-> AMM (Base+0/+3)` & `VAS 20Hz ACRO HUD`, `L967-1116`), `[I-7]` (`AMM <-> GPS Swarm & Server`, `L1117-1165`), `[I-8]` (`AMM <-> GCS CH 50000`, `L1166-1204`), and `[I-9]` (`AMM` Probe & 2-Phase Cascade `AMM -[Base+4]-> FCP -[Base+1]-> VAS -[Base+10/11]-> TCA/ASA`, `L1205-1289`). In `[I-6]`, document that `AMM -> FCP` `MSG_OPERATOR_CMD` (`Base+0`) is **`[DEPRECATED]`** and `AMM` is sole `Base+0` command arbiter and sole 5Hz `Base+3` publisher (yielding `Base+3` whenever `VAS Base+2` reports `activeSource == "MFD_ACRO"`). Fix pre-existing ICD bugs:
- `L1123`, `L1137`, `L1144`: normalize `10005` (`Base+5`), mark `10045` `[DEPRECATED]`.
- `L1182`: `requestedBandwidth = 40` (was `20`).
- `L1195`, `L1232`, `L1255`, `L1280-1281`: verify `10080`/`10120` with `10040`/`10060 [DEPRECATED]`.
- `L1265-1266`: fix `Base_old+6`/`Base_old+7` -> `Base_old+10`/`Base_old+11 (구 Base_old+6/+7 [DEPRECATED])` and update Layer 0/1/2/3 cascade from `AMM` down to `TCA/ASA`.

- [ ] **Step 5: Unify `[I-10]` (`L1290-1380`), Verify `[I-11]` (`L1381-1417`), and Add `[I-12]` (`Base+4`) + Sections 4–5 (`L1420-1460`)**

1. In `[I-10]` (`L1290-1380`): rename primary wireless commands from `MSG_SURFACE_CMD` / `MSG_SURFACE_STATUS` to **`MSG_AERO_CMD` / `MSG_AERO_STATUS`**, keep `MSG_SURFACE_DISCOVER_REQ/ACK`, add explicit deprecation notice (`MSG_SURFACE_CMD` / `MSG_SURFACE_STATUS` `[DEPRECATED]`), and fix lowercase `fcp` on `L1332`.
2. Verify `[I-11]` (`L1381-1417`): already `AMM <-> Payload`, keep unchanged.
3. Insert new subsection **`### [Interface I-12] 궤적 세트포인트 및 외루프 상태 피드백 (AMM <-> FCP, Base+4)`** right after `[I-11]` with complete Lua tables and field definitions for `MSG_TRAJECTORY_SETPOINT` (`20Hz`, `AMM -> FCP`), `MSG_OUTER_LOOP_STATUS` (`20Hz / On-Change`, `FCP -> AMM`), and the retired `CH_NAV_SENSOR` `[DEPRECATED]` note.
4. Update Section 4 Watchdog Matrix (`L1420-1430`) for 3-tier isolation: `AMM (Node 03)` (`[I-5]` / `[I-7]` GPS `5,000ms` / Dynamic Guide `300ms`), `FCP (Node 04)` (`[I-12]` `AMM_TIMEOUT` `500ms` -> 10s `AMM_TIMEOUT_HOLD` -> `EMERGENCY_LAND`; `[I-1]` `VAS` `500ms`), `VAS (Node 01)` (`[I-2]` `FCP_TIMEOUT` `1,500ms` -> 10s `FAILSAFE_HOLD` -> `EMERGENCY_LAND`), `TCA/ASA` (`300ms`). Fix lowercase `fcp` on `L1424`. Update Section 5 (`L1433-1460`) to include `AMM (Node 03)` in Table 5.1, align FCP `v2.0.0 Approved` / VAS `v1.19.0 Approved` notes, and clean `L1447`.

- [ ] **Step 6: Verify Task 1 Single-Doc Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib; from tools import verify_all_specs as v; s=pathlib.Path('docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md').read_text(encoding='utf-8'); assert 'v1.28.0' in s and 'I-12' in s and 'MSG_TRAJECTORY_SETPOINT' in s and 'QUATERNION_RATE' in s and 'MSG_AERO_CMD' in s; assert 'MSG_SURFACE_CMD`' not in s or 'DEPRECATED' in s" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Python assertion exits 0; `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` section of `verify_all_specs.py` shows `0 Errors, 0 Warnings` for all 8 checks (broken links, stale dirs, metadata, revision history, nested deprecation, raw `Base+6/7`, `* 20` formula, balanced Mermaid, zero banned tokens).

---

### Task 2: System Architecture & Packet Flow Diagram (`SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` `v2.12.1 -> v2.13.0 Approved`)

**Files:**
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:6-65` (Metadata, Revision History, Cross-References, Overview `20채널` fix)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:66-233` (Section 2 global architecture diagram & 6-airframe control flow diagram)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:234-298` (Section 3 Packet Exchange Matrix `[I-1..I-12]`)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:299-609` (Section 4 lifecycle sequences 1–6)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md:610-935` (Sections 5–8 Master Channel Matrix, 40ch sub-allocation, collision/failsafe/bandwidth rules, final summary cleanups)

**Interfaces:**
- Consumes: Task 1 `[I-1..I-12]` channel, actor, and message definitions.
- Produces: Synchronized visual/tabular system routing SSOT (`v2.13.0 Approved`) referenced by Tasks 3–7.

- [ ] **Step 1: Update Metadata (`L6-45`) and Overview (`L46-65`)**

Bump `Version` to `v2.13.0`, `Date` to `2026-11-11`, keep `Approved`, append `v2.13.0` row in Revision History, sync cross-reference badges (`AMM v1.3.0`, `ICD v1.28.0`, `FCP v2.0.0`, `VAS v1.19.0`, `ASA v1.7.0`), and fix `L61` `"온보드 20채널"` -> `"온보드 40채널"`.

- [ ] **Step 2: Redraw Section 2 Global Architecture & 6-Airframe Flowcharts (`L66-233`)**

Update Section 2 (`L66-178`) so external domains (`GCS CH 50000`, `GPS CH 60001/60002 & Base+5`, `Tower ATC / GAC / Facility CH 50001~50004 & Base_sec+*`, `MFD / Remote C2 Base+0/+3`) terminate ONLY at `AMM (Node 03)`, while `AMM <-> FCP (Node 04)` communicates strictly via `Base+4 [I-12]`, `VAS -> FCP & AMM` via `Base+2 [I-1]`, `FCP -> VAS` (`+ AMM/GCS/MFD E_STOP`) via `Base+1 [I-2]`, and `VAS -> TCA/ASA` via `Base+10/11` (`[I-3]`, `[I-10]` unified to `MSG_AERO_CMD`/`MSG_AERO_STATUS`). Update `L179-233` 6-airframe diagram to show `AMM -> FCP` outer-loop `SE(3)` projection into `QUATERNION_RATE` (`Base+1`) -> `VAS` mixing -> `TCA/ASA`. Verify every Mermaid block has even double-quote count.

- [ ] **Step 3: Update Section 3 Packet Exchange Matrix (`L234-298`)**

Re-author table rows (`[I-1..I-12]`):
- `[I-1]` `VAS -> FCP, AMM, Alignment` (`Base+2`).
- `[I-2]` `FCP -> VAS` `MSG_ATTITUDE_CMD` (`QUATERNION_RATE`), `MFD -> VAS` (`RATE_COMMAND`), `AMM/GCS/MFD -> VAS` `MSG_EMERGENCY_OVERRIDE`, `VAS -> AMM/FCP/MFD/GCS` `MSG_EMERGENCY_ALERT` (`Base+1`).
- `[I-5]`, `[I-7]`, `[I-8]` sender/receiver `FCP` -> `AMM`.
- `[I-6]` `MFD/GCS <-> AMM` (`Base+0`), `AMM -> MFD/GCS` (`Base+3`, 5Hz, yield on `MFD_ACRO`), `VAS -> MFD` (`Base+3`, 20Hz `MFD_ACRO`); mark `AMM -> FCP` `MSG_OPERATOR_CMD` `[DEPRECATED]`.
- `[I-9]` `AMM` collision probe (`Base+0`) + 2-phase rebind cascade (`AMM -> FCP -> VAS -> TCA/ASA`).
- `[I-10]` replace `MSG_SURFACE_CMD`/`STATUS` (`L290-291`) with **`MSG_AERO_CMD` / `MSG_AERO_STATUS`** (`MSG_SURFACE_*` `[DEPRECATED]`).
- Add **`[I-12]`** rows (`MSG_TRAJECTORY_SETPOINT` `AMM -> FCP` `Base+4`, `MSG_OUTER_LOOP_STATUS` `FCP -> AMM` `Base+4`).

- [ ] **Step 4: Redraw Section 4 Sequence Diagrams (`L299-609`) & Fix Pre-existing Channel Bugs**

1. **Seq 1 (`L301-349`)**: Show 4-tier 20Hz loop (`AMM` trajectory + `Base+3` 5Hz -> `FCP` `SE(3)` `Base+4` -> `VAS` `QUATERNION_RATE` `Base+1` -> `TCA Base+10` / `ASA Base+11 MSG_AERO_CMD` & `MSG_AERO_STATUS`). Fix `L322, 329` `MSG_SURFACE_*` -> `MSG_AERO_*`.
2. **Seq 2 (`L350-383`)** & **Seq 3 (`L384-461`)**: Replace `FCP` participant with `AMM (Node 03)` across GPS `CH 60001`/`Base+5` and 3-Tier `ATC`/`GAC`/`Facility`. Show `AMM -> FCP` (`Base+4`) `targetPos/targetVel/feedforwardAccel/constraintProfile` guidance update upon facility handoff.
3. **Seq 5 (`L524-557`)**: Move `MSG_BLOCK_REQUEST`/`ASSIGN` (`CH 50000`) and `MSG_CHANNEL_PROBE` (`Base+0`) from `FCP` to `AMM`; fix `L537-546` legacy `BW: 20` / `10040` -> **`BW: 40` / `10080`** (`N=3`, `blockId: 3`, `Base: 10080`).
4. **Seq 6 (`L558-609`)**: Fix `AMM -[Base_old+4]-> FCP -[Base_old+1]-> VAS -[Base_old+10/11]-> TCA/ASA`, and replace `L571-605` `10060` / `bandwidth: 20` / `Base_old+6/7` / `newBase+6/7` -> **`10120` (`N=4`) / `bandwidth: 40` / `Base_old+10/+11` / `newBase+10/+11`**.

- [ ] **Step 5: Update Sections 5–8 (`L610-935`) and Clean `BW=20`/`2000`/`Overclaim` Defects**

1. Update Table 5.1 (`L612-636`, incl. `L633` ASA `MSG_AERO_CMD`/`STATUS` description) to reflect `AMM (Node 03)` (`CH 50000~50004`, `CH 60001/60002`, `Base_sec+*`, `Base+0/+2/+3/+4/+5/+20~29`), `FCP (Node 04)` (`Base+4/+2/+1`), `VAS (Node 01)` (`Base+0 [Calib], +1, +2, +3 [ACRO], +10, +11`), `ASA` (`MSG_AERO_CMD`/`STATUS`).
2. Update Table 5.3 (`L710-734`, incl. `L724` `MSG_AERO_CMD`/`STATUS`): `Base+4` = `CH_TRAJECTORY_CMD` (Zone 1, `AMM <-> FCP`, 20Hz; `CH_NAV_SENSOR` `[DEPRECATED]`), `Base+5` = `CH_EXTERNAL_COMM` (`GPS/Facility <-> AMM`), `Base+11` = `MSG_AERO_*`.
3. Fix Section 6–7 bugs: `L752` `MAX_CRAFT_LIMIT = 1000` (was `2000`); update pseudo-code channel formula checks (`* 40`); `L822` `Base+1~7` -> `Base+0~5, +10~11`; verify `L848` (`N <= 1000`); replace `L930` `"완벽히 차단"` overclaim with `"구조적으로 격리·탐지"`; update `L935` `VAC_TAP_Integration` -> `VAS_TCA_Integration`.

- [ ] **Step 6: Verify Task 2 Single-Doc Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib, re; s=pathlib.Path('docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md').read_text(encoding='utf-8'); assert 'v2.13.0' in s and 'CH_TRAJECTORY_CMD' in s and 'MSG_AERO_CMD' in s; assert 'MAX_CRAFT_LIMIT = 2000' not in s and 'Base+1~7' not in s and '온보드 20채널' not in s and 'Base_old+6' not in s and 'Base_old+7' not in s and '완벽히' not in s" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; `SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` reports `0 Errors, 0 Warnings`.

---

### Task 3: AMM Program Specification (`AMM_PROGRAM_SPECIFICATION.md` `v1.2.0 -> v1.3.0 Approved`)

**Files:**
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:6-29` (Metadata, Revision History, Cross-Refs)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:30-159` (Section 1 overview/anti-goals rewrite, Section 2 dual-mode & coroutine separation, Section 3 dual-modem hardware & RF channels)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:160-303` (Section 4 wire protocols: deprecate `AMM->FCP` `MSG_OPERATOR_CMD`, add `Base+4` `[I-12]`, `[I-5]`, `[I-7]`, `[I-8]`, `[I-9]`, update `Base+2`/`Base+3` MFD_ACRO yield)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:304-415` (Section 5 5Hz TUI & headless decoupling; keep Sections 6–7 & 9 mission engine / web editor intact while updating C2/facility execution flow)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md:696-802` (Sections 8, 10, 11 module architecture, `amm_config.json`, 3-tier failsafe & verification criteria)

**Interfaces:**
- Consumes: Task 1 `[I-5..I-9]`, `[I-11]`, `[I-12]`, `[I-1]`, `[I-2]` (`MSG_EMERGENCY_OVERRIDE`/`ALERT`), Task 2 channel matrix.
- Produces: Complete `AMM (Node 03)` `v1.3.0 Approved` spec defining `nav_engine`, `facility_client`, `channel_sentinel`, `trajectory_generator` (4-phase docking / dynamic-deck 2nd-order Taylor extrapolation / runway ILS / LOITER / POI_HOLD), decoupled `20Hz` + `5Hz` coroutines, and external-tier failsafe table.
- Guardrail (`Rule 1`): Do **NOT** create Markdown relative links (`[text](modules/...)`) to uncreated Lua files (`nav_engine.lua`, `trajectory_generator.lua`, `facility_client.lua`, `channel_sentinel.lua`). Reference module names in inline backticks only (`verify_all_specs.py` Rule 1).

- [ ] **Step 1: Update Metadata, Cross-References & Revision History (`L6-29`)**

Set `Version` to `v1.3.0`, `Date` to `2026-11-11`, keep `Status: Approved`, sync cross-refs (`ICD v1.28.0`, `Diagram v2.13.0`, `FCP v2.0.0`, `VAS v1.19.0`, add refs to `GAC v1.4.2`, `GPS v2.2.3`, `GCS v1.0.2`, `RUNWAY v1.10.7`, `LANDING_PAD v2.4.3`, `DOCKING_ARM v1.11.2`), and add `v1.3.0` row in Revision History.

- [ ] **Step 2: Rewrite Section 1, 2 & 3 (`L30-159`) for External Gateway + Trajectory Ownership**

1. **Section 1 (`L30-110`)**: Replace `L106` current Anti-Goal forbidding `CH 50003` beacon / GPS / direct guidance logic! State explicitly that `AMM (Node 03)` owns:
   - Strategic Mission Planning & 13-action Sequencer (`v1.1.0`/`v1.2.0`),
   - External Infrastructure Gateway (`CH 50000` bootstrap, `CH 50001~50004` Tower ATC/GAC/Beacon/Dispatch, `Base_sec+*` sector/tactical comms, `CH 60001/60002` + `Base+5` GPS),
   - 20Hz Navigation Estimation (`nav_engine`: async GPS pings + 20Hz `VAS Base+2` DR + $\alpha = 0.35$ complementary filter + kinematic gate + 5,000ms GPS timeout loiter/hold),
   - 20Hz Trajectory Generation (`trajectory_generator`: setpoint `{targetPos, targetVel, feedforwardAccel, targetHeading}` for `TAKEOFF`, `CRUISE`, `LOITER`, `POI_HOLD`, `APPROACH_LAND`, `LANDING`, `DOCKING`, `FAILSAFE_RTH`, `HOVER_HOLD`, `EMERGENCY_LAND`, including 4-phase docking & `-0.8` abort trigger and 2nd-order Dynamic Deck Taylor extrapolation),
   - Onboard C2 Single Entry (`Base+0`) and sole 5Hz MFD Telemetry Publisher (`Base+3`, muting during `VAS Base+2` `activeSource == "MFD_ACRO"`).
2. **Section 2 (`L111-132`)**: Clean `L118` (`Base+6 [DEPRECATED]` -> preserve `[DEPRECATED]` tag cleanly), document the decoupled **Dual-Coroutine Execution Model**:
   - Coroutine A (`20Hz` / 50ms): `network_manager`, `nav_engine`, `facility_client`, `channel_sentinel`, `mission_engine`/`condition_evaluator`/`hook_runner`, `c2_arbiter`, `trajectory_generator`, `Base+4` `[I-12]` Tx/Rx, `Base+2` `[I-1]` Rx.
   - Coroutine B (`5Hz` / 200ms): `ui_renderer` (`parallel.waitForAny` when `headless == false`; completely omitted when `headless == true` while Coroutine A keeps publishing `Base+3` 5Hz HUD telemetry to GCS/remote MFD).
3. **Section 3 (`L133-159`)**: Specify Dual Wireless Ender Modem (`top`: onboard internal Zone 1/3 `Base+0~5, +20~29`; `back`: infra external `50000~50004`, `Base_sec+*`, `60001/60002`) plus explicit **single-modem fallback** opening the full union on `top` when `back` is absent. Tabulate all channels owned/subscribed by `AMM`.

- [ ] **Step 3: Revise Section 4 Wire Protocols (`L160-303`) & Section 5 TUI (`L304-351`)**

1. **Section 4.1 (`L164-194`)**: Redefine `Base+0` (`MSG_OPERATOR_CMD`) as **inbound** to `AMM` (`Cockpit / GCS -> AMM`, `PILOT_PRIMARY` vs `GCS_OVERRIDE`) with an explicit notice marking `AMM -> FCP` `MSG_OPERATOR_CMD` (`v1.0.0~v1.2.0`) as **`[DEPRECATED]`** (Zero-Fallback).
2. Keep Section 4.2 (`MSG_MISSION_CMD`/`ACK`), Section 4.3 (`Zone 3` `MSG_PAYLOAD_REQ`/`ACK`), and Section 4.4 (`MSG_EMERGENCY_OVERRIDE`, noting `AMM -> VAS` on `Base+1` for `CUTOFF`/`CUSHION_STOP` and `VAS -> AMM` `MSG_EMERGENCY_ALERT` listener).
3. Add **`4.6 [I-12] FCP 궤적 세트포인트 송출 및 상태 피드백 (Base+4, 20Hz)`** with full `MSG_TRAJECTORY_SETPOINT` (`targetPos`, `targetVel`, `feedforwardAccel`, `targetHeading`, `currentPos`, `navValid`, `gpsTimedOut`, `hdop`, `posEpoch`, `arm`, `flightActive`, `flightMode`, `constraintProfile`, optional `flapHint`, optional `translationBiasHint`) and `MSG_OUTER_LOOP_STATUS` (`fsmState`, `posError`, `velError`, `saturated`, `navStale`).
4. Add **`4.7 [I-5/I-7/I-8/I-9] 인프라 게이트웨이, GPS, 부트스트랩 및 채널 재바인딩`** documenting how `AMM` handles `CH 50000` bootstrap, `Base+0` `MSG_CHANNEL_PROBE/_ACK`, 2-phase `MSG_CHANNEL_REBIND` initiation down to `FCP` via `Base+4`, `CH 60001/60002` + `Base+5` GPS, and `CH 50001~50004`/`Base_sec+*` facility protocols.
5. Update **Section 4.5 (`Base+3` & `Base+2`)** (`L288-303`): clarify that `AMM` **subscribes** to `VAS` `Base+2` (`MSG_FLIGHT_TELEMETRY`, 20Hz) and **publishes** `Base+3` (`MSG_MFD_STATE`, 5Hz) for GCS & remote viewers while muting `Base+3` whenever `VAS Base+2` reports `activeSource == "MFD_ACRO"`.
6. Update Section 5 (`L304-351`): state Coroutine B (`5Hz` TUI) isolation from Coroutine A (`20Hz` trajectory/nav loop), preserve 51x19 layout + `v1.2.0` external editor & `file_transfer` workflows unchanged in Sections 6–7 & 9.

- [ ] **Step 4: Update Section 8, Section 10 Module Map & `amm_config.json`, Section 11 Failsafes (`L696-802`)**

1. Section 8 (`L696-712`): specify `c2_arbiter` arbitration (`GCS_OVERRIDE` > `PILOT_PRIMARY`) triggering trajectory switches (`TAKEOFF`, `CRUISE`, `LOITER`, `POI_HOLD`, `APPROACH_LAND`, `RTH`, `ABORT`) directly inside `AMM`'s `trajectory_generator` and forwarding only `arm`/`flightActive`/`flightMode`/setpoint via `Base+4` (and `E_STOP` on `Base+1`).
2. Section 10 (`L748-786`): add backtick-only modules `nav_engine.lua`, `facility_client.lua`, `channel_sentinel.lua`, `trajectory_generator.lua` alongside existing `v1.2.0` modules (`mission_engine`, `condition_evaluator`, `hook_runner`, `c2_arbiter`, `network_manager`, `ui_renderer`, `input_handler`, `waypoint_queue`). Expand `config/amm_config.json` with migrated infra/nav/safety config blocks (`primaryModemSide`, `infraModemSide`, `channels` incl. `bootstrapChannel: 50000`, `trajectoryCmd` `Base+4`, `externalComm` `Base+5`, `navigation`, `safety`: `dynamicGuideTimeoutMs: 300`, `maxApproachRetries: 3`, `atcDeniedRetryIntervalSec: 15`, `maxAtcDeniedRetries: 10`, `lowFuelRthThreshold: 0.20`, `emergencyLandFuelThreshold: 0.10`, `vasTelemetryTimeoutMs: 500`, `fcpStatusTimeoutMs: 500`, `autoStartMission`, `autoRunDroppedFile`, `headless`).
3. Section 11 (`L787-802`): add Tier-1 AMM external failsafe matrix (GPS `5,000ms` DR loiter, Dynamic Deck `300ms` wave-off, ATC `DENIED` 15s × 10 + alternate/RTH, `GO_AROUND` 3× + divert/RTH, fuel `<20%`/`<10%`, docking 300ms/`>0.30m` `-0.8` abort, FCP `Base+4` 500ms monitor/alert) and keep all `v1.2.0` verification criteria.

- [ ] **Step 5: Verify Task 3 Single-Doc Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib; s=pathlib.Path('docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); assert 'v1.3.0' in s and 'nav_engine.lua' in s and 'trajectory_generator.lua' in s and 'MSG_TRAJECTORY_SETPOINT' in s and 'file_transfer' in s; assert 'Base+6' not in s or 'DEPRECATED' in s" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; `AMM_PROGRAM_SPECIFICATION.md` reports `0 Errors, 0 Warnings` (zero broken links to uncreated Lua modules!).

---

### Task 4: FCP Outer-Loop Controller Specification (`FCP_PROGRAM_SPECIFICATION.md` `v1.16.0 Implemented -> v2.0.0 Approved`)

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:6-187` (Metadata `v2.0.0 Approved`, Revision History, Section 1 slim mission/boundaries, Section 2 single `top` modem 3-channel isolation)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:224-293` (Section 4 slim module architecture & 20Hz outer-loop tick pipeline)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:294-761` (Section 5 unified SE(3) outer-loop law $g=11.0\text{ m/s}^2$ & 6-airframe projections -> `(targetQuaternion, targetAngularRates, collectiveThrust)` + remove/deprecate `/etc/vac/` & direct docking/facility drivers)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:762-1068` (Deprecate Section 6 GPS/DR fusion in favor of AMM `Base+4` + local velocity propagation; slim Section 7 to 6-state FSM & `PASSIVE_TRACKING` + 2.0s bumpless ramp)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:1069-2218` (Section 8 internal ICD `[I-1]/[I-2]/[I-12]` + `[DEPRECATED]` `[I-5..I-10]`, Section 9 slim `fcp_config.json`, Section 10–12 `AMM_TIMEOUT` 500ms / pseudocode / status parity)

**Interfaces:**
- Consumes: Task 1–3 contracts (`Base+4` `MSG_TRAJECTORY_SETPOINT`, `Base+2` `MSG_FLIGHT_TELEMETRY`, `Base+1` `MSG_EMERGENCY_ALERT`/`REBIND_ACK`).
- Produces: Pure onboard SE(3) outer-loop controller spec (`v2.0.0 Approved`):
  - Single `top` modem, ONLY 3 active channels (`Base+4`, `Base+2`, `Base+1`).
  - Inputs: `targetPos`, `targetVel`, `feedforwardAccel`, `targetHeading`, `currentPos`/`posEpoch`, `constraintProfile`, `arm`/`flightActive`/`flightMode`, VAS velocity/attitude/health.
  - Core Law ($g = 11.0\text{ m/s}^2$): $\mathbf{a}_{\text{des}} = \mathbf{a}_{\text{ff}} + \mathbf{K}_p(\mathbf{p}_{\text{ref}}-\mathbf{p}) + \mathbf{K}_d(\mathbf{v}_{\text{ref}}-\mathbf{v}) + \int \mathbf{K}_i(\mathbf{p}_{\text{ref}}-\mathbf{p})\,dt$, $\mathbf{f}_{\text{des}} = \mathbf{a}_{\text{des}} + g\,\hat{\mathbf{u}}_y$, outputting `QUATERNION_RATE` (`targetQuaternion`, `targetAngularRates`, `collectiveThrust`, optional `flapTarget`, optional `translationBias {surge, sway}`) on `Base+1` and `MSG_OUTER_LOOP_STATUS` on `Base+4`.
  - Clean deprecation (never deletion of history): external RF (`50000`, `50001~50004`, `60001/60002`, `Base+0`, `Base+3`, `Base+5`) and `/etc/vac/thruster_profile.json` marked `[DEPRECATED]` or removed cleanly per Zero-Fallback.

- [ ] **Step 1: Update Metadata (`Implemented -> Approved`, `v2.0.0`), Cross-Refs, Section 1 & 2 (`L6-187`)**

1. Set `Status: Approved`, `Version: v2.0.0`, `Date: 2026-11-11`, add `v2.0.0` row explaining breaking role shrink (SE(3) outer-loop-only between `AMM Base+4` and `VAS Base+1`; infra/GPS/C2/MFD migrated to `AMM v1.3.0`).
2. Clean pre-existing `FCP` defects in lines `49-187`: replace `L85` `"고유 20채널 블록"` -> `"고유 40채널 블록"`, remove `L164`/`L180` overclaims (`"완벽히 격리"`, `"0.5ms 이하로 보장"` -> single-modem onboard internal isolation description), remove `back` infra modem (`infraModemSide`), and declare only `top` modem opening `Base+4`, `Base+2`, `Base+1` (`CH 50000~50004`, `60001/60002`, `Base_sec+*`, `Base+0`, `Base+3`, `Base+5` `[DEPRECATED]`).

- [ ] **Step 2: Redefine Section 4 Slim Module Architecture (`L224-293`)**

Replace the former 8-module list (which included `nav_engine`, `facility_client`, `channel_sentinel`, `operator_handler`) with FCP `v2.0.0`'s focused 5-module outer-loop pipeline:
1. `network_manager.lua` (single `top` modem: `Base+4`, `Base+2`, `Base+1`; `MSG_CHANNEL_REBIND` relay)
2. `state_propagator.lua` (local DR propagation from `VAS Base+2` velocity between AMM `posEpoch` ticks, `dt <= 0.1s` guard)
3. `outer_loop_controller.lua` (SE(3) acceleration law + 6-airframe quaternion/angular-rate/collective-thrust allocation + 2.0s bumpless ramp)
4. `flight_fsm.lua` (6-state outer-loop lifecycle FSM + `AMM_TIMEOUT` 500ms & `VAS_TIMEOUT` 500ms sentinels)
5. `main.lua` & optional async `ui_renderer.lua` (`debug: true` via `parallel.waitForAny`, headless by default).
Annotate retired `nav_engine`, `facility_client`, `channel_sentinel`, `operator_handler` as migrated to `AMM`.

- [ ] **Step 3: Rewrite Section 5 SE(3) Outer-Loop Mathematical Law (`L294-761`)**

1. Present the unified SE(3) outer-loop formulation cleanly:
   - Velocity-integrated state propagation between AMM `posEpoch` updates: $\mathbf{p}(t_k) = \mathbf{p}(t_{k-1}) + \mathbf{v}_{\text{vas}}\Delta t$ (with bounded smooth offset merge when `posEpoch` increments).
   - Desired inertial acceleration:
     $$\mathbf{a}_{\text{des}} = \mathbf{a}_{\text{ff}} + \mathbf{K}_p(\mathbf{p}_{\text{ref}} - \mathbf{p}) + \mathbf{K}_d(\mathbf{v}_{\text{ref}} - \mathbf{v}) + \int \mathbf{K}_i(\mathbf{p}_{\text{ref}} - \mathbf{p})\,dt$$
     with conditional anti-windup driven by `VAS` telemetry `actuatorHealth` / saturation flags and magnitude bounds.
   - Desired specific force vector using CC:Aeronautics gravity $g = 11.0\text{ m/s}^2$:
     $$\mathbf{f}_{\text{des}} = \mathbf{a}_{\text{des}} + g\,\hat{\mathbf{u}}_y$$
   - Desired thrust axis $\hat{\mathbf{b}}_y^{\text{des}} = \mathbf{f}_{\text{des}} / \|\mathbf{f}_{\text{des}}\|$ combined with `targetHeading` ($\psi_{\text{ref}}$) and yaw slew rate cap to construct **`targetQuaternion` ($\mathbf{q}_{\text{cmd}}$)**, **`targetAngularRates` ($\boldsymbol{\omega}_{\text{cmd}}$)** (analytic time-derivative / slew-limited trajectory rate feedforward), and normalized **`collectiveThrust` ($T_{\text{col}} \in [0, 1]$)**.
2. Map all 6 airframes cleanly (`FIXED_WING`, `WINGED_VTOL`, `VECTORED_VTOL`, `ADVANCED_VTOL`, `QUADROTOR`, `HEXAROTOR`):
   - `QUADROTOR` / `HEXAROTOR`: tilt-to-accelerate thrust vector alignment ($\theta,\phi$ tilt clamped, `flapTarget = 0.0`, `translationBias = nil`).
   - `VECTORED_VTOL` / `ADVANCED_VTOL`: honor `constraintProfile` (`STRICT_LEVEL` keeps level $\mathbf{q}_{\text{cmd}}$ aligned to `targetHeading` while outputting `translationBias {surge, sway}` and `collectiveThrust`; `TILT_ASSISTED` caps pitch within $\pm 10^\circ$ at $15.0^\circ/\text{s}$ slew; fallback to tilt mode if `VAS` reports sway thruster loss; NO `translationBias.heave` (`[DEPRECATED]`) and NO `/etc/vac/thruster_profile.json` read (`L485, 536` removed/marked migrated to `VAS` `I-4`)).
   - `FIXED_WING` / `WINGED_VTOL`: forward airspeed/bank-to-turn projection (`FIXED_WING` bank $\to \mathbf{q}_{\text{cmd}}$, coordinated turn yaw rate $\to \boldsymbol{\omega}_{\text{cmd}}$, normalized forward/TECS `collectiveThrust`, optional `flapTarget`; `WINGED_VTOL` continuous hover-to-cruise blend governed by `targetVel` & `constraintProfile`).
3. Move strategic `LOITER`, `POI_HOLD`, docking 4-phase orchestration, and runway ILS generation out of `FCP` (now computed by `AMM` and delivered as `(targetPos, targetVel, feedforwardAccel, targetHeading, constraintProfile)` on `Base+4`), retaining only outer-loop tracking execution of `STRICT_LEVEL` / `translationBiasHint` and noting legacy FCP direct facility/docking routines (`§5.9`) as `[DEPRECATED]` (migrated to `AMM`).

- [ ] **Step 4: Refactor Sections 6–7 (`L762-1068`) into State Propagation & 6-State FSM**

1. **Section 6 (`L762-817`)**: Mark external GPS/DR/kinematic gate (`CH 60001/Base+5`) as **migrated to `AMM` `[DEPRECATED]`** and specify FCP's lightweight local velocity propagation + stale-nav flag (`navStale` when `AMM` `posEpoch` stalls or `navValid == false` > threshold).
2. **Section 7 (`L818-1068`)**: Replace the old 16-state FSM with FCP `v2.0.0`'s **6-State Outer-Loop FSM**:
   - `BOOT` -> `IDLE_ARMED` (`arm=true, flightActive=false`)
   - `IDLE_ARMED` <-> `ACTIVE_TRACKING` (`arm=true, flightActive=true`, 20Hz `Base+4` <-> `Base+1`)
   - `ACTIVE_TRACKING` <-> `PASSIVE_TRACKING` (on `VAS Base+2` `activeSource == "MFD_ACRO"`, silences `Base+1` output & freezes outer-loop integrators; upon return to `"FCP"` executes **2.0s bumpless linear ramp**, plus `trigger_bumpless_transition` reset on discrete `flightMode` transitions from `AMM`)
   - `ACTIVE_TRACKING` -> `AMM_TIMEOUT_HOLD` (`Base+4` silence $\ge 500\text{ ms}$: holds level hover at current propagated altitude / fixed-wing $18^\circ$ bank loiter for up to `10.0s`)
   - `AMM_TIMEOUT_HOLD` -> `EMERGENCY_LAND` (unrecovered > `10.0s` or critical fuel/loss: controlled descent at $-1.5\text{ m/s}$ rotary / $-1.0\text{ m/s}$ glide).
   Ensure balanced quotes in Mermaid `stateDiagram-v2` and mark 16-state mission FSM (`DOCK_*`, `RTH`, `GO_AROUND`) as `[DEPRECATED]` (migrated to `AMM`).

- [ ] **Step 5: Refactor Sections 8–12 (`L1069-2218`) & Clean Remaining `FCP` Defects**

1. **Section 8 (`L1069-1498`)**: Keep `[I-1]` (`Base+2` Rx), `[I-2]` (`Base+1` `QUATERNION_RATE` Tx + `MSG_EMERGENCY_ALERT` Rx), and add `[I-12]` (`Base+4` Rx `MSG_TRAJECTORY_SETPOINT`/`REBIND` & Tx `MSG_OUTER_LOOP_STATUS`/`REBIND_ACK`). Clearly label legacy `[I-5..I-9]` subsections (`L1248-1452`) as **`[DEPRECATED — Migrated to AMM v1.3.0]`** (fixing `L1422` `requestedBandwidth = 40`, `L1474` `oldBase+10/+11` while deprecated). Keep `[I-10]` ASA deprecation notice aligned with `MSG_AERO_CMD`/`STATUS` (`L1457-1469`).
2. **Section 9 (`L1499-1658`)**: Shrink `fcp_config.json` to pure outer-loop configuration: remove `infraModemSide`, external `channels` (`50000`, `50001`, `50003`, `60002`, `10003`), `navigation` GPS block, `vectored_vtol.profileValidation` (`/etc/vac/thruster_profile.json` `L1581`), `vectored_vtol.docking`, and infra retry timers; add `outerLoop: { gravityMps2: 11.0, kpPos, kdVel, kiPos, maxAccelMps2, hoverThrustNorm: 0.635 }`, `channels: { baseChannel: 10000, bandwidth: 40, attitudeCmd: 10001, telemetry: 10002, trajectoryCmd: 10004 }`, and `safety: { ammCommandTimeoutMs: 500, coreTelemetryTimeoutMs: 500, failsafeHoldDurationSec: 10.0, emergencyLandDescentMps: 1.5, fixedWingGlideDescentMps: 1.0, bumplessRampSec: 2.0 }` (mark `L1505` `FCP-NODE-04-4402` -> `"FCP-NODE-04-UUID"`, `L1515` `bandwidth: 40`).
3. **Sections 10–12 (`L1659-2218`)**: Focus Section 10 on `AMM_TIMEOUT` (500ms), `VAS_TIMEOUT` (500ms), and `EMERGENCY_LAND`; replace Section 11 pseudocode with SE(3) outer-loop `outer_loop_controller` + `flight_fsm` + `Base+4/2/1` loop; update Section 12 test criteria for `v2.0.0 Approved` (explicitly noting v1.16.0 implementation archive is superseded by `TASK-208`, cleaning `L2139` overclaim `"완벽히"` -> `"정확히"`, preserving `L2210` installer package ID `` `fcp` ``, checking `L2182` `Base+11 (구 Base+7 [DEPRECATED])`, updating `L2218` cross-refs). Also ensure `L478`/`L533` overclaims (`"원천 차단"` / `"원천 제거"`) and deprecated `L1422`/`L1429` (`requestedBandwidth = 40`, `baseChannel = 10080` for `blockId = 3`) are cleaned.

- [ ] **Step 6: Verify Task 4 Single-Doc Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib; s=pathlib.Path('docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); assert 'v2.0.0' in s and '`Approved`' in s and '11.0' in s and 'AMM_TIMEOUT_HOLD' in s and 'PASSIVE_TRACKING' in s and 'QUATERNION_RATE' in s; assert '/etc/vac/' not in s and '이하로 보장' not in s and '고유 20채널' not in s" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; `FCP_PROGRAM_SPECIFICATION.md` reports `0 Errors, 0 Warnings`.

---

### Task 5: VAS Inner-Loop Specification (`VAS_PROGRAM_SPECIFICATION.md` `v1.18.0 Implemented -> v1.19.0 Approved`)

**Files:**
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:1-143` (Metadata `v1.19.0 Approved`, Revision History, Cross-Refs, Section 1 architecture & channel topology)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:226-562` (Section 4–5 pipeline, fix `SatWap`/`satTap`/`adapterWap`/`safeOutputsWap`/`uapCmd` defects, trim normal climb PI)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:563-784` (Section 6 `QUATERNION_RATE` inner-loop + `collectiveThrust` airframe mapping + `FCP_TIMEOUT` failsafe synth; Section 7 `E_STOP > MFD_ACRO > FCP` & 9-State FSM)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:785-1320` (Section 8 `[I-1]` to `FCP`+`AMM`, `[I-2]` `QUATERNION_RATE`, `[I-10]` `MSG_AERO_*`, `[I-5]` `MSG_SURFACE_DISCOVER_*`, `[I-6]` 20Hz ACRO MFD yield, `[I-9]` rebind `AMM->FCP->VAS`)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md:1321-1622` (Section 9 `system.json` fix `reserved04/6/7/uapCommandTimeoutMs`; Section 11–12 `fcp` lowercase & `node_tap`/`adapter_tap` historical cleanup)

**Interfaces:**
- Consumes: Task 1 `[I-1]`, `[I-2]`, `[I-3]`, `[I-4]`, `[I-6]` (`ACRO` HUD), `[I-9]`, `[I-10]`.
- Produces: Inner-loop core specification (`v1.19.0 Approved`) enforcing strict `QUATERNION_RATE` / `RATE_COMMAND` consumption on `Base+1` and clean fail-safe vertical hold/descent only inside `FAILSAFE_HOLD` / `EMERGENCY_LAND`.

- [ ] **Step 1: Update Metadata (`Implemented -> Approved`, `v1.19.0`), Cross-Refs & Section 1–2 (`L1-143`)**

1. Bump `Status: Approved`, `Version: v1.19.0`, `Date: 2026-11-11`, add `v1.19.0` Revision History row, update cross-reference versions (`ICD v1.28.0`, `Diagram v2.13.0`, `FCP v2.0.0`, `ASA v1.7.0`, `AMM v1.3.0`).
2. In Section 1 (`L38-119`), show `AMM (Node 03)` above `FCP (Node 04)` and annotate `L124` (`top` modem): remove external GCS/facility ambiguity (VAS communicates with `AMM` via `Base+2` `TELEMETRY`, `Base+1` `EMERGENCY`, `Base+3` 20Hz during `MFD_ACRO`, and `Alignment` on `Base+0` + `Base_hangar+*`). Keep `Base+10` (`CH_THRUST_ACTUATION`) and `Base+11` (`CH_SURFACE_ACTUATION`, mark `L106/107` alias consistently) intact.

- [ ] **Step 2: Revise Sections 4–5 (`L226-562`) & Scrub Legacy Identifier Bugs**

1. Remove normal-flight `compute_climb_wrench` vertical velocity PI loop from `flight_dynamics_core` (`§5.6`, `L486-496`), keeping unit quaternion SO(3) attitude/angular-rate stabilization, anti-windup, and `collectiveThrust` normalization; note that altitude/vertical-velocity hold runs strictly inside `state_machine` fallback (`FAILSAFE_HOLD` / `EMERGENCY_LAND`) when `FCP_TIMEOUT` (1500ms) occurs.
2. Fix ALL pre-existing identifier bugs verified in Section 4–5:
   - `L254, 256, 261, 281, 324, 331, 366-417, 452, 601`: rename `satTap`/`safeOutputsTap`/`adapterTap`/`A_TAP` -> `satTca`/`safeOutputsTca`/`adapterTca`/`A_TCA`, and rename `SatWap`/`adapterWap`/`saturationStatus`/`safeOutputsWap` -> `SatAsa`/`adapterAsa`/`safeOutputsAsa`.
   - `L262`: `TAP으로` -> `TCA로`.
   - `L450`: rename `uapCmd` -> `fcpCmd`.
   - `L546`: clarify `AMM` owns normal 5Hz `Base+3` emission while `VAS` pauses `Base+3` until `activeSource == "MFD_ACRO"` (then `VAS` streams 20Hz direct HUD frames while `AMM` mutes); fix lowercase `fcp` in `L546`.

- [ ] **Step 3: Revise Sections 6–7 Control Laws & FSM (`L563-784`)**

1. **Section 6.2–6.3 (`L584-639`)**: Specify `flight_dynamics_core` tracking `targetQuaternion` + `targetAngularRates` feedforward with `collectiveThrust` mapping across all 6 airframes:
   - `QUADROTOR` / `HEXAROTOR`: `collectiveThrust` -> vertical lift (`heave` body-frame thrust).
   - `VECTORED_VTOL` / `ADVANCED_VTOL`: `collectiveThrust` -> lift/heave + `translationBias {surge, sway}` (`STRICT_LEVEL` zero-tilt or `TILT_ASSISTED` pitch).
   - `FIXED_WING`: `collectiveThrust` -> forward thrust (`surge`), with Stall Guard ($V \le 10\text{ m/s}$), Flap $V_{fe}$ Guard ($V > 15\text{ m/s}$), and `maxTiltDeg` clamp in `vehicle_policy`.
   - `WINGED_VTOL`: `transitionAlpha`-blended allocation of `collectiveThrust` + pitch tilt.
   Fix lowercase `fcp` on `L626`.
2. **Section 7 (`L690-784`)**: Clarify arbitration **`E_STOP (AMM/GCS/MFD) > MFD_ACRO (RATE_COMMAND) > FCP (QUATERNION_RATE)`**, explicitly specify `FAILSAFE_HOLD` (10s self-synthesized hover / $18^\circ$ bank loiter on `FCP_TIMEOUT` 1500ms) -> `EMERGENCY_LAND` (`-1.5 m/s` rotary / $-1.0\text{ m/s}$ glide), and confirm `PASSIVE_TRACKING` notification back to `FCP` & `AMM` via `Base+2` `activeSource = "MFD_ACRO"`.

- [ ] **Step 4: Refactor Section 8 Interface Payloads (`L785-1320`)**

1. **`§8.1 [I-1]` (`L787-838`)**: List `FCP (Node 04)` and `AMM (Node 03)` as 20Hz `Base+2` `MSG_FLIGHT_TELEMETRY` subscribers (plus `Alignment`).
2. **`§8.2 [I-2]` (`L839-882`)**: Replace the old `ATTITUDE_ANGLE` schema with `QUATERNION_RATE` (`targetQuaternion {w,x,y,z}`, `targetAngularRates {pitchRate,rollRate,yawRate}`, `collectiveThrust`, optional `flapTarget`, optional `translationBias {surge, sway}`) and `RATE_COMMAND` (`MFD_ACRO`). Explicitly mark `"ATTITUDE_ANGLE"`, `angleTargets`, `rateTargets`, `targetClimbRate`, `targetThrottle`, and `translationBias.heave` (`L874-878`) as **`[DEPRECATED]`** (Zero-Fallback).
3. **`§8.6 [I-5]` (`L1126-1188`)**: Fix `L1127` `Base + 7` -> `Base + 11 (구 Base + 7 [DEPRECATED])`, and fix `L1160-1177` **`MSG_AERO_DISCOVER_REQ` / `MSG_AERO_DISCOVER_ACK`** -> **`MSG_SURFACE_DISCOVER_REQ` / `MSG_SURFACE_DISCOVER_ACK`** (`MSG_AERO_DISCOVER_*` `[DEPRECATED]`), matching Master ICD `[I-10]` and `ASA` §4.3.
4. **`§8.7 [I-6]` (`L1189-1221`)**: Clarify `AMM` owns 5Hz `Base+3` during `"FCP"` control while `VAS` yields `Base+3` until `activeSource == "MFD_ACRO"` (at which point `VAS` emits 20Hz HUD frames and `AMM` mutes).
5. **`§8.8–8.10` (`L1222-1320`)**: Update `L1224` (`AMM`/`GCS`/`MFD` `E_STOP`, `FCP` alert subscriber, lowercase `fcp` fix), `L1280` (`AMM -> FCP -> VAS -> TCA/ASA` cascade, lowercase `fcp` fix).

- [ ] **Step 5: Fix Section 9 `system.json` & Section 11–12 Defects (`L1321-1622`)**

1. **`L1432-1434` (`config/system.json`)**: replace `"reserved04": 4` -> `"trajectory": 4` (map reference; VAS opens only `c2Command/0`, `guidance/1`, `telemetry/2`, `mfd/3` [ACRO], `actuation/10`, `asaActuation/11`), `"actuation": 6` -> `"actuation": 10`, `"asaActuation": 7` -> `"asaActuation": 11`.
2. **`L1456`**: rename `"uapCommandTimeoutMs": 1500` -> **`"fcpCommandTimeoutMs": 1500`** (document the legacy key removal only in Revision History prose `"구버전 유도 타임아웃 설정 키를 fcpCommandTimeoutMs로 정규화"`, with zero literal legacy key string left anywhere in `VAS_PROGRAM_SPECIFICATION.md`).
3. Fix `L1555` lowercase `fcp` (`-> FCP 및 AMM`), retain historical Section 12 slice audit context accurately, and update `L1622` footer cross-ref versions (`v1.28.0`, `v2.13.0`, `v2.0.0`, `v1.7.0`, `v1.3.0`).

- [ ] **Step 6: Verify Task 5 Single-Doc Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib, re; s=pathlib.Path('docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); assert 'v1.19.0' in s and '`Approved`' in s and 'QUATERNION_RATE' in s and 'MSG_SURFACE_DISCOVER_REQ' in s and 'fcpCommandTimeoutMs' in s; assert 'SatWap' not in s and 'adapterWap' not in s and 'safeOutputsWap' not in s and 'uapCmd' not in s and 'reserved04' not in s and 'uapCommandTimeoutMs' not in s" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; `VAS_PROGRAM_SPECIFICATION.md` reports `0 Errors, 0 Warnings`.

---

### Task 6: Control & Hangar Peer Specs (`ASA v1.7.0 Approved`, `TCA v1.11.1 Implemented`, `ALIGNMENT v2.6.1 Implemented`)

**Files:**
- Modify: `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (`v1.6.0 -> v1.7.0 Approved`, `L1-541`)
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md` (`v1.11.0 -> v1.11.1 Implemented`, `L1-670`)
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.6.0 -> v2.6.1 Implemented`, `L1-857`)

**Interfaces:**
- Consumes: Task 1 `[I-3]`, `[I-4]`, `[I-9]`, `[I-10]` & Task 5 `VAS v1.19.0`.
- Produces: Cleanly aligned actuator/calibration peer specifications with zero channel arithmetic bugs (`10007`, `+6`, `+7`, `bw=20`) or outdated upstream node attribution (`FCP` -> `AMM` / `VAS`).

- [ ] **Step 1: Revise `ASA_PROGRAM_SPECIFICATION.md` (`v1.6.0 -> v1.7.0 Approved`)**

Update `Version: v1.7.0`, `Date: 2026-11-11`, keep `Status: Approved`, add `v1.7.0` Revision History row, update `L14-22` & `L532-541` cross-ref versions, and apply all semantic/defect fixes:
- `L31` (`v1.3.0` historical row): change ``구 `Base+11` [DEPRECATED]`` -> ``구 `Base+7` [DEPRECATED]`` (or clarify `Base+7 -> Base+11`).
- `L41`, `L69`, `L70`, `L113`: replace outer-loop attribution `"기구학적 자세/방위/승강률"` with `FCP` SE(3) `QUATERNION_RATE` + optional `flapTarget` (`Base+1` -> `VAS`), and note `Base+2` `MSG_FLIGHT_TELEMETRY` goes to `FCP` & `AMM`.
- `L92`: fix `Base + 6` missing tag -> `Base + 10 (구 Base + 6 [DEPRECATED])`, and remove `"원천 차단"` overclaim (`"방지하기 위해"`).
- `L125`: fix `"FCP 무선 통신 전용 포트"` -> **`"VAS (Node 01) 및 Alignment 지상 교정 무선 통신 전용 포트"`**!
- `L181`: fix `"surfaceActuation": 10007` -> **`"surfaceActuation": 10011`** (`Base + 11` for `AIRCRAFT_01`).
- `L269`: fix lowercase `fcp` -> `상위 FCP 및 AMM`.
- `L344`: fix `"GCS가 fcp에"` -> **`"GCS가 AMM에 기체 Base 채널 재할당을 발령하고, AMM이 FCP $\to$ VAS를 거쳐"`**.
- `L346`: fix `oldBase + 7` -> **`oldBase + 11`**.
- `L363`: fix `bandwidth = 20` -> **`bandwidth = 40`**.
- `L485`, `L490`: fix `newBaseChannel + 7` -> **`newBaseChannel + 11`**.

- [ ] **Step 2: Revise `TCA_PROGRAM_SPECIFICATION.md` (`v1.11.0 -> v1.11.1 Implemented`)**

Keep `Status: Implemented`, bump `Version: v1.11.1`, `Date: 2026-11-11`, add `v1.11.1` Revision History row (documentation/cross-ref/channel-constant fix only — zero TCA Lua runtime behavioral change), sync `L14-22` & `L670` cross-ref versions, and fix:
- `L32`, `L45`: change ``구 `Base+10` [DEPRECATED]`` -> ``구 `Base+6` [DEPRECATED]``; remove `"완벽히"` overclaims on `L45`, `L51`.
- `L452`: change `FCP -> VAS` -> **`AMM -> FCP -> VAS`**.
- `L454`: change `oldBase + 6` ACK -> **`oldBase + 10`**.
- `L547`, `L551`: change `newBaseChannel + 6` -> **`newBaseChannel + 10`**.
- `L588`, `L592`: clarify `FCP` / `AMM` emergency hover & `EMERGENCY_LAND` triggers on `TOTAL_LOSS` / `TIMEOUT`.

- [ ] **Step 3: Revise `ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.6.0 -> v2.6.1 Implemented`)**

Keep `Status: Implemented`, bump `Version: v2.6.1`, `Date: 2026-11-11`, add `v2.6.1` Revision History row (zero Alignment runtime change), sync `L14-22` & `L857` cross-ref versions (`ICD v1.28.0`, `Diagram v2.13.0`, `VAS v1.19.0`, `FCP v2.0.0`, `ASA v1.7.0`, `TCA v1.11.1`), and fix `L623` `hardwareUuid = "FCP-NODE-04-4402"` -> `"VAS-NODE-01-4402"` in `MSG_CALIBRATION_INIT_ACK` (`VAS` responds on `Base_hangar+1`). Also note `MSG_SURFACE_DISCOVER_REQ/ACK` alignment (`L243, L252, L648`) already matches Task 5.

- [ ] **Step 4: Verify Task 6 Peer Specs Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib; asa=pathlib.Path('docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); tca=pathlib.Path('docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); alg=pathlib.Path('docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md').read_text(encoding='utf-8'); assert '10007' not in asa and 'newBaseChannel + 7' not in asa and 'bandwidth = 20' not in asa and 'newBaseChannel + 6' not in tca and 'FCP-NODE-04-4402' not in alg" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; all 3 files pass `verify_all_specs.py` with `0 Errors, 0 Warnings`.

---

### Task 7: Ground & Airspace Infrastructure Peer Specs (`RUNWAY`, `DOCKING_ARM`, `GAC`, `LANDING_PAD`, `GCS`, `GPS`)

**Files:**
- Modify: `docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md` (`v1.10.6 -> v1.10.7 Approved`, `L1-411`)
- Modify: `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md` (`v1.11.1 -> v1.11.2 Approved`, `L1-441`)
- Modify: `docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.4.1 -> v1.4.2 Implemented`, `L1-782`)
- Modify: `docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md` (`v2.4.2 -> v2.4.3 Implemented`, `L1-775`)
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.0.1 -> v1.0.2 Implemented`, `L1-181`)
- Modify: `docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v2.3.0 -> v2.3.1 Implemented`, `L1-1132`)

**Interfaces:**
- Consumes: Task 1 `[I-5]`, `[I-6]`, `[I-7]`, `[I-8]` (`AMM (Node 03)` owns external airborne RF endpoints).
- Produces: Synchronized ground-infra ICDs where airborne counterparty terminology consistently names `AMM (Node 03)` (or `기체 AMM (Node 03)` relaying trajectory to `FCP Base+4`), preserving 100% backward compatibility on actual wire channels (`CH 50000~50004`, `Base_sec+*`, `CH 60001/60002`, `Base+5`, `Base+0`) so `GAC`, `LANDING_PAD`, `GCS`, and `GPS` retain `Implemented` status without Lua changes.

- [ ] **Step 1: Revise `Approved` Facility Specs (`RUNWAY v1.10.7`, `DOCKING_ARM v1.11.2`)**

1. **`RUNWAY_SPECIFICATION_AND_ICD.md`**: Bump `v1.10.7` (`2026-11-12`, `Approved`), add Revision History row, update cross-refs (`ICD v1.28.0`, `Diagram v2.13.0`, `AMM v1.3.0`, `FCP v2.0.0`, `VAS v1.19.0`, `GAC v1.4.2`, `GPS v2.3.1`, `LANDING_PAD v2.4.3`, `DOCKING_ARM v1.11.2`). Across `L46-411` (`L46, 54, 56, 77, 84-100, 275-292, 349, 401, 410`): replace external `FCP (Node 04)` radio counterparty (`50001`, `50003`, `Base_sec+0`, `Base_sec+10+Idx`, `Base+5`) with **`기체 AMM (Node 03)`** and note that `AMM` synthesizes the relative ILS glide-slope / ship velocity-compensated setpoint and forwards it over `Base+4` to `FCP (Node 04)` for outer-loop tracking.
2. **`DOCKING_ARM_SPECIFICATION_AND_ICD.md`**: Bump `v1.11.2` (`2026-11-12`, `Approved`), add Revision History row, update cross-refs (`L24-32`). Across `L65-432` (`L65-72, 89, 99-117, 250-303, 363, 432`): replace airborne `FCP (Node 04)` counterparty (`50001`, `50003`, `Base_sec+0`, `Base_sec+10+Idx`, `Base+5`, `MSG_DOCK_CAPTURE_STAGE` `HARD_LOCKED` / `DOCKING_ARM_CMD` alias) with **`기체 AMM (Node 03)`**, clarifying that `AMM` drives the 4-phase docking trajectory & `-0.8` abort trigger via `Base+4` while disarming `FCP`/`VAS` immediately upon `HARD_LOCKED`. Note `DOCKING_ARM`'s dependency on `AMM_PROGRAM_SPECIFICATION.md` (`v1.3.0`) as well as `FCP` (`v2.0.0`).

- [ ] **Step 2: Revise `Implemented` Sector/Pad Specs (`GAC v1.4.2`, `LANDING_PAD v2.4.3`)**

Bump versions (`GAC v1.4.2`, `LANDING_PAD v2.4.3`, `2026-11-12`), retain `Status: Implemented` (zero Lua changes in `src/0_infra/{gac,landing_pad}/`), add Revision History rows noting airborne endpoint terminology alignment to `AMM (Node 03)` (`ICD v1.28.0`), update cross-refs (`AMM v1.3.0`, `FCP v2.0.0`, `VAS v1.19.0`, etc.):
- **`GAC`**: update `L117-126, 257-281, 380-475, 529-592` airborne actor labels `FCP (Node 04)` -> `기체 AMM (Node 03)` (clarifying `FCP` receives trajectory from `AMM`).
- **`LANDING_PAD`**: update `L52, 60, 70-75, 150-179, 445, 510, 534, 541` (`L52-60` and `§5` `L510-541`: clarify `AMM (Node 03)` performs 20Hz Dynamic Pad 2nd-order Taylor extrapolation, 300ms heartbeat timeout wave-off, and `landingPermitted` / `DANGEROUS` hover gating before sending setpoints on `Base+4` to `FCP`).

- [ ] **Step 3: Revise `Implemented` Core Infra Specs (`GCS v1.0.2`, `GPS v2.3.1`)**

1. **`GCS_PROGRAM_SPECIFICATION_AND_ICD.md`**: Bump `v1.0.2` (`2026-11-12`, `Implemented`), add Revision History row, update cross-refs (`ICD v1.28.0`, `Diagram v2.13.0`, `AMM v1.3.0`, `FCP v2.0.0`, `VAS v1.19.0`). Update `L37` (`MSG_BLOCK_REQUEST` sender: `기체 AMM (Node 03)`), `L41`/`L95` (`Base+0` `MSG_OPERATOR_CMD`/`MSG_MISSION_CMD` receiver: `AMM (Node 03)`), `L44`/`L104` (`Base+1` `MSG_EMERGENCY_OVERRIDE` receiver: `VAS (Node 01)` direct, bypassing `AMM` & `FCP`), `L46` (`Base+3` 5Hz telemetry source: `AMM (Node 03)` / `VAS` when ACRO), and keep `L120` (`#02 AIRCRAFT_02 [10040]`) untouched because `10000 + (2-1)*40 = 10040` is valid under $BW=40$.
2. **`GPS_PROGRAM_SPECIFICATION_AND_ICD.md`**: Bump `v2.3.1` (`2026-11-12`, `Implemented`), add Revision History row, update cross-refs (`L24-35`, adding `AMM v1.3.0`). Update `L40, 71, 89, 107-142, 179, 250, 926-999, 1111-1112`: airborne GPS client is **`AMM (Node 03)`** (`nav_engine` + `gps/client.lua` managed mode, calling `handleMessage()` inside 20Hz loop instead of synchronous `locate()`, executing `5,000ms` timeout DR loiter and `HDOP > 5.0` precision-landing lockout). Clean `L234` stale `10045` example -> `10005` (`N=1` `Base+5`, 구 `10045 [DEPRECATED]`). Check all Mermaid blocks for balanced double quotes.

- [ ] **Step 4: Verify Task 7 Infra Peer Specs Hygiene**

Run in PowerShell:
```powershell
python -c "import pathlib; pairs=[('docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md','v1.10.7'),('docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md','v1.11.2'),('docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md','v1.4.2'),('docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md','v2.4.3'),('docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md','v1.0.2'),('docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md','v2.3.1')]; assert all(v in pathlib.Path(p).read_text(encoding='utf-8') and 'AMM' in pathlib.Path(p).read_text(encoding='utf-8') for p,v in pairs)" ; if ($?) { python tools/verify_all_specs.py }
```
Expected: Assertions exit 0; `verify_all_specs.py` passes with `0 Errors, 0 Warnings` across all 15 specifications.

---

### Task 8: Spec Status Manifest, `TASK.md`, Living Context (`GEMINI.md`, `.agent/memory/`) & Full Verification

**Files:**
- Modify: `tools/verify_spec_status.py:4-35` (Update docstring `7 Implemented, 8 Approved`; move `FCP` & `VAS` from `TARGET_IMPLEMENTED` to `TARGET_APPROVED`)
- Modify: `TASK.md:5, 23-140` (Archive completed `TASK-206` Spec Refactor `TASK-206-1~8` & register follow-up implementation tasks `TASK-207` AMM `v1.3.0`, `TASK-208` FCP `v2.0.0`, `TASK-209` VAS `v1.19.0`, `TASK-210` / `TASK-105` ASA `v1.7.0`; sync inline spec citations for `TASK-117, 122, 202, 204, 401, 103, 104, 105, 108` and make `TASK-201` Section 3 `L125-129` `R5`-compliant)
- Modify: `GEMINI.md:1-47` (Update Section 1 Current Phase/Handover/Next Action while staying `<= 80` lines)
- Modify: `.agent/memory/workspace-root.md` (Append historical log entry referencing `TASK-206` — satisfies `verify_context_docs.py` R8)

**Interfaces:**
- Consumes: Final version numbers and statuses produced in Tasks 1–7 (`7 Implemented, 8 Approved`).
- Produces: Synchronized CI verification tools, task roadmap (`TASK.md`), and 3-tier context memory passing `verify_context_docs.py` with `0 findings`.

- [ ] **Step 1: Update `tools/verify_spec_status.py` (`L4-35`)**

Update docstring lines 4–5 (`7 Implemented specs`, `8 Approved specs`), remove `FCP_PROGRAM_SPECIFICATION.md` and `VAS_PROGRAM_SPECIFICATION.md` from `TARGET_IMPLEMENTED` (`L16-26`), and add both to `TARGET_APPROVED` (`L28-35`). Run `python tools/verify_spec_status.py` -> Expect `[PASS] All 15 specs have valid statuses (7 Implemented, 8 Approved)!`.

- [ ] **Step 2: Synchronize `TASK.md` Roadmap & Citations (Preserve `R5` Hygiene)**

1. Update header line 5 (`직전 완료: TASK-206 ...`, active queue).
2. Add follow-up implementation tasks to Section 1 (`Active Immediate Tasks`):
   - `[ ] **TASK-207: AMM v1.3.0 외부 게이트웨이·항법·궤적 생성기 구현**` (`docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` `(현재 v1.3.0 Approved)`, `src/3_planning/amm/`, implementing `nav_engine`, `facility_client`, `channel_sentinel`, `trajectory_generator`, `Base+4` `[I-12]`, `20Hz`/`5Hz` coroutines). Note dependency relative to `TASK-202-4~5` and `TASK-122`.
   - `[ ] **TASK-208: FCP v2.0.0 SE(3) 외루프 제어기 경량화 전면 개편**` (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` `(현재 v2.0.0 Approved)`, `src/2_guidance/fcp/`, shrinking FCP to 3 internal channels `Base+4/+2/+1`, $g=11.0\text{ m/s}^2$ SE(3) law, 6-state FSM).
   - `[ ] **TASK-209: VAS v1.19.0 `QUATERNION_RATE` 내루프 정규화 및 ACRO/페일세이프 정합화**` (`docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` `(현재 v1.19.0 Approved)`, `src/1_control/vas/`).
   - `[ ] **TASK-210: ASA v1.7.0 / TCA / Alignment 구현 정합화**` (or note inside `TASK-105` for `ASA v1.7.0 Approved` and post-implementation follow-up).
3. Update all inline `(현재 vX.Y.Z Status)` references across `TASK-117` (`L49`), `TASK-122` (`L67` — also note `TASK-122` GPS/FCP impact now migrates to AMM on impl), `TASK-202` (`L80`), `TASK-204` (`L88`), `TASK-401` (`L91`), `TASK-103` (`L100`), `TASK-104` (`L106`), `TASK-105` (`L109`), `TASK-108` (`L112`).
4. Mark `TASK-206` (`TASK-206-1` ~ `TASK-206-8`) `[x]` and move `[x] **TASK-206: FCP 외루프 경량화 및 AMM 상위 계층 이관을 위한 15대 사양서 전면 개편**` to top of Section 3 (`Completed Tasks Archive`, pruning oldest beyond 10 items per `TASK.md` line 14!).
5. **Crucial `R5` fix in `TASK-201` (`L125, L126, L129`)**: Do NOT leave `` `path/spec.md` (v1.16.0 Implemented) `` inside Section 3 because `verify_context_docs.py` R5 compares every `` `*.md` (vX.Y.Z Status) `` match anywhere in `TASK.md` against current disk headers! Rephrase archived badges cleanly by separating prose from path (e.g., `` (`docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, 당시 `v1.16.0 Implemented`) ``).

- [ ] **Step 3: Sync `GEMINI.md` (`<= 80` lines) & `.agent/memory/workspace-root.md`**

Update `GEMINI.md` Section 1 (`직전 완료`: `TASK-206` + new version/status counts `7 Implemented, 8 Approved`, `다음 액션`: `TASK-207~209` / `TASK-202-4~5`), keeping total lines strictly `<= 80` and checking Section 4 gotchas (`Base+4 = CH_TRAJECTORY_CMD`, `QUATERNION_RATE`, `AMM` external gateway). Append a factual `TASK-206` entry to `.agent/memory/workspace-root.md` with exact verification numbers.

- [ ] **Step 4: Run Full Static, Harness, Context, and Negative-Regex Verification Suite**

Run in PowerShell:
```powershell
python tools/verify_all_specs.py --check-readmes ; if ($?) { python tools/verify_spec_status.py } ; if ($?) { python tools/verify_context_docs.py } ; if ($?) { python tools/verify_manifest_sync.py } ; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" } ; if ($?) { python tools/validate_lua_syntax.py }
```
Expected:
- `verify_all_specs.py --check-readmes`: `SCAN RESULT: ALL 15 SPECS 100% CLEAN (0 Errors, 0 Warnings)`
- `verify_spec_status.py`: `[PASS] All 15 specs have valid statuses (7 Implemented, 8 Approved)!`
- `verify_context_docs.py`: `0 findings`
- `verify_manifest_sync.py`: `0 Errors, 0 Warnings`
- `unittest tests/harness`: all tests `PASS`
- `validate_lua_syntax.py`: all Lua files `PASS` (unchanged codebase sanity check)

- [ ] **Step 5: Run Targeted Spec Defect Audit & Commit**

Run a final Python check verifying zero stray pre-existing bugs or leaked prohibited terms across all 15 specs (`docs/system/*.md`, `docs/specs/**/*.md`):
- Zero occurrences of `uapCmd`, `uapCommandTimeoutMs`, `SatWap`, `satTap`, `adapterWap`, `safeOutputsWap`, `reserved04`, `/etc/vac/`, `10007`, `newBaseChannel + 6`, `newBaseChannel + 7`, `MAX_CRAFT_LIMIT = 2000`, `Base+1~7`, `VALKYRIEN`, `kontraption:`.
- Zero un-deprecated `MSG_SURFACE_CMD`, `MSG_SURFACE_STATUS`, `MSG_AERO_DISCOVER_REQ/ACK`, `ATTITUDE_ANGLE`, `translationBias.heave`, `10045`.

Then stage and commit strictly the documentation & `verify_spec_status.py` changes:
```powershell
& "C:\Program Files\Git\cmd\git.exe" status -sb
& "C:\Program Files\Git\cmd\git.exe" add docs/ tools/verify_spec_status.py TASK.md GEMINI.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(specs): shrink FCP to SE(3) outer-loop and migrate gateway/nav/mission ownership to AMM"
```
