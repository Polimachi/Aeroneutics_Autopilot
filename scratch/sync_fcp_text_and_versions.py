import re

# 1. docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md
p = 'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# Header & Metadata
c = c.replace('# SAS (자율 항법 및 외루프 임무 제어 컴퓨터) 상세 규격서\n> **SAS: Universal Autopilot & Mission Guidance Computer Program Specification**',
              '# FCP (비행 제어 프로그램) 상세 규격서\n> **FCP: Flight Control Program (Outer-Loop Mission Guidance Computer)**')
c = c.replace('| **문서 버전 (Version)** | `v1.10.0` |', '| **문서 버전 (Version)** | `v1.11.0` |')
c = c.replace('| **구현 코드 (Source)** | `src/2_guidance/sas/` |', '| **구현 코드 (Source)** | `src/2_guidance/fcp/` |')
c = c.replace('| **주관 도메인 (Domain)** | 자율 오토파일럿 및 미션 유도 컴퓨터 (SAS / Node 04) |',
              '| **주관 도메인 (Domain)** | 외루프 유도 및 자율 임무 컴퓨터 (FCP / Node 04) |')

# References
c = c.replace('(마스터 ICD v1.20.1)', '(마스터 ICD v1.21.0)')
c = c.replace('(전체 구조도 v2.7.0)', '(전체 구조도 v2.8.0)')
c = c.replace('(비행 제어 코어 v1.11.0)', '(비행 제어 코어 v1.13.0)')

# Revision History
rev_target = '| `v1.10.0` | 2026-11-07 |'
if '| `v1.11.0` | 2026-11-07 |' not in c:
    rev_row = '| `v1.11.0` | 2026-11-07 | 기존 SAS 명칭을 FCP(Flight Control Program)로 전면 개정, 디렉토리/파일명(`fcp/`) 및 런타임 식별자(`FCP`) 동기화, 구 SAS 명칭 [DEPRECATED] 이력 명시 | 시스템 명칭 통일 및 식별자 표준화 |\n'
    c = c.replace(rev_target, rev_row + rev_target)

# Section 1.1
c = c.replace('**SAS (Stability Augmentation System / Node 04)**',
              '**FCP (Flight Control Program / Node 04)** [구 SAS (Stability Augmentation System) [DEPRECATED]]')

# Deprecation note in section 1.1
dep_note = '''> [!NOTE]
> **명칭 개정 및 식별자 동기화 (Zero-Fallback 원칙)**
> 기존 'SAS(Stability Augmentation System)' 명칭 및 구 식별자(`"SAS"`, `"SAS-04"`, `"SAS-NODE-04-4402"`)는 본 v1.11.0 규격에서 공식 폐기([DEPRECATED])되었으며, 새로운 표준 식별자인 `"FCP"` 및 `"FCP-04"`로 전면 대체되었습니다. 런타임 환경에서는 이중 키 폴백을 허용하지 않으므로 수신단(VAS 등)과 송신단이 `"FCP"` 단일 키로 즉시 동기화됩니다.

'''
if '명칭 개정 및 식별자 동기화 (Zero-Fallback 원칙)' not in c:
    c = c.replace('> [!NOTE]\n> **구현 및 배포 현황 요약', dep_note + '> [!NOTE]\n> **구현 및 배포 현황 요약')

