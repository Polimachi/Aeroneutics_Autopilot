-- src/modules/guidance_controller.lua
local vectored_vtol_driver = require("vectored_vtol_driver")

local guidance_controller = {}
guidance_controller.SUPPORTED_AIRFRAMES = { VECTORED_VTOL = true }
guidance_controller.DEFERRED_AIRFRAMES = {
    FIXED_WING = true, WINGED_VTOL = true, QUADROTOR = true, HEXAROTOR = true,
}

local function clamp(val, min_v, max_v)
    if val < min_v then return min_v end
    if val > max_v then return max_v end
    return val
end

function guidance_controller.is_airframe_supported(airframe_type)
    if guidance_controller.SUPPORTED_AIRFRAMES[airframe_type] then
        return true, nil
    end
    return false, "UNSUPPORTED_AIRFRAME_DEFERRED"
end

function guidance_controller.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    local safe = cfg.safety or {}
    return {
        config = cfg,
        airframeType = sys.airframeType or "VECTORED_VTOL",
        bumplessRampSec = safe.bumplessRampSec or 2.0,
        rampStartMs = 0,
        wasInHold = false,
        driver_state = { prev_heading = 0.0 },
    }
end

function guidance_controller.compute_l1(state, pos, vel, wp_prev, wp_next)
    local vx, vz = vel.x or 0.0, vel.z or 0.0
    local gs = math.sqrt(vx * vx + vz * vz)
    local l1_dist = math.max(15.0, gs * 1.5)
    local seg_x = wp_next.x - wp_prev.x
    local seg_z = wp_next.z - wp_prev.z
    local seg_len = math.sqrt(seg_x * seg_x + seg_z * seg_z)
    if seg_len < 0.01 then
        return { x = wp_next.x, y = wp_next.y or pos.y, z = wp_next.z }, 0.0
    end
    local nx, nz = seg_x / seg_len, seg_z / seg_len
    local px, pz = pos.x - wp_prev.x, pos.z - wp_prev.z
    local proj = px * nx + pz * nz
    local xtrack = px * (-nz) + pz * nx
    local carrot_dist = clamp(proj + l1_dist, 0.0, seg_len)
    return {
        x = wp_prev.x + nx * carrot_dist,
        y = wp_next.y or pos.y,
        z = wp_prev.z + nz * carrot_dist,
    }, xtrack
end

function guidance_controller.compute_longitudinal(state, nav, target_alt, target_climb_rate, dt)
    local pos_y = nav and nav.pos and nav.pos.y or 64.0
    local vel_y = nav and nav.vel and nav.vel.y or 0.0
    local alt_err = target_alt - pos_y
    local heave = clamp(0.12 * alt_err - 0.15 * vel_y, -1.0, 1.0)
    local hover_thr = 0.635
    local thr = clamp(hover_thr + heave * 0.35, 0.0, 1.0)
    return heave, thr
end

local function apply_ramping(state, raw_cmd, now_ms)
    local ramp_duration_ms = state.bumplessRampSec * 1000.0
    local elapsed = (now_ms or 0) - state.rampStartMs
    local lambda = clamp(elapsed / ramp_duration_ms, 0.0, 1.0)
    raw_cmd.surge = raw_cmd.surge * lambda
    raw_cmd.sway = raw_cmd.sway * lambda
    return raw_cmd
end

function guidance_controller.pack_attitude_cmd(state, raw, fsm_state, is_flight_active)
    local r = raw or {}
    local mode = fsm_state or "CRUISE"
    local active = (is_flight_active == true)
    local af = state and state.airframeType
    local isAero = (af == "FIXED_WING" or af == "WINGED_VTOL")
    local flap = 0.0
    if isAero then
        if mode == "TAKEOFF" then flap = 0.35
        elseif mode == "APPROACH_LAND" or mode == "EMERGENCY_LAND" then flap = 1.0 end
    end

    return {
        source = "FCP",
        arm = true,
        flightActive = active,
        flightMode = mode,
        commandType = "ATTITUDE_ANGLE",
        angleTargets = {
            targetPitch = r.targetPitch or 0.0,
            targetRoll = r.targetRoll or 0.0,
            targetHeading = r.targetHeading or 0.0,
            turnRateFF = r.turnRateFF or 0.0,
        },
        targetThrottle = r.throttle or 0.0,
        targetClimbRate = r.targetClimbRate or 0.0,
        flapTarget = flap,
        translationBias = {
            surge = r.surge or 0.0,
            sway = r.sway or 0.0,
            heave = r.heave or 0.0,
        },
        acroActive = false,
        surge = r.surge or 0.0,
        sway = r.sway or 0.0,
        heave = r.heave or 0.0,
        throttle = r.throttle or 0.0,
        targetPitch = r.targetPitch or 0.0,
        targetRoll = r.targetRoll or 0.0,
        targetHeading = r.targetHeading or 0.0,
        mode = r.mode or "VECTORED_VTOL",
    }
end

function guidance_controller.compute(state, nav, mission_target, fsm_ctx, dt)
    local supported, reason = guidance_controller.is_airframe_supported(state.airframeType)
    if not supported then return nil, reason end

    local fsm_state = fsm_ctx and fsm_ctx.state or "CRUISE"
    local now = fsm_ctx and fsm_ctx.now_ms or 0

    if fsm_state == "FAILSAFE_HOLD" then
        if not state.wasInHold then
            vectored_vtol_driver.reset_integrals(state.driver_state)
        end
        state.wasInHold = true
    elseif state.wasInHold and fsm_state ~= "FAILSAFE_HOLD" then
        state.wasInHold = false
        state.rampStartMs = now
        vectored_vtol_driver.reset_integrals(state.driver_state)
    elseif fsm_state == "DISARMED" then
        vectored_vtol_driver.reset_integrals(state.driver_state)
    end

    local raw = vectored_vtol_driver.compute(state.config, nav, mission_target, fsm_state, dt, state.driver_state)
    state.driver_state.prev_heading = raw.targetHeading

    if (now - state.rampStartMs) < (state.bumplessRampSec * 1000.0) and fsm_state == "CRUISE" then
        raw = apply_ramping(state, raw, now)
    end
    raw.mode = "VECTORED_VTOL"

    local is_active = (fsm_ctx and fsm_ctx.flightActive)
    if is_active == nil then
        local inactive = { BOOT_INIT = true, DISARMED = true, ARMING = true, IDLE_ARMED = true, PASSIVE_TRACKING = true }
        is_active = not inactive[fsm_state]
    end
    return guidance_controller.pack_attitude_cmd(state, raw, fsm_state, is_active), nil
end

return guidance_controller
