-- src/2_guidance/fcp/modules/outer_loop_controller.lua
-- FCP v2.1.0 Unified SE(3) Outer-Loop Controller
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

local function normalize_quat(q)
    local n = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if n > 1e-9 then
        local inv = 1.0 / n
        return { w = q.w * inv, x = q.x * inv, y = q.y * inv, z = q.z * inv }
    end
    return { w = 1.0, x = 0.0, y = 0.0, z = 0.0 }
end

local function euler_deg_to_quat(pitchDeg, rollDeg, yawDeg)
    local p = math.rad(tonumber(pitchDeg) or 0.0) * 0.5
    local r = math.rad(tonumber(rollDeg) or 0.0) * 0.5
    local y = math.rad(tonumber(yawDeg) or 0.0) * 0.5
    local cp, sp = math.cos(p), math.sin(p)
    local cr, sr = math.cos(r), math.sin(r)
    local cy, sy = math.cos(y), math.sin(y)
    return normalize_quat({
        w = cr * cp * cy + sr * sp * sy,
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy,
    })
end

local function quat_to_euler_deg(q)
    local sinp = clamp(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0)
    local pitch = math.deg(math.asin(sinp))
    local roll = math.deg(math.atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)))
    local yaw = math.deg(math.atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)))
    return pitch, roll, yaw
end

local function quat_slerp(q1, q2, alpha)
    local dot = q1.w * q2.w + q1.x * q2.x + q1.y * q2.y + q1.z * q2.z
    local qb = { w = q2.w, x = q2.x, y = q2.y, z = q2.z }
    if dot < 0.0 then
        dot = -dot
        qb.w, qb.x, qb.y, qb.z = -qb.w, -qb.x, -qb.y, -qb.z
    end
    if dot > 0.9995 then
        local inv = 1.0 - alpha
        return normalize_quat({
            w = inv * q1.w + alpha * qb.w,
            x = inv * q1.x + alpha * qb.x,
            y = inv * q1.y + alpha * qb.y,
            z = inv * q1.z + alpha * qb.z,
        })
    end
    local theta0 = math.acos(clamp(dot, -1.0, 1.0))
    local theta = theta0 * alpha
    local sin0 = math.sin(theta0)
    local s2 = math.sin(theta) / sin0
    local s1 = math.cos(theta) - dot * s2
    return normalize_quat({
        w = s1 * q1.w + s2 * qb.w,
        x = s1 * q1.x + s2 * qb.x,
        y = s1 * q1.y + s2 * qb.y,
        z = s1 * q1.z + s2 * qb.z,
    })
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
    if satPos and err > 0 then return curr_int end
    if satNeg and err < 0 then return curr_int end
    local delta = (ki or 0.0) * err * dt
    return clamp(curr_int + delta, -limit, limit)
end

local function get_outer_loop_gains(cfg)
    local ol = (cfg and cfg.outerLoop) or {}
    local kp = ol.kpPos or { x = 0.90, y = 1.10, z = 0.90 }
    local kd = ol.kdVel or { x = 1.20, y = 1.35, z = 1.20 }
    local ki = ol.kiPos or { x = 0.05, y = 0.08, z = 0.05 }
    local maxAcc = tonumber(ol.maxAccelMps2) or 6.5
    local maxInt = tonumber(ol.maxIntegralAccel) or 1.5
    local g = tonumber(ol.gravityMps2) or 11.0
    return kp, kd, ki, maxAcc, maxInt, g
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
        saturated = false,
        activeConstraintProfile = "STRICT_LEVEL",
    }
end

function outer_loop_controller.reset_integrators(state)
    if not state then return end
    state.integrators = { x = 0.0, y = 0.0, z = 0.0 }
    state.saturated = false
end

local function check_sat_flags(satFlags, axis, bodyAxis)
    if not satFlags then return false, false end
    local vSat = satFlags.vasSat or {}
    local spPos = satFlags.axisSaturatedPos or vSat.axisSaturatedPos or {}
    local spNeg = satFlags.axisSaturatedNeg or vSat.axisSaturatedNeg or {}
    local satPos = spPos[axis] or spPos[bodyAxis]
    local satNeg = spNeg[axis] or spNeg[bodyAxis]
    if axis == "y" then
        satPos = satPos or vSat.thrustClamped or satFlags.thrustClamped
        satNeg = satNeg or vSat.thrustClamped or satFlags.thrustClamped
    else
        satPos = satPos or vSat.tiltClamped or satFlags.tiltClamped
        satNeg = satNeg or vSat.tiltClamped or satFlags.tiltClamped
    end
    return satPos == true, satNeg == true
