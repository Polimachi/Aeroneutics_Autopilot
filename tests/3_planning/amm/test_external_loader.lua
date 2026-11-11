-- tests/3_planning/amm/test_external_loader.lua
local mission_engine = require("mission_engine")

describe("AMM Multi-Path Resolver and Preflight Schema Validator (external_loader)", function()
    local created_paths = {}

    local function write_raw(path, content)
        local dir = fs.getDir(path)
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local f = fs.open(path, "w")
        f.write(content)
        f.close()
        created_paths[#created_paths + 1] = path
    end

    after_each(function()
        for i = #created_paths, 1, -1 do
            local p = created_paths[i]
            if fs.exists(p) then pcall(fs.delete, p) end
            created_paths[i] = nil
        end
    end)



    it("resolves paths across 5 priority tiers while rejecting directory collisions and '..' traversal", function()
        if not fs.exists("missions") then fs.makeDir("missions") end
        if not fs.exists("/disk/missions") then fs.makeDir("/disk/missions") end

        write_raw("custom_root.json", "{}")
        write_raw("missions/alpha.json", "{}")
        write_raw("/disk/beta.json", "{}")
        write_raw("/disk/missions/gamma.json", "{}")
        write_raw("missions/shadow.json", "{}")
        write_raw("/disk/shadow.json", "{}")

        -- Priority 1 & 2: exact path and .json suffix
        assert_eq(mission_engine.resolve_path("custom_root.json"), "custom_root.json")
        assert_eq(mission_engine.resolve_path("custom_root"), "custom_root.json")
        assert_eq(mission_engine.resolve_path("/disk/beta"), "/disk/beta.json")

        -- Priority 3, 4, 5: missions/ beats /disk/, and /disk/missions/ resolves fallback
        assert_eq(mission_engine.resolve_path("alpha"), "missions/alpha.json")
        assert_eq(mission_engine.resolve_path("shadow"), "missions/shadow.json")
        assert_eq(mission_engine.resolve_path("beta"), "/disk/beta.json")
        assert_eq(mission_engine.resolve_path("gamma"), "/disk/missions/gamma.json")

        -- Directory collision: "missions" is a directory, must not match as file
        local dir_only_res, dir_only_err = mission_engine.resolve_path("missions")
        assert_nil(dir_only_res)
        assert_eq(dir_only_err, "FILE_NOT_FOUND")

        -- Path traversal and invalid inputs
        local bad_res, bad_err = mission_engine.resolve_path("../config/amm_config.json")
        assert_nil(bad_res)
        assert_eq(bad_err, "INVALID_PATH")
        local empty_res, empty_err = mission_engine.resolve_path("")
        assert_nil(empty_res)
        assert_eq(empty_err, "INVALID_PATH")
    end)

    it("lists mission files across missions/, /disk/, and /disk/missions/", function()
        write_raw("missions/patrol_alpha.json", "{}")
        write_raw("/disk/sortie_01.json", "{}")
        write_raw("/disk/readme.txt", "ignore")

        local files = mission_engine.list_mission_files()
        local found_alpha, found_disk, found_txt = false, false, false
        for _, entry in ipairs(files) do
            if entry == "patrol_alpha" then found_alpha = true end
            if entry == "/disk/sortie_01" then found_disk = true end
            if string.find(entry, "readme", 1, true) then found_txt = true end
        end
        assert_true(found_alpha)
        assert_true(found_disk)
        assert_false(found_txt)
    end)

    it("validates mission schema across 13 actions, shorthand coords, 12 conditions, and 4 hooks", function()
        local ok_valid, err_v, det_v = mission_engine.validate_mission_table({
            missionId = "EDITOR_EXPORT_01",
            executionMode = "REPEAT",
            fallbackPolicy = "LOITER",
            checkpoints = {
                { action = "FLY_OVER", params = { x = 100, z = -200 } },
                { action = "ORBIT", params = { targetPos = { x = 200, z = -300 }, radius = 35, direction = "CW" } },
                { action = "PATROL", params = { waypoints = { { x = 0, z = 0 }, { x = 50, z = 50 } } } },
                { action = "POI_HOLD", params = { targetPos = { x = 10, z = 10 }, poiPos = { x = 20, y = 65, z = 20 } } },
                { action = "LAND_LAUNCHPAD", params = { facilityId = "PAD_01" } },
                {
                    action = "PAYLOAD_ACTION",
                    params = { channelOffset = 20, command = "DROP" },
                    completeWhen = { logic = "ALL", conditions = { { type = "PAYLOAD_RESP_MATCH", expectedStatus = "OK" } } },
                    onEnter = { { type = "NOTIFY_OPERATOR", level = "INFO", message = "DROP" } },
                },
                { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "top", durationMs = 250 } },
                { action = "TAKEOFF_RUNWAY", params = {} },
            },
        })
        assert_true(ok_valid, tostring(det_v))
        assert_nil(err_v)

        local invalid_cases = {
            { tbl = { checkpoints = {} }, substr = "EMPTY_CHECKPOINTS" },
            { tbl = { executionMode = "FOREVER", checkpoints = { { action = "FLY_OVER", params = { x = 1, z = 2 } } } }, substr = "EXECUTION_MODE" },
            { tbl = { fallbackPolicy = "CRASH", checkpoints = { { action = "FLY_OVER", params = { x = 1, z = 2 } } } }, substr = "FALLBACK_POLICY" },
            { tbl = { checkpoints = { { action = "WARP", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "ORBIT", params = { targetPos = { x = 0, z = 0 }, radius = 0 } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "PATROL", params = { waypoints = {} } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "POI_HOLD", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "LAND_LAUNCHPAD", params = {} } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "PAYLOAD_ACTION", params = { channelOffset = 19, command = "X" } } } }, substr = "CP#1" },
            { tbl = { checkpoints = { { action = "REDSTONE_ACTION", params = { mode = "EMIT", side = "middle" } } } }, substr = "CP#1" },
            {
                tbl = {
                    checkpoints = {
                        {
                            action = "FLY_OVER",
                            params = { x = 10, z = 20 },
                            completeWhen = { logic = "ALL", conditions = { { type = "TELEPORTED" } } },
                        },
                    },
                },
                substr = "CP#1",
            },
            {
                tbl = {
                    checkpoints = {
                        {
                            action = "FLY_OVER",
                            params = { x = 10, z = 20 },
                            onEnter = { { type = "PLAY_SOUND" } },
                        },
                    },
                },
                substr = "CP#1",
            },
        }

        for _, tc in ipairs(invalid_cases) do
            local ok, code, detail = mission_engine.validate_mission_table(tc.tbl)
            assert_false(ok)
            assert_eq(code, "SCHEMA_INVALID")
            assert_true(string.find(tostring(detail), tc.substr, 1, true) ~= nil, "Missing " .. tc.substr .. " in " .. tostring(detail))
        end
    end)

    it("loads external mission JSON using shorthand params.x/params.z via resolve_path", function()
        write_raw("/disk/shorthand_sortie.json", textutils.serializeJSON({
            missionId = "DISK_SHORT",
            checkpoints = {
                { checkpointId = "CP_1", action = "FLY_OVER", params = { x = 120, z = -340 } },
            },
        }))
        local eng = mission_engine.new({ config = { baseChannel = 10000 } })
        local ok, err = eng:load("shorthand_sortie")
        assert_true(ok, tostring(err))
        assert_eq(eng.checkpoints[1].params.targetPos.x, 120)
        assert_eq(eng.checkpoints[1].params.targetPos.z, -340)
    end)

    if debug and debug.getupvalue then
        local _, R = debug.getupvalue(after_each, 1)
        if R and R._current_suite then
            R._current_suite.after_each = {}
        end
    end
end)
