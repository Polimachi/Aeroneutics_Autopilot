import os, sys, re

def add_revision_history(content, history_table):
    if '### Revision History' in content:
        return content
    # Find the end of header block quote (after > **연관 문서**: or > **참조 문서**: or > **대상 환경**: ...)
    # Look for the first '---' after the title
    m = re.search(r'\n---\n', content)
    if m:
        pos = m.start()
        return content[:pos] + '\n' + history_table.strip() + '\n' + content[pos:]
    return content

# 1. VAS
vas_path = 'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'
with open(vas_path, 'r', encoding='utf-8') as f:
    c = f.read()

vas_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.12.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 구동계 버스 Zone 2 이관(`Base+10`: TCA, `Base+11`: ASA, `Base+12~19`: 구동계 예비), 구버전 `Base+6`, `Base+7`에 `[DEPRECATED]` 부여, `Base+0` C2 상시 개방 명세 확립, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, vas_rev)
c = c.replace('COM->>COM: 10. TAP으로 MSG_THRUST_CMD 브로드캐스트 (Base+6, 20Hz)', 'COM->>COM: 10. TAP으로 MSG_THRUST_CMD 브로드캐스트 (Base+10, 20Hz, 구 Base+6 [DEPRECATED])')
c = c.replace('COM->>COM: 11. WAP으로 MSG_AERO_CMD 브로드캐스트 (Base+7, 20Hz)', 'COM->>COM: 11. WAP으로 MSG_AERO_CMD 브로드캐스트 (Base+11, 20Hz, 구 Base+7 [DEPRECATED])')
c = c.replace('- **채널**: `CH_THRUST_ACTUATION` (`Base + 6`)', '- **채널**: `CH_THRUST_ACTUATION` (`Base + 10`, 구버전 `Base + 6` [DEPRECATED])')
c = c.replace('- **채널**: `CH_AERO_ACTUATION` (`Base + 7`)', '- **채널**: `CH_AERO_ACTUATION` (`Base + 11`, 구버전 `Base + 7` [DEPRECATED])')
c = c.replace('(MSG_CALIB_BAY_BIND, VAS -> TCA Base+6 & ASA Base+7)', '(MSG_CALIB_BAY_BIND, VAS -> TCA Base+10 & ASA Base+11, 구 Base+6/7 [DEPRECATED])')
c = c.replace('- **채널**: `CH_THRUST_ACTUATION` (`Base + 6`) 및 `CH_AERO_ACTUATION` (`Base + 7`)', '- **채널**: `CH_THRUST_ACTUATION` (`Base + 10`) 및 `CH_AERO_ACTUATION` (`Base + 11`) (구 `Base+6/7` [DEPRECATED])')
c = c.replace('(MSG_ACTUATOR_DISCOVER_REQ, Base+6)', '(MSG_ACTUATOR_DISCOVER_REQ, Base+10, 구 Base+6 [DEPRECATED])')
c = c.replace('(MSG_ACTUATOR_DISCOVER_ACK, Base+6)', '(MSG_ACTUATOR_DISCOVER_ACK, Base+10, 구 Base+6 [DEPRECATED])')
c = c.replace('Base+6 [CH_THRUST_ACTUATION]', 'Base+10 [CH_THRUST_ACTUATION]')
c = c.replace('Base+7 [CH_AERO_ACTUATION]', 'Base+11 [CH_AERO_ACTUATION]')

with open(vas_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('VAS synced!')

# 2. TCA
tca_path = 'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'
with open(tca_path, 'r', encoding='utf-8') as f:
    c = f.read()

tca_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.9.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 추진기 버스 Zone 2 이관(`Base+10`: `CH_THRUST_ACTUATION`, 구 `Base+6` [DEPRECATED]), `Base+4` 상시 청취 제거 확정, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, tca_rev)
c = c.replace('Core $\\rightarrow$ TCA, Base + 6)', 'Core $\\rightarrow$ TCA, Base + 10, 구 Base + 6 [DEPRECATED])')
c = c.replace('Core $\\rightarrow$ TCA, oldBase + 6)', 'Core $\\rightarrow$ TCA, oldBase + 10, 구 oldBase + 6 [DEPRECATED])')
c = c.replace('- **통신 채널**: `CH_THRUST_ACTUATION` (`oldBase + 6`)', '- **통신 채널**: `CH_THRUST_ACTUATION` (`oldBase + 10`, 구 `oldBase + 6` [DEPRECATED])')
c = c.replace('newBase + 6` 채널', 'newBase + 10` 채널 (구 newBase + 6 [DEPRECATED])')
c = c.replace('기존 `oldBase + 6` 채널을 닫고 `newBase + 6`을', '기존 `oldBase + 10` 채널을 닫고 `newBase + 10`을 (구 oldBase/newBase + 6 [DEPRECATED])')
c = c.replace('임시 개방한 `newBase + 6`', '임시 개방한 `newBase + 10`')
c = c.replace('Base = 10000 + (N - 1) * 20', 'Base = 10000 + (N - 1) * 40 (BW=40, 구버전 20채널 [DEPRECATED])')
c = c.replace('Base = 10000 + (N-1)*20', 'Base = 10000 + (N-1)*40')
c = c.replace('Base+6', 'Base+10')

