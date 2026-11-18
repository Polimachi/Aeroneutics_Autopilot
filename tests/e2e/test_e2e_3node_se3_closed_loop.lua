-- tests/e2e/test_e2e_3node_se3_closed_loop.lua
-- Scenario 8: 4-Tier SE(3) Live Closed Loop (AMM -> FCP -> VAS -> TCA), MFD_ACRO Takeover/Release,
-- 4-Layer MSG_CHANNEL_REBIND Cascade, and 3-Tier Failsafe Cascade
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

local B_6X12 = {
    { 0, 0, 8,  0, 0, 8,  0, 0, 8,  0, 0, 8 },
    { 0, 8, 0,  0, 8, 0,  0, 8, 0,  0, 8, 0 },
    { 1, 0, 0,  1, 0, 0,  1, 0, 0,  1, 0, 0 },
    {-1, 0, 0, -1, 0, 0,  1, 0, 0,  1, 0, 0 },
    { 1, 0, 0, -1, 0, 0,  1, 0, 0, -1, 0, 0 },
    { 0, 2,-2,  0, 2, 2,  0,-2,-2,  0,-2, 2 },
}

local B_DAGGER = {
    { 0.0,     0.0,     0.25, -0.25,  0.25,  0.0    },
    { 0.0,     0.03125, 0.0,   0.0,   0.0,   0.0625 },
    { 0.03125, 0.0,     0.0,   0.0,   0.0,  -0.0625 },
    { 0.0,     0.0,     0.25, -0.25, -0.25,  0.0    },
    { 0.0,     0.03125, 0.0,   0.0,   0.0,   0.0625 },
    { 0.03125, 0.0,     0.0,   0.0,   0.0,   0.0625 },
    { 0.0,     0.0,     0.25,  0.25,  0.25,  0.0    },
    { 0.0,     0.03125, 0.0,   0.0,   0.0,  -0.0625 },
    { 0.03125, 0.0,     0.0,   0.0,   0.0,  -0.0625 },
    { 0.0,     0.0,     0.25,  0.25, -0.25,  0.0    },
    { 0.0,     0.03125, 0.0,   0.0,   0.0,  -0.0625 },
    { 0.03125, 0.0,     0.0,   0.0,   0.0,   0.0625 },
}

local function install_vas_sensors(vas_node, altitude_ref)
    local orig = vas_node.env.peripheral
    local gimbal = {
        getAngles = function() return { pitch = 0.0, roll = 0.0, yaw = 0.0 } end,
        getAngularRates = function() return { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 } end,
    }
    local alt = {
        getHeight = function() return altitude_ref.y end,
        getVerticalSpeed = function() return altitude_ref.vy end,
    }
    local vel = {
        getVelocity = function() return { vx = altitude_ref.vx, vy = altitude_ref.vy, vz = altitude_ref.vz } end,
    }
    local map = { left = gimbal, right = alt, back = vel }
    local types = { left = "gimbal_sensor", right = "altitude_sensor", back = "velocity_sensor" }
    vas_node.env.peripheral = {
        getNames = function() return { "top", "left", "right", "back" } end,
        isPresent = function(s) return s == "top" or map[s] ~= nil end,
        getType = function(s) return types[s] or orig.getType(s) end,
        wrap = function(s) return map[s] or orig.wrap(s) end,
        find = function(pt, fn)
            for s, t in pairs(types) do
                if t == pt or t == ("avionics:" .. tostring(pt)) then return map[s] end
            end
            return orig.find(pt, fn)
        end,
        call = orig.call,
    }
end

local function install_tca_thruster(tca_node)
    local vec_hw = { _power = 0, _vectorX = 0.0, _vectorY = 0.0 }
    function vec_hw.setPower(p) vec_hw._power = tonumber(p) or 0 end
    function vec_hw.setVector(x, y)
        vec_hw._vectorX = tonumber(x) or 0.0
        vec_hw._vectorY = tonumber(y) or 0.0
    end
    function vec_hw.getVectorX() return vec_hw._vectorX end
    function vec_hw.getVectorY() return vec_hw._vectorY end
    function vec_hw.getPower() return vec_hw._power end

    local orig = tca_node.env.peripheral
    tca_node.env.peripheral = {
        getNames = function() return { "top", "left" } end,
        isPresent = function(s) return s == "top" or s == "left" end,
        getType = function(s) return (s == "left") and "vector_thruster" or orig.getType(s) end,
        wrap = function(s) return (s == "left") and vec_hw or orig.wrap(s) end,
        find = orig.find,
        call = orig.call,
    }
    return vec_hw
end

local function init_amm_and_fcp(bus)
    local amm_node = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
    local fcp_node = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
    local amm_main = amm_node:require("main")
    local amm_app = amm_main.create_app({
        domainId = "AIRCRAFT_01", baseChannel = 10000, airframeType = "ADVANCED_VTOL",
        headless = true, defaultAlt = 150.0, defaultSpeed = 18.0, arrivalRadius = 15.0,
    }, amm_node.modem)
    amm_app.sentinel.status = "ACQUIRED"
    amm_app.sentinel.baseChannel = 10000
    amm_app.nav.pos = { x = 0.0, y = 70.0, z = 0.0 }
    amm_app.nav.navValid = true
    amm_app.traj.airframeType = "ADVANCED_VTOL"

    local fcp_main = fcp_node:require("main")
    local fcp_cfg = fcp_main.load_config()
    fcp_cfg.system.airframeType = "ADVANCED_VTOL"
    fcp_cfg.system.domainId = "AIRCRAFT_01"
    fcp_cfg.configPath = "tmp_s8_fcp.json"
    fcp_cfg.safety = { ammSetpointTimeoutMs = 500, ammTimeoutHoldToEmgMs = 10000, bumplessRampSec = 2.0 }
    local fcp_ctx = fcp_main.create_context(fcp_cfg, function() return fcp_node.modem end)
    fcp_ctx.nav.pos = { x = 0.0, y = 70.0, z = 0.0 }

    return {
        amm_node = amm_node, amm_main = amm_main, amm = amm_app,
        amm_sentinel = amm_node:require("channel_sentinel"),
        fcp_node = fcp_node, fcp_main = fcp_main,
        fcp_net = fcp_node:require("network_manager"), fcp = fcp_ctx,
    }
