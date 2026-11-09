-- tests/0_development/installer/test_manifest_and_registry.lua
local manifest = require("manifest")
local version_registry = require("version_registry")

describe("manifest dual-source module definitions", function()
    it("registers all 12 modules in deterministic order with shared /lib/avionics_sensors.lua bundling", function()
        local list = manifest.listModules()
        assert_eq(#list, 12)
        assert_eq(list[1].id, "vas")
        assert_eq(list[2].id, "tca")
        assert_eq(list[3].id, "fcp")
        assert_eq(list[4].id, "alignment")
        assert_eq(list[5].id, "gps_server")
        assert_eq(list[6].id, "gps_node")
        assert_eq(list[7].id, "gps_client")
        assert_eq(list[8].id, "sensors")
        assert_eq(list[9].id, "gac")
        assert_eq(list[10].id, "landing_pad")
        assert_eq(list[11].id, "amm")
        assert_eq(list[12].id, "gcs")

        assert_not_nil(manifest.SHARED_LIBS)
        assert_not_nil(manifest.SHARED_LIBS.avionics_sensors)
        assert_eq(manifest.SHARED_LIBS.avionics_sensors.repoPath, "src/0_development/sensors/avionics_sensors.lua")
        assert_eq(manifest.SHARED_LIBS.avionics_sensors.dest, "/lib/avionics_sensors.lua")

        -- Every module must deploy /lib/avionics_sensors.lua
        for _, mod in ipairs(list) do
            local foundShared = false
            for _, f in ipairs(mod.files) do
                if f.dest == "/lib/avionics_sensors.lua" and f.repoPath == "src/0_development/sensors/avionics_sensors.lua" then
                    foundShared = true
                    break
                end
            end
            assert_true(foundShared, "Module " .. tostring(mod.id) .. " missing /lib/avionics_sensors.lua")
        end

        local fcp = manifest.getModule("fcp")
        assert_eq(fcp.installDir, "/")
        assert_true(fcp.startup.enabled)
        assert_eq(fcp.startup.path, "/startup/00_fcp.lua")
        assert_eq(fcp.startup.args[1], "--daemon")

        local gpsClient = manifest.getModule("gps_client")
        assert_false(gpsClient.startup.enabled)

        local sensorsMod = manifest.getModule("sensors")
        assert_false(sensorsMod.startup.enabled)
    end)

    it("resolves GitHub raw URLs and handles configured vs unconfigured Google Drive IDs", function()
        local entry = { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = nil }
        local ghUrl, ghErr = manifest.resolveUrl("github", entry)
        assert_nil(ghErr)
        assert_eq(ghUrl, "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/1_control/vas/main.lua")

        local gdNil, gdErr = manifest.resolveUrl("gdrive", entry)
        assert_nil(gdNil)
        assert_eq(gdErr, "GDRIVE_ID_UNCONFIGURED")

        local gdOk, gdOkErr = manifest.resolveUrl("gdrive", entry, { ["src/1_control/vas/main.lua"] = "1AbCdEfGhIjKlMnOp" })
        assert_nil(gdOkErr)
        assert_eq(gdOk, "https://drive.usercontent.google.com/download?id=1AbCdEfGhIjKlMnOp&export=download&confirm=t")
    end)

    it("exposes manifest constants and bootstrap file definitions", function()
        assert_eq(manifest.VERSION, "1.0.0")
        assert_eq(manifest.SOURCES.GITHUB, "github")
        assert_eq(manifest.SOURCES.GDRIVE, "gdrive")
        assert_eq(#manifest.BOOTSTRAP_FILES, 7)
        assert_eq(version_registry.DEFAULT_META_PATH, "/.version.json")
    end)

    it("exposes ADVANCED_VTOL airframe preset and files in manifest", function()
        local advPreset = manifest.getAirframePreset("ADVANCED_VTOL")
        assert_not_nil(advPreset)
        assert_eq(advPreset.airframeType, "ADVANCED_VTOL")
        assert_eq(advPreset.configTemplate.system.airframeType, "ADVANCED_VTOL")

        local list = manifest.listAirframePresets()
        assert_true(#list >= 2)

        local fcp = manifest.getModule("fcp")
        local foundAdvDriver = false
        for _, f in ipairs(fcp.files) do
            if f.dest == "/modules/advanced_vtol_driver.lua" then
                foundAdvDriver = true
                break
            end
        end
        assert_true(foundAdvDriver, "fcp missing advanced_vtol_driver.lua")
    end)
end)

describe("version_registry /.version.json persistence and multi-module orphan safety", function()
    it("saves atomically, detects single-module orphans, and protects files shared with co-installed modules", function()
        local metaPath = sdk.temp_path(".version.json")
        local meta = version_registry.load(metaPath)
        assert_deep_eq(meta.modules, {})

        version_registry.recordInstall(meta, "gps_server", "2.2.0", {
            "/gps/server.lua",
            "/gps/modules/protocol.lua",
            "/gps/modules/old_legacy.lua",
        }, "github", 1000)
        version_registry.recordInstall(meta, "gps_client", "2.2.0", {
            "/apis/gps_client.lua",
            "/gps/modules/protocol.lua",
        }, "github", 1005)

        local okSave = version_registry.save(metaPath, meta)
        assert_true(okSave)

        local reloaded = version_registry.load(metaPath)
        -- Upgrading gps_server drops protocol.lua and old_legacy.lua from gps_server's list,
        -- but protocol.lua is still owned by gps_client so ONLY old_legacy.lua may be orphaned!
        local orphans = version_registry.getOrphanFiles(reloaded, "gps_server", { "/gps/server.lua" })
        assert_deep_eq(orphans, { "/gps/modules/old_legacy.lua" })
    end)

    it("isolates per-module file lists in /.version.json when co-installing gps_client alongside fcp", function()
        local meta = version_registry.load("/_nonexistent_version.json")
        version_registry.recordInstall(meta, "fcp", "1.11.0", { "/main.lua", "/fcp_runtime.lua" }, "github", 2000)
        local clientOrphans = version_registry.getOrphanFiles(meta, "gps_client", { "/apis/gps_client.lua" })
        assert_deep_eq(clientOrphans, {})
        local removable = version_registry.removeModule(meta, "fcp")
        assert_deep_eq(removable, { "/fcp_runtime.lua", "/main.lua" })
    end)

    it("protects shared files when removing a co-installed module", function()
        local meta = { modules = {} }
        version_registry.recordInstall(meta, "mod_a", "1.0.0", { "/shared.lua", "/a_only.lua" }, "github", 100)
        version_registry.recordInstall(meta, "mod_b", "1.0.0", { "/shared.lua", "/b_only.lua" }, "github", 200)

        local removedA = version_registry.removeModule(meta, "mod_a")
        assert_deep_eq(removedA, { "/a_only.lua" })
        assert_nil(meta.modules["mod_a"])
        assert_not_nil(meta.modules["mod_b"])

        local removedB = version_registry.removeModule(meta, "mod_b")
        assert_deep_eq(removedB, { "/b_only.lua", "/shared.lua" })
        assert_nil(meta.modules["mod_b"])
    end)
end)
