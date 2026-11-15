-- tests/e2e/test_e2e_ota_deploy_rollback.lua
-- End-to-End Integration: Multi-Node Hangar Wireless OTA Deploy, Safety Gate, CRC32 Abort & 2-Stage Boot Watchdog Rollback (ICD 1.9.5 I-13)
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

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

local function read_json(path)
    local raw = read_text(path)
    local parsed = textutils.unserializeJSON(raw)
    assert_not_nil(parsed, "failed to parse JSON: " .. tostring(path))
    return parsed
end

local function write_json(path, tbl)
    write_text(path, textutils.serializeJSON(tbl))
end

local function clone_table(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = clone_table(v)
    end
    return out
end

local function create_ota_cluster(tag, opts)
    opts = opts or {}
    local bus = virtual_bus.create_bus({ clock = 1763210000.0 })
    local roots = {
        srv = sdk.temp_path("e2e_ota_" .. tag .. "_srv"),
        vas = sdk.temp_path("e2e_ota_" .. tag .. "_vas"),
        tca = sdk.temp_path("e2e_ota_" .. tag .. "_tca"),
        fcp = sdk.temp_path("e2e_ota_" .. tag .. "_fcp"),
        amm = sdk.temp_path("e2e_ota_" .. tag .. "_amm"),
    }
    for _, dir in pairs(roots) do
        if fs.exists(dir) then
            fs.delete(dir)
        end
        fs.makeDir(dir)
    end

    local srvNode = node_sandbox.create_node(bus, "OTA_SRV", "src/0_development/ota")
    if type(opts.txHook) == "function" then
        local origTx = srvNode.modem.transmit
        srvNode.modem.transmit = function(a1, a2, a3, ...)
            local ch, replyCh, pkt
            if a1 == srvNode.modem then
                ch, replyCh, pkt = a2, a3, ...
            else
                ch, replyCh, pkt = a1, a2, a3
            end
            local allow, modified = opts.txHook(ch, replyCh, pkt)
            if allow == false then
                return
            end
            origTx(ch, replyCh, modified or pkt)
        end
    end

    local vasNode = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
    local tcaNode = node_sandbox.create_node(bus, "TCA", "src/1_control/tca")
    local fcpNode = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
    local ammNode = node_sandbox.create_node(bus, "AMM", "src/3_planning/amm")
    local instNode = node_sandbox.create_node(bus, "INSTALLER", "src/0_development/installer")

    local ota_agent = srvNode:require("ota_agent")
    local ota_protocol = srvNode:require("ota_protocol")
    local ota_server = srvNode:require("ota_server")
    local startup_generator = instNode:require("startup_generator")

    local vasDaemon = vasNode:require("core_daemon")
    local tcaDaemon = tcaNode:require("tca_daemon")
    local fcpMain = fcpNode:require("main")
    local fcpNetMgr = fcpNode:require("network_manager")
    local ammMain = ammNode:require("main")

    local reboots = { vas = 0, tca = 0, fcp = 0, amm = 0 }

    local vasState = vasDaemon.init({
        system = {
            aircraftDomainId = "AIRCRAFT_01",
            baseChannel = 10000,
            debug = false,
        },
        ota = {
            bayId = 1,
            rootDir = roots.vas,
            fsApi = fs,
            bootConfirmTicks = 20,
            onRebootFn = function()
                reboots.vas = reboots.vas + 1
            end,
        },
    })

    local function build_tca_cfg()
        return {
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
                rootDir = roots.tca,
                fsApi = fs,
                bootConfirmTicks = 20,
                onRebootFn = function()
                    reboots.tca = reboots.tca + 1
                end,
            },
        }
    end
    local tcaInst = tcaDaemon.init(build_tca_cfg(), tcaNode.modem)

    local fcpCfg = fcpMain.load_config("config/fcp_config.json")
    fcpCfg.system.domainId = "AIRCRAFT_01"
    fcpCfg.ota = {
        bayId = 1,
        rootDir = roots.fcp,
        fsApi = fs,
        bootConfirmTicks = 20,
        onRebootFn = function()
            reboots.fcp = reboots.fcp + 1
        end,
    }
    local fcpCtx = fcpMain.create_context(fcpCfg, function()
        return fcpNode.modem
    end)

    local ammCfg = ammMain.load_config("config/amm_config.json")
    ammCfg.headless = true
    ammCfg.domainId = "AIRCRAFT_01"
    ammCfg.ota = {
        bayId = 1,
        rootDir = roots.amm,
        fsApi = fs,
        bootConfirmTicks = 20,
        onRebootFn = function()
            reboots.amm = reboots.amm + 1
        end,
    }
    local ammApp = ammMain.create_app(ammCfg, ammNode.modem)

    local cluster = {
        bus = bus,
        roots = roots,
        reboots = reboots,
        ota_agent = ota_agent,
        ota_protocol = ota_protocol,
        startup_generator = startup_generator,
        srvNode = srvNode,
        vasNode = vasNode,
        tcaNode = tcaNode,
        fcpNode = fcpNode,
        ammNode = ammNode,
        vasDaemon = vasDaemon,
        vasState = vasState,
        tcaDaemon = tcaDaemon,
        tcaInst = tcaInst,
        build_tca_cfg = build_tca_cfg,
        fcpCtx = fcpCtx,
        ammApp = ammApp,
    }

    function cluster.pump_onboard()
        for _, msg in ipairs(vasNode.modem:drain()) do
            vasDaemon.handle_event(cluster.vasState, "modem_message", msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance)
        end
        for _, msg in ipairs(tcaNode.modem:drain()) do
            cluster.tcaInst:step_event("modem_message", msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance)
        end
        for _, msg in ipairs(fcpNode.modem:drain()) do
            fcpNetMgr.ingest_modem_event(cluster.fcpCtx.net, msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance, math.floor(bus.time * 1000))
        end
        for _, msg in ipairs(ammNode.modem:drain()) do
            ammMain.process_event(cluster.ammApp, "modem_message", msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance)
        end
    end

    function cluster.poll_server_event(remainingSec)
        if #srvNode.modem.inbox > 0 then
            local msg = table.remove(srvNode.modem.inbox, 1)
            return "modem_message", msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance
        end
        if (tonumber(remainingSec) or 0) <= 0 then
            return "timer", "timeout"
        end
        bus:step(0.05)
        cluster.pump_onboard()
        bus:deliver()
        if #srvNode.modem.inbox > 0 then
            local msg = table.remove(srvNode.modem.inbox, 1)
            return "modem_message", msg.side, msg.channel, msg.replyChannel, msg.payload, msg.distance
        end
        return "timer", "tick"
    end

    cluster.server = ota_server.new({
        config = {
            version = "0.1.0",
            ota = {
                bayId = 1,
                chunkSize = opts.chunkSize or 48,
                ackTimeoutSec = opts.ackTimeoutSec or 0.25,
                maxRetries = (opts.maxRetries ~= nil) and opts.maxRetries or 2,
                defaultSourceDir = "/ota_packages",
                autoSyncOnBoot = false,
            },
            network = {
                domainId = "HANGAR-OTA-01",
            },
        },
        modem = srvNode.modem,
        fsApi = fs,
        httpApi = false,
        rootDir = roots.srv,
        clockFn = function()
            return math.floor(bus.time * 1000)
        end,
        sleepFn = function() end,
        pollEventFn = cluster.poll_server_event,
    })

    function cluster.cleanup()
        cluster.ammApp.running = false
        cluster.vasState.running = false
        cluster.fcpCtx.running = false
        for _, dir in pairs(roots) do
            if fs.exists(dir) then
                fs.delete(dir)
            end
        end
    end

    return cluster
