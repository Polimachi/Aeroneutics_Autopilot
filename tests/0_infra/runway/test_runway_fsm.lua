-- tests/0_infra/runway/test_runway_fsm.lua
local tactical_streamer = require("modules.tactical_streamer")
local runway_fsm = require("modules.runway_fsm")

describe("Runway FSM & GAC Slot / Wave-Off Lifecycle", function()
    local cfg = {
        facilityId = "RWY_09L",
        sectorId = 1,
        runwayIndex = 1,
        mobility = "DYNAMIC",
        channels = { tacticalChannel = 50211, sectorFacilityChannel = 50202 },
    }

    it("handles SLOT_ASSIGN -> APPROACH -> TOUCHDOWN (ROLLOUT) -> VACATED -> FREE", function()
        local st = tactical_streamer.create(cfg)
        local fsm = runway_fsm.create(cfg, st, true)
        assert_eq(fsm:get_state(), "IDLE")

        -- Reject incompatible QUADROTOR on CTOL runway
        local rej = fsm:handle_backbone_message({
            type = "MSG_ATC_SLOT_ASSIGN",
            payload = { facilityId = "RWY_09L", aircraftId = "QUAD_1", airframeType = "QUADROTOR" },
        }, 10.0)
        assert_eq(#rej, 1)
        assert_eq(rej[1].payload.status, "REJECTED")

        -- Accept FIXED_WING
        local acc = fsm:handle_backbone_message({
            type = "MSG_ATC_SLOT_ASSIGN",
            payload = { facilityId = "RWY_09L", aircraftId = "JET_01", airframeType = "FIXED_WING", slotDurationSec = 120 },
        }, 11.0)
        assert_eq(#acc, 1)
        assert_eq(acc[1].payload.status, "ACCEPTED")
        assert_eq(fsm:get_state(), "APPROACH_DYNAMIC")

        -- Touchdown -> ROLLOUT (OCCUPIED to GAC)
        local tdOut = fsm:handle_tactical_message({
            type = "MSG_RUNWAY_TOUCHDOWN",
            domainId = "JET_01",
            payload = { facilityId = "RWY_09L", touchdownSpeed = 24.5 },
        }, 20.0)
        assert_eq(fsm:get_state(), "ROLLOUT")
        assert_eq(#tdOut, 1)
        assert_eq(tdOut[1].payload.status, "OCCUPIED")

        -- Vacated -> IDLE (FREE to GAC)
        local vacOut = fsm:handle_tactical_message({
            type = "MSG_RUNWAY_VACATED",
            domainId = "JET_01",
            payload = { facilityId = "RWY_09L", runwayCleared = true, exitTaxiway = "TWY_A" },
        }, 30.0)
        assert_eq(fsm:get_state(), "IDLE")
        assert_eq(#vacOut, 1)
        assert_eq(vacOut[1].payload.status, "FREE")
    end)

    it("triggers WAVE_OFF and MSG_ABORT_APPROACH after 3.0s continuous DANGEROUS deck", function()
        local st = tactical_streamer.create(cfg)
        local fsm = runway_fsm.create(cfg, st, true)
        fsm:handle_backbone_message({
            type = "MSG_ATC_SLOT_ASSIGN",
            payload = { facilityId = "RWY_09L", aircraftId = "JET_01", airframeType = "WINGED_VTOL", slotDurationSec = 120 },
        }, 10.0)

        fsm:tick(0.05, 11.0, "DANGEROUS", true)
        assert_eq(fsm:get_state(), "APPROACH_DYNAMIC")
        local out = fsm:tick(0.05, 14.1, "DANGEROUS", true)
        assert_eq(fsm:get_state(), "WAVE_OFF")
        assert_eq(out[1].type, "MSG_ABORT_APPROACH")
        assert_eq(out[1].payload.reason, "DECK_UNSTABLE")
    end)
end)