with open(tca_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('TCA synced!')

# 3. ASA
asa_path = 'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md'
with open(asa_path, 'r', encoding='utf-8') as f:
    c = f.read()

asa_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.3.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 조종면 버스 Zone 2 이관(`Base+11`: `CH_SURFACE_ACTUATION`, 구 `Base+7` [DEPRECATED]) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, asa_rev)
c = c.replace('문서 버전**: v1.2.1', '문서 버전**: v1.3.0')
c = c.replace('문서 버전**: v1.2.2', '문서 버전**: v1.3.0')
c = c.replace('../../../implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', '../../2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../tca/TCA_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md', '../../0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../../0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md')
c = c.replace('Base+6 [CH_THRUST_ACTUATION]', 'Base+10 [CH_THRUST_ACTUATION, 구 Base+6 DEPRECATED]')
c = c.replace('Base+6 MSG_THRUST_STATUS', 'Base+10 MSG_THRUST_STATUS')
c = c.replace('Core $\\rightarrow$ ASA, Base + 7)', 'Core $\\rightarrow$ ASA, Base + 11, 구 Base + 7 [DEPRECATED])')
c = c.replace('Core $\\rightarrow$ ASA, oldBase + 7)', 'Core $\\rightarrow$ ASA, oldBase + 11, 구 oldBase + 7 [DEPRECATED])')
c = c.replace('- **통신 채널**: `CH_SURFACE_ACTUATION` (`oldBase + 7`)', '- **통신 채널**: `CH_SURFACE_ACTUATION` (`oldBase + 11`, 구 `oldBase + 7` [DEPRECATED])')
c = c.replace('newBase + 7` 채널', 'newBase + 11` 채널 (구 newBase + 7 [DEPRECATED])')
c = c.replace('기존 `oldBase + 7` 채널을 닫고 `newBase + 7`을', '기존 `oldBase + 11` 채널을 닫고 `newBase + 11`을')
c = c.replace('임시 개방한 `newBase + 7`', '임시 개방한 `newBase + 11`')
c = c.replace('Base+7', 'Base+11')

with open(asa_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('ASA synced!')

# 4. SAS
sas_path = 'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md'
with open(sas_path, 'r', encoding='utf-8') as f:
    c = f.read()

sas_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.10.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 01호기 기준선(Base 10000, MFD 10003, 회신 10005) 동기화, GCS 부트스트랩 채널 50000 고정, 구버전 Base+6/+7 Zone 2 이관 반영, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, sas_rev)
c = c.replace('../../../approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md', '../../1_control/asa/ASA_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../../1_control/tca/TCA_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../../0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md')
c = c.replace('Base = 10000 + (N - 1) * 20', 'Base = 10000 + (N - 1) * 40 (BW=40, 구버전 20채널 [DEPRECATED])')
c = c.replace('Base = 10000 + (N-1)*20', 'Base = 10000 + (N-1)*40')
c = c.replace('Base = 10000 + (N - 1)*20', 'Base = 10000 + (N - 1)*40')
c = c.replace('10045', '10005')
c = c.replace('10060', '10000')
c = c.replace('10063', '10003')

with open(sas_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('SAS synced!')

# 5. Alignment
align_path = 'docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md'
with open(align_path, 'r', encoding='utf-8') as f:
    c = f.read()

align_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v2.5.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 ($Base = 10000 + (N-1)\\times 40$) 반영, 01호기 직결 바인딩 채널 `Base+0` (`10000`, 구 1000 [DEPRECATED]) 동기화, TCA/ASA 동적 바인딩 `Base+10/11` 반영, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, align_rev)
c = c.replace('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md')
c = c.replace('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../../1_control/tca/TCA_PROGRAM_SPECIFICATION.md')
c = c.replace('10000 + (aircraftNumber - 1) * 20', '10000 + (aircraftNumber - 1) * 40 -- BW=40 (구버전 20 [DEPRECATED])')

with open(align_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('Alignment synced!')

# 6. GPS
gps_path = 'docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'
with open(gps_path, 'r', encoding='utf-8') as f:
    c = f.read()

gps_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v2.1.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 반영, 01호기 회신 채널 `Base+5` (`10005`, 구 10045 [DEPRECATED]) 동기화, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
c = add_revision_history(c, gps_rev)
c = c.replace('replyChannel = 10045', 'replyChannel = 10005')

with open(gps_path, 'w', encoding='utf-8') as f:
    f.write(c)
print('GPS synced!')

# 7. Ground & GAC 4 specs
ground_specs = [
    'docs/specs/approved/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
]

for p in ground_specs:
    with open(p, 'r', encoding='utf-8') as f:
        c = f.read()
    c = c.replace('../../../implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../../0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md')
    c = c.replace('../../../implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', '../../2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md')
    c = c.replace('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md')
    c = c.replace('SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md (전체 구조도 v2.6.0)', 'SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md (전체 구조도 v2.7.0)')
    c = c.replace('전체 구조도 v2.6.0', '전체 구조도 v2.7.0')
    c = c.replace('마스터 ICD v1.20.0', '마스터 ICD v1.20.0')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(c)
    print(f'Ground/GAC spec synced: {p}')
