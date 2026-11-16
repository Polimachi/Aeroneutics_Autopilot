# TASK-125: 비행체 40채널 블록 개편 및 프로토콜·경합·검증 결함 12종 해소 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TASK-125-1`부터 `TASK-125-13`까지 비행체 40채널 블록(`10000..49960`, `BW=40`)의 채널 혼재(`Base+0`/`Base+1`), `Base+3` 이중 송신자 경합, 동시 부팅 및 꺼진 점유자 프로브 충돌, Zone 3 확장(`Base+30..39`)·편대 `TBD` 이관, GCS 고정 대역폭/`REASSIGNED` 상태 불일치, 전 블록(`Base+0..39`) 침범 감시, Rule 3 수학적 중복, 그리고 의사코드 인자 버그를 Spec-First 및 TDD로 완전 해소하고 전사 가드레일을 통과시킨다.

**Architecture:**
먼저 마스터 ICD·전체 구조도·연관 6대 서브시스템 사양서(`AMM`, `VAS`, `FCP`, `GCS`, `ALIGNMENT`, `FDR`)와 기계 판독형 SSOT 계약(`config/protocol_contracts.json`)을 동시 개정(`Approved`)한 뒤, 각 독립 완결형 CC:Tweaked 코드베이스(`src/{0_infra/gcs,0_development/{alignment,fdr,installer},1_control/vas,2_guidance/fcp,3_planning/amm}`)에 Zero-Fallback 단일 경로(`ver == "1.9.5"`, 구 오프셋 폴백 금지)로 구현한다. 마지막으로 Virtual Bus 다중 노드 E2E 시뮬레이션·변이 살상(`run_mutation_tests.py`)·3대 정적/실부팅 가드레일을 통과한 후 서브시스템 사양서를 `Implemented`로 승격한다.

**Tech Stack:** Lua 5.2 (CraftOS-PC headless / Cobalt, `bit32`, CC:Tweaked `modem`/`fs`), Python 3.10+ (`verify_contracts.py`, `verify_runtime_wiring.py`, `verify_all_specs.py`, `verify_spec_status.py`, `verify_manifest_sync.py`, `run_unit_tests.py`, `run_e2e_tests.py`, `run_boot_smoke.py`, `run_mutation_tests.py`, `verify_context_docs.py`), Virtual Bus Multi-Node E2E Harness (`harness/simulation/virtual_bus.lua`, `harness/simulation/node_sandbox.lua`).

