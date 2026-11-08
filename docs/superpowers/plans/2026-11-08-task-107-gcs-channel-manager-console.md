# TASK-107: GCS 채널 관리자 및 지상 비행 지휘 콘솔 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CC:Tweaked Advanced Computer 환경에서 40채널 블록($N=1\sim 1000$, $10000\sim 49960$) 스티키 자동 배정 및 충돌 중재를 수행하는 GCS 채널 관리자(`CH 50000`)와 다중 기체 원격 비행 지휘 콘솔(51x19 TUI)을 독립 완결형 패키지로 구현한다.

**Architecture:** GCS는 `CH 50000`(`CH_BOOTSTRAP`)을 상시 청취하여 신규 기체의 `MSG_BLOCK_REQUEST`에 대해 JSON 영속화 레지스트리 기반의 고유 40채널 블록(`MSG_BLOCK_ASSIGN`)을 스티키 배정하고, 선택된 활성 기체의 `Base+3` 텔레메트리를 5Hz로 수신해 실시간 HUD를 렌더링하며, `Base+0`으로 원격 C2 오버라이드(`MSG_OPERATOR_CMD`) 및 `Base+1` 직결 하드 비상차단(`MSG_EMERGENCY_OVERRIDE`, `E_STOP`)을 송출한다.

**Tech Stack:** CC:Tweaked Lua 5.2, ComputerCraft `term.blit` / `parallel` / `os.pullEventRaw`, CraftOS-PC Headless Unit Test Runner (`tools/run_unit_tests.py`).

**Spec:** `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` (신규 작성, `Draft` $\to$ `Approved`)

---

## Global Constraints

- **Single Function Length**: 개별 Lua 함수는 50줄 이내를 엄수한다 (모듈화 및 단일 책임 원칙).
- **Multi-Codebase Autonomy**: `src/0_infra/gcs/`는 외부 패키지 직접 require 없이 독립 완결형으로 구성한다.
- **RF Spectrum Standard**: 기체 40채널 표준 규격 $Base = 10000 + (N-1) \times 40$ ($N=1\sim 1000$, 대역 $10000\sim 49999$) 및 `CH 50000` 부트스트랩 채널을 준수한다.
- **Zero-Fallback Single-Key**: UAFS Network Envelope v1.9.5 표준 스키마 단일 경로만 처리하며 레거시 듀얼키 폴백을 일체 배제한다.
- **Overclaim Ban**: "완벽", "무결점", "100% 보장" 등의 과장 표현을 코드, 주석, 문서 어디에도 기재하지 않는다.
- **Terminal Resolution**: 51x19 표준 컬러 터미널 해상도에 최적화하여 좌측 기체 텔레메트리 HUD(25열), 우측 등록 기체 목록/채널 할당 현황(26열), 하단 3행 명령 상태바를 분할 렌더링한다.

---

## Review Focus

1. **채널 재할당 시 스티키(Sticky) 보존**: 동일한 `domainId` 또는 `hardwareUuid`로 재요청 인입 시 기존 번호($N$)를 유지하고 중복 번호를 새로 채번하지 않는지 검증.
2. **블록 소진 및 대역 범위 방어**: 1,000대 상한($N=1000, Base=49960$) 초과 시 또는 유효 범위를 벗어난 번호가 요청될 때 `DENIED` 상태를 정상 회신하는지 검증.
3. **C2 오버라이드 권한 명시**: 원격 지령 송출 시 `authority = "GCS_OVERRIDE"` 및 `source = "GCS"`가 정확히 기재되어 온보드 FCP/VAS에서 조종석 MFD 대비 관제 권한으로 인식되는지 검증.
4. **타겟 기체 전환 시 모뎀 채널 스위칭**: 활성 기체를 $N_1$에서 $N_2$로 변경할 때 구버전 텔레메트리 채널(`Base_1 + 3`)을 닫고 신규 채널(`Base_2 + 3`)을 정확히 개방하여 혼선이 없는지 검증.
5. **레지스트리 파일 파손/부재 시 자가 복구**: `channel_registry.json`이 존재하지 않거나 손상되었을 때 빈 레지스트리로 안전 초기화되어 런타임 크래시가 발생하지 않는지 검증.

---

## File Structure & Responsibilities

