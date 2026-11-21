-- src/0_infra/pocket_pda/modules/telemetry_hud_state.lua
-- Pocket PDA telemetry HUD state, quaternion-to-Euler conversion, fleet snoop, and RSSI link classifier

local telemetry_hud_state = {}

local CRAFT_BASE_MIN = 10000
local CRAFT_BASE_MAX = 49960
local CRAFT_BANDWIDTH = 40

local function get_time_ms(now_ms)
    if type(now_ms) == "number" then
        return now_ms
    end
    if os and os.epoch then
        return os.epoch("utc")
    end
    if os and os.time then
        return math.floor(os.time() * 1000)
    end
    return 0
end

local function is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function telemetry_hud_state.init(cfg)
    return {
        cfg = (type(cfg) == "table") and cfg or {},
        altitudeY = 0.0,
        verticalSpeed = 0.0,
        groundSpeed = 0.0,
        pitch = 0.0,
        roll = 0.0,
        yaw = 0.0,
        fuel = 0.0,
        dynamicLoad = 0.0,
        fsmState = "UNKNOWN",
        flightMode = "---",
        activeSource = "---",
        sensorOk = false,
        actuatorOk = false,
        lastTelemMs = nil,
        lastDistanceM = nil,
        linkQuality = { tier = "LOST", rssiPct = 0, distanceStr = "---" },
        lastPbitReport = nil,
        lastMissionAck = nil,
        lastAlert = nil,
        nodes = {
            AMM = { online = false, lastSeenMs = 0 },
            VAS = { online = false, lastSeenMs = 0 },
            GCS = { online = false, lastSeenMs = 0 },
            ALN = { online = false, lastSeenMs = 0 },
            FDR = { online = false, lastSeenMs = 0 },
        },
        discoveredCrafts = {},
        discoveredOrder = {},
    }
end

function telemetry_hud_state.classify_link_quality(distance_m, age_ms, cfg)
    local c = (type(cfg) == "table") and cfg or {}
    local lq = (type(c.linkQuality) == "table") and c.linkQuality or {}
    local timeout_ms = lq.telemetryTimeoutMs or c.telemetryTimeoutMs or 2000
    local strong_max = lq.strongMaxDistM or 80.0
    local good_max = lq.goodMaxDistM or 200.0

    if not is_finite_number(age_ms) or age_ms < 0 or age_ms > timeout_ms then
        return { tier = "LOST", rssiPct = 0, distanceStr = "---" }
    end
    if distance_m == nil then
        return { tier = "STRONG", rssiPct = 100, distanceStr = "ENDER" }
    end
    if not is_finite_number(distance_m) then
        return { tier = "LOST", rssiPct = 0, distanceStr = "---" }
    end

    local d = math.max(0.0, distance_m)
    local dist_str = string.format("%.1fm", d)
    if d <= strong_max then
        local ratio = math.min(1.0, d / math.max(1e-6, strong_max))
        return { tier = "STRONG", rssiPct = math.floor(100 - ratio * 25 + 0.5), distanceStr = dist_str }
    elseif d <= good_max then
        local span = math.max(1e-6, good_max - strong_max)
        local ratio = math.min(1.0, (d - strong_max) / span)
        return { tier = "GOOD", rssiPct = math.floor(74 - ratio * 34 + 0.5), distanceStr = dist_str }
    end

    local excess = d - good_max
    local ratio = math.min(1.0, excess / 300.0)
    return { tier = "WEAK", rssiPct = math.max(10, math.floor(39 - ratio * 29 + 0.5)), distanceStr = dist_str }
end

function telemetry_hud_state.quat_to_euler_deg(q)
    if type(q) ~= "table" then
        return 0.0, 0.0, 0.0
    end
    local w = tonumber(q.w) or 1.0
    local x = tonumber(q.x) or 0.0
    local y = tonumber(q.y) or 0.0
    local z = tonumber(q.z) or 0.0
    local norm = math.sqrt(w * w + x * x + y * y + z * z)
    if norm <= 1e-9 then
        return 0.0, 0.0, 0.0
    end
    local inv = 1.0 / norm
    w, x, y, z = w * inv, x * inv, y * inv, z * inv

    -- Matches VAS quat.lua axis convention (clamped sinp in [-1, 1], yaw in [0, 360))
    local sinp = math.max(-1.0, math.min(1.0, 2.0 * (w * y - z * x)))
    local pitch = math.deg(math.asin(sinp))
    local roll = math.deg(math.atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)))
    local yaw = (math.deg(math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))) + 360.0) % 360.0
    if yaw >= 360.0 or yaw < 0.0 then
        yaw = 0.0
    end
    return pitch, roll, yaw
end

local function mark_node_online(hud, node_name, ts)
    local node = hud.nodes and hud.nodes[node_name]
    if node then
        node.online = true
        node.lastSeenMs = ts
    end
end

