-- tests/3_planning/amm/test_ui_renderer.lua
local ui_renderer = require("ui_renderer")

describe("AMM 51x19 Dual-Pane TUI Renderer", function()
    it("creates a 51x19 screen buffer initialized with spaces", function()
        local buf = ui_renderer.create_buffer(51, 19)
        assert_not_nil(buf)
        assert_eq(#buf.text, 19)
        assert_eq(#buf.fg, 19)
        assert_eq(#buf.bg, 19)
        assert_eq(string.len(buf.text[1]), 51)
        assert_eq(string.len(buf.fg[1]), 51)
        assert_eq(string.len(buf.bg[1]), 51)
    end)

    it("renders header, HUD pane, queue pane, and footer correctly", function()
        local buf = ui_renderer.create_buffer(51, 19)
        local mfd_state = {
            fsmState = "CRUISE",
            attitude = { pitch = 2.5, roll = -1.2, heading = 90.0 },
            dynamics = { altitudeY = 150.0, verticalSpeed = 0.1, groundSpeed = 18.0 },
            fuel = 0.85,
            activeSource = "FCP"
        }
        local queue_data = {
            state = "EN_ROUTE",
            active_index = 1,
            items = {
                { id = 1, x = 100, z = 200, alt = 150, speed = 18, completed = false },
                { id = 2, x = 300, z = 400, alt = 160, speed = 20, completed = false, facilityId = "PAD_01" },
            },
            arrivalRadius = 15.0
        }
        local app_state = {
            domainId = "AIRCRAFT_01",
            authority = "PILOT_PRIMARY",
            banner = "MISSION EN ROUTE",
            input_mode = "NAV",
            input_buffer = ""
        }

        ui_renderer.render_screen(buf, mfd_state, queue_data, app_state)

        -- Check row 1 has domainId and fsmState
        assert_true(string.find(buf.text[1], "AIRCRAFT_01") ~= nil)
        assert_true(string.find(buf.text[1], "CRUISE") ~= nil)

        -- Check row 2 has divider
        assert_true(string.find(buf.text[2], "+") ~= nil)

        -- Check left pane has altitude and heading
        assert_true(string.find(buf.text[6], "150.0") ~= nil)

        -- Check right pane has waypoint item
        local found_wp = false
        for r = 4, 10 do
            if string.find(buf.text[r], "100") then found_wp = true break end
        end
        assert_true(found_wp)

        -- Check status banner and footer
        assert_true(string.find(buf.text[17], "MISSION EN ROUTE") ~= nil)
        assert_true(string.find(buf.text[18], "STOP") ~= nil)
        assert_true(string.find(buf.text[19], "CMD>") ~= nil)
    end)

    it("flushes rows via term.blit without throwing errors", function()
        local buf = ui_renderer.create_buffer(51, 19)
        local blit_rows = {}
        local mock_term = {
            setCursorPos = function(x, y) end,
            blit = function(t, f, b)
                table.insert(blit_rows, { t = t, f = f, b = b })
            end
        }
        ui_renderer.flush_buffer(buf, mock_term)
        assert_eq(#blit_rows, 19)
        assert_eq(string.len(blit_rows[1].t), 51)
    end)
end)
