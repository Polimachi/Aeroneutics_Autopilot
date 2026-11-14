-- src/2_guidance/fcp/modules/network_manager.lua
-- FCP 3-Channel Single-Modem Network Manager (Master ICD v1.28.0, Zone 1 Base+4/+2/+1)
local network_manager = {}
network_manager.PROTO_VERSION = "1.9.5"

local function safe_unserialize(raw)
    if type(raw) == "table" then return raw end
    if type(raw) == "string" and textutils and textutils.unserializeJSON then
        return textutils.unserializeJSON(raw)
    end
    return nil
end

local function resolve_modem(side, modem_lookup_fn)
    if type(modem_lookup_fn) == "function" then
        local m = modem_lookup_fn(side)
        if m then return m end
    elseif type(modem_lookup_fn) == "table" and modem_lookup_fn.transmit then
        return modem_lookup_fn
    end
    if side and peripheral and peripheral.getType and peripheral.getType(side) == "modem" then
        return peripheral.wrap(side)
    end
    if peripheral and peripheral.find then
        return peripheral.find("modem", function(_, dev)
            return dev and (dev.isWireless == nil or dev.isWireless())
        end)
    end
    return nil
end

local function persist_config(ctx)
    local path = ctx.configPath or "config/fcp_config.json"
    if not fs or not fs.open then return false end
    local cfg = ctx.config or {}
    if fs.exists and fs.exists(path) then
        local rf = fs.open(path, "r")
        if rf then
            local raw = rf.readAll()
            rf.close()
            local parsed = textutils and textutils.unserializeJSON and textutils.unserializeJSON(raw)
            if type(parsed) == "table" then cfg = parsed end
        end
    end
    if not cfg.channels then cfg.channels = {} end
    cfg.channels.baseChannel = ctx.baseChannel
    cfg.channels.bandwidth = cfg.channels.bandwidth or 40
    cfg.channels.trajectoryOffset = ctx.channels.trajectory - ctx.baseChannel
    cfg.channels.telemetryOffset = ctx.channels.telemetry - ctx.baseChannel
    cfg.channels.guidanceOffset = ctx.channels.guidance - ctx.baseChannel
    local ser = textutils and (textutils.serializeJSON or textutils.serialiseJSON)
    if not ser then return false end
    local ok, content = pcall(ser, cfg)
    if not ok or not content then return false end
    local f = fs.open(path, "w")
    if not f then return false end
    f.write(content)
    f.close()
    return true
end

function network_manager.init(config, modem_lookup_fn)
    local cfg = config or {}
    local sys = cfg.system or {}
    local chs = cfg.channels or {}
    local base_ch = chs.baseChannel or 10000
    local primarySide = sys.primaryModemSide or "top"
    local m = resolve_modem(primarySide, modem_lookup_fn)

    local channels = {
        trajectory = base_ch + (chs.trajectoryOffset or 4),
        telemetry = base_ch + (chs.telemetryOffset or 2),
        guidance = base_ch + (chs.guidanceOffset or 1),
    }

    if m and m.open then
        m.open(channels.trajectory)
        m.open(channels.telemetry)
        m.open(channels.guidance)
    end

    return {
        domainId = (type(sys.domainId) == "string" and sys.domainId ~= "" and sys.domainId) or "AIRCRAFT_01",
        hardwareUuid = sys.hardwareUuid or "FCP-NODE-04-UUID",
        baseChannel = base_ch,
        channels = channels,
        modem = m,
        primarySide = primarySide,
        configPath = cfg.configPath or "config/fcp_config.json",
        config = cfg,
        seq = 0,
        rebindTx = nil,
        inbound = { trajectory = nil, telemetry = nil, emergencyAlert = nil, rebindAck = nil },
    }
end

function network_manager.encode_envelope(ctx, packetType, payload)
    ctx.seq = (ctx.seq or 0) + 1
    return {
        ver = network_manager.PROTO_VERSION,
        domainId = ctx.domainId,
        senderId = ctx.hardwareUuid,
        type = packetType,
        seq = ctx.seq,
        time = (os.epoch and os.epoch("utc")) or 0,
        payload = payload or {},
    }
end

function network_manager.decode_envelope(rawPacket)
    return safe_unserialize(rawPacket)
end

function network_manager.verify_packet(ctx, packet)
    if type(ctx) ~= "table" or type(packet) ~= "table" then return false end
    if packet.ver ~= network_manager.PROTO_VERSION then return false end
    if packet.domainId ~= ctx.domainId then return false end
    return true
end

local function transmit_packet(ctx, ch, reply_ch, msg_type, payload)
    local m = ctx.modem
    if not m or not m.transmit then return false end
    local env = network_manager.encode_envelope(ctx, msg_type, payload)
    m.transmit(ch, reply_ch, env)
    return true
