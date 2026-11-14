-- src/3_planning/amm/modules/c2_arbiter.lua
-- AMM C2 Arbiter: Authority Switching, Queue FSM & Handover
local mission_engine = require("mission_engine")
local chattering_guard = require("chattering_guard")

local c2_arbiter = {}
c2_arbiter.__index = c2_arbiter

function c2_arbiter.new(queue, net, config, engine, guard)
    local cfg = config or {}
    local eng = engine or (cfg and cfg.engine) or nil
    local g = guard or (eng and eng.guard) or chattering_guard.init(cfg)
    local self = setmetatable({
        queue = queue,
        net = net,
        config = cfg,
        engine = eng,
        guard = g,
        authority = "PILOT_PRIMARY",
        armed = false,
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
        local fm = nil
        if p.command == "HOLD" or p.flightMode == "HOVER_HOLD" then
            fm = "HOVER_HOLD"
        elseif p.command == "RTH" or p.flightMode == "FAILSAFE_RTH" then
            fm = "FAILSAFE_RTH"
        elseif p.command == "LAND" or p.flightMode == "EMERGENCY_LAND" then
            fm = "EMERGENCY_LAND"
        elseif type(p.flightMode) == "string" and p.flightMode ~= "" then
            fm = (p.flightMode == "IDLE") and "IDLE_ARMED" or p.flightMode
        elseif type(p.command) == "string" and p.command ~= "" then
            fm = (p.command == "IDLE") and "IDLE_ARMED" or p.command
        end
        if fm then
            local par = type(p.params) == "table" and p.params or {}
            local is_idle = (fm == "IDLE_ARMED")
            self.emergencyGoal = {
                flightMode = fm,
                arm = not is_idle and true or (self.armed == true),
                flightActive = not is_idle,
                targetPos = par.targetPos or par.targetWaypoint,
                targetAlt = par.targetAlt,
                targetSpeed = par.targetSpeed,
                designatedFacilityId = par.designatedFacilityId,
            }
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
    PRECONDITION_FAILED = "PRECONDITION_FAILED",
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
            {
                baseChannel = eng.baseChannel,
                system = self.config and self.config.system,
                safety = self.config and self.config.safety,
            }
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
        local passthrough = (err_start == "DEFERRED_ACTION_UNSUPPORTED" or err_start == "PRECONDITION_FAILED" or err_start == "SCHEMA_INVALID")
        local status = passthrough and err_start or "INVALID_CMD"
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

local function handle_cmd_confirm(self, _p, now_ms)
    if not self.engine or not self.engine.waitingHumanAuth or not self.engine.confirm then
        send_ack(self, "CONFIRM", "INVALID_CMD", "NOT_WAITING_AUTH")
        return false, "INVALID_CMD"
    end
    local ok, err = self.engine:confirm(now_ms)
    local status = ok and "ACCEPTED" or (LOAD_ERR_TO_ACK[err] or "INVALID_CMD")
    send_ack(self, "CONFIRM", status, not ok and err or nil)
    if ok then
        self.lastBanner = "HUMAN AUTH CONFIRMED"
    end
    return ok, status
end

local MISSION_CMD_HANDLERS = {
    RUN = handle_cmd_run,
    STOP = handle_cmd_stop,
    PAUSE = handle_cmd_pause,
    RESUME = handle_cmd_resume,
    NEXT = handle_cmd_next,
    CONFIRM = handle_cmd_confirm,
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

local function make_wp_cruise_goal(wp)
    if not wp then return nil end
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

local function handle_queue_arrival(self, craft_pos)
    local arrived, status, wp = self.queue:check_arrival(craft_pos)
    if not arrived then return end

    if status == "ADVANCED" then
        self.activeGoal = make_wp_cruise_goal(wp)
        self.lastBanner = "ARRIVED: ADVANCING TO WP" .. (wp and wp.id or "")
    elseif status == "COMPLETED" then
        if wp and wp.facilityId then
            self.activeGoal = {
                flightMode = "LANDING",
                arm = true,
                flightActive = true,
                designatedFacilityId = wp.facilityId,
            }
            self.lastBanner = "MISSION COMPLETE: APPROACHING " .. wp.facilityId
        else
            self.activeGoal = {
                flightMode = "LOITER",
                arm = true,
                flightActive = true,
                targetPos = wp and { x = wp.x, z = wp.z } or nil,
                targetAlt = wp and wp.alt or nil,
                targetSpeed = wp and wp.speed or nil,
            }
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

local function sync_state_and_step(self, p, now_ms, allow_engine)
    self.fsmState = p.fsmState or p.controlState or self.fsmState
    local ctrl = p.controlState or p.fsmState
    if ctrl == "DISARMED" then
        self.armed = false
    elseif ctrl ~= nil then
        self.armed = true
    end
    self.activeSource = p.activeSource or self.activeSource
    self.airframeType = p.airframeType or p.airframe or self.airframeType

    if self.fcpTakeoffActive and self.fsmState == "CRUISE" then
        self.fcpTakeoffActive = false
        if self.queue then
            self.queue.state = "EN_ROUTE"
            local active_wp = self.queue:get_active()
            if active_wp then
                self.activeGoal = make_wp_cruise_goal(active_wp)
                self.lastBanner = "TAKEOFF COMPLETE: EN ROUTE TO WP" .. active_wp.id
            end
        end
    end

    if allow_engine and self.engine and self.engine:count() > 0 then
        handle_engine_telemetry(self, p, now_ms)
    elseif (not self.engine or self.engine:count() == 0) and self.queue then
        local craft_pos = p.navigation and p.navigation.currentPos
        if craft_pos then
            handle_queue_arrival(self, craft_pos)
        end
    end
end

function c2_arbiter:handle_mfd_state(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    if p.source == "AMM_INTEGRATED" then return end
    self.latest_mfd_payload = p
    sync_state_and_step(self, p, now_ms, false)
end

local PILOT_ACTION_HANDLERS = {
    ARM = function(self, _par, _now_ms)
        self.armed = true
        self.activeGoal = { flightMode = "IDLE_ARMED", arm = true, flightActive = false }
        self.lastBanner = "PILOT: CMD ARM"
    end,
    TAKEOFF = function(self, par, _now_ms)
        self.armed = true
        self.fcpTakeoffActive = true
        self.emergencyGoal = nil
        self.activeGoal = { flightMode = "TAKEOFF", arm = true, flightActive = true, targetAlt = par.targetAlt }
        self.lastBanner = "PILOT: CMD TAKEOFF"
    end,
    HOLD = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.armed = true
        self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        self.lastBanner = "PILOT: EMERGENCY HOVER_HOLD"
    end,
    RTH = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.armed = true
        self.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        self.lastBanner = "PILOT: EMERGENCY RTH"
    end,
    LAND = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.armed = true
        self.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true }
        self.activeGoal = self.emergencyGoal
        self.lastBanner = "PILOT: EMERGENCY LAND"
    end,
    ESTOP = function(self, _par, _now_ms)
        if self.queue then self.queue.state = "SUSPENDED" end
        if self.engine and self.engine.pause then self.engine:pause() end
        self.armed = false
        self.emergencyGoal = { flightMode = "IDLE_ARMED", arm = false, flightActive = false }
        self.activeGoal = self.emergencyGoal
        if self.net and self.net.send_emergency_override then
            self.net:send_emergency_override("E_STOP", "PILOT_ESTOP_HOTKEY", "ESTOP_CONFIRM_KEY", "AMM")
        end
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
                if active_wp then
                    self.activeGoal = make_wp_cruise_goal(active_wp)
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
    if self.emergencyGoal and self.emergencyGoal._fcpTimeout then
        self.emergencyGoal = nil
    end
    if p.trackingStatus then self.fcpTrackingStatus = p.trackingStatus end
end

function c2_arbiter:handle_flight_telemetry(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    self.latest_telem = p
    self.lastTelemMs = now_ms or ((os.epoch and os.epoch("utc")) or (os.time() * 1000))
    sync_state_and_step(self, p, now_ms, true)
    local fuel = p.fuel
    if type(fuel) == "number" then
        local latches = chattering_guard.update_fuel_latches(self.guard, fuel, self.config, not self.armed)
        if latches and latches.emergFuelLatched then
            self.emergencyGoal = { flightMode = "EMERGENCY_LAND", arm = true, flightActive = true, _fuelLatch = "EMERG" }
            self.lastBanner = "[CRITICAL FUEL: EMERGENCY LAND]"
        elseif latches and latches.lowFuelLatched then
            if not self.emergencyGoal or self.emergencyGoal.flightMode ~= "EMERGENCY_LAND" then
                self.emergencyGoal = { flightMode = "FAILSAFE_RTH", arm = true, flightActive = true, _fuelLatch = "LOW" }
                self.lastBanner = "[LOW FUEL: FAILSAFE RTH]"
            end
        elseif self.emergencyGoal and self.emergencyGoal._fuelLatch then
            self.emergencyGoal = nil
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
                self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true, _fcpTimeout = true }
            end
        end
    end
end

function c2_arbiter:get_effective_goal()
    if self.emergencyGoal then
        return self.emergencyGoal
    end
    if self.engine then
        if self.engine.state == "EN_ROUTE" and self.engine.get_trajectory_goal then
            local g = self.engine:get_trajectory_goal()
            if g then return g end
        elseif (self.engine.state == "ABORTED" or self.engine.state == "SUSPENDED")
            and self.engine.get_fallback_goal then
            local fg = self.engine:get_fallback_goal()
            if fg then return fg end
        end
    end
    if self.activeGoal and self.activeGoal.flightMode ~= "CRUISE" then
        return self.activeGoal
    end
    if self.armed and not self.fcpTakeoffActive and self.queue and self.queue.state == "EN_ROUTE" then
        local wp = self.queue:get_active()
        if wp then
            return make_wp_cruise_goal(wp)
        end
    end
    return self.activeGoal or { flightMode = "IDLE_ARMED", arm = (self.armed == true), flightActive = false }
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
