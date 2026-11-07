-- src/modules/thruster_profile.lua
local thruster_profile = {}

local function try_load_file(path)
    if not fs or not fs.exists or not fs.exists(path) then
        return nil
    end
    local h = fs.open(path, "r")
    if not h then return nil end
    local content = h.readAll()
    h.close()
    if textutils and textutils.unserializeJSON then
        return textutils.unserializeJSON(content)
    end
    return nil
end

function thruster_profile.init(config)
    local cfg = config or {}
    local g = cfg.guidance or {}
    local vv = g.vectored_vtol or {}
    local pv = vv.profileValidation or {}
    local path = pv.profilePath or "config/thruster_profile.json"
    local initial_profile = try_load_file(path)
    return {
        profilePath = path,
        minSwayAccelMps2 = pv.minSwayAccelMps2 or 2.0,
        allowUncalibratedWithWarning = pv.allowUncalibratedWithWarning ~= false,
        swayLossAction = pv.swayLossAction or "EMERGENCY_LAND",
        profile = initial_profile,
        swayTotalLoss = false,
    }
end

function thruster_profile.on_profile_sync(state, payload, persist)
    if not state then return end
    state.profile = payload or {}
    if persist ~= false and fs and textutils and textutils.serializeJSON then
        pcall(function()
            local dir = string.match(state.profilePath, "(.+)/[^/]+$")
            if dir and not fs.exists(dir) then fs.makeDir(dir) end
            local h = fs.open(state.profilePath, "w")
            if h then
                h.write(textutils.serializeJSON(state.profile))
                h.close()
            end
        end)
    end
end

function thruster_profile.evaluate_takeoff_gate(state)
    if not state or not state.profile then
        if state and state.allowUncalibratedWithWarning then
            return { allowed = true, warn_code = "UNCALIB_PROFILE_MISSING_WARN" }
        end
        return { allowed = false, block_reason = "PROFILE_MISSING" }
    end
    local prof = state.profile
    if prof.controllabilityStatus ~= "FULL_6DOF_PASS" then
        return { allowed = false, block_reason = "PROFILE_STATUS_DEFICIT" }
    end
    local sway = prof.swayMaxAccel or prof.swayAccelMps2 or 0.0
    if sway < state.minSwayAccelMps2 then
        return { allowed = false, block_reason = "PROFILE_6DOF_SWAY_DEFICIT" }
    end
    return { allowed = true }
end

function thruster_profile.on_actuator_status(state, payload)
    if not state or not payload then return end
    if payload.healthStatus == "TOTAL_LOSS" or payload.swayAuthorityLost == true then
        state.swayTotalLoss = true
    end
end

function thruster_profile.has_sway_loss(state)
    return state ~= nil and state.swayTotalLoss == true
end

return thruster_profile