end

local function handle_rebind_prepare(ctx, payload, now_ms)
    local newBase = tonumber(payload.newBaseChannel)
    if not newBase then return false end
    local m = ctx.modem
    if m and m.open then
        m.open(newBase + 4)
        m.open(newBase + 2)
        m.open(newBase + 1)
    end
    local txId = payload.transactionId or ("REBIND-" .. tostring(newBase))
    ctx.rebindTx = {
        txId = txId,
        oldBase = tonumber(payload.oldBaseChannel) or ctx.baseChannel,
        newBase = newBase,
        bandwidth = tonumber(payload.bandwidth) or 40,
        startMs = now_ms or (os.epoch and os.epoch("utc") or 0),
        status = "PREPARE",
    }
    local fwd = {
        transactionId = txId,
        action = "PREPARE",
        oldBaseChannel = ctx.rebindTx.oldBase,
        newBaseChannel = newBase,
        bandwidth = ctx.rebindTx.bandwidth,
    }
    transmit_packet(ctx, ctx.rebindTx.oldBase + 1, ctx.rebindTx.oldBase + 1, "MSG_CHANNEL_REBIND", fwd)
    return true
end

local function handle_rebind_commit(ctx, payload, now_ms)
    local tx = ctx.rebindTx
    local oldBase = (tx and tx.oldBase) or tonumber(payload.oldBaseChannel) or ctx.baseChannel
    local newBase = (tx and tx.newBase) or tonumber(payload.newBaseChannel) or ctx.baseChannel
    local txId = (tx and tx.txId) or payload.transactionId

    local fwd = {
        transactionId = txId,
        action = "COMMIT",
        oldBaseChannel = oldBase,
        newBaseChannel = newBase,
        bandwidth = 40,
    }
    transmit_packet(ctx, oldBase + 1, oldBase + 1, "MSG_CHANNEL_REBIND", fwd)

    local m = ctx.modem
    if m and m.close then
        m.close(oldBase + 4)
        m.close(oldBase + 2)
        m.close(oldBase + 1)
    end
    if m and m.open then
        m.open(newBase + 4)
        m.open(newBase + 2)
        m.open(newBase + 1)
    end

    ctx.baseChannel = newBase
    ctx.channels = { trajectory = newBase + 4, telemetry = newBase + 2, guidance = newBase + 1 }
    persist_config(ctx)
    ctx.rebindTx = nil
    return true
end

local function handle_rebind_rollback(ctx, payload)
    local tx = ctx.rebindTx
    local oldBase = (tx and tx.oldBase) or tonumber(payload and payload.oldBaseChannel) or ctx.baseChannel
    local newBase = (tx and tx.newBase) or tonumber(payload and payload.newBaseChannel)
    local txId = (tx and tx.txId) or (payload and payload.transactionId)

    local fwd = {
        transactionId = txId,
        action = "ROLLBACK",
        oldBaseChannel = oldBase,
        newBaseChannel = newBase,
        bandwidth = 40,
    }
    transmit_packet(ctx, oldBase + 1, oldBase + 1, "MSG_CHANNEL_REBIND", fwd)

    if newBase and ctx.modem and ctx.modem.close then
        ctx.modem.close(newBase + 4)
        ctx.modem.close(newBase + 2)
        ctx.modem.close(newBase + 1)
    end
    ctx.rebindTx = nil
    return true
end

local function dispatch_trajectory(ctx, pkt, now_ms)
    local t = pkt.type
    local p = pkt.payload or {}
    if t == "MSG_TRAJECTORY_SETPOINT" then
        ctx.inbound.trajectory = pkt
        return true
    elseif t == "MSG_CHANNEL_REBIND" then
        if p.action == "PREPARE" then
            return handle_rebind_prepare(ctx, p, now_ms)
        elseif p.action == "COMMIT" then
            return handle_rebind_commit(ctx, p, now_ms)
        elseif p.action == "ROLLBACK" then
            return handle_rebind_rollback(ctx, p)
        end
    end
    return false
end

local function dispatch_guidance(ctx, pkt)
    local t = pkt.type
    local p = pkt.payload or {}
    if t == "MSG_CHANNEL_REBIND_ACK" then
        if ctx.rebindTx and p.transactionId == ctx.rebindTx.txId then
            local st = (p.status == "FAILED") and "FAILED" or "READY"
            ctx.rebindTx.status = (st == "READY") and "ACKED" or "FAILED"
            local ackFwd = {
                transactionId = p.transactionId,
                nodeId = "FCP",
                action = p.action or "PREPARE",
                status = st,
                oldBaseChannel = ctx.rebindTx.oldBase,
                newBaseChannel = ctx.rebindTx.newBase,
                subNodesReady = p.subNodesReady,
            }
            transmit_packet(ctx, ctx.rebindTx.oldBase + 4, ctx.rebindTx.oldBase + 4, "MSG_CHANNEL_REBIND_ACK", ackFwd)
            if st == "FAILED" then
                handle_rebind_rollback(ctx, {
                    transactionId = ctx.rebindTx.txId,
                    oldBaseChannel = ctx.rebindTx.oldBase,
                    newBaseChannel = ctx.rebindTx.newBase,
                })
            end
        end
        return true
    elseif t == "MSG_EMERGENCY_ALERT" then
        ctx.inbound.emergencyAlert = pkt
        return true
    end
    return false
