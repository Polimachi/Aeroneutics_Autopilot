-- tests/0_development/ota/test_ota_agent.lua
-- Unit test suite for self-contained slave OTA agent (/lib/ota_agent.lua)

local ota_agent = require("ota_agent")

local function write_text(path, content)
    local parent = fs.getDir(path)
    if parent and parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
    local h = fs.open(path, "w")
    assert_not_nil(h, "failed to open for write: " .. tostring(path))
    h.write(content)
    h.close()
end

local function read_text(path)
    assert_true(fs.exists(path), "expected file to exist: " .. tostring(path))
    local h = fs.open(path, "r")
    assert_not_nil(h, "failed to open for read: " .. tostring(path))
    local data = h.readAll()
    h.close()
    return data
end

local function make_env_envelope(domainId, seq, msgType, payload)
    return {
        ver = "1.9.5",
        domainId = domainId or "HANGAR-OTA-01",
        seq = seq or 1,
        type = msgType,
        time = 1763210000000 + (seq or 1),
        payload = payload or {},
    }
end

local function make_test_node(tag, opts)
    opts = opts or {}
    local rootDir = sdk.temp_path("ota_node_" .. tag)
    if fs.exists(rootDir) then
        fs.delete(rootDir)
    end
    fs.makeDir(rootDir)

    local modem = mock.modem({ wireless = true })
    local statusState = opts.status or { controlState = "DISARMED", isAirborne = false }
    local rebootCalls = 0
    local seqCounter = 0

    local agent = ota_agent.new({
        moduleId = opts.moduleId or "vas",
        domainId = opts.domainId or "AIRCRAFT_01",
        bayId = opts.bayId or 1,
        bayIds = opts.bayIds,
        bootConfirmTicks = opts.bootConfirmTicks or 20,
        fsApi = opts.fsApi or fs,
        modemApi = modem,
        rootDir = rootDir,
        getStatusFn = function()
            return statusState
        end,
        onRebootFn = function()
            rebootCalls = rebootCalls + 1
        end,
        seqFn = function()
            seqCounter = seqCounter + 1
            return seqCounter
        end,
        clockFn = function()
            return 1763210000123
        end,
    })

    return {
        rootDir = rootDir,
        modem = modem,
        agent = agent,
        setStatus = function(ctrl, airborne)
            statusState.controlState = ctrl
            statusState.isAirborne = airborne
        end,
        getReboots = function()
            return rebootCalls
        end,
        cleanup = function()
            if fs.exists(rootDir) then
                fs.delete(rootDir)
            end
        end,
    }
end

describe("ota_agent CRC32 (IEEE 802.3)", function()
    it("computes standard IEEE 802.3 CRC32 vectors with bit32", function()
        assert_eq(ota_agent.crc32(""), 0)
        assert_eq(ota_agent.crc32("123456789"), 0xCBF43926)
        assert_eq(ota_agent.crc32("Create_Aeroneutics_OTA"), ota_agent.crc32("Create_Aeroneutics_OTA"))
        assert_ne(ota_agent.crc32("abc"), ota_agent.crc32("abd"))
    end)

    it("falls back to pure-Lua 5.2 arithmetic when bit32 is absent", function()
        local origBit32 = _G.bit32
        local ok, emptyCrc, vecCrc = pcall(function()
            _G.bit32 = nil
            return ota_agent.crc32(""), ota_agent.crc32("123456789")
        end)
        _G.bit32 = origBit32
        assert_true(ok, "pure-Lua crc32 fallback must not throw: " .. tostring(emptyCrc))
        assert_eq(emptyCrc, 0)
        assert_eq(vecCrc, 0xCBF43926)
    end)
end)

