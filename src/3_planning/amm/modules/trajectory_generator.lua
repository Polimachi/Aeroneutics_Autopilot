-- src/3_planning/amm/modules/trajectory_generator.lua
-- AMM 20Hz Trajectory Generator (11 Modes, LOITER/POI_HOLD, Virtual ILS, DOCKING & [I-12] Setpoint Builder)

local facility_client = require("facility_client")

local trajectory_generator = {}

trajectory_generator.MODES = {
    IDLE_ARMED = "IDLE_ARMED",
    TAKEOFF = "TAKEOFF",
    CRUISE = "CRUISE",
    LOITER = "LOITER",
    POI_HOLD = "POI_HOLD",
    APPROACH_LAND = "APPROACH_LAND",
    LANDING = "LANDING",
    DOCKING = "DOCKING",
    FAILSAFE_RTH = "FAILSAFE_RTH",
    HOVER_HOLD = "HOVER_HOLD",
    EMERGENCY_LAND = "EMERGENCY_LAND",
}

local function is_finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function sanitize_num(v, default)
    if is_finite(v) then return v end
    return default or 0.0
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

local function normalize_heading(deg)
    local d = (deg % 360.0 + 360.0) % 360.0
    return d
end

local function calc_distance_3d(p1, p2)
    local dx = (p2.x or 0.0) - (p1.x or 0.0)
    local dy = (p2.y or 0.0) - (p1.y or 0.0)
    local dz = (p2.z or 0.0) - (p1.z or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function apply_yaw_rate_limit(prev_h, target_h, max_rate, dt)
    local diff = wrap_deg180(target_h - prev_h)
    local max_step = max_rate * (dt or 0.05)
    local step = clamp(diff, -max_step, max_step)
    return normalize_heading(prev_h + step)
end

local function generate_idle(state, nav, fac, goal, dt, now_ms)
    local isArmed = (goal and goal.arm == true) or false
    return {
        arm = isArmed,
        flightActive = false,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = nav.pos.x, y = nav.pos.y, z = nav.pos.z },
        targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0,
        headingMode = "AUTO",
        distanceToWp = 0.0,
    }
end

local function generate_takeoff(state, nav, fac, goal, dt, now_ms)
    local cfgTraj = (state.config and state.config.trajectory) or {}
    local climbRate = cfgTraj.takeoffClimbRateMps or 2.5
    local clearanceAlt = cfgTraj.takeoffClearanceAltitudeM or 15.0

    if state.takeoffOriginY == nil then
        state.takeoffOriginY = nav.pos.y
        state.takeoffAnchorPos = { x = nav.pos.x, z = nav.pos.z }
    end

    local anchor = state.takeoffAnchorPos or nav.pos
    local targetY = sanitize_num(goal and goal.targetAlt, state.takeoffOriginY + clearanceAlt)
    local distRemaining = math.max(0.0, targetY - nav.pos.y)

    local isAero = (state.airframeType == "FIXED_WING" or state.airframeType == "WINGED_VTOL")
    local flap = isAero and 0.35 or 0.0

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = anchor.x, y = targetY, z = anchor.z },
        targetVel = { vx = 0.0, vy = climbRate, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0,
        headingMode = "FIXED",
        flapHint = flap,
        distanceToWp = distRemaining,
    }
end

