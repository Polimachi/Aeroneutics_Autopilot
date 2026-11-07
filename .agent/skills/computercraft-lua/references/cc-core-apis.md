# CC:Tweaked Core APIs & Computer/Network Patterns

## 1. Event System
```lua
-- Pull events (yields execution)
local event, p1, p2, p3 = os.pullEvent(filter?)
local event, ... = os.pullEventRaw(filter?)  -- catches terminate

-- Common Events:
-- "key", keyCode, isHeld | "key_up", keyCode | "char", character
-- "timer", timerId | "alarm", alarmId
-- "rednet_message", senderId, message, protocol
-- "modem_message", side, channel, replyChannel, message, distance
-- "turtle_inventory" | "peripheral", side | "peripheral_detach", side
-- "redstone" | "terminate" | "mouse_click", button, x, y | "monitor_touch", side, x, y
```

## 2. Rednet Communication
```lua
rednet.open("back")  -- open modem on specified side
rednet.close()       -- close all modems

rednet.send(recipientId, message, protocol?)
rednet.broadcast(message, protocol?)
local senderId, message, protocol = rednet.receive(protocolFilter?, timeout?)

-- DNS-like naming
rednet.host(protocol, hostname)
rednet.unhost(protocol)
rednet.lookup(protocol, hostname?) -- returns id or table of ids
```

## 3. Peripheral API
```lua
peripheral.getNames()           -- list all peripherals
peripheral.isPresent(side)
peripheral.getType(side)
peripheral.find(type, filter?)  -- returns wrapped peripheral(s)

local p = peripheral.wrap(side)
p.someMethod()
peripheral.call(side, "method", args...)
-- Common types: "modem", "monitor", "speaker", "drive", "printer", "command", "computer", "inventory"
```

## 4. File System (`fs`)
```lua
local file = fs.open("path", mode) -- "r", "w", "a", "rb", "wb", "ab"
local content = file.readAll()
file.write("data")
file.writeLine("line")
file.close()

fs.exists(path)     fs.isDir(path)      fs.list(path)
fs.makeDir(path)    fs.delete(path)     fs.move(from, to)
fs.copy(from, to)   fs.getSize(path)    fs.getFreeSpace(path)
```

## 5. HTTP & WebSockets
```lua
local response = http.get(url, headers?, binary?)
local body = response.readAll()
response.close()

local response = http.post(url, body, headers?, binary?)
http.request(url, body?, headers?, binary?, method?) -- async: http_success / http_failure

local ws = http.websocket(url, headers?)
ws.send(message)
local msg = ws.receive(timeout?)
ws.close()
```

## 6. Term & Display
```lua
term.write(text)            term.clear()            term.clearLine()
term.setCursorPos(x, y)     term.getCursorPos()     term.getSize()
term.setTextColor(color)    term.setBackgroundColor(color)
term.scroll(n)

local mon = peripheral.wrap("top")
mon.setTextScale(scale)     -- 0.5 to 5
term.redirect(mon)          -- redirect output to monitor
```

## 7. Parallel Execution
```lua
parallel.waitForAny(func1, func2, ...)
parallel.waitForAll(func1, func2, ...)
```

## 8. Redstone & Colors APIs
```lua
redstone.getInput("top")            -- boolean
redstone.getAnalogInput("top")      -- 0-15
redstone.setOutput("left", true)
redstone.setAnalogOutput("left", 15) -- 0-15
redstone.getBundledInput("back")
redstone.setBundledOutput("back", colors.combine(colors.red, colors.blue))

-- Colors constants:
-- white, orange, magenta, lightBlue, yellow, lime, pink, gray,
-- lightGray, cyan, purple, blue, brown, green, red, black
colors.combine(colors.red, colors.blue)
colors.subtract(combined, colors.red)
colors.test(combined, colors.blue)  -- boolean
```

## 9. Generic Inventory API
```lua
local inv = peripheral.wrap("top") -- or peripheral.find("inventory")
inv.size()                         -- total slot count
inv.list()                         -- slot -> {name, count, nbt?}
inv.getItemDetail(slot)            -- detailed metadata table
inv.getItemLimit(slot)             -- max slot capacity
inv.pushItems("bottom", 1, 64)
inv.pushItems("minecraft:chest_0", 2, 16, 5)
inv.pullItems("left", 1, 64)
inv.pullItems("minecraft:barrel_1", 3, 32, 1)
```

## 10. `textutils` API
```lua
textutils.serialize(data, options?)
textutils.unserialize(str)
textutils.serializeJSON(data, bNBTStyle?) -- alias: serialiseJSON
textutils.unserializeJSON(str)            -- alias: unserialiseJSON
textutils.urlEncode(str)
textutils.tabulate(...)
textutils.pagedTabulate(...)
textutils.pagedPrint(text, freeLines?)
textutils.formatTime(time, b24Hour?)
textutils.complete(prefix, options?)
textutils.empty()
textutils.json_null
```

## 11. Common Computer, GPS & Rednet Patterns

### Event Server Pattern
```lua
local function safeRednetOpen(side)
    if not rednet.isOpen() then
        rednet.open(side or "top")
    end
end

safeRednetOpen("back")
rednet.host("myservice", "server1")

while true do
    local senderId, message, protocol = rednet.receive("myservice")
    if type(message) == "table" and message.type == "request" then
        local response = handleRequest(message.data)
        rednet.send(senderId, {type = "response", data = response}, "myservice")
    end
end
```

### GPS Locate & Transmitter Pattern
```lua
local x, y, z = gps.locate(5) -- 5 second timeout
if x then
    print(("Position: %d, %d, %d"):format(x, y, z))
end
```

### Redstone Control & User Input Normalization
```lua
write("direction (l, r): ")
local direction = read():lower()
if direction == "l" or direction == "left" then
    direction = "left"
elseif direction == "r" or direction == "right" then
    direction = "right"
end

-- Periodic Redstone Poll Loop
while true do
    if redstone.getInput("top") then
        redstone.setOutput("left", true)
    elseif redstone.getInput("right") then
        redstone.setOutput("left", false)
    end
    os.sleep(1)
end
```
