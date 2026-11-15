# TASK-117: Wireless OTA Deployment Server & Slave Atomic Rollback Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Hangar Wireless OTA Deployment Server (`src/0_development/ota/`) and a Slave Atomic Rollback Guard (`/lib/ota_agent.lua` + 2-stage boot commit watchdog in `startup_generator.lua`) across onboard avionics subsystems (`VAS`, `TCA`, `FCP`, `AMM`), backed by a formal `I-13` ICD specification, wire-contract enforcement, and multi-node E2E verification.

**Architecture:** Hangar OTA traffic uses dedicated hangar bay channels (`Base_hangar + 4` for `CH_OTA_CMD`, `Base_hangar + 5` for `CH_OTA_ACK`, where `Base_hangar = 101 + (BayID - 1) * 10`, strictly outside `0..100` and aircraft `10000..49999`). Onboard nodes open their configured `ota.bayId` (default `1` -> `105`/`106`) plus optional `ota.bayIds` expansion, while the server selects `bayId` (`1..10`) via config or CLI/TUI. The OTA Server uses `/ota_packages/<moduleId>/` as its staged package SSOT and supports automated (`autoSyncOnBoot`) or explicit (`CLI sync` / `TUI [S]ync`) GitHub/manifest remote download into `/ota_packages/` when `http` is enabled. A self-contained shared library `src/0_development/ota/ota_agent.lua` (staged to `/lib/ota_agent.lua`) provides pure-Lua/bit32 CRC32 verification, ICD `1.9.5` envelope framing, chunked staging into `/ota_staging/<txId>/`, atomic backup snapshotting to `/ota_backup/<txId>/`, safety gating (`DISARMED`/`BOOT`/`IDLE_ARMED` with `isAirborne ~= true`), `config/*.json` preservation (`overwriteConfig = false` default) with module-exclusive orphan cleanup, `/.ota_pending.json` creation (`maxBootAttempts = 1`), and stabilized post-boot commit (`20` healthy ticks / ~1s window via `tick_boot_commit()`). On reboot, `startup_generator.lua`'s hook runs the 2-stage commit watchdog to restore `/ota_backup/<txId>/` (including deleted orphan files) and `/.version.json` on load failure, runtime crash, or pre-commit reboot.

**Tech Stack:** CraftOS-PC (CC:Tweaked Cobalt Lua 5.2 with `bit32`), Python 3 (`tools/verify_*.py`, `tools/run_*.py`), `config/protocol_contracts.json` SSOT wire contracts, Git CLI (`"C:\Program Files\Git\cmd\git.exe"` on Windows PowerShell 5.1).

**Spec:** `TASK.md` (`TASK-117`, `TASK-117-1`..`TASK-117-5`), `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` (created in Task 1), `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`I-13`), `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`.

**Global Constraints:**
- Cobalt Lua 5.2 only: `bit32` is allowed (`bit32.bxor`, `bit32.rshift`, `bit32.band`, `bit32.bnot`, with pure-Lua math fallback if `bit32` is mocked absent); never use Lua 5.3+ `//`, `&`, `|`, `~`, `<<`, `>>`, or `goto`.
- Multi-codebase independence: `src/<layer>/<name>/` subsystems never `require` files from another subsystem directory. The only cross-subsystem libraries live under `/lib/` (`avionics_sensors.lua` and `ota_agent.lua`).
- Zero-Fallback (`ver = "1.9.5"`): Every OTA packet MUST use the strict top-level ICD `1.9.5` envelope (`ver`, `domainId`, `seq`, `type`, `time`, `payload`). No dual-key fallbacks (`pkt.ver or pkt.version`).
- Do NOT modify `src/1_control/asa/**` (`0 diff` frozen until `TASK-105` resumes).
- Never use `printError` in CC:Tweaked Lua (forbidden by harness UI auditor).
- Windows PowerShell 5.1 shell: chain commands with `; if ($?) { ... }`, never `&&`. Use `& "C:\Program Files\Git\cmd\git.exe"` for Git.
- Never place `ota_agent.lua` in `manifest.SHARED_LIBS` yet because `verify_manifest_sync.py` requires all `SHARED_LIBS` entries in `config/gdrive_mapping.json` (deferred to `TASK-501`). Register `ota_agent.lua` in module `files` arrays with `gdriveId = nil` and whitelist `SHARED_OTA_AGENT_REPO_PATH` in `verify_manifest_sync.py` identically to `SHARED_SENSOR_REPO_PATH`.

**Review Focus (5 Real Failure Modes Pinned to Verification):**
1. **Mid-transfer chunk loss, reordering, or CRC32 corruption leaving partial live files:** Verified in Task 3 (`test_ota_agent.lua`) and Task 7 (`test_e2e_ota_deploy_rollback.lua`) where invalid CRC32 or missing chunk aborts inside `/ota_staging/<txId>/` without modifying live target files or `/.version.json`.
2. **OTA packet accepted while airborne, `ARMING`, `NORMAL`, or `FAILSAFE_HOLD`:** Verified in Task 3 (`ota_agent.is_safe_for_ota`) and Task 4 (`VAS`/`TCA`/`FCP`/`AMM` unit tests) plus Task 7 E2E, asserting immediate `MSG_OTA_NACK` (`reason = "NOT_DISARMED"`) and zero disk mutation.
3. **Newly flashed Lua syntax error, runtime crash on boot, or pre-commit hang/crash loop:** Verified in Task 2 (`test_migration_and_startup.lua`) and Task 7 (`test_e2e_ota_deploy_rollback.lua`), asserting automatic restoration of `/ota_backup/<txId>/` + `/.version.json`, deletion of `/.ota_pending.json`, creation of `/.ota_rollback.json`, and reboot/recovery without manual intervention.
4. **Multi-module `/.version.json` ownership / missing metadata / orphan conflict across hangar targets:** Verified in Task 3 (`test_ota_agent.lua`), Task 5 (`test_ota_server.lua`), and Task 7 (`test_e2e_ota_deploy_rollback.lua`), ensuring `targetDomainId` + `targetModuleId` filtering prevents a `TCA` packet from flashing a `VAS` computer on the same bay channel, and missing `/.version.json` falls back cleanly to configured module metadata rather than crashing.
5. **Hangar channel `0..100` collision, Bay ID mismatch, or packet payload overflow:** Verified in Task 1 (`verify_contracts.py`), Task 5 (`test_ota_protocol.lua` chunk sizing <= 2048 bytes per chunk), and Task 6 (`verify_runtime_wiring.py`, `run_boot_smoke.py`).

---

## Task 1: OTA ICD `I-13` Specification, Subsystem Spec Updates, & Contract SSOT (`TASK-117-1`)

