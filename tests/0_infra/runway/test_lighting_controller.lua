-- tests/0_infra/runway/test_lighting_controller.lua
local lighting_controller = require("modules.lighting_controller")

describe("Runway Wired Lighting, Arresting Clutch, and Graceful Degradation", function()
    local function make_integrator()
        local out = {}
        return {
            outputs = out,
            setOutput = function(side, val) out[side] = val end,
            getOutput = function(side) return out[side] == true end,
        }
    end

    it("degrades gracefully without error when all wired peripherals are missing", function()
        local lc = lighting_controller.create({})
        local status = lc:apply_state("IDLE", { speed = 2.0, direction = 90.0 }, 0)
        assert_false(status.hasIntegrator)
        assert_false(status.hasClutch)
        assert_false(status.hasWindDisplay)
        assert_eq(status.warning, "redstone_integrator_0 missing")
    end)

    it("drives 6-side truth table, wave-off blink phase, and arresting clutch across FSM states", function()
        local ri = make_integrator()
        local clutchLevel = nil
        local windLines = {}
        local clutch = { setAnalogOutput = function(v) clutchLevel = v end, setOutput = function(_, v) clutchLevel = v end }
        local disp = {
            clear = function() windLines = {} end,
            setCursorPos = function() end,
            write = function(s) table.insert(windLines, s) end,
        }

        local lc = lighting_controller.create({ integrator = ri, clutch = clutch, windDisplay = disp })

        -- IDLE (FREE): north CLEAR=true, south HOT=false, top PAPI=false, east HOLD=false, clutch=0
        lc:apply_state("IDLE", { speed = 3.0, direction = 90.0 }, 0)
        assert_true(ri.outputs.north)
        assert_false(ri.outputs.south)
        assert_false(ri.outputs.top)
        assert_false(ri.outputs.east)
        assert_eq(clutchLevel, 0)
        assert_true(#windLines >= 1)

        -- APPROACH_DYNAMIC: top PAPI=true, south HOT=false, north CLEAR=true, east HOLD=true
        lc:apply_state("APPROACH_DYNAMIC", { speed = 3.0, direction = 90.0 }, 0)
        assert_true(ri.outputs.top)
        assert_true(ri.outputs.east)
        assert_true(ri.outputs.north)
        assert_false(ri.outputs.south)

        -- ROLLOUT (OCCUPIED): south HOT=true, north CLEAR=false, clutch=15
        lc:apply_state("ROLLOUT", { speed = 3.0, direction = 90.0 }, 0)
        assert_true(ri.outputs.south)
        assert_false(ri.outputs.north)
        assert_eq(clutchLevel, 15)

        -- WAVE_OFF blinks top and south across phase toggle
        lc:apply_state("WAVE_OFF", { speed = 3.0, direction = 90.0 }, 0)
        assert_true(ri.outputs.top)
        assert_true(ri.outputs.south)
        lc:apply_state("WAVE_OFF", { speed = 3.0, direction = 90.0 }, 5)
        assert_false(ri.outputs.top)
        assert_false(ri.outputs.south)
    end)
end)
