-- Multi-Level Step Pulse Sequencer (S=4, 8, 12, 300ms)
local multi_pulse_sequencer = {}
local Sequencer = {}
Sequencer.__index = Sequencer

local DEFAULT_LEVELS = { 4, 8, 12 }
local DEFAULT_DURATION_MS = 300
local DEFAULT_MAX_TILT = 12.0

function multi_pulse_sequencer.new(craftDomainId, opts)
    opts = opts or {}
    local obj = {
        domainId = craftDomainId or "AIRCRAFT_01",
        levels = opts.levels or DEFAULT_LEVELS,
        durationMs = opts.durationMs or DEFAULT_DURATION_MS,
        maxTiltDeg = opts.maxTiltDeg or DEFAULT_MAX_TILT,
        currentThruster = nil,
        stepIndex = 1,
        complete = false
    }
    return setmetatable(obj, Sequencer)
end

function Sequencer:start_thruster(thrusterId)
    self.currentThruster = thrusterId
    self.stepIndex = 1
    self.complete = false
end

function Sequencer:next_step()
    if self.stepIndex < #self.levels then
        self.stepIndex = self.stepIndex + 1
        return true
    else
        self.complete = true
        return false
    end
end

function Sequencer:get_current_step()
    local lvl = self.levels[self.stepIndex] or 0
    return self.stepIndex, lvl
end

function Sequencer:is_complete()
    return self.complete
end

function Sequencer:build_pulse_packet(seq)
    local now = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    local _, lvl = self:get_current_step()
    return {
        ver = "1.9.5",
        domainId = self.domainId,
        seq = seq or 1,
        type = "MSG_CALIB_PULSE",
        time = now,
        payload = {
            targetThrusterId = self.currentThruster,
            stepIndex = self.stepIndex,
            pulseLevel = lvl,
            pulseDurationMs = self.durationMs,
            safetyMaxTiltDeg = self.maxTiltDeg
        }
    }
end

return multi_pulse_sequencer