**Files:**
- Create: `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/README.md` (if module list / spec count needs alignment)
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Modify: `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
- Modify: `config/protocol_contracts.json`
- Modify: `tools/verify_all_specs.py`
- Modify: `tools/verify_spec_status.py`
- Modify: `tests/harness/test_verify_contracts.py`

**Interfaces:**
- Produces: Wire protocol SSOT in `config/protocol_contracts.json`:
  - `channels.hangar.offsets`: add `"otaCmd": 4`, `"otaAck": 5` (`Base_hangar + 4` / `Base_hangar + 5`, default Bay 1 = `105` / `106`, strictly outside `0..100`).
  - `interfaces`: add `I-13` (`OTA Server <-> Onboard Nodes [VAS/TCA/FCP/AMM]`, `band: "hangar"`, `channels: ["Base_hangar + 4", "Base_hangar + 5"]`) defining 10 canonical `1.9.5` packet types:
    - `MSG_OTA_DISCOVER_REQ`: `{ targetModuleId, targetDomainId }`
    - `MSG_OTA_DISCOVER_ACK`: `{ moduleId, versions, filesCount, controlState, isAirborne, freeSpace, agentVer }`
    - `MSG_OTA_BEGIN`: `{ txId, targetDomainId, targetModuleId, targetVersion, overwriteConfig, files, totalBytes, totalCrc32 }` (`files = { { path, size, crc32, chunkCount }, ... }`, `overwriteConfig` optional boolean default `false`)
    - `MSG_OTA_CHUNK`: `{ txId, targetDomainId, targetModuleId, fileIndex, chunkIndex, chunkCrc32, data }`
    - `MSG_OTA_COMMIT`: `{ txId, targetDomainId, targetModuleId, autoReboot }`
    - `MSG_OTA_ABORT`: `{ txId, targetDomainId, targetModuleId, reason }`
    - `MSG_OTA_REBOOT`: `{ txId, targetDomainId, targetModuleId }`
    - `MSG_OTA_ACK`: `{ txId, moduleId, phase, fileIndex, chunkIndex, status }` (`phase` in `{"BEGIN", "CHUNK", "APPLIED"}`)
    - `MSG_OTA_NACK`: `{ txId, moduleId, phase, reason, expectedIndex }` (`reason` in `{"NOT_DISARMED", "MODULE_MISMATCH", "DOMAIN_MISMATCH", "CRC_MISMATCH", "SEQ_OUT_OF_ORDER", "DISK_ERROR", "TX_NOT_FOUND"}`)
    - `MSG_OTA_BOOT_STATUS`: `{ txId, moduleId, status, version, rollbackReason }` (`status` in `{"COMMITTED", "ROLLED_BACK"}`)
- Consumes: Existing `AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` `v1.31.0` (`I-1..I-12`), `config/protocol_contracts.json` envelope `1.9.5`.

- [ ] **Step 1: Update contract validator test to expect `I-13` (Red)**

In `tests/harness/test_verify_contracts.py`, locate the assertion checking interface count (`len(ifaces) == 12`) and update/add an expectation asserting `I-13` is registered with `hangar.offsets.otaCmd == 4` and `hangar.offsets.otaAck == 5`:

```python
def test_protocol_contracts_includes_ota_i13_and_hangar_offsets(self):
    contracts = json.loads((REPO_ROOT / "config" / "protocol_contracts.json").read_text(encoding="utf-8"))
    self.assertEqual(contracts["channels"]["hangar"]["offsets"]["otaCmd"], 4)
    self.assertEqual(contracts["channels"]["hangar"]["offsets"]["otaAck"], 5)
    iface_ids = {item["id"] for item in contracts["interfaces"]}
    self.assertIn("I-13", iface_ids)
```

Also update the existing interface count check (`12` -> `13`, `I-1..I-13`). Run the test to confirm failure before editing `config/protocol_contracts.json`:

```powershell
python -m unittest tests/harness/test_verify_contracts.py
```

Expected: `FAIL` (`KeyError: 'otaCmd'` / `AssertionError: 'I-13' not found`).

- [ ] **Step 2: Author `OTA_PROGRAM_SPECIFICATION.md` and update `protocol_contracts.json` + system/subsystem specs**

1. Create `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` following the exact metadata table header from `FDR_PROGRAM_SPECIFICATION.md` (`문서 버전: v0.1.0`, `작성일: 2026-11-15`, `최종 수정일: 2026-11-15`, `문서 상태: Approved`, `대상 서브시스템: src/0_development/ota/ & /lib/ota_agent.lua`). Document:
   - Overview & Hangar Channel Allocation (`Base_hangar = 101 + (BayID - 1) * 10`; `Base_hangar + 4` `CH_OTA_CMD`; `Base_hangar + 5` `CH_OTA_ACK`; `0..100` forbidden).
   - Multi-Node Addressing (`/.version.json` discovery, `targetDomainId` + `targetModuleId` routing across `vas`, `tca`, `fcp`, `amm`).
   - 10 canonical `I-13` `1.9.5` packet schemas (exact field names matching `config/protocol_contracts.json`), Zero-Fallback rule.
   - Slave Safety Gate rules per subsystem (`VAS`, `TCA`, `FCP`, `AMM`).
   - Atomic Staging, CRC32 Verification, `/ota_backup/<txId>/` Snapshot, `/.ota_pending.json` 2-Stage Boot Commit Watchdog, and Automatic Rollback Protocol.
   - CLI / `51x19` TUI Server modes and `config/ota_config.json` schema.
   - `Revision History` table (`v0.1.0 | 2026-11-15 | Initial Approved OTA & Atomic Rollback Specification | TASK-117-1`).
2. Update `config/protocol_contracts.json`:
   - Add `"otaCmd": 4, "otaAck": 5` to `channels.hangar.offsets`.
   - Add `I-13` entry to `interfaces` with all 10 packet definitions and exact required payload keys.
3. Update `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` and `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`:
   - Register `I-13` (`OTA Server <-> Onboard Nodes`) and update hangar channel map (`+4 CH_OTA_CMD`, `+5 CH_OTA_ACK`).
4. Update `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`:
   - Update the `+4~+9` reserved channel note to mark `Base_hangar + 4` (`CH_OTA_CMD`) and `Base_hangar + 5` (`CH_OTA_ACK`) as allocated to `I-13` OTA and `+6~+9` as `CH_RESERVED_06~09` (avoid writing bare `Base+6` / `Base+7` substrings that trigger `verify_all_specs.py` Rule 6). Keep `Implemented` status since `alignment` runtime code is unchanged.
5. Update `INSTALLER_PROGRAM_SPECIFICATION.md`, `VAS_PROGRAM_SPECIFICATION.md`, `TCA_PROGRAM_SPECIFICATION.md`, `FCP_PROGRAM_SPECIFICATION.md`, `AMM_PROGRAM_SPECIFICATION.md`:
   - Add OTA `/lib/ota_agent.lua` integration, `Base_hangar + 4/+5` listener, safe-state gate, `confirm_boot_commit()`, and `startup_generator` 2-stage boot watchdog requirements.
   - Transition their `문서 상태` to `Approved` (per `skill-workflows.md` Revision Protocol since their `src/` code will be modified in Tasks 2 & 4) and add `Revision History` entries for `2026-11-15`.

- [ ] **Step 3: Update spec governance scripts (`verify_all_specs.py`, `verify_spec_status.py`)**

1. In `tools/verify_all_specs.py`, add `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` to `SPEC_FILES` and `REVISION_HISTORY_SPECS`.
2. In `tools/verify_spec_status.py`, add `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md` to `TARGET_APPROVED` (and temporarily move `INSTALLER`, `VAS`, `TCA`, `FCP`, `AMM` into `TARGET_APPROVED` alongside `OTA` until Task 7 promotes all 6 back to `Implemented`).

- [ ] **Step 4: Run spec & contract validators (Green)**

```powershell
python -m unittest tests/harness/test_verify_contracts.py ; if ($?) { python tools/verify_contracts.py --specs-only } ; if ($?) { python tools/verify_all_specs.py --check-readmes } ; if ($?) { python tools/verify_spec_status.py }
```

Expected: All pass with `0 errors, 0 warnings`.

- [ ] **Step 5: Commit Task 1**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add config/protocol_contracts.json docs/ tools/verify_all_specs.py tools/verify_spec_status.py tests/harness/test_verify_contracts.py ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(ota): add I-13 OTA spec, hangar +4/+5 contracts, and subsystem ICD updates" }
```

