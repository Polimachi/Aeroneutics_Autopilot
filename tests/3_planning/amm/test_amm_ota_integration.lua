-- tests/3_planning/amm/test_amm_ota_integration.lua
local amm_main = require("main")
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

local function make_amm_node(tag, extraOta)
    local rootDir = sdk.temp_path("amm_ota_" .. tag)
    if fs.exists(rootDir) then
        fs.delete(rootDir)
    end
    fs.makeDir(rootDir)

    local modem = mock.modem({ wireless = true })
    local cfg = amm_main.load_config("config/amm_config.json")
    cfg.headless = true
    cfg.ota = {
        bayId = 1,
        rootDir = rootDir,
        onRebootFn = function() end,
    }
    if type(extraOta) == "table" then
        for k, v in pairs(extraOta) do
            cfg.ota[k] = v
        end
    end
    local app = amm_main.create_app(cfg, modem)
    return app, modem, rootDir
end

describe("AMM OTA integration", function()
    it("opens CH 105 on create_app and responds to MSG_OTA_DISCOVER_REQ with moduleId amm", function()
        local app, modem = make_amm_node("discover")
        assert_true(modem.isOpen(105), "OTA CMD channel 105 must be opened on init")
        assert_eq(app.otaAgent.bootConfirmTicks, 20, "default bootConfirmTicks must be 20")

        local req = make_ota_pkt("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        })
        amm_main.process_event(app, "modem_message", "back", 105, 106, req, 1)

        local acks = find_tx_of_type(modem, "MSG_OTA_DISCOVER_ACK")
        assert_eq(#acks, 1)
        assert_eq(acks[1].tx, 106)
        assert_eq(acks[1].pkt.payload.moduleId, "amm")
    end)

    it("defers pending OTA commit until configured stabilization 20Hz ticks complete", function()
        local app, modem, rootDir = make_amm_node("boot_commit", { bootConfirmTicks = 5 })
        local pendingPath = rootDir .. "/.ota_pending.json"
        write_json(pendingPath, {
            txId = "tx-amm-01",
            moduleId = "amm",
            targetVersion = "2.2.0",
            backupDir = rootDir .. "/ota_backup/tx-amm-01",
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        })

        assert_true(fs.exists(pendingPath), "pending marker must not commit inside create_app")

        amm_main.step_20hz_tick(app, 0.05, 1000)
        assert_true(fs.exists(pendingPath), "pending marker must NOT commit on tick 1")
        assert_eq(#find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS"), 0)

        for i = 2, 4 do
            amm_main.step_20hz_tick(app, 0.05, 1000 + i * 50)
            assert_true(fs.exists(pendingPath), "pending marker must remain before stabilization tick 5")
        end

        amm_main.step_20hz_tick(app, 0.05, 1250)
        assert_false(fs.exists(pendingPath), "pending marker must clear on stabilization tick 5")

        local statuses = find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS")
        assert_eq(#statuses, 1)
        assert_eq(statuses[1].tx, 106)
        assert_eq(statuses[1].pkt.payload.status, "COMMITTED")
        assert_eq(statuses[1].pkt.payload.moduleId, "amm")
        assert_eq(statuses[1].pkt.payload.version, "2.2.0")
    end)

    it("rejects MSG_OTA_BEGIN with NOT_DISARMED when NORMAL or airborne", function()
        local app, modem = make_amm_node("safety")
        app.arbiter.fsmState = "NORMAL"
        app.arbiter.latest_telem = { controlState = "NORMAL", isAirborne = true }

        local content = "return true"
        local crc = ota_agent.crc32(content)
        local beginReq = make_ota_pkt("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-amm-deny",
            targetModuleId = "amm",
            targetDomainId = "AIRCRAFT_01",
            targetVersion = "2.2.0",
            totalBytes = #content,
            totalCrc32 = crc,
            files = {
                { path = "/main.lua", size = #content, crc32 = crc, chunkCount = 1 },
            },
        })
        amm_main.process_event(app, "modem_message", "back", 105, 106, beginReq, 1)

        local nacks = find_tx_of_type(modem, "MSG_OTA_NACK")
        assert_eq(#nacks, 1)
        assert_eq(nacks[1].tx, 106)
        assert_eq(nacks[1].pkt.payload.phase, "BEGIN")
        assert_eq(nacks[1].pkt.payload.reason, "NOT_DISARMED")
    end)
end)
