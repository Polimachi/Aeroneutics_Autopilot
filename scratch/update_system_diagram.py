import os, sys

path = 'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update Revision History right after lines 6
rev_history = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v2.7.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 ($Base = 10000 + (N-1)\\times 40$, $N=1\\sim 1000$), 4대 Zone(Zone 1: 코어, Zone 2: 구동계, Zone 3: 탑재체, Zone 4: 편대/확장) 전면 재편, 구동계 버스 Zone 2 이관(`Base+10`: TCA, `Base+11`: ASA, `Base+12~19`: 구동계 예비), 구버전 20채널 및 `Base+6`, `Base+7`에 `[DEPRECATED]` 배지 부여, 하위 사양서 5종 `approved/` 승격 전이 상대 링크 동기화 | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''

target = '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  '
if target in content:
    content = content.replace(target, target + '\n' + rev_history)
else:
    target2 = '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics'
    content = content.replace(target2, target2 + '\n' + rev_history)

# Update doc version in header
content = content.replace('문서 버전**: v2.6.0', '문서 버전**: v2.7.0')

# 2. Update relative links: implemented -> approved
content = content.replace('../specs/implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', '../specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md', '../specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md')

# 3. Section 1 Overview
content = content.replace(
    '기체 블록을 `10000 ~ 49999` ($Base = 10000 + (N-1) \\times 20$)의 2,000대 완전 연속 수납 구조로 재편하여',
    '기체 블록을 `10000 ~ 49999` ($Base = 10000 + (N-1) \\times 40$, $BW=40$)의 1,000대 완전 연속 수납 구조로 재편하고(구 20채널 [DEPRECATED]),'
)

# 4. Section 2 Mermaid Diagram
content = content.replace(
    'subgraph DOMAIN_AIRCRAFT["[비행체 온보드] 전용 20채널 블록 (Base = 10000 + (N-1)*20, BW = 20)"]',
    'subgraph DOMAIN_AIRCRAFT["[비행체 온보드] 전용 40채널 블록 (Base = 10000 + (N-1)*40, BW = 40)"]'
)
content = content.replace(
    'VAS 산하 3구역 조종면/플랩 분산 구동 (Base+7)',
    'VAS 산하 3구역 조종면/플랩 분산 구동 (Base+11, 구 Base+7 [DEPRECATED])'
)
content = content.replace(
    'CORE <==>|"Base + 6 (20Hz 지령 / 이벤트 피드백)<br/>[I-3] 내루프 추력 및 상태 피드백 (폐루프 PASS)"| TCA',
    'CORE <==>|"Base + 10 (20Hz 지령 / 이벤트 피드백)<br/>[I-3] 내루프 추력 및 상태 피드백 (구 Base+6 [DEPRECATED])"| TCA'
)
content = content.replace(
    'CORE <==>|"Base + 7 (20Hz 지령 / 이벤트 피드백)<br/>[I-10] 공력 조종면 및 플랩 지령 (V² 스케줄링)"| ASA',
    'CORE <==>|"Base + 11 (20Hz 지령 / 이벤트 피드백)<br/>[I-10] 공력 조종면 및 플랩 지령 (구 Base+7 [DEPRECATED])"| ASA'
)
content = content.replace(
    'CORE ==>|"Base + 6 / Base + 7<br/>[I-4] 베이 동적 바인딩 (MSG_CALIB_BAY_BIND)"| TCA',
    'CORE ==>|"Base + 10 / Base + 11<br/>[I-4] 베이 동적 바인딩 (MSG_CALIB_BAY_BIND)"| TCA'
)
content = content.replace(
    'CORE ==>|"Base + 6 / Base + 7<br/>[I-4] 베이 동적 바인딩 (MSG_CALIB_BAY_BIND)"| ASA',
    'CORE ==>|"Base + 10 / Base + 11<br/>[I-4] 베이 동적 바인딩 (MSG_CALIB_BAY_BIND)"| ASA'
)
content = content.replace(
    'SAS ==>|"Base+0/1 -> Base+6/7<br/>[I-9] 계층형 채널 전파 (MSG_CHANNEL_REBIND)"| CORE',
    'SAS ==>|"Base+0/1 -> Base+10/11<br/>[I-9] 계층형 채널 전파 (MSG_CHANNEL_REBIND)"| CORE'
)
content = content.replace(
    'subgraph INNER_LOOP["온보드 실시간 3계층 폐루프 (Base + 1, Base + 2, Base + 6, Base + 7)"]',
    'subgraph INNER_LOOP["온보드 실시간 3계층 폐루프 (Base + 1, Base + 2, Base + 10, Base + 11)"]'
)
content = content.replace(
    'CORE_NODE ==>|"Base+6: MSG_THRUST_CMD (20Hz)"| TAP_NODE',
    'CORE_NODE ==>|"Base+10: MSG_THRUST_CMD (20Hz, 구 Base+6 [DEPRECATED])"| TAP_NODE'
)
content = content.replace(
    'TAP_NODE -.->|"Base+6: MSG_ACTUATOR_STATUS (이벤트)"| CORE_NODE',
    'TAP_NODE -.->|"Base+10: MSG_ACTUATOR_STATUS (이벤트)"| CORE_NODE'
)
content = content.replace(
    'CORE_NODE ==>|"Base+7: MSG_SURFACE_CMD (20Hz)"| WAP_NODE',
    'CORE_NODE ==>|"Base+11: MSG_SURFACE_CMD (20Hz, 구 Base+7 [DEPRECATED])"| WAP_NODE'
)
content = content.replace(
    'WAP_NODE -.->|"Base+7: MSG_SURFACE_STATUS (이벤트)"| CORE_NODE',
    'WAP_NODE -.->|"Base+11: MSG_SURFACE_STATUS (이벤트)"| CORE_NODE'
)

