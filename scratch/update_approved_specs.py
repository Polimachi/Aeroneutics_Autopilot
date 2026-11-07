import os, sys

def update_file(path, updates):
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    for old, new in updates:
        if old not in c:
            print(f'WARNING: target string not found in {path}: {repr(old)[:60]}')
        else:
            c = c.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(c)
    print(f'Updated {path} successfully!')

# 1. VAS
vas_path = 'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'
vas_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.12.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 구동계 버스 Zone 2 이관(`Base+10`: TCA, `Base+11`: ASA, `Base+12~19`: 구동계 예비), 구버전 `Base+6`, `Base+7`에 `[DEPRECATED]` 부여, `Base+0` C2 상시 개방 명세 확립, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
vas_updates = [
    ('> **문서 버전**: v1.11.0', '> **문서 버전**: v1.12.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  ', '> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  \n' + vas_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('Base+6 [CH_THRUST_ACTUATION]', 'Base+10 [CH_THRUST_ACTUATION, 구 Base+6 DEPRECATED]'),
    ('Base+7 [CH_AERO_ACTUATION]', 'Base+11 [CH_AERO_ACTUATION, 구 Base+7 DEPRECATED]'),
    ('Base+6: MSG_THRUST_CMD', 'Base+10: MSG_THRUST_CMD (구 Base+6 [DEPRECATED])'),
    ('Base+7: MSG_AERO_CMD', 'Base+11: MSG_AERO_CMD (구 Base+7 [DEPRECATED])'),
    ('Base+6 [CH_THRUST_ACTUATION]', 'Base+10 [CH_THRUST_ACTUATION]'),
    ('Base+7 [CH_AERO_ACTUATION]', 'Base+11 [CH_AERO_ACTUATION]'),
    ('`Base+6`', '`Base+10` (구 `Base+6` [DEPRECATED])'),
    ('`Base+7`', '`Base+11` (구 `Base+7` [DEPRECATED])'),
    ('Base+6 TCA', 'Base+10 TCA'),
    ('Base+7 ASA', 'Base+11 ASA'),
    ('Base+6, Base+7', 'Base+10, Base+11 (구 Base+6, Base+7 [DEPRECATED])'),
    ('Base+6 / Base+7', 'Base+10 / Base+11 (구 Base+6/7 [DEPRECATED])'),
    ('Base+6/Base+7', 'Base+10/Base+11'),
]
update_file(vas_path, vas_updates)

# 2. TCA
tca_path = 'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'
tca_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.9.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 추진기 버스 Zone 2 이관(`Base+10`: `CH_THRUST_ACTUATION`, 구 `Base+6` [DEPRECATED]), `Base+4` 상시 청취 제거 확정, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
tca_updates = [
    ('> **문서 버전**: v1.8.0', '> **문서 버전**: v1.9.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create Propulsion: Simulated  ', '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create Propulsion: Simulated  \n' + tca_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../vas/VAS_PROGRAM_SPECIFICATION.md'),
    ('Base+6 (CH_THRUST_ACTUATION)', 'Base+10 (CH_THRUST_ACTUATION, 구 Base+6 [DEPRECATED])'),
    ('`Base+6`', '`Base+10` (구 `Base+6` [DEPRECATED])'),
    ('`Base + 6`', '`Base + 10` (구 `Base + 6` [DEPRECATED])'),
    ('Base+6: MSG_THRUST_CMD', 'Base+10: MSG_THRUST_CMD'),
    ('Base+6: MSG_ACTUATOR_STATUS', 'Base+10: MSG_ACTUATOR_STATUS'),
    ('Base+6', 'Base+10'),
]
update_file(tca_path, tca_updates)

# 3. ASA
asa_path = 'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md'
asa_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.3.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 조종면 버스 Zone 2 이관(`Base+11`: `CH_SURFACE_ACTUATION`, 구 `Base+7` [DEPRECATED]) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
asa_updates = [
    ('> **문서 버전**: v1.2.1', '> **문서 버전**: v1.3.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  ', '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  \n' + asa_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../vas/VAS_PROGRAM_SPECIFICATION.md'),
    ('Base+7 [CH_SURFACE_ACTUATION]', 'Base+11 [CH_SURFACE_ACTUATION, 구 Base+7 DEPRECATED]'),
    ('`Base + 7`', '`Base + 11` (구 `Base + 7` [DEPRECATED])'),
    ('`Base+7`', '`Base+11` (구 `Base+7` [DEPRECATED])'),
    ('Base+7: MSG_SURFACE_CMD', 'Base+11: MSG_SURFACE_CMD'),
    ('Base+7: MSG_SURFACE_STATUS', 'Base+11: MSG_SURFACE_STATUS'),
    ('Base+7', 'Base+11'),
]
update_file(asa_path, asa_updates)

# 4. SAS
sas_path = 'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md'
sas_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.10.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장($Base = 10000 + (N-1)\\times 40$) 반영, 01호기 기준선(Base 10000, MFD 10003, 회신 10005) 동기화, GCS 부트스트랩 채널 50000 고정, 구버전 Base+6/+7 Zone 2 이관 반영, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
sas_updates = [
    ('> **문서 버전**: v1.9.0', '> **문서 버전**: v1.10.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  ', '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  \n' + sas_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'),
    ('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../../approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'),
    ('../../../implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', '../../approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'),
    ('Base = 10000 + (N - 1) * 20', 'Base = 10000 + (N - 1) * 40 (BW=40, 구버전 20채널 [DEPRECATED])'),
    ('Base = 10000 + (N-1)*20', 'Base = 10000 + (N-1)*40'),
    ('replyChannel = 10045', 'replyChannel = 10005'),
    ('Base+7', 'Base+11 (구 Base+7 [DEPRECATED])'),
    ('Base+6', 'Base+10 (구 Base+6 [DEPRECATED])'),
]
update_file(sas_path, sas_updates)

# 5. Alignment
align_path = 'docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md'
align_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v2.5.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 ($Base = 10000 + (N-1)\\times 40$) 반영, 01호기 직결 바인딩 채널 `Base+0` (`10000`, 구 1000 [DEPRECATED]) 동기화, TCA/ASA 동적 바인딩 `Base+10/11` 반영, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
align_updates = [
    ('> **문서 버전**: v2.4.0', '> **문서 버전**: v2.5.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  ', '> **대상 환경**: Minecraft CC:Tweaked, Create: Aeronautics, Create: Avionics  \n' + align_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'),
    ('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../../approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'),
    ('local craftBase = 10000 + (aircraftNumber - 1) * 20', 'local craftBase = 10000 + (aircraftNumber - 1) * 40 -- 40채널 기준 (구 20채널 [DEPRECATED])'),
    ('Base+6', 'Base+10 (구 Base+6 [DEPRECATED])'),
    ('Base+7', 'Base+11 (구 Base+7 [DEPRECATED])'),
]
update_file(align_path, align_updates)

# 6. GPS
gps_path = 'docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'
gps_rev = '''
### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v2.1.0` | 2026-11-07 | 비행체 전용 40채널($BW=40$) 대역 확장 반영, 01호기 회신 채널 `Base+5` (`10005`, 구 10045 [DEPRECATED]) 동기화, 승격 전이(`implemented/` $\\to$ `approved/`) | 서브채널 대역폭 확장 및 기능 영역별 직교성 확보, 1000대 수용량 확립 |
'''
gps_updates = [
    ('> **문서 버전**: v2.0.4', '> **문서 버전**: v2.1.0'),
    ('> **대상 환경**: Minecraft CC:Tweaked (Ender Modem, Advanced Monitor), Create: Aeronautics, Create: Avionics', '> **대상 환경**: Minecraft CC:Tweaked (Ender Modem, Advanced Monitor), Create: Aeronautics, Create: Avionics\n' + gps_rev),
    ('../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.6.0)', '../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 구조도 v2.7.0)'),
    ('../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md', '../../approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'),
    ('../../../implemented/1_control/tca/TCA_PROGRAM_SPECIFICATION.md', '../../approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'),
    ('../../../implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', '../../approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md'),
    ('replyChannel = 10045', 'replyChannel = 10005'),
]
update_file(gps_path, gps_updates)
