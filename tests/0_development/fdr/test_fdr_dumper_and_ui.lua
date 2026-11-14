-- Unit tests for FDR jsonl_dumper (streaming rollover + ring dump) and 51x19 fdr_ui
local storage_pool = require("storage_pool")
local jsonl_dumper = require("jsonl_dumper")
local ring_buffer = require("ring_buffer")
local fdr_ui = require("fdr_ui")

local function make_two_disk_env(disk1Free, disk2Free)
    local files = {}
    local dirs = {}
    local specs = {
        drive_a = { mountPath = "/disk", freeBytes = disk1Free, hasData = true },
        drive_b = { mountPath = "/disk2", freeBytes = disk2Free, hasData = true },
    }
    local pApi = {
        getNames = function() return { "drive_a", "drive_b" } end,
        getType = function() return "drive" end,
    }
    local dApi = {
        isPresent = function() return true end,
        hasData = function() return true end,
        getMountPath = function(n) return specs[n].mountPath end,
    }
    local fsApi = {
        getFreeSpace = function(p)
            if string.sub(p, 1, 6) == "/disk2" then return specs.drive_b.freeBytes end
            if string.sub(p, 1, 5) == "/disk" then return specs.drive_a.freeBytes end
            return 0
        end,
        exists = function(p) return dirs[p] == true or files[p] ~= nil end,
        isDir = function(p) return dirs[p] == true end,
        makeDir = function(p) dirs[p] = true end,
        list = function() return {} end,
        delete = function(p) files[p] = nil end,
        open = function(p, mode)
            if mode == "w" then files[p] = "" end
            if mode == "a" then files[p] = files[p] or "" end
            local flushes = 0
            return {
                write = function(s)
                    files[p] = files[p] .. s
                end,
                writeLine = function(line)
                    files[p] = files[p] .. line .. "\n"
                    if string.sub(p, 1, 6) == "/disk2" then
                        specs.drive_b.freeBytes = math.max(0, specs.drive_b.freeBytes - (#line + 1))
                    elseif string.sub(p, 1, 5) == "/disk" then
                        specs.drive_a.freeBytes = math.max(0, specs.drive_a.freeBytes - (#line + 1))
                    end
                end,
                flush = function() flushes = flushes + 1 end,
                close = function() end,
                _flushes = function() return flushes end,
            }
        end,
    }
    local cfg = {
        aircraftIndexN = 1,
        baseChannel = 10000,
        recordMode = "STREAMING",
        tapOptions = { aero = true, trajectory = true },
        streaming = { flushIntervalFrames = 2, flushIntervalSec = 1.0 },
        storage = {
            preferExternalDisk = true,
            allowLocalFallback = false,
            localDumpDir = "/logs",
            diskSubDir = "fdr_logs",
            maxPartBytes = 250,
            rollOverReserveBytes = 16384,
            minFreeSpaceBytes = 16384,
            autoPruneOldest = false,
            maxTotalSessions = 10,
        },
    }
    return cfg, pApi, dApi, fsApi, files, specs
end

describe("fdr jsonl_dumper STREAMING & rollover", function()
    it("writes valid META, FRAME, and FOOTER JSONL across multi-disk part rollover", function()
        local cfg, pApi, dApi, fsApi, files, specs = make_two_disk_env(90000, 40000)
        local apis = { peripheral = pApi, disk = dApi, fs = fsApi }
        local stream, err = jsonl_dumper.open_stream(cfg, {
            sessionId = "AIRCRAFT_01_1000",
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            startedAtMs = 1000,
        }, apis)
        assert_not_nil(stream, err)
        assert_eq(stream.partIndex, 1)

        -- Shrink disk 1 low enough to trigger disk switch after part limit rollover
        specs.drive_a.freeBytes = 10000

        for i = 1, 4 do
            local ok, rErr = jsonl_dumper.append_frame(stream, {
                recordType = "FRAME",
                seqIdx = i,
                rxMs = 1000 + i * 50,
                txMs = 995 + i * 50,
                channel = 10002,
                offset = 2,
                msgType = "MSG_FLIGHT_TELEMETRY",
                payload = { attitude = { pitch = i * 1.5 }, controlState = "NORMAL" },
            }, 1000 + i * 50, apis)
            assert_true(ok, rErr)
        end

        assert_true(jsonl_dumper.close_stream(stream, "MANUAL_STOP", 1500, apis))
        assert_true(#stream.parts >= 2)
        assert_eq(stream.parts[1].mountPath, "/disk")
        assert_eq(stream.parts[2].mountPath, "/disk2")

        local p1Text = files[stream.parts[1].filePath]
        local p2Text = files[stream.parts[2].filePath]
        assert_not_nil(p1Text)
        assert_not_nil(p2Text)
        assert_true(string.find(p1Text, '"recordType":"META"', 1, true) ~= nil or string.find(p1Text, '"META"', 1, true) ~= nil)
        assert_true(string.find(p1Text, '"FOOTER"', 1, true) ~= nil)
        assert_true(string.find(p2Text, '"FOOTER"', 1, true) ~= nil)
    end)

    it("fails cleanly with ERR_DISK_FULL when no volume meets minFreeSpaceBytes", function()
        local cfg, pApi, dApi, fsApi = make_two_disk_env(1024, 1024)
        local buf = ring_buffer.init(10)
        ring_buffer.push(buf, { recordType = "FRAME", seqIdx = 1, rxMs = 10, channel = 10002, offset = 2, msgType = "MSG_FLIGHT_TELEMETRY", payload = {} })
        local ok, manifest, err = jsonl_dumper.dump_ring_buffer(buf, cfg, {
            sessionId = "AIRCRAFT_01_2000",
            domainId = "AIRCRAFT_01",
            baseChannel = 10000,
            trigger = "E_STOP",
            nowMs = 2000,
        }, { peripheral = pApi, disk = dApi, fs = fsApi })
        assert_false(ok)
        assert_nil(manifest)
        assert_eq(err, "ERR_DISK_FULL")
    end)
end)

describe("fdr 51x19 fdr_ui renderer", function()
    it("renders exact 51-char term.blit rows showing Aligner status and VFS pool", function()
        local termMock = mock.term(51, 19)
        local ok = fdr_ui.render(termMock, {
            mode = "LOGGING",
            aircraftIndexN = 2,
            baseChannel = 10040,
            domainId = "HAWK_02",
            activeMount = "/disk2",
            activeFreeKB = 102,
            poolFreeKB = 420,
            partIndex = 3,
            framesWritten = 480,
            countsByOffset = { [1] = 120, [2] = 120, [10] = 120, [11] = 60, [4] = 60 },
            exportStatus = "GDRIVE READY",
        })
        assert_true(ok)
        for y = 1, 19 do
            assert_eq(#termMock._lines[y], 51)
            assert_eq(#termMock._fg[y], 51)
            assert_eq(#termMock._bg[y], 51)
        end
        assert_true(termMock:_contains("HAWK_02"))
        assert_true(termMock:_contains("/disk2"))
        assert_true(termMock:_contains("LOGGING"))
    end)
end)
