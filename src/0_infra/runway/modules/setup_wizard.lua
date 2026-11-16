-- src/0_infra/runway/modules/setup_wizard.lua
-- Commissioning setup wizard for Runway Controller

local setup_wizard = {}

local BASE_CHANNEL_START = 50001
local SECTOR_CHANNEL_SPAN = 200

local function non_empty_str(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

function setup_wizard.derive_channels(sectorId, runwayIndex)
    local s = tonumber(sectorId) or 1
    local idx = tonumber(runwayIndex) or 1
    local base = BASE_CHANNEL_START + s * SECTOR_CHANNEL_SPAN
    return {
        sectorChannel = base,
        sectorFacilityChannel = base + 1,
        sectorGpsReplyChannel = base + 5,
        tacticalChannel = base + 10 + (idx - 1),
    }
end

function setup_wizard.create(offsetTransform)
    local wizard = {}

    function wizard:evaluate_sensors(mobility, scanReport)
        local rep = scanReport or {}
        if string.upper(mobility or "DYNAMIC") == "DYNAMIC" then
            if rep.gimbal == true and rep.altitude == true and rep.velocity == true then
                return true, "READY"
            end
            return false, "HALT_WITH_WARNING"
        end
        return true, "READY"
    end

    function wizard:calculate_preview(compPos, yawDeg, mountingYawOffset, tdOff, endOff)
        if not offsetTransform then return compPos, compPos end
        return offsetTransform.calculate_runway_points(compPos, yawDeg, mountingYawOffset, tdOff, endOff)
    end

    function wizard:assemble_config(d)
        local data = d or {}
        local fid = non_empty_str(data.facilityId) or "RWY_ALPHA_09L"
        local secId = tonumber(data.sectorId) or 1
        local rIdx = tonumber(data.runwayIndex) or 1
        local mob = string.upper(non_empty_str(data.mobility) or "DYNAMIC")
        local ch = setup_wizard.derive_channels(secId, rIdx)
        return {
            version = "1.12.0",
            facilityId = fid,
            sectorId = secId,
            runwayIndex = rIdx,
            mobility = mob,
            gacChannel = ch.sectorChannel,
            sectorFacilityChannel = ch.sectorFacilityChannel,
            sectorGpsReplyChannel = ch.sectorGpsReplyChannel,
            tacticalChannel = ch.tacticalChannel,
            channels = ch,
            approachHeading = tonumber(data.approachHeading) or 90.0,
            approachDirection = non_empty_str(data.approachDirection) or "FRONT",
            glideSlopeAngle = tonumber(data.glideSlopeAngle) or 3.0,
            touchdownZoneLength = tonumber(data.touchdownZoneLength) or 80.0,
            mountingYawOffset = tonumber(data.mountingYawOffset) or 0.0,
            position = data.position or { x = 0.0, y = 64.0, z = 0.0 },
            touchdownOffset = data.touchdownOffset or { forward = 0.0, right = 0.0, up = 0.0 },
            endOffset = data.endOffset or { forward = 200.0, right = 0.0, up = 0.0 },
            wirelessModemSide = non_empty_str(data.wirelessModemSide) or "top",
            slotDurationSec = tonumber(data.slotDurationSec) or 120,
        }
    end

    return wizard
end

return setup_wizard