replacements_fcp = [
    ('SAS 소프트웨어', 'FCP 소프트웨어'),
    ('SAS (Node 04)', 'FCP (Node 04)'),
    ('SAS(Node 04)', 'FCP(Node 04)'),
    ('SAS-04', 'FCP-04'),
    ('SAS-NODE-04-4402', 'FCP-NODE-04-4402'),
    ('SAS-NODE-04-UUID', 'FCP-NODE-04-UUID'),
    ('source = "SAS"', 'source = "FCP"'),
    ('activeSource = "SAS"', 'activeSource = "FCP"'),
    ('telemetry.activeSource == "SAS"', 'telemetry.activeSource == "FCP"'),
    ('activeSource == SAS', 'activeSource == FCP'),
    ('subgraph UAP_NODE["[SAS 자율 항법 컴퓨터 (Node 04)]"]', 'subgraph UAP_NODE["[FCP 비행 제어 컴퓨터 (Node 04)]"]'),
    ('subgraph UAP_PORTS["[SAS 하드웨어 포트 매핑 (Node 04)]"]', 'subgraph UAP_PORTS["[FCP 하드웨어 포트 매핑 (Node 04)]"]'),
    ('PC["SAS 컴퓨터 (Advanced Computer)"]', 'PC["FCP 컴퓨터 (Advanced Computer)"]'),
    ('SAS 5Hz', 'FCP 5Hz'),
    ('SAS 전담', 'FCP 전담'),
    ('SAS 유도', 'FCP 유도'),
    ('SAS 장애', 'FCP 장애'),
    ('SAS 비상', 'FCP 비상'),
    ('SAS 단독', 'FCP 단독'),
    ('SAS 자율', 'FCP 자율'),
    ('SAS 측', 'FCP 측'),
    ('SAS가', 'FCP가'),
    ('SAS는', 'FCP는'),
    ('SAS의', 'FCP의'),
    ('SAS를', 'FCP를'),
    ('SAS에', 'FCP에'),
    ('SAS로', 'FCP로'),
    ('SAS와', 'FCP와'),
    ('`SAS`', '`FCP`'),
    ('"SAS"', '"FCP"'),
    ('SAS/MFD', 'FCP/MFD'),
    ('MFD/SAS', 'MFD/FCP'),
    ('SAS(외루프)', 'FCP(외루프)'),
    ('SAS -', 'FCP -'),
    ('SAS (', 'FCP ('),
    ('SAS 및', 'FCP 및'),
    ('SAS 자체', 'FCP 자체'),
]

for t, r in replacements_fcp:
    c = c.replace(t, r)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('FCP spec updated.')

# 2. docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md
p = 'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace('| **문서 버전 (Version)** | `v1.20.1` |', '| **문서 버전 (Version)** | `v1.21.0` |')
rev_target = '| `v1.20.1` | 2026-11-07 |'
if '| `v1.21.0` | 2026-11-07 |' not in c:
    rev_row = '| `v1.21.0` | 2026-11-07 | 자율 유도 컴퓨터 Node 04 명칭 SAS → FCP(Flight Control Program) 전면 개정, 상대 링크 및 패킷 source/activeSource 식별자(\'FCP\') 동기화, 제어 권한 체계(\'E_STOP > MFD_ACRO > FCP\') 반영 | 시스템 명칭 표준화 및 패킷 스키마 일체화 |\n'
    c = c.replace(rev_target, rev_row + rev_target)

