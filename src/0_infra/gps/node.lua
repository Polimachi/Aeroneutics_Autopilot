-- GPS Swarm Node Daemon (Gate 4 Cluster Node)
local commissioning = require("commissioning")
local config_store = require("config_store")
local protocol = require("protocol")
local storage_hal = require("storage_hal")
local wizard_cli = require("wizard_cli")

local function runCountdown(fsm)
    term.clear()
    term.setCursorPos(1, 1)
    print("=======================================================================")
    print(string.format("[ GPS SWARM NODE BOOT: CompID %d ]", fsm.computerId))
    print("Press [S] within 3 seconds to enter Setup Wizard...")
    print("=======================================================================")

    local timerId = os.startTimer(3.0)
    while true do
        local eventData = { os.pullEvent() }
        local ev = eventData[1]
        if ev == "timer" and eventData[2] == timerId then
            fsm:handleEvent("COUNTDOWN_TIMEOUT")
            break
        elseif ev == "char" and (eventData[2] == "s" or eventData[2] == "S") then
            fsm:handleEvent("KEY_PRESSED", { key = "s" })
            break
        elseif ev == "key" and eventData[2] == 31 then -- key 's' code
            fsm:handleEvent("KEY_PRESSED", { key = "s" })
            break
        end
    end
end

local function loadOrCommissionNode(args, modem)
    local cfg = config_store.parseNodeCliArgs(args)
    if cfg then return cfg end

    cfg = storage_hal.readJson("/gps_data/node.json")
    local compId = os.getComputerID and os.getComputerID() or 0
    local fsm = commissioning.newFSM({ hasConfig = (cfg ~= nil), computerId = compId })

    if fsm:getState() == "COUNTDOWN_3S" then
        runCountdown(fsm)
    end
    if fsm:getState() == "SETUP_WIZARD" then
        cfg = wizard_cli.runWizard(modem, fsm, "/gps_data/node.json")
    end
    if not cfg or not cfg.nodeId then
        error("Node configuration missing (provide CLI args or /gps_data/node.json)", 2)
    end
    return cfg
end

local function handlePingMessage(modem, nodeCfg, channel, msg, distance, state)
    if channel ~= protocol.CH_GPS_PING or type(msg) ~= "table" then return end
    local ok = protocol.validatePacket(msg, protocol.MSG_REQUEST)
    if not ok then return end

    local req = msg.payload
    local nowMs = os.epoch and os.epoch("utc") or 0
    local measuredDist = tonumber(distance) or 0.0
    state.reportSeq = (state.reportSeq or 0) + 1
    local reportPkt = protocol.buildNodeReport(nodeCfg.nodeId, state.reportSeq, {
        targetClient = msg.domainId,
        clientSeq = req.clientSeq,
        nodeId = nodeCfg.nodeId,
        nodePos = {
            x = nodeCfg.position.x,
            y = nodeCfg.position.y,
            z = nodeCfg.position.z,
        },
        measuredDistance = measuredDist,
        clientAltitudeY = req.altitudeY,
        replyChannel = req.replyChannel,
    }, nowMs)

    modem.transmit(protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, reportPkt)
    state.reportsSent = state.reportsSent + 1
    if harness_set_state then harness_set_state("reports_sent", state.reportsSent) end
    print(string.format("[%s] Dist=%.1fm for %s#%s", nodeCfg.nodeId, measuredDist, tostring(msg.domainId), tostring(req.clientSeq)))
end

local function sendHeartbeat(modem, nodeCfg, state)
    local nowMs = os.epoch and os.epoch("utc") or 0
    state.hbSeq = state.hbSeq + 1
    local hbPkt = protocol.buildHeartbeat(nodeCfg.nodeId, state.hbSeq, {
        nodeId = nodeCfg.nodeId,
        computerId = nodeCfg.computerId,
        pos = nodeCfg.position,
        status = "ONLINE",
        uptime = state.ticks,
        reportsSent = state.reportsSent,
    }, nowMs)
    modem.transmit(protocol.CH_GPS_NODE_IN, protocol.CH_GPS_PING, hbPkt)
    state.heartbeatsSent = state.heartbeatsSent + 1
    if harness_set_state then harness_set_state("heartbeats_sent", state.heartbeatsSent) end
end

local function nodeEventLoop(modem, nodeCfg, state)
    local hbTimer = os.startTimer(10.0)
    while true do
        local eventData = { os.pullEvent() }
        local ev = eventData[1]
        if ev == "terminate" then
            print("Node terminated cleanly.")
            break
        elseif ev == "timer" and eventData[2] == hbTimer then
            hbTimer = os.startTimer(10.0)
            state.ticks = state.ticks + 10
            sendHeartbeat(modem, nodeCfg, state)
        elseif ev == "modem_message" then
            handlePingMessage(modem, nodeCfg, eventData[3], eventData[5], eventData[6], state)
            if harness_set_state and state.reportsSent >= 1 then
                sleep(0.05)
                break
            end
        end
    end
end

local function main(...)
    local args = { ... }
    local modem = peripheral.find("modem")
    if not modem then error("No modem attached for GPS node", 2) end
    modem.open(protocol.CH_GPS_PING)

    local nodeCfg = loadOrCommissionNode(args, modem)

    term.clear()
    term.setCursorPos(1, 1)
    print(string.format("=== GPS NODE %s ===", nodeCfg.nodeId))
    print(string.format("Pos: (%d, %d, %d)", nodeCfg.position.x, nodeCfg.position.y, nodeCfg.position.z))
    print(string.format("CH %d -> CH %d", protocol.CH_GPS_PING, protocol.CH_GPS_NODE_IN))

    local state = { reportsSent = 0, reportSeq = 0, heartbeatsSent = 0, hbSeq = 0, ticks = 0 }
    if harness_set_state then harness_set_state("reports_sent", 0) end
    nodeEventLoop(modem, nodeCfg, state)
end

local args = { ... }
local isRequired = (_G.describe ~= nil) or (type(args[2]) == "string" and args[2]:sub(-4) == ".lua")
if not isRequired then
    main(...)
end

return {
    loadOrCommissionNode = loadOrCommissionNode,
    handlePingMessage = handlePingMessage,
    sendHeartbeat = sendHeartbeat,
    run = main,
}
