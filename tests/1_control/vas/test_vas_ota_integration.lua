-- tests/1_control/vas/test_vas_ota_integration.lua
local core_daemon = require("core_daemon")
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

local function make_vas_node(tag, extraOta)
    local rootDir = sdk.temp_path("vas_ota_" .. tag)
    if fs.exists(rootDir) then
        fs.delete(rootDir)
    end
    fs.makeDir(rootDir)

    local wirelessModem = mock.modem({ wireless = true })
    local wiredModem = mock.modem({ wireless = false })
    mock.peripheral_registry({
        top = { type = "modem", dev = wirelessModem },
        bottom = { type = "modem", dev = wiredModem },
    })

    local otaCfg = {
        bayId = 1,
        rootDir = rootDir,
        onRebootFn = function() end,
    }
    if type(extraOta) == "table" then
        for k, v in pairs(extraOta) do
            otaCfg[k] = v
        end
    end

    local cfg = {
        system = {
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
            debug = false,
        },
        ota = otaCfg,
    }
    local state = core_daemon.init(cfg)
    return state, wirelessModem, rootDir
end

describe("VAS OTA integration", function()
    it("opens CH 105 on init and responds to MSG_OTA_DISCOVER_REQ with moduleId vas", function()
        local state, modem = make_vas_node("discover")
        assert_true(modem.isOpen(105), "OTA CMD channel 105 must be opened on init")
        assert_eq(state.otaAgent.bootConfirmTicks, 20, "default bootConfirmTicks must be 20")

        local req = make_ota_pkt("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        })
        local handled = core_daemon.handle_event(state, "modem_message", "top", 105, 106, req, 1)
        assert_true(handled, "VAS handle_event must process OTA discover frame")

        local acks = find_tx_of_type(modem, "MSG_OTA_DISCOVER_ACK")
        assert_eq(#acks, 1)
        assert_eq(acks[1].tx, 106)
        assert_eq(acks[1].pkt.payload.moduleId, "vas")
    end)

    it("defers pending OTA commit until configured stabilization ticks complete", function()
        local state, modem, rootDir = make_vas_node("boot_commit", { bootConfirmTicks = 5 })
        local pendingPath = rootDir .. "/.ota_pending.json"
        write_json(pendingPath, {
            txId = "tx-vas-01",
            moduleId = "vas",
            targetVersion = "1.23.0",
            backupDir = rootDir .. "/ota_backup/tx-vas-01",
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        })

        assert_true(fs.exists(pendingPath), "pending marker must still exist immediately after init")

        core_daemon.tick(state)
        assert_true(fs.exists(pendingPath), "pending marker must NOT be committed on tick 1")
        assert_eq(#find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS"), 0)

        for _ = 2, 4 do
            core_daemon.tick(state)
            assert_true(fs.exists(pendingPath), "pending marker must remain before stabilization tick 5")
        end

        core_daemon.tick(state)
        assert_false(fs.exists(pendingPath), "pending marker must be cleared on stabilization tick 5")

        local statuses = find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS")
        assert_eq(#statuses, 1)
        assert_eq(statuses[1].tx, 106)
        assert_eq(statuses[1].pkt.payload.status, "COMMITTED")
        assert_eq(statuses[1].pkt.payload.moduleId, "vas")
        assert_eq(statuses[1].pkt.payload.version, "1.23.0")
    end)

    it("rejects MSG_OTA_BEGIN with NOT_DISARMED when NORMAL or airborne", function()
        local state, modem = make_vas_node("safety")
        state.fsm.currentState = "NORMAL"
        state.fsm.isAirborne = true

        local content = "return true"
        local crc = ota_agent.crc32(content)
        local beginReq = make_ota_pkt("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-vas-deny",
            targetModuleId = "vas",
            targetDomainId = "AIRCRAFT_01",
            targetVersion = "1.23.0",
            totalBytes = #content,
            totalCrc32 = crc,
            files = {
                { path = "/main.lua", size = #content, crc32 = crc, chunkCount = 1 },
            },
        })

        local handled = core_daemon.handle_event(state, "modem_message", "top", 105, 106, beginReq, 1)
        assert_true(handled)

        local nacks = find_tx_of_type(modem, "MSG_OTA_NACK")
        assert_eq(#nacks, 1)
        assert_eq(nacks[1].tx, 106)
        assert_eq(nacks[1].pkt.payload.phase, "BEGIN")
        assert_eq(nacks[1].pkt.payload.reason, "NOT_DISARMED")
    end)
end)