local function generate_cruise(state, nav, fac, goal, dt, now_ms)
    local cfgDefSpeed = (state.config and state.config.defaultSpeed) or 18.0
    local targetSpeed = sanitize_num(goal and goal.targetSpeed, cfgDefSpeed)
    local tgt = (goal and goal.targetPos) or nav.pos
    local targetAlt = sanitize_num(goal and goal.targetAlt, tgt.y or nav.pos.y)
    local targetY = (goal and goal.targetPos) and sanitize_num(goal.targetPos.y, targetAlt) or targetAlt

    local dx = tgt.x - nav.pos.x
    local dy = targetY - nav.pos.y
    local dz = tgt.z - nav.pos.z
    local dist3D = math.sqrt(dx * dx + dy * dy + dz * dz)
    local dist2D = math.sqrt(dx * dx + dz * dz)

    local vx, vy, vz = 0.0, 0.0, 0.0
    if dist3D > 0.01 then
        vx = (dx / dist3D) * targetSpeed
        vy = (dy / dist3D) * targetSpeed
        vz = (dz / dist3D) * targetSpeed
    end

    local heading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0
    if dist2D >= 0.5 then
        heading = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
    end
    if goal and goal.headingMode == "FIXED" and goal.fixedHeadingDeg then
        heading = goal.fixedHeadingDeg
    end

    local flap = (goal and goal.flapHint) or 0.0
    return {
        arm = true,
        flightActive = true,
        constraintProfile = (goal and goal.constraintProfile) or "STANDARD",
        targetPos = { x = tgt.x, y = targetY, z = tgt.z },
        targetVel = { vx = vx, vy = vy, vz = vz },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = heading,
        headingMode = (goal and goal.headingMode) or "AUTO",
        flapHint = flap,
        distanceToWp = dist3D,
        activeWpIndex = goal and goal.activeWpIndex,
    }
end

local function calc_orbit_tangent_and_accel(rx, rz, R, v_t, isCCW)
    local r = math.sqrt(rx * rx + rz * rz)
    local ux, uz
    if r < 1e-3 then
        ux, uz, r = 0.0, -1.0, 0.0
    else
        ux, uz = rx / r, rz / r
    end
    local dir = isCCW and -1.0 or 1.0
    local tx = -dir * uz
    local tz = dir * ux
    local ac = (v_t * v_t) / R
    return ux, uz, tx, tz, r, -ux * ac, -uz * ac
end

local function generate_loiter(state, nav, fac, goal, dt, now_ms)
    local cfgTraj = (state.config and state.config.trajectory) or {}
    local center = (goal and goal.targetPos) or nav.pos
    local targetAlt = sanitize_num(goal and goal.targetAlt, center.y or nav.pos.y)
    local rawR = tonumber(goal and goal.loiterRadius) or cfgTraj.loiterRadiusM or 30.0
    local R = math.max(5.0, rawR)
    local rawVt = tonumber(goal and goal.targetSpeed) or cfgTraj.loiterSpeedMps or 10.0
    local v_t = math.max(1.0, rawVt)
    local kp = cfgTraj.loiterRadialKp or 1.0
    local maxRate = cfgTraj.maxYawRateDegPerSec or 30.0

    local isCCW = (goal and goal.loiterDirection == "CCW")
    local rx = nav.pos.x - center.x
    local rz = nav.pos.z - center.z
    local ux, uz, tx, tz, r, ax_in, az_in = calc_orbit_tangent_and_accel(rx, rz, R, v_t, isCCW)

    local v_tan_x = tx * v_t
    local v_tan_z = tz * v_t
    local r_err = R - r
    local v_rad_x = ux * (r_err * kp)
    local v_rad_z = uz * (r_err * kp)

    local tan_hdg = (math.deg(math.atan2(tx, -tz)) + 360.0) % 360.0
    local heading = apply_yaw_rate_limit(state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0, tan_hdg, maxRate, dt)
    local maxVert = tonumber(goal and goal.maxVertSpeedMps) or cfgTraj.loiterVertSpeedMps or 3.0
    local alt_err = targetAlt - nav.pos.y
    local vy = (math.abs(alt_err) > 0.1) and clamp(alt_err * 0.5, -maxVert, maxVert) or 0.0

    return {
        arm = true,
        flightActive = true,
        constraintProfile = (goal and goal.constraintProfile) or "STANDARD",
        targetPos = { x = center.x + ux * R, y = targetAlt, z = center.z + uz * R },
        targetVel = { vx = v_tan_x + v_rad_x, vy = vy, vz = v_tan_z + v_rad_z },
        feedforwardAccel = { ax = ax_in, ay = 0.0, az = az_in },
        targetHeading = heading,
        headingMode = (goal and goal.headingMode) or "AUTO",
        distanceToWp = math.abs(r - R),
    }