describe("ota_agent hangar bay channel allocation and routing", function()
    it("computes Base_hangar + 4 / + 5 for bays 1..10 and rejects invalid bays", function()
        local cmd1, ack1 = ota_agent.get_channels(1)
        assert_eq(cmd1, 105)
        assert_eq(ack1, 106)

        local cmd10, ack10 = ota_agent.get_channels(10)
        assert_eq(cmd10, 195)
        assert_eq(ack10, 196)

        assert_throws(function() ota_agent.get_channels(0) end)
        assert_throws(function() ota_agent.get_channels(11) end)
        assert_throws(function() ota_agent.get_channels(1.5) end)
        assert_throws(function() ota_agent.get_channels("bad") end)
    end)

    it("opens all configured bayIds and replies on matching bay ackCh", function()
        local ctx = make_test_node("multibay", { bayId = 1, bayIds = { 1, 2 } })
        local cmdPrimary, ackPrimary, pairsList = ctx.agent:open_channels()
        assert_eq(cmdPrimary, 105)
        assert_eq(ackPrimary, 106)
        assert_eq(#pairsList, 2)
        assert_true(ctx.modem.isOpen(105))
        assert_true(ctx.modem.isOpen(115))

        local req1 = make_env_envelope("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        })
        local handled2 = ctx.agent:handle_packet(115, 116, req1)
        assert_true(handled2)
        assert_eq(#ctx.modem._transmitted, 1)
        assert_eq(ctx.modem._transmitted[1].tx, 116)
        assert_eq(ctx.modem._transmitted[1].rx, 115)

        local handled1 = ctx.agent:handle_packet(105, 106, req1)
        assert_true(handled1)
        assert_eq(#ctx.modem._transmitted, 2)
        assert_eq(ctx.modem._transmitted[2].tx, 106)
        assert_eq(ctx.modem._transmitted[2].rx, 105)

        -- Post-reboot BOOT_STATUS broadcasts across all configured bays (Bay 1 + Bay 2)
        write_text(ctx.rootDir .. "/.ota_pending.json", textutils.serializeJSON({
            txId = "tx-multibay-1",
            moduleId = "vas",
            targetVersion = "1.22.0",
            backupDir = "",
        }))
        local reported, rec = ctx.agent:confirm_boot_commit()
        assert_true(reported)
        assert_eq(rec.status, "COMMITTED")
        assert_eq(#ctx.modem._transmitted, 4)
        local bootChannels = {
            [ctx.modem._transmitted[3].tx] = ctx.modem._transmitted[3].pkt.type,
            [ctx.modem._transmitted[4].tx] = ctx.modem._transmitted[4].pkt.type,
        }
        assert_eq(bootChannels[106], "MSG_OTA_BOOT_STATUS")
        assert_eq(bootChannels[116], "MSG_OTA_BOOT_STATUS")

        ctx.cleanup()
    end)
end)

describe("ota_agent strict 1.9.5 envelope and safety gate", function()
    it("enforces is_safe_for_ota truth table across all flight states", function()
        assert_true(ota_agent.is_safe_for_ota({ controlState = "DISARMED", isAirborne = false }))
        assert_true(ota_agent.is_safe_for_ota({ controlState = "BOOT", isAirborne = false }))
        assert_true(ota_agent.is_safe_for_ota({ controlState = "IDLE_ARMED", isAirborne = nil }))

        local deniedStates = {
            "ARMING",
            "NORMAL",
            "CALIBRATION",
            "FAILSAFE_HOLD",
            "EMERGENCY_LAND",
            "AIRBORNE_EMERGENCY",
            "E_STOP",
            "ACTIVE_TRACKING",
            "PASSIVE_TRACKING",
            "AMM_TIMEOUT_HOLD",
            "UNKNOWN_STATE",
        }
        for _, st in ipairs(deniedStates) do
            local safe, reason = ota_agent.is_safe_for_ota({ controlState = st, isAirborne = false })
            assert_false(safe, "state must be rejected: " .. st)
            assert_eq(reason, "NOT_DISARMED")
        end

        local safeAir, reasonAir = ota_agent.is_safe_for_ota({ controlState = "DISARMED", isAirborne = true })
        assert_false(safeAir)
        assert_eq(reasonAir, "NOT_DISARMED")

        local safeNil, reasonNil = ota_agent.is_safe_for_ota(nil)
        assert_false(safeNil)
        assert_eq(reasonNil, "NOT_DISARMED")
    end)

    it("rejects non-1.9.5 or malformed envelopes without fallback", function()
        local ctx = make_test_node("bad_env")
        ctx.agent:open_channels()

        -- Missing ver (even if legacy version key provided)
        local ok1 = ctx.agent:handle_packet(105, 106, {
            version = "1.9.5",
            domainId = "HANGAR",
            seq = 1,
            type = "MSG_OTA_DISCOVER_REQ",
            time = 1000,
            payload = { targetModuleId = "*", targetDomainId = "*" },
        })
        assert_false(ok1)
        assert_eq(#ctx.modem._transmitted, 0)

        -- Wrong ver
        local ok2 = ctx.agent:handle_packet(105, 106, {
            ver = "1.9.4",
            domainId = "HANGAR",
            seq = 2,
            type = "MSG_OTA_DISCOVER_REQ",
            time = 1001,
            payload = { targetModuleId = "*", targetDomainId = "*" },
        })
        assert_false(ok2)
        assert_eq(#ctx.modem._transmitted, 0)

        ctx.cleanup()
    end)

    it("rejects BEGIN and REBOOT with NOT_DISARMED and zero disk writes when unsafe", function()
        local ctx = make_test_node("unsafe_gate", {
            status = { controlState = "NORMAL", isAirborne = true },
        })
        ctx.agent:open_channels()

        local content = "print('new')"
        local beginPkt = make_env_envelope("HANGAR", 1, "MSG_OTA_BEGIN", {
            txId = "tx-unsafe-1",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = {
                { path = "/main.lua", size = #content, crc32 = ota_agent.crc32(content), chunkCount = 1 },
            },
            totalBytes = #content,
            totalCrc32 = ota_agent.crc32(content),
        })

        local okBegin = ctx.agent:handle_packet(105, 106, beginPkt)
        assert_false(okBegin)
        assert_eq(#ctx.modem._transmitted, 1)
        local nack = ctx.modem._transmitted[1].pkt
        assert_eq(nack.ver, "1.9.5")
        assert_eq(nack.type, "MSG_OTA_NACK")
        assert_eq(nack.payload.reason, "NOT_DISARMED")
        assert_false(fs.exists(ctx.rootDir .. "/ota_staging"))
        assert_false(fs.exists(ctx.rootDir .. "/.ota_pending.json"))

        -- Also test ARMING with isAirborne=false
        ctx.setStatus("ARMING", false)
        local rebootPkt = make_env_envelope("HANGAR", 2, "MSG_OTA_REBOOT", {
            txId = "tx-unsafe-2",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
        })
        local okReboot = ctx.agent:handle_packet(105, 106, rebootPkt)
        assert_false(okReboot)
        assert_eq(ctx.getReboots(), 0)
        assert_eq(#ctx.modem._transmitted, 2)
        assert_eq(ctx.modem._transmitted[2].pkt.type, "MSG_OTA_NACK")
        assert_eq(ctx.modem._transmitted[2].pkt.payload.reason, "NOT_DISARMED")

        ctx.cleanup()
    end)
end)

describe("ota_agent module and domain addressing", function()
    it("silently ignores mismatched targetModuleId and rejects mismatched targetDomainId", function()
        local ctx = make_test_node("addr", { moduleId = "vas", domainId = "AIRCRAFT_01" })
        ctx.agent:open_channels()

        -- Another module on the same shared channel -> silent ignore
        local otherModBegin = make_env_envelope("HANGAR", 1, "MSG_OTA_BEGIN", {
            txId = "tx-tca-1",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "tca",
            targetVersion = "1.14.0",
            files = { { path = "/main.lua", size = 3, crc32 = ota_agent.crc32("abc"), chunkCount = 1 } },
            totalBytes = 3,
            totalCrc32 = ota_agent.crc32("abc"),
        })
        local okOtherMod = ctx.agent:handle_packet(105, 106, otherModBegin)
        assert_false(okOtherMod)
        assert_eq(#ctx.modem._transmitted, 0)

        -- Same moduleId, wrong domainId -> NACK DOMAIN_MISMATCH, zero disk writes
        local wrongDomainBegin = make_env_envelope("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-dom-1",
            targetDomainId = "AIRCRAFT_99",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = { { path = "/main.lua", size = 3, crc32 = ota_agent.crc32("abc"), chunkCount = 1 } },
            totalBytes = 3,
            totalCrc32 = ota_agent.crc32("abc"),
        })
        local okWrongDom = ctx.agent:handle_packet(105, 106, wrongDomainBegin)
        assert_false(okWrongDom)
        assert_eq(#ctx.modem._transmitted, 1)
        assert_eq(ctx.modem._transmitted[1].pkt.type, "MSG_OTA_NACK")
        assert_eq(ctx.modem._transmitted[1].pkt.payload.reason, "DOMAIN_MISMATCH")
        assert_false(fs.exists(ctx.rootDir .. "/ota_staging"))

        ctx.cleanup()
    end)
end)

describe("ota_agent nominal chunked staging, atomic apply, and abort paths", function()
    it("performs multi-file chunked OTA, writes backup and .ota_pending.json, updates .version.json, and reboots", function()
        local ctx = make_test_node("nominal")
        ctx.agent:open_channels()

        -- Pre-existing files & .version.json
        write_text(ctx.rootDir .. "/main.lua", "print('old main')")
        write_text(ctx.rootDir .. "/.version.json", textutils.serializeJSON({
            modules = {
                vas = {
                    id = "vas",
                    version = "1.21.0",
                    files = { "/main.lua" },
                    source = "github",
                    installedAt = 1000,
                },
            },
        }))

        local f1c1 = "local x = 1\n"
        local f1c2 = "print('new main', x)\n"
        local f1All = f1c1 .. f1c2
        local f2All = "return { ver = 2 }\n"
        local pkgAll = f1All .. f2All

        local beginPkt = make_env_envelope("HANGAR", 1, "MSG_OTA_BEGIN", {
            txId = "tx-nom-01",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = {
                { path = "/main.lua", size = #f1All, crc32 = ota_agent.crc32(f1All), chunkCount = 2 },
                { path = "/modules/new_mod.lua", size = #f2All, crc32 = ota_agent.crc32(f2All), chunkCount = 1 },
            },
            totalBytes = #pkgAll,
            totalCrc32 = ota_agent.crc32(pkgAll),
        })

        assert_true(ctx.agent:handle_packet(105, 106, beginPkt))
        assert_eq(ctx.modem._transmitted[1].pkt.type, "MSG_OTA_ACK")
        assert_eq(ctx.modem._transmitted[1].pkt.payload.phase, "BEGIN")

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 2, "MSG_OTA_CHUNK", {
            txId = "tx-nom-01", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(f1c1), data = f1c1,
        })))
        assert_eq(ctx.modem._transmitted[2].pkt.payload.phase, "CHUNK")
        assert_eq(ctx.modem._transmitted[2].pkt.payload.fileIndex, 1)
        assert_eq(ctx.modem._transmitted[2].pkt.payload.chunkIndex, 1)

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 3, "MSG_OTA_CHUNK", {
            txId = "tx-nom-01", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 2, chunkCrc32 = ota_agent.crc32(f1c2), data = f1c2,
        })))

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 4, "MSG_OTA_CHUNK", {
            txId = "tx-nom-01", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 2, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(f2All), data = f2All,
        })))

        -- Commit with autoReboot = true
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 5, "MSG_OTA_COMMIT", {
            txId = "tx-nom-01",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            autoReboot = true,
        })))

        local appliedAck = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(appliedAck.type, "MSG_OTA_ACK")
        assert_eq(appliedAck.payload.phase, "APPLIED")
        assert_eq(appliedAck.payload.status, "PENDING_COMMIT")
        assert_eq(ctx.getReboots(), 1)

        -- Verify live files swapped
        assert_eq(read_text(ctx.rootDir .. "/main.lua"), f1All)
        assert_eq(read_text(ctx.rootDir .. "/modules/new_mod.lua"), f2All)

        -- Verify staging cleaned
        assert_false(fs.exists(ctx.rootDir .. "/ota_staging/tx-nom-01"))

        -- Verify .version.json updated
        local verData = textutils.unserializeJSON(read_text(ctx.rootDir .. "/.version.json"))
        assert_eq(verData.modules.vas.version, "1.22.0")

        -- Verify .ota_pending.json schema matches startup_generator.lua
        local pending = textutils.unserializeJSON(read_text(ctx.rootDir .. "/.ota_pending.json"))
        assert_eq(pending.txId, "tx-nom-01")
        assert_eq(pending.moduleId, "vas")
        assert_eq(pending.targetVersion, "1.22.0")
        assert_eq(pending.bootAttempts, 0)
        assert_eq(pending.maxBootAttempts, 1)
        assert_eq(pending.status, "PENDING_COMMIT")
        assert_true(fs.exists(pending.versionBackupPath))
        assert_eq(#pending.restoredFiles, 2)

        local byDest = {}
        for _, rf in ipairs(pending.restoredFiles) do
            byDest[rf.dest] = rf
        end
        local mainRec = byDest[ctx.rootDir .. "/main.lua"]
        assert_not_nil(mainRec)
        assert_true(mainRec.existed)
        assert_eq(read_text(mainRec.src), "print('old main')")

        local newModRec = byDest[ctx.rootDir .. "/modules/new_mod.lua"]
        assert_not_nil(newModRec)
        assert_false(newModRec.existed)

        ctx.cleanup()
    end)

    it("rejects out-of-order chunks, chunk CRC mismatches, and commit CRC mismatches without touching live files", function()
        local ctx = make_test_node("crc_abort")
        ctx.agent:open_channels()

        write_text(ctx.rootDir .. "/main.lua", "print('safe original')")
        local payloadStr = "print('corruptible')"

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 1, "MSG_OTA_BEGIN", {
            txId = "tx-bad-1",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = {
                { path = "/main.lua", size = #payloadStr, crc32 = ota_agent.crc32(payloadStr), chunkCount = 1 },
            },
            totalBytes = #payloadStr,
            totalCrc32 = ota_agent.crc32(payloadStr),
        })))

        -- Out-of-order chunk (chunkIndex = 2 instead of 1)
        local okOob = ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 2, "MSG_OTA_CHUNK", {
            txId = "tx-bad-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 2, chunkCrc32 = ota_agent.crc32(payloadStr), data = payloadStr,
        }))
        assert_false(okOob)
        local nackOob = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(nackOob.type, "MSG_OTA_NACK")
        assert_eq(nackOob.payload.reason, "SEQ_OUT_OF_ORDER")
        assert_eq(nackOob.payload.expectedIndex, 1)

        -- Chunk CRC mismatch
        local okBadChunk = ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 3, "MSG_OTA_CHUNK", {
            txId = "tx-bad-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 1, chunkCrc32 = 12345, data = payloadStr,
        }))
        assert_false(okBadChunk)
        local nackCrc = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(nackCrc.type, "MSG_OTA_NACK")
        assert_eq(nackCrc.payload.reason, "CRC_MISMATCH")

        -- Abort cleans staging
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 4, "MSG_OTA_ABORT", {
            txId = "tx-bad-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", reason = "RETRY_EXHAUSTED",
        })))
        assert_false(fs.exists(ctx.rootDir .. "/ota_staging/tx-bad-1"))

        -- Abort with empty txId must not delete parent /ota_staging directory
        write_text(ctx.rootDir .. "/ota_staging/tx-sibling/file_1.part", "keep_me")
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 4, "MSG_OTA_ABORT", {
            txId = "", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", reason = "MALFORMED",
        })))
        assert_true(fs.exists(ctx.rootDir .. "/ota_staging/tx-sibling/file_1.part"))

        -- Second transaction: valid chunk, wrong totalCrc32 at COMMIT
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 5, "MSG_OTA_BEGIN", {
            txId = "tx-bad-2",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = {
                { path = "/main.lua", size = #payloadStr, crc32 = ota_agent.crc32(payloadStr), chunkCount = 1 },
            },
            totalBytes = #payloadStr,
            totalCrc32 = 999999,
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 6, "MSG_OTA_CHUNK", {
            txId = "tx-bad-2", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(payloadStr), data = payloadStr,
        })))
        local okCommit = ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 7, "MSG_OTA_COMMIT", {
            txId = "tx-bad-2", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", autoReboot = true,
        }))
        assert_false(okCommit)
        local nackCommit = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(nackCommit.type, "MSG_OTA_NACK")
        assert_eq(nackCommit.payload.reason, "CRC_MISMATCH")

        assert_false(fs.exists(ctx.rootDir .. "/ota_staging/tx-bad-2"))
        assert_false(fs.exists(ctx.rootDir .. "/.ota_pending.json"))
        assert_eq(read_text(ctx.rootDir .. "/main.lua"), "print('safe original')")
        assert_eq(ctx.getReboots(), 0)

        ctx.cleanup()
    end)
