# Alignment — 격납고 동역학 시스템 식별 및 프로파일 동기화 플레이북

> **대상 코드베이스**: `src/0_development/alignment/` (`main.lua`)  
> **관련 사양서**: [ALIGNMENT_PROGRAM_SPECIFICATION.md](../../docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md)

---

## 1. 서브시스템 개요 및 역할 (Overview & Role)

`Alignment`는 격납고 테스트 베드에서 기체의 물리적 추진기/공력 조종면 구성을 탐색하고, 단계별 펄스 인가와 최소자승(OLS) 회귀를 통해 기체 동역학 프로파일과 토폴로지 매니페스트(`peripheralManifest`)를 산출해 온보드 `VAS`로 동기화하는 지상 교정 프로그램입니다.

- **구동계 자동 탐색**: 격납고 베이 채널(`Base_hangar+3`)을 통해 `TCA` 및 `ASA` 클러스터(`MSG_ACTUATOR_DISCOVER_REQ/ACK`, `MSG_SURFACE_DISCOVER_REQ/ACK`)를 식별합니다.
- **6-DoF OLS 동역학 식별 및 제어성 판정**: 다중 스텝 펄스(`multi_pulse_sequencer`) 응답 적분 및 회귀 분석으로 `FULL_6DOF_PASS` 또는 `AERO_ASSISTED_PASS` 여부를 판정하고 의사역행렬(Pseudo-Inverse) 배분 계수를 생성합니다.
- **조립 토폴로지 해시 및 재조립 인터록 연동 (`TASK-136`)**: 교정 완료 시 기체 질량·주변장치 매니페스트 해시를 생성해 `MSG_PROFILE_SYNC`에 첨부하므로, 이후 비행 전 블록 변형/재조립 시 `VAS`가 이를 감지하여 재교정 인터록(`RECALIBRATION_REQUIRED`)을 작동시킬 수 있습니다.

---

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)

| 구분 | 품목 / 페리페럴 | 필수 여부 | 비고 |
| :--- | :--- | :---: | :--- |
| 컴퓨터 | Advanced Computer | 필수 | 51×19 컬러 TUI 또는 외부 모니터 HUD 출력 |
| 통신 | Wireless Modem 또는 Ender Modem | 필수 | 격납고 베이 채널(`101~200`) 및 기체 `Base+8` 교신용 |
| 외부 모니터 | Advanced Monitor (`3×2` 이상 권장) | 선택 | 해상도 `>= 70×30` 연결 시 대형 3D 인공수평선·OLS 그래프 HUD 표시 |

- 기체 측에는 교정 대상인 `VAS`, `TCA`(및 고정익/하이브리드 시 `ASA`)가 전원이 켜진 상태로 대기해야 하며, 기체가 격납고 내에서 안전하게 펄스 시험이 가능한 **조립 완료·지상 구속 또는 충분한 여유 공간** 상태여야 합니다.

---

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)

1. **격납고 테스트 베드 배치**:
   - 기체 주변 반경 내에 블록 충돌이 없도록 여유 공간(전후좌우 최소 5블록, 상공 충분한 공간)을 확보합니다.
   - 펄스 인가 중 기체가 과도하게 기울어지지 않도록 테스트 베드 또는 수평 바닥 위에 기체를 정지 배치합니다.
2. **Alignment 컴퓨터 배치**:
   - 격납고 벽면 또는 관제 데스크에 Advanced Computer를 설치하고 어느 한 면에 Wireless/Ender Modem을 부착합니다.
   - 대형 HUD를 보려면 컴퓨터 인접 면(또는 유선 모뎀 연결)에 `3×2` 크기 이상의 Advanced Monitor를 배치합니다.
3. **다중 베이(Bay) 운영 시 주의**:
   - 여러 격납고 베이를 동시에 운영할 때는 각 베이 컴퓨터의 `station.bayId`(`1 ~ 10`)와 `station.baseHangarChannel`이 서로 겹치지 않도록 다르게 지정합니다.

---

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)

`Alignment`는 격납고 전용 채널 대역(`101 ~ 200`)과 기체의 교정 개시 채널(`Base + 8`)을 사용합니다.

$$\text{Base}_{\text{hangar}} = 101 + (\text{BayID} - 1) \times 10 \quad (1 \le \text{BayID} \le 10)$$

| 채널 | 용도 | 송수신 방향 |
| :--- | :--- | :--- |
| `Base + 8` (기본 `10008`) | `MSG_CALIBRATION_INIT` 교정 세션 개시 알림 | `Alignment` → 기체 `VAS` |
| `Base_hangar + 0` (기본 `101`) | `calibrationCmd` — 교정 명령 및 `MSG_CALIBRATION_CLOSE` 송출 | `Alignment` ↔ `VAS` |
| `Base_hangar + 1` (기본 `102`) | `calibrationTelem` — 20Hz 텔레메트리 및 `MSG_PROFILE_SYNC` 수신 확인 | `VAS` → `Alignment` |
| `Base_hangar + 2` (기본 `103`) | `facilityInterlock` — 격납고 도어/테스트 베드 시설 인터록 | `Alignment` ↔ 시설 |
| `Base_hangar + 3` (기본 `104`) | `tapDirect` — `MSG_ACTUATOR_DISCOVER_*`, `MSG_SURFACE_DISCOVER_*`, `MSG_CALIB_PULSE` | `Alignment` ↔ `TCA`/`ASA` |

