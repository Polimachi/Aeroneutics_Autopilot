# Program Specifications (사양서)

Create: Aeronautics 및 CC:Tweaked 비행선 제어 소프트웨어의 프로그램 사양서를 관리하는 디렉토리입니다.
구현할 프로그램의 **요구사항**, **도메인/런타임 제약사항**, **의사코드(Pseudocode)** 등을 포함합니다.

---

## 1. 디렉토리 구조 및 생명주기 (Lifecycle)

사양서는 상태에 따라 다음 4단계 하위 디렉토리로 분류하여 관리합니다:

- `drafts/`: 신규 작성 중이거나 초기 검토 중인 사양서 초안 (`specification-lifecycle-manager` 적용 제외)
- `approved/`: 요구사항 및 제약사항 검토가 완료되어 **구현 대기 중**인 활성 사양서 (`specification-lifecycle-manager` SSOT Tier 3 관할)
- `implemented/`: 코드베이스 반영 및 검증이 완료된 **구현 완료** 활성 사양서 (`specification-lifecycle-manager` SSOT Tier 3 관할)
- `archived/`: 변경, 대체 또는 폐기되어 동결 보관된 과거 사양서 (`specification-lifecycle-manager` 양방향 스캔 제외)

> **계층 경로 보존 원칙**: 모든 사양서는 상태 디렉토리(`drafts/`, `approved/`, `implemented/`, `archived/`) 간 이동 시 계층 서브디렉토리 구조(예: `1_control/vas/`, `2_guidance/sas/`)를 동일하게 유지해야 합니다. 본 안내 문서(`docs/specs/README.md`)는 메타 가이드로서 SSOT 사양서 동기화 대상에서 제외됩니다.

---

## 2. 상태 전이 및 스킬 관할 규칙 (Lifecycle & Skill Scope)

```
[ 신규 사양서 초안 작성 (스킬 비발동) ]
        │
        ▼
   ┌─────────┐    검토 완료 & 승격 배치 (전역 SSOT 동기화 발동)
   │ drafts/ ├─────────────────────┐
   └─────────┘                     │
                                   ▼
                            ┌──────────────┐   코드 검증 통과 후 경량 승격   ┌──────────────┐
                            │  approved/   ├────────────────────────────►│ implemented/ │
                            │  (구현 대기)  │◄────────────────────────────┤  (구현 완료)  │
                            └──────┬───────┘   런타임 코드 변경 필요 스펙 수정 └──────┬───────┘
                                   │          (단순 링크/배지 동기화는 유지)         │
                                   │                                              │
                                   └──────────────► archived/ ◄───────────────────┘
                                          (폐기 시 상위 참조 정리 후 스캔 동결)
```

### 사양서 수정 및 양방향 동기화 규칙 (Revision Protocol — `specification-lifecycle-manager`)
1. **런타임 영향 기준 직행 이동**: 활성 사양서 수정 및 양방향 동기화 시, 요구사항·패킷 스키마·채널·파라미터 변경으로 **`src/` 런타임 코드 수정이 필요한 Tier 3 사양서만** `drafts/`를 거치지 않고 즉시 계층 경로를 유지한 채 `approved/`로 이동합니다. 단순 상대 링크나 참조 버전 배지만 갱신된 연관 사양서는 `implemented/`에 그대로 유지합니다 (`docs/system/` 문서는 위치 고정).
2. **메타데이터 및 조건부 `Revision History` 기록**:
   - 모든 활성 사양서는 상단 인용구(`> **문서 버전**: vX.Y.Z (...)`, `> **최종 수정일**: YYYY-MM-DD`)를 기본 유지·갱신합니다.
   - **실질 스펙 변경(`approved/` 이동 대상)이 발생한 사양서에 한해** 상단 인용구 바로 아래에 아래 `Revision History` 테이블을 신설·누적 기록합니다(단순 링크·배지 동기화 문서에는 테이블을 추가하지 않음):

| 버전 | 일자 | 변경 요약 | 변경 사유 |
| :--- | :--- | :--- | :--- |
| v1.1 | YYYY-MM-DD | 센서 타임아웃 파라미터 변경 | 통신 불안정 이슈 대응 |

### 코드베이스 적용 완료 시 규칙 (Completion Protocol — 경량 전이 예외)
1. **검증 통과 필수**: 코드베이스에 `approved/` 사양서 내용이 반영되고, 문법 검사·단위 테스트 등 `verification-before-completion` 검증 증거가 확보되어야 합니다.
2. **경량 자동 승격 (`specification-lifecycle-manager` 비호출)**: 검증 통과 직후 완료 보고 전에 에이전트가 Mixed-Scope 중단 예외로서 사양서를 `approved/`에서 `implemented/`로 이동하고, `docs/system/` 및 `docs/specs/{approved,implemented}/` 내 상대 마크다운 링크 경로만 즉시 치환합니다.

