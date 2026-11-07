# Advanced Peripherals API Reference

```lua
-- Peripheral wrapper examples:
local me = peripheral.find("meBridge")
local rs = peripheral.find("rsBridge")
local geo = peripheral.find("geoScanner")
local pd = peripheral.find("playerDetector")
local chat = peripheral.find("chatBox")
local im = peripheral.find("inventoryManager")
local env = peripheral.find("environmentDetector")
local colony = peripheral.find("colonyIntegrator")
local ar = peripheral.find("arController")
local redstoneInt = peripheral.find("redstoneIntegrator")
local energy = peripheral.find("energyDetector")

-- 1. ME Bridge (Applied Energistics 2)
me.listItems()                            -- list all stored items
me.getItem({name = "minecraft:iron_ingot"}) -- details of specific item
me.craftItem({name = "minecraft:chest", count = 1}) -- trigger crafting job
me.isItemCrafting({name = "minecraft:chest"}) -- check if crafting active
me.getEnergyStorage() / me.getMaxEnergyStorage() -- AE2 network energy stats
me.listCraftableItems()                   -- list items with crafting patterns
me.exportItem({name = "minecraft:oak_log", count = 64}, "up") -- export to connected chest
me.importItem({name = "minecraft:cobblestone", count = 64}, "up") -- import into AE2
me.listFluids() / me.listGas()            -- fluid and chemical/gas queries

-- 2. RS Bridge (Refined Storage)
rs.listItems() / rs.getItem(item) / rs.craftItem(item, count)
rs.isItemCrafting(item) / rs.getEnergyStorage() / rs.getMaxEnergyStorage()
rs.exportItem(item, direction) / rs.importItem(item, direction)

-- 3. Geo Scanner
geo.scan(radius)                          -- scan radius around block for blocks/ores (returns table of {x,y,z,name,tags})
geo.chunkAnalyze()                        -- analyze current chunk block distribution
geo.costCheck()                           -- check fuel or cooldown cost for scanning

-- 4. Player Detector
pd.getPlayersInRange(range)               -- list player names within radius
pd.isPlayerInRange(range, username)       -- check if specific player is in radius
pd.getPlayersInCoords(pos1, pos2)         -- list players inside bounding box
pd.isPlayerInCoords(pos1, pos2, username) -- check player inside bounding box
pd.getPlayerPos(username)                 -- returns {x, y, z, dimension, pitch, yaw}
pd.getOnlinePlayers()                     -- returns table of all online player names
-- Events fired: "playerJoin", "playerLeave", "playerClick"

-- 5. Chat Box
chat.sendMessage(msg, prefix?, brackets?, bracketColor?, range?) -- send public chat message
chat.sendMessageToPlayer(msg, player, prefix?, ...)             -- send private whisper to player
chat.sendFormattedMessage(jsonComponent, prefix?, ...)          -- send JSON formatted raw text
chat.sendToastToPlayer(player, msg, title, icon, ...)           -- send Minecraft toast notification
-- Event fired: "chat", username, message, uuid, isHidden

-- 6. Inventory Manager
im.addItemToPlayer(direction, {name=..., count=...})            -- push items directly into player inventory
im.removeItemFromPlayer(direction, {name=..., count=...})       -- pull items from player inventory
im.getItems() / im.getArmor()                                   -- inspect inventory/armor of adjacent player
im.getEmptySpace() / im.isPlayer()                              -- inventory stats

-- 7. Environment Detector
env.getBiome()                            -- current biome ID
env.getBlockLightLevel() / env.getSkyLightLevel() / env.getDayLightLevel()
env.getTime() / env.getMoonPhase()
env.isRaining() / env.isThunder() / env.isSunny()
env.isSlimeChunk()

-- 8. Colony Integrator (MineColonies)
colony.getCitizens() / colony.getBuildings() / colony.getHappiness()
colony.getVisitors() / colony.getWorkOrders() / colony.isActive()

-- 9. AR Controller (Augmented Reality HUD)
ar.clear()                                -- clear canvas
ar.drawBox(x, y, w, h, color, opacity)    -- draw filled rectangle
ar.drawString(text, x, y, color)          -- render HUD text
ar.drawItemIcon(itemId, x, y)             -- render Minecraft item sprite
ar.show() / ar.hide()                     -- toggle layer visibility

-- 10. Redstone Integrator & Energy Detector
redstoneInt.setOutput(side, power) / redstoneInt.getInput(side)
redstoneInt.setAnalogOutput(side, 0-15) / redstoneInt.getAnalogInput(side)
energy.getEnergy() / energy.getMaxEnergy() / energy.getTransferRate()
```
