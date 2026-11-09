-- src/0_infra/gcs/modules/fleet_tracker.lua
-- Multi-craft telemetry cache and active target tracker
-- UAFS Ecosystem GCS v1.0.0

local fleet_tracker = {}

local DEFAULT_TIMEOUT_MS = 5000

fleet_tracker.AIRFRAME_LABELS = {
    ADVANCED_VTOL = "ADV_VTOL",
    VECTORED_VTOL = "VEC_VTOL",
    WINGED_VTOL   = "WNG_VTOL",
    FIXED_WING    = "FIX_WING",
    QUADROTOR     = "QUAD_ROT",
    HEXAROTOR     = "HEXA_ROT",
    UNKNOWN       = "UNKNOWN",
}

fleet_tracker.AIRFRAME_ICONS = {
    ADVANCED_VTOL = "^V^",
    VECTORED_VTOL = ">V<",
    WINGED_VTOL   = "-V-",
    FIXED_WING    = "-=-",
    QUADROTOR     = "+X+",
    HEXAROTOR     = "*X*",
    UNKNOWN       = "<?>",
}

function fleet_tracker.get_airframe_label(airframeType)
    if not airframeType then return "UNKNOWN" end
    return fleet_tracker.AIRFRAME_LABELS[airframeType] or tostring(airframeType)
end

function fleet_tracker.get_airframe_icon(airframeType)
    if not airframeType then return "<?>" end
    return fleet_tracker.AIRFRAME_ICONS[airframeType] or "<!>"
end

function fleet_tracker.init(config)
    local ui_cfg = (config and config.ui) or {}
    local timeout_sec = ui_cfg.telemetryTimeoutSec or 5.0
    return {
        crafts = {},
        craft_order = {},
        active_index = nil,
        timeout_ms = timeout_sec * 1000
    }
end

function fleet_tracker.register_craft(state, domain_id, base_channel, block_id, airframe_type)
    if not state or not domain_id then return false end

    if not state.crafts[domain_id] then
        table.insert(state.craft_order, domain_id)
    end

    state.crafts[domain_id] = {
        domainId = domain_id,
        baseChannel = base_channel,
        blockId = block_id,
        airframeType = airframe_type,
        telemetry = nil,
        lastSeenMs = 0,
        isStale = true
    }

    if not state.active_index and #state.craft_order > 0 then
        state.active_index = 1
    end
    return true
end

function fleet_tracker.unregister_craft(state, domain_id)
    if not state or not domain_id or not state.crafts[domain_id] then
        return false
    end
    state.crafts[domain_id] = nil

    local new_order = {}
    for _, id in ipairs(state.craft_order) do
        if id ~= domain_id then
            table.insert(new_order, id)
        end
    end
    state.craft_order = new_order

    if #state.craft_order == 0 then
        state.active_index = nil
    elseif state.active_index and state.active_index > #state.craft_order then
        state.active_index = #state.craft_order
    end
    return true
end

function fleet_tracker.get_craft(state, domain_id)
    if not state or not domain_id then return nil end
    return state.crafts[domain_id]
end

function fleet_tracker.get_active_craft(state)
    if not state or not state.active_index then return nil end
    local domain_id = state.craft_order[state.active_index]
    if not domain_id then return nil end
    return state.crafts[domain_id]
end

function fleet_tracker.select_craft(state, domain_id)
    if not state or not domain_id or not state.crafts[domain_id] then
        return false
    end
    for idx, id in ipairs(state.craft_order) do
        if id == domain_id then
            state.active_index = idx
            return true
        end
    end
    return false
end

function fleet_tracker.select_next(state)
    if not state or #state.craft_order == 0 then return nil end
    local cur = state.active_index or 1
    cur = (cur % #state.craft_order) + 1
    state.active_index = cur
    return fleet_tracker.get_active_craft(state)
end

function fleet_tracker.update_telemetry(state, domain_id, mfd_state_payload, now_ms)
    if not state or not domain_id then return false end
    local craft = state.crafts[domain_id]
    if not craft then return false end

    craft.telemetry = mfd_state_payload
    if mfd_state_payload and (mfd_state_payload.airframeType or mfd_state_payload.airframe or mfd_state_payload.mode) then
        craft.airframeType = mfd_state_payload.airframeType or mfd_state_payload.airframe or mfd_state_payload.mode
    end
    craft.lastSeenMs = now_ms or 0
    craft.isStale = false
    return true
end

function fleet_tracker.prune_stale(state, now_ms)
    if not state or not now_ms then return end
    for _, craft in pairs(state.crafts) do
        if craft.lastSeenMs == 0 or (now_ms - craft.lastSeenMs) > state.timeout_ms then
            craft.isStale = true
        else
            craft.isStale = false
        end
    end
end

function fleet_tracker.get_fleet_summary(state)
    if not state then return {} end
    local list = {}
    for _, id in ipairs(state.craft_order) do
        local c = state.crafts[id]
        if c then
            local af = c.airframeType or (c.telemetry and (c.telemetry.airframeType or c.telemetry.airframe or c.telemetry.mode)) or "UNKNOWN"
            table.insert(list, {
                domainId = c.domainId,
                baseChannel = c.baseChannel,
                blockId = c.blockId,
                fsmState = (c.telemetry and c.telemetry.fsmState) or "UNKNOWN",
                airframeType = af,
                airframeLabel = fleet_tracker.get_airframe_label(af),
                airframeIcon = fleet_tracker.get_airframe_icon(af),
                isStale = c.isStale,
                lastSeenMs = c.lastSeenMs
            })
        end
    end
    return list
end

return fleet_tracker
