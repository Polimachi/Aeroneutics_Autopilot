-- src/0_infra/landing_pad/modules/setup_wizard.lua
-- 5-stage commissioning setup wizard for Landing Pad

local setup_wizard = {}

local BASE_CHANNEL_START = 50001
local SECTOR_CHANNEL_SPAN = 200

function setup_wizard.derive_channels(sectorIndex, padIndex)
    local s = tonumber(sectorIndex) or 1
    local idx = tonumber(padIndex) or 1
    local base = BASE_CHANNEL_START + s * SECTOR_CHANNEL_SPAN

    return {
        sectorChannel = base + 0,
        sectorFacilityChannel = base + 1,
        sectorGpsReplyChannel = base + 5,
        tacticalChannel = base + 10 + (idx - 1)
    }
end

function setup_wizard.create(offsetTransform)
    local wizard = {}

    function wizard:evaluate_sensors(mode, scanReport)
        local rep = scanReport or {}
        if mode == "DYNAMIC" then
            local isAllPresent = (rep.gimbal == true) and (rep.altitude == true) and (rep.velocity == true)
            if not isAllPresent then
                return false, "HALT_WITH_WARNING"
            end
            return true, "READY"
        else
            -- STATIC mode does not strictly require avionics sensors
            return true, "READY"
        end
    end

    function wizard:calculate_preview(compPos, platformYaw, mountingYawOffset, bodyOffset)
        if not offsetTransform then
            return compPos or { x = 0, y = 64, z = 0 }
        end
        return offsetTransform.calculate_pad_position(compPos, platformYaw, mountingYawOffset, bodyOffset)
    end

    function wizard:assemble_config(stepData)
        local d = stepData or {}
        local fid = tostring(d.facilityId or d.padId or "PAD_01")
        local secId = tonumber(d.sectorId or d.sectorIndex) or 1
        local pIdx = tonumber(d.padIndex) or 1
        local mob = tostring(d.mobility or d.mode or "DYNAMIC")
        local ch = setup_wizard.derive_channels(secId, pIdx)
        return {
            version = "2.4.0",
            ver = "2.4.0",
            facilityId = fid,
            padId = fid,
            sectorId = secId,
            sectorIndex = secId,
            padIndex = pIdx,
            mobility = mob,
            mode = mob,
            gacChannel = ch.sectorChannel,
            sectorFacilityChannel = ch.sectorFacilityChannel,
            sectorGpsReplyChannel = ch.sectorGpsReplyChannel,
            tacticalChannel = ch.tacticalChannel,
            approachHeading = tonumber(d.approachHeading) or 180.0,
            safeDescentRate = tonumber(d.safeDescentRate) or 1.0,
            clearanceZoneRadius = tonumber(d.clearanceZoneRadius) or 5.0,
            maxSupportedWeight = tonumber(d.maxSupportedWeight) or 45000.0,
            wirelessModemSide = tostring(d.wirelessModemSide or "top"),
            slotDurationSec = tonumber(d.slotDurationSec) or 120,
            channels = ch,
            mountingYawOffset = tonumber(d.mountingYawOffset) or 0.0,
            bodyOffset = {
                forward = tonumber(d.forward) or 0.0,
                right = tonumber(d.right) or 0.0,
                up = tonumber(d.up) or 0.0
            },
            position = {
                x = tonumber(d.x) or 0.0,
                y = tonumber(d.y) or 64.0,
                z = tonumber(d.z) or 0.0
            }
        }
    end

    return wizard
end

return setup_wizard
