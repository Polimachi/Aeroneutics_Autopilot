"""Static integrity and authorization scanner for Create_Aeroneutics playbooks."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from harness.unit.static_guard import PROHIBITED_MOD_TOKENS, _matches_prohibited_token
from tools.verify_all_specs import find_inline_peer_version_badges
from tools.verify_context_docs import check_overclaim

REQUIRED_PLAYBOOKS: tuple[str, ...] = (
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

RESERVED_EXPANSION_SLOTS: dict[str, str] = {
    "playbook/1_control/asa.md": "TASK-105 / TASK-210",
    "playbook/0_infra/docking_arm.md": "TASK-104",
    "playbook/0_infra/tower_atc.md": "TASK-108",
}

EXPECTED_SECTION_ORDER: list[int] = [1, 2, 3, 4, 5, 6, 7]
_SECTION_HEADING_RE = re.compile(r"^##\s+(\d+)\.\s+\S")
_LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
_FENCE_RE = re.compile(r"^(```|~~~)")


@dataclass(frozen=True)
class PlaybookFinding:
    rule: str
    path: str
    line: int
    message: str

    def format(self) -> str:
        return f"[{self.rule}] {self.path}:L{self.line}: {self.message}"


def _non_fenced_lines(text: str) -> list[tuple[int, str]]:
    """Return (1-based line_no, line) pairs outside fenced code blocks."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for line_no, raw in enumerate(text.splitlines(), 1):
        stripped = raw.strip()
        if _FENCE_RE.match(stripped):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append((line_no, raw))
    return out


def _check_relative_links(
    text: str, doc_path: Path, rel_path: str
) -> tuple[list[PlaybookFinding], set[Path]]:
    """Validate relative markdown links and return resolved existing target paths."""
    findings: list[PlaybookFinding] = []
    resolved_targets: set[Path] = set()
    doc_dir = doc_path.parent
    for line_no, line in _non_fenced_lines(text):
        for _, link in _LINK_RE.findall(line):
            if (
                link.startswith("http://")
                or link.startswith("https://")
                or link.startswith("#")
                or link.startswith("mailto:")
            ):
                continue
            clean = link.split("#", 1)[0].strip()
            if not clean:
                continue
            target = (doc_dir / clean).resolve()
            if not target.exists():
                findings.append(
                    PlaybookFinding(
                        "LINK",
                        rel_path,
                        line_no,
                        f"broken relative link '{clean}' -> '{target}' not found",
                    )
                )
            else:
                resolved_targets.add(target)
    return findings, resolved_targets


def _check_common_hygiene(text: str, rel_path: str) -> list[PlaybookFinding]:
    """Check overclaim terms, Rule 10 inline peer version badges, and banned mod tokens."""
    findings: list[PlaybookFinding] = []
    for f in check_overclaim(text, rel_path):
        findings.append(PlaybookFinding("OVERCLAIM", rel_path, f.line, f.message))

    for line_no, snippet in find_inline_peer_version_badges(text, rel_path):
        findings.append(
            PlaybookFinding(
                "RULE10",
                rel_path,
                line_no,
                f"inline peer version badge forbidden: {snippet[:80]}",
            )
        )

    for line_no, raw in enumerate(text.splitlines(), 1):
        lower_line = raw.lower()
        for tok in PROHIBITED_MOD_TOKENS:
            if _matches_prohibited_token(lower_line, tok):
                findings.append(
                    PlaybookFinding(
                        "BANNED_MOD",
                        rel_path,
                        line_no,
                        f"prohibited mod token '{tok}' detected",
                    )
                )
                break
    return findings


def _check_seven_sections(text: str, rel_path: str) -> list[PlaybookFinding]:
    """Verify required 7 sections (## 1. .. ## 7.) appear in exact order."""
    found: list[tuple[int, int]] = []
    for line_no, line in _non_fenced_lines(text):
        m = _SECTION_HEADING_RE.match(line.strip())
        if m:
            found.append((line_no, int(m.group(1))))

    found_nums = [num for _, num in found]
    if found_nums == EXPECTED_SECTION_ORDER:
        return []

    first_line = found[0][0] if found else 1
    return [
        PlaybookFinding(
            "SECTIONS",
            rel_path,
            first_line,
            f"expected ordered 7 sections {EXPECTED_SECTION_ORDER}, got {found_nums}",
        )
    ]


