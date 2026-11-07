import os, re

def update_file(path, replacements):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    original = content
    for pattern, repl in replacements:
        if callable(repl):
            content = re.sub(pattern, repl, content)
        else:
            content = re.sub(pattern, repl, content)
    if content != original:
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(content)
        print(f"[UPDATED] {path}")
    else:
        print(f"[UNCHANGED] {path}")

# 1. Docking Arm Spec
docking_replacements = [
    (r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`v1\.10\.4`\s*\|', '| **문서 버전 (Version)** | `v1.10.5` |'),
    (r'\|\s*\*\*구현 코드 \(Source\)\*\*\s*\|\s*`src/0_ground/docking_arm/`\s*\|', '| **구현 코드 (Source)** | `src/0_infra/docking_arm/` |'),
    (r'(\n\| \*\*주관 도메인 \(Domain\)\*\* \|[^\n]+\n)', r'''\1
### Revision History

| 버전 | 일자 | 개정 요약 | 개정 사유 |
| :--- | :--- | :--- | :--- |
| `v1.10.5` | 2026-11-07 | 사양서 및 코드 디렉토리 `0_ground` → `0_infra` 통합 이동 및 경로 동기화 | 지상 인프라 체계 단일화 구조 개편 |
| `v1.10.4` | 2026-11-07 | 40채널 확장 및 표준 메타데이터 표 적용 | Phase 0 ICD 동기화 |
'''),
    (r'\.\./\.\./0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\.\./\.\./0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
    (r'\(착륙패드 규격서 v2\.2\.4\)', '(착륙패드 규격서 v2.2.5)'),
    (r'\(활주로 규격서 v1\.10\.4\)', '(활주로 규격서 v1.10.5)'),
]
update_file('docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md', docking_replacements)

# 2. Landing Pad Spec
landing_replacements = [
    (r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`v2\.2\.4`\s*\|', '| **문서 버전 (Version)** | `v2.2.5` |'),
    (r'\|\s*\*\*구현 코드 \(Source\)\*\*\s*\|\s*`src/0_ground/landing_pad/`\s*\|', '| **구현 코드 (Source)** | `src/0_infra/landing_pad/` |'),
    (r'(\n\| \*\*주관 도메인 \(Domain\)\*\* \|[^\n]+\n)', r'''\1
### Revision History

| 버전 | 일자 | 개정 요약 | 개정 사유 |
| :--- | :--- | :--- | :--- |
| `v2.2.5` | 2026-11-07 | 사양서 및 코드 디렉토리 `0_ground` → `0_infra` 통합 이동 및 경로 동기화 | 지상 인프라 체계 단일화 구조 개편 |
| `v2.2.4` | 2026-11-07 | 40채널 확장 및 표준 메타데이터 표 적용 | Phase 0 ICD 동기화 |
'''),
    (r'\.\./\.\./0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\.\./\.\./0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
    (r'\(활주로 규격서 v1\.10\.[0-9]+\)', '(활주로 규격서 v1.10.5)'),
    (r'\(도킹암 규격서 v1\.10\.[0-9]+\)', '(도킹암 규격서 v1.10.5)'),
]
update_file('docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md', landing_replacements)

# 3. Runway Spec
runway_replacements = [
    (r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`v1\.10\.4`\s*\|', '| **문서 버전 (Version)** | `v1.10.5` |'),
    (r'\|\s*\*\*구현 코드 \(Source\)\*\*\s*\|\s*`src/0_ground/runway/`\s*\|', '| **구현 코드 (Source)** | `src/0_infra/runway/` |'),
    (r'(\n\| \*\*주관 도메인 \(Domain\)\*\* \|[^\n]+\n)', r'''\1
### Revision History

| 버전 | 일자 | 개정 요약 | 개정 사유 |
| :--- | :--- | :--- | :--- |
| `v1.10.5` | 2026-11-07 | 사양서 및 코드 디렉토리 `0_ground` → `0_infra` 통합 이동 및 경로 동기화 | 지상 인프라 체계 단일화 구조 개편 |
| `v1.10.4` | 2026-11-07 | 40채널 확장 및 표준 메타데이터 표 적용 | Phase 0 ICD 동기화 |
'''),
    (r'\.\./\.\./0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\.\./\.\./0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD\.md', '../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
    (r'\(착륙패드 규격서 v2\.2\.[0-9]+\)', '(착륙패드 규격서 v2.2.5)'),
    (r'\(도킹암 규격서 v1\.10\.[0-9]+\)', '(도킹암 규격서 v1.10.5)'),
]
update_file('docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md', runway_replacements)

# 4. GAC Spec
gac_replacements = [
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (착륙패드 규격서 v2.2.5)'),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../runway/RUNWAY_SPECIFICATION_AND_ICD.md) (활주로 규격서 v1.10.5)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (도킹암 규격서 v1.10.5)'),
    (r'\[GPS_PROGRAM_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD\.md\)',
     r'[GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md)'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
]
update_file('docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md', gac_replacements)

# 5. GPS Spec
gps_replacements = [
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\) 도킹암 규격서 연계 \(v1\.10\.[0-9]+ 동기화\)',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) 도킹암 규격서 연계 (v1.10.5 동기화)'),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\) 착륙패드 규격서 연계 \(v2\.2\.[0-9]+ 동기화\)',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) 착륙패드 규격서 연계 (v2.2.5 동기화)'),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\) 활주로 규격서 연계 \(v1\.10\.[0-9]+ 동기화\)',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../runway/RUNWAY_SPECIFICATION_AND_ICD.md) 활주로 규격서 연계 (v1.10.5 동기화)'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
]
update_file('docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md', gps_replacements)

# 6. SAS Spec
sas_replacements = [
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../../0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md) (활주로 규격서 v1.10.5)'),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../../0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (착륙패드 규격서 v2.2.5)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../../0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (도킹암 규격서 v1.10.5)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./\.\./0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\)',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../../0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md)'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
]
update_file('docs/specs/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md', sas_replacements)

