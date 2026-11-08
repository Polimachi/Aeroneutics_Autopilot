"""
Specification status validation tool.
Asserts that all 14 active specifications have expected in-document status:
- 8 Implemented specs
- 6 Approved specs
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

TARGET_IMPLEMENTED = [
    'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md',
    'docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/gcs/GCS_PROGRAM_SPECIFICATION_AND_ICD.md',
]

TARGET_APPROVED = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
]


def check_status(repo_root: Path) -> int:
    errors: list[str] = []
    status_pat = re.compile(r'\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|')

    for rel_path in TARGET_IMPLEMENTED:
        spec_path = (repo_root / rel_path).resolve()
        if not spec_path.exists():
            errors.append(f"Missing file: {rel_path} ({spec_path})")
            continue
        content = spec_path.read_text(encoding='utf-8')
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {rel_path}")
        elif m.group(1).strip() != 'Implemented':
            errors.append(f"{rel_path}: expected 'Implemented', got '{m.group(1).strip()}'")

    for rel_path in TARGET_APPROVED:
        spec_path = (repo_root / rel_path).resolve()
        if not spec_path.exists():
            errors.append(f"Missing file: {rel_path} ({spec_path})")
            continue
        content = spec_path.read_text(encoding='utf-8')
        m = status_pat.search(content)
        if not m:
            errors.append(f"Missing status table in {rel_path}")
        elif m.group(1).strip() != 'Approved':
            errors.append(f"{rel_path}: expected 'Approved', got '{m.group(1).strip()}'")

    if errors:
        print(f"[FAIL] {len(errors)} spec status violation(s):")
        for e in errors:
            print("  - " + e)
        return 1

    total_count = len(TARGET_IMPLEMENTED) + len(TARGET_APPROVED)
    print(f"[PASS] All {total_count} specs have valid statuses ({len(TARGET_IMPLEMENTED)} Implemented, {len(TARGET_APPROVED)} Approved)!")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Specification Status Distribution Checker")
    parser.add_argument("--root", type=str, default=None, help="Repository root path override")
    args = parser.parse_args()

    repo_root = Path(args.root).resolve() if args.root else REPO_ROOT
    return check_status(repo_root=repo_root)


if __name__ == '__main__':
    sys.exit(main())
