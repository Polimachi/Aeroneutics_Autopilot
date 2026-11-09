from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class TestTerminologyGuard(unittest.TestCase):
    UAP_PATTERN = re.compile(r'(?<![A-Za-z0-9])uap(?![A-Za-z0-9])', re.IGNORECASE)
    SAS_PATTERN = re.compile(r'(?<![A-Za-z0-9])SAS(?![A-Za-z0-9])')
    WAP_PATTERN = re.compile(r'(?<![A-Za-z0-9])wap(?![A-Za-z0-9])', re.IGNORECASE)
    VAS_CORE_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)
    VAS_ALIGN_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAS[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
    VAC_ALIGN_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Align(?![A-Za-z0-9])', re.IGNORECASE)
    VAC_CORE_PATTERN = re.compile(r'(?<![A-Za-z0-9])VAC[-_]Core(?![A-Za-z0-9])', re.IGNORECASE)

    def _collect_violations(self, base_dir: Path, pattern: re.Pattern, extensions: list[str]) -> list[str]:
        violations = []
        for ext in extensions:
            for p in base_dir.rglob(f'*{ext}'):
                if 'superpowers' in p.parts or '.git' in p.parts:
                    continue
                content = p.read_text(encoding='utf-8', errors='replace')
                for idx, line in enumerate(content.splitlines(), 1):
                    if pattern.search(line):
                        violations.append(f"{p.relative_to(REPO_ROOT)}:L{idx}: {line.strip()[:80]}")
        return violations

    def test_no_uap_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 UAP 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.UAP_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} UAP occurrences:\n" + "\n".join(violations[:10]))

    def test_no_sas_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 SAS 잔존을 검출한다 (소급 전면 삭제)."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.SAS_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} SAS occurrences:\n" + "\n".join(violations[:10]))

    def test_no_wap_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 WAP 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.WAP_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} WAP occurrences:\n" + "\n".join(violations[:10]))

    def test_no_legacy_wap_files(self):
        """src/ 및 tests/ 내에 구버전 WAP 모듈명이 남아있지 않은지 검출한다."""
        banned_filenames = {'node_wap.lua', 'actuator_adapter_wap.lua', 'node_wap_sim.lua'}
        found = []
        for folder in ['src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                for p in d.rglob('*.lua'):
                    if p.name in banned_filenames:
                        found.append(str(p.relative_to(REPO_ROOT)))
        self.assertEqual(found, [], f"Legacy WAP files found: {found}")

    def test_no_vas_core_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAS-Core 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAS_CORE_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAS-Core occurrences:\n" + "\n".join(violations[:10]))

    def test_no_vas_align_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAS-Align 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAS_ALIGN_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAS-Align occurrences:\n" + "\n".join(violations[:10]))

    def test_no_vac_align_or_core_in_entire_repository(self):
        """docs/, src/, tests/ 전역에서 VAC-Align 및 VAC-Core 잔존을 검출한다."""
        violations = []
        for folder in ['docs', 'src', 'tests']:
            d = REPO_ROOT / folder
            if d.exists():
                violations.extend(self._collect_violations(d, self.VAC_ALIGN_PATTERN, ['.md', '.lua', '.json']))
                violations.extend(self._collect_violations(d, self.VAC_CORE_PATTERN, ['.md', '.lua', '.json']))
        self.assertEqual(violations, [], f"Found {len(violations)} VAC-Align/VAC-Core occurrences:\n" + "\n".join(violations[:10]))


if __name__ == '__main__':
    unittest.main()
