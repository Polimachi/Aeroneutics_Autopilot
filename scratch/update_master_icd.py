import os, sys

path = 'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update Revision History right after lines 6
rev_history = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.20.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 ($Base = 10000 + (N-1)\\times 40$, $N=1\\sim 1000$), 4대 Zone(Zone 1: 코어, Zone 2: 구동계, Zone 3: 탑재체, Zone 4: 편대/확장) 전면 재편, 구동계 버스 Zone 2 이관(`Base+10`: TCA, `Base+11`: ASA, `Base+12~19`: 구동계 예비), 구버전 20채널 및 `Base+6`, `Base+7`에 `[DEPRECATED]` 배지 부여, 하위 사양서 5종 `approved/` 승격 전이 상대 링크 동기화 | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''

target = '> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  '
if target in content:
    content = content.replace(target, target + '\n' + rev_history)
else:
    target2 = '> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics'
    content = content.replace(target2, target2 + '\n' + rev_history)

# 2. Update relative links: implemented -> approved
content = content.replace('../specs/implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', '../specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md', '../specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md')
content = content.replace('../specs/implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md')

# 3. Update Mermaid Diagram in Section 2
content = content.replace(
    'subgraph AIRCRAFT_BLOCK["비행체 20채널 전용 블록 (Base: 10000 + (N-1)*20, N = 1 ~ 2000 연속 수납)"]',
    'subgraph AIRCRAFT_BLOCK["비행체 40채널 전용 블록 (Base: 10000 + (N-1)*40, BW=40, N = 1 ~ 1000 연속 수납)"]'
)
content = content.replace(
    'CORE <==>|"[I-3] MSG_THRUST_CMD (20Hz) / MSG_ACTUATOR_STATUS (이벤트) (Base+6)"| TCA',
    'CORE <==>|"[I-3] MSG_THRUST_CMD (20Hz) / MSG_ACTUATOR_STATUS (이벤트) (Base+10, 구 Base+6 [DEPRECATED])"| TCA'
)
content = content.replace(
    'CORE <==>|"[I-10] MSG_SURFACE_CMD (20Hz) / MSG_SURFACE_STATUS (이벤트) (Base+7)"| ASA',
    'CORE <==>|"[I-10] MSG_SURFACE_CMD (20Hz) / MSG_SURFACE_STATUS (이벤트) (Base+11, 구 Base+7 [DEPRECATED])"| ASA'
)
content = content.replace(
    'CORE ==>|"[I-4] MSG_CALIB_BAY_BIND (Base+6/Base+7, 베이 동적 바인딩)"| TCA',
    'CORE ==>|"[I-4] MSG_CALIB_BAY_BIND (Base+10/Base+11, 베이 동적 바인딩)"| TCA'
)
content = content.replace(
    'CORE ==>|"[I-4] MSG_CALIB_BAY_BIND (Base+6/Base+7, 베이 동적 바인딩)"| ASA',
    'CORE ==>|"[I-4] MSG_CALIB_BAY_BIND (Base+10/Base+11, 베이 동적 바인딩)"| ASA'
)

# 4. Interface I-3
content = content.replace(
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 6`)',
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 10`, 구버전 `Base + 6` [DEPRECATED])'
)
content = content.replace(
    '채널 `Base + 6` 전용 액추에이터 버스를 사용하여',
    '채널 `Base + 10` (구 `Base + 6` [DEPRECATED]) 전용 액추에이터 버스를 사용하여'
)
content = content.replace(
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 6`, 지상 교정 시 $Base_{\\text{hangar}} + 3$, 구버전 `1001` [DEPRECATED])',
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 10`, 지상 교정 시 $Base_{\\text{hangar}} + 3$, 구버전 `Base + 6` [DEPRECATED], 구버전 `1001` [DEPRECATED])'
)

# 5. Interface I-4
content = content.replace(
    '기체 내부 `Base + 4` 채널은 `CH_RESERVED_04`로 전환되어',
    '기체 내부 `Base + 4` 채널은 `CH_NAV_SENSOR`(온보드 항법 센서 버스)로 재편되었으며(구 교정채널 [DEPRECATED]),'
)
content = content.replace(
    'VAS (Node 01) $\\rightarrow$ TCA & ASA (Base+6 / Base+7, 베이 채널 개방 명령)',
    'VAS (Node 01) $\\rightarrow$ TCA & ASA (Base+10 / Base+11, 베이 채널 개방 명령, 구 Base+6/7 [DEPRECATED])'
)
content = content.replace(
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 6`) 및 `CH_SURFACE_ACTUATION` (`Base + 7`)',
    '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 10`) 및 `CH_SURFACE_ACTUATION` (`Base + 11`) (구 `Base+6`, `Base+7` [DEPRECATED])'
)

# 6. Interface I-7
content = content.replace(
    'replyChannel = 10045,              -- 비행체 01 전용 Base+5 채널',
    'replyChannel = 10005,              -- 비행체 01 전용 Base+5 채널 (구 10045 [DEPRECATED])'
)

