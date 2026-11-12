-- src/3_planning/amm/modules/c2_arbiter.lua
-- AMM C2 Arbiter: Authority Switching, Queue FSM & Handover
local mission_engine = require("mission_engine")

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
        latest_outer_status = nil,
        latest_telem = nil,
        lastOuterStatusMs = 0,
        lastTelemMs = 0,
        fcpTimedOut = false,
        emergencyGoal = nil,
        activeGoal = nil,
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
        if self.engine then
            self.engine.authority = "GCS_OVERRIDE"
        end
        if self.queue and self.queue.state == "EN_ROUTE" then
            self.queue.state = "SUSPENDED"
        end
        if self.engine and self.engine.state == "EN_ROUTE" then
            self.engine:pause()
        end
        if p.command == "HOLD" or p.flightMode == "HOVER_HOLD" then
            self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
        elseif p.command == "RTH" or p.flightMode == "FAILSAFE_RTH" then
            self.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
        elseif p.command == "LAND" or p.flightMode == "EMERGENCY_LAND" then
            self.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true }
        end
        self.lastBanner = "[GCS OVERRIDE ACTIVE - MISSION SUSPENDED]"
    end
end

local LOAD_ERR_TO_ACK = {
    INVALID_PATH = "INVALID_CMD",
    FILE_NOT_FOUND = "FILE_NOT_FOUND",
    SCHEMA_INVALID = "SCHEMA_INVALID",
    PARSE_ERROR = "SCHEMA_INVALID",
    DEFERRED_ACTION_UNSUPPORTED = "DEFERRED_ACTION_UNSUPPORTED",
}

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

    local data = nil
    if p.missionName then
        local pre_data, err_load, detail = mission_engine.preflight_file(
            p.missionName,
            { baseChannel = eng.baseChannel }
        )
        if not pre_data then
            local status = LOAD_ERR_TO_ACK[err_load] or "INVALID_CMD"
            send_ack(self, "RUN", status, detail or err_load)
            return false, status
        end
        data = pre_data
    elseif eng:count() == 0 then
        send_ack(self, "RUN", "INVALID_CMD", "NO_MISSION")
        return false, "INVALID_CMD"
    end

    if p.forceRestart and (eng.state == "EN_ROUTE" or eng.state == "SUSPENDED") then
        eng:stop(now_ms)
    end

    if data then
        local ok_lt, err_lt = eng:load_table(data)
        if not ok_lt then
            send_ack(self, "RUN", "SCHEMA_INVALID", err_lt)
            return false, "SCHEMA_INVALID"
        end
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
    local ok = self.engine:pause()
    if not ok then
        send_ack(self, "PAUSE", "INVALID_CMD", "INVALID_STATE_TRANSITION")
        return false, "INVALID_CMD"
    end
    send_ack(self, "PAUSE", "ACCEPTED", nil)
    self.lastBanner = "MISSION PAUSED"
    return true, "ACCEPTED"
end

