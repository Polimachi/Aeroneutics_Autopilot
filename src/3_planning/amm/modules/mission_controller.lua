-- src/3_planning/amm/modules/mission_controller.lua
-- Mission controller & airframe profile evaluator for AMM

local mission_controller = {}

local SUPPORTED_AIRFRAMES = {
    ADVANCED_VTOL = true,
    VECTORED_VTOL = true,
    WINGED_VTOL   = true,
    FIXED_WING    = true,
    QUADROTOR     = true,
    HEXAROTOR     = true,
}

function mission_controller.is_airframe_supported(airframeType)
    if not airframeType then return false end
    return SUPPORTED_AIRFRAMES[airframeType] == true
end

function mission_controller.get_supported_airframes()
    local list = {}
    for af, _ in pairs(SUPPORTED_AIRFRAMES) do
        table.insert(list, af)
    end
    table.sort(list)
    return list
end

return mission_controller