---

## 5. 소프트웨어 설치 방법 (Installation)

1. 컴퓨터에 통합 인스톨러를 배치하거나 원격 실행합니다([installer.md](installer.md) 참고):
   ```text
   wget run https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/installer.lua
   ```
2. TUI에서 `Development & Calibration` → `Alignment`를 선택해 설치하거나 CLI로 직접 설치합니다:
   ```text
   /installer.lua install alignment
   ```
3. 설치가 완료되면 `/main.lua`, `/modules/*.lua`, `/lib/avionics_sensors.lua` 및 부팅 훅 `/startup/00_alignment.lua`가 생성됩니다. 재부팅(`reboot`) 시 자동 시작됩니다.

---

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)

기본 설정 파일 경로는 `/config.json`이며, 파일이 없을 경우 `main.lua`의 기본값이 적용됩니다.

```json
{
  "station": {
    "stationId": "HANGAR_BAY_01",
    "bayId": 1,
    "baseHangarChannel": 101,
    "channels": {
      "calibrationCmd": 101,
      "calibrationTelem": 102,
      "facilityInterlock": 103,
      "tapDirect": 104
    }
  },
  "safety": {
    "tiltAbortDeg": 12.0,
    "tiltWarnDeg": 8.0,
    "watchdogTimeoutMs": 300,
    "maxDeadband": 6.0,
    "minR2Warning": 0.85
  }
}
```

| 키 | 기본값 | 설명 |
| :--- | :--- | :--- |
| `station.bayId` | `1` | 격납고 베이 번호(`1~10`), 베이 채널 자동 산출 기준 |
| `station.baseHangarChannel` | `101` | 베이 시작 채널 (`101 + (bayId - 1) * 10`) |
| `safety.tiltAbortDeg` | `12.0` | 교정 펄스 중 Pitch/Roll 절대값이 이 각도를 초과하면 즉시 교정 중단(ABORT) |
| `safety.tiltWarnDeg` | `8.0` | 기울기 주의 경고 임계 각도(도) |
| `safety.watchdogTimeoutMs` | `300` | 펄스/텔레메트리 워치독 타임아웃(ms) |
| `safety.maxDeadband` | `6.0` | 허용 최대 추력기 데드밴드 한계 |
| `safety.minR2Warning` | `0.85` | OLS 회귀 결정계수($R^2$) 경고 하한 |

- 교정 산출물은 로컬 `/profiles/<profileId>.json`으로 백업 저장되며, 승인 시 `MSG_PROFILE_SYNC` 패킷으로 `VAS`의 `/config/thrusters.json` 및 `/config/peripheral_manifest.json`에 반영됩니다.

---

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)

### TUI 단축키

| 키 | 동작 | 설명 |
| :---: | :--- | :--- |
| `Space` | `PAUSE` | 진행 중인 펄스 시퀀스를 일시정지 |
| `R` | `RETRY` | 현재 실패 또는 보류된 구동기 교정을 재시도 |
| `Y` | `USER_APPROVE` | 산출된 교정 프로파일을 승인하고 `VAS` 동기화 확정 |
| `Q` | `ABORT` | 교정 세션을 안전 중단하고 점유 중인 채널을 해제 |

### 자주 발생하는 문제 및 해결법

- **`Tilt Guard` 초과로 교정이 즉시 중단됨 (`tiltAbortDeg > 12.0°`)**
  - 기체 무게중심(CoM) 대비 추진기 배치가 크게 비대칭이거나 지면 고정 없이 높은 펄스가 인가된 상태입니다. 추진기 대칭 배치 또는 기체 지지 구조를 점검한 뒤 `R`로 재시도하세요.
- **구동기/조종면이 탐색되지 않음 (`ACTUATOR_DISCOVER` 미응답)**
  - 대상 기체 `TCA`/`ASA`의 `aircraftDomainId`와 `Alignment` 대상 도메인(`AIRCRAFT_01`) 일치 여부, 그리고 무선 모뎀 범위 및 베이 채널(`104`) 개방 여부를 확인하세요.
- **`R² < 0.85` 경고 출력**
  - 교정 중 외부 바람/충돌 또는 인접 블록 마찰로 외란이 유입되었거나 `velocity_sensor` 3축 배선이 누락된 상태입니다. 주변 간섭을 제거하고 [sensors.md](sensors.md) 기준으로 센서 연결을 확인하세요.
- **교정 후 비행 직전 `RECALIBRATION_REQUIRED`가 계속 해제되지 않음**
  - 프로파일 승인(`Y`) 시 `controllabilityStatus`가 `FULL_6DOF_PASS` 또는 `AERO_ASSISTED_PASS`여야 하며, 교정 세션 종료 시 `saveProfile = true`로 정상 커밋되어야 `VAS`의 재교정 래치가 해제됩니다.