end

local function stage_server_package(cluster, moduleId, version, filesSpec)
    local pkgDir = cluster.roots.srv .. "/ota_packages/" .. moduleId
    if fs.exists(pkgDir) then
        fs.delete(pkgDir)
    end
    fs.makeDir(pkgDir)

    local manifestFiles = {}
    local rawContents = {}
    local totalBytes = 0
    for idx, f in ipairs(filesSpec) do
        local norm = cluster.ota_protocol.normalize_rel_path(f.path)
        local localPath = "files" .. norm
        write_text(pkgDir .. "/" .. localPath, f.content)
        manifestFiles[idx] = {
            path = norm,
            localPath = localPath,
            size = #f.content,
            crc32 = cluster.ota_agent.crc32(f.content),
        }
        rawContents[idx] = f.content
        totalBytes = totalBytes + #f.content
    end

    write_json(pkgDir .. "/ota_package.json", {
        schemaVersion = "1.0.0",
        moduleId = moduleId,
        version = version,
        totalBytes = totalBytes,
        totalCrc32 = cluster.ota_agent.crc32(table.concat(rawContents)),
        files = manifestFiles,
    })
    local pkg, err = cluster.server:load_package("/ota_packages/" .. moduleId)
    assert_not_nil(pkg, "load_package failed: " .. tostring(err))
    return pkg
