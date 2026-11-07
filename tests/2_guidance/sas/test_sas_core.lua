-- Unit test suite for 2_guidance/sas
local flight_fsm = require("flight_fsm")

describe("sas config file staging and access", function()
    it("reads configuration from staged config/sas_config.json", function()
        assert_true(fs.exists("config/sas_config.json"), "config/sas_config.json must exist in staged root")
        local f = fs.open("config/sas_config.json", "r")
        assert_not_nil(f)
        local raw = f.readAll()
        f.close()
        local data = textutils.unserializeJSON(raw)
        assert_not_nil(data)
        assert_not_nil(data.system)
        assert_not_nil(data.channels)
        assert_not_nil(data.safety)
    end)
end)

describe("sas flight FSM state transitions and failsafes", function()
    it("transitions through ground sequence BOOT_INIT -> TAKEOFF", function()
        local fsm = flight_fsm.init({
            system = { airframeType = "VECTORED_VTOL" },
            safety = { emergencyLandFuelThreshold = 0.10, lowFuelRthThreshold = 0.20 }
        })
        assert_eq(fsm.current_state, "BOOT_INIT")
        assert_false(fsm.inFlight)

        flight_fsm.evaluate(fsm, { channelAcquired = true })
        assert_eq(fsm.current_state, "DISARMED")

        flight_fsm.evaluate(fsm, { cmd = "ARM" })
        assert_eq(fsm.current_state, "ARMING")

        flight_fsm.evaluate(fsm, { coreArmed = true })
        assert_eq(fsm.current_state, "IDLE_ARMED")

        flight_fsm.evaluate(fsm, { cmd = "TAKEOFF", takeoffGate = { allowed = true } })
        assert_eq(fsm.current_state, "TAKEOFF")
        assert_true(fsm.inFlight)
    end)

    it("triggers EMERGENCY_LAND on critical fuel drop during flight", function()
        local fsm = flight_fsm.init({
            safety = { emergencyLandFuelThreshold = 0.10, lowFuelRthThreshold = 0.20 }
        })
        flight_fsm.transition_to(fsm, "CRUISE")
        assert_true(fsm.inFlight)

        local action = flight_fsm.check_failsafes(fsm, { fuel = 0.05 })
        assert_eq(action, "EMERGENCY_LAND")
        assert_eq(fsm.current_state, "EMERGENCY_LAND")
        assert_eq(fsm.lockReason, "CRITICAL_LOW_FUEL")
    end)
end)