local function register_discovered_craft(hud, n, domain_id, base_ch, ts)
    if not is_finite_number(n) or math.floor(n) ~= n or n < 1 or n > 1000 then
        return
    end
    if not hud.discoveredCrafts[n] then
        table.insert(hud.discoveredOrder, n)
        table.sort(hud.discoveredOrder)
    end
    hud.discoveredCrafts[n] = {
        aircraftIndexN = n,
        domainId = domain_id,
        baseChannel = base_ch,
        lastSeenMs = ts,
    }
end

local function accept_or_lock_craft_domain(net_ctx, pkt)
    if type(net_ctx) ~= "table" then
        return true
    end
    local pkt_dom = (type(pkt.domainId) == "string" and pkt.domainId ~= "") and pkt.domainId or nil
    if net_ctx.autoDomain == true then
        if pkt_dom and pkt_dom ~= "*" then
            net_ctx.targetDomainId = pkt_dom
            net_ctx.autoDomain = false
        end
        return true
    end
    local target = net_ctx.targetDomainId
    if type(target) == "string" and target ~= "" and target ~= "*" and pkt_dom and pkt_dom ~= target then
        return false
    end
    return true
end

local function apply_attitude(hud, att)
    if type(att) ~= "table" then return end
    if att.w ~= nil then
        hud.pitch, hud.roll, hud.yaw = telemetry_hud_state.quat_to_euler_deg(att)
        return
    end
    if is_finite_number(att.pitch) then hud.pitch = att.pitch end
    if is_finite_number(att.roll) then hud.roll = att.roll end
    if is_finite_number(att.yaw) then
        hud.yaw = att.yaw
    elseif is_finite_number(att.heading) then
        hud.yaw = att.heading
    end
end

local function apply_dynamics(hud, dyn)
    if type(dyn) ~= "table" then return end
    if is_finite_number(dyn.altitudeY) then hud.altitudeY = dyn.altitudeY end
    if is_finite_number(dyn.verticalSpeed) then hud.verticalSpeed = dyn.verticalSpeed end
    if is_finite_number(dyn.groundSpeed) then
        hud.groundSpeed = dyn.groundSpeed
    elseif type(dyn.velocity) == "table" then
        local vx = tonumber(dyn.velocity.vx) or 0.0
        local vz = tonumber(dyn.velocity.vz) or 0.0
        hud.groundSpeed = math.sqrt(vx * vx + vz * vz)
    end
end

local function apply_payload_telemetry(hud, p)
    apply_attitude(hud, p.attitude)
    apply_dynamics(hud, p.dynamics)
    if is_finite_number(p.fuel) then
        hud.fuel = math.max(0.0, math.min(1.0, p.fuel))
    end
    if is_finite_number(p.dynamicLoad) then
        hud.dynamicLoad = p.dynamicLoad
    end
    if p.sensorOk ~= nil then
        hud.sensorOk = (p.sensorOk == true)
    end
    if type(p.actuatorHealth) == "table" then
        local ah = p.actuatorHealth
        if ah.allOk ~= nil then
            hud.actuatorOk = (ah.allOk == true)
        else
            hud.actuatorOk = (ah.tap ~= false) and (ah.asa ~= false)
        end
    elseif p.actuatorHealth ~= nil then
        hud.actuatorOk = (p.actuatorHealth == true)
    end
end

local function record_craft_telemetry_rx(hud, net_ctx, base, pkt, distance_m, ts)
    hud.lastTelemMs = ts
    hud.lastDistanceM = distance_m
    hud.linkQuality = telemetry_hud_state.classify_link_quality(distance_m, 0, hud.cfg)

    local n = (type(net_ctx) == "table" and net_ctx.aircraftIndexN)
        or (math.floor((base - CRAFT_BASE_MIN) / CRAFT_BANDWIDTH) + 1)
    local domain_id = (type(pkt.domainId) == "string" and pkt.domainId ~= "") and pkt.domainId
        or (type(net_ctx) == "table" and net_ctx.targetDomainId)
        or string.format("AIRCRAFT_%02d", n)
    register_discovered_craft(hud, n, domain_id, base, ts)
end

local function handle_block_assign(hud, net_ctx, channel, p, ts)
    local gcs_ch = (type(net_ctx) == "table" and net_ctx.gcsBootstrapChannel) or 50000
    if channel ~= gcs_ch then return false end
    mark_node_online(hud, "GCS", ts)

    local base_ch = p.baseChannel
    local valid_status = (p.status == nil or p.status == "ASSIGNED" or p.status == "REASSIGNED")
    if valid_status and is_finite_number(base_ch) and base_ch >= CRAFT_BASE_MIN
        and base_ch <= CRAFT_BASE_MAX and ((base_ch - CRAFT_BASE_MIN) % CRAFT_BANDWIDTH) == 0 then
        local n = math.floor((base_ch - CRAFT_BASE_MIN) / CRAFT_BANDWIDTH) + 1
        local existing = hud.discoveredCrafts[n]
        local dom = (type(p.domainId) == "string" and p.domainId ~= "") and p.domainId
            or (existing and existing.domainId)
            or string.format("AIRCRAFT_%02d", n)
        register_discovered_craft(hud, n, dom, base_ch, ts)
    end
    return true
