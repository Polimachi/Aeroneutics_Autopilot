# TASK-014: 전수 감사 3대 사각지대 방지 가드레일 설계서

> **작성일**: 2026-11-14  
> **대상 과제**: `TASK-014` (`reports/reviewCompleted/Audit_Report_1_11142026.md` 후속 재발 방지 체계)  
> **상태**: 설계 확정 (`Approved` 대기)

---

## 1. 목적 및 배경 (Intent & Why)

`TASK-013` 전수 감사([Audit_Report_1_11142026.md](../../../reports/reviewCompleted/Audit_Report_1_11142026.md))에서 기존 정적·동적 검증 파이프라인(`verify_all_specs.py`, `verify_spec_status.py`, `verify_manifest_sync.py`, `run_unit_tests.py`, `run_e2e_tests.py`, `run_mutation_tests.py`)이 전부 `Exit 0`을 반환했음에도 아래 3대 구조적 사각지대에서 43건의 결함이 누적되었다.

1. **사양서 간 SSOT 분열**: `Master ICD`, `Diagram`, 14개 서브시스템 사양서가 패킷명·채널·필드명·열거형·타임아웃을 자유 형식 마크다운으로 중복 서술해 사양서 간 충돌(`[I-9]` Camp A/B, `[I-5]` 3분열, `[I-4]` 채널/스키마 불일치)을 기존 링크/금지어 스캐너가 탐지하지 못했다.
2. **계층 간 와이어 계약 불일치**: 단위 테스트가 모듈별 수동 Mock에 의존하고, `tests/e2e/`도 `virtual_bus`를 경유한 패킷의 공통 엔벨로프·스키마·수치 범위·Zero-Fallback 준수 여부를 기계적으로 검증하지 않아 송신단과 수신단 스키마 어긋남(`VAS -> ASA`, `Landing Pad -> GAC`, `AMM <-> FCP`)이 통과했다.
3. **미배선 런타임 경로**: `modules/*.lua` 단위 통과와 별개로 실제 진입점 `main.lua`의 `require` 경로 유효성, 모듈 도달성(고아 파일 `TST-LOW-01`), 임포트 후 미사용, 실제 CraftOS-PC 설치 레이아웃 부팅 및 초기 틱 무결성이 검증되지 않았다.

본 설계는 `.py` 외부 검증 도구와 CraftOS-PC 기반 스모크/패킷 검증을 우선 구축하고, `.py`로 강제할 수 없는 변경 절차(계약 갱신 및 완료 게이트 실행)만 `.agent/` 작업 컨텍스트로 보완해 위 3대 사각지대를 구조적으로 차단한다.

---

## 2. 목표, 비목표 및 안티목표 (Goals, Non-Goals, Anti-Goals)

### 목표 (Goals)
- 기계가 판독 가능한 단일 프로토콜 계약 정본(`config/protocol_contracts.json`)을 두고, `.py` 도구가 **16개 활성 사양서**, **E2E 실전 패킷 캡처**, **활성 `src/` Lua/JSON 설정**을 단일 정본 기준으로 교차 검증한다.
- E2E 시뮬레이션(`virtual_bus.lua` + `tools/run_e2e_tests.py`) 중 버스를 통과하는 모든 패킷을 `protocol_contracts.json` 스키마로 자동 검증해 계약 위반·`[DEPRECATED]` 패킷/필드 송출 시 즉시 실패시킨다.
- `.py` 정적 도달성/배선 검증기(`tools/verify_runtime_wiring.py`)와 CraftOS-PC 실부팅 스모크 러너(`tools/run_boot_smoke.py`)로 고아 모듈, 깨진 `require`, 미호출 임포트, `main.lua` 부팅 크래시·채널 미개방을 차단한다.
- 현행 동결(`TASK-105`, `src/1_control/asa`) 및 코드 미구현(`RUNWAY`, `DOCKING_ARM`) 서브시스템은 기존 `DEFERRED_SUBSYSTEM_DIRS` 정책과 동일하게 사양서 SSOT 검증은 수행하되 런타임/코드 검증은 기본 유예(`--include-deferred`로 강제 가능)한다.

