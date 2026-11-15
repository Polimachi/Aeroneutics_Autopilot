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

        -- Submodule helper and /lib shared helper
        fs.makeDir(bootRoot .. "/lib")
        local subHelperPath = bootRoot .. "/modules/sub_helper.lua"
        local sh = fs.open(subHelperPath, "w")
        sh.write("return { tag = \"OK_SUB\" }")
        sh.close()

        local libHelperPath = bootRoot .. "/lib/avionics_sensors.lua"
        local lh = fs.open(libHelperPath, "w")
        lh.write("return { VERSION = \"1.0.0\" }")
        lh.close()

        -- Target main.lua
        local mainPath = bootRoot .. "/main.lua"
        local mh = fs.open(mainPath, "w")
        mh.write("local h = require(\"sub_helper\"); local s = require(\"avionics_sensors\"); local a = {...}; _G.__BOOT_TEST_OUT = h.tag .. \":\" .. s.VERSION .. \":\" .. tostring(a[1])")
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
        assert_eq(_G.__BOOT_TEST_OUT, "OK_SUB:1.0.0:--daemon")

        -- Remove hook
        local okRemove = startup_generator.removeHook("/startup/00_fcp.lua", bootRoot)
        assert_true(okRemove, "removeHook should succeed")
        assert_false(fs.exists(expectedHookPath), "Hook file should be deleted")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)

    it("handles syntax/load error rollback, restores backup, cleans pending, writes rollback record, and invokes reboot", function()
        local bootRoot = sdk.temp_path("boot_ota_loaderr")
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
        fs.makeDir(bootRoot)
        fs.makeDir(bootRoot .. "/startup")
        fs.makeDir(bootRoot .. "/modules")

        local backupDir = bootRoot .. "/ota_backup/tx-101"
        fs.makeDir(backupDir)

        -- Backup original main.lua
        local origMainPath = backupDir .. "/main.lua"
        local bh = fs.open(origMainPath, "w")
        bh.write("_G.__OTA_TEST_STAGE = 'RESTORED_MAIN'")
        bh.close()

        -- Backup version file
        local versionBakPath = backupDir .. "/.version.json"
        local vbh = fs.open(versionBakPath, "w")
        vbh.write(textutils.serializeJSON({ version = "1.12.0" }))
        vbh.close()

        -- Target main.lua with broken syntax
        local targetPath = bootRoot .. "/main.lua"
        local th = fs.open(targetPath, "w")
        th.write("this is invalid lua syntax !!! @@ ##")
        th.close()

        -- Active version file (updated by OTA)
        local curVersionPath = bootRoot .. "/.version.json"
        local cvh = fs.open(curVersionPath, "w")
        cvh.write(textutils.serializeJSON({ version = "1.13.0-uncommitted" }))
        cvh.close()

        -- Orphan file created by failed OTA (existed = false)
        local orphanPath = bootRoot .. "/modules/orphan.lua"
        local oh = fs.open(orphanPath, "w")
        oh.write("return 'orphan'")
        oh.close()

        -- Write /.ota_pending.json
        local pending = {
            txId = "tx-101",
            moduleId = "tca",
            targetVersion = "1.13.0",
            backupDir = backupDir,
            versionBackupPath = versionBakPath,
            restoredFiles = {
                { src = origMainPath, dest = targetPath, existed = true },
                { src = "", dest = orphanPath, existed = false },
            },
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        }
        local ph = fs.open(bootRoot .. "/.ota_pending.json", "w")
        ph.write(textutils.serializeJSON(pending))
        ph.close()

        local spec = {
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = targetPath,
            installDir = bootRoot,
            otaRootPrefix = bootRoot,
        }
        local okInstall, errInstall = startup_generator.installHook(spec, bootRoot)
        assert_true(okInstall, "installHook should succeed: " .. tostring(errInstall))

        local hookPath = bootRoot .. "/startup/00_tca.lua"
        assert_true(fs.exists(hookPath), "Hook file must exist")

        -- Mock os.reboot
        local origReboot = os.reboot
        local rebootCount = 0
        os.reboot = function()
            rebootCount = rebootCount + 1
        end

        _G.__OTA_TEST_STAGE = nil
        local okRun, runErr = pcall(dofile, hookPath)
        os.reboot = origReboot

        assert_true(okRun, "dofile should not throw unhandled error on rollback: " .. tostring(runErr))
        assert_eq(rebootCount, 1, "os.reboot should have been invoked exactly once")

        -- Verify pending removed
        assert_false(fs.exists(bootRoot .. "/.ota_pending.json"), "pending transaction must be deleted")

        -- Verify rollback record written
        local rollbackPath = bootRoot .. "/.ota_rollback.json"
        assert_true(fs.exists(rollbackPath), "rollback record must exist")
        local rh = fs.open(rollbackPath, "r")
        local rollbackData = textutils.unserializeJSON(rh.readAll())
        rh.close()
        assert_eq(rollbackData.txId, "tx-101")
        assert_eq(rollbackData.moduleId, "tca")
        assert_eq(rollbackData.targetVersion, "1.13.0")
        assert_eq(rollbackData.reason, "BOOT_LOAD_ERROR")
        assert_true(rollbackData.error ~= nil, "error message must be recorded")

        -- Verify original main.lua restored
        local rmh = fs.open(targetPath, "r")
        local mainContent = rmh.readAll()
        rmh.close()
        assert_eq(mainContent, "_G.__OTA_TEST_STAGE = 'RESTORED_MAIN'")

        -- Verify orphan file deleted
        assert_false(fs.exists(orphanPath), "newly added orphan file must be deleted")

        -- Verify version restored
        local rvh = fs.open(curVersionPath, "r")
        local restoredVersion = textutils.unserializeJSON(rvh.readAll())
        rvh.close()
        assert_eq(restoredVersion.version, "1.12.0")

        -- Verify backupDir deleted
        assert_false(fs.exists(backupDir), "backupDir must be cleaned up")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)

    it("handles runtime crash rollback, restores backup, cleans pending, writes rollback record, and invokes reboot", function()
        local bootRoot = sdk.temp_path("boot_ota_runtime_crash")
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
        fs.makeDir(bootRoot)
        fs.makeDir(bootRoot .. "/startup")

        local backupDir = bootRoot .. "/ota_backup/tx-102"
        fs.makeDir(backupDir)

        -- Backup original main.lua
        local origMainPath = backupDir .. "/main.lua"
        local bh = fs.open(origMainPath, "w")
        bh.write("_G.__OTA_TEST_STAGE = 'RESTORED_MAIN_RUNTIME'")
        bh.close()

        -- Target main.lua with runtime crash
        local targetPath = bootRoot .. "/main.lua"
        local th = fs.open(targetPath, "w")
        th.write("error('nil deref in tca controller')")
        th.close()

        -- Write /.ota_pending.json
        local pending = {
            txId = "tx-102",
            moduleId = "tca",
            targetVersion = "1.13.0",
            backupDir = backupDir,
            restoredFiles = {
                { src = origMainPath, dest = targetPath, existed = true },
            },
            bootAttempts = 0,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        }
        local ph = fs.open(bootRoot .. "/.ota_pending.json", "w")
        ph.write(textutils.serializeJSON(pending))
        ph.close()

        local spec = {
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = targetPath,
            installDir = bootRoot,
            otaRootPrefix = bootRoot,
        }
        local okInstall, errInstall = startup_generator.installHook(spec, bootRoot)
        assert_true(okInstall, "installHook should succeed: " .. tostring(errInstall))

        local hookPath = bootRoot .. "/startup/00_tca.lua"

        -- Mock os.reboot
        local origReboot = os.reboot
        local rebootCount = 0
        os.reboot = function()
            rebootCount = rebootCount + 1
        end

        local okRun, runErr = pcall(dofile, hookPath)
        os.reboot = origReboot

        assert_true(okRun, "dofile should not throw unhandled error on rollback: " .. tostring(runErr))
        assert_eq(rebootCount, 1, "os.reboot should have been invoked exactly once")

        -- Verify pending removed
        assert_false(fs.exists(bootRoot .. "/.ota_pending.json"), "pending transaction must be deleted")

        -- Verify rollback record written
        local rollbackPath = bootRoot .. "/.ota_rollback.json"
        assert_true(fs.exists(rollbackPath), "rollback record must exist")
        local rh = fs.open(rollbackPath, "r")
        local rollbackData = textutils.unserializeJSON(rh.readAll())
        rh.close()
        assert_eq(rollbackData.txId, "tx-102")
        assert_eq(rollbackData.moduleId, "tca")
        assert_eq(rollbackData.reason, "BOOT_RUNTIME_CRASH")
        assert_true(rollbackData.error ~= nil and rollbackData.error:find("nil deref") ~= nil, "error message must contain crash reason")

        -- Verify original main.lua restored
        local rmh = fs.open(targetPath, "r")
        local mainContent = rmh.readAll()
        rmh.close()
        assert_eq(mainContent, "_G.__OTA_TEST_STAGE = 'RESTORED_MAIN_RUNTIME'")

        -- Verify backupDir deleted
        assert_false(fs.exists(backupDir), "backupDir must be cleaned up")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)

    it("handles pre-commit reboot loop timeout, restores backup before run, and executes restored target cleanly without reboot", function()
        local bootRoot = sdk.temp_path("boot_ota_timeout")
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
        fs.makeDir(bootRoot)
        fs.makeDir(bootRoot .. "/startup")

        local backupDir = bootRoot .. "/ota_backup/tx-103"
        fs.makeDir(backupDir)

        -- Backup original main.lua that executes cleanly
        local origMainPath = backupDir .. "/main.lua"
        local bh = fs.open(origMainPath, "w")
        bh.write("_G.__OTA_TEST_STAGE = 'WATCHDOG_TIMEOUT_RECOVERED'")
        bh.close()

        -- Target main.lua has crashing code (would fail if executed)
        local targetPath = bootRoot .. "/main.lua"
        local th = fs.open(targetPath, "w")
        th.write("error('broken target code should not execute')")
        th.close()

        -- Write /.ota_pending.json with bootAttempts = 1, maxBootAttempts = 1
        local pending = {
            txId = "tx-103",
            moduleId = "tca",
            targetVersion = "1.13.0",
            backupDir = backupDir,
            restoredFiles = {
                { src = origMainPath, dest = targetPath, existed = true },
            },
            bootAttempts = 1,
            maxBootAttempts = 1,
            status = "PENDING_COMMIT",
        }
        local ph = fs.open(bootRoot .. "/.ota_pending.json", "w")
        ph.write(textutils.serializeJSON(pending))
        ph.close()

        local spec = {
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = targetPath,
            installDir = bootRoot,
            otaRootPrefix = bootRoot,
        }
        local okInstall, errInstall = startup_generator.installHook(spec, bootRoot)
        assert_true(okInstall, "installHook should succeed: " .. tostring(errInstall))

        local hookPath = bootRoot .. "/startup/00_tca.lua"

        -- Mock os.reboot
        local origReboot = os.reboot
        local rebootCount = 0
        os.reboot = function()
            rebootCount = rebootCount + 1
        end

        _G.__OTA_TEST_STAGE = nil
        local okRun, runErr = pcall(dofile, hookPath)
        os.reboot = origReboot

        assert_true(okRun, "dofile should succeed: " .. tostring(runErr))
        assert_eq(rebootCount, 0, "os.reboot must NOT be invoked when timeout rolls back prior to target run")
        assert_eq(_G.__OTA_TEST_STAGE, "WATCHDOG_TIMEOUT_RECOVERED", "restored target must have executed cleanly")

        -- Verify pending removed
        assert_false(fs.exists(bootRoot .. "/.ota_pending.json"), "pending transaction must be deleted")

        -- Verify rollback record written
        local rollbackPath = bootRoot .. "/.ota_rollback.json"
        assert_true(fs.exists(rollbackPath), "rollback record must exist")
        local rh = fs.open(rollbackPath, "r")
        local rollbackData = textutils.unserializeJSON(rh.readAll())
        rh.close()
        assert_eq(rollbackData.txId, "tx-103")
        assert_eq(rollbackData.reason, "BOOT_WATCHDOG_TIMEOUT")

        -- Verify backupDir deleted
        assert_false(fs.exists(backupDir), "backupDir must be cleaned up")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)

    it("preserves normal boot behavior when /.ota_pending.json is absent", function()
        local bootRoot = sdk.temp_path("boot_ota_normal")
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
        fs.makeDir(bootRoot)
        fs.makeDir(bootRoot .. "/startup")

        local targetPath = bootRoot .. "/main.lua"
        local th = fs.open(targetPath, "w")
        th.write("_G.__OTA_TEST_STAGE = 'NORMAL_BOOT_SUCCESS'")
        th.close()

        local spec = {
            path = "/startup/00_tca.lua",
            name = "TCA",
            target = targetPath,
            installDir = bootRoot,
            otaRootPrefix = bootRoot,
        }
        local okInstall, errInstall = startup_generator.installHook(spec, bootRoot)
        assert_true(okInstall, "installHook should succeed: " .. tostring(errInstall))

        local hookPath = bootRoot .. "/startup/00_tca.lua"

        local origReboot = os.reboot
        local rebootCount = 0
        os.reboot = function()
            rebootCount = rebootCount + 1
        end

        _G.__OTA_TEST_STAGE = nil
        local okRun, runErr = pcall(dofile, hookPath)
        os.reboot = origReboot

        assert_true(okRun, "dofile should succeed: " .. tostring(runErr))
        assert_eq(rebootCount, 0, "os.reboot must not be invoked during normal boot")
        assert_eq(_G.__OTA_TEST_STAGE, "NORMAL_BOOT_SUCCESS")
        assert_false(fs.exists(bootRoot .. "/.ota_pending.json"), "no pending file should exist")
        assert_false(fs.exists(bootRoot .. "/.ota_rollback.json"), "no rollback file should exist")

        -- Clean up
        if fs.exists(bootRoot) then fs.delete(bootRoot) end
    end)
end)
