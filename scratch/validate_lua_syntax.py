import ctypes
import os

dll_path = r"c:\Users\sjmik\Desktop\Antigravity_Workspace\Lua_Harness\bin\lua52.dll"
lua = ctypes.CDLL(dll_path)

lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadfilex.restype = ctypes.c_int
lua.lua_close.argtypes = [ctypes.c_void_p]

L = lua.luaL_newstate()

files = [
    r"src\2_guidance\fcp\modules\drivers\fixed_wing_driver.lua",
    r"src\2_guidance\fcp\modules\drivers\helicopter_driver.lua",
    r"src\2_guidance\fcp\modules\drivers\drone_driver.lua",
    r"src\1_control\asa\modules\control_surface_mapper.lua",
    r"src\1_control\vas\modules\dynamic_trim_compensator.lua",
    r"src\1_control\vas\modules\thrust_mixer.lua",
    r"src\1_control\vas\modules\preflight_bit.lua"
]

all_ok = True
print("=== Lua 5.2 Syntax Validation ===")
for f in files:
    full_path = os.path.abspath(f)
    if not os.path.exists(full_path):
        print(f"FAILED (Not found): {f}")
        all_ok = False
        continue
    ret = lua.luaL_loadfilex(L, full_path.encode('utf-8'), None)
    if ret == 0:
        print(f"PASS [Syntax OK]: {f}")
    else:
        print(f"FAIL [Syntax Error code {ret}]: {f}")
        all_ok = False

lua.lua_close(L)
if all_ok:
    print("ALL 7 FILES PASSED LUA 5.2 COMPILATION SUCCESSFULLY!")
else:
    raise SystemExit(1)
