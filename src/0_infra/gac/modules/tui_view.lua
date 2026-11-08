-- src/0_infra/gac/modules/tui_view.lua
-- Dual-display 3-tab TUI view and interactive operator controls for GAC

local tui_view = {}

function tui_view.create(termDev, monitorDev)
    local termTarget = termDev or term
    local monTarget = monitorDev

    local view = {
        activeTab = 1,
        selectedFacilityIndex = 1,
        logs = {}
    }

    function view:set_active_tab(tabIndex)
        if tabIndex >= 1 and tabIndex <= 3 then
            self.activeTab = tabIndex
        end
    end

    function view:add_log(entry)
        table.insert(self.logs, entry)
        if #self.logs > 50 then
            table.remove(self.logs, 1)
        end
    end

    local function draw_text(dev, x, y, text, fg, bg)
        if not dev or not dev.setCursorPos then return end
        dev.setCursorPos(x, y)
        if fg and dev.setTextColor then dev.setTextColor(fg) end
        if bg and dev.setBackgroundColor then dev.setBackgroundColor(bg) end
        dev.write(tostring(text))
    end

    local function render_to_device(dev, state)
        if not dev or not dev.getSize then return end
        local w, h = dev.getSize()
        if w < 51 or h < 19 then
            -- Fallback compact rendering if screen too small
            dev.clear()
            draw_text(dev, 1, 1, "GAC CONSOLE - SCREEN TOO SMALL (" .. w .. "x" .. h .. ")", colors.red, colors.black)
            return
        end

        dev.clear()

        local cfg = state and state.config or {}
        local wind = state and state.surfaceWind or { speed = 0, direction = 0 }
        local status = state and state.sectorStatus or "OPERATIONAL"

        -- Y=1: Header
        local statusColor = colors.green
        if status == "DECK_DANGEROUS" or status == "EMERGENCY_LOCKDOWN" then
            statusColor = colors.red
        elseif status == "MAINTENANCE" then
            statusColor = colors.yellow
        end

        draw_text(dev, 1, 1, "GAC | " .. tostring(cfg.sectorId or "SECTOR") .. " [" .. tostring(cfg.baseSecChannel or 50201) .. "]", colors.white, colors.blue)
        draw_text(dev, 30, 1, "WIND: " .. string.format("%d@%.1fm/s", wind.direction or 0, wind.speed or 0), colors.yellow, colors.blue)
        draw_text(dev, 46, 1, status:sub(1, 6), statusColor, colors.blue)

        -- Y=2: Tabs
        local t1Bg = (view.activeTab == 1) and colors.cyan or colors.gray
        local t2Bg = (view.activeTab == 2) and colors.cyan or colors.gray
        local t3Bg = (view.activeTab == 3) and colors.cyan or colors.gray
        draw_text(dev, 1, 2, " [1: OVERVIEW] ", colors.black, t1Bg)
        draw_text(dev, 18, 2, " [2: FACILITIES] ", colors.black, t2Bg)
        draw_text(dev, 36, 2, " [3: LOGS & COMMS] ", colors.black, t3Bg)

        -- Content area Y=3..18
        if view.activeTab == 1 then
            -- Tab 1: Overview
            local summary = state and state.summary or {}
            draw_text(dev, 2, 4, "=== SECTOR METRICS ===", colors.yellow, colors.black)
            draw_text(dev, 2, 5, "Total Pads: " .. tostring(summary.totalLandingPads or 0) .. "  | Free Pads: " .. tostring(summary.freeLandingPads or 0), colors.white, colors.black)
            draw_text(dev, 2, 6, "Max Weight: " .. string.format("%.0f kg", summary.maxSupportWeight or 0) .. " | Max Radius: " .. string.format("%.1f m", summary.maxSupportRadius or 0), colors.white, colors.black)
            draw_text(dev, 2, 7, "Tower ATC Channel: " .. tostring(cfg.towerAtcChannel or 50001), colors.white, colors.black)

            draw_text(dev, 2, 9, "=== ACTIVE TRAFFIC QUEUE ===", colors.yellow, colors.black)
            local traffic = state and state.traffic or {}
            local lineY = 10
            if #traffic == 0 then
                draw_text(dev, 4, lineY, "(No active aircraft in sector)", colors.gray, colors.black)
            else
                for idx, craft in ipairs(traffic) do
                    if lineY > 17 then break end
                    draw_text(dev, 4, lineY, string.format("#%d %s - %s [%s]", idx, craft.id or "?", craft.state or "?", craft.assignedPad or "NONE"), colors.white, colors.black)
                    lineY = lineY + 1
                end
            end
        elseif view.activeTab == 2 then
            -- Tab 2: Facilities
            draw_text(dev, 2, 4, "ID       TYPE         STATUS      CRAFT       CH", colors.yellow, colors.black)
            draw_text(dev, 2, 5, "---------------------------------------------------", colors.gray, colors.black)
            local facilities = state and state.facilities or {}
            local lineY = 6
            for idx, fac in ipairs(facilities) do
                if lineY > 17 then break end
                local isSelected = (idx == view.selectedFacilityIndex)
                local fg = isSelected and colors.black or colors.white
                local bg = isSelected and colors.lightGray or colors.black
                local facStatus = fac.status or "FREE"
                local statusFg = isSelected and colors.black or colors.green
                if facStatus == "OCCUPIED" then statusFg = isSelected and colors.black or colors.orange
                elseif facStatus == "RESERVED" then statusFg = isSelected and colors.black or colors.yellow
                elseif facStatus == "MAINTENANCE" or facStatus == "GO_AROUND" then statusFg = isSelected and colors.black or colors.red
                end

                local rowText = string.format("%-8s %-12s %-11s %-11s %-5d",
                    tostring(fac.facilityId):sub(1, 8),
                    tostring(fac.type or "PAD"):sub(1, 12),
                    facStatus:sub(1, 11),
                    tostring(fac.currentCraft or "-"):sub(1, 11),
                    fac.tacticalChannel or 0
                )
                draw_text(dev, 2, lineY, rowText, fg, bg)
                lineY = lineY + 1
            end
        elseif view.activeTab == 3 then
            -- Tab 3: Logs
            draw_text(dev, 2, 4, "=== RECENT AUDIT LOGS ===", colors.yellow, colors.black)
            local startIdx = math.max(1, #view.logs - 12)
            local lineY = 5
            for idx = startIdx, #view.logs do
                if lineY > 18 then break end
                draw_text(dev, 2, lineY, view.logs[idx]:sub(1, 48), colors.white, colors.black)
                lineY = lineY + 1
            end
        end

        -- Y=19: Shortcut Bar
        draw_text(dev, 1, 19, "[1-3]Tab [Up/Dn]Sel [M]aint [F]ree [W]ave [E]mg [Q]uit", colors.black, colors.lightGray)
    end

    function view:render(state)
        render_to_device(termTarget, state)
        if monTarget then
            render_to_device(monTarget, state)
        end
    end

    function view:handle_key(key, char, state)
        if key == keys.one or char == "1" then
            self.activeTab = 1
            return "SWITCH_TAB", 1
        elseif key == keys.two or char == "2" then
            self.activeTab = 2
            return "SWITCH_TAB", 2
        elseif key == keys.three or char == "3" then
            self.activeTab = 3
            return "SWITCH_TAB", 3
        elseif key == keys.up then
            if self.selectedFacilityIndex > 1 then
                self.selectedFacilityIndex = self.selectedFacilityIndex - 1
            end
            return "CURSOR_UP", self.selectedFacilityIndex
        elseif key == keys.down then
            local maxFacs = state and state.facilities and #state.facilities or 10
            if self.selectedFacilityIndex < maxFacs then
                self.selectedFacilityIndex = self.selectedFacilityIndex + 1
            end
            return "CURSOR_DOWN", self.selectedFacilityIndex
        elseif key == keys.m or char == "m" or char == "M" then
            return "TOGGLE_MAINTENANCE", self.selectedFacilityIndex
        elseif key == keys.f or char == "f" or char == "F" then
            return "FORCE_FREE", self.selectedFacilityIndex
        elseif key == keys.w or char == "w" or char == "W" then
            return "WAVE_OFF", self.selectedFacilityIndex
        elseif key == keys.e or char == "e" or char == "E" then
            return "TOGGLE_EMERGENCY", nil
        elseif key == keys.a or char == "a" or char == "A" then
            return "ADD_FACILITY", nil
        elseif key == keys.d or char == "d" or char == "D" then
            return "DELETE_FACILITY", self.selectedFacilityIndex
        elseif key == keys.q or char == "q" or char == "Q" then
            return "QUIT", nil
        end
        return nil, nil
    end

    function view:handle_touch(x, y, state)
        if y == 2 then
            if x >= 1 and x <= 16 then
                self.activeTab = 1
                return "SWITCH_TAB", 1
            elseif x >= 17 and x <= 33 then
                self.activeTab = 2
                return "SWITCH_TAB", 2
            elseif x >= 34 then
                self.activeTab = 3
                return "SWITCH_TAB", 3
            end
        elseif y >= 6 and y <= 18 and self.activeTab == 2 then
            local clickedIdx = y - 5
            self.selectedFacilityIndex = clickedIdx
            return "SELECT_FACILITY", clickedIdx
        end
        return nil, nil
    end

    return view
end

return tui_view
