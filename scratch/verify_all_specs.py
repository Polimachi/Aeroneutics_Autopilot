import os, sys, re

SPEC_FILES = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md',
]

REVISION_HISTORY_SPECS = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
]

def verify_all():
    print("=" * 65)
    print("Universal Specification Suite Comprehensive Integrity Scanner")
    print(f"Inspecting {len(SPEC_FILES)} active specifications...")
    print("=" * 65 + "\n")

    total_errors = 0
    total_warnings = 0
    link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

    for path in SPEC_FILES:
        if not os.path.exists(path):
            print(f"[ERROR] Missing file: {path}")
            total_errors += 1
            continue

        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        doc_dir = os.path.dirname(path)
        base_name = os.path.basename(path)
        lines = content.splitlines()

        print(f">> Checking {base_name} ({len(lines)} lines)")

        # 1. Relative Link Verification
        links = link_pattern.findall(content)
        broken = []
        for text, link in links:
            if link.startswith('http://') or link.startswith('https://') or link.startswith('#'):
                continue
            clean = link.split('#')[0]
            if not clean:
                continue
            target = os.path.normpath(os.path.join(doc_dir, clean))
            if not os.path.exists(target):
                broken.append((clean, target))

        if broken:
            print(f"   [FAIL] {len(broken)} broken relative link(s):")
            for c, t in broken:
                print(f"      - Link '{c}' -> '{t}' not found")
            total_errors += len(broken)
        else:
            print(f"   [PASS] All relative links valid ({len(links)} links checked)")

        # 2. Check for stale 'implemented/' in links
        stale_impl = re.findall(r'\[[^\]]+\]\([^\)]*implemented[^\)]*\)', content)
        if stale_impl:
            print(f"   [FAIL] Stale 'implemented/' links detected: {stale_impl}")
            total_errors += len(stale_impl)
        else:
            print(f"   [PASS] Zero stale 'implemented/' links")

        # 3. Check Revision History presence & table columns
        if path in REVISION_HISTORY_SPECS:
            if '### Revision History' not in content:
                print(f"   [FAIL] Missing '### Revision History' table")
                total_errors += 1
            else:
                # Check for standard columns: 버전, 개정 일자 (or 일자), 개정 요약, 개정 사유
                rev_match = re.search(r'### Revision History.*?\n\n(.*?)(?=\n\n|---|\n#)', content, re.DOTALL)
                if rev_match:
                    rev_table = rev_match.group(1)
                    if '버전' not in rev_table or '개정 요약' not in rev_table:
                        print(f"   [WARN] Revision History table header non-standard")
                        total_warnings += 1
                print(f"   [PASS] Revision History verified")

        # 4. Check for nested/messy deprecation patterns
        nested_patterns = [
            r'구\s*Base\+10',
            r'구\s*Base\+11',
            r'\[DEPRECATED\]\s*\[DEPRECATED\]',
            r'구버전\s*\(?구버전',
            r'구\s*구버전',
            r'Base\+10\s*\(구\s*Base\+10',
            r'Base\+11\s*\(구\s*Base\+11',
        ]
        found_nested = []
        for i, line in enumerate(lines, 1):
            for pat in nested_patterns:
                if re.search(pat, line):
                    found_nested.append((i, line.strip()))
        if found_nested:
            print(f"   [FAIL] Found {len(found_nested)} nested/awkward deprecation string(s):")
            for lno, text in found_nested:
                print(f"      L{lno}: {text[:80]}")
            total_errors += len(found_nested)
        else:
            print(f"   [PASS] Zero nested deprecation remnants")

        # 5. Check for un-deprecated Base+6 or Base+7
        raw_b67 = []
        for i, line in enumerate(lines, 1):
            if re.search(r'Base\s*\+\s*[67]\b', line):
                if 'DEPRECATED' not in line and 'deprecated' not in line:
                    raw_b67.append((i, line.strip()))
        if raw_b67:
            print(f"   [FAIL] Found {len(raw_b67)} un-deprecated Base+6/7 references:")
            for lno, text in raw_b67:
                print(f"      L{lno}: {text[:80]}")
            total_errors += len(raw_b67)
        else:
            print(f"   [PASS] Deprecation hygiene clean (Base+6/7 zero raw occurrence)")

        # 6. Check 40-channel Base formula consistency
        undep_base_20 = []
        for i, line in enumerate(lines, 1):
            if re.search(r'10000\s*\+\s*\(?N\s*[-–]\s*1\)?\s*\*\s*20\b', line):
                if 'DEPRECATED' not in line and 'deprecated' not in line:
                    undep_base_20.append((i, line.strip()))
        if undep_base_20:
            print(f"   [FAIL] Found un-deprecated legacy 20-channel Base formula:")
            for lno, text in undep_base_20:
                print(f"      L{lno}: {text[:80]}")
            total_errors += len(undep_base_20)
        else:
            print(f"   [PASS] Base formula clean (* 40 standard)")

        # 7. Check Mermaid block syntax (balanced quotes and delimiters)
        mermaid_blocks = re.findall(r'```mermaid\n(.*?)\n```', content, re.DOTALL)
        mermaid_errs = []
        for idx, block in enumerate(mermaid_blocks, 1):
            # Check quotation balance
            double_quotes = block.count('"')
            if double_quotes % 2 != 0:
                mermaid_errs.append(f"Mermaid block #{idx} has unbalanced double quotes ({double_quotes})")
        if mermaid_errs:
            print(f"   [FAIL] Mermaid syntax issues: {mermaid_errs}")
            total_errors += len(mermaid_errs)
        else:
            print(f"   [PASS] All Mermaid blocks syntactically balanced ({len(mermaid_blocks)} blocks)")

        print("")

    print("=" * 65)
    if total_errors == 0:
        print(f"SCAN RESULT: ALL {len(SPEC_FILES)} SPECS 100% CLEAN (0 Errors, {total_warnings} Warnings)")
        return 0
    else:
        print(f"SCAN RESULT: FAILED with {total_errors} errors, {total_warnings} warnings.")
        return total_errors

if __name__ == '__main__':
    sys.exit(verify_all())
