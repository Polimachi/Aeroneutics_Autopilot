-- src/0_infra/gac/modules/tui_view.lua
-- Dual-display 3-tab TUI view and interactive operator controls for GAC

local tui_view = {}

local function first_non_empty_entry(val)
    if type(val) == "string" and val ~= "" then
        return val
    elseif type(val) == "table" and #val > 0 and type(val[1]) == "string" and val[1] ~= "" then
        return val[1]
    end
    return nil
end

function tui_view.format_dedicated_badge(fac)
    if type(fac) ~= "table" then
        return "PUBLIC", false
    end
    local craftId = first_non_empty_entry(fac.dedicatedCraftIds)
    if craftId then
        return "[DED: " .. craftId .. "]", true
    end
    local airframeType = first_non_empty_entry(fac.dedicatedAirframeTypes)
    if airframeType then
        return "[DED: " .. airframeType .. "]", true
    end
    return "PUBLIC", false
end

local function short_facility_type(fType)
    if fType == "LANDING_PAD" or not fType then
        return "PAD"
    elseif fType == "DOCKING_ARM" then
        return "DOCK"
    elseif fType == "RUNWAY" then
        return "RWY"
    end
    return tostring(fType):sub(1, 4)
end

local function split_csv(str)
    if type(str) ~= "string" then return nil end
    local out = {}
    for part in string.gmatch(str, "([^,]+)") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(out, trimmed)
        end
    end
    if #out == 0 then return nil end
    return out
end

local function parse_prompt_input(mode, buffer)
    if mode == "ADD_FACILITY" then
        local parts = {}
        for part in string.gmatch(buffer .. ",", "([^,]*),") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end
        local id = parts[1]
        if not id or id == "" then return nil end
        local dedVal = (parts[6] and parts[6] ~= "") and parts[6] or nil
        return {
            facilityId = id,
            type = "LANDING_PAD",
            tacticalChannel = tonumber(parts[2]) or 50211,
            maxSupportWeight = 30000.0,
            maxSupportRadius = 10.0,
            coordinates = {
                x = tonumber(parts[3]) or 0.0,
                y = tonumber(parts[4]) or 65.0,
                z = tonumber(parts[5]) or 0.0
            },
            status = "FREE",
            mobility = "STATIC",
            dedicatedCraftIds = dedVal
        }
    elseif mode == "EDIT_DEDICATED" then
        local craftPart, typePart = buffer:match("^([^|]*)|?(.*)$")
        return {
            dedicatedCraftIds = split_csv(craftPart),
            dedicatedAirframeTypes = split_csv(typePart)
        }
    end
    return nil
end

