-- GPS Central Server Daemon (Gate 3 UI & Gate 4 Cluster Node #0)
local protocol = require("protocol")
local session_scheduler = require("session_scheduler")
local storage_hal = require("storage_hal")
local monitor_ui = require("monitor_ui")
local radar_math = require("radar_math")

local function initServer()
    local modem = peripheral.find("modem")
    if modem then
        modem.open(protocol.CH_GPS_SERVICE)
        modem.open(protocol.CH_GPS_NODE_IN)
        modem.open(protocol.CH_GPS_MGMT)
    end
    local registry = storage_hal.readJson("/gps_data/nodes.json") or { nodes = {} }
    local scheduler = session_scheduler.new({ windowMs = 50, tombstoneTtlMs = 1000 })
    local mon = peripheral.find("monitor")
    local ui = nil
    if mon then
        pcall(mon.setTextScale, 0.5)
        ui = monitor_ui.new({ width = 79, height = 36 })
    end
    local state = {
        ticks = 0, solvedCount = 0, seq = 1,
        lastSolvedStatus = "NOMINAL", activeNodes = 0,
        nodes = {}, clients = {}, totalSolves = 0
    }
    for _, nd in pairs(registry.nodes or {}) do
        table.insert(state.nodes, { id = nd.id, x = nd.x, y = nd.y, z = nd.z, status = "ONLINE" })
    end
    state.activeNodes = #state.nodes
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
    local action, earlyPayload = scheduler:ingestReport(msg.payload, registry, nowMs)
    if action == "EARLY_SOLVED" and earlyPayload and modem then
        state.solvedCount = state.solvedCount + 1
        state.totalSolves = state.solvedCount
        state.lastSolvedStatus = earlyPayload.status
        if harness_set_state then harness_set_state("last_solved_status", earlyPayload.status) end
        state.seq = state.seq + 1
        local pkt = protocol.buildResponse("GPS_BASE_NET", state.seq, earlyPayload, nowMs)
        modem.transmit(earlyPayload.replyChannel, protocol.CH_GPS_SERVICE, pkt)
    end
end

local function handleHeartbeat(state, msg)
    if not msg.payload or not msg.payload.nodeId then return end
    local nid = msg.payload.nodeId
    for _, n in ipairs(state.nodes) do
        if n.id == nid then
            n.status = msg.payload.status or "ONLINE"
            return
        end
    end
    local pos = msg.payload.position or { x = 0, y = 0, z = 0 }
    table.insert(state.nodes, {
        id = nid, x = pos.x, y = pos.y, z = pos.z,
        status = msg.payload.status or "ONLINE"
    })
    state.activeNodes = #state.nodes
end

local function flushTimerExpired(scheduler, registry, modem, state)
    local nowMs = os.epoch and os.epoch("utc") or 0
    local solved = scheduler:flushExpired(registry, nowMs)
    for _, item in ipairs(solved) do
        state.solvedCount = state.solvedCount + 1
        state.totalSolves = state.solvedCount
        state.lastSolvedStatus = item.payload.status
        if harness_set_state then harness_set_state("last_solved_status", item.payload.status) end
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
        elseif msg.type == protocol.MSG_HEARTBEAT then
            handleHeartbeat(state, msg)
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

main()
