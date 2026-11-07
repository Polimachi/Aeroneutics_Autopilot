-- 300ms Fail-Safe Watchdog Sentinel & Pulse Cutoff for TCA
local watchdog_sentinel = {}
watchdog_sentinel.__index = watchdog_sentinel

function watchdog_sentinel.init(timeoutMs, onTimeoutCb)
    local inst = {
        timeoutMs = tonumber(timeoutMs) or 300, onTimeoutCb = onTimeoutCb,
        lastSeq = 0, lastFeedMs = 0, isExpired = false, pulseTimerId = nil, onPulseEndCb = nil,
        watchdogTimerId = nil, hasFed = false
    }
    return setmetatable(inst, watchdog_sentinel)
end

function watchdog_sentinel.new(timeoutMs)
    return watchdog_sentinel.init(timeoutMs, nil)
end

function watchdog_sentinel.start_timer(wd, sec)
    if not wd or not os or not os.startTimer then return nil end
    local s = math.max(0.05, tonumber(sec) or (wd.timeoutMs / 1000.0))
    wd.watchdogTimerId = os.startTimer(s)
    return wd.watchdogTimerId
end

function watchdog_sentinel.cancel_pulse(wd)
    if not wd then return end
    if wd.pulseTimerId and os and os.cancelTimer then
        pcall(os.cancelTimer, wd.pulseTimerId)
    end
    wd.pulseTimerId = nil
    wd.onPulseEndCb = nil
end

function watchdog_sentinel.is_pulse_active(wd)
    return wd and wd.pulseTimerId ~= nil
end

function watchdog_sentinel.feed(wd, seq, nowMs)
    if not wd then return false, "NO_SENTINEL" end
    local current = tonumber(nowMs) or ((os.epoch and os.epoch("utc")) or 0)
    local numSeq = tonumber(seq)
    if numSeq and wd.hasFed and numSeq == wd.lastSeq then
        return false, "DUPLICATE_SEQ"
    end
    wd.lastSeq = numSeq or (wd.lastSeq + 1)
    wd.lastFeedMs = current
    wd.isExpired = false
    wd.hasFed = true
    if not wd.watchdogTimerId and os and os.startTimer then
        wd:start_timer(wd.timeoutMs / 1000.0)
    end
    return true, nil
end

function watchdog_sentinel.is_expired(wd, nowMs)
    if not wd then return true end
    local current = tonumber(nowMs) or ((os.epoch and os.epoch("utc")) or 0)
    if wd.lastFeedMs == 0 then return false end
    if (current - wd.lastFeedMs) >= wd.timeoutMs then
        if not wd.isExpired then
            wd.isExpired = true
            if wd.onTimeoutCb then pcall(wd.onTimeoutCb) end
        end
        return true
    end
    return wd.isExpired
end

function watchdog_sentinel.get_remaining_ms(wd, nowMs)
    if not wd then return 0 end
    local current = tonumber(nowMs) or ((os.epoch and os.epoch("utc")) or 0)
    if wd.lastFeedMs == 0 then return wd.timeoutMs end
    local rem = wd.timeoutMs - (current - wd.lastFeedMs)
    return (rem < 0) and 0 or rem
end

function watchdog_sentinel.schedule_pulse(wd, durationMs, onPulseEndCb)
    if not wd then return nil end
    local sec = math.max(0.05, (tonumber(durationMs) or 300) / 1000.0)
    wd.onPulseEndCb = onPulseEndCb
    if os and os.startTimer then wd.pulseTimerId = os.startTimer(sec) end
    return wd.pulseTimerId
end

function watchdog_sentinel.handle_pulse(wd, pulseLevel, durationMs, adapterState)
    if not wd or not adapterState then return false end
    local ok_aa, mod_aa = pcall(require, "actuator_adapter")
    local aa = ok_aa and mod_aa or package.loaded["actuator_adapter"]
    local pLvl = tonumber(pulseLevel) or 0
    local dMs = tonumber(durationMs) or 0
    if pLvl <= 0 or dMs <= 0 then
        wd:cancel_pulse()
        if aa and aa.cut_thrust then aa.cut_thrust(adapterState) end
        return true
    end
    if aa and aa.apply_thrust then aa.apply_thrust(adapterState, pLvl, 1, 1) end
    wd:schedule_pulse(dMs, function()
        if aa and aa.cut_thrust then aa.cut_thrust(adapterState) end
    end)
    return true
end

function watchdog_sentinel.handle_timer(wd, timerId, nowMs)
    if not wd or not timerId then return false end
    if wd.pulseTimerId and timerId == wd.pulseTimerId then
        wd.pulseTimerId = nil
        if wd.onPulseEndCb then
            local cb = wd.onPulseEndCb
            wd.onPulseEndCb = nil
            pcall(cb)
            return true
        end
    end
    if wd.watchdogTimerId and timerId == wd.watchdogTimerId then
        wd.watchdogTimerId = nil
        local current = tonumber(nowMs) or ((os.epoch and os.epoch("utc")) or 0)
        if wd:is_expired(current) then
            wd:start_timer(wd.timeoutMs / 1000.0)
        else
            local rem = wd:get_remaining_ms(current)
            wd:start_timer(rem / 1000.0)
        end
        return true
    end
    return false
end

return watchdog_sentinel
