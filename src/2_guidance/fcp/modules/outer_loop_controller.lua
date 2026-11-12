-- src/2_guidance/fcp/modules/outer_loop_controller.lua
-- FCP v2.0.0 Unified SE(3) Outer-Loop Controller
-- Supports 6 Airframes: FIXED_WING, WINGED_VTOL, VECTORED_VTOL, ADVANCED_VTOL, QUADROTOR, HEXAROTOR
-- CC:Tweaked Lua 5.2 / Cobalt VM compliant: all functions <= 50 lines, Zero-Fallback

local outer_loop_controller = {}

local VALID_AIRFRAMES = {
    FIXED_WING = true,
    WINGED_VTOL = true,
    VECTORED_VTOL = true,
    ADVANCED_VTOL = true,
    QUADROTOR = true,
    HEXAROTOR = true,
}

function outer_loop_controller.is_airframe_supported(airframeType)
    if not airframeType or type(airframeType) ~= "string" then return false end
    return VALID_AIRFRAMES[airframeType] == true
end

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

local function euler_deg_to_quat(pitchDeg, rollDeg, yawDeg)
    local p = math.rad(tonumber(pitchDeg) or 0.0) * 0.5
    local r = math.rad(tonumber(rollDeg) or 0.0) * 0.5
    local y = math.rad(tonumber(yawDeg) or 0.0) * 0.5

    local cp, sp = math.cos(p), math.sin(p)
    local cr, sr = math.cos(r), math.sin(r)
    local cy, sy = math.cos(y), math.sin(y)

    local q = {
        w = cr * cp * cy + sr * sp * sy,
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy
    }
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if n > 1e-9 then
        local inv = 1.0 / n
        return { w = q.w * inv, x = q.x * inv, y = q.y * inv, z = q.z * inv }
    end
    return { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
end

local function compute_yaw_cmd(prev_h, target_h, maxYawRate, dt)
    local diff = wrap_deg180(target_h - prev_h)
    local max_step = (maxYawRate or 30.0) * dt
    local step = clamp(diff, -max_step, max_step)
    local new_h = (prev_h + step + 360.0) % 360.0
    local yawRate = (dt > 1e-6) and (step / dt) or 0.0
    return new_h, yawRate
end

local function update_axis_integrator(curr_int, err, ki, limit, dt, satPos, satNeg)
    if satPos and err > 0 then
        return curr_int
    end
    if satNeg and err < 0 then
        return curr_int
    end
    local delta = (ki or 0.0) * err * dt
    return clamp(curr_int + delta, -limit, limit)
end

local function get_se3_gains(cfg)
    local se3 = (cfg and cfg.se3) or {}
    local kp = se3.kp or { x = 1.6, y = 2.2, z = 1.6 }
    local kd = se3.kd or { x = 1.4, y = 1.8, z = 1.4 }
    local ki = se3.ki or { x = 0.08, y = 0.12, z = 0.08 }
    local drag = se3.drag or { x = 0.02, y = 0.0, z = 0.02 }
    local lim = se3.integralLimit or { x = 3.0, y = 4.0, z = 3.0 }
    local g = tonumber(se3.gravityMps2) or 11.0
    return kp, kd, ki, drag, lim, g
end

function outer_loop_controller.init(cfg)
    local c = cfg or {}
    local sys = c.system or {}
    return {
        airframeType = sys.airframeType or "VECTORED_VTOL",
        cfg = c,
        integrators = { x = 0.0, y = 0.0, z = 0.0 },
        prev_heading = nil,
        prev_surge = 0.0,
        prev_sway = 0.0,
        current_pitch = 0.0,
        current_roll = 0.0,
        holdPos = nil,
    }
end

function outer_loop_controller.reset_integrators(state)
    if not state then return end
    state.integrators = { x = 0.0, y = 0.0, z = 0.0 }
end

local function check_sat_flags(satFlags, axis, surgeOrSwayOrHeave)
    if not satFlags then return false, false end
    local vSat = satFlags.vasSat or satFlags
    local posTable = vSat.axisSaturatedPos or satFlags.axisSaturatedPos or {}
    local negTable = vSat.axisSaturatedNeg or satFlags.axisSaturatedNeg or {}
    local satPos = posTable[axis] or posTable[surgeOrSwayOrHeave]
    local satNeg = negTable[axis] or negTable[surgeOrSwayOrHeave]
    if axis == "y" then
        satPos = satPos or vSat.thrustClamped or satFlags.thrustClamped
        satNeg = satNeg or vSat.thrustClamped or satFlags.thrustClamped
    else
        satPos = satPos or vSat.tiltClamped or satFlags.tiltClamped
        satNeg = satNeg or vSat.tiltClamped or satFlags.tiltClamped
    end
    return satPos == true, satNeg == true
end

function outer_loop_controller.compute_desired_accel(state, nav, setpoint, dt, satFlags)
    local d_t = (tonumber(dt) and dt > 0) and dt or 0.05
    local kp, kd, ki, drag, lim, g = get_se3_gains(state and state.cfg)
    local pos = (nav and nav.pos) or { x = 0, y = 64, z = 0 }
    local vel = (nav and (nav.vel or nav.velocity)) or { x = 0, y = 0, z = 0 }
    local vx, vy, vz = vel.vx or vel.x or 0.0, vel.vy or vel.y or 0.0, vel.vz or vel.z or 0.0

    local sp = setpoint or {}
    local tpos = sp.targetPos or pos
    local tvel = sp.targetVel or { x = 0, y = 0, z = 0 }
    local tvx, tvy, tvz = tvel.vx or tvel.x or 0.0, tvel.vy or tvel.y or 0.0, tvel.vz or tvel.z or 0.0

    local ex = (tpos.x or pos.x) - pos.x
    local ey = (tpos.y or pos.y) - pos.y
    local ez = (tpos.z or pos.z) - pos.z

    local evx = tvx - vx
    local evy = tvy - vy
    local evz = tvz - vz

    local ff = sp.feedforwardAccel or {}
    local ffx = ff.ax or ff.x or 0.0
    local ffy = ff.ay or ff.y or 0.0
    local ffz = ff.az or ff.z or 0.0

    local ints = (state and state.integrators) or { x = 0.0, y = 0.0, z = 0.0 }
    local vSat = satFlags and satFlags.vasSat
    local actH = (satFlags and satFlags.actuatorHealth) or (vSat and vSat.actuatorHealth)
    local freeze = (satFlags and satFlags.navStale) or (vSat and vSat.navStale) or (actH and actH.tap == false)
    if not freeze and state then
        local spX, snX = check_sat_flags(satFlags, "x", "surge")
        local spY, snY = check_sat_flags(satFlags, "y", "heave")
        local spZ, snZ = check_sat_flags(satFlags, "z", "sway")
        ints.x = update_axis_integrator(ints.x, ex, ki.x, lim.x, d_t, spX, snX)
        ints.y = update_axis_integrator(ints.y, ey, ki.y, lim.y, d_t, spY, snY)
        ints.z = update_axis_integrator(ints.z, ez, ki.z, lim.z, d_t, spZ, snZ)
        state.integrators = ints
    end

    local alpha = (satFlags and tonumber(satFlags.rampAlpha)) or 1.0
    local ax = ffx + alpha * (kp.x * ex + kd.x * evx) + ints.x - drag.x * vx
    local ay = ffy + alpha * (kp.y * ey + kd.y * evy) + ints.y - drag.y * vy + g
    local az = ffz + alpha * (kp.z * ez + kd.z * evz) + ints.z - drag.z * vz

    return { ax = ax, ay = ay, az = az, x = ax, y = ay, z = az }
end

local function project_multirotor(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local cfg = state.cfg or {}
    local se3 = cfg.se3 or {}
    local hoverThr = tonumber(se3.hoverThrustRatio) or 0.635
    local maxTilt = tonumber(se3.multirotorMaxTiltDeg) or 25.0
    local g = tonumber(se3.gravityMps2) or 11.0

    local surge_a, sway_a = project_to_body(a_des.ax, a_des.az, heading)
    local ay = math.max(0.0, a_des.ay)
    local ay_tilt = math.max(0.5 * g, ay)

    local p_deg = clamp(math.deg(-math.atan2(surge_a, ay_tilt)), -maxTilt, maxTilt)
    local r_deg = clamp(math.deg(math.atan2(sway_a, ay_tilt)), -maxTilt, maxTilt)

    local quat = euler_deg_to_quat(p_deg, r_deg, heading)
    local rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = yawRateFF }

    local f_norm = math.sqrt(surge_a * surge_a + sway_a * sway_a + ay * ay)
    local colThrust = clamp(hoverThr * (f_norm / g), 0.0, 1.0)

    return quat, rates, colThrust, 0.0, nil
end

local function resolve_vtol_pitch(profile, swayLoss, surge, nav, sp, dt, state, se3)
    if swayLoss then return 0.0 end
    local mode = sp and sp.flightMode
    if mode == "LOITER" or mode == "POI_HOLD" then
        state.current_pitch = 0.0
        return 0.0
    end
    local target_p = 0.0
    if profile == "TILT_ASSISTED" then
        local vel = (nav and (nav.vel or nav.velocity)) or {}
        local vx = vel.vx or vel.x or 0.0
        local vz = vel.vz or vel.z or 0.0
        local gs = math.sqrt(vx * vx + vz * vz)
        local thresh = tonumber(se3.tiltAssistedThresholdSpeedMps) or 15.0
        if gs > thresh or math.abs(surge) >= 0.95 then
            local max_p = tonumber(se3.tiltAssistedMaxPitchDeg) or 10.0
            target_p = clamp(-surge * max_p, -max_p, max_p)
        end
    end
    local slew = (tonumber(se3.tiltSlewRateDegPerSec) or 15.0) * dt
    local cur_p = state.current_pitch or 0.0
    local new_p = cur_p + clamp(target_p - cur_p, -slew, slew)
    state.current_pitch = new_p
    return new_p
end

local function project_vtol_bias(state, a_des, sp, fsmCtx, dt, heading, is_advanced, swayLoss)
    local se3 = (state.cfg and state.cfg.se3) or {}
    local raw_s, raw_w = 0.0, 0.0
    if sp.translationBiasHint and not swayLoss then
        raw_s = clamp(tonumber(sp.translationBiasHint.surge) or 0.0, -1.0, 1.0)
        raw_w = clamp(tonumber(sp.translationBiasHint.sway) or 0.0, -1.0, 1.0)
    else
        local s_a, w_a = project_to_body(a_des.ax, a_des.az, heading)
        raw_s = clamp(s_a / 10.0, -1.0, 1.0)
        raw_w = swayLoss and 0.0 or clamp(w_a / 10.0, -1.0, 1.0)
    end

    local rampAlpha = (fsmCtx and tonumber(fsmCtx.rampAlpha)) or 1.0
    raw_s = raw_s * rampAlpha
    raw_w = raw_w * rampAlpha

    local surge = raw_s
    local sway = raw_w
    if is_advanced then
        local max_step = (tonumber(se3.gimbalSlewRate) or 2.0) * dt
        surge = state.prev_surge + clamp(raw_s - state.prev_surge, -max_step, max_step)
        sway = state.prev_sway + clamp(raw_w - state.prev_sway, -max_step, max_step)
    end
    state.prev_surge = surge
    state.prev_sway = sway
    return { surge = surge, sway = sway }
end

local function project_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF, is_advanced)
    local cfg = state.cfg or {}
    local se3 = cfg.se3 or {}
    local hoverThr = tonumber(se3.hoverThrustRatio) or 0.635
    local g = tonumber(se3.gravityMps2) or 11.0

    local swayLoss = (fsmCtx and ((fsmCtx.actuatorHealth and fsmCtx.actuatorHealth.tap == false)
                     or fsmCtx.swayLoss == true or (fsmCtx.vasSat and fsmCtx.vasSat.swayLoss == true)))
    local bias = project_vtol_bias(state, a_des, sp, fsmCtx, dt, heading, is_advanced, swayLoss)

    local profile = sp.constraintProfile or "STRICT_LEVEL"
    local pitch = resolve_vtol_pitch(profile, swayLoss, bias.surge, nav, sp, dt, state, se3)
    local roll = 0.0
    if swayLoss then
        local _, w_a = project_to_body(a_des.ax, a_des.az, heading)
        roll = clamp(math.deg(math.atan2(w_a, a_des.ay)), -25.0, 25.0)
    end

    local quat = euler_deg_to_quat(pitch, roll, heading)
    local rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = yawRateFF }
    local colThrust = clamp(hoverThr * (math.max(0.0, a_des.ay) / g), 0.0, 1.0)

    return quat, rates, colThrust, nil, bias