# 7. Master ICD
master_replacements = [
    (r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`v1\.20\.0`\s*\|', '| **문서 버전 (Version)** | `v1.20.1` |'),
    (r'(\| 버전 \| 개정 일자 \| 개정 요약 \| 개정 사유 \|\n\| :---:? \| :---:? \| :--- \| :--- \|\n)',
     r'''\1| `v1.20.1` | 2026-11-07 | 0_ground 도메인의 0_infra 통합 반영 및 하위 사양서 링크·버전(v1.10.5/v2.2.5) 갱신 | 지상 인프라 디렉토리 단일화 반영 |
'''),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\) \(v2\.2\.[0-9]+\)',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (v2.2.5)'),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\) \(v1\.10\.[0-9]+\)',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md) (v1.10.5)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\) \(v1\.10\.[0-9]+\)',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (v1.10.5)'),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\)',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md)'),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\)',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\)',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md)'),
]
update_file('docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md', master_replacements)

# 8. Packet Diagram
diagram_replacements = [
    (r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`v1\.10\.3`\s*\|', '| **문서 버전 (Version)** | `v1.10.4` |'),
    (r'(\| 버전 \| 개정 일자 \| 개정 요약 \| 개정 사유 \|\n\| :---:? \| :---:? \| :--- \| :--- \|\n)',
     r'''\1| `v1.10.4` | 2026-11-07 | 0_ground 도메인의 0_infra 통합 반영 및 하위 사양서 링크(docs/specs/0_infra) 동기화 | 지상 인프라 구조 통합 반영 |
'''),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md) (활주로 규격서 v1.10.5)'),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (착륙 패드 규격서 v2.2.5)'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\(\.\./specs/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD\.md\)(?: \([^)]+\))?',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (도킹암 규격서 v1.10.5)'),
    (r'\(마스터 ICD v1\.20\.0\)', '(마스터 ICD v1.20.1)'),
]
update_file('docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md', diagram_replacements)

# 9. src README files
docking_src_readme = [
    (r'`0_ground/docking_arm`', '`0_infra/docking_arm`'),
    (r'\[DOCKING_ARM_SPECIFICATION_AND_ICD\.md\]\([^\)]*\)',
     r'[DOCKING_ARM_SPECIFICATION_AND_ICD.md](../../../docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md)'),
]
update_file('src/0_infra/docking_arm/README.md', docking_src_readme)

landing_src_readme = [
    (r'`0_ground/landing_pad`', '`0_infra/landing_pad`'),
    (r'\[LANDING_PAD_SPECIFICATION_AND_ICD\.md\]\([^\)]*\)',
     r'[LANDING_PAD_SPECIFICATION_AND_ICD.md](../../../docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md)'),
]
update_file('src/0_infra/landing_pad/README.md', landing_src_readme)

runway_src_readme = [
    (r'`0_ground/runway`', '`0_infra/runway`'),
    (r'\[RUNWAY_SPECIFICATION_AND_ICD\.md\]\([^\)]*\)',
     r'[RUNWAY_SPECIFICATION_AND_ICD.md](../../../docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md)'),
]
update_file('src/0_infra/runway/README.md', runway_src_readme)

print("Batch update script execution finished.")

# Update src/README.md
src_readme = [
    (r'- \*\*`0_ground/`\*\*: 지상 시설물 계층 \(Ground Facility Layer\)\n  - `landing_pad/`: \*\*LANDING_PAD\*\* - VTOL 착륙패드 및 버티포트 스테이션\n  - `runway/`: \*\*RUNWAY\*\* - 활주로 및 항공모함 비행갑판 관제 스테이션\n  - `docking_arm/`: \*\*DOCKING_ARM\*\* - 기체 정밀 도킹 2축 로봇 암 스테이션\n',
     ''),
    (r'(- \*\*`0_infra/`\*\*: [^\n]+\n  - `gps/`: [^\n]+\n  - `gac/`: [^\n]+\n)',
     r'''\1  - `docking_arm/`: **DOCKING_ARM** - 기체 정밀 도킹 2축 로봇 암 스테이션
  - `landing_pad/`: **LANDING_PAD** - VTOL 착륙패드 및 버티포트 스테이션
  - `runway/`: **RUNWAY** - 활주로 및 항공모함 비행갑판 관제 스테이션
'''),
    (r'- \*\*`0_infra/`\*\*: 인프라 계층 \(Infrastructure Layer\)',
     '- **`0_infra/`**: 인프라 및 지상 시설물 계층 (Infrastructure & Ground Facility Layer)')
]
update_file('src/README.md', src_readme)
