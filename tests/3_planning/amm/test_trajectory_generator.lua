-- tests/3_planning/amm/test_trajectory_generator.lua
local trajectory_generator = require("trajectory_generator")

describe("AMM 20Hz trajectory_generator (11 Modes, LOITER/POI_HOLD, Virtual ILS, DOCKING & [I-12] Setpoint Builder)", function()
    local config = {
        defaultAlt = 150.0,
        defaultSpeed = 18.0,
        system = {
            domainId = "AIRCRAFT_01",
            airframeType = "VECTORED_VTOL",
        },
        trajectory = {
            takeoffClearanceAltitudeM = 15.0,
            takeoffClimbRateMps = 2.5,
            loiterRadiusM = 30.0,
            loiterSpeedMps = 10.0,
            loiterRadialKp = 1.0,
            maxYawRateDegPerSec = 30.0,
            approachDescentRateMps = -1.5,
            touchdownDescentRateMps = -0.5,
            landingAlignDistanceM = 0.5,
            emergencyDescentRateMps = -2.0,
            docking = {
                creepSpeedMps = 0.4,
                maxHorizToleranceM = 0.15,
                maxVertToleranceM = 0.15,
                maxHeadingToleranceDeg = 2.0,
                abortThresholdM = 0.30,
                abortHeadingThresholdDeg = 5.0,
                abortSurgeBias = -0.8,
                abortSafetyDistanceM = 15.0,
                abortTimeoutMs = 300,
            },
        },
    }

    local function make_nav(x, y, z, vx, vy, vz, heading)
        return {
            pos = { x = x or 0.0, y = y or 64.0, z = z or 0.0 },
            vel = { x = vx or 0.0, y = vy or 0.0, z = vz or 0.0 },
            attitude = { pitch = 0.0, roll = 0.0, heading = heading or 0.0 },
            rates = { p = 0.0, q = 0.0, r = 0.0 },
            groundSpeed = math.sqrt((vx or 0.0)^2 + (vz or 0.0)^2),
            altitudeY = y or 64.0,
            verticalSpeed = vy or 0.0,
            hdop = 1.1,
            posEpoch = 42,
            navValid = true,
            gpsStale = false,
            coreArmed = true,
        }
    end

    it("verifies trajectory_generator exposes all 11 canonical MODES and initializes cleanly", function()
        local state = trajectory_generator.init(config)
        assert_not_nil(state)
        assert_not_nil(trajectory_generator.MODES)
        local expected = {
            "IDLE", "TAKEOFF", "CRUISE", "LOITER", "POI_HOLD",
            "APPROACH_LAND", "LANDING", "DOCKING", "FAILSAFE_RTH",
            "HOVER_HOLD", "EMERGENCY_LAND"
        }
        for _, mode in ipairs(expected) do
            assert_not_nil(trajectory_generator.MODES[mode], "Mode " .. mode .. " must be defined in MODES")
        end
    end)

    it("enforces canonical [I-12] Zero-Fallback schema and forbids targetAccelFF/targetHeadingDeg", function()
        local state = trajectory_generator.init(config)
        local nav = make_nav(100.0, 150.0, 200.0, 10.0, 0.0, 0.0, 90.0)
        local goal = {
            flightMode = "CRUISE",
            targetPos = { x = 200.0, y = 150.0, z = 200.0 },
            targetSpeed = 18.0,
        }
        local setpoint = trajectory_generator.compute(state, nav, nil, goal, 0.05, 1000)
        assert_not_nil(setpoint)

        -- Required canonical keys
        assert_true(setpoint.arm)
        assert_true(setpoint.flightActive)
        assert_eq(setpoint.flightMode, "CRUISE")
        assert_eq(setpoint.constraintProfile, "STANDARD")
        assert_not_nil(setpoint.targetPos)
        assert_not_nil(setpoint.targetVel)
        assert_not_nil(setpoint.feedforwardAccel)
        assert_not_nil(setpoint.targetHeading)
        assert_not_nil(setpoint.headingMode)
        assert_not_nil(setpoint.maxHorizSpeedMps)
        assert_not_nil(setpoint.maxVertSpeedMps)
        assert_not_nil(setpoint.maxTiltDeg)
        assert_not_nil(setpoint.currentPos)
        assert_near(setpoint.currentPos.x, 100.0, 1e-4)
        assert_near(setpoint.currentPos.y, 150.0, 1e-4)
        assert_near(setpoint.currentPos.z, 200.0, 1e-4)
        assert_true(setpoint.navValid)
        assert_false(setpoint.gpsTimedOut)
        assert_near(setpoint.hdop, 1.1, 1e-4)
        assert_eq(setpoint.posEpoch, 42)

        -- Strict Zero-Fallback ban on deprecated/dual keys
        assert_nil(setpoint.targetAccelFF, "targetAccelFF is prohibited by Zero-Fallback ruling")
        assert_nil(setpoint.targetHeadingDeg, "targetHeadingDeg is prohibited by Zero-Fallback ruling")
        assert_nil(setpoint.accelFF, "accelFF is prohibited")
    end)

    it("handles TAKEOFF mode: anchors takeoffOriginY, climbs at +2.5m/s with zero horizontal offset until clearance", function()
        local state = trajectory_generator.init(config)
        local nav = make_nav(10.0, 64.0, 20.0, 0.0, 0.0, 0.0, 45.0)
        local goal = { flightMode = "TAKEOFF" }

        -- First tick at y = 64.0
        local sp1 = trajectory_generator.compute(state, nav, nil, goal, 0.05, 1000)
        assert_eq(sp1.flightMode, "TAKEOFF")
        assert_eq(sp1.constraintProfile, "STRICT_LEVEL")
        assert_true(sp1.arm)
        assert_true(sp1.flightActive)
        assert_near(sp1.targetPos.x, 10.0, 1e-4)
        assert_near(sp1.targetPos.z, 20.0, 1e-4)
        assert_near(sp1.targetPos.y, 79.0, 1e-4) -- 64.0 + 15.0
        assert_near(sp1.targetVel.vx, 0.0, 1e-4)
        assert_near(sp1.targetVel.vz, 0.0, 1e-4)
        assert_near(sp1.targetVel.vy, 2.5, 1e-4)
        assert_near(sp1.feedforwardAccel.ax, 0.0, 1e-4)
        assert_near(sp1.feedforwardAccel.ay, 0.0, 1e-4)
        assert_near(sp1.feedforwardAccel.az, 0.0, 1e-4)

        -- Intermediate tick at y = 70.0 (anchor remains 64.0)
        local nav2 = make_nav(10.1, 70.0, 19.9, 0.0, 2.5, 0.0, 45.0)
        local sp2 = trajectory_generator.compute(state, nav2, nil, goal, 0.05, 1050)
        assert_near(sp2.targetPos.y, 79.0, 1e-4)
        assert_near(sp2.targetVel.vy, 2.5, 1e-4)
        assert_near(sp2.distanceToWp, 9.0, 1e-4) -- 79.0 - 70.0
    end)

    it("handles CRUISE mode: normalizes 3D direction to targetSpeed, zero vertical feedforward once at targetAlt", function()
        local state = trajectory_generator.init(config)
        -- Craft at (0, 150, 0), target at (300, 150, 400) -> 3-4-5 triangle, 2D dist = 500m
        local nav = make_nav(0.0, 150.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        local goal = {
            flightMode = "CRUISE",
            targetPos = { x = 300.0, y = 150.0, z = 400.0 },
            targetSpeed = 20.0,
            activeWpIndex = 2,
        }
        local sp = trajectory_generator.compute(state, nav, nil, goal, 0.05, 1000)
        assert_near(sp.distanceToWp, 500.0, 1e-4)
        assert_near(sp.targetVel.vx, 12.0, 1e-4) -- (300/500)*20
        assert_near(sp.targetVel.vz, 16.0, 1e-4) -- (400/500)*20
        assert_near(sp.targetVel.vy, 0.0, 1e-4)
        assert_near(sp.feedforwardAccel.ay, 0.0, 1e-4)
        assert_eq(sp.activeWpIndex, 2)
        -- Heading towards (300, 400): dx=300, -dz=-400 -> atan2(300, -400) = 143.13 deg
        assert_near(sp.targetHeading, 143.13, 0.1)
    end)

    it("handles LOITER mode: enforces R >= 5.0m, computes CW/CCW tangential speed + radial restoration + centripetal feedforward", function()
        local state = trajectory_generator.init(config)
        -- Center at (100, 150, 100), R = 30m, v_t = 10m/s
        -- Craft at (100, 150, 70) -> exactly North of center (rx=0, rz=-30, r=30)
        local nav = make_nav(100.0, 150.0, 70.0, 0.0, 0.0, 0.0, 90.0)
        local goalCW = {
            flightMode = "LOITER",
            targetPos = { x = 100.0, y = 150.0, z = 100.0 },
            loiterRadius = 30.0,
            loiterDirection = "CW",
            targetSpeed = 10.0,
        }
        local spCW = trajectory_generator.compute(state, nav, nil, goalCW, 0.05, 1000)
        -- North of center for CW: tangent points East (+X)
        assert_near(spCW.targetVel.vx, 10.0, 1e-3)
        assert_near(spCW.targetVel.vz, 0.0, 1e-3)
        -- On circle (r = R = 30), radial error = 0
        -- Centripetal acceleration: a_c = v_t^2 / R = 100 / 30 = 3.333 m/s^2 pointing inward (+Z)
        assert_near(spCW.feedforwardAccel.ax, 0.0, 1e-3)
        assert_near(spCW.feedforwardAccel.az, 100.0 / 30.0, 1e-3)

        -- Test CCW direction: tangent points West (-X)
        local goalCCW = {
            flightMode = "LOITER",
            targetPos = { x = 100.0, y = 150.0, z = 100.0 },
            loiterRadius = 30.0,
            loiterDirection = "CCW",
            targetSpeed = 10.0,
        }
        local spCCW = trajectory_generator.compute(state, nav, nil, goalCCW, 0.05, 1050)
        assert_near(spCCW.targetVel.vx, -10.0, 1e-3)
        assert_near(spCCW.targetVel.vz, 0.0, 1e-3)

        -- Test radial restoration when craft is at r = 40m (10m outside circle)
        -- Craft at (100, 150, 60) -> rx=0, rz=-40, r=40
        local navOutside = make_nav(100.0, 150.0, 60.0, 0.0, 0.0, 0.0, 90.0)
        local spOut = trajectory_generator.compute(state, navOutside, nil, goalCW, 0.05, 1100)
        -- loiterRadialKp = 1.0, err = (30 - 40) = -10 m/s along outward vector (0, -1) -> restoration = +10 m/s in +Z (inward)
        assert_near(spOut.targetVel.vz, 10.0, 1e-3)

        -- Test minimum radius clamp R >= 5.0m
        local goalSmall = {
            flightMode = "LOITER",
            targetPos = { x = 100.0, y = 150.0, z = 100.0 },
            loiterRadius = 2.0, -- should clamp to 5.0
            targetSpeed = 10.0,
        }
        local spSmall = trajectory_generator.compute(state, nav, nil, goalSmall, 0.05, 1150)
        -- Centripetal acceleration with R = 5.0: 100 / 5 = 20.0 m/s^2
        local totalAccel = math.sqrt(spSmall.feedforwardAccel.ax^2 + spSmall.feedforwardAccel.az^2)
        assert_near(totalAccel, 20.0, 1e-3)

        -- Test center singularity r < 1e-3
        local navCenter = make_nav(100.0, 150.0, 100.0, 0.0, 0.0, 0.0, 0.0)
        local spCenter = trajectory_generator.compute(state, navCenter, nil, goalCW, 0.05, 1200)
        assert_not_nil(spCenter)
        assert_true(spCenter.feedforwardAccel.ax == spCenter.feedforwardAccel.ax) -- not NaN
    end)

    it("handles POI_HOLD mode: holds targetPos, aims targetHeading at poiPos with rate limit, freezes yaw inside 0.5m", function()
        local state = trajectory_generator.init(config)
        state.prevHeading = 0.0
        -- Craft at (0, 100, 0), POI at (100, 100, 0) -> East (heading 90 deg)
        local nav = make_nav(0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        local goal = {
            flightMode = "POI_HOLD",
            targetPos = { x = 0.0, y = 100.0, z = 0.0 },
            poiPos = { x = 100.0, y = 100.0, z = 0.0 },
            headingMode = "POI",
        }
        -- First tick at dt = 0.05s: rate limited to 30 deg/s * 0.05 = 1.5 deg
        local sp1 = trajectory_generator.compute(state, nav, nil, goal, 0.05, 1000)
        assert_eq(sp1.flightMode, "POI_HOLD")
        assert_eq(sp1.constraintProfile, "STRICT_LEVEL")
        assert_near(sp1.flapHint, 0.0, 1e-4)
        assert_near(sp1.targetVel.vx, 0.0, 1e-4)
        assert_near(sp1.targetVel.vy, 0.0, 1e-4)
        assert_near(sp1.targetVel.vz, 0.0, 1e-4)
        assert_near(sp1.targetHeading, 1.5, 1e-3)

        -- Inside 0.5m singularity: POI at (0.2, 100, 0.2)
        local navNear = make_nav(0.0, 100.0, 0.0, 0.0, 0.0, 0.0, 1.5)
        local goalNear = {
            flightMode = "POI_HOLD",
            targetPos = { x = 0.0, y = 100.0, z = 0.0 },
            poiPos = { x = 0.2, y = 100.0, z = 0.2 },
        }
        local spNear = trajectory_generator.compute(state, navNear, nil, goalNear, 0.05, 1050)
        -- Yaw freezes at prevHeading (1.5)
        assert_near(spNear.targetHeading, 1.5, 1e-3)
    end)

    it("handles APPROACH_LAND & LANDING with 2-stage VTOL descent and dynamic deck extrapolation", function()
        local state = trajectory_generator.init(config)
        -- Stage 1: d_2D > 0.5m -> approach descent vy = -1.5 m/s
        local navFar = make_nav(10.0, 80.0, 10.0, 0.0, 0.0, 0.0, 0.0)
        local goalStatic = {
            flightMode = "APPROACH_LAND",
            targetPos = { x = 0.0, y = 64.0, z = 0.0 },
        }
        local spFar = trajectory_generator.compute(state, navFar, nil, goalStatic, 0.05, 1000)
        assert_near(spFar.targetVel.vy, -1.5, 1e-3)

        -- Stage 2: d_2D <= 0.5m -> touchdown descent vy = -0.5 m/s
        local navClose = make_nav(0.2, 66.0, 0.2, 0.0, 0.0, 0.0, 0.0)
        local spClose = trajectory_generator.compute(state, navClose, nil, goalStatic, 0.05, 1050)
        assert_near(spClose.targetVel.vy, -0.5, 1e-3)

        -- Dynamic deck integration
        local facilityState = {
            padMobility = "DYNAMIC",
            dynamicGuide = {
                pos = { x = 50.0, y = 65.0, z = 50.0 },
                vel = { vx = 4.0, vy = 0.0, vz = 0.0 },
                accel = { ax = 0.5, ay = 0.0, az = 0.0 },
                attitude = { pitch = 0.0, roll = 0.0, yaw = 90.0 },
                approachHeading = 90.0,
                lastUpdateMs = 1100,
            },
        }
        local goalDyn = {
            flightMode = "APPROACH_LAND",
            padMobility = "DYNAMIC",
        }
        local spDyn = trajectory_generator.compute(state, navFar, facilityState, goalDyn, 0.05, 1100)
        -- Matches moving deck speed (vx = 4.0) + descent
        assert_near(spDyn.targetVel.vx, 4.0, 0.1)
        assert_near(spDyn.targetHeading, 90.0, 1e-3)

        -- Virtual ILS glideslope for FIXED_WING
        local goalILS = {
            flightMode = "APPROACH_LAND",
            airframeType = "FIXED_WING",
            runwayThreshold = { x = 0.0, y = 64.0, z = 0.0 },
            approachBearingDeg = 0.0,
            glideslopeDeg = 3.0,
            targetSpeed = 15.0,
        }
        local spILS = trajectory_generator.compute(state, navFar, nil, goalILS, 0.05, 1150)
        assert_near(spILS.flapHint, 1.0, 1e-4)
        assert_eq(spILS.constraintProfile, "FIXED_WING_GLIDE")
    end)

    it("handles DOCKING mode: respects tolerances, creeps at 0.4m/s, aborts when error exceeds threshold with surge = -0.8 until safety distance", function()
        local state = trajectory_generator.init(config)
        local dockTarget = { x = 0.0, y = 100.0, z = 0.0, heading = 0.0 }
        local goal = {
            flightMode = "DOCKING",
            targetPos = dockTarget,
            fixedHeadingDeg = 0.0,
        }

        -- Nominal docking corridor (dx = 0.05 <= 0.15, heading error = 1.0 <= 2.0)
        local navNominal = make_nav(0.05, 100.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        local spNom = trajectory_generator.compute(state, navNominal, nil, goal, 0.05, 1000)
        assert_not_nil(spNom.translationBiasHint)
        assert_near(spNom.translationBiasHint.surge, 0.4, 1e-3)
        assert_false(state.dockingAborted)

        -- Alignment error exceeds threshold (dx = 0.35m > 0.30m) -> Triggers Abort!
        local navOffTrack = make_nav(0.35, 100.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        local spAbort = trajectory_generator.compute(state, navOffTrack, nil, goal, 0.05, 1050)
        assert_true(state.dockingAborted)
        assert_near(spAbort.translationBiasHint.surge, -0.8, 1e-3)

        -- During abort retreat: still within abortSafetyDistanceM (e.g. dist = 5.0m < 15.0m)
        local navRetreating = make_nav(0.0, 100.0, 5.0, 0.0, 0.0, 0.0, 0.0)
        local spRetreat = trajectory_generator.compute(state, navRetreating, nil, goal, 0.05, 1200)
        assert_true(state.dockingAborted)
        assert_near(spRetreat.translationBiasHint.surge, -0.8, 1e-3)

        -- Cleared safety distance (16.0m >= 15.0m) AND elapsed time (400ms >= 300ms) -> Resets abort!
        local navCleared = make_nav(0.0, 100.0, 16.0, 0.0, 0.0, 0.0, 0.0)
        local spCleared = trajectory_generator.compute(state, navCleared, nil, goal, 0.05, 1500)
        assert_false(state.dockingAborted)

        -- HARD_LOCKED disarms craft
        local facHardLock = { isHardLocked = true, dockingStage = "HARD_LOCKED" }
        local spLocked = trajectory_generator.compute(state, navNominal, facHardLock, goal, 0.05, 1550)
        assert_false(spLocked.arm)
        assert_false(spLocked.flightActive)
    end)

    it("handles EMERGENCY_LAND mode: commands vy = -2.0m/s, STRICT_LEVEL, flapHint = 1.0 for winged craft", function()
        local state = trajectory_generator.init(config)
        local nav = make_nav(50.0, 120.0, 50.0, 10.0, 0.0, 5.0, 180.0)
        local goalWinged = {
            flightMode = "EMERGENCY_LAND",
            airframeType = "WINGED_VTOL",
        }
        local sp = trajectory_generator.compute(state, nav, nil, goalWinged, 0.05, 1000)
        assert_eq(sp.flightMode, "EMERGENCY_LAND")
        assert_eq(sp.constraintProfile, "STRICT_LEVEL")
        assert_near(sp.targetVel.vy, -2.0, 1e-4)
        assert_near(sp.targetVel.vx, 0.0, 1e-4)
        assert_near(sp.targetVel.vz, 0.0, 1e-4)
        assert_near(sp.flapHint, 1.0, 1e-4)
    end)

    it("handles IDLE, HOVER_HOLD, and FAILSAFE_RTH modes", function()
        local state = trajectory_generator.init(config)
        local nav = make_nav(10.0, 64.0, 20.0, 0.0, 0.0, 0.0, 0.0)

        -- IDLE: on ground, flightActive = false
        local spIdle = trajectory_generator.compute(state, nav, nil, { flightMode = "IDLE" }, 0.05, 1000)
        assert_false(spIdle.flightActive)
        assert_near(spIdle.targetVel.vx, 0.0, 1e-4)
        assert_near(spIdle.targetVel.vy, 0.0, 1e-4)
        assert_near(spIdle.targetVel.vz, 0.0, 1e-4)

        -- HOVER_HOLD: holds current position, flightActive = true
        local spHover = trajectory_generator.compute(state, nav, nil, { flightMode = "HOVER_HOLD" }, 0.05, 1050)
        assert_true(spHover.flightActive)
        assert_eq(spHover.constraintProfile, "STRICT_LEVEL")
        assert_near(spHover.targetPos.x, 10.0, 1e-4)
        assert_near(spHover.targetPos.z, 20.0, 1e-4)

        -- FAILSAFE_RTH: flies towards homePos (0, 150, 0)
        local spRth = trajectory_generator.compute(state, nav, nil, {
            flightMode = "FAILSAFE_RTH",
            homePos = { x = 0.0, y = 150.0, z = 0.0 },
            targetSpeed = 18.0,
        }, 0.05, 1100)
        assert_true(spRth.flightActive)
        assert_eq(spRth.flightMode, "FAILSAFE_RTH")
        assert_near(spRth.targetPos.x, 0.0, 1e-4)
        assert_near(spRth.targetPos.y, 150.0, 1e-4)
        assert_near(spRth.targetPos.z, 0.0, 1e-4)
    end)
end)
