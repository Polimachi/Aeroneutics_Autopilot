-- src/3_planning/amm/modules/c2_arbiter.lua
-- AMM C2 Arbiter: Authority Switching, Queue FSM & Handover
local mission_engine = require("mission_engine")
local chattering_guard = require("chattering_guard")
local facility_client = require("facility_client")

local c2_arbiter = {}
c2_arbiter.__index = c2_arbiter

local function resolve_now_ms(self, now_ms)
    if type(now_ms) == "number" then
        return now_ms
    end
    if self and type(self.clockFn) == "function" then
        local t = self.clockFn()
        if type(t) == "number" then
            return t
        end
    end
    return (os.epoch and os.epoch("utc")) or (os.time() * 1000)
end

function c2_arbiter.new(queue, net, config, engine, guard)
    local cfg = config or {}
    local safe = cfg.safety or {}
    local eng = engine or (cfg and cfg.engine) or nil
    local g = guard or (eng and eng.guard) or chattering_guard.init(cfg)
    local self = setmetatable({
        queue = queue,
        net = net,
        config = cfg,
        engine = eng,
        guard = g,
        clockFn = cfg.clockFn,
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
        acroRecoveryHoldMs = safe.acroRecoveryHoldMs or cfg.acroRecoveryHoldMs or 300,
        lastVasPriorityMs = nil,
        vasMfdPriorityUntilMs = 0,
        emergencyGoal = nil,
        activeGoal = nil,
        coldBootHandled = false,
        onColdBootRecovery = cfg.onColdBootRecovery,
    }, c2_arbiter)
    if type(net) == "table" then
        if net.set_arbiter then
            net:set_arbiter(self)
        else
            net.arbiter = self
        end
    end
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

local function resolve_craft_pos(self, par)
    local eng = self.engine
    local mfd_pos = eng and eng.lastMfd and eng.lastMfd.navigation and eng.lastMfd.navigation.currentPos
    local lat_mfd_pos = self.latest_mfd_payload and self.latest_mfd_payload.navigation and self.latest_mfd_payload.navigation.currentPos
    local telem_pos = self.latest_telem and self.latest_telem.navigation and self.latest_telem.navigation.currentPos
    return mfd_pos or lat_mfd_pos or telem_pos or par.targetPos or (eng and eng.homePos) or { x = 0, y = 64, z = 0 }
end

local function apply_land_nearest_goal(self, par)
    local fac = (self.engine and self.engine.fac) or self.fac
    local pos = resolve_craft_pos(self, par)
    local best = fac and facility_client.find_nearest_free_landing_facility(fac, pos, par.facilityTypeFilter, par.maxRangeM) or nil
    if best then
        local bpos = best.position or {}
        local tpos = (bpos.x and bpos.z) and { x = bpos.x, y = bpos.y, z = bpos.z } or par.targetPos
        self.armed = true
        self.emergencyGoal = {
            flightMode = "LANDING",
            arm = true,
            flightActive = true,
            facilityId = best.facilityId,
            designatedFacilityId = best.facilityId,
            targetPos = tpos,
            targetAlt = bpos.y or par.targetAlt,
            targetSpeed = par.targetSpeed,
        }
        return "[GCS OVERRIDE: LAND_NEAREST " .. tostring(best.facilityId) .. "]"
    end
    self.armed = true
    self.emergencyGoal = {
        flightMode = "EMERGENCY_LAND",
        arm = true,
        flightActive = true,
        targetPos = par.targetPos or par.targetWaypoint,
        targetAlt = par.targetAlt,
        targetSpeed = par.targetSpeed,
    }
    return "[GCS OVERRIDE: EMERGENCY_LAND FALLBACK]"
end

local function resolve_override_flight_mode(p)
    if p.command == "HOLD" or p.flightMode == "HOVER_HOLD" then
        return "HOVER_HOLD"
    elseif p.command == "RTH" or p.command == "RTB" or p.flightMode == "FAILSAFE_RTH" then
        return "FAILSAFE_RTH"
    elseif p.command == "LAND" or p.flightMode == "EMERGENCY_LAND" then
        return "EMERGENCY_LAND"
    elseif type(p.flightMode) == "string" and p.flightMode ~= "" then
        return (p.flightMode == "IDLE") and "IDLE_ARMED" or p.flightMode
    elseif type(p.command) == "string" and p.command ~= "" then
        return (p.command == "IDLE") and "IDLE_ARMED" or p.command
    end
    return nil
