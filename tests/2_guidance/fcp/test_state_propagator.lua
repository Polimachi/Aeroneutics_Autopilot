-- tests/2_guidance/fcp/test_state_propagator.lua
local state_propagator = require("state_propagator")

describe("test_fcp_network_and_rebind|test_state_propagator: FCP State Propagator 20Hz Integration and DR", function()
    it("initializes default state table with zeroed vectors and valid flags", function()
        local state = state_propagator.init({ posMergeMaxStepM = 2.0, navStaleTimeoutMs = 500 })
        assert_not_nil(state)
        assert_eq(state.pos.x, 0.0)
        assert_eq(state.pos.y, 0.0)
        assert_eq(state.pos.z, 0.0)
        assert_eq(state.vel.vx, 0.0)
        assert_eq(state.vel.vy, 0.0)
        assert_eq(state.vel.vz, 0.0)
        assert_eq(state.navValid, true)
        assert_eq(state.navStale, false)
        assert_eq(state.posEpoch, 0)
    end)

    it("keeps navStale false at boot before any telemetry arrives", function()
        local state = state_propagator.init({ navStaleTimeoutMs = 500 })
        local snap = state_propagator.propagate(state, 5000)
        assert_false(snap.navStale, "Boot before first telemetry must not mark navStale=true")
    end)

    it("ingests VAS Base+2 telemetry and updates velocity, attitude and rates", function()
        local state = state_propagator.init()
        local telem = {
            dynamics = {
                velocity = { vx = 10.0, vy = 1.0, vz = -5.0 },
                altitudeY = 120.0,
            },
            attitude = { pitch = 2.0, roll = -1.0, yaw = 90.0 },
            angularRates = { pitchRate = 0.1, rollRate = 0.0, yawRate = 0.2 },
            actuatorHealth = { tap = false, asa = true },
            activeSource = "FCP",
            sensorOk = true,
        }
        state_propagator.on_telemetry(state, telem, 1000)

        assert_eq(state.vel.vx, 10.0)
        assert_eq(state.vel.vy, 1.0)
        assert_eq(state.vel.vz, -5.0)
        assert_eq(state.attitude.yaw, 90.0)
        assert_eq(state.attitude.heading, 90.0)
        assert_eq(state.angularRates.pitchRate, 0.1)
        assert_eq(state.lastTelemMs, 1000)
        assert_false(state.actuatorHealth.allOk, "allOk must be false when tap=false")
        assert_eq(state.activeSource, "FCP")
    end)

    it("integrates velocity over dt and clamps dt to 0.1s max", function()
        local state = state_propagator.init()
        local telem = {
            dynamics = { velocity = { vx = 20.0, vy = 0.0, vz = 0.0 } },
            attitude = {}, angularRates = {}, actuatorHealth = {},
        }
        state_propagator.on_telemetry(state, telem, 1000)
        state.lastPropagateMs = 1000

        -- Normal step: 50ms (0.05s) -> 20.0 * 0.05 = 1.0m
        local res = state_propagator.propagate(state, 1050)
        assert_near(res.pos.x, 1.0, 1e-4)

        -- dt clamp check: jump of 500ms -> dt clamped to 0.1s -> 20.0 * 0.1 = 2.0m -> total 3.0m
        local res_clamped = state_propagator.propagate(state, 1550)
        assert_near(res_clamped.pos.x, 3.0, 1e-4)

        -- Negative dt check: should not integrate backward
        local res_neg = state_propagator.propagate(state, 1500)
        assert_near(res_neg.pos.x, 3.0, 1e-4)
    end)

    it("smoothly merges AMM posEpoch currentPos within posMergeMaxStepM = 2.0", function()
        local state = state_propagator.init({ posMergeMaxStepM = 2.0 })
        state.pos = { x = 100.0, y = 50.0, z = -200.0 }
        state.lastSyncedEpoch = 10

        -- Small delta (< 2.0m): should fully snap
        local sp_small = {
            posEpoch = 11,
            currentPos = { x = 101.0, y = 50.5, z = -200.0 }, -- dist = sqrt(1.25) ~ 1.118m < 2.0m
            navValid = true,
            gpsTimedOut = false,
            hdop = 1.0,
        }
        state_propagator.on_setpoint_epoch(state, sp_small, 2000)
        assert_near(state.pos.x, 101.0, 1e-4)
        assert_near(state.pos.y, 50.5, 1e-4)
        assert_near(state.pos.z, -200.0, 1e-4)
        assert_eq(state.lastSyncedEpoch, 11)

        -- Large delta (> 2.0m): should clamp jump to exactly 2.0m along delta vector
        local sp_large = {
            posEpoch = 12,
            currentPos = { x = 111.0, y = 50.5, z = -200.0 }, -- delta = +10.0m in X
            navValid = true,
            gpsTimedOut = false,
            hdop = 1.0,
        }
        state_propagator.on_setpoint_epoch(state, sp_large, 2050)
        assert_near(state.pos.x, 103.0, 1e-4, "X position should have advanced by 2.0m max")
        assert_eq(state.lastSyncedEpoch, 12)

        -- Ignore older or equal posEpoch
        local sp_old = {
            posEpoch = 12,
            currentPos = { x = 150.0, y = 50.5, z = -200.0 },
        }
        state_propagator.on_setpoint_epoch(state, sp_old, 2100)
        assert_near(state.pos.x, 103.0, 1e-4, "Old posEpoch must not update pos")
    end)

    it("evaluates navStale when telemetry age exceeds 500ms, posEpoch stagnates, or navValid is false", function()
        local state = state_propagator.init({ navStaleTimeoutMs = 500 })
        local telem = {
            dynamics = { velocity = { vx = 0.0, vy = 0.0, vz = 0.0 } },
            attitude = {}, angularRates = {}, actuatorHealth = {},
        }
        state_propagator.on_telemetry(state, telem, 1000)

        -- At t = 1400 (age = 400ms <= 500ms)
        local res_fresh = state_propagator.propagate(state, 1400)
        assert_false(res_fresh.navStale)

        -- At t = 1501 (age = 501ms > 500ms)
        local res_stale = state_propagator.propagate(state, 1501)
        assert_true(res_stale.navStale)

        -- Telemetry refreshed at t = 1600, plus posEpoch=1 received at t=1600
        state_propagator.on_telemetry(state, telem, 1600)
        state_propagator.on_setpoint_epoch(state, { posEpoch = 1, currentPos = { x = 0, y = 0, z = 0 }, navValid = true }, 1600)
        local res_refreshed = state_propagator.propagate(state, 1610)
        assert_false(res_refreshed.navStale)

        -- Keep telemetry fresh at t = 2200, but posEpoch stagnates (> 500ms since epoch 1)
        state_propagator.on_telemetry(state, telem, 2200)
        state_propagator.on_setpoint_epoch(state, { posEpoch = 1, currentPos = { x = 0, y = 0, z = 0 }, navValid = true }, 2200)
        local res_epoch_stale = state_propagator.propagate(state, 2200)
        assert_true(res_epoch_stale.navStale, "posEpoch stagnation > 500ms must flag navStale")

        -- Fresh epoch clears stagnation, then navValid = false flags navStale
        state_propagator.on_setpoint_epoch(state, { posEpoch = 2, currentPos = { x = 0, y = 0, z = 0 }, navValid = false }, 2210)
        local res_invalid = state_propagator.propagate(state, 2215)
        assert_true(res_invalid.navStale)
    end)

    it("propagate returns complete state snapshot matching contract", function()
        local state = state_propagator.init()
        local telem = {
            dynamics = { velocity = { vx = 12.0, vy = 0.0, vz = 5.0 } },
            attitude = { pitch = 1.0, roll = 0.0, yaw = 45.0 },
            angularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
            actuatorHealth = { tap = true, asa = true, allOk = true },
            activeSource = "FCP",
        }
        state_propagator.on_telemetry(state, telem, 1000)
        local out = state_propagator.propagate(state, 1050)

        assert_not_nil(out.pos)
        assert_not_nil(out.vel)
        assert_not_nil(out.attitude)
        assert_not_nil(out.angularRates)
        assert_not_nil(out.groundSpeed)
        assert_not_nil(out.airspeed)
        assert_not_nil(out.posEpoch)
        assert_not_nil(out.lastTelemMs)
        assert_not_nil(out.navStale)
        assert_not_nil(out.actuatorHealth)
    end)
end)
