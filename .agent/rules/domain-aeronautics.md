---
trigger: model_decision
description: Apply ONLY when planning architecture/features (/plan) or writing, modifying, or reviewing CC:Tweaked Lua code and harness specs. Do NOT apply to general chat or unrelated git/doc tasks. Enforces Valkyrien Skies mod ban and Create/Avionics/Radars/Propulsion/Advanced Peripherals allowlist.
---

# Domain & Dependency Rules (Create: Aeronautics Ecosystem)

## 1. Valkyrien Skies (VS1/VS2) 계통 의존성 영구 금지 (`prohibited-mods`)

CC:Tweaked Lua 코드, 테스트, Mock, 하네스 설정 어디에도 Valkyrien Skies 본체 및 산하 애드온 의존성을 사용하지 않는다.

- **절대 차단 문자열 및 모드 식별자**:
  - 본체·브리지: `valkyrien`, `valkyrienskies`, `vs2`, `cc_vs`, `vs_computers`, `valkyriencomputers`, `ship_api`, `extendedshipapi`, `ship_reader`
  - 산하 애드온: `vs_clockwork`(`physics_infuser`, `flap_bearing`, `gravitron`, `phys_bearing`, `redstone_resistor`), `vs_eureka`/`eureka`(`ship_helm`, `eureka:ship_helm`), `trackwork`/`vs_trackwork`(`phys_track`, `suspension_track`), `vs_tournament`, `vs_addition`, `create_interactive`, `valkyrien_pirates`, `vmod`, `drivebywire`
  - 네임스페이스 접두사 차단: `kontraption:` (단, `Create Propulsion: Simulated`의 단독 `ion_thruster` 페리페럴은 아래 허용 목록에 따라 정상 허용), `vs_clockwork:`, `eureka:`, `vs_eureka:`, `trackwork:`, `vs_trackwork:`, `vs_tournament:`, `tournament:`, `vs_addition:`, `valkyrien:`, `vs2:`, `cc_vs:`
- **CC:VS 전용 API 차단**:
  - `peripheral.find("ship")` / `peripheral.wrap("ship")`
  - 전역 `ship` 전용 메서드: `getWorldspacePosition`, `getShipyardPosition`, `getMomentOfInertiaTensor`, `applyInvariantForce`, `applyInvariantTorque`, `applyRotDependentForce`, `applyRotDependentTorque`, `getQuaternion`, `getOmega`, `getSlug`, `setSlug`, `isStatic`, `setStatic`, `getScale`, `getTransformationMatrix`

## 2. 공식 허용 모드 및 페리페럴 생태계

- **순정 Create & Create: Aeronautics 계통**:
  - `create:*` (`create:clockwork_bearing`, `clockwork_bearing`, `mechanical_bearing`, `propeller_bearing` 등), `Create: Aeronautics` (`simulated`, `landlord`), `Create: Offroad`, `Create: Liftoff`, `Create: High Seas`
- **CC:Avionics (`Create: Avionics`)**:
  - `avionics_controller`, `radar`, `gimbal_sensor`, `velocity_sensor`, `navigation_table`, `laser_sensor`, `laser_pointer`, `throttle_lever`, `steering_wheel`, `propeller`, `propeller_bearing`, `gyroscopic_propeller_bearing`, `gas_provider`, `wheel_mount`, 대기·항법 계기(`air_data`, `altitude_sensor`, `gyroscopic_sensor`, `optical_sensor`, Thermometer/Barometer/Hygrometer/Rain Gauge/Almanac)
- **CC:Radars (`Create: Radars`)**:
  - `fire_controller`, `radar_monitor`, `auto_pitch_controller`, `auto_yaw_controller`, `plane_radar`, `radar_bearing`
- **Create Propulsion: Simulated**:
  - `thruster`, `ion_thruster`(단독 페리페럴 식별자 허용), `creative_thruster`, `vector_thruster`, `liquid_vector_thruster`, `creative_vector_thruster`, `stirling_engine`, `redstone_transmission`, `tilt_adapter`, `coral_generator`
- **Advanced Peripherals**:
  - `meBridge`, `rsBridge`, `geoScanner`, `playerDetector`, `chatBox`, `inventoryManager`, `environmentDetector`, `colonyIntegrator`, `arController`, `redstoneIntegrator`, `energyDetector`
- **CC:Tweaked 순정 페리페럴 및 일반 변수명**:
  - `modem`, `monitor`, `speaker`, `printer`, `drive`, `computer`, `inventory`, `redstone`
  - 일반 비행체 상태 변수명(`airship`, `aircraft`, `flight_state`, `ship_state`, `ship_pos`, `ship_heading`, `ship_telemetry`, `ship_velocity`)은 정상 허용한다.
