-- VAS Layer 1: Flight Dynamics Core (VICD-Spec v1.1.0)
local quat = require("quat")

local flight_dynamics_core = {}

function flight_dynamics_core.init(config)
    local cfg = config or {}
    local attCfg = cfg.attitude or {}
    local climbCfg = cfg.climb or {}

    return {
        config = cfg,
        thrustScale = cfg.thrustScale or 15.0,
        gains = {
            pitch = {
                kp = attCfg.pitch and attCfg.pitch.kp or 3.2,
                ki = attCfg.pitch and attCfg.pitch.ki or 0.15,
                kd = attCfg.pitch and attCfg.pitch.kd or 0.45,
                integralLimit = attCfg.pitch and attCfg.pitch.integralLimit or 4.0
            },
            roll = {
                kp = attCfg.roll and attCfg.roll.kp or 3.5,
                ki = attCfg.roll and attCfg.roll.ki or 0.12,
                kd = attCfg.roll and attCfg.roll.kd or 0.48,
                integralLimit = attCfg.roll and attCfg.roll.integralLimit or 4.0
            },
            yaw = {
                kp = attCfg.yaw and attCfg.yaw.kp or 2.8,
                ki = attCfg.yaw and attCfg.yaw.ki or 0.08,
                kd = attCfg.yaw and attCfg.yaw.kd or 0.35,
                integralLimit = attCfg.yaw and attCfg.yaw.integralLimit or 2.5
            },
            climb = {
                kp = climbCfg.kp or 2.0,
                ki = climbCfg.ki or 0.10,
                kd = climbCfg.kd or 0.00,
                integralLimit = climbCfg.integralLimit or 3.0
            }
        },
        integrators = {
            pitch = 0.0, roll = 0.0, yaw = 0.0, climb = 0.0
        }
    }
end

function flight_dynamics_core.reset_integrators(state)
    state.integrators.pitch = 0.0
    state.integrators.roll = 0.0
    state.integrators.yaw = 0.0
    state.integrators.climb = 0.0
end

local function update_axis_integrator(currentVal, err, dt, limit, isSatPos, isSatNeg)
    local lim = tonumber(limit) or 4.0
    local delta = err * dt
    if delta > 0.0 and isSatPos then
        return currentVal
    elseif delta < 0.0 and isSatNeg then
        return currentVal
    end
    local nextVal = currentVal + delta
    return math.max(-lim, math.min(lim, nextVal))
end

function flight_dynamics_core.compute_attitude_wrench(state, targetQ, measQ, angularRate, dt, satStatus, targetRates, commandType)
    local isRateCmd = (commandType == "RATE_COMMAND")
    local pTarget = (targetRates and (targetRates.pitchRate or targetRates.pitch or targetRates.x)) or 0.0
    local rTarget = (targetRates and (targetRates.rollRate or targetRates.roll or targetRates.y)) or 0.0
    local yTarget = (targetRates and (targetRates.yawRate or targetRates.yaw or targetRates.z)) or 0.0

    local pRate = (angularRate and angularRate.x) or (angularRate and angularRate.pitchRate) or 0.0
    local rRate = (angularRate and angularRate.y) or (angularRate and angularRate.rollRate) or 0.0
    local yRate = (angularRate and angularRate.z) or (angularRate and angularRate.yawRate) or 0.0

    local eRateRoll = rTarget - rRate
    local eRatePitch = pTarget - pRate
    local eRateYaw = yTarget - yRate

    local eRoll, ePitch, eYaw = 0.0, 0.0, 0.0
    if not isRateCmd then
        local errQ = quat.error_quaternion(targetQ, measQ)
        eRoll = 2.0 * errQ.x
        ePitch = 2.0 * errQ.y
        eYaw = 2.0 * errQ.z
    end

    local g = state.gains
    local inP, inR, inY
    if isRateCmd then
        inP = 0.0
        inR = 0.0
        inY = 0.0
    else
        local satPos = (satStatus and satStatus.axisSaturatedPos) or {}
        local satNeg = (satStatus and satStatus.axisSaturatedNeg) or {}
        inP = update_axis_integrator(state.integrators.pitch, ePitch, dt, g.pitch.integralLimit, satPos.pitch, satNeg.pitch)
        inR = update_axis_integrator(state.integrators.roll, eRoll, dt, g.roll.integralLimit, satPos.roll, satNeg.roll)
        inY = update_axis_integrator(state.integrators.yaw, eYaw, dt, g.yaw.integralLimit, satPos.yaw, satNeg.yaw)
        state.integrators.pitch = inP
        state.integrators.roll = inR
        state.integrators.yaw = inY
    end

    return {
        rollTorque  = (isRateCmd and 0.0 or (g.roll.kp * eRoll + g.roll.ki * inR)) + g.roll.kd * eRateRoll,
        pitchTorque = (isRateCmd and 0.0 or (g.pitch.kp * ePitch + g.pitch.ki * inP)) + g.pitch.kd * eRatePitch,
        yawTorque   = (isRateCmd and 0.0 or (g.yaw.kp * eYaw + g.yaw.ki * inY)) + g.yaw.kd * eRateYaw
    }
end

function flight_dynamics_core.compute_climb_wrench(state, targetVy, measVy, baseThrottle, dt, satStatus)
    local satPos = (satStatus and satStatus.axisSaturatedPos) or {}
    local satNeg = (satStatus and satStatus.axisSaturatedNeg) or {}
    local eClimb = (tonumber(targetVy) or 0.0) - (tonumber(measVy) or 0.0)

    local gC = state.gains.climb
    local inC = update_axis_integrator(state.integrators.climb, eClimb, dt, gC.integralLimit, satPos.heave, satNeg.heave)
    state.integrators.climb = inC

    local baseT = tonumber(baseThrottle) or 0.0
    local heaveEffort = baseT + gC.kp * eClimb + gC.ki * inC
    return math.max(0.0, math.min(15.0, heaveEffort))
end

function flight_dynamics_core.compute(state, telem, guidance, dt, satStatus)
    local deltaT = math.max(0.005, math.min(0.2, dt or 0.05))
    local measQ = telem.orientation or quat.identity()
    local targetQ = guidance.targetQuaternion or guidance.targetOrientation or quat.identity()
    local rates = telem.angularRate or telem.rates or { x = 0, y = 0, z = 0 }
    local targetRates = guidance.targetAngularRates
    local cmdType = guidance.commandType or "QUATERNION_RATE"

    local attWrench = flight_dynamics_core.compute_attitude_wrench(
        state, targetQ, measQ, rates, deltaT, satStatus, targetRates, cmdType
    )

    local bias = guidance.translationBias or {}
    local thrustScale = state.thrustScale or (state.config and state.config.thrustScale) or 15.0
    local cThrust = math.max(0.0, math.min(1.0, tonumber(guidance.collectiveThrust) or 0.0))
    local thrustEffort = math.max(0.0, math.min(15.0, cThrust * thrustScale))

    local alpha = math.max(0.0, math.min(1.0, tonumber(guidance.transitionAlpha) or 0.0))
    local bSurge = tonumber(bias.surge) or 0.0
    local bSway = tonumber(bias.sway) or 0.0

    local surgeDemand = bSurge * (1.0 - alpha) + thrustEffort * alpha
    local heaveDemand = thrustEffort * (1.0 - alpha)
    local swayDemand = bSway

    return {
        surge = surgeDemand,
        sway = swayDemand,
        heave = heaveDemand,
        rollTorque = attWrench.rollTorque,
        pitchTorque = attWrench.pitchTorque,
        yawTorque = attWrench.yawTorque
    }
end

return flight_dynamics_core
