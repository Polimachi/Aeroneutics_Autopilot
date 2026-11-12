-- Interactive CLI wizard for node commissioning
local commissioning = require("commissioning")
local protocol = require("protocol")
local storage_hal = require("storage_hal")

local wizard_cli = {}

local function waitForPacket(modem, listenCh, expectedType, timeoutSec)
    modem.open(listenCh)
    local tId = os.startTimer(timeoutSec or 3.0)
    while true do
        local eventData = { os.pullEvent() }
        local ev = eventData[1]
        if ev == "timer" and eventData[2] == tId then
            return nil, "TIMEOUT"
        elseif ev == "modem_message" then
            local ch = eventData[3]
            local msg = eventData[5]
            if ch == listenCh and type(msg) == "table" and msg.type == expectedType then
                return msg.payload, nil
            end
        end
    end
end

local function stepHello(modem, fsm)
    print("\n[1/4] Scanning Central Server on CH " .. protocol.CH_GPS_NODE_IN .. "...")
    local helloPkt = fsm:buildHelloPacket(os.epoch("utc"))
    modem.transmit(protocol.CH_GPS_NODE_IN, protocol.CH_GPS_MGMT, helloPkt)
    local offer, err = waitForPacket(modem, protocol.CH_GPS_MGMT, protocol.MSG_NODE_OFFER, 2.0)
    if offer then
        fsm:handleOffer(offer)
        print("  > Server Offer Received: " .. fsm.nodeId)
    else
        fsm:handleOffer({ suggestedNodeId = "NODE_" .. tostring(fsm.computerId) })
        print("  > Server timeout (" .. tostring(err) .. "). Defaulting to: " .. fsm.nodeId)
    end
end

local function stepCoords(fsm)
    print("\n[2/4] Enter Node Position (Minecraft F3: \"X Y Z\"):")
    while true do
        write("  > Enter Pos: ")
        local input = read()
        local ok, pos = commissioning.parseF3Coords(input)
        if ok then
            fsm:setCoordinates(pos)
            print(string.format("  > Position Accepted: (%d, %d, %d)", pos.x, pos.y, pos.z))
            break
        else
            print("  [ERROR] Invalid format. Example: 1200 140 -350")
        end
    end
end

local function stepVerify(modem, fsm)
    print("\n[3/4] Cross-Verifying Position with Swarm...")
    local vReq = fsm:buildVerifyReqPacket(os.epoch("utc"))
    modem.transmit(protocol.CH_GPS_NODE_IN, protocol.CH_GPS_MGMT, vReq)
    local vResp, _ = waitForPacket(modem, protocol.CH_GPS_MGMT, protocol.MSG_NODE_VERIFY_RESP, 2.5)
    if vResp then
        fsm:handleVerifyResp(vResp)
        local passed = vResp.passed == true
        print(string.format("  > Swarm Max Residual: %.2fm [%s]", vResp.maxResidual or 0, passed and "PASSED" or "WARN"))
    else
        fsm:handleVerifyResp({ passed = true, maxResidual = 0 })
        print("  > Standalone Mode: Bypassing swarm cross-verification.")
    end
end

local function stepCommit(modem, fsm, nodeCfgPath)
    print("\n[4/4] Finalizing Registration...")
    local cReq = fsm:buildCommitPacket(os.epoch("utc"))
    modem.transmit(protocol.CH_GPS_NODE_IN, protocol.CH_GPS_MGMT, cReq)
    local ack, _ = waitForPacket(modem, protocol.CH_GPS_MGMT, protocol.MSG_NODE_REG_ACK, 2.0)
    if ack then
        fsm:handleRegAck(ack)
        print("  > Server Registration ACK received.")
    else
        fsm:handleRegAck({ status = "COMMITTED" })
        print("  > Local registration completed.")
    end

    local cfg = {
        version = "1.9.5",
        nodeId = fsm.nodeId,
        computerId = fsm.computerId,
        position = fsm.position,
        channels = { ping = protocol.CH_GPS_PING, service = protocol.CH_GPS_SERVICE, nodeIn = protocol.CH_GPS_NODE_IN, mgmt = protocol.CH_GPS_MGMT },
        modemSide = "top",
    }
    local okWrite, errWrite = storage_hal.writeJsonAtomic(nodeCfgPath or "/gps_data/node.json", cfg)
    if not okWrite then
        error("Failed to write node config: " .. tostring(errWrite), 2)
    end
    print("  > Configuration saved to " .. (nodeCfgPath or "/gps_data/node.json"))
    return cfg
end

function wizard_cli.runWizard(modem, fsm, nodeCfgPath)
    term.clear()
    term.setCursorPos(1, 1)
    print("=======================================================================")
    print("[ CC:TWEAKED GPS NODE SETUP WIZARD v1.9.5 ]")
    print("=======================================================================")

    stepHello(modem, fsm)
    stepCoords(fsm)
    stepVerify(modem, fsm)
    local cfg = stepCommit(modem, fsm, nodeCfgPath)

    print("\n>> Node [" .. tostring(fsm.nodeId) .. "] is now ONLINE!")
    print("=======================================================================")
    return cfg
end

return wizard_cli
