-- Dynamic Settling Guard and Baseline Stability Sentinel
local settling_guard = {}
local Guard = {}
Guard.__index = Guard

local DEFAULT_MAX_ANG = 0.02
local DEFAULT_MAX_LIN = 0.05
local DEFAULT_TIMEOUT = 1.5

local function compute_norm(v, k1, k2, k3)
    local x = v[k1] or 0
    local y = v[k2] or 0
    local z = v[k3] or 0
    return math.sqrt(x * x + y * y + z * z)
end

function settling_guard.new(opts)
    opts = opts or {}
    local obj = {
        maxAngularRate = opts.maxAngularRate or DEFAULT_MAX_ANG,
        maxLinearVelocity = opts.maxLinearVelocity or DEFAULT_MAX_LIN,
        timeoutSec = opts.timeoutSec or DEFAULT_TIMEOUT,
        elapsedTime = 0
    }
    return setmetatable(obj, Guard)
end

function Guard:reset()
    self.elapsedTime = 0
end

function Guard:check_sample(sample, dt)
    self.elapsedTime = self.elapsedTime + (dt or 0.05)
    local lv = sample.linearVelocity or sample
    local av = sample.angularVelocity or sample
    
    local linNorm = compute_norm(lv, "surge", "sway", "heave")
    local angNorm = compute_norm(av, "pitch", "roll", "yaw")
    
    local isSettled = (angNorm < self.maxAngularRate) and (linNorm < self.maxLinearVelocity)
    local isTimeout = (self.elapsedTime >= self.timeoutSec)
    
    return isSettled, isTimeout, self.elapsedTime, angNorm, linNorm
end

function Guard:get_elapsed_time()
    return self.elapsedTime
end

return settling_guard
