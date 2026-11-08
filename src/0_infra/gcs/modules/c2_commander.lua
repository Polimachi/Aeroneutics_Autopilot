-- src/0_infra/gcs/modules/c2_commander.lua
-- C2 command generator and emergency cutoff packet synthesizer
-- UAFS Ecosystem GCS v1.0.0

local c2_commander = {}

local VALID_COMMANDS = {
    ARM = true,
    DISARM = true,
    TAKEOFF = true,
    CRUISE = true,
    HOLD = true,
    RTH = true,
    LAND = true,
    WAYPOINT = true
}

function c2_commander.is_valid_command(cmd)
    if type(cmd) ~= "string" then return false end
    return VALID_COMMANDS[cmd] == true
end

function c2_commander.create_operator_cmd(cmd_type, target_craft, params)
    if not c2_commander.is_valid_command(cmd_type) then
        return nil, "invalid command type: " .. tostring(cmd_type)
    end
    if type(target_craft) ~= "string" or target_craft == "" then
        return nil, "target_craft must be a non-empty string"
    end

    local payload = {
        targetCraft = target_craft,
        authority = "GCS_OVERRIDE",
        command = cmd_type,
        params = params or {}
    }
    return payload, nil
end

function c2_commander.create_emergency_estop(target_craft, reason)
    return {
        source = "GCS",
        action = "E_STOP",
        targetCraft = target_craft,
        reason = reason or "OPERATOR_HARD_STOP"
    }
end

return c2_commander