replacements_icd = [
    ('(SAS ↔ VAS', '(FCP ↔ VAS'),
    ('자율 항법 컴퓨터(SAS, Node 04)', '비행 제어 컴퓨터(FCP, Node 04)'),
    ('SAS (Node 04)', 'FCP (Node 04)'),
    ('SAS(Node 04)', 'FCP(Node 04)'),
    ('`E_STOP` > `MFD_ACRO` > `SAS`', '`E_STOP` > `MFD_ACRO` > `FCP`'),
    ('E_STOP > MFD_ACRO > SAS', 'E_STOP > MFD_ACRO > FCP'),
    ('SAS["자율 항법 SAS (Node 04)<br/>* L1/TECS 외루프 유도 & C2 명령 입력 (Base+0)<br/>* 공용 5Hz MFD 상태 다운링크 (Base+3)"]',
     'FCP["비행 제어 FCP (Node 04)<br/>* L1/TECS 외루프 유도 & C2 명령 입력 (Base+0)<br/>* 공용 5Hz MFD 상태 다운링크 (Base+3)"]'),
    ('SAS <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| SAS', 'FCP <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| GCS'),
    ('SAS <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| GCS', 'FCP <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| GCS'),
    ('GCS <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| SAS', 'GCS <==>|"[I-8] MSG_BLOCK_* (CH 50000)"| FCP'),
    ('SAS -.->|"[I-7] MSG_GPS_REQUEST (CH 60001)"| GPS', 'FCP -.->|"[I-7] MSG_GPS_REQUEST (CH 60001)"| GPS'),
    ('GPS -.->|"[I-7] MSG_GPS_RESPONSE (Base+5 replyChannel)"| SAS', 'GPS -.->|"[I-7] MSG_GPS_RESPONSE (Base+5 replyChannel)"| FCP'),
    ('GAC -.->|"[I-5] MSG_FACILITY_BEACON (CH 50003, 1Hz 표준 브로드캐스트)"| SAS', 'GAC -.->|"[I-5] MSG_FACILITY_BEACON (CH 50003, 1Hz 표준 브로드캐스트)"| FCP'),
    ('SAS <==>|"[I-5] MSG_ATC_COMM (CH 50001 진입/이탈 교신)"| ATC', 'FCP <==>|"[I-5] MSG_ATC_COMM (CH 50001 진입/이탈 교신)"| ATC'),
    ('SAS <==>|"[I-5] MSG_GAC_COMM (CH Base_sec+0 구역 교신)"| GAC', 'FCP <==>|"[I-5] MSG_GAC_COMM (CH Base_sec+0 구역 교신)"| GAC'),
    ('FAC <==>|"[I-5] STATIC(1Hz)/DYNAMIC(20Hz) 유도 (CH Base_sec+10+Idx)"| SAS', 'FAC <==>|"[I-5] STATIC(1Hz)/DYNAMIC(20Hz) 유도 (CH Base_sec+10+Idx)"| FCP'),
    ('MFD -->|"[I-6] MSG_OPERATOR_CMD (Base+0, 일반/RTH/HOLD/LAND)"| SAS', 'MFD -->|"[I-6] MSG_OPERATOR_CMD (Base+0, 일반/RTH/HOLD/LAND)"| FCP'),
    ('GCS -->|"[I-6] MSG_OPERATOR_CMD (Base+0, 임무/오프셋/RTH/LAND)"| SAS', 'GCS -->|"[I-6] MSG_OPERATOR_CMD (Base+0, 임무/오프셋/RTH/LAND)"| FCP'),
    ('SAS -->|"[I-6] MSG_MFD_STATE (Base+3, 공용 5Hz 상태 다운링크)"| MFD', 'FCP -->|"[I-6] MSG_MFD_STATE (Base+3, 공용 5Hz 상태 다운링크)"| MFD'),
    ('CORE -->|"[I-1] MSG_FLIGHT_TELEMETRY (Base+2, 20Hz 텔레메트리/상태)"| SAS', 'CORE -->|"[I-1] MSG_FLIGHT_TELEMETRY (Base+2, 20Hz 텔레메트리/상태)"| FCP'),
    ('SAS -->|"[I-2] MSG_ATTITUDE_CMD (Base+1, 20Hz 외루프 유도)"| CORE', 'FCP -->|"[I-2] MSG_ATTITUDE_CMD (Base+1, 20Hz 외루프 유도)"| CORE'),
    ('`VAS` $\\rightarrow$ `SAS`', '`VAS` $\\rightarrow$ `FCP`'),
    ('`SAS / MFD` $\\rightarrow$ `VAS`', '`FCP / MFD` $\\rightarrow$ `VAS`'),
    ('`"SAS"`', '`"FCP"`'),
    ('source = "SAS"', 'source = "FCP"'),
    ('activeSource = "SAS"', 'activeSource = "FCP"'),
    ('SAS-NODE-04-4402', 'FCP-NODE-04-4402'),
    ('`SAS`', '`FCP`'),
    ('SAS 외루프', 'FCP 외루프'),
    ('SAS 5Hz', 'FCP 5Hz'),
    ('SAS 단독', 'FCP 단독'),
    ('SAS 장애', 'FCP 장애'),
    ('SAS 비상', 'FCP 비상'),
    ('SAS 전담', 'FCP 전담'),
    ('SAS 유도', 'FCP 유도'),
    ('SAS와', 'FCP와'),
    ('SAS가', 'FCP가'),
    ('SAS는', 'FCP는'),
    ('SAS의', 'FCP의'),
    ('SAS를', 'FCP를'),
    ('SAS에', 'FCP에'),
    ('SAS로', 'FCP로'),
    ('(v1.9.0)', '(v1.11.0)'),
    ('(v1.11.0)', '(v1.13.0)'),
]

for t, r in replacements_icd:
    c = c.replace(t, r)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('ICD updated.')

