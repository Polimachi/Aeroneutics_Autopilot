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
end)
