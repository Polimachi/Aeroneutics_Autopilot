-- tests/0_development/installer/test_bootstrapper.lua
-- Unit tests for 3-Mode Root Bootstrapper (installer.lua)

_G.__INSTALLER_LIB_MODE = true
local bootstrapper = require("installer")

local function createMockHttp(routes, defaultBody)
    local m = { _calls = {} }
    m.get = function(url, headers, binary)
        table.insert(m._calls, { url = url, headers = headers, binary = binary })
        local r = routes and routes[url]
        if type(r) == "function" then
            r = r(url, headers, binary)
        end
        if not r and defaultBody then
            r = { code = 200, body = defaultBody }
        end
        if not r then
            return nil, "404 Not Found"
        end
        if r.fail then
            return nil, r.error or "HTTP_REQUEST_FAILED"
        end

        local handle = {
            getResponseCode = function() return r.code or 200 end,
            getResponseHeaders = function() return r.headers or {} end,
            readAll = function() return r.body or "-- content from " .. tostring(url) end,
            close = function() end,
        }
        return handle
    end
    return m
end

local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local h = fs.open(path, "w")
    if not h then
        error("Failed to open file for write: " .. tostring(path))
    end
    h.write(content)
    h.close()
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local c = h.readAll()
    h.close()
    return c
end

describe("bootstrapper context detection", function()
    it("detects direct_root, disk (/disk & /disk2), and remote_wget contexts accurately", function()
        local ctx1 = bootstrapper.detectContext("/installer.lua", fs)
        assert_eq(ctx1.mode, "direct_root")
        assert_eq(ctx1.targetRoot, "/")
        assert_true(ctx1.preserveSelf)

        local ctx2 = bootstrapper.detectContext("installer.lua", fs)
        assert_eq(ctx2.mode, "direct_root")
        assert_eq(ctx2.targetRoot, "/")
        assert_true(ctx2.preserveSelf)

        local ctx3 = bootstrapper.detectContext("/disk/installer.lua", fs)
        assert_eq(ctx3.mode, "disk")
        assert_eq(ctx3.targetRoot, "/")
        assert_true(ctx3.preserveSelf)

        local ctx4 = bootstrapper.detectContext("disk2/installer.lua", fs)
        assert_eq(ctx4.mode, "disk")
        assert_eq(ctx4.targetRoot, "/")
        assert_true(ctx4.preserveSelf)

        local ctx5 = bootstrapper.detectContext("/rom/programs/http/wget.lua", fs)
        assert_eq(ctx5.mode, "remote_wget")
        assert_eq(ctx5.targetRoot, "/")
        assert_false(ctx5.preserveSelf)

        local ctx6 = bootstrapper.detectContext("/_tmp_wget_run.lua", fs)
        assert_eq(ctx6.mode, "remote_wget")
        assert_eq(ctx6.targetRoot, "/")
        assert_false(ctx6.preserveSelf)
    end)
end)