# 3. docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md
p = 'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace('| **문서 버전 (Version)** | `v2.7.0` |', '| **문서 버전 (Version)** | `v2.8.0` |')
rev_target = '| `v2.7.0` | 2026-11-07 |'
if '| `v2.8.0` | 2026-11-07 |' not in c:
    rev_row = '| `v2.8.0` | 2026-11-07 | 자율 유도 컴퓨터 Node 04 명칭 SAS → FCP(Flight Control Program) 전면 개정, 상대 링크 및 9개 다이어그램 전수 표기 동기화 | 시스템 명칭 표준화 |\n'
    c = c.replace(rev_target, rev_row + rev_target)

replacements_diag = [
    ('(SAS ↔ VAS', '(FCP ↔ VAS'),
    ('(SAS 자율 항법 규격서 v1.9.0)', '(FCP 자율 비행 제어 규격서 v1.11.0)'),
    ('자율 항법 컴퓨터 SAS', '비행 제어 컴퓨터 FCP'),
    ('SAS["자율 항법 컴퓨터 SAS<br/>(startup.lua / Node 04 / 검증 v1.2.2 PASS 31개 슬라이스)<br/>* FSM / 항로 계획 / 외루프 유도 & C2 명령 입력(Base+0)<br/>* 공용 5Hz MFD 상태 다운링크 (Base+3)"]',
     'FCP["비행 제어 컴퓨터 FCP<br/>(startup.lua / Node 04 / 검증 v1.2.2 PASS 31개 슬라이스)<br/>* FSM / 항로 계획 / 외루프 유도 & C2 명령 입력(Base+0)<br/>* 공용 5Hz MFD 상태 다운링크 (Base+3)"]'),
    ('SAS <==>|"CH 50000', 'FCP <==>|"CH 50000'),
    ('-->|"Base + 0\n[I-6] 조종사 C2 명령/임무/RTH/HOLD/LAND"| SAS', '-->|"Base + 0\n[I-6] 조종사 C2 명령/임무/RTH/HOLD/LAND"| FCP'),
    ('SAS -.->|"CH 60001', 'FCP -.->|"CH 60001'),
    ('replyChannel)\n[I-7] 정밀 2D 좌표 응답"| SAS', 'replyChannel)\n[I-7] 정밀 2D 좌표 응답"| FCP'),
    ('표준 브로드캐스트)\n[I-5] 권역 기본 인프라 정보"| SAS', '표준 브로드캐스트)\n[I-5] 권역 기본 인프라 정보"| FCP'),
    ('진입 유도 개시"| SAS', '진입 유도 개시"| FCP'),
    ('SAS <==>|"CH 50001', 'FCP <==>|"CH 50001'),
    ('SAS <==>|"Base_sec + 0', 'FCP <==>|"Base_sec + 0'),
    ('정밀 ILS 유도 벡터"| SAS', '정밀 ILS 유도 벡터"| FCP'),
    ('패드 접근 유도"| SAS', '패드 접근 유도"| FCP'),
    ('도킹 유도 벡터"| SAS', '도킹 유도 벡터"| FCP'),
    ('SAS <==>|"Base + 5', 'FCP <==>|"Base + 5'),
    ('진입/착륙/이탈 완료 통보"| FAC_PAD', '진입/착륙/이탈 완료 통보"| FAC_PAD'),
    ('활주로 점유 완료 통보"| FAC_RUNWAY', '활주로 점유 완료 통보"| FAC_RUNWAY'),
    ('거치/분리 완료 통보"| FAC_DOCK', '거치/분리 완료 통보"| FAC_DOCK'),
    ('RTH/HOLD/LAND"| SAS', 'RTH/HOLD/LAND"| FCP'),
    ('SAS -->|"Base + 3', 'FCP -->|"Base + 3'),
    ('CORE ==>|"Base + 2 (20Hz)\n[I-1] 자세/속도/위치 텔레메트리 & 센서 헬스"| SAS',
     'CORE ==>|"Base + 2 (20Hz)\n[I-1] 자세/속도/위치 텔레메트리 & 센서 헬스"| FCP'),
    ('SAS ==>|"Base + 1 (20Hz)\n[I-2] 외루프 유도 (MSG_ATTITUDE_CMD)"| CORE',
     'FCP ==>|"Base + 1 (20Hz)\n[I-2] 외루프 유도 (MSG_ATTITUDE_CMD)"| CORE'),
    ('CORE -.->|"Base + 1 (비상 셧다운 시)\n[I-2] 비상 경보 (MSG_EMERGENCY_ALERT)"| SAS',
     'CORE -.->|"Base + 1 (비상 셧다운 시)\n[I-2] 비상 경보 (MSG_EMERGENCY_ALERT)"| FCP'),
    ('SAS -.->|"Base + 0 (기동 전 자동 탐색)\n[I-9] 채널 충돌 프로브"| SAS',
     'FCP -.->|"Base + 0 (기동 전 자동 탐색)\n[I-9] 채널 충돌 프로브"| FCP'),
    ('SAS ==>|"Base+0/1 -> Base+10/11\n[I-9] 새 채널 바인딩 (MSG_CHANNEL_REBIND)"| CORE',
     'FCP ==>|"Base+0/1 -> Base+10/11\n[I-9] 새 채널 바인딩 (MSG_CHANNEL_REBIND)"| CORE'),
    ('UAP_NODE["SAS 자율 항법 (Node 04)', 'UAP_NODE["FCP 비행 제어 (Node 04)'),
    ('participant U as SAS (Node 04)', 'participant U as FCP (Node 04)'),
    ('participant U as SAS (Client Node 04)', 'participant U as FCP (Client Node 04)'),
    ('participant U as 자율 항법 SAS (Node 04)', 'participant U as 비행 제어 FCP (Node 04)'),
    ('자율 항법 컴퓨터 SAS', '비행 제어 컴퓨터 FCP'),
    ('`SAS`', '`FCP`'),
    ('`"SAS"`', '`"FCP"`'),
    ('"SAS"', '"FCP"'),
    ('SAS 5Hz', 'FCP 5Hz'),
    ('SAS 단독', 'FCP 단독'),
    ('SAS 장애', 'FCP 장애'),
    ('SAS 전담', 'FCP 전담'),
    ('SAS 유도', 'FCP 유도'),
    ('SAS FSM', 'FCP FSM'),
    ('SAS(외루프)', 'FCP(외루프)'),
    ('SAS(프로브)', 'FCP(프로브)'),
    ('SAS (정상)', 'FCP (정상)'),
    ('SAS /', 'FCP /'),
    ('SAS,', 'FCP,'),
    ('SAS와', 'FCP와'),
    ('SAS가', 'FCP가'),
    ('SAS는', 'FCP는'),
    ('SAS의', 'FCP의'),
    ('SAS를', 'FCP를'),
    ('SAS에', 'FCP에'),
    ('SAS로', 'FCP로'),
    ('uap_main.lua', 'node_fcp.lua'),
]

