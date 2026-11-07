--[[
    ========================================================================
    CONTROL SURFACE MAPPER (control_surface_mapper.lua)
    Create: Aeronautics 기계식 베어링 조종면 Tiered 탐색 및 매핑 모듈
    
    [역할]
    - UAFS ASA (Layer 3) 4대 조종면(Elevator, LeftAileron, RightAileron, Rudder) 탐색
    - 3계층 우선순위(Tiered Discovery) 알고리즘:
      * Tier 1: 공식 PascalCase 네임태그 (Elevator, LeftAileron, RightAileron, Rudder)
      * Tier 2: 모드 및 베어링 접두사 제거 후 PascalCase 복합명
      * Tier 3: 게임 자동 생성 ID 및 소문자/스네이크 케이스
    - 100% 순수 CraftOS 호환 및 비인가 모드 차단
    ========================================================================
]]

local control_surface_mapper = {}

--- 공식 표준 PascalCase 상수 정의
control_surface_mapper.PASCAL_NAMES = {
    elevator = "Elevator",
    leftAileron = "LeftAileron",
    rightAileron = "RightAileron",
    rudder = "Rudder",
}

--- 게임 및 모드 접두사 제거 헬퍼
---@param rawName string
---@return string
local function stripPrefix(rawName)
    local s = rawName
    local colonPos = string.find(s, ":")
    if colonPos then s = string.sub(s, colonPos + 1) end
    s = string.gsub(s, "^mechanical_bearing_", "")
    s = string.gsub(s, "^swivel_bearing_", "")
    s = string.gsub(s, "^bearing_", "")
    return s
end

--- 문자열이 PascalCase 패턴인지 판별 (첫 글자 대문자)
---@param s string
---@return boolean
local function isPascalLike(s)
    local first = string.sub(s, 1, 1)
    return first >= "A" and first <= "Z"
end

--- 단일 이름에 대한 조종면 매칭
---@param candidate string
---@return string? surfaceKey, number tier
local function evaluateName(candidate)
    if candidate == "Elevator" or candidate == "ElevatorBearing" or candidate == "MainElevator" then
        return "elevator", 1
    elseif candidate == "LeftAileron" or candidate == "LeftAileronBearing" or
           candidate == "AileronLeft" or candidate == "AileronLeftBearing" then
        return "leftAileron", 1
    elseif candidate == "RightAileron" or candidate == "RightAileronBearing" or
           candidate == "AileronRight" or candidate == "AileronRightBearing" then
        return "rightAileron", 1
    elseif candidate == "Rudder" or candidate == "RudderBearing" or candidate == "MainRudder" then
        return "rudder", 1
    end
    return nil, 99
end

--- Tier 3 소문자/스네이크 케이스 매칭 헬퍼
---@param lower string
---@return string? surfaceKey, number tier
local function evaluateTier3(lower)
    if string.find(lower, "left_aileron") or string.find(lower, "aileron_left") or
       string.find(lower, "aileron_l") or string.find(lower, "leftaileron") then
        return "leftAileron", 3
    elseif string.find(lower, "right_aileron") or string.find(lower, "aileron_right") or
           string.find(lower, "aileron_r") or string.find(lower, "rightaileron") then
        return "rightAileron", 3
    elseif string.find(lower, "elevator") then
        return "elevator", 3
    elseif string.find(lower, "rudder") then
        return "rudder", 3
    end
    return nil, 99
end

--- 주어진 페리페럴 이름의 조종면 종류 및 우선순위(Tier) 판정
---@param rawName string
---@return string? surfaceKey "elevator"|"leftAileron"|"rightAileron"|"rudder", nil if unmatched
---@return number tier 1|2|3 discovery tier, 99 if unmatched
function control_surface_mapper.classify(rawName)
    if not rawName or type(rawName) ~= "string" then return nil, 99 end

    -- Tier 1: 원본 이름 그대로 PascalCase 매칭
    local key1, t1 = evaluateName(rawName)
    if key1 then return key1, t1 end

    -- Tier 2: 모드 및 베어링 접두사 제거 후 PascalCase 매칭
    local stripped = stripPrefix(rawName)
    if isPascalLike(stripped) then
        local key2, _ = evaluateName(stripped)
        if key2 then return key2, 2 end
    end

    -- Tier 3: 소문자 정규화 기반 게임 ID 및 스네이크 케이스 매칭
    local lower = string.lower(rawName)
    local key3, t3 = evaluateTier3(lower)
    if key3 then return key3, t3 end

    return nil, 99
end

--- CC:Tweaked 주변기기 환경을 스캔하여 4대 조종면 페리페럴 래핑 테이블 반환
---@param pEnv table? peripheral 전역 객체 (미지정 시 _G.peripheral 사용)
---@return table { elevator = any?, leftAileron = any?, rightAileron = any?, rudder = any? }
function control_surface_mapper.scan(pEnv)
    local periph = pEnv or peripheral
    local results = { elevator = nil, leftAileron = nil, rightAileron = nil, rudder = nil }
    local bestTiers = { elevator = 99, leftAileron = 99, rightAileron = 99, rudder = 99 }

    if not periph or not periph.getNames or not periph.wrap then
        return results
    end

    local names = periph.getNames()
    for _, name in ipairs(names) do
        local key, tier = control_surface_mapper.classify(name)
        if key and tier < bestTiers[key] then
            results[key] = periph.wrap(name)
            bestTiers[key] = tier
        end
    end

    return results
end

return control_surface_mapper
