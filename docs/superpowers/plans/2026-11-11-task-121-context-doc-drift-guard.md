# TASK-121 Context Document Drift Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 에이전트가 개별 작업을 끝내려는 시점에 루트 컨텍스트 문서(`README.md`, `GEMINI.md`, `TASK.md`, `.agent/memory/*.md`)의 어긋남을 자동으로 검출하고, 수정할 때까지 턴 종료를 보류시킨다.

**Architecture:** 읽기 전용 검사기 `tools/verify_context_docs.py`가 8개 규칙을 판정한다. Antigravity `Stop` 훅(`.agent/hooks/context_doc_guard.py`)은 이번 대화에서 저장소가 바뀐 경우(작업 트리 dirty 또는 `SessionStart` 기준 HEAD 이후 커밋 발생)에만 검사기를 import해 실행하고, 위반이 있으면 `{"decision": "continue"}`로 에이전트를 루프에 되돌린다. 같은 위반 서명에 대한 강제 재개는 대화당 2회로 제한하며, 훅 내부 오류는 항상 종료 허용(fail-open)으로 처리한다.

**Tech Stack:** Python 3.10+ 표준 라이브러리만 사용 (`re`, `json`, `hashlib`, `subprocess`, `dataclasses`, `unittest`), Antigravity `hooks.json` (`SessionStart`, `Stop`, `PreToolUse`).

**Spec:** 별도 설계 문서 없음. 2026-11-10 대화에서 **접근법 B**(검사 스크립트 + `Stop` 훅 강제)를 사용자가 선택했으며, 결정 사항은 아래 `Design Decisions`에 기록한다. 원인 분석 근거는 `.agent/memory/workspace-root.md`의 `2026-11-10 — 루트 4대 마크다운 Mode B 감사` 항목.

## Design Decisions

| # | 결정 | 근거 |
| :-- | :--- | :--- |
| D1 | 테스트 수치 SSOT는 `GEMINI.md` §3 하나. `README.md`에는 `N/M PASS` 형태 수치를 두지 않는다 | 3중 수기 관리가 감사 시 README 낡음의 원인 |
| D2 | `TASK.md` 완료 이력의 모든 `TASK-ID`는 `.agent/memory/*.md`의 `## YYYY-MM-DD — ...` 제목에 등장해야 한다 | Mode A가 "구조 변경" 조건이라 기능 태스크 9개 누락 |
| D3 | 과장 금지어 목록은 `AGENTS.md` `no-overclaim` 절의 금지 예를 그대로 복제한다. `AGENTS.md` 자체는 검사 대상에서 제외 | 목록 정의 문서가 자기 자신에 걸리지 않도록 |
| D4 | `TASK.md`에서 `` `docs/(specs|system)/...md` `` 경로 바로 뒤 버전/상태 표기만 실제 메타데이터와 대조한다 | 경로 없는 서술형 버전 언급은 오탐 위험이 커서 제외 (한계로 명시) |
| D5 | 훅 트리거 = 작업 트리 dirty **또는** HEAD ≠ `SessionStart` 기준 HEAD (단, 직전 통과 HEAD와 같으면 제외) | 이 저장소는 태스크마다 커밋하므로 dirty 조건만으로는 커밋 후 종료 시 검사가 빠짐 |
| D6 | 동일 위반 서명(SHA-1)당 강제 재개 최대 2회, 이후 종료 허용 | 브레인스토밍·Q&A 턴에서 사용자 소유 변경 때문에 무한 루프가 나지 않도록 |
| D7 | 훅 예외·git 부재·잘못된 stdin은 모두 종료 허용 / `{}` 반환 | 훅 버그가 에이전트를 가두면 안 됨 |
| D8 | 기존 `block_dangerous_git.py`를 같은 `hooks.json`에 `PreToolUse`로 등록 (스크립트 로직은 수정하지 않음) | 감사 중 미등록 상태로 발견됨. 사용자가 B안에서 동시 등록 허용 |

## Global Constraints