end

local function project_fixed_wing(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local cfg = state.cfg or {}
    local se3 = cfg.se3 or {}
    local turn = (cfg.guidance and cfg.guidance.turn) or {}
    local maxBank = tonumber(turn.nominalMaxBankDeg) or 20.0
    local g = tonumber(se3.gravityMps2) or 11.0

    local surge_a, sway_a = project_to_body(a_des.ax, a_des.az, heading)
    local bank_cmd = clamp(math.deg(math.atan2(sway_a, g)), -maxBank, maxBank)
    local maxRollStep = (tonumber(turn.bankSlewRateDegPerSec) or 45.0) * dt
    local roll = state.current_roll + clamp(bank_cmd - state.current_roll, -maxRollStep, maxRollStep)
    state.current_roll = roll

    local vel = (nav and (nav.vel or nav.velocity)) or {}
    local vx = vel.vx or vel.x or 0.0
    local vz = vel.vz or vel.z or 0.0
    local gs = math.max(math.sqrt(vx * vx + vz * vz), 1.0)
    local pitch_cmd = clamp(math.deg(math.atan2(a_des.ay - g, gs)), -20.0, 20.0)

    local rotSpeed = tonumber(se3.fixedWingRotationSpeedMps) or 12.0
    local stallSpeed = tonumber(se3.fixedWingStallSpeedMps) or 10.0
    if sp.flightMode == "TAKEOFF" and gs < rotSpeed then
        pitch_cmd = 0.0
    elseif gs < stallSpeed then
        pitch_cmd = clamp(pitch_cmd, -10.0, 5.0)
    end

    local yawRateBTT = (g / gs) * math.tan(math.rad(roll)) * (180.0 / math.pi)
    local totalYawRate = clamp(yawRateFF + yawRateBTT, -30.0, 30.0)

    local flap = 0.0
    if sp.flapHint ~= nil then
        flap = clamp(tonumber(sp.flapHint) or 0.0, 0.0, 1.0)
    else
        local mode = sp.flightMode
        if mode == "TAKEOFF" then flap = 0.35
        elseif mode == "APPROACH_LAND" then flap = 0.70
        elseif mode == "LANDING" then flap = 1.00
        end
    end

    local quat = euler_deg_to_quat(pitch_cmd, roll, heading)
    local rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = totalYawRate }
    local colThrust = clamp(0.70 + (surge_a / 20.0), 0.0, 1.0)

    return quat, rates, colThrust, flap, nil
