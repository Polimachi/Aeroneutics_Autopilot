-- src/3_planning/amm/modules/hook_runner.lua
-- AMM 0-Tick Non-Blocking Hook Runner & Zone 3 / Redstone Device Driver

local action_registry = require("action_registry")

local hook_runner = {}
hook_runner.__index = hook_runner

hook_runner.VALID_HOOK_TYPES = {
    REDSTONE_SET = true,
    REDSTONE_PULSE = true,
    ZONE3_PAYLOAD_CMD = true,
    NOTIFY_OPERATOR = true,
}

local VALID_SIDES = {
    top = true, bottom = true, left = true,
    right = true, front = true, back = true,
}

local function is_finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function now_fallback_ms()
    return (os.epoch and os.epoch("utc")) or (os.time() * 1000) or 0
end

local function resolve_color_mask(color, colors_api)
    if type(color) == "number" and is_finite(color) then
        return color
    end
    if type(color) == "string" and type(colors_api) == "table" and is_finite(colors_api[color]) then
        return colors_api[color]
    end
    return nil
end

local function apply_redstone(rs, colors_api, spec, active)
    if type(rs) ~= "table" or type(spec) ~= "table" or not VALID_SIDES[spec.side] then
        return nil, 0
    end
    if spec.color ~= nil then
        local mask = resolve_color_mask(spec.color, colors_api)
        if not mask then return nil, 0 end
        local cur = (type(rs.getBundledOutput) == "function" and rs.getBundledOutput(spec.side)) or 0
        local next_mask = active and bit32.bor(cur, mask) or bit32.band(cur, bit32.bnot(mask))
        if type(rs.setBundledOutput) == "function" then
            rs.setBundledOutput(spec.side, next_mask)
        end
        return "bundled", mask
    end
    if spec.level ~= nil and type(spec.level) == "number" then
        local lvl = active and math.max(0, math.min(15, math.floor(spec.level))) or 0
        if type(rs.setAnalogOutput) == "function" then
            rs.setAnalogOutput(spec.side, lvl)
        end
        return "analog", 0
    end
    if type(rs.setOutput) == "function" then
        rs.setOutput(spec.side, active == true)
    end
    return "digital", 0
end

local function deactivate_pulse(rs, colors_api, entry)
    local spec = { side = entry.side }
    if entry.kind == "bundled" then
        spec.color = entry.colorMask
    elseif entry.kind == "analog" then
        spec.level = 0
    end
    apply_redstone(rs, colors_api, spec, false)
end

local function schedule_pulse(self, spec, now_ms)
    local t_ms = is_finite(now_ms) and now_ms or now_fallback_ms()
    local kind, mask = apply_redstone(self.redstone, self.colors, spec, true)
    if not kind then return false end
    local dur = math.max(0, tonumber(spec.durationMs) or 500)
    local expire = t_ms + dur
    local key = tostring(spec.side) .. ":" .. kind .. ":" .. tostring(mask)
    local existing = self.activePulses[key]
    if existing then
        existing.expireMs = math.max(existing.expireMs, expire)
    else
        self.activePulses[key] = {
            side = spec.side,
            kind = kind,
            colorMask = mask,
            expireMs = expire,
        }
    end
    return true
end

local HOOK_HANDLERS = {
    REDSTONE_SET = function(self, hook)
        local active = (hook.state ~= false) and (hook.level == nil or hook.level > 0)
        local kind = apply_redstone(self.redstone, self.colors, hook, active)
        return kind ~= nil
    end,
    REDSTONE_PULSE = function(self, hook, _cp, now_ms)
        return schedule_pulse(self, hook, now_ms)
    end,
    ZONE3_PAYLOAD_CMD = function(self, hook, checkpoint)
        if not self.net then return false end
        local sel = (hook.channelOffset ~= nil) and hook.channelOffset or hook.targetChannel
        local cp_id = checkpoint and checkpoint.checkpointId or nil
        local ok = self.net:send_payload_req(sel, cp_id, hook.command, hook.payload or {}, { keepOpen = false })
        return ok == true
    end,
    NOTIFY_OPERATOR = function(self, hook, checkpoint, _now_ms, emitted)
        local note = {
            level = hook.level or "INFO",
            message = tostring(hook.message or ""),
        }
        table.insert(self.notifications, note)
        table.insert(emitted, note)
        if type(self.on_notify) == "function" then
            self.on_notify(note.level, note.message, checkpoint)
        end
        return true
    end,
}

function hook_runner.new(opts)
    local o = opts or {}
    return setmetatable({
        net = o.net,
        redstone = o.redstone or _G.redstone,
        colors = o.colors or _G.colors,
        on_notify = o.on_notify,
        activePulses = {},
        pendingPayload = nil,
        lastPayloadAck = nil,
        notifications = {},
    }, hook_runner)
end

