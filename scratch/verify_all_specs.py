import os, sys, re

SPEC_FILES = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
    'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
    'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md',
]

REVISION_HISTORY_SPECS = [
    'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
    'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
    'docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
    'docs/specs/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
    'docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
    'docs/specs/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md',
    'docs/specs/0_infra/runway/RUNWAY_SPECIFICATION_AND_ICD.md',
]

VALID_STATUSES = ['Draft', 'Approved', 'Implemented', 'Deprecated']

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

        # 2. Check for stale lifecycle directories in links ('approved/', 'implemented/', etc.)
        stale_links = re.findall(r'\[[^\]]+\]\([^\)]*(?:approved/|implemented/|drafts/|archived/)[^\)]*\)', content)
        if stale_links:
            print(f"   [FAIL] Stale lifecycle directory links detected: {stale_links}")
            total_errors += len(stale_links)
        else:
            print(f"   [PASS] Zero stale lifecycle directory links")

        # 3. Standard In-Document Metadata Table Verification
        meta_table_match = re.search(r'\|\s*항목\s*\|\s*내용\s*\|', content)
        if not meta_table_match:
            print(f"   [FAIL] Missing standard metadata table (| 항목 | 내용 |)")
            total_errors += 1
        else:
            # Check 5 mandatory fields
            status_match = re.search(r'\|\s*\*\*문서 상태 \(Status\)\*\*\s*\|\s*`([^`]+)`\s*\|', content)
            ver_match = re.search(r'\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*`([^`]+)`\s*\|', content)
            date_match = re.search(r'\|\s*\*\*최종 수정일 \(Date\)\*\*\s*\|\s*`([^`]+)`\s*\|', content)
            source_match = re.search(r'\|\s*\*\*구현 코드 \(Source\)\*\*\s*\|\s*`([^`]+)`\s*\|', content)
            domain_match = re.search(r'\|\s*\*\*주관 도메인 \(Domain\)\*\*\s*\|\s*([^\n|]+)\|', content)

            missing_fields = []
            if not status_match: missing_fields.append('문서 상태 (Status)')
            if not ver_match: missing_fields.append('문서 버전 (Version)')
            if not date_match: missing_fields.append('최종 수정일 (Date)')
            if not source_match: missing_fields.append('구현 코드 (Source)')
            if not domain_match: missing_fields.append('주관 도메인 (Domain)')

            if missing_fields:
                print(f"   [FAIL] Missing mandatory metadata field(s): {missing_fields}")
                total_errors += len(missing_fields)
            else:
                status_val = status_match.group(1).strip()
                if status_val not in VALID_STATUSES:
                    print(f"   [FAIL] Invalid status value: '{status_val}' (must be one of {VALID_STATUSES})")
                    total_errors += 1
                else:
                    print(f"   [PASS] In-document metadata table verified (Status: {status_val}, Version: {ver_match.group(1).strip()}, Date: {date_match.group(1).strip()})")

        # 4. Check Revision History presence & table columns
        if path in REVISION_HISTORY_SPECS:
            if '### Revision History' not in content:
                print(f"   [FAIL] Missing '### Revision History' table")
                total_errors += 1
            else:
                rev_match = re.search(r'### Revision History.*?\n\n(.*?)(?=\n\n|---|\n#)', content, re.DOTALL)
                if rev_match:
                    rev_table = rev_match.group(1)
                    if '버전' not in rev_table or '개정 요약' not in rev_table:
                        print(f"   [WARN] Revision History table header non-standard")
                        total_warnings += 1
                print(f"   [PASS] Revision History verified")

        # 5. Check for nested/messy deprecation patterns
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

        # 6. Check for un-deprecated Base+6 or Base+7
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

        # 7. Check 40-channel Base formula consistency
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

        # 8. Check Mermaid block syntax (balanced quotes and delimiters)
        mermaid_blocks = re.findall(r'```mermaid\n(.*?)\n```', content, re.DOTALL)
        mermaid_errs = []
        for idx, block in enumerate(mermaid_blocks, 1):
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