end

local function step_integrators(state, ex, ey, ez, ki, maxInt, d_t, satFlags)
    local ints = (state and state.integrators) or { x = 0.0, y = 0.0, z = 0.0 }
    local vSat = satFlags and satFlags.vasSat
    local actH = (satFlags and satFlags.actuatorHealth) or (vSat and vSat.actuatorHealth)
    local freeze = (satFlags and satFlags.navStale) or (vSat and vSat.navStale) or (actH and actH.tap == false)
    if not freeze and state then
        local spX, snX = check_sat_flags(satFlags, "x", "surge")
        local spY, snY = check_sat_flags(satFlags, "y", "heave")
        local spZ, snZ = check_sat_flags(satFlags, "z", "sway")
        ints.x = update_axis_integrator(ints.x, ex, ki.x, maxInt, d_t, spX, snX)
        ints.y = update_axis_integrator(ints.y, ey, ki.y, maxInt, d_t, spY, snY)
        ints.z = update_axis_integrator(ints.z, ez, ki.z, maxInt, d_t, spZ, snZ)
        state.integrators = ints
    end
    return ints
end

function outer_loop_controller.compute_desired_accel(state, nav, setpoint, dt, satFlags)
    local d_t = (tonumber(dt) and dt > 0) and dt or 0.05
    local kp, kd, ki, maxAcc, maxInt, g = get_outer_loop_gains(state and state.cfg)
    local pos = (nav and nav.pos) or { x = 0, y = 64, z = 0 }
    local vel = (nav and nav.vel) or {}
    local vx, vy, vz = vel.vx or 0.0, vel.vy or 0.0, vel.vz or 0.0
    local sp = setpoint or {}
    local tpos = sp.targetPos or pos
    local tvel = sp.targetVel or {}
    local tvx, tvy, tvz = tvel.vx or 0.0, tvel.vy or 0.0, tvel.vz or 0.0
    local ex, ey, ez = (tpos.x or pos.x) - pos.x, (tpos.y or pos.y) - pos.y, (tpos.z or pos.z) - pos.z
    local ints = step_integrators(state, ex, ey, ez, ki, maxInt, d_t, satFlags)
    local ff = sp.feedforwardAccel or {}
    local alpha = (satFlags and tonumber(satFlags.rampAlpha)) or 1.0
    local ax = (ff.ax or 0.0) + alpha * (kp.x * ex + kd.x * (tvx - vx)) + ints.x
    local ay_kin = (ff.ay or 0.0) + alpha * (kp.y * ey + kd.y * (tvy - vy)) + ints.y
    local az = (ff.az or 0.0) + alpha * (kp.z * ez + kd.z * (tvz - vz)) + ints.z
    local norm = math.sqrt(ax * ax + ay_kin * ay_kin + az * az)
    local saturated = (maxAcc > 0.0 and norm > maxAcc)
    if saturated then
        local s = maxAcc / norm
        ax, ay_kin, az = ax * s, ay_kin * s, az * s
    end
    if state then state.saturated = saturated end
    return { ax = ax, ay = ay_kin + g, az = az, saturated = saturated }
end

local function project_multirotor(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local ol = (state.cfg and state.cfg.outerLoop) or {}
    local mr = ol.multirotor or {}
    local hoverThr = tonumber(ol.hoverThrustNorm) or 0.635
    local maxTilt = tonumber(mr.maxTiltDeg) or 25.0
    local g = tonumber(ol.gravityMps2) or 11.0
    local surge_a, sway_a = project_to_body(a_des.ax, a_des.az, heading)
    local ay = math.max(0.0, a_des.ay)
    local ay_tilt = math.max(0.5 * g, ay)
    local p_deg = clamp(math.deg(-math.atan2(surge_a, ay_tilt)), -maxTilt, maxTilt)
    local r_deg = clamp(math.deg(math.atan2(sway_a, ay_tilt)), -maxTilt, maxTilt)
    local quat = euler_deg_to_quat(p_deg, r_deg, heading)
    local rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = yawRateFF }
    local f_norm = math.sqrt(surge_a * surge_a + sway_a * sway_a + ay * ay)
    local colThrust = clamp(hoverThr * (f_norm / g), 0.0, 1.0)
    state.activeConstraintProfile = sp.constraintProfile or "STRICT_LEVEL"
    return quat, rates, colThrust, 0.0, nil