- Python 3.10+ 표준 라이브러리만 사용. 외부 패키지 추가 금지.
- 기본 셸은 Windows PowerShell 5.1: 명령 체이닝은 `; if ($?) { ... }`, `&&` 금지.
- Git은 PATH 미등록: 코드에서는 `shutil.which("git")` 실패 시 `C:\Program Files\Git\cmd\git.exe`로 대체. 계획서 명령은 `& "C:\Program Files\Git\cmd\git.exe" ...`.
- 훅 `command`는 Windows에서 `cmd /c`로 실행되고 작업 디렉토리는 `hooks.json`이 있는 `.agent/`이다.
- 검사기는 읽기 전용: 어떤 파일도 쓰지 않는다. 훅의 유일한 쓰기 대상은 `.runtime/context_doc_guard_state.json` (`.gitignore` 등록된 `.runtime/`).
- `src/`, `docs/specs/`, `docs/system/`은 수정하지 않는다 (Lua 스킬·`specification-lifecycle-manager` 비발동).
- 출력 메시지·문서에 `AGENTS.md` 과장 금지 규칙 적용 (측정 근거 없는 성능 주장 금지).
- 파일 읽기는 `encoding="utf-8-sig"` + `str.splitlines()` (CRLF/BOM 혼재 대응).

## Review Focus

1. **사용자 소유 미커밋 변경이 있는 상태의 대화·계획 턴** → 같은 위반으로 3번째 종료 시도는 허용되어야 함 (Task 3 `test_stop_allows_after_two_continues_for_same_signature`).
2. **훅 내부 예외, git 실행 파일 없음, 비 JSON stdin** → 종료 허용 (Task 3 `test_main_fails_open_on_bad_stdin`, `test_stop_fails_open_when_checks_raise`).
3. **커밋 직후 깨끗한 작업 트리로 종료** → 기준 HEAD와 다르면 검사 실행 (Task 3 `test_stop_checks_when_head_moved_since_session_start`).
4. **CRLF·BOM이 섞인 한국어 문서** → 줄 번호와 판정이 LF 문서와 동일 (Task 1 `test_markers_crlf_input`).
5. **TASK.md가 존재하지 않는 사양서 경로를 참조** → 크래시 없이 `missing spec file` 위반 1건 (Task 2 `test_spec_version_missing_file`).

---

## File Structure

| 파일 | 상태 | 책임 |
| :--- | :--- | :--- |
| `tools/verify_context_docs.py` | Create | 8개 규칙 판정, `run_all`, CLI (`--json`) |
| `tests/harness/test_context_docs.py` | Create | 규칙별 픽스처 단위 테스트 + 실저장소 0건 회귀 |
| `.agent/hooks/context_doc_guard.py` | Create | `session-start`/`stop` 훅 진입점, 트리거·루프 상한·상태 파일 |
| `tests/harness/test_context_doc_guard_hook.py` | Create | 가짜 git으로 훅 판정 테스트 |
| `.agent/hooks.json` | Create | `context-doc-guard`(SessionStart, Stop) + `git-guardrails`(PreToolUse) 등록 |
| `tests/harness/test_tools_integrity.py` | Modify | `expected_tools`에 `verify_context_docs.py` 추가 |
| `.agent/skills/verification-before-completion/SKILL.md` | Modify | 5-Step Gate에 검사기 실행 단계 추가 |
| `.agent/skills/md-management/SKILL.md` | Modify | Mode A 트리거를 "TASK-ID 완료마다 메모리 기록"으로 확장 |
| `.agent/rules/skill-workflows.md` | Modify | 완료 보고 절에 검사기·훅 1줄 |
| `GEMINI.md`, `TASK.md`, `.agent/memory/workspace-root.md` | Modify | 표준 명령·Gotcha·태스크 종결·이력 (Mode A) |

---

### Task 1: 검사기 — 단일 문서 규칙 (R1 README 수치, R2 과장 금지어, R3 GEMINI 구조, R6 TASK 마커, R7 완료 이력 상한)

**Files:**
- Create: `tools/verify_context_docs.py`
- Test: `tests/harness/test_context_docs.py`

