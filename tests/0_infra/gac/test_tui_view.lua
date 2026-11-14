-- tests/0_infra/gac/test_tui_view.lua
local tui_view = require("tui_view")

describe("GAC 3-tab TUI view and operator controls", function()
    local mockTerm = {
        getSize = function() return 51, 19 end,
        clear = function() end,
        setCursorPos = function(x, y) end,
        setTextColor = function(c) end,
        setBackgroundColor = function(c) end,
        write = function(text) end
    }

    it("initializes with Tab 1 active and switches tabs via method or key", function()
        local tui = tui_view.create(mockTerm)
        assert_eq(tui.activeTab, 1)
        
        tui:handle_key(keys.two, "2", {})
        assert_eq(tui.activeTab, 2)
        
        tui:handle_key(keys.three, "3", {})
        assert_eq(tui.activeTab, 3)
    end)

    it("dispatches operator action events: Maint, Free, Emergency", function()
        local tui = tui_view.create(mockTerm)
        tui.activeTab = 2
        tui.selectedFacilityIndex = 1
        
        local actM, dataM = tui:handle_key(keys.m, "m", {})
        assert_eq(actM, "TOGGLE_MAINTENANCE")
        
        local actF, dataF = tui:handle_key(keys.f, "f", {})
        assert_eq(actF, "FORCE_FREE")
        
        local actE, dataE = tui:handle_key(keys.e, "e", {})
        assert_eq(actE, "TOGGLE_EMERGENCY")
    end)

    it("translates touch events on tab header to tab change", function()
        local tui = tui_view.create(mockTerm)
        -- Tab bar is at Y=2: [1: OVERVIEW] is at X=1~15, [2: FACILITIES] at X=18~32
        local act, data = tui:handle_touch(20, 2, {})
        assert_eq(tui.activeTab, 2)
    end)

    it("manages circular log buffer up to 50 items", function()
        local tui = tui_view.create(mockTerm)
        for i = 1, 60 do
            tui:add_log("Log message " .. i)
        end
        assert_eq(#tui.logs, 50)
        assert_eq(tui.logs[#tui.logs], "Log message 60")
    end)

    it("formats DED/PUBLIC badges and renders Tab 2 with Cyan highlight for dedicated facilities", function()
        local badge1, isDed1 = tui_view.format_dedicated_badge({ facilityId = "P1", dedicatedCraftIds = { "VTOL_01" } })
        assert_eq(badge1, "[DED: VTOL_01]")
        assert_true(isDed1)

        local badge2, isDed2 = tui_view.format_dedicated_badge({ facilityId = "P2", dedicatedAirframeTypes = "DRONE" })
        assert_eq(badge2, "[DED: DRONE]")
        assert_true(isDed2)

        local badge3, isDed3 = tui_view.format_dedicated_badge({ facilityId = "P3" })
        assert_eq(badge3, "PUBLIC")
        assert_false(isDed3)

        local writtenLines = {}
        local usedColors = {}
        local captureTerm = {
            getSize = function() return 51, 19 end,
            clear = function() end,
            setCursorPos = function(x, y) end,
            setTextColor = function(c) table.insert(usedColors, c) end,
            setBackgroundColor = function(c) end,
            write = function(text) table.insert(writtenLines, tostring(text)) end
        }
        local tui = tui_view.create(captureTerm)
        tui:set_active_tab(2)
        tui.selectedFacilityIndex = 1 -- Select row 1 so row 2 is unselected dedicated
        tui:render({
            config = { sectorId = "ALPHA", baseSecChannel = 50201 },
            facilities = {
                { facilityId = "PAD_01", type = "LANDING_PAD", status = "FREE", tacticalChannel = 50211 },
                { facilityId = "PAD_02", type = "LANDING_PAD", status = "FREE", tacticalChannel = 50212, dedicatedCraftIds = "VTOL_01" }
            }
        })

        local joined = table.concat(writtenLines, "\n")
        assert_true(string.find(joined, "PUBLIC", 1, true) ~= nil)
        assert_true(string.find(joined, "[DED: VTOL_01]", 1, true) ~= nil)

        local hasCyan = false
        for _, col in ipairs(usedColors) do
            if col == colors.cyan then hasCyan = true break end
        end
        assert_true(hasCyan)
    end)

    it("dispatches ADD_FACILITY, DELETE_FACILITY, and EDIT_DEDICATED keys and applies operator mutations", function()
        local tui = tui_view.create(mockTerm)
        tui.activeTab = 2
        tui.selectedFacilityIndex = 2

        local actA = tui:handle_key(keys.a, "a", {})
        assert_eq(actA, "ADD_FACILITY")

        local actD, idxD = tui:handle_key(keys.d, "d", {})
        assert_eq(actD, "DELETE_FACILITY")
        assert_eq(idxD, 2)

        local actP, idxP = tui:handle_key(keys.p, "p", {})
        assert_eq(actP, "EDIT_DEDICATED")
        assert_eq(idxP, 2)
    end)

    it("supports non-blocking ADD_FACILITY and EDIT_DEDICATED inline prompts", function()
        local tui = tui_view.create(mockTerm)
        tui:open_prompt("ADD_FACILITY")
        for c in string.gmatch("PAD_03,50213,10,65,20,VIP_01", ".") do
            tui:handle_key(nil, c, {})
        end
        local actAdd, fac = tui:handle_key(keys.enter, nil, {})
        assert_eq(actAdd, "ADD_FACILITY")
        assert_eq(fac.facilityId, "PAD_03")
        assert_eq(fac.tacticalChannel, 50213)
        assert_eq(fac.dedicatedCraftIds, "VIP_01")

        tui:open_prompt("EDIT_DEDICATED", 1)
        for c in string.gmatch("V1,V2|DRONE", ".") do
            tui:handle_key(nil, c, {})
        end
        local actEdit, idx, payload = tui:handle_key(keys.enter, nil, {})
        assert_eq(actEdit, "EDIT_DEDICATED")
        assert_eq(idx, 1)
        assert_eq(payload.dedicatedCraftIds[2], "V2")
        assert_eq(payload.dedicatedAirframeTypes[1], "DRONE")
    end)

    it("handles Enter and S hotkeys in Tab 2", function()
        local tui = tui_view.create(mockTerm)
        tui.activeTab = 2
        tui.selectedFacilityIndex = 1

        local actEnter, idxEnter = tui:handle_key(keys.enter, nil, {})
        assert_eq(actEnter, "SELECT_FACILITY")
        assert_eq(idxEnter, 1)

        local actSave = tui:handle_key(keys.s, "s", {})
        assert_eq(actSave, "SAVE_CONFIG")
    end)
end)
