# 1. Master ICD
p1 = 'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md'
with open(p1, 'r', encoding='utf-8') as f:
    c1 = f.read()
c1 = c1.replace(
    'TCA(Base+6) / 공력 3축 자세(Ail/Elev/Rudd) 및 플랩: VAS Layer 3 `actuator_adapter_asa` $\\rightarrow$ ASA(Base+7)',
    'TCA(Base+10, 구 Base+6 [DEPRECATED]) / 공력 3축 자세(Ail/Elev/Rudd) 및 플랩: VAS Layer 3 `actuator_adapter_asa` $\\rightarrow$ ASA(Base+11, 구 Base+7 [DEPRECATED])'
)
with open(p1, 'w', encoding='utf-8') as f:
    f.write(c1)

# 2. VAS
p2 = 'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md'
with open(p2, 'r', encoding='utf-8') as f:
    c2 = f.read()
c2 = c2.replace(
    '- **전파 채널**: `CH_THRUST_ACTUATION` (`Base + 6`), `CH_AERO_ACTUATION` (`Base + 7`) (TCA/ASA 전파)',
    '- **전파 채널**: `CH_THRUST_ACTUATION` (`Base + 10`), `CH_AERO_ACTUATION` (`Base + 11`) (TCA/ASA 전파, 구 `Base+6/7` [DEPRECATED])'
)
with open(p2, 'w', encoding='utf-8') as f:
    f.write(c2)

# 3. TCA
p3 = 'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md'
with open(p3, 'r', encoding='utf-8') as f:
    c3 = f.read()
c3 = c3.replace(
    '임시 개방한 `newBase + 10`을 파기하고 `oldBase + 6` 유지.',
    '임시 개방한 `newBase + 10`을 파기하고 `oldBase + 10` 유지 (구 oldBase+6 [DEPRECATED]).'
)
with open(p3, 'w', encoding='utf-8') as f:
    f.write(c3)

# 4. ASA
p4 = 'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md'
with open(p4, 'r', encoding='utf-8') as f:
    c4 = f.read()
c4 = c4.replace(
    '임시 개방한 `newBase + 11`을 즉시 파기하고 `oldBase + 7`을 유지.',
    '임시 개방한 `newBase + 11`을 즉시 파기하고 `oldBase + 11`을 유지 (구 oldBase+7 [DEPRECATED]).'
)
with open(p4, 'w', encoding='utf-8') as f:
    f.write(c4)

# 5. SAS
p5 = 'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md'
with open(p5, 'r', encoding='utf-8') as f:
    c5 = f.read()
c5 = c5.replace(
    '`Base + 7` 채널을 통해 VAS-Core의',
    '`Base + 11` 채널(구 `Base + 7` [DEPRECATED])을 통해 VAS-Core의'
)
c5 = c5.replace(
    '하위 TCA(`oldBase + 6`) 및 ASA(`oldBase + 7`)으로 동시 중계 전파.',
    '하위 TCA(`oldBase + 10`) 및 ASA(`oldBase + 11`) (구 oldBase+6/7 [DEPRECATED])으로 동시 중계 전파.'
)
with open(p5, 'w', encoding='utf-8') as f:
    f.write(c5)

print('Final 6 lines patched!')