end

function network_manager.ingest_modem_event(ctx, side, ch, reply_ch, msg, dist, now_ms)
    local pkt = safe_unserialize(msg)
    if not pkt or not network_manager.verify_packet(ctx, pkt) then return false end

    local isTraj = (ch == ctx.channels.trajectory) or (ctx.rebindTx and ch == ctx.rebindTx.newBase + 4)
    local isTelem = (ch == ctx.channels.telemetry) or (ctx.rebindTx and ch == ctx.rebindTx.newBase + 2)
    local isGuid = (ch == ctx.channels.guidance) or (ctx.rebindTx and ch == ctx.rebindTx.newBase + 1)

    if isTraj then
        return dispatch_trajectory(ctx, pkt, now_ms)
    elseif isTelem then
        if pkt.type == "MSG_FLIGHT_TELEMETRY" then
            ctx.inbound.telemetry = pkt
            return true
        end
    elseif isGuid then
        return dispatch_guidance(ctx, pkt)
    end
    return false
end

function network_manager.poll_inbound(ctx)
    local res = {
        trajectory = ctx.inbound.trajectory,
        telemetry = ctx.inbound.telemetry,
        emergencyAlert = ctx.inbound.emergencyAlert,
        rebindAck = ctx.inbound.rebindAck,
    }
    ctx.inbound.trajectory = nil
    ctx.inbound.telemetry = nil
    ctx.inbound.emergencyAlert = nil
    ctx.inbound.rebindAck = nil
    return res
end

function network_manager.poll_all(ctx)
    return network_manager.poll_inbound(ctx)
end

function network_manager.step_rebind_watchdog(ctx, now_ms)
    if not ctx or not ctx.rebindTx then return nil end
    local tx = ctx.rebindTx
    if tx.status == "PREPARE" then
        local now = now_ms or (os.epoch and os.epoch("utc") or 0)
        if (now - tx.startMs) > 500 then
            local failAck = {
                transactionId = tx.txId,
                nodeId = "FCP",
                action = "PREPARE",
                status = "FAILED",
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
            }
            transmit_packet(ctx, tx.oldBase + 4, tx.oldBase + 4, "MSG_CHANNEL_REBIND_ACK", failAck)
            handle_rebind_rollback(ctx, {
                transactionId = tx.txId,
                oldBaseChannel = tx.oldBase,
                newBaseChannel = tx.newBase,
            })
            return "ROLLED_BACK"
        end
    end
    return tx.status
end

function network_manager.send_attitude_cmd(ctx, payload)
    return transmit_packet(ctx, ctx.channels.guidance, ctx.channels.guidance, "MSG_ATTITUDE_CMD", payload)
end

function network_manager.send_guidance_cmd(ctx, payload)
    return network_manager.send_attitude_cmd(ctx, payload)
end

function network_manager.send_outer_loop_status(ctx, payload)
    return transmit_packet(ctx, ctx.channels.trajectory, ctx.channels.trajectory, "MSG_OUTER_LOOP_STATUS", payload)
end

function network_manager.send_channel_rebind(ctx, payload)
    local ch = (ctx.channels and ctx.channels.guidance) or (ctx.baseChannel + 1)
    return transmit_packet(ctx, ch, ch, "MSG_CHANNEL_REBIND", payload)
end

function network_manager.bind_aircraft_channels(ctx, base_ch)
    local b = base_ch or ctx.baseChannel
    ctx.baseChannel = b
    ctx.channels = { trajectory = b + 4, telemetry = b + 2, guidance = b + 1 }
    local m = ctx.modem
    if m and m.open then
        m.open(ctx.channels.trajectory)
        m.open(ctx.channels.telemetry)
        m.open(ctx.channels.guidance)
    end
end

function network_manager.rebind_aircraft_channels(ctx, new_base)
    local old_b = ctx.baseChannel
    local m = ctx.modem
    if m and m.close then
        m.close(old_b + 4)
        m.close(old_b + 2)
        m.close(old_b + 1)
    end
    network_manager.bind_aircraft_channels(ctx, new_base)
end

return network_manager
