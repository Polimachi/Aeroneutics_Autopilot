# TASK-016 설계 규격 — 제품 아키텍처(L1~L4) 효율성·효용성 검사

| 항목 | 값 |
|---|---|
| 문서 상태 | Implemented (P0~P6 완료) |
| 기준 커밋 | `d63d0db` (P0 기준선) / `eb339b5` (P1 계측·감사 도구 병합) |
| 작성일 | 2026-11-18 |
| 선행 감사 | `TASK-013` 정합성 전수 감사 ([Audit_Report_1_11142026.md](../../reports/reviewCompleted/Audit_Report_1_11142026.md)), `TASK-014` 사각지대 가드레일 |
| 최종 보고서 | [Architecture_Efficiency_Audit_1_11182026.md](../../reports/underReview/Architecture_Efficiency_Audit_1_11182026.md) |

## 1. 확정 범위 및 방식 (Q1~Q4 + 추가 지침)

- **Q1 (범위)**: 제품 아키텍처 **L1~L4 한정** (L1 런타임 토폴로지, L2 통신·RF 프로토콜, L3 코드 구조, L4 사양·문서 체계). 배포 경로(L6)·거버넌스(L7)·기존 검증 도구 효용 평가(L5)는 제외.
- **Q2 (계측)**: `harness/simulation/{node_sandbox,virtual_bus}.lua`, `harness/unit/guest/runner_lib.lua`, `tools/run_e2e_tests.py`에 `--profile` 및 `--check-baseline` 추가 (E2E 노드 바이트코드 명령어·wall-clock CPU ms·`require` 비용·채널 패킷/바이트/미수신 통계).
- **Q3 (영구 편입)**: `tools/audit/` 패키지(`registry`, `static`, `dupes`, `specs`, `split`, `guard`) 및 `config/audit_baselines.json` 영구 편입, `tests/harness/` 회귀 테스트 등록.
- **Q4 (실행 체계)**: P0 기준선 → P1 격리 워크트리 TDD 도구 구축 → P2 지표 수집 → P3 4개 렌즈 병렬 검토(`R-L1..R-L4`) → P4 독립 교차 검증(`V-A`, `V-B`) → P5 Decision Gates(A1~A5) → P6 보고서·가드·후속 TASK.
- **추가 1 (`docking_arm`)**: `src/0_infra/docking_arm/`에 코드가 부재하므로 `docs/specs/0_infra/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md`만을 근거로 `[SPEC-ONLY]` 검토(L1·L2·L4 적용, L3·동적 계측 제외).
- **추가 2 (분할 트랙 S)**: Lua 단일 파일(`>= 20,000 B` 또는 `>= 450줄`), 서브시스템(`>= 90,000 B`), 사양서(`>= 80,000 B`), WebUI(`>= 100,000 B`)를 N1~N5(필요성)·F1~F6(수행 가능성) 기준으로 평가.

## 2. 불변식 취급 및 판정 루브릭

- 확정 불변식(`멀티 코드베이스 독립 완결`, `Zero-Fallback`, `20Hz 헤드리스`, `40채널 블록`, `사양서 영구 경로`)은 결함으로 판정하지 않고 비용을 정량화한다.
- 6-판정 매트릭스: **Keep**(U2~3, E2~3), **Optimize**(U2~3, E0~1), **Watch**(U1, E2~3), **Consolidate**(U1, E0~1), **Investigate**(U0, E2~3), **Retire**(U0, E0~1).
- 트랙 S 판정: **Split**, **Split-Prereq**, **Keep-Justified**, **Keep**, **Extract**.
- 모든 본문 항목은 증거 ID + 재현 명령/`file:line` 및 신뢰도 `>= 80`을 요구하며, `< 80`은 관찰 사항으로 분리한다.