**Interfaces:**
- Produces:
  - `@dataclass(frozen=True) class Finding: rule: str; path: str; line: int; message: str` + `def format(self) -> str` → `"[{rule}] {path}:L{line}: {message}"`
  - 상수: `MAX_GEMINI_LINES = 80`, `ARCHIVE_CAP = 10`, `GEMINI_SECTIONS = ("## 1. Current Phase & Active Handover", "## 2. Confirmed Architecture & Paths", "## 3. Standard Commands", "## 4. Gotchas & Invariants")`, `BANNED_TERMS = ("세계 최고 수준", "최고 수준", "무결점", "완벽", "원천 차단", "무오염", "100% 보장", "world-class", "best-in-class", "flawless", "zero-defect", "bulletproof")`, `GUARANTEE_RE = re.compile(r"\bguarantee[sd]?\b", re.IGNORECASE)`
  - `check_readme_counts(text: str, path: str = "README.md") -> list[Finding]` — rule `R1`, 패턴 `\b\d+/\d+\s*(?:PASS|KILLED|passed)\b`
  - `check_overclaim(text: str, path: str) -> list[Finding]` — rule `R2`, 줄·용어당 1건 (`"세계 최고 수준"` 줄에서 `"최고 수준"` 중복 보고 금지: 더 긴 용어가 매치되면 그 부분 문자열 용어는 건너뜀)
  - `check_gemini_structure(text: str, path: str = "GEMINI.md") -> list[Finding]` — rule `R3`, 줄 수 > 80이면 1건, `## ` 제목 목록 ≠ `GEMINI_SECTIONS`이면 1건
  - `check_task_markers(text: str, path: str = "TASK.md") -> list[Finding]` — rule `R6`. 부모 = `^- \[( |-|x)\] \*\*(?:\[연기\] )?TASK-(\d+)\b`, 자식 = `^\s+- \[( |-|x)\] \*\*TASK-(\d+)-\d+` (직전 부모에 귀속). 위반: 부모 `[ ]`인데 자식 중 `[x]` 존재 → "parent should be [-]"; 부모 `[x]`인데 자식 중 `[ ]`/`[-]` 존재 → "parent closed with open child". 위반 줄 = 부모 줄.
  - `check_task_archive_cap(text: str, path: str = "TASK.md") -> list[Finding]` — rule `R7`. `## ✅ 3.`로 시작하는 줄부터 다음 `## ` 전까지 `^- \[x\] \*\*TASK-\d+` 개수 > 10이면 1건
  - `archived_task_ids(text: str) -> list[str]` — R7과 같은 구간의 `TASK-NNN` 목록 (Task 2가 사용)

- [ ] **Step 1: 실패 테스트 작성** — `tests/harness/test_context_docs.py`, `sys.path`에 `REPO_ROOT / "tools"` 추가 후 `import verify_context_docs as vcd`

```python
class TestSingleDocRules(unittest.TestCase):
    def test_readme_counts_flags_pass_ratio(self):
        f = vcd.check_readme_counts("x\n단위 `294/294 PASS`\n")
        self.assertEqual([(x.rule, x.line) for x in f], [("R1", 2)])

    def test_readme_counts_ignores_dates_and_paths(self):
        self.assertEqual(vcd.check_readme_counts("2026/11/10 a/b c 12/34"), [])

    def test_overclaim_reports_longest_term_once(self):
        f = vcd.check_overclaim("세계 최고 수준 달성\n", "TASK.md")
        self.assertEqual(len(f), 1)
        self.assertIn("세계 최고 수준", f[0].message)

    def test_overclaim_guarantee_case_insensitive(self):
        self.assertEqual(len(vcd.check_overclaim("We GUARANTEED it", "README.md")), 1)

    def test_gemini_structure_line_cap(self):
        body = "\n".join(vcd.GEMINI_SECTIONS) + "\n" + "x\n" * 80
        self.assertEqual([x.rule for x in vcd.check_gemini_structure(body)], ["R3"])

    def test_gemini_structure_section_mismatch(self):
        body = "## 1. Current Phase & Active Handover\n## 3. Standard Commands\n"
        self.assertEqual(len(vcd.check_gemini_structure(body)), 1)

    def test_markers_open_parent_with_done_child(self):
        t = "- [ ] **TASK-114: x**\n  - [x] **TASK-114-1**: a\n  - [ ] **TASK-114-2**: b\n"
        f = vcd.check_task_markers(t)
        self.assertEqual([(x.rule, x.line) for x in f], [("R6", 1)])

    def test_markers_closed_parent_with_open_child(self):
        t = "- [x] **TASK-009: x**\n    - [ ] **TASK-009-1**: a\n"
        self.assertEqual(len(vcd.check_task_markers(t)), 1)

    def test_markers_deferred_parent_and_in_progress_ok(self):
        t = "- [ ] **[연기] TASK-104: x**\n- [-] **TASK-201: y**\n  - [x] **TASK-201-1**: a\n"
        self.assertEqual(vcd.check_task_markers(t), [])

    def test_markers_crlf_input(self):
        t = "- [ ] **TASK-114: x**\r\n  - [x] **TASK-114-1**: a\r\n"
        self.assertEqual([x.line for x in vcd.check_task_markers(t)], [1])

    def test_archive_cap(self):
        items = "".join(f"- [x] **TASK-{i:03d}: t**\n" for i in range(11))
        t = "## ✅ 3. 완료\n" + items + "## 4. other\n- [x] **TASK-999: z**\n"
        self.assertEqual([x.rule for x in vcd.check_task_archive_cap(t)], ["R7"])
        self.assertEqual(len(vcd.archived_task_ids(t)), 11)
```

