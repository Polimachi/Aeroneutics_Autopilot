--[[
    ========================================================================
    HELICOPTER GUIDANCE DRIVER (helicopter_driver.lua)
    UAFS FCP Layer 2: Rotary-Wing (Helicopter) Guidance & Anti-Torque Driver
    
    [역할]
    - AIRFRAME = "HELICOPTER" 표준 가이던스 드라이버
    - Collective Throttle 및 틸트 코사인 양력 손실 보상 (Tilt Cosine Compensation)
    - 메인 로터 토크 반동 상쇄 전향 보상 (Anti-Torque Feed-forward) 지시
    - 사이클릭 틸트 한계 관리 및 Autorotation 비상 강하 모드 지원
    ========================================================================
]]

local helicopter_driver = {}
helicopter_driver.AIRFRAME = "HELICOPTER"

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

--- 틸트 각도에 따른 수직 양력 손실 보상 계수 산출 (1.0 / (cos(P) * cos(R)))
---@param curPitch number? 피치각 (도)
---@param curRoll number? 롤각 (도)
---@return number tiltScale
function helicopter_driver.computeTiltScale(curPitch, curRoll)
    local radP = math.rad(curPitch or 0.0)
    local radR = math.rad(curRoll or 0.0)
    local cosFactor = math.max(0.70, math.cos(radP) * math.cos(radR))
    return 1.0 / cosFactor
end

--- 경로 또는 타겟 지향 헤딩 산출
---@param cfg table
---@param nav table
---@param target table
---@param dt number
---@param prev_heading number?
---@return number targetHeading
function helicopter_driver.compute_heading(cfg, nav, target, dt, prev_heading)
    local g = cfg and cfg.guidance and (cfg.guidance.helicopter or cfg.guidance.heli) or {}
    local max_rate = g.maxYawRateDegPerSec or 35.0
    local prev_h = prev_heading or (nav and nav.attitude and nav.attitude.heading) or 0.0
    local mode = g.headingMode or "FACE_PATH"

    local target_h = prev_h
    if target and target.x and target.z and nav and nav.pos then
        local dx = target.x - nav.pos.x
        local dz = target.z - nav.pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if mode == "FACE_PATH" and dist >= 1.5 then
            target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
        elseif mode == "TARGET_LOCK" then
            target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
        end
    end

    local diff = wrap_deg180(target_h - prev_h)
    local max_step = max_rate * dt
    local step = clamp(diff, -max_step, max_step)
    return (prev_h + step + 360.0) % 360.0
end

--- 비상 오토로테이션 강하 지시 연산
---@param nav table
---@return table
local function compute_emergency(nav)
    local head = nav.attitude and nav.attitude.heading or 0.0
    return {
        surge = 0.0,
        sway = 0.0,
        heave = -0.5,
        throttle = 0.25,
        targetPitch = 0.0,
        targetRoll = 0.0,
        targetHeading = head,
        targetClimbRate = -2.5,
        antiTorqueFeedforward = 0.10,
        flightMode = "AUTOROTATION_DESCENT"
    }
end

--- 헬리콥터 비행 유도 명령 산출 메인 엔트리
---@param cfg table
---@param nav table
---@param target table
---@param fsm_state string
---@param dt number
---@param driver_state table?
---@return table
function helicopter_driver.compute(cfg, nav, target, fsm_state, dt, driver_state)
    if fsm_state == "EMERGENCY_LAND" then
        return compute_emergency(nav)
    end

    local g = cfg and cfg.guidance and (cfg.guidance.helicopter or cfg.guidance.heli) or {}
    local hover_throttle = g.hoverThrottle or 0.65
    local anti_torque_gain = g.antiTorqueGain or 0.35
    local cyclic_max_angle = g.cyclicMaxAngle or 15.0

    local pos = nav.pos or { x = 0, y = 64, z = 0 }
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local att = nav.attitude or { pitch = 0, roll = 0, heading = 0 }
    local cur_pitch = att.pitch or 0.0
    local cur_roll = att.roll or 0.0
    local cur_head = att.heading or 0.0
    local tgt_x, tgt_y, tgt_z = target.x or pos.x, target.y or pos.y, target.z or pos.z

    -- 위치 오차를 기체 좌표계로 사상
    local err_x = tgt_x - pos.x
    local err_z = tgt_z - pos.z
    local err_surge, err_sway = project_to_body(err_x, err_z, cur_head)
    local vel_surge, vel_sway = project_to_body(vel.x, vel.z, cur_head)

    -- 수평 위치 PID 오차를 사이클릭 목표 각도로 변환
    local skp, skd = g.surgeKp or 0.12, g.surgeKd or 0.08
    local wkp, wkd = g.swayKp or 0.12, g.swayKd or 0.08
    local target_pitch = clamp(-(skp * err_surge - skd * vel_surge) * cyclic_max_angle, -cyclic_max_angle, cyclic_max_angle)
    local target_roll  = clamp((wkp * err_sway - wkd * vel_sway) * cyclic_max_angle, -cyclic_max_angle, cyclic_max_angle)

    -- 고도 및 승강률 제어 + 틸트 양력 손실 보상
    local alt_err = tgt_y - pos.y
    local target_climb = clamp(alt_err * 0.5, -4.0, 4.0)
    local climb_err = target_climb - (vel.y or 0.0)
    local tilt_scale = helicopter_driver.computeTiltScale(cur_pitch, cur_roll)
    local raw_throttle = hover_throttle + climb_err * (g.climbKp or 0.10)
    local collective_throttle = clamp(raw_throttle * tilt_scale, 0.0, 1.0)

    -- 헤딩 산출
    local prev_h = driver_state and driver_state.prev_heading or cur_head
    local cmd_h = helicopter_driver.compute_heading(cfg, nav, target, dt, prev_h)

    -- 테일로터 안티토크 전향 보상치
    local anti_torque_ff = clamp(collective_throttle * anti_torque_gain, 0.0, 1.0)

    return {
        surge = clamp(err_surge * 0.2, -1.0, 1.0),
        sway = clamp(err_sway * 0.2, -1.0, 1.0),
        heave = clamp(alt_err * 0.2, -1.0, 1.0),
        throttle = collective_throttle,
        targetPitch = target_pitch,
        targetRoll = target_roll,
        targetHeading = cmd_h,
        targetClimbRate = target_climb,
        antiTorqueFeedforward = anti_torque_ff,
        flightMode = "HOVER_STABILIZED"
    }
end

return helicopter_driver
