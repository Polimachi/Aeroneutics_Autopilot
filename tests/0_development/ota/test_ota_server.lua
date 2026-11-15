-- tests/0_development/ota/test_ota_server.lua
-- Unit test suite for Hangar Wireless OTA Deployment Server, Protocol, and TUI

local ota_agent = require("ota_agent")
local ota_protocol = require("ota_protocol")
local ota_server = require("ota_server")
local ota_ui = require("ota_ui")

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

local function make_temp_dir(tag)
    local dir = sdk.temp_path("ota_srv_" .. tag)
    if fs.exists(dir) then
        fs.delete(dir)
    end
    fs.makeDir(dir)
    return dir
end

local function make_virtual_bus(opts)
    opts = opts or {}
    local bus = {
        nodes = {},
        events = {},
        serverTxLog = {},
        txHook = opts.txHook,
        clockMs = 1763210000000,
    }

    local serverModem = mock.modem({ wireless = true })
    local origServerTransmit = serverModem.transmit
    serverModem.transmit = function(txCh, replyCh, pkt)
        origServerTransmit(txCh, replyCh, pkt)
        bus.serverTxLog[#bus.serverTxLog + 1] = { tx = txCh, rx = replyCh, pkt = pkt }

        local forwardPkt = pkt
        if type(bus.txHook) == "function" then
            local allow, modified = bus.txHook(txCh, replyCh, pkt)
            if allow == false then
                return
            end
            if modified ~= nil then
                forwardPkt = modified
            end
        end

        for _, node in ipairs(bus.nodes) do
            if node.modem.isOpen(txCh) then
                node.agent:handle_packet(txCh, replyCh, forwardPkt)
            end
        end
    end

    function bus.add_node(tag, nodeOpts)
        nodeOpts = nodeOpts or {}
        local rootDir = make_temp_dir("node_" .. tag)
        local nodeModem = mock.modem({ wireless = true })
        local origNodeTransmit = nodeModem.transmit
        nodeModem.transmit = function(txCh, replyCh, pkt)
            origNodeTransmit(txCh, replyCh, pkt)
            if serverModem.isOpen(txCh) then
                bus.events[#bus.events + 1] = { "modem_message", "top", txCh, replyCh, pkt, 0 }
            end
        end

        local statusState = nodeOpts.status or { controlState = "DISARMED", isAirborne = false }
        local reboots = 0
        local seq = 0
        local agent = ota_agent.new({
            moduleId = nodeOpts.moduleId or "vas",
            domainId = nodeOpts.domainId or "UAV-01",
            bayId = nodeOpts.bayId or 1,
            bayIds = nodeOpts.bayIds,
            bootConfirmTicks = nodeOpts.bootConfirmTicks or 5,
            fsApi = fs,
            modemApi = nodeModem,
            rootDir = rootDir,
            getStatusFn = function()
                return statusState
            end,
            onRebootFn = function()
                reboots = reboots + 1
            end,
            seqFn = function()
                seq = seq + 1
                return seq
            end,
            clockFn = function()
                bus.clockMs = bus.clockMs + 1
                return bus.clockMs
            end,
        })
        agent:open_channels()

        local rec = {
            rootDir = rootDir,
            modem = nodeModem,
            agent = agent,
            setStatus = function(ctrl, airborne)
                statusState.controlState = ctrl
                statusState.isAirborne = airborne
            end,
            getReboots = function()
                return reboots
            end,
            cleanup = function()
                if fs.exists(rootDir) then
                    fs.delete(rootDir)
                end
            end,
        }
        bus.nodes[#bus.nodes + 1] = rec
        return rec
    end

    function bus.poll_event(_timeoutSec)
        if #bus.events > 0 then
            local ev = table.remove(bus.events, 1)
            return ev[1], ev[2], ev[3], ev[4], ev[5], ev[6]
        end
        return nil
    end

    bus.serverModem = serverModem
    return bus
end

local function make_server(bus, serverRoot, extraOpts)
    extraOpts = extraOpts or {}
    return ota_server.new({
        config = extraOpts.config or {
            version = "0.1.0",
            ota = {
                bayId = extraOpts.bayId or 1,
                chunkSize = extraOpts.chunkSize or 2048,
                ackTimeoutSec = 0.2,
                maxRetries = extraOpts.maxRetries or 3,
                defaultSourceDir = "/ota_packages",
                autoSyncOnBoot = false,
                manifestUrl = "https://mock.local/manifest.lua",
                githubRawBase = "https://mock.local/raw/",
            },
            network = {
                domainId = "HANGAR-OTA-01",
            },
        },
        modem = bus and bus.serverModem or extraOpts.modem,
        fsApi = fs,
        httpApi = extraOpts.httpApi,
        rootDir = serverRoot,
        clockFn = function()
            if bus then
                bus.clockMs = bus.clockMs + 10
                return bus.clockMs
            end
            return 1763210000000
        end,
        sleepFn = function() end,
        pollEventFn = bus and bus.poll_event or nil,
    })
end

describe("ota_protocol strict 1.9.5 envelope and chunking", function()
    it("builds and strictly parses ICD 1.9.5 envelopes without legacy key fallback", function()
        local env = ota_protocol.build_envelope("HANGAR-OTA-01", 7, "MSG_OTA_DISCOVER_REQ", {
            targetModuleId = "*",
            targetDomainId = "*",
        }, 1763210000123)

        assert_eq(ota_protocol.ICD_VERSION, "1.9.5")
        assert_eq(env.ver, "1.9.5")
        assert_eq(env.domainId, "HANGAR-OTA-01")
        assert_eq(env.seq, 7)
        assert_eq(env.type, "MSG_OTA_DISCOVER_REQ")
        assert_eq(env.time, 1763210000123)

        local parsed, err = ota_protocol.parse_envelope(env)
        assert_not_nil(parsed, err)
        assert_eq(parsed.seq, 7)

        -- Reject legacy 'version' key when 'ver' is absent
        local badLegacy, badErr = ota_protocol.parse_envelope({
            version = "1.9.5",
            domainId = "HANGAR-OTA-01",
            seq = 1,
            type = "MSG_OTA_ACK",
            time = 1000,
            payload = {},
        })
        assert_nil(badLegacy)
        assert_not_nil(badErr)

        -- Reject mismatched version
        local badVer, badVerErr = ota_protocol.parse_envelope({
            ver = "1.9.4",
            domainId = "HANGAR-OTA-01",
            seq = 1,
            type = "MSG_OTA_ACK",
            time = 1000,
            payload = {},
        })
        assert_nil(badVer)
        assert_not_nil(badVerErr)
    end)

    it("chunks multi-chunk and zero-byte files using ota_agent.crc32", function()
        local bigData = string.rep("A", 2048) .. "TAIL"
        local fm, chunks = ota_protocol.chunk_file("/modules/big.lua", bigData)
        assert_eq(fm.path, "/modules/big.lua")
        assert_eq(fm.size, 2052)
        assert_eq(fm.chunkCount, 2)
        assert_eq(#chunks, 2)
        assert_eq(#chunks[1].data, 2048)
        assert_eq(#chunks[2].data, 4)
        assert_eq(chunks[2].chunkCrc32, ota_agent.crc32("TAIL"))

        local threeData = string.rep("X", 64) .. string.rep("Y", 64) .. "END"
        local fm3, chunks3 = ota_protocol.chunk_file("/modules/three.lua", threeData, 64)
        assert_eq(fm3.size, 131)
        assert_eq(fm3.crc32, ota_agent.crc32(threeData))
        assert_eq(fm3.chunkCount, 3)
        assert_eq(#chunks3, 3)
        assert_eq(chunks3[3].chunkCrc32, ota_agent.crc32("END"))

        local emptyFm, emptyChunks = ota_protocol.chunk_file("/empty.lua", "", 2048)
        assert_eq(emptyFm.size, 0)
        assert_eq(emptyFm.chunkCount, 0)
        assert_eq(#emptyChunks, 0)
    end)
end)

describe("ota_server remote sync staging & package loading", function()
    it("downloads manifest & module files via sandboxed env, writes ota_package.json, and loads package", function()
        local srvRoot = make_temp_dir("sync")
        local mainLuaSrc = "print('tca v1.9.1')\n"
        local daemonLuaSrc = "return { tick = function() return true end }\n"
        local manifestSrc = [[
local manifest = {}
manifest.MODULE_ORDER = { "tca" }
manifest.MODULES = {
    tca = {
        id = "tca",
        name = "TCA",
        version = "1.9.1",
        files = {
            { repoPath = "src/1_control/tca/main.lua", dest = "/main.lua" },
            { repoPath = "src/1_control/tca/modules/tca_daemon.lua", dest = "/modules/tca_daemon.lua" },
        },
    },
}
return manifest
]]
        local responses = {
            ["https://mock.local/manifest.lua"] = manifestSrc,
            ["https://mock.local/raw/src/1_control/tca/main.lua"] = mainLuaSrc,
            ["https://mock.local/raw/src/1_control/tca/modules/tca_daemon.lua"] = daemonLuaSrc,
        }
        local mockHttp = {
            get = function(url)
                local body = responses[url]
                if not body then
                    return nil, "NOT_FOUND"
                end
                return {
                    getResponseCode = function() return 200 end,
                    readAll = function() return body end,
                    close = function() end,
                }
            end,
        }

        local srv = make_server(nil, srvRoot, { httpApi = mockHttp })
        local ok, info = srv:sync_remote({ moduleIds = { "tca" } })
        assert_true(ok, "sync_remote should succeed: " .. tostring(info and info.error))
        assert_true(fs.exists(srvRoot .. "/ota_packages/tca/ota_package.json"))

        local pkg, loadErr = srv:load_package("/ota_packages/tca")
        assert_not_nil(pkg, loadErr)
        assert_eq(pkg.moduleId, "tca")
        assert_eq(pkg.version, "1.9.1")
        assert_eq(#pkg.files, 2)
        assert_eq(pkg.totalBytes, #mainLuaSrc + #daemonLuaSrc)
        assert_eq(pkg.totalCrc32, ota_agent.crc32(mainLuaSrc .. daemonLuaSrc))
        assert_eq(pkg.files[1].content, mainLuaSrc)
        assert_eq(pkg.files[2].content, daemonLuaSrc)

        fs.delete(srvRoot)
    end)

    it("sandboxes remote manifest loading against global access", function()
        local srvRoot = make_temp_dir("sync_sandbox")
        local maliciousManifest = [[
_G.__PWNED_BY_MANIFEST = true
return { MODULES = {} }
]]
        local mockHttp = {
            get = function(_url)
                return {
                    getResponseCode = function() return 200 end,
                    readAll = function() return maliciousManifest end,
                    close = function() end,
                }
            end,
        }
        local srv = make_server(nil, srvRoot, { httpApi = mockHttp })
        local ok, _ = srv:sync_remote({ moduleIds = { "tca" } })
        assert_false(ok)
        assert_nil(_G.__PWNED_BY_MANIFEST)
        fs.delete(srvRoot)
    end)
end)

describe("ota_server multi-node discovery and bay routing", function()
    it("discovers multiple onboard nodes on Bay 1 with version and safety state", function()
        local bus = make_virtual_bus()
        local srvRoot = make_temp_dir("discover")

        local vasNode = bus.add_node("vas", {
            moduleId = "vas",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "DISARMED", isAirborne = false },
        })
        write_text(vasNode.rootDir .. "/.version.json", textutils.serializeJSON({
            modules = { vas = { id = "vas", version = "1.22.0", files = { "/main.lua" } } },
        }))

        local tcaNode = bus.add_node("tca", {
            moduleId = "tca",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "ARMING", isAirborne = false },
        })
        write_text(tcaNode.rootDir .. "/.version.json", textutils.serializeJSON({
            modules = { tca = { id = "tca", version = "1.9.0", files = { "/main.lua", "/modules/a.lua" } } },
        }))

        local srv = make_server(bus, srvRoot, { bayId = 1 })
        local nodes = srv:discover({ bayId = 1, windowSec = 0.05 })
        assert_eq(#nodes, 2)

        local byMod = {}
        for _, n in ipairs(nodes) do
            byMod[n.moduleId] = n
        end

        assert_not_nil(byMod.vas)
        assert_eq(byMod.vas.domainId, "UAV-01")
        assert_eq(byMod.vas.version, "1.22.0")
        assert_eq(byMod.vas.controlState, "DISARMED")
        assert_true(byMod.vas.safeForOta)

        assert_not_nil(byMod.tca)
        assert_eq(byMod.tca.domainId, "UAV-01")
        assert_eq(byMod.tca.version, "1.9.0")
        assert_eq(byMod.tca.controlState, "ARMING")
        assert_false(byMod.tca.safeForOta)

        vasNode.cleanup()
        tcaNode.cleanup()
        fs.delete(srvRoot)
    end)
end)

describe("ota_server chunked deploy, retry, safety abort, and corruption abort", function()
    it("retries transient chunk 2 drop, completes transfer, preserves/overrides config, and receives APPLIED ACK", function()
        local droppedChunk2Once = false
        local bus = make_virtual_bus({
            txHook = function(_txCh, _replyCh, pkt)
                if pkt.type == "MSG_OTA_CHUNK" and pkt.payload.chunkIndex == 2 and not droppedChunk2Once then
                    droppedChunk2Once = true
                    return false
                end
                return true
            end,
        })
        local srvRoot = make_temp_dir("retry_deploy")
        local node = bus.add_node("tca_retry", {
            moduleId = "tca",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "DISARMED", isAirborne = false },
        })
        write_text(node.rootDir .. "/main.lua", "print('old')")
        write_text(node.rootDir .. "/config/tca.json", '{"keepMe":true}')

        local srv = make_server(bus, srvRoot, { bayId = 1, chunkSize = 16, maxRetries = 3 })
        local newMain = "local a = 1234567890\nlocal b = 'hello_world_ota'\n"
        local newCfg = '{"keepMe":false}'
        local pkg = {
            moduleId = "tca",
            version = "1.9.2",
            files = {
                { path = "/main.lua", content = newMain },
                { path = "/config/tca.json", content = newCfg },
            },
        }

        local progressEvents = 0
        local ok, res = srv:deploy(
            { domainId = "UAV-01", moduleId = "tca", bayId = 1 },
            pkg,
            {
                chunkSize = 16,
                overwriteConfig = false,
                onProgress = function()
                    progressEvents = progressEvents + 1
                end,
            }
        )
        assert_true(ok, "deploy should succeed after transient retry: " .. tostring(res and res.reason))
        assert_true(droppedChunk2Once)
        assert_eq(res.phase, "APPLIED")
        assert_true(progressEvents >= 3)
        assert_eq(read_text(node.rootDir .. "/main.lua"), newMain)
        -- Existing config preserved when overwriteConfig = false
        assert_eq(read_text(node.rootDir .. "/config/tca.json"), '{"keepMe":true}')
        assert_true(fs.exists(node.rootDir .. "/.ota_pending.json"))

        node.cleanup()
        fs.delete(srvRoot)
    end)

    it("aborts immediately with MSG_OTA_ABORT on NOT_DISARMED NACK and leaves target disk untouched", function()
        local bus = make_virtual_bus()
        local srvRoot = make_temp_dir("armed_abort")
        local node = bus.add_node("vas_armed", {
            moduleId = "vas",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "NORMAL", isAirborne = true },
        })
        write_text(node.rootDir .. "/main.lua", "print('live_intact')")

        local srv = make_server(bus, srvRoot, { bayId = 1 })
        local pkg = {
            moduleId = "vas",
            version = "1.23.0",
            files = { { path = "/main.lua", content = "print('should_not_write')" } },
        }

        local ok, res = srv:deploy({ domainId = "UAV-01", moduleId = "vas", bayId = 1 }, pkg)
        assert_false(ok)
        assert_eq(res.reason, "NOT_DISARMED")
        assert_eq(read_text(node.rootDir .. "/main.lua"), "print('live_intact')")
        assert_false(fs.exists(node.rootDir .. "/ota_staging"))
        assert_false(fs.exists(node.rootDir .. "/.ota_pending.json"))

        local sawAbort = false
        for _, entry in ipairs(bus.serverTxLog) do
            if entry.pkt and entry.pkt.type == "MSG_OTA_ABORT" and entry.pkt.payload.reason == "NOT_DISARMED" then
                sawAbort = true
            end
        end
        assert_true(sawAbort, "expected server to emit MSG_OTA_ABORT on NOT_DISARMED")

        node.cleanup()
        fs.delete(srvRoot)
    end)

    it("aborts cleanly after retry exhaustion on persistent chunk corruption without modifying live files", function()
        local corruptCount = 0
        local bus = make_virtual_bus({
            txHook = function(_txCh, _replyCh, pkt)
                if pkt.type == "MSG_OTA_CHUNK" then
                    corruptCount = corruptCount + 1
                    local badPkt = {
                        ver = pkt.ver,
                        domainId = pkt.domainId,
                        seq = pkt.seq,
                        type = pkt.type,
                        time = pkt.time,
                        payload = {
                            txId = pkt.payload.txId,
                            targetDomainId = pkt.payload.targetDomainId,
                            targetModuleId = pkt.payload.targetModuleId,
                            fileIndex = pkt.payload.fileIndex,
                            chunkIndex = pkt.payload.chunkIndex,
                            chunkCrc32 = pkt.payload.chunkCrc32,
                            data = "CORRUPTED_BYTES!",
                        },
                    }
                    return true, badPkt
                end
                return true
            end,
        })
        local srvRoot = make_temp_dir("corrupt_abort")
        local node = bus.add_node("fcp_corrupt", {
            moduleId = "fcp",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "DISARMED", isAirborne = false },
        })
        write_text(node.rootDir .. "/main.lua", "print('fcp_original')")

        local srv = make_server(bus, srvRoot, { bayId = 1, maxRetries = 2 })
        local pkg = {
            moduleId = "fcp",
            version = "2.1.0",
            files = { { path = "/main.lua", content = "print('fcp_updated')" } },
        }

        local ok, res = srv:deploy({ domainId = "UAV-01", moduleId = "fcp", bayId = 1 }, pkg, { maxRetries = 2 })
        assert_false(ok)
        assert_eq(res.reason, "CRC_MISMATCH")
        assert_eq(corruptCount, 3) -- initial attempt + 2 retries
        assert_eq(read_text(node.rootDir .. "/main.lua"), "print('fcp_original')")
        assert_false(fs.exists(node.rootDir .. "/ota_staging/" .. tostring(res.txId)))
        assert_false(fs.exists(node.rootDir .. "/.ota_pending.json"))

        local sawAbort = false
        for _, entry in ipairs(bus.serverTxLog) do
            if entry.pkt and entry.pkt.type == "MSG_OTA_ABORT" then
                sawAbort = true
            end
        end
        assert_true(sawAbort, "expected MSG_OTA_ABORT after retry exhaustion")

        node.cleanup()
        fs.delete(srvRoot)
    end)

    it("awaits MSG_OTA_BOOT_STATUS COMMITTED when awaitBootStatus is enabled", function()
        local bus = make_virtual_bus()
        local srvRoot = make_temp_dir("boot_status")
        local node = bus.add_node("amm_boot", {
            moduleId = "amm",
            domainId = "UAV-01",
            bayId = 1,
            status = { controlState = "DISARMED", isAirborne = false },
        })
        write_text(node.rootDir .. "/main.lua", "print('amm_v1')")

        -- Pre-queue COMMITTED status on reboot callback
        node.agent.onRebootFn = function()
            node.agent:confirm_boot_commit()
        end

        local srv = make_server(bus, srvRoot, { bayId = 1 })
        local pkg = {
            moduleId = "amm",
            version = "2.1.0",
            files = { { path = "/main.lua", content = "print('amm_v2')" } },
        }
        local ok, res = srv:deploy(
            { domainId = "UAV-01", moduleId = "amm", bayId = 1 },
            pkg,
            { autoReboot = true, awaitBootStatus = true }
        )
        assert_true(ok, "deploy + boot status should commit: " .. tostring(res and res.reason))
        assert_eq(res.status, "COMMITTED")
        assert_eq(res.version, "2.1.0")
        assert_false(fs.exists(node.rootDir .. "/.ota_pending.json"))

        node.cleanup()
        fs.delete(srvRoot)
    end)
end)

describe("ota_ui 51x19 TUI rendering", function()
    it("renders 51x19 dashboard with nodes, safety badges, progress bar, and hotkeys without errors", function()
        local scr = mock.term(51, 19)
        local ok = ota_ui.render(scr, {
            bayId = 2,
            cmdCh = 115,
            ackCh = 116,
            domainId = "HANGAR-OTA-01",
            modemPresent = true,
            nodes = {
                {
                    domainId = "UAV-01",
                    moduleId = "vas",
                    version = "1.22.0",
                    controlState = "DISARMED",
                    isAirborne = false,
                    safeForOta = true,
                },
                {
                    domainId = "UAV-01",
                    moduleId = "tca",
                    version = "1.9.1",
                    controlState = "NORMAL",
                    isAirborne = true,
                    safeForOta = false,
                },
            },
            selectedIdx = 1,
            progress = { active = true, sentChunks = 3, totalChunks = 6, stage = "CHUNK" },
            statusMsg = "DISCOVERED 2 NODES",
            overwriteConfig = false,
            autoReboot = true,
        })
        assert_true(ok)
        assert_true(scr._contains("BAY:02"))
        assert_true(scr._contains("UAV-01"))
        assert_true(scr._contains("vas"))
        assert_true(scr._contains("50%"))
        assert_true(scr._contains("[D]iscover"))
    end)
end)

describe("ota main CLI and headless shutdown", function()
    it("supports discover --bay=2 CLI and cleanly exits headless loop on shutdown", function()
        local mainMod = require("main")
        local bus = make_virtual_bus()
        local srvRoot = make_temp_dir("main_cli")
        local bay2Node = bus.add_node("bay2_vas", {
            moduleId = "vas",
            domainId = "UAV-02",
            bayId = 2,
            status = { controlState = "DISARMED", isAirborne = false },
        })

        local okDisc, nodes = mainMod.run({ "discover", "--bay=2" }, {
            modem = bus.serverModem,
            fs = fs,
            rootDir = srvRoot,
            pollEventFn = bus.poll_event,
        })
        assert_true(okDisc)
        assert_eq(#nodes, 1)
        assert_eq(nodes[1].domainId, "UAV-02")
        assert_false(bus.serverModem.isOpen(116))

        -- Headless mode exits cleanly on "shutdown" event
        local evIdx = 0
        local okHeadless, state = mainMod.run({ "--headless" }, {
            modem = bus.serverModem,
            fs = fs,
            rootDir = srvRoot,
            pollEventFn = function()
                evIdx = evIdx + 1
                if evIdx == 1 then
                    return "shutdown"
                end
                return "terminate"
            end,
        })
        assert_true(okHeadless)
        assert_false(state.running)
        assert_false(bus.serverModem.isOpen(106))

        bay2Node.cleanup()
        fs.delete(srvRoot)
    end)
end)
