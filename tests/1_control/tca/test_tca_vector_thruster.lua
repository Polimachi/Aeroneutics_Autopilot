-- Unit test suite for TCA Vector Thruster Peripheral Adapter & Daemon (TASK-115)
local actuator_adapter = require("actuator_adapter")
local discovery_handler = require("discovery_handler")
local group_allocator = require("group_allocator")
local status_reporter = require("status_reporter")
local tca_daemon = require("tca_daemon")

local function create_mock_vector_thruster()
    local dev = {
        _power = 0,
        _vectorX = 0.0,
        _vectorY = 0.0,
        _powerCalls = {},
        _vectorCalls = {}
    }
    dev.setPower = function(p)
        dev._power = tonumber(p) or 0
        table.insert(dev._powerCalls, dev._power)
    end
    dev.setVector = function(x, y)
        dev._vectorX = tonumber(x) or 0.0
        dev._vectorY = tonumber(y) or 0.0
        table.insert(dev._vectorCalls, { x = dev._vectorX, y = dev._vectorY })
    end
    dev.getVectorX = function() return dev._vectorX end
    dev.getVectorY = function() return dev._vectorY end
    dev.getPower = function() return dev._power end
    return dev
end

describe("tca vector thruster peripheral adapter", function()
    it("scans and detects mock vector_thruster with setVector and setPower", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        assert_not_nil(state)
        assert_eq(state.interactionMode, "API")
        assert_eq(#state.peripherals, 1)
        assert_eq(state.peripherals[1].name, "left")
        assert_true(state.peripherals[1].isVectorCapable, "peripheral must be marked vector capable")
        assert_true(state.isVectorCapable, "adapter state must be vector capable")
        -- Cold boot neutral centering
        assert_near(mockDev._vectorX, 0.0, 1e-6)
        assert_near(mockDev._vectorY, 0.0, 1e-6)
    end)

    it("applies polymorphic table thrust command to setPower and setVector", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        local cmd = { thrust = 12, gimbalX = 0.5, gimbalY = -0.3 }
        actuator_adapter.apply_thrust(state, cmd, 1, 1)

        assert_eq(mockDev._power, 12)
        assert_near(mockDev._vectorX, 0.5, 1e-6)
        assert_near(mockDev._vectorY, -0.3, 1e-6)
        assert_near(state.lastGimbal.x, 0.5, 1e-6)
        assert_near(state.lastGimbal.y, -0.3, 1e-6)
        assert_false(state.isGimbalSaturated)
    end)

    it("cuts thrust and centers nozzle gimbals to (0, 0) on fail-safe cut_thrust", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        actuator_adapter.apply_thrust(state, { thrust = 14, gimbalX = 0.8, gimbalY = 0.4 }, 1, 1)
        assert_eq(mockDev._power, 14)
        assert_near(mockDev._vectorX, 0.8, 1e-6)

        actuator_adapter.cut_thrust(state)

        assert_eq(mockDev._power, 0)
        assert_near(mockDev._vectorX, 0.0, 1e-6)
        assert_near(mockDev._vectorY, 0.0, 1e-6)
        assert_near(state.lastGimbal.x, 0.0, 1e-6)
        assert_near(state.lastGimbal.y, 0.0, 1e-6)
        assert_false(state.isGimbalSaturated)
    end)

    it("clamps gimbal deflections to [-1.0, 1.0] and triggers gimbalSaturated flag", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        actuator_adapter.apply_thrust(state, { thrust = 12, gimbalX = 1.5, gimbalY = -2.0 }, 1, 1)

        assert_eq(mockDev._power, 12)
        assert_near(mockDev._vectorX, 1.0, 1e-6)
        assert_near(mockDev._vectorY, -1.0, 1e-6)
        assert_near(state.lastGimbal.x, 1.0, 1e-6)
        assert_near(state.lastGimbal.y, -1.0, 1e-6)
        assert_true(state.isGimbalSaturated)
    end)

    it("maintains backward compatibility with scalar number input setting neutral gimbals", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        actuator_adapter.apply_thrust(state, 10, 1, 1)

        assert_eq(mockDev._power, 10)
        assert_near(mockDev._vectorX, 0.0, 1e-6)
        assert_near(mockDev._vectorY, 0.0, 1e-6)
        assert_near(state.lastGimbal.x, 0.0, 1e-6)
        assert_near(state.lastGimbal.y, 0.0, 1e-6)
        assert_false(state.isGimbalSaturated)
    end)
end)

describe("tca vector thruster discovery and status reporting", function()
    it("reports vector capability and gimbal limits in discovery ACK", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local state = actuator_adapter.init("API", nil, {
            modemSide = "top",
            redstoneSide = "bottom",
            apiSides = { "left", "right" }
        })

        local isVec, limits = discovery_handler.resolve_vector_capability(state)
        assert_true(isVec)
        assert_eq(limits.minX, -1.0)
        assert_eq(limits.maxX, 1.0)
        assert_eq(limits.minY, -1.0)
        assert_eq(limits.maxY, 1.0)

        local cfg = {
            groupId = "THR_VTOL_1",
            aircraftDomainId = "AIRCRAFT_01",
            interactionMode = "API",
            nominalActuatorCount = 1
        }
        local reqPkt = { seq = 42, payload = { targetGroup = "ALL" } }
        local ack = discovery_handler.create_ack(reqPkt, cfg, state)

        assert_not_nil(ack)
        assert_eq(ack.type, "MSG_ACTUATOR_DISCOVER_ACK")
        assert_true(ack.payload.isVectorCapable)
        assert_not_nil(ack.payload.gimbalLimits)
        assert_eq(ack.payload.gimbalLimits.minX, -1.0)
        assert_eq(ack.payload.gimbalLimits.maxX, 1.0)
    end)

    it("propagates appliedGimbal and gimbalSaturated in status_reporter", function()
        local mockModem = mock.modem()
        local rep = status_reporter.init("THR_VTOL_1", mockModem, 10010, "AIRCRAFT_01")

        local statusPayload = {
            groupId = "THR_VTOL_1",
            interactionMode = "API",
            appliedSignal = 12,
            appliedRatio = 0.8,
            isSaturated = false,
            activeCount = 1,
            totalCount = 1,
            healthStatus = "API_NOMINAL",
            appliedGimbal = { x = 0.5, y = -0.3 },
            gimbalSaturated = false
        }

        local sent = rep:check_and_send(statusPayload, true)
        assert_true(sent)
        assert_eq(#mockModem._transmitted, 1)

        local sentPkt = mockModem._transmitted[1].pkt
        assert_eq(sentPkt.type, "MSG_ACTUATOR_STATUS")
        assert_not_nil(sentPkt.payload.appliedGimbal)
        assert_near(sentPkt.payload.appliedGimbal.x, 0.5, 1e-6)
        assert_near(sentPkt.payload.appliedGimbal.y, -0.3, 1e-6)
        assert_false(sentPkt.payload.gimbalSaturated)
    end)

    it("extracts polymorphic group outputs in group_allocator", function()
        local outputs = {
            THR_FIXED = 12,
            THR_VECTOR = { thrust = 14, gimbalX = 0.7, gimbalY = -0.4 }
        }

        local fixed = group_allocator.extract_group_output(outputs, "THR_FIXED")
        assert_eq(fixed, 12)

        local vec = group_allocator.extract_group_output(outputs, "THR_VECTOR")
        assert_not_nil(vec)
        assert_eq(type(vec), "table")
        assert_eq(vec.thrust, 14)
        assert_near(vec.gimbalX, 0.7, 1e-6)
        assert_near(vec.gimbalY, -0.4, 1e-6)
    end)

    it("handles vector thrust command in tca_daemon and centers on watchdog timeout", function()
        local mockDev = create_mock_vector_thruster()
        mock.peripheral_registry({
            left = { type = "vector_thruster", dev = mockDev }
        })

        local mockModem = mock.modem()
        local cfg = {
            groupId = "THR_VTOL_1",
            aircraftDomainId = "AIRCRAFT_01",
            aircraftIndexN = 1,
            baseChannel = 10000,
            channels = { thrustActuation = 10010 },
            watchdogTimeoutMs = 300,
            nominalActuatorCount = 1,
            interactionMode = "API",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } }
        }

        local daemon = tca_daemon.init(cfg, mockModem)

        local cmdPkt = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 5,
            type = "MSG_THRUST_CMD",
            payload = {
                watchdogSeq = 5,
                controlState = "NORMAL",
                outputs = {
                    THR_VTOL_1 = { thrust = 12, gimbalX = 0.6, gimbalY = -0.2 }
                }
            }
        }
        daemon:handle_thrust_cmd(cmdPkt)

        assert_eq(mockDev._power, 12)
        assert_near(mockDev._vectorX, 0.6, 1e-6)
        assert_near(mockDev._vectorY, -0.2, 1e-6)

        -- Watchdog timeout failsafe: cuts power and neutralizes gimbals
        daemon:handle_watchdog_timeout()
        assert_eq(mockDev._power, 0)
        assert_near(mockDev._vectorX, 0.0, 1e-6)
        assert_near(mockDev._vectorY, 0.0, 1e-6)
    end)
end)