### 비목표 (Non-Goals)
- `src/<layer>/<name>/` 간 런타임 Lua 공용 패킷/유틸리티 모듈 도입 (멀티 코드베이스 독립 완결성 불변식 유지).
- 기존 16개 사양서 마크다운 본문에 기계 파싱용 HTML 마커(`<!-- contract:... -->`)를 전면 삽입하는 대규모 문서 재작성.
- 매 AI 턴 종료 `Stop` 훅(`.agent/hooks/context_doc_guard.py`)에 무거운 CraftOS-PC 실행을 추가해 대화 반응 속도를 저하시키는 것.
- 기존 `tests/e2e/` 8종 시나리오의 일괄 재작성.

### 안티목표 (Anti-Goals)
- 검증 통과를 위해 Zero-Fallback 예외나 광범위한 침묵(Allowlist 남용)을 기본값으로 두어 실제 계층 불일치를 은폐하는 설계.
- `Revision History`나 `[DEPRECATED]` 표기 영역에서 정당한 구버전 변경 이력 언급을 오탐(False Positive)으로 차단해 운영 불가능하게 만드는 규칙.

---

## 3. 제약 조건 (Constraints)

- **멀티 코드베이스 독립성**: `src/<layer>/<name>/` 간 공용 `.lua` 모듈 직접 참조 금지 (유일한 공용 라이브러리는 `/lib/avionics_sensors.lua`).
- **하위 호환 및 기존 훅 경량화**: `virtual_bus.lua` 기존 API(`create_bus`, `create_modem`, `step`, `find_packets`, `clear_log`)를 깨지 않으며, `Stop` 훅은 기존 R1~R8 경량 검사만 유지한다.
- **동결 경계 보호**: `src/1_control/asa/**` 및 `tests/1_control/asa/**`는 `TASK-105` 재개 전까지 `0 diff` 동결을 유지한다.
- **도구 무결성 통합**: `tools/` 하위에 추가되는 `.py` 도구는 `tests/harness/test_tools_integrity.py` 및 `tests/harness/` 단위 테스트에 등록해 회귀 검증 가능해야 한다.
- **표현 규율**: 과장 표현(`100% 보장`, `무결점`, `원천 차단` 등)을 사용하지 않고 검사 범위와 조건을 사실 그대로 명시한다.

---

## 4. 고려한 접근법 및 선택 근거 (Approaches)

| 영역 | 검토 대안 | 장단점 및 트레이드오프 | 채택 결정 |
| :--- | :--- | :--- | :--- |
| **계약 SSOT 원천** | ① `config/protocol_contracts.json` 신설<br>② `Master ICD` 마크다운 직접 파싱<br>③ JSON에서 마크다운/Lua 자동 생성 | ②는 한글 서술·LaTeX 수식 파싱 취약성 높음. ③은 16개 사양서 및 117개 Lua 파일 침습도 과다. ①은 파싱 안정성과 3자 교차 검증(사양서·E2E·코드) 균형이 가장 우수. | **① `config/protocol_contracts.json`** |
| **사양서 SSOT 검사** | ① 다층 정적 대조(패킷/채널/핵심 필드/열거형/타임아웃 + `[DEPRECATED]` 누락·회귀값 검출)<br>② 마커 블록(`<!-- contract -->`) 강제<br>③ 패킷명·채널만 최소 검사 | ②는 기존 16개 사양서 전면 편집 필요. ③은 `I-9` 필드명·타임아웃·상태 열거형 분열 재발 방지 불가. | **① 다층 정적 대조** |
| **와이어 계약 검증** | ① E2E 버스 패킷 캡처 `.py` 검증 + 정적 폴백/폐기키 린트<br>② Lua 게스트 내부 실시간 `error()`만<br>③ 정적 Lua/JSON 키 스캔만 | ②는 정적 `src/` 이중키 폴백 미검출. ③은 동적 페이로드 타입·범위·조립 오류 미검출. | **① E2E 패킷 캡처 + 정적 린트 병행** |
| **미배선 경로 검출** | ① 정적 `main.lua` 도달성/임포트 검사(`.py`) + CraftOS-PC 실부팅 스모크<br>② 정적 도달성 검사만<br>③ 기존 E2E 전면 `main.lua` 부팅형 개편 | ②는 `require` 경로/부팅 인자/채널 미개방 등 런타임 결함 누락. ③은 기존 E2E 8종 리팩토링 비용 과다. | **① 정적 도달성 + 실부팅 스모크 병행** |
| **파이프라인/에이전트 연동** | ① `tools/` + `tests/harness/` + `run_e2e_tests.py` 통합 + `.agent/` 규칙·스킬 게이트 (Stop 훅 경량 유지)<br>② Stop 훅에 정적 검사 직접 삽입<br>③ `tools/`만 추가 | ②는 미완성 중간 편집 턴마다 훅 오작동/마찰 유발. ③은 신규 사양 수정 시 `protocol_contracts.json` 갱신 누락 가능. | **① 파이프라인 통합 + 스킬/규칙 게이트** |
| **유예 범위 취급** | ① `asa` 코드 기본 유예(`--include-deferred`), 사양서 SSOT는 전 16종 검사<br>② `asa` 코드 즉시 검사 + allowlist<br>③ `Implemented` 11종만 검사 | ②는 동결 파일 주변 allowlist 유지 부담. ③은 `Master ICD`/`Diagram`/`ASA`/`RUNWAY`/`DOCKING_ARM` 분열 방치. | **① `asa` 코드 유예 + 사양서 16종 전수 검사** |

