-- tests/e2e/test_e2e_pocket_pda_remote.lua
-- Scenario 11: Pocket PDA Remote C2, Single-Key E_STOP + Immediate FDR JSONL Dump,
-- and Remote Hangar Alignment & FDR Dynamic Aircraft [N] Rebinding
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

local function make_vfs_fs(free_map)
    local files, dirs = {}, {}
    local function norm(p)
        local c = tostring(p or "/"):gsub("//+", "/")
        if #c > 1 and c:sub(-1) == "/" then c = c:sub(1, -2) end
        return c
    end
    return {
        exists = function(p)
            p = norm(p)
            return files[p] ~= nil or dirs[p] == true or p == "/" or free_map[p] ~= nil
        end,
        isDir = function(p)
            p = norm(p)
            return dirs[p] == true or p == "/" or free_map[p] ~= nil
        end,
        makeDir = function(p) dirs[norm(p)] = true end,
        getFreeSpace = function(p)
            p = norm(p)
            if free_map[p] then return free_map[p] end
            local best, best_val = "/", free_map["/"] or 0
            for k, v in pairs(free_map) do
                if p:sub(1, #k) == k and #k >= #best then
                    best, best_val = k, v
                end
            end
            return best_val
        end,
        list = function(p)
            p = norm(p)
            local pre = (p == "/") and "/" or (p .. "/")
            local seen, out = {}, {}
            for k, _ in pairs(files) do
                if k:sub(1, #pre) == pre then
                    local seg = k:sub(#pre + 1):match("^([^/]+)")
                    if seg and not seen[seg] then
                        seen[seg] = true
                        out[#out + 1] = seg
                    end
                end
            end
            return out
        end,
        delete = function(p) files[norm(p)] = nil end,
        open = function(p, mode)
            p = norm(p)
            if mode == "w" then
                local buf = ""
                return {
                    write = function(s) buf = buf .. tostring(s) end,
                    writeLine = function(s) buf = buf .. tostring(s) .. "\n" end,
                    flush = function() files[p] = buf end,
                    close = function() files[p] = buf end,
                }
            elseif mode == "r" and files[p] then
                local data = files[p]
                return { readAll = function() return data end, close = function() end }
            end
            return nil
        end,
        _files = files,
    }
end

local function create_fdr_fixture(bus, fdr_node, aircraft_n, base_ch)
    local tx_spy = 0
    local orig_tx = fdr_node.modem.transmit
    fdr_node.modem.transmit = function(...)
        tx_spy = tx_spy + 1
        return orig_tx(...)
    end

    local fs_api = make_vfs_fs({ ["/"] = 500000, ["/disk"] = 200000 })
    local disks = { drive_0 = { mount = "/disk", data = true } }
    local apis = {
        modem = fdr_node.modem,
        fs = fs_api,
        peripheral = {
            getNames = function() return { "top", "drive_0" } end,
            getType = function(n) return (n == "top") and "modem" or "drive" end,
            isPresent = function(n) return n == "top" or disks[n] ~= nil end,
            wrap = function(n) return (n == "top") and fdr_node.modem or {} end,
        },
        disk = {
            isPresent = function(n) return disks[n] ~= nil end,
            hasData = function(n) return disks[n] and disks[n].data == true end,
            getMountPath = function(n) return disks[n] and disks[n].mount or nil end,
        },
        epoch = function() return math.floor(bus.time * 1000) end,
    }

    local fdr_main = fdr_node:require("main")
    local st = fdr_main.init({
        schemaVersion = "1.1.0",
        aircraftIndexN = aircraft_n,
        baseChannel = base_ch,
        domainId = "*",
        autoStartOnBoot = true,
        recordMode = "STREAMING",
        tapOptions = { aero = true, trajectory = true, includeControlEvents = false },
        streaming = { flushIntervalFrames = 50, flushIntervalSec = 10.0 },
        storage = {
            preferExternalDisk = true,
            allowLocalFallback = true,
            localDumpDir = "/logs",
            diskSubDir = "fdr_logs",
            maxPartBytes = 8192,
            rollOverReserveBytes = 16384,
            minFreeSpaceBytes = 16384,
            autoPruneOldest = false,
            autoFlushOnEstop = true,
        },
    }, apis)

    return {
        main = fdr_main,
        state = st,
        fs = fs_api,
        get_tx_count = function() return tx_spy end,
    }
end

local function drain_pda(app, pda_node, now_ms)
    for _, msg in ipairs(pda_node.modem:drain()) do
        app:process_modem_message(msg.channel, msg.replyChannel, msg.payload, msg.distance, now_ms)
    end
end

local function drain_fdr(fdr_fix, fdr_node)
    for _, msg in ipairs(fdr_node.modem:drain()) do
        fdr_fix.main.handle_event(fdr_fix.state, "modem_message", "top", msg.channel, msg.replyChannel, msg.payload)
    end
end

describe("Scenario 11: Pocket PDA Multi-Node Remote C2, E_STOP+Dump & Hangar and FDR Control", function()
    it("Scenario 11a: ingests 38.0m telemetry, commands HOLD/RTB/LAND_NEAREST, and triggers [X] E_STOP + immediate FDR dump", function()
        local bus = virtual_bus.create_bus({ clock = 1000.0, default_distance = 38.0 })
        sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)

        local pda = node_sandbox.create_node(bus, "PDA", "src/0_infra/pocket_pda")
        local amm = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local tca = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
        local fdr = node_sandbox.create_node(bus, "FDR", "src/0_development/fdr")

        local pda_main = pda:require("main")
        local app = pda_main.create_app({
            defaults = {
                aircraftIndexN = 1,
                targetDomainId = "AIRCRAFT_01",
                hangarBayId = 1,
                fdrBoundIndexN = 1,
            },
        }, pda.modem)
        assert_true(pda.modem:isOpen(10000))
        assert_true(pda.modem:isOpen(10002))
        assert_true(pda.modem:isOpen(10003))
        assert_true(pda.modem:isOpen(10009))

        local fdr_fix = create_fdr_fixture(bus, fdr, 1, 10000)
        assert_eq(fdr_fix.state.mode, "LOGGING")
        assert_eq(fdr_fix.get_tx_count(), 0)

        -- VAS + TCA setup
        local vas_net = vas:require("network_manager")
        local vas_state = vas_net.init({ aircraftDomainId = "AIRCRAFT_01", baseChannel = 10000 })
        vas_state.wirelessModem = vas.modem
        local vas_sm = vas:require("state_machine")
        local vas_fsm = vas_sm.init({}, true)
        vas_fsm.currentState = "NORMAL"
        local vas_feeder = vas:require("telemetry_feeder")
        local feeder_st = vas_feeder.init({ telemetryDiag = true })

        local tca_daemon = tca:require("tca_daemon")
        local tca_inst = tca_daemon.init({
            groupId = "THR_MAIN_L",
            interactionMode = "REDSTONE",
            channels = { thrustActuation = 10010 },
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
        }, tca.modem)
        tca.modem:open(10010)

        -- Apply nominal positive thrust before E_STOP
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 1,
            controlState = "NORMAL",
            outputs = { THR_MAIN_L = 10 },
        })
        bus:step(0.05)
        for _, m in ipairs(tca.modem:drain()) do
            tca_inst:handle_thrust_cmd(m.payload)
        end
        drain_fdr(fdr_fix, fdr)
        assert_eq(tca_inst.adapterState.lastSignal, 10)

        -- AMM arbiter + facility beacons setup
        local amm_cfg = {
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            defaultAlt = 150.0,
            defaultSpeed = 18.0,
            arrivalRadius = 15.0,
        }
        local q = amm:require("waypoint_queue").new(amm_cfg)
        q:add(100, 100, 150, 18)
        local amm_net = amm:require("network_manager").new(amm_cfg)
        amm_net.modem = amm.modem
        amm.modem:open(10000)

        local fac_mod = amm:require("facility_client")
        local fac_st = fac_mod.init(amm_cfg)
        fac_mod.update_beacons(fac_st, {
            sectorId = "SECTOR_01",
            facilities = {
                { facilityId = "PAD_BUSY_01", facilityType = "LANDING_PAD", status = "OCCUPIED", dedicated = false, position = { x = 10, y = 65, z = 10 } },
                { facilityId = "PAD_FREE_02", facilityType = "LANDING_PAD", status = "FREE", dedicated = false, position = { x = 120, y = 65, z = 80 } },
                { facilityId = "PAD_FAR_03", facilityType = "LANDING_PAD", status = "FREE", dedicated = false, position = { x = 400, y = 65, z = 400 } },
            },
        }, math.floor(bus.time * 1000))

        local arbiter = amm:require("c2_arbiter").new(q, amm_net, amm_cfg)
        arbiter.fac = fac_st
        arbiter.latest_telem = { navigation = { currentPos = { x = 0, y = 120, z = 0 } } }

        -- 1. VAS (10002) & AMM (10003) telemetry ingestion at senderDistance = 38.0m -> STRONG
        vas_feeder.tick(feeder_st, vas_state, {
            attitude = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            rates = { p = 0.0, q = 0.0, r = 0.0 },
            dynamics = { altitudeY = 120.0, verticalSpeed = 0.5, velocity = { vx = 10.0, vy = 0.5, vz = 0.0 } },
            fuel = 0.85,
        }, { currentState = "NORMAL", activeSource = "FCP" }, nil, {
            sensorOk = true,
            sensorHealth = { attitude = true, altitude = true, velocity = true, fuel = true },
            satFlags = { axisSaturatedPos = {}, axisSaturatedNeg = {} },
            diag = { saturationFreeze = false },
        })
        amm_net:send_mfd_state({
            source = "AMM_INTEGRATED",
            fsmState = "CRUISE",
            flightMode = "AUTO_NAV",
            attitude = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            dynamics = { altitudeY = 120.0, verticalSpeed = 0.5, groundSpeed = 10.0 },
            fuel = 0.85,
            sensorOk = true,
            actuatorHealth = { tap = true, asa = true, allOk = true },
        }, arbiter, math.floor(bus.time * 1000))
        bus:step(0.05)

        local now_ms = math.floor(bus.time * 1000)
        drain_pda(app, pda, now_ms)
        drain_fdr(fdr_fix, fdr)

        assert_eq(app.hud.linkQuality.tier, "STRONG")
        assert_eq(app.hud.linkQuality.distanceStr, "38.0m")
        assert_true(app.hud.nodes.VAS.online)
        assert_true(app.hud.nodes.AMM.online)
        assert_eq(app.hud.fsmState, "CRUISE")
        assert_eq(app.hud.flightMode, "AUTO_NAV")
        assert_near(app.hud.altitudeY, 120.0, 1e-6)
        assert_true(fdr_fix.state.framesWritten >= 2)

        -- Confirm JSONL telemetry frame is still buffered before [X]
        local part_path = fdr_fix.state.stream.parts[1].filePath
        assert_nil(string.find(fdr_fix.fs._files[part_path] or "", "MSG_FLIGHT_TELEMETRY", 1, true))

        -- 2. Remote C2 commands on Base+0: HOLD -> RTB -> LAND_NEAREST
        assert_true(app:process_key(nil, "h", now_ms + 50))
        bus:step(0.05)
        for _, m in ipairs(amm.modem:drain()) do arbiter:handle_gcs_packet(m.payload, now_ms + 50) end
        assert_eq(arbiter.authority, "GCS_OVERRIDE")
        assert_eq(q.state, "SUSPENDED")
        assert_eq(arbiter.emergencyGoal.flightMode, "HOVER_HOLD")

        assert_true(app:process_key(nil, "r", now_ms + 100))
        bus:step(0.05)
        for _, m in ipairs(amm.modem:drain()) do arbiter:handle_gcs_packet(m.payload, now_ms + 100) end
        assert_eq(arbiter.emergencyGoal.flightMode, "FAILSAFE_RTH")

        assert_true(app:process_key(nil, "l", now_ms + 150))
        bus:step(0.05)
        for _, m in ipairs(amm.modem:drain()) do arbiter:handle_gcs_packet(m.payload, now_ms + 150) end
        assert_eq(arbiter.emergencyGoal.flightMode, "LANDING")
        assert_eq(arbiter.emergencyGoal.facilityId, "PAD_FREE_02")

        -- 3. Single-key [X] E_STOP on Base+9 -> VAS latches E_STOP, TCA cuts thrust to 0, FDR flushes immediately
        assert_true(app:process_key(nil, "x", now_ms + 200))
        bus:step(0.05)

        local estop_pkts = bus:find_packets({ type = "MSG_EMERGENCY_OVERRIDE", channel = 10009 })
        local dump_pkts = bus:find_packets({ type = "MSG_FDR_REMOTE_CMD", channel = 10009 })
        assert_eq(#estop_pkts, 1)
        assert_eq(estop_pkts[1].payload.payload.action, "E_STOP")
        assert_eq(estop_pkts[1].payload.payload.source, "POCKET_PDA")
        assert_eq(#dump_pkts, 1)
        assert_eq(dump_pkts[1].payload.payload.action, "DUMP_NOW")

        for _, m in ipairs(vas.modem:drain()) do
            if m.payload and m.payload.type == "MSG_EMERGENCY_OVERRIDE" then
                assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, nil, m.channel, m.replyChannel, m.payload))
            end
        end
        assert_eq(vas_fsm.currentState, "E_STOP")
        assert_eq(vas_fsm.activeSource, "EMERGENCY_DIRECT")

        local safe_out = vas_sm.apply_output_safety_rule(vas_fsm, { THR_MAIN_L = 10 }, false)
        assert_eq(safe_out.THR_MAIN_L, 0)
        vas_net.send_packet(vas_state, 10010, "MSG_THRUST_CMD", {
            watchdogSeq = 2,
            controlState = vas_fsm.currentState,
            outputs = safe_out,
        })
        bus:step(0.05)

        for _, m in ipairs(tca.modem:drain()) do
            tca_inst:handle_thrust_cmd(m.payload)
        end
        assert_eq(tca_inst.lastControlState, "E_STOP")
        assert_eq(tca_inst.adapterState.lastSignal or 0, 0)

        drain_fdr(fdr_fix, fdr)
        assert_true(fdr_fix.state.estopFlushed)
        assert_true(string.find(fdr_fix.fs._files[part_path] or "", "MSG_FLIGHT_TELEMETRY", 1, true) ~= nil)
        assert_true(string.find(fdr_fix.fs._files[part_path] or "", "MSG_EMERGENCY_OVERRIDE", 1, true) ~= nil)
        assert_true(string.find(fdr_fix.state.lastEventMsg or "", "FLUSHED", 1, true) ~= nil)
        assert_eq(fdr_fix.get_tx_count(), 0)

        fdr_fix.main.shutdown(fdr_fix.state, "E2E_DONE")
    end)

    it("Scenario 11b: rebinds FDR to N=2 with 0 tx, and runs remote Alignment Bay 1 session lifecycle for AIRCRAFT_02", function()
        local bus = virtual_bus.create_bus({ clock = 2000.0, default_distance = 20.0 })
        sdk.patch(os, "epoch", function() return math.floor(bus.time * 1000 + 0.5) end)

        local pda = node_sandbox.create_node(bus, "PDA", "src/0_infra/pocket_pda")
        local align = node_sandbox.create_node(bus, "ALIGN", "src/0_development/alignment")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local fdr = node_sandbox.create_node(bus, "FDR", "src/0_development/fdr")

        local pda_main = pda:require("main")
        local app = pda_main.create_app({
            defaults = {
                aircraftIndexN = 1,
                targetDomainId = "AIRCRAFT_01",
                hangarBayId = 1,
                fdrBoundIndexN = 1,
            },
        }, pda.modem)

        local fdr_fix = create_fdr_fixture(bus, fdr, 1, 10000)
        assert_true(fdr.modem:isOpen(10009))

        -- VAS configured for Aircraft N=2 (Base = 10040, AIRCRAFT_02)
        local vas_net = vas:require("network_manager")
        local vas_state = vas_net.init({ aircraftIndexN = 2, aircraftDomainId = "AIRCRAFT_02", baseChannel = 10040 })
        vas_state.wirelessModem = vas.modem
        local vas_fsm = vas:require("state_machine").init({}, true)
        local vas_feeder = vas:require("telemetry_feeder")
        local feeder_st = vas_feeder.init({ telemetryDiag = false })

        -- Alignment Bay 1 standing by on CH 101
        local align_main = align:require("main")
        local align_cfg = {
            station = { stationId = "HANGAR_BAY_01", bayId = 1, baseHangarChannel = 101 },
            safety = { tiltAbortDeg = 12.0, tiltWarnDeg = 8.0, watchdogTimeoutMs = 5000 },
        }
        align.modem:open(101)
        local align_master_inst = nil

        -- 1. Switch PDA to N=2 (Base = 10040)
        assert_true(app:process_key(nil, "]", 2000000))
        assert_eq(app.net.aircraftIndexN, 2)
        assert_eq(app.net.baseChannel, 10040)
        assert_eq(app.net.targetDomainId, "AIRCRAFT_02")
        assert_true(pda.modem:isOpen(10040))
        assert_true(pda.modem:isOpen(10049))
        assert_false(pda.modem:isOpen(10000))

        -- 2. Remote FDR BIND_AIRCRAFT to N=2 (10049) + N=2 telemetry + DUMP_NOW
        assert_true(app:process_key(nil, "3", 2000050))
        assert_true(app:process_key(nil, "b", 2000060))
        bus:step(0.05)

        drain_fdr(fdr_fix, fdr)
        vas.modem:drain() -- clear dual-target 10049 command on VAS inbox
        assert_eq(fdr_fix.state.tap.aircraftIndexN, 2)
        assert_eq(fdr_fix.state.tap.baseChannel, 10040)
        assert_true(fdr.modem:isOpen(10042))
        assert_true(fdr.modem:isOpen(10049))
        assert_false(fdr.modem:isOpen(10002))
        assert_false(fdr.modem:isOpen(10009))
        assert_eq(fdr_fix.get_tx_count(), 0)

        -- Emit N=2 telemetry and trigger remote DUMP_NOW
        vas_feeder.tick(feeder_st, vas_state, {
            attitude = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            rates = { p = 0.0, q = 0.0, r = 0.0 },
            dynamics = { altitudeY = 85.0, verticalSpeed = 0.0, velocity = { vx = 5.0, vy = 0.0, vz = 0.0 } },
            fuel = 0.90,
        }, { currentState = "NORMAL", activeSource = "FCP" }, nil, {
            sensorOk = true,
            sensorHealth = { attitude = true, altitude = true, velocity = true, fuel = true },
            actuatorHealth = { tap = true, asa = true, allOk = true },
        })
        bus:step(0.05)
        drain_pda(app, pda, math.floor(bus.time * 1000))
        drain_fdr(fdr_fix, fdr)
        assert_true(fdr_fix.state.framesWritten >= 1)
        assert_eq(fdr_fix.state.tap.lockedDomainId, "AIRCRAFT_02")

        local n2_part_path = fdr_fix.state.stream.parts[1].filePath
        assert_true(app:process_key(nil, "d", 2000150))
        bus:step(0.05)
        drain_fdr(fdr_fix, fdr)
        vas.modem:drain()
        assert_eq(fdr_fix.state.stream.baseChannel, 10040)
        assert_true(string.find(fdr_fix.fs._files[n2_part_path] or "", "10042", 1, true) ~= nil)
        assert_true(string.find(fdr_fix.fs._files[n2_part_path] or "", "MSG_FLIGHT_TELEMETRY", 1, true) ~= nil)
        assert_true(string.find(fdr_fix.state.lastEventMsg or "", "FLUSHED", 1, true) ~= nil)
        assert_eq(fdr_fix.get_tx_count(), 0)

        -- 3. Remote Alignment Bay 1 (101/102) BIND_SESSION for N=2 (AIRCRAFT_02, 10048)
        assert_true(app:process_key(nil, "2", 2000200))
        assert_true(app:process_key(nil, "b", 2000210))
        bus:step(0.05)

        for _, m in ipairs(align.modem:drain()) do
            align_master_inst = align_main.handle_modem_message(align_master_inst, m.channel, m.payload, align_cfg, align.modem, 2000220)
        end
        bus:step(0.05)

        -- VAS (10048) processes MSG_CALIBRATION_INIT and replies with MSG_CALIBRATION_INIT_ACK on 102
        for _, m in ipairs(vas.modem:drain()) do
            if m.channel == 10048 then
                assert_true(vas_net.dispatch(vas_state, vas_fsm, nil, nil, m.channel, m.replyChannel, m.payload))
            end
        end
        assert_eq(vas_fsm.currentState, "CALIBRATION")
        bus:step(0.05)

        -- PDA receives MSG_ALIGN_REMOTE_STATUS (SESSION_STARTED) and MSG_CALIBRATION_INIT_ACK (READY)
        drain_pda(app, pda, math.floor(bus.time * 1000))
        assert_eq(app.link.alignment.status, "SESSION_STARTED")
        assert_eq(app.link.alignment.aircraftIndexN, 2)
        assert_eq(app.link.alignment.craftBaseChannel, 10040)
        assert_not_nil(app.link.alignment.lastInitAck)
        assert_eq(app.link.alignment.initStatus, "READY")
        assert_eq(app.link.alignment.lastInitAck.aircraftDomainId, "AIRCRAFT_02")
        assert_true(app.hud.nodes.ALN.online)

        -- 4. Remote lifecycle control: PAUSE_SESSION -> RETRY_STEP -> RELEASE_SESSION
        -- (clear ALIGN inbox from MSG_CALIBRATION_INIT_ACK to stay in remote lifecycle control)
        align.modem:drain()

        assert_true(app:process_key(nil, "p", 2000300))
        bus:step(0.05)
        for _, m in ipairs(align.modem:drain()) do
            align_master_inst = align_main.handle_modem_message(align_master_inst, m.channel, m.payload, align_cfg, align.modem, 2000310)
        end
        bus:step(0.05)
        drain_pda(app, pda, math.floor(bus.time * 1000))
        assert_eq(app.link.alignment.status, "PAUSED")
        assert_eq(app.link.alignment.fsmState, "ANOMALY_PAUSE")

        assert_true(app:process_key(nil, "t", 2000350))
        bus:step(0.05)
        for _, m in ipairs(align.modem:drain()) do
            align_master_inst = align_main.handle_modem_message(align_master_inst, m.channel, m.payload, align_cfg, align.modem, 2000360)
        end
        bus:step(0.05)
        drain_pda(app, pda, math.floor(bus.time * 1000))
        assert_eq(app.link.alignment.status, "RETRYING")
        assert_eq(app.link.alignment.fsmState, "INTEGRATING")

        assert_true(app:process_key(nil, "k", 2000400))
        bus:step(0.05)
        for _, m in ipairs(align.modem:drain()) do
            align_master_inst = align_main.handle_modem_message(align_master_inst, m.channel, m.payload, align_cfg, align.modem, 2000410)
        end
        bus:step(0.05)
        for _, m in ipairs(vas.modem:drain()) do
            vas_net.dispatch(vas_state, vas_fsm, nil, nil, m.channel, m.replyChannel, m.payload)
        end
        bus:step(0.05)

        drain_pda(app, pda, math.floor(bus.time * 1000))
        assert_eq(app.link.alignment.fsmState, "STANDBY")
        assert_eq(app.link.alignment.status, "CLOSED")
        assert_not_nil(app.link.alignment.lastCloseAck)
        assert_false(vas.modem:isOpen(101))
        assert_false(vas.modem:isOpen(104))

        fdr_fix.main.shutdown(fdr_fix.state, "E2E_DONE")
    end)
end)
