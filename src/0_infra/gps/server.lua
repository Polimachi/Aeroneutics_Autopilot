-- GPS Central Server Daemon (Gate 3 UI & Gate 4 Cluster Node #0)
local protocol = require("protocol")
local session_scheduler = require("session_scheduler")
local storage_hal = require("storage_hal")
local monitor_ui = require("monitor_ui")
local radar_math = require("radar_math")
local config_store = require("config_store")

local function countOnlineNodes(nodes)
    local c = 0
    for _, n in ipairs(nodes or {}) do
        if n.status == "ONLINE" then c = c + 1 end
    end
    return c
end

local function upsertClient(state, clientId, payload, altitudeY, nowMs)
    if not payload or type(payload.position) ~= "table" or not clientId or clientId == "" then return end
    local cid = tostring(clientId)
    local altY = tonumber(altitudeY) or 0
    for _, c in ipairs(state.clients) do
        if c.id == cid then
            c.x = tonumber(payload.position.x) or c.x
            c.y = altY
            c.z = tonumber(payload.position.z) or c.z
            c.lastSeenMs = nowMs
            c.lastSeen = 0
            return
        end
    end
    table.insert(state.clients, {
        id = cid,
        x = tonumber(payload.position.x) or 0,
        y = altY,
        z = tonumber(payload.position.z) or 0,
        lastSeenMs = nowMs,
        lastSeen = 0,
    })
    state.clientCount = #state.clients
end

local function refreshClientAges(state, nowMs)
    for _, c in ipairs(state.clients or {}) do
        c.lastSeen = math.max(0, (nowMs - (c.lastSeenMs or nowMs)) / 1000.0)
    end
    state.clientCount = #(state.clients or {})
end

local function initServer()
    local modem = peripheral.find("modem")
    if modem then
        modem.open(protocol.CH_GPS_SERVICE)
        modem.open(protocol.CH_GPS_NODE_IN)
        modem.open(protocol.CH_GPS_MGMT)
    end
    local rawNodes = storage_hal.readJson("/gps_data/nodes.json")
    local registry = config_store.normalizeServerRegistry(rawNodes)
    local scheduler = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
    local mon = peripheral.find("monitor")
    local ui = nil
    if mon then
        pcall(mon.setTextScale, 0.5)
        ui = monitor_ui.new({ width = 79, height = 36 })
    end
    local state = {
        ticks = 0, solvedCount = 0, seq = 1,
        lastSolvedStatus = "NOMINAL", activeNodes = 0, clientCount = 0,
        listenChan = protocol.CH_GPS_PING, dataChan = protocol.CH_GPS_SERVICE,
        nodes = {}, clients = {}, totalSolves = 0
    }
    local nodeKeys = {}
    for k in pairs(registry.nodes or {}) do
        table.insert(nodeKeys, k)
    end
    table.sort(nodeKeys)
    for _, k in ipairs(nodeKeys) do
        local nd = registry.nodes[k]
        local pos = type(nd.position) == "table" and nd.position or {}
        table.insert(state.nodes, {
            id = tostring(nd.nodeId),
            x = tonumber(pos.x) or 0,
            y = tonumber(pos.y) or 0,
            z = tonumber(pos.z) or 0,
            status = nd.status or "ONLINE",
            ping = 0,
        })
    end
    state.activeNodes = countOnlineNodes(state.nodes)
    return modem, registry, scheduler, state, mon, ui
end

local function renderConsole(termDev, state)
    local w, _ = termDev.getSize()
    termDev.setBackgroundColor(colors.black)
    termDev.setTextColor(colors.yellow)
    termDev.setCursorPos(1, 1)
    local header = "CC-GPS SERVER v1.9.5 [HEADLESS]"
    termDev.write(header .. string.rep(" ", math.max(0, w - #header)))
    termDev.setTextColor(colors.white)
    termDev.setCursorPos(1, 2)
    termDev.write(string.rep("-", w))
    termDev.setCursorPos(1, 3)
    termDev.setTextColor(colors.green)
    termDev.write("STATUS: NOMINAL")
    termDev.setCursorPos(1, 5)
    termDev.setTextColor(colors.lightGray)
    termDev.write(string.format("Active Nodes: %d | Solved: %d", state.activeNodes or 0, state.solvedCount or 0))
    termDev.setCursorPos(1, 6)
    termDev.write(string.format("Uptime Ticks: %d", state.ticks or 0))
    termDev.setCursorPos(1, 8)
    termDev.setTextColor(colors.cyan)
    termDev.write("[CHANNELS] 60002:SVC  60003:NODE_IN  60004:MGMT")
end

local function handleNodeReport(scheduler, registry, modem, state, msg)
    local ok = protocol.validatePacket(msg, protocol.MSG_NODE_REPORT)
    if not ok then return end
    local nowMs = os.epoch and os.epoch("utc") or 0
    local action, earlyPayload, earlyReplyCh = scheduler:ingestReport(msg.payload, registry, nowMs)
    if action == "EARLY_SOLVED" and earlyPayload then
        state.solvedCount = state.solvedCount + 1
        state.totalSolves = state.solvedCount
        state.lastSolvedStatus = earlyPayload.status
        upsertClient(state, earlyPayload.targetClient, earlyPayload, msg.payload.clientAltitudeY, nowMs)
        if harness_set_state then harness_set_state("last_solved_status", earlyPayload.status) end
        if modem and earlyReplyCh and earlyReplyCh > 0 then
            state.seq = state.seq + 1
            local pkt = protocol.buildResponse("GPS_BASE_NET", state.seq, earlyPayload, nowMs)
            modem.transmit(earlyReplyCh, protocol.CH_GPS_SERVICE, pkt)
        end
    end
end

local function handleHeartbeat(state, msg, registry)
    local ok = protocol.validatePacket(msg, protocol.MSG_NODE_HEARTBEAT)
    if not ok or type(msg.payload) ~= "table" or not msg.payload.nodeId then return end
    local nid = tostring(msg.payload.nodeId)
    local pos = type(msg.payload.pos) == "table" and msg.payload.pos or nil
    local nextStatus = msg.payload.status or "ONLINE"
    if registry and type(registry.nodes) == "table" then
        if registry.nodes[nid] then
            registry.nodes[nid].status = nextStatus
            registry.nodes[nid].lastHeartbeat = msg.time or (os.epoch and os.epoch("utc") or 0)
            if pos then
                registry.nodes[nid].position = {
                    x = tonumber(pos.x) or (registry.nodes[nid].position and registry.nodes[nid].position.x) or 0,
                    y = tonumber(pos.y) or (registry.nodes[nid].position and registry.nodes[nid].position.y) or 0,
                    z = tonumber(pos.z) or (registry.nodes[nid].position and registry.nodes[nid].position.z) or 0,
                }
            end
        elseif next(registry.nodes) ~= nil then
            return
        end
    end
    for _, n in ipairs(state.nodes) do
        if n.id == nid then
            n.status = nextStatus
            if pos then
                n.x = tonumber(pos.x) or n.x
                n.y = tonumber(pos.y) or n.y
                n.z = tonumber(pos.z) or n.z
            end
            state.activeNodes = countOnlineNodes(state.nodes)
            return
        end
    end
    table.insert(state.nodes, {
        id = nid,
        x = pos and (tonumber(pos.x) or 0) or 0,
        y = pos and (tonumber(pos.y) or 0) or 0,
        z = pos and (tonumber(pos.z) or 0) or 0,
        status = nextStatus,
        ping = 0,
    })
    state.activeNodes = countOnlineNodes(state.nodes)
end

local function handleStatusRequest(modem, state, evData)
    local msg = evData[5]
    local ok = protocol.validatePacket(msg, protocol.MSG_STATUS_REQ)
    if not ok or not modem then return end
    local replyCh = tonumber(evData[4])
    if not replyCh or replyCh < 1 or replyCh > 65535 then
        replyCh = protocol.CH_GPS_SERVICE
    end
    local nowMs = os.epoch and os.epoch("utc") or 0
    state.seq = state.seq + 1
    local pkt = protocol.buildStatusResp("GPS_BASE_NET", state.seq, {
        activeNodes = state.activeNodes or 0,
        uptime = math.floor((state.ticks or 0) / 20),
        totalSolved = state.solvedCount or 0,
        version = protocol.WIRE_VERSION,
    }, nowMs)
    modem.transmit(replyCh, protocol.CH_GPS_SERVICE, pkt)
end

local function flushTimerExpired(scheduler, registry, modem, state)
    local nowMs = os.epoch and os.epoch("utc") or 0
    local solved = scheduler:flushExpired(registry, nowMs)
    for _, item in ipairs(solved) do
        local st = item.payload and item.payload.status
        if st == "FIX_OK" or st == "FIX_DEGRADED" then
            state.solvedCount = state.solvedCount + 1
            state.totalSolves = state.solvedCount
        end
        state.lastSolvedStatus = st
        if item.payload and item.payload.position then
            upsertClient(state, item.payload.targetClient, item.payload, item.clientAltitudeY, nowMs)
        end
        if harness_set_state then harness_set_state("last_solved_status", st) end
        if modem and item.replyChannel and item.replyChannel > 0 then
            state.seq = state.seq + 1
            local pkt = protocol.buildResponse("GPS_BASE_NET", state.seq, item.payload, nowMs)
            modem.transmit(item.replyChannel, protocol.CH_GPS_SERVICE, pkt)
        end
    end
end

local function handleUiAction(action, state)
    if (action == "ACTION_REFRESH" or action == "ACTION_REFIT") and #state.nodes > 0 then
        state.bounds = radar_math.computeCentroidSpan(state.nodes, 1.2)
    end
end

local function handleModemMsg(scheduler, registry, modem, state, evData)
    local channel, msg = evData[3], evData[5]
    if channel == protocol.CH_GPS_NODE_IN and type(msg) == "table" then
        if msg.type == protocol.MSG_NODE_REPORT then
            handleNodeReport(scheduler, registry, modem, state, msg)
        elseif msg.type == protocol.MSG_NODE_HEARTBEAT then
            handleHeartbeat(state, msg, registry)
        end
    elseif channel == protocol.CH_GPS_SERVICE and type(msg) == "table" then
        if msg.type == protocol.MSG_STATUS_REQ then
            handleStatusRequest(modem, state, evData)
        end
    end
end

local function serverEventLoop(modem, scheduler, registry, state, termDev, mon, ui)
    local tickTimer = os.startTimer(0.05)
    while true do
        local evData = { os.pullEvent() }
        local ev = evData[1]
        if ev == "terminate" then break
        elseif ev == "timer" and evData[2] == tickTimer then
            tickTimer = os.startTimer(0.05)
            state.ticks = state.ticks + 1
            flushTimerExpired(scheduler, registry, modem, state)
            if state.ticks % 2 == 0 then
                renderConsole(termDev, state)
                refreshClientAges(state, os.epoch and os.epoch("utc") or 0)
                if mon and ui then ui:render(mon, state) end
            end
            if harness_set_state and state.solvedCount >= 1 then sleep(0.1); break end
        elseif ev == "monitor_touch" and ui then
            local act = ui:handleTouch(evData[3], evData[4])
            if act then handleUiAction(act, state) end
        elseif ev == "peripheral" and peripheral.getType(evData[2]) == "monitor" then
            mon = peripheral.wrap(evData[2])
            pcall(mon.setTextScale, 0.5)
            ui = monitor_ui.new({ width = 79, height = 36 })
        elseif ev == "peripheral_detach" then
            mon = peripheral.find("monitor")
            if not mon then ui = nil end
        elseif ev == "modem_message" then
            handleModemMsg(scheduler, registry, modem, state, evData)
        end
    end
end

local function main()
    local modem, registry, scheduler, state, mon, ui = initServer()
    local termDev = term.current()
    termDev.clear()
    renderConsole(termDev, state)
    if mon and ui then ui:render(mon, state) end
    serverEventLoop(modem, scheduler, registry, state, termDev, mon, ui)
end

local args = { ... }
local isRequired = (_G.describe ~= nil) or (type(args[2]) == "string" and args[2]:sub(-4) == ".lua")
if not isRequired then
    main()
end

return {
    initServer = initServer,
    handleNodeReport = handleNodeReport,
    handleHeartbeat = handleHeartbeat,
    handleStatusRequest = handleStatusRequest,
    flushTimerExpired = flushTimerExpired,
    handleModemMsg = handleModemMsg,
    run = main,
}
