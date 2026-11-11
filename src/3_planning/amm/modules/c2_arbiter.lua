-- src/3_planning/amm/modules/c2_arbiter.lua
-- AMM C2 Arbiter: Authority Switching, Queue FSM & Handover
local c2_arbiter = {}
c2_arbiter.__index = c2_arbiter

function c2_arbiter.new(queue, net, config, engine)
    local cfg = config or {}
    local self = setmetatable({
        queue = queue,
        net = net,
        engine = engine or (cfg and cfg.engine) or nil,
        authority = "PILOT_PRIMARY",
        fsmState = "DISARMED",
        activeSource = "FCP",
        airframeType = cfg.airframeType or nil,
        lastBanner = "SYSTEM_READY",
        fcpTakeoffActive = false,
        latest_mfd_payload = nil,
    }, c2_arbiter)
    if self.engine then
        self.engine.authority = self.authority
    end
    return self
end

function c2_arbiter:set_engine(engine)
    self.engine = engine
    if self.engine then
        self.engine.authority = self.authority
    end
end

function c2_arbiter:handle_gcs_packet(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then
        return
    end
    if packet.type == "MSG_MISSION_CMD" then
        return self:handle_mission_cmd(packet, now_ms)
    end
    local p = packet.payload
    if p.authority == "GCS_OVERRIDE" then
        self.authority = "GCS_OVERRIDE"
        if self.queue and self.queue.state == "EN_ROUTE" then
            self.queue.state = "SUSPENDED"
        end
        if self.engine and self.engine.state == "EN_ROUTE" then
            self.engine:pause()
        end
        self.lastBanner = "[GCS OVERRIDE ACTIVE - MISSION SUSPENDED]"
    end
end

local function normalize_mission_path(name)
    if type(name) ~= "string" or name == "" or string.find(name, "%.%.") then
        return nil, "INVALID_CMD"
    end
    local path = name
    if not string.match(path, "^missions/") and not string.match(path, "^/missions/") then
        path = "missions/" .. path
    end
    if not string.match(path, "%.json$") then
        path = path .. ".json"
    end
    return path, nil
end

local function send_ack(self, action, status, reason)
    if not self.net or not self.net.send_mission_ack then return false end
    local eng = self.engine
    return self.net:send_mission_ack({
        action = action,
        status = status,
        missionId = eng and eng.missionId,
        missionState = eng and eng.state,
        activeIndex = eng and eng.active_index,
        totalCheckpoints = eng and eng:count(),
        reason = reason,
    })
end

local function handle_cmd_run(self, p, now_ms)
    local eng = self.engine
    if eng.state == "EN_ROUTE" and not p.forceRestart then
        send_ack(self, "RUN", "BUSY_REJECTED", nil)
        return false, "BUSY_REJECTED"
    end

    if p.forceRestart then
        eng:stop(now_ms)
    end

    if p.missionName then
        local path, err = normalize_mission_path(p.missionName)
        if not path then
            send_ack(self, "RUN", "INVALID_CMD", err)
            return false, "INVALID_CMD"
        end
        local ok_load, err_load = eng:load(path)
        if not ok_load then
            local status = "INVALID_CMD"
            if err_load == "FILE_NOT_FOUND" then
                status = "FILE_NOT_FOUND"
            elseif err_load == "DEFERRED_ACTION_UNSUPPORTED" then
                status = "DEFERRED_ACTION_UNSUPPORTED"
            end
            send_ack(self, "RUN", status, err_load)
            return false, status
        end
    elseif eng:count() == 0 then
        send_ack(self, "RUN", "INVALID_CMD", "NO_MISSION")
        return false, "INVALID_CMD"
    end

    local ok_start, err_start = eng:start(p.executionMode, now_ms)
    if not ok_start then
        local status = (err_start == "DEFERRED_ACTION_UNSUPPORTED") and "DEFERRED_ACTION_UNSUPPORTED" or "INVALID_CMD"
        send_ack(self, "RUN", status, err_start)
        return false, status
    end

    send_ack(self, "RUN", "ACCEPTED", nil)
    self.lastBanner = "MISSION RUN: " .. (eng.missionId or "ACTIVE")
    return true, "ACCEPTED"
end

local function handle_cmd_stop(self, _p, now_ms)
    self.engine:stop(now_ms)
    send_ack(self, "STOP", "ACCEPTED", nil)
    self.lastBanner = "MISSION STOPPED"
    return true, "ACCEPTED"
end

local function handle_cmd_pause(self, _p, _now_ms)
    self.engine:pause()
    send_ack(self, "PAUSE", "ACCEPTED", nil)
    self.lastBanner = "MISSION PAUSED"
    return true, "ACCEPTED"
end

local function handle_cmd_resume(self, _p, now_ms)
    self.engine:resume(now_ms)
    send_ack(self, "RESUME", "ACCEPTED", nil)
    self.lastBanner = "MISSION RESUMED"
    return true, "ACCEPTED"
end

local function handle_cmd_next(self, _p, now_ms)
    local ok, res = self.engine:skip_next(now_ms)
    local status = ok and "ACCEPTED" or "INVALID_CMD"
    send_ack(self, "NEXT", status, not ok and res or nil)
    if ok then
        self.lastBanner = "MISSION ADVANCED TO CP " .. self.engine.active_index
    end
    return ok, status
end

local MISSION_CMD_HANDLERS = {
    RUN = handle_cmd_run,
    STOP = handle_cmd_stop,
    PAUSE = handle_cmd_pause,
    RESUME = handle_cmd_resume,
    NEXT = handle_cmd_next,
}

function c2_arbiter:handle_mission_cmd(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then
        return false, "INVALID_PACKET"
    end
    local p = packet.payload
    local action = p.action
    if not self.engine then
        if self.net then
            self.net:send_mission_ack({
                action = action,
                status = "INVALID_CMD",
                reason = "ENGINE_UNAVAILABLE",
            })
        end
        return false, "ENGINE_UNAVAILABLE"
    end

    local handler = MISSION_CMD_HANDLERS[action]
    if not handler then
        send_ack(self, action or "UNKNOWN", "INVALID_CMD", "UNKNOWN_ACTION")
        return false, "INVALID_CMD"
    end

    return handler(self, p, now_ms)
end

local function build_params(wp)
    if not wp then return {} end
    return {
        targetWaypoint = { x = wp.x, z = wp.z },
        targetAlt = wp.alt,
        targetSpeed = wp.speed,
        designatedFacilityId = wp.facilityId,
    }
end

local function handle_queue_arrival(self, craft_pos)
    local arrived, status, wp = self.queue:check_arrival(craft_pos)
    if not arrived then return end

    if status == "ADVANCED" then
        self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(wp), "NONE", self.authority)
        self.lastBanner = "ARRIVED: ADVANCING TO WP" .. (wp and wp.id or "")
    elseif status == "COMPLETED" then
        if wp and wp.facilityId then
            local par = { designatedFacilityId = wp.facilityId }
            self.net:send_operator_cmd("CRUISE", "LANDING", par, "NONE", self.authority)
            self.lastBanner = "MISSION COMPLETE: APPROACHING " .. wp.facilityId
        else
            self.net:send_operator_cmd("LOITER", "LOITER", build_params(wp), "NONE", self.authority)
            self.lastBanner = "MISSION COMPLETE: LOITERING"
        end
    end
end

local function handle_engine_telemetry(self, p, now_ms)
    if not self.engine or self.engine:count() == 0 then return end
    local res = self.engine:step_telemetry(p, now_ms)
    if res == "ADVANCED" then
        local cp = self.engine:get_active()
        self.lastBanner = "ARRIVED: ADVANCING TO CP " .. (cp and (cp.checkpointId or cp.id) or "")
    elseif res == "COMPLETED" then
        self.lastBanner = "MISSION COMPLETE"
    elseif res == "ABORTED" then
        self.lastBanner = "MISSION ABORTED"
    end
end

function c2_arbiter:handle_mfd_state(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    self.latest_mfd_payload = p
    self.fsmState = p.fsmState or self.fsmState
    self.activeSource = p.activeSource or self.activeSource
    self.airframeType = p.airframeType or p.airframe or self.airframeType

    if self.fcpTakeoffActive and self.fsmState == "CRUISE" then
        self.fcpTakeoffActive = false
        if self.queue then
            self.queue.state = "EN_ROUTE"
            local active_wp = self.queue:get_active()
            if active_wp then
                self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(active_wp), "NONE", self.authority)
                self.lastBanner = "TAKEOFF COMPLETE: EN ROUTE TO WP" .. active_wp.id
            end
        end
    end

    if self.engine and self.engine:count() > 0 then
        handle_engine_telemetry(self, p, now_ms)
    elseif self.queue then
        local craft_pos = p.navigation and p.navigation.currentPos
        if craft_pos then
            handle_queue_arrival(self, craft_pos)
        end
    end
end

local PILOT_ACTION_HANDLERS = {
    ARM = function(self, _par, _now_ms)
        self.net:send_operator_cmd("ARM", "CRUISE", {}, "NONE", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: CMD ARM"
    end,
    TAKEOFF = function(self, par, _now_ms)
        self.fcpTakeoffActive = true
        self.net:send_operator_cmd("TAKEOFF", "TAKEOFF", { targetAlt = par.targetAlt }, "NONE", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: CMD TAKEOFF"
    end,
    HOLD = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "HOVER_HOLD", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY HOVER_HOLD"
    end,
    RTH = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "RTH", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY RTH"
    end,
    LAND = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "EMERGENCY_LAND", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY LAND"
    end,
    ESTOP = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.net:send_emergency_override("CUTOFF", "PILOT_ESTOP_HOTKEY")
        self.lastBanner = "PILOT: E_STOP TRANSMITTED"
    end,
    PAUSE = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.lastBanner = "MISSION QUEUE PAUSED"
    end,
    RESUME = function(self, _par, now_ms)
        if self.engine and self.engine:count() > 0 then
            self.engine:resume(now_ms)
        end
        if self.queue then
            self.queue.state = "EN_ROUTE"
            if not self.engine or self.engine:count() == 0 then
                local active_wp = self.queue:get_active()
                if active_wp then
                    self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(active_wp), "NONE", "PILOT_PRIMARY")
                end
            end
        end
        self.lastBanner = "MISSION RESUMED"
    end,
}

function c2_arbiter:handle_pilot_action(action, params, now_ms)
    self.authority = "PILOT_PRIMARY"
    if self.engine then
        self.engine.authority = "PILOT_PRIMARY"
    end
    local handler = PILOT_ACTION_HANDLERS[action]
    if handler then
        handler(self, params or {}, now_ms)
    end
end

return c2_arbiter