```
docs/specs/0_infra/gcs/
└── GCS_PROGRAM_SPECIFICATION_AND_ICD.md # GCS 채널 관리자 및 지상 비행 지휘 콘솔 상세 규격서 (v1.0.0 Approved)

src/0_infra/gcs/
├── main.lua                             # 메인 엔트리 데몬 (20Hz 이벤트 루프, 5Hz UI 렌더링, parallel 이벤트 수신)
├── config/
│   ├── gcs_config.json                  # GCS 기본 설정 (bootstrapChannel, defaultBandwidth, activeCraftTarget)
│   └── channel_registry.json            # 채널 스티키 영속화 레지스트리 (domainId/UUID -> blockId, baseChannel)
└── modules/
    ├── channel_manager.lua              # 40채널 블록 할당, 스티키 매핑, 충돌 중재, JSON 영속화
    ├── network_manager.lua              # ICD v1.9.5 엔벨로프 통신 관리자 (CH 50000, Base+0/1/3 라우팅)
    ├── c2_commander.lua                 # 원격 비행 C2 명령 생성 (ARM, TAKEOFF, HOLD, RTH, LAND, E_STOP)
    ├── fleet_tracker.lua                # 등록 기체 인벤토리 및 실시간 텔레메트리 캐시
    └── ui_renderer.lua                  # 51x19 분할 TUI 화면 렌더러 (채널 모니터, 기체 HUD, 핫키 바)

tests/0_infra/gcs/
├── test_channel_manager.lua             # 채널 할당/재할당, 스티키 보존, 한계 초과 단위 테스트
├── test_network_manager.lua             # 패킷 인코딩/디코딩, 채널 개폐 및 주소 라우팅 단위 테스트
├── test_c2_commander.lua                # C2 오버라이드 및 E_STOP 직결 패킷 합성 단위 테스트
├── test_fleet_tracker.lua               # 다중 기체 텔레메트리 수집 및 활성 기체 스위칭 단위 테스트
├── test_ui_renderer.lua                 # 51x19 터미널 버퍼 텍스트/색상 렌더링 단위 테스트
├── test_main_loop.lua                   # 메인 루프 이벤트 디스패치 및 타이머 구동 테스트
└── test_gcs_integration.lua             # FCP 부트스트랩 및 C2 지휘 연동 종단간 폐루프 테스트
```

---

### Task 1: GCS 프로그램 사양서 작성 및 기본 설정 스캐폴딩

**Files:**
- Create: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Create: `src/0_infra/gcs/config/gcs_config.json`
- Create: `src/0_infra/gcs/config/channel_registry.json`
- Modify: `tools/verify_spec_status.py:27-34`
- Modify: `TASK.md:25-33`
- Test: `tests/0_infra/gcs/test_channel_manager.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_channel_manager.lua`에 설정 파일 로드 및 기본값 검증 테스트 작성 (Fail 예상).
- [ ] Step 2: 단위 테스트 실행하여 모듈/설정 부재로 실패 확인:
  ```powershell
  python tools/run_unit_tests.py --target 0_infra/gcs
  ```
- [ ] Step 3: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md` 사양서 작성 (Status: `Approved`, Version: `v1.0.0`, Date: `2026-11-08`).
  - 시스템 개요, CH 50000 부트스트랩 프로토콜, 원격 C2 오버라이드 인터페이스, 51x19 TUI 레이아웃 명세.
- [ ] Step 4: `src/0_infra/gcs/config/gcs_config.json` 및 `channel_registry.json` 생성.
- [ ] Step 5: `tools/verify_spec_status.py`의 `TARGET_APPROVED`에 신규 사양서 등록.
- [ ] Step 6: `python tools/verify_all_specs.py` 및 `python tools/verify_spec_status.py` 통과 확인.
- [ ] Step 7: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "docs(gcs): create GCS specification v1.0.0 Approved and config scaffolding"
  ```

---

### Task 2: 40채널 블록 할당 및 스티키 영속화 관리자 (`channel_manager.lua`)

**Files:**
- Create: `src/0_infra/gcs/modules/channel_manager.lua`
- Test: `tests/0_infra/gcs/test_channel_manager.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_channel_manager.lua`에 블록 할당, 스티키 보존, 해제, 범위 초과(`DENIED`), JSON 저장/불러오기 테스트 추가.
- [ ] Step 2: 단위 테스트 실행하여 실패 확인.
- [ ] Step 3: `channel_manager.lua` 구현:
  - `compute_base(n)`: $Base = 10000 + (n - 1) \times 40$ 산출.
  - `allocate_block(state, domain_id, hardware_uuid, requested_bw)`:
    - 기존 매핑 존재 시 동일 `blockId`, `baseChannel` 반환.
    - 미등록 기체 시 $1 \sim 1000$ 중 가장 낮은 미점유 $N$ 배정.
    - 블록 초과 시 `status = "DENIED"`, `reason = "EXHAUSTED"` 반환.
  - `release_block(state, domain_id)`: 배정 해제.
  - `load_registry(path)` / `save_registry(path, state)`: JSON 영속화.