end

function c2_arbiter:handle_gcs_packet(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then
        return
    end
    if packet.type == "MSG_MISSION_CMD" then
        return self:handle_mission_cmd(packet, now_ms)
    end
    local p = packet.payload
    if p.authority ~= "GCS_OVERRIDE" then return end

    self.authority = "GCS_OVERRIDE"
    if self.engine then self.engine.authority = "GCS_OVERRIDE" end
    if self.queue and self.queue.state == "EN_ROUTE" then self.queue.state = "SUSPENDED" end
    if self.engine and self.engine.state == "EN_ROUTE" then self.engine:pause() end

    local par = type(p.params) == "table" and p.params or {}
    if p.command == "LAND_NEAREST" then
        self.lastBanner = apply_land_nearest_goal(self, par)
        return
    end
    local fm = resolve_override_flight_mode(p)
    if fm then
        local is_idle = (fm == "IDLE_ARMED")
        if p.command == "ARM" then self.armed = true
        elseif p.command == "DISARM" then self.armed = false end
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

local function persist_mission_if_requested(eng, p, default_save)
    local should_save = (p.saveToDisk == nil) and default_save or (p.saveToDisk == true)
    if not should_save or not eng or not eng.save then return true end
    local safe_id = tostring(eng.missionId or "MISSION_01"):gsub("[^%w_%-]", "_")
    if safe_id == "" then safe_id = "MISSION_01" end
    return eng:save("/missions/" .. safe_id .. ".json")
end

local function preflight_inline_mission(self, action, tbl)
    local ok_v, err_v, det_v = mission_engine.validate_mission_table(tbl, self.config)
    if not ok_v then
        local status = LOAD_ERR_TO_ACK[err_v] or "SCHEMA_INVALID"
        send_ack(self, action, status, det_v or err_v)
        return nil, status
    end
    return tbl, nil
end

local function resolve_run_mission_data(self, p, eng)
    if type(p.missionData) == "table" then
        return preflight_inline_mission(self, "RUN", p.missionData)
    end
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
            return nil, status
        end
        return pre_data, nil
    end
    if eng:count() == 0 then
        send_ack(self, "RUN", "INVALID_CMD", "NO_MISSION")
        return nil, "INVALID_CMD"
    end
    return false, nil
end

local function handle_cmd_load(self, p, now_ms)
    local eng = self.engine
    if eng.state == "EN_ROUTE" and not p.forceRestart then
        send_ack(self, "LOAD", "BUSY_REJECTED", nil)
        return false, "BUSY_REJECTED"
    end
    if type(p.missionData) ~= "table" then
        send_ack(self, "LOAD", "SCHEMA_INVALID", "MISSING_MISSION_DATA")
        return false, "SCHEMA_INVALID"
    end
    local data, v_status = preflight_inline_mission(self, "LOAD", p.missionData)
    if not data then return false, v_status end
    if p.forceRestart and (eng.state == "EN_ROUTE" or eng.state == "SUSPENDED") then
        eng:stop(now_ms)
    end
    local ok_lt, err_lt = eng:load_table(data)
    if not ok_lt then
        local status = (err_lt == "DEFERRED_ACTION_UNSUPPORTED") and err_lt or "SCHEMA_INVALID"
        send_ack(self, "LOAD", status, err_lt)
        return false, status
    end
    persist_mission_if_requested(eng, p, true)
    send_ack(self, "LOAD", "ACCEPTED", nil)
    self.lastBanner = "MISSION LOADED: " .. (eng.missionId or "ACTIVE")
    return true, "ACCEPTED"
end

local function handle_cmd_run(self, p, now_ms)
    local eng = self.engine
    if eng.state == "EN_ROUTE" and not p.forceRestart then
        send_ack(self, "RUN", "BUSY_REJECTED", nil)
        return false, "BUSY_REJECTED"
    end
    local data, err_status = resolve_run_mission_data(self, p, eng)
    if data == nil then return false, err_status end

    if p.forceRestart and (eng.state == "EN_ROUTE" or eng.state == "SUSPENDED") then
        eng:stop(now_ms)
    end
    if data then
        local ok_lt, err_lt = eng:load_table(data)
        if not ok_lt then
            send_ack(self, "RUN", "SCHEMA_INVALID", err_lt)
            return false, "SCHEMA_INVALID"
        end
        if type(p.missionData) == "table" then
            persist_mission_if_requested(eng, p, false)
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
    LOAD = handle_cmd_load,
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

function c2_arbiter:update_acro_yield_window(state_val, active_source, source_tag, now_ms)
    local now = resolve_now_ms(self, now_ms)
    local is_acro = (active_source == "MFD_ACRO") or (source_tag == "CORE_ACRO_TAKEOVER")
    local is_vas_failsafe = (state_val == "FAILSAFE_HOLD") or (state_val == "EMERGENCY_LAND")
        or (state_val == "AIRBORNE_RECOVERY_HOLD") or (source_tag == "CORE_FAILSAFE")
    if is_acro or is_vas_failsafe then
        self.lastVasPriorityMs = now
        self.vasMfdPriorityUntilMs = now + (self.acroRecoveryHoldMs or 300)
    end
end

function c2_arbiter:can_transmit_mfd(now_ms)
    if self.activeSource == "MFD_ACRO" then
        return false, "YIELDED_TO_MFD_ACRO"
    end
    local now = resolve_now_ms(self, now_ms)
    if self.lastVasPriorityMs ~= nil and now < (self.vasMfdPriorityUntilMs or 0) then
        return false, "ACRO_RECOVERY_HOLD"
    end
    if self.fsmState == "FAILSAFE_HOLD" or self.fsmState == "EMERGENCY_LAND"
        or self.fsmState == "AIRBORNE_RECOVERY_HOLD" then
        return false, "YIELDED_TO_VAS_FAILSAFE"
    end
    return true
end

local function sync_state_and_step(self, p, state_val, source_val, now_ms, allow_engine)
    if state_val ~= nil then
        self.fsmState = state_val
        self.armed = (state_val ~= "DISARMED")
    end
    if source_val ~= nil then
        self.activeSource = source_val
    end
    self.airframeType = p.airframeType or p.airframe or self.airframeType
    self:update_acro_yield_window(state_val, source_val, p.source, now_ms)

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
    local src = p.activeSource
    if src == nil and (p.source == "CORE_ACRO_TAKEOVER" or p.acroActive == true) then
        src = "MFD_ACRO"
    end
    sync_state_and_step(self, p, p.fsmState, src, resolve_now_ms(self, now_ms), false)
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
    self.lastOuterStatusMs = resolve_now_ms(self, now_ms)
    self.fcpTimedOut = false
    if self.emergencyGoal and self.emergencyGoal._fcpTimeout then
        self.emergencyGoal = nil
    end
    if p.trackingStatus then self.fcpTrackingStatus = p.trackingStatus end
end

local function handle_vas_cold_boot_telem(self, p, t_ms)
    if p.controlState == "AIRBORNE_RECOVERY_HOLD" and not self.coldBootHandled then
        if type(self.onColdBootRecovery) == "function" then
            self.onColdBootRecovery(t_ms, p)
        end
        self.coldBootHandled = true
        if not self.armed then
            self.armed = true
            self.emergencyGoal = { flightMode = "HOVER_HOLD", arm = true, flightActive = true, _coldBootHold = true }
        end
    elseif p.controlState == "DISARMED" and self.armed == false
        and self.engine and self.engine.persist_flight_state and self.engine.state ~= "EN_ROUTE" then
        self.engine:persist_flight_state("GROUND_SAFE", t_ms)
    end
end

function c2_arbiter:handle_flight_telemetry(packet, now_ms)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    local t_ms = resolve_now_ms(self, now_ms)
    self.latest_telem = p
    self.lastTelemMs = t_ms
    sync_state_and_step(self, p, p.controlState, p.activeSource, t_ms, true)
    handle_vas_cold_boot_telem(self, p, t_ms)
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
    local now = resolve_now_ms(self, now_ms)
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
