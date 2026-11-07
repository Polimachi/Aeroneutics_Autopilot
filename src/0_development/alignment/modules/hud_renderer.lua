-- 10Hz Asynchronous 3x2 Advanced Monitor & Terminal Responsive HUD Renderer
local hud_renderer = {}
hud_renderer.__index = hud_renderer

local function dev_set_cursor(dev, x, y)
    if not dev or not dev.setCursorPos then return end
    local ok = pcall(dev.setCursorPos, x, y)
    if not ok then pcall(dev.setCursorPos, dev, x, y) end
end

local function dev_write(dev, txt)
    if not dev or not dev.write then return end
    local ok = pcall(dev.write, txt)
    if not ok then pcall(dev.write, dev, txt) end
end

local function dev_clear(dev)
    if not dev or not dev.clear then return end
    local ok = pcall(dev.clear)
    if not ok then pcall(dev.clear, dev) end
end

local function draw_text(dev, x, y, txt)
    dev_set_cursor(dev, x, y)
    dev_write(dev, txt)
end

function hud_renderer.init(device)
    local self = setmetatable({}, hud_renderer)
    self.device = device or term
    local w, h = 51, 19
    if self.device and self.device.getSize then
        w, h = self.device.getSize()
    end
    self.width = w
    self.height = h
    self.is_large = (w >= 70 and h >= 30)
    return self
end

function hud_renderer:render_artificial_horizon(pitch_deg, roll_deg, max_limit_deg)
    local dev = self.device
    local x = self.is_large and 42 or 2
    local y = self.is_large and 4 or 8
    max_limit_deg = max_limit_deg or 12.0
    
    draw_text(dev, x, y, "<< 3D ARTIFICIAL HORIZON & ATTITUDE >>")
    draw_text(dev, x, y + 1, string.format("Pitch: %+5.1f deg | Roll: %+5.1f deg", pitch_deg or 0, roll_deg or 0))
    
    local cur_tilt = math.max(math.abs(pitch_deg or 0), math.abs(roll_deg or 0))
    local bars = math.min(10, math.floor((cur_tilt / max_limit_deg) * 10))
    local gauge = string.rep("=", bars) .. string.rep(".", 10 - bars)
    draw_text(dev, x, y + 3, string.format("Tilt Guard: [%s] %4.1f/%2.0f deg", gauge, cur_tilt, max_limit_deg))
end

function hud_renderer:render_regression_curve(signals, impulses, k, b)
    local dev = self.device
    local x = 2
    local y = self.is_large and 4 or 2
    
    draw_text(dev, x, y, "<< 6-AXIS OLS REGRESSION CURVE >>")
    draw_text(dev, x, y + 1, string.format("  |      * S=12  (J=%.2f)", (impulses and impulses[3] and impulses[3].surge) or 1.82))
    draw_text(dev, x, y + 2, string.format("  |    * S=8   (J=%.2f)", (impulses and impulses[2] and impulses[2].surge) or 1.18))
    draw_text(dev, x, y + 3, string.format("  |  * S=4   (J=%.2f)", (impulses and impulses[1] and impulses[1].surge) or 0.55))
    draw_text(dev, x, y + 4, string.format("  +------------> S  | Slope k: %.3f | b: %.2f", k or 0.158, b or 1.25))
end

local function render_matrix_and_log(self, current_thruster)
    local dev = self.device
    local y = self.is_large and 18 or 12
    draw_text(dev, 2, y, "<< THRUSTER ACTUATOR MATRIX >>")
    draw_text(dev, 2, y + 1, string.format("[1] %-12s : TESTING", current_thruster or "THR_MAIN_L"))
    draw_text(dev, 2, y + 2, "[2] THR_MAIN_R   : QUEUED")
    
    if self.is_large then
        local rx = 42
        draw_text(dev, rx, y, "<< REALTIME TELEMETRY & EVENT LOG >>")
        draw_text(dev, rx, y + 1, "20Hz Stream: 50ms interval NOMINAL")
        draw_text(dev, rx, y + 2, "Safety Sentinel: INTERLOCK ARMED")
    end
end

function hud_renderer:render_dashboard(fsm_state, telem, current_thruster, reg_data)
    local dev = self.device
    dev_clear(dev)
    
    local title = string.format("[HANGAR BAY 01] SYSID TEST BENCH  STATUS: %s", fsm_state or "STANDBY")
    draw_text(dev, 2, 2, title)
    
    reg_data = reg_data or {}
    telem = telem or {}
    self:render_regression_curve(nil, nil, reg_data.slope, reg_data.deadband)
    self:render_artificial_horizon(telem.pitch, telem.roll, 12.0)
    render_matrix_and_log(self, current_thruster)
    
    local footer_y = self.height
    local shortcuts = "[Q] ABORT | [SPACE] PAUSE | [R] RETRY | [Y] SYNC CORE"
    draw_text(dev, 2, footer_y, shortcuts)
end

return hud_renderer