---

## Task 2: 2-Stage Boot Commit Watchdog in `startup_generator.lua` (`TASK-117-2a`)

**Files:**
- Modify: `src/0_development/installer/modules/startup_generator.lua`
- Modify: `tests/0_development/installer/test_migration_and_startup.lua`

**Interfaces:**
- Produces (inside generated `/startup.lua` hook from `startup_generator.generateHookContent(spec)`):
  - Checks `/.ota_pending.json` before invoking `target`.
  - Pending schema: `{ txId, moduleId, targetVersion, backupDir, versionBackupPath, restoredFiles, files, bootAttempts, maxBootAttempts, status }`.
  - Functions embedded cleanly into the generated startup script (or delegating to helper block inside `/startup.lua` with zero external dependencies so rollback works even if `/lib/ota_agent.lua` itself was corrupted by an OTA update!):
    - If `/.ota_pending.json` exists and `bootAttempts >= maxBootAttempts`: restore all files from `backupDir` (and `versionBackupPath` -> `/.version.json`), delete `/.ota_pending.json`, write `/.ota_rollback.json` (`{ txId, moduleId, reason = "BOOT_WATCHDOG_TIMEOUT", timestamp }`), clean up `backupDir`, then load the restored `target`.
    - Otherwise if `/.ota_pending.json` exists: increment `bootAttempts = bootAttempts + 1`, persist `/.ota_pending.json` immediately before running `target`.
    - Load `target` via `loadfile(target, nil, env)` and run via `pcall(fn, unpackFn(hookArgs))`.
    - If `not fn` (syntax/load error) or `not okRun` (runtime crash) AND `/.ota_pending.json` still exists: restore backup files + `/.version.json`, delete `/.ota_pending.json`, write `/.ota_rollback.json` (`reason = "BOOT_LOAD_ERROR"` or `"BOOT_RUNTIME_CRASH"`, `error = tostring(err)`), and reboot via `if not _G.__OTA_DISABLE_REBOOT and os and os.reboot then os.reboot() end` (only erroring when NOT under OTA rollback or re-raising only if not pending).
- Consumes: Existing `startup_generator.generateHookContent(spec)` and `startup_generator.installHook(spec, targetRoot, fsApi)`.

- [ ] **Step 1: Write failing rollback watchdog unit tests in `tests/0_development/installer/test_migration_and_startup.lua` (Red)**

Append 3 focused tests to `tests/0_development/installer/test_migration_and_startup.lua` using an isolated temp dir + mocked `_G.__OTA_DISABLE_REBOOT = true` (or mocked `os.reboot` spy):
1. **Syntax/Load Error Rollback:** Install hook for `/app/main.lua` containing broken Lua syntax (`"invalid lua @@@"`), place valid previous file in `/ota_backup/tx-01/app/main.lua` and `/.version.json.bak` -> `/.version.json`, write `/.ota_pending.json` (`txId="tx-01"`, `bootAttempts=0`, `maxBootAttempts=1`), execute hook via `dofile(expectedHookPath)`. Assert: `/app/main.lua` equals the backed-up valid content, `/.ota_pending.json` is deleted, `/.ota_rollback.json` exists with `txId == "tx-01"` and `reason == "BOOT_LOAD_ERROR"`, and `reboot` spy was triggered.
2. **Runtime Crash Rollback:** Install hook for `/app/main.lua` calling `error("nil deref")`, run hook with `/.ota_pending.json`. Assert: `/app/main.lua` restored from backup, `/.ota_pending.json` removed, `/.ota_rollback.json` has `reason == "BOOT_RUNTIME_CRASH"`.
3. **Pre-Commit Reboot Loop Rollback (`bootAttempts >= maxBootAttempts`):** Write `/.ota_pending.json` with `bootAttempts=1`, `maxBootAttempts=1`, place new buggy `/app/main.lua` that exits before calling `confirm_boot_commit()`, and valid backup. Execute hook. Assert: backup is restored BEFORE running `/app/main.lua`, `/.ota_pending.json` is removed, `/.ota_rollback.json` has `reason == "BOOT_WATCHDOG_TIMEOUT"`, and restored `/app/main.lua` runs cleanly without calling `reboot`.

Run unit tests for installer to confirm Red:

```powershell
python tools/run_unit_tests.py --target installer --clean-orphans
```

Expected: `FAIL` (rollback watchdog logic not present in `startup_generator.lua` yet).

- [ ] **Step 2: Implement self-contained 2-stage watchdog in `startup_generator.lua`**

Update `startup_generator.generateHookContent(spec)` in `src/0_development/installer/modules/startup_generator.lua`:
- Keep `/lib/?.lua` package.path injection, `cc.require.make`, and `args` forwarding intact so existing `test_migration_and_startup.lua` L173 (`dofile(expectedHookPath)` when `/.ota_pending.json` does NOT exist) behaves identically.
- Embed a pure-CC-`fs`+`textutils` rollback helper block inside the generated hook string (with zero `require` dependencies so even if `/lib/` is damaged, recovery still executes).
- Ensure `fs.makeDir` creates parent directories before restoring each backed-up file, copies cleanly, removes backup dir + `/.ota_pending.json`, writes `/.ota_rollback.json`, and invokes `os.reboot()` (respecting mocked `os.reboot` / `_G.__OTA_DISABLE_REBOOT` test guard cleanly).
- Note: Respect the zero-overclaim rule in comments; document the non-obvious *why* (self-contained inside `/startup.lua` because `/lib/ota_agent.lua` itself might be the broken file).

