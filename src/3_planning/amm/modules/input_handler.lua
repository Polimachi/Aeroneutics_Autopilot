-- src/3_planning/amm/modules/input_handler.lua
-- AMM Modal Input Handler: NAV/HOTKEY mode vs CLI EDIT buffer mode
local input_handler = {}
input_handler.__index = input_handler

local HOTKEYS = {
    x = "ESTOP", X = "ESTOP",
    h = "HOLD",  H = "HOLD",
    r = "RTH",   R = "RTH",
    l = "LAND",  L = "LAND",
    a = "ARM",   A = "ARM",
    t = "TAKEOFF", T = "TAKEOFF",
}

function input_handler.new()
    local self = setmetatable({
        mode = "NAV", -- "NAV" | "CLI"
        buffer = "",
    }, input_handler)
    return self
end

function input_handler:set_mode(new_mode)
    self.mode = new_mode or "NAV"
    if self.mode == "NAV" then
        self.buffer = ""
    end
end

function input_handler:handle_ctrl_key(char_or_key)
    local ch = string.lower(tostring(char_or_key or ""))
    if ch == "x" then
        return { action = "ESTOP", reason = "CTRL_X_EMERGENCY" }
    end
    return nil
end

local function parse_cli_command(line)
    local trimmed = string.match(line or "", "^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    local parts = {}
    for part in string.gmatch(trimmed, "%S+") do
        table.insert(parts, part)
    end
    local cmd_name = table.remove(parts, 1)
    return {
        type = "COMMAND",
        name = string.lower(cmd_name),
        args = parts,
    }
end

function input_handler:handle_char(ch)
    if self.mode == "NAV" then
        if ch == "/" then
            self.mode = "CLI"
            self.buffer = ""
            return nil
        end
        local act = HOTKEYS[ch]
        if act then
            return { action = act, key = ch }
        end
        return nil
    elseif self.mode == "CLI" then
        self.buffer = self.buffer .. ch
        return nil
    end
end

function input_handler:handle_key(key_code)
    local k_enter = (keys and keys.enter) or 28
    local k_esc = (keys and keys.escape) or 256
    local k_bsp = (keys and keys.backSpace) or 14

    if self.mode == "NAV" then
        if key_code == k_enter then
            self.mode = "CLI"
            self.buffer = ""
        end
        return nil
    elseif self.mode == "CLI" then
        if key_code == k_esc then
            self:set_mode("NAV")
            return nil
        elseif key_code == k_bsp then
            if #self.buffer > 0 then
                self.buffer = string.sub(self.buffer, 1, -2)
            end
            return nil
        elseif key_code == k_enter then
            local cmd = parse_cli_command(self.buffer)
            self:set_mode("NAV")
            return cmd
        end
    end
    return nil
end

return input_handler
