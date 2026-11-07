# 전체 시스템 사양서 통합 리팩토링 구현 계획 (System Specifications Refactoring Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비행체 전용 40채널($BW=40$) 및 4대 Zone(코어, 구동계, 탑재체, 편대/확장) 전면 개편에 맞추어, 13종 시스템 사양서 전체의 기계적 치환 잔재(중첩된 DEPRECATED 배지, 어색한 문장)를 정제하고 메타데이터 인용구, Revision History, Mermaid 다이어그램, 패킷 스키마 표, 상대 링크를 일관된 엔터프라이즈급 SSOT 규격으로 통합 리팩토링합니다.

**Architecture:** 3계층 사양서 위계(Tier 1 Master ICD, Tier 2 System Diagram, Tier 3 서브시스템/지상시설 사양서 10종)를 기준으로 문서를 4대 작업 그룹으로 분할합니다. 각 문서마다 (1) 메타데이터/Revision History 정비, (2) 기계적 치환 잔재 제거 및 자연스러운 한국어 기술문 정제, (3) 패킷 스키마 및 채널 매핑 표 표준화, (4) Mermaid 다이어그램 가독성 강화를 순차 적용하고, 전용 검증 스크립트(`scratch/verify_all_specs.py`)로 링크와 채널 정합성을 자동 검증합니다.

**Tech Stack:** Markdown (GFM), Mermaid Diagrams, Python 3 (검증 스크립트 정규식 파서), Git

**Spec:** [docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md), [docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md)

## Global Constraints

- **대역폭 및 베이스 수식 단일 표준**: 모든 사양서에서 기체 채널 대역폭은 $BW = 40$이며 기본 수식은 $Base = 10000 + (N - 1) \times 40$ ($N = 1 \dots 1000$) 단일 규격을 유지한다.
- **Zone 1~4 서브채널 구조**: Zone 1 코어(`+0` C2, `+1` 유도, `+2` 텔레메트리, `+3` MFD, `+4` 센서버스, `+5` P2P회신, `+6~9` 코어예비), Zone 2 구동계(`+10` TCA추진, `+11` ASA조종면, `+12~19` 구동계예비), Zone 3 탑재체(`+20` 탑재체, `+21` 무장, `+22~29` 예비), Zone 4 편대(`+30` 편대링크, `+31~39` 전술예비).
- **Zero-Fallback 및 명시적 Deprecation**: 구버전 $BW=20$, `Base+6`, `Base+7`, `1000`(Alignment), `10045`(GPS) 등은 사양서 내 채널 할당 표 및 본문에서 `[DEPRECATED]` 배지로 1회 명시 보존하되, 중첩되거나 지저분하게 반복된 문자열(예: ``Base+10` (구 `Base+6` [DEPRECATED])`의 이중 중첩)을 단일하고 명료한 형식으로 정제한다.
- **상대 링크 정합성**: `docs/system/`과 `docs/specs/approved/` 간의 상호 참조 링크는 깨짐 없이 디렉토리 깊이에 맞는 상대 경로를 유지한다.
- **과장 표현 금지 (Overclaim Ban)**: "완벽", "무결점", "세계 최고", "원천 차단", "100% 보장" 등의 비검증 수식어를 배제하고 측정/규격에 근거한 객관적 기술 문장으로 서술한다.

## Review Focus

1. **중첩 치환 잔재 누락**: 스크립트 치환 과정에서 발생한 ``Base+10` (구 `Base+6` [DEPRECATED])` 형태의 다중 괄호 중첩이 본문에 잔존하는 결함.
2. **다이어그램과 본문 불일치**: Mermaid 다이어그램 화살표 라벨 채널(`Base+10`, `Base+11`)과 다이어그램 직후 본문 채널 기술이 어긋나는 결함.
3. **상대 링크 경로 오류**: `implemented/` 디렉토리 폐지에 따른 상대 링크 수정 중 상위 디렉토리 점(`../`) 개수 불일치로 인한 링크 깨짐.
4. **패킷 스키마 표 내 타입/단위 누락**: ICD 공통 엔벨로프 필드(`ver`, `domainId`, `seq`, `type`, `time`, `payload`) 및 페이로드 세부 필드의 단위/범위 불일치.
5. **Revision History 테이블 누락/오정렬**: 8개 주요 사양서 상단에 일관된 칼럼(`버전`, `개정 일자`, `개정 요약`, `개정 사유`) 구조가 유지되지 않는 결함.

