-- src/modules/advanced_vtol_driver.lua
-- Dedicated outer-loop guidance driver for ADVANCED_VTOL airframes (2D nozzle gimbaled thruster VTOL).
local advanced_vtol_driver = {}
advanced_vtol_driver.AIRFRAME = "ADVANCED_VTOL"

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

function advanced_vtol_driver.resolve_horizontal_error(pos, target, fsm_state, g, cfg)
    local tgt_x = target and target.x or pos.x
    local tgt_z = target and target.z or pos.z
    if fsm_state ~= "LOITER" then
        return tgt_x - pos.x, tgt_z - pos.z, nil
    end
    local rx, rz = tgt_x - pos.x, tgt_z - pos.z
    local d_center = math.sqrt(rx * rx + rz * rz)
    local ux_out, uz_out = 0.0, -1.0
    if d_center > 0.1 then
        ux_out, uz_out = -rx / d_center, -rz / d_center
    end
    local dir = (target and target.loiterDirection == "CCW") and -1.0 or 1.0
    local tx_unit, tz_unit = -dir * uz_out, dir * ux_out
    local radius = math.max(5.0, tonumber(target and target.loiterRadius) or (g and g.orbitRadiusM) or (cfg and cfg.navigation and cfg.navigation.loiterRadiusM) or 30.0)
    local v_orbit = math.max(1.0, tonumber(target and target.targetSpeed) or (g and g.orbitSpeedMps) or 8.0)
    local k_rad = (g and g.loiterRadialKp) or 1.0
    local r_err = (radius - d_center) * k_rad
    local err_x = ux_out * r_err + tx_unit * v_orbit
    local err_z = uz_out * r_err + tz_unit * v_orbit
    local tan_hdg = (math.deg(math.atan2(tx_unit, -tz_unit)) + 360.0) % 360.0
    return err_x, err_z, tan_hdg
end

function advanced_vtol_driver.compute_heading(cfg, nav, target, dt, prev_heading, fsm_state, tangent_heading)
    local g = cfg and cfg.guidance and (cfg.guidance.advanced_vtol or cfg.guidance.vectored_vtol) or {}
    local max_rate = g.maxYawRateDegPerSec or 30.0
    local prev_h = prev_heading or (nav and nav.attitude and nav.attitude.heading) or 0.0
    local mode = (target and target.headingMode) or g.headingMode or "FACE_PATH"

    local target_h = prev_h
    if mode == "FIXED" and target and target.fixedHeading ~= nil then
        local fh = tonumber(target.fixedHeading)
        if fh and fh == fh and fh ~= math.huge and fh ~= -math.huge then
            target_h = ((fh % 360.0) + 360.0) % 360.0
        end
    elseif mode == "POI" or mode == "TARGET_LOCK" or mode == "ORBIT_POINT" or fsm_state == "POI_HOLD" then
        local poi = (target and target.poiTarget) or g.targetPoint or target
        if poi and poi.x and poi.z and nav and nav.pos then
            local dx = poi.x - nav.pos.x
            local dz = poi.z - nav.pos.z
            if (dx * dx + dz * dz) >= 0.25 then
                target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
            end
        end
    elseif mode == "AUTO" or mode == "FACE_PATH" then
        if fsm_state == "LOITER" then
            if target and target.poiTarget and target.poiTarget.x and target.poiTarget.z and nav and nav.pos then
                local dx = target.poiTarget.x - nav.pos.x
                local dz = target.poiTarget.z - nav.pos.z
                if (dx * dx + dz * dz) >= 0.25 then
                    target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
                end
            elseif tangent_heading ~= nil then
                target_h = tangent_heading
            end
        elseif target and target.x and target.z and nav and nav.pos then
            local dx = target.x - nav.pos.x
            local dz = target.z - nav.pos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist >= 1.5 then
                target_h = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
            end
        end
    end

    local diff = wrap_deg180(target_h - prev_h)
    local delta_t = dt or 0.05
    local max_step = max_rate * delta_t
    local step = clamp(diff, -max_step, max_step)
    return (prev_h + step + 360.0) % 360.0
end

