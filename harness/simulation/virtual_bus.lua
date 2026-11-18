-- harness/simulation/virtual_bus.lua
-- Virtual RF network bus router for CC:Tweaked multi-node simulation
local M = {}

local function estimate_bytes(v, depth)
    local t = type(v)
    if t == "string" then
        return #v + 2
    elseif t == "number" or t == "boolean" then
        return #tostring(v)
    elseif t == "table" then
        if (depth or 0) > 6 then
            return 2
        end
        local total = 2
        local first = true
        for k, val in pairs(v) do
            if not first then total = total + 1 end
            first = false
            total = total + #tostring(k) + 3 + estimate_bytes(val, (depth or 0) + 1)
        end
        return total
    end
    return 4
end

local function strip_self(self_tbl, a1, ...)
    if a1 == self_tbl then
        return ...
    end
    return a1, ...
end

function M.create_bus(opts)
    local options = opts or {}
    local bus = {
        time = tonumber(options.clock or 1000.0),
        default_distance = tonumber(options.default_distance or 25.0),
        packet_loss_rate = tonumber(options.packet_loss_rate or 0.0),
        modems = {},
        channels = {}, -- channel -> { [node_id] = modem }
        pending = {},
        packet_log = {},
        seq = 0,
    }

    function bus:create_modem(node_id, side)
        local nid = tostring(node_id or "ANON_" .. tostring(#bus.modems + 1))
        local m_side = tostring(side or "top")

        local modem = {
            node_id = nid,
            side = m_side,
            opened = {},
            inbox = {},
            on_message = nil,
        }

        function modem.open(a1, ...)
            local ch = tonumber(strip_self(modem, a1, ...))
            if not ch or ch < 0 or ch > 65535 then
                error("Invalid channel: " .. tostring(ch), 2)
            end
            modem.opened[ch] = true
            if not bus.channels[ch] then
                bus.channels[ch] = {}
            end
            bus.channels[ch][nid] = modem
        end

        function modem.close(a1, ...)
            local ch = tonumber(strip_self(modem, a1, ...))
            if ch then
                modem.opened[ch] = nil
                if bus.channels[ch] then
                    bus.channels[ch][nid] = nil
                    if next(bus.channels[ch]) == nil then
                        bus.channels[ch] = nil
                    end
                end
            end
        end

        function modem.closeAll(a1, ...)
            for ch, _ in pairs(modem.opened) do
                modem.close(ch)
            end
        end

        function modem.isOpen(a1, ...)
            local ch = tonumber(strip_self(modem, a1, ...))
            return ch ~= nil and modem.opened[ch] == true
        end

        function modem.isWireless(a1, ...)
            return true
        end

        function modem.getNamesRemote(a1, ...)
            return {}
        end

        function modem.isPresentRemote(a1, ...)
            return false
        end

        function modem.getTypeRemote(a1, ...)
            return nil
        end

        function modem.drain(a1, ...)
            local out = modem.inbox
            modem.inbox = {}
            return out
        end

        function modem.transmit(a1, a2, a3, ...)
            local ch, reply_ch, payload
            if a1 == modem then
                ch, reply_ch, payload = a2, a3, ...
            else
                ch, reply_ch, payload = a1, a2, a3
            end

            ch = tonumber(ch)
            reply_ch = tonumber(reply_ch)
            if not ch or ch < 0 or ch > 65535 then
                error("Invalid channel " .. tostring(ch), 2)
            end
            if not reply_ch or reply_ch < 0 or reply_ch > 65535 then
                error("Invalid reply channel " .. tostring(reply_ch), 2)
            end

            table.insert(bus.pending, {
                from = nid,
                channel = ch,
                replyChannel = reply_ch,
                payload = payload,
                distance = bus.default_distance,
                time = bus.time,
            })
        end

        bus.modems[nid] = modem
        return modem
    end

    function bus:step(dt)
        local delta = tonumber(dt or 0.05)
        self.time = self.time + delta
        self:deliver()
    end

    function bus:deliver()
        local current_pending = self.pending
        self.pending = {}

        for _, msg in ipairs(current_pending) do
            self.seq = self.seq + 1
            local logged_pkt = {
                seq = self.seq,
                from = msg.from,
                channel = msg.channel,
                replyChannel = msg.replyChannel,
                payload = msg.payload,
                distance = msg.distance,
                time = msg.time,
            }
            table.insert(self.packet_log, logged_pkt)

            if type(_G.__VIRTUAL_BUS_PACKET_LOG) == "table" then
                table.insert(_G.__VIRTUAL_BUS_PACKET_LOG, {
                    suite = _G.__ACTIVE_E2E_SUITE,
                    channel = msg.channel,
                    replyChannel = msg.replyChannel,
                    from = msg.from,
                    time = msg.time,
                    payload = msg.payload,
                })
            end

            local delivered_count = 0
            local listeners = self.channels[msg.channel]
            if listeners then
                for lid, target_modem in pairs(listeners) do
                    -- Deliver to all listening nodes (except sender unless loopback explicitly allowed)
                    if lid ~= msg.from then
                        delivered_count = delivered_count + 1
                        local entry = {
                            side = target_modem.side,
                            channel = msg.channel,
                            replyChannel = msg.replyChannel,
                            payload = msg.payload,
                            distance = msg.distance,
                        }
                        table.insert(target_modem.inbox, entry)
                        if type(target_modem.on_message) == "function" then
                            local ok, err = pcall(target_modem.on_message, entry)
                            if not ok then
                                -- log warning, do not crash router
                            end
                        end
                    end
                end
            end

            local prof = _G.__AUDIT_PROFILE
            if type(prof) == "table" and prof.enabled then
                prof.bus = prof.bus or { channels = {}, edges = {} }
                local channels_map = prof.bus.channels
                local ch_key = tostring(msg.channel)
                local crec = channels_map[ch_key]
                if not crec then
                    crec = {
                        channel = msg.channel,
                        packets = 0,
                        total_bytes = 0,
                        max_bytes = 0,
                        unreceived_packets = 0,
                        senders = {},
                    }
                    channels_map[ch_key] = crec
                end
                crec.packets = crec.packets + 1
                if delivered_count == 0 then
                    crec.unreceived_packets = crec.unreceived_packets + 1
                end

                if not prof.skip_lua_bytes then
                    local nbytes = estimate_bytes(msg.payload, 0)
                    crec.total_bytes = crec.total_bytes + nbytes
                    if nbytes > crec.max_bytes then
                        crec.max_bytes = nbytes
                    end
                    crec.senders[msg.from] = (crec.senders[msg.from] or 0) + 1

                    local edges_map = prof.bus.edges
                    local pkt_type = (type(msg.payload) == "table" and tostring(msg.payload.type or "<unknown>")) or "<non-table>"
                    local ekey = tostring(msg.from) .. "|" .. ch_key .. "|" .. pkt_type
                    local erec = edges_map[ekey]
                    if not erec then
                        erec = {
                            from = msg.from,
                            channel = msg.channel,
                            packet_type = pkt_type,
                            count = 0,
                            total_bytes = 0,
                        }
                        edges_map[ekey] = erec
                    end
                    erec.count = erec.count + 1
                    erec.total_bytes = erec.total_bytes + nbytes
                end
            end
        end
    end

    function bus:find_packets(filter)
        local flt = filter or {}
        local results = {}
        for _, pkt in ipairs(self.packet_log) do
            local matched = true
            if flt.channel ~= nil and pkt.channel ~= flt.channel then
                matched = false
            end
            if flt.replyChannel ~= nil and pkt.replyChannel ~= flt.replyChannel then
                matched = false
            end
            if flt.from ~= nil and pkt.from ~= flt.from then
                matched = false
            end
            if flt.type ~= nil then
                local pkt_type = (type(pkt.payload) == "table" and pkt.payload.type) or nil
                if pkt_type ~= flt.type then
                    matched = false
                end
            end
            if matched then
                table.insert(results, pkt)
            end
        end
        return results
    end

    function bus:clear_log()
        self.packet_log = {}
    end

    return bus
end

return M
