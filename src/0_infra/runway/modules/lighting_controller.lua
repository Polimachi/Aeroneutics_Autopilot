-- src/0_infra/runway/modules/lighting_controller.lua
-- Wired peripheral controller for Runway PAPI/ALS lights, clutch & wind display
-- Degrades gracefully when optional wired hardware is not attached.

local lighting_controller = {}

local STATE_LIGHTS = {
    IDLE = { top = false, bottom = false, north = true, south = false, east = false, west = false },
    FREE = { top = false, bottom = false, north = true, south = false, east = false, west = false },
    RESERVED = { top = true, bottom = true, north = true, south = false, east = true, west = false },
    APPROACH_STATIC = { top = true, bottom = true, north = true, south = false, east = true, west = false },
    APPROACH_DYNAMIC = { top = true, bottom = true, north = true, south = false, east = true, west = false },
    ROLLOUT = { top = true, bottom = true, north = false, south = true, east = true, west = false },
    OCCUPIED = { top = true, bottom = true, north = false, south = true, east = true, west = false },
    VACATING = { top = false, bottom = true, north = false, south = true, east = true, west = false },
    LINE_UP_WAIT = { top = false, bottom = true, north = false, south = true, east = false, west = false },
    TAKEOFF_ROLL = { top = true, bottom = true, north = false, south = true, east = false, west = false },
}

local function resolve_outputs(stateName, tickCount)
    if stateName == "WAVE_OFF" or stateName == "MAINTENANCE" then
        local blink = (math.floor((tickCount or 0) / 5) % 2) == 0
        return { top = blink, bottom = true, north = false, south = blink, east = true, west = false }
    end
    return STATE_LIGHTS[stateName] or STATE_LIGHTS.IDLE
end

local function update_clutch(clutch, stateName)
    if not clutch then return end
    local lvl = (stateName == "ROLLOUT" or stateName == "OCCUPIED") and 15 or 0
    if type(clutch.setAnalogOutput) == "function" then
        pcall(clutch.setAnalogOutput, lvl)
    elseif type(clutch.setOutput) == "function" then
        pcall(clutch.setOutput, "top", lvl)
    end
end

local function update_wind_display(disp, stateName, surfaceWind)
    if not disp or type(disp.write) ~= "function" then return end
    local wind = surfaceWind or {}
    local line1 = string.format("RWY: %-12s", tostring(stateName or "IDLE"))
    local line2 = string.format("WND:%03d/%02dm/s", math.floor(wind.direction or 0), math.floor(wind.speed or 0))
    if type(disp.clear) == "function" then pcall(disp.clear) end
    if type(disp.setCursorPos) == "function" then pcall(disp.setCursorPos, 1, 1) end
    pcall(disp.write, line1)
    if type(disp.setCursorPos) == "function" then pcall(disp.setCursorPos, 1, 2) end
    pcall(disp.write, line2)
end

function lighting_controller.create(devices)
    local devs = devices or {}
    local controller = {}

    function controller:set_devices(nextDevices)
        devs = nextDevices or {}
    end

    function controller:apply_state(stateName, surfaceWind, tickCount)
        local ri = devs.integrator
        local hasRi = (ri ~= nil and type(ri.setOutput) == "function")
        if hasRi then
            local outputs = resolve_outputs(stateName, tickCount)
            for side, val in pairs(outputs) do
                pcall(ri.setOutput, side, val)
            end
        end
        local hasClutch = (devs.clutch ~= nil)
        if hasClutch then update_clutch(devs.clutch, stateName) end
        local hasWind = (devs.windDisplay ~= nil)
        if hasWind then update_wind_display(devs.windDisplay, stateName, surfaceWind) end

        return {
            hasIntegrator = hasRi,
            hasClutch = hasClutch,
            hasWindDisplay = hasWind,
            warning = (not hasRi) and "redstone_integrator_0 missing" or nil,
        }
    end

    return controller
end

return lighting_controller