function advanced_vtol_driver.compute_envelope_attitude(cfg, fsm_state, ground_speed, surge_raw, dt, driver_state)
    local g = cfg and cfg.guidance and (cfg.guidance.advanced_vtol or cfg.guidance.vectored_vtol) or {}
    local mode = g.envelopeMode or "STRICT_LEVEL"
    local prev_p = driver_state and driver_state.current_pitch or 0.0
    local delta_t = dt or 0.05
    local slew_rate = g.tiltSlewRateDegPerSec or 15.0
    local max_step = slew_rate * delta_t

    local target_pitch = 0.0
    if mode == "TILT_ASSISTED" and fsm_state == "CRUISE" then
        local thresh = g.tiltAssistedThresholdSpeedMps or 15.0
        local max_pitch = g.tiltAssistedMaxPitchDeg or 10.0
        local s_raw = surge_raw or 0.0
        if (ground_speed or 0.0) > thresh or math.abs(s_raw) >= 0.95 then
            target_pitch = clamp(-s_raw * max_pitch, -max_pitch, max_pitch)
        end
    end

    local diff = clamp(target_pitch - prev_p, -max_step, max_step)
    local new_pitch = prev_p + diff
    if driver_state then
        driver_state.current_pitch = new_pitch
    end
    return new_pitch, 0.0
end

local function compute_emergency(nav, hover_thr, emergency_descent)
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local head = nav.attitude and nav.attitude.heading or 0.0
    local vsurge, vsway = project_to_body(vel.x, vel.z, head)
    local descent = emergency_descent or -2.0
    local heave = clamp(0.2 * (descent - vel.y), -0.5, 0.5)
    local throttle = clamp(hover_thr + heave * 0.35, 0.0, 1.0)
    local surge = clamp(-0.2 * vsurge, -0.3, 0.3)
    local sway = clamp(-0.2 * vsway, -0.3, 0.3)
    return {
        surge = surge,
        sway = sway,
        heave = heave,
        throttle = throttle,
        targetThrottle = throttle,
        targetPitch = 0.0,
        targetRoll = 0.0,
        targetHeading = head,
        targetClimbRate = descent,
        translationBias = {
            surge = surge,
            sway = sway,
            heave = heave,
        },
        flapTarget = 0.0,
        mode = "ADVANCED_VTOL",
    }
end

function advanced_vtol_driver.reset_integrals(driver_state)
    if not driver_state then return end
    driver_state.surge_i = 0.0
    driver_state.sway_i = 0.0
    driver_state.heave_i = 0.0
    driver_state.current_pitch = 0.0
    driver_state.prev_surge = 0.0
    driver_state.prev_sway = 0.0
    driver_state.takeoff_origin_y = nil
end

