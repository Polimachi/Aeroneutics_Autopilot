-- tests/0_infra/runway/test_sensor_adapter.lua
local sensor_adapter = require("modules.sensor_adapter")

describe("Runway Sensor Adapter and Graceful Peripheral Scan", function()
    it("marks STATIC mode healthy without avionics sensors and scans optional wired peripherals safely", function()
        local origFind = _G.peripheral and _G.peripheral.find
        local origWrap = _G.peripheral and _G.peripheral.wrap
        _G.peripheral = _G.peripheral or {}
        _G.peripheral.find = function() return nil end
        _G.peripheral.wrap = function() return nil end

        local sa = sensor_adapter.create("STATIC", nil)
        local healthy, report = sa:scan_peripherals()
        assert_true(healthy)
        assert_false(report.redstoneIntegrator)
        assert_false(report.carrierClutch)
        assert_false(report.windDisplay)

        _G.peripheral.find = origFind
        _G.peripheral.wrap = origWrap
    end)

    it("requires 3 avionics sensors in DYNAMIC mode and enforces 10deg/2.5mps deck stability limits", function()
        local origFind = _G.peripheral and _G.peripheral.find
        _G.peripheral = _G.peripheral or {}
        _G.peripheral.find = function() return nil end

        local sa = sensor_adapter.create("DYNAMIC", nil)
        local healthy = sa:scan_peripherals()
        assert_false(healthy)

        local st1, perm1 = sa:evaluate_deck_stability(5.0, 4.0, 1.0)
        assert_eq(st1, "STABLE")
        assert_true(perm1)

        local st2, perm2 = sa:evaluate_deck_stability(9.0, 6.0, 0.5) -- tilt = ~10.82 > 10
        assert_eq(st2, "DANGEROUS")
        assert_false(perm2)

        local st3, perm3 = sa:evaluate_deck_stability(0.0, 0.0, -3.0)
        assert_eq(st3, "DANGEROUS")
        assert_false(perm3)

        _G.peripheral.find = origFind
    end)
end)