**Spec:**
- [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (`v1.31.0` → `v1.32.0 Approved`)
- [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (`v2.15.1` → `v2.16.0 Approved`)
- [AMM_PROGRAM_SPECIFICATION.md](../../specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (`v2.0.1 Implemented` → `v2.1.0 Approved` → `Implemented`)
- [VAS_PROGRAM_SPECIFICATION.md](../../specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (`v1.21.0 Implemented` → `v1.22.0 Approved` → `Implemented`)
- [FCP_PROGRAM_SPECIFICATION.md](../../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (`v2.1.0 Implemented` → `v2.2.0 Approved` → `Implemented`)
- [GCS_PROGRAM_SPECIFICATION_AND_ICD.md](../../specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md) (`v1.1.0 Implemented` → `v1.2.0 Approved` → `Implemented`)
- [ALIGNMENT_PROGRAM_SPECIFICATION.md](../../specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md) (`v2.7.0 Implemented` → `v2.8.0 Approved` → `Implemented`)
- [FDR_PROGRAM_SPECIFICATION.md](../../specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md) (`v0.3.0 Implemented` → `v0.4.0 Approved` → `Implemented`)

---

## Global Constraints

1. **Zero-Fallback 단일 스키마 원칙 (`ver == "1.9.5"`):**
   - `Base+9` (`CH_EMERGENCY_CORE`: `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`)와 `Base+8` (`CH_CALIBRATION_INIT`: `MSG_CALIBRATION_INIT`) 이전 완료 후 구 채널(`Base+1` 비상 패킷, `Base+0` 교정 진입)에 대한 듀얼 수신 폴백을 절대 두지 않는다.
   - `VAS`는 `Base+0` (`C2`) 채널을 열지 않고 `Base+8` (`calibration`), `Base+9` (`emergency`)를 개방하며, 수신 채널 불일치 패킷은 즉시 폐기(`return false, "WRONG_CHANNEL"`)한다.
2. **ASA 코드베이스 동결 준수 (`[연기] TASK-105`):**
   - `src/1_control/asa/**`, `tests/1_control/asa/**`, `docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md` (`v1.8.0 Approved`)는 `0 diff`를 유지한다. `Base+11` (`CH_AERO_ACTUATION`) 계약은 변경하지 않는다.
3. **멀티 코드베이스 독립 완결성:**
   - `src/<layer>/<name>/` 간 직접 `require()` 참조 금지(예외는 `/lib/avionics_sensors.lua`뿐이다). 각 노드의 채널 오프셋·상수 테이블은 해당 서브시스템 내부와 `manifest.lua` `defaultConfigs`에만 선언한다.
4. **WebUI 미션 에디터 및 Mission Editor 사양 격리 (`TASK-125-7` 경계):**
   - `Base+30..39`는 `Zone 3` 탑재체·특수 임무 확장 예비 영역(`CH_PAYLOAD_EXT_30..39`, Zone 3 총합 `Base+20..39`)으로 재편성하고 편대 비행(`CH_FORMATION_LINK`)은 향후 독립 광역 데이터링크(`TBD`)로 이관한다.
   - 기존 `ACT_PAY_BUS_CMD` / `ZONE3_PAYLOAD_CMD` 표준 오프셋 입력 검증(`20..29`) 및 `tools/amm_mission_editor.html` / `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (`v0.3.1 Implemented`)는 본 태스크에서 수정하지 않는다(`TASK-401` 확장 시 `30..39` 액션 할당 예정).
5. **변이 살상 가드레일 `MUT-07` 보존:**
   - `tools/run_mutation_tests.py`의 `MUT-07`은 `src/1_control/vas/modules/network_manager.lua` 내 `if msgType == "MSG_EMERGENCY_OVERRIDE" then` 분기 문구를 변이 대상으로 사용한다. 채널 분리 검사(`channel == state.channels.emergency`)를 추가하더라도 `if msgType == "MSG_EMERGENCY_OVERRIDE" then` 조건문을 제거·변형하지 않아야 `MUT-07` 25/25 `KILLED`가 유지된다.
6. **Windows PowerShell 5.1 & Git CLI 규약:**
   - 셸 체이닝은 `&&` 대신 `; if ($?) { ... }`를 사용한다.
   - Git 호출은 `& "C:\Program Files\Git\cmd\git.exe"`를 사용한다.

---

## Review Focus

구현 및 리뷰 단계에서 아래 5개 실패 모드를 우선 집중 검증한다(각 항목은 해당 Task의 자동화 테스트로 고정됨):

1. **구 채널 듀얼키 폴백 누수 (`Base+1` E_STOP / `Base+0` Calibration Leak):**
   - *위험:* `VAS network_manager.dispatch`가 수신 채널을 검사하지 않으면 구 채널(`Base+1` E_STOP, `Base+0` `MSG_CALIBRATION_INIT`) 주입 시에도 상태 전이가 허용되어 Zero-Fallback 위반.
   - *고정 테스트:* Task 2 `tests/1_control/vas/test_vas_core.lua` (음성 케이스: `Base+1` `MSG_EMERGENCY_OVERRIDE` 거부 & `Base+0` `MSG_CALIBRATION_INIT` 거부, 양성 케이스: `Base+9` & `Base+8` 수락) + Task 7 `tests/e2e/test_e2e_c2_and_estop.lua`, `tests/e2e/test_e2e_hangar_alignment.lua`.
2. **동시 부팅 프로브 자기 충돌(Self-Conflict Deadlock) 및 경합 누락:**
   - *위험:* 다회 재프로브/지터 백오프 중 자기 `hardwareUuid` 필터가 빠지면 스스로 `CONFLICT_DETECTED`에 걸려 `LOCKED_CONFLICT`로 락다운되거나, 동시 부팅 2기체가 응답 전에 같은 `200ms` 윈도우를 통과함.
   - *고정 테스트:* Task 5 `tests/3_planning/amm/test_channel_sentinel.lua` (동일 `hardwareUuid` 프로브 무시, 지터·다회 재시도, 미획득/보유 중 `DISARMED` 응답 검증) + Task 7 `tests/e2e/test_e2e_bootstrap_and_telemetry.lua` (2기체 동시 부팅 경합 회피 E2E).
3. **꺼진 점유자(Sleeping Occupant) 블록 탈취 및 공중 충돌:**
   - *위험:* 기존 기체 전원이 꺼져 프로브에 침묵할 때 GCS 메모리 휘발이나 스캔 침묵을 빈 채널로 오판해 신규 기체에 같은 블록을 주면, 기존 기체 재부팅 시 공중 충돌 발생.
   - *고정 테스트:* Task 4 `tests/0_infra/gcs/test_channel_manager.lua` (영속 `channel_registry.json` 리스 복원, `preferredBase` 충돌 시 `"REASSIGNED"` 반환, `requestedBandwidth ~= 40` `"DENIED"`) + Task 5 `tests/3_planning/amm/test_channel_sentinel.lua` (로컬 `channel_lease.json` 캐시 기반 부팅 재검증 핸드셰이크) + Task 7 `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`.
4. **`Base+3` (`CH_MFD_STATE`) 핸드오버 복귀 시 양방향 에코 스톰:**
   - *위험:* `MFD_ACRO` 종료 직후 `VAS`의 `250ms` 타임아웃 복귀와 `AMM` 5Hz 다운링크 재개 타이밍이 어긋나면 양쪽이 동시에 `Base+3`에 송신함.
   - *고정 테스트:* Task 3 `tests/3_planning/amm/test_network_manager.lua` 및 `tests/3_planning/amm/test_c2_arbiter.lua` (`MFD_ACRO` 억제, 복귀 히스테리시스 `acroRecoveryHoldMs = 300ms` 유예 창, `FAILSAFE_HOLD` 중 VAS 우선권 확인).
5. **계약 SSOT·검증 도구·`MUT-07` 변이 회귀:**
   - *위험:* `config/protocol_contracts.json`의 채널 오프셋(`+8`, `+9`, `+20..39`), `REASSIGNED` enum, `FDR` 패시브 탭 채널, 또는 `VAS` `MUT-07` 타깃 라인 중 하나라도 어긋나면 E2E 계약 검증(`474+` 패킷)이나 `run_mutation_tests.py`가 실패함.
   - *고정 테스트:* Task 1 `tests/harness/test_verify_contracts.py` (`--specs-only`), Task 7 `verify_contracts.py`, `run_mutation_tests.py` (`25/25 KILLED`), `run_e2e_tests.py`.

---

## Task 1: Spec-First 전사 사양서·프로토콜 계약 SSOT·검증 도구 동기화 (`TASK-125-1`..`13` 명세 확정)

### Interfaces
- **Consumes:** 현행 마스터 ICD (`v1.31.0`), 전체 구조도 (`v2.15.1`), 6대 서브시스템 사양서 (`AMM`, `VAS`, `FCP`, `GCS`, `ALIGNMENT`, `FDR`), `config/protocol_contracts.json`, `tools/verify_contracts.py`
- **Produces:** 개정(`Approved`)된 전사 사양서 8종, 동기화된 `config/protocol_contracts.json` (Base+8 `CH_CALIBRATION_INIT`, Base+9 `CH_EMERGENCY_CORE`, Zone 3 `20..39` 확장, `zone4` 제거/`TBD`, `I-8` `"REASSIGNED"` / `"DENIED"`, `I-9` 다회 프로브/지터/영속 리스 파라미터), 보강된 `tools/verify_contracts.py` & `tests/harness/test_verify_contracts.py`

### Files
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` (`v1.31.0` → `v1.32.0`, `Approved`)
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` (`v2.15.1` → `v2.16.0`, `Approved`)
- Modify: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md` (`v2.0.1 Implemented` → `v2.1.0 Approved`)
- Modify: `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md` (`v1.21.0 Implemented` → `v1.22.0 Approved`)
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md` (`v2.1.0 Implemented` → `v2.2.0 Approved`)
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (`v1.1.0 Implemented` → `v1.2.0 Approved`)
- Modify: `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md` (`v2.7.0 Implemented` → `v2.8.0 Approved`)
- Modify: `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md` (`v0.3.0 Implemented` → `v0.4.0 Approved`)
- Modify: `config/protocol_contracts.json`
- Modify: `tools/verify_contracts.py`
- Modify: `tests/harness/test_verify_contracts.py`

- [ ] **Step 1: `tests/harness/test_verify_contracts.py`에 신규 계약 불변식 실패 테스트 추가 (Red)**

Add unit test cases verifying:
1. `Base+8` (`CH_CALIBRATION_INIT`)과 `Base+9` (`CH_EMERGENCY_CORE`)가 `zone1_flight_core.offsets` (`[0, 1, 2, 3, 4, 5, 8, 9]`)에 포함되고, `I-2` 비상 패킷(`MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`)은 `offset: 9`, `I-4` 지상 교정 초기화(`MSG_CALIBRATION_INIT`)는 `offset: 8`로 바인딩됨을 검증.
2. `Base+1`의 `MSG_EMERGENCY_OVERRIDE` 또는 `Base+0`의 `MSG_CALIBRATION_INIT`이 E2E/계약 패킷 검증에 유입되면 `validate_e2e_packets`가 채널 오프셋 위반 에러(`channel mismatch for strict interface binding`)를 반환함을 검증.
3. `MSG_BLOCK_ASSIGN.enums.status`에 `"ASSIGNED"`, `"REASSIGNED"`, `"DENIED"`, `"FAILED"`가 허용되고, `I-8` `requestedBandwidth`가 `numericBounds: [40, 40]` 고정 계약임을 검증.

- [ ] **Step 2: Red 테스트 실행 확인**

```powershell
python -m unittest tests/harness/test_verify_contracts.py -v
```
Expected: 새로 추가한 `Base+8`/`Base+9`/`REASSIGNED`/strict channel binding 테스트 FAIL.

- [ ] **Step 3: `config/protocol_contracts.json` 개정**

다음 항목을 정확히 업데이트한다:
1. `channels.aircraft.zones`:
   - `zone1_flight_core.offsets`: `[0, 1, 2, 3, 4, 5, 8, 9]` (주석/이름에 `8=CH_CALIBRATION_INIT`, `9=CH_EMERGENCY_CORE` 명시; `6, 7`은 `deprecatedOffsets: [6, 7]` 유지).
   - `zone3_payload.offsets`: `[20, 21, 22, 23, 24, 25, 26, 27, 28, 29]` 유지 + `zone3_payload_ext` 신설 (`offsets: [30, 31, 32, 33, 34, 35, 36, 37, 38, 39]`, description `"Zone 3 Payload & Special Mission Extension (CH_PAYLOAD_EXT_30..39); Zone 4 Formation Link moved to TBD wide-area datalink"`). 기존 `zone4_swarm_formation` 블록 제거.
2. `interfaces`:
   - `I-2`: `MSG_ATTITUDE_CMD` 전용 `offset: 1` 채널 매처와 비상 전용 `I-2-EMG` (또는 `I-2` 내부 `packetChannelOverrides`: `MSG_EMERGENCY_OVERRIDE -> aircraft_offset 9`, `MSG_EMERGENCY_ALERT -> aircraft_offset 9`, `channelMatchers`에 `offset: 1`, `offset: 9` 포함).
   - `I-4`: `MSG_CALIBRATION_INIT`을 `aircraft_offset: 8` (`CH_CALIBRATION_INIT`)로 매칭(기존 `aircraft_offset: 0` 제거) + `packetChannelOverrides`: `MSG_CALIBRATION_INIT -> aircraft_offset 8`, `hangar_offset` (`0, 1, 3`) 유지.
   - `I-6`: `timeoutsMs`에 `acroTimeoutMs: 250`, `acroRecoveryHoldMs: 300` 추가.
   - `I-8`: `MSG_BLOCK_REQUEST` `optionalKeys`에 `"preferredBase"`, `"conflictBase"` 추가, `numericBounds.requestedBandwidth: [40, 40]`; `MSG_BLOCK_ASSIGN` `enums.status: ["ASSIGNED", "REASSIGNED", "DENIED", "FAILED"]`, `optionalKeys`에 `"leaseState"`, `"reassignedFrom"`, `"reason"` 추가.
   - `I-9`: `channelMatchers`에 `offset: 8, 9` 및 `offsets 20..39` 감시 범위 반영; `timeoutsMs`에 `probeListenMs: 200`, `probeJitterMaxMs: 100`, `probeRetryCount: 2`, `maxReassignAttempts: 3`, `gcsBootstrapTimeoutMs: 2000`, `intrusionAlertWindowMs: 30000`, `rebindAckTimeoutMs: 500` 추가; `MSG_CHANNEL_PROBE_ACK` `optionalKeys`에 `"responderUuid"`, `"responderStatus"` 추가.

- [ ] **Step 4: `tools/verify_contracts.py` 정적·E2E 엄격 채널 검증 확장 (Green)**

`tools/verify_contracts.py`에 다음 경량 검증을 추가한다:
1. `validate_e2e_packets`: 인터페이스에 `packetChannelOverrides`가 선언되어 있고 패킷의 `channel`이 `aircraft` 대역(`10000..49999`)일 때, 해당 `msgType`의 계산된 `offset`이 허용된 override 오프셋과 불일치하면 에러를 기록한다(예: `Base+1`에서 `MSG_EMERGENCY_OVERRIDE`/`MSG_EMERGENCY_ALERT` 수신 또는 `Base+0`에서 `MSG_CALIBRATION_INIT` 수신 시 즉시 차단).
2. `numericBounds` / `enums`가 `I-8`의 `requestedBandwidth: [40, 40]` 및 `"REASSIGNED"` / `"DENIED"`를 자동 검증한다.

Run test:
```powershell
python -m unittest tests/harness/test_verify_contracts.py -v
```
Expected: `PASS`.

- [ ] **Step 5: 마스터 ICD (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`) & 전체 구조도 (`SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`) 개정**

`specification-lifecycle-manager` 절차에 따라 아래 내용을 정확히 반영하고 버전을 `v1.32.0 Approved` (마스터 ICD), `v2.16.0 Approved` (전체 구조도)로 갱신한다:
1. **40채널 서브할당 표 (`Diagram §5.1, §5.2, §5.3` & `ICD` 인터페이스 매트릭스):**
   - `Base+0`: `CH_OPERATOR_C2` (비행 C2 + 부트스트랩/운용 충돌 프로브 전용 — 지상 교정 진입 패킷 제외).
   - `Base+1`: `CH_FLIGHT_GUIDANCE` (순수 20Hz `MSG_ATTITUDE_CMD` 전용 — 비상 정지/경보 완전 분리).
   - `Base+3`: `CH_MFD_STATE` (`MFD_ACRO`/`FAILSAFE_HOLD`/`EMERGENCY_LAND` 시 `VAS` 20Hz 배타적 우선, 평시 `AMM` 5Hz, 복귀 시 `acroRecoveryHoldMs = 300ms` 히스테리시스 유예 후 `AMM` 재개).
   - `Base+8`: `CH_CALIBRATION_INIT` (`Alignment -> VAS` 지상 교정 세션 개시 `MSG_CALIBRATION_INIT` 전용).
   - `Base+9`: `CH_EMERGENCY_CORE` (`E_STOP` `MSG_EMERGENCY_OVERRIDE` & `MSG_EMERGENCY_ALERT` 전용 비상 버스).
   - `Base+20~39`: Zone 3 Payload & Special Mission 버스 통합 (`Base+20` `CH_PAYLOAD_BUS`, `Base+21` `CH_WEAPON_BUS`, `Base+22~29` `CH_PAYLOAD_RSV_22~29`, `Base+30~39` `CH_PAYLOAD_EXT_30~39` 확장 예비). 편대 비행(`CH_FORMATION_LINK`)은 `TBD` (향후 독립 광역 데이터링크)로 이관.
2. **채널 프로브, 회피 루프 & 영속 리스 규약 (`TASK-125-2`, `-3`, `-4`):**
   - 랜덤 백오프 지터 `0~100ms` 선행 대기 + 다회(`probeRetryCount = 2`, 회당 `200ms`) 재프로브 + `CONFLICT_DETECTED` 수신 시 GCS `conflictBase` 보고 재할당 회피 루프(`maxReassignAttempts = 3`) 후 3회 연속 충돌 시에만 `LOCKED_CONFLICT` 시동 잠금.
   - `AMM` 부팅 즉시 `Base+0` 상시 개방(지상 `DISARMED`/`IDLE`/`PROBING`/`ACQUIRED` 포함) 및 자기 `hardwareUuid` 무시 규칙 명시.
   - 꺼진 점유자(Sleeping Occupant) 방지: GCS `channel_registry.json` 영속 리스(`hardwareUuid`, `leaseState`, `lastSeenMs`) + `AMM` 로컬 디스크 캐시(`config/channel_lease.json`) + 부팅 시 GCS `MSG_BLOCK_REQUEST(preferredBase)` 재검증 핸드셰이크. GCS 무응답 타임아웃 시 로컬 `channel_lease.json` 보유 및 다회 ARP 프로브 통과 기체는 `[NO_GCS_LEASE]` 경고로 오프라인 운용 허용, 미보유 기체는 `LOCKED_NO_GCS` 시동 잠금.
3. **GCS & 검증 규칙 결함 4종 (`TASK-125-8`, `-9`, `-10`, `-11`, `-12`):**
   - `Diagram §6.1` L798 `checkCollision(existingCraft.baseChannel, reqBW, craftUuid)`(3인자) → 4인자 `checkCollision(existingCraft.baseChannel, FIXED_BW, candidateBase, FIXED_BW)`로 정합 수정.
   - 가변 `reqBW` 제거 → `BW = 40` 고정 계약 단일화 (`requestedBandwidth ~= 40` 시 `"DENIED"`).
   - `§6.1` & Seq 5 재할당 응답 상태를 `§6.3`과 일치시켜 `"REASSIGNED"`로 통일.
   - `§6.3` 비행 중 채널 침범 감시 범위를 `Base+0~5, +10~11`에서 **전 블록 `Base+0~39`**(Zone 1 Core `+8`/`+9` 및 Zone 3 Payload `+20~39` 포함)로 확대.
   - `§7.2` Rule 3 (`[50000, 60020]` 중복 체크) 삭제: Rule 2 (`Base + 39 <= 49999`)로 수학적 동치 보장, `ChannelValidator` 의사코드 단순화.

- [ ] **Step 6: 6대 서브시스템 사양서(`AMM`, `VAS`, `FCP`, `GCS`, `ALIGNMENT`, `FDR`) `Approved` 개정 및 연관 버전 배지 동기화**

각 사양서 상단 메타데이터를 `Approved`로 전이하고 `Revision History`를 추가한다:
- `AMM` (`v2.1.0 Approved`): `Base+9` E_STOP 송신, `Base+3` 300ms 복귀 히스테리시스, `Base+0` 부팅 즉시 프로브 응답기, 지터(0~100ms)·2회 재프로브·로컬 리스 캐시(`channel_lease.json`) 재검증, `Base+0..39` 전수 침범 감시, Zone 3 확장(`Base+20~39`, 편대 `TBD`).
- `VAS` (`v1.22.0 Approved`): `Base+8` `CH_CALIBRATION_INIT` (`MSG_CALIBRATION_INIT` 전용 수신, `Base+0` 미개방), `Base+9` `CH_EMERGENCY_CORE` (`E_STOP` 수신 & `MSG_EMERGENCY_ALERT` 송신), `Base+3` `MFD_ACRO`/`FAILSAFE_HOLD` 우선권 및 `acroTimeoutMs = 250ms` 규약, `formationLink = 30` 제거.
- `FCP` (`v2.2.0 Approved`): `Base+1` 순수 20Hz `MSG_ATTITUDE_CMD` 송신 전용화, `Base+9` `MSG_EMERGENCY_ALERT` 구독 추가(비상 경보 시 `EMERGENCY_HOLD` 안전 전이).
- `GCS` (`v1.2.0 Approved`): `OFFSET_ESTOP = 9` (`Base+9` 송신), `BW = 40` 고정 검증(`~= 40` 시 `"DENIED"`), 영속 리스 기반 충돌 시 `"REASSIGNED"` 반환 및 4인자 블록 충돌 검사.
- `ALIGNMENT` (`v2.8.0 Approved`): `MSG_CALIBRATION_INIT` 송신 대상 채널을 `Base+0`에서 `Base+8` (`CH_CALIBRATION_INIT`)로 변경.
- `FDR` (`v0.4.0 Approved`): 패시브 감청 채널 목록에 `Base+9` (`CH_EMERGENCY_CORE`: `MSG_EMERGENCY_OVERRIDE`, `MSG_EMERGENCY_ALERT`) 추가 및 `Base+1`은 순수 `MSG_ATTITUDE_CMD` 전용으로 갱신.

- [ ] **Step 7: 사양 정합성 스크립트 3종 검증 실행**

```powershell
python tools/verify_all_specs.py --check-readmes ; if ($?) { python tools/verify_spec_status.py } ; if ($?) { python tools/verify_contracts.py --specs-only }
```
Expected: `0 Errors, 0 Warnings`, `verify_spec_status.py` PASS (`6`건 `Approved` 전이 반영 — `verify_spec_status.py`의 허용 목록에 따라 임시/최종 전이 확인), `verify_contracts.py --specs-only` `0 errors`.
*(참고: `tools/verify_spec_status.py`가 구현 완료 전에는 `TARGET_IMPLEMENTED`를 엄격히 요구하므로, 사양서 `Approved` 전이 중에는 `verify_all_specs.py --check-readmes`와 `verify_contracts.py --specs-only` 통과를 확인하고, Task 7 완료 직전 `Implemented` 승격 후 `verify_spec_status.py`를 최종 PASS시킨다.)*

- [ ] **Step 8: 커밋 (Spec & Contract SSOT)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add docs/system/ docs/specs/ config/protocol_contracts.json tools/verify_contracts.py tests/harness/test_verify_contracts.py ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "docs(specs): ratify TASK-125 40-channel block remediation specs and contract SSOT" }
```

---

## Task 2: `Base+9` 비상 채널 & `Base+8` 교정 채널 격리 (`TASK-125-1`, `TASK-125-6`)

### Interfaces
- **Consumes:** `config/protocol_contracts.json` (`I-2` `offset: 9` E_STOP/EMERGENCY_ALERT, `I-4` `offset: 8` `MSG_CALIBRATION_INIT`)
- **Produces:** Zero-Fallback 단일 채널 송수신 구현 — `VAS`(`c2` 제거, `calibration=8`, `emergency=9`), `FCP`(`guidance=1`, `emergency=9`), `AMM`(`emergency=9` `E_STOP` 송신), `GCS`(`OFFSET_ESTOP=9`), `Alignment`(`+8` 송신), `FDR`(`+9` 패시브 감청), `installer/modules/manifest.lua` 기본 설정 일치

### Files
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Modify: `src/2_guidance/fcp/modules/network_manager.lua` & `src/2_guidance/fcp/config/fcp_config.json`
- Modify: `src/3_planning/amm/modules/network_manager.lua` & `src/3_planning/amm/modules/c2_arbiter.lua`
- Modify: `src/0_infra/gcs/modules/network_manager.lua`
- Modify: `src/0_development/alignment/modules/align_master.lua` & `src/0_development/alignment/main.lua` (if applicable)
- Modify: `src/0_development/fdr/modules/packet_tap.lua`
- Modify: `tests/1_control/vas/test_vas_core.lua`
- Modify: `tests/0_infra/gcs/test_network_manager.lua` & `tests/0_infra/gcs/test_gcs_integration.lua`
- Modify: `tests/2_guidance/fcp/test_fcp_network_and_rebind.lua`
- Modify: `tests/3_planning/amm/test_network_manager.lua`, `tests/3_planning/amm/test_c2_arbiter.lua`
- Modify: `tests/0_development/alignment/test_alignment_core.lua`
- Modify: `tests/0_development/fdr/test_fdr_main.lua`, `tests/0_development/fdr/test_fdr_ring_and_tap.lua`

- [ ] **Step 1: 단위 테스트에 `Base+8` / `Base+9` 격리 및 구 채널(`Base+0`/`Base+1`) 거부 검증 추가 (Red)**

각 서브시스템 테스트 파일에 아래 단언을 먼저 추가한다:
1. `tests/1_control/vas/test_vas_core.lua`:
   - `net.channels.calibration == 10008`, `net.channels.emergency == 10009` 검증, `wirelessModem.isOpen(10008)` & `isOpen(10009)` `true`, `wirelessModem.isOpen(10000)` `false` (`c2` 미개방).
   - `vas_net.dispatch(..., 10001, ..., MSG_EMERGENCY_OVERRIDE)` → `false, "WRONG_CHANNEL"`.
   - `vas_net.dispatch(..., 10009, ..., MSG_EMERGENCY_OVERRIDE)` → `true` (`E_STOP` 전이).
   - `vas_net.dispatch(..., 10000, ..., MSG_CALIBRATION_INIT)` → `false, "WRONG_CHANNEL"`.
   - `vas_net.dispatch(..., 10008, ..., MSG_CALIBRATION_INIT)` → `true` (`CALIBRATION` 전이).
   - `send_emergency_alert` → `10009` 송신 확인 (`10001` 아님).
2. `tests/0_infra/gcs/test_network_manager.lua`: `send_estop_command`가 `target_base + 9` (`10009`)로 송신함을 검증.
3. `tests/3_planning/amm/test_network_manager.lua`: `send_emergency_override`가 `baseChannel + 9` (`10009`)로 송신함을 검증.
4. `tests/0_development/alignment/test_alignment_core.lua`: `init_bay_session`이 `MSG_CALIBRATION_INIT`을 `craft_base_ch + 8` (`10008`)로 송신함을 검증.
5. `tests/0_development/fdr/test_fdr_main.lua` & `test_fdr_ring_and_tap.lua`: `[9] = { MSG_EMERGENCY_OVERRIDE = true, MSG_EMERGENCY_ALERT = true }` 매핑 및 `Base+9` 패킷 수집 시 `autoFlushOnEstop` 발동(구 `Base+1` E_STOP은 미수집) 검증.
6. `tests/2_guidance/fcp/test_fcp_network_and_rebind.lua`: `FCP`가 `Base+9` (`10009`)를 개방하고 `Base+9` `MSG_EMERGENCY_ALERT` 수신 시 `EMERGENCY_HOLD` 전환, `Base+1` 수신 `MSG_EMERGENCY_ALERT` 무시 확인.

- [ ] **Step 2: Red 테스트 실행**

```powershell
foreach ($t in @("vas", "gcs", "fcp", "amm", "alignment", "fdr")) { python tools/run_unit_tests.py --target $t --clean-orphans }
```
Expected: 지정된 6개 타깃에서 신규/갱신된 `Base+8` & `Base+9` 단언 FAIL.

- [ ] **Step 3: `VAS` (`src/1_control/vas/modules/network_manager.lua`) 격리 구현 & `MUT-07` 보존**

1. `network_manager.ZONE_OFFSETS`: `c2` 제거 (또는 `channels.c2` 미할당), `calibration = 8`, `emergency = 9` 추가 (`guidance = 1`, `telemetry = 2`, `mfd = 3`, `trajectory = 4`, `clientReply = 5`, `actuation = 10`, `aero = 11`).
2. `init`: `channels.calibration = baseCh + (s.calibration or zo.calibration)`, `channels.emergency = baseCh + (s.emergency or zo.emergency)`. 무선 모뎀 개방 목록을 `{ channels.calibration, channels.guidance, channels.emergency, channels.actuation, channels.aero }`로 변경 (`c2` `Base+0` 개방 금지!).
3. `dispatch`:
   - `if msgType == "MSG_EMERGENCY_OVERRIDE" then` (**`MUT-07` 매칭 라인 원문 그대로 유지!**): 블록 내부 첫 줄에서 `if channel ~= state.channels.emergency then return false, "WRONG_CHANNEL" end` 검사 후 기존 `authKey`·`E_STOP` 전이 실행.
   - `elseif msgType == "MSG_CALIBRATION_INIT" then`: `if channel ~= state.channels.calibration then return false, "WRONG_CHANNEL" end` 검사.
   - `elseif msgType == "MSG_ATTITUDE_CMD" then`: `if channel ~= state.channels.guidance then return false, "WRONG_CHANNEL" end`.
4. `send_emergency_alert`: `txChannel = state.channels.emergency` (`Base+9`).

- [ ] **Step 4: `FCP`, `AMM`, `GCS`, `Alignment`, `FDR`, `manifest.lua` 구현 반영**

1. `src/2_guidance/fcp/modules/network_manager.lua` & `fcp_config.json`: `channels.emergencyOffset = 9`, `emergencyCh = baseChannel + 9` 개방 및 `Base+9`에서만 `MSG_EMERGENCY_ALERT` 수락 (`Base+1`에서 거부).
2. `src/3_planning/amm/modules/network_manager.lua`: `send_emergency_override` 전송 채널을 `self.baseChannel + 9` (`OFFSET_EMERGENCY = 9`)로 변경 (`bind_modems` 시 필요 시 `Base+9` 개방 또는 송신 전용 사용 확인 — `TASK-125-11` 전 블록 감시를 위해 Task 5에서 `Base+0..39` 개방 전략과 통합).
3. `src/0_infra/gcs/modules/network_manager.lua`: `local OFFSET_ESTOP = 9` (`-- Base + 9: CH_EMERGENCY_CORE`).
4. `src/0_development/alignment/modules/align_master.lua`: `init_bay_session`이 `MSG_CALIBRATION_INIT` 전송 시 `self.craft_base_ch + 8`로 송신 (`craft_base_ch` 유효성 검증은 `0 % 40` 기준 유지, 전송 목적지만 `+8`).
5. `src/0_development/fdr/modules/packet_tap.lua`: `ALLOWED_TYPES_BY_OFFSET[1]`에서 `MSG_EMERGENCY_*` 제거(`MSG_ATTITUDE_CMD`만 유지), `ALLOWED_TYPES_BY_OFFSET[9] = { MSG_EMERGENCY_OVERRIDE = true, MSG_EMERGENCY_ALERT = true }` 추가, `build_channel_map` 기본 offsets `{ 1, 2, 9, 10 }` & `countsByOffset`에 `[9] = 0` 추가.
6. `src/0_development/installer/modules/manifest.lua`: `vas.defaultConfigs["/config/system.json"].channels` (`c2` 제거, `calibration = 8`, `emergency = 9`), `fcp` `defaultConfigs` / `AIRFRAME_PRESETS` (`emergencyOffset = 9` 추가), `fcp_config.json` 동기화.

- [ ] **Step 5: 단위 테스트 + `MUT-07` 변이 테스트 실행 (Green)**

```powershell
foreach ($t in @("vas", "gcs", "fcp", "amm", "alignment", "fdr")) { python tools/run_unit_tests.py --target $t --clean-orphans; if (-not $?) { throw "Unit test failed: $t" } } ; if ($?) { python tools/run_mutation_tests.py }
```
Expected: 지정된 6개 타깃 단위 테스트 전부 PASS, `run_mutation_tests.py` `25/25 KILLED` (`MUT-07` 포함).

- [ ] **Step 6: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add src/ tests/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(protocol): isolate Base+9 emergency and Base+8 calibration channels" }
```

---

## Task 3: `Base+3` (`CH_MFD_STATE`) 이중 송신자 핸드오버 경합 해소 (`TASK-125-5`)

### Interfaces
- **Consumes:** `VAS` `activeSource` (`"FCP" | "MFD_ACRO"`) 및 `fsmState` (`"FAILSAFE_HOLD" | "EMERGENCY_LAND"`), `AMM` `c2_arbiter.activeSource`, `ICD I-6` (`acroTimeoutMs = 250`, `acroRecoveryHoldMs = 300`)
- **Produces:** `AMM` `c2_arbiter`의 비차단 억제·복귀 히스테리시스 게이트 (`update_acro_yield_window`), `VAS telemetry_feeder` 우선권 불변 및 양측 동시 송신 0건 보장

### Files
- Modify: `src/3_planning/amm/config/amm_config.json` (`safety.acroRecoveryHoldMs = 300`)
- Modify: `src/3_planning/amm/modules/c2_arbiter.lua`
- Modify: `src/3_planning/amm/modules/network_manager.lua`
- Modify: `src/3_planning/amm/main.lua` (`step_5hz_downlink`에서 히스테리시스 상태 체크)
- Modify: `src/1_control/vas/modules/telemetry_feeder.lua` (필요 시 명시적 priority/suppressMetadata 검사 강화)
- Modify: `src/0_development/installer/modules/manifest.lua` (`amm` `configTemplate` 동기화)
- Modify: `tests/3_planning/amm/test_c2_arbiter.lua` & `tests/3_planning/amm/test_network_manager.lua` & `tests/3_planning/amm/test_main_loop.lua`

- [ ] **Step 1: `Base+3` 핸드오버 히스테리시스 및 경합 차단 단위 테스트 작성 (Red)**

`tests/3_planning/amm/test_c2_arbiter.lua` 및 `test_network_manager.lua`에 아래 케이스를 추가한다:
1. `VAS`가 `activeSource = "MFD_ACRO"` 또는 `fsmState = "FAILSAFE_HOLD"` / `"EMERGENCY_LAND"` 상태의 `MSG_MFD_STATE`를 송출한 뒤, `activeSource = "FCP"`로 복귀한 직후 **`t < 300ms` 유예 창 내부**에서는 `amm.c2_arbiter:can_transmit_mfd(nowMs)` 및 `amm_net:send_mfd_state(..., nowMs)`가 `false, "ACRO_RECOVERY_HOLD"`를 반환하며 `Base+3` 송신을 억제함을 검증.
2. `nowMs - lastVasPriorityMs >= 300` 경과 후에는 정상적으로 `AMM` 5Hz 송출을 재개함을 검증.
3. `telemetry_feeder.lua`가 `FAILSAFE_HOLD` 중 4틱 다운샘플, `MFD_ACRO` 중 매 틱(20Hz) `Base+3` 송출을 유지함을 재확인.

- [ ] **Step 2: Red 테스트 실행**

```powershell
python tools/run_unit_tests.py --target amm --clean-orphans
```
Expected: `ACRO_RECOVERY_HOLD` 유예 창 테스트 FAIL.

- [ ] **Step 3: `AMM` `c2_arbiter.lua`, `network_manager.lua`, `main.lua` 히스테리시스 구현 (Green)**

1. `src/3_planning/amm/config/amm_config.json` & `manifest.lua`: `safety.acroRecoveryHoldMs = 300`.
2. `c2_arbiter.lua`:
   - `self.vasMfdPriorityUntilMs = 0`, `self.acroRecoveryHoldMs = cfg.acroRecoveryHoldMs or 300`.
   - `handle_mfd_state(payload, nowMs)`: `activeSource == "MFD_ACRO"`이거나 `fsmState == "FAILSAFE_HOLD"` / `"EMERGENCY_LAND"`인 경우 `self.vasMfdPriorityUntilMs = nowMs + self.acroRecoveryHoldMs`로 연장하고 `self.activeSource` 갱신. `activeSource == "FCP"`로 복귀해도 `nowMs < self.vasMfdPriorityUntilMs` 동안은 `can_transmit_mfd(nowMs)`가 `false, "ACRO_RECOVERY_HOLD"` 반환.
3. `network_manager.lua` (`send_mfd_state`) & `main.lua` (`step_5hz_downlink`): `arbiter:can_transmit_mfd(nowMs)`와 `activeSource == "MFD_ACRO"`를 일관 검증해 경계 겹침 원천 차단.

- [ ] **Step 4: 단위 테스트 통과 확인 & 커밋**

```powershell
python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target vas --clean-orphans } ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/ src/1_control/vas/ src/0_development/installer/modules/manifest.lua tests/3_planning/amm/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm,vas): enforce Base+3 MFD_ACRO yield hysteresis window" } }
```
Expected: `amm`, `vas` 단위 테스트 PASS.

---

## Task 4: GCS 고정 대역폭(`BW=40`), `REASSIGNED` 상태 통일, 4인자 충돌 검사 및 영속 리스 관리 (`TASK-125-3`, `-9`, `-10`, `-12`)

### Interfaces
- **Consumes:** `MSG_BLOCK_REQUEST { domainId, hardwareUuid, requestedBandwidth, [preferredBase], [conflictBase] }`, 영속 파일 `config/channel_registry.json`
- **Produces:** `MSG_BLOCK_ASSIGN { blockId, baseChannel, bandwidth=40, status=("ASSIGNED"|"REASSIGNED"|"DENIED"|"FAILED"), channelRange, leaseState, [reassignedFrom], [reason] }`

### Files
- Modify: `src/0_infra/gcs/modules/channel_manager.lua`
- Modify: `src/0_infra/gcs/main.lua`
- Modify: `tests/0_infra/gcs/test_channel_manager.lua`
- Modify: `tests/0_infra/gcs/test_gcs_integration.lua`

- [ ] **Step 1: GCS 고정 `BW=40`, `"REASSIGNED"` / `"DENIED"`, 영속 리스 테스트 추가 (Red)**

`tests/0_infra/gcs/test_channel_manager.lua` 및 `test_gcs_integration.lua`에 아래 케이스를 추가한다:
1. **가변 `reqBW` 거부 (`TASK-125-9`):** `allocate_block(state, "AIRCRAFT_04", "UUID-4", 20)` 또는 `80` 호출 시 `res.status == "DENIED"`, `res.reason == "INVALID_BANDWIDTH"` 반환, 레지스트리 미기록 확인.
2. **충돌 시 `"REASSIGNED"` 반환 (`TASK-125-10`):** Block 1(`10000`)을 `"AIRCRAFT_01"` (`UUID-1`)이 점유(오프라인 포함) 중일 때, `"AIRCRAFT_02"` (`UUID-2`)가 `preferredBase = 10000`으로 요청하면 `res.status == "REASSIGNED"`, `res.reassignedFrom == 10000`, `res.baseChannel == 10040`, `res.blockId == 2` 반환 검증.
3. **Rule 2 단일 경계 검증 (`TASK-125-12`):** `is_valid_block_range(baseChannel)`가 `baseChannel >= 10000 and baseChannel <= 49960 and (baseChannel - 10000) % 40 == 0`만으로 `[50000, 60020]`과 비겹침을 보장하고 `10040`은 `49960` 초과 시 `false` 반환함을 검증.
4. **꺼진 점유자(Sleeping Occupant) 영속 리스 보호 (`TASK-125-3`):** `"AIRCRAFT_01"` 할당 후 `channel_manager.init(cfg, registryPath)`를 새 상태로 재로드해도 `"AIRCRAFT_01"` (`leaseState = "OFFLINE_RESERVED"` 또는 `"ACTIVE_LEASE"`)이 Block 1을 유지하여 신규 기체 `"AIRCRAFT_05"`가 Block 1을 탈취하지 못하고 Block 2 (`10040`)를 할당받음을 검증. `release_block` 명시 호출 시에만 Block 1 반환.
5. **로컬 캐시 부팅 재검증 핸드셰이크 (`TASK-125-3`):** 기존 점유자 `"AIRCRAFT_01"`이 재부팅해 `preferredBase = 10000`, 동일 `hardwareUuid = "UUID-1"`으로 요청 시 `status == "ASSIGNED"`, `baseChannel == 10000` 재확인 반환; 반면 다른 `hardwareUuid = "UUID-NEW"`가 `preferredBase = 10000` 요청 시 `"REASSIGNED"`로 Block 2 할당 검증.

- [ ] **Step 2: Red 테스트 실행**

```powershell
python tools/run_unit_tests.py --target gcs --clean-orphans
```
Expected: 신규 `DENIED` / `REASSIGNED` / 영속 리스 재로드 테스트 FAIL.

- [ ] **Step 3: `src/0_infra/gcs/modules/channel_manager.lua` & `main.lua` 구현 (Green)**

1. `FIXED_BW = 40` 상수 고정. `allocate_block(state, domain_id, hardware_uuid, requested_bw, preferred_base, now_ms)`:
   - `if requested_bw ~= FIXED_BW then return { status = "DENIED", reason = "INVALID_BANDWIDTH", bandwidth = FIXED_BW } end`
   - 4인자 `ranges_overlap(baseA, bwA, baseB, bwB)`: `not (baseA + bwA - 1 < baseB or baseB + bwB - 1 < baseA)`.
   - Rule 2 단독 경계 검사(`base >= baseMin and base + FIXED_BW - 1 <= 49999 and (base - baseMin) % FIXED_BW == 0`) — Rule 3 `[50000, 60020]` 중복 검사 미사용.
   - 기존 동일 `domain_id` + `hardware_uuid` 매칭 시 기존 블록 재확인(`status = "ASSIGNED"`, `leaseState = "ACTIVE_LEASE"`, `lastSeenMs = now_ms`).
   - `preferred_base` 지정 시 해당 블록 점유자(`allocations` + `ranges_overlap`)가 없거나 동일 UUID면 `status = "ASSIGNED"`; 다른 기체가 영속 점유 중이거나 `conflict_base`로 보고 회피 요청된 블록이면(`conflict_base` 제외) 최저 빈 블록 검색 할당 후 `status = "REASSIGNED"`, `reassignedFrom = conflict_base or preferred_base` 반환.
   - 빈 블록 0개 시 `status = "FAILED"`, `reason = "NO_FREE_BLOCK"`.
   - `save_registry(state)`로 즉시 `config/channel_registry.json` 영속화 (`domainId`, `hardwareUuid`, `blockId`, `baseChannel`, `bandwidth = 40`, `leaseState = "ACTIVE_LEASE"`, `lastSeenMs`).
2. `src/0_infra/gcs/main.lua`: `MSG_BLOCK_REQUEST` 핸들러가 `payload.preferredBase`와 `nowMs`를 `channel_manager.allocate_block`에 전달하고, `"DENIED"`/`"REASSIGNED"`/`"ASSIGNED"`/`"FAILED"` 상태를 그대로 `MSG_BLOCK_ASSIGN`으로 송신.

- [ ] **Step 4: 단위 테스트 실행 & 커밋**

```powershell
python tools/run_unit_tests.py --target gcs --clean-orphans ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" add src/0_infra/gcs/ tests/0_infra/gcs/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(gcs): enforce fixed BW=40, REASSIGNED status, and persistent lease registry" } }
```
Expected: `gcs` 단위 테스트 PASS.

---

## Task 5: AMM `channel_sentinel` 지터·다회 프로브, 상시 응답, 캐시 리스 재검증 및 전 블록 침범 감시 (`TASK-125-2`, `-3`, `-4`, `-11`, `-12`)

### Interfaces
- **Consumes:** `amm_config.json` / `channel_lease.json`, `MSG_BLOCK_ASSIGN`, `MSG_CHANNEL_PROBE`, `Base+0..39` 인바운드 모뎀 프레임
- **Produces:** 백오프 지터 + 2회 재프로브 + 최대 3회 GCS 재요청 회피(`CONFLICT_DETECTED` → `conflictBase` 보고) + 조건부 오프라인 리스(`[NO_GCS_LEASE]` vs `LOCKED_NO_GCS`), 부팅 즉시 `Base+0` 응답기, 로컬 `channel_lease.json` 영속 마커, AMM 온보드 모뎀 전 블록(`Base+0..39`, ~40+채널) 개방·자국 `domainId` O(1) 통과·이종 침범 30초 지속 시 `FAILSAFE_HOLD`/`RTH` 트리거

### Files
- Modify: `src/3_planning/amm/modules/channel_sentinel.lua`
- Modify: `src/3_planning/amm/modules/network_manager.lua`
- Modify: `src/3_planning/amm/main.lua`
- Modify: `src/3_planning/amm/config/amm_config.json` & `src/0_development/installer/modules/manifest.lua`
- Modify: `tests/3_planning/amm/test_channel_sentinel.lua`
- Modify: `tests/3_planning/amm/test_network_manager.lua`
- Modify: `tests/3_planning/amm/test_main_loop.lua`

- [ ] **Step 1: 지터·다회 프로브·자기 UUID 무시·부팅 응답기·전 블록 침범 감시 단위 테스트 작성 (Red)**

`tests/3_planning/amm/test_channel_sentinel.lua` 및 `test_network_manager.lua`, `test_main_loop.lua`에 아래 케이스를 추가한다:
1. **동시 부팅 지터 + 2회 재프로브 (`TASK-125-2`):**
   - `start_bootstrap`이 `preferredBase` (로컬 캐시 존재 시)와 `requestedBandwidth = 40`을 싣는지 확인.
   - `on_block_assign(st, { baseChannel = 10040, status = "ASSIGNED" }, 1000, rng)` 시 `0 <= jitterMs <= 100` 동안 대기 후 Round 1 `MSG_CHANNEL_PROBE` 송신, `200ms` 침묵 시 Round 2 `MSG_CHANNEL_PROBE` 재송신, 두 라운드 모두 무응답일 때 `ACQUIRED` 확정 검증 (단일 200ms만으로 조기 확정하지 않음!).
   - `CONFLICT_DETECTED` 수신 시: 1~2회차 충돌에는 `LOCKED_CONFLICT` 대신 `REASSIGN_REQUEST` 상태 + `conflictBase = 10040`을 실은 `MSG_BLOCK_REQUEST` 생성(최대 `maxReassignAttempts = 3`회 자동 재요청); 3회 연속 충돌 초과 시 `LOCKED_CONFLICT` (`is_locked(st) == true`) 검증.
   - 자기 자신의 `hardwareUuid`로 들어온 `MSG_CHANNEL_PROBE`는 `nil` 반환(자기 충돌 미유발) 검증.
2. **부팅 직후 `Base+0` 프로브 응답기 (`TASK-125-4`):**
   - `st.status == "BOOT_VERIFY"` 또는 `"DISARMED"` / `"PROBING"` (보유/검증 중 로컬 `baseChannel = 10000` 바인딩 상태)에서 타 기체(`hardwareUuid = "OTHER"`)의 `MSG_CHANNEL_PROBE(candidateBase = 10000)` 수신 시 즉시 `MSG_CHANNEL_PROBE_ACK { status = "CONFLICT_DETECTED", occupiedBase = 10000, responderUuid = st.hardwareUuid }` 반환 검증.
3. **로컬 점유 마커 영속, 부팅 재검증 & 조건부 오프라인 정책 (`TASK-125-3`):**
   - `ACQUIRED` 확정 시 `save_lease_cache(st, leasePath)` 기록 및 재부팅 `init()` 시 `cachedBase = 10000` 로딩 → `start_bootstrap`에서 `preferredBase = 10000`으로 GCS 재검증 요청 → GCS가 `"REASSIGNED"` (`baseChannel = 10080`) 회신 시 새 채널로 안전 프로브/전환하고 구 채널 고집 금지.
   - GCS 오프라인 타임아웃 시: `cachedBase` 보유 + 다회 ARP 프로브 무충돌 통과 시 `ACQUIRED_OFFLINE` / `offlineWarning = "NO_GCS_LEASE"` (`is_locked(st) == false`); `cachedBase == nil`인 미보유 기체는 `LOCKED_NO_GCS` (`is_locked(st) == true`).
4. **전 블록(`Base+0..39`) 개방 및 침범 감시 (`TASK-125-11`):**
   - `network_manager:bind_modems`가 온보드 모뎀에 `baseChannel + 0 .. baseChannel + 39` 전 블록(40채널)을 개방하고(`<= 128` CC:Tweaked 상한 준수), 자국 `domainId` 패킷은 O(1) 즉시 통과(침범 카운트 0), `Base+8`, `Base+9`, `Base+10`, `Base+20`, `Base+30`, `Base+39` 등에서 `domainId ~= ownDomainId`인 외부 패킷 수신 시 침범 카운터 증가 및 차단(`INTRUSION_DETECTED`), 30,000ms 연속 침범 시 `HOVER_HOLD` / `FAILSAFE_HOLD` 트리거 검증.
5. **Rule 2 경계 단순 검증 (`TASK-125-12`):** `is_valid_base`가 `10000..49960`, 40배수 단일 수학식으로 검증됨 확인.

- [ ] **Step 2: Red 테스트 실행**

```powershell
python tools/run_unit_tests.py --target amm --clean-orphans
```
Expected: 다회 프로브 / 자기 UUID 필터 / 부팅 응답기 / 전 블록 침범 감시 테스트 FAIL.

- [ ] **Step 3: `src/3_planning/amm/modules/channel_sentinel.lua` 확장 구현 (Green)**

1. 상수 및 설정: `CRAFT_BANDWIDTH = 40`, `MIN_BASE = 10000`, `MAX_BASE = 49960` (`49960 + 39 = 49999` 단일 경계 검증), `DEFAULT_LISTEN_MS = 200`, `DEFAULT_JITTER_MAX_MS = 100`, `DEFAULT_PROBE_RETRIES = 2`, `INTRUSION_ESCALATE_MS = 30000`.
2. `init(cfg, nowMs, leasePath)`:
   - 로컬 캐시 `config/channel_lease.json` (`fs.exists` 확인 후 안전 읽기)에서 `cachedBase` / `hardwareUuid` 일치 시 `st.cachedBase = ...`, `st.baseChannel = cachedBase` (단, `ACQUIRED` 전까지 프로브 응답용 바인딩만 활성화하고 비행 Arming은 GCS 확인+프로브 통과 후 허용).
   - `st.rngSeed`는 `hardwareUuid` 해시 + `nowMs` 혼합 결정적 PRNG로 생성 (단위 테스트에서 `rng` 주입 오버라이드 가능).
3. `start_bootstrap` & `on_block_assign`:
   - `start_bootstrap`: `payload = { domainId = st.domainId, hardwareUuid = st.hardwareUuid, requestedBandwidth = 40, preferredBase = st.cachedBase or st.baseChannel }`.
   - `on_block_assign`: `"DENIED"`/`"FAILED"` 시 `LOCKED_CONFLICT`; `"ASSIGNED"`/`"REASSIGNED"` 시 `st.candidateBase = assignPayload.baseChannel`, `st.jitterDelayMs = ... (0..100)`, `st.probeRound = 0`, `st.probeMaxRounds = 2`, `st.status = "JITTER_WAIT"`.
4. `negotiate_and_probe(st, nowMs, probesOut)`:
   - `JITTER_WAIT` 경과 시 Round 1 송출 → `PROBING` (`probeWaitMs = 200`) → 무응답 만료 시 `probeRound < probeMaxRounds`이면 짧은 재지터(0~50ms) 후 Round 2 재송신 → 전 라운드 무응답 시 `ACQUIRED` + `save_lease_cache`.
   - `GCS_WAIT` 타임아웃(`2000ms`) 시: `st.cachedBase ~= nil`이면 `candidateBase = st.cachedBase`로 오프라인 다회 프로브 진행 후 통과 시 `ACQUIRED_OFFLINE` + `offlineWarning = "NO_GCS_LEASE"`, `st.cachedBase == nil`이면 `LOCKED_NO_GCS`.
   - `CONFLICT_DETECTED` 수신 시: `st.reassignAttempts = st.reassignAttempts + 1`; `st.reassignAttempts < 3`이면 `conflictBase = st.candidateBase`를 기록하고 `status = "REASSIGN_REQUEST"`로 전이해 GCS `MSG_BLOCK_REQUEST(conflictBase)` 자동 재요청; `>= 3`이면 `LOCKED_CONFLICT` (`is_locked(st) == true`).
5. `handle_incoming_probe(st, pkt)`:
   - `pkt.payload.hardwareUuid == st.hardwareUuid` → `nil` (자기 자신 송신 루프백 무시!).
   - `st.status == "ACQUIRED"` 또는 `((st.status == "BOOT_VERIFY" or st.status == "DISARMED" or st.status == "PROBING" or st.status == "JITTER_WAIT") and (st.baseChannel == cand or st.candidateBase == cand))`이면 `MSG_CHANNEL_PROBE_ACK { status = "CONFLICT_DETECTED", occupiedBase = cand, responderUuid = st.hardwareUuid, responderStatus = st.status }` 즉시 반환.
6. `record_intrusion_sample(st, channel, domainId, nowMs)` & `step_intrusion_watchdog(st, nowMs)`:
   - `is_in_own_block(st, channel)` (`base <= channel <= base + 39`): 타 기체 `domainId ~= st.domainId` (및 인프라 화이트리스트 외) 패킷 감지 시 `st.intrusionCount` 증가, 최초/연속 침범 타임스탬프 추적 → `nowMs - st.intrusionFirstMs >= 30000` 지속 시 `"FAILSAFE_ESCALATE"` 반환.

- [ ] **Step 4: `AMM` `network_manager.lua` & `main.lua` 연결 (Green)**

1. `network_manager:bind_modems` & `main.lua`: 부팅 즉시 `Base+0` (`CH_OPERATOR_C2`) 개방 및 블록 확정/캐시 시 온보드 모뎀 `Base+0..39` 40채널 전수 개방 보장(`TASK-125-4`, `TASK-125-11`), `step_sentinel_20hz`가 `GCS_WAIT`/`JITTER_WAIT`/`PROBING`/`REASSIGN_REQUEST`/`ACQUIRED` 상태를 비동기 스텝으로 구동하며 충돌 시 `conflictBase`를 실은 `MSG_BLOCK_REQUEST` 재요청 송신.
2. `main.lua` (`handle_modem_message`): 최상단에서 `domainId == self.domainId`인 정상 자국 패킷은 O(1) 즉시 정상 디스패치로 통과하고, `Base+0..39` 내 이종 `domainId` 패킷만 `channel_sentinel.record_intrusion_sample`로 전달해 카운트·차단하며 30초 연속 침범 시 `arbiter` / `trajectory` 안전 체공 전이 연동.

- [ ] **Step 5: 단위 테스트 실행 & 커밋**

```powershell
python tools/run_unit_tests.py --target amm --clean-orphans ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" add src/3_planning/amm/ src/0_development/installer/modules/manifest.lua tests/3_planning/amm/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "feat(amm): add probe jitter, multi-probe, boot responder, lease cache, and full-block intrusion monitor" } }
```
Expected: `amm` 단위 테스트 PASS.

---

## Task 6: Zone 3 `Base+30..39` 확장 재편 및 `formationLink` 제거 (`TASK-125-7`)

### Interfaces
- **Consumes:** `config/protocol_contracts.json` (`zone3_payload_ext`, `zone4_swarm_formation` 제거)
- **Produces:** `VAS` `ZONE_OFFSETS`에서 `formationLink = 30` 제거 및 `payloadExtStart = 30` / Zone 3 확장 주석 정렬, `tests/1_control/vas/test_vas_core.lua` 정합화 (표준 `ACT_PAY_BUS_CMD` `20..29` 및 `tools/amm_mission_editor.html` 불변 준수)

### Files
- Modify: `src/1_control/vas/modules/network_manager.lua`
- Modify: `src/0_development/installer/modules/manifest.lua` (if `formationLink` referenced)
- Modify: `tests/1_control/vas/test_vas_core.lua`

- [ ] **Step 1: `test_vas_core.lua` L246 단언을 `formationLink == nil` & Zone 3 확장 검증으로 갱신 (Red)**

`tests/1_control/vas/test_vas_core.lua`에서:
- `assert_nil(net.channels.formationLink)` (`TASK-125-7`: 편대 비행은 `TBD` 독립 광역 데이터링크로 이관됨) 추가.
- 기존 `assert_eq(net.channels.formationLink, 10030)` 제거.

- [ ] **Step 2: Red 테스트 실행**

```powershell
python tools/run_unit_tests.py --target vas --clean-orphans
```
Expected: `assert_nil(net.channels.formationLink)` FAIL.

- [ ] **Step 3: `src/1_control/vas/modules/network_manager.lua` 정리 (Green)**

`network_manager.ZONE_OFFSETS` 및 `init`에서 `formationLink = 30` 필드 제거하고 `-- Base+30..39: Zone 3 Payload & Special Mission Extension (Formation Link moved to TBD wide-area datalink)` 주석만 유지.

- [ ] **Step 4: 단위 테스트 실행 & 커밋**

```powershell
python tools/run_unit_tests.py --target vas --clean-orphans ; if ($?) { python tools/run_unit_tests.py --target amm --clean-orphans } ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" add src/1_control/vas/ tests/1_control/vas/ ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "refactor(vas): remove legacy formationLink=30 in favor of Zone 3 Base+30..39 extension" } }
```
Expected: `vas`, `amm` 단위 테스트 PASS.

---

## Task 7: 다중 노드 E2E 시뮬레이션 정합화, 전사 가드레일·변이 테스트 검증, 사양서 `Implemented` 승격 및 컨텍스트 동기화 (`TASK-125-13`)

### Interfaces
- **Consumes:** 완료된 Task 1~6 사양서, 계약 SSOT, 6대 코드베이스 변경분
- **Produces:** 개정된 E2E 스위트(동시 부팅 경합 회피, 꺼진 점유자 재검증/`REASSIGNED`, `Base+9` E_STOP, `Base+8` 교정, `Base+3` 핸드오버, `FDR` `Base+9` 감청), 7대 검증 CLI 0-error 통과, `Implemented` 승격된 6대 서브시스템 사양서, 동기화된 `TASK.md`, `.agent/memory/workspace-root.md`, `GEMINI.md`

### Files
- Modify: `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`
- Modify: `tests/e2e/test_e2e_c2_and_estop.lua`
- Modify: `tests/e2e/test_e2e_hangar_alignment.lua`
- Modify: `tests/e2e/test_e2e_fdr_blackbox.lua`
- Modify: `tests/e2e/test_e2e_advanced_vtol_flight.lua` (if `Base+1` E_STOP / `Base+0` calibration used — inspect before editing)
- Modify: `tests/e2e/test_e2e_waypoint_guidance.lua` (if affected)
- Modify (status `Approved` → `Implemented`): `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`, `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`, `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`, `docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`, `docs/specs/0_development/fdr/FDR_PROGRAM_SPECIFICATION.md`
- Modify: `TASK.md`, `.agent/memory/workspace-root.md`, `GEMINI.md` (if snapshot invariants/versions need sync)

- [ ] **Step 1: E2E 테스트 파일 정합화 및 신규 시나리오 검증 추가 (Red → Green)**

1. `tests/e2e/test_e2e_c2_and_estop.lua`:
   - `vas.modem:open(10009)` 및 `vas_state.channels.emergency = 10009`, `calibration = 10008` 설정.
   - `AMM` 및 `GCS` `E_STOP` 송신이 `10009` (`Base+9`)로 전송됨을 단언 (`bus:find_packets({ type = "MSG_EMERGENCY_OVERRIDE", channel = 10009 })`) 및 구 `10001` E_STOP 주입 시 `VAS` 거부 음성 테스트 추가.
2. `tests/e2e/test_e2e_hangar_alignment.lua`:
   - `vas.modem:open(10008)` (기존 `open(10000)` 제거), `Alignment`가 `10008` (`Base+8`)로 `MSG_CALIBRATION_INIT` 전송, `10000`에 전송된 교정 패킷 거부 및 `10000` C2 패킷 `VAS` 미수신 음성 테스트 추가.
3. `tests/e2e/test_e2e_fdr_blackbox.lua`:
   - `FDR`이 `Base+9` (`10009`)를 감청해 `MSG_EMERGENCY_OVERRIDE` / `MSG_EMERGENCY_ALERT` 수신 및 `autoFlushOnEstop` 동작 확인 (`txSpy == 0` 불변).
4. `tests/e2e/test_e2e_bootstrap_and_telemetry.lua`:
   - 2기체(`AIRCRAFT_01` 꺼진 점유자 캐시 `preferredBase=10000` + `AIRCRAFT_02` 동시 부팅) 시나리오 추가: GCS 영속 레지스트리 기반 `"REASSIGNED"` 응답 + 지터/2회 프로브 경유 충돌 회피 검증.
5. 나머지 E2E 파일(`test_e2e_advanced_vtol_flight.lua` 등) 내 `Base+1` E_STOP / `Base+0` Calibration 잔존 사용처 전수 검사 (`git grep`) 후 `Base+9`/`Base+8`로 정렬.

- [ ] **Step 2: E2E 및 전체 단위 테스트·계약 검증 실행**

```powershell
python tools/run_unit_tests.py --require-tests --clean-orphans ; if ($?) { python tools/run_e2e_tests.py --clean-orphans }
```
Expected: 전체 단위 테스트 13개 타깃 PASS, E2E 테스트 9개 스위트 PASS 및 계약 위반 `0 violations`.

- [ ] **Step 3: 6대 서브시스템 사양서 `Implemented` 승격 및 연관 문서 버전·상태 정합**

`verify_contracts.py`와 `run_e2e_tests.py` 통과 확인 직후, Task 1에서 `Approved`로 두었던 6대 사양서(`AMM v2.1.0`, `VAS v1.22.0`, `FCP v2.2.0`, `GCS v1.2.0`, `ALIGNMENT v2.8.0`, `FDR v0.4.0`) 상단 메타데이터 `문서 상태 (Status)`를 `Implemented`로, `최종 수정일`을 당일 날짜로 갱신한다(마스터 ICD `v1.32.0` 및 전체 구조도 `v2.16.0`은 기준 문서 규약에 따라 `Approved` 유지).

- [ ] **Step 4: 전사 7대 가드레일·변이 살상·매니페스트 정합 실행**

```powershell
python tools/verify_all_specs.py --check-readmes ; if ($?) { python tools/verify_spec_status.py } ; if ($?) { python tools/verify_contracts.py } ; if ($?) { python tools/verify_runtime_wiring.py } ; if ($?) { python tools/run_boot_smoke.py --clean-orphans } ; if ($?) { python tools/verify_manifest_sync.py } ; if ($?) { python tools/run_mutation_tests.py } ; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }
```
Expected: 모든 스크립트 `0 Errors, 0 Warnings` / `PASS` / `11/11 PASS` / `25/25 KILLED` 및 `src/1_control/asa/**` `0 diff` (`git status` 확인).

- [ ] **Step 5: `TASK.md`, `.agent/memory/workspace-root.md`, `GEMINI.md` 동기화 및 `verify_context_docs.py` 통과**

- `TASK.md`: `TASK-125` 및 `TASK-125-1..13` 체크 `[x]` 처리 후 `§3 완료된 작업 이력` 최상단 이동(최근 10개 상한 유지).
- `.agent/memory/workspace-root.md`: `TASK-125` 완료 이력 1항목 추가(`TASK-ID` 명기, 실측 수치 포함).
- `GEMINI.md`: `1. Current Phase & Active Handover` 및 `4. Gotchas & Invariants` (40채널 요약에 `Base+8` 교정, `Base+9` 비상, `Base+30..39` Zone 3 확장, 편대 `TBD` 반영, strictly <= 80 lines 준수).
- 검증:
```powershell
python tools/verify_context_docs.py
```
Expected: `0 findings`.

- [ ] **Step 6: 최종 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tests/ docs/ TASK.md .agent/memory/workspace-root.md GEMINI.md ; if ($?) { & "C:\Program Files\Git\cmd\git.exe" commit -m "test,docs(TASK-125): verify multi-node E2E, promote specs, and sync context" }
```
