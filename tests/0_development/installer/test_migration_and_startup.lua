-- tests/0_development/installer/test_migration_and_startup.lua
local migration_engine = require("migration_engine")
local startup_generator = require("startup_generator")

describe("migration_engine deepMerge and migrateFile", function()
    it("recursively preserves nested user overrides at depth >= 3 while backfilling missing keys", function()
        local existing = {
            channels = {
                baseChannel = 10040,
            },
            ports = {
                apiSides = { "front" },
            },
            telemetry = {
                nested = {
                    level3 = {
                        customRate = 50,
                    },
                },
            },
        }

        local defaults = {
            channels = {
                baseChannel = 10000,
                bandwidth = 40,
                gpsPingChannel = 60001,
            },
            ports = {
                modemSide = "top",
                apiSides = { "left", "right" },
            },
            telemetry = {
                nested = {
                    level3 = {
                        customRate = 10,
                        defaultRate = 20,
                    },
                },
            },
        }

        -- Deep copies to verify immutability
        local existingCopy = textutils.unserializeJSON(textutils.serializeJSON(existing))
        local defaultsCopy = textutils.unserializeJSON(textutils.serializeJSON(defaults))

        local merged = migration_engine.deepMerge(existing, defaults)

        -- 1. Assert channel overrides and backfilled keys
        assert_eq(merged.channels.baseChannel, 10040)
        assert_eq(merged.channels.bandwidth, 40)
        assert_eq(merged.channels.gpsPingChannel, 60001)

        -- 2. Assert port overrides and array replacement (not index-merged)
        assert_eq(merged.ports.modemSide, "top")
        assert_deep_eq(merged.ports.apiSides, { "front" })

        -- 3. Assert depth >= 3 preservation
        assert_eq(merged.telemetry.nested.level3.customRate, 50)
        assert_eq(merged.telemetry.nested.level3.defaultRate, 20)

        -- 4. Assert input immutability
        assert_deep_eq(existing, existingCopy)
        assert_deep_eq(defaults, defaultsCopy)
    end)

    it("migrates missing and existing JSON config files atomically", function()
        local cfgPath = sdk.temp_path("test_config.json")
        local tmpPath = cfgPath .. ".tmp"

        local initialDefaults = {
            version = "1.0.0",
            settings = {
                timeout = 500,
                mode = "AUTO",
                tags = { "primary", "vtol" },
            },
        }

        -- Run 1: Missing file -> creates new file from defaults
        local ok1, cfg1, err1 = migration_engine.migrateFile(cfgPath, initialDefaults)
        assert_true(ok1, "migrateFile should succeed for missing file: " .. tostring(err1))
        assert_nil(err1)
        assert_deep_eq(cfg1, initialDefaults)
        assert_true(fs.exists(cfgPath), "Destination config file must exist")
        assert_false(fs.exists(tmpPath), "No temporary .tmp file should remain")

        -- User customizes the config
        cfg1.settings.timeout = 800
        cfg1.settings.tags = { "secondary" }
        local h = fs.open(cfgPath, "w")
        h.write(textutils.serializeJSON(cfg1))
        h.close()

        -- Run 2: Existing customized file + updated schema defaults
        local updatedDefaults = {
            version = "1.1.0",
            settings = {
                timeout = 500,
                mode = "AUTO",
                retryCount = 3,
                tags = { "primary", "vtol" },
            },
        }

        local ok2, cfg2, err2 = migration_engine.migrateFile(cfgPath, updatedDefaults)
        assert_true(ok2, "migrateFile should succeed for existing file: " .. tostring(err2))
        assert_nil(err2)
        assert_false(fs.exists(tmpPath), "No temporary .tmp file should remain on second run")

        -- Verify customizations preserved and new keys backfilled
        assert_eq(cfg2.settings.timeout, 800)
        assert_deep_eq(cfg2.settings.tags, { "secondary" })
        assert_eq(cfg2.settings.retryCount, 3)
        assert_eq(cfg2.settings.mode, "AUTO")
    end)
end)

describe("startup_generator multi-boot hook generator", function()
    it("resolves target paths and handles absolute vs relative specifications cleanly", function()
        assert_eq(startup_generator.resolveTargetPath("/", "/startup/00_fcp.lua"), "/startup/00_fcp.lua")
        assert_eq(startup_generator.resolveTargetPath("/", "startup/00_fcp.lua"), "/startup/00_fcp.lua")
        assert_eq(startup_generator.resolveTargetPath("/_tmp/boot_root", "/startup/00_fcp.lua"), "/_tmp/boot_root/startup/00_fcp.lua")
        assert_eq(startup_generator.resolveTargetPath("/_tmp/boot_root", "startup/00_fcp.lua"), "/_tmp/boot_root/startup/00_fcp.lua")
        assert_eq(startup_generator.resolveTargetPath("/_tmp/boot_root", "/_tmp/boot_root/main.lua"), "/_tmp/boot_root/main.lua")
        assert_eq(startup_generator.resolveTargetPath("/_tmp/boot_root", "/"), "/_tmp/boot_root")
    end)

    it("executes generated startup hook with bare submodule require and forwards daemon args", function()
        local bootRoot = sdk.temp_path("boot_root")
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
        fs.makeDir(bootRoot)
        fs.makeDir(bootRoot .. "/modules")
        fs.makeDir(bootRoot .. "/startup")

        -- Submodule helper
        local subHelperPath = bootRoot .. "/modules/sub_helper.lua"
        local sh = fs.open(subHelperPath, "w")
        sh.write("return { tag = \"OK_SUB\" }")
        sh.close()

        -- Target main.lua
        local mainPath = bootRoot .. "/main.lua"
        local mh = fs.open(mainPath, "w")
        mh.write("local h = require(\"sub_helper\"); local a = {...}; _G.__BOOT_TEST_OUT = h.tag .. \":\" .. tostring(a[1])")
        mh.close()

        -- Install hook
        local spec = {
            path = "/startup/00_fcp.lua",
            name = "FCP",
            target = mainPath,
            installDir = bootRoot,
            args = { "--daemon" },
        }

        local okInstall, errInstall = startup_generator.installHook(spec, bootRoot)
        assert_true(okInstall, "installHook should succeed: " .. tostring(errInstall))
        assert_nil(errInstall)

        local expectedHookPath = bootRoot .. "/startup/00_fcp.lua"
        assert_true(fs.exists(expectedHookPath), "Hook file must exist at " .. expectedHookPath)
        assert_false(fs.exists(bootRoot .. "/startup.lua"), "Sibling /startup.lua must not be created or overwritten")

        -- Execute the generated hook
        _G.__BOOT_TEST_OUT = nil
        dofile(expectedHookPath)
        assert_eq(_G.__BOOT_TEST_OUT, "OK_SUB:--daemon")

        -- Remove hook
        local okRemove = startup_generator.removeHook("/startup/00_fcp.lua", bootRoot)
        assert_true(okRemove, "removeHook should succeed")
        assert_false(fs.exists(expectedHookPath), "Hook file should be deleted")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)
end)
