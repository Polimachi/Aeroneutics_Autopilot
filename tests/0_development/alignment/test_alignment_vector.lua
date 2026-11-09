-- Unit test suite for ADVANCED_VTOL alignment gimbal calibration & pseudo-inverse engine
local discovery_client = require("discovery_client")
local multi_pulse_sequencer = require("multi_pulse_sequencer")
local ols_regression_engine = require("ols_regression_engine")
local profile_exporter = require("profile_exporter")
local controllability_checker = require("controllability_checker")

local function mat_mult(A, B)
    local rowsA = #A
    local colsA = #A[1]
    local rowsB = #B
    local colsB = #B[1]
    assert(colsA == rowsB, string.format("Matrix dim mismatch: colsA=%d, rowsB=%d", colsA, rowsB))
    local C = {}
    for i = 1, rowsA do
        C[i] = {}
        for j = 1, colsB do
            local sum = 0.0
            for k = 1, colsA do
                sum = sum + A[i][k] * B[k][j]
            end
            C[i][j] = sum
        end
    end
    return C
end

describe("alignment vector gimbal calibration & pseudo-inverse engine", function()
    it("detects vector-capable nodes in discovery_client", function()
        local client = discovery_client.new("AIRCRAFT_01")
        assert_not_nil(client)

        local vecAck = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 10,
            type = "MSG_ACTUATOR_DISCOVER_ACK",
            payload = {
                groupId = "THR_VEC_1",
                interactionMode = "API",
                activeCount = 1,
                totalCount = 1,
                isVectorCapable = true,
                gimbalLimits = { minX = -1.0, maxX = 1.0, minY = -1.0, maxY = 1.0 },
                healthStatus = "NOMINAL"
            }
        }
        local stdAck = {
            ver = "1.9.5",
            domainId = "AIRCRAFT_01",
            seq = 11,
            type = "MSG_ACTUATOR_DISCOVER_ACK",
            payload = {
                groupId = "THR_STD_1",
                interactionMode = "REDSTONE",
                activeCount = 1,
                totalCount = 1,
                isVectorCapable = false,
                healthStatus = "NOMINAL"
            }
        }

        assert_true(client:process_ack(vecAck))
        assert_true(client:process_ack(stdAck))

        assert_true(client:is_vector_capable("THR_VEC_1"))
        assert_false(client:is_vector_capable("THR_STD_1"))
        assert_false(client:is_vector_capable("NON_EXISTENT"))

        local actInfo = client:get_actuator("THR_VEC_1")
        assert_not_nil(actInfo)
        assert_true(actInfo.isVectorCapable)
        assert_not_nil(actInfo.gimbalLimits)
        assert_eq(actInfo.gimbalLimits.maxX, 1.0)
    end)

    it("schedules multi-pulse sequence for throttle, gimbalX, and gimbalY", function()
        local seq = multi_pulse_sequencer.generate_vector_sequence("THR_VEC_FL")
        assert_not_nil(seq)
        -- 3 throttle pulses (5, 10, 15) + 3 gimbal X pulses (-0.5, 0.5, 1.0) + 3 gimbal Y pulses (-0.5, 0.5, 1.0)
        assert_eq(#seq, 9)

        -- Phase 1: Throttle
        assert_eq(seq[1].phase, "THROTTLE")
        assert_eq(seq[1].pulseLevel, 5)
        assert_near(seq[1].gimbalX, 0.0, 1e-4)
        assert_near(seq[1].gimbalY, 0.0, 1e-4)

        assert_eq(seq[2].phase, "THROTTLE")
        assert_eq(seq[2].pulseLevel, 10)

        assert_eq(seq[3].phase, "THROTTLE")
        assert_eq(seq[3].pulseLevel, 15)

        -- Phase 2: Gimbal X (base throttle 8)
        assert_eq(seq[4].phase, "GIMBAL_X")
        assert_eq(seq[4].pulseLevel, 8)
        assert_near(seq[4].gimbalX, -0.5, 1e-4)
        assert_near(seq[4].gimbalY, 0.0, 1e-4)

        assert_eq(seq[5].phase, "GIMBAL_X")
        assert_eq(seq[5].pulseLevel, 8)
        assert_near(seq[5].gimbalX, 0.5, 1e-4)

        assert_eq(seq[6].phase, "GIMBAL_X")
        assert_eq(seq[6].pulseLevel, 8)
        assert_near(seq[6].gimbalX, 1.0, 1e-4)

        -- Phase 3: Gimbal Y (base throttle 8)
        assert_eq(seq[7].phase, "GIMBAL_Y")
        assert_eq(seq[7].pulseLevel, 8)
        assert_near(seq[7].gimbalX, 0.0, 1e-4)
        assert_near(seq[7].gimbalY, -0.5, 1e-4)

        assert_eq(seq[8].phase, "GIMBAL_Y")
        assert_eq(seq[8].pulseLevel, 8)
        assert_near(seq[8].gimbalY, 0.5, 1e-4)

        assert_eq(seq[9].phase, "GIMBAL_Y")
        assert_eq(seq[9].pulseLevel, 8)
        assert_near(seq[9].gimbalY, 1.0, 1e-4)

        -- Test Sequencer object vector stepping & packet generation
        local sequencer = multi_pulse_sequencer.new("AIRCRAFT_01")
        sequencer:start_vector_thruster("THR_VEC_FL")
        assert_false(sequencer:is_complete())

        local pkt1 = sequencer:build_pulse_packet(1)
        assert_eq(pkt1.type, "MSG_CALIB_PULSE")
        assert_eq(pkt1.payload.targetThrusterId, "THR_VEC_FL")
        assert_eq(pkt1.payload.pulseLevel, 5)
        assert_eq(pkt1.payload.phase, "THROTTLE")
        assert_near(pkt1.payload.gimbalX, 0.0, 1e-4)

        -- Step to phase 2 (gimbal X)
        for _ = 1, 3 do sequencer:next_step() end
        local pkt4 = sequencer:build_pulse_packet(4)
        assert_eq(pkt4.payload.phase, "GIMBAL_X")
        assert_eq(pkt4.payload.pulseLevel, 8)
        assert_near(pkt4.payload.gimbalX, -0.5, 1e-4)
    end)

    it("computes 6-axis OLS derivative slopes for T, gx, and gy", function()
        local pulseResults = {
            throttle = {
                signals = { 5, 10, 15 },
                impulses = {
                    { surge = 0.0, sway = 0.0, heave = 5.0,  roll = 0.0, pitch = 2.5,  yaw = 0.0 },
                    { surge = 0.0, sway = 0.0, heave = 10.0, roll = 0.0, pitch = 5.0,  yaw = 0.0 },
                    { surge = 0.0, sway = 0.0, heave = 15.0, roll = 0.0, pitch = 7.5,  yaw = 0.0 },
                }
            },
            gimbalX = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = 0.0, sway = -4.0, heave = 8.0, roll = -2.0, pitch = 4.0, yaw = 1.0 },
                    { surge = 0.0, sway = 4.0,  heave = 8.0, roll = 2.0,  pitch = 4.0, yaw = -1.0 },
                    { surge = 0.0, sway = 8.0,  heave = 8.0, roll = 4.0,  pitch = 4.0, yaw = -2.0 },
                }
            },
            gimbalY = {
                signals = { -0.5, 0.5, 1.0 },
                impulses = {
                    { surge = -4.0, sway = 0.0, heave = 8.0, roll = 0.0, pitch = -2.0, yaw = 0.0 },
                    { surge = 4.0,  sway = 0.0, heave = 8.0, roll = 0.0, pitch = 2.0,  yaw = 0.0 },
                    { surge = 8.0,  sway = 0.0, heave = 8.0, roll = 0.0, pitch = 4.0,  yaw = 0.0 },
                }
            }
        }

        local slopes = ols_regression_engine.compute_vector_slopes(pulseResults)
        assert_not_nil(slopes)
        assert_not_nil(slopes.dThrust)
        assert_not_nil(slopes.dGimbalX)
        assert_not_nil(slopes.dGimbalY)

        -- dThrust: dHeave/dT = 1.0, dPitch/dT = 0.5
        assert_near(slopes.dThrust.heave, 1.0, 1e-4)
        assert_near(slopes.dThrust.pitch, 0.5, 1e-4)
        assert_near(slopes.dThrust.surge, 0.0, 1e-4)

        -- dGimbalX: dSway/dgx = 8.0, dRoll/dgx = 4.0, dYaw/dgx = -2.0
        assert_near(slopes.dGimbalX.sway, 8.0, 1e-4)
        assert_near(slopes.dGimbalX.roll, 4.0, 1e-4)
        assert_near(slopes.dGimbalX.yaw, -2.0, 1e-4)

        -- dGimbalY: dSurge/dgy = 8.0, dPitch/dgy = 4.0
        assert_near(slopes.dGimbalY.surge, 8.0, 1e-4)
        assert_near(slopes.dGimbalY.pitch, 4.0, 1e-4)
    end)

    it("computes Moore-Penrose pseudo-inverse B_dagger such that B * B_dagger approx I_6", function()
        -- Controllable 6-DoF coupled Control Effectiveness Matrix B (6 x 6 full rank)
        local B_6x6 = {
            { 6.0,  0.0,  1.0,  0.0,  0.0,  0.0 }, -- surge
            { 0.0,  6.0,  0.0,  1.0,  0.0,  0.0 }, -- sway
            { 0.0,  0.0,  4.0,  0.0,  1.0,  0.0 }, -- heave
            { 1.0,  0.0,  0.0,  5.0,  0.0,  0.0 }, -- pitch
            { 0.0,  1.0,  0.0,  0.0,  5.0,  0.0 }, -- roll
            { 0.0,  0.0,  1.0,  0.0,  0.0,  3.0 }  -- yaw
        }

        local B_dagger = profile_exporter.compute_pseudo_inverse(B_6x6)
        assert_not_nil(B_dagger)
        assert_eq(#B_dagger, 6)
        assert_eq(#B_dagger[1], 6)

        -- Compute product P = B * B_dagger
        local P = mat_mult(B_6x6, B_dagger)
        assert_eq(#P, 6)
        assert_eq(#P[1], 6)

        for i = 1, 6 do
            for j = 1, 6 do
                local expected = (i == j) and 1.0 or 0.0
                assert_near(P[i][j], expected, 1e-3)
            end
        end

        -- Test underdetermined 6 x 12 matrix (4 vector thrusters with T, gx, gy)
        local B_6x12 = {
            -- T1, gx1, gy1,  T2, gx2, gy2,  T3, gx3, gy3,  T4, gx4, gy4
            { 0,   0,   8,    0,   0,   8,    0,   0,   8,    0,   0,   8 }, -- surge
            { 0,   8,   0,    0,   8,   0,    0,   8,   0,    0,   8,   0 }, -- sway
            { 1,   0,   0,    1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- heave
            {-1,   0,   0,   -1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- pitch
            { 1,   0,   0,   -1,   0,   0,    1,   0,   0,   -1,   0,   0 }, -- roll
            { 0,   2,  -2,    0,   2,   2,    0,  -2,  -2,    0,  -2,   2 }  -- yaw
        }

        local B_dagger_12 = profile_exporter.compute_pseudo_inverse(B_6x12)
        assert_not_nil(B_dagger_12)
        assert_eq(#B_dagger_12, 12)
        assert_eq(#B_dagger_12[1], 6)

        local P_12 = mat_mult(B_6x12, B_dagger_12)
        assert_eq(#P_12, 6)
        assert_eq(#P_12[1], 6)

        for i = 1, 6 do
            for j = 1, 6 do
                local expected = (i == j) and 1.0 or 0.0
                assert_near(P_12[i][j], expected, 1e-3)
            end
        end

        -- Singularity test: singular matrix returns nil and error
        local B_singular = {
            { 1, 0, 0, 0, 0, 0 },
            { 1, 0, 0, 0, 0, 0 }, -- duplicate row -> singular B * B^T
            { 0, 0, 1, 0, 0, 0 },
            { 0, 0, 0, 1, 0, 0 },
            { 0, 0, 0, 0, 1, 0 },
            { 0, 0, 0, 0, 0, 1 }
        }
        local inv_sing, err = profile_exporter.compute_pseudo_inverse(B_singular)
        assert_nil(inv_sing)
        assert_not_nil(err)
    end)

    it("evaluates ADVANCED_VTOL controllability and exports profile with matrices", function()
        local B_6x12 = {
            -- T1, gx1, gy1,  T2, gx2, gy2,  T3, gx3, gy3,  T4, gx4, gy4
            { 0,   0,   8,    0,   0,   8,    0,   0,   8,    0,   0,   8 }, -- surge
            { 0,   8,   0,    0,   8,   0,    0,   8,   0,    0,   8,   0 }, -- sway
            { 1,   0,   0,    1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- heave
            {-1,   0,   0,   -1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- pitch
            { 1,   0,   0,   -1,   0,   0,    1,   0,   0,   -1,   0,   0 }, -- roll
            { 0,   2,  -2,    0,   2,   2,    0,  -2,  -2,    0,  -2,   2 }  -- yaw
        }
        local B_dagger = profile_exporter.compute_pseudo_inverse(B_6x12)

        -- Controllability evaluation for ADVANCED_VTOL
        local evalResult = controllability_checker.evaluate({}, "ADVANCED_VTOL", {}, nil, B_dagger, B_6x12)
        assert_not_nil(evalResult)
        assert_eq(evalResult.status, "FULL_6DOF_PASS")
        assert_true(evalResult.passed)

        -- Export profile with ADVANCED_VTOL metadata and matrices
        local profile = {
            profileId = "PROF-AIRCRAFT_01",
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            calibratedBy = "HANGAR_BAY_01",
            totalDryMass = 12000.0,
            controllabilityStatus = evalResult.status,
            controlEffectivenessMatrix = B_6x12,
            pseudoInverseMatrix = B_dagger,
            thrusterCoefficients = {}
        }

        local json = profile_exporter.serialize_profile(profile)
        assert_not_nil(json)
        assert_true(json:find('"airframeType"%s*:%s*"ADVANCED_VTOL"') ~= nil or json:find('"ADVANCED_VTOL"') ~= nil)
        assert_true(json:find('"isVectorVtol"%s*:%s*true') ~= nil or json:find('"isVectorVtol":true') ~= nil)

        local syncPkt = profile_exporter.build_sync_packet("AIRCRAFT_01", 1, profile)
        assert_eq(syncPkt.type, "MSG_PROFILE_SYNC")
        assert_eq(syncPkt.payload.airframeType, "ADVANCED_VTOL")
        assert_true(syncPkt.payload.isVectorVtol)
        assert_not_nil(syncPkt.payload.pseudoInverseMatrix)
    end)
end)
