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

    def test_extended_domain_tokens_and_prefixes_blocked(self) -> None:
        blocked_cases = [
            'local p = require("valkyrien_pirates")\n',
            'local t = peripheral.find("vs_trackwork")\n',
            'local inf = peripheral.find("physics_infuser")\n',
            'local flap = peripheral.find("flap_bearing")\n',
            'local grav = peripheral.find("gravitron")\n',
            'local pb = peripheral.find("phys_bearing")\n',
            'local rr = peripheral.find("redstone_resistor")\n',
            'local helm = peripheral.find("ship_helm")\n',
            'local pt = peripheral.find("phys_track")\n',
            'local st = peripheral.find("suspension_track")\n',
            'local c = peripheral.find("vs_clockwork:bearing")\n',
            'local e = peripheral.find("vs_eureka:helm")\n',
            'local tr = peripheral.find("trackwork:wheel")\n',
            'local tour = peripheral.find("vs_tournament:cannon")\n',
            'local add = peripheral.find("vs_addition:prop")\n',
            'local val = peripheral.find("valkyrien:ship")\n',
            'local cc = peripheral.find("cc_vs:reader")\n',
        ]
        for snippet in blocked_cases:
            issues = scan_lua_source(snippet, "modules/flight_block.lua", self.checker)
            self.assertTrue(
                any(i.code == "PROHIBITED_MOD_VIOLATION" for i in issues),
                f"Failed to detect violation in: {snippet}",
            )

    def test_trackwork_matches_vs_trackwork(self) -> None:
        code = 'local tw = peripheral.find("vs_trackwork")\n'
        issues = scan_lua_source(code, "modules/track.lua", self.checker)
        self.assertTrue(any(i.code == "PROHIBITED_MOD_VIOLATION" for i in issues))

    def test_wrapped_ship_methods_blocked(self) -> None:
        wrapped_calls = [
            'local s = peripheral.wrap("some_dev")\nlocal q = s.getQuaternion()\n',
            'local obj = peripheral.wrap("dev")\nlocal o = obj:getOmega()\n',
            'local p = peripheral.wrap("x")\nlocal m = p.getMomentOfInertiaTensor()\n',
            'local dev = get_dev()\ndev.applyInvariantForce(1, 2, 3)\n',
        ]
        for snippet in wrapped_calls:
            issues = scan_lua_source(snippet, "modules/wrapped.lua", self.checker)
            self.assertTrue(
                any(i.code == "PROHIBITED_MOD_VIOLATION" for i in issues),
                f"Failed to catch wrapped ship method in: {snippet}",
            )

    def test_legacy_arg_table_access_blocked_but_declared_arg_allowed(self) -> None:
        bad_arg_snippets = [
            "local function run()\n    return arg[1]\nend\n",
            "local function get_count()\n    return #arg\nend\n",
            "local function iterate()\n    for k, v in ipairs(arg) do end\nend\n",
            "local val = arg.n\n",
        ]
        for snippet in bad_arg_snippets:
            issues = scan_lua_source(snippet, "modules/arg_bad.lua", self.checker)
            self.assertTrue(
                any(i.code == "PROHIBITED_LUA51_ARG_API" for i in issues),
                f"Failed to catch legacy arg in: {snippet}",
            )

        good_arg_snippets = [
            "local function run(arg)\n    return arg[1]\nend\n",
            "local arg = { ... }\nlocal first = arg[1]\n",
            "local args = { ... }\nlocal first = args[1]\n",
            "local function f(...)\n    local args = { ... }\n    return #args\nend\n",
            'local arg = "flag"\nif arg == "--source" then end\n',
        ]
        for snippet in good_arg_snippets:
            issues = scan_lua_source(snippet, "modules/arg_good.lua", self.checker)
            self.assertFalse(
                any(i.code == "PROHIBITED_LUA51_ARG_API" for i in issues),
                f"False positive on valid arg in: {snippet}",
            )

    def test_infinite_loop_without_yield_blocked(self) -> None:
        bad_loops = [
            "while true do\n    local a = 1\nend\n",
            "while 1 do\n    local b = 2\nend\n",
            "repeat\n    local c = 3\nuntil false\n",
            "repeat\n    local d = 4\nuntil nil\n",
        ]
        for snippet in bad_loops:
            issues = scan_lua_source(snippet, "modules/loop_bad.lua", self.checker)
            self.assertTrue(
                any(i.code == "INFINITE_LOOP_WITHOUT_YIELD" for i in issues),
                f"Failed to catch infinite loop in: {snippet}",
            )

        good_loops = [
            "while true do\n    sleep(0.05)\nend\n",
            "while true do\n    os.pullEvent()\nend\n",
            "while true do\n    if done then break end\nend\n",
            "while true do\n    return 42\nend\n",
            "while true do\n    local ev = rednet.receive()\nend\n",
            "while true do\n    local line = read()\nend\n",
            "repeat\n    coroutine.yield()\nuntil false\n",
            "while true do\n    http.get('http://example.com')\nend\n",
        ]
        for snippet in good_loops:
            issues = scan_lua_source(snippet, "modules/loop_good.lua", self.checker)
            self.assertFalse(
                any(i.code == "INFINITE_LOOP_WITHOUT_YIELD" for i in issues),
                f"False positive on yielding loop in: {snippet}",
            )

    def test_cross_subsystem_require_blocked_in_src(self) -> None:
        bad_requires = [
            ('src/1_control/vas/modules/core_daemon.lua', 'local gps = require("src.0_infra.gps.protocol")\n'),
            ('src/1_control/vas/modules/core_daemon.lua', 'local fcp = require("fcp.modules.flight_fsm")\n'),
            ('src/2_guidance/fcp/modules/flight_fsm.lua', 'local amm = require("src.3_planning.amm.main")\n'),
        ]
        for rel_path, snippet in bad_requires:
            issues = scan_lua_source(snippet, rel_path, self.checker)
            self.assertTrue(
                any(i.code == "CROSS_SUBSYSTEM_REQUIRE" for i in issues),
                f"Failed to catch cross-subsystem require in: {snippet}",
            )

        good_requires = [
            ('src/1_control/vas/modules/core_daemon.lua', 'local quat = require("modules.quat")\n'),
            ('src/1_control/vas/modules/core_daemon.lua', 'local sensors = require("avionics_sensors")\n'),
            ('src/1_control/vas/modules/core_daemon.lua', 'local sensors = require("/lib/avionics_sensors.lua")\n'),
            ('src/1_control/vas/modules/core_daemon.lua', '-- local gps = require("src.0_infra.gps.protocol")\n'),
            ('src/0_infra/landing_pad/main.lua', 'local gps_client = require("modules.gps_client")\n'),
            ('tests/1_control/vas/test_vas_core.lua', 'local vas = require("vas_core")\n'),
        ]
        for rel_path, snippet in good_requires:
            issues = scan_lua_source(snippet, rel_path, self.checker)
            self.assertFalse(
                any(i.code == "CROSS_SUBSYSTEM_REQUIRE" for i in issues),
                f"False positive on valid require in: {snippet}",
            )


if __name__ == "__main__":
    unittest.main()