end

local function generate_poi_hold(state, nav, fac, goal, dt, now_ms)
    local cfgTraj = (state.config and state.config.trajectory) or {}
    local maxRate = cfgTraj.maxYawRateDegPerSec or 30.0
    local targetPos = (goal and goal.targetPos) or nav.pos
    local poi = (goal and (goal.poiPos or goal.poiTarget)) or targetPos

    local dx = poi.x - nav.pos.x
    local dz = poi.z - nav.pos.z
    local distPoi = math.sqrt(dx * dx + dz * dz)

    local targetH = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0
    if distPoi >= 0.5 then
        local desiredH = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
        targetH = apply_yaw_rate_limit(targetH, desiredH, maxRate, dt)
    end

    local distWp = calc_distance_3d(nav.pos, targetPos)
    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
        targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = targetH,
        headingMode = "POI",
        flapHint = 0.0,
        distanceToWp = distWp,
    }
end

local function compute_virtual_ils(state, nav, goal)
    local rwy = (goal and goal.runwayThreshold) or (goal and goal.targetPos) or nav.pos
    local bearing = (goal and (goal.approachBearingDeg or goal.fixedHeadingDeg or goal.targetHeading)) or 0.0
    local gammaDeg = (goal and goal.glideslopeDeg) or 3.0
    local gammaRad = math.rad(gammaDeg)
    local v_app = (goal and goal.targetSpeed) or 15.0

    local rad_b = math.rad(bearing)
    local cos_g = math.cos(gammaRad)
    local vx = math.sin(rad_b) * v_app * cos_g
    local vz = -math.cos(rad_b) * v_app * cos_g
    local vy = -v_app * math.sin(gammaRad)

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "FIXED_WING_GLIDE",
        targetPos = { x = rwy.x, y = rwy.y, z = rwy.z },
        targetVel = { vx = vx, vy = vy, vz = vz },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = normalize_heading(bearing),
        headingMode = "FIXED",
        flapHint = 1.0,
        distanceToWp = calc_distance_3d(nav.pos, rwy),
    }
end

local function compute_dynamic_deck_approach(state, nav, fac, alignDist, appDescent, tdDescent, now_ms)
    local p_deck, v_deck = facility_client.extrapolate_dynamic_deck(fac, now_ms)
    local dx = p_deck.x - nav.pos.x
    local dz = p_deck.z - nav.pos.z
    local d_2d = math.sqrt(dx * dx + dz * dz)
    local vy = (d_2d > alignDist) and appDescent or tdDescent
    local gAcc = fac.dynamicGuide.accel or { ax = 0.0, ay = 0.0, az = 0.0 }
    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = p_deck.x, y = p_deck.y, z = p_deck.z },
        targetVel = { vx = v_deck.vx, vy = vy + v_deck.vy, vz = v_deck.vz },
        feedforwardAccel = { ax = gAcc.ax or 0.0, ay = gAcc.ay or 0.0, az = gAcc.az or 0.0 },
        targetHeading = p_deck.heading or fac.dynamicGuide.approachHeading or state.prevHeading or 0.0,
        headingMode = "FIXED",
        flapHint = 0.0,
        distanceToWp = d_2d,
    }
end

