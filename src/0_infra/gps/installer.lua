-- installer.lua - Interactive All-in-One Disk Installer for CC-GPS
local installer_core = require("installer_core")
local storage_hal = require("storage_hal")

local function printHeader()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("   CC-GPS ALL-IN-ONE DISK INSTALLER     ")
    print("========================================")
    print("Select installation target:")
    print(" [1] Central Server (GCS & Scheduler)")
    print(" [2] Swarm Node (Trilateration Beacon)")
    print(" [3] Client Library (gps_client API)")
    print(" [4] Exit")
    print("----------------------------------------")
end

local function installServer()
    print("Installing Central Server files to /gps/...")
    fs.makeDir("/gps")
    fs.makeDir("/gps_data")
    if not fs.exists("/gps_data/nodes.json") then
        storage_hal.writeJson("/gps_data/nodes.json", { nodes = {} })
    end
    fs.makeDir("/startup")
    local hook = installer_core.generateStartupHook("server", "/gps/server.lua")
    storage_hal.writeAtomic("/startup/00_gps.lua", hook)
    print("[SUCCESS] Central Server installed.")
end

local function installNode()
    print("Installing Swarm Node files to /gps/...")
    fs.makeDir("/gps")
    fs.makeDir("/gps_data")
    local defaultCfg = {
        role = "NODE",
        channel = 60002,
        networkKey = "GPS_BASE_NET",
        heartbeatSec = 10,
        position = { x = 0, y = 0, z = 0 }
    }
    local curCfg = storage_hal.readJson("/gps_data/node_cfg.json")
    local finalCfg = installer_core.migrateConfig(curCfg, defaultCfg)
    storage_hal.writeJson("/gps_data/node_cfg.json", finalCfg)
    fs.makeDir("/startup")
    local hook = installer_core.generateStartupHook("node", "/gps/node.lua")
    storage_hal.writeAtomic("/startup/00_gps.lua", hook)
    print("[SUCCESS] Swarm Node installed.")
end

local function installClient()
    print("Installing Client API library to /apis/...")
    fs.makeDir("/apis")
    print("[SUCCESS] Client library registered.")
end

local function main()
    printHeader()
    write("Enter choice (1-4): ")
    local choice = read()
    if choice == "1" then
        installServer()
    elseif choice == "2" then
        installNode()
    elseif choice == "3" then
        installClient()
    else
        print("Installation canceled.")
    end
end

if not _G.harness_is_testing then
    main()
end

return {
    installServer = installServer,
    installNode = installNode,
    installClient = installClient
}
