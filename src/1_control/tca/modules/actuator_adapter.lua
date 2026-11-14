-- Dual-Mode Thruster Interaction Actuator Adapter for TCA (v1.11.0)
local group_allocator = require("group_allocator")

local actuator_adapter = {
    ALL_SIDES = {"top", "bottom", "left", "right", "front", "back"},
    DEFAULT_REDSTONE_SIDE = "bottom",
    DEFAULT_API_SIDES = {"left", "right", "front", "back"},
    SUPPORTED_METHODS = {"setPower", "setThrust", "setAnalogOutput", "setOutput", "setSpeed", "setTargetSpeed"},
    VECTOR_THRUSTER_TYPES = {"vector_thruster", "liquid_vector_thruster", "creative_vector_thruster"},
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

local function is_vector_type(pType)
    if not pType then return false end
    for _, vt in ipairs(actuator_adapter.VECTOR_THRUSTER_TYPES) do
        if pType == vt then return true end
    end
    return false
end

local function ensure_vector_methods(wrapped)
    if not wrapped.setVector and type(wrapped.setVectorX) == "function" and type(wrapped.setVectorY) == "function" then
        wrapped.setVector = function(x, y)
            wrapped.setVectorX(x)
            wrapped.setVectorY(y)
        end
    end
    if wrapped.setVector and not wrapped.setVectorX then
        wrapped.setVectorX = function(x)
            local curY = (wrapped.getVectorY and wrapped.getVectorY()) or 0.0
            return wrapped.setVector(x, curY)
        end
    end
    if wrapped.setVector and not wrapped.setVectorY then
        wrapped.setVectorY = function(y)
            local curX = (wrapped.getVectorX and wrapped.getVectorX()) or 0.0
            return wrapped.setVector(curX, y)
        end
    end
end

function actuator_adapter.scan_api_peripherals(state)
    local results, ports = {}, state and state.ports
    local modemSide = (ports and ports.modemSide) or "top"
    local whitelist = (ports and ports.apiSides) or actuator_adapter.DEFAULT_API_SIDES
    local hasVector = false
    if peripheral and peripheral.getNames then
        for _, name in ipairs(peripheral.getNames()) do
            local pType = peripheral.isPresent(name) and peripheral.getType(name)
            if pType and not actuator_adapter.IGNORED_TYPES[pType] and is_side_allowed(name, modemSide, whitelist) then
                local wrapped = peripheral.wrap(name)
                if type(wrapped) == "table" then
                    local isVec = is_vector_type(pType) or (type(wrapped.setVector) == "function")
                    if isVec then
                        hasVector = true
                        ensure_vector_methods(wrapped)
                        -- Cold Boot Neutral Centering: initialize nozzle to (0, 0)
                        pcall(wrapped.setVector, 0.0, 0.0)
                    end
                    for _, m in ipairs(actuator_adapter.SUPPORTED_METHODS) do
                        if type(wrapped[m]) == "function" then
                            table.insert(results, {
                                name = name,
                                wrapped = wrapped,
                                method = m,
                                isVectorCapable = isVec,
                                type = pType
                            })
                            break
                        end
                    end
                end
            end
        end
    end
    if state then
        state.peripherals = results
        state.isVectorCapable = hasVector
        if state.lastGimbal == nil then state.lastGimbal = { x = 0.0, y = 0.0 } end
        if state.isGimbalSaturated == nil then state.isGimbalSaturated = false end
    end
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
        ports = tablePorts, lastSignal = 0, lastRatio = 0.0, peripherals = {}, dispatchedCount = 0,
        isVectorCapable = false, lastGimbal = { x = 0.0, y = 0.0 }, isGimbalSaturated = false
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

local function dispatch_val(item, val)
    if not item or not item.wrapped or type(item.wrapped[item.method]) ~= "function" then return false end
    local m = item.method
    if m == "setSpeed" or m == "setTargetSpeed" then
        return pcall(item.wrapped[m], val * 256)
    elseif m == "setAnalogOutput" then
        return pcall(item.wrapped[m], math.floor(val * 15 + 0.5))
    end
    return pcall(item.wrapped[m], val)
end

function actuator_adapter.apply_redstone_thrust(state, rawSignal)
    local raw = (type(rawSignal) == "table" and rawSignal.thrust) or rawSignal
    local directSignal = math.max(0, math.min(15, math.floor((tonumber(raw) or 0) + 0.5)))
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
    local raw = (type(rawSignal) == "table" and rawSignal.thrust) or rawSignal
    local boosted, _, isSaturated = group_allocator.calculate_api_boosted_signal(raw, activeCount, totalCount)
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

function actuator_adapter.apply_vector_thrust(state, rawSignal, activeCount, totalCount)
    local devs = state.peripherals or {}
    if #devs == 0 then
        actuator_adapter.cut_thrust(state)
        return "API_NO_DEVICES", 0.0, 0, false, { x = 0.0, y = 0.0 }, false
    end

    local rawThrust = (type(rawSignal) == "table" and rawSignal.thrust) or rawSignal or 0
    local rawGx = (type(rawSignal) == "table" and tonumber(rawSignal.gimbalX)) or 0.0
    local rawGy = (type(rawSignal) == "table" and tonumber(rawSignal.gimbalY)) or 0.0

    local clampedGx = math.max(-1.0, math.min(1.0, rawGx))
    local clampedGy = math.max(-1.0, math.min(1.0, rawGy))
    local isGimbalSat = (rawGx > 1.0 or rawGx < -1.0 or rawGy > 1.0 or rawGy < -1.0)

    state.lastGimbal = { x = clampedGx, y = clampedGy }
    state.isGimbalSaturated = isGimbalSat

    local boosted, _, isThrustSat = group_allocator.calculate_api_boosted_signal(rawThrust, activeCount, totalCount)
    state.lastSignal = boosted
    state.lastRatio = math.max(0.0, math.min(1.0, boosted / 15.0))

    if rs and rs.setAnalogOutput then
        for _, s in ipairs(actuator_adapter.ALL_SIDES) do rs.setAnalogOutput(s, 0) end
    end

    local count = 0
    for _, item in ipairs(devs) do
        local okThrust = false
        if item.isVectorCapable or (item.wrapped and type(item.wrapped.setVector) == "function") then
            if item.wrapped and type(item.wrapped.setPower) == "function" then
                okThrust = pcall(item.wrapped.setPower, boosted)
            else
                okThrust = dispatch_val(item, state.lastRatio)
            end
            pcall(item.wrapped.setVector, clampedGx, clampedGy)
        else
            okThrust = dispatch_val(item, state.lastRatio)
        end
        if okThrust then count = count + 1 end
    end
    state.dispatchedCount = count

    return "API_VECTOR_APPLIED", state.lastRatio, count, isThrustSat, state.lastGimbal, state.isGimbalSaturated
end

function actuator_adapter.apply_thrust(state, rawSignal, activeCount, totalCount)
    if not state then return "INVALID_STATE", 0, 0 end
    if state.interactionMode == "REDSTONE" then
        return actuator_adapter.apply_redstone_thrust(state, rawSignal)
    end
    if state.isVectorCapable or type(rawSignal) == "table" then
        return actuator_adapter.apply_vector_thrust(state, rawSignal, activeCount, totalCount)
    end
    return actuator_adapter.apply_api_thrust(state, rawSignal, activeCount, totalCount)
end

function actuator_adapter.cut_thrust(state)
    if not state then return false end
    state.lastSignal, state.lastRatio, state.dispatchedCount = 0, 0.0, 0
    state.lastGimbal = { x = 0.0, y = 0.0 }
    state.isGimbalSaturated = false
    if rs and rs.setAnalogOutput then
        for _, s in ipairs(actuator_adapter.ALL_SIDES) do rs.setAnalogOutput(s, 0) end
    end
    for _, item in ipairs(state.peripherals or {}) do
        if item.wrapped and type(item.wrapped.setPower) == "function" then
            pcall(item.wrapped.setPower, 0)
        else
            dispatch_val(item, 0.0)
        end
        if item.isVectorCapable or (item.wrapped and type(item.wrapped.setVector) == "function") then
            pcall(item.wrapped.setVector, 0.0, 0.0)
        end
    end
    return true
end

return actuator_adapter