end

local function init_vas_and_tca(bus, sensor_state)
    local vas_node = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
    local tca_node = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
    install_vas_sensors(vas_node, sensor_state)
    local vec_hw = install_tca_thruster(tca_node)

    local vas_daemon = vas_node:require("core_daemon")
    local vas_state = vas_daemon.init({
        system = {
            debug = false, domainId = "AIRCRAFT_01", aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000, airframeType = "ADVANCED_VTOL", vehicleType = "ADVANCED_VTOL",
            isVectorVtol = true, pseudoInverseMatrix = B_DAGGER, controlEffectivenessMatrix = B_6X12,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
            timeouts = { fcpCommandTimeoutMs = 1500 },
        },
        sensors = {
            roles = {
                gimbal = { peripheralType = "gimbal_sensor", preferredSide = "left" },
                altitude = { peripheralType = "altitude_sensor", preferredSide = "right" },
                velocity = { peripheralType = "velocity_sensor", preferredSide = "back" },
                fuel = { required = false },
            },
        },
        thrusters = {
            airframeType = "ADVANCED_VTOL", isVectorVtol = true,
            pseudoInverseMatrix = B_DAGGER, controlEffectivenessMatrix = B_6X12,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
        },
    })

    local tca_mod = tca_node:require("tca_daemon")
    local tca_inst = tca_mod.init({
        groupId = "THR_VEC_1", aircraftDomainId = "AIRCRAFT_01", aircraftIndexN = 1,
        baseChannel = 10000, channels = { thrustActuation = 10010 }, watchdogTimeoutMs = 300,
        nominalActuatorCount = 1, interactionMode = "API", configPath = "tmp_s8_tca.json",
        ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } },
    }, tca_node.modem)
    tca_node.modem:open(10010)

    return {
        vas_node = vas_node, vas_daemon = vas_daemon, vas = vas_state,
        tca_node = tca_node, tca = tca_inst, vec_hw = vec_hw,
    }
end

local function create_rig()
    local bus = virtual_bus.create_bus({ clock = 1.0 })
    sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)
    sdk.patch(_G, "print", function() end)
    local sensor_state = { y = 70.0, vx = 0.0, vy = 0.0, vz = 0.0 }
    local top = init_amm_and_fcp(bus)
    local bot = init_vas_and_tca(bus, sensor_state)
    local gcs_node = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
    gcs_node.modem:open(10003)

    local rig = {
        bus = bus, sensor_state = sensor_state, gcs_node = gcs_node, gcs_inbox = {},
        drop_amm_b4 = false, drop_fcp_b1 = false,
    }
    for k, v in pairs(top) do rig[k] = v end
    for k, v in pairs(bot) do rig[k] = v end
    return rig
end

local function deliver_node_inbox(rig)
    local now_ms = math.floor(rig.bus.time * 1000 + 0.5)
    for _, m in ipairs(rig.amm_node.modem:drain()) do
        rig.amm.now_ms = now_ms
        rig.amm_main.process_event(rig.amm, "modem_message", m.side, m.channel, m.replyChannel, m.payload)
    end
    for _, m in ipairs(rig.fcp_node.modem:drain()) do
        local is_b4 = (m.channel == rig.fcp.net.channels.trajectory)
        if not (rig.drop_amm_b4 and is_b4 and m.payload and m.payload.type == "MSG_TRAJECTORY_SETPOINT") then
            rig.fcp_net.ingest_modem_event(rig.fcp.net, m.side, m.channel, m.replyChannel, m.payload, m.distance, now_ms)
        end
    end
    for _, m in ipairs(rig.vas_node.modem:drain()) do
        local is_b1 = (m.channel == rig.vas.net.channels.guidance)
        if not (rig.drop_fcp_b1 and is_b1 and m.payload and m.payload.type == "MSG_ATTITUDE_CMD") then
            rig.vas_daemon.handle_event(rig.vas, "modem_message", m.side, m.channel, m.replyChannel, m.payload)
        end
    end
    for _, m in ipairs(rig.tca_node.modem:drain()) do
        rig.tca:dispatch_modem_message(m.channel, m.replyChannel, m.payload)
    end
    for _, m in ipairs(rig.gcs_node.modem:drain()) do
        table.insert(rig.gcs_inbox, m)
    end
end

local function pump_bus(rig, dt, rounds)
    for _ = 1, (rounds or 1) do
        rig.bus:step(dt or 0.01)
        deliver_node_inbox(rig)
    end
end

local function step_all(rig, dt)
    local step_dt = dt or 0.05
    if not rig.drop_amm_b4 then
        local now_ms = math.floor(rig.bus.time * 1000 + 0.5)
        rig.amm.now_ms = now_ms
        rig.amm_main.step_20hz_tick(rig.amm, step_dt, now_ms)
    end
    pump_bus(rig, step_dt * 0.25, 1)
    rig.fcp_main.step_tick(rig.fcp, step_dt, math.floor(rig.bus.time * 1000 + 0.5))
    pump_bus(rig, step_dt * 0.25, 1)
    rig.vas_daemon.tick(rig.vas)
    pump_bus(rig, step_dt * 0.5, 1)
end