end

describe("Scenario 10: Hangar Wireless OTA Deploy & Watchdog Rollback E2E", function()
    it("discovers VAS/TCA/FCP/AMM on Bay 1, deploys TCA preserving config and pruning orphans, runs real startup hook, and commits after 20 ticks", function()
        local c = create_ota_cluster("nominal")

        -- Seed live files & version metadata across all 4 onboard nodes
        write_text(c.roots.vas .. "/main.lua", "-- vas live v1.22.0\n")
        write_json(c.roots.vas .. "/.version.json", {
            modules = { vas = { id = "vas", version = "1.22.0", files = { "/main.lua" } } },
        })

        write_text(c.roots.tca .. "/main.lua", "_G.__E2E_TCA_BOOT_VER = '1.9.1'\nreturn true\n")
        write_text(c.roots.tca .. "/modules/tca_daemon.lua", "-- tca daemon v1.9.1\n")
        write_text(c.roots.tca .. "/modules/orphan_old.lua", "-- obsolete helper\n")
        local origTcaCfg = '{"keepUserCustom":true,"baseChannel":10040}'
        write_text(c.roots.tca .. "/config/tca_config.json", origTcaCfg)
        write_json(c.roots.tca .. "/.version.json", {
            modules = {
                tca = {
                    id = "tca",
                    version = "1.9.1",
                    files = { "/main.lua", "/modules/tca_daemon.lua", "/modules/orphan_old.lua", "/config/tca_config.json" },
                },
            },
        })

        write_text(c.roots.fcp .. "/main.lua", "-- fcp live v2.0.0\n")
        write_json(c.roots.fcp .. "/.version.json", {
            modules = { fcp = { id = "fcp", version = "2.0.0", files = { "/main.lua" } } },
        })

        write_text(c.roots.amm .. "/main.lua", "-- amm live v2.1.0\n")
        write_json(c.roots.amm .. "/.version.json", {
            modules = { amm = { id = "amm", version = "2.1.0", files = { "/main.lua" } } },
        })

        -- Install real 2-stage watchdog startup hook for TCA
        local okHook, errHook = c.startup_generator.installHook({
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = c.roots.tca .. "/main.lua",
            installDir = c.roots.tca,
            otaRootPrefix = c.roots.tca,
        }, c.roots.tca, fs)
        assert_true(okHook, "installHook failed: " .. tostring(errHook))

        -- 1. Discover all 4 onboard nodes on Hangar Bay 1 (105/106)
        local nodes = c.server:discover({ bayId = 1, windowSec = 0.25 })
        assert_eq(#nodes, 4)
        local byMod = {}
        for _, n in ipairs(nodes) do
            byMod[n.moduleId] = n
            assert_true(n.safeForOta, "expected safeForOta=true for " .. n.moduleId)
        end
        assert_eq(byMod.vas.version, "1.22.0")
        assert_eq(byMod.tca.version, "1.9.1")
        assert_eq(byMod.fcp.version, "2.0.0")
        assert_eq(byMod.amm.version, "2.1.0")

        -- 2. Stage & deploy updated TCA package (preserve config, prune orphan_old.lua)
        local newTcaMain = "_G.__E2E_TCA_BOOT_VER = '1.9.2'\nreturn true\n"
        local newTcaDaemon = "-- tca daemon v1.9.2 updated\n"
        local pkg = stage_server_package(c, "tca", "1.9.2", {
            { path = "/main.lua", content = newTcaMain },
            { path = "/modules/tca_daemon.lua", content = newTcaDaemon },
            { path = "/config/tca_config.json", content = '{"keepUserCustom":false}' },
        })

        local okDeploy, res = c.server:deploy(
            { domainId = "AIRCRAFT_01", moduleId = "tca", bayId = 1 },
            pkg,
            { overwriteConfig = false, autoReboot = true }
        )
        assert_true(okDeploy, "TCA deploy failed: " .. tostring(res and res.reason))
        assert_eq(res.phase, "APPLIED")
        assert_eq(res.status, "PENDING_COMMIT")
        assert_eq(c.reboots.tca, 1)

        -- Verify TCA staging committed + backup + pending + orphan cleanup + untouched siblings
        assert_eq(read_text(c.roots.tca .. "/main.lua"), newTcaMain)
        assert_eq(read_text(c.roots.tca .. "/modules/tca_daemon.lua"), newTcaDaemon)
        assert_eq(read_text(c.roots.tca .. "/config/tca_config.json"), origTcaCfg)
        assert_false(fs.exists(c.roots.tca .. "/modules/orphan_old.lua"))
        assert_true(fs.exists(c.roots.tca .. "/.ota_pending.json"))
        local backupDir = c.roots.tca .. "/ota_backup/" .. res.txId
        assert_true(fs.exists(backupDir))
        local tcaVerMeta = read_json(c.roots.tca .. "/.version.json")
        assert_eq(tcaVerMeta.modules.tca.version, "1.9.2")

        assert_eq(read_text(c.roots.vas .. "/main.lua"), "-- vas live v1.22.0\n")
        assert_eq(read_text(c.roots.fcp .. "/main.lua"), "-- fcp live v2.0.0\n")
        assert_eq(read_text(c.roots.amm .. "/main.lua"), "-- amm live v2.1.0\n")
        assert_false(fs.exists(c.roots.vas .. "/.ota_pending.json"))
        assert_false(fs.exists(c.roots.fcp .. "/.ota_pending.json"))
        assert_false(fs.exists(c.roots.amm .. "/.ota_pending.json"))

        -- 3. Execute simulated reboot through real startup_generator 2-stage watchdog hook
        _G.__E2E_TCA_BOOT_VER = nil
        dofile(c.roots.tca .. "/startup/00_tca.lua")
        assert_eq(_G.__E2E_TCA_BOOT_VER, "1.9.2")
        _G.__E2E_TCA_BOOT_VER = nil

        local pendingAfterBoot = read_json(c.roots.tca .. "/.ota_pending.json")
        assert_eq(pendingAfterBoot.bootAttempts, 1)

        -- 4. Re-boot TCA daemon and drive 20 healthy stabilization ticks
        c.tcaInst = c.tcaDaemon.init(c.build_tca_cfg(), c.tcaNode.modem)
        for i = 1, 19 do
            c.tcaInst:step_event("timer", i)
            assert_true(fs.exists(c.roots.tca .. "/.ota_pending.json"), "pending must remain before tick 20")
        end
        assert_eq(#c.bus:find_packets({ type = "MSG_OTA_BOOT_STATUS" }), 0)

        c.tcaInst:step_event("timer", 20)
        c.bus:step(0.05)

        assert_false(fs.exists(c.roots.tca .. "/.ota_pending.json"))
        assert_false(fs.exists(backupDir))

        local srvBootMsgs = {}
        for _, msg in ipairs(c.srvNode.modem:drain()) do
            if type(msg.payload) == "table" and msg.payload.type == "MSG_OTA_BOOT_STATUS" then
                srvBootMsgs[#srvBootMsgs + 1] = msg
            end
        end
        assert_eq(#srvBootMsgs, 1)
        assert_eq(srvBootMsgs[1].channel, 106)
        assert_eq(srvBootMsgs[1].payload.payload.txId, res.txId)
        assert_eq(srvBootMsgs[1].payload.payload.moduleId, "tca")
        assert_eq(srvBootMsgs[1].payload.payload.status, "COMMITTED")
        assert_eq(srvBootMsgs[1].payload.payload.version, "1.9.2")

        c.cleanup()
    end)

    it("rejects deploy to VAS with NOT_DISARMED when VAS is armed and airborne", function()
        local c = create_ota_cluster("safety_deny")
        write_text(c.roots.vas .. "/main.lua", "-- vas protected v1.22.0\n")
        write_json(c.roots.vas .. "/.version.json", {
            modules = { vas = { id = "vas", version = "1.22.0", files = { "/main.lua" } } },
        })

        c.vasState.fsm.currentState = "NORMAL"
        c.vasState.fsm.isAirborne = true

        local pkg = stage_server_package(c, "vas", "1.23.0", {
            { path = "/main.lua", content = "-- should never land\n" },
        })

        local ok, res = c.server:deploy({ domainId = "AIRCRAFT_01", moduleId = "vas", bayId = 1 }, pkg)
        c.bus:step(0.05)
        c.pump_onboard()
        assert_false(ok)
        assert_eq(res.reason, "NOT_DISARMED")
        assert_eq(read_text(c.roots.vas .. "/main.lua"), "-- vas protected v1.22.0\n")
        assert_eq(read_json(c.roots.vas .. "/.version.json").modules.vas.version, "1.22.0")
        assert_false(fs.exists(c.roots.vas .. "/.ota_pending.json"))
        assert_false(fs.exists(c.roots.vas .. "/ota_staging"))

        local nacks = c.bus:find_packets({ type = "MSG_OTA_NACK" })
        assert_true(#nacks >= 1)
        assert_eq(nacks[1].payload.payload.reason, "NOT_DISARMED")
        local aborts = c.bus:find_packets({ type = "MSG_OTA_ABORT" })
        assert_true(#aborts >= 1)
        assert_eq(aborts[1].payload.payload.reason, "NOT_DISARMED")

        c.cleanup()
    end)

    it("aborts transfer with CRC_MISMATCH and discards staging when a MSG_OTA_CHUNK payload byte is tampered on the bus", function()
        local tampered = false
        local c
        c = create_ota_cluster("crc_tamper", {
            maxRetries = 1,
            txHook = function(_ch, _replyCh, pkt)
                if type(pkt) == "table" and pkt.type == "MSG_OTA_CHUNK" then
                    tampered = true
                    local bad = clone_table(pkt)
                    local origData = tostring(bad.payload.data or "")
                    local flippedByte = (origData:sub(1, 1) == "X") and "Y" or "X"
                    bad.payload.data = flippedByte .. origData:sub(2)
                    return true, bad
                end
                return true
            end,
        })

        write_text(c.roots.fcp .. "/main.lua", "-- fcp original v2.0.0\n")
        write_json(c.roots.fcp .. "/.version.json", {
            modules = { fcp = { id = "fcp", version = "2.0.0", files = { "/main.lua" } } },
        })

        local pkg = stage_server_package(c, "fcp", "2.1.0", {
            { path = "/main.lua", content = "-- fcp tampered payload candidate\n" },
        })

        local ok, res = c.server:deploy({ domainId = "AIRCRAFT_01", moduleId = "fcp", bayId = 1 }, pkg, { maxRetries = 1 })
        c.bus:step(0.05)
        c.pump_onboard()
        assert_false(ok)
        assert_true(tampered)
        assert_eq(res.reason, "CRC_MISMATCH")
        assert_eq(read_text(c.roots.fcp .. "/main.lua"), "-- fcp original v2.0.0\n")
        assert_eq(read_json(c.roots.fcp .. "/.version.json").modules.fcp.version, "2.0.0")
        assert_false(fs.exists(c.roots.fcp .. "/ota_staging/" .. tostring(res.txId)))
        assert_false(fs.exists(c.roots.fcp .. "/.ota_pending.json"))

        local nacks = c.bus:find_packets({ type = "MSG_OTA_NACK" })
        assert_true(#nacks >= 1)
        assert_eq(nacks[1].payload.payload.reason, "CRC_MISMATCH")
        local aborts = c.bus:find_packets({ type = "MSG_OTA_ABORT" })
        assert_true(#aborts >= 1)

        c.cleanup()
    end)

    it("automatically rolls back poisoned TCA boot crash via startup_generator watchdog and delivers ROLLED_BACK status", function()
        local c = create_ota_cluster("watchdog_rollback")

        local origMain = "_G.__E2E_TCA_BOOT_VER = '1.9.1-restored'\nreturn true\n"
        local origKeep = "return 'legacy_keep_ok'\n"
        write_text(c.roots.tca .. "/main.lua", origMain)
        write_text(c.roots.tca .. "/modules/legacy_keep.lua", origKeep)
        write_json(c.roots.tca .. "/.version.json", {
            modules = {
                tca = {
                    id = "tca",
                    version = "1.9.1",
                    files = { "/main.lua", "/modules/legacy_keep.lua" },
                },
            },
        })

        local okHook, errHook = c.startup_generator.installHook({
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = c.roots.tca .. "/main.lua",
            installDir = c.roots.tca,
            otaRootPrefix = c.roots.tca,
        }, c.roots.tca, fs)
        assert_true(okHook, "installHook failed: " .. tostring(errHook))

        -- Deploy poisoned TCA payload (runtime crash + deletes legacy_keep.lua + adds bad_extra.lua)
        local pkg = stage_server_package(c, "tca", "1.9.9-bad", {
            { path = "/main.lua", content = "error('SIMULATED_E2E_BOOT_CRASH')\n" },
            { path = "/modules/bad_extra.lua", content = "return 'should_be_removed'\n" },
        })

        local okDeploy, res = c.server:deploy(
            { domainId = "AIRCRAFT_01", moduleId = "tca", bayId = 1 },
            pkg,
            { autoReboot = true }
        )
        assert_true(okDeploy, "poisoned payload staging should apply before reboot: " .. tostring(res and res.reason))
        assert_eq(res.status, "PENDING_COMMIT")
        assert_false(fs.exists(c.roots.tca .. "/modules/legacy_keep.lua"))
        assert_true(fs.exists(c.roots.tca .. "/modules/bad_extra.lua"))
        assert_true(fs.exists(c.roots.tca .. "/.ota_pending.json"))

        -- Simulate reboot via generated startup hook with os.reboot spy
        local origReboot = os.reboot
        local origDisable = _G.__OTA_DISABLE_REBOOT
        local rebootSpy = 0
        _G.__OTA_DISABLE_REBOOT = false
        os.reboot = function()
            rebootSpy = rebootSpy + 1
        end
        local okHookRun, hookErr = pcall(dofile, c.roots.tca .. "/startup/00_tca.lua")
        os.reboot = origReboot
        _G.__OTA_DISABLE_REBOOT = origDisable

        assert_true(okHookRun, "startup hook watchdog must catch runtime crash: " .. tostring(hookErr))
        assert_eq(rebootSpy, 1)

        -- Assert full filesystem & version rollback
        assert_eq(read_text(c.roots.tca .. "/main.lua"), origMain)
        assert_eq(read_text(c.roots.tca .. "/modules/legacy_keep.lua"), origKeep)
        assert_false(fs.exists(c.roots.tca .. "/modules/bad_extra.lua"))
        assert_eq(read_json(c.roots.tca .. "/.version.json").modules.tca.version, "1.9.1")
        assert_false(fs.exists(c.roots.tca .. "/.ota_pending.json"))
        assert_false(fs.exists(c.roots.tca .. "/ota_backup/" .. res.txId))

        local rbRec = read_json(c.roots.tca .. "/.ota_rollback.json")
        assert_eq(rbRec.txId, res.txId)
        assert_eq(rbRec.moduleId, "tca")
        assert_eq(rbRec.targetVersion, "1.9.9-bad")
        assert_eq(rbRec.reason, "BOOT_RUNTIME_CRASH")

        -- Boot restored TCA again and verify ROLLED_BACK status reaches server
        _G.__E2E_TCA_BOOT_VER = nil
        dofile(c.roots.tca .. "/startup/00_tca.lua")
        assert_eq(_G.__E2E_TCA_BOOT_VER, "1.9.1-restored")
        _G.__E2E_TCA_BOOT_VER = nil

        c.tcaInst = c.tcaDaemon.init(c.build_tca_cfg(), c.tcaNode.modem)
        c.tcaInst:step_event("timer", 1)
        c.bus:step(0.05)

        assert_false(fs.exists(c.roots.tca .. "/.ota_rollback.json"))

        local srvBootMsgs = {}
        for _, msg in ipairs(c.srvNode.modem:drain()) do
            if type(msg.payload) == "table" and msg.payload.type == "MSG_OTA_BOOT_STATUS" then
                srvBootMsgs[#srvBootMsgs + 1] = msg
            end
        end
        assert_eq(#srvBootMsgs, 1)
        assert_eq(srvBootMsgs[1].channel, 106)
        assert_eq(srvBootMsgs[1].payload.payload.txId, res.txId)
        assert_eq(srvBootMsgs[1].payload.payload.moduleId, "tca")
        assert_eq(srvBootMsgs[1].payload.payload.status, "ROLLED_BACK")
        assert_eq(srvBootMsgs[1].payload.payload.rollbackReason, "BOOT_RUNTIME_CRASH")

        c.cleanup()
    end)
end)