- [ ] Step 4: 단위 테스트 실행하여 통과 확인:
  ```powershell
  python tools/run_unit_tests.py --target 0_infra/gcs
  ```
- [ ] Step 5: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement 40-channel block sticky allocator and registry manager"
  ```

---

### Task 3: 무선 모뎀 통신 및 채널 라우터 (`network_manager.lua`)

**Files:**
- Create: `src/0_infra/gcs/modules/network_manager.lua`
- Test: `tests/0_infra/gcs/test_network_manager.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_network_manager.lua`에 `CH 50000` 개폐, `MSG_BLOCK_REQUEST` 수신 파싱, `MSG_BLOCK_ASSIGN` 송신, 타겟 기체 `Base+0/1/3` 동적 바인딩 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 실패 확인.
- [ ] Step 3: `network_manager.lua` 구현:
  - UAFS Envelope v1.9.5 인코딩/디코딩 (`ver`, `domainId`, `seq`, `type`, `time`, `payload`).
  - `open_bootstrap_channel(ctx)`: CH 50000 바인딩.
  - `set_active_craft(ctx, base_channel)`: 이전 `Base_old+3` 닫고 신규 `Base_new+3` 열기.
  - `send_block_assign(ctx, reply_ch, payload)`: CH 50000 회신.
  - `send_c2_command(ctx, target_base, cmd_payload)`: `target_base + 0` 송출.
  - `send_emergency_override(ctx, target_base, override_payload)`: `target_base + 1` 송출.
- [ ] Step 4: 단위 테스트 실행하여 통과 확인.
- [ ] Step 5: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement network manager for CH 50000 and target craft routing"
  ```

---

### Task 4: 원격 비행 C2 명령 생성기 (`c2_commander.lua`)

**Files:**
- Create: `src/0_infra/gcs/modules/c2_commander.lua`
- Test: `tests/0_infra/gcs/test_c2_commander.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_c2_commander.lua`에 C2 지령(`ARM`, `DISARM`, `TAKEOFF`, `HOLD`, `RTH`, `LAND`, `WAYPOINT`) 패킷 생성 및 `E_STOP` 직결 패킷 생성 검증 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 실패 확인.
- [ ] Step 3: `c2_commander.lua` 구현:
  - `create_operator_cmd(cmd_type, target_craft, params)`:
    - `authority = "GCS_OVERRIDE"` 부여.
    - `command = cmd_type` 및 파라미터 매핑.
  - `create_emergency_estop(target_craft, reason)`:
    - `action = "E_STOP"`, `source = "GCS"`, `reason = reason` 매핑.
- [ ] Step 4: 단위 테스트 실행하여 통과 확인.
- [ ] Step 5: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement C2 command synthesizer and emergency cutoff generator"
  ```

---

### Task 5: 다중 기체 텔레메트리 캐시 및 활성 기체 추적기 (`fleet_tracker.lua`)

**Files:**
- Create: `src/0_infra/gcs/modules/fleet_tracker.lua`
- Test: `tests/0_infra/gcs/test_fleet_tracker.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_fleet_tracker.lua`에 기체 등록/텔레메트리 갱신, 통신 두절(타임아웃) 판정, 활성 타겟 순환 선택(`select_next_craft`) 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 실패 확인.
- [ ] Step 3: `fleet_tracker.lua` 구현:
  - `update_telemetry(state, domain_id, mfd_state_payload, now_ms)`: 자세, 동역학, 연료, FSM 상태 캐싱.
  - `get_active_telemetry(state)`: 현재 선택된 기체의 텔레메트리 반환.
  - `select_craft(state, domain_id)` / `select_next(state)`: 관제 타겟 절체.
  - `prune_stale(state, now_ms, timeout_ms)`: 두절 기체 플래그 관리.
- [ ] Step 4: 단위 테스트 실행하여 통과 확인.
- [ ] Step 5: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement fleet tracker and multi-craft telemetry cache"
  ```

---

### Task 6: 51x19 분할 TUI 콘솔 렌더러 (`ui_renderer.lua`)

