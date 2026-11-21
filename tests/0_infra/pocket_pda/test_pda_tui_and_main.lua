-- tests/0_infra/pocket_pda/test_pda_tui_and_main.lua
local pocket_tui = require("pocket_tui")
local main = require("main")

local function make_cfg()
    return {
        schemaVersion = "1.0.0",
        system = {
            id = "PDA_01",
            domainId = "POCKET_PDA_01",
            modemSide = "back",
            loopFrequencyHz = 20,
            uiRefreshRateHz = 5,
        },
        defaults = {
            aircraftIndexN = 1,
            targetDomainId = "AIRCRAFT_01",
            hangarBayId = 1,
            fdrBoundIndexN = 1,
        },
        channels = {
            gcsBootstrapChannel = 50000,
            missionAckChannel = 50004,
            aircraftBaseMin = 10000,
            aircraftBandwidth = 40,
            maxAircraft = 1000,
            hangarBaseMin = 101,
            hangarBandwidth = 10,
            maxHangarBays = 10,
        },
        linkQuality = {
            telemetryTimeoutMs = 2000,
            nodeStaleMs = 3000,
            strongMaxDistM = 80.0,
            goodMaxDistM = 200.0,
        },
        ui = {
            screenWidth = 26,
            screenHeight = 20,
        },
    }
end