describe("bootstrapper local core resolution and execution", function()
    it("targets computer root / and preserves disk files when launched from /disk/installer.lua", function()
        local diskSim = sdk.temp_path("disk_sim")
        local pcRoot = sdk.temp_path("pc_root")

        fs.makeDir(diskSim)
        fs.makeDir(pcRoot)

        local diskScript = diskSim .. "/installer.lua"
        writeFile(diskScript, "-- original disk installer content")

        local mockHttp = createMockHttp(nil, "-- mock bootstrap file")
        local runnerCalled = false
        local runnerOpts = nil

        local appRunner = function(opts)
            runnerCalled = true
            runnerOpts = opts
            local cacheDir = pcRoot .. "/.installer_cache"
            assert_true(fs.exists(cacheDir))
            assert_true(fs.exists(cacheDir .. "/installer_app.lua"))
            assert_true(fs.exists(cacheDir .. "/modules/manifest.lua"))
            return true, nil
        end

        local ok, err = bootstrapper.bootstrapAndRun({
            runningProgram = "/disk/installer.lua",
            targetRoot = pcRoot,
            http = mockHttp,
            appRunner = appRunner,
            fs = fs,
            localCoreDir = false, -- force remote bootstrap
        })

        assert_true(ok)
        assert_eq(err, nil)
        assert_true(runnerCalled)
        assert_eq(runnerOpts.targetRoot, pcRoot)

        -- Cache must be cleaned up
        assert_false(fs.exists(pcRoot .. "/.installer_cache"))

        -- Disk file preserved untouched
        assert_true(fs.exists(diskScript))
        assert_eq(readFile(diskScript), "-- original disk installer content")
    end)

    it("cleans /.installer_cache even if installer_app.run raises an error", function()
        local pcRoot = sdk.temp_path("pc_root_err")
        fs.makeDir(pcRoot)

        local mockHttp = createMockHttp(nil, "-- mock bootstrap file")
        local appRunner = function(opts)
            local cacheDir = pcRoot .. "/.installer_cache"
            assert_true(fs.exists(cacheDir))
            error("SIMULATED_APP_FATAL_ERROR")
        end

        local ok, err = bootstrapper.bootstrapAndRun({
            runningProgram = "/disk/installer.lua",
            targetRoot = pcRoot,
            http = mockHttp,
            appRunner = appRunner,
            fs = fs,
            localCoreDir = false, -- force remote bootstrap
        })

        assert_false(ok)
        assert_true(tostring(err):find("SIMULATED_APP_FATAL_ERROR") ~= nil)

        -- Cache must be cleaned up despite the error
        assert_false(fs.exists(pcRoot .. "/.installer_cache"))
    end)

    it("preserves /installer.lua on computer root after direct_root execution completes", function()
        local pcRoot = sdk.temp_path("pc_root_direct")
        fs.makeDir(pcRoot)

        local rootInstaller = pcRoot .. "/installer.lua"
        writeFile(rootInstaller, "-- root installer script")

        local mockHttp = createMockHttp(nil, "-- mock bootstrap file")
        local runnerCalled = false

        local appRunner = function(opts)
            runnerCalled = true
            return true, nil
        end

        local ok, err = bootstrapper.bootstrapAndRun({
            runningProgram = "/installer.lua",
            targetRoot = pcRoot,
            http = mockHttp,
            appRunner = appRunner,
            fs = fs,
            localCoreDir = false, -- force remote bootstrap
        })

        assert_true(ok)
        assert_true(runnerCalled)

        -- /installer.lua on root must remain untouched
        assert_true(fs.exists(rootInstaller))
        assert_eq(readFile(rootInstaller), "-- root installer script")
    end)

    it("resolves local core directory when present and runs without HTTP calls", function()
        local testCoreDir = sdk.temp_path("test_core")
        writeFile(testCoreDir .. "/installer_app.lua", "-- mock app")
        writeFile(testCoreDir .. "/modules/manifest.lua", "-- mock manifest")

        local ctx = { scriptDir = testCoreDir, runningPath = testCoreDir .. "/installer.lua", mode = "direct_root" }
        local resolved = bootstrapper.resolveLocalCoreDir(ctx, fs)
        assert_eq(resolved, testCoreDir)

        local ctxEmpty = { scriptDir = sdk.temp_path("nonexistent_core_dir"), runningPath = "nonexistent/installer.lua", mode = "direct_root" }
        local noDir = bootstrapper.resolveLocalCoreDir(ctxEmpty, fs)
        assert_eq(noDir, nil)

        local pcRoot = sdk.temp_path("pc_root_local")
        fs.makeDir(pcRoot)

        local failHttp = {
            get = function()
                error("HTTP must not be called when local core exists")
            end
        }

        local runnerCalled = false
        local appRunner = function(opts)
            runnerCalled = true
            return true, nil
        end

        local ok, err = bootstrapper.bootstrapAndRun({
            runningProgram = testCoreDir .. "/installer.lua",
            targetRoot = pcRoot,
            localCoreDir = testCoreDir,
            http = failHttp,
            appRunner = appRunner,
            fs = fs,
        })

        assert_true(ok)
        assert_true(runnerCalled)
    end)
end)