end

local function handle_flight_telemetry(hud, net_ctx, channel, base, pkt, distance_m, ts)
    if channel ~= (base + 2) or not accept_or_lock_craft_domain(net_ctx, pkt) then
        return false
    end
    local p = pkt.payload
    apply_payload_telemetry(hud, p)
    if type(p.controlState) == "string" then hud.fsmState = p.controlState end
    if type(p.activeSource) == "string" then hud.activeSource = p.activeSource end
    mark_node_online(hud, "VAS", ts)
    record_craft_telemetry_rx(hud, net_ctx, base, pkt, distance_m, ts)
    return true
end

local function handle_mfd_state(hud, net_ctx, channel, base, pkt, distance_m, ts)
    if channel ~= (base + 3) or not accept_or_lock_craft_domain(net_ctx, pkt) then
        return false
    end
    local p = pkt.payload
    apply_payload_telemetry(hud, p)
    if type(p.fsmState) == "string" then
        hud.fsmState = p.fsmState
    elseif type(p.controlState) == "string" then
        hud.fsmState = p.controlState
    end
    if type(p.flightMode) == "string" then hud.flightMode = p.flightMode end
    if type(p.activeSource) == "string" then
        hud.activeSource = p.activeSource
    elseif type(p.source) == "string" then
        hud.activeSource = p.source
    end
    mark_node_online(hud, (p.source == "AMM_INTEGRATED") and "AMM" or "VAS", ts)
    record_craft_telemetry_rx(hud, net_ctx, base, pkt, distance_m, ts)
    return true
end

function telemetry_hud_state.ingest_packet(hud, net_ctx, channel, pkt, distance_m, now_ms)
    if type(hud) ~= "table" or type(pkt) ~= "table" or pkt.ver ~= "1.9.5"
        or type(pkt.type) ~= "string" or type(pkt.payload) ~= "table" then
        return false
    end

    local ts = get_time_ms(now_ms)
    local base = (type(net_ctx) == "table" and net_ctx.baseChannel) or CRAFT_BASE_MIN
    local ack_ch = (type(net_ctx) == "table" and net_ctx.missionAckChannel) or 50004
    local ptype, p = pkt.type, pkt.payload

    if ptype == "MSG_BLOCK_ASSIGN" then
        return handle_block_assign(hud, net_ctx, channel, p, ts)
    elseif ptype == "MSG_MISSION_ACK" then
        if channel ~= ack_ch and channel ~= (base + 0) then return false end
        hud.lastMissionAck = p
        mark_node_online(hud, "AMM", ts)
        return true
    elseif ptype == "MSG_FLIGHT_TELEMETRY" then
        return handle_flight_telemetry(hud, net_ctx, channel, base, pkt, distance_m, ts)
    elseif ptype == "MSG_MFD_STATE" then
        return handle_mfd_state(hud, net_ctx, channel, base, pkt, distance_m, ts)
    elseif ptype == "MSG_PBIT_REPORT" then
        if (channel ~= (base + 2) and channel ~= (base + 8)) or not accept_or_lock_craft_domain(net_ctx, pkt) then
            return false
        end
        hud.lastPbitReport = p
        mark_node_online(hud, "VAS", ts)
        return true
    elseif ptype == "MSG_EMERGENCY_ALERT" then
        if channel ~= (base + 9) or not accept_or_lock_craft_domain(net_ctx, pkt) then
            return false
        end
        hud.lastAlert = p
        mark_node_online(hud, "VAS", ts)
        return true
    end
    return false
end

function telemetry_hud_state.update_link_timeouts(hud, now_ms)
    if type(hud) ~= "table" then return end
    local ts = get_time_ms(now_ms)
    local age_ms = is_finite_number(hud.lastTelemMs) and math.max(0, ts - hud.lastTelemMs) or nil
    hud.linkQuality = telemetry_hud_state.classify_link_quality(hud.lastDistanceM, age_ms, hud.cfg)

    local lq = (type(hud.cfg.linkQuality) == "table") and hud.cfg.linkQuality or {}
    local stale_ms = lq.nodeStaleMs or hud.cfg.nodeTimeoutMs or 3000
    for _, node in pairs(hud.nodes or {}) do
        if type(node) == "table" and node.online then
            if not is_finite_number(node.lastSeenMs) or (ts - node.lastSeenMs) > stale_ms then
                node.online = false
            end
        end
    end
end

function telemetry_hud_state.select_next_discovered(hud, current_n)
    if type(hud) ~= "table" or type(hud.discoveredOrder) ~= "table" or #hud.discoveredOrder == 0 then
        return nil, nil
    end
    local order = hud.discoveredOrder
    local next_n = order[1]
    if is_finite_number(current_n) then
        for i = 1, #order do
            if order[i] > current_n then
                next_n = order[i]
                break
            end
        end
    end
    local entry = hud.discoveredCrafts and hud.discoveredCrafts[next_n]
    return next_n, entry and entry.domainId or nil
end

return telemetry_hud_state
