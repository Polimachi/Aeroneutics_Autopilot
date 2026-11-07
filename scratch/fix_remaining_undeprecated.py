import os, sys

# 1. Master ICD
p1 = 'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md'
with open(p1, 'r', encoding='utf-8') as f:
    c1 = f.read()
c1 = c1.replace('WAP의 VAS 산하 Base+7 편입', 'WAP의 VAS 산하 Base+11 편입 (구 Base+7 [DEPRECATED])')
c1 = c1.replace('(Node 06-xx, Base+7)', '(Node 06-xx, Base+11, 구 Base+7 [DEPRECATED])')
c1 = c1.replace('VAS (Node 01) $\\rightarrow$ TCA & ASA (Base+6 / Base+7, 베이 채널 동적 개폐 지령)', 'VAS (Node 01) $\\rightarrow$ TCA & ASA (Base+10 / Base+11, 구 Base+6/7 [DEPRECATED], 베이 채널 동적 개폐 지령)')
c1 = c1.replace('TCA(Base+6) / 공력 3축 자세(Ail/Elev/Rudd) 및 플랩: VAS Layer 3 `actuator_adapter_asa` $\\rightarrow$ ASA(Base+7)', 'TCA(Base+10, 구 Base+6 [DEPRECATED]) / 공력 3축 자세(Ail/Elev/Rudd) 및 플랩: VAS Layer 3 `actuator_adapter_asa` $\\rightarrow$ ASA(Base+11, 구 Base+7 [DEPRECATED])')
with open(p1, 'w', encoding='utf-8') as f:
    f.write(c1)

# 2. System Diagram
p2 = 'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md'
with open(p2, 'r', encoding='utf-8') as f:
    c2 = f.read()
c2 = c2.replace('WAP의 VAS 산하 Base+7 편입', 'WAP의 VAS 산하 Base+11 편입 (구 Base+7 [DEPRECATED])')
c2 = c2.replace('| `Base + 6`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 6`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)', '| `Base + 10`, $Base_{\\text{hangar}}+3$ (CALIB 시) | `Base + 10`, $Base_{\\text{hangar}}+0/+3$ (CALIB 시)')
with open(p2, 'w', encoding='utf-8') as f:
    f.write(c2)

# 3. VAS
p3 = 'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'
with open(p3, 'r', encoding='utf-8') as f:
    c3 = f.read()
c3 = c3.replace('(MSG_AERO_DISCOVER_REQ, Base+7)', '(MSG_AERO_DISCOVER_REQ, Base+11, 구 Base+7 [DEPRECATED])')
c3 = c3.replace('(MSG_AERO_DISCOVER_ACK, Base+7)', '(MSG_AERO_DISCOVER_ACK, Base+11, 구 Base+7 [DEPRECATED])')
c3 = c3.replace('- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 6`), `CH_AERO_ACTUATION` (`Base + 7`)', '- **통신 채널**: `CH_THRUST_ACTUATION` (`Base + 10`), `CH_AERO_ACTUATION` (`Base + 11`) (구 `Base+6`, `Base+7` [DEPRECATED])')
with open(p3, 'w', encoding='utf-8') as f:
    f.write(c3)

# 4. TCA
p4 = 'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'
with open(p4, 'r', encoding='utf-8') as f:
    c4 = f.read()
c4 = c4.replace('임시 개방한 `newBase + 6` 채널을 닫고', '임시 개방한 `newBase + 10` 채널(구 `newBase + 6` [DEPRECATED])을 닫고')
with open(p4, 'w', encoding='utf-8') as f:
    f.write(c4)

# 5. ASA
p5 = 'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md'
with open(p5, 'r', encoding='utf-8') as f:
    c5 = f.read()
c5 = c5.replace('임시 개방한 `newBase + 7` 채널을 닫고', '임시 개방한 `newBase + 11` 채널(구 `newBase + 7` [DEPRECATED])을 닫고')
with open(p5, 'w', encoding='utf-8') as f:
    f.write(c5)

# 6. SAS
p6 = 'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md'
with open(p6, 'r', encoding='utf-8') as f:
    c6 = f.read()
c6 = c6.replace('구버전 Base+6/+7 Zone 2 이관 반영', '구버전 Base+6/+7 [DEPRECATED] Zone 2 이관 반영')
c6 = c6.replace('WAP는 [VAS_PROGRAM_SPECIFICATION.md](../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md) 산하 3계층 액추에이터(`Base+7`)로 편입되었으므로', 'WAP는 [VAS_PROGRAM_SPECIFICATION.md](../../1_control/vas/VAS_PROGRAM_SPECIFICATION.md) 산하 3계층 액추에이터(`Base+11`, 구 `Base+7` [DEPRECATED])로 편입되었으므로')
c6 = c6.replace('하위 드라이버(TCA `Base+6`, WAP `Base+7`)에 전파.', '하위 드라이버(TCA `Base+10`, WAP `Base+11`, 구 `Base+6/7` [DEPRECATED])에 전파.')
with open(p6, 'w', encoding='utf-8') as f:
    f.write(c6)

print('All remaining un-deprecated references patched!')
