--[[
    ========================================================================
    AERONAUTICS DYNAMIC TRIM COMPENSATOR (dynamic_trim_compensator.lua)
    CraftOS / CC:Tweaked 비선형 실속 경계 적응형 동적 트림 및 게인 스케줄러
    
    [역할]
    - 고받음각(High AoA) 및 저속 영역에서의 동적 트림(Dynamic Trim) 자동 보상
    - 동압(Dynamic Pressure) 변화에 따른 3축 적응형 PID 게인 스케줄링
    - 실속 경계 감지 시 피치 댐핑(Kd) 증강을 통한 비선형 발산 억제
    - 50줄 이내 단일 책임 원칙(SRP) 및 100% CraftOS 순수 런타임 준수
    ========================================================================
]]

local dynamic_trim_compensator = {}
dynamic_trim_compensator.__index = dynamic_trim_compensator

--- 신규 DynamicTrimCompensator 인스턴스 생성
---@param options table? { nominalSpeed: number?, stallSpeed: number?, criticalAlpha: number? }
function dynamic_trim_compensator.new(options)
    options = options or {}
    local self = setmetatable({}, dynamic_trim_compensator)
    self.nominalSpeed = options.nominalSpeed or 20.0
    self.stallSpeed = options.stallSpeed or 15.0
    self.criticalAlpha = options.criticalAlpha or 16.0
    return self
end

--- 대기속도 및 받음각 기반 동적 트림 오프셋 산출
---@param airspeed number
---@param alpha number
---@return table { pitchTrim: number, throttleTrim: number, stallWarning: boolean }
function dynamic_trim_compensator:computeTrimOffsets(airspeed, alpha)
    local pitchTrim = 0.0
    local throttleTrim = 0.0
    local stallWarning = false

    -- 1. 고받음각 영역 피치다운 트림 보상
    if alpha > 8.0 then
        local excessAlpha = math.min(15.0, alpha - 8.0)
        pitchTrim = -(excessAlpha * 0.45)
    end

    -- 2. 저속 실속 경계 스로틀 부스트 트림 보상
    if airspeed < (self.stallSpeed * 1.25) then
        stallWarning = true
        local deficit = math.max(0.0, (self.stallSpeed * 1.25) - airspeed)
        throttleTrim = math.min(5.0, deficit * 0.8)
    end

    return {
        pitchTrim = pitchTrim,
        throttleTrim = throttleTrim,
        stallWarning = stallWarning,
    }
end

--- 동압 변동에 따른 적응형 PID 게인 스케줄링 산출
---@param baseGains table 원본 PID 게인 테이블
---@param airspeed number 현재 대기속도 (m/s)
---@param stallWarning boolean 실속 경고 여부
---@return table 스케줄링된 PID 게인 테이블
function dynamic_trim_compensator:scheduleGains(baseGains, airspeed, stallWarning)
    baseGains = baseGains or { pitch = { kp = 4.0, ki = 0.2, kd = 1.5 } }
    local safeSpd = math.max(8.0, math.min(40.0, airspeed))
    -- 동압 역비례 스케일러 (속도 저하 시 조종면 타면 효율 감소 보상)
    local speedRatio = self.nominalSpeed / safeSpd
    local kpScale = math.max(0.65, math.min(1.85, speedRatio))
    local kdBoost = stallWarning and 1.6 or 1.0

    local pitchBase = baseGains.pitch or { kp = 4.0, ki = 0.2, kd = 1.5 }
    local scheduledPitch = {
        kp = pitchBase.kp * kpScale,
        ki = pitchBase.ki or 0.2,
        kd = (pitchBase.kd or 1.5) * kdBoost,
    }

    local climbBase = baseGains.climb or { kp = 2.5, kd = 1.2 }
    local scheduledClimb = {
        kp = math.max(2.5, climbBase.kp * kpScale),
        kd = (climbBase.kd or 1.2) * kdBoost,
    }

    return {
        pitch = scheduledPitch,
        climb = scheduledClimb,
        roll = baseGains.roll or { kp = 4.0, ki = 0.2, kd = 1.5 },
        yaw = baseGains.yaw or { kp = 1.5, ki = 0.02, kd = 1.0 },
    }
end

--- 종합 트림 보상 및 게인 산출 엔트리
---@param telemetry table { airspeed: number?, pitch: number?, alpha: number? }
---@param baseGains table 원본 게인
---@return table { trim: table, gains: table, stallWarning: boolean }
function dynamic_trim_compensator:evaluate(telemetry, baseGains)
    telemetry = telemetry or {}
    local spd = telemetry.airspeed or self.nominalSpeed
    local alpha = telemetry.alpha or (telemetry.pitch and math.max(0.0, telemetry.pitch)) or 2.0

    local trimInfo = self:computeTrimOffsets(spd, alpha)
    local gains = self:scheduleGains(baseGains, spd, trimInfo.stallWarning)

    return {
        trim = trimInfo,
        gains = gains,
        stallWarning = trimInfo.stallWarning,
    }
end

return dynamic_trim_compensator