end

local function project_winged_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local se3 = (state.cfg and state.cfg.se3) or {}
    local vLow = tonumber(se3.wingedVtolVLowMps) or 8.0
    local vHigh = tonumber(se3.wingedVtolVHighMps) or 18.0

    local vel = (nav and (nav.vel or nav.velocity)) or {}
    local vx = vel.vx or vel.x or 0.0
    local vz = vel.vz or vel.z or 0.0
    local gs = math.sqrt(vx * vx + vz * vz)
    local alpha = clamp((gs - vLow) / (vHigh - vLow), 0.0, 1.0)

    local qH, rH, thH, fH, biasH = project_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF, false)
    local qF, rF, thF, fF, biasF = project_fixed_wing(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)

    if alpha <= 0.0 then
        return qH, rH, thH, 0.0, biasH
    elseif alpha >= 1.0 then
        return qF, rF, thF, 0.0, nil
    end

    local flap = (sp.flapHint ~= nil) and clamp(tonumber(sp.flapHint) or 0.0, 0.0, 1.0) or 0.50
    local colThrust = (1.0 - alpha) * thH + alpha * thF
    local bias = biasH and { surge = biasH.surge * (1.0 - alpha), sway = biasH.sway * (1.0 - alpha) } or nil
    return qH, rH, colThrust, flap, bias
