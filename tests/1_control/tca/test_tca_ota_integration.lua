-- tests/1_control/tca/test_tca_ota_integration.lua
local tca_daemon = require("tca_daemon")
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

local function make_tca_node(tag)
    local rootDir = sdk.temp_path("tca_ota_" .. tag)
    if fs.exists(rootDir) then
        fs.delete(rootDir)
    end
    fs.makeDir(rootDir)

    local modem = mock.modem({ wireless = true })
    local cfg = {
        groupId = "THR_MAIN_L",
        aircraftDomainId = "AIRCRAFT_01",
        aircraftIndexN = 1,
        baseChannel = 10000,
        channels = { thrustActuation = 10010 },
        watchdogTimeoutMs = 300,
        nominalActuatorCount = 4,
        interactionMode = "REDSTONE",
        ports = { modemSide = "top", redstoneSide = "bottom", apiSides = {} },
        ota = {
            bayId = 1,
            rootDir = rootDir,
            bootConfirmTicks = 20,
            onRebootFn = function() end,
        },
    }
    local inst = tca_daemon.init(cfg, modem)
    return inst, modem, rootDir
end

describe("TCA OTA integration", function()
    it("opens CH 105 on init and responds to MSG_OTA_DISCOVER_REQ with moduleId tca", function()
        local inst, modem = make_tca_node("discover")
        assert_true(modem.isOpen(105), "OTA CMD channel 105 must be opened on init")

        local req = make_ota_pkt("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        })
        local keepGoing = inst:step_event("modem_message", "top", 105, 106, req, 1)
        assert_true(keepGoing)

        local acks = find_tx_of_type(modem, "MSG_OTA_DISCOVER_ACK")
        assert_eq(#acks, 1)
        assert_eq(acks[1].tx, 106)
        assert_eq(acks[1].pkt.payload.moduleId, "tca")
    end)

    it("defers pending OTA commit until 20 healthy loop ticks complete", function()
        local inst, modem, rootDir = make_tca_node("boot_commit")
        local pendingPath = rootDir .. "/.ota_pending.json"
        write_json(pendingPath, {
            txId = "tx-tca-01",
            moduleId = "tca",
            targetVersion = "1.14.0",
            backupDir = rootDir .. "/ota_backup/tx-tca-01",
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        })

        assert_true(fs.exists(pendingPath), "pending marker must not commit inside init")

        inst:step_event("timer", 1)
        assert_true(fs.exists(pendingPath), "pending marker must NOT commit on tick 1")
        assert_eq(#find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS"), 0)

        for i = 2, 19 do
            inst:step_event("timer", i)
            assert_true(fs.exists(pendingPath), "pending marker must remain before tick 20")
        end

        inst:step_event("timer", 20)
        assert_false(fs.exists(pendingPath), "pending marker must clear on tick 20")

        local statuses = find_tx_of_type(modem, "MSG_OTA_BOOT_STATUS")
        assert_eq(#statuses, 1)
        assert_eq(statuses[1].tx, 106)
        assert_eq(statuses[1].pkt.payload.status, "COMMITTED")
        assert_eq(statuses[1].pkt.payload.moduleId, "tca")
        assert_eq(statuses[1].pkt.payload.version, "1.14.0")
    end)

    it("rejects MSG_OTA_BEGIN with NOT_DISARMED when NORMAL or thrust active", function()
        local inst, modem = make_tca_node("safety")
        local thrustPkt = make_ota_pkt("AIRCRAFT_01", 1, "MSG_THRUST_CMD", {
            watchdogSeq = 1,
            controlState = "NORMAL",
            outputs = { THR_MAIN_L = 10 },
        })
        inst:step_event("modem_message", "top", 10010, 10010, thrustPkt, 1)

        local content = "return true"
        local crc = ota_agent.crc32(content)
        local beginReq = make_ota_pkt("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-tca-deny",
            targetModuleId = "tca",
            targetDomainId = "AIRCRAFT_01",
            targetVersion = "1.14.0",
            totalBytes = #content,
            totalCrc32 = crc,
            files = {
                { path = "/main.lua", size = #content, crc32 = crc, chunkCount = 1 },
            },
        })
        inst:step_event("modem_message", "top", 105, 106, beginReq, 1)

        local nacks = find_tx_of_type(modem, "MSG_OTA_NACK")
        assert_eq(#nacks, 1)
        assert_eq(nacks[1].tx, 106)
        assert_eq(nacks[1].pkt.payload.phase, "BEGIN")
        assert_eq(nacks[1].pkt.payload.reason, "NOT_DISARMED")
    end)
end)
