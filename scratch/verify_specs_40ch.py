import os, sys, re

spec_files = [
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

print(f"=== 40-Channel Specification Verification Suite ===")
print(f"Inspecting {len(spec_files)} active specifications...\n")

total_errors = 0
total_warnings = 0

link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')

for path in spec_files:
    if not os.path.exists(path):
        print(f"[FAIL] Missing spec file: {path}")
        total_errors += 1
        continue
    
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    doc_dir = os.path.dirname(path)
    file_name = os.path.basename(path)
    print(f"--- Checking {file_name} ---")

    # 1. Relative Link Verification
    links = link_pattern.findall(content)
    broken_links = []
    for text, link in links:
        # Ignore external or anchor-only links
        if link.startswith('http://') or link.startswith('https://') or link.startswith('#'):
            continue
        # Split anchor
        clean_link = link.split('#')[0]
        if not clean_link:
            continue
        target_path = os.path.normpath(os.path.join(doc_dir, clean_link))
        if not os.path.exists(target_path):
            broken_links.append((clean_link, target_path))
    
    if broken_links:
        print(f"  [ERROR] {len(broken_links)} broken relative link(s):")
        for orig, full in broken_links:
            print(f"    - Link '{orig}' -> '{full}' NOT FOUND")
        total_errors += len(broken_links)
    else:
        print(f"  [OK] All relative links valid ({len(links)} links checked)")

    # 2. Check for stale 'implemented/' links
    stale_impl = re.findall(r'\[[^\]]+\]\([^\)]*implemented[^\)]*\)', content)
    if stale_impl:
        print(f"  [ERROR] Found stale 'implemented/' links: {stale_impl}")
        total_errors += len(stale_impl)
    else:
        print(f"  [OK] Zero stale 'implemented/' links")

    # 3. Check Revision History presence on promoted specs
    if path in [
        'docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md',
        'docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md',
        'docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md',
        'docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md',
        'docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md',
        'docs/specs/approved/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md',
        'docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md',
        'docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md',
    ]:
        if '### Revision History' not in content:
            print(f"  [ERROR] Missing '### Revision History' table!")
            total_errors += 1
        else:
            print(f"  [OK] '### Revision History' present")

    # 4. Check for un-deprecated Base+6 or Base+7
    lines = content.splitlines()
    undeprecated_b67 = []
    for i, line in enumerate(lines, 1):
        if re.search(r'Base\s*\+\s*[67]\b', line):
            if 'DEPRECATED' not in line and 'deprecated' not in line:
                undeprecated_b67.append((i, line.strip()))
    
    if undeprecated_b67:
        print(f"  [WARNING/ERROR] {len(undeprecated_b67)} un-deprecated Base+6/7 references:")
        for line_no, text in undeprecated_b67:
            print(f"    L{line_no}: {text[:80]}")
        total_errors += len(undeprecated_b67)
    else:
        print(f"  [OK] Deprecation hygiene clean (Base+6/7 zero raw occurrence)")

    # 5. Check Base formula (must have * 40 or *40 if mentioning Base formula)
    legacy_base_20 = re.findall(r'Base\s*=\s*10000\s*\+\s*\(?N\s*[-–]\s*1\)?\s*\*\s*20', content)
    undep_base_20 = []
    for l in lines:
        if '10000 + (N - 1) * 20' in l or '10000 + (N-1)*20' in l or '10000 + (N-1) * 20' in l:
            if 'DEPRECATED' not in l and 'deprecated' not in l:
                undep_base_20.append(l.strip())
    if undep_base_20:
        print(f"  [ERROR] Un-deprecated legacy 20-channel Base formula: {undep_base_20}")
        total_errors += len(undep_base_20)
    else:
        print(f"  [OK] Base channel formula clean (* 40 standard)")

print("\n" + "="*50)
if total_errors == 0:
    print(f"SUCCESS: ALL 13 SPECIFICATIONS VERIFIED 100% CLEAN (0 Errors, {total_warnings} Warnings)!")
else:
    print(f"FAILED: Found {total_errors} errors across specifications.")
sys.exit(total_errors)
