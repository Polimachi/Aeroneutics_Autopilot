-- src/0_infra/gac/modules/facility_inventory.lua
-- In-memory registry and status manager for GAC facility swarm

local facility_inventory = {}

local function has_dedicated_entries(val)
    if type(val) == "string" then
        return val ~= ""
    end
    if type(val) == "table" then
        return #val > 0
    end
    return false
end

function facility_inventory.is_facility_dedicated(fac)
    if type(fac) ~= "table" then
        return false
    end
    return has_dedicated_entries(fac.dedicatedCraftIds)
        or has_dedicated_entries(fac.dedicatedAirframeTypes)
end

function facility_inventory.create(initialFacilities)
    local state = {
        facilities = {},
        emergencyLockdown = false
    }

    local function clone_table(orig)
        if type(orig) ~= "table" then return orig end
        local copy = {}
        for k, v in pairs(orig) do
            copy[k] = type(v) == "table" and clone_table(v) or v
        end
        return copy
    end

    if type(initialFacilities) == "table" then
        for _, fac in ipairs(initialFacilities) do
            if fac.facilityId then
                state.facilities[fac.facilityId] = clone_table(fac)
            end
        end
    end

    local inv = {}

    function inv:add_facility(fac)
        if type(fac) ~= "table" or not fac.facilityId then
            return false, "INVALID_FACILITY_DATA"
        end
        state.facilities[fac.facilityId] = clone_table(fac)
        return true, nil
    end

    function inv:remove_facility(facilityId)
        if not facilityId or not state.facilities[facilityId] then
            return false, "FACILITY_NOT_FOUND"
        end
        state.facilities[facilityId] = nil
        return true, nil
    end

    function inv:get_facility(facilityId)
        return state.facilities[facilityId]
    end

    function inv:get_all_facilities()
        local list = {}
        for _, fac in pairs(state.facilities) do
            table.insert(list, fac)
        end
        table.sort(list, function(a, b) return tostring(a.facilityId) < tostring(b.facilityId) end)
        return list
    end

    function inv:is_dedicated(facilityId)
        return facility_inventory.is_facility_dedicated(state.facilities[facilityId])
    end

    function inv:update_dedicated(facilityId, dedicatedCraftIds, dedicatedAirframeTypes)
        local fac = state.facilities[facilityId]
        if not fac then
            return false, "FACILITY_NOT_FOUND"
        end
        fac.dedicatedCraftIds = clone_table(dedicatedCraftIds)
        fac.dedicatedAirframeTypes = clone_table(dedicatedAirframeTypes)
        return true, nil
    end

    function inv:update_status(facilityId, status, craftId, faultCode)
        local fac = state.facilities[facilityId]
        if not fac then
            return false, "FACILITY_NOT_FOUND"
        end
        fac.status = status
        fac.currentCraft = craftId
        fac.faultCode = faultCode
        return true, nil
    end

    function inv:update_dynamic_telemetry(facilityId, pos, heading, vel)
        local fac = state.facilities[facilityId]
        if not fac then
            return false, "FACILITY_NOT_FOUND"
        end
        if pos then
            fac.coordinates = clone_table(pos)
        end
        if heading ~= nil then
            fac.heading = heading
        end
        if vel then
            fac.velocity = clone_table(vel)
        end
        return true, nil
    end

    function inv:set_emergency_lockdown(active)
        state.emergencyLockdown = (active == true)
    end

    function inv:is_emergency_lockdown()
        return state.emergencyLockdown
    end

    function inv:get_free_pads()
        if state.emergencyLockdown then
            return {}
        end
        local freePads = {}
        for _, fac in pairs(state.facilities) do
            if (fac.type == "LANDING_PAD" or fac.type == nil) and fac.status == "FREE" then
                table.insert(freePads, fac)
            end
        end
        table.sort(freePads, function(a, b) return tostring(a.facilityId) < tostring(b.facilityId) end)
        return freePads
    end

    function inv:get_summary()
        local totalPads = 0
        local freePads = 0
        local totalRunways = 0
        local freeRunways = 0
        local maxWeight = 0.0
        local maxRadius = 0.0

        for _, fac in pairs(state.facilities) do
            local fType = fac.type or "LANDING_PAD"
            local isDedicated = facility_inventory.is_facility_dedicated(fac)
            if fType == "LANDING_PAD" then
                totalPads = totalPads + 1
                if fac.status == "FREE" and not state.emergencyLockdown and not isDedicated then
                    freePads = freePads + 1
                end
                if (fac.maxSupportWeight or 0) > maxWeight then
                    maxWeight = fac.maxSupportWeight
                end
                if (fac.maxSupportRadius or 0) > maxRadius then
                    maxRadius = fac.maxSupportRadius
                end
            elseif fType == "RUNWAY" then
                totalRunways = totalRunways + 1
                if fac.status == "FREE" and not state.emergencyLockdown and not isDedicated then
                    freeRunways = freeRunways + 1
                end
            end
        end

        return {
            totalLandingPads = totalPads,
            freeLandingPads = freePads,
            totalRunways = totalRunways,
            freeRunways = freeRunways,
            maxSupportWeight = maxWeight,
            maxSupportRadius = maxRadius
        }
    end

    return inv
end

return facility_inventory