function hook_runner:execute_hooks(hooks, checkpoint, now_ms)
    if type(hooks) ~= "table" then return 0, {} end
    local count, emitted = 0, {}
    for _, hook in ipairs(hooks) do
        local handler = type(hook) == "table" and HOOK_HANDLERS[hook.type]
        if handler and handler(self, hook, checkpoint, now_ms, emitted) then
            count = count + 1
        end
    end
    return count, emitted
end

local function start_payload_action(self, cp)
    if not self.net then return false, "NET_UNAVAILABLE" end
    local p = cp.params or {}
    local sel = (p.channelOffset ~= nil) and p.channelOffset or (p.targetChannel ~= nil and p.targetChannel or p.channel)
    local ch_valid, ch_err = self.net:resolve_payload_channel(sel)
    if not ch_valid then return false, ch_err end
    local wait_ack = (p.waitForAck ~= false and p.awaitAck ~= false)
    self.lastPayloadAck = nil
    local cmd_body = p.commandPayload or p.payload or {}
    local ok, ch_or_err = self.net:send_payload_req(sel, cp.checkpointId, p.command, cmd_body, { keepOpen = wait_ack })
    if not ok then return false, ch_or_err end
    if wait_ack then
        self.pendingPayload = {
            channel = ch_or_err,
            checkpointId = cp.checkpointId,
            command = p.command,
            expectedStatus = p.expectedStatus or "OK",
        }
    end
    return true, nil
end

local function start_redstone_action(self, cp, now_ms)
    local p = cp.params or {}
    if not VALID_SIDES[p.side] then return false, "INVALID_REDSTONE_SIDE" end
    if p.mode == "WAIT_INPUT" then return true, nil end
    if p.mode ~= "EMIT" then return false, "INVALID_REDSTONE_MODE" end
    if tonumber(p.durationMs or 0) > 0 then
        schedule_pulse(self, p, now_ms)
    else
        apply_redstone(self.redstone, self.colors, p, p.state ~= false)
    end
    return true, nil
end

function hook_runner:start_action(checkpoint, now_ms)
    if type(checkpoint) ~= "table" or type(checkpoint.action) ~= "string" then
        return false, "INVALID_CHECKPOINT"
    end
    if action_registry.is_action_deferred(checkpoint.action) then
        return false, "DEFERRED_ACTION_UNSUPPORTED"
    end
    if action_registry.is_legacy_action(checkpoint.action) then
        return false, "SCHEMA_INVALID"
    end
    if checkpoint.action == "ACT_PAY_BUS_CMD" then
        return start_payload_action(self, checkpoint)
    elseif checkpoint.action == "ACT_PAY_REDSTONE" then
        return start_redstone_action(self, checkpoint, now_ms)
    end
    return true, nil
end

function hook_runner:tick(now_ms)
    local t_ms = is_finite(now_ms) and now_ms or now_fallback_ms()
    local expired = {}
    for key, entry in pairs(self.activePulses) do
        if t_ms >= entry.expireMs then
            expired[#expired + 1] = key
        end
    end
    for _, key in ipairs(expired) do
        deactivate_pulse(self.redstone, self.colors, self.activePulses[key])
        self.activePulses[key] = nil
    end
    return #expired
end

function hook_runner:on_payload_ack(packet, channel)
    local pkt = packet
    if self.net and self.net.decode_envelope then
        local ok, dec = self.net:decode_envelope(packet)
        if not ok then return false, dec end
        pkt = dec
    elseif type(pkt) ~= "table" or type(pkt.payload) ~= "table" then
        return false, "INVALID_PAYLOAD"
    end
    if pkt.type ~= "MSG_PAYLOAD_ACK" then
        return false, "UNEXPECTED_PACKET_TYPE"
    end
    if channel ~= nil and self.net and not self.net:is_payload_channel(channel) then
        return false, "INVALID_ZONE3_CHANNEL"
    end
    local pending = self.pendingPayload
    if pending then
        if channel ~= nil and pending.channel ~= channel then return false, "CHANNEL_MISMATCH" end
        if pending.checkpointId ~= nil and pkt.payload.checkpointId ~= pending.checkpointId then
            return false, "CHECKPOINT_MISMATCH"
        end
    end
    self.lastPayloadAck = pkt.payload
    local close_ch = channel or (pending and pending.channel)
    if self.net and close_ch then
        self.net:close_payload_channel(close_ch)
    end
    self.pendingPayload = nil
    return true, self.lastPayloadAck
end

function hook_runner:get_last_payload_ack()
    return self.lastPayloadAck
end

function hook_runner:clear_step_state()
    self.pendingPayload = nil
    self.lastPayloadAck = nil
    if self.net and self.net.close_all_payload_channels then
        self.net:close_all_payload_channels()
    end
end

function hook_runner:cleanup()
    self:clear_step_state()
    for _, entry in pairs(self.activePulses) do
        deactivate_pulse(self.redstone, self.colors, entry)
    end
    self.activePulses = {}
end

return hook_runner
