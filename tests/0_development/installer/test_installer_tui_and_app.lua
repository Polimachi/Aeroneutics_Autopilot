-- tests/0_development/installer/test_installer_tui_and_app.lua
-- Unit tests for 51x19 TUI View and Main Installer Application Controller

local manifest = require("manifest")
local version_registry = require("version_registry")
local tui_view = require("tui_view")
local installer_app = require("installer_app")

local function createMockHttp(routes, defaultHandler)
    local m = { _calls = {} }
    m.get = function(url, headers, binary)
        table.insert(m._calls, { url = url, headers = headers, binary = binary })
        local r = routes and routes[url]
        if type(r) == "function" then
            r = r(url, headers, binary)
        end
        if not r and defaultHandler then
            r = defaultHandler(url, headers, binary)
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
            readAll = function() return r.body or "-- content from " .. url end,
            close = function() end,
        }
        return handle
    end
    return m
end

local function readFile(path)
    if not fs.exists(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local c = h.readAll()
    h.close()
    return c
end

describe("tui_view 51x19 terminal rendering and source toggle", function()
    it("renders header, 7-module menu, progress bar, and source toggle within 51x19 bounds", function()
        -- 1. Source toggle logic
        assert_eq(tui_view.toggleSource("github"), "gdrive")
        assert_eq(tui_view.toggleSource("gdrive"), "github")
        assert_eq(tui_view.toggleSource("GITHUB"), "gdrive")
        assert_eq(tui_view.toggleSource("GDRIVE"), "github")

        local modules = manifest.listModules()
        assert_eq(#modules, 10)

        -- 2. Color terminal rendering
        local termColor = mock.term(51, 19)
        assert_true(termColor.isColor())

        tui_view.renderHeader(termColor, "Create: Aeronautics", "Installer", "github", "Root")
        assert_true(termColor:_contains("[GitHub]"))
        assert_true(termColor:_contains("Create: Aeronautics"))

        tui_view.renderMenu(termColor, modules, 1, "github", {})
        assert_true(termColor:_contains("[GitHub]"))
        for _, mod in ipairs(modules) do
            assert_true(termColor:_contains(mod.name))
        end

        tui_view.renderMenu(termColor, modules, 2, "gdrive", { tca = { version = "1.9.1" } })
        assert_true(termColor:_contains("[GDrive]"))
        assert_true(termColor:_contains("TCA"))

        tui_view.renderProgress(termColor, 4, 10, "/modules/core.lua", "github")
        assert_true(termColor:_contains("[GitHub]"))
        assert_true(termColor:_contains("4/10"))

        tui_view.renderMessage(termColor, "info", "Operation completed successfully")
        assert_true(termColor:_contains("Operation completed"))

        -- 3. Monochrome terminal rendering (isColor() == false)
        local termMono = mock.term(51, 19)
        termMono.isColor = function() return false end
        termMono.isColour = termMono.isColor

        tui_view.renderMenu(termMono, modules, 3, "gdrive", {})
        assert_true(termMono:_contains("[GDrive]"))
        for _, mod in ipairs(modules) do
            assert_true(termMono:_contains(mod.name))
        end
    end)
end)

describe("installer_app module installation and upgrade pipeline", function()
    it("installs module end-to-end, preserves user config, writes startup hook, cleans orphans, and updates /.version.json", function()
        local appRoot = sdk.temp_path("installer_app_test_root")
        fs.makeDir(appRoot .. "/modules")

        -- Pre-existing config.json
        local initialCfg = {
            schemaVersion = "1.2.0",
            groupId = "THR_CUSTOM_R",
            customSetting = "preserved_value",
        }
        local hCfg = fs.open(appRoot .. "/config.json", "w")
        hCfg.write(textutils.serializeJSON(initialCfg))
        hCfg.close()

        -- Pre-existing /.version.json with orphan
        local initialMeta = {
            installerVersion = "1.0.0",
            modules = {
                tca = {
                    id = "tca",
                    version = "1.0.0",
                    files = { "/main.lua", "/modules/legacy_old.lua" },
                    source = "github",
                    installedAt = 1000,
                },
            },
        }
        local hMeta = fs.open(appRoot .. "/.version.json", "w")
        hMeta.write(textutils.serializeJSON(initialMeta))
        hMeta.close()

        -- Pre-existing orphan file on disk
        local hOrphan = fs.open(appRoot .. "/modules/legacy_old.lua", "w")
        hOrphan.write("-- legacy old code")
        hOrphan.close()
        assert_true(fs.exists(appRoot .. "/modules/legacy_old.lua"))

        -- Mock HTTP serving TCA files
        local mockHttp = createMockHttp(nil, function(url)
            return { code = 200, body = "-- valid lua code for " .. url }
        end)

        local ok, installedFiles, err = installer_app.installModule("tca", {
            targetRoot = appRoot,
            source = "github",
            http = mockHttp,
        })

        assert_true(ok)
        assert_nil(err)
        assert_not_nil(installedFiles)
        assert_true(#installedFiles >= 9)

        -- 1. All TCA files downloaded
        assert_true(fs.exists(appRoot .. "/main.lua"))
        assert_true(fs.exists(appRoot .. "/modules/tca_daemon.lua"))
        assert_true(fs.exists(appRoot .. "/modules/config_manager.lua"))

        -- 2. User config preserved and backfilled
        local rawCfg = readFile(appRoot .. "/config.json")
        assert_not_nil(rawCfg)
        local mergedCfg = textutils.unserializeJSON(rawCfg)
        assert_eq(mergedCfg.groupId, "THR_CUSTOM_R")
        assert_eq(mergedCfg.customSetting, "preserved_value")
        assert_eq(mergedCfg.channels.thrustActuation, 10010)

        -- 3. Startup hook created
        assert_true(fs.exists(appRoot .. "/startup/00_tca.lua"))

        -- 4. Orphan removed
        assert_false(fs.exists(appRoot .. "/modules/legacy_old.lua"))

        -- 5. /.version.json updated
        local updatedMeta = version_registry.load(appRoot .. "/.version.json")
        assert_not_nil(updatedMeta.modules.tca)
        assert_eq(updatedMeta.modules.tca.version, "1.9.1")
        assert_eq(updatedMeta.modules.tca.source, "github")
    end)

    it("aborts before orphan cleanup or registry update when downloadBatch fails", function()
        local appRoot = sdk.temp_path("installer_app_abort_root")
        fs.makeDir(appRoot .. "/modules")

        -- Pre-existing orphan and metadata
        local initialMeta = {
            installerVersion = "1.0.0",
            modules = {
                tca = {
                    id = "tca",
                    version = "1.0.0",
                    files = { "/main.lua", "/modules/legacy_old.lua" },
                    source = "github",
                    installedAt = 1000,
                },
            },
        }
        local hMeta = fs.open(appRoot .. "/.version.json", "w")
        hMeta.write(textutils.serializeJSON(initialMeta))
        hMeta.close()

        local hOrphan = fs.open(appRoot .. "/modules/legacy_old.lua", "w")
        hOrphan.write("-- legacy preserved")
        hOrphan.close()

        -- Mock HTTP that fails
        local mockHttp = createMockHttp(nil, function(url)
            return { fail = true, error = "HTTP 500 Internal Server Error" }
        end)

        local ok, installedFiles, err = installer_app.installModule("tca", {
            targetRoot = appRoot,
            source = "github",
            http = mockHttp,
        })

        assert_false(ok)
        assert_nil(installedFiles)
        assert_not_nil(err)

        -- Pre-existing files must remain untouched
        assert_true(fs.exists(appRoot .. "/modules/legacy_old.lua"))
        local reloadedMeta = version_registry.load(appRoot .. "/.version.json")
        assert_eq(reloadedMeta.modules.tca.version, "1.0.0")
        assert_deep_eq(reloadedMeta.modules.tca.files, { "/main.lua", "/modules/legacy_old.lua" })
    end)

    it("drives interactive TUI key sequence ([S] toggle -> [S] toggle -> select -> Enter -> [Q] quit)", function()
        local appRoot = sdk.temp_path("installer_tui_interactive_root")
        fs.makeDir(appRoot)

        local events = {
            { "char", "s" },
            { "char", "s" },
            { "key", 208 },
            { "key", 28 },
            { "char", "y" },
            { "char", "q" },
        }
        local eventIdx = 0
        local function pullSyntheticEvent()
            eventIdx = eventIdx + 1
            if eventIdx <= #events then
                local ev = events[eventIdx]
                return ev[1], ev[2]
            end
            return nil
        end

        local mockHttp = createMockHttp(nil, function(url)
            return { code = 200, body = "-- dummy module code" }
        end)

        local termMock = mock.term(51, 19)

        local ok, err = installer_app.run({
            targetRoot = appRoot,
            http = mockHttp,
            term = termMock,
            pullEvent = pullSyntheticEvent,
        })

        assert_true(ok)
        assert_nil(err)

        -- Module 2 ("tca") selected and installed
        assert_true(fs.exists(appRoot .. "/main.lua"))
        assert_true(fs.exists(appRoot .. "/startup/00_tca.lua"))
        local meta = version_registry.load(appRoot .. "/.version.json")
        assert_not_nil(meta.modules.tca)
    end)

    it("executes non-interactive CLI install and uninstall commands", function()
        local appRoot = sdk.temp_path("installer_cli_root")
        fs.makeDir(appRoot)

        local mockHttp = createMockHttp(nil, function(url)
            return { code = 200, body = "-- cli code" }
        end)

        -- CLI install
        local okInst, errInst = installer_app.run({
            cliArgs = { "install", "tca", "--source", "github" },
            targetRoot = appRoot,
            http = mockHttp,
        })
        assert_true(okInst)
        assert_nil(errInst)
        assert_true(fs.exists(appRoot .. "/main.lua"))
        assert_true(fs.exists(appRoot .. "/startup/00_tca.lua"))

        -- CLI uninstall
        local okUninst, errUninst = installer_app.run({
            cliArgs = { "uninstall", "tca" },
            targetRoot = appRoot,
        })
        assert_true(okUninst)
        assert_nil(errUninst)
        assert_false(fs.exists(appRoot .. "/main.lua"))
        assert_false(fs.exists(appRoot .. "/startup/00_tca.lua"))
    end)
end)