---

## 5. 상세 아키텍처 (Decided Architecture)

### 5.1 계약 SSOT (`config/protocol_contracts.json`)
- **역할**: 전 시스템 유선/무선 통신 계약의 기계 판독형 정본.
- **최상위 구조**:
  - `schemaVersion`: 계약 스키마 버전 문자열.
  - `envelope`: 공통 엔벨로프 버전(`"1.9.5"`) 및 필수 최상위 키(`["ver", "domainId", "seq", "type", "time", "payload"]`).
  - `channels`: 전역 고정 채널(`50000..50004`, `60001..60004`), 격납고 대역(`101..200`, `hangarBandwidth: 10`), 기체 40채널 대역(`baseMin: 10000`, `baseMax: 49960`, `bandwidth: 40`, Zone 오프셋 규칙, `deprecatedOffsets: [6, 7]`).
  - `interfaces`: `I-1` ~ `I-12` 인터페이스 배열. 각 항목은 `id`, `specs`(관련 사양서 상대 경로 목록), `channelMatchers`(오프셋 또는 전역 채널 목록), `packets`(패킷별 `requiredKeys`, `fieldTypes`, `numericBounds`, `enums`), `timeoutsMs`, `deprecatedPacketTypes`, `deprecatedPayloadKeys`, `regressionPatterns`(과거 충돌 수치/키)를 보유한다.
  - `missionSchema`: 미션 JSON `v2.0.0`의 활성 `ACT_*`(36), `DEC_*`(6), `MAC_*`(3), `CONDITION_TYPES`(14), 폐기된 `v1.x` 액션/키 목록.
  - `deferredSubsystems`: `["src/1_control/asa"]` (런타임/정적 코드 검사 기본 유예 대상).

### 5.2 SSOT 정합성 및 정적 폴백 린터 (`tools/verify_contracts.py`)
1. **사양서 SSOT 대조 (`verify_specs_against_contracts`)**:
   - `verify_spec_status.py`에 등재된 활성 16종 사양서를 대상으로 동작(`Draft` 상태 파일 제외).
   - `Revision History` 섹션(metadata 표 아래 다음 `---` 또는 `## 1.` 직전까지)을 분리해 과거 변경 이력 서술에서의 오탐을 배제한다.
   - `Master ICD` 및 `Diagram`이 모든 활성 인터페이스(`I-1`~`I-12`)의 정본 패킷명과 채널 규칙을 포함하는지 검증한다.
   - 각 인터페이스 `specs` 목록의 사양서가 정본 패킷명·핵심 필드/열거형·주요 타임아웃(`500ms`, `120,000ms` 등)을 누락하지 않았는지, 반대로 `deprecatedPacketTypes`·`deprecatedPayloadKeys`가 `[DEPRECATED]` / `DEPRECATED` 표기 없이 등장하거나 `regressionPatterns`가 비폐기 맥락에 등장하지 않는지 검증한다.
