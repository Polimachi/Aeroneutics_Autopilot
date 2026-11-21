-- src/0_infra/pocket_pda/modules/remote_link_controller.lua
-- Pocket PDA remote Alignment (Base_hangar+0/+1) and FDR (Base+9, 0tx) session controller (ICD v1.9.5)

local pda_network = require("pda_network")

local remote_link_controller = {}

local VALID_ALIGN_ACTIONS = {
    BIND_SESSION = true,
    START_PULSE = true,
    PAUSE_SESSION = true,
    RETRY_STEP = true,
    APPROVE_SYNC = true,
    ABORT_SESSION = true,
    RELEASE_SESSION = true,
}

local VALID_FDR_ACTIONS = {
    BIND_AIRCRAFT = true,
    SET_MODE = true,
    DUMP_NOW = true,
    EXPORT_NOW = true,
    ROLLOVER_NOW = true,
    CLEAR_BUFFER = true,
}

local VALID_FDR_MODES = {
    LOGGING = true,
    STANDBY = true,
    PAUSED = true,
}

local function get_time_ms(now_ms)
    if type(now_ms) == "number" then return now_ms end
    if os and os.epoch then return os.epoch("utc") end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

local function is_hangar_telem_channel(ch)
    return type(ch) == "number" and ch >= 102 and ch <= 192 and ((ch - 102) % 10 == 0)
end

