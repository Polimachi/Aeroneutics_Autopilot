-- tests/0_infra/runway/test_main_loop.lua
describe("Runway Main Daemon Integration", function()
    it("opens Base_sec+1/+5/+10 channels, keeps CH 60001 transmit-only, and boots cleanly without wired peripherals", function()
        local opened = {}
        local mockModem = {
            isWireless = function() return true end,
            isOpen = function(ch) return opened[ch] == true end,
            open = function(ch) opened[ch] = true end,
            close = function() end,
            closeAll = function() end,
            transmit = function() end,
        }
        local origFind = _G.peripheral and _G.peripheral.find
        local origWrap = _G.peripheral and _G.peripheral.wrap
        local origPull = _G.os and _G.os.pullEventRaw
        local origCfg = package.loaded["modules.config_store"]
        local origMain = package.loaded["main"]

        package.loaded["modules.config_store"] = {
            load_config = function()
                return {
                    facilityId = "RWY_MAIN_TEST",
                    mobility = "STATIC",
                    sectorId = 1,
                    runwayIndex = 1,
                    approachHeading = 90.0,
                    approachDirection = "FRONT",
                    glideSlopeAngle = 3.0,
                    touchdownZoneLength = 80.0,
                    position = { x = 0, y = 64, z = 0 },
                    touchdownOffset = { forward = 0, right = 0, up = 0 },
                    endOffset = { forward = 300, right = 0, up = 0 },
                    channels = {
                        sectorChannel = 50201,
                        sectorFacilityChannel = 50202,
                        sectorGpsReplyChannel = 50206,
                        tacticalChannel = 50211,
                    },
                }
            end,
            save_config = function() return true end,
            create_default = function() return {} end,
            normalize_config = function(c) return c end,
        }
        package.loaded["main"] = nil
        local mainModule = require("main")

        _G.peripheral = _G.peripheral or {}
        _G.peripheral.find = function(ptype)
            if ptype == "modem" then return mockModem end
            return nil
        end
        _G.peripheral.wrap = function() return nil end
        local pulls = 0
        _G.os.pullEventRaw = function()
            pulls = pulls + 1
            if pulls == 1 then return "timer", 1 end
            return "terminate"
        end

        local ok, err = pcall(mainModule.run)

        _G.peripheral.find = origFind
        _G.peripheral.wrap = origWrap
        _G.os.pullEventRaw = origPull
        package.loaded["modules.config_store"] = origCfg
        package.loaded["main"] = origMain

        assert_true(ok, "main.run errored: " .. tostring(err))
        assert_true(opened[50202], "sectorFacilityChannel must be opened")
        assert_true(opened[50206], "sectorGpsReplyChannel must be opened")
        assert_true(opened[50211], "tacticalChannel must be opened")
        assert_nil(opened[60001], "CH 60001 must remain transmit-only")
    end)
end)
