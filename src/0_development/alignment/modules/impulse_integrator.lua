-- 20Hz Trapezoidal Rule Numerical Impulse Integrator
local impulse_integrator = {}
local Integrator = {}
Integrator.__index = Integrator

local AXES = { "surge", "sway", "heave", "pitch", "roll", "yaw" }

local function zero_vector()
    return { surge = 0, sway = 0, heave = 0, pitch = 0, roll = 0, yaw = 0 }
end

function impulse_integrator.new()
    local obj = {
        baseline = zero_vector(),
        totalImpulse = zero_vector(),
        lastState = nil,
        sampleCount = 0
    }
    return setmetatable(obj, Integrator)
end

function Integrator:reset()
    self.baseline = zero_vector()
    self.totalImpulse = zero_vector()
    self.lastState = nil
    self.sampleCount = 0
end

function Integrator:sample_baseline(samples)
    local n = #samples
    if n == 0 then return end
    local sum = zero_vector()
    for _, s in ipairs(samples) do
        local lv = s.linearVelocity or s
        local av = s.angularVelocity or s
        sum.surge = sum.surge + (lv.surge or 0)
        sum.sway  = sum.sway  + (lv.sway  or 0)
        sum.heave = sum.heave + (lv.heave or 0)
        sum.pitch = sum.pitch + (av.pitch or 0)
        sum.roll  = sum.roll  + (av.roll  or 0)
        sum.yaw   = sum.yaw   + (av.yaw   or 0)
    end
    for _, a in ipairs(AXES) do
        self.baseline[a] = sum[a] / n
    end
end

local function extract_state(sample, baseline)
    local lv = sample.linearVelocity or sample
    local av = sample.angularVelocity or sample
    return {
        surge = (lv.surge or 0) - baseline.surge,
        sway  = (lv.sway  or 0) - baseline.sway,
        heave = (lv.heave or 0) - baseline.heave,
        pitch = (av.pitch or 0) - baseline.pitch,
        roll  = (av.roll  or 0) - baseline.roll,
        yaw   = (av.yaw   or 0) - baseline.yaw
    }
end

function Integrator:integrate_step(sample, dt)
    local curr = extract_state(sample, self.baseline)
    self.sampleCount = self.sampleCount + 1
    if self.lastState then
        for _, a in ipairs(AXES) do
            local trap = (self.lastState[a] + curr[a]) * 0.5 * dt
            self.totalImpulse[a] = self.totalImpulse[a] + trap
        end
    end
    self.lastState = curr
end

function Integrator:get_total_impulse()
    local res = {}
    for _, a in ipairs(AXES) do res[a] = self.totalImpulse[a] end
    return res
end

function Integrator:get_baseline()
    local res = {}
    for _, a in ipairs(AXES) do res[a] = self.baseline[a] end
    return res
end

function Integrator:get_sample_count()
    return self.sampleCount
end

return impulse_integrator
