-- src/3_planning/amm/modules/c2_arbiter.lua
-- AMM C2 Arbiter: Authority Switching, Queue FSM & Handover
local c2_arbiter = {}
c2_arbiter.__index = c2_arbiter

function c2_arbiter.new(queue, net, config)
    local cfg = config or {}
    local self = setmetatable({
        queue = queue,
        net = net,
        authority = "PILOT_PRIMARY",
        fsmState = "DISARMED",
        activeSource = "FCP",
        airframeType = cfg.airframeType or nil,
        lastBanner = "SYSTEM_READY",
        fcpTakeoffActive = false,
        latest_mfd_payload = nil,
    }, c2_arbiter)
    return self
end

function c2_arbiter:handle_gcs_packet(packet)
    if not packet or type(packet.payload) ~= "table" then
        return
    end
    local p = packet.payload
    if p.authority == "GCS_OVERRIDE" then
        self.authority = "GCS_OVERRIDE"
        if self.queue and self.queue.state == "EN_ROUTE" then
            self.queue.state = "SUSPENDED"
        end
        self.lastBanner = "[GCS OVERRIDE ACTIVE - MISSION SUSPENDED]"
    end
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

function c2_arbiter:handle_mfd_state(packet)
    if not packet or type(packet.payload) ~= "table" then return end
    local p = packet.payload
    self.latest_mfd_payload = p
    self.fsmState = p.fsmState or self.fsmState
    self.activeSource = p.activeSource or self.activeSource
    self.airframeType = p.airframeType or p.airframe or self.airframeType

    if self.fcpTakeoffActive and self.fsmState == "CRUISE" then
        self.fcpTakeoffActive = false
        self.queue.state = "EN_ROUTE"
        local active_wp = self.queue:get_active()
        if active_wp then
            self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(active_wp), "NONE", self.authority)
            self.lastBanner = "TAKEOFF COMPLETE: EN ROUTE TO WP" .. active_wp.id
        end
    end

    local craft_pos = p.navigation and p.navigation.currentPos
    if not craft_pos then return end
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

function c2_arbiter:handle_pilot_action(action, params)
    self.authority = "PILOT_PRIMARY"
    local par = params or {}

    if action == "ARM" then
        self.net:send_operator_cmd("ARM", "CRUISE", {}, "NONE", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: CMD ARM"
    elseif action == "TAKEOFF" then
        self.fcpTakeoffActive = true
        self.net:send_operator_cmd("TAKEOFF", "TAKEOFF", { targetAlt = par.targetAlt }, "NONE", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: CMD TAKEOFF"
    elseif action == "HOLD" then
        if self.queue then self.queue.state = "SUSPENDED" end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "HOVER_HOLD", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY HOVER_HOLD"
    elseif action == "RTH" then
        if self.queue then self.queue.state = "SUSPENDED" end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "RTH", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY RTH"
    elseif action == "LAND" then
        if self.queue then self.queue.state = "SUSPENDED" end
        self.net:send_operator_cmd("CRUISE", "CRUISE", {}, "EMERGENCY_LAND", "PILOT_PRIMARY")
        self.lastBanner = "PILOT: EMERGENCY LAND"
    elseif action == "ESTOP" then
        if self.queue then self.queue.state = "SUSPENDED" end
        self.net:send_emergency_override("CUTOFF", "PILOT_ESTOP_HOTKEY")
        self.lastBanner = "PILOT: E_STOP TRANSMITTED"
    elseif action == "PAUSE" then
        if self.queue then self.queue.state = "SUSPENDED" end
        self.lastBanner = "MISSION QUEUE PAUSED"
    elseif action == "RESUME" then
        if self.queue then
            self.queue.state = "EN_ROUTE"
            local active_wp = self.queue:get_active()
            if active_wp then
                self.net:send_operator_cmd("CRUISE", "CRUISE", build_params(active_wp), "NONE", "PILOT_PRIMARY")
            end
        end
        self.lastBanner = "MISSION RESUMED"
    end
end

return c2_arbiter
