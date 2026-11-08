# TASK-110: FCP VTOL 제어 고도화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VECTORED_VTOL 기종의 외루프 유도 제어기를 3축(Surge/Sway/Heave) 완전 PID + Anti-windup, TILT_ASSISTED 피치 슬루율 완화, 수평 고정 수직 이륙 및 2단계 감속 수직 착륙 시퀀스로 고도화하여 호버 정밀도와 천이 비행 안정성을 확보한다.

**Architecture:** `vectored_vtol_driver.lua` 내부에 지속적 드라이버 상태(`driver_state`)를 보존하여 오차 적분(Anti-windup 클램프 포함) 및 직전 틸트 피치각을 유지하고, FSM 상태에 따라 `CRUISE` 모드에서만 단일 15m/s 임계값 기반 TILT_ASSISTED 슬루율 틸트를 인가하며, `TAKEOFF` 및 `APPROACH_LAND`에서는 수평/수직 분리 2단계 시퀀스를 집행한다.

**Tech Stack:** CC:Tweaked Lua 5.2, CraftOS-PC Unit Test Framework, JSON Config Loader.

**Spec:** [FCP_PROGRAM_SPECIFICATION.md](../../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md)

## Global Constraints

- **Single Execution Path (Zero-Fallback)**: 폴백 키(`sas_*`, 구버전 변수명)를 일체 사용하지 않으며 `fcp_config.json`의 표준 스키마 단일 경로만 참조한다.
- **Overclaim Ban**: "완벽", "무결점", "100% 보장" 등의 과장 표현을 코드, 주석, 문서 어디에도 기재하지 않는다.
- **20Hz Real-Time Isolation**: 연산 루프는 50ms(20Hz) 내에 완료되어야 하며 무거운 블로킹 연산이나 터미널 출력을 포함하지 않는다.
- **Permanent Unified Path**: 사양서 경로는 `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`를 영구 유지한다.
- **Headless Principle**: FCP 가이던스는 터미널 렌더링에 의존하지 않고 헤드리스로 계산을 완결한다.

## Review Focus

1. **적분기 와인드업(Windup) 누적 및 발산**: 정상상태 오차가 클 때 적분기가 무한정 누적되어 오버슈트가 발생하는지 여부 → `maxI` 클램핑 검증.
2. **모드 천이 시 피치 급변(Step Jump)**: CRUISE 진입 및 15m/s 초과 시 틸트 각도가 순간적으로 $\pm 10^\circ$로 튀지 않고 슬루율에 따라 부드럽게 점진 전환되는지 검증.
3. **비(非) CRUISE 상태에서의 틸트 오작동**: 이착륙(TAKEOFF, APPROACH_LAND) 및 비상(EMERGENCY_LAND, FAILSAFE_HOLD) 모드에서 STRICT_LEVEL($0.0^\circ$)이 강제 고정되는지 검증.
4. **수직 이륙 시 조기 수평 이동 편류**: 안전 고도 도달 전 수평 추력이 발생하여 지상 구조물과 충돌하지 않고 수평 바이어스가 $0.0$으로 잠기는지 검증.
5. **호버 홀드/리셋 시 적분기 잔류**: 비행 상태 전환(HOLD, DISARM 등) 시 적분 누적치가 초기화되어 복귀 시 범프(Bump)가 없는지 검증.

---

### Task 1: FCP 사양서 개정 및 설정 파일(`fcp_config.json`) 스키마 확장

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:1-50`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:470-550`
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:1820-1865`
- Modify: `src/2_guidance/fcp/config/fcp_config.json:50-87`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Steps:**
- [ ] Step 1: `tests/2_guidance/fcp/test_fcp_core.lua`에 `fcp_config.json`의 신규 PID 및 시퀀스 필드 검증 테스트 추가 (Fail 예상).
- [ ] Step 2: 단위 테스트를 실행하여 신규 설정 키 부재로 실패함을 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 3: `fcp_config.json`의 `guidance.vectored_vtol` 블록에 신규 설정 필드 추가:
  - `surgeKi` (기본값 0.02), `surgeMaxI` (기본값 0.20)
  - `swayKi` (기본값 0.02), `swayMaxI` (기본값 0.20)
  - `heaveKi` (기본값 0.02), `heaveMaxI` (기본값 0.20)
  - `tiltSlewRateDegPerSec` (기본값 15.0)
  - `takeoffClearanceAltitudeM` (기본값 15.0)
  - `takeoffClimbRateMps` (기본값 2.5)
  - `approachDescentRateMps` (기본값 -1.5)
  - `touchdownDescentRateMps` (기본값 -0.5)
  - `landingAlignDistanceM` (기본값 0.5)
- [ ] Step 4: `FCP_PROGRAM_SPECIFICATION.md`의 메타데이터 표를 `Approved`, 버전 `v1.13.0`으로 개정하고 Revision History 추가 및 Section 5.6/11.2에 3축 PID/슬루율/이착륙 시퀀스 상세 명세 반영.
- [ ] Step 5: 단위 테스트 및 사양서 검증 스크립트 실행하여 통과 확인:
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  python tools/verify_all_specs.py
  ```
