# TASK-403 설계 결정: AMM WebUI 미션 에디터 World Preset 및 `ACT_TKL_LAND_NEAREST`

- 결정 일자: 2026-11-14 (`/grill-me`)
- 추적 과제: `TASK.md` `TASK-403` (후속 `TASK-404`, `TASK-011-4`)
- 대상 사양서: `docs/specs/3_planning/amm/AMM_PROGRAM_SPECIFICATION.md`, `docs/specs/3_planning/amm/AMM_MISSION_EDITOR_SPECIFICATION.md` (개정은 `TASK-403-1`에서 Spec-First로 수행)
- 비고: 2026-11-15 `TASK.md` 크기 감축을 위해 원문을 그대로 이관함.

## 확정 설계 결정

- **구조 범위**: **멀티 월드 프로필 구조** — 월드/서버별 이름(`Survival_Main`, `Test_Lab` 등)을 생성·전환하며 각 월드마다 시설물 목록 독립 보관
- **시설 스키마**: `facilityId`, `label`, `type`(`LANDING_PAD` | `RUNWAY` | `DOCKING_ARM` | `RALLY` | `POI` | `CUSTOM`), `x`/`z`(필수), `y`(선택), `headingDeg`(선택), `notes`(선택)
- **이중 영속성**: `localStorage` 자동 저장 + World Preset `.json` 파일 Export/Import(백업·공유·병합) 병행
- **UI/등록 동선**: 상단 헤더 `World` 선택·드로어(`#worldPresetDrawer`) + 체크포인트 `Params` `'Save as Facility'` 및 캔버스 좌표 픽커(`PICK_FACILITY`) 빠른 등록
- **편집 연동 및 바인딩**: 2D 캔버스 배경 시설물 핀 레이어(토글·클릭 할당/센터링) + 인스펙터 `Params` `'From World…'` 퀵픽 + `'+ From Facility'` 병행; **순수 값 복사**(미션 JSON `v2.0.0` 순수성 유지) 및 **스마트 Y 매핑**(`facility.y`는 `poiPos.y`에 기본 반영하고 `targetAlt`는 비행 고도 보호를 위해 명시적 선택 시에만 적용)
- **이착륙 시설 지정 규약**: 도킹암(`ACT_MOB_ARM_DOCK`/`UNDOCK`)·랜딩패드(`ACT_TKL_TAKEOFF_VERT`, `ACT_TKL_LAND_NORM`/`PREC`)·활주로(`ACT_TKL_TAKEOFF_RWY`/`LAND_RWY`) 및 시설 기반 매크로(`MAC_*`)는 **활성 월드 프로필 내 호환 타입 시설 드롭다운 선택**으로 전환(좌표·`facilityId` 자동 채움; 외부 JSON 미등록 `facilityId` 임포트 시 `WARNING` + `'현재 월드에 등록'` 1클릭 버튼 제공)
- **신규 행동 `ACT_TKL_LAND_NEAREST` (가장 가까운 착륙 가능 시설에 착륙)**: `AMM` 런타임(`facility_client.find_nearest_free_landing_facility` 연동)과 에디터 동시 확장; `facilityTypeFilter`(`"ANY"` | `"LANDING_PAD"` | `"RUNWAY"`)·`maxRangeM`(선택) 지원, 비콘 기반 최근접 `FREE` 착륙 시설 동적 탐색 후 착륙(`FACILITY_TOUCHDOWN` 완료), 가용 시설 부재 시 체크포인트 `abort`/`fallbackPolicy` 전이
- **2D XZ 캔버스 4변 좌표 눈금 표시**: 메인 `(X, Z)` 평면 상단/하단(X축) 및 좌측/우측(Z축) 가장자리 격자선에 월드 좌표 라벨(`tabular-nums` 고정폭, 주 격자선 정렬, 툴바·HUD 영역 회피) 실시간 렌더링
