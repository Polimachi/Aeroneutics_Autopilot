-- tests/e2e/test_e2e_fdr_blackbox.lua
-- End-to-End Integration: VAS (opt-in telemetryDiag) + FCP + FDR Ground In-Flight Aligner (Receive-Only + VFS Rollover)
local virtual_bus = require("virtual_bus")
local node_sandbox = require("node_sandbox")

local function make_vfs_fs(freeMap)
    local files, dirs = {}, {}
    local function norm(p)
        local c = tostring(p or "/"):gsub("//+", "/")
        if #c > 1 and c:sub(-1) == "/" then c = c:sub(1, -2) end
        return c
    end
    return {
        exists = function(p) p = norm(p); return files[p] ~= nil or dirs[p] == true or p == "/" or freeMap[p] ~= nil end,
        isDir = function(p) p = norm(p); return dirs[p] == true or p == "/" or freeMap[p] ~= nil end,
        makeDir = function(p) dirs[norm(p)] = true end,
        getFreeSpace = function(p)
            p = norm(p)
            if freeMap[p] then return freeMap[p] end
            local best, bVal = "/", freeMap["/"] or 0
            for k, v in pairs(freeMap) do
                if p:sub(1, #k) == k and #k >= #best then best, bVal = k, v end
            end
            return bVal
        end,
        list = function(p)
            p = norm(p)
            local pre = (p == "/") and "/" or (p .. "/")
            local seen, out = {}, {}
            for k, _ in pairs(files) do
                if k:sub(1, #pre) == pre then
                    local seg = k:sub(#pre + 1):match("^([^/]+)")
                    if seg and not seen[seg] then seen[seg] = true; table.insert(out, seg) end
                end
            end
            return out
        end,
        delete = function(p) files[norm(p)] = nil end,
        open = function(p, mode)
            p = norm(p)
            if mode == "w" then
                local buf = ""
                return {
                    write = function(s) buf = buf .. tostring(s) end,
                    writeLine = function(s) buf = buf .. tostring(s) .. "\n" end,
                    flush = function() files[p] = buf end,
                    close = function() files[p] = buf end,
                }
            elseif mode == "r" and files[p] then
                local data = files[p]
                return { readAll = function() return data end, close = function() end }
            end
            return nil
        end,
        _files = files,
        _freeMap = freeMap,
    }
end

describe("Scenario 9: FDR Ground In-Flight Aligner E2E", function()
    it("passively taps VAS telemetryDiag + FCP commands with 0 tx, rolls over across VFS disks, rebinds [N], and flushes E_STOP", function()
        local bus = virtual_bus.create_bus({ clock = 2000.0 })
        local fcp = node_sandbox.create_node(bus, "FCP", "src/2_guidance/fcp")
        local vas = node_sandbox.create_node(bus, "VAS", "src/1_control/vas")
        local fdr = node_sandbox.create_node(bus, "FDR", "src/0_development/fdr")

        local txSpy = 0
        local origTx = fdr.modem.transmit
        fdr.modem.transmit = function(...)
            txSpy = txSpy + 1
            return origTx(...)
        end

        local fsApi = make_vfs_fs({ ["/"] = 500000, ["/disk"] = 200000, ["/disk2"] = 300000 })
        local disks = {
            drive_0 = { mount = "/disk", data = true },
            drive_1 = { mount = "/disk2", data = true },
        }
        local apis = {
            modem = fdr.modem,
            fs = fsApi,
            peripheral = {
                getNames = function() return { "top", "drive_0", "drive_1" } end,
                getType = function(n) return (n == "top") and "modem" or "drive" end,
                isPresent = function(n) return n == "top" or disks[n] ~= nil end,
                wrap = function(n) return (n == "top") and fdr.modem or {} end,
            },
            disk = {
                isPresent = function(n) return disks[n] ~= nil end,
                hasData = function(n) return disks[n] and disks[n].data == true end,
                getMountPath = function(n) return disks[n] and disks[n].mount or nil end,
            },
            epoch = function() return math.floor(bus.time * 1000) end,
        }

        local fdr_main = fdr:require("main")
        local st = fdr_main.init({
            schemaVersion = "1.1.0",
            aircraftIndexN = 1,
            baseChannel = 10000,
            domainId = "*",
            autoStartOnBoot = true,
            recordMode = "STREAMING",
            tapOptions = { aero = true, trajectory = true, includeControlEvents = false },
            streaming = { flushIntervalFrames = 2, flushIntervalSec = 1.0 },
            storage = {
                preferExternalDisk = true,
                allowLocalFallback = true,
                localDumpDir = "/logs",
                diskSubDir = "fdr_logs",
                maxPartBytes = 420,
                rollOverReserveBytes = 16384,
                minFreeSpaceBytes = 16384,
                autoPruneOldest = false,
                autoFlushOnEstop = true,
            },
        }, apis)

        assert_eq(st.mode, "LOGGING")
        assert_true(fdr.modem:isOpen(10001))
        assert_true(fdr.modem:isOpen(10002))
        assert_true(fdr.modem:isOpen(10010))

        -- VAS telemetry_feeder with telemetryDiag=true + FCP attitude commands
        local vas_feeder = vas:require("telemetry_feeder")
        local feederState = vas_feeder.init({ telemetryDiag = true })
        local vasNet = {
            channels = { telemetry = 10002, mfd = 10003 },
            wirelessModem = vas.modem,
            domainId = "CRAFT_E2E_01",
            aircraftDomainId = "CRAFT_E2E_01",
            seq = 0,
        }
        local comState = {
            attitude = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
            rates = { p = 0.01, q = 0.02, r = 0.0 },
            dynamics = { altitudeY = 120.0, verticalSpeed = 0.5, velocity = { vx = 1.0, vy = 0.5, vz = 0.0 } },
            fuel = { amount = 900, capacity = 1000, ratio = 0.9 },
        }

        for i = 1, 5 do
            fcp.modem:transmit(10001, 10001, {
                ver = "1.9.5",
                domainId = "CRAFT_E2E_01",
                seq = i,
                time = 2000 + i * 50,
                type = "MSG_ATTITUDE_CMD",
                payload = {
                    commandType = "QUATERNION_RATE",
                    targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
                    collectiveThrust = 0.65,
                },
            })
            vas_feeder.tick(feederState, vasNet, comState, { currentState = "NORMAL" }, nil, {
                sensorOk = true,
                satFlags = { axisSaturatedPos = { pitch = false }, axisSaturatedNeg = {} },
                diag = { saturationFreeze = false, integrators = { pitch = 0.1 * i } },
            })
            vas.modem:transmit(10010, 10010, {
                ver = "1.9.5",
                domainId = "CRAFT_E2E_01",
                seq = 100 + i,
                time = 2000 + i * 50,
                type = "MSG_THRUST_CMD",
                payload = { watchdogSeq = i, controlState = "NORMAL", outputs = { m1 = 0.55, m2 = 0.52 } },
            })
            bus:step(0.05)

            local inbox = fdr.modem:drain()
            for _, msg in ipairs(inbox) do
                fdr_main.handle_event(st, "modem_message", "top", msg.channel, msg.replyChannel, msg.payload)
            end
        end

        assert_eq(st.tap.lockedDomainId, "CRAFT_E2E_01")
        assert_true(st.framesWritten >= 10)
        assert_true(#st.stream.parts >= 2)
        assert_eq(txSpy, 0)

        -- Edge-latched E_STOP auto-flush on Base+1
        fcp.modem:transmit(10001, 10001, {
            ver = "1.9.5",
            domainId = "CRAFT_E2E_01",
            seq = 999,
            time = 2500,
            type = "MSG_EMERGENCY_OVERRIDE",
            payload = { action = "E_STOP", source = "GCS" },
        })
        bus:step(0.05)
        for _, msg in ipairs(fdr.modem:drain()) do
            fdr_main.handle_event(st, "modem_message", "top", msg.channel, msg.replyChannel, msg.payload)
        end
        assert_true(st.estopFlushed)

        -- Dynamic [N] rebind to N=2 (Base=10040)
        assert_true(fdr_main.switch_aircraft(st, 2, "*"))
        assert_eq(st.tap.baseChannel, 10040)
        assert_true(fdr.modem:isOpen(10042))
        assert_false(fdr.modem:isOpen(10002))
        assert_not_nil(st.lastSessionManifest)
        assert_true(fsApi.exists(st.lastSessionManifest.manifestPath))
        assert_eq(txSpy, 0)

        fdr_main.shutdown(st, "E2E_DONE")
        assert_false(st.running)
    end)
end)