function advanced_vtol_driver.compute(cfg, nav, target, fsm_state, dt, driver_state)
    local g = cfg and cfg.guidance and (cfg.guidance.advanced_vtol or cfg.guidance.vectored_vtol) or {}
    local hover_thr = g.hoverThrottle or 0.635
    if fsm_state == "EMERGENCY_LAND" then
        return compute_emergency(nav, hover_thr, g.emergencyDescentRateMps or -2.0)
    end

    local pos = nav.pos or { x = 0, y = 64, z = 0 }
    local vel = nav.vel or { x = 0, y = 0, z = 0 }
    local head = nav.attitude and nav.attitude.heading or 0.0
    local tgt_x = target and target.x or pos.x
    local tgt_y = target and target.y or pos.y
    local tgt_z = target and target.z or pos.z

    local err_x, err_z, tan_hdg = advanced_vtol_driver.resolve_horizontal_error(pos, target, fsm_state, g, cfg)
    local err_surge, err_sway = project_to_body(err_x, err_z, head)
    local vel_surge, vel_sway = project_to_body(vel.x, vel.z, head)

    local skp, skd = g.surgeKp or 0.15, g.surgeKd or 0.08
    local wkp, wkd = g.swayKp or 0.15, g.swayKd or 0.08
    local hkp, hkd = g.heaveKp or 0.12, g.heaveKd or 0.15

    local delta_t = dt or 0.05
    local ski = g.surgeKi or 0.02
    local smaxi = g.surgeMaxI or 0.20
    local wki = g.swayKi or 0.02
    local wmaxi = g.swayMaxI or 0.20
    local hki = g.heaveKi or 0.02
    local hmaxi = g.heaveMaxI or 0.20

    if driver_state then
        driver_state.surge_i = clamp((driver_state.surge_i or 0.0) + ski * err_surge * delta_t, -smaxi, smaxi)
        driver_state.sway_i = clamp((driver_state.sway_i or 0.0) + wki * err_sway * delta_t, -wmaxi, wmaxi)
        driver_state.heave_i = clamp((driver_state.heave_i or 0.0) + hki * (tgt_y - pos.y) * delta_t, -hmaxi, hmaxi)
    end
    local s_i = driver_state and driver_state.surge_i or 0.0
    local w_i = driver_state and driver_state.sway_i or 0.0
    local h_i = driver_state and driver_state.heave_i or 0.0

    local raw_surge = clamp(skp * err_surge - skd * vel_surge + s_i, -1.0, 1.0)
    local raw_sway = clamp(wkp * err_sway - wkd * vel_sway + w_i, -1.0, 1.0)
    local heave = clamp(hkp * (tgt_y - pos.y) - hkd * vel.y + h_i, -1.0, 1.0)
    local throttle = clamp(hover_thr + heave * 0.35, 0.0, 1.0)

    local takeoff_clearance = g.takeoffClearanceAltitudeM or 15.0
    local takeoff_climb = g.takeoffClimbRateMps or 2.5
    local approach_descent = g.approachDescentRateMps or -1.5
    local touchdown_descent = g.touchdownDescentRateMps or -0.5
    local align_dist = g.landingAlignDistanceM or 0.5

    local target_climb = clamp((tgt_y - pos.y) * 0.5, -5.0, 5.0)

    if fsm_state == "TAKEOFF" then
        if driver_state then
            if not driver_state.takeoff_origin_y then
                driver_state.takeoff_origin_y = pos.y
            end
            if pos.y < (driver_state.takeoff_origin_y + takeoff_clearance) then
                raw_surge = 0.0
                raw_sway = 0.0
                target_climb = takeoff_climb
            end
        else
            target_climb = takeoff_climb
        end
    elseif fsm_state == "APPROACH_LAND" then
        local dist_2d = math.sqrt(err_x * err_x + err_z * err_z)
        if dist_2d > align_dist then
            target_climb = approach_descent
        else
            target_climb = touchdown_descent
        end
    elseif fsm_state == "TOUCHDOWN" then
        target_climb = touchdown_descent
    else
        if driver_state then
            driver_state.takeoff_origin_y = nil
        end
    end

    local gimbal_slew = g.gimbalSlewRate or 2.0
    local max_bias_step = gimbal_slew * delta_t

    local prev_s = driver_state and driver_state.prev_surge or 0.0
    local diff_s = clamp(raw_surge - prev_s, -max_bias_step, max_bias_step)
    local surge = prev_s + diff_s

    local prev_w = driver_state and driver_state.prev_sway or 0.0
    local diff_w = clamp(raw_sway - prev_w, -max_bias_step, max_bias_step)
    local sway = prev_w + diff_w

    if driver_state then
        driver_state.prev_surge = surge
        driver_state.prev_sway = sway
    end

    local gs = nav.groundSpeed or math.sqrt(vel.x * vel.x + vel.z * vel.z)
    local pitch, roll = advanced_vtol_driver.compute_envelope_attitude(cfg, fsm_state, gs, surge, delta_t, driver_state)
    local prev_h = driver_state and driver_state.prev_heading or head
    local cmd_h = advanced_vtol_driver.compute_heading(cfg, nav, target, dt, prev_h, fsm_state, tan_hdg)

    return {
        surge = surge,
        sway = sway,
        heave = heave,
        throttle = throttle,
        targetThrottle = throttle,
        targetPitch = pitch,
        targetRoll = roll,
        targetHeading = cmd_h,
        targetClimbRate = target_climb,
        translationBias = {
            surge = surge,
            sway = sway,
            heave = heave,
        },
        flapTarget = 0.0,
        mode = "ADVANCED_VTOL",
    }
end

return advanced_vtol_driver