---

## Task Structure

### Task 1: 전역 사양서 통합 검증 스크립트 구축 (Verification Tooling)

**Files:**
- Create: `scratch/verify_all_specs.py`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: `docs/system/*.md`, `docs/specs/approved/**/*.md`
- Produces: 링크 유효성, 채널/수식 정합성, 중첩 잔재 감지, Mermaid 구문 검증 CLI

- [ ] **Step 1: Write the failing test / inspection script in `scratch/verify_all_specs.py`**

```python
# scratch/verify_all_specs.py
import os, sys, re

def check_specs():
    # 1. Check all relative links
    # 2. Check 40-channel formula consistency (Base = 10000 + (N-1)*40)
    # 3. Detect duplicate/nested deprecation patterns like "Base+10 (구 Base+6" appearing multiple times or nested
    # 4. Check Revision History presence and table formatting
    # 5. Check no stale 'implemented/' links exist
    pass
```

- [ ] **Step 2: Run verification script to baseline existing issues**

Run: `python scratch/verify_all_specs.py`
Expected: Baseline report identifying all formatting, link, and nested string anomalies across 13 markdown specs.

- [ ] **Step 3: Implement comprehensive AST/regex checks in `scratch/verify_all_specs.py`**
Include checks for relative link targets, 40-channel formulas, nested `[DEPRECATED]` strings, and Revision History tables.

- [ ] **Step 4: Run test to verify scanner runs reliably**

Run: `python scratch/verify_all_specs.py`
Expected: Returncode 0 or clear failure list detailing remaining spec cleanup points.

- [ ] **Step 5: Commit tooling**

```bash
git add scratch/verify_all_specs.py
git commit -m "chore: add universal 40-channel specification suite verification tool"
```

---

### Task 2: Tier 1 마스터 ICD 전면 리팩토링 (Master ICD Refactoring)

**Files:**
- Modify: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: 40-channel architecture specification, 4-Zone layout
- Produces: 정제된 Master ICD (v1.20.0 SSOT Tier 1)

- [ ] **Step 1: Inspect Master ICD for style and text anomalies**
Identify all instances of duplicate `[DEPRECATED]` phrasing, broken table rows, or awkward Korean prose resulting from string replacements.

- [ ] **Step 2: Refactor Header, Metadata, and Revision History**
Standardize blockquote metadata:
```markdown
# 비행체 자율 제어 및 통신 데이터 교환 통합 규격서 (ICD)
> **Autonomous Flight System Interface Control Document (ICD / IDD)**  
> **프로젝트**: Universal Autonomous Flight Stack (UAFS Ecosystem)  
> **문서 버전**: v1.20.0  
> **최종 수정일**: 2026-11-07  
> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  
```
Ensure the `Revision History` table cleanly summarizes v1.20.0 changes without nested parenthesis.

- [ ] **Step 3: Refactor Section 2 (Interface Matrix & Mermaid Diagram)**
Clean up the Mermaid diagram:
- Clear grouping of `DOMAIN_AIRCRAFT` into 40-channel block with Zone 1~4 annotations.
- Direct, clean labels: `Base+10: MSG_THRUST_CMD` and `Base+11: MSG_SURFACE_CMD` with a single footnote/legend for deprecation.

- [ ] **Step 4: Refactor Section 3 (Interface Specifications I-1 ~ I-10)**
- I-3 (TCA): State `Base+10` cleanly. Add a clean deprecation box:
  ```markdown
  > [!NOTE]
  > **채널 마이그레이션**: 추진기 구동 버스는 기존 `Base+6`에서 Zone 2 전용 버스 `Base+10`(`CH_THRUST_ACTUATION`)으로 공식 이전되었습니다. 구버전 `Base+6`은 폐지(`[DEPRECATED]`)되었으며 Zero-Fallback 원칙이 적용됩니다.
  ```
- I-4 (Alignment): Cleanly state `Base+0` direct binding and `Base+10`/`Base+11` bay bind cascade.
- I-7 (GPS): Standardize `replyChannel = Base + 5` (Aircraft 01: `10005`, legacy `10045` `[DEPRECATED]`).
- I-8 (GCS Bootstrap): Clarify `CH_BOOTSTRAP = 50000`, candidateBase $10000 \sim 49960$, bandwidth 40.
- I-9 (Channel Probe & Rebind): Clarify 2-Phase Commit transaction on `Base+0/1 -> Base+10/11`.
- I-10 (ASA): State `Base+11` cleanly with migration note replacing legacy `Base+7`.

