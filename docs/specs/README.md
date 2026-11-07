# Program Specifications (사양서)

Create: Aeronautics 및 CC:Tweaked 비행선 제어 소프트웨어의 프로그램 사양서를 관리하는 디렉토리입니다.  
구현할 프로그램의 **요구사항**, **도메인/런타임 제약사항**, **의사코드(Pseudocode)** 등을 포함합니다.

---

## 1. 디렉토리 구조 및 영구 경로 원칙 (Unified Directory Structure)

모든 사양서는 생명주기 상태에 따른 폴더 분리(`drafts/`, `approved/`, `implemented/`, `archived/`) 없이, **기능 도메인 기반의 단일 디렉토리 계층**에 영구 배치됩니다.  
문서의 생명주기(상태)와 수정 이력은 파일 이동이 아닌 **문서 내부의 상단 메타데이터 요약 테이블 및 Revision History**로 관리합니다.

- `0_development/`: 개발·검증·교정 지원 도구 사양서 (`alignment` 등)
- `0_infra/`: 기지 지상 인프라 및 핵심 유틸리티 규격서 (`gps`, `gac`, `docking_arm`, `landing_pad`, `runway` 등)
- `1_control/`: 온보드 실시간 제어 사양서 (`vas`, `tca`, `asa` 등)
- `2_guidance/`: 자율 항법 및 오토파일럿 사양서 (`sas` 등)
- `3_planning/`: 경로 생성 및 자율 편대 비행 기획 사양서
- `4_mission/`: 미션 시나리오 및 탑재체 임무 제어 사양서

> **영구 경로 불변 원칙**: 사양서 파일의 위치가 상태 변화에 따라 이동하지 않으므로, 상위 ICD(`docs/system/`) 및 사양서 간 상대 마크다운 링크(`../../...`)는 영구적으로 안정성을 유지합니다.

---

## 2. 문서 내부 생명주기 메타데이터 규격 (In-Document Metadata Specification)

모든 사양서 최상단에는 아래 **5대 필수 항목**을 갖춘 표준 메타데이터 테이블을 배치합니다:

```markdown
| 항목 | 내용 |
| :--- | :--- |
| **문서 상태 (Status)** | `Approved` |
| **문서 버전 (Version)** | `v1.12.0` |
| **최종 수정일 (Date)** | `2026-11-07` |
| **구현 코드 (Source)** | `src/1_control/vas/` |
| **주관 도메인 (Domain)** | 온보드 실시간 비행 제어 및 고정밀 계측 코어 (VAS / Node 01) |
```

### 생명주기 4단계 상태 정의 (Lifecycle States)
1. **`Draft`**: 신규 작성 중이거나 초기 기획 단계의 사양서. (`specification-lifecycle-manager` SSOT 스캔 대상에서 제외)
2. **`Approved`**: 요구사항, 패킷 스키마, 채널 할당, FSM 검토가 완료되어 **구현 대기 중**인 활성 사양서. (또는 `Implemented` 상태의 사양서에 런타임 코드 수정이 필요한 개정이 발생했을 때 전이)
3. **`Implemented`**: 코드베이스(`src/`) 반영 및 테스트 러너/하네스 검증(`verification-before-completion`)이 완료된 **구현 완료** 사양서.
4. **`Deprecated`**: 상위 아키텍처 재편이나 신규 프로토콜로 대체되어 폐기된 사양서. (Zero-Fallback 원칙에 따라 대체 규격 명시 및 수신단 레거시 폴백 차단)

---

## 3. 상태 전이 및 스킬 관할 프로토콜 (State Transitions & Protocols)

```
[ 신규 사양서 작성 (Status: Draft) ]
             │
             ▼
      ┌──────────────┐   코드 검증 통과 후 자동 승격   ┌──────────────┐
      │   Approved   ├─────────────────────────────►│ Implemented │
      │  (구현 대기)  │◄─────────────────────────────┤  (구현 완료)  │
      └──────┬───────┘   런타임 코드 변경 수반 스펙 수정  └──────┬───────┘
             │          (단순 링크/오탈자 수정 시 유지)          │
             │                                              │
             └──────────────► Deprecated ◄──────────────────┘
                         (대체 규격 명시 & Zero-Fallback)
```

### 사양서 수정 프로토콜 (Revision Protocol — `specification-lifecycle-manager`)
1. **런타임 영향 판단 및 상태 전이**:
   - `Implemented` 상태의 사양서에 패킷 스키마, 채널, 알고리즘, 파라미터 등 `src/` 코드 수정이 수반되는 개정이 발생하면, **표의 `문서 상태`를 `Approved`로 전이**하고 버전을 판올림(Minor/Major)하며 `최종 수정일`을 갱신합니다.
   - 문서 하단 또는 상단에 `Revision History` 테이블 행을 추가하여 개정 사유와 내역을 명시합니다.
   - 단순 오탈자 교정, 설명 보강, 상대 링크 동기화 등 런타임 코드에 영향이 없는 수정의 경우, `Implemented` 상태를 유지하고 패치 버전(+0.0.1) 및 `최종 수정일`만 갱신합니다.
2. **Mixed-Scope 인터록**: 활성 사양서(`Approved`/`Implemented`) 수정과 `src/` 코드 수정을 한 턴에 동시 요청받은 경우, 인터록을 발동하여 사양서 우선(Spec-First) 또는 순차 실행(Sequential)을 사용자에게 확인합니다.

### 코드베이스 구현 완료 프로토콜 (Completion Protocol — 경량 자동 승격)
1. **검증 통과 필수**: 대상 사양서의 요구사항이 코드에 반영되고 `verification-before-completion` 검증(문법 검사, 단위 테스트, 하네스 실행) 통과 증거를 확보합니다.
2. **경량 자동 승격**: 검증 통과 직후 완료 보고 전에, 에이전트가 파일 이동 없이 사양서 상단 메타데이터 표의 **`문서 상태`를 `Implemented`로 자동 갱신**하고 **`최종 수정일`을 당일 날짜로 동기화**합니다 (`specification-lifecycle-manager` 비호출, Mixed-Scope 면제).