local function generate_approach_land(state, nav, fac, goal, dt, now_ms)
    local isFixedWing = (goal and goal.airframeType == "FIXED_WING") or (state.airframeType == "FIXED_WING")
    if isFixedWing and (goal and (goal.runwayThreshold or goal.glideslopeDeg)) then
        return compute_virtual_ils(state, nav, goal)
    end

    local cfgTraj = (state.config and state.config.trajectory) or {}
    local appDescent = cfgTraj.approachDescentRateMps or -1.5
    local tdDescent = cfgTraj.touchdownDescentRateMps or -0.5
    local alignDist = cfgTraj.landingAlignDistanceM or 0.5

    local isDyn = (goal and goal.padMobility == "DYNAMIC") or (fac and fac.padMobility == "DYNAMIC")
    if isDyn and fac and fac.dynamicGuide then
        return compute_dynamic_deck_approach(state, nav, fac, alignDist, appDescent, tdDescent, now_ms)
    end

    local targetPos = (goal and goal.targetPos) or (fac and fac.staticGuide and fac.staticGuide.touchdownPoint) or { x = nav.pos.x, y = 64.0, z = nav.pos.z }
    local dx = targetPos.x - nav.pos.x
    local dz = targetPos.z - nav.pos.z
    local d_2d = math.sqrt(dx * dx + dz * dz)
    local vy = (d_2d > alignDist) and appDescent or tdDescent
    local isAero = (state.airframeType == "FIXED_WING" or state.airframeType == "WINGED_VTOL")

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z },
        targetVel = { vx = clamp(dx * 0.5, -2.0, 2.0), vy = vy, vz = clamp(dz * 0.5, -2.0, 2.0) },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0,
        headingMode = "AUTO",
        flapHint = isAero and 1.0 or 0.0,
        distanceToWp = d_2d,
    }
end

local function generate_landing(state, nav, fac, goal, dt, now_ms)
    return generate_approach_land(state, nav, fac, goal, dt, now_ms)
end

local function check_docking_abort(state, nav, fac, targetPos, targetHeading, cfgDock, now_ms)
    local abortDist = cfgDock.abortThresholdM or 0.30
    local abortHead = cfgDock.abortHeadingThresholdDeg or 5.0
    local safetyDist = cfgDock.abortSafetyDistanceM or 15.0
    local abortHoldMs = cfgDock.abortTimeoutMs or 300

    local dx = targetPos.x - nav.pos.x
    local dy = targetPos.y - nav.pos.y
    local dz = targetPos.z - nav.pos.z
    local dist_3d = math.sqrt(dx * dx + dy * dy + dz * dz)

    local radH = math.rad(targetHeading)
    local crossTrackErr = math.abs((-dx) * math.cos(radH) + (-dz) * math.sin(radH))
    local vertErr = math.abs(dy)
    local craftHeading = (nav.attitude and nav.attitude.heading) or 0.0
    local headingErr = math.abs(wrap_deg180(craftHeading - targetHeading))

    if state.dockingAborted then
        local elapsed = (now_ms or 0) - (state.dockingAbortStartMs or now_ms or 0)
        if dist_3d >= safetyDist and elapsed >= abortHoldMs then
            state.dockingAborted = false
            state.dockingAbortStartMs = nil
        else
            return true, dist_3d
        end
    end

    local facAborted = (fac and fac.dockingAborted == true)
    if facAborted or crossTrackErr > abortDist or vertErr > abortDist or headingErr > abortHead then
        state.dockingAborted = true
        state.dockingAbortStartMs = now_ms or 0
        return true, dist_3d
    end
    return false, dist_3d
end

local function generate_docking(state, nav, fac, goal, dt, now_ms)
    if fac and (fac.isHardLocked == true or fac.dockingStage == "HARD_LOCKED") then
        return {
            arm = false,
            flightActive = false,
            constraintProfile = "STRICT_LEVEL",
            targetPos = (goal and goal.targetPos) or nav.pos,
            targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
            feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
            targetHeading = state.prevHeading or 0.0,
            headingMode = "FIXED",
            distanceToWp = 0.0,
        }
    end

    local cfgTraj = (state.config and state.config.trajectory) or {}
    local cfgDock = cfgTraj.docking or {}
    local creepSpeed = cfgDock.creepSpeedMps or 0.4
    local abortSurge = cfgDock.abortSurgeBias or -0.8
    local targetPos = (goal and goal.targetPos) or nav.pos
    local targetHeading = (goal and (goal.fixedHeadingDeg or goal.targetHeading)) or 0.0

    local isAborted, dist_3d = check_docking_abort(state, nav, fac, targetPos, targetHeading, cfgDock, now_ms)
    local surgeBias = isAborted and abortSurge or creepSpeed

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = targetPos,
        targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = targetHeading,
        headingMode = "FIXED",
        translationBiasHint = { surge = surgeBias, sway = 0.0 },
        distanceToWp = dist_3d,
    }