- [ ] Step 6: Git 변경사항 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "docs(fcp): revise specification to v1.13.0 Approved and add vectored vtol PID config"
  ```

---

### Task 2: `vectored_vtol_driver.lua` 3축 Surge/Sway/Heave PID 및 Anti-windup 구현

**Files:**
- Modify: `src/2_guidance/fcp/modules/vectored_vtol_driver.lua`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Steps:**
- [ ] Step 1: `tests/2_guidance/fcp/test_fcp_core.lua`에 `vectored_vtol_driver.compute` 호출 시 지속 오차에 대한 적분기 누적 및 `maxI` 클램핑, 적분 리셋 동작 검증 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 적분기 미구현으로 실패함을 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 3: `vectored_vtol_driver.lua`에 적분기 상태 초기화 및 관리 로직 구현:
  - `driver_state.surge_i`, `driver_state.sway_i`, `driver_state.heave_i` 관리.
  - $I = \text{clamp}(I + K_i \cdot e \cdot dt, -\text{maxI}, \text{maxI})$.
  - `vectored_vtol_driver.reset_integrals(driver_state)` 함수 제공.
  - Surge, Sway, Heave 제어 출력식에 $I$ 항 결합:
    - $\text{surge} = \text{clamp}(K_{p,s} \cdot e_s - K_{d,s} \cdot v_s + I_s, -1.0, 1.0)$
    - $\text{sway} = \text{clamp}(K_{p,w} \cdot e_w - K_{d,w} \cdot v_w + I_w, -1.0, 1.0)$
    - $\text{heave} = \text{clamp}(K_{p,h} \cdot e_h - K_{d,h} \cdot v_y + I_h, -1.0, 1.0)$
- [ ] Step 4: 단위 테스트 실행하여 PID 적분 연산 및 클램프 통과 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 5: Git 변경사항 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(fcp): implement 3-axis surge/sway/heave PID with anti-windup clamping in vectored vtol driver"
  ```

---

### Task 3: TILT_ASSISTED 피치 슬루율(Slew-rate) 완화 및 STRICT_LEVEL 인터록 구현

**Files:**
- Modify: `src/2_guidance/fcp/modules/vectored_vtol_driver.lua`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Steps:**
- [ ] Step 1: `tests/2_guidance/fcp/test_fcp_core.lua`에 속도 15m/s 초과 시 피치각이 1틱(50ms) 내에 최대 $\text{slewRate} \cdot dt$만큼만 완만히 변화하는지, 비(非) CRUISE 모드에서 $0.0^\circ$로 고정되는지 검증하는 테스트 추가.
- [ ] Step 2: 단위 테스트 실행하여 점진 슬루율 미적용으로 실패함을 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 3: `vectored_vtol_driver.compute_envelope_attitude` 개편:
  - 인자로 `dt`, `driver_state` 전달받아 `driver_state.current_pitch` 보존.
  - `fsm_state ~= "CRUISE"`인 경우 목표 피치 $0.0^\circ$ 강제.
  - `fsm_state == "CRUISE"`이고 모드가 `TILT_ASSISTED`인 경우:
    - 속도 $> 15.0\text{ m/s}$ 또는 $|s_{raw}| \ge 0.95$ 시 목표 피치 $P_{target} = \text{clamp}(-s_{raw} \cdot P_{max}, -P_{max}, P_{max})$.
    - 미충족 시 목표 피치 $P_{target} = 0.0^\circ$.
  - 피치 슬루율 적용:
    - $\Delta P_{max} = \text{tiltSlewRateDegPerSec} \cdot dt$
    - $P_{new} = \text{clamp}(P_{target}, P_{prev} - \Delta P_{max}, P_{prev} + \Delta P_{max})$
    - `driver_state.current_pitch = P_{new}` 갱신 및 반환.