local function assert_valid_buffer(buf)
    assert_not_nil(buf)
    assert_eq(#buf.text, 20)
    assert_eq(#buf.fg, 20)
    assert_eq(#buf.bg, 20)
    for y = 1, 20 do
        assert_eq(#buf.text[y], 26, "text width mismatch at row " .. y)
        assert_eq(#buf.fg[y], 26, "fg width mismatch at row " .. y)
        assert_eq(#buf.bg[y], 26, "bg width mismatch at row " .. y)
        assert_true(string.match(buf.fg[y], "^[0-9a-f]+$") ~= nil, "invalid fg hex at row " .. y)
        assert_true(string.match(buf.bg[y], "^[0-9a-f]+$") ~= nil, "invalid bg hex at row " .. y)
    end
end

local function buffer_contains(buf, substr)
    for y = 1, 20 do
        if string.find(buf.text[y], substr, 1, true) then
            return true
        end
    end
    return false
end

local function make_hud_sample()
    return {
        fsmState = "CRUISE", flightMode = "AUTO_NAV", activeSource = "AMM_INT",
        altitudeY = 125.4, verticalSpeed = 0.2, groundSpeed = 18.5,
        pitch = 2.1, roll = -4.5, yaw = 92.4, fuel = 0.75,
        sensorOk = true, actuatorOk = true,
        linkQuality = { tier = "STRONG", rssiPct = 90, distanceStr = "38.0m" },
        lastPbitReport = { overallStatus = "PASS" },
        discoveredOrder = { 1, 2, 3 },
        nodes = {
            AMM = { online = true, lastSeenMs = 4900 },
            VAS = { online = true, lastSeenMs = 4900 },
            GCS = { online = true, lastSeenMs = 4900 },
            ALN = { online = false, lastSeenMs = 0 },
            FDR = { online = true, lastSeenMs = 4900 },
        },
    }
end

local function make_sample_vm(active_tab, overrides)
    local vm = {
        activeTab = active_tab or "HUD",
        statusMsg = "PBIT_OK",
        nowMs = 5000,
        net = {
            aircraftIndexN = 1, baseChannel = 10000, targetDomainId = "AIRCRAFT_01",
            hangarBayId = 2, hangarBaseChannel = 111,
        },
        hud = make_hud_sample(),
        link = {
            alignment = {
                bayId = 2, stationId = "HANGAR_BAY_02", aircraftIndexN = 1,
                targetCraftDomain = "AIRCRAFT_01", baseHangarChannel = 111,
                fsmState = "SYNC_APPROVAL", status = "SESSION_STARTED",
                activeThruster = "THR_MAIN_L", controllabilityStatus = "FULL_6DOF_PASS",
                confidenceR2 = 0.992, reason = "READY_FOR_SYNC", lastCmd = "START_PULSE",
            },
            fdr = {
                boundIndexN = 3, boundBaseChannel = 10080, boundDomainId = "AIRCRAFT_03",
                mode = "LOGGING", recordMode = "STREAMING", lastCmd = "DUMP_NOW",
            },
        },
    }
    if overrides then
        for k, v in pairs(overrides) do vm[k] = v end
    end
    return vm
end

describe("Pocket PDA 26x20 3-Tab TUI renderer", function()
    it("creates 26x20 buffers, clamps/pads format_line, handles nil view_model, and flushes 20 blit rows", function()
        assert_eq(pocket_tui.SCREEN_W, 26)
        assert_eq(pocket_tui.SCREEN_H, 20)

        local long_str = pocket_tui.format_line("ABCDEFGHIJKLMNOPQRSTUVWXYZ_EXTRA", 26)
        assert_eq(#long_str, 26)
        assert_eq(long_str, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

        local short_str = pocket_tui.format_line("HI", 26)
        assert_eq(#short_str, 26)
        assert_eq(string.sub(short_str, 1, 2), "HI")

        local nil_str = pocket_tui.format_line(nil, 26)
        assert_eq(#nil_str, 26)

        local buf = pocket_tui.create_buffer()
        assert_valid_buffer(buf)

        -- Cold-start nil view_model must still render valid 26x20 buffer
        pocket_tui.render_screen(buf, nil)
        assert_valid_buffer(buf)

        -- All 3 tabs render exact 26x20 lines and flush cleanly to 26x20 terminal
        for _, tab in ipairs({ "HUD", "ALIGN", "FDR" }) do
            local vm = make_sample_vm(tab)
            pocket_tui.render_screen(buf, vm)
            assert_valid_buffer(buf)

            local calls = 0
            local cursor_ys = {}
            local term_mock = mock.term(26, 20)
            local orig_set = term_mock.setCursorPos
            local orig_blit = term_mock.blit
            term_mock.setCursorPos = function(x, y)
                assert_eq(x, 1)
                cursor_ys[#cursor_ys + 1] = y
                orig_set(x, y)
            end
            term_mock.blit = function(t, f, b)
                calls = calls + 1
                assert_eq(#t, 26)
                assert_eq(#f, 26)
                assert_eq(#b, 26)
                orig_blit(t, f, b)
            end

            assert_true(pocket_tui.flush_buffer(buf, term_mock))
            assert_eq(calls, 20)
            assert_eq(#cursor_ys, 20)
        end

        -- Verify ALIGN and FDR body fields
        pocket_tui.render_screen(buf, make_sample_vm("ALIGN"))
        assert_true(buffer_contains(buf, "BAY:02"))
        assert_true(buffer_contains(buf, "CH:111"))
        assert_true(buffer_contains(buf, "SYNC_APPROVAL"))
        assert_true(buffer_contains(buf, "THR_MAIN_L"))
        assert_true(buffer_contains(buf, "0.992"))
        assert_true(buffer_contains(buf, "FULL_6DOF_PASS"))

        pocket_tui.render_screen(buf, make_sample_vm("FDR"))
        assert_true(buffer_contains(buf, "PDA N:001"))
        assert_true(buffer_contains(buf, "FDR N:003"))
        assert_true(buffer_contains(buf, "LOGGING"))
        assert_true(buffer_contains(buf, "0 tx"))
        assert_true(buffer_contains(buf, "DUMP_NOW"))

        assert_false(pocket_tui.flush_buffer(buf, {}))
    end)

    it("renders HUD tab with craft N:001, 10000, kinematics, Euler P/R/Y, fuel bar, link tiers, and 5 node flags", function()
        local buf = pocket_tui.create_buffer(26, 20)
        local vm = make_sample_vm("HUD")
        pocket_tui.render_screen(buf, vm)
        assert_valid_buffer(buf)

        assert_true(buffer_contains(buf, "N:001"))
        assert_true(buffer_contains(buf, "10000"))
        assert_true(buffer_contains(buf, "125.4m"))
        assert_true(buffer_contains(buf, "+0.2m/s"))
        assert_true(buffer_contains(buf, "18.5m/s"))
        assert_true(buffer_contains(buf, "P: +2.1"))
        assert_true(buffer_contains(buf, "R: -4.5"))
        assert_true(buffer_contains(buf, "Y:092.4"))
        assert_true(buffer_contains(buf, "FUEL:["))
        assert_true(buffer_contains(buf, "STRONG"))
        assert_true(buffer_contains(buf, "38.0m"))
        assert_true(buffer_contains(buf, "AMM"))
        assert_true(buffer_contains(buf, "VAS"))
        assert_true(buffer_contains(buf, "GCS"))
        assert_true(buffer_contains(buf, "ALN"))
        assert_true(buffer_contains(buf, "FDR"))

        -- ENDER link quality display
        vm.hud.linkQuality = { tier = "STRONG", rssiPct = 100, distanceStr = "ENDER" }
        pocket_tui.render_screen(buf, vm)
        assert_true(buffer_contains(buf, "STRONG"))
        assert_true(buffer_contains(buf, "ENDER"))

        -- LOST link quality display
        vm.hud.linkQuality = { tier = "LOST", rssiPct = 0, distanceStr = "---" }
        pocket_tui.render_screen(buf, vm)
        assert_true(buffer_contains(buf, "LOST"))
        assert_true(buffer_contains(buf, "---"))
    end)
end)

describe("Pocket PDA main app config, keybindings, telemetry ingestion, and shutdown", function()
    it("loads nested pda_config.json schema via fs_api and falls back safely when absent", function()
        local sample_json = [[{
            "schemaVersion": "1.0.0",
            "system": { "id": "PDA_99", "domainId": "POCKET_PDA_99", "modemSide": "back", "loopFrequencyHz": 20, "uiRefreshRateHz": 10 },
            "defaults": { "aircraftIndexN": 2, "targetDomainId": "AIRCRAFT_02", "hangarBayId": 3, "fdrBoundIndexN": 2 },
            "channels": { "gcsBootstrapChannel": 50000, "missionAckChannel": 50004, "aircraftBaseMin": 10000, "aircraftBandwidth": 40, "maxAircraft": 1000, "hangarBaseMin": 101, "hangarBandwidth": 10, "maxHangarBays": 10 },
            "linkQuality": { "telemetryTimeoutMs": 2000, "nodeStaleMs": 3000, "strongMaxDistM": 80.0, "goodMaxDistM": 200.0 },
            "ui": { "screenWidth": 26, "screenHeight": 20 }
        }]]
        local mock_fs = {
            exists = function(p) return p == "config/pda_config.json" end,
            open = function()
                return { readAll = function() return sample_json end, close = function() end }
            end,
        }
        local loaded = main.load_config("config/pda_config.json", mock_fs)
        assert_eq(loaded.system.id, "PDA_99")
        assert_eq(loaded.system.uiRefreshRateHz, 10)
        assert_eq(loaded.defaults.aircraftIndexN, 2)
        assert_eq(loaded.defaults.hangarBayId, 3)
        assert_eq(loaded.ui.screenWidth, 26)
        assert_eq(loaded.ui.screenHeight, 20)

        local fallback = main.load_config("nonexistent.json", mock_fs)
        assert_eq(fallback.system.id, "PDA_01")
        assert_eq(fallback.system.uiRefreshRateHz, 5)
        assert_eq(fallback.ui.screenWidth, 26)
    end)

    it("dispatches global, HUD, ALIGN, and FDR hotkeys, ingests modem packets, renders, and shuts down on Q", function()
        local modem = mock.modem({ wireless = true })
        local app = main.create_app(make_cfg(), modem)
        assert_true(app.running)
        assert_eq(app.activeTab, "HUD")
        assert_true(modem.isOpen(10000))
        assert_true(modem.isOpen(10009))
        assert_true(modem.isOpen(102))
        assert_true(modem.isOpen(50000))

        -- 1. Global [X] E_STOP + DUMP_NOW
        assert_true(app:process_key(nil, "x", 1000))
        assert_eq(#modem._transmitted, 2)
        assert_eq(modem._transmitted[1].tx, 10009)
        assert_eq(modem._transmitted[1].pkt.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(modem._transmitted[1].pkt.payload.action, "E_STOP")
        assert_eq(modem._transmitted[2].tx, 10009)
        assert_eq(modem._transmitted[2].pkt.type, "MSG_FDR_REMOTE_CMD")
        assert_eq(modem._transmitted[2].pkt.payload.action, "DUMP_NOW")

        -- Global [H], [R], [L]
        modem._transmitted = {}
        assert_true(app:process_key(nil, "h", 1100))
        assert_eq(modem._transmitted[#modem._transmitted].tx, 10000)
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.command, "HOLD")

        assert_true(app:process_key(nil, "r", 1110))
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.command, "RTH")

        assert_true(app:process_key(nil, "l", 1120))
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.command, "LAND_NEAREST")

        -- Tab 1 HUD hotkeys: [A]=ARM, [T]=TAKEOFF, [P]=PBIT
        modem._transmitted = {}
        assert_true(app:process_key(nil, "a", 1200))
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.command, "ARM")
        assert_true(app:process_key(nil, "t", 1210))
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.command, "TAKEOFF")
        assert_true(app:process_key(nil, "p", 1220))
        assert_eq(modem._transmitted[#modem._transmitted].tx, 10008)
        assert_eq(modem._transmitted[#modem._transmitted].pkt.type, "MSG_PBIT_REQ")

        -- Aircraft stepping with ] / [ / Right(205) / Left(203)
        assert_true(app:process_key(nil, "]", 1300))
        assert_eq(app.net.aircraftIndexN, 2)
        assert_false(modem.isOpen(10000))
        assert_true(modem.isOpen(10040))

        assert_true(app:process_key(205, nil, 1310))
        assert_eq(app.net.aircraftIndexN, 3)
        assert_true(modem.isOpen(10080))

        assert_true(app:process_key(nil, "[", 1320))
        assert_eq(app.net.aircraftIndexN, 2)
        assert_true(app:process_key(203, nil, 1330))
        assert_eq(app.net.aircraftIndexN, 1)
        assert_true(app:process_key(nil, "[", 1340))
        assert_eq(app.net.aircraftIndexN, 1) -- clamped at 1

        -- Fleet discovery via CH 50000 + Tab cycling
        assert_true(app:process_modem_message(50000, 50000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 1, type = "MSG_BLOCK_ASSIGN", time = 1400,
            payload = { status = "ASSIGNED", blockId = 1, baseChannel = 10000, domainId = "FALCON_01" },
        }, 50.0, 1400))
        assert_true(app:process_modem_message(50000, 50000, {
            ver = "1.9.5", domainId = "GCS_01", seq = 2, type = "MSG_BLOCK_ASSIGN", time = 1410,
            payload = { status = "ASSIGNED", blockId = 4, baseChannel = 10120, domainId = "FALCON_04" },
        }, 50.0, 1410))
        assert_true(app:process_key(15, nil, 1420))
        assert_eq(app.net.aircraftIndexN, 4)
        assert_eq(app.net.targetDomainId, "FALCON_04")
        assert_true(modem.isOpen(10120))
        assert_true(app:process_key(nil, "\t", 1430))
        assert_eq(app.net.aircraftIndexN, 1)
        assert_eq(app.net.targetDomainId, "FALCON_01")

        -- Inbound telemetry & MFD updates
        assert_true(app:process_modem_message(10002, 10002, {
            ver = "1.9.5", domainId = "FALCON_01", seq = 3, type = "MSG_FLIGHT_TELEMETRY", time = 1500,
            payload = {
                attitude = { pitch = 3.0, roll = -1.5, yaw = 180.0 },
                dynamics = { altitudeY = 88.5, verticalSpeed = 1.2, groundSpeed = 14.0 },
                fuel = 0.65, controlState = "NORMAL", activeSource = "FCP",
                sensorOk = true, actuatorHealth = { allOk = true },
            },
        }, 35.0, 1500))
        assert_near(app.hud.altitudeY, 88.5, 1e-6)
        assert_true(app:process_modem_message(10003, 10003, {
            ver = "1.9.5", domainId = "FALCON_01", seq = 4, type = "MSG_MFD_STATE", time = 1520,
            payload = {
                source = "AMM_INTEGRATED", fsmState = "CRUISE", flightMode = "AUTO_NAV",
                dynamics = { altitudeY = 90.0, verticalSpeed = 0.0, groundSpeed = 16.0 },
            },
        }, 35.0, 1520))
        assert_eq(app.hud.fsmState, "CRUISE")
        assert_true(app.hud.nodes.AMM.online)

        -- Tab 2 ALIGN switching + bay bounds + all 7 actions + status ingest
        assert_true(app:process_key(nil, "2", 1600))
        assert_eq(app.activeTab, "ALIGN")
        assert_true(app:process_key(nil, "=", 1610))
        assert_eq(app.net.hangarBayId, 2)
        assert_eq(app.link.alignment.bayId, 2)
        assert_false(modem.isOpen(102))
        assert_true(modem.isOpen(112))
        assert_true(app:process_key(nil, "+", 1620))
        assert_eq(app.net.hangarBayId, 3)
        assert_true(app:process_key(nil, "-", 1630))
        assert_eq(app.net.hangarBayId, 2)

        modem._transmitted = {}
        local align_cases = {
            { key = "b", act = "BIND_SESSION" },
            { key = "g", act = "START_PULSE" },
            { key = "p", act = "PAUSE_SESSION" },
            { key = "t", act = "RETRY_STEP" },
            { key = "y", act = "APPROVE_SYNC" },
            { key = "a", act = "ABORT_SESSION" },
            { key = "k", act = "RELEASE_SESSION" },
        }
        for idx, c in ipairs(align_cases) do
            assert_true(app:process_key(nil, c.key, 1700 + idx))
            local rec = modem._transmitted[#modem._transmitted]
            assert_eq(rec.tx, 111)
            assert_eq(rec.pkt.type, "MSG_ALIGN_REMOTE_CMD")
            assert_eq(rec.pkt.payload.action, c.act)
        end

        assert_true(app:process_modem_message(112, 112, {
            ver = "1.9.5", domainId = "FALCON_01", seq = 5, type = "MSG_ALIGN_REMOTE_STATUS", time = 1800,
            payload = {
                stationId = "HANGAR_BAY_02", bayId = 2, aircraftIndexN = 1,
                fsmState = "TUNING", status = "PULSE_STARTED",
                activeThruster = "THR_MAIN_R", confidenceR2 = 0.985,
            },
        }, 20.0, 1800))
        assert_eq(app.link.alignment.fsmState, "TUNING")
        assert_true(app.hud.nodes.ALN.online)

        -- Tab 3 FDR switching + all 6 actions + M toggle
        assert_true(app:process_key(nil, "3", 1900))
        assert_eq(app.activeTab, "FDR")
        modem._transmitted = {}

        assert_true(app:process_key(nil, "b", 1910))
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.action, "BIND_AIRCRAFT")
        assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.targetAircraftIndexN, 1)

        -- M toggles LOGGING -> STANDBY (autoStartLogging = false) -> LOGGING (autoStartLogging = true)
        assert_true(app:process_key(nil, "m", 1920))
        local tx_standby = modem._transmitted[#modem._transmitted]
        assert_eq(tx_standby.pkt.payload.action, "SET_MODE")
        assert_eq(tx_standby.pkt.payload.recordMode, "STANDBY")
        assert_false(tx_standby.pkt.payload.autoStartLogging)
        assert_eq(app.link.fdr.mode, "STANDBY")

        assert_true(app:process_key(nil, "m", 1930))
        local tx_log = modem._transmitted[#modem._transmitted]
        assert_eq(tx_log.pkt.payload.action, "SET_MODE")
        assert_eq(tx_log.pkt.payload.recordMode, "LOGGING")
        assert_true(tx_log.pkt.payload.autoStartLogging)
        assert_eq(app.link.fdr.mode, "LOGGING")

        for idx, c in ipairs({
            { key = "d", act = "DUMP_NOW" },
            { key = "u", act = "EXPORT_NOW" },
            { key = "s", act = "ROLLOVER_NOW" },
            { key = "c", act = "CLEAR_BUFFER" },
        }) do
            assert_true(app:process_key(nil, c.key, 1940 + idx))
            assert_eq(modem._transmitted[#modem._transmitted].pkt.payload.action, c.act)
        end

        -- Global [X] still emits E_STOP + DUMP_NOW even on Tab 3
        modem._transmitted = {}
        assert_true(app:process_key(nil, "x", 1960))
        assert_eq(#modem._transmitted, 2)
        assert_eq(modem._transmitted[1].pkt.type, "MSG_EMERGENCY_OVERRIDE")
        assert_eq(modem._transmitted[2].pkt.type, "MSG_FDR_REMOTE_CMD")

        -- Bounds & unknown keys
        assert_false(app:process_key(nil, "z", 1965))
        local bad_sel, bad_err = app:select_aircraft(1001)
        assert_false(bad_sel)
        assert_eq(bad_err, "ERR_AIRCRAFT_INDEX_RANGE")
        assert_true(app:select_aircraft(1000))
        assert_true(app:process_key(nil, "]", 1966))
        assert_eq(app.net.aircraftIndexN, 1000)

        assert_true(app:process_key(nil, "2", 1967))
        for _ = 1, 10 do assert_true(app:process_key(nil, "=", 1968)) end
        assert_eq(app.net.hangarBayId, 10)
        for _ = 1, 12 do assert_true(app:process_key(nil, "-", 1969)) end
        assert_eq(app.net.hangarBayId, 1)
        assert_true(app:process_key(nil, "3", 1969))

        -- Render onto mock 26x20 terminal
        local scr = mock.term(26, 20)
        assert_true(app:render(scr, 1970))
        assert_true(scr._contains("FDR"))
        assert_true(scr._contains("0 tx"))

        -- Clean shutdown on [Q]
        assert_true(app:process_key(nil, "q", 2000))
        assert_false(app.running)
        assert_false(modem.isOpen(10000))
        assert_false(modem.isOpen(112))
        assert_false(modem.isOpen(50000))
        assert_false(modem.isOpen(50004))
    end)
end)
