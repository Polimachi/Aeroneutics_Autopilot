import os, re, sys

TARGET_IMPLEMENTED = [
    'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
]

TARGET_APPROVED = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
]

def check_status():
    errors = []
    status_pat = re.compile(r'\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|')

    for path in TARGET_IMPLEMENTED:
        if not os.path.exists(path):
            errors.append(f"Missing file: {path}")
            continue
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {path}")
        elif m.group(1).strip() != 'Implemented':
            errors.append(f"{path}: expected 'Implemented', got '{m.group(1).strip()}'")

    for path in TARGET_APPROVED:
        if not os.path.exists(path):
            errors.append(f"Missing file: {path}")
            continue
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {path}")
        elif m.group(1).strip() != 'Approved':
            errors.append(f"{path}: expected 'Approved', got '{m.group(1).strip()}'")

    if errors:
        print(f"[FAIL] {len(errors)} spec status violation(s):")
        for e in errors:
            print("  - " + e)
        sys.exit(1)
    print(f"[PASS] All 12 specs have valid statuses (5 Implemented, 7 Approved)!")

if __name__ == '__main__':
    check_status()