function tui_view.apply_operator_action(action, data, ctx, extraPayload)
    if type(ctx) ~= "table" or not ctx.inventory then
        return false, "MISSING_CONTEXT"
    end

    local inv = ctx.inventory
    local cfg = ctx.config
    local baseSec = (cfg and cfg.baseSecChannel) or 50201
    local domainId = (cfg and cfg.sectorId) or "GAC_NODE"

    local function get_time_ms()
        if os.epoch then return os.epoch("utc") end
        if os.time then return os.time() * 1000 end
        return 0
    end

    local function get_seq()
        return os.time and os.time() or 0
    end

    local function persist_and_sync(facId, status, craftId)
        if cfg and ctx.configLoader then
            cfg.facilities = inv:get_all_facilities()
            if ctx.configPath and ctx.configLoader.save_config then
                ctx.configLoader.save_config(ctx.configPath, cfg)
            end
        end
        if facId and ctx.modem and ctx.modem.transmit then
            ctx.modem.transmit(baseSec + 1, baseSec, {
                ver = "1.9.5",
                domainId = domainId,
                seq = get_seq(),
                type = "MSG_ATC_FACILITY_UPDATE",
                time = get_time_ms(),
                payload = {
                    facilityId = facId,
                    status = status,
                    currentCraft = craftId
                }
            })
        end
    end

    local function resolve_facility(indexOrId)
        if type(indexOrId) == "number" then
            return inv:get_all_facilities()[indexOrId]
        elseif type(indexOrId) == "string" then
            return inv:get_facility(indexOrId)
        end
        return nil
    end

    if action == "ADD_FACILITY" then
        if type(data) ~= "table" or not data.facilityId or data.facilityId == "" then
            return false, "INVALID_FACILITY_DATA"
        end
        local ok, err = inv:add_facility(data)
        if not ok then return false, err end
        if ctx.tui then ctx.tui:add_log("[OP] Added facility " .. tostring(data.facilityId)) end
        persist_and_sync()
        return true, nil
    elseif action == "DELETE_FACILITY" then
        local targetFac = resolve_facility(data)
        if not targetFac then return false, "FACILITY_NOT_FOUND" end
        local ok, err = inv:remove_facility(targetFac.facilityId)
        if not ok then return false, err end
        if ctx.tui then
            local count = #inv:get_all_facilities()
            if ctx.tui.selectedFacilityIndex > count and count > 0 then
                ctx.tui.selectedFacilityIndex = count
            end
            ctx.tui:add_log("[OP] Deleted facility " .. tostring(targetFac.facilityId))
        end
        persist_and_sync()
        return true, nil
    elseif action == "EDIT_DEDICATED" then
        local targetFac = resolve_facility(data)
        if not targetFac then return false, "FACILITY_NOT_FOUND" end
        if type(extraPayload) ~= "table" then return false, "INVALID_DEDICATED_PAYLOAD" end
        local ok, err = inv:update_dedicated(
            targetFac.facilityId,
            extraPayload.dedicatedCraftIds,
            extraPayload.dedicatedAirframeTypes
        )
        if not ok then return false, err end
        if ctx.tui then ctx.tui:add_log("[OP] Dedicated updated: " .. tostring(targetFac.facilityId)) end
        persist_and_sync()
        return true, nil
    elseif action == "TOGGLE_MAINTENANCE" then
        local targetFac = resolve_facility(data)
        if not targetFac then return false, "FACILITY_NOT_FOUND" end
        local nextStatus = (targetFac.status == "MAINTENANCE") and "FREE" or "MAINTENANCE"
        inv:update_status(targetFac.facilityId, nextStatus, nil)
        if ctx.tui then ctx.tui:add_log(string.format("[OP] %s status -> %s", targetFac.facilityId, nextStatus)) end
        persist_and_sync(targetFac.facilityId, nextStatus, nil)
        return true, nil
    elseif action == "FORCE_FREE" then
        local targetFac = resolve_facility(data)
        if not targetFac then return false, "FACILITY_NOT_FOUND" end
        inv:update_status(targetFac.facilityId, "FREE", nil)
        if ctx.tui then ctx.tui:add_log(string.format("[OP] %s FORCE FREE reset", targetFac.facilityId)) end
        persist_and_sync(targetFac.facilityId, "FREE", nil)
        return true, nil
    elseif action == "WAVE_OFF" then
        local targetFac = resolve_facility(data)
        if not targetFac then return false, "FACILITY_NOT_FOUND" end
        if targetFac.tacticalChannel and ctx.modem and ctx.modem.transmit then
            ctx.modem.transmit(targetFac.tacticalChannel, baseSec, {
                ver = "1.9.5",
                domainId = domainId,
                seq = get_seq(),
                type = "MSG_ABORT_APPROACH",
                time = get_time_ms(),
                payload = {
                    facilityId = targetFac.facilityId,
                    reason = "GAC_ORDER",
                    recommendedClimbAltitude = 100.0
                }
            })
        end
        inv:update_status(targetFac.facilityId, "GO_AROUND", nil)
        if ctx.tui then ctx.tui:add_log(string.format("[OP] Wave-off issued for %s", targetFac.facilityId)) end
        return true, nil
    elseif action == "TOGGLE_EMERGENCY" then
        local isEmg = not inv:is_emergency_lockdown()
        inv:set_emergency_lockdown(isEmg)
        if ctx.tui then
            ctx.tui:add_log(isEmg and "[OP] EMERGENCY LOCKDOWN ENGAGED!" or "[OP] Emergency lockdown disengaged.")
        end
        if isEmg and ctx.modem and ctx.modem.transmit then
            for _, fac in ipairs(inv:get_all_facilities()) do
                if fac.tacticalChannel then
                    ctx.modem.transmit(fac.tacticalChannel, baseSec, {
                        ver = "1.9.5",
                        domainId = domainId,
                        seq = get_seq(),
                        type = "MSG_ABORT_APPROACH",
                        time = get_time_ms(),
                        payload = {
                            facilityId = fac.facilityId,
                            reason = "GAC_ORDER",
                            recommendedClimbAltitude = 100.0
                        }
                    })
                end
            end
        end
        return true, nil
    end

    return false, "UNKNOWN_ACTION"
