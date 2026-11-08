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
end)
