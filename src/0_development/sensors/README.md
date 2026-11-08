# CC:Avionics Standard Sensor Library (`src/0_development/sensors/`)

프로젝트 전 프로그램에서 공통 참조하는 **CC:Avionics (`Create: Avionics`) 4종 센서 전용 표준 API 함수 모음** 단일 원본(SSOT) 디렉토리입니다.

## 지원 센서 범위

1. **`velocity_sensor`**: 장착 축 기준 방향 선속도(`getVelocity`, `getAxis`) 및 3축 합성 속도 벡터(`read_vector3`)
2. **`altitude_sensor`**: 월드 고도(`getHeight`), 해수면 대비 기압비(`getAirPressure`), 수직 속도(`getVerticalSpeed`)
3. **`gimbal_sensor`**: 동체 기준 피치/롤 각도(`getAngles`/`getAnglesRad`), 3축 각속도(`getAngularRates`/`getAngularRatesRad`), 중력 벡터 및 무특이점 기울기(`getGravity`, `compute_tilt_deg`), 고유 가속도(`getLinearAcceleration`)
4. **`physics_assembler`**: 조립 여부(`isAssembled`), 총 질량(`getMass`), 무게중심(`getCenterOfMass`), 3×3 관성 텐서(`getInertiaTensor`), 서브레벨 식별자(`getSubLevelId`, `getSubLevelName`) 및 `parallel.waitForAll` 기반 1틱 일괄 조회(`read`)

## 배포 및 참조 방식

- **통합 인스톨러([manifest.lua](../installer/modules/manifest.lua))**: 각 컴퓨터의 `/lib/avionics_sensors.lua`로 번들 또는 단독 배포됩니다.
- **단위 테스트 하네스**: 모든 테스트 타겟 실행 시 게스트 `/lib/avionics_sensors.lua`로 자동 스테이징됩니다.
- **런타임 참조**: `local sensors = require("avionics_sensors")`