for t, r in replacements_diag:
    c = c.replace(t, r)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('Diagram doc updated.')

# 4. docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md
p = 'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace('| **문서 버전 (Version)** | `v1.12.0` |', '| **문서 버전 (Version)** | `v1.13.0` |')
rev_target = '| `v1.12.0` | 2026-11-07 |'
if '| `v1.13.0` | 2026-11-07 |' not in c:
    rev_row = '| `v1.13.0` | 2026-11-07 | 상위 자율 유도 컴퓨터 명칭 SAS → FCP(Flight Control Program) 개정에 따른 제어 권한 중재(\'E_STOP > MFD_ACRO > FCP\') 및 텔레메트리/상태머신 activeSource(\'FCP\') 동기화, 상대 링크 갱신 | FCP 명칭 전면 개정 동기화 |\n'
    c = c.replace(rev_target, rev_row + rev_target)

replacements_vas = [
    ('(SAS 자율 항법 규격서 v1.9.0)', '(FCP 자율 비행 제어 규격서 v1.11.0)'),
    ('(마스터 ICD v1.20.0)', '(마스터 ICD v1.21.0)'),
    ('(전체 구조도 v2.7.0)', '(전체 구조도 v2.8.0)'),
    ('`E_STOP` > `MFD_ACRO` > `SAS`', '`E_STOP` > `MFD_ACRO` > `FCP`'),
    ('E_STOP > MFD_ACRO > SAS', 'E_STOP > MFD_ACRO > FCP'),
    ('SAS["SAS (Node 04)<br/>자율 유도 & 외루프 C2"]', 'FCP["FCP (Node 04)<br/>비행 제어 & 외루프 C2"]'),
    ('SAS ==>|"Base+1 [CH_FLIGHT_GUIDANCE] (20Hz MSG_ATTITUDE_CMD)"| COMMS',
     'FCP ==>|"Base+1 [CH_FLIGHT_GUIDANCE] (20Hz MSG_ATTITUDE_CMD)"| COMMS'),
    ('TELEM ==>|"Base+2 [CH_TELEMETRY] (20Hz MSG_FLIGHT_TELEMETRY)"| SAS',
     'TELEM ==>|"Base+2 [CH_TELEMETRY] (20Hz MSG_FLIGHT_TELEMETRY)"| FCP'),
    ('activeSource = "SAS"', 'activeSource = "FCP"'),
    ('`activeSource` | string | 제어 권한 | 필수 | 현재 Base+1 제어권을 행사 중인 활성 권한자 (`"SAS"`, `"MFD_ACRO"`, `"EMERGENCY_DIRECT"`)',
     '`activeSource` | string | 제어 권한 | 필수 | 현재 Base+1 제어권을 행사 중인 활성 권한자 (`"FCP"`, `"MFD_ACRO"`, `"EMERGENCY_DIRECT"`)'),
    ('`source` | string | `"SAS"` \| `"MFD_DIRECT"`', '`source` | string | `"FCP"` \| `"MFD_DIRECT"`'),
    ('SAS 5Hz', 'FCP 5Hz'),
    ('SAS (Node 04)', 'FCP (Node 04)'),
    ('SAS(Node 04)', 'FCP(Node 04)'),
    ('SAS 유도', 'FCP 유도'),
    ('SAS 장애', 'FCP 장애'),
    ('SAS 비상', 'FCP 비상'),
    ('SAS 단독', 'FCP 단독'),
    ('SAS 전담', 'FCP 전담'),
    ('SAS와', 'FCP와'),
    ('SAS가', 'FCP가'),
    ('SAS는', 'FCP는'),
    ('SAS의', 'FCP의'),
    ('SAS를', 'FCP를'),
    ('SAS에', 'FCP에'),
    ('SAS로', 'FCP로'),
    ('`SAS`', '`FCP`'),
    ('"SAS"', '"FCP"'),
]