2. **정적 Lua/JSON 와이어 및 Zero-Fallback 검사 (`verify_code_against_contracts`)**:
   - 활성 `src/<layer>/<name>/` 하위 `.lua` 및 `config/*.json`을 스캔한다(`deferredSubsystems`는 `--include-deferred` 지정 시에만 포함).
   - 주석·문자열 경계를 분리한 뒤, 금지된 `deprecatedPacketTypes` 문자열 리터럴 사용, 대표적인 이중키 폴백 패턴(`payload.X or payload.Y`, `cfg.outerLoop or cfg.se3`, `s.ELEV or s.elevator` 등 `or` 기반 다중 키 대체), 구형 설정 키(`surfaceMix`, `aeroEnvelope`, `navStaleEpochMs` 등)를 검출한다.
   - 모든 `src/**/config/*.json`의 JSON 파싱 무결성을 검사한다.
3. **E2E 패킷 검증 엔진 (`validate_captured_packets`)**:
   - `run_e2e_tests.py`가 호출하는 순수 Python 검증 함수로도 제공된다.
   - 패킷별 공통 엔벨로프(`ver == "1.9.5"`, `domainId` 문자열, `seq` 숫자, `type` 문자열, `time` 숫자, `payload` dict) 검사.
   - `channel` 및 `payload.type`으로 `interfaces` 규칙을 매핑해 `deprecatedPacketTypes`/`deprecatedPayloadKeys` 사용 시 FAIL, `requiredKeys` 누락 시 FAIL, `enums` 불일치 시 FAIL, `numericBounds`(`min`/`max`) 이탈 시 FAIL.

### 5.3 E2E 실전 패킷 캡처 연동 (`harness/simulation/virtual_bus.lua` + `tools/run_e2e_tests.py`)
- `virtual_bus.lua`:
  - `_G.__VIRTUAL_BUS_PACKET_LOG`가 테이블로 설정되어 있으면(또는 `bus:deliver()` 시점마다) 모든 송신 패킷 `{ suite = ..., channel, replyChannel, from, time, payload }`를 누적 기록한다.
  - 기존 `virtual_bus.create_bus` / `step` / `find_packets` / `clear_log` 시그니처와 동작은 100% 보존한다.
- `tools/run_e2e_tests.py`:
  - 게스트 `startup_script`에서 `_G.__VIRTUAL_BUS_PACKET_LOG = {}`를 초기화하고, `R.write_result` payload에 `captured_packets`를 포함해 호스트로 반환한다.
  - 호스트 Python 측에서 테스트 통과 후 `validate_captured_packets`를 실행해 단 1건의 와이어 계약 위반이 있어도 `run_e2e_tests.py` 전체 결과를 `FAIL`(Exit 1)로 반환한다(`--skip-contract-check` 옵션은 디버그 용도로만 제공).

### 5.4 미배선 런타임 경로 차단 (`tools/verify_runtime_wiring.py` + `tools/run_boot_smoke.py`)
1. **정적 배선 및 도달성 검증 (`tools/verify_runtime_wiring.py`)**:
   - `manifest.lua`와 `src/<layer>/<name>/main.lua` 보유 서브시스템(기본: 활성 10종; `asa`는 `--include-deferred`)을 대상으로 그래프를 구축한다.
   - `main.lua`(및 `main.lua`가 `shell.run`으로 실행하는 진입 파일: 예 `gps`의 `server.lua`, `node.lua`, `client_entry.lua`)를 루트로 삼아 `require(...)`, `dofile(...)`, `loadfile(...)`, `shell.run(...)` 참조를 재귀 추적한다.
   - 검사 규칙:
     - **깨진 참조 (Broken Reference)**: 호출된 모듈/스크립트 파일이 해당 서브시스템 내 유효 탐색 경로(또는 `/lib/avionics_sensors.lua`)에 존재하지 않으면 FAIL. 또한 `main.lua`가 `modules/` 하위 파일을 `require("foo")` 형태로 호출할 때, `main.lua` 자체 또는 `installer/modules/startup_generator.lua`가 `modules/?.lua`를 지원하는지 확인하고 불일치 시 FAIL.
     - **고아 모듈 (Orphan Module)**: 서브시스템 내 `.lua` 파일 중 루트에서 도달 불가능한 파일이 있으면 FAIL (`node_*.lua` 하네스 전용 시뮬레이션 더미 및 명시적 allowlist 제외; 기본 allowlist는 빈 상태 유지 목표).
     - **미사용 임포트 (Dead Import)**: `main.lua`에서 `local mod = require("...")`로 바인딩한 식별자 `mod`가 해당 파일 본문의 다른 라인에서 한 번도 참조되지 않으면 FAIL.