end

local function resolve_vtol_pitch(profile, swayLoss, surge, sp, dt, state, subCfg)
    if swayLoss then return 0.0 end
    local mode = sp and sp.flightMode
    if mode == "LOITER" or mode == "POI_HOLD" then
        state.current_pitch = 0.0
        return 0.0
    end
    local target_p = 0.0
    if profile == "TILT_ASSISTED" then
        local max_p = tonumber(subCfg.tiltAssistedMaxPitchDeg) or 10.0
        target_p = clamp(-surge * max_p, -max_p, max_p)
    end
    local slew = (tonumber(subCfg.tiltSlewRateDegPerSec) or 15.0) * dt
    local cur_p = state.current_pitch or 0.0
    local new_p = cur_p + clamp(target_p - cur_p, -slew, slew)
    state.current_pitch = new_p
    return new_p
end

local function project_vtol_bias(state, a_des, sp, fsmCtx, dt, heading, is_advanced, swayLoss, subCfg)
    local raw_s, raw_w = 0.0, 0.0
    if sp.translationBiasHint and not swayLoss then
        raw_s = clamp(tonumber(sp.translationBiasHint.surge) or 0.0, -1.0, 1.0)
        raw_w = clamp(tonumber(sp.translationBiasHint.sway) or 0.0, -1.0, 1.0)
    else
        local s_a, w_a = project_to_body(a_des.ax, a_des.az, heading)
        local gain_s = tonumber(subCfg.surgeAccelToBiasGain) or 0.18
        local gain_w = tonumber(subCfg.swayAccelToBiasGain) or 0.18
        raw_s = clamp(s_a * gain_s, -1.0, 1.0)
        raw_w = swayLoss and 0.0 or clamp(w_a * gain_w, -1.0, 1.0)
    end
    local rampAlpha = (fsmCtx and tonumber(fsmCtx.rampAlpha)) or 1.0
    local surge, sway = raw_s * rampAlpha, raw_w * rampAlpha
    if is_advanced then
        local max_step = (tonumber(subCfg.gimbalSlewRate) or 2.0) * dt
        surge = state.prev_surge + clamp(surge - state.prev_surge, -max_step, max_step)
        sway = state.prev_sway + clamp(sway - state.prev_sway, -max_step, max_step)
    end
    state.prev_surge, state.prev_sway = surge, sway
    return { surge = surge, sway = sway }
end

local function project_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF, is_advanced)
    local ol = (state.cfg and state.cfg.outerLoop) or {}
    local subCfg = (is_advanced and ol.advanced_vtol or ol.vectored_vtol) or {}
    local hoverThr = tonumber(ol.hoverThrustNorm) or 0.635
    local g = tonumber(ol.gravityMps2) or 11.0
    local k_ty = tonumber(subCfg.thrustPerGScale) or 0.06
    local swayLoss = (fsmCtx and ((fsmCtx.actuatorHealth and fsmCtx.actuatorHealth.tap == false)
        or fsmCtx.swayLoss == true or (fsmCtx.vasSat and fsmCtx.vasSat.swayLoss == true)))
    local bias = project_vtol_bias(state, a_des, sp, fsmCtx, dt, heading, is_advanced, swayLoss, subCfg)
    local profile = sp.constraintProfile or "STRICT_LEVEL"
    local pitch = resolve_vtol_pitch(profile, swayLoss, bias.surge, sp, dt, state, subCfg)
    local roll = 0.0
    if swayLoss then
        local _, w_a = project_to_body(a_des.ax, a_des.az, heading)
        roll = clamp(math.deg(math.atan2(w_a, math.max(0.5 * g, a_des.ay))), -25.0, 25.0)
    end
    state.activeConstraintProfile = swayLoss and "TILT_ASSISTED" or profile
    local quat = euler_deg_to_quat(pitch, roll, heading)
    local rates = { pitchRate = 0.0, rollRate = 0.0, yawRate = yawRateFF }
    local colThrust = clamp(hoverThr + k_ty * (a_des.ay - g), 0.0, 1.0)
    return quat, rates, colThrust, nil, bias
