-- Unit tests for FDR Multi-Disk Spanned VFS storage_pool
local storage_pool = require("storage_pool")

local function make_storage_cfg(overrides)
    local cfg = {
        storage = {
            preferExternalDisk = true,
            allowLocalFallback = true,
            localDumpDir = "/logs",
            diskSubDir = "fdr_logs",
            maxPartBytes = 100000,
            rollOverReserveBytes = 16384,
            minFreeSpaceBytes = 16384,
            autoPruneOldest = true,
            maxTotalSessions = 2,
        },
    }
    if overrides then
        for k, v in pairs(overrides) do cfg.storage[k] = v end
    end
    return cfg
end

local function make_mock_vfs(diskSpecs, localFree)
    local files = {}
    local dirs = { ["/logs"] = true }
    local deleted = {}

    local peripheralApi = {
        getNames = function()
            local names = { "top" }
            for name, _ in pairs(diskSpecs) do table.insert(names, name) end
            return names
        end,
        getType = function(name)
            return diskSpecs[name] and "drive" or "modem"
        end,
    }
    local diskApi = {
        isPresent = function(name) return diskSpecs[name] and diskSpecs[name].present ~= false end,
        hasData = function(name) return diskSpecs[name] and diskSpecs[name].hasData ~= false end,
        getMountPath = function(name) return diskSpecs[name] and diskSpecs[name].mountPath end,
    }
    local fsApi = {
        getFreeSpace = function(path)
            for _, spec in pairs(diskSpecs) do
                if path == spec.mountPath or string.sub(path, 1, #spec.mountPath + 1) == spec.mountPath .. "/" then
                    return spec.freeBytes
                end
            end
            return localFree
        end,
        exists = function(p) return dirs[p] == true or files[p] ~= nil end,
        isDir = function(p) return dirs[p] == true end,
        makeDir = function(p) dirs[p] = true end,
        list = function(dir)
            local out = {}
            local prefix = (dir == "/" and "/") or (dir .. "/")
            for p, _ in pairs(files) do
                if string.sub(p, 1, #prefix) == prefix then
                    local rel = string.sub(p, #prefix + 1)
                    if rel ~= "" and not string.find(rel, "/", 1, true) then
                        table.insert(out, rel)
                    end
                end
            end
            table.sort(out)
            return out
        end,
        delete = function(p)
            files[p] = nil
            table.insert(deleted, p)
        end,
        open = function(p, mode)
            if mode == "w" then files[p] = "" end
            if mode == "r" then
                if files[p] == nil then return nil end
                local data = files[p]
                return { readAll = function() return data end, close = function() end }
            end
            return {
                writeLine = function(line) files[p] = (files[p] or "") .. line .. "\n" end,
                write = function(s) files[p] = (files[p] or "") .. s end,
                flush = function() end,
                close = function() end,
            }
        end,
    }
    return peripheralApi, diskApi, fsApi, files, deleted
end

describe("fdr Multi-Disk VFS storage_pool", function()
    it("scans wired drives, skips audio disks, and picks largest free external volume", function()
        local specs = {
            drive_0 = { mountPath = "/disk", freeBytes = 32000, hasData = true },
            drive_audio = { mountPath = "/disk2", freeBytes = 90000, hasData = false },
            drive_1 = { mountPath = "/disk3", freeBytes = 110000, hasData = true },
        }
        local pApi, dApi, fsApi = make_mock_vfs(specs, 500000)
        local cfg = make_storage_cfg()

        local vols = storage_pool.scan_volumes(cfg, pApi, dApi, fsApi)
        -- 2 valid data drives + 1 local fallback
        assert_eq(#vols, 3)

        local best = storage_pool.select_best_volume(vols, cfg)
        assert_not_nil(best)
        assert_eq(best.mountPath, "/disk3")
        assert_eq(storage_pool.get_pool_free_bytes(vols), 32000 + 110000 + 500000)
    end)

    it("falls back to local /logs only when all external drives lack minFreeSpaceBytes", function()
        local specs = {
            drive_0 = { mountPath = "/disk", freeBytes = 4096, hasData = true },
        }
        local pApi, dApi, fsApi = make_mock_vfs(specs, 250000)
        local cfg = make_storage_cfg()

        local vols = storage_pool.scan_volumes(cfg, pApi, dApi, fsApi)
        local best = storage_pool.select_best_volume(vols, cfg)
        assert_not_nil(best)
        assert_eq(best.mountPath, "/logs")
        assert_true(best.isLocal)
    end)

    it("prunes oldest inactive session parts while preserving active session files", function()
        local specs = {
            drive_0 = { mountPath = "/disk", freeBytes = 80000, hasData = true },
        }
        local pApi, dApi, fsApi, files, deleted = make_mock_vfs(specs, 0)
        local cfg = make_storage_cfg({ allowLocalFallback = false, maxTotalSessions = 1 })

        files["/disk/fdr_logs/AIRCRAFT_01_1000_part001.jsonl"] = "old1\n"
        files["/disk/fdr_logs/AIRCRAFT_01_2000_part001.jsonl"] = "old2\n"
        files["/disk/fdr_logs/AIRCRAFT_01_3000_part001.jsonl"] = "active\n"
        fsApi.makeDir("/disk/fdr_logs")

        local vols = storage_pool.scan_volumes(cfg, pApi, dApi, fsApi)
        local removed = storage_pool.prune_oldest_sessions(vols, cfg, "AIRCRAFT_01_3000", fsApi)
        assert_true(removed >= 1)
        assert_nil(files["/disk/fdr_logs/AIRCRAFT_01_1000_part001.jsonl"])
        assert_not_nil(files["/disk/fdr_logs/AIRCRAFT_01_3000_part001.jsonl"])
        assert_true(#deleted >= 1)
    end)
end)
