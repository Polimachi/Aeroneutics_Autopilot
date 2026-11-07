-- Dynamic session bucket scheduler and 2-tier late report defense for CC:Tweaked GPS
local protocol = require("protocol")
local trilateration = require("trilateration")
local config_store = require("config_store")

local session_scheduler = {}
session_scheduler.__index = session_scheduler

function session_scheduler.new(opts)
    local o = opts or {}
    local self = setmetatable({}, session_scheduler)
    self.windowMs = tonumber(o.windowMs) or 50
    self.tombstoneTtlMs = tonumber(o.tombstoneTtlMs) or 1000
    self.tombstoneCap = tonumber(o.tombstoneCap) or 1024
    self.rebootResetMs = tonumber(o.rebootResetMs) or 5000
    self.active_sessions = {}
    self.completed_tombstones = {}
    self.tombstone_order = {}
    self.client_last_solved = {}
    self.client_last_solve_time = {}
    return self
end

function session_scheduler:addTombstone(sessionKey, expireMs)
    if not self.completed_tombstones[sessionKey] then
        if #self.tombstone_order >= self.tombstoneCap then
            local oldest = table.remove(self.tombstone_order, 1)
            self.completed_tombstones[oldest] = nil
        end
        table.insert(self.tombstone_order, sessionKey)
    end
    self.completed_tombstones[sessionKey] = expireMs
end

local function checkDefenseFilters(self, targetClient, clientSeq, sessionKey, nowMs)
    local lastTime = self.client_last_solve_time[targetClient]
    if lastTime and (nowMs - lastTime) >= self.rebootResetMs then
        self.client_last_solved[targetClient] = nil
        self.client_last_solve_time[targetClient] = nil
    end
    local lastSolved = self.client_last_solved[targetClient]
    if lastSolved and clientSeq <= lastSolved then
        return "DROPPED", "HIGH_WATERMARK"
    end
    local tbExpire = self.completed_tombstones[sessionKey]
    if tbExpire then
        if nowMs < tbExpire then return "DROPPED", "TOMBSTONE" end
        self.completed_tombstones[sessionKey] = nil
    end
    return "OK", nil
end

local function tryEarlySolve(self, session, registry, nowMs)
    if #session.reportsList < 4 then return nil end
    local proj = trilateration.projectHorizontal(session.reportsList, session.clientAltitudeY)
    local optimal = trilateration.selectOptimalNodes(proj, 6)
    if not optimal or #optimal < 4 then return nil end
    local bbox = config_store.computeSwarmBBox(registry, session.reportsList)
    local sol = trilateration.solve(session.reportsList, session.clientAltitudeY, bbox)
    if not sol then return nil end
    local sKey = session.targetClient .. ":" .. session.clientSeq
    self.active_sessions[sKey] = nil
    self:addTombstone(sKey, nowMs + self.tombstoneTtlMs)
    self.client_last_solved[session.targetClient] = math.max(
        self.client_last_solved[session.targetClient] or 0,
        session.clientSeq
    )
    self.client_last_solve_time[session.targetClient] = nowMs
    local resp = protocol.buildResponse("GPS_BASE_NET", 1, {
        targetClient = session.targetClient,
        clientSeq = session.clientSeq,
        status = sol.status,
        position = { x = sol.x, z = sol.z },
        accuracy = sol.accuracy,
        hdop = sol.hdop,
        nodeCount = sol.nodeCount,
        selectedNodes = sol.selectedNodes,
    }, nowMs)
    return resp.payload
end

function session_scheduler:ingestReport(reportPayload, registry, nowMs)
    local target = tostring(reportPayload.targetClient or "")
    local seq = tonumber(reportPayload.clientSeq) or 0
    local sKey = target .. ":" .. seq
    local filterAction, filterReason = checkDefenseFilters(self, target, seq, sKey, nowMs)
    if filterAction ~= "OK" then return filterAction, nil, filterReason end
    local ok, resolved, resReason = config_store.resolveNodeReport(registry, reportPayload)
    if not ok then return "DROPPED", nil, resReason end
    local session = self.active_sessions[sKey]
    if not session then
        session = {
            targetClient = target,
            clientSeq = seq,
            clientAltitudeY = tonumber(reportPayload.clientAltitudeY) or 0,
            replyChannel = tonumber(reportPayload.replyChannel) or 0,
            reports = {},
            reportsList = {},
            expireMs = nowMs + self.windowMs,
        }
        self.active_sessions[sKey] = session
    end
    if not session.reports[resolved.id] then
        session.reports[resolved.id] = resolved
        table.insert(session.reportsList, resolved)
    end
    local earlyPayload = tryEarlySolve(self, session, registry, nowMs)
    if earlyPayload then return "EARLY_SOLVED", earlyPayload end
    return "BUFFERED"
end

function session_scheduler:flushExpired(registry, nowMs)
    local responses = {}
    local expiredKeys = {}
    for sKey, session in pairs(self.active_sessions) do
        if nowMs >= session.expireMs then table.insert(expiredKeys, sKey) end
    end
    for _, sKey in ipairs(expiredKeys) do
        local session = self.active_sessions[sKey]
        self.active_sessions[sKey] = nil
        local count = #session.reportsList
        if count >= 3 then
            local bbox = config_store.computeSwarmBBox(registry, session.reportsList)
            local sol = trilateration.solve(session.reportsList, session.clientAltitudeY, bbox)
            if sol then
                self:addTombstone(sKey, nowMs + self.tombstoneTtlMs)
                self.client_last_solved[session.targetClient] = math.max(
                    self.client_last_solved[session.targetClient] or 0,
                    session.clientSeq
                )
                self.client_last_solve_time[session.targetClient] = nowMs
                local resp = protocol.buildResponse("GPS_BASE_NET", 1, {
                    targetClient = session.targetClient,
                    clientSeq = session.clientSeq,
                    status = sol.status,
                    position = { x = sol.x, z = sol.z },
                    accuracy = sol.accuracy,
                    hdop = sol.hdop,
                    nodeCount = sol.nodeCount,
                    selectedNodes = sol.selectedNodes,
                }, nowMs)
                table.insert(responses, { replyChannel = session.replyChannel, payload = resp.payload })
            end
        end
        if count < 3 then
            self:addTombstone(sKey, nowMs + 150)
            local failResp = protocol.buildResponse("GPS_BASE_NET", 1, {
                targetClient = session.targetClient,
                clientSeq = session.clientSeq,
                status = "FAIL_INSUFFICIENT",
            }, nowMs)
            table.insert(responses, { replyChannel = session.replyChannel, payload = failResp.payload })
        end
    end
    return responses
end

return session_scheduler