end

local function generate_failsafe_rth(state, nav, fac, goal, dt, now_ms)
    local home = (goal and (goal.homePos or goal.targetPos)) or { x = 0.0, y = 150.0, z = 0.0 }
    local targetAlt = (goal and goal.targetAlt) or home.y or 150.0
    local targetSpeed = (goal and goal.targetSpeed) or (state.config and state.config.defaultSpeed) or 18.0

    local dx = home.x - nav.pos.x
    local dy = targetAlt - nav.pos.y
    local dz = home.z - nav.pos.z
    local dist3D = math.sqrt(dx * dx + dy * dy + dz * dz)
    local dist2D = math.sqrt(dx * dx + dz * dz)

    local vx, vy, vz = 0.0, 0.0, 0.0
    if dist3D > 0.01 then
        vx = (dx / dist3D) * targetSpeed
        vy = (dy / dist3D) * targetSpeed
        vz = (dz / dist3D) * targetSpeed
    end

    local heading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0
    if dist2D >= 0.5 then
        heading = (math.deg(math.atan2(dx, -dz)) + 360.0) % 360.0
    end

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STANDARD",
        targetPos = { x = home.x, y = targetAlt, z = home.z },
        targetVel = { vx = vx, vy = vy, vz = vz },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = heading,
        headingMode = "AUTO",
        distanceToWp = dist3D,
    }
end

local function generate_hover_hold(state, nav, fac, goal, dt, now_ms)
    local tgt = (goal and goal.targetPos) or nav.pos
    local targetY = (goal and goal.targetAlt) or tgt.y or nav.pos.y
    local dist = calc_distance_3d(nav.pos, { x = tgt.x, y = targetY, z = tgt.z })
    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = tgt.x, y = targetY, z = tgt.z },
        targetVel = { vx = 0.0, vy = 0.0, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = (goal and goal.fixedHeadingDeg) or state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0,
        headingMode = (goal and goal.headingMode) or "AUTO",
        distanceToWp = dist,
    }
end

local function generate_emergency_land(state, nav, fac, goal, dt, now_ms)
    local cfgTraj = (state.config and state.config.trajectory) or {}
    local descentRate = cfgTraj.emergencyDescentRateMps or -2.0
    local isAero = (goal and (goal.airframeType == "FIXED_WING" or goal.airframeType == "WINGED_VTOL"))
        or (state.airframeType == "FIXED_WING" or state.airframeType == "WINGED_VTOL")

    return {
        arm = true,
        flightActive = true,
        constraintProfile = "STRICT_LEVEL",
        targetPos = { x = nav.pos.x, y = math.max(0.0, nav.pos.y - 100.0), z = nav.pos.z },
        targetVel = { vx = 0.0, vy = descentRate, vz = 0.0 },
        feedforwardAccel = { ax = 0.0, ay = 0.0, az = 0.0 },
        targetHeading = state.prevHeading or (nav.attitude and nav.attitude.heading) or 0.0,
        headingMode = "AUTO",
        flapHint = isAero and 1.0 or 0.0,
        distanceToWp = nav.pos.y,
    }
end

local MODE_GENERATORS = {
    IDLE_ARMED = generate_idle,
    TAKEOFF = generate_takeoff,
    CRUISE = generate_cruise,
    LOITER = generate_loiter,
    POI_HOLD = generate_poi_hold,
    APPROACH_LAND = generate_approach_land,
    LANDING = generate_landing,
    DOCKING = generate_docking,
    FAILSAFE_RTH = generate_failsafe_rth,
    HOVER_HOLD = generate_hover_hold,
    EMERGENCY_LAND = generate_emergency_land,
}

