---
name: computercraft-lua
description: >-
  CC:Tweaked ComputerCraft, CC:Avionics, CC:Radars, Create Propulsion: Simulated,
  and Advanced Peripherals API reference and patterns. USE ONLY WHEN writing,
  modifying, or reviewing .lua code that interacts with CC:Tweaked APIs,
  peripherals, events, rednet, redstone, or turtles. NEVER invoke during general
  chat, verbal Q&A, pure math/table Lua utilities without CC APIs, Python harness
  scripting, or markdown/JSON edits.
---

# ComputerCraft CC:Tweaked & Aeronautics API Skill

Expert reference for developing and verifying Lua scripts in Minecraft CC:Tweaked (ComputerCraft 1.109.0+ / Lua 5.2 Cobalt runtime) across Create: Aeronautics, Avionics, Radars, Propulsion, and peripherals.

## Scope & Selective Reference Loading (Progressive Disclosure)

Do **not** load all reference files at once. Read **only** the reference file matching the APIs touched by your current task:

1. **Flight, Attitude, Radar, Fire Control & Thrusters** (`CC:Avionics`, `CC:Radars`, `Create Propulsion: Simulated`):
   - Read [references/avionics-propulsion-radars.md](./references/avionics-propulsion-radars.md)
2. **Core CraftOS APIs & Network/Redstone Patterns** (`os.pullEvent`, `rednet`, `peripheral`, `fs`, `http`, `term`, `parallel`, `redstone`, `colors`, `inventory`, `textutils`, GPS/server loops):
   - Read [references/cc-core-apis.md](./references/cc-core-apis.md)
3. **Advanced Peripherals Addon** (`meBridge`, `rsBridge`, `geoScanner`, `playerDetector`, `chatBox`, `inventoryManager`, `environmentDetector`, `colonyIntegrator`, `arController`, `redstoneIntegrator`, `energyDetector`):
   - Read [references/advanced-peripherals.md](./references/advanced-peripherals.md)
4. **Turtle Robotics & Mining/Inventory Patterns** (`turtle.*` movement, digging, fuel, slot rotation, 3D loops):
   - Read [references/turtle-patterns.md](./references/turtle-patterns.md)

## Core Environment & Lua 5.2 Essentials

- **Devices**: Stationary `Computers`, mobile `Turtles`, portable `Pocket Computers`, and external `Peripherals`.
- **Lua 5.2 Rules**:
  - Use `...` for varargs (not `arg`).
  - Use `_ENV` for environments (not `getfenv`/`setfenv`).
  - No binary chunk support; `goto` statement is available.
  - Use `bit32.*` for bitwise logic and `math.floor(a / b)` for integer division (no Lua 5.3 operators).

## Mandatory CC:Tweaked Best Practices

### 1. Always Handle Peripheral & Action Failures
```lua
local sensor = peripheral.find("gimbal_sensor")
if not sensor then
    error("Required gimbal_sensor peripheral not attached", 0)
end
```

### 2. Yield Regularly (`Too long without yielding` Prevention)
```lua
for i = 1, 10000 do
    doWork()
    if i % 100 == 0 then
        sleep(0) -- minimal yield
    end
end
```

### 3. Modularize via `require` & Clean Entry Points
```lua
-- utils.lua
local M = {}
function M.log(msg)
    print("[" .. os.date("%H:%M:%S") .. "] " .. msg)
end
return M

-- startup.lua / main.lua
local utils = require("utils")
utils.log("Started")
```

### 4. Packaging & Deployment Conventions
- Keep a clear entry point per program (`startup.lua` or `main.lua`).
- Avoid spaces in file names to keep `wget`, `pastebin`, CraftOS mounts, and world-save copies (`saves/<world>/computercraft/computer/<id>/`) clean.