**Files:**
- Create: `src/0_infra/gcs/modules/ui_renderer.lua`
- Test: `tests/0_infra/gcs/test_ui_renderer.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_ui_renderer.lua`에 51x19 화면 버퍼 크기, 상단 채널 관리자 바, 좌측 텔레메트리 HUD, 우측 기체 목록, 하단 핫키 바 포맷팅 검증 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 실패 확인.
- [ ] Step 3: `ui_renderer.lua` 구현:
  - `term.blit` 무깜빡임 가상 버퍼 렌더링.
  - Row 1: GCS 헤더 (청취 포트 50000, 총 등록 기체 수, 현재 시각).
  - Rows 2-16 (좌측 25열): 활성 기체 계기 HUD (자세 각도, 고도 Y, 속도, 연료 게이지, FSM 상태).
  - Rows 2-16 (우측 26열): 등록 기체 리스트 (도메인 ID, Base 채널, 상태).
  - Rows 17-19: 시스템 메시지 및 C2 핫키 가이드 (`[A]rm [T]akeoff [H]old [R]th [L]and [X]E-Stop [Tab]Craft`).
- [ ] Step 4: 단위 테스트 실행하여 버퍼 출력 검증 통과 확인.
- [ ] Step 5: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement 51x19 dual-pane TUI console renderer"
  ```

---

### Task 7: 메인 엔트리 루프 (`main.lua`) 및 통합 인스톨러(`manifest.lua`) 등록

**Files:**
- Create: `src/0_infra/gcs/main.lua`
- Modify: `src/0_development/installer/modules/manifest.lua`
- Test: `tests/0_infra/gcs/test_main_loop.lua`
- Test: `tests/0_development/installer/test_manifest_and_registry.lua`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_main_loop.lua`에 모뎀 수신 이벤트, 키 입력 이벤트, 5Hz UI 타이머 이벤트 디스패치 루프 테스트 작성.
- [ ] Step 2: `tests/0_development/installer/test_manifest_and_registry.lua`에 `gcs` 패키지 등록 검증 테스트 작성.
- [ ] Step 3: `src/0_infra/gcs/main.lua` 구현:
  - `parallel.waitForAny` 기반 논블로킹 이벤트 수신 및 UI 타이머 디스패치.
  - 키보드 입력 매핑 (`[A]`, `[T]`, `[H]`, `[R]`, `[L]`, `[X]`, `[TAB]`).
- [ ] Step 4: `manifest.lua`의 `PACKAGES`에 `gcs` 항목 추가 (`id = "gcs"`, 파일 목록, startup 스크립트).
- [ ] Step 5: 단위 테스트 실행하여 통과 확인:
  ```powershell
  python tools/run_unit_tests.py --target 0_infra/gcs
  python tools/run_unit_tests.py --target 0_development/installer
  ```
- [ ] Step 6: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(gcs): implement main daemon loop and register gcs package in installer manifest"
  ```

---

### Task 8: 종단간 E2E 시뮬레이션 통합 테스트, 사양서 `Implemented` 승격 및 마일스톤 완료

**Files:**
- Create: `tests/0_infra/gcs/test_gcs_integration.lua`
- Modify: `docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md:6-12`
- Modify: `tools/verify_spec_status.py:16-34`
- Modify: `TASK.md`
- Modify: `GEMINI.md`

**Steps:**
- [ ] Step 1: `tests/0_infra/gcs/test_gcs_integration.lua` 작성:
  - FCP 시뮬레이터에서 CH 50000으로 `MSG_BLOCK_REQUEST` 발송 $\rightarrow$ GCS가 `MSG_BLOCK_ASSIGN` 회신 $\rightarrow$ FCP가 Base+3 텔레메트리 송출 $\rightarrow$ GCS가 Base+0으로 C2 오버라이드 및 Base+1로 E_STOP 송출 검증.
- [ ] Step 2: 전체 12개 타겟 단위 테스트 러너 및 정적 분석 실행:
  ```powershell
  python tools/run_unit_tests.py --require-tests --clean-orphans
  python -m unittest discover -s tests/harness -p "test_*.py"
  python tools/validate_lua_syntax.py
  python tools/verify_all_specs.py
  ```
- [ ] Step 3: `GCS_PROGRAM_SPECIFICATION_AND_ICD.md` 메타데이터 표 상태를 `Implemented`로 승격.
- [ ] Step 4: `tools/verify_spec_status.py`에서 GCS 사양서를 `TARGET_APPROVED`에서 `TARGET_IMPLEMENTED`로 이동 및 검증 실행:
  ```powershell
  python tools/verify_spec_status.py
  ```
- [ ] Step 5: `TASK.md`의 `TASK-107`을 완료(`[x]`) 처리하고 완료 이력으로 이동.
- [ ] Step 6: `GEMINI.md` 스냅샷 갱신 (80줄 상한 엄수).
- [ ] Step 7: Git 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "chore(gcs): complete TASK-107 GCS implementation and promote spec to Implemented"
  ```
