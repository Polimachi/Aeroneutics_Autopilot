-- src/0_infra/gac/modules/beacon_broadcaster.lua
-- 1Hz aggregated sector beacon and dispatch broadcaster for GAC

local beacon_broadcaster = {}

local PROTOCOL_VER = "1.9.5"

local function extract_fac_pos(fac)
    if type(fac.position) == "table" then return fac.position end
    if type(fac.coordinates) == "table" then return fac.coordinates end
    if type(fac.touchdownPoint) == "table" then return fac.touchdownPoint end
    return nil
end

local function build_facility_snapshots(inventory)
    if not (inventory and inventory.get_all_facilities) then return nil end
    local list = {}
    for _, fac in ipairs(inventory:get_all_facilities()) do
        local isDed = false
        if inventory.is_dedicated then isDed = inventory:is_dedicated(fac.facilityId) == true end
        local pos = extract_fac_pos(fac)
        table.insert(list, {
            facilityId = fac.facilityId,
            facilityType = fac.facilityType or fac.type or "LANDING_PAD",
            status = fac.status or "UNKNOWN",
            position = pos and { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 } or nil,
            heading = fac.heading or 0.0,
            endPoint = fac.endPoint,
            tacticalChannel = fac.tacticalChannel,
            dedicated = isDed
        })
    end
    return list
end

function beacon_broadcaster.create(config)
    local cfg = config or {}
    local state = {
        seq = 1000,
        lastBroadcast = nil
    }

    local function get_time_ms()
        if os.epoch then
            return os.epoch("utc")
        end
        return os.time() * 1000
    end

    local bc = {}

    function bc:build_sector_beacon(inventory, surfaceWind, sectorStatus)
        state.seq = state.seq + 1
        local summary = inventory and inventory.get_summary and inventory:get_summary() or {
            totalLandingPads = 0,
            freeLandingPads = 0,
            totalRunways = 0,
            freeRunways = 0,
            totalDockingArms = 0,
            freeDockingArms = 0,
            maxSupportWeight = 0,
            maxSupportRadius = 0
        }

        local wind = surfaceWind or { speed = 0.0, direction = 0.0 }
        local status = sectorStatus or "OPERATIONAL"
        local facilities = build_facility_snapshots(inventory)

        return {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = state.seq,
            type = "MSG_FACILITY_BEACON",
            time = get_time_ms(),
            payload = {
                sectorId = cfg.sectorId or "UNKNOWN_SECTOR",
                sectorName = cfg.sectorName or "Sector Apron",
                sectorType = cfg.sectorType or "VERTIPORT",
                towerAtcChannel = cfg.towerAtcChannel or 50001,
                gacChannel = cfg.baseSecChannel or 50201,
                facilitiesSummary = summary,
                surfaceWind = {
                    speed = wind.speed or 0.0,
                    direction = wind.direction or 0.0
                },
                mobility = cfg.mobility or "STATIC",
                status = status,
                facilities = facilities
            }
        }
    end

    function bc:build_dispatch_packet(activeSectors)
        state.seq = state.seq + 1
        local sectorsList = activeSectors or {
            {
                sectorId = cfg.sectorId or "UNKNOWN_SECTOR",
                sectorName = cfg.sectorName or "Sector Apron",
                sectorType = cfg.sectorType or "VERTIPORT",
                gacChannel = cfg.baseSecChannel or 50201,
                towerAtcChannel = cfg.towerAtcChannel or 50001
            }
        }

        return {
            ver = PROTOCOL_VER,
            domainId = cfg.sectorId or "GAC_NODE",
            seq = state.seq,
            type = "MSG_GAC_DISPATCH",
            time = get_time_ms(),
            payload = {
                activeSectors = sectorsList
            }
        }
    end

    function bc:broadcast_1hz(modem, inventory, surfaceWind, sectorStatus, nowSec)
        local now = nowSec or (os.clock and os.clock() or 0)
        if state.lastBroadcast and (now - state.lastBroadcast) < 1.0 then
            return false
        end

        state.lastBroadcast = now
        if not modem or not modem.transmit then
            return false
        end

        local beaconPkt = bc:build_sector_beacon(inventory, surfaceWind, sectorStatus)
        local dispatchPkt = bc:build_dispatch_packet()

        local beaconCh = cfg.beaconChannel or 50003
        local dispatchCh = cfg.dispatchChannel or 50004
        local replyCh = cfg.baseSecChannel or 50201

        modem.transmit(beaconCh, replyCh, beaconPkt)
        modem.transmit(dispatchCh, replyCh, dispatchPkt)

        return true
    end

    return bc
end

return beacon_broadcaster