# 5. Section 3 Interface Table
content = content.replace(
    '| `Base + 6`<br>(`CH_THRUST_ACTUATION`) |',
    '| `Base + 10`<br>(`CH_THRUST_ACTUATION`, 구 `Base+6` `[DEPRECATED]`) |'
)
content = content.replace(
    '`Base + 6` /<br>$Base_{\\text{hangar}} + 3$',
    '`Base + 10` /<br>$Base_{\\text{hangar}} + 3$'
)
content = content.replace(
    '요청자 채널 (`Base+6` / $Base_{\\text{hangar}}+3$)',
    '요청자 채널 (`Base+10` / $Base_{\\text{hangar}}+3$)'
)
content = content.replace(
    '`Base + 6` / `Base + 7`',
    '`Base + 10` / `Base + 11` (구 `Base+6/7` `[DEPRECATED]`)'
)
content = content.replace(
    '`Base+0/1` $\\rightarrow$ `Base+6/7`',
    '`Base+0/1` $\\rightarrow$ `Base+10/11` (구 `Base+6/7` `[DEPRECATED]`)'
)
content = content.replace(
    '`bandwidth` (20)',
    '`bandwidth` (40, 구버전 20 `[DEPRECATED]`)'
)
content = content.replace(
    '| `Base + 7`<br>(`CH_SURFACE_ACTUATION`) |',
    '| `Base + 11`<br>(`CH_SURFACE_ACTUATION`, 구 `Base+7` `[DEPRECATED]`) |'
)
content = content.replace(
    '요청자 채널 (`Base+7` / $Base_{\\text{hangar}}+3$)',
    '요청자 채널 (`Base+11` / $Base_{\\text{hangar}}+3$)'
)

# Sequence diagram text
content = content.replace('MSG_THRUST_CMD (Base+6, 20Hz)', 'MSG_THRUST_CMD (Base+10, 20Hz)')
content = content.replace('MSG_SURFACE_CMD (Base+7, 20Hz)', 'MSG_SURFACE_CMD (Base+11, 20Hz)')
content = content.replace('MSG_SURFACE_STATUS (Base+7)', 'MSG_SURFACE_STATUS (Base+11)')
content = content.replace('MSG_ACTUATOR_STATUS (Base+6)', 'MSG_ACTUATOR_STATUS (Base+10)')
content = content.replace('MSG_CALIB_BAY_BIND (Base+6)', 'MSG_CALIB_BAY_BIND (Base+10)')
content = content.replace('MSG_CALIB_BAY_BIND (Base+7)', 'MSG_CALIB_BAY_BIND (Base+11)')

# 6. Section 5 Master Channel Matrix (5.1)
content = content.replace(
    '기체별 고유 채널 블록($N$, $Base = 10000 + (N - 1) \\times 20$, $BW=20$, $N=1\\sim 2000$) 배정',
    '기체별 고유 채널 블록($N$, $Base = 10000 + (N - 1) \\times 40$, $BW=40$, $N=1\\sim 1000$, 구 $BW=20$ [DEPRECATED]) 배정'
)
content = content.replace(
    '`Base + 6`, `Base + 7`, `Base + 2`, `Base + 3` (ACRO 시), `Base + 1`, $Base_{\\text{hangar}}+1$ (CALIB 시) | `Base + 1`, `Base + 6`, `Base + 7`, `Base + 0` (CALIB INIT 시)',
    '`Base + 10`, `Base + 11`, `Base + 2`, `Base + 3` (ACRO 시), `Base + 1`, $Base_{\\text{hangar}}+1$ (CALIB 시) | `Base + 1`, `Base + 10`, `Base + 11`, `Base + 0` (CALIB INIT 시)'
)
content = content.replace(
    '| **추력 어댑터 TCA 클러스터**| `tap_daemon.lua / main.lua` (Node 02-xx)<br/>[TCA_PROGRAM_SPECIFICATION.md](../specs/implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md) | 기체 온보드 | `Base + 6`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 6`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)',
    '| **추력 어댑터 TCA 클러스터**| `tap_daemon.lua / main.lua` (Node 02-xx)<br/>[TCA_PROGRAM_SPECIFICATION.md](../specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md) | 기체 온보드 | `Base + 10`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 10`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)'
)
content = content.replace(
    '| **공력 조종면 ASA 클러스터**| `wap_daemon.lua` (Node 06-xx)<br/>[ASA_PROGRAM_SPECIFICATION.md](../specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md) | 기체 온보드 | `Base + 7`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 7`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)',
    '| **공력 조종면 ASA 클러스터**| `wap_daemon.lua` (Node 06-xx)<br/>[ASA_PROGRAM_SPECIFICATION.md](../specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md) | 기체 온보드 | `Base + 11`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 11`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)'
)

