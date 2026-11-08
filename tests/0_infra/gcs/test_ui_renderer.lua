-- tests/0_infra/gcs/test_ui_renderer.lua
local ui_renderer = require("ui_renderer")

describe("GCS 51x19 dual-pane TUI console renderer", function()
    it("creates a 51x19 buffer filled with empty lines", function()
        local buf = ui_renderer.create_buffer(51, 19)
        assert_not_nil(buf)
        assert_not_nil(buf.text)
        assert_eq(#buf.text, 19)
        assert_eq(#buf.text[1], 51)
        assert_eq(#buf.fg[1], 51)
        assert_eq(#buf.bg[1], 51)
    end)

    it("renders header with active target and fleet count", function()
        local buf = ui_renderer.create_buffer(51, 19)
        local active_craft = {
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            blockId = 1,
            isStale = false,
            telemetry = {
                attitude = { pitch = 2.5, roll = -0.5, heading = 180.0 },
                dynamics = { altitudeY = 125.4, verticalSpeed = 0.5, groundSpeed = 16.2 },
                fuel = 0.82,
                fsmState = "CRUISE",
                actuatorHealth = { tap = true, asa = true, allOk = true }
            }
        }
        local fleet_summary = {
            { domainId = "AIRCRAFT_01", baseChannel = 10000, blockId = 1, fsmState = "CRUISE", isStale = false },
            { domainId = "AIRCRAFT_02", baseChannel = 10040, blockId = 2, fsmState = "HOLD", isStale = false }
        }

        ui_renderer.render_screen(buf, active_craft, fleet_summary, "ALL SYSTEMS NOMINAL")

        -- Row 1: Header
        local line1 = buf.text[1]
        assert_eq(#line1, 51)
        assert_true(string.find(line1, "GCS CH50000") ~= nil, "Header must show GCS CH50000")
        assert_true(string.find(line1, "CRAFTS: 2") ~= nil, "Header must show fleet count")
        assert_true(string.find(line1, "TARGET: AIRCRAFT_01") ~= nil, "Header must show active target")

        -- Row 4..12: Left HUD contains attitude/alt/fuel/fsm
        local line4 = buf.text[4]
        assert_true(string.find(line4, "AIRCRAFT_01") ~= nil)
        local line5 = buf.text[5]
        assert_true(string.find(line5, "CRUISE") ~= nil)

        -- Row 17: Status
        local line17 = buf.text[17]
        assert_true(string.find(line17, "ALL SYSTEMS NOMINAL") ~= nil)

        -- Row 18: C2 guide
        local line18 = buf.text[18]
        assert_true(string.find(line18, "[A]rm", 1, true) ~= nil)
        assert_true(string.find(line18, "[X]E-Stop", 1, true) ~= nil)

        -- Row 19: Nav guide
        local line19 = buf.text[19]
        assert_true(string.find(line19, "[Tab]NextCraft", 1, true) ~= nil)
    end)

    it("flushes buffer to term device using blit", function()
        local buf = ui_renderer.create_buffer(51, 19)
        local written_lines = {}
        local mock_term = {
            setCursorPos = function(x, y) end,
            blit = function(t, f, b)
                table.insert(written_lines, { text = t, fg = f, bg = b })
            end
        }

        ui_renderer.flush_buffer(buf, mock_term)
        assert_eq(#written_lines, 19)
        assert_eq(#written_lines[1].text, 51)
    end)
end)
