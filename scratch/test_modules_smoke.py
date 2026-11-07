import ctypes
import os

dll_path = r"c:\Users\sjmik\Desktop\Antigravity_Workspace\Lua_Harness\bin\lua52.dll"
lua = ctypes.CDLL(dll_path)

lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadstring.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

L = lua.luaL_newstate()
lua.luaL_openlibs(L)

test_script = """
package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./src/2_guidance/sas/modules/drivers/?.lua;./src/1_control/asa/modules/?.lua;./src/1_control/vas/modules/?.lua"

print("[Test 1] Fixed Wing Driver")
local fw = dofile("src/2_guidance/sas/modules/drivers/fixed_wing_driver.lua")
assert(fw.AIRFRAME == "FIXED_WING", "FW AIRFRAME mismatch")
local fw_out = fw.compute({}, { pos = {x=0,y=100,z=0}, vel = {x=20,y=0,z=0}, groundSpeed=20, airspeed=20 }, { x=100, y=120, z=0 }, "CRUISE", 0.05)
assert(fw_out.throttle > 0, "FW throttle invalid")
print("  FW OK: throttle=" .. tostring(fw_out.throttle) .. ", pitch=" .. tostring(fw_out.targetPitch))

print("[Test 2] Helicopter Driver")
local heli = dofile("src/2_guidance/sas/modules/drivers/helicopter_driver.lua")
assert(heli.AIRFRAME == "HELICOPTER", "Heli AIRFRAME mismatch")
local heli_out = heli.compute({}, { pos = {x=0,y=50,z=0}, vel = {x=0,y=0,z=0} }, { x=10, y=60, z=0 }, "HOVER", 0.05)
assert(heli_out.throttle > 0, "Heli throttle invalid")
print("  Heli OK: throttle=" .. tostring(heli_out.throttle) .. ", antiTorque=" .. tostring(heli_out.antiTorqueFeedforward))

print("[Test 3] Drone Driver")
local drone = dofile("src/2_guidance/sas/modules/drivers/drone_driver.lua")
assert(drone.AIRFRAME == "MULTIROTOR_DRONE", "Drone AIRFRAME mismatch")
local drone_out = drone.compute({}, { pos = {x=0,y=50,z=0}, vel = {x=0,y=0,z=0} }, { x=5, y=55, z=5 }, "HOVER", 0.05)
assert(drone_out.throttle > 0, "Drone throttle invalid")
print("  Drone OK: throttle=" .. tostring(drone_out.throttle))

print("[Test 4] Control Surface Mapper")
local csm = dofile("src/1_control/asa/modules/control_surface_mapper.lua")
local key, tier = csm.classify("create:mechanical_bearing_Elevator")
assert(key == "elevator" and tier == 2, "CSM classify failed")
print("  CSM OK: key=" .. tostring(key) .. ", tier=" .. tostring(tier))

print("[Test 5] Dynamic Trim Compensator")
local dtc = dofile("src/1_control/vas/modules/dynamic_trim_compensator.lua")
local comp = dtc.new({ nominalSpeed = 20.0, stallSpeed = 15.0 })
local eval = comp:evaluate({ airspeed = 12.0, alpha = 10.0 }, { pitch = { kp = 4.0, ki = 0.2, kd = 1.5 } })
assert(eval.stallWarning == true, "Stall warning expected")
print("  DTC OK: stallWarning=" .. tostring(eval.stallWarning) .. ", pitchTrim=" .. tostring(eval.trim.pitchTrim))

print("[Test 6] Thrust Mixer")
local tm = dofile("src/1_control/vas/modules/thrust_mixer.lua")
local mixer = tm.init({
    coefficients = {
        main = { surge = 1.0, heave = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0, deadband = 1.0, maxThrust = 15 }
    }
})
local mixed = tm.mix(mixer, { surge = 15.0, sway = 0, heave = 0, pitch = 0, roll = 0, yaw = 0 })
assert(mixed.main == 15, "Mixer output mismatch")
print("  TM OK: main=" .. tostring(mixed.main))

print("[Test 7] Preflight BIT")
local bit = dofile("src/1_control/vas/modules/preflight_bit.lua")
local bit_res = bit.evaluateStatus({}, {"Modem advisory"}, 2, {"TAG1", "TAG2"})
assert(bit_res.status == "AMBER" and bit_res.isArmed == true, "BIT evaluation failed")
print("  BIT OK: status=" .. bit_res.status .. ", isArmed=" .. tostring(bit_res.isArmed))

print("ALL 7 MODULES EXECUTED AND PASSED SMOKE TESTS!")
"""

ret = lua.luaL_loadstring(L, test_script.encode('utf-8'))
if ret != 0:
    err = lua.lua_tolstring(L, -1, None)
    print("Compilation error:", err.decode('utf-8'))
else:
    pcall_ret = lua.lua_pcallk(L, 0, 0, 0, 0, None)
    if pcall_ret != 0:
        err = lua.lua_tolstring(L, -1, None)
        print("Runtime error:", err.decode('utf-8'))

lua.lua_close(L)
