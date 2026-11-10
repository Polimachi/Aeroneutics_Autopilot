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
        assert_eq(#modules, 12)

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

    it("computes 12-row viewport window and scrolls smoothly when items exceed 12 rows", function()
        local f1, l1, s1 = tui_view.computeViewport(15, 1, 12, 0)
        assert_eq(f1, 1)
        assert_eq(l1, 12)
        assert_eq(s1, 0)

        local f2, l2, s2 = tui_view.computeViewport(15, 14, 12, s1)
        assert_eq(f2, 3)
        assert_eq(l2, 14)
        assert_eq(s2, 2)

        local f3, l3, s3 = tui_view.computeViewport(15, 15, 12, s2)
        assert_eq(f3, 4)
        assert_eq(l3, 15)
        assert_eq(s3, 3)

        local f4, l4, s4 = tui_view.computeViewport(15, 2, 12, s3)
        assert_eq(f4, 2)
        assert_eq(l4, 13)
        assert_eq(s4, 1)
    end)

    it("renders category folder menu, clears ghost rows on folder transition, and scrolls >12 modules within 51x19 bounds", function()
        local categories = manifest.listCategories()
        assert_eq(#categories, 5)

        local termColor = mock.term(51, 19)
        local installedMap = {
            gps_server = { version = "2.2.0" },
            gcs = { version = "1.0.0" },
        }
        local catScroll = tui_view.renderCategoryMenu(termColor, categories, 2, "github", installedMap, 0)
        assert_eq(catScroll, 0)
        assert_true(termColor:_contains("[DIR] 0_infra"))
        assert_true(termColor:_contains("[2/6 inst]"))
        assert_true(termColor:_contains("[Enter] Open Folder"))
        assert_true(termColor:_contains("3_planning"))

        -- Switch to a 1-module folder (2_guidance -> FCP) and verify ghost rows are cleared
        local guidanceCat = categories[4]
        local modScroll = tui_view.renderMenu(termColor, guidanceCat.modules, 1, "github", {}, guidanceCat, 0)
        assert_eq(modScroll, 0)
        assert_true(termColor:_contains("FCP"))
        assert_true(termColor:_contains("Folder: 2_guidance"))
        assert_true(termColor:_contains("[Bksp/B] Folders"))
        assert_false(termColor:_contains("3_planning"), "stale category row must be cleared")
        assert_false(termColor:_contains("[2/6 inst]"), "stale category counter must be cleared")

        -- Verify >12 module list scrolls smoothly within rows 4..15
        local syntheticMods = {}
        for i = 1, 15 do
            syntheticMods[i] = {
                id = string.format("mod_%02d", i),
                name = string.format("MOD_%02d", i),
                version = "1.0.0",
            }
        end
        local scrollOut = tui_view.renderMenu(
            termColor,
            syntheticMods,
            15,
            "github",
            {},
            { id = "infra", code = "0_infra", name = "Ground Infrastructure" },
            0
        )
        assert_eq(scrollOut, 3)
        assert_true(termColor:_contains("MOD_15"))
        assert_true(termColor:_contains("[4-15 of 15]"))
        assert_false(termColor:_contains("MOD_01"), "top item must scroll out of 12-row viewport")

        -- Incremental cursor delta inside active viewport vs scroll-crossing full render fallback
        local termDelta = mock.term(51, 19)
        local s0 = tui_view.renderMenu(termDelta, syntheticMods, 1, "github", {}, { id = "infra", code = "0_infra", name = "Ground Infrastructure" }, 0)
        assert_eq(s0, 0)
        tui_view.renderMessage(termDelta, "info", "Temporary status")
        assert_true(tui_view.updateSelection(termDelta, syntheticMods, 1, 2, 0, {}, false, true))
        assert_true(termDelta:_contains("> MOD_02"))
        assert_true(termDelta:_contains("  MOD_01"))
        assert_false(termDelta:_contains("Temporary status"), "status row must be cleared on cursor move")
        assert_false(tui_view.updateSelection(termDelta, syntheticMods, 12, 13, 0, {}, false, false), "crossing bottom edge requires full viewport scroll")
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

    it("drives 2-level interactive TUI folder navigation (Category -> Open Folder -> Install -> Backspace to Category -> Quit)", function()
        local appRoot = sdk.temp_path("installer_tui_interactive_root")
        fs.makeDir(appRoot)

        local events = {
            { "char", "s" },   -- toggle to GDrive
            { "char", "s" },   -- toggle back to GitHub
            { "key", 208 },    -- Down -> 0_infra (#2)
            { "key", 208 },    -- Down -> 1_control (#3)
            { "key", 28 },     -- Enter -> open 1_control folder ([1] vas, [2] tca)
            { "key", 208 },    -- Down -> tca (#2)
            { "key", 28 },     -- Enter -> confirm install tca
            { "char", "y" },   -- confirm install
            { "key", 14 },     -- Backspace -> return to CATEGORY_MENU
            { "char", "q" },   -- Quit from CATEGORY_MENU
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

        -- Module "tca" selected inside 1_control folder and installed
        assert_true(fs.exists(appRoot .. "/main.lua"))
        assert_true(fs.exists(appRoot .. "/startup/00_tca.lua"))
        local meta = version_registry.load(appRoot .. "/.version.json")
        assert_not_nil(meta.modules.tca)

        -- Returning to CATEGORY_MENU preserves parent selection and shows updated [1/2 inst]
        assert_true(termMock:_contains("[DIR] 1_control"))
        assert_true(termMock:_contains("[1/2 inst]"))
    end)

    it("supports uninstalling an installed module inside a category folder and navigating back via [B] key", function()
        local appRoot = sdk.temp_path("installer_tui_uninstall_root")
        fs.makeDir(appRoot .. "/startup")

        -- Pre-seed installed gcs fixture on disk to keep the TUI uninstall test focused on navigation and removal
        local hMain = fs.open(appRoot .. "/main.lua", "w")
        hMain.write("-- dummy gcs code")
        hMain.close()
        local hHook = fs.open(appRoot .. "/startup/00_gcs.lua", "w")
        hHook.write("-- gcs hook")
        hHook.close()
        local hMeta = fs.open(appRoot .. "/.version.json", "w")
        hMeta.write(textutils.serializeJSON({
            installerVersion = "1.1.0",
            modules = {
                gcs = {
                    id = "gcs",
                    version = "1.0.0",
                    files = { "/main.lua" },
                    source = "github",
                    installedAt = 1000,
                },
            },
        }))
        hMeta.close()

        local events = {
            { "key", 208 },    -- Down -> 0_infra (#2)
            { "key", 205 },    -- Right -> open 0_infra folder (6 modules, gcs is #6)
            { "key", 208 },    -- #2 gps_node
            { "key", 208 },    -- #3 gps_client
            { "key", 208 },    -- #4 gac
            { "key", 208 },    -- #5 landing_pad
            { "key", 208 },    -- #6 gcs
            { "char", "u" },   -- prompt uninstall gcs
            { "char", "y" },   -- confirm uninstall
            { "char", "b" },   -- return to CATEGORY_MENU
            { "char", "q" },   -- quit
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

        local termMock = mock.term(51, 19)
        local ok, err = installer_app.run({
            targetRoot = appRoot,
            term = termMock,
            pullEvent = pullSyntheticEvent,
        })

        assert_true(ok)
        assert_nil(err)
        assert_false(fs.exists(appRoot .. "/main.lua"))
        assert_false(fs.exists(appRoot .. "/startup/00_gcs.lua"))
        local meta = version_registry.load(appRoot .. "/.version.json")
        assert_nil(meta.modules.gcs)
        assert_true(termMock:_contains("[DIR] 0_infra"))
        assert_true(termMock:_contains("[0/6 inst]"))
    end)

    it("handles [U] guard on uninstalled modules, Backspace cancel, Left return, and custom stub fallback", function()
        local appRoot = sdk.temp_path("installer_tui_edges_root")
        fs.makeDir(appRoot)

        local events = {
            { "key", 28 },    -- Enter first folder (0_development)
            { "char", "u" },  -- Not installed -> warn message on row h
            { "key", 28 },    -- Enter -> CONFIRM_INSTALL
            { "key", 14 },    -- Backspace -> cancel confirm
            { "key", 203 },   -- Left -> return to CATEGORY_MENU
            { "key", 16 },    -- Key Q -> quit
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

        local termMock = mock.term(51, 19)
        local ok, err = installer_app.run({
            targetRoot = appRoot,
            term = termMock,
            pullEvent = pullSyntheticEvent,
        })

        assert_true(ok)
        assert_nil(err)
        assert_true(termMock:_contains("[DIR] 0_development"))

        -- Custom manifest stub without listCategories falls back to single "All Modules" folder
        local stubEvents = { { "key", 16 } }
        local sIdx = 0
        local okStub, errStub = installer_app.run({
            targetRoot = appRoot,
            term = mock.term(51, 19),
            manifest = {
                listModules = function()
                    return { { id = "tca", name = "TCA", version = "1.9.1" } }
                end,
            },
            pullEvent = function()
                sIdx = sIdx + 1
                local ev = stubEvents[sIdx]
                if ev then return ev[1], ev[2] end
                return nil
            end,
        })
        assert_true(okStub)
        assert_nil(errStub)
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