end

local function prepare_fsm_setpoint(state, nav, setpoint, fsmCtx)
    local sp = setpoint or {}
    local cState = fsmCtx and fsmCtx.currentState
    local pos = (nav and nav.pos) or { x = 0, y = 64, z = 0 }
    local head = (nav and nav.attitude and nav.attitude.heading) or 0.0

    if cState == "AMM_TIMEOUT_HOLD" then
        if not state.holdPos then
            state.holdPos = { x = pos.x, y = pos.y, z = pos.z }
        end
        return {
            targetPos = state.holdPos,
            targetVel = { x = 0.0, y = 0.0, z = 0.0, vx = 0.0, vy = 0.0, vz = 0.0 },
            feedforwardAccel = { x = 0.0, y = 0.0, z = 0.0, ax = 0.0, ay = 0.0, az = 0.0 },
            targetHeading = head,
            constraintProfile = "STRICT_LEVEL",
            flightMode = "HOVER_HOLD",
            arm = true,
            flightActive = true,
        }
    else
        state.holdPos = nil
    end

    if cState == "EMERGENCY_LAND" then
        local safe = (state.cfg and state.cfg.safety) or {}
        local descentRate = tonumber(safe.emergencyDescentRateMps) or -2.0
        return {
            targetPos = { x = pos.x, y = pos.y, z = pos.z },
            targetVel = { x = 0.0, y = descentRate, z = 0.0, vx = 0.0, vy = descentRate, vz = 0.0 },
            feedforwardAccel = { x = 0.0, y = 0.0, z = 0.0, ax = 0.0, ay = 0.0, az = 0.0 },
            targetHeading = head,
            constraintProfile = "STRICT_LEVEL",
            flightMode = "EMERGENCY_LAND",
            arm = true,
            flightActive = true,
        }
    end

    return sp
