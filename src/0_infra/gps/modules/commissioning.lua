-- Pure FSM and coordinate parser for node commissioning
local protocol = require("protocol")

local commissioning = {}

function commissioning.parseF3Coords(str)
    if type(str) ~= "string" then return false, "INVALID_STRING" end
    local parts = {}
    for part in string.gmatch(str, "%S+") do
        local num = tonumber(part)
        if not num then return false, "INVALID_COORDINATES" end
        table.insert(parts, num)
    end
    if #parts ~= 3 then return false, "INVALID_COORDINATE_COUNT" end
    return true, { x = parts[1], y = parts[2], z = parts[3] }
end

local FSM = {}
FSM.__index = FSM

function FSM:getState()
    return self.state
end

function FSM:getWizardStep()
    return self.wizardStep
end

function FSM:handleEvent(evType, data)
    if self.state == "COUNTDOWN_3S" then
        if evType == "KEY_PRESSED" and data and (data.key == "s" or data.key == "S") then
            self.state = "SETUP_WIZARD"
            self.wizardStep = "HELLO"
        elseif evType == "COUNTDOWN_TIMEOUT" then
            self.state = "DAEMON_RUN"
        end
    end
end

function FSM:buildHelloPacket(nowMs)
    return protocol.buildEnvelope(self.computerId, 1, protocol.MSG_NODE_HELLO, {
        computerId = self.computerId,
    }, nowMs)
end

function FSM:handleOffer(offerPayload)
    if not offerPayload then return false end
    self.nodeId = tostring(offerPayload.suggestedNodeId or ("NODE_" .. tostring(self.computerId)))
    self.wizardStep = "COORDS"
    return true
end

function FSM:setCoordinates(pos)
    if type(pos) ~= "table" or type(pos.x) ~= "number" then return false end
    self.position = { x = pos.x, y = pos.y, z = pos.z }
    self.wizardStep = "VERIFY"
    return true
end

function FSM:buildVerifyReqPacket(nowMs)
    return protocol.buildEnvelope(self.nodeId or self.computerId, 1, protocol.MSG_NODE_VERIFY_REQ, {
        nodeId = self.nodeId,
        computerId = self.computerId,
        nodePos = self.position,
    }, nowMs)
end

function FSM:handleVerifyResp(respPayload)
    if not respPayload then return false end
    self.verifyPassed = respPayload.passed == true
    self.maxResidual = tonumber(respPayload.maxResidual) or 0
    self.wizardStep = "COMMIT"
    return true
end

function FSM:buildCommitPacket(nowMs)
    return protocol.buildEnvelope(self.nodeId or self.computerId, 1, protocol.MSG_NODE_REG_COMMIT, {
        nodeId = self.nodeId,
        computerId = self.computerId,
        nodePos = self.position,
        passed = self.verifyPassed,
    }, nowMs)
end

function FSM:handleRegAck(ackPayload)
    if not ackPayload then return false end
    self.state = "DAEMON_RUN"
    return true
end

function commissioning.newFSM(opts)
    local o = opts or {}
    local instance = {
        hasConfig = o.hasConfig == true,
        computerId = tonumber(o.computerId) or (os.getComputerID and os.getComputerID() or 0),
        state = (o.hasConfig == true) and "COUNTDOWN_3S" or "SETUP_WIZARD",
        wizardStep = "HELLO",
        nodeId = nil,
        position = nil,
        verifyPassed = false,
        maxResidual = 0,
    }
    setmetatable(instance, FSM)
    return instance
end

return commissioning
