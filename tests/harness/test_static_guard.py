import unittest

from harness.unit.config import resolve_craftos_paths
from harness.unit.static_guard import Lua52SyntaxChecker, scan_lua_source


class TestStaticGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        paths = resolve_craftos_paths()
        cls.checker = Lua52SyntaxChecker(paths.lua52_dll)

    def test_lua52_dll_catches_syntax_error_with_line(self) -> None:
        v = scan_lua_source("local a = 1\nlocal b =\nreturn a\n", "modules/bad.lua", self.checker)
        self.assertTrue(any(item.code == "LUA52_SYNTAX_ERROR" and item.line >= 2 for item in v))

    def test_lua53_operators_rejected_but_urls_and_strings_ignored(self) -> None:
        safe_url_src = (
            '-- Docs: https://tweaked.cc/module/peripheral.html?a=1&b=2\n'
            'local url = "https://example.com/api//v1?x=1&y=2|z=3"\n'
            'local long_str = [[http://local//test << >> & |]]\n'
            'local ok = (1 ~= 2)\n'
            'return url, long_str, ok\n'
        )
        self.assertEqual(scan_lua_source(safe_url_src, "modules/safe.lua", self.checker), [])

        bad_ops = [
            "local q = 10 // 3\n",
            "local m = 6 & 3\n",
            "local n = 6 | 1\n",
            "local s = 1 << 4\n",
        ]
        for snippet in bad_ops:
            issues = scan_lua_source(snippet, "modules/op.lua", None)
            self.assertTrue(any(i.code == "LUA53_OPERATOR" for i in issues), snippet)

    def test_host_os_apis_rejected(self) -> None:
        issues = scan_lua_source('os.execute("dir")\nos.remove("a.txt")\n', "modules/os_bad.lua", self.checker)
        codes = [i.code for i in issues]
        self.assertEqual(codes.count("PROHIBITED_HOST_OS_API"), 2)

    def test_vs2_blocked_and_create_aeronautics_plus_ion_thruster_allowed(self) -> None:
        blocked_cases = [
            'local s = peripheral.find("ship")\n',
            'local q = ship.getQuaternion()\n',
            'local k = peripheral.find("kontraption:ion_thruster")\n',
            'local h = peripheral.wrap("eureka:ship_helm")\n',
            'local v = require("vs2.ship")\n',
        ]
        for code in blocked_cases:
            issues = scan_lua_source(code, "modules/flight.lua", self.checker)
            self.assertTrue(any(i.code == "PROHIBITED_MOD_VIOLATION" for i in issues), code)

        allowed_code = (
            'local ion = peripheral.find("ion_thruster")\n'
            'local vec = peripheral.find("vector_thruster")\n'
            'local gim = peripheral.find("gimbal_sensor")\n'
            'local brg = peripheral.find("create:clockwork_bearing")\n'
            'local ship_state = { ship_pos = { x = 0, y = 64, z = 0 }, ship_velocity = 12.0 }\n'
            'return ion, vec, gim, brg, ship_state\n'
        )
        self.assertEqual(scan_lua_source(allowed_code, "modules/aero.lua", self.checker), [])

    def test_word_boundary_avoids_false_positives_for_short_tokens(self) -> None:
        safe_code = (
            'local devmode = true\n'
            'local navmode = "auto"\n'
            'local prevs2 = 42\n'
            'local msg = "switching to devmode now"\n'
            'return devmode, navmode, prevs2, msg\n'
        )
        issues = scan_lua_source(safe_code, "modules/safe_mode.lua", self.checker)
        self.assertEqual(issues, [])


if __name__ == "__main__":
    unittest.main()
