-- tests/3_planning/amm/test_ui_renderer.lua
local ui_renderer = require("ui_renderer")

describe("AMM 51x19 Dual-Pane TUI Renderer (ui_renderer)", function()
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

    it("computes centered 6-row viewport windows across boundary indices", function()
        local s0, e0 = ui_renderer.compute_viewport(0, 1, 6)
        assert_eq(s0, 1)
        assert_eq(e0, 0)

        local s1, e1 = ui_renderer.compute_viewport(4, 3, 6)
        assert_eq(s1, 1)
        assert_eq(e1, 4)

        local s_mid, e_mid = ui_renderer.compute_viewport(10, 6, 6)
        assert_eq(e_mid - s_mid + 1, 6)
        assert_true(s_mid <= 6 and 6 <= e_mid)

        local s_end, e_end = ui_renderer.compute_viewport(10, 10, 6)
        assert_eq(s_end, 5)
        assert_eq(e_end, 10)
    end)

    it("renders mission_engine 6-row scroll viewport, O/*/! markers, 5-row condition progress, and clears stale reused buffer cells", function()
        local mission_engine = require("mission_engine")
        local buf = ui_renderer.create_buffer(51, 19)
        local eng = mission_engine.new({ config = { baseChannel = 10000 } })

        local cps = {}
        for i = 1, 10 do
            if i == 1 then
                cps[i] = { checkpointId = "CP_01", action = "TAKEOFF_LAUNCHPAD", params = { facilityId = "PAD_BRAVO", targetAlt = 150 } }
            elseif i == 5 then
                cps[i] = { checkpointId = "CP_05", action = "PAYLOAD_ACTION", params = { channelOffset = 20, command = "DROP" } }
            elseif i == 6 then
                cps[i] = {
                    checkpointId = "CP_06",
                    action = "ORBIT",
                    params = { targetPos = { x = 450, z = -1200 }, targetAlt = 150, cruiseSpeed = 18, radius = 40, direction = "CW", durationSec = 30 },
                }
            else
                cps[i] = { checkpointId = "CP_" .. i, action = "FLY_OVER", params = { targetPos = { x = i * 100, z = -100 }, acceptanceRadius = 20 } }
            end
        end
        assert_true(eng:load_table({ missionId = "SORTIE_LONG_NAME_99", executionMode = "REPEAT", checkpoints = cps }))
        eng.state = "EN_ROUTE"
        eng.active_index = 6
        eng.enteredAtMs = 1000
        eng.checkpoints[1].status = "COMPLETED"
        eng.checkpoints[5].status = "ABORTED"
        eng.checkpoints[6].status = "ACTIVE"

        local mfd = {
            fsmState = "LOITER",
            dynamics = { altitudeY = 148.5, verticalSpeed = 0.1, groundSpeed = 18.0 },
            navigation = { currentPos = { x = 350, z = -1100 } },
            attitude = { pitch = 1.0, roll = 0.0, heading = 90.0 },
            fuel = 0.82,
        }
        ui_renderer.render_screen(buf, mfd, eng, { domainId = "AIRCRAFT_01", authority = "PILOT_PRIMARY", banner = "OK", input_mode = "NAV", now_ms = 13000 })

        -- Every row must strictly have 51 characters across text, fg, and bg
        for y = 1, 19 do
            assert_eq(string.len(buf.text[y]), 51, "text width mismatch at row " .. y)
            assert_eq(string.len(buf.fg[y]), 51, "fg width mismatch at row " .. y)
            assert_eq(string.len(buf.bg[y]), 51, "bg width mismatch at row " .. y)
        end

        assert_true(string.find(buf.text[3], "(6/10)", 1, true) ~= nil)
        -- Scroll viewport shows CP 5 ('!' aborted) and CP 6 ('*' active) inside rows 4..9
        local found_abort, found_active = false, false
        for r = 4, 9 do
            local right_slice = string.sub(buf.text[r], 27, 51)
            if string.find(right_slice, "! 5:PAYLD", 1, true) or string.find(right_slice, "!5:PAYLD", 1, true) then
                found_abort = true
            end
            if string.find(right_slice, "* 6:ORBIT", 1, true) or string.find(right_slice, "*6:ORBIT", 1, true) then
                found_active = true
            end
        end
        assert_true(found_abort, "Expected aborted marker ! on CP 5")
        assert_true(found_active, "Expected active marker * on CP 6")

        -- 5-row active checkpoint detail panel (rows 11..15)
        assert_true(string.find(buf.text[11], "EN_ROUTE", 1, true) ~= nil)
        assert_true(string.find(buf.text[11], "REPEAT", 1, true) ~= nil)
        assert_true(string.find(buf.text[12], "ORBIT", 1, true) ~= nil)
        assert_true(string.find(buf.text[13], "DUR 12/30s", 1, true) ~= nil)
        assert_true(string.find(buf.text[14], "150", 1, true) ~= nil)
        assert_true(string.find(buf.text[15], "141.4", 1, true) ~= nil)

        -- Re-render a 1-checkpoint mission on the SAME buffer -> rows 5..9 must be cleared (no ghost rows from 10-cp mission)
        local eng_short = mission_engine.new({ config = { baseChannel = 10000 } })
        assert_true(eng_short:load_table({
            missionId = "SHORT",
            checkpoints = { { action = "FLY_TO", params = { x = 10, z = 20 } } },
        }))
        ui_renderer.render_screen(buf, mfd, eng_short, { domainId = "AIRCRAFT_01", authority = "PILOT_PRIMARY", banner = "SHORT", input_mode = "NAV", now_ms = 1000 })
        for r = 5, 9 do
            assert_eq(string.sub(buf.text[r], 27, 51), string.rep(" ", 25), "Ghost text leaked at row " .. r)
        end
    end)
end)