end

function tui_view.create(termDev, monitorDev)
    local termTarget = termDev or term
    local monTarget = monitorDev

    local view = {
        activeTab = 1,
        selectedFacilityIndex = 1,
        logs = {},
        prompt = nil
    }

    function view:open_prompt(mode, targetIdx)
        local label = (mode == "ADD_FACILITY")
            and "Add ID,CH,X,Y,Z[,DED]: "
            or "Ded Craft|Type (Enter): "
        self.prompt = {
            mode = mode,
            targetIdx = targetIdx,
            label = label,
            buffer = ""
        }
    end

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
            draw_text(dev, 2, 4, "ID     TYPE STATUS    DEDICATED      CRAFT   CH", colors.yellow, colors.black)
            draw_text(dev, 2, 5, string.rep("-", 50), colors.gray, colors.black)
            local facilities = state and state.facilities or {}
            local lineY = 6
            for idx, fac in ipairs(facilities) do
                if lineY > 17 then break end
                local isSelected = (idx == view.selectedFacilityIndex)
                local dedBadge, isDedicated = tui_view.format_dedicated_badge(fac)
                local fg = isSelected and colors.black or (isDedicated and colors.cyan or colors.white)
                local bg = isSelected and colors.lightGray or colors.black
                local facStatus = fac.status or "FREE"

                local rowText = string.format("%-6s %-4s %-9s %-14s %-7s %-5d",
                    tostring(fac.facilityId):sub(1, 6),
                    short_facility_type(fac.type),
                    facStatus:sub(1, 9),
                    dedBadge:sub(1, 14),
                    tostring(fac.currentCraft or "-"):sub(1, 7),
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

        if view.prompt then
            local promptLine = (view.prompt.label .. view.prompt.buffer .. "_"):sub(1, 50)
            draw_text(dev, 1, 18, promptLine, colors.black, colors.yellow)
        end

        -- Y=19: Shortcut Bar
        draw_text(dev, 1, 19, "[1-3]Tab [A]dd [D]el [P]Ded [M]nt [F]re [E]mg [Q]", colors.black, colors.lightGray)
    end

    function view:render(state)
        render_to_device(termTarget, state)
        if monTarget then
            render_to_device(monTarget, state)
        end
    end

    function view:handle_key(key, char, state)
        if self.prompt then
            if keys and key == keys.escape then
                self.prompt = nil
                return "PROMPT_CANCEL", nil
            elseif keys and key == keys.backspace then
                self.prompt.buffer = self.prompt.buffer:sub(1, math.max(0, #self.prompt.buffer - 1))
                return "PROMPT_INPUT", self.prompt.buffer
            elseif keys and key == keys.enter then
                local mode = self.prompt.mode
                local targetIdx = self.prompt.targetIdx
                local parsed = parse_prompt_input(mode, self.prompt.buffer)
                self.prompt = nil
                if mode == "ADD_FACILITY" and parsed then
                    return "ADD_FACILITY", parsed
                elseif mode == "EDIT_DEDICATED" and parsed then
                    return "EDIT_DEDICATED", targetIdx, parsed
                end
                return "PROMPT_CANCEL", nil
            elseif char and type(char) == "string" and #char == 1 then
                self.prompt.buffer = self.prompt.buffer .. char
                return "PROMPT_INPUT", self.prompt.buffer
            end
            return nil, nil
        end

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
        elseif key == keys.p or char == "p" or char == "P" then
            return "EDIT_DEDICATED", self.selectedFacilityIndex
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