local function handle_cmd_resume(self, _p, now_ms)
    local ok = self.engine:resume(now_ms)
    if not ok then
        send_ack(self, "RESUME", "INVALID_CMD", "INVALID_STATE_TRANSITION")
        return false, "INVALID_CMD"
    end
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
        self.activeGoal = { flightMode = "IDLE", arm = true, flightActive = false }
        if self.net and self.net.send_operator_cmd then
            self.net:send_operator_cmd("ARM", "CRUISE", {}, "NONE", "PILOT_PRIMARY")
        end
        self.lastBanner = "PILOT: CMD ARM"
    end,
    TAKEOFF = function(self, par, _now_ms)
        self.fcpTakeoffActive = true
        self.emergencyGoal = nil
        self.activeGoal = { flightMode = "TAKEOFF", arm = true, flightActive = true, targetAlt = par.targetAlt }
        if self.net and self.net.send_operator_cmd then
            self.net:send_operator_cmd("TAKEOFF", "TAKEOFF", { targetAlt = par.targetAlt }, "NONE", "PILOT_PRIMARY")
        end
        self.lastBanner = "PILOT: CMD TAKEOFF"
    end,
    HOLD = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        if self.net and self.net.send_operator_cmd then
            self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "HOVER_HOLD", "PILOT_PRIMARY")
        end
        self.lastBanner = "PILOT: EMERGENCY HOVER_HOLD"
    end,
    RTH = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        if self.net and self.net.send_operator_cmd then
            self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "RTH", "PILOT_PRIMARY")
        end
        self.lastBanner = "PILOT: EMERGENCY RTH"
    end,
    LAND = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        if self.net and self.net.send_operator_cmd then
            self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "EMERGENCY_LAND", "PILOT_PRIMARY")
        end
        self.lastBanner = "PILOT: EMERGENCY LAND"
    end,
    ESTOP = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.emergencyGoal = { flightMode = "IDLE", arm = false, flightActive = false }
        self.activeGoal = self.emergencyGoal
        self.net:send_emergency_override("E_STOP", "PILOT_ESTOP_HOTKEY", "ESTOP_CONFIRM_KEY", "AMM")
        self.lastBanner = "PILOT: E_STOP TRANSMITTED"
    end,
    PAUSE = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.lastBanner = "MISSION QUEUE PAUSED"
    end,
    RESUME = function(self, _par, now_ms)
        self.emergencyGoal = nil
        if self.engine and self.engine:count() > 0 then
            self.engine:resume(now_ms)
        end
        if self.queue then
            self.queue.state = "EN_ROUTE"
            if not self.engine or self.engine:count() == 0 then
                local active_wp = self.queue:get_active()
                if active_wp and self.net and self.net.send_operator_cmd then
                    self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(active_wp), "NONE", "PILOT_PRIMARY")
                end
            end
        end
        self.lastBanner = "MISSION RESUMED"
    end,
}

function c2_arbiter:handle_outer_loop_status(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    self.latest_outer_status = p
    self.lastOuterStatusMs = now_ms or ((os.epoch and os.epoch("utc")) or (os.time() * 1000))
    self.fcpTimedOut = false
    if p.trackingStatus then self.fcpTrackingStatus = p.trackingStatus end
end

function c2_arbiter:handle_flight_telemetry(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    self.latest_telem = p
    self.lastTelemMs = now_ms or ((os.epoch and os.epoch("utc")) or (os.time() * 1000))
    if p.activeSource then self.activeSource = p.activeSource end
    local fuel = p.fuel
    if type(fuel) == "number" then
        if fuel < 0.10 then
            self.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true }
            self.lastBanner = "[CRITICAL FUEL: EMERGENCY LAND]"
        elseif fuel < 0.20 and (not self.emergencyGoal or self.emergencyGoal.flightMode ~= "EMERGENCY_LAND") then
            self.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
            self.lastBanner = "[LOW FUEL: FAILSAFE RTH]"
        end
    end
end

function c2_arbiter:check_timeouts(now_ms)
    local now = now_ms or ((os.epoch and os.epoch("utc")) or (os.time() * 1000))
    if self.lastOuterStatusMs and self.lastOuterStatusMs > 0 then
        if (now - self.lastOuterStatusMs) > 500 then
            self.fcpTimedOut = true
            self.lastBanner = "[ALERT: FCP TIMEOUT - HOVER HOLD]"
            if not self.emergencyGoal then
                self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
            end
        end
    end
end

function c2_arbiter:get_effective_goal()
    if self.emergencyGoal then
        return self.emergencyGoal
    end
    if self.engine and self.engine.state == "EN_ROUTE" and self.engine.get_trajectory_goal then
        local g = self.engine:get_trajectory_goal()
        if g then return g end
    end
    if self.queue and self.queue.state == "EN_ROUTE" then
        local wp = self.queue:get_active()
        if wp then
            return {
                flightMode = "CRUISE",
                arm = true,
                flightActive = true,
                targetPos = { x = wp.x, z = wp.z },
                targetAlt = wp.alt,
                targetSpeed = wp.speed,
                facilityId = wp.facilityId,
            }
        end
    end
    return self.activeGoal or { flightMode = "IDLE", arm = (self.authority ~= "DISARMED"), flightActive = false }
end

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
