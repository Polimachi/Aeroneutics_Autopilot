-- Realtime safety sentinel and interlock monitor for Alignment
local safety_sentinel = {}
safety_sentinel.__index = safety_sentinel

function safety_sentinel.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({}, safety_sentinel)
    self.tilt_abort_deg = cfg.tiltAbortDeg or 12.0
    self.tilt_warn_deg = cfg.tiltWarnDeg or 8.0
    self.watchdog_timeout_ms = cfg.watchdogTimeoutMs or 300
    self.max_deadband = cfg.maxDeadband or 6.0
    self.min_r2_warning = cfg.minR2Warning or 0.85
    self.last_telemetry_ms = 0
    return self
end

function safety_sentinel:reset_watchdog(now_ms)
    self.last_telemetry_ms = now_ms or 0
end

function safety_sentinel:check_telemetry(telem, now_ms)
    telem = telem or {}
    local pitch = math.abs(telem.pitch or 0.0)
    local roll = math.abs(telem.roll or 0.0)
    
    if now_ms then
        self:reset_watchdog(now_ms)
    end
    
    if pitch > self.tilt_abort_deg or roll > self.tilt_abort_deg then
        return { status = "ABORT", reason = "TILT_HARD_LIMIT", pitch = pitch, roll = roll }
    end
    
    if pitch > self.tilt_warn_deg or roll > self.tilt_warn_deg then
        return { status = "PAUSE", reason = "TILT_SOFT_WARNING", pitch = pitch, roll = roll }
    end
    
    return { status = "OK", pitch = pitch, roll = roll }
end

function safety_sentinel:check_watchdog(now_ms)
    now_ms = now_ms or 0
    local elapsed = now_ms - self.last_telemetry_ms
    if elapsed >= self.watchdog_timeout_ms then
        return { status = "ABORT", reason = "TELEMETRY_WATCHDOG_TIMEOUT", elapsed_ms = elapsed }
    end
    return { status = "OK", elapsed_ms = elapsed }
end

function safety_sentinel:check_regression_anomaly(reg)
    reg = reg or {}
    local r2 = reg.confidenceR2 or 0.0
    local deadband = reg.deadband or 0.0
    
    if r2 < self.min_r2_warning or deadband > self.max_deadband then
        return { status = "PAUSE", reason = "REGRESSION_ANOMALY", r2 = r2, deadband = deadband }
    end
    return { status = "OK", r2 = r2, deadband = deadband }
end

return safety_sentinel
