# Turtle API & Robotics Patterns

## 1. Turtle API (Robotic Control)
```lua
-- Movement (all return success, errorMessage)
turtle.forward()    turtle.back()
turtle.up()         turtle.down()
turtle.turnLeft()   turtle.turnRight()

-- World Interaction
turtle.dig()        turtle.digUp()      turtle.digDown()
turtle.place()      turtle.placeUp()    turtle.placeDown()
turtle.attack()     turtle.attackUp()   turtle.attackDown()

-- Inventory (16 slots)
turtle.select(slot) -- 1-16
turtle.getItemDetail(slot?)
turtle.getItemCount(slot?)
turtle.transferTo(slot, count?)
turtle.drop(count?)     turtle.dropUp()     turtle.dropDown()
turtle.suck(count?)     turtle.suckUp()     turtle.suckDown()

-- Fuel System
turtle.getFuelLevel()   -- number or "unlimited"
turtle.getFuelLimit()
turtle.refuel(count?)   -- consume fuel items in selected slot

-- Inspection & Comparison
turtle.inspect()        turtle.inspectUp()      turtle.inspectDown() -- returns success, blockData
turtle.detect()         turtle.detectUp()       turtle.detectDown()  -- returns boolean
turtle.compare()        turtle.compareUp()      turtle.compareDown()
turtle.compareTo(slot)

-- Crafting (requires crafty turtle)
turtle.craft(limit?)
```

## 2. Fuel Management Patterns
```lua
local function ensureFuel(minLevel)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    if fuel < minLevel then
        for slot = 1, 16 do
            turtle.select(slot)
            if turtle.refuel(0) then -- test if item is fuel
                turtle.refuel()
            end
            if turtle.getFuelLevel() >= minLevel then
                return true
            end
        end
        return false
    end
    return true
end
```

## 3. Safe Digging, Slot Rotation & 3D Loop Patterns
```lua
local function safeDig()
    local success, err = turtle.dig()
    if not success and err ~= "Nothing to dig here" then
        print("Dig failed: " .. tostring(err))
        return false
    end
    return true
end

local function mineForward()
    while turtle.detect() do
        turtle.dig()
        sleep(0.4) -- wait for falling gravel/sand
    end
    return turtle.forward()
end

local slot = 1
local function checkAndFillSlot()
    while turtle.getItemCount(slot) == 0 do
        slot = (slot % 16) + 1
        turtle.select(slot)
    end
end

local turn = "left"
local function adjustOrientation()
    if turn == "left" then
        turtle.turnLeft()
        mineForward()
        turtle.turnLeft()
        turn = "right"
    else
        turtle.turnRight()
        mineForward()
        turtle.turnRight()
        turn = "left"
    end
end
```