- [ ] **Step 2: 실패 확인**

Run: `python -m unittest tests.harness.test_context_docs -v`
Expected: `ModuleNotFoundError: No module named 'verify_context_docs'`

- [ ] **Step 3: 위 Interfaces의 상수·`Finding`·6개 함수를 `tools/verify_context_docs.py`에 구현**

모든 함수는 입력 문자열을 `splitlines()`로 처리하고 줄 번호는 1부터.

- [ ] **Step 4: 통과 확인**

Run: `python -m unittest tests.harness.test_context_docs -v`
Expected: `Ran 11 tests ... OK`

- [ ] **Step 5: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/verify_context_docs.py tests/harness/test_context_docs.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): add single-document context drift rules (TASK-121-1)"
```

---

### Task 2: 검사기 — 교차 참조 규칙 (R4 사양서 분포, R5 사양서 버전, R8 메모리 커버리지) + `run_all`/CLI + 실저장소 회귀

**Files:**
- Modify: `tools/verify_context_docs.py`
- Modify: `tests/harness/test_context_docs.py`
- Modify: `tests/harness/test_tools_integrity.py` (`expected_tools` 목록에 `WORKSPACE_ROOT / "tools" / "verify_context_docs.py"` 1줄)

**Interfaces:**
- Consumes: Task 1의 `Finding`, `archived_task_ids`, 모든 `check_*`
- Produces:
  - `read_spec_meta(path: Path) -> tuple[str, str] | None` — 메타데이터 표에서 `(version, status)`. 버전 패턴 `\|\s*\*\*문서 버전 \(Version\)\*\*\s*\|\s*` + 백틱 `(v\d+\.\d+\.\d+)`, 상태 패턴은 `tools/verify_spec_status.py`의 `status_pat`과 동일 문자열.
  - `iter_spec_files(repo_root: Path) -> list[Path]` — `docs/system/*.md` + `docs/specs/**/*.md`, 파일명 `README.md` 제외, 정렬.
  - `check_gemini_spec_distribution(gemini_text: str, repo_root: Path) -> list[Finding]` — rule `R4`. GEMINI의 `(\d+) Implemented, (\d+) Approved`를 실제 상태 개수와 비교. 패턴이 없으면 1건.
  - `check_task_spec_versions(task_text: str, repo_root: Path, path: str = "TASK.md") -> list[Finding]` — rule `R5`. 패턴 `` `(docs/(?:specs|system)/[^`]+\.md)`\s*\(?(?:현재\s+)?(v\d+\.\d+\.\d+)(?:\s+(Draft|Approved|Implemented|Deprecated))? ``. 버전 불일치 1건, 상태가 표기된 경우 상태 불일치 1건, 파일 없음이면 `missing spec file` 1건.
  - `memory_heading_task_ids(memory_texts: dict[str, str]) -> set[str]` — `^## \d{4}-\d{2}-\d{2} — ` 제목 줄의 모든 `TASK-\d+`.
  - `check_memory_coverage(task_text: str, memory_texts: dict[str, str], path: str = "TASK.md") -> list[Finding]` — rule `R8`. `archived_task_ids` 중 메모리 제목에 없는 ID마다 1건.
  - `run_all(repo_root: Path) -> list[Finding]` — 대상: `README.md`(R1, R2), `GEMINI.md`(R2, R3, R4), `TASK.md`(R2, R5, R6, R7, R8), `.agent/memory/*.md`(R2). `AGENTS.md`는 대상 아님.
  - `main(argv: list[str] | None = None) -> int` — 위반 0건이면 `[PASS] context docs: 0 findings` 출력 후 0, 아니면 `[FAIL] context docs: N findings` + 각 `format()` 후 1. `--json`이면 `[{"rule","path","line","message"}, ...]` JSON 배열만 출력.

- [ ] **Step 1: 실패 테스트 추가** (임시 디렉토리 픽스처는 `tempfile.TemporaryDirectory`)

```python
SPEC = "| **문서 상태 (Status)** | `Implemented` |\n| **문서 버전 (Version)** | `v1.15.0` |\n"

class TestCrossRefRules(unittest.TestCase):
    def _repo(self, tmp):
        root = Path(tmp); d = root / "docs/specs/2_guidance/fcp"; d.mkdir(parents=True)
        (d / "FCP.md").write_text(SPEC, encoding="utf-8")
        (root / "docs/system").mkdir(parents=True)
        return root

    def test_spec_version_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            t = "- **사양서 상태**: `docs/specs/2_guidance/fcp/FCP.md` (v1.16.0 Approved)\n"
            rules = [(x.rule, x.line) for x in vcd.check_task_spec_versions(t, root)]
            self.assertEqual(rules, [("R5", 1), ("R5", 1)])

    def test_spec_version_current_prefix_ok(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            t = "`docs/specs/2_guidance/fcp/FCP.md` (현재 v1.15.0 Implemented → 목표 v1.16.0 Approved)\n"
            self.assertEqual(vcd.check_task_spec_versions(t, root), [])

    def test_spec_version_missing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            f = vcd.check_task_spec_versions("`docs/specs/x/NOPE.md` (v1.0.0)\n", root)
            self.assertEqual(len(f), 1); self.assertIn("missing spec file", f[0].message)

    def test_gemini_distribution(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._repo(tmp)
            self.assertEqual(vcd.check_gemini_spec_distribution("(1 Implemented, 0 Approved)", root), [])
            self.assertEqual(len(vcd.check_gemini_spec_distribution("(2 Implemented, 0 Approved)", root)), 1)
            self.assertEqual(len(vcd.check_gemini_spec_distribution("no counts", root)), 1)

    def test_memory_coverage(self):
        t = "## ✅ 3. 완료\n- [x] **TASK-009: a**\n- [x] **TASK-116: b**\n"
        mem = {"workspace-root.md": "## 2026-11-10 — 인스톨러 개편 (TASK-116)\n본문 TASK-009\n"}
        f = vcd.check_memory_coverage(t, mem)
        self.assertEqual([x.rule for x in f], ["R8"]); self.assertIn("TASK-009", f[0].message)

class TestRepositoryBaseline(unittest.TestCase):
    def test_repository_has_no_context_drift(self):
        findings = vcd.run_all(REPO_ROOT)
        self.assertEqual(findings, [], "\n".join(x.format() for x in findings))

    def test_cli_json_exit_code(self):
        r = subprocess.run([sys.executable, str(REPO_ROOT / "tools/verify_context_docs.py"), "--json"],
                           capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(r.returncode, 0, r.stdout); self.assertEqual(json.loads(r.stdout), [])
```

- [ ] **Step 2: 실패 확인**

Run: `python -m unittest tests.harness.test_context_docs -v`
Expected: `AttributeError: module 'verify_context_docs' has no attribute 'check_task_spec_versions'` 등 FAIL/ERROR

- [ ] **Step 3: Interfaces의 함수와 `run_all`, `main`, `if __name__ == "__main__": sys.exit(main())` 구현**

- [ ] **Step 4: 통과 확인 + 실저장소 위반 처리**

Run: `python -m unittest tests.harness.test_context_docs -v`
Expected: `Ran 18 tests ... OK`.
`test_repository_has_no_context_drift`가 실패하면 출력된 위반이 **실제 문서 어긋남인지 오탐인지** 판정한다: 실제 어긋남이면 해당 문서를 고치고, 오탐이면 규칙 패턴을 좁히고 오탐 사례를 픽스처 테스트로 추가한다. 금지 규칙을 끄는 방식으로 통과시키지 않는다.

- [ ] **Step 5: 하네스 전체 회귀**

Run: `python -m unittest discover -s tests/harness -p "test_*.py"`
Expected: 기존 50개 + 신규 18개 = `Ran 68 tests ... OK`

- [ ] **Step 6: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add tools/verify_context_docs.py tests/harness/test_context_docs.py tests/harness/test_tools_integrity.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(tools): add cross-reference context drift rules and CLI (TASK-121-2)"
```

---

### Task 3: `Stop`/`SessionStart` 훅 스크립트

**Files:**
- Create: `.agent/hooks/context_doc_guard.py`
- Test: `tests/harness/test_context_doc_guard_hook.py` (`importlib.util.spec_from_file_location`으로 로드)

**Interfaces:**
- Consumes: `verify_context_docs.run_all(repo_root) -> list[Finding]`, `Finding.format()`
- Produces:
  - 상수: `REPO_ROOT = Path(__file__).resolve().parents[2]`, `STATE_PATH = REPO_ROOT / ".runtime" / "context_doc_guard_state.json"`, `MAX_CONTINUES = 2`, `MAX_LISTED = 10`
  - `class GitProbe(Protocol): def head(self) -> str | None; def is_dirty(self) -> bool`
  - `class SubprocessGit` — `__init__(self, repo_root: Path)`; git 실행 파일은 `shutil.which("git") or r"C:\Program Files\Git\cmd\git.exe"`; `head()`는 `rev-parse HEAD`, `is_dirty()`는 `status --porcelain` 출력 비어있지 않음. 실패 시 `None` / `False`.
  - `load_state(path: Path) -> dict` (없거나 손상 시 `{}`), `save_state(path: Path, state: dict) -> None` (부모 디렉토리 생성)
  - `handle_session_start(payload: dict, state: dict, git: GitProbe) -> dict` — `state[conversationId] = {"baseline": git.head(), "lastCleanHead": None, "continues": {}}`, 반환 `{}`
  - `handle_stop(payload: dict, state: dict, git: GitProbe, run_checks: Callable[[], list]) -> dict`
    1. `terminationReason != "NO_TOOL_CALL"` 또는 `fullyIdle is False` → `{"decision": "allow"}`
    2. 항목이 없으면 `{"baseline": None, "lastCleanHead": None, "continues": {}}`로 생성
    3. `triggered = dirty or (baseline is not None and head != baseline and head != lastCleanHead)`; 아니면 allow
    4. `run_checks()` 예외 → allow. 위반 0건 → `dirty`가 아니면 `lastCleanHead = head`, allow
    5. 서명 = 위반 `format()`을 정렬·개행 결합한 SHA-1. 횟수 ≥ `MAX_CONTINUES` → allow. 아니면 +1 후 `{"decision": "continue", "reason": ...}`
  - `reason` 문구 (정확히):
    ```text
    [context-doc-guard] 컨텍스트 문서 정합성 위반 {n}건.
    - 이번 작업에서 생긴 위반이면 지금 수정하고 `python tools/verify_context_docs.py` 결과 0 findings를 확인한 뒤 종료하세요.
    - 이번 작업과 무관한 기존 위반이거나 현재 단계(계획·브레인스토밍·Q&A)에서 수정할 수 없으면, 사용자에게 한 줄로 보고하고 종료하세요.
    {최대 10개 finding.format() 줄, 초과 시 "... 외 {k}건"}
    ```
  - `main(argv: list[str] | None = None) -> int` — 모드 `session-start` | `stop`. stdin JSON 파싱 → 상태 로드 → 핸들러 → 상태 저장 → stdout JSON. **모든 예외**에서 `session-start`는 `{}`, `stop`은 `{"decision": "allow"}` 출력 후 0 반환.

- [ ] **Step 1: 실패 테스트 작성** — `FakeGit(head: str | None, dirty: bool)` 픽스처와 `FINDING = vcd.Finding("R1", "README.md", 3, "count")` 사용

```python
def stop_payload(reason="NO_TOOL_CALL", idle=True):
    return {"conversationId": "c1", "terminationReason": reason, "fullyIdle": idle}

class TestStopHook(unittest.TestCase):
    def test_allows_non_normal_termination(self):
        self.assertEqual(hook.handle_stop(stop_payload("USER_CANCELED"), {}, FakeGit("a", True), lambda: [FINDING])["decision"], "allow")

    def test_allows_when_background_busy(self):
        self.assertEqual(hook.handle_stop(stop_payload(idle=False), {}, FakeGit("a", True), lambda: [FINDING])["decision"], "allow")

    def test_skips_checks_when_repo_unchanged(self):
        state = {}; hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        called = []
        out = hook.handle_stop(stop_payload(), state, FakeGit("a", False), lambda: called.append(1) or [FINDING])
        self.assertEqual((out["decision"], called), ("allow", []))

    def test_continues_on_dirty_tree_with_findings(self):
        out = hook.handle_stop(stop_payload(), {}, FakeGit("a", True), lambda: [FINDING])
        self.assertEqual(out["decision"], "continue"); self.assertIn("[R1] README.md:L3", out["reason"])

    def test_stop_checks_when_head_moved_since_session_start(self):
        state = {}; hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        self.assertEqual(hook.handle_stop(stop_payload(), state, FakeGit("b", False), lambda: [FINDING])["decision"], "continue")

    def test_clean_pass_records_head_and_skips_next_time(self):
        state = {}; hook.handle_session_start({"conversationId": "c1"}, state, FakeGit("a", False))
        hook.handle_stop(stop_payload(), state, FakeGit("b", False), lambda: [])
        called = []
        hook.handle_stop(stop_payload(), state, FakeGit("b", False), lambda: called.append(1) or [])
        self.assertEqual(called, [])

    def test_stop_allows_after_two_continues_for_same_signature(self):
        state = {}; g = FakeGit("a", True)
        decisions = [hook.handle_stop(stop_payload(), state, g, lambda: [FINDING])["decision"] for _ in range(3)]
        self.assertEqual(decisions, ["continue", "continue", "allow"])

    def test_stop_fails_open_when_checks_raise(self):
        def boom(): raise RuntimeError("x")
        self.assertEqual(hook.handle_stop(stop_payload(), {}, FakeGit("a", True), boom)["decision"], "allow")

    def test_main_fails_open_on_bad_stdin(self):
        r = subprocess.run([sys.executable, str(HOOK_PATH), "stop"], input="not json",
                           capture_output=True, text=True, encoding="utf-8")
        self.assertEqual((r.returncode, json.loads(r.stdout)), (0, {"decision": "allow"}))

    def test_state_roundtrip_and_corrupt_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "s.json"; p.write_text("{bad", encoding="utf-8")
            self.assertEqual(hook.load_state(p), {})
            hook.save_state(p, {"c1": {"baseline": "a"}}); self.assertEqual(hook.load_state(p)["c1"]["baseline"], "a")
```

- [ ] **Step 2: 실패 확인**

Run: `python -m unittest tests.harness.test_context_doc_guard_hook -v`
Expected: `FileNotFoundError` 또는 로드 실패로 ERROR

- [ ] **Step 3: Interfaces대로 `.agent/hooks/context_doc_guard.py` 구현** — `verify_context_docs`는 `sys.path.insert(0, str(REPO_ROOT / "tools"))` 후 import

- [ ] **Step 4: 통과 확인**

Run: `python -m unittest tests.harness.test_context_doc_guard_hook -v`
Expected: `Ran 10 tests ... OK`

- [ ] **Step 5: 실행 시간 측정 (기록용, 판정 기준 아님)**

Run: `Measure-Command { '{"conversationId":"m","terminationReason":"NO_TOOL_CALL","fullyIdle":true}' | python .agent/hooks/context_doc_guard.py stop } | Select-Object TotalMilliseconds`
Expected: 측정값을 커밋 메시지 본문과 메모리 항목에 기록. 15초(`hooks.json` timeout)를 넘으면 중단하고 보고.

- [ ] **Step 6: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add .agent/hooks/context_doc_guard.py tests/harness/test_context_doc_guard_hook.py
& "C:\Program Files\Git\cmd\git.exe" commit -m "feat(hooks): add context doc drift Stop/SessionStart guard (TASK-121-3)"
```

---

### Task 4: `hooks.json` 등록 및 실환경 스모크

**Files:**
- Create: `.agent/hooks.json`

**Interfaces:**
- Consumes: Task 3 `context_doc_guard.py session-start|stop`, 기존 `.agent/hooks/block_dangerous_git.py` (수정 금지)

- [ ] **Step 1: `.agent/hooks.json` 작성**

```json
{
  "context-doc-guard": {
    "SessionStart": [
      { "type": "command", "command": "python hooks/context_doc_guard.py session-start", "timeout": 10 }
    ],
    "Stop": [
      { "type": "command", "command": "python hooks/context_doc_guard.py stop", "timeout": 15 }
    ]
  },
  "git-guardrails": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          { "type": "command", "command": "python hooks/block_dangerous_git.py", "timeout": 10 }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: JSON 유효성 확인**

Run: `python -c "import json; json.load(open('.agent/hooks.json', encoding='utf-8')); print('OK')"`
Expected: `OK`

- [ ] **Step 3: 커밋** (훅은 새 대화부터 로드되므로 스모크 전에 커밋)

```powershell
& "C:\Program Files\Git\cmd\git.exe" add .agent/hooks.json
& "C:\Program Files\Git\cmd\git.exe" commit -m "chore(hooks): register context doc guard and git guardrails hooks (TASK-121-4)"
```

- [ ] **Step 4: 실환경 스모크 — 사용자 수행 (새 대화 필요)**

사용자에게 아래 3가지를 새 대화에서 확인해 달라고 요청하고 결과를 받는다:
1. **드리프트 강제**: "README.md에 `단위 1/1 PASS` 한 줄 추가하고 끝내" → 에이전트가 종료 직전 `[context-doc-guard] ... [R1]` 사유로 재개되어 줄을 제거해야 함.
2. **git 가드**: "`git push --dry-run` 실행해" → `BLOCKED by git-guardrails` 거부.
3. **승인 프롬프트 회귀**: 평소 자동 실행되던 일반 명령(예: `git status -sb`)에서 **새 승인 창이 뜨지 않는지**.

3번에서 새 승인 창이 뜨면 `git-guardrails` 블록에 `"enabled": false`를 넣어 끄고, 사용자에게 보고한 뒤 결정을 받는다 (fallthrough `"ask"` 변경은 이 태스크 범위 밖).

---

### Task 5: 워크플로우 연동 및 컨텍스트 동기화

**Files:**
- Modify: `.agent/skills/verification-before-completion/SKILL.md` (5-Step Gate)
- Modify: `.agent/skills/md-management/SKILL.md` (`## 2. Mode A` 첫 문장)
- Modify: `.agent/rules/skill-workflows.md` (`작업 완료 보고 및 마일스톤 인계` 절)
- Modify: `GEMINI.md`, `TASK.md`, `.agent/memory/workspace-root.md`

- [ ] **Step 1: `verification-before-completion` Gate에 단계 추가** — `4. VERIFY` 다음에 삽입하고 이후 번호를 한 칸씩 민다:

```markdown
5. **CONTEXT DOCS**: Run `python tools/verify_context_docs.py`. Fix every finding caused by this task (memory entry, TASK.md markers, spec versions, README counts, banned terms) and re-run until `0 findings`. Report pre-existing findings in one line instead of fixing them out of scope.
```

- [ ] **Step 2: `md-management` Mode A 트리거 확장** — `## 2.` 제목 아래 "Run **only** after ..." 문장을 다음으로 교체:

```markdown
Run after **every TASK-ID completion** (append one `.agent/memory/<dir-slug>.md` entry whose heading contains the TASK-ID; enforced by `tools/verify_context_docs.py` rule R8). Update `GEMINI.md` only when phases, directory layout, standard CLI/harness commands, or key architectural gotchas change.
```

- [ ] **Step 3: `skill-workflows.md` 완료 절에 1줄 추가**

```markdown
  - 작업 완료 직전 `python tools/verify_context_docs.py`로 컨텍스트 문서 정합성을 확인한다. `.agent/hooks.json`의 `Stop` 훅이 위반 시 턴 종료를 보류한다 (동일 위반당 최대 2회).
```

- [ ] **Step 4: Mode A 컨텍스트 동기화 (`md-management` 호출)**
  - `GEMINI.md` §3에 `- **컨텍스트 문서 정합성**: \`python tools/verify_context_docs.py\` (0 findings, 규칙 R1~R8).` 추가, 하네스 회귀 수치를 Task 2·3 실측값으로 갱신.
  - `GEMINI.md` §4에 `- **컨텍스트 문서 Stop 훅**: \`.agent/hooks.json\`이 작업 종료 시 \`verify_context_docs\` 위반을 검사해 재개시킨다 (새 대화부터 적용, 동일 위반 2회 상한, 오류 시 종료 허용).` 추가 — 80줄 이하 유지.
  - `TASK.md`: TASK-121 하위 항목 `[x]`, 부모 `[x]`로 완료 이력 상단 이동, 11번째 항목 정리.
  - `.agent/memory/workspace-root.md`: `## 2026-11-11 — 컨텍스트 문서 드리프트 가드 구축 (TASK-121)` 항목 추가 (Task 3 Step 5 측정값 포함).

- [ ] **Step 5: 전체 검증**

Run:
```powershell
python tools/verify_context_docs.py; if ($?) { python -m unittest discover -s tests/harness -p "test_*.py" }; if ($?) { python tools/verify_all_specs.py }; if ($?) { python tools/verify_manifest_sync.py }
```
Expected: `[PASS] context docs: 0 findings`, 하네스 `OK`, 사양서 `0 Errors, 0 Warnings`, 매니페스트 `0 Errors, 0 Warnings`.

- [ ] **Step 6: 커밋**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add .agent/skills/verification-before-completion/SKILL.md .agent/skills/md-management/SKILL.md .agent/rules/skill-workflows.md GEMINI.md TASK.md .agent/memory/workspace-root.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(meta): wire context doc guard into completion workflow and close TASK-121"
```

---

## Known Limitations (의도적 범위 제외)

- 경로 없이 쓴 사양서 버전 언급(예: `GEMINI.md` §1 "FCP 사양서 v1.15.0")은 R5 대상이 아니다.
- `GEMINI.md` §3의 테스트 수치 자체가 실제 실행 결과와 맞는지는 검사하지 않는다 (훅에서 CraftOS 테스트를 돌리기엔 느림). 이 부분은 기존 `verification-before-completion`의 테스트 실행이 담당한다.
- 훅은 Antigravity 에이전트 세션에서만 동작한다. 사람이 직접 커밋한 변경은 하네스 회귀(`test_repository_has_no_context_drift`)로 잡힌다.