- [ ] **Step 5: Refactor Section 4 & Section 5 (Watchdog & Status)**
Clean up Watchdog table lines for I-3 (`Base+10`) and I-10 (`Base+11`). Ensure status tables are aligned.

- [ ] **Step 6: Verify Master ICD**

Run: `python scratch/verify_all_specs.py`
Expected: Master ICD passes all link, channel, and deprecation hygiene checks.

- [ ] **Step 7: Commit Master ICD**

```bash
git add docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md
git commit -m "docs(system): refactor Master ICD v1.20.0 for clean 40-channel architecture"
```

---

### Task 3: Tier 2 시스템 관계도 및 채널 다이어그램 리팩토링 (System Diagram Refactoring)

**Files:**
- Modify: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: Master ICD v1.20.0, 40-channel spectrum architecture
- Produces: 정제된 System Diagram (v2.7.0 SSOT Tier 2)

- [ ] **Step 1: Inspect System Diagram for mechanical replacement remnants**
Scan Section 2, Section 3, Section 4 sequence diagrams, and Section 5 spectrum diagrams for awkward phrasing or nested text.

- [ ] **Step 2: Refactor Header & Revision History**
Standardize metadata blockquote and clean up `Revision History` table for `v2.7.0`.

- [ ] **Step 3: Refactor Section 2 (System Architecture Diagram)**
Improve Mermaid readability:
- Use clean subgraph `DOMAIN_AIRCRAFT["[비행체 온보드] 전용 40채널 블록 (Base = 10000 + (N-1)*40, BW = 40)"]`.
- Format connection lines concisely without inline nested deprecation clutter.

- [ ] **Step 4: Refactor Section 3 & Section 4 (Packet Flow & Sequence Diagrams)**
Clean up all 6 Mermaid sequence diagrams:
- Seq 1 (Normal Flight): `Base+10 (20Hz)` for TCA, `Base+11 (20Hz)` for ASA.
- Seq 4 (Alignment Hangar Bay Binding): Clean `MSG_CALIB_BAY_BIND` to `Base+10` and `Base+11`.
- Seq 5 (Channel Bootstrap & Probe): 40-channel bandwidth request (`BW=40`).
- Seq 6 (Hierarchical Rebind): Cascade from `Base+0/1` to `Base+10/11`.

- [ ] **Step 5: Refactor Section 5, 6, 7 (Master Channel Spectrum & Boundary Rules)**
- 5.1 Matrix: Clean rows for GCS, VAS, TCA, ASA.
- 5.2 Spectrum Map: Crisp Mermaid ASCII layout showing 40-channel block slices ($10000\sim 10039, 10040\sim 10079$).
- 5.3 Subchannel Table: Ensure all 14 rows across Zone 1, 2, 3, 4 have clear, unified formatting.
- Section 6 & 7: Polish mathematical equations and pseudocode for $BW=40$ overlap and boundary detection.

- [ ] **Step 6: Verify System Diagram**

Run: `python scratch/verify_all_specs.py`
Expected: System Diagram passes all link and channel checks.

- [ ] **Step 7: Commit System Diagram**

```bash
git add docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md
git commit -m "docs(system): refactor System Diagram v2.7.0 with clean 40-channel spectrum topology"
```

---

### Task 4: Tier 3 온보드 제어 사양서 3종 리팩토링 (VAS, TCA, ASA)