local function find_latest_pkt(bus, pkt_type, channel, min_seq)
    local pkts = bus:find_packets({ type = pkt_type, channel = channel })
    for i = #pkts, 1, -1 do
        if not min_seq or pkts[i].seq > min_seq then
            return pkts[i].payload
        end
    end
    return nil
end

local function cleanup_temp_files()
    if fs and fs.exists then
        if fs.exists("tmp_s8_fcp.json") then pcall(fs.delete, "tmp_s8_fcp.json") end
        if fs.exists("tmp_s8_tca.json") then pcall(fs.delete, "tmp_s8_tca.json") end
    end
end

local function verify_bumpless_ramp(rig, find_pkt, steps)
    local prev_s, prev_w, max_ds, max_dw = 0.0, 0.0, 0.0, 0.0
    for _ = 1, (steps or 40) do
        local seq_r = #rig.bus.packet_log
        step_all(rig, 0.05)
        local cmd = find_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10001, seq_r)
        assert_not_nil(cmd)
        local b = cmd.payload.translationBias
        max_ds = math.max(max_ds, math.abs(b.surge - prev_s))
        max_dw = math.max(max_dw, math.abs(b.sway - prev_w))
        prev_s, prev_w = b.surge, b.sway
    end
    assert_near(rig.fcp.rampAlpha, 1.0, 1e-6)
    assert_true(max_ds <= 0.11 and max_dw <= 0.11, "ADVANCED_VTOL surge/sway transition must be continuous")
end

