-- Unit tests for FDR main.lua lifecycle, keybindings, hotplug recovery, and E_STOP edge-latch.
local fdr_main = require("main")
local storage_pool = require("storage_pool")

local function make_mem_fs(freeByPath)
    local files = {}
    local dirs = {}
    local freeMap = freeByPath or { ["/"] = 500000, ["/disk"] = 200000 }
    local function norm(p)
        local clean = tostring(p or "/"):gsub("//+", "/")
        if #clean > 1 and clean:sub(-1) == "/" then clean = clean:sub(1, -2) end
        return clean
    end
    local function parent_of(p)
        return norm(p):match("^(.*)/[^/]+$") or "/"
    end
    local api = {}
    api.exists = function(p)
        p = norm(p)
        return files[p] ~= nil or dirs[p] == true or p == "/" or freeMap[p] ~= nil
    end
    api.isDir = function(p)
        p = norm(p)
        return dirs[p] == true or p == "/" or freeMap[p] ~= nil
    end
    api.makeDir = function(p)
        dirs[norm(p)] = true
    end
    api.getFreeSpace = function(p)
        p = norm(p)
        if freeMap[p] then return freeMap[p] end
        local bestMatch, bestVal = "/", freeMap["/"] or 0
        for k, v in pairs(freeMap) do
            if p:sub(1, #k) == k and #k >= #bestMatch then
                bestMatch, bestVal = k, v
            end
        end
        return bestVal
    end
    api.list = function(p)
        p = norm(p)
        local prefix = (p == "/") and "/" or (p .. "/")
        local seen, out = {}, {}
        for k, _ in pairs(files) do
            if k:sub(1, #prefix) == prefix then
                local rest = k:sub(#prefix + 1)
                local seg = rest:match("^([^/]+)")
                if seg and not seen[seg] then
                    seen[seg] = true
                    table.insert(out, seg)
                end
            end
        end
        for k, _ in pairs(dirs) do
            if k:sub(1, #prefix) == prefix then
                local rest = k:sub(#prefix + 1)
                local seg = rest:match("^([^/]+)")
                if seg and not seen[seg] then
                    seen[seg] = true
                    table.insert(out, seg)
                end
            end
        end
        return out
    end
    api.delete = function(p)
        p = norm(p)
        files[p] = nil
    end
    api.open = function(p, mode)
        p = norm(p)
        if mode == "w" then
            local parent = parent_of(p)
            dirs[parent] = true
            local buf = ""
            return {
                write = function(s) buf = buf .. tostring(s) end,
                writeLine = function(s) buf = buf .. tostring(s) .. "\n" end,
                flush = function() files[p] = buf end,
                close = function() files[p] = buf end,
            }
        elseif mode == "r" then
            local data = files[p]
            if not data then return nil end
            return {
                readAll = function() return data end,
                close = function() end,
            }
        end
        return nil
    end
    api._files = files
    api._freeMap = freeMap
    return api
end

local function make_mock_apis(freeMap)
    local opened = {}
    local txCount = 0
    local modem = {
        open = function(ch) opened[ch] = true end,
        close = function(ch) opened[ch] = nil end,
        isOpen = function(ch) return opened[ch] == true end,
        isWireless = function() return true end,
        transmit = function() txCount = txCount + 1 end,
        _opened = opened,
        _getTxCount = function() return txCount end,
    }
    local disks = { "/disk" }
    local peripheralApi = {
        getNames = function() return { "top", "drive_0" } end,
        getType = function(name) return (name == "drive_0") and "drive" or "modem" end,
        isPresent = function(name) return name == "top" or name == "drive_0" end,
        wrap = function(name)
            if name == "top" then return modem end
            return {}
        end,
    }
    local diskApi = {
        isPresent = function(name) return name == "drive_0" and disks[1] ~= nil end,
        hasData = function(name) return name == "drive_0" and disks[1] ~= nil end,
        getMountPath = function(name) return (name == "drive_0") and disks[1] or nil end,
    }
    local fsApi = make_mem_fs(freeMap)
    local posts = {}
    local httpApi = {
        post = function(url, body, headers)
            table.insert(posts, { url = url, body = body, headers = headers })
            return { close = function() end }
        end,
    }
    local termCalls = 0
    local termApi = {
        blit = function() termCalls = termCalls + 1 end,
        setCursorPos = function() end,
        clear = function() end,
    }
    return {
        modem = modem,
        peripheral = peripheralApi,
        disk = diskApi,
        fs = fsApi,
        http = httpApi,
        term = termApi,
        _disks = disks,
        _posts = posts,
        _getTermCalls = function() return termCalls end,
        _nowMs = 1000,
        epoch = function() return 1000 end,
    }
end

local function make_cfg(mode)
    return {
        schemaVersion = "1.1.0",
        aircraftIndexN = 1,
        baseChannel = 10000,
        domainId = "*",
        modemSide = "top",
        autoStartOnBoot = true,
        recordMode = mode or "STREAMING",
        tapOptions = { aero = true, trajectory = true, includeControlEvents = false },
        streaming = { flushIntervalFrames = 2, flushIntervalSec = 1.0 },
        ringBuffer = { capacity = 8 },
        storage = {
            preferExternalDisk = true,
            allowLocalFallback = true,
            localDumpDir = "/logs",
            diskSubDir = "fdr_logs",
            maxPartBytes = 100000,
            rollOverReserveBytes = 16384,
            minFreeSpaceBytes = 16384,
            autoPruneOldest = true,
            maxTotalSessions = 10,
            autoFlushOnEstop = true,
        },
        export = {
            mode = "GDRIVE_WEBHOOK",
            webhookUrl = "https://example.invalid/fdr",
            gdriveFolderId = "1C3ZWMoXjsba1QE8ksgWG0LSfxzW_nMWI",
            gdriveFolderName = "FDR_Reports",
        },
        debug = true,
    }
end

describe("FDR main daemon lifecycle and keybindings", function()
    it("starts in LOGGING (STREAMING), taps RF passively with 0 transmit, and switches aircraft [N]", function()
        local apis = make_mock_apis({ ["/"] = 500000, ["/disk"] = 200000 })
        local st = fdr_main.init(make_cfg("STREAMING"), apis)
        assert_eq(st.mode, "LOGGING")
        assert_eq(st.tap.baseChannel, 10000)
        assert_true(apis.modem.isOpen(10002))

        local okPkt = {
            ver = "1.9.5",
            domainId = "CRAFT_01",
            seq = 1,
            time = 1000,
            type = "MSG_FLIGHT_TELEMETRY",
            payload = { controlState = "NORMAL", sensorOk = true },
        }
        assert_true(fdr_main.handle_event(st, "modem_message", "top", 10002, 10002, okPkt))
        assert_eq(st.framesWritten, 1)
        assert_eq(st.tap.lockedDomainId, "CRAFT_01")
        assert_eq(apis.modem._getTxCount(), 0)

        -- Switch aircraft to N=3 -> Base = 10080, closes old stream cleanly
        local okSw = fdr_main.switch_aircraft(st, 3, "*")
        assert_true(okSw)
        assert_eq(st.tap.aircraftIndexN, 3)
        assert_eq(st.tap.baseChannel, 10080)
        assert_false(apis.modem.isOpen(10002))
        assert_true(apis.modem.isOpen(10082))
        assert_eq(apis.modem._getTxCount(), 0)

        -- Quit safely
        local qKey = (keys and keys.q) or 16
        fdr_main.handle_event(st, "key", qKey, false)
        assert_false(st.running)
        assert_false(apis.modem.isOpen(10082))
    end)

    it("enters DISK_FULL when volumes lack space and recovers automatically on disk insert", function()
        local apis = make_mock_apis({ ["/"] = 100, ["/disk"] = 100 })
        local st = fdr_main.init(make_cfg("STREAMING"), apis)
        assert_eq(st.mode, "DISK_FULL")

        -- Insert disk with space and fire disk event
        apis.fs._freeMap["/disk"] = 200000
        fdr_main.handle_event(st, "disk", "drive_0")
        assert_eq(st.mode, "LOGGING")
        assert_not_nil(st.stream)
    end)

    it("latches E_STOP auto-flush once per E_STOP edge and handles [P]/[S]/[D]/[U]/[C] keys", function()
        local apis = make_mock_apis({ ["/"] = 500000, ["/disk"] = 200000 })
        local dumpCalls = 0
        local st = fdr_main.init(make_cfg("RING_BUFFER"), apis)
        assert_eq(st.mode, "LOGGING")

        local estopPkt = {
            ver = "1.9.5",
            domainId = "CRAFT_01",
            seq = 1,
            time = 1000,
            type = "MSG_EMERGENCY_OVERRIDE",
            payload = { action = "E_STOP", source = "GCS" },
        }
        fdr_main.handle_event(st, "modem_message", "top", 10001, 10001, estopPkt)
        assert_true(st.estopFlushed)
        assert_not_nil(st.lastSessionManifest)
        local firstDumpPath = st.lastSessionManifest.manifestPath

        -- Second E_STOP packet should NOT re-flush repeatedly while latched
        apis._files_before = {}
        local pKey = (keys and keys.p) or 25
        fdr_main.handle_event(st, "key", pKey, false)
        assert_eq(st.mode, "PAUSED")
        fdr_main.handle_event(st, "key", pKey, false)
        assert_eq(st.mode, "LOGGING")

        -- [U] triggers cloud export without modem transmit
        local uKey = (keys and keys.u) or 22
        fdr_main.handle_event(st, "key", uKey, false)
        assert_true(#apis._posts >= 1)
        assert_eq(apis.modem._getTxCount(), 0)
        assert_not_nil(firstDumpPath)

        -- [C] resets ring buffer & counts
        local cKey = (keys and keys.c) or 46
        fdr_main.handle_event(st, "key", cKey, false)
        assert_false(st.estopFlushed)
        assert_eq(st.tap.countsByOffset[1], 0)
    end)
end)
