-- Group Output Allocation & Thrust Loss Proportional Compensation (v1.4.0)
local group_allocator = {}

--- Clamp signal to integer range [0, 15]
function group_allocator.clamp_signal(signal)
    local num = tonumber(signal) or 0
    local rounded = math.floor(num + 0.5)
    if rounded < 0 then return 0
    elseif rounded > 15 then return 15 end
    return rounded
end

--- Apply deadband threshold to signal (signals <= deadband become 0)
function group_allocator.apply_deadband(signal, deadband)
    local s = group_allocator.clamp_signal(signal)
    local db = tonumber(deadband) or 0
    if s <= db then return 0 end
    return s
end

--- Extract group output signal safely from outputs table
function group_allocator.extract_group_output(outputs, groupId, deadband)
    if type(outputs) ~= "table" or not groupId then return 0 end
    local raw = outputs[groupId]
    local clamped = group_allocator.clamp_signal(raw)
    if deadband then return group_allocator.apply_deadband(clamped, deadband) end
    return clamped
end

--- Process redstone direct signal with optional deadband
function group_allocator.process_redstone_signal(reqSignal, deadband)
    return group_allocator.apply_deadband(reqSignal, deadband)
end

--- Calculate boosted signal and proportional ratio for API mode
function group_allocator.calculate_api_boosted_signal(reqSignal, activeCount, totalCount)
    local act = tonumber(activeCount) or 0
    local tot = tonumber(totalCount) or act
    local req = group_allocator.clamp_signal(reqSignal)

    if act <= 0 then return 0, 0.0, false end
    if act >= tot then return req, 1.0, false end

    local ratio = tot / act
    local rawBoosted = req * ratio
    local isSaturated = rawBoosted > 15
    local boostedSignal = group_allocator.clamp_signal(rawBoosted)
    return boostedSignal, ratio, isSaturated
end

--- Backward-compatible alias for calculate_api_boosted_signal
function group_allocator.calculate_boosted_signal(reqSignal, activeCount, totalCount)
    return group_allocator.calculate_api_boosted_signal(reqSignal, activeCount, totalCount)
end

--- Check if requested signal saturates the actuator
function group_allocator.is_saturated(reqSignal, mode, activeCount, totalCount)
    local req = tonumber(reqSignal) or 0
    if req <= 0 then return false end
    if mode == "REDSTONE" then return req > 15 end
    local act = tonumber(activeCount) or 0
    local tot = tonumber(totalCount) or act
    if act <= 0 then return false end
    return (req * (tot / act)) > 15
end

return group_allocator
