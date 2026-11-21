-- tests/0_infra/pocket_pda/test_pda_network_and_hud.lua
local pda_network = require("pda_network")
local telemetry_hud_state = require("telemetry_hud_state")

local function make_cfg(overrides)
    local cfg = {
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
    if overrides then
        for k, v in pairs(overrides) do
            cfg[k] = v
        end
    end
    return cfg
end

local function euler_to_quat(pitch_deg, roll_deg, yaw_deg)
    local p = math.rad(pitch_deg) * 0.5
    local r = math.rad(roll_deg) * 0.5
    local y = math.rad(yaw_deg) * 0.5
    local cp, sp = math.cos(p), math.sin(p)
    local cr, sr = math.cos(r), math.sin(r)
    local cy, sy = math.cos(y), math.sin(y)
    return {
        w = cr * cp * cy + sr * sp * sy,
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy,
    }
end

describe("Pocket PDA network router & channel management", function()
    it("computes craft and hangar base channels and rejects out-of-range inputs", function()
        local b1, e1 = pda_network.compute_craft_base(1)
        assert_eq(b1, 10000)
        assert_nil(e1)

        local b2 = pda_network.compute_craft_base(2)
        assert_eq(b2, 10040)

        local b1000 = pda_network.compute_craft_base(1000)
        assert_eq(b1000, 49960)

        local b0, err0 = pda_network.compute_craft_base(0)
        assert_nil(b0)
        assert_eq(err0, "ERR_AIRCRAFT_INDEX_RANGE")

        local b1001, err1001 = pda_network.compute_craft_base(1001)
        assert_nil(b1001)
        assert_eq(err1001, "ERR_AIRCRAFT_INDEX_RANGE")

        local bfrac, errfrac = pda_network.compute_craft_base(1.5)
        assert_nil(bfrac)
        assert_eq(errfrac, "ERR_AIRCRAFT_INDEX_RANGE")

        local h1, he1 = pda_network.compute_hangar_base(1)
        assert_eq(h1, 101)
        assert_nil(he1)

        assert_eq(pda_network.compute_hangar_base(10), 191)

        local h0, herr0 = pda_network.compute_hangar_base(0)
        assert_nil(h0)
        assert_eq(herr0, "ERR_HANGAR_BAY_RANGE")

        local h11, herr11 = pda_network.compute_hangar_base(11)
        assert_nil(h11)
        assert_eq(herr11, "ERR_HANGAR_BAY_RANGE")

        assert_eq(pda_network.default_domain_for_index(1), "AIRCRAFT_01")
        assert_eq(pda_network.default_domain_for_index(12), "AIRCRAFT_12")
    end)

    it("skips non-modem back monitor, opens core channels, and rebinds aircraft and hangar channels cleanly", function()
        local mon_back = mock.term(26, 20)
        local wired_bottom = mock.modem({ wireless = false })
        local wireless_top = mock.modem({ wireless = true })
        mock.peripheral_registry({
            back = { type = "monitor", dev = mon_back },
            bottom = { type = "modem", dev = wired_bottom },
            top = { type = "modem", dev = wireless_top },
        })

        local ctx = pda_network.init(make_cfg())
        assert_not_nil(ctx)
        assert_eq(ctx.modem, wireless_top)
        assert_eq(ctx.baseChannel, 10000)
        assert_eq(ctx.hangarBaseChannel, 101)

        local ok_open, err_open = pda_network.open_channels(ctx)
        assert_true(ok_open)
        assert_nil(err_open)

        local expected_open = { 102, 10000, 10002, 10003, 10008, 10009, 50000, 50004 }
        for _, ch in ipairs(expected_open) do
            assert_true(wireless_top.isOpen(ch), "expected channel open: " .. tostring(ch))
        end

        local ok_rebind, err_rebind = pda_network.rebind_aircraft(ctx, 3)
        assert_true(ok_rebind)
        assert_nil(err_rebind)
        assert_eq(ctx.aircraftIndexN, 3)
        assert_eq(ctx.baseChannel, 10080)
        assert_eq(ctx.targetDomainId, "AIRCRAFT_03")
        assert_true(ctx.autoDomain)

        for _, off in ipairs({ 0, 2, 3, 8, 9 }) do
            assert_false(wireless_top.isOpen(10000 + off), "old craft channel should be closed")
            assert_true(wireless_top.isOpen(10080 + off), "new craft channel should be open")
        end
        assert_true(wireless_top.isOpen(102))
        assert_true(wireless_top.isOpen(50000))
        assert_true(wireless_top.isOpen(50004))

        local ok_bay, err_bay = pda_network.rebind_hangar_bay(ctx, 2)
        assert_true(ok_bay)
        assert_nil(err_bay)
        assert_eq(ctx.hangarBayId, 2)
        assert_eq(ctx.hangarBaseChannel, 111)
        assert_false(wireless_top.isOpen(102))
        assert_true(wireless_top.isOpen(112))

        local bad_ok, bad_err = pda_network.rebind_aircraft(ctx, 1001)
        assert_false(bad_ok)
        assert_eq(bad_err, "ERR_AIRCRAFT_INDEX_RANGE")
        assert_eq(ctx.aircraftIndexN, 3)

        assert_true(pda_network.close_channels(ctx))
        assert_false(wireless_top.isOpen(10080))
        assert_false(wireless_top.isOpen(112))
        assert_false(wireless_top.isOpen(50000))

        local no_modem_ok, no_modem_err = pda_network.open_channels({ modem = nil })
        assert_false(no_modem_ok)
        assert_eq(no_modem_err, "ERR_NO_MODEM")
    end)

    it("transmits v1.9.5 envelopes to aircraft, hangar, and raw channels and parses envelopes", function()
        local modem = mock.modem({ wireless = true })
        local ctx = pda_network.init(make_cfg(), modem)

        local ok1, pkt1 = pda_network.transmit_to_aircraft(ctx, 0, 0, "MSG_OPERATOR_CMD", {
            authority = "GCS_OVERRIDE",
            command = "HOLD",
            params = { source = "POCKET_PDA" },
        }, 1200)
        assert_true(ok1)
        assert_eq(pkt1.ver, "1.9.5")
        assert_eq(pkt1.domainId, "AIRCRAFT_01")
        assert_eq(pkt1.time, 1200)
        assert_eq(#modem._transmitted, 1)
        assert_eq(modem._transmitted[1].tx, 10000)
        assert_eq(modem._transmitted[1].rx, 10000)

        local ok2, pkt2 = pda_network.transmit_to_hangar(ctx, 0, 1, "MSG_ALIGN_REMOTE_CMD", {
            action = "BIND_SESSION",
            stationId = "HANGAR_BAY_01",
            bayId = 1,
            aircraftIndexN = 1,
        }, 1300)
        assert_true(ok2)
        assert_eq(pkt2.type, "MSG_ALIGN_REMOTE_CMD")
        assert_eq(modem._transmitted[2].tx, 101)
        assert_eq(modem._transmitted[2].rx, 102)

        local ok3, pkt3 = pda_network.transmit_raw_channel(ctx, 10049, 10049, "MSG_FDR_REMOTE_CMD", {
            action = "DUMP_NOW",
            targetAircraftIndexN = 2,
            source = "POCKET_PDA",
        }, "AIRCRAFT_02", 1400)
        assert_true(ok3)
        assert_eq(pkt3.domainId, "AIRCRAFT_02")
        assert_eq(modem._transmitted[3].tx, 10049)

        local parsed, perr = pda_network.parse_envelope(pkt1)
        assert_not_nil(parsed)
        assert_nil(perr)

        local bad1 = pda_network.parse_envelope({ ver = "1.0.0", type = "X", payload = {} })
        assert_nil(bad1)
        local bad2 = pda_network.parse_envelope("invalid")
        assert_nil(bad2)
    end)
end)

describe("Pocket PDA telemetry HUD state & link quality classifier", function()
    it("classifies STRONG, GOOD, WEAK, ENDER, and LOST link quality tiers", function()
        local cfg = make_cfg()

        local strong = telemetry_hud_state.classify_link_quality(30.0, 100, cfg)
        assert_eq(strong.tier, "STRONG")
        assert_eq(strong.distanceStr, "30.0m")
        assert_true(strong.rssiPct >= 75 and strong.rssiPct <= 100)

        local good = telemetry_hud_state.classify_link_quality(120.0, 200, cfg)
        assert_eq(good.tier, "GOOD")
        assert_eq(good.distanceStr, "120.0m")
        assert_true(good.rssiPct >= 40 and good.rssiPct <= 74)

        local weak = telemetry_hud_state.classify_link_quality(300.0, 200, cfg)
        assert_eq(weak.tier, "WEAK")
        assert_eq(weak.distanceStr, "300.0m")
        assert_true(weak.rssiPct >= 10 and weak.rssiPct <= 39)

        local ender = telemetry_hud_state.classify_link_quality(nil, 100, cfg)
        assert_eq(ender.tier, "STRONG")
        assert_eq(ender.distanceStr, "ENDER")
        assert_eq(ender.rssiPct, 100)

        local lost_timeout = telemetry_hud_state.classify_link_quality(30.0, 3000, cfg)
        assert_eq(lost_timeout.tier, "LOST")
        assert_eq(lost_timeout.distanceStr, "---")
        assert_eq(lost_timeout.rssiPct, 0)

        local lost_nil_age = telemetry_hud_state.classify_link_quality(30.0, nil, cfg)
        assert_eq(lost_nil_age.tier, "LOST")
        assert_eq(lost_nil_age.rssiPct, 0)
    end)

    it("ingests telemetry, MFD, block assign, PBIT, emergency alert, and ages node timeouts", function()
        local cfg = make_cfg({
            defaults = {
                aircraftIndexN = 1,
                targetDomainId = "*",
                hangarBayId = 1,
                fdrBoundIndexN = 1,
            },
        })
        local modem = mock.modem({ wireless = true })
        local net_ctx = pda_network.init(cfg, modem)
        local hud = telemetry_hud_state.init(cfg)
        assert_true(net_ctx.autoDomain)

        local q = euler_to_quat(12.0, -6.0, 135.0)
        local telem_pkt = {
            ver = "1.9.5",
            domainId = "FALCON_01",
            seq = 1,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1000,
            payload = {
                attitude = q,
                angularRates = { pitchRate = 0, rollRate = 0, yawRate = 0 },
                dynamics = { altitudeY = 142.5, verticalSpeed = 1.8, velocity = { vx = 3.0, vy = 1.8, vz = 4.0 } },
                fuel = 0.78,
                dynamicLoad = 0.42,
                controlState = "NORMAL",
                activeSource = "FCP",
                sensorOk = true,
                sensorHealth = { gimbal = true },
                actuatorHealth = { tap = true, asa = true, allOk = true },
            },
        }
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 10002, telem_pkt, 42.5, 1000))
        assert_eq(net_ctx.targetDomainId, "FALCON_01")
        assert_false(net_ctx.autoDomain)
        assert_near(hud.pitch, 12.0, 0.05)
        assert_near(hud.roll, -6.0, 0.05)
        assert_near(hud.yaw, 135.0, 0.05)
        assert_near(hud.altitudeY, 142.5, 1e-6)
        assert_near(hud.verticalSpeed, 1.8, 1e-6)
        assert_near(hud.groundSpeed, 5.0, 1e-6)
        assert_near(hud.fuel, 0.78, 1e-6)
        assert_eq(hud.fsmState, "NORMAL")
        assert_eq(hud.activeSource, "FCP")
        assert_true(hud.sensorOk)
        assert_true(hud.actuatorOk)
        assert_true(hud.nodes.VAS.online)
        assert_eq(hud.linkQuality.tier, "STRONG")
        assert_eq(hud.linkQuality.distanceStr, "42.5m")

        -- Mismatched domain on Base+2 is ignored once domain is locked
        local rogue_pkt = {
            ver = "1.9.5",
            domainId = "ROGUE_99",
            seq = 2,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1050,
            payload = { controlState = "E_STOP", dynamics = { altitudeY = 0 } },
        }
        assert_false(telemetry_hud_state.ingest_packet(hud, net_ctx, 10002, rogue_pkt, 10.0, 1050))
        assert_eq(hud.fsmState, "NORMAL")

        -- MSG_MFD_STATE on Base+3 from AMM_INTEGRATED
        local mfd_pkt = {
            ver = "1.9.5",
            domainId = "FALCON_01",
            seq = 3,
            type = "MSG_MFD_STATE",
            time = 1100,
            payload = {
                source = "AMM_INTEGRATED",
                fsmState = "CRUISE",
                flightMode = "AUTO_NAV",
                activeSource = "FCP",
                attitude = { pitch = 1.5, roll = -2.0, heading = 270.0 },
                dynamics = { altitudeY = 150.0, verticalSpeed = 0.0, groundSpeed = 18.5 },
                fuel = 0.75,
                actuatorHealth = { tap = true, asa = true, allOk = true },
            },
        }
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 10003, mfd_pkt, 45.0, 1100))
        assert_eq(hud.fsmState, "CRUISE")
        assert_eq(hud.flightMode, "AUTO_NAV")
        assert_near(hud.groundSpeed, 18.5, 1e-6)
        assert_near(hud.yaw, 270.0, 1e-6)
        assert_true(hud.nodes.AMM.online)

        -- MSG_BLOCK_ASSIGN on CH 50000 for fleet discovery + cycling
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 50000, {
            ver = "1.9.5",
            domainId = "GCS_01",
            seq = 4,
            type = "MSG_BLOCK_ASSIGN",
            time = 1200,
            payload = { status = "ASSIGNED", blockId = 4, baseChannel = 10120, bandwidth = 40 },
        }, 50.0, 1200))
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 50000, {
            ver = "1.9.5",
            domainId = "GCS_01",
            seq = 5,
            type = "MSG_BLOCK_ASSIGN",
            time = 1210,
            payload = { status = "ASSIGNED", blockId = 2, baseChannel = 10040, bandwidth = 40 },
        }, 50.0, 1210))
        assert_true(hud.nodes.GCS.online)
        assert_eq(#hud.discoveredOrder, 3)
        assert_eq(hud.discoveredOrder[1], 1)
        assert_eq(hud.discoveredOrder[2], 2)
        assert_eq(hud.discoveredOrder[3], 4)

        local next_n, next_dom = telemetry_hud_state.select_next_discovered(hud, 1)
        assert_eq(next_n, 2)
        assert_eq(next_dom, "AIRCRAFT_02")
        local next_n2 = telemetry_hud_state.select_next_discovered(hud, 2)
        assert_eq(next_n2, 4)
        local wrap_n, wrap_dom = telemetry_hud_state.select_next_discovered(hud, 4)
        assert_eq(wrap_n, 1)
        assert_eq(wrap_dom, "FALCON_01")

        -- MSG_PBIT_REPORT & MSG_EMERGENCY_ALERT
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 10008, {
            ver = "1.9.5",
            domainId = "FALCON_01",
            seq = 6,
            type = "MSG_PBIT_REPORT",
            time = 1300,
            payload = { requestId = "P1", overallStatus = "PASS", takeoffPermitted = true, checks = {} },
        }, 40.0, 1300))
        assert_eq(hud.lastPbitReport.overallStatus, "PASS")

        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 10009, {
            ver = "1.9.5",
            domainId = "FALCON_01",
            seq = 7,
            type = "MSG_EMERGENCY_ALERT",
            time = 1400,
            payload = { reason = "LOW_FUEL", isAirborne = true, fsmState = "EMERGENCY_LAND", altitude = 85.0 },
        }, 40.0, 1400))
        assert_eq(hud.lastAlert.reason, "LOW_FUEL")

        -- actuatorHealth.allOk == false overrides tap/asa true
        assert_true(telemetry_hud_state.ingest_packet(hud, net_ctx, 10002, {
            ver = "1.9.5",
            domainId = "FALCON_01",
            seq = 8,
            type = "MSG_FLIGHT_TELEMETRY",
            time = 1450,
            payload = {
                controlState = "EMERGENCY_LAND",
                actuatorHealth = { tap = true, asa = true, allOk = false },
            },
        }, 40.0, 1450))
        assert_false(hud.actuatorOk)

        -- Timeout aging: > telemetryTimeoutMs (2000) -> LOST; > nodeStaleMs (3000) -> nodes offline
        telemetry_hud_state.update_link_timeouts(hud, 3500)
        assert_eq(hud.linkQuality.tier, "LOST")
        assert_true(hud.nodes.VAS.online)

        telemetry_hud_state.update_link_timeouts(hud, 5000)
        assert_false(hud.nodes.VAS.online)
        assert_false(hud.nodes.AMM.online)
        assert_false(hud.nodes.GCS.online)
    end)
end)
