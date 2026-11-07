--[[
    ========================================================================
    FIXED WING GUIDANCE DRIVER (fixed_wing_driver.lua)
    UAFS FCP Layer 2: Fixed-Wing (Airplane) Guidance & TECS Stall Protection
    
    [역할]
    - AIRFRAME = "FIXED_WING" 표준 가이던스 드라이버
    - TECS (Total Energy Control System) 속도 우선 실속 방지 및 활공 유도
    - 저속/착륙/이륙 시 플랩(flapTarget) 스케줄링 연산
    - 순수 CraftOS 런타임 및 무결성 보장 (하드웨어 의존성 분리)
    ========================================================================
]]

local fixed_wing_driver = {}
fixed_wing_driver.AIRFRAME = "FIXED_WING"

local function clamp(val, min_v, max_v)
    if val < min_v then return min_v end
    if val > max_v then return max_v end
    return val
end

local function wrap_deg180(deg)
    local d = (deg + 180.0) % 360.0
    if d < 0 then d = d + 360.0 end
    return d - 180.0
end

local function project_to_body(ux, uz, heading_deg)
    local rad = math.rad(heading_deg or 0.0)
    local sin_h, cos_h = math.sin(rad), math.cos(rad)
    local surge = ux * sin_h - uz * cos_h
    local sway = ux * cos_h + uz * sin_h
    return surge, sway
end

--- 경로 또는 목표 지향 헤딩 산출
---@param cfg table
---@param nav table
---@param target table
---@param dt number
---@param prev_heading number?
---@return number targetHeading
function fixed_wing_driver.compute_heading(cfg, nav, target, dt, prev_heading)
    local g = cfg and cfg.guidance and (cfg.guidance.fixed_wing or cfg.guidance.airplane) or {}
    local max_rate = g.maxYawRateDegPerSec or 20.0
    local prev_h = prev_heading or (nav and nav.attitude and nav.attitude.heading) or 0.0
    local mode = g.headingMode or "FACE_PATH"

    local target_h = prev_h
    if target and target.x and target.z and nav and nav.pos then
        local dx = target.x - nav.pos.x
        local dz = target.z - nav.pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if (mode == "FACE_PATH" and dist >= 3.0) or mode == "TARGET_LOCK" then
            target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
        end
    end

    local diff = wrap_deg180(target_h - prev_h)
    local max_step = max_rate * dt
    local step = clamp(diff, -max_step, max_step)
    return (prev_h + step + 360.0) % 360.0
end

--- 대기속도 및 비행 상태 기반 피치/롤 비행 외피 한계 및 자세 목표 산출
---@param cfg table
---@param fsm_state string
---@param ground_speed number
---@param airspeed number
---@param desired_pitch number
---@param heading_diff number
---@return number pitch, number roll, boolean isStallWarning, string flightMode
function fixed_wing_driver.compute_envelope_attitude(cfg, fsm_state, ground_speed, airspeed, desired_pitch, heading_diff)
    local g = cfg and cfg.guidance and (cfg.guidance.fixed_wing or cfg.guidance.airplane) or {}
    local stall_spd = g.stallSpeed or 15.0
    local safe_spd = g.safeSpeed or 20.0
    local max_stall_pitch = g.maxStallPitch or 3.0
    local max_normal_pitch = g.maxNormalPitch or 15.0
    local max_bank_angle = g.maxBankAngle or 30.0

    local cur_spd = airspeed > 0 and airspeed or ground_speed
    local is_stall = false
    local flight_mode = "NORMAL_CRUISE"
    local pitch = desired_pitch

    if cur_spd < stall_spd then
        is_stall = true
        flight_mode = "STALL_RECOVERY_SPEED_PRIORITY"
        pitch = clamp(desired_pitch, -max_normal_pitch, max_stall_pitch)
        if pitch > max_stall_pitch then
            pitch = 0.0
        end
    elseif cur_spd < safe_spd then
        flight_mode = "SPEED_MARGIN_PROTECTION"
        local ratio = (cur_spd - stall_spd) / (safe_spd - stall_spd)
        local allowed_max_pitch = max_stall_pitch + ratio * (max_normal_pitch - max_stall_pitch)
        pitch = clamp(desired_pitch, -max_normal_pitch, allowed_max_pitch)
    else
        pitch = clamp(desired_pitch, -max_normal_pitch, max_normal_pitch)
    end

    -- 뱅크각(Roll)을 통한 선회 조정 (Coordinated Turn)
    local bank_gain = g.coordinatedTurnGain or 1.2
    local roll = clamp(heading_diff * bank_gain, -max_bank_angle, max_bank_angle)

    if fsm_state == "EMERGENCY_LAND" then
        flight_mode = "ADAPTIVE_GLIDE_DESCENT"
        pitch = 0.0
        roll = 0.0
    end

    return pitch, roll, is_stall, flight_mode