**Files:**
- Modify: `docs/specs/approved/1_control/vas/VAS_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/approved/1_control/tca/TCA_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/approved/1_control/asa/ASA_PROGRAM_SPECIFICATION.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: Master ICD v1.20.0, Layer 1/2/3 control sandwich architecture
- Produces: 정합성 100% 온보드 비행 제어 사양서 3종 (v1.12.0, v1.9.0, v1.3.0)

- [ ] **Step 1: Refactor `VAS_PROGRAM_SPECIFICATION.md`**
- Polish Header, metadata, and Revision History (`v1.12.0`).
- Clean up Layer 3 Dual Adapter text: `actuator_adapter_tca` (`Base+10`), `actuator_adapter_asa` (`Base+11`).
- Clean up Sequence diagram in Section 3 and Data Flow in Section 4.
- In Section 8 (ICD Interface Details):
  - 8.3 [I-3]: Standardize `Base+10` (`CH_THRUST_ACTUATION`).
  - 8.4 [I-10]: Standardize `Base+11` (`CH_SURFACE_ACTUATION` / `CH_AERO_ACTUATION`).
  - 8.5 [I-4]: Standardize `Base+0` direct binding and `Base+10/11` bay bind forwarding.
  - 8.6 [I-5 Discovery]: Standardize `Base+10` and `Base+11`.
  - 8.10 [I-9 Rebind]: Standardize `Base+10` and `Base+11` forwarding.

- [ ] **Step 2: Refactor `TCA_PROGRAM_SPECIFICATION.md`**
- Polish Header, metadata, and Revision History (`v1.9.0`).
- Ensure all references to `thrustActuation` cleanly use `Base+10` (with clear deprecation notice for legacy `Base+6`).
- Standardize Section 4.4 (`MSG_CALIB_BAY_BIND`) and Section 4.5 (`MSG_CHANNEL_REBIND` on `oldBase+10` / `newBase+10`).
- Ensure `Base+4` is cleanly documented as permanently detached from normal operations.

- [ ] **Step 3: Refactor `ASA_PROGRAM_SPECIFICATION.md`**
- Polish Header, metadata, and Revision History (`v1.3.0`).
- Fix all relative markdown links pointing to peer specs (`../../approved/...`).
- Ensure all references to surface actuation use `Base+11` (with clear deprecation notice for legacy `Base+7`).
- Standardize Section 4.4 and Section 4.5 (`MSG_CHANNEL_REBIND` on `oldBase+11` / `newBase+11`).

- [ ] **Step 4: Verify 온보드 제어 사양서 3종**

Run: `python scratch/verify_all_specs.py`
Expected: VAS, TCA, ASA specs pass all verification checks.

- [ ] **Step 5: Commit 온보드 제어 사양서**

```bash
git add docs/specs/approved/1_control/
git commit -m "docs(specs): refactor VAS, TCA, and ASA control specs for clean Zone 2 actuator bus"
```

---

### Task 5: Tier 3 자율 항법 및 지상 시험 사양서 3종 리팩토링 (SAS, Alignment, GPS)

**Files:**
- Modify: `docs/specs/approved/2_guidance/fcp/FCP_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/approved/0_development/alignment/ALIGNMENT_PROGRAM_SPECIFICATION.md`
- Modify: `docs/specs/approved/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: Master ICD v1.20.0, System Diagram v2.7.0
- Produces: 정합성 100% 항법 및 지상 시험 사양서 3종 (v1.10.0, v2.5.0, v2.1.0)

- [ ] **Step 1: Refactor `SAS_PROGRAM_SPECIFICATION.md`**
- Polish Header, metadata, and Revision History (`v1.10.0`).
- Ensure Aircraft 01 baseline is consistent throughout: `Base = 10000`, `CH_FLIGHT_GUIDANCE = 10001`, `CH_TELEMETRY = 10002`, `CH_MFD_STATE = 10003`, `CH_CLIENT_REPLY = 10005`.
- Standardize GCS bootstrap channel to `50000` (`CH_BOOTSTRAP`).
- Clean up common envelope encoding documentation to mandate `time` field.
- Clean up downstream rebind text for TCA (`Base+10`) and ASA (`Base+11`).

- [ ] **Step 2: Refactor `ALIGNMENT_PROGRAM_SPECIFICATION.md`**
- Polish Header, metadata, and Revision History (`v2.5.0`).
- Ensure formula is cleanly stated: `craftBase = 10000 + (aircraftNumber - 1) * 40`.
- Document Aircraft 01 direct binding on `Base+0` (`10000`, with note deprecating legacy 4-digit `1000`).
- Clean up bay bind propagation text to TCA (`Base+10`) and ASA (`Base+11`).

- [ ] **Step 3: Refactor `GPS_PROGRAM_SPECIFICATION_AND_ICD.md`**
- Polish Header, metadata, and Revision History (`v2.1.0`).
- Standardize Aircraft 01 reply channel to `Base+5` (`10005`, with note deprecating legacy `10045`).
- Ensure Swarm channels (`60001 ~ 60004`) are crisply formatted across all message schemas.