- [ ] **Step 3: Run installer unit tests (Green)**

```powershell
python tools/run_unit_tests.py --target installer --clean-orphans
```

Expected: All tests in `tests/0_development/installer/` PASS (including all existing tests + 3 new watchdog rollback tests).

- [ ] **Step 4: Commit Task 2**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/startup_generator.lua tests/0_development/installer/test_migration_and_startup.lua ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(installer): add 2-stage OTA boot watchdog and automatic backup rollback in startup hook" }
```

---

## Task 3: Self-Contained Slave `ota_agent.lua` (`/lib/ota_agent.lua`) & CRC32 (`TASK-117-2b`)

**Files:**
- Create: `src/0_development/ota/ota_agent.lua`
- Create: `tests/0_development/ota/test_ota_agent.lua`

**Interfaces:**
- Produces (`local ota_agent = {}`):
  - `ota_agent.AGENT_VERSION = "1.0.0"`
  - `ota_agent.ICD_VERSION = "1.9.5"`
  - `ota_agent.HANGAR_BAY_BASE = 101`, `ota_agent.HANGAR_BAY_BANDWIDTH = 10`
  - `ota_agent.OFFSET_CMD = 4`, `ota_agent.OFFSET_ACK = 5`
  - `ota_agent.get_channels(bayId) -> cmdChannel, ackChannel` (computes `101 + (bayId - 1) * 10 + 4` and `+ 5`, clamps/validates `bayId` in `1..10`, asserts result `>= 105`)
  - `ota_agent.crc32(str) -> number` (unsigned 32-bit CRC32, IEEE 802.3 `0xEDB88320`, using `bit32` with pure-Lua 5.2 fallback if `bit32` is nil)
  - `ota_agent.is_safe_for_ota(status) -> boolean, string|nil` (`status = { controlState, isAirborne }`: requires `status.isAirborne ~= true` and `status.controlState` in `{"DISARMED", "BOOT", "IDLE_ARMED"}`; rejects `"ARMING"`, `"NORMAL"`, `"CALIBRATION"`, `"FAILSAFE_HOLD"`, `"EMERGENCY_LAND"`, `"AIRBORNE_EMERGENCY"`, `"E_STOP"`, `"ACTIVE_TRACKING"`, `"PASSIVE_TRACKING"`, `"AMM_TIMEOUT_HOLD"`, or `isAirborne == true` with `false, "NOT_DISARMED"`)
  - `ota_agent.new(opts) -> agent` (`opts = { moduleId, domainId, bayId, bayIds, bootConfirmTicks, fsApi, modemApi, getStatusFn, onRebootFn, rootDir, seqFn, clockFn }`, where `bayIds` defaults to `{ tonumber(bayId) or 1 }` and `bootConfirmTicks` defaults to `20`)
  - `agent:open_channels() -> cmdChannels, ackChannels` (opens all configured bay CMD channels, returning primary `cmdCh, ackCh` or channel lists cleanly)
  - `agent:handle_packet(channel, replyChannel, rawPacket) -> boolean, string|nil` (accepts any opened bay `cmdCh`, validates strict ICD `1.9.5` envelope, handles `MSG_OTA_DISCOVER_REQ`, `MSG_OTA_BEGIN`, `MSG_OTA_CHUNK`, `MSG_OTA_COMMIT`, `MSG_OTA_ABORT`, `MSG_OTA_REBOOT`; preserves existing `config/*.json` unless `overwriteConfig == true`; snapshots & removes module-exclusive orphan files tracked in `/.version.json`; writes `/.ota_pending.json` with `maxBootAttempts = 1`; emits `MSG_OTA_DISCOVER_ACK`, `MSG_OTA_ACK`, or `MSG_OTA_NACK` on matching bay `ackCh`)
  - `agent:tick_boot_commit() -> boolean, table|nil` (increments healthy runtime tick counter; once `bootTicks >= bootConfirmTicks` (20 ticks default), delegates to `agent:confirm_boot_commit()`)
  - `agent:confirm_boot_commit() -> boolean, table|nil` (immediately clears `/ota_backup/<txId>/` and `/.ota_pending.json` and transmits `MSG_OTA_BOOT_STATUS` with `status = "COMMITTED"`; if `/.ota_rollback.json` exists, transmits `MSG_OTA_BOOT_STATUS` with `status = "ROLLED_BACK"` and clears `/.ota_rollback.json`)
- Consumes: Standard CC `fs`, `textutils`, `os`, `bit32` (injected via `opts` for isolated unit testing). Zero external `require` calls so `/lib/ota_agent.lua` works standalone on every node.

- [ ] **Step 1: Write failing unit tests in `tests/0_development/ota/test_ota_agent.lua` (Red)**

Test cases to write:
1. **CRC32 Known Vectors:** `ota_agent.crc32("") == 0`, `ota_agent.crc32("123456789") == 0xCBF43926`.
2. **Hangar Channel Calculation:** `get_channels(1) == 105, 106`; `get_channels(10) == 195, 196`; invalid `bayId = 0` errors cleanly (`> 100` invariant).
3. **Envelope & Safety Gate Enforcement:** Non-`1.9.5` packet is ignored/NACKed; `MSG_OTA_BEGIN` when `isAirborne = true` or `controlState = "NORMAL"` / `"ARMING"` / `"FAILSAFE_HOLD"` emits `MSG_OTA_NACK` (`reason = "NOT_DISARMED"`) and leaves `/ota_staging` untouched.
4. **Module & Domain Addressing:** Packet with `targetModuleId = "tca"` on a `"vas"` agent is ignored without error; `targetModuleId = "vas"` + `targetDomainId = "UAV-01"` succeeds.
5. **Nominal Chunked Staging & Atomic Commit:** Send `MSG_OTA_DISCOVER_REQ` -> assert `MSG_OTA_DISCOVER_ACK`; send `MSG_OTA_BEGIN` -> `MSG_OTA_CHUNK` (2 files, multiple chunks) -> `MSG_OTA_COMMIT` (`autoReboot = false` in commit phase test or verify `onRebootFn` fired when `autoReboot = true`). Assert: live files updated atomically, `/ota_backup/<txId>/` holds original files, `/.ota_pending.json` written with `status = "PENDING_COMMIT"`, `/.version.json` updated with new `targetVersion`, `MSG_OTA_ACK` (`phase = "APPLIED"`) sent.
6. **CRC32 Mismatch Abort & Zero-Pollution:** Send `MSG_OTA_CHUNK` with bad `chunkCrc32` or corrupted payload under valid total CRC mismatch -> assert `MSG_OTA_NACK` (`reason = "CRC_MISMATCH"`), live files completely untouched, staging cleaned up.
7. **Config Preservation, Orphan Cleanup & Stabilized Boot Commit:** Deploy package containing both `.lua` and `config/vas_config.json` when `overwriteConfig = false` and an old orphan `/vas/modules/legacy.lua` exists in `/.version.json`: assert existing `config/vas_config.json` is preserved, `/vas/modules/legacy.lua` is backed up to `/ota_backup/<txId>/` and removed from live FS (and restored if rollback occurs). Call `agent:tick_boot_commit()` `bootConfirmTicks - 1` times -> assert `/.ota_pending.json` still exists; on tick `bootConfirmTicks` (or direct `agent:confirm_boot_commit()`) -> deletes pending + backup and emits `MSG_OTA_BOOT_STATUS` (`status = "COMMITTED"`). Call `confirm_boot_commit()` / `tick_boot_commit()` when `/.ota_rollback.json` exists -> emits `MSG_OTA_BOOT_STATUS` (`status = "ROLLED_BACK"`) and deletes marker.

Run test (expect failure because `ota_agent.lua` does not exist yet):

```powershell
python tools/run_unit_tests.py --target ota --clean-orphans
```

Expected: `FAIL` / module `ota_agent` not found.

- [ ] **Step 2: Implement `src/0_development/ota/ota_agent.lua`**

Implement `src/0_development/ota/ota_agent.lua` cleanly:
- Precompute 256-entry IEEE CRC32 lookup table using `bit32` (or pure Lua helper if `bit32` is nil).
- Helper `split_root_path(rootDir, p)` so unit tests can isolate filesystem roots to temp dirs while production uses `"/"`.
- Keep functions small and single-purpose: `make_envelope`, `send_ack`, `send_nack`, `handle_discover`, `handle_begin`, `handle_chunk`, `handle_commit`, `handle_abort`, `snapshot_backups`, `apply_staging`, `update_version_json`.
- Zero `require(...)` imports at top-level.
- Update `/.version.json` safely even when `/.version.json` does not yet exist (initializes `{ installerVersion = "ota", modules = { [moduleId] = ... } }`), preserving other modules' entries if present.

- [ ] **Step 3: Run `ota` unit tests (Green)**

```powershell
python tools/run_unit_tests.py --target ota --clean-orphans
```

Expected: All `test_ota_agent.lua` assertions PASS.

- [ ] **Step 4: Commit Task 3**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/ota/ota_agent.lua tests/0_development/ota/test_ota_agent.lua ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(ota): implement self-contained slave ota_agent with CRC32, staging, and safety gate" }
```

---

## Task 4: Onboard Node Integration (`VAS`, `TCA`, `FCP`, `AMM`) (`TASK-117-3`)

**Files:**
- Modify: `src/1_control/vas/main.lua`, `src/1_control/vas/modules/core_daemon.lua`, `src/1_control/vas/modules/network_manager.lua` (plus `config/` if default `ota` section is declared)
- Modify: `src/1_control/tca/main.lua`, `src/1_control/tca/modules/tca_daemon.lua`
- Modify: `src/2_guidance/fcp/main.lua`, `src/2_guidance/fcp/modules/network_manager.lua`
- Modify: `src/3_planning/amm/main.lua`, `src/3_planning/amm/modules/network_manager.lua`
- Create/Modify unit tests:
  - `tests/1_control/vas/test_vas_ota_integration.lua`
  - `tests/1_control/tca/test_tca_ota_integration.lua`
  - `tests/2_guidance/fcp/test_fcp_ota_integration.lua`
  - `tests/3_planning/amm/test_amm_ota_integration.lua`

**Interfaces:**
- Consumes: `require("ota_agent")` (with graceful `pcall(require, "ota_agent")` guard or guaranteed `/lib/ota_agent.lua` staging; remember `verify_runtime_wiring.py` checks `require` targets against `IGNORED_REQUIRE_TARGETS`, handled in Task 6 — meanwhile unit test harness stages `/lib/ota_agent.lua` or updates `harness/unit/engine.py` early if needed). Note: Stage `ota_agent.lua` in `harness/unit/engine.py` in Step 1 if unit runner needs `/lib/ota_agent.lua` immediately!
- Safety state mapping per subsystem:
  - **VAS** (`core_daemon.init` / `tick` / `handle_event`): `status = { controlState = state.fsm.currentState, isAirborne = state.fsm.isAirborne }`. Opens configured `ota.bayId`/`ota.bayIds` CMD channel(s) (default Bay 1 `105`). Calls `state.otaAgent:tick_boot_commit()` each main control tick until confirmed (~1s / `bootConfirmTicks = 20` default). Forwards `modem_message` on OTA CMD channel(s) to `state.otaAgent:handle_packet(...)`.
  - **TCA** (`tca_daemon.init` / `step_event` / `dispatch_modem_message`): `status = { controlState = inst.lastControlState or "DISARMED", isAirborne = (inst.adapterState and inst.adapterState.lastSignal or 0) > 0 }`. Opens configured `ota.bayId`/`ota.bayIds`. Calls `inst.otaAgent:tick_boot_commit()` on healthy `step_event` ticks until confirmed. Routes OTA CMD channel frames to `inst.otaAgent:handle_packet(...)`.
  - **FCP** (`fcp_main.create_context` / `step_tick` / `network_manager`): `status = { controlState = ctx.fsm.currentState, isAirborne = (ctx.lastTelemPayload and ctx.lastTelemPayload.isAirborne == true) or (ctx.lastTelemPayload and (ctx.lastTelemPayload.controlState == "NORMAL" or ctx.lastTelemPayload.controlState == "FAILSAFE_HOLD" or ctx.lastTelemPayload.controlState == "EMERGENCY_LAND" or ctx.lastTelemPayload.controlState == "AIRBORNE_EMERGENCY")) or false }`. Calls `ctx.otaAgent:tick_boot_commit()` on healthy `step_tick` ticks until confirmed. Routes OTA CMD channel frames to `ctx.otaAgent:handle_packet(...)`.
  - **AMM** (`amm/main.lua` `handle_modem_message` / `network_manager.open_channels` / timer loop): `status = { controlState = (app.arbiter and app.arbiter.fsmState) or "DISARMED", isAirborne = (app.arbiter and app.arbiter.latest_telem and app.arbiter.latest_telem.isAirborne == true) or false }`. Opens configured `ota.bayId`/`ota.bayIds`. Calls `app.otaAgent:tick_boot_commit()` on healthy loop ticks until confirmed. Routes OTA CMD channel frames to `app.otaAgent:handle_packet(...)`.
- Produces: Every target node autonomously opens `Base_hangar + 4`, responds to OTA discovery/transfer when disarmed on ground, rejects OTA with `NOT_DISARMED` when armed/airborne, and commits pending updates once healthy.
- **Invariant Check:** `src/1_control/asa/**` MUST remain 100% untouched (`0 diff`).

- [ ] **Step 1: Ensure `harness/unit/engine.py` stages `/lib/ota_agent.lua` and write failing integration tests for VAS, TCA, FCP, AMM (Red)**

1. Check `harness/unit/engine.py` (around `_stage_shared_sensors` / `/lib/` staging): add `src/0_development/ota/ota_agent.lua` -> `/lib/ota_agent.lua` staging right beside `src/0_development/sensors/avionics_sensors.lua` -> `/lib/avionics_sensors.lua` so all subsystem unit tests can `require("ota_agent")` via `/lib/?.lua`.
2. Write 4 minimal, high-signal unit test files (`tests/1_control/vas/test_vas_ota_integration.lua`, `tests/1_control/tca/test_tca_ota_integration.lua`, `tests/2_guidance/fcp/test_fcp_ota_integration.lua`, `tests/3_planning/amm/test_amm_ota_integration.lua`):
   - Each test initializes the subsystem daemon/context with a mock modem + isolated temp FS containing `/.ota_pending.json`.
   - Asserts `confirm_boot_commit()` runs on the first healthy tick and emits `MSG_OTA_BOOT_STATUS` (`COMMITTED`).
   - Asserts `MSG_OTA_DISCOVER_REQ` on `105` returns `MSG_OTA_DISCOVER_ACK` on `106` with correct `moduleId` (`"vas"`, `"tca"`, `"fcp"`, `"amm"`).
   - Asserts switching node state to armed/airborne causes `MSG_OTA_BEGIN` to return `MSG_OTA_NACK` (`reason = "NOT_DISARMED"`).

Run tests to confirm Red:

```powershell
python tools/run_unit_tests.py --target vas tca fcp amm --clean-orphans
```

Expected: New OTA integration tests FAIL (nodes do not open `105` or attach `otaAgent` yet).

- [ ] **Step 2: Wire `ota_agent` into `VAS`, `TCA`, `FCP`, and `AMM`**

Implement minimal, clean wiring in each of the 4 subsystems:
- `src/1_control/vas/modules/core_daemon.lua` & `network_manager.lua` & `main.lua`
- `src/1_control/tca/modules/tca_daemon.lua` & `main.lua`
- `src/2_guidance/fcp/modules/network_manager.lua` & `main.lua`
- `src/3_planning/amm/modules/network_manager.lua` & `main.lua`

Make sure `bayId` defaults to `1` (`105`/`106`) if `ota.bayId` is absent in subsystem config, `domainId` reads from the node's config (`system.domainId` / `aircraft.domainId` / `domainId`), and normal flight channels keep top priority in event dispatch.

- [ ] **Step 3: Run unit tests for VAS, TCA, FCP, AMM and verify `asa` `0 diff` (Green)**

```powershell
python tools/run_unit_tests.py --target vas tca fcp amm --clean-orphans ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" diff --exit-code src/1_control/asa/ }
```

Expected: All unit tests in `vas`, `tca`, `fcp`, `amm` PASS; `git diff --exit-code src/1_control/asa/` exits `0`.

- [ ] **Step 4: Commit Task 4**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add harness/unit/engine.py src/1_control/vas/ src/1_control/tca/ src/2_guidance/fcp/ src/3_planning/amm/ tests/1_control/vas/ tests/1_control/tca/ tests/2_guidance/fcp/ tests/3_planning/amm/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(onboard): integrate ota_agent safety gate and boot commit across VAS, TCA, FCP, AMM" }
```

---

## Task 5: Hangar Wireless OTA Deployment Server (`src/0_development/ota/`) (`TASK-117-4a`)

**Files:**
- Create: `src/0_development/ota/config/ota_config.json`
- Create: `src/0_development/ota/modules/ota_protocol.lua`
- Create: `src/0_development/ota/modules/ota_server.lua`
- Create: `src/0_development/ota/modules/ota_ui.lua`
- Create: `src/0_development/ota/main.lua`
- Create: `tests/0_development/ota/test_ota_server.lua`

**Interfaces:**
- Consumes: `require("ota_agent")` (specifically `ota_agent.crc32` and `ota_agent.get_channels` — zero duplicated CRC32 code!), CC `modem`, `fs`, `http` (optional, for remote GitHub/manifest sync), `textutils`, `os`, `term`, `parallel`.
- `config/ota_config.json`: `{ version = "0.1.0", ota = { bayId = 1, chunkSize = 2048, ackTimeoutSec = 1.5, maxRetries = 3, defaultSourceDir = "/ota_packages", autoSyncOnBoot = false, manifestUrl = "https://raw.githubusercontent.com/sjmik1004/Create_Aeroneutics/main/src/0_development/installer/modules/manifest.lua", githubRawBase = "https://raw.githubusercontent.com/sjmik1004/Create_Aeroneutics/main/" }, network = { domainId = "HANGAR-OTA-01" } }`.
- `ota_protocol.lua`:
  - `ota_protocol.ICD_VERSION = "1.9.5"`
  - `ota_protocol.build_envelope(domainId, seq, msgType, payload, nowMs) -> table`
  - `ota_protocol.parse_envelope(raw, expectedVer) -> table|nil, string|nil`
  - `ota_protocol.chunk_file(relPath, content, chunkSize) -> fileManifest, chunks` (computes per-file size/CRC32 and per-chunk CRC32 via `ota_agent.crc32`)
- `ota_server.lua`:
  - `ota_server.new(opts) -> server` (`opts = { config, modem, fsApi, httpApi, rootDir, clockFn, sleepFn, pollEventFn }`)
  - `server:sync_remote(opts) -> boolean, table` (when `httpApi` is present, fetches remote `manifest.lua` + target module files from GitHub Raw and stages `ota_package.json` + files into `/ota_packages/<moduleId>/`, triggered automatically on startup when `autoSyncOnBoot == true` or via CLI `sync` / TUI `[S]ync`)
  - `server:discover(opts) -> discoveredNodes` (broadcasts `MSG_OTA_DISCOVER_REQ` on `cmdCh`, collects `MSG_OTA_DISCOVER_ACK` during `discoverWindowSec`)
  - `server:load_package(packageDirOrManifest) -> package, string|nil` (reads target module files + versions from `/ota_packages/<moduleId>/ota_package.json`)
  - `server:deploy(targetSpec, package, opts) -> boolean, table` (`targetSpec = { domainId, moduleId, overwriteConfig }`: sends `MSG_OTA_BEGIN` -> awaits `MSG_OTA_ACK`; sends each `MSG_OTA_CHUNK` with ACK/NACK retry up to `maxRetries`, re-sending on timeout or `SEQ_OUT_OF_ORDER`; sends `MSG_OTA_COMMIT` -> awaits `MSG_OTA_ACK` (`APPLIED`); optionally awaits `MSG_OTA_BOOT_STATUS` (`COMMITTED` or `ROLLED_BACK`) after reboot)
- `ota_ui.lua` & `main.lua`:
  - CLI support (`main.lua discover [--bay=N]`, `main.lua sync [moduleId]`, `main.lua deploy <moduleId> <domainId> <packageDir> [--bay=N]`), AND interactive `51x19` TUI (node list, safety status badge, chunk progress bar, `[D]iscover`, `[S]ync`, `[U]pdate`, `[B]ay`, `[Q]uit`) when launched interactively without CLI action args (headless-safe under `--headless` or test `os.shutdown` event).
  - Never calls `printError`.

- [ ] **Step 1: Write failing server unit tests in `tests/0_development/ota/test_ota_server.lua` (Red)**

Test cases to write (using an in-memory paired virtual modem connecting `ota_server` and a real `ota_agent` instance, plus mock `httpApi`!):
1. **Remote Sync Staging:** Mock `httpApi.get` returning a valid `manifest.lua` snippet + `tca` files; call `server:sync_remote({ moduleIds = { "tca" } })`; assert `/ota_packages/tca/ota_package.json` and downloaded files exist and load cleanly via `server:load_package`.
2. **Multi-Node Discovery:** Server sends `MSG_OTA_DISCOVER_REQ`; two virtual agents (`vas` on `"UAV-01"`, `tca` on `"UAV-01"`) respond with `MSG_OTA_DISCOVER_ACK`. Assert `server:discover()` returns both nodes indexed by `domainId`/`moduleId` with version and `controlState`.
3. **Packet Chunking & Retry on Transient Drop:** Drop the 2nd chunk once in the mock modem; assert `server:deploy(...)` retries `chunkIndex = 2`, completes transfer, verifies `APPLIED` ACK, and writes updated files on the target agent's virtual FS.
4. **Abort on Target `NOT_DISARMED` NACK:** Target agent is armed; assert `server:deploy(...)` stops immediately on `MSG_OTA_NACK` (`reason = "NOT_DISARMED"`), sends `MSG_OTA_ABORT`, returns `false, { reason = "NOT_DISARMED" }`, and target files remain unchanged.
5. **Checksum/Retry Exhaustion Rollback Abort:** Mock modem corrupts chunk continuously beyond `maxRetries`; assert server aborts cleanly without leaving corrupted live files.

Run test (expect failure):

```powershell
python tools/run_unit_tests.py --target ota --clean-orphans
```

Expected: `FAIL` (`ota_server` / `ota_protocol` not created yet).

- [ ] **Step 2: Implement `ota_config.json`, `ota_protocol.lua`, `ota_server.lua`, `ota_ui.lua`, `main.lua`**

Implement the 5 files cleanly in `src/0_development/ota/`, ensuring:
- Strict top-level ICD `1.9.5` envelope (`ver`, `domainId`, `seq`, `type`, `time`, `payload`).
- Zero unused locals/imports (`verify_runtime_wiring.py` clean).
- Zero `printError`.
- Clean shutdown path handling `"terminate"` / `os.shutdown` for `run_boot_smoke.py`.

- [ ] **Step 3: Run `ota` unit tests & Lua syntax check (Green)**

```powershell
python tools/run_unit_tests.py --target ota --clean-orphans ; if ($?) { python tools/validate_lua_syntax.py }
```

Expected: All `test_ota_agent.lua` and `test_ota_server.lua` tests PASS; `validate_lua_syntax.py` exits `0`.

- [ ] **Step 4: Commit Task 5**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/ota/ tests/0_development/ota/test_ota_server.lua ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(ota): implement hangar wireless OTA deployment server, protocol, and TUI" }
```

---

## Task 6: Installer Manifest Packaging, Wiring & Harness Registration (`TASK-117-4b`)

**Files:**
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `tools/verify_manifest_sync.py`
- Modify: `tools/verify_runtime_wiring.py`
- Modify: `tools/run_boot_smoke.py`
- Modify: `tools/run_e2e_tests.py`
- Modify: `tests/harness/test_boot_smoke_runner.py`
- Modify: `tests/harness/test_manifest_sync_verifier.py` (if assertions check exact module counts or shared injections)

**Interfaces:**
- `manifest.lua`:
  - Add `"ota"` to `MODULE_ORDER` (right after `"fdr"`).
  - Add `MODULES.ota = { id = "ota", category = "dev", label = "Wireless OTA Server", version = "0.1.0", dir = "ota", entry = "main.lua", autorun = false, files = { main.lua, config/ota_config.json, modules/ota_protocol.lua, modules/ota_server.lua, modules/ota_ui.lua, { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = nil } } }`.
  - Add `{ repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = nil }` to `files` of `vas`, `tca`, `fcp`, and `amm` in `MODULES` (NOTE: `gdriveId = nil`, NOT added to `SHARED_LIBS`).
- `verify_manifest_sync.py`:
  - Add `SHARED_OTA_AGENT_REPO_PATH = "src/0_development/ota/ota_agent.lua"` and `SHARED_OTA_AGENT_DEST = "/lib/ota_agent.lua"`, updating `is_shared_injection` (L449-466) to permit `/lib/ota_agent.lua` across categories identically to `SHARED_SENSOR_REPO_PATH`.
- `verify_runtime_wiring.py`:
  - Add `"ota_agent"`, `"/lib/ota_agent"`, `"/lib/ota_agent.lua"` to `IGNORED_REQUIRE_TARGETS` (L56-66) so `vas`/`tca`/`fcp`/`amm` `require("ota_agent")` passes static wiring checks just like `avionics_sensors`. Ensure `src/0_development/ota/main.lua` reaches `ota_protocol`, `ota_server`, `ota_ui`, and `ota_agent` (via `require("ota_agent")` in `ota_protocol.lua` or `main.lua`).
- `run_boot_smoke.py` & `run_e2e_tests.py`:
  - Update `_stage_shared_sensors` (or rename to `_stage_shared_libs`) to copy both `avionics_sensors.lua` and `ota_agent.lua` into `/lib/` inside the sandbox!
  - Register `0_development/ota` in `run_boot_smoke.py` `build_smoke_targets` (increasing active targets `11 -> 12` and total list `12 -> 13`, updating `tests/harness/test_boot_smoke_runner.py` assertions accordingly).

- [ ] **Step 1: Update `test_boot_smoke_runner.py` & `test_manifest_sync_verifier.py` expectations (Red)**

In `tests/harness/test_boot_smoke_runner.py`, add `"0_development/ota"` to expected active targets and update expected target count (`11` -> `12`, `12` -> `13`), plus add an assertion that `ota_agent.lua` is staged into `/lib/ota_agent.lua`. Run harness tests to confirm Red:

```powershell
python -m unittest tests/harness/test_boot_smoke_runner.py tests/harness/test_manifest_sync_verifier.py tests/harness/test_verify_runtime_wiring.py
```

Expected: `FAIL` (`0_development/ota` missing from `run_boot_smoke.py` targets).

- [ ] **Step 2: Update `manifest.lua`, `verify_manifest_sync.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py`, `run_e2e_tests.py`**

Apply all 5 edits cleanly, ensuring `installer` self-test (`tests/0_development/installer/`) and `manifest` sync remain consistent.

- [ ] **Step 3: Run harness, manifest, wiring, and boot smoke checks (Green)**

```powershell
python tools/verify_manifest_sync.py ; if ($?) { python tools/verify_runtime_wiring.py } ; if ($?) { python tools/run_boot_smoke.py --clean-orphans } ; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```

Expected: `verify_manifest_sync.py` `0 Errors, 0 Warnings`; `verify_runtime_wiring.py` `0 violations`; `run_boot_smoke.py` `12/12 PASS`; `tests/harness` all PASS.

- [ ] **Step 4: Commit Task 6**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/0_development/installer/modules/manifest.lua tools/verify_manifest_sync.py tools/verify_runtime_wiring.py tools/run_boot_smoke.py tools/run_e2e_tests.py tests/harness/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "build(ota): package ota module & /lib/ota_agent.lua in manifest, wiring verifier, and runners" }
```

---

## Task 7: Multi-Node E2E Verification, Full Test Gate, Spec Promotion & Context Sync (`TASK-117-5`)

**Files:**
- Create: `tests/e2e/test_e2e_ota_deploy_rollback.lua`
- Modify (promotion to `Implemented`):
  - `docs/specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md`
  - `docs/specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md`
  - `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
  - `docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
  - `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
  - `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`
  - `tools/verify_spec_status.py`
- Modify (context docs sync):
  - `TASK.md` (mark `TASK-117` `[x]` with completion summary & metrics)
  - `GEMINI.md` (update `직전 완료` & `다음 액션` & verified test counts, keep `<= 80 lines`)
  - `README.md` (update spec count `16` -> `17` / `17` -> `18` if needed per `verify_context_docs.py` R7/sync checks)
  - `.agent/memory/workspace-root.md` (append `TASK-117` completion record per `verify_context_docs.py` R8)

**Interfaces:**
- E2E suite (`tests/e2e/test_e2e_ota_deploy_rollback.lua`) validates 4 end-to-end scenarios on the shared CraftOS-PC virtual RF bus (all packets audited against `config/protocol_contracts.json` `I-13`):
  1. **Nominal Multi-Node Wireless Deploy (`VAS` + `TCA` + `FCP` + `AMM`):** Discover all 4 onboard nodes via Bay 1 (`105`/`106`), deploy updated module file to `TCA` without altering `VAS`/`FCP`/`AMM`, execute simulated reboot via `startup_generator` hook, confirm healthy boot tick calls `confirm_boot_commit()`, emits `MSG_OTA_BOOT_STATUS` (`COMMITTED`), cleans up `/ota_backup/` and `/.ota_pending.json`, and updates `/.version.json`.
  2. **Safety Gate Rejection While Armed/Airborne:** Transition `VAS` to `isAirborne = true` / `NORMAL`; deploy from `ota_server`; assert target responds with `MSG_OTA_NACK` (`reason = "NOT_DISARMED"`) and target live file + `/.version.json` are untouched.
  3. **CRC32 Tamper Abort:** Inject bit-flip into one chunk over the virtual bus; assert server + slave abort with `MSG_OTA_NACK` (`reason = "CRC_MISMATCH"`), staging is discarded, and live files remain unchanged.
  4. **Boot Crash Automatic Rollback:** Deploy a poisoned `TCA` payload containing a Lua syntax/runtime crash; run simulated reboot through `startup_generator` hook; assert watchdog detects failure, restores original `TCA` files and `/.version.json` from `/ota_backup/<txId>/`, removes `/.ota_pending.json`, writes `/.ota_rollback.json`, and restored `TCA` boots cleanly and reports `MSG_OTA_BOOT_STATUS` (`ROLLED_BACK`).

- [ ] **Step 1: Write `tests/e2e/test_e2e_ota_deploy_rollback.lua` and run E2E runner (Red -> Green)**

Write `tests/e2e/test_e2e_ota_deploy_rollback.lua` using the `harness/simulation/` virtual bus helpers (patterned after `tests/e2e/test_e2e_fdr_blackbox.lua`, ensuring `os.shutdown()` handshake at termination). Run:

```powershell
python tools/run_e2e_tests.py --clean-orphans
```

Fix any E2E defects discovered in `ota_server`, `ota_agent`, node adapters, or `startup_generator` until `run_e2e_tests.py` passes with 0 contract violations.

- [ ] **Step 2: Run full project verification gate (all suites)**

Run every guardrail and test command sequentially:

```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans ; if ($?) { python tools/run_e2e_tests.py --clean-orphans } ; if ($?) { python tools/run_boot_smoke.py --clean-orphans } ; if ($?) { python tools/verify_contracts.py } ; if ($?) { python tools/verify_runtime_wiring.py } ; if ($?) { python tools/verify_manifest_sync.py } ; if ($?) { python tools/verify_all_specs.py --check-readmes } ; if ($?) { python tools/validate_lua_syntax.py } ; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```

Also re-verify frozen subsystem:

```powershell
& "C:\Program Files\Git\cmd\git.exe" diff --exit-code src/1_control/asa/
```

Expected: Every single suite and verifier reports PASS with 0 errors/warnings/violations.

- [ ] **Step 3: Promote specs to `Implemented` & sync project context docs**

1. Update `문서 상태` -> `Implemented` and `최종 수정일` -> `2026-11-15` in the 6 modified/created specs (`OTA`, `INSTALLER`, `VAS`, `TCA`, `FCP`, `AMM`) and move them into `TARGET_IMPLEMENTED` in `tools/verify_spec_status.py`.
2. Update `TASK.md` (mark `TASK-117` `[x]`, sync any version/status badges in `TASK.md` per `_TASK_SPEC_REF_RE`), `GEMINI.md` (update `직전 완료`, `다음 액션`, `verify_spec_status.py` `Implemented`/`Approved` distribution counts, and E2E/unit/smoke counts; keep `GEMINI.md` strictly `<= 80 lines`), `README.md` (add `ota` to directory tree and sync spec/E2E/smoke counts per `verify_context_docs.py` R1–R9), and append `TASK-117` completion record to `.agent/memory/workspace-root.md`.
3. Run final doc/status/context verification:

```powershell
python tools/verify_spec_status.py ; if ($?) { python tools/verify_all_specs.py --check-readmes } ; if ($?) { python tools/verify_context_docs.py } ; if ($?) { python tools/verify_contracts.py }
```

Expected: All 4 checks PASS (`0 errors`, `0 findings`).

- [ ] **Step 4: Commit Task 7**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/e2e/test_e2e_ota_deploy_rollback.lua docs/ tools/verify_spec_status.py TASK.md GEMINI.md README.md .agent/memory/workspace-root.md ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "test(ota): add multi-node OTA deploy/rollback E2E suite and promote TASK-117 specs" }
```