end

--- 비상 활공 강하 지시 연산
---@param nav table
---@return table
local function compute_emergency(nav)
    local head = nav.attitude and nav.attitude.heading or 0.0
    return {
        surge = 0.45,
        sway = 0.0,
        heave = -0.5,
        throttle = 0.35,
        targetPitch = 0.0,
        targetRoll = 0.0,
        targetHeading = head,
        targetClimbRate = -1.5,
        flapTarget = 0.5,
        isStallWarning = false,
        flightMode = "ADAPTIVE_GLIDE_DESCENT"
    }
end

--- 고정익 유도 명령 산출 메인 엔트리
---@param cfg table
---@param nav table
---@param target table
---@param fsm_state string
---@param dt number
---@param driver_state table?
---@return table
function fixed_wing_driver.compute(cfg, nav, target, fsm_state, dt, driver_state)
    if fsm_state == "EMERGENCY_LAND" then
        return compute_emergency(nav)
    end

    local g = cfg and cfg.guidance and (cfg.guidance.fixed_wing or cfg.guidance.airplane) or {}
    local cruise_throttle = g.cruiseThrottle or 0.70
    local stall_throttle = g.stallThrottle or 1.0
    local safe_spd = g.safeSpeed or 20.0

    local pos = nav.pos or { x = 0, y = 64, z = 0 }
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local head = nav.attitude and nav.attitude.heading or 0.0
    local tgt_x, tgt_y, tgt_z = target.x or pos.x, target.y or pos.y, target.z or pos.z

    local gs = nav.groundSpeed or math.sqrt(vel.x * vel.x + vel.z * vel.z)
    local airspeed = nav.airspeed or gs

    -- 헤딩 연산
    local prev_h = driver_state and driver_state.prev_heading or head
    local cmd_h = fixed_wing_driver.compute_heading(cfg, nav, target, dt, prev_h)
    local heading_diff = wrap_deg180(cmd_h - head)

    -- 고도 및 승강률 목표 연산
    local alt_err = tgt_y - pos.y
    local target_climb = clamp(alt_err * 0.4, -4.0, 4.0)
    local climb_err = target_climb - (vel.y or 0.0)

    -- 기본 피치 요구각
    local desired_pitch = clamp(target_climb * 3.5, -15.0, 15.0)

    -- 외피 제한 및 모드 판정
    local pitch, roll, is_stall, flight_mode = fixed_wing_driver.compute_envelope_attitude(
        cfg, fsm_state, gs, airspeed, desired_pitch, heading_diff
    )

    -- 스로틀 연산 (TECS 에너지 균형)
    local throttle = cruise_throttle
    if is_stall then
        throttle = stall_throttle
    else
        throttle = clamp(cruise_throttle + climb_err * 0.12, 0.20, 1.0)
    end

    -- 플랩 전개 스케줄링 (저속 영역 또는 진입/착륙 시 전개)
    local flap_target = 0.0
    if airspeed < safe_spd or fsm_state == "APPROACH" or fsm_state == "LANDING" then
        local deficit = clamp((safe_spd - airspeed) / safe_spd, 0.0, 1.0)
        flap_target = math.max(0.3, deficit)
    end

    return {
        surge = throttle,
        sway = 0.0,
        heave = clamp(alt_err * 0.1, -1.0, 1.0),
        throttle = throttle,
        targetPitch = pitch,
        targetRoll = roll,
        targetHeading = cmd_h,
        targetClimbRate = target_climb,
        flapTarget = flap_target,
        isStallWarning = is_stall,
        flightMode = flight_mode
    }
end

return fixed_wing_driver