end

function outer_loop_controller.compute(state, nav, setpoint, fsmCtx, dt)
    local d_t = (tonumber(dt) and dt > 0) and dt or 0.05
    local s = state or outer_loop_controller.init()
    if fsmCtx and fsmCtx.resetIntegrators then
        outer_loop_controller.reset_integrators(s)
    end

    local sp = prepare_fsm_setpoint(s, nav, setpoint, fsmCtx)
    local prev_h = s.prev_heading or (nav and nav.attitude and nav.attitude.heading) or 0.0
    local target_h = (sp and sp.targetHeading) or prev_h
    local maxYaw = ((s.cfg and s.cfg.guidance and s.cfg.guidance.vectored_vtol) or {}).maxYawRateDegPerSec or 30.0
    local new_h, yawRateFF = compute_yaw_cmd(prev_h, target_h, maxYaw, d_t)
    s.prev_heading = new_h

    local a_des = outer_loop_controller.compute_desired_accel(s, nav, sp, d_t, fsmCtx)
    local af = s.airframeType or "VECTORED_VTOL"

    local quat, rates, colThrust, flap, bias
    if af == "QUADROTOR" or af == "HEXAROTOR" then
        quat, rates, colThrust, flap, bias = project_multirotor(s, a_des, nav, sp, fsmCtx, d_t, new_h, yawRateFF)
    elseif af == "VECTORED_VTOL" then
        quat, rates, colThrust, flap, bias = project_vtol(s, a_des, nav, sp, fsmCtx, d_t, new_h, yawRateFF, false)
    elseif af == "ADVANCED_VTOL" then
        quat, rates, colThrust, flap, bias = project_vtol(s, a_des, nav, sp, fsmCtx, d_t, new_h, yawRateFF, true)
    elseif af == "FIXED_WING" then
        quat, rates, colThrust, flap, bias = project_fixed_wing(s, a_des, nav, sp, fsmCtx, d_t, new_h, yawRateFF)
    elseif af == "WINGED_VTOL" then
        quat, rates, colThrust, flap, bias = project_winged_vtol(s, a_des, nav, sp, fsmCtx, d_t, new_h, yawRateFF)
    end

    local arm = (fsmCtx and fsmCtx.arm ~= nil) and fsmCtx.arm or (sp.arm ~= nil and sp.arm) or true
    local flightActive = (fsmCtx and fsmCtx.flightActive ~= nil) and fsmCtx.flightActive or (sp.flightActive ~= nil and sp.flightActive) or true

    return {
        source = "FCP",
        arm = arm,
        flightActive = flightActive,
        flightMode = sp.flightMode or "CRUISE",
        mode = af,
        commandType = "QUATERNION_RATE",
        targetQuaternion = quat,
        targetAngularRates = rates,
        collectiveThrust = colThrust,
        flapTarget = flap,
        translationBias = bias,
        acroActive = false,
    }
end

return outer_loop_controller
