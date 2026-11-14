-- Unit test suite for VAS ADVANCED_VTOL allocation & policy
local vehicle_policy = require("vehicle_policy")
local thrust_mixer = require("thrust_mixer")
local actuator_adapter_tca = require("actuator_adapter_tca")
local core_daemon = require("core_daemon")

local B_6x12 = {
    -- T1, gx1, gy1,  T2, gx2, gy2,  T3, gx3, gy3,  T4, gx4, gy4
    { 0,   0,   8,    0,   0,   8,    0,   0,   8,    0,   0,   8 }, -- surge (row 1)
    { 0,   8,   0,    0,   8,   0,    0,   8,   0,    0,   8,   0 }, -- sway (row 2)
    { 1,   0,   0,    1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- heave (row 3)
    {-1,   0,   0,   -1,   0,   0,    1,   0,   0,    1,   0,   0 }, -- pitch (row 4)
    { 1,   0,   0,   -1,   0,   0,    1,   0,   0,   -1,   0,   0 }, -- roll (row 5)
    { 0,   2,  -2,    0,   2,   2,    0,  -2,  -2,    0,  -2,   2 }  -- yaw (row 6)
}

local B_DAGGER_12x6 = {
    -- surge, sway, heave, pitch, roll, yaw
    { 0.0,      0.0,      0.25, -0.25,  0.25,  0.0     }, -- T1
    { 0.0,      0.03125,  0.0,   0.0,    0.0,   0.0625  }, -- gx1
    { 0.03125,  0.0,      0.0,   0.0,    0.0,  -0.0625  }, -- gy1
    { 0.0,      0.0,      0.25, -0.25, -0.25,  0.0     }, -- T2
    { 0.0,      0.03125,  0.0,   0.0,    0.0,   0.0625  }, -- gx2
    { 0.03125,  0.0,      0.0,   0.0,    0.0,   0.0625  }, -- gy2
    { 0.0,      0.0,      0.25,  0.25,  0.25,  0.0     }, -- T3
    { 0.0,      0.03125,  0.0,   0.0,    0.0,  -0.0625  }, -- gx3
    { 0.03125,  0.0,      0.0,   0.0,    0.0,  -0.0625  }, -- gy3
    { 0.0,      0.0,      0.25,  0.25, -0.25,  0.0     }, -- T4
    { 0.0,      0.03125,  0.0,   0.0,    0.0,  -0.0625  }, -- gx4
    { 0.03125,  0.0,      0.0,   0.0,    0.0,   0.0625  }  -- gy4
}

describe("vas advanced_vtol allocation & policy", function()
    it("recognizes ADVANCED_VTOL as pure thruster VTOL in vehicle_policy", function()
        local pol = vehicle_policy.init({ vehicleType = "ADVANCED_VTOL" })
        assert_eq(pol.vehicleType, "ADVANCED_VTOL")

        -- Flap target strictly 0.0 regardless of commanded flap
        local flap = vehicle_policy.resolve_flap_target(pol, { flapTarget = 0.8 }, 15.0, {})
        assert_eq(flap, 0.0, "flapTarget must be 0.0 for ADVANCED_VTOL")

        -- Transition alpha strictly 0.0
        local alpha = vehicle_policy.compute_transition_weights(pol, 25.0)
        assert_eq(alpha, 0.0, "transitionAlpha must be 0.0 for ADVANCED_VTOL")

        -- Stall guard bypassed
        local cmd = { collectiveThrust = 0.2, targetQuaternion = { w = 1, x = 0, y = 0, z = 0 } }
        local telem = { airspeed = 2.0, sensorHealth = { isAirspeedValid = true, isVelocityValid = true, velocity = true } }
        vehicle_policy.apply_stall_guard(pol, telem, cmd)
        assert_eq(cmd.collectiveThrust, 0.2, "Stall guard must not override collectiveThrust for ADVANCED_VTOL")
    end)

    it("loads pseudoInverseMatrix in thrust_mixer and allocates 6-DoF vector thrust", function()
        local profile = {
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            controlEffectivenessMatrix = B_6x12,
            pseudoInverseMatrix = B_DAGGER_12x6,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" }
        }

        local mixerState = thrust_mixer.init(profile)
        assert_true(mixerState.isVectorVtol)
        assert_not_nil(mixerState.pseudoInverseMatrix)

        -- Heave demand 20.0 (T = 5 for each thruster), Surge demand 16.0 (gy = 0.5)
        local demand = {
            surge = 16.0,
            sway = 0.0,
            heave = 20.0,
            pitch = 0.0,
            roll = 0.0,
            yaw = 0.0
        }

        local outputs = thrust_mixer.allocate_vector_vtol(mixerState, demand)
        assert_not_nil(outputs)
        assert_not_nil(outputs.THR_VEC_1)
        assert_not_nil(outputs.THR_VEC_2)
        assert_not_nil(outputs.THR_VEC_3)
        assert_not_nil(outputs.THR_VEC_4)

        -- Verify polymorphic structure
        assert_eq(type(outputs.THR_VEC_1), "table")
        assert_eq(outputs.THR_VEC_1.thrust, 5)
        assert_near(outputs.THR_VEC_1.gimbalX, 0.0, 1e-4)
        assert_near(outputs.THR_VEC_1.gimbalY, 0.5, 1e-4)

        -- Verify thrust_mixer.mix also dispatches to allocate_vector_vtol when vector VTOL
        local mixed = thrust_mixer.mix(mixerState, demand)
        assert_eq(type(mixed.THR_VEC_1), "table")
        assert_eq(mixed.THR_VEC_1.thrust, 5)
    end)

    it("clamps gimbals and tags directional anti-windup when surge demand saturates", function()
        local profile = {
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            controlEffectivenessMatrix = B_6x12,
            pseudoInverseMatrix = B_DAGGER_12x6,
            vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" }
        }

        local mixerState = thrust_mixer.init(profile)

        -- Large surge demand 40.0 pushes gy to 40 * 0.03125 = 1.25 -> clamped to 1.0
        local demand = {
            surge = 40.0,
            sway = 0.0,
            heave = 20.0,
            pitch = 0.0,
            roll = 0.0,
            yaw = 0.0
        }

        local outputs, satStatus = thrust_mixer.allocate_vector_vtol(mixerState, demand)
        assert_eq(outputs.THR_VEC_1.gimbalY, 1.0)
        assert_not_nil(satStatus)
        assert_true(satStatus.axisSaturatedPos.surge, "Positive surge must be marked saturated")
        assert_false(satStatus.axisSaturatedNeg.surge, "Negative surge must not be saturated")
    end)

    it("falls back to linear scalar mixer with warning when pseudoInverseMatrix is missing", function()
        local profile = {
            airframeType = "ADVANCED_VTOL",
            isVectorVtol = true,
            thrusterCoefficients = {
                THR_MAIN = { surge = 1.0, heave = 0.5, deadband = 1, maxThrust = 15 }
            }
        }
        local mixerState = thrust_mixer.init(profile)
        assert_true(mixerState.isVectorVtol)
        assert_nil(mixerState.pseudoInverseMatrix)

        local demand = { surge = 10.0, heave = 5.0 }
        local outputs = thrust_mixer.mix(mixerState, demand)
        assert_not_nil(outputs.THR_MAIN)
        assert_eq(type(outputs.THR_MAIN), "number")
    end)

    it("transmits polymorphic outputs in MSG_THRUST_CMD and suppresses MSG_AERO_CMD in core_daemon", function()
        local wirelessModem = mock.modem({ wireless = true })
        mock.peripheral_registry({
            top = { type = "modem", dev = wirelessModem },
            bottom = { type = "altitude_sensor", dev = mock.avionics_altitude({ altitude = 100.0, verticalSpeed = 0.0 }) },
            left = { type = "velocity_sensor", dev = mock.avionics_velocity({ vx = 5.0, vy = 0.0, vz = 0.0 }) },
            right = { type = "fuel", dev = mock.fuel_tank(500, 1000) }
        })

        local daemonState = core_daemon.init({
            system = {
                vehicleType = "ADVANCED_VTOL",
                aircraftDomainId = "AIRCRAFT_01",
                baseChannel = 10000,
                isVectorVtol = true
            },
            thrusters = {
                airframeType = "ADVANCED_VTOL",
                isVectorVtol = true,
                controlEffectivenessMatrix = B_6x12,
                pseudoInverseMatrix = B_DAGGER_12x6,
                vectorGroupOrder = { "THR_VEC_1", "THR_VEC_2", "THR_VEC_3", "THR_VEC_4" },
                isStaticFallback = false
            },
            surfaces = { surfaceGeometry = { AIL_L = { axis = "pitch", sign = 1.0 } } },
            sensors = { roles = { altitude = { preferredSide = "bottom", peripheralType = "altitude_sensor" } } },
            pid = {}
        })

        -- Arm daemon to NORMAL state
        daemonState.fsm.currentState = "NORMAL"

        wirelessModem._transmitted = {}
        core_daemon.tick(daemonState)

        local sentThrustPkt = nil
        local sentAero = false
        for _, tx in ipairs(wirelessModem._transmitted) do
            if tx.pkt.type == "MSG_THRUST_CMD" then sentThrustPkt = tx.pkt end
            if tx.pkt.type == "MSG_AERO_CMD" then sentAero = true end
        end

        assert_not_nil(sentThrustPkt, "MSG_THRUST_CMD must be transmitted")
        assert_false(sentAero, "MSG_AERO_CMD must NOT be transmitted for ADVANCED_VTOL")

        -- Verify polymorphic output format in packet payload
        local outs = sentThrustPkt.payload and sentThrustPkt.payload.outputs
        assert_not_nil(outs, "outputs must be present in MSG_THRUST_CMD payload")
        assert_not_nil(outs.THR_VEC_1, "THR_VEC_1 must be in outputs")
        assert_eq(type(outs.THR_VEC_1), "table", "THR_VEC_1 must be a polymorphic table { thrust, gimbalX, gimbalY }")
        assert_not_nil(outs.THR_VEC_1.thrust)
        assert_not_nil(outs.THR_VEC_1.gimbalX)
        assert_not_nil(outs.THR_VEC_1.gimbalY)
    end)
end)
