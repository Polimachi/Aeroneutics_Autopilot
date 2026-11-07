-- Dual-Mode Thruster Interaction Actuator Adapter for TCA (v1.4.0)
local group_allocator = require("group_allocator")

local actuator_adapter = {
    ALL_SIDES = {"top", "bottom", "left", "right", "front", "back"},
    DEFAULT_REDSTONE_SIDE = "bottom",
    DEFAULT_API_SIDES = {"left", "right", "front", "back"},
    SUPPORTED_METHODS = {"setPower", "setThrust", "setAnalogOutput", "setOutput", "setSpeed", "setTargetSpeed"},
    IGNORED_TYPES = { modem = true, monitor = true, computer = true, drive = true, speaker = true, printer = true }
}

function actuator_adapter.save_interaction_mode(path, mode)
    if type(path) ~= "string" or not mode or not fs or not fs.open then return false end
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(mode)
    f.close()
    return true
end

function actuator_adapter.load_interaction_mode(path)
    if type(path) ~= "string" or not fs or not fs.exists or not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local content = f.readAll()
    f.close()
    return (content == "API" or content == "REDSTONE") and content or nil
end

local function is_side_allowed(name, modemSide, whitelist)
    if name == modemSide then return false end
    if whitelist and type(whitelist) == "table" then
        for _, w in ipairs(whitelist) do if w == name then return true end end
        return false
    end
    return true
end

function actuator_adapter.scan_api_peripherals(state)
    local results, ports = {}, state and state.ports
    local modemSide = (ports and ports.modemSide) or "top"
    local whitelist = (ports and ports.apiSides) or actuator_adapter.DEFAULT_API_SIDES
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            local pType = peripheral.isPresent(name) and peripheral.getType(name)
            if pType and not actuator_adapter.IGNORED_TYPES[pType] and is_side_allowed(name, modemSide, whitelist) then
                local wrapped = peripheral.wrap(name)
                if type(wrapped) == "table" then
                    for _, m in ipairs(actuator_adapter.SUPPORTED_METHODS) do
                        if type(wrapped[m]) == "function" then
                            table.insert(results, { name = name, wrapped = wrapped, method = m })
                            break
                        end
                    end
                end
            end
        end
    end
    if state then state.peripherals = results end
    return results
end

function actuator_adapter.detect_api_peripherals(state)
    return (state and state.peripherals) or actuator_adapter.scan_api_peripherals(state)
end

function actuator_adapter.init(defaultInteractionMode, configPath, ports)
    local tableMode = (type(configPath) == "table" and configPath.interactionMode) or nil
    local tablePorts = (type(configPath) == "table" and configPath.ports) or ports
    local loaded = (type(configPath) == "string") and actuator_adapter.load_interaction_mode(configPath) or tableMode
    local chosen = loaded or (type(defaultInteractionMode) == "string" and defaultInteractionMode) or "REDSTONE"
    local state = {
        interactionMode = chosen, configPath = (type(configPath) == "string") and configPath or nil,
        ports = tablePorts, lastSignal = 0, lastRatio = 0.0, peripherals = {}, dispatchedCount = 0
    }
    actuator_adapter.scan_api_peripherals(state)
    return state
end

function actuator_adapter.set_interaction_mode(state, mode)
    if not state or (mode ~= "REDSTONE" and mode ~= "API") then return false end
    actuator_adapter.cut_thrust(state)
    state.interactionMode = mode
    if state.configPath then actuator_adapter.save_interaction_mode(state.configPath, mode) end
    return true
end

function actuator_adapter.toggle_interaction_mode(state)
    if not state then return "REDSTONE" end
    local newMode = (state.interactionMode == "REDSTONE") and "API" or "REDSTONE"
    actuator_adapter.set_interaction_mode(state, newMode)
    return state.interactionMode
end

function actuator_adapter.toggle_mode(state)
    return actuator_adapter.toggle_interaction_mode(state)
end

local function dispatch_val(item, ratio)
    if not item or not item.wrapped or type(item.wrapped[item.method]) ~= "function" then return false end
    local m = item.method
    if m == "setSpeed" or m == "setTargetSpeed" then
        return pcall(item.wrapped[m], ratio * 256)
    elseif m == "setAnalogOutput" then
        return pcall(item.wrapped[m], math.floor(ratio * 15 + 0.5))
    end
    return pcall(item.wrapped[m], ratio)
end

function actuator_adapter.apply_redstone_thrust(state, rawSignal)
    local directSignal = math.max(0, math.min(15, math.floor((tonumber(rawSignal) or 0) + 0.5)))
    state.lastSignal, state.lastRatio, state.dispatchedCount = directSignal, 0.0, 1
    local outSide = (state.ports and state.ports.redstoneSide) or actuator_adapter.DEFAULT_REDSTONE_SIDE
    if rs and rs.setAnalogOutput then
        rs.setAnalogOutput(outSide, directSignal)
        for _, s in ipairs(actuator_adapter.ALL_SIDES) do
            if s ~= outSide then rs.setAnalogOutput(s, 0) end
        end
    end
    return "REDSTONE_APPLIED", directSignal
end

function actuator_adapter.apply_api_thrust(state, rawSignal, activeCount, totalCount)
    local devs = state.peripherals or {}
    if #devs == 0 then
        actuator_adapter.cut_thrust(state)
        return "API_NO_DEVICES", 0.0, 0, false
    end
    local boosted, _, isSaturated = group_allocator.calculate_api_boosted_signal(rawSignal, activeCount, totalCount)
    state.lastSignal = boosted
    state.lastRatio = math.max(0.0, math.min(1.0, boosted / 15.0))
    if rs and rs.setAnalogOutput then
        for _, s in ipairs(actuator_adapter.ALL_SIDES) do rs.setAnalogOutput(s, 0) end
    end
    local count = 0
    for _, item in ipairs(devs) do
        if dispatch_val(item, state.lastRatio) then count = count + 1 end
    end
    state.dispatchedCount = count
    return "API_APPLIED", state.lastRatio, count, isSaturated
end

function actuator_adapter.apply_thrust(state, rawSignal, activeCount, totalCount)
    if not state then return "INVALID_STATE", 0, 0 end
    if state.interactionMode == "REDSTONE" then
        return actuator_adapter.apply_redstone_thrust(state, rawSignal)
    end
    return actuator_adapter.apply_api_thrust(state, rawSignal, activeCount, totalCount)
end

function actuator_adapter.cut_thrust(state)
    if not state then return false end
    state.lastSignal, state.lastRatio, state.dispatchedCount = 0, 0.0, 0
    if rs and rs.setAnalogOutput then
        for _, s in ipairs(actuator_adapter.ALL_SIDES) do rs.setAnalogOutput(s, 0) end
    end
    for _, item in ipairs(state.peripherals or {}) do dispatch_val(item, 0.0) end
    return true
end

return actuator_adapter