local function assemble_setpoint(st, safeNav, rawNav, res, mode, goal, targetH)
    local tpos = res.targetPos or safeNav.pos
    local tvel = res.targetVel or { vx = 0.0, vy = 0.0, vz = 0.0 }
    local a_ff = res.feedforwardAccel or { ax = 0.0, ay = 0.0, az = 0.0 }
    local cfgDefSpeed = (st.config and st.config.defaultSpeed) or 18.0

    local setpoint = {
        arm = (res.arm ~= false),
        flightActive = (res.flightActive == true),
        flightMode = mode,
        constraintProfile = res.constraintProfile or "STANDARD",
        targetPos = { x = sanitize_num(tpos.x, safeNav.pos.x), y = sanitize_num(tpos.y, safeNav.pos.y), z = sanitize_num(tpos.z, safeNav.pos.z) },
        targetVel = { vx = sanitize_num(tvel.vx, 0.0), vy = sanitize_num(tvel.vy, 0.0), vz = sanitize_num(tvel.vz, 0.0) },
        feedforwardAccel = { ax = sanitize_num(a_ff.ax, 0.0), ay = sanitize_num(a_ff.ay, 0.0), az = sanitize_num(a_ff.az, 0.0) },
        targetHeading = targetH,
        headingMode = res.headingMode or (goal and goal.headingMode) or "AUTO",
        maxHorizSpeedMps = sanitize_num(goal and goal.maxHorizSpeedMps, cfgDefSpeed),
        maxVertSpeedMps = sanitize_num(goal and goal.maxVertSpeedMps, 5.0),
        maxTiltDeg = sanitize_num(goal and goal.maxTiltDeg, 35.0),
        currentPos = { x = safeNav.pos.x, y = safeNav.pos.y, z = safeNav.pos.z },
        navValid = (rawNav.navValid == true),
        gpsTimedOut = (rawNav.gpsStale == true),
        hdop = sanitize_num(rawNav.hdop, 1.0),
        posEpoch = math.floor(sanitize_num(rawNav.posEpoch, 0)),
        activeWpIndex = res.activeWpIndex or (goal and goal.activeWpIndex),
        distanceToWp = res.distanceToWp,
    }
    if res.flapHint ~= nil then
        setpoint.flapHint = sanitize_num(res.flapHint, 0.0)
    end
    if res.translationBiasHint ~= nil then
        setpoint.translationBiasHint = {
            surge = sanitize_num(res.translationBiasHint.surge, 0.0),
            sway = sanitize_num(res.translationBiasHint.sway, 0.0),
        }
    end
    return setpoint
end

function trajectory_generator.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    return {
        config = cfg,
        airframeType = sys.airframeType or "VECTORED_VTOL",
        prevHeading = 0.0,
        takeoffOriginY = nil,
        takeoffAnchorPos = nil,
        dockingAborted = false,
        dockingAbortStartMs = nil,
    }
end

function trajectory_generator.compute(state, navState, facilityState, goal, dt, now_ms)
    local st = state or {}
    local nav = navState or {}
    local npos = nav.pos or { x = 0.0, y = 64.0, z = 0.0 }
    local safeNav = {
        pos = { x = sanitize_num(npos.x, 0.0), y = sanitize_num(npos.y, 64.0), z = sanitize_num(npos.z, 0.0) },
        vel = nav.vel or { x = 0.0, y = 0.0, z = 0.0 },
        attitude = nav.attitude or { pitch = 0.0, roll = 0.0, heading = st.prevHeading or 0.0 },
    }

    local mode = (goal and goal.flightMode) or "IDLE_ARMED"
    if mode ~= "TAKEOFF" then
        st.takeoffOriginY = nil
        st.takeoffAnchorPos = nil
    end

    local gen = MODE_GENERATORS[mode] or generate_idle
    local res = gen(st, safeNav, facilityState, goal, dt or 0.05, now_ms or 0)

    local targetH = normalize_heading(sanitize_num(res.targetHeading, st.prevHeading or 0.0))
    st.prevHeading = targetH

    return assemble_setpoint(st, safeNav, nav, res, mode, goal, targetH)
end

return trajectory_generator