local function build_fdr_targets(net_ctx, link_state, action, new_base)
    local targets, seen = {}, {}
    local function add(ch)
        if type(ch) == "number" and not seen[ch] then
            seen[ch] = true
            targets[#targets + 1] = ch
        end
    end
    local fdr_n = (type(link_state) == "table" and type(link_state.fdr) == "table") and link_state.fdr.boundIndexN or nil
    local bound_base = (fdr_n and pda_network.compute_craft_base(fdr_n)) or net_ctx.baseChannel
    if bound_base then add(bound_base + 9) end
    if action == "BIND_AIRCRAFT" and new_base then add(new_base + 9) end
    if type(net_ctx.baseChannel) == "number" then add(net_ctx.baseChannel + 9) end
    return targets
end

--- Initialize remote Alignment and FDR tracking state.
function remote_link_controller.init(cfg)
    local c = (type(cfg) == "table") and cfg or {}
    local defs = (type(c.defaults) == "table") and c.defaults or {}
    local craft_n = defs.aircraftIndexN or c.defaultAircraftIndexN or 1
    local bay_id = defs.hangarBayId or c.defaultHangarBayId or 1
    local fdr_n = defs.fdrBoundIndexN or c.defaultFdrBoundIndexN or craft_n
    local prefix = c.stationIdPrefix or "HANGAR_BAY_"
    return {
        cfg = c,
        stationIdPrefix = prefix,
        alignment = {
            bayId = bay_id,
            stationId = string.format("%s%02d", prefix, bay_id),
            aircraftIndexN = craft_n,
            targetCraftDomain = defs.targetDomainId or c.defaultTargetDomainId or pda_network.default_domain_for_index(craft_n),
            baseHangarChannel = pda_network.compute_hangar_base(bay_id) or 101,
            craftBaseChannel = pda_network.compute_craft_base(craft_n) or 10000,
            fsmState = "STANDBY",
            status = "IDLE",
            activeThruster = "---",
            controllabilityStatus = "---",
            confidenceR2 = nil,
            reason = nil,
            lastUpdateMs = nil,
            lastCmd = nil,
            lastCmdMs = nil,
            lastInitAck = nil,
            lastCalibAck = nil,
            lastCloseAck = nil,
        },
        fdr = {
            boundIndexN = fdr_n,
            boundBaseChannel = pda_network.compute_craft_base(fdr_n) or 10000,
            mode = "LOGGING",
            recordMode = "STREAMING",
            lastCmd = nil,
            lastCmdMs = nil,
        },
    }
end

--- Transmit MSG_ALIGN_REMOTE_CMD on Base_hangar+0 (reply Base_hangar+1).
function remote_link_controller.send_align_cmd(net_ctx, link_state, action, opts, now_ms)
    if type(net_ctx) ~= "table" or not net_ctx.modem then
        return false, "ERR_NO_MODEM"
    end
    if not VALID_ALIGN_ACTIONS[action] then
        return false, "ERR_INVALID_ALIGN_ACTION"
    end
    local o = (type(opts) == "table") and opts or {}
    local aln = (type(link_state) == "table" and type(link_state.alignment) == "table") and link_state.alignment or nil
    local bay_id = o.bayId or (aln and aln.bayId) or net_ctx.hangarBayId or 1
    local hangar_base, b_err = pda_network.compute_hangar_base(bay_id)
    if not hangar_base then return false, b_err end

    local craft_n = o.aircraftIndexN or net_ctx.aircraftIndexN or (aln and aln.aircraftIndexN) or 1
    local _, c_err = pda_network.compute_craft_base(craft_n)
    if c_err then return false, c_err end

    local prefix = (type(link_state) == "table" and link_state.stationIdPrefix) or "HANGAR_BAY_"
    local station_id = o.stationId or (aln and aln.bayId == bay_id and aln.stationId) or string.format("%s%02d", prefix, bay_id)
    local raw_dom = o.targetCraftDomain or net_ctx.targetDomainId
    local target_dom = (type(raw_dom) == "string" and raw_dom ~= "" and raw_dom ~= "*")
        and raw_dom or pda_network.default_domain_for_index(craft_n)

    local payload = {
        action = action,
        stationId = station_id,
        bayId = bay_id,
        aircraftIndexN = craft_n,
        targetCraftDomain = target_dom,
        baseHangarChannel = hangar_base,
        source = o.source or "POCKET_PDA",
    }
    if o.reason ~= nil then payload.reason = o.reason end
    if o.saveProfile ~= nil then payload.saveProfile = (o.saveProfile == true) end

    local ok = pda_network.transmit_raw_channel(net_ctx, hangar_base, hangar_base + 1, "MSG_ALIGN_REMOTE_CMD", payload, target_dom, now_ms)
    if not ok then return false, "ERR_TX_FAILED" end
    if aln then
        aln.bayId = bay_id
        aln.stationId = station_id
        aln.baseHangarChannel = hangar_base
        aln.aircraftIndexN = craft_n
        aln.targetCraftDomain = target_dom
        aln.lastCmd = action
        aln.lastCmdMs = get_time_ms(now_ms)
    end
    return true, nil
end

local function apply_remote_status(aln, p, ts)
    if type(p.stationId) == "string" then aln.stationId = p.stationId end
    if type(p.bayId) == "number" then aln.bayId = p.bayId end
    if type(p.aircraftIndexN) == "number" then aln.aircraftIndexN = p.aircraftIndexN end
    if type(p.fsmState) == "string" then aln.fsmState = p.fsmState end
    if type(p.status) == "string" then aln.status = p.status end
    if type(p.targetCraftDomain) == "string" then aln.targetCraftDomain = p.targetCraftDomain end
    if type(p.baseHangarChannel) == "number" then aln.baseHangarChannel = p.baseHangarChannel end
    if type(p.craftBaseChannel) == "number" then aln.craftBaseChannel = p.craftBaseChannel end
    if type(p.activeThruster) == "string" then aln.activeThruster = p.activeThruster end
    if type(p.controllabilityStatus) == "string" then aln.controllabilityStatus = p.controllabilityStatus end
    if type(p.confidenceR2) == "number" then aln.confidenceR2 = p.confidenceR2 end
    if p.reason ~= nil then aln.reason = p.reason end
    aln.lastUpdateMs = ts
end

--- Consume Alignment remote status and calibration ACK packets on Base_hangar+1.
function remote_link_controller.ingest_align_packet(link_state, channel, pkt, now_ms)
    if type(link_state) ~= "table" or type(link_state.alignment) ~= "table" or not is_hangar_telem_channel(channel) then
        return false
    end
    if type(pkt) ~= "table" or pkt.ver ~= "1.9.5" or type(pkt.type) ~= "string" or type(pkt.payload) ~= "table" then
        return false
    end
    local aln, p, ts = link_state.alignment, pkt.payload, get_time_ms(now_ms)
    if pkt.type == "MSG_ALIGN_REMOTE_STATUS" then
        apply_remote_status(aln, p, ts)
        return true
    elseif pkt.type == "MSG_CALIBRATION_INIT_ACK" then
        aln.lastInitAck = p
        if type(p.aircraftDomainId) == "string" then aln.targetCraftDomain = p.aircraftDomainId end
        if type(p.bayId) == "number" then aln.bayId = p.bayId end
        if type(p.status) == "string" then aln.initStatus = p.status end
        if type(p.airframeType) == "string" then aln.airframeType = p.airframeType end
        if type(p.baseChannel) == "number" then aln.craftBaseChannel = p.baseChannel end
        if type(p.hardwareUuid) == "string" then aln.hardwareUuid = p.hardwareUuid end
        aln.lastUpdateMs = ts
        return true
    elseif pkt.type == "MSG_CALIB_ACK" then
        aln.lastCalibAck = p
        if type(p.profileId) == "string" then aln.profileId = p.profileId end
        if type(p.status) == "string" then aln.calibAckStatus = p.status end
        aln.lastUpdateMs = ts
        return true
    elseif pkt.type == "MSG_CALIBRATION_CLOSE_ACK" then
        aln.lastCloseAck = p
        if type(p.bayId) == "number" then aln.bayId = p.bayId end
        if p.status == "CLOSED" then
            aln.fsmState = "STANDBY"
            aln.status = "CLOSED"
        end
        aln.lastUpdateMs = ts
        return true
    end
    return false
end

local function update_fdr_link_state(fdr, action, target_n, new_base, opts, now_ms)
    if not fdr then return end
    if action == "BIND_AIRCRAFT" then
        fdr.boundIndexN = target_n
        fdr.boundBaseChannel = new_base
        if opts.autoStartLogging == true then fdr.mode = "LOGGING" end
    elseif action == "SET_MODE" then
        fdr.mode = opts.recordMode
    end
    fdr.lastCmd = action
    fdr.lastCmdMs = get_time_ms(now_ms)
end

--- Transmit passive one-way MSG_FDR_REMOTE_CMD on Base+9 (and dual-target when bound differs).
function remote_link_controller.send_fdr_cmd(net_ctx, link_state, action, opts, now_ms)
    if type(net_ctx) ~= "table" or not net_ctx.modem then
        return false, "ERR_NO_MODEM"
    end
    if not VALID_FDR_ACTIONS[action] then
        return false, "ERR_INVALID_FDR_ACTION"
    end
    local o = (type(opts) == "table") and opts or {}
    local fdr = (type(link_state) == "table" and type(link_state.fdr) == "table") and link_state.fdr or nil
    local target_n = (action == "BIND_AIRCRAFT")
        and (o.targetAircraftIndexN or net_ctx.aircraftIndexN or (fdr and fdr.boundIndexN) or 1)
        or (o.targetAircraftIndexN or (fdr and fdr.boundIndexN) or net_ctx.aircraftIndexN or 1)
    local new_base, n_err = pda_network.compute_craft_base(target_n)
    if not new_base then return false, n_err end
    if action == "SET_MODE" and not VALID_FDR_MODES[o.recordMode] then
        return false, "ERR_INVALID_FDR_MODE"
    end

    local payload = {
        action = action,
        targetAircraftIndexN = target_n,
        source = o.source or "POCKET_PDA",
        targetDomainId = o.targetDomainId or net_ctx.targetDomainId,
        reason = o.reason or "PDA_REMOTE_CMD",
        recordMode = o.recordMode,
    }
    if o.autoStartLogging ~= nil then payload.autoStartLogging = (o.autoStartLogging == true) end

    local sent_any = false
    for _, ch in ipairs(build_fdr_targets(net_ctx, link_state, action, new_base)) do
        if pda_network.transmit_raw_channel(net_ctx, ch, ch, "MSG_FDR_REMOTE_CMD", payload, nil, now_ms) then
            sent_any = true
        end
    end
    if not sent_any then return false, "ERR_TX_FAILED" end
    update_fdr_link_state(fdr, action, target_n, new_base, o, now_ms)
    return true, nil
end

return remote_link_controller
