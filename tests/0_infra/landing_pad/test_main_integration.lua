-- tests/0_infra/landing_pad/test_main_integration.lua
local config_default = require("config")

describe("Landing pad main daemon integration", function()
    it("loads default configuration specification", function()
        assert_not_nil(config_default)
        assert_eq(config_default.ver, "2.4.0")
        assert_not_nil(config_default.channels)
        assert_eq(config_default.channels.sectorFacilityChannel, 50202)
        assert_eq(config_default.channels.sectorGpsReplyChannel, 50206)
        assert_eq(config_default.channels.tacticalChannel, 50211)
    end)

    it("verifies main entrypoint exists and can be required without syntax error", function()
        local ok, mainModule = pcall(require, "main")
        assert_true(ok, "main.lua should load without error")
        assert_not_nil(mainModule)
    end)

    it("opens facility, gps reply, and tactical channels but keeps CH 60001 transmit-only", function()
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
        local origConfigStore = package.loaded["modules.config_store"]
        local origMain = package.loaded["main"]

        local cfgStoreMock = {
            load_config = function()
                return {
                    padId = "PAD_TEST",
                    mode = "STATIC",
                    sectorIndex = 1,
                    channels = {
                        sectorFacilityChannel = 50202,
                        sectorGpsReplyChannel = 50206,
                        tacticalChannel = 50211,
                    },
                    position = { x = 0, y = 64, z = 0 },
                }
            end,
            save_config = function() return true end,
            create_default = function() return {} end,
            normalize_config = function(c) return c end,
        }
        package.loaded["modules.config_store"] = cfgStoreMock
        package.loaded["main"] = nil
        local mainModule = require("main")
        _G.peripheral = _G.peripheral or {}
        _G.peripheral.find = function(ptype)
            if ptype == "modem" then return mockModem end
            return nil
        end
        _G.peripheral.wrap = function() return nil end
        _G.os.pullEventRaw = function() return "terminate" end

        local ok, err = pcall(mainModule.run)

        _G.peripheral.find = origFind
        _G.peripheral.wrap = origWrap
        _G.os.pullEventRaw = origPull
        package.loaded["modules.config_store"] = origConfigStore
        package.loaded["main"] = origMain

        assert_true(ok, "mainModule.run errored: " .. tostring(err))
        assert_true(opened[50202], "sectorFacilityChannel must be opened")
        assert_true(opened[50206], "sectorGpsReplyChannel must be opened")
        assert_true(opened[50211], "tacticalChannel must be opened")
        assert_nil(opened[60001], "CH 60001 must remain transmit-only")
    end)
end)
