-- src/0_infra/gac/modules/beacon_broadcaster.lua
-- 1Hz aggregated sector beacon and dispatch broadcaster for GAC

local beacon_broadcaster = {}

local PROTOCOL_VER = "1.9.5"

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
                status = status
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