end

local function resolve_fw_flap(sp)
    if sp.flapHint ~= nil then
        return clamp(tonumber(sp.flapHint) or 0.0, 0.0, 1.0)
    end
    local mode = sp.flightMode
    if mode == "TAKEOFF" then return 0.35 end
    if mode == "APPROACH_LAND" then return 0.70 end
    if mode == "LANDING" then return 1.00 end
    return 0.0
end

local function project_fixed_wing(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local ol = (state.cfg and state.cfg.outerLoop) or {}
    local fw = ol.fixed_wing or {}
    local g = tonumber(ol.gravityMps2) or 11.0
    local maxBank = (fsmCtx and fsmCtx.currentState == "AMM_TIMEOUT_HOLD") and 18.0 or (tonumber(fw.nominalMaxBankDeg) or 20.0)
    local _, sway_a = project_to_body(a_des.ax, a_des.az, heading)
    local maxRollStep = (tonumber(fw.bankSlewRateDegPerSec) or 45.0) * dt
    local roll = state.current_roll + clamp(clamp(math.deg(math.atan2(sway_a, g)), -maxBank, maxBank) - state.current_roll, -maxRollStep, maxRollStep)
    state.current_roll = roll
    local vel, tvel = (nav and nav.vel) or {}, sp.targetVel or {}
    local vx, vz = vel.vx or 0.0, vel.vz or 0.0
    local tvx, tvz = tvel.vx or 0.0, tvel.vz or 0.0
    local gs = math.sqrt(vx * vx + vz * vz)
    local v_ref = math.sqrt(tvx * tvx + tvz * tvz)
    local alt_err = ((sp.targetPos and sp.targetPos.y) or (nav and nav.pos and nav.pos.y) or 64.0) - ((nav and nav.pos and nav.pos.y) or 64.0)
    local ke_err = (v_ref * v_ref - gs * gs) / (2.0 * g)
    local maxPitch = tonumber(fw.nominalMaxPitchDeg) or 20.0
    local pitch_cmd = clamp((tonumber(fw.trimPitchDeg) or 2.5) + (tonumber(fw.balanceKp) or 0.65) * (alt_err - ke_err), -maxPitch, maxPitch)
    local colThrust = clamp((tonumber(fw.trimThrottle) or 0.70) + (tonumber(fw.energyKp) or 0.03) * (alt_err + ke_err), 0.0, 1.0)
    if sp.flightMode == "TAKEOFF" and gs < (tonumber(fw.rotationSpeedMps) or 12.0) then
        pitch_cmd = 0.0
    elseif gs < (tonumber(fw.stallSpeedMps) or 10.0) then
        pitch_cmd = clamp(pitch_cmd, -10.0, 5.0)
    end
    local maxYaw = tonumber(ol.maxYawRateDegPerSec) or 30.0
    local yawRateBTT = (g / math.max(gs, 1.0)) * math.tan(math.rad(roll)) * (180.0 / math.pi)
    state.activeConstraintProfile = sp.constraintProfile or "STRICT_LEVEL"
    return euler_deg_to_quat(pitch_cmd, roll, heading), { pitchRate = 0.0, rollRate = 0.0, yawRate = clamp(yawRateFF + yawRateBTT, -maxYaw, maxYaw) }, colThrust, resolve_fw_flap(sp), nil
end

local function project_winged_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    local ol = (state.cfg and state.cfg.outerLoop) or {}
    local wv = ol.winged_vtol or {}
    local vLow = tonumber(wv.vLowMps) or 8.0
    local vHigh = tonumber(wv.vHighMps) or 18.0
    local vel = (nav and nav.vel) or {}
    local vx, vz = vel.vx or 0.0, vel.vz or 0.0
    local gs = math.sqrt(vx * vx + vz * vz)
    local span = vHigh - vLow
    local alpha = (span > 1e-6) and clamp((gs - vLow) / span, 0.0, 1.0) or ((gs >= vHigh) and 1.0 or 0.0)
    local qH, rH, thH, _, biasH = project_vtol(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF, false)
    local qF, rF, thF, _, _ = project_fixed_wing(state, a_des, nav, sp, fsmCtx, dt, heading, yawRateFF)
    if alpha <= 0.0 then
        return qH, rH, thH, 0.0, biasH
    elseif alpha >= 1.0 then
        local flapHigh = (sp.flapHint ~= nil) and clamp(tonumber(sp.flapHint) or 0.0, 0.0, 1.0) or 0.0
        return qF, rF, thF, flapHigh, nil
    end
    local qBlend = quat_slerp(qH, qF, alpha)
    local pDeg, rDeg, yDeg = quat_to_euler_deg(qBlend)
    pDeg = clamp(pDeg, tonumber(wv.transitionMinPitchDeg) or -10.0, tonumber(wv.transitionMaxPitchDeg) or 12.0)
    local rates = {
        pitchRate = (1.0 - alpha) * rH.pitchRate + alpha * rF.pitchRate,
        rollRate = (1.0 - alpha) * rH.rollRate + alpha * rF.rollRate,
        yawRate = (1.0 - alpha) * rH.yawRate + alpha * rF.yawRate,
    }
    local flap = (sp.flapHint ~= nil) and clamp(tonumber(sp.flapHint) or 0.0, 0.0, 1.0) or (tonumber(wv.transitionFlapTarget) or 0.50)
    local bias = biasH and { surge = biasH.surge * (1.0 - alpha), sway = biasH.sway * (1.0 - alpha) } or nil
    return euler_deg_to_quat(pDeg, rDeg, yDeg), rates, (1.0 - alpha) * thH + alpha * thF, flap, bias
end

local function prepare_fsm_setpoint(state, nav, setpoint, fsmCtx)
    local sp = setpoint or {}
    local cState = fsmCtx and fsmCtx.currentState
    local pos = (nav and nav.pos) or { x = 0, y = 64, z = 0 }
    local head = (nav and nav.attitude and (nav.attitude.yaw or nav.attitude.heading)) or 0.0
    if cState == "AMM_TIMEOUT_HOLD" then
        if not state.holdPos then state.holdPos = { x = pos.x, y = pos.y, z = pos.z } end
        return {
            targetPos = state.holdPos,
            targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
            feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
            targetHeading = head,
            constraintProfile = "STRICT_LEVEL",
            flightMode = "HOVER_HOLD",
            arm = true,
            flightActive = true,
        }
    end
    state.holdPos = nil
    if cState == "EMERGENCY_LAND" then
        local safe = (state.cfg and state.cfg.safety) or {}
        local rawRate = (state.airframeType == "FIXED_WING") and (tonumber(safe.fixedWingGlideDescentMps) or -1.0) or (tonumber(safe.emergencyDescentRateMps) or -1.5)
        local descentRate = -math.abs(rawRate)
        return {
            targetPos = { x = pos.x, y = pos.y, z = pos.z },
            targetVel = { vx = 0.0, vy = descentRate, vz = 0.0 },
            feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
            targetHeading = head,
            constraintProfile = "STRICT_LEVEL",
            flightMode = "EMERGENCY_LAND",
            arm = true,
            flightActive = true,
        }
    end
    return sp
end

local function resolve_bool_flag(fsmCtx, sp, key, defaultVal)
    if fsmCtx and fsmCtx[key] ~= nil then return fsmCtx[key] == true end
    if sp and sp[key] ~= nil then return sp[key] == true end
    return defaultVal
end

function outer_loop_controller.compute(state, nav, setpoint, fsmCtx, dt)
    local d_t = (tonumber(dt) and dt > 0) and dt or 0.05
    local s = state or outer_loop_controller.init()
    if fsmCtx and fsmCtx.resetIntegrators then
        outer_loop_controller.reset_integrators(s)
    end
    local sp = prepare_fsm_setpoint(s, nav, setpoint, fsmCtx)
    local prev_h = s.prev_heading or (nav and nav.attitude and (nav.attitude.yaw or nav.attitude.heading)) or 0.0
    local target_h = (sp and sp.targetHeading) or prev_h
    local ol = (s.cfg and s.cfg.outerLoop) or {}
    local maxYaw = tonumber(ol.maxYawRateDegPerSec) or 30.0
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

    return {
        source = "FCP",
        arm = resolve_bool_flag(fsmCtx, sp, "arm", true),
        flightActive = resolve_bool_flag(fsmCtx, sp, "flightActive", true),
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
