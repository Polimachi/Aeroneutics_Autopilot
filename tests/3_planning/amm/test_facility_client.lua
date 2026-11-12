-- tests/3_planning/amm/test_facility_client.lua
local facility_client = require("facility_client")

describe("AMM 3-Tier facility_client & Dynamic Deck Extrapolation", function()
    local function create_test_config()
        return {
            safety = {
                dynamicGuideTimeoutMs = 300,
                maxApproachRetries = 3,
                atcDeniedRetryIntervalSec = 15,
                maxAtcDeniedRetries = 10,
                deniedHoldingClimbM = 30.0,
                goAroundTargetAltM = 100.0,
            },
            trajectory = {
                docking = {
                    abortSurgeBias = -0.8,
                    abortTimeoutMs = 300,
                }
            }
        }
    end

    describe("1. Beacon ingestion and GAC check-in request", function()
        it("initializes default state with correct safety thresholds", function()
            local cfg = create_test_config()
            local state = facility_client.init(cfg)
            assert_not_nil(state)
            assert_eq(state.padMobility, "STATIC")
            assert_eq(state.maxApproachRetries, 3)
            assert_eq(state.dynamicGuideTimeoutMs, 300)
            assert_eq(state.atcDeniedRetryIntervalSec, 15)
            assert_eq(state.maxAtcDeniedRetries, 10)
            assert_eq(state.deniedHoldingClimbM, 30.0)
            assert_eq(state.goAroundTargetAltM, 100.0)
            assert_eq(state.atcStatus, "NONE")
            assert_eq(state.approachRetryCount, 0)
            assert_eq(state.atcDeniedCount, 0)
        end)

        it("ingests facility beacons and expires stale beacons after 5000ms", function()
            local state = facility_client.init(create_test_config())
            local beacon1 = {
                facilityId = "PAD_ALPHA",
                facilityType = "LANDING_PAD",
                status = "FREE",
                position = { x = 100, y = 64, z = 200 }
            }
            local beacon2 = {
                facilityId = "PAD_BRAVO",
                facilityType = "LANDING_PAD",
                status = "OCCUPIED",
                position = { x = 500, y = 64, z = 500 }
            }

            facility_client.update_beacons(state, beacon1, 1000)
            facility_client.update_beacons(state, beacon2, 1000)

            assert_not_nil(state.beacons["PAD_ALPHA"])
            assert_not_nil(state.beacons["PAD_BRAVO"])

            -- Find nearest free landing pad from (110, 205)
            local nearest, dist = facility_client.find_nearest_free_landing_facility(state, { x = 110, z = 205 })
            assert_not_nil(nearest)
            assert_eq(nearest.facilityId, "PAD_ALPHA")
            assert_true(dist < 15.0)

            -- Beacon 1 expires at t = 6500ms (1000 + 5000 threshold is 1500)
            local beacon3 = {
                facilityId = "RUNWAY_01",
                facilityType = "RUNWAY",
                status = "FREE",
                position = { x = 0, y = 64, z = 0 }
            }
            facility_client.update_beacons(state, beacon3, 6500)
            assert_nil(state.beacons["PAD_ALPHA"], "Old beacon must expire after 5000ms")
            assert_nil(state.beacons["PAD_BRAVO"], "Old beacon must expire after 5000ms")
            assert_not_nil(state.beacons["RUNWAY_01"])
        end)

        it("builds compliant MSG_GAC_CHECKIN_REQ packet", function()
            local state = facility_client.init(create_test_config())
            local craftInfo = {
                aircraftId = "AIRCRAFT_01",
                craftWeight = 1250.0,
                craftRadius = 4.5,
                airframeType = "VECTORED_VTOL",
                preferredFacilityId = "PAD_ALPHA",
                isEmergency = false,
            }

            local req = facility_client.build_checkin_req(state, craftInfo, "SECTOR_DELTA")
            assert_not_nil(req)
            assert_eq(req.type, "MSG_GAC_CHECKIN_REQ")
            assert_eq(req.ver, "1.9.5")
            assert_not_nil(req.payload)
            assert_eq(req.payload.sectorId, "SECTOR_DELTA")
            assert_eq(req.payload.aircraftId, "AIRCRAFT_01")
            assert_eq(req.payload.craftWeight, 1250.0)
            assert_eq(req.payload.craftRadius, 4.5)
            assert_eq(req.payload.airframeType, "VECTORED_VTOL")
            assert_eq(req.payload.preferredFacilityId, "PAD_ALPHA")
            assert_eq(req.payload.isEmergency, false)
        end)
    end)

    describe("2. ATC clearance handling, denial retries, and holding climb", function()
        it("handles CLEARED status and binds active facility channels", function()
            local state = facility_client.init(create_test_config())
            local clr = {
                status = "CLEARED",
                assignedFacilityId = "PAD_02",
                assignedTacticalChannel = 50212,
                padMobility = "DYNAMIC",
            }

            facility_client.on_atc_clearance(state, clr, { x = 0, y = 80, z = 0 }, 1000)
            assert_eq(state.atcStatus, "CLEARED")
            assert_eq(state.activePadId, "PAD_02")
            assert_eq(state.padChannel, 50212)
            assert_eq(state.padMobility, "DYNAMIC")
            assert_eq(state.approachRetryCount, 0)
            assert_eq(state.atcDeniedCount, 0)
        end)

        it("handles DENIED status, increments count, raises holdingTargetAlt by 30m, and schedules 15s retry", function()
            local state = facility_client.init(create_test_config())
            local deniedPkt = {
                status = "DENIED",
                reason = "SECTOR_ALL_OCCUPIED"
            }

            facility_client.on_atc_clearance(state, deniedPkt, { x = 0, y = 70.0, z = 0 }, 1000)
            assert_eq(state.atcStatus, "DENIED")
            assert_eq(state.atcDeniedCount, 1)
            assert_eq(state.holdingTargetAlt, 100.0, "70m + 30m climb = 100m")

            -- Watchdog: at t=5000ms (only 4s elapsed, less than 15s retry interval)
            local wd1 = facility_client.evaluate_guide_watchdog(state, 5000)
            assert_eq(wd1.shouldRetryAtc, false)

            -- Watchdog: at t=16500ms (15.5s elapsed, >= 15s retry interval)
            local wd2 = facility_client.evaluate_guide_watchdog(state, 16500)
            assert_eq(wd2.shouldRetryAtc, true)
            assert_eq(wd2.holdAltClimbM, 30.0)
        end)

        it("triggers RTH after maxAtcDeniedRetries (10) consecutive denials", function()
            local state = facility_client.init(create_test_config())
            for i = 1, 10 do
                facility_client.on_atc_clearance(state, { status = "DENIED" }, { x = 0, y = 70.0, z = 0 }, i * 1000)
                assert_eq(state.atcDeniedCount, i)
            end

            -- 11th denial exceeds maxAtcDeniedRetries = 10
            facility_client.on_atc_clearance(state, { status = "DENIED" }, { x = 0, y = 70.0, z = 0 }, 11000)
            assert_eq(state.atcDeniedCount, 11)

            local wd = facility_client.evaluate_guide_watchdog(state, 30000)
            assert_eq(wd.retriesExhausted, true)
            assert_eq(wd.action, "RTH")
            assert_eq(wd.shouldRetryAtc, false)
        end)
    end)

    describe("3. 2nd-order Taylor dynamic deck extrapolation and 300ms watchdog", function()
        it("extrapolates dynamic deck position and velocity using 2nd-order Taylor expansion", function()
            local state = facility_client.init(create_test_config())
            local guidePkt = {
                type = "MSG_FACILITY_DYNAMIC_GUIDE",
                payload = {
                    facilityId = "PAD_CARRIER_01",
                    touchdownPoint = { x = 100.0, y = 64.0, z = 200.0 },
                    velocity = { vx = 10.0, vy = 0.0, vz = 4.0 },
                    acceleration = { ax = 2.0, ay = 0.0, az = -1.0 },
                    attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 },
                    deckStatus = "STABLE",
                    abortAlert = false
                }
            }

            facility_client.on_tactical_guide(state, guidePkt, 10000)
            assert_eq(state.padMobility, "DYNAMIC")
            assert_not_nil(state.dynamicGuide)

            -- Extrapolate at dt = 0.2s (t = 10200ms)
            -- p_x = 100.0 + 10.0*0.2 + 0.5*2.0*(0.2^2) = 100 + 2.0 + 0.04 = 102.04
            -- p_z = 200.0 + 4.0*0.2 + 0.5*(-1.0)*(0.2^2) = 200 + 0.8 - 0.02 = 200.78
            -- v_x = 10.0 + 2.0*0.2 = 10.4
            -- v_z = 4.0 + (-1.0)*0.2 = 3.8
            local pos, vel = facility_client.extrapolate_dynamic_deck(state, 10200)
            assert_not_nil(pos)
            assert_not_nil(vel)
            assert_true(math.abs(pos.x - 102.04) < 0.001, "pos.x Taylor 2nd-order accurate")
            assert_true(math.abs(pos.y - 64.0) < 0.001, "pos.y accurate")
            assert_true(math.abs(pos.z - 200.78) < 0.001, "pos.z Taylor 2nd-order accurate")
            assert_true(math.abs(vel.vx - 10.4) < 0.001, "vel.vx accurate")
            assert_true(math.abs(vel.vz - 3.8) < 0.001, "vel.vz accurate")
        end)

        it("clamps extrapolation time step to maximum 0.5s", function()
            local state = facility_client.init(create_test_config())
            local guidePkt = {
                type = "MSG_FACILITY_DYNAMIC_GUIDE",
                payload = {
                    touchdownPoint = { x = 0.0, y = 50.0, z = 0.0 },
                    velocity = { vx = 10.0, vy = 0.0, vz = 0.0 },
                    acceleration = { ax = 0.0, ay = 0.0, az = 0.0 },
                }
            }
            facility_client.on_tactical_guide(state, guidePkt, 1000)

            -- At dt = 1.0s (t = 2000ms), clamp to dt = 0.5s
            -- p_x = 0 + 10.0*0.5 = 5.0
            local pos, vel = facility_client.extrapolate_dynamic_deck(state, 2000)
            assert_true(math.abs(pos.x - 5.0) < 0.001, "Extrapolation dt clamped to 0.5s")
        end)

        it("triggers go-around when dynamic guide exceeds 300ms watchdog during active landing", function()
            local state = facility_client.init(create_test_config())
            state.flightMode = "APPROACH_LAND"
            local guidePkt = {
                type = "MSG_FACILITY_DYNAMIC_GUIDE",
                payload = {
                    facilityId = "PAD_CARRIER_01",
                    touchdownPoint = { x = 100, y = 64, z = 100 },
                    velocity = { vx = 0, vy = 0, vz = 0 },
                    acceleration = { ax = 0, ay = 0, az = 0 }
                }
            }
            facility_client.on_tactical_guide(state, guidePkt, 1000)
            state.activePadId = "PAD_CARRIER_01"

            -- At t = 1200ms (elapsed 200ms <= 300ms): safe
            local wd1 = facility_client.evaluate_guide_watchdog(state, 1200)
            assert_eq(wd1.triggerGoAround, false)

            -- At t = 1350ms (elapsed 350ms > 300ms): trigger go-around #1
            local wd2 = facility_client.evaluate_guide_watchdog(state, 1350)
            assert_eq(wd2.triggerGoAround, true)
            assert_eq(wd2.targetAlt, 100.0, "goAroundTargetAltM = 100.0")
            assert_eq(state.approachRetryCount, 1)

            -- Subsequent timeouts up to maxApproachRetries = 3
            local wd3 = facility_client.evaluate_guide_watchdog(state, 1700)
            assert_eq(wd3.triggerGoAround, true)
            assert_eq(state.approachRetryCount, 2)

            local wd4 = facility_client.evaluate_guide_watchdog(state, 2100)
            assert_eq(wd4.triggerGoAround, true)
            assert_eq(state.approachRetryCount, 3)

            -- 4th timeout (exceeds maxApproachRetries = 3) -> retries exhausted, FAILSAFE_RTH
            local wd5 = facility_client.evaluate_guide_watchdog(state, 2500)
            assert_eq(wd5.retriesExhausted, true)
            assert_eq(wd5.action, "FAILSAFE_RTH")
            assert_eq(state.touchdownAborted, true)
        end)
    end)

    describe("4. Docking 4-stage lifecycle and MSG_TOUCHDOWN_COMPLETE", function()
        it("advances docking 4-stage lifecycle to HARD_LOCKED and disarms", function()
            local state = facility_client.init(create_test_config())
            state.activePadId = "DOCK_ARM_01"

            facility_client.on_docking_status(state, { stage = "APPROACHING" }, 1000)
            assert_eq(state.dockingStage, "APPROACHING")
            assert_eq(state.isHardLocked, false)

            facility_client.on_docking_status(state, { stage = "ALIGNED" }, 2000)
            assert_eq(state.dockingStage, "ALIGNED")

            facility_client.on_docking_status(state, { stage = "CAPTURED" }, 3000)
            assert_eq(state.dockingStage, "CAPTURED")

            facility_client.on_docking_status(state, { stage = "RETRIEVING" }, 4000)
            assert_eq(state.dockingStage, "RETRIEVING")

            facility_client.on_docking_status(state, { stage = "HARD_LOCKED" }, 5000)
            assert_eq(state.dockingStage, "HARD_LOCKED")
            assert_eq(state.isHardLocked, true)
            assert_eq(state.flightActive, false)
        end)

        it("handles docking ABORTED stage with negative surge bias", function()
            local state = facility_client.init(create_test_config())
            facility_client.on_docking_status(state, { stage = "ABORTED", reason = "ALIGNMENT_LOST" }, 6000)
            assert_eq(state.dockingStage, "ABORTED")
            assert_eq(state.dockingAborted, true)
            assert_eq(state.abortTrajectoryBias, -0.8)
        end)

        it("builds compliant MSG_TOUCHDOWN_COMPLETE packet", function()
            local state = facility_client.init(create_test_config())
            state.activePadId = "PAD_01"

            local td = facility_client.build_touchdown_complete(state, "GROUND_IDLE")
            assert_not_nil(td)
            assert_eq(td.type, "MSG_TOUCHDOWN_COMPLETE")
            assert_eq(td.ver, "1.9.5")
            assert_eq(td.payload.facilityId, "PAD_01")
            assert_eq(td.payload.craftState, "GROUND_IDLE")
            assert_not_nil(td.payload.touchdownTime)

            local td_tbl = facility_client.build_touchdown_complete(state, { craftState = "GROUND_IDLE", facilityId = "PAD_02" })
            assert_not_nil(td_tbl)
            assert_eq(td_tbl.payload.facilityId, "PAD_02")
            assert_eq(td_tbl.payload.craftState, "GROUND_IDLE")
        end)
    end)
end)
