"""Unit and end-to-end tests for tools/verify_all_specs.py (18 specs & Rule 10)."""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

import tools.verify_all_specs as vas

MASTER_ICD_REL = "docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md"
EDITOR_SPEC_REL = "docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md"

MINIMAL_SPEC_TEMPLATE = """# Synthetic Specification

| 항목 | 내용 |
| :--- | :--- |
| **문서 상태 (Status)** | `Implemented` |
| **문서 버전 (Version)** | `v1.0.0` |
| **최종 수정일 (Date)** | `2026-11-20` |
| **구현 코드 (Source)** | `src/` |
| **주관 도메인 (Domain)** | 테스트 도메인 |

### Revision History

| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |
| :---: | :---: | :--- | :--- |
| `v1.0.0` | `2026-11-20` | 초기 작성 | 테스트 |

---

## 1. 개요
{body}
"""


def _build_synthetic_suite(root: Path, overrides: dict[str, str] | None = None) -> None:
    """Create minimal valid files for all specs in SPEC_FILES under root."""
    overrides = overrides or {}
    for rel_path in vas.SPEC_FILES:
        target = root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        body = overrides.get(rel_path, "정상 본문입니다.")
        target.write_text(MINIMAL_SPEC_TEMPLATE.format(body=body), encoding="utf-8")


class TestVerifyAllSpecsLists(unittest.TestCase):
    def test_spec_lists_contain_18_active_specs_including_editor(self) -> None:
        self.assertEqual(len(vas.SPEC_FILES), 18)
        self.assertEqual(len(vas.REVISION_HISTORY_SPECS), 18)
        self.assertEqual(len(set(vas.SPEC_FILES)), 18)
        self.assertEqual(set(vas.SPEC_FILES), set(vas.REVISION_HISTORY_SPECS))
        self.assertIn(EDITOR_SPEC_REL, vas.SPEC_FILES)
        self.assertIn(EDITOR_SPEC_REL, vas.REVISION_HISTORY_SPECS)


