-- src/modules/vectored_vtol_driver.lua
local vectored_vtol_driver = {}
vectored_vtol_driver.AIRFRAME = "VECTORED_VTOL"

local function clamp(val, min_v, max_v)
    if val < min_v then return min_v end
    if val > max_v then return max_v end
    return val
end

local function project_to_body(ux, uz, heading_deg)
    local rad = math.rad(heading_deg or 0.0)
    local sin_h, cos_h = math.sin(rad), math.cos(rad)
    local surge = ux * sin_h - uz * cos_h
    local sway = ux * cos_h + uz * sin_h
    return surge, sway
end

local function wrap_deg180(deg)
    local d = (deg + 180.0) % 360.0
    if d < 0 then d = d + 360.0 end
    return d - 180.0
end

function vectored_vtol_driver.compute_heading(cfg, nav, target, dt, prev_heading)
    local g = cfg and cfg.guidance and cfg.guidance.vectored_vtol or {}
    local max_rate = g.maxYawRateDegPerSec or 30.0
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

function vectored_vtol_driver.compute_envelope_attitude(cfg, fsm_state, ground_speed, surge_raw)
    local g = cfg and cfg.guidance and cfg.guidance.vectored_vtol or {}
    local mode = g.envelopeMode or "STRICT_LEVEL"
    if mode ~= "TILT_ASSISTED" or fsm_state ~= "CRUISE" then
        return 0.0, 0.0
    end
    local thresh = g.tiltAssistedThresholdSpeedMps or 15.0
    local max_pitch = g.tiltAssistedMaxPitchDeg or 10.0
    local s_raw = surge_raw or 0.0
    if (ground_speed or 0.0) > thresh or math.abs(s_raw) >= 0.95 then
        local pitch = clamp(-s_raw * max_pitch, -max_pitch, max_pitch)
        return pitch, 0.0
    end
    return 0.0, 0.0
end

local function compute_emergency(nav, hover_thr)
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local head = nav.attitude and nav.attitude.heading or 0.0
    local vsurge, vsway = project_to_body(vel.x, vel.z, head)
    local heave = clamp(0.2 * (-2.0 - vel.y), -0.5, 0.5)
    return {
        surge = clamp(-0.2 * vsurge, -0.3, 0.3),
        sway = clamp(-0.2 * vsway, -0.3, 0.3),
        heave = heave,
        throttle = clamp(hover_thr + heave * 0.35, 0.0, 1.0),
        targetPitch = 0.0,
        targetRoll = 0.0,
        targetHeading = head,
        targetClimbRate = -2.0,
    }
end

function vectored_vtol_driver.compute(cfg, nav, target, fsm_state, dt, driver_state)
    local g = cfg and cfg.guidance and cfg.guidance.vectored_vtol or {}
    local hover_thr = g.hoverThrottle or 0.635
    if fsm_state == "EMERGENCY_LAND" then
        return compute_emergency(nav, hover_thr)
    end

    local pos = nav.pos or { x = 0, y = 64, z = 0 }
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local head = nav.attitude and nav.attitude.heading or 0.0
    local tgt_x, tgt_y, tgt_z = target.x or pos.x, target.y or pos.y, target.z or pos.z

    local err_x = tgt_x - pos.x
    local err_z = tgt_z - pos.z
    local err_surge, err_sway = project_to_body(err_x, err_z, head)
    local vel_surge, vel_sway = project_to_body(vel.x, vel.z, head)

    local skp, skd = g.surgeKp or 0.15, g.surgeKd or 0.08
    local wkp, wkd = g.swayKp or 0.15, g.swayKd or 0.08
    local hkp, hkd = g.heaveKp or 0.12, g.heaveKd or 0.15

    local surge = clamp(skp * err_surge - skd * vel_surge, -1.0, 1.0)
    local sway = clamp(wkp * err_sway - wkd * vel_sway, -1.0, 1.0)
    local heave = clamp(hkp * (tgt_y - pos.y) - hkd * vel.y, -1.0, 1.0)
    local throttle = clamp(hover_thr + heave * 0.35, 0.0, 1.0)

    local gs = nav.groundSpeed or math.sqrt(vel.x * vel.x + vel.z * vel.z)
    local pitch, roll = vectored_vtol_driver.compute_envelope_attitude(cfg, fsm_state, gs, surge)
    local prev_h = driver_state and driver_state.prev_heading or head
    local cmd_h = vectored_vtol_driver.compute_heading(cfg, nav, target, dt, prev_h)

    return {
        surge = surge, sway = sway, heave = heave, throttle = throttle,
        targetPitch = pitch, targetRoll = roll, targetHeading = cmd_h,
        targetClimbRate = clamp((tgt_y - pos.y) * 0.5, -5.0, 5.0),
    }
end

return vectored_vtol_driver
