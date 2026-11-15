-- tests/2_guidance/fcp/test_fcp_ota_integration.lua
package.path = package.path .. ";/modules/?.lua;/?/init.lua"
local fcp_main = require("main")
local network_manager = require("network_manager")
local ota_agent = require("ota_agent")

local function write_json(path, tbl)
    local parent = fs.getDir(path)
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
    local h = fs.open(path, "w")
    assert_not_nil(h, "failed to open for write: " .. tostring(path))
    h.write(textutils.serializeJSON(tbl))
    h.close()
end

local function make_ota_pkt(domainId, seq, msgType, payload)
    return {
        ver = "1.9.5",
        domainId = domainId,
        seq = seq,
        type = msgType,
        time = 1763210000000 + seq,
        payload = payload,
    }
end

local function find_tx_of_type(modem, msgType)
    local out = {}
    for _, item in ipairs(modem._transmitted) do
        if type(item.pkt) == "table" and item.pkt.type == msgType then
            out[#out + 1] = item
        end
    end
    return out
end

local function make_fcp_node(tag)
    local rootDir = sdk.temp_path("fcp_ota_" .. tag)
    if fs.exists(rootDir) then
        fs.delete(rootDir)
    end
    fs.makeDir(rootDir)

    local modem = mock.modem({ wireless = true })
    local cfg = fcp_main.load_config("config/fcp_config.json")
    cfg.ota = {
        bayId = 1,
        rootDir = rootDir,
        bootConfirmTicks = 20,
        onRebootFn = function() end,
    }
    local ctx = fcp_main.create_context(cfg, function() return modem end)
    return ctx, modem, rootDir
end

describe("FCP OTA integration", function()
    it("opens CH 105 on create_context and responds to MSG_OTA_DISCOVER_REQ with moduleId fcp", function()
        local ctx, modem = make_fcp_node("discover")
        assert_true(modem.isOpen(105), "OTA CMD channel 105 must be opened on init")

        local req = make_ota_pkt("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        })
        local handled = network_manager.ingest_modem_event(ctx.net, "top", 105, 106, req, 1, 1000)
        assert_true(handled, "FCP network manager must dispatch OTA discover frame")

        local acks = find_tx_of_type(modem, "MSG_OTA_DISCOVER_ACK")
        assert_eq(#acks, 1)
        assert_eq(acks[1].tx, 106)
        assert_eq(acks[1].pkt.payload.moduleId, "fcp")
    end)

    it("defers pending OTA commit until 20 healthy step_tick cycles complete", function()
        local ctx, modem, rootDir = make_fcp_node("boot_commit")
        local pendingPath = rootDir .. "/.ota_pending.json"
        write_json(pendingPath, {
            txId = "tx-fcp-01",
            moduleId = "fcp",
            targetVersion = "2.3.0",
            backupDir = rootDir .. "/ota_backup/tx-fcp-01",
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        })

        assert_true(fs.exists(pendingPath), "pending marker must not commit inside create_context")

        fcp_main.step_tick(ctx, 0.05, 1000)
        assert_true(fs.exists(pendingPath), "pending marker must NOT commit on tick 1")
        assert_eq(#find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS"), 0)

        for i = 2, 19 do
            fcp_main.step_tick(ctx, 0.05, 1000 + i * 50)
            assert_true(fs.exists(pendingPath), "pending marker must remain before tick 20")
        end

        fcp_main.step_tick(ctx, 0.05, 2000)
        assert_false(fs.exists(pendingPath), "pending marker must clear on tick 20")

        local statuses = find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS")
        assert_eq(#statuses, 1)
        assert_eq(statuses[1].tx, 106)
        assert_eq(statuses[1].pkt.payload.status, "COMMITTED")
        assert_eq(statuses[1].pkt.payload.moduleId, "fcp")
        assert_eq(statuses[1].pkt.payload.version, "2.3.0")
    end)

    it("rejects MSG_OTA_BEGIN when ACTIVE_TRACKING or when VAS telemetry reports ARMING/airborne", function()
        local ctx, modem = make_fcp_node("safety")
        local content = "return true"
        local crc = ota_agent.crc32(content)
        local beginReq1 = make_ota_pkt("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-fcp-deny-1",
            targetModuleId = "fcp",
            targetDomainId = "AIRCRAFT_01",
            targetVersion = "2.3.0",
            totalBytes = #content,
            totalCrc32 = crc,
            files = {
                { path = "/main.lua", size = #content, crc32 = crc, chunkCount = 1 },
            },
        })

        ctx.fsm.currentState = "ACTIVE_TRACKING"
        assert_true(network_manager.ingest_modem_event(ctx.net, "top", 105, 106, beginReq1, 1, 1000))

        ctx.fsm.currentState = "IDLE_ARMED"
        ctx.lastTelemPayload = { controlState = "ARMING", isAirborne = false }
        local beginReq2 = make_ota_pkt("HANGAR", 3, "MSG_OTA_BEGIN", {
            txId = "tx-fcp-deny-2",
            targetModuleId = "fcp",
            targetDomainId = "AIRCRAFT_01",
            targetVersion = "2.3.0",
            totalBytes = #content,
            totalCrc32 = crc,
            files = {
                { path = "/main.lua", size = #content, crc32 = crc, chunkCount = 1 },
            },
        })
        assert_true(network_manager.ingest_modem_event(ctx.net, "top", 105, 106, beginReq2, 1, 1050))

        local nacks = find_tx_of_type(modem, "MSG_OTA_NACK")
        assert_eq(#nacks, 2)
        assert_eq(nacks[1].pkt.payload.reason, "NOT_DISARMED")
        assert_eq(nacks[2].pkt.payload.reason, "NOT_DISARMED")
    end)
end)