describe("Scenario 8: 4-Tier SE(3) Live Closed Loop (AMM -> FCP -> VAS -> TCA)", function()
    it("drives live AMM -> FCP -> VAS -> TCA closed loop across TAKEOFF, CRUISE, LOITER, POI_HOLD, and LANDING", function()
        cleanup_temp_files()
        local rig = create_rig()
        local now_ms = math.floor(rig.bus.time * 1000 + 0.5)

        -- AMM Boot State Verification: arm must be false prior to pilot arming
        local boot_goal = rig.amm.arbiter:get_effective_goal()
        assert_false(boot_goal.arm, "AMM boot goal must have arm = false before any pilot/C2 arming action")

        rig.amm.arbiter:handle_pilot_action("TAKEOFF", { targetAlt = 150.0 }, now_ms)
        step_all(rig, 0.05)
        step_all(rig, 0.05)
        step_all(rig, 0.05)
        assert_eq(rig.fcp.fsm.currentState, "ACTIVE_TRACKING")
        assert_eq(rig.vas.fsm.currentState, "NORMAL")
        assert_true(rig.vec_hw._power > 0)

        local modes = {
            { mode = "CRUISE", goal = { flightMode = "CRUISE", arm = true, flightActive = true, targetPos = { x = 40, y = 150, z = -60 }, targetAlt = 150, targetSpeed = 18, constraintProfile = "STRICT_LEVEL" } },
            { mode = "LOITER", goal = { flightMode = "LOITER", arm = true, flightActive = true, targetPos = { x = 40, y = 150, z = -60 }, targetAlt = 150, loiterRadius = 30 } },
            { mode = "POI_HOLD", goal = { flightMode = "POI_HOLD", arm = true, flightActive = true, targetPos = { x = 40, y = 150, z = -60 }, targetAlt = 150, poiTarget = { x = 100, y = 70, z = -60 } } },
            { mode = "LANDING", goal = { flightMode = "LANDING", arm = true, flightActive = true, targetPos = { x = 40, y = 70, z = -60 }, targetAlt = 70 } },
        }
        for _, entry in ipairs(modes) do
            local seq0 = #rig.bus.packet_log
            rig.amm.arbiter.fcpTakeoffActive = false
            rig.amm.arbiter.activeGoal = entry.goal
            step_all(rig, 0.05)
            local att = find_latest_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10001, seq0)
            assert_not_nil(att, "Missing FCP Base+1 command for " .. entry.mode)
            assert_eq(att.payload.commandType, "QUATERNION_RATE")
            assert_eq(att.payload.flightMode, entry.mode)
            assert_not_nil(find_latest_pkt(rig.bus, "MSG_THRUST_CMD", 10010, seq0))
            assert_not_nil(find_latest_pkt(rig.bus, "MSG_FLIGHT_TELEMETRY", 10002, seq0))
            local tlm = find_latest_pkt(rig.bus, "MSG_FLIGHT_TELEMETRY", 10002, seq0)
            if tlm and tlm.payload and tlm.payload.actuatorHealth then
                assert_true(tlm.payload.actuatorHealth.allOk ~= nil)
            end
        end
        assert_true(#rig.gcs_inbox >= 1, "AMM 5Hz Base+3 MFD downlink must reach GCS")
    end)

    it("handles MFD_ACRO takeover (AMM Base+3 yield, VAS CORE_ACRO_TAKEOVER, FCP PASSIVE_TRACKING)", function()
        local rig = create_rig()
        rig.amm.arbiter.activeGoal = {
            flightMode = "CRUISE", arm = true, flightActive = true,
            targetPos = { x = 30, y = 150, z = -40 }, targetAlt = 150, targetSpeed = 18, constraintProfile = "STRICT_LEVEL",
        }
        step_all(rig, 0.05)
        step_all(rig, 0.05)

        local mfd_node = node_sandbox.create_node(rig.bus, "MFD_ACRO", "src/1_control/vas")
        mfd_node.modem:transmit(10001, 10001, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_ATTITUDE_CMD", time = 1200,
            payload = {
                source = "MFD_ACRO", acroActive = true, commandType = "RATE_COMMAND", arm = true, flightActive = true,
                targetAngularRates = { pitchRate = 0, rollRate = 0, yawRate = 12 }, collectiveThrust = 0.65,
            },
        })
        pump_bus(rig, 0.01, 1)
        assert_eq(rig.vas.fsm.activeSource, "MFD_ACRO")

        local seq_acro = #rig.bus.packet_log
        rig.vas_daemon.tick(rig.vas)
        pump_bus(rig, 0.01, 1)
        local seq_passive = #rig.bus.packet_log
        step_all(rig, 0.05)
        assert_eq(rig.fcp.fsm.currentState, "PASSIVE_TRACKING")
        assert_eq(rig.amm.arbiter.activeSource, "MFD_ACRO")
        local ok_yield, err_yield = rig.amm.net:send_mfd_state({ fsmState = "CRUISE" }, rig.amm.arbiter.activeSource)
        assert_false(ok_yield)
        assert_eq(err_yield, "YIELDED_TO_MFD_ACRO")
        local acro_mfd = find_latest_pkt(rig.bus, "MSG_MFD_STATE", 10003, seq_acro)
        assert_not_nil(acro_mfd)
        assert_eq(acro_mfd.payload.source, "CORE_ACRO_TAKEOVER")
        assert_nil(find_latest_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10001, seq_passive), "FCP must silence Base+1 in PASSIVE_TRACKING")
    end)

    it("handles MFD_ACRO release to FCP and performs 2.0s bumpless release ramp", function()
        local rig = create_rig()
        rig.amm.arbiter.activeGoal = {
            flightMode = "CRUISE", arm = true, flightActive = true,
            targetPos = { x = 30, y = 150, z = -40 }, targetAlt = 150, targetSpeed = 18, constraintProfile = "STRICT_LEVEL",
        }
        step_all(rig, 0.05)
        step_all(rig, 0.05)

        local mfd_node = node_sandbox.create_node(rig.bus, "MFD_ACRO", "src/1_control/vas")
        mfd_node.modem:transmit(10001, 10001, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 1, type = "MSG_ATTITUDE_CMD", time = 1200,
            payload = {
                source = "MFD_ACRO", acroActive = true, commandType = "RATE_COMMAND", arm = true, flightActive = true,
                targetAngularRates = { pitchRate = 0, rollRate = 0, yawRate = 12 }, collectiveThrust = 0.65,
            },
        })
        pump_bus(rig, 0.01, 1)
        rig.vas_daemon.tick(rig.vas)
        pump_bus(rig, 0.01, 1)
        step_all(rig, 0.05)

        mfd_node.modem:transmit(10001, 10001, {
            ver = "1.9.5", domainId = "AIRCRAFT_01", seq = 2, type = "MSG_ATTITUDE_CMD", time = 1300,
            payload = {
                source = "MFD_ACRO", acroActive = false, commandType = "QUATERNION_RATE", arm = true, flightActive = true,
                targetQuaternion = { w = 1, x = 0, y = 0, z = 0 },
                targetAngularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 }, collectiveThrust = 0.65,
            },
        })
        pump_bus(rig, 0.01, 1)
        rig.vas_daemon.tick(rig.vas)
        pump_bus(rig, 0.01, 1)
        rig.fcp.bumplessRampSec = 1.25
        step_all(rig, 0.05)
        assert_eq(rig.vas.fsm.activeSource, "FCP")
        assert_eq(rig.fcp.fsm.currentState, "ACTIVE_TRACKING")
        assert_not_nil(rig.fcp.rampStartMs)
        assert_true(rig.fcp.rampAlpha < 0.2)
        verify_bumpless_ramp(rig, find_latest_pkt, 25)
    end)

    it("executes 4-layer live MSG_CHANNEL_REBIND cascade (AMM -> FCP -> VAS -> TCA -> ACKs -> COMMIT) and continues closed loop", function()
        local rig = create_rig()
        rig.amm.arbiter.activeGoal = {
            flightMode = "CRUISE", arm = true, flightActive = true,
            targetPos = { x = 20, y = 150, z = -20 }, targetAlt = 150, constraintProfile = "STRICT_LEVEL",
        }
        step_all(rig, 0.05)

        local now_ms = math.floor(rig.bus.time * 1000 + 0.5)
        local prep = rig.amm_sentinel.initiate_rebind(rig.amm.sentinel, 10080, now_ms)
        assert_not_nil(prep)
        rig.amm.net:send_rebind_command("PREPARE", prep.payload.transactionId, 10000, 10080)
        pump_bus(rig, 0.01, 6)

        assert_not_nil(rig.amm.sentinel.rebindTx)
        assert_eq(rig.amm.sentinel.rebindTx.status, "ACKED")

        local rebind_acks = rig.bus:find_packets({ type = "MSG_CHANNEL_REBIND_ACK" })
        assert_true(#rebind_acks >= 1, "Must transmit MSG_CHANNEL_REBIND_ACK upward")

        step_all(rig, 0.05)
        pump_bus(rig, 0.01, 4)

        assert_eq(rig.amm.net.baseChannel, 10080)
        assert_eq(rig.fcp.net.baseChannel, 10080)
        assert_eq(rig.vas.net.baseChannel, 10080)
        assert_eq(rig.tca.cfg.baseChannel, 10080)
        assert_true(rig.amm_node.modem:isOpen(10084) and not rig.amm_node.modem:isOpen(10004))
        assert_true(rig.fcp_node.modem:isOpen(10081) and not rig.fcp_node.modem:isOpen(10001))
        assert_true(rig.vas_node.modem:isOpen(10081) and not rig.vas_node.modem:isOpen(10001))
        assert_true(rig.tca_node.modem:isOpen(10090) and not rig.tca_node.modem:isOpen(10010))

        rig.gcs_node.modem:open(10083)
        local seq_new = #rig.bus.packet_log
        for _ = 1, 4 do step_all(rig, 0.05) end
        assert_not_nil(find_latest_pkt(rig.bus, "MSG_TRAJECTORY_SETPOINT", 10084, seq_new))
        assert_not_nil(find_latest_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10081, seq_new))
        assert_not_nil(find_latest_pkt(rig.bus, "MSG_THRUST_CMD", 10090, seq_new))
        assert_not_nil(find_latest_pkt(rig.bus, "MSG_FLIGHT_TELEMETRY", 10082, seq_new))
        assert_not_nil(find_latest_pkt(rig.bus, "MSG_MFD_STATE", 10083, seq_new))
        cleanup_temp_files()
    end)

    it("executes 3-tier failsafe cascade across AMM Base+4 drop and FCP Base+1 drop", function()
        local rig = create_rig()
        rig.amm.arbiter.activeGoal = {
            flightMode = "CRUISE", arm = true, flightActive = true,
            targetPos = { x = 20, y = 150, z = -20 }, targetAlt = 150, constraintProfile = "STRICT_LEVEL",
        }
        step_all(rig, 0.05)
        step_all(rig, 0.05)
        assert_eq(rig.fcp.fsm.currentState, "ACTIVE_TRACKING")
        assert_eq(rig.vas.fsm.currentState, "NORMAL")

        -- Tier A: Drop AMM Base+4 -> FCP 500ms AMM_TIMEOUT_HOLD -> 10s EMERGENCY_LAND
        rig.drop_amm_b4 = true
        rig.bus.time = rig.bus.time + 0.55
        step_all(rig, 0.05)
        assert_eq(rig.fcp.fsm.currentState, "AMM_TIMEOUT_HOLD")
        local seq_hold = #rig.bus.packet_log
        step_all(rig, 0.05)
        local hold_att = find_latest_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10001, seq_hold)
        assert_not_nil(hold_att)
        assert_eq(hold_att.payload.flightMode, "HOVER_HOLD")

        rig.bus.time = rig.bus.time + 10.1
        step_all(rig, 0.05)
        assert_eq(rig.fcp.fsm.currentState, "EMERGENCY_LAND")
        local seq_emg = #rig.bus.packet_log
        step_all(rig, 0.05)
        local emg_att = find_latest_pkt(rig.bus, "MSG_ATTITUDE_CMD", 10001, seq_emg)
        assert_not_nil(emg_att)
        assert_eq(emg_att.payload.flightMode, "EMERGENCY_LAND")

        -- Tier B: Drop FCP Base+1 -> VAS 1500ms FAILSAFE_HOLD -> 10s EMERGENCY_LAND
        rig.drop_fcp_b1 = true
        rig.bus.time = rig.bus.time + 1.6
        for _ = 1, 4 do step_all(rig, 0.05) end
        assert_eq(rig.vas.fsm.currentState, "FAILSAFE_HOLD")
        assert_eq(rig.vas.fsm.transitionReason, "FCP_CMD_TIMEOUT_1500MS")
        assert_eq(rig.tca.lastControlState, "FAILSAFE_HOLD")
        local fs_mfd = find_latest_pkt(rig.bus, "MSG_MFD_STATE", 10003, seq_emg)
        assert_not_nil(fs_mfd)
        assert_eq(fs_mfd.payload.source, "CORE_FAILSAFE")

        rig.bus.time = rig.bus.time + 10.1
        step_all(rig, 0.05)
        assert_eq(rig.vas.fsm.currentState, "EMERGENCY_LAND")
        assert_eq(rig.tca.lastControlState, "EMERGENCY_LAND")
    end)

    it("recovers from mid-air cold reboot across VAS, FCP, and AMM (AIRBORNE_RECOVERY_HOLD -> RESUME & RTB)", function()
        local vasSnap = "tmp_s8_vas_fs.json"
        local ammSnap = "tmp_s8_amm_fs.json"
        local ammLease = "tmp_s8_amm_lease.json"
        local missionPath = "missions/test_e2e_cb_sortie.json"
        local function clean_cb()
            for _, p in ipairs({ vasSnap, ammSnap, ammLease, missionPath, "tmp_s8_fcp.json", "tmp_s8_tca.json" }) do
                if fs.exists(p) then pcall(fs.delete, p) end
            end
        end
        clean_cb()
        if not fs.exists("missions") then fs.makeDir("missions") end

        local mh = fs.open(missionPath, "w")
        mh.write(textutils.serializeJSON({
            version = "2.0.0",
            missionId = "test_e2e_cb_sortie",
            executionMode = "SINGLE",
            checkpoints = {
                { checkpointId = "CP_1_TK", action = "ACT_TKL_TAKEOFF_VERT", params = { targetAlt = 140, facilityId = "PAD_HOME_01" } },
                { checkpointId = "CP_2_WP", action = "ACT_NAV_GOTO_WP", params = { targetPos = { x = 80, z = -40 }, targetAlt = 140, cruiseSpeed = 16 } },
            },
        }))
        mh.close()

        local seedJson = textutils.serializeJSON({
            schemaVersion = 1,
            armedState = "AIRBORNE_ACTIVE",
            missionId = "test_e2e_cb_sortie",
            currentCpIdx = 2,
            homePadId = "PAD_HOME_01",
            homePos = { x = 0, y = 70, z = 0 },
            savedAtEpoch = 1000,
        })
        for _, spath in ipairs({ vasSnap, ammSnap }) do
            local sh = fs.open(spath, "w")
            sh.write(seedJson)
            sh.close()
        end

        local bus = virtual_bus.create_bus({ clock = 2.0 })
        sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)
        sdk.patch(_G, "print", function() end)
        local sensor_state = { y = 140.0, vx = 0.0, vy = -2.5, vz = 0.0 }

        -- Cold-boot VAS + TCA + FCP before AMM synchronizes
        local vas_node = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca_node = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        install_vas_sensors(vas_node, sensor_state)
        local vec_hw = install_tca_thruster(tca_node)

        local tca_inst = tca_node:require("tca_daemon").init({
            groupId = "THR_VEC_1", aircraftDomainId = "AIRCRAFT_01", aircraftIndexN = 1,
            baseChannel = 10000, channels = { thrustActuation = 10010 }, watchdogTimeoutMs = 300,
            nominalActuatorCount = 1, interactionMode = "API", configPath = "tmp_s8_tca.json",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } },
        }, tca_node.modem)
        tca_node.modem:open(10010)

        local fcp_node = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local fcp_main = fcp_node:require("main")
        local fcp_cfg = fcp_main.load_config()
        fcp_cfg.system.airframeType = "ADVANCED_VTOL"
        fcp_cfg.system.domainId = "AIRCRAFT_01"
        fcp_cfg.configPath = "tmp_s8_fcp.json"
        fcp_cfg.safety = { ammSetpointTimeoutMs = 500, ammTimeoutHoldToEmgMs = 10000, bumplessRampSec = 2.0 }
        local fcp_ctx = fcp_main.create_context(fcp_cfg, function() return fcp_node.modem end)
        fcp_ctx.nav.pos = { x = 10.0, y = 140.0, z = -5.0 }

        local vas_daemon = vas_node:require("core_daemon")
        local vas_state = vas_daemon.init({
            system = {
                debug = false, domainId = "AIRCRAFT_01", aircraftDomainId = "AIRCRAFT_01",
                baseChannel = 10000, airframeType = "ADVANCED_VTOL", vehicleType = "ADVANCED_VTOL",
                isVectorVtol = true, pseudoInverseMatrix = B_DAGGER, controlEffectivenessMatrix = B_6X12,
                vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
                timeouts = { fcpCommandTimeoutMs = 1500 },
                bootRecovery = { enabled = true, stateFilePath = vasSnap, bootTimeoutMs = 500, recoveryMaxHoldSec = 10.0 },
            },
            sensors = {
                roles = {
                    gimbal = { peripheralType = "gimbal_sensor", preferredSide = "left" },
                    altitude = { peripheralType = "altitude_sensor", preferredSide = "right" },
                    velocity = { peripheralType = "velocity_sensor", preferredSide = "back" },
                    fuel = { required = false },
                },
            },
            thrusters = {
                airframeType = "ADVANCED_VTOL", isVectorVtol = true,
                pseudoInverseMatrix = B_DAGGER, controlEffectivenessMatrix = B_6X12,
                vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
            },
        })

        assert_eq(vas_state.fsm.currentState, "AIRBORNE_RECOVERY_HOLD")
        assert_true(vas_state.fsm.isAirborne)
        assert_true((vas_state.bootElapsedMs or 0) <= 500)

        local fcp_net = fcp_node:require("network_manager")
        local gcs_node = node_sandbox.create_node(bus, "GCS", "src/0_infra/gcs")
        gcs_node.modem:open(10003)

        -- Pump VAS boot tick to TCA & FCP, then step FCP alone (AMM still offline)
        bus:step(0.01)
        for _, m in ipairs(tca_node.modem:drain()) do
            tca_inst:dispatch_modem_message(m.channel, m.replyChannel, m.payload)
        end
        for _, m in ipairs(fcp_node.modem:drain()) do
            fcp_net.ingest_modem_event(fcp_ctx.net, m.side, m.channel, m.replyChannel, m.payload, m.distance, 2010)
        end
        assert_true(vec_hw._power > 0, "VAS boot tick must actuate thrust via TCA immediately")

        local seq_silence = #bus.packet_log
        fcp_main.step_tick(fcp_ctx, 0.05, 2050)
        assert_eq(fcp_ctx.fsm.currentState, "IDLE_ARMED")
        assert_nil(find_latest_pkt(bus, "MSG_ATTITUDE_CMD", 10001, seq_silence), "FCP must silence Base+1 disarm during AIRBORNE_RECOVERY_HOLD")

        -- Now cold-boot AMM with RESUME policy
        local amm_node = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local amm_main = amm_node:require("main")
        local amm_app = amm_main.create_app({
            domainId = "AIRCRAFT_01", baseChannel = 10000, airframeType = "ADVANCED_VTOL",
            headless = true, defaultAlt = 140.0, defaultSpeed = 16.0, arrivalRadius = 15.0,
            leasePath = ammLease, clock_ms = 2100,
            recovery = { enabled = true, persist = true, stateFilePath = ammSnap, coldBootPolicy = "RESUME" },
        }, amm_node.modem)
        amm_app.sentinel.status = "ACQUIRED"
        amm_app.sentinel.baseChannel = 10000
        amm_app.nav.pos = { x = 10.0, y = 140.0, z = -5.0 }
        amm_app.nav.navValid = true
        amm_app.traj.airframeType = "ADVANCED_VTOL"

        assert_eq(amm_app.engine.state, "EN_ROUTE")
        assert_eq(amm_app.engine.active_index, 2)

        local rig = {
            bus = bus, sensor_state = sensor_state, gcs_node = gcs_node, gcs_inbox = {},
            amm_node = amm_node, amm_main = amm_main, amm = amm_app, amm_sentinel = amm_node:require("channel_sentinel"),
            fcp_node = fcp_node, fcp_main = fcp_main, fcp_net = fcp_net, fcp = fcp_ctx,
            vas_node = vas_node, vas_daemon = vas_daemon, vas = vas_state,
            tca_node = tca_node, tca = tca_inst, vec_hw = vec_hw,
        }
        step_all(rig, 0.05)
        step_all(rig, 0.05)

        assert_eq(fcp_ctx.fsm.currentState, "ACTIVE_TRACKING")
        assert_not_nil(fcp_ctx.rampStartMs)
        assert_true(fcp_ctx.rampAlpha < 0.25)
        assert_eq(vas_state.fsm.currentState, "NORMAL")
        assert_eq(tca_inst.lastControlState, "NORMAL")

        -- Verify coldBootPolicy = RTB on cold-boot AMM restores FAILSAFE_RTH to PAD_HOME_01
        local amm_rtb_node = node_sandbox.create_node(bus, "AMM_RTB", "src/3_planning/amm")
        local amm_rtb_main = amm_rtb_node:require("main")
        local amm_rtb = amm_rtb_main.create_app({
            domainId = "AIRCRAFT_01", baseChannel = 10000, airframeType = "ADVANCED_VTOL",
            headless = true, defaultAlt = 140.0, defaultSpeed = 16.0, arrivalRadius = 15.0,
            leasePath = ammLease, clock_ms = 2300,
            recovery = { enabled = true, persist = false, stateFilePath = ammSnap, coldBootPolicy = "RTB" },
        }, amm_rtb_node.modem)
        local rtb_goal = amm_rtb.arbiter:get_effective_goal()
        assert_eq(rtb_goal.flightMode, "FAILSAFE_RTH")
        assert_eq(rtb_goal.designatedFacilityId, "PAD_HOME_01")
        assert_true(rtb_goal.arm)
        assert_true(rtb_goal.flightActive)

        clean_cb()
    end)

    it("executes multi-node PBIT handshake, peripheralManifest topology interlock, and >1.5s GPS blackout HOLD_LEVEL + recovery (TASK-136, TASK-131, TASK-128)", function()
        local fsSnap1 = "/_e2e_t131_vas.json"
        local fsSnap2 = "/_e2e_t131_amm.json"
        local function cleanup_files()
            for _, p in ipairs({ fsSnap1, fsSnap2, "tmp_e2e_pbit_tca.json", "tmp_e2e_pbit_fcp.json", "config/thrusters.json", "config/peripheral_manifest.json" }) do
                if fs.exists(p) then fs.delete(p) end
            end
        end
        cleanup_files()

        local bus = virtual_bus.create_bus({ clock = 1.0 })
        sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)
        sdk.patch(_G, "print", function() end)

        local sensor_state = { y = 64.0, vx = 0.0, vy = 0.0, vz = 0.0 }
        local vas_node = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca_node = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local fcp_node = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local amm_node = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local align_node = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local gps_node = node_sandbox.create_node(bus, "GPS", "src/0_infra/gps")

        install_vas_sensors(vas_node, sensor_state)
        install_tca_thruster(tca_node)

        local vas_daemon = vas_node:require("core_daemon")
        local vas_net = vas_node:require("network_manager")
        local vas_sp = vas_node:require("sensor_pipeline")
        local vas_fsm_mod = vas_node:require("state_machine")

        local vas_state = vas_daemon.init({
            system = {
                debug = false, domainId = "AIRCRAFT_01", aircraftDomainId = "AIRCRAFT_01",
                baseChannel = 10000, airframeType = "ADVANCED_VTOL", vehicleType = "ADVANCED_VTOL",
                bootRecovery = { enabled = false, stateFilePath = fsSnap1 },
            },
            sensors = {
                roles = {
                    gimbal = { peripheralType = "gimbal_sensor", preferredSide = "left" },
                    altitude = { peripheralType = "altitude_sensor", preferredSide = "right" },
                    velocity = { peripheralType = "velocity_sensor", preferredSide = "back" },
                    fuel = { required = false },
                },
            },
            thrusters = { THR_VEC_1 = { heave = 1.0, maxThrust = 15 } },
        })
        vas_node.modem:open(10008)
        vas_node.modem:open(10010)

        local tca_inst = tca_node:require("tca_daemon").init({
            groupId = "THR_VEC_1", aircraftDomainId = "AIRCRAFT_01", aircraftIndexN = 1,
            baseChannel = 10000, channels = { thrustActuation = 10010 }, watchdogTimeoutMs = 300,
            nominalActuatorCount = 1, interactionMode = "API", configPath = "tmp_e2e_pbit_tca.json",
            ports = { modemSide = "top", redstoneSide = "bottom", apiSides = { "left" } },
        }, tca_node.modem)
        tca_inst.lastControlState = "DISARMED"
        tca_node.modem:open(10010)

        local amm_main = amm_node:require("main")
        local amm_app = amm_main.create_app({
            domainId = "AIRCRAFT_01", baseChannel = 10000, airframeType = "ADVANCED_VTOL",
            headless = true, defaultAlt = 140.0, defaultSpeed = 16.0, arrivalRadius = 15.0,
            clock_ms = 1000,
            recovery = { enabled = false, persist = false, stateFilePath = fsSnap2 },
        }, amm_node.modem)
        amm_node.modem:open(10002)
        amm_node.modem:open(10005)
        amm_node.modem:open(10008)

        -- Complete initial VAS<->TCA discovery handshake so adapter.tcaConnected becomes true
        bus:step(0.01)
        for _, m in ipairs(tca_node.modem:drain()) do
            tca_inst:dispatch_modem_message(m.channel, m.replyChannel, m.payload)
        end
        bus:step(0.01)
        for _, m in ipairs(vas_node.modem:drain()) do
            vas_net.dispatch(vas_state.net, vas_state.fsm, vas_state.fdCore, vas_state.adapter, m.channel, m.replyChannel, m.payload)
        end
        assert_true(vas_state.adapter.tcaConnected)

        -- 1. TASK-131: AMM sends MSG_PBIT_REQ on Base+8 -> VAS -> TCA (<5% wiggle) & AMM (MSG_PBIT_REPORT)
        assert_true(amm_app.net:send_pbit_req({ requestId = "E2E-PBIT-1", source = "AMM", runWiggle = true, busRttMs = 15 }))
        bus:step(0.01)
        for _, m in ipairs(vas_node.modem:drain()) do
            vas_net.dispatch(vas_state.net, vas_state.fsm, vas_state.fdCore, vas_state.adapter, m.channel, m.replyChannel, m.payload)
        end
        bus:step(0.01)
        for _, m in ipairs(tca_node.modem:drain()) do
            tca_inst:dispatch_modem_message(m.channel, m.replyChannel, m.payload)
        end
        assert_eq(tca_inst.adapterState.lastSignal, 0)
        assert_near(tca_inst.lastPbitWiggleRatio or 0, 0.04, 1e-6)
        bus:step(0.01)
        for _, m in ipairs(amm_node.modem:drain()) do
            amm_main.handle_modem_message(amm_app, m.channel, m.payload, 1030)
        end
        assert_not_nil(amm_app.engine.lastPbitReport)
        assert_eq(amm_app.engine.lastPbitReport.overallStatus, "PASS")
        assert_true(amm_app.engine.lastPbitReport.takeoffPermitted)

        local mission = {
            missionId = "E2E_PBIT_GATE", version = "2.0.0", fallbackPolicy = "HOVER_HOLD",
            checkpoints = { { checkpointId = "CP_TO", action = "ACT_TKL_TAKEOFF_VERT", params = { targetAlt = 120.0 } } },
        }
        amm_app.engine.requirePbit = true
        assert_true(amm_app.engine:load_table(mission))
        assert_true(amm_app.engine:start("SINGLE", 1040))

        -- 2. TASK-136: Alignment peripheralManifest check detects >5% mass shift & fails PBIT inertiaProfile
        local exporter = align_node:require("profile_exporter")
        local manifest = exporter.build_peripheral_manifest("AIRCRAFT_01", { THR_VEC_1 = { peripheralCount = 1 } }, {}, { "gimbal" }, 10000.0)
        vas_state.net.on_profile_sync({ profileId = "PROF-E2E", controllabilityStatus = "FULL_6DOF_PASS", peripheralManifest = manifest })
        assert_false(vas_state.fsm.recalibrationRequired)
        local topoBad = vas_sp.verify_and_rebind_topology(vas_state.sensors, vas_state.peripheralManifest, { "thruster_left" }, 11500.0)
        assert_true(topoBad.recalibrationRequired)
        vas_fsm_mod.update_contraption_interlock(vas_state.fsm, "ASSEMBLED", topoBad.recalibrationRequired, topoBad.reason)
        local repFail = vas_fsm_mod.evaluate_pbit(vas_state.fsm, { busRttMs = 12 })
        assert_eq(repFail.overallStatus, "FAIL")
        assert_false(repFail.takeoffPermitted)

        -- 3. TASK-128: MSG_NAV_QUALITY over virtual_bus + FCP 1.5s DR hold-over -> HOLD_LEVEL -> recovery ramp
        local gpsProto = gps_node:require("protocol")
        local nqPkt = gpsProto.buildNavQuality("GPS_BASE_NET", 1, {
            targetClient = "AIRCRAFT_01", navQuality = "LOST", satelliteCount = 1,
            consecutiveFailures = 3, hdop = 9.9, status = "NO_FIX",
            drHoldoverActive = false, holdLevelActive = true, blackoutMs = 1700,
        }, 1200)
        gps_node.modem:transmit(10005, 10005, nqPkt)
        bus:step(0.01)
        for _, m in ipairs(amm_node.modem:drain()) do
            amm_main.handle_modem_message(amm_app, m.channel, m.payload, 1210)
        end
        assert_eq(amm_app.nav.navQuality, "LOST")

        local fcp_main = fcp_node:require("main")
        local fcp_sp = fcp_node:require("state_propagator")
        local fcp_cfg = fcp_main.load_config()
        fcp_cfg.system.airframeType = "ADVANCED_VTOL"
        fcp_cfg.system.domainId = "AIRCRAFT_01"
        fcp_cfg.configPath = "tmp_e2e_pbit_fcp.json"
        local fcp_ctx = fcp_main.create_context(fcp_cfg, function() return fcp_node.modem end)
        fcp_sp.on_setpoint_epoch(fcp_ctx.nav, { posEpoch = 1, currentPos = { x = 100, y = 140, z = 200 }, navValid = true, gpsTimedOut = false, navQuality = "GOOD" }, 1000)
        local snapOk = fcp_sp.propagate(fcp_ctx.nav, 1050)
        assert_false(snapOk.holdLevelActive)

        fcp_sp.on_setpoint_epoch(fcp_ctx.nav, { posEpoch = 2, currentPos = { x = 100, y = 140, z = 200 }, navValid = true, gpsTimedOut = true, navQuality = "LOST" }, 1600)
        local snapDr = fcp_sp.propagate(fcp_ctx.nav, 1650)
        assert_true(snapDr.drHoldoverActive)
        assert_false(snapDr.holdLevelActive)

        local snapLvl = fcp_sp.propagate(fcp_ctx.nav, 2700)
        assert_true(snapLvl.holdLevelActive)

        -- Recovery clears holdLevelActive via chunk blend & FCP step_tick triggers bumpless ramp
        fcp_sp.on_setpoint_epoch(fcp_ctx.nav, { posEpoch = 3, currentPos = { x = 125, y = 140, z = 200 }, navValid = true, gpsTimedOut = false, navQuality = "GOOD" }, 2750)
        fcp_ctx.prevHoldLevel = true
        fcp_main.step_tick(fcp_ctx, 0.05, 2800)
        assert_false(fcp_ctx.nav.holdLevelActive)
        assert_not_nil(fcp_ctx.rampStartMs)

        cleanup_files()
    end)
end)
