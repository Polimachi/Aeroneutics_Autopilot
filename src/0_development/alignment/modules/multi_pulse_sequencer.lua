-- Multi-Level Step Pulse Sequencer for Standard and Vector Thrusters
local multi_pulse_sequencer = {}
local Sequencer = {}
Sequencer.__index = Sequencer

local DEFAULT_LEVELS = { 4, 8, 12 }
local DEFAULT_VECTOR_THROTTLE_LEVELS = { 5, 10, 15 }
local DEFAULT_GIMBAL_X_DEFLECTIONS = { -0.5, 0.5, 1.0 }
local DEFAULT_GIMBAL_Y_DEFLECTIONS = { -0.5, 0.5, 1.0 }
local DEFAULT_BASE_THROTTLE = 8
local DEFAULT_DURATION_MS = 300
local DEFAULT_MAX_TILT = 12.0

function multi_pulse_sequencer.generate_vector_sequence(groupId, opts)
    opts = opts or {}
    local durationMs = opts.durationMs or DEFAULT_DURATION_MS
    local throttleLevels = opts.throttleLevels or DEFAULT_VECTOR_THROTTLE_LEVELS
    local gxDeflections = opts.gimbalXDeflections or DEFAULT_GIMBAL_X_DEFLECTIONS
    local gyDeflections = opts.gimbalYDeflections or DEFAULT_GIMBAL_Y_DEFLECTIONS
    local baseThrottle = opts.baseThrottle or DEFAULT_BASE_THROTTLE

    local steps = {}
    local stepCounter = 1

    -- Phase 1: Throttle (neutral gimbal)
    for _, lvl in ipairs(throttleLevels) do
        table.insert(steps, {
            phase = "THROTTLE",
            targetThrusterId = groupId,
            stepIndex = stepCounter,
            pulseLevel = lvl,
            gimbalX = 0.0,
            gimbalY = 0.0,
            durationMs = durationMs
        })
        stepCounter = stepCounter + 1
    end

    -- Phase 2: Gimbal X (base throttle 8)
    for _, gx in ipairs(gxDeflections) do
        table.insert(steps, {
            phase = "GIMBAL_X",
            targetThrusterId = groupId,
            stepIndex = stepCounter,
            pulseLevel = baseThrottle,
            gimbalX = gx,
            gimbalY = 0.0,
            durationMs = durationMs
        })
        stepCounter = stepCounter + 1
    end

    -- Phase 3: Gimbal Y (base throttle 8)
    for _, gy in ipairs(gyDeflections) do
        table.insert(steps, {
            phase = "GIMBAL_Y",
            targetThrusterId = groupId,
            stepIndex = stepCounter,
            pulseLevel = baseThrottle,
            gimbalX = 0.0,
            gimbalY = gy,
            durationMs = durationMs
        })
        stepCounter = stepCounter + 1
    end

    return steps
end

function multi_pulse_sequencer.new(craftDomainId, opts)
    opts = opts or {}
    local obj = {
        domainId = craftDomainId or "AIRCRAFT_01",
        levels = opts.levels or DEFAULT_LEVELS,
        durationMs = opts.durationMs or DEFAULT_DURATION_MS,
        maxTiltDeg = opts.maxTiltDeg or DEFAULT_MAX_TILT,
        currentThruster = nil,
        stepIndex = 1,
        complete = false,
        isVectorMode = false,
        vectorSteps = nil
    }
    return setmetatable(obj, Sequencer)
end

function Sequencer:start_thruster(thrusterId)
    self.currentThruster = thrusterId
    self.stepIndex = 1
    self.complete = false
    self.isVectorMode = false
    self.vectorSteps = nil
end

function Sequencer:start_vector_thruster(thrusterId, opts)
    self.currentThruster = thrusterId
    self.stepIndex = 1
    self.complete = false
    self.isVectorMode = true
    self.vectorSteps = multi_pulse_sequencer.generate_vector_sequence(thrusterId, opts)
end

function Sequencer:next_step()
    local totalSteps = self.isVectorMode and (self.vectorSteps and #self.vectorSteps or 0) or #self.levels
    if self.stepIndex < totalSteps then
        self.stepIndex = self.stepIndex + 1
        return true
    else
        self.complete = true
        return false
    end
end

function Sequencer:get_current_step()
    if self.isVectorMode and self.vectorSteps then
        local step = self.vectorSteps[self.stepIndex] or {}
        return self.stepIndex, step.pulseLevel or 0, step.gimbalX or 0.0, step.gimbalY or 0.0, step.phase or "UNKNOWN"
    else
        local lvl = self.levels[self.stepIndex] or 0
        return self.stepIndex, lvl
    end
end

function Sequencer:is_complete()
    return self.complete
end

function Sequencer:build_pulse_packet(seq)
    local now = (os.epoch and os.epoch("utc")) or (os.time() * 1000)
    if self.isVectorMode and self.vectorSteps then
        local step = self.vectorSteps[self.stepIndex] or {}
        return {
            ver = "1.9.5",
            domainId = self.domainId,
            seq = seq or 1,
            type = "MSG_CALIB_PULSE",
            time = now,
            payload = {
                targetThrusterId = self.currentThruster,
                stepIndex = self.stepIndex,
                phase = step.phase,
                pulseLevel = step.pulseLevel or 0,
                gimbalX = step.gimbalX or 0.0,
                gimbalY = step.gimbalY or 0.0,
                pulseDurationMs = step.durationMs or self.durationMs,
                safetyMaxTiltDeg = self.maxTiltDeg
            }
        }
    else
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
end

return multi_pulse_sequencer
