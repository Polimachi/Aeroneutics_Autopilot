-- tests/0_infra/gcs/test_c2_commander.lua
local c2_commander = require("c2_commander")

describe("GCS C2 commander and emergency generator", function()
    it("validates command types against allowlist", function()
        assert_true(c2_commander.is_valid_command("ARM"))
        assert_true(c2_commander.is_valid_command("DISARM"))
        assert_true(c2_commander.is_valid_command("TAKEOFF"))
        assert_true(c2_commander.is_valid_command("CRUISE"))
        assert_true(c2_commander.is_valid_command("HOLD"))
        assert_true(c2_commander.is_valid_command("RTH"))
        assert_true(c2_commander.is_valid_command("LAND"))
        assert_true(c2_commander.is_valid_command("WAYPOINT"))

        assert_false(c2_commander.is_valid_command("INVALID_CMD"))
        assert_false(c2_commander.is_valid_command(""))
        assert_false(c2_commander.is_valid_command(nil))
    end)

    it("creates standard operator commands with GCS_OVERRIDE authority", function()
        local payload, err = c2_commander.create_operator_cmd("TAKEOFF", "AIRCRAFT_01", { altitude = 100.0 })
        assert_nil(err)
        assert_not_nil(payload)
        assert_eq(payload.targetCraft, "AIRCRAFT_01")
        assert_eq(payload.authority, "GCS_OVERRIDE")
        assert_eq(payload.command, "TAKEOFF")
        assert_eq(payload.params.altitude, 100.0)

        -- Default empty params when nil
        local payload_arm = c2_commander.create_operator_cmd("ARM", "AIRCRAFT_02")
        assert_eq(payload_arm.command, "ARM")
        assert_eq(payload_arm.authority, "GCS_OVERRIDE")
        assert_not_nil(payload_arm.params)
    end)

    it("rejects invalid commands or missing target craft", function()
        local p1, err1 = c2_commander.create_operator_cmd("UNKNOWN", "AIRCRAFT_01")
        assert_nil(p1)
        assert_not_nil(err1)

        local p2, err2 = c2_commander.create_operator_cmd("LAND", nil)
        assert_nil(p2)
        assert_not_nil(err2)
    end)

    it("creates emergency E_STOP override payload", function()
        local estop = c2_commander.create_emergency_estop("AIRCRAFT_01", "MANUAL_ABORT")
        assert_not_nil(estop)
        assert_eq(estop.source, "GCS")
        assert_eq(estop.action, "E_STOP")
        assert_eq(estop.targetCraft, "AIRCRAFT_01")
        assert_eq(estop.reason, "MANUAL_ABORT")

        -- Default reason when omitted
        local estop_def = c2_commander.create_emergency_estop("AIRCRAFT_02")
        assert_eq(estop_def.reason, "OPERATOR_HARD_STOP")
    end)
end)