- [ ] Step 4: 단위 테스트 실행하여 슬루율 및 STRICT_LEVEL 인터록 통과 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 5: Git 변경사항 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(fcp): add pitch slew-rate limiter and strict level interlock in vectored vtol driver"
  ```

---

### Task 4: 수평 고정 수직 이륙 및 2단계 감속 수직 착륙 시퀀스 구현

**Files:**
- Modify: `src/2_guidance/fcp/modules/vectored_vtol_driver.lua`
- Modify: `src/2_guidance/fcp/modules/guidance_controller.lua`
- Test: `tests/2_guidance/fcp/test_fcp_core.lua`

**Steps:**
- [ ] Step 1: `tests/2_guidance/fcp/test_fcp_core.lua`에 `TAKEOFF` 상태 시 수평 이동 차단(`surge=0, sway=0`) 및 목표 승강률 인가, `APPROACH_LAND` 상태 시 수평 정렬 전/후 강하율 분기 검증 테스트 작성.
- [ ] Step 2: 단위 테스트 실행하여 시퀀스 미적용으로 실패함을 확인.
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 3: `vectored_vtol_driver.lua`에 이착륙 모드별 전용 시퀀스 로직 반영:
  - `fsm_state == "TAKEOFF"`:
    - 이륙 시작 고도 $y_0$ 기록 또는 목표 고도 판정.
    - 현재 고도가 안전 이륙 고도 미달 시 `surge = 0.0, sway = 0.0` 강제, `targetClimbRate = takeoffClimbRateMps` ($+2.5\text{ m/s}$).
    - 피치/롤 $0.0^\circ$ 유지.
  - `fsm_state == "APPROACH_LAND"`:
    - 수평 거리 $d_{2D} = \sqrt{\Delta x^2 + \Delta z^2}$.
    - $d_{2D} > \text{landingAlignDistanceM}$ (0.5m): 수평 정렬 집중 (`surge`, `sway` PID 활성), 승강률 $\text{approachDescentRateMps}$ ($-1.5\text{ m/s}$).
    - $d_{2D} \le \text{landingAlignDistanceM}$ (정렬 완료): 승강률 $\text{touchdownDescentRateMps}$ ($-0.5\text{ m/s}$) 완만 터치다운 강하.
- [ ] Step 4: `guidance_controller.lua`에서 모드 전환 시(HOLD 진입/이탈, DISARM 전환) `vectored_vtol_driver.reset_integrals`를 트리거하도록 연동.
- [ ] Step 5: 단위 테스트 실행하여 통과 확인:
  ```powershell
  python tools/run_unit_tests.py --target 2_guidance/fcp
  ```
- [ ] Step 6: Git 변경사항 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "feat(fcp): enforce horizontal-locked takeoff and 2-stage staged descent landing"
  ```

---

### Task 5: 전체 회귀 검증, 사양서 `Implemented` 전이 및 마일스톤 동기화

**Files:**
- Modify: `docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md:1-35`
- Modify: `TASK.md:25-33`
- Modify: `GEMINI.md`

**Steps:**
- [ ] Step 1: 전체 단위 테스트 러너 및 구문 정적 검사 실행:
  ```powershell
  python tools/run_unit_tests.py --require-tests --clean-orphans
  python tools/validate_lua_syntax.py
  python tools/verify_all_specs.py
  python tools/verify_spec_status.py
  ```
  - 모든 11개 대상 단위 테스트 및 구문 무결성 통과 확인.
- [ ] Step 2: `FCP_PROGRAM_SPECIFICATION.md` 상단 메타데이터 표의 상태를 `Implemented`로 환원하고 `최종 수정일` 갱신.
- [ ] Step 3: `TASK.md`의 `TASK-110` 항목을 완료(`[x]`) 처리하고 완료 이력(`## 3. 완료된 작업 이력`)으로 이동.
- [ ] Step 4: `GEMINI.md`의 최근 마일스톤 및 활성 인계 항목 동기화 (80줄 상한 엄수).
- [ ] Step 5: Git 변경사항 커밋:
  ```powershell
  & "C:\Program Files\Git\cmd\git.exe" commit -am "chore(fcp): complete TASK-110 vtol guidance refinement and sync spec status to Implemented"
  ```