def verify_playbooks(
    repo_root: Path, allow_reserved: bool = False
) -> tuple[list[PlaybookFinding], int, int]:
    """Scan playbook/ under repo_root and return (findings, error_count, warning_count)."""
    findings: list[PlaybookFinding] = []
    playbook_dir = repo_root / "playbook"
    if not playbook_dir.is_dir():
        findings.append(
            PlaybookFinding("MISSING", "playbook/", 1, "playbook directory does not exist")
        )
        return findings, len(findings), 0

    allowed_set = set(REQUIRED_PLAYBOOKS) | {"playbook/README.md"}
    if allow_reserved:
        allowed_set |= set(RESERVED_EXPANSION_SLOTS)

    disk_md = sorted(
        p.relative_to(repo_root).as_posix() for p in playbook_dir.rglob("*.md")
    )
    for rel in disk_md:
        if rel not in allowed_set:
            hint = (
                f" (reserved for {RESERVED_EXPANSION_SLOTS[rel]}; pass --allow-reserved to permit)"
                if rel in RESERVED_EXPANSION_SLOTS
                else ""
            )
            findings.append(
                PlaybookFinding(
                    "UNAUTHORIZED",
                    rel,
                    1,
                    f"Unauthorized playbook file '{rel}'{hint}",
                )
            )

    readme_rel = "playbook/README.md"
    readme_path = repo_root / readme_rel
    readme_targets: set[Path] = set()
    if not readme_path.is_file():
        findings.append(PlaybookFinding("MISSING", readme_rel, 1, "missing playbook/README.md"))
    else:
        readme_text = readme_path.read_text(encoding="utf-8-sig")
        link_findings, readme_targets = _check_relative_links(
            readme_text, readme_path, readme_rel
        )
        findings.extend(link_findings)
        findings.extend(_check_common_hygiene(readme_text, readme_rel))

    present_playbooks: list[str] = []
    for rel in REQUIRED_PLAYBOOKS:
        path = repo_root / rel
        if not path.is_file():
            findings.append(
                PlaybookFinding("MISSING", rel, 1, f"missing required playbook '{rel}'")
            )
            continue
        present_playbooks.append(rel)
        if readme_path.is_file() and path.resolve() not in readme_targets:
            findings.append(
                PlaybookFinding(
                    "INDEX",
                    readme_rel,
                    1,
                    f"playbook/README.md is missing link to '{rel}'",
                )
            )

    if allow_reserved:
        for rel in sorted(RESERVED_EXPANSION_SLOTS):
            if (repo_root / rel).is_file():
                present_playbooks.append(rel)

    for rel in present_playbooks:
        path = repo_root / rel
        text = path.read_text(encoding="utf-8-sig")
        findings.extend(_check_seven_sections(text, rel))
        link_findings, _ = _check_relative_links(text, path, rel)
        findings.extend(link_findings)
        findings.extend(_check_common_hygiene(text, rel))

    return findings, len(findings), 0


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(
        description="Verify Create_Aeroneutics playbooks structure, authorization, and links."
    )
    parser.add_argument("--root", type=str, default=None, help="Repository root override")
    parser.add_argument(
        "--allow-reserved",
        action="store_true",
        help="Permit reserved expansion slots (e.g., pocket_pda.md, asa.md)",
    )
    parser.add_argument("--json", action="store_true", help="Emit findings as JSON")
    args = parser.parse_args(argv)

    repo_root = Path(args.root).resolve() if args.root else REPO_ROOT
    findings, errors, warnings = verify_playbooks(
        repo_root, allow_reserved=args.allow_reserved
    )

    if args.json:
        payload = {
            "requiredCount": len(REQUIRED_PLAYBOOKS),
            "errors": errors,
            "warnings": warnings,
            "findings": [asdict(f) for f in findings],
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 1 if errors > 0 else 0

    if errors == 0 and warnings == 0:
        print(
            f"SCAN RESULT: ALL {len(REQUIRED_PLAYBOOKS)} PLAYBOOKS & README CLEAN "
            f"({errors} Errors, {warnings} Warnings)"
        )
        return 0

    print(f"[FAIL] playbook verification: {errors} Errors, {warnings} Warnings")
    for f in findings:
        print("  " + f.format())
    return 1


if __name__ == "__main__":
    sys.exit(main())