# 7. Interface I-8
content = content.replace(
    'baseChannel = 10040,                     -- Base = 10000 + (3 - 1)*20',
    'baseChannel = 10080,                     -- Base = 10000 + (3 - 1)*40 (구버전 10040 [DEPRECATED])'
)

# 8. Interface I-9
content = content.replace(
    '| `payload.candidateBase` | uint16 | $10000 \\sim 49980$ | 필수 | 선점 시도할 후보 기체 베이스 채널 ($N = 1 \\sim 2000$) |',
    '| `payload.candidateBase` | uint16 | $10000 \\sim 49960$ | 필수 | 선점 시도할 후보 기체 베이스 채널 ($N = 1 \\sim 1000$) |'
)
content = content.replace(
    '| `payload.bandwidth` | uint8 | 20 | 필수 | 점유 요구 대역폭 (기본 20채널) |',
    '| `payload.bandwidth` | uint8 | 40 | 필수 | 점유 요구 대역폭 (기본 40채널, 구버전 20채널 [DEPRECATED]) |'
)
content = content.replace(
    '| `payload.occupiedBase` | uint16 | $10000 \\sim 49980$ | 필수 | 이미 점유 중인 기체 베이스 채널 |',
    '| `payload.occupiedBase` | uint16 | $10000 \\sim 49960$ | 필수 | 이미 점유 중인 기체 베이스 채널 |'
)
content = content.replace(
    '- **통신 채널**: 상위 계층 `Base + 0` / `Base + 1` $\\rightarrow$ 하위 계층 `Base + 6` / `Base + 7`',
    '- **통신 채널**: 상위 계층 `Base + 0` / `Base + 1` $\\rightarrow$ 하위 계층 `Base + 10` / `Base + 11` (구 `Base+6/7` [DEPRECATED])'
)
content = content.replace(
    'candidateBase = 10040,',
    'candidateBase = 10080,                   -- N=3 후보 Base (구 10040 [DEPRECATED])'
)
content = content.replace(
    'occupiedBase = 10040,',
    'occupiedBase = 10080,                    -- 선점 중인 Base (구 10040 [DEPRECATED])'
)
content = content.replace(
    'oldBase = 10040,\n        newBase = 10060,',
    'oldBase = 10080,\n        newBase = 10120,                   -- 40채널 기준 재바인딩 (구 10040/10060 [DEPRECATED])'
)

# 9. Interface I-10
content = content.replace(
    '- **통신 채널**: `CH_SURFACE_ACTUATION` (`Base + 7`)',
    '- **통신 채널**: `CH_SURFACE_ACTUATION` (`Base + 11`, 구버전 `Base + 7` [DEPRECATED])'
)
content = content.replace(
    'WAP은 SAS 직결에서 **`VAS` 산하 3계층 분산 액추에이터 버스(`Base + 7`)로 완전 편입**되었습니다.',
    'WAP은 SAS 직결에서 **`VAS` 산하 3계층 분산 액추에이터 버스(`Base + 11`, 구 `Base+7` [DEPRECATED])로 완전 편입**되었습니다.'
)
content = content.replace(
    '채널 `Base + 7` 독립 버스를 사용하여 추진기 버스(`Base + 6`) 및 유도 명령 버스(`Base + 1`)와의',
    '채널 `Base + 11` 독립 버스를 사용하여 추진기 버스(`Base + 10`) 및 유도 명령 버스(`Base + 1`)와의'
)
content = content.replace(
    '- **통신 채널**: `CH_SURFACE_ACTUATION` (`Base + 7`, 지상 교정 시 $Base_{\\text{hangar}} + 3$)',
    '- **통신 채널**: `CH_SURFACE_ACTUATION` (`Base + 11`, 지상 교정 시 $Base_{\\text{hangar}} + 3$, 구버전 `Base + 7` [DEPRECATED])'
)

# 10. Watchdog table & summary
content = content.replace(
    '| **I-10: ASA 조종면 명령 / 헬스 (Base+7)** |',
    '| **I-10: ASA 조종면 명령 / 헬스 (Base+11)** |'
)
content = content.replace(
    '| **I-3: TCA 추력 명령 / 헬스 (Base+6)** |',
    '| **I-3: TCA 추력 명령 / 헬스 (Base+10)** |'
)
content = content.replace(
    'VAS 산하 3구역 노드(06-L/R/T), Base+7 전용 버스, 동적 탐색 및 활공 트림 확정',
    'VAS 산하 3구역 노드(06-L/R/T), Base+11 전용 버스(구 Base+7 [DEPRECATED]), 동적 탐색 및 활공 트림 확정'
)
content = content.replace(
    '- **채널 검증**: `Base+6` (`10026`, `CH_THRUST_ACTUATION`) 단일 버스 실시간 검증 완료',
    '- **채널 검증**: `Base+10` (구 `Base+6` [DEPRECATED], `CH_THRUST_ACTUATION`) 단일 버스 실시간 검증 완료'
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Updated Master ICD successfully!')
