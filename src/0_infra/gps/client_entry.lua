-- GPS Client CLI Entrypoint (Gate 4 Cluster Client #2)
local gps_client = require("gps_client")
local protocol = require("protocol")

local function runClient(args)
    local domainId = args[1] or "AIRCRAFT_01"
    local altitudeY = tonumber(args[2]) or 100.0
    local replyChannel = tonumber(args[3]) or protocol.resolveDomainReplyChannel(domainId) or protocol.DEFAULT_REPLY_CHANNEL

    gps_client.init(domainId, "AIRCRAFT", replyChannel)

    term.clear()
    term.setCursorPos(1, 1)
    print(string.format("[GPS CLIENT] Domain: %s, ReplyCH: %d", domainId, replyChannel))
    print(string.format("Querying GPS fix at Alt=%.1fm...", altitudeY))

    -- Brief 50ms yield so swarm nodes and server complete modem binding
    sleep(0.05)

    local x, y, z, meta = gps_client.locate(altitudeY, 0.5)
    local status = meta and meta.status or "UNKNOWN"
    if harness_set_state then
        harness_set_state("resp_status", status)
    end

    if x and z then
        print(string.format("Fix: (%.2f, %.2f, %.2f) Status: %s", x, y, z, status))
    else
        print(string.format("Fix failed with status: %s", status))
    end
end

runClient({ ... })