2. **CraftOS-PC 실부팅 스모크 러너 (`tools/run_boot_smoke.py`)**:
   - `src/0_development/installer/modules/manifest.lua`의 실제 배포 파일 매핑 또는 서브시스템 루트 레이아웃대로 각 서브시스템을 CraftOS-PC 세션에 스테이징한다(`modules/`, `hal/`, `config/`, `/lib/avionics_sensors.lua` 포함).
   - `startup_generator.lua`와 동일한 `package.path` 주입 환경에서 `parallel.waitForAny` 감독 코루틴으로 각 `main.lua`를 실행한다:
     - 서브시스템별 스모크 부트 인자/사전 조건 매트릭스(예: `installer` `--help` 또는 비대화형 검사 모드, `gps` 기본 `server` 모드 및 `node`/`client` 모드, `tca` 사전 `config.json` 스테이징으로 대화형 마법사 블로킹 회피, `fcp`/`gcs` `--daemon` 또는 기본 모드)를 명시한다.
     - 모의 `modem`·`monitor`·`redstone`·`avionics` 주변기기를 부착하고 약 `0.35s`(약 7틱) 무오류 구동을 유지한 뒤 `terminate` 이벤트 또는 타임아웃으로 종료한다.
     - 부팅 중 Lua 예외, `require` 실패, 혹은 선언된 필수 수신 채널 미개방 시 해당 서브시스템을 FAIL 처리한다.

### 5.5 파이프라인 및 에이전트 컨텍스트 통합
- **`tests/harness/` 단위 테스트 추가 및 등록**:
  - `tests/harness/test_verify_contracts.py`: 정상/위반(`Revision History` 예외 포함, 이중키 폴백, 폐기 토큰) fixture 테스트.
  - `tests/harness/test_verify_runtime_wiring.py`: 고아 모듈, 깨진 `require`, 미사용 임포트 검출 fixture 테스트.
  - `tests/harness/test_e2e_contract_validation.py`: `validate_captured_packets`의 엔벨로프·필수키·열거형·수치범위·폐기패킷 차단 테스트.
  - `tests/harness/test_tools_integrity.py`: `verify_contracts.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py` 존재 및 실행 검증 추가.
- **에이전트 컨텍스트(.agent/) 보완**:
  - `.agent/rules/skill-workflows.md`:
    - 활성 사양서 프로토콜/패킷/채널/열거형 변경 시 `config/protocol_contracts.json` 동시 갱신 의무 명시.
    - 작업 완료 보고 전 `verify_contracts.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py` 실행 의무 추가.
  - `.agent/skills/specification-lifecycle-manager/SKILL.md`: Case B 및 Option 2 Phase 1에서 `config/protocol_contracts.json` 동기화 및 `python tools/verify_contracts.py` 통과를 필수 체크 항목으로 추가.
  - `.agent/skills/verification-before-completion/SKILL.md`: 최종 검증 체크리스트에 `verify_contracts.py`, `verify_runtime_wiring.py`, `run_boot_smoke.py` 추가.
  - `.agent/hooks/context_doc_guard.py`: 기존 R1~R8 경량 게이트만 유지(턴 지연 방지).

---

## 6. 구현자에게 위임되는 세부 사항 (What's Left to the Builder)

- `config/protocol_contracts.json` 내 `[I-1]` ~ `[I-12]` 각 패킷의 상세 `requiredKeys` 및 `numericBounds` 초기 데이터 추출 (`AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` 및 15개 활성 사양서 현행 본문 기준).
- `tools/run_boot_smoke.py`에서 10개 서브시스템별 최소 모의 주변기기(`modem`, `monitor`, `velocity`, `altitude`, `gimbal`, `thruster` 등) 및 `config.json` 스모크 픽스처 세부 구성 (`installer`가 비대화형 스모크 플래그 미보유 시 최소 `--smoke-check` 또는 호출 방식 조율 포함).
- `verify_runtime_wiring.py`에서 `pcall(require, ...)`와 동적 테이블 호출 같은 특수 케이스의 정밀 AST/정규식 판별 세부 구현.
