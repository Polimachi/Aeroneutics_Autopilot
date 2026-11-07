import tempfile
import unittest
from pathlib import Path

from harness.unit.config import UnitTargetConfig, resolve_craftos_paths
from harness.unit.engine import run_target_unit_tests


class TestGuestSdk(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.paths = resolve_craftos_paths()

    def test_assertions_nan_inf_deep_eq_and_dual_call_mocks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sdir = root / "src" / "1_control" / "sdk_check"
            tdir = root / "tests" / "1_control" / "sdk_check"
            sdir.mkdir(parents=True)
            tdir.mkdir(parents=True)
            (sdir / "main.lua").write_text("return true\n", encoding="utf-8")
            (tdir / "test_sdk_features.lua").write_text(
                'describe("extended assertions", function()\n'
                '    it("rejects NaN and inf in assert_near while passing finite tolerance", function()\n'
                '        assert_near(0.3000001, 0.3, 1e-5)\n'
                '        assert_throws(function() assert_near(0 / 0, 1.0, 0.1) end, "non-finite")\n'
                '        assert_throws(function() assert_near(math.huge, math.huge, 0.1) end, "non-finite")\n'
                '        assert_throws(function() assert_near(1.0, 100.0, 0 / 0) end, "tolerance")\n'
                '        assert_throws(function() assert_near(1.0, 100.0, math.huge) end, "tolerance")\n'
                '        assert_throws(function() assert_near(1.0, 1.0, -0.01) end, "tolerance")\n'
                '    end)\n'
                '    it("compares nested and cyclic tables in assert_deep_eq", function()\n'
                '        assert_deep_eq({ a = 1, b = { x = "ok" } }, { a = 1, b = { x = "ok" } })\n'
                '        assert_throws(function()\n'
                '            assert_deep_eq({ payload = { sig = 8 } }, { payload = { sig = 9 } })\n'
                '        end, "payload.sig")\n'
                '        local c1, c2 = {}, {}\n'
                '        c1.self = c1\n'
                '        c2.self = c2\n'
                '        assert_deep_eq(c1, c2)\n'
                '    end)\n'
                'end)\n'
                'describe("dual dot/colon mocks and avionics registry", function()\n'
                '    it("normalizes dot and colon calls on mock.modem, mock.term, and mock.actuator", function()\n'
                '        local m = mock.modem()\n'
                '        m.open(101)\n'
                '        m:open(102)\n'
                '        m.transmit(101, 102, { cmd = "A" })\n'
                '        m:transmit(103, 104, { cmd = "B" })\n'
                '        assert_true(m.isOpen(101) and m:isOpen(102))\n'
                '        assert_eq(m._transmitted[1].tx, 101)\n'
                '        assert_eq(m._transmitted[2].tx, 103)\n'
                '        local scr = mock.term(20, 5)\n'
                '        scr.setCursorPos(1, 1)\n'
                '        scr:write("HELLO")\n'
                '        assert_true(scr:_contains("HELLO"))\n'
                '        local act = mock.actuator("bearing")\n'
                '        act.setSpeed(128)\n'
                '        assert_eq(act._lastSpeed, 128)\n'
                '        act:setSpeed(-64)\n'
                '        assert_eq(act._lastSpeed, -64)\n'
                '    end)\n'
                '    it("registers CC:Avionics sensors in mock.peripheral_registry", function()\n'
                '        mock.peripheral_registry({\n'
                '            left = { type = "gimbal_sensor", dev = mock.avionics_gimbal({ pitch = 2.5, roll = -1.0 }) },\n'
                '            right = { type = "altitude_sensor", dev = mock.avionics_altitude({ altitude = 120.5, verticalSpeed = 1.2 }) },\n'
                '        })\n'
                '        local g = peripheral.find("gimbal_sensor")\n'
                '        local a = peripheral.wrap("right")\n'
                '        assert_near(g.getAngles().pitch, 2.5, 1e-6)\n'
                '        assert_near(a.getAltitude(), 120.5, 1e-6)\n'
                '    end)\n'
                'end)\n',
                encoding="utf-8",
            )
            target = UnitTargetConfig(target_id="1_control/sdk_check", source_dir=sdir, tests_dir=tdir)
            rep = run_target_unit_tests(target, self.paths, root / "sessions")
            self.assertEqual(rep.status, "PASS", rep.errors or [t.error for t in rep.tests])
            self.assertEqual(rep.passed_tests, 4)


if __name__ == "__main__":
    unittest.main()