# 7. Section 5.2 Spectrum Map
content = content.replace('C1["기체 #01 : 10000 ~ 10019 (BW=20)"]', 'C1["기체 #01 : 10000 ~ 10039 (BW=40)"]')
content = content.replace('C2["기체 #02 : 10020 ~ 10039 (BW=20)"]', 'C2["기체 #02 : 10040 ~ 10079 (BW=40)"]')
content = content.replace('C3["기체 #03 : 10040 ~ 10059 (BW=20)"]', 'C3["기체 #03 : 10080 ~ 10119 (BW=40)"]')
content = content.replace(
    'CN["기체 #N... : 10000+(N-1)*20 ~ +19<br/>(N = 1 ~ 2000, 4만개 채널 연속 수납)"]',
    'CN["기체 #N... : 10000+(N-1)*40 ~ +39<br/>(N = 1 ~ 1000, 4만개 채널 연속 수납, BW=40)"]'
)

# 8. Section 5.3 Master Subchannel Table Replacement
old_sub_section_header = '### 5.3 기체 전용 20채널 블록 내부 구조도 (Aircraft 20-Channel Block Sub-Allocation)'
new_sub_section = '''### 5.3 기체 전용 40채널 블록 내부 구조도 (Aircraft 40-Channel Block Sub-Allocation)

각 비행체에는 **폭 40채널($BW=40$)의 전용 독립 블록**이 배정되며($Base = 10000 + (N - 1) \\times 40$, $N=1\\sim 1000$), 내부 서브포트는 10채널 단위 4대 기능 영역(Zone 1~4)으로 다음과 같이 엄격히 구획됩니다 (구버전 $BW=20$ `[DEPRECATED]`).

| 포트 오프셋 | 채널 식별 상수 | 소속 영역 | 송신 주체 (Tx) | 수신 주체 (Rx) | 갱신 주기 | 용도 및 트래픽 특성 |
| :---: | :--- | :---: | :--- | :--- | :---: | :--- |
| **`Base + 0`** | `CH_OPERATOR_C2` | Zone 1 | MFD, GCS 콘솔, SAS(프로브) | SAS, VAS(교정) | 이벤트 구동 | **오퍼레이터 C2 단일 진입로**: 조종사/GCS 비행명령, 일반 모드, `RTH`, `HOVER_HOLD`, `EMERGENCY_LAND`, 기동 전 선점 프로브, 지상 교정 바인딩(`MSG_CALIBRATION_INIT`) |
| **`Base + 1`** | `CH_FLIGHT_GUIDANCE` | Zone 1 | SAS, MFD (급기동), GCS (하드킬), VAS | VAS, SAS | 20Hz / 이벤트 | **상위 외루프 유도 및 직결 선점 버스**: SAS 외루프 20Hz 지령(`MSG_ATTITUDE_CMD`), MFD 직결 급기동(`MFD_ACRO` 20Hz), MFD/GCS 하드 비상차단(`E_STOP`), Core 공중비상알림(`MSG_EMERGENCY_ALERT`) |
| **`Base + 2`** | `CH_TELEMETRY` | Zone 1 | VAS | SAS, GCS | 20Hz (50ms) | **비행 동역학 스트림**(`MSG_FLIGHT_TELEMETRY`): 자세, 각속도, 고도, 속도, 부하율, 능동소스(`activeSource`), 구동기 헬스(`actuatorHealth`) |
| **`Base + 3`** | `CH_MFD_STATE` | Zone 1 | SAS (평시), VAS (ACRO 시) | Cockpit MFD | 5Hz (평시) / 20Hz (ACRO) | **조종석 계기판 다운링크**: 평시 SAS 5Hz 통합본(항법+계측), MFD_ACRO 급기동 진입 시 VAS 20Hz 고속 초저지연 HUD 직접 송출 (Core 평시 침묵) |
| **`Base + 4`** | `CH_NAV_SENSOR` | Zone 1 | 센서 버스 / 짐벌 | VAS, SAS | 20Hz | **온보드 항법 센서 버스**: 짐벌/대기/관성 센서 전용 버스 (구버전 지상교정 채널 `[DEPRECATED]` 후 센서 버스로 재편) |
| **`Base + 5`** | `CH_FACILITY_P2P` / `CH_CLIENT_REPLY` | Zone 1 | GPS 서버, 시설물, ATC | SAS | 측위 시 / 도킹 시 | **1:1 회신 전용 포트**: GPS 측위 응답(`MSG_GPS_RESPONSE`), ATC 접근 허가, 시설물 ACK |
| **`Base + 6 ~ 9`** | `CH_RESERVED_CORE_06 ~ 09` | Zone 1 | 예비 | 예비 | 미배정 | **코어 제어망 확장 예비** (구버전 `Base+6` 추진기, `Base+7` 공력면 `[DEPRECATED]`) |
| **`Base + 10`** | `CH_THRUST_ACTUATION` | Zone 2 | VAS, TCA | TCA, VAS | 20Hz (50ms) | **추진기 전용 버스** (구버전 `Base+6` `[DEPRECATED]`에서 Zone 2로 이관): Core 추력지령(`MSG_THRUST_CMD`), TCA 상태 회신(`MSG_ACTUATOR_STATUS`), 베이 바인딩 전파(`MSG_CALIB_BAY_BIND`), 디스커버리 |
| **`Base + 11`** | `CH_SURFACE_ACTUATION`| Zone 2 | VAS, ASA | ASA, VAS | 20Hz (50ms) | **공력 조종면 전용 버스** (구버전 `Base+7` `[DEPRECATED]`에서 Zone 2로 이관): Core 공력지령(`MSG_SURFACE_CMD`, V² 스케줄링), ASA 상태/포화 회신(`MSG_SURFACE_STATUS`), 베이 바인딩 전파, 디스커버리 |
| **`Base + 12 ~ 19`** | `CH_RESERVED_ACT_12 ~ 19` | Zone 2 | 예비 | 예비 | 미배정 | **구동계 확장 예비 (총 8개 채널)**: 틸트, 착륙장치, 역추진 등 필요 시 확장 |
| **`Base + 20`** | `CH_PAYLOAD_BUS` | Zone 3 | 미션 컴퓨터 | 탑재체/화물 | 이벤트/주기 | **통합 탑재체 버스**: 화물 적재 센서, 엄빌리컬 충전/급유, 마그넷/릴리즈 클램프 제어 |
| **`Base + 21`** | `CH_WEAPON_BUS` | Zone 3 | 화력제어 / MFD | 터렛/무장 | 이벤트 | **통합 무장 버스**: CC:Radars 연동 화력제어, 자동 터렛 조준, 무장 트리거 |
| **`Base + 22 ~ 29`** | `CH_RESERVED_PAYLOAD_22 ~ 29` | Zone 3 | 예비 | 예비 | 미배정 | **탑재체 확장 예비 (총 8개 채널)** |
| **`Base + 30`** | `CH_FORMATION_LINK` | Zone 4 | SAS / 편대장기 | 편대원 기체 | 5~10Hz | **통합 편대 데이터링크**: 편대원 간 실시간 위치/속도 벡터 공유 및 충돌 회피 |
| **`Base + 31 ~ 39`** | `CH_RESERVED_EXP_31 ~ 39` | Zone 4 | 예비 | 예비 | 미배정 | **시스템 전술 확장 예비 (총 9개 채널)** |
'''

start_idx = content.find(old_sub_section_header)
if start_idx != -1:
    end_idx = content.find('## 6. 채널 중복', start_idx)
    if end_idx != -1:
        content = content[:start_idx] + new_sub_section + '\n\n---\n\n' + content[end_idx:]

# 9. Sections 6 & 7 updates
content = content.replace(
    'local reqBW = requestPacket.payload.requestedBandwidth or 20',
    'local reqBW = requestPacket.payload.requestedBandwidth or 40'
)
content = content.replace(
    '기체당 20채널의 대역폭 중 13개의 예비 채널(`Base+4`, `Base+8 ~ Base+19`)을 사전에 확보함으로써',
    '기체당 40채널의 대역폭 중 29개의 예비 채널(Zone 1~4 확장 예비)을 사전에 확보함으로써'
)
content = content.replace(
    '간의 `Base+6` 액추에이터 통신 버스 및 이벤트 피드백 루프가',
    '간의 `Base+10` (구 `Base+6` [DEPRECATED]) 액추에이터 통신 버스 및 이벤트 피드백 루프가'
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated System Diagram successfully!')