class TestRule10InlinePeerVersionBadges(unittest.TestCase):
    def test_flags_markdown_link_with_semver_in_related_docs_and_body(self) -> None:
        content = (
            "> **연관 문서**:\n"
            "> - [AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md) (v2.7.1)\n"
            "본문 링크 [FCP](../../2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md#sec-3) `v2.6.1`\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md"
        )
        self.assertEqual([line_no for line_no, _ in findings], [2, 3])

    def test_flags_backticked_peer_md_with_semver_in_prose(self) -> None:
        content = (
            "`VAS_PROGRAM_SPECIFICATION.md` (`v1.26.1`) 규격을 따릅니다.\n"
            "참고: `TCA_PROGRAM_SPECIFICATION.md`는 v1.15.1 이상이어야 합니다.\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md"
        )
        self.assertEqual([line_no for line_no, _ in findings], [1, 2])

    def test_flags_semver_adjacent_to_hangul_particles(self) -> None:
        link_findings = vas.find_inline_peer_version_badges(
            "[VAS.md](VAS.md) v1.26.1에서", "x.md"
        )
        self.assertEqual(len(link_findings), 1)
        prose_findings = vas.find_inline_peer_version_badges(
            "`VAS.md` v1.26.1의", "x.md"
        )
        self.assertEqual(len(prose_findings), 1)

    def test_ignores_revision_history_table_and_resumes_immediately_after_table(self) -> None:
        content = (
            "### Revision History\n"
            "\n"
            "| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |\n"
            "| :---: | :---: | :--- | :--- |\n"
            "| `v2.7.1` | `2026-11-15` | `OTA_PROGRAM_SPECIFICATION.md` v0.1.0 반영 | 동기화 |\n"
            "> **연관 규격서**: [AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md) (v2.7.1)\n"
            "- [VAS_PROGRAM_SPECIFICATION.md](VAS_PROGRAM_SPECIFICATION.md) (`v1.26.1`)\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md"
        )
        self.assertEqual([line_no for line_no, _ in findings], [6, 7])

    def test_ignores_revision_history_separated_by_blank_line_then_related_docs(self) -> None:
        content = (
            "### Revision History\n"
            "\n"
            "| 버전 | 개정 일자 | 개정 요약 | 개정 사유 |\n"
            "| :---: | :---: | :--- | :--- |\n"
            "| `v2.22.1` | `2026-11-20` | `GAC` (`v1.7.0`) 동기화 | 정리 |\n"
            "\n"
            "> **연관 규격서**:\n"
            "> - [GAC_PROGRAM_SPECIFICATION_AND_ICD.md](../specs/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md) (v1.7.1)\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md"
        )
        self.assertEqual([line_no for line_no, _ in findings], [8])

    def test_exempts_master_icd_section_5_1_only(self) -> None:
        icd_content = (
            "## 1. 개요\n"
            "[VAS_PROGRAM_SPECIFICATION.md](../specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (v1.26.1)\n"
            "### 5.1 온보드 및 인프라 프로그램 사양·구현 현황\n"
            "> [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (`v2.22.1`)\n"
            "| **Installer** | Ground | `v1.3.1` | [INSTALLER_PROGRAM_SPECIFICATION.md](../specs/0_development/installer/INSTALLER_PROGRAM_SPECIFICATION.md) |\n"
            "### 5.2 통합 시험 결과\n"
            "[FCP_PROGRAM_SPECIFICATION.md](../specs/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md) (v2.6.1)\n"
        )
        # Forward-slash and Windows backslash rel_path normalization
        self.assertEqual(
            [line_no for line_no, _ in vas.find_inline_peer_version_badges(icd_content, MASTER_ICD_REL)],
            [2, 7],
        )
        self.assertEqual(
            [
                line_no
                for line_no, _ in vas.find_inline_peer_version_badges(
                    icd_content, MASTER_ICD_REL.replace("/", "\\")
                )
            ],
            [2, 7],
        )
        # Non-ICD spec with ### 5.1 heading is NOT exempted
        non_icd_findings = vas.find_inline_peer_version_badges(
            icd_content, "docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md"
        )
        self.assertEqual([line_no for line_no, _ in non_icd_findings], [2, 4, 5, 7])

    def test_exempts_master_icd_section_5_1_until_hr_separator(self) -> None:
        icd_content = (
            "### 5.1 현황\n"
            "| **OTA** | Ground | `v0.1.1` | [OTA_PROGRAM_SPECIFICATION.md](../specs/0_development/ota/OTA_PROGRAM_SPECIFICATION.md) |\n"
            "---\n"
            "[AMM_PROGRAM_SPECIFICATION.md](../specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md) (v2.7.1)\n"
        )
        findings = vas.find_inline_peer_version_badges(icd_content, MASTER_ICD_REL)
        self.assertEqual([line_no for line_no, _ in findings], [4])

    def test_exempts_deprecation_notes_while_catching_genuine_peer_badge_on_same_line(self) -> None:
        content = (
            "구 규격 참조 [ASA_PROGRAM_SPECIFICATION.md](ASA.md) (`[DEPRECATED - v1.12.0]`)\n"
            "신규+구 규격 [ASA_PROGRAM_SPECIFICATION.md](ASA.md) (v1.8.1) `[DEPRECATED - v1.12.0]`\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/specs/1_control/vas/VAS_PROGRAM_SPECIFICATION.md"
        )
        self.assertEqual([line_no for line_no, _ in findings], [2])

    def test_ignores_standalone_and_unlinked_prose_versions(self) -> None:
        content = (
            "- **AMM `v2.0.0` 미션 스키마 동등성**: 내부 스키마 버전 설명\n"
            "- 단독 릴리스 메모 `v0.6.1` 또는 `v1.9.5` 프로토콜 언급\n"
            "- [AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md) (버전 배지 없음)\n"
        )
        findings = vas.find_inline_peer_version_badges(
            content, "docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md"
        )
        self.assertEqual(findings, [])


class TestVerifyAllEndToEnd(unittest.TestCase):
    def test_verify_all_passes_on_clean_minimal_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_suite(root)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = vas.verify_all(root, check_readmes=False)
            self.assertEqual(rc, 0, buf.getvalue())
            self.assertIn("ALL 18 SPECS 100% CLEAN (0 Errors, 0 Warnings)", buf.getvalue())

    def test_verify_all_fails_when_inline_peer_badge_present(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target_rel = "docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md"
            _build_synthetic_suite(
                root,
                overrides={
                    target_rel: "- [AMM_PROGRAM_SPECIFICATION.md](AMM_PROGRAM_SPECIFICATION.md) (v2.7.1)"
                },
            )
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = vas.verify_all(root, check_readmes=False)
            out = buf.getvalue()
            self.assertGreater(rc, 0, out)
            self.assertIn("[FAIL] [Rule 10: Inline peer version badge]", out)
            self.assertIn(target_rel, out)


if __name__ == "__main__":
    unittest.main()