end)

describe("ota_agent config preservation, orphan cleanup, and 2-stage boot commit/rollback", function()
    it("preserves existing config/*.json when overwriteConfig is false, cleans orphan .lua files with backup, and commits after 20 ticks", function()
        local ctx = make_test_node("cfg_orphan_commit")
        ctx.agent:open_channels()

        local customCfg = '{"aircraftIndexN": 7, "custom": true}'
        write_text(ctx.rootDir .. "/main.lua", "print('v1')")
        write_text(ctx.rootDir .. "/modules/legacy_orphan.lua", "return 'legacy'")
        write_text(ctx.rootDir .. "/lib/avionics_sensors.lua", "return 'shared_lib'")
        write_text(ctx.rootDir .. "/config/vas_config.json", customCfg)
        write_text(ctx.rootDir .. "/.version.json", textutils.serializeJSON({
            modules = {
                vas = {
                    id = "vas",
                    version = "1.21.0",
                    files = {
                        "/main.lua",
                        "/modules/legacy_orphan.lua",
                        "/config/vas_config.json",
                    },
                    source = "github",
                    installedAt = 1000,
                },
            },
        }))

        local newMain = "print('v2')"
        local newDefaultCfg = '{"aircraftIndexN": 1, "custom": false}'
        local brandNewCfg = '{"enabled": true}'
        local pkgAll = newMain .. newDefaultCfg .. brandNewCfg

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 1, "MSG_OTA_BEGIN", {
            txId = "tx-cfg-1",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            overwriteConfig = false,
            files = {
                { path = "/main.lua", size = #newMain, crc32 = ota_agent.crc32(newMain), chunkCount = 1 },
                { path = "/config/vas_config.json", size = #newDefaultCfg, crc32 = ota_agent.crc32(newDefaultCfg), chunkCount = 1 },
                { path = "/config/new_cfg.json", size = #brandNewCfg, crc32 = ota_agent.crc32(brandNewCfg), chunkCount = 1 },
            },
            totalBytes = #pkgAll,
            totalCrc32 = ota_agent.crc32(pkgAll),
        })))

        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 2, "MSG_OTA_CHUNK", {
            txId = "tx-cfg-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(newMain), data = newMain,
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 3, "MSG_OTA_CHUNK", {
            txId = "tx-cfg-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 2, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(newDefaultCfg), data = newDefaultCfg,
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 4, "MSG_OTA_CHUNK", {
            txId = "tx-cfg-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 3, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(brandNewCfg), data = brandNewCfg,
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 5, "MSG_OTA_COMMIT", {
            txId = "tx-cfg-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", autoReboot = false,
        })))

        -- Existing config preserved, new missing config installed, shared /lib preserved, orphan deleted
        assert_eq(read_text(ctx.rootDir .. "/config/vas_config.json"), customCfg)
        assert_eq(read_text(ctx.rootDir .. "/config/new_cfg.json"), brandNewCfg)
        assert_eq(read_text(ctx.rootDir .. "/lib/avionics_sensors.lua"), "return 'shared_lib'")
        assert_false(fs.exists(ctx.rootDir .. "/modules/legacy_orphan.lua"))

        -- Verify orphan recorded in restoredFiles with backup
        local pending = textutils.unserializeJSON(read_text(ctx.rootDir .. "/.ota_pending.json"))
        local orphanEntry = nil
        for _, rf in ipairs(pending.restoredFiles) do
            if rf.dest == ctx.rootDir .. "/modules/legacy_orphan.lua" then
                orphanEntry = rf
            end
        end
        assert_not_nil(orphanEntry, "orphan file must be recorded in restoredFiles")
        assert_true(orphanEntry.existed)
        assert_eq(read_text(orphanEntry.src), "return 'legacy'")

        -- 19 ticks do not commit yet
        for _ = 1, 19 do
            local committed, statusRec = ctx.agent:tick_boot_commit()
            assert_false(committed)
            assert_nil(statusRec)
        end
        assert_true(fs.exists(ctx.rootDir .. "/.ota_pending.json"))
        assert_true(fs.exists(pending.backupDir))

        -- 20th tick commits and emits MSG_OTA_BOOT_STATUS COMMITTED
        local committed20, statusRec20 = ctx.agent:tick_boot_commit()
        assert_true(committed20)
        assert_not_nil(statusRec20)
        assert_eq(statusRec20.status, "COMMITTED")
        assert_false(fs.exists(ctx.rootDir .. "/.ota_pending.json"))
        assert_false(fs.exists(pending.backupDir))

        local bootMsg = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(bootMsg.ver, "1.9.5")
        assert_eq(bootMsg.type, "MSG_OTA_BOOT_STATUS")
        assert_eq(bootMsg.payload.txId, "tx-cfg-1")
        assert_eq(bootMsg.payload.moduleId, "vas")
        assert_eq(bootMsg.payload.status, "COMMITTED")
        assert_eq(bootMsg.payload.version, "1.22.0")

        ctx.cleanup()
    end)

    it("reports and clears /.ota_rollback.json via MSG_OTA_BOOT_STATUS ROLLED_BACK", function()
        local ctx = make_test_node("rollback_report")
        ctx.agent:open_channels()

        write_text(ctx.rootDir .. "/.ota_rollback.json", textutils.serializeJSON({
            txId = "tx-rb-9",
            moduleId = "vas",
            targetVersion = "1.22.0",
            reason = "BOOT_LOAD_ERROR",
            error = "syntax error",
            timestamp = 1763210000000,
        }))

        local reported, rec = ctx.agent:tick_boot_commit()
        assert_true(reported)
        assert_not_nil(rec)
        assert_false(fs.exists(ctx.rootDir .. "/.ota_rollback.json"))

        local rbMsg = ctx.modem._transmitted[#ctx.modem._transmitted].pkt
        assert_eq(rbMsg.ver, "1.9.5")
        assert_eq(rbMsg.type, "MSG_OTA_BOOT_STATUS")
        assert_eq(rbMsg.payload.txId, "tx-rb-9")
        assert_eq(rbMsg.payload.moduleId, "vas")
        assert_eq(rbMsg.payload.status, "ROLLED_BACK")
        assert_eq(rbMsg.payload.version, "1.22.0")
        assert_eq(rbMsg.payload.rollbackReason, "BOOT_LOAD_ERROR")

        ctx.cleanup()
    end)

    it("handles overwriteConfig=true, safe REBOOT, TX_NOT_FOUND, DISK_ERROR, and untracked DISCOVER_ACK", function()
        -- Custom fs proxy with low free space check
        local lowSpace = false
        local fsProxy = setmetatable({
            getFreeSpace = function(path)
                if lowSpace then
                    return 5
                end
                return fs.getFreeSpace(path)
            end,
        }, { __index = fs })

        local ctx = make_test_node("edge_cases", { fsApi = fsProxy })
        ctx.agent:open_channels()

        -- Untracked DISCOVER_REQ
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 1, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*", targetDomainId = "*",
        })))
        local discAck = ctx.modem._transmitted[1].pkt
        assert_eq(discAck.type, "MSG_OTA_DISCOVER_ACK")
        assert_eq(discAck.payload.moduleId, "vas")
        assert_eq(discAck.payload.versions.vas, "0.0.0-untracked")
        assert_eq(discAck.payload.filesCount, 0)
        assert_eq(discAck.payload.agentVer, ota_agent.AGENT_VERSION)

        -- DISK_ERROR when freeSpace < totalBytes
        lowSpace = true
        local cfgNew = '{"k": 99}'
        local okDisk = ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 2, "MSG_OTA_BEGIN", {
            txId = "tx-disk-err",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            files = { { path = "/config/vas_config.json", size = #cfgNew, crc32 = ota_agent.crc32(cfgNew), chunkCount = 1 } },
            totalBytes = #cfgNew,
            totalCrc32 = ota_agent.crc32(cfgNew),
        }))
        assert_false(okDisk)
        assert_eq(ctx.modem._transmitted[2].pkt.payload.reason, "DISK_ERROR")
        lowSpace = false

        -- TX_NOT_FOUND for unknown txId
        local okTx = ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 3, "MSG_OTA_COMMIT", {
            txId = "tx-missing", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", autoReboot = false,
        }))
        assert_false(okTx)
        assert_eq(ctx.modem._transmitted[3].pkt.payload.reason, "TX_NOT_FOUND")

        -- overwriteConfig = true overwrites existing config
        write_text(ctx.rootDir .. "/config/vas_config.json", '{"k": 1}')
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 4, "MSG_OTA_BEGIN", {
            txId = "tx-ow-1",
            targetDomainId = "AIRCRAFT_01",
            targetModuleId = "vas",
            targetVersion = "1.22.0",
            overwriteConfig = true,
            files = { { path = "/config/vas_config.json", size = #cfgNew, crc32 = ota_agent.crc32(cfgNew), chunkCount = 1 } },
            totalBytes = #cfgNew,
            totalCrc32 = ota_agent.crc32(cfgNew),
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 5, "MSG_OTA_CHUNK", {
            txId = "tx-ow-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
            fileIndex = 1, chunkIndex = 1, chunkCrc32 = ota_agent.crc32(cfgNew), data = cfgNew,
        })))
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 6, "MSG_OTA_COMMIT", {
            txId = "tx-ow-1", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas", autoReboot = false,
        })))
        assert_eq(read_text(ctx.rootDir .. "/config/vas_config.json"), cfgNew)

        -- Safe MSG_OTA_REBOOT invokes onRebootFn
        assert_true(ctx.agent:handle_packet(105, 106, make_env_envelope("HANGAR", 7, "MSG_OTA_REBOOT", {
            txId = "tx-rb-cmd", targetDomainId = "AIRCRAFT_01", targetModuleId = "vas",
        })))
        assert_eq(ctx.getReboots(), 1)

        ctx.cleanup()
    end)
end)