- [ ] **Step 4: Verify 자율 항법 및 지상 시험 사양서 3종**

Run: `python scratch/verify_all_specs.py`
Expected: SAS, Alignment, GPS specs pass all verification checks.

- [ ] **Step 5: Commit 자율 항법 및 지상 시험 사양서**

```bash
git add docs/specs/approved/2_guidance/ docs/specs/approved/0_development/ docs/specs/approved/0_infra/gps/
git commit -m "docs(specs): refactor SAS, Alignment, and GPS specs for unified 40-channel baseline"
```

---

### Task 6: Tier 3 지상 시설물 및 관제 사양서 4종 리팩토링 (Docking Arm, Landing Pad, Runway, GAC)

**Files:**
- Modify: `docs/specs/approved/0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/approved/0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/approved/0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD.md`
- Modify: `docs/specs/approved/0_infra/gac/GAC_PROGRAM_SPECIFICATION_AND_ICD.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: Master ICD v1.20.0, GAC 3-Tier architecture
- Produces: 정합성 100% 지상 시설물 및 관제 사양서 4종 (Patch SemVer bump)

- [ ] **Step 1: Refactor `DOCKING_ARM_SPECIFICATION_AND_ICD.md`**
- Verify and clean relative links pointing to `approved/` specs.
- Update header version badge and referenced System Diagram version (`v2.7.0`).
- Clean up any residual mechanical replacement formatting.

- [ ] **Step 2: Refactor `LANDING_PAD_SPECIFICATION_AND_ICD.md`**
- Verify and clean relative links pointing to `approved/` specs.
- Update header version badge and referenced System Diagram version (`v2.7.0`).
- Standardize tactical guidance channel descriptions ($Base_{\text{sec}} + 10 + \text{Idx}$).

- [ ] **Step 3: Refactor `RUNWAY_SPECIFICATION_AND_ICD.md`**
- Verify and clean relative links pointing to `approved/` specs.
- Update header version badge and referenced System Diagram version (`v2.7.0`).
- Standardize ILS glide slope descriptions and GAC coordination.

- [ ] **Step 4: Refactor `GAC_PROGRAM_SPECIFICATION_AND_ICD.md`**
- Verify and clean relative links pointing to `approved/` specs.
- Update header version badge and referenced System Diagram version (`v2.7.0`).
- Clean up Sector 0 beacon (`CH 50003`) and Sector S base formula ($Base_{\text{sec}} = 50001 + S \times 200$).

- [ ] **Step 5: Verify 지상 시설물 및 관제 사양서 4종**

Run: `python scratch/verify_all_specs.py`
Expected: Ground and GAC specs pass all verification checks.

- [ ] **Step 6: Commit 지상 시설물 및 관제 사양서**

```bash
git add docs/specs/approved/0_ground/ docs/specs/approved/0_infra/gac/
git commit -m "docs(specs): refactor Ground facilities and GAC specs with verified peer links"
```

---

### Task 7: 메타 인덱스 갱신 및 전역 무결성 최종 검증 (Final Verification & Handover)

**Files:**
- Modify: `docs/specs/README.md`
- Test: `scratch/verify_all_specs.py`

**Interfaces:**
- Consumes: All 13 refactored specifications
- Produces: 100% 무결점 사양서 스위트 및 완료 핸드오버 보고서

- [ ] **Step 1: Update `docs/specs/README.md`**
Update the specification inventory table in `docs/specs/README.md` reflecting the new 40-channel versions and the current lifecycle state (`approved/` 10종, `docs/system/` 2종).

- [ ] **Step 2: Run Full Automated Verification Suite**

Run: `python scratch/verify_all_specs.py`
Expected: `SUCCESS: ALL 13 SPECIFICATIONS VERIFIED 100% CLEAN (0 Errors, 0 Warnings)!`

- [ ] **Step 3: Check git status and diff cleanliness**

Run: `& "C:\Program Files\Git\cmd\git.exe" status -s`
Expected: Clean working tree with well-organized commits or staged changes.

- [ ] **Step 4: Commit Meta & Verification Artifacts**

```bash
git add docs/specs/README.md scratch/verify_all_specs.py
git commit -m "docs: finalize 40-channel specification suite refactoring and lifecycle status"
```
