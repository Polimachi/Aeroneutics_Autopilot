"""Unit and CLI tests for tools/verify_playbooks.py (TDD)."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

EXPECTED_REQUIRED_PLAYBOOKS = (
    "playbook/0_development/alignment.md",
    "playbook/0_development/fdr.md",
    "playbook/0_development/installer.md",
    "playbook/0_development/ota.md",
    "playbook/0_development/sensors.md",
    "playbook/0_infra/gps.md",
    "playbook/0_infra/gcs.md",
    "playbook/0_infra/gac.md",
    "playbook/0_infra/landing_pad.md",
    "playbook/0_infra/pocket_pda.md",
    "playbook/0_infra/runway.md",
    "playbook/1_control/vas.md",
    "playbook/1_control/tca.md",
    "playbook/2_guidance/fcp.md",
    "playbook/3_planning/amm.md",
    "playbook/3_planning/amm_mission_editor.md",
)

MINIMAL_PLAYBOOK_BODY = """# Synthetic Playbook

## 1. 서브시스템 개요 및 역할 (Overview & Role)
개요 설명.

## 2. 필수 하드웨어 및 페리페럴 목록 (Peripherals & Wiring)
하드웨어 목록.

## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)
배치 지침.

## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)
채널 설정.

## 5. 소프트웨어 설치 방법 (Installation)
설치 방법.

## 6. 설정 파일 가이드 (Configuration Parameters & Defaults)
설정 가이드.

## 7. 기본 조작 및 트러블슈팅 (TUI/Keybinds & Troubleshooting)
기본 조작 및 문제 해결.
"""


def _build_synthetic_playbooks(root: Path, overrides: dict[str, str] | None = None) -> None:
    overrides = overrides or {}
    readme_links = []
    for rel in EXPECTED_REQUIRED_PLAYBOOKS:
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(overrides.get(rel, MINIMAL_PLAYBOOK_BODY), encoding="utf-8")
        sub_rel = rel.removeprefix("playbook/")
        readme_links.append(f"- [{sub_rel}]({sub_rel})")

    readme_path = root / "playbook" / "README.md"
    default_readme = "# Playbook Index\n\n" + "\n".join(readme_links) + "\n"
    readme_path.write_text(overrides.get("playbook/README.md", default_readme), encoding="utf-8")


def _run_cli(root: Path, *extra_args: str) -> subprocess.CompletedProcess[str]:
    script = WORKSPACE_ROOT / "tools" / "verify_playbooks.py"
    return subprocess.run(
        [sys.executable, str(script), "--root", str(root), *extra_args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=str(WORKSPACE_ROOT),
        timeout=30,
    )


class TestVerifyPlaybooks(unittest.TestCase):
    def test_valid_16_playbooks_and_readme_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_playbooks(root)
            res = _run_cli(root)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertIn("0 Errors, 0 Warnings", res.stdout)

    def test_missing_required_playbook_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_playbooks(root)
            (root / "playbook" / "0_infra" / "runway.md").unlink()
            res = _run_cli(root)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("runway.md", res.stdout)

    def test_unauthorized_file_and_reserved_slot_handling(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_playbooks(root)

            reserved = root / "playbook" / "1_control" / "asa.md"
            reserved.write_text(MINIMAL_PLAYBOOK_BODY, encoding="utf-8")
            res_default = _run_cli(root)
            self.assertNotEqual(res_default.returncode, 0)
            self.assertIn("Unauthorized playbook file", res_default.stdout)

            res_allowed = _run_cli(root, "--allow-reserved")
            self.assertEqual(res_allowed.returncode, 0, res_allowed.stdout + res_allowed.stderr)

            random_file = root / "playbook" / "0_infra" / "random.md"
            random_file.write_text(MINIMAL_PLAYBOOK_BODY, encoding="utf-8")
            res_random = _run_cli(root, "--allow-reserved")
            self.assertNotEqual(res_random.returncode, 0)
            self.assertIn("Unauthorized playbook file", res_random.stdout)

    def test_missing_or_out_of_order_section_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            missing_sec_body = MINIMAL_PLAYBOOK_BODY.replace(
                "## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)\n채널 설정.\n\n", ""
            )
            _build_synthetic_playbooks(root, {"playbook/1_control/vas.md": missing_sec_body})
            res_missing = _run_cli(root)
            self.assertNotEqual(res_missing.returncode, 0)

            reordered_body = MINIMAL_PLAYBOOK_BODY.replace(
                "## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)\n배치 지침.\n\n"
                "## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)\n채널 설정.",
                "## 4. RF 모뎀 및 채널/네트워크 설정 (Modem & Channels)\n채널 설정.\n\n"
                "## 3. 물리 설치 및 블록 배치 지침 (Physical Placement)\n배치 지침.",
            )
            _build_synthetic_playbooks(root, {"playbook/1_control/vas.md": reordered_body})
            res_reordered = _run_cli(root)
            self.assertNotEqual(res_reordered.returncode, 0)

    def test_broken_relative_link_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            broken_body = MINIMAL_PLAYBOOK_BODY + "\n참고: [broken](../does_not_exist.md)\n"
            _build_synthetic_playbooks(root, {"playbook/0_infra/gps.md": broken_body})
            res = _run_cli(root)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("does_not_exist.md", res.stdout)

    def test_readme_missing_required_link_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_playbooks(
                root, {"playbook/README.md": "# Playbook Index\n\n- [gps](0_infra/gps.md)\n"}
            )
            res = _run_cli(root)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("README.md", res.stdout)

    def test_overclaim_inline_badge_and_banned_mod_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            overclaim_body = MINIMAL_PLAYBOOK_BODY + "\n완벽한 제어를 guarantee 합니다.\n"
            _build_synthetic_playbooks(root, {"playbook/2_guidance/fcp.md": overclaim_body})
            res_over = _run_cli(root)
            self.assertNotEqual(res_over.returncode, 0)

            badge_body = MINIMAL_PLAYBOOK_BODY + "\n[SPEC.md](../docs/specs/x.md) v1.0.0\n"
            _build_synthetic_playbooks(root, {"playbook/2_guidance/fcp.md": badge_body})
            res_badge = _run_cli(root)
            self.assertNotEqual(res_badge.returncode, 0)

            mod_body = MINIMAL_PLAYBOOK_BODY + "\nvalkyrien 블록을 연결합니다.\n"
            _build_synthetic_playbooks(root, {"playbook/2_guidance/fcp.md": mod_body})
            res_mod = _run_cli(root)
            self.assertNotEqual(res_mod.returncode, 0)

    def test_json_output_format(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _build_synthetic_playbooks(root)
            res = _run_cli(root, "--json")
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            payload = json.loads(res.stdout)
            self.assertEqual(payload["errors"], 0)
            self.assertEqual(payload["warnings"], 0)
            self.assertEqual(payload["requiredCount"], 16)


if __name__ == "__main__":
    unittest.main()