for t, r in replacements_vas:
    c = c.replace(t, r)

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)
print('VAS spec updated.')

# 5. Other specifications: replace SAS mentions
other_specs = [
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/README.md',
]

for op in other_specs:
    with open(op, 'r', encoding='utf-8') as f:
        c = f.read()
    c = c.replace('SAS (Node 04)', 'FCP (Node 04)')
    c = c.replace('SAS(Node 04)', 'FCP(Node 04)')
    c = c.replace('`SAS`', '`FCP`')
    c = c.replace('"SAS"', '"FCP"')
    c = c.replace('SAS 자율 항법', 'FCP 비행 제어')
    c = c.replace('SAS 클라이언트', 'FCP 클라이언트')
    c = c.replace('SAS 비행체', 'FCP 비행체')
    c = c.replace('SAS 노드', 'FCP 노드')
    c = c.replace('SAS 유도', 'FCP 유도')
    c = c.replace('SAS ↔', 'FCP ↔')
    c = c.replace('↔ SAS', '↔ FCP')
    c = c.replace('SAS가', 'FCP가')
    c = c.replace('SAS는', 'FCP는')
    c = c.replace('SAS의', 'FCP의')
    c = c.replace('SAS를', 'FCP를')
    c = c.replace('SAS에', 'FCP에')
    c = c.replace('SAS로', 'FCP로')
    c = c.replace('SAS와', 'FCP와')
    c = c.replace('2_guidance/: 자율 항법 및 오토파일럿 사양서 (sas 등)', '2_guidance/: 비행 제어 및 외루프 유도 사양서 (fcp 등)')
    with open(op, 'w', encoding='utf-8') as f:
        f.write(c)
    print(f'Updated {op}')

print('All specification updates complete.')
