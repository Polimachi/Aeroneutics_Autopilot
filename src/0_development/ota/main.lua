-- src/0_development/ota/main.lua
-- Entrypoint for Hangar Wireless OTA Deployment Server (CLI & 51x19 Interactive TUI)

if package and package.path then
    package.path = "/modules/?.lua;./modules/?.lua;/lib/?.lua;src/0_development/ota/modules/?.lua;src/0_development/ota/?.lua;" .. package.path
end

local ota_agent = require("ota_agent")
local ota_protocol = require("ota_protocol")
local ota_server = require("ota_server")
local ota_ui = require("ota_ui")

local main = {}

local function read_config(fsApi)
    local fApi = fsApi or _G.fs
    local candidates = { "/config/ota_config.json", "config/ota_config.json" }
    if not fApi or type(fApi.exists) ~= "function" then
        return {}
    end
    for _, path in ipairs(candidates) do
        if fApi.exists(path) then
            local h = fApi.open(path, "r")
            if h then
                local raw = h.readAll()
                h.close()
                if textutils and type(textutils.unserializeJSON) == "function" then
                    local ok, parsed = pcall(textutils.unserializeJSON, raw)
                    if ok and type(parsed) == "table" then
                        return parsed
                    end
                end
            end
        end
    end
    return {}
end

local function parse_cli_args(args)
    local positional = {}
    local flags = {}
    for _, raw in ipairs(args or {}) do
        local s = tostring(raw)
        if s == "--headless" then
            flags.headless = true
        elseif s == "--overwrite-config" then
            flags.overwriteConfig = true
        elseif s == "--reboot" then
            flags.autoReboot = true
        else
            local bayStr = s:match("^%-%-bay=(%d+)$")
            if bayStr then
                flags.bayId = tonumber(bayStr)
            else
                positional[#positional + 1] = s
            end
        end
    end
    return positional, flags
end

local function close_server_channels(server)
    if server and server.modem and type(server.modem.close) == "function" and server.ackCh then
        pcall(server.modem.close, server.ackCh)
    end
end

local function build_ui_state(appState)
    local cmdCh, ackCh = ota_agent.get_channels(appState.server.bayId)
    return {
        bayId = appState.server.bayId,
        cmdCh = cmdCh,
        ackCh = ackCh,
        domainId = appState.server.domainId,
        modemPresent = (appState.server.modem ~= nil),
        nodes = appState.nodes,
        selectedIdx = appState.selectedIdx,
        progress = appState.progress,
        statusMsg = appState.statusMsg,
        overwriteConfig = appState.overwriteConfig,
        autoReboot = appState.autoReboot,
    }
end

local function render_if_available(appState)
    if appState.headless or not appState.termObj then
        return false
    end
    return ota_ui.render(appState.termObj, build_ui_state(appState))
end

local function run_discover_action(appState)
    appState.statusMsg = "DISCOVERING BAY " .. tostring(appState.server.bayId) .. "..."
    render_if_available(appState)
    appState.nodes = appState.server:discover({ bayId = appState.server.bayId })
    if #appState.nodes > 0 then
        appState.selectedIdx = math.max(1, math.min(#appState.nodes, appState.selectedIdx))
    else
        appState.selectedIdx = 1
    end
    appState.statusMsg = "FOUND " .. tostring(#appState.nodes) .. " NODE(S)"
end

local function run_sync_action(appState, moduleId)
    appState.statusMsg = "SYNCING REMOTE PACKAGES..."
    render_if_available(appState)
    local modList = moduleId and { moduleId } or nil
    local ok, info = appState.server:sync_remote({ moduleIds = modList })
    if ok then
        local count = (info and info.synced) and #info.synced or 0
        appState.statusMsg = "SYNCED " .. tostring(count) .. " MODULE(S)"
    else
        appState.statusMsg = "SYNC FAIL: " .. tostring(info and info.error or "ERR")
    end
end

local function run_deploy_selected(appState)
    local node = appState.nodes[appState.selectedIdx]
    if not node then
        appState.statusMsg = "NO TARGET SELECTED"
        return
    end
    local pkgDir = appState.server.defaultSourceDir .. "/" .. node.moduleId
    local pkg, loadErr = appState.server:load_package(pkgDir)
    if not pkg then
        appState.statusMsg = "PKG ERR: " .. tostring(loadErr)
        return
    end
    appState.progress = { active = true, sentChunks = 0, totalChunks = 1, stage = "BEGIN" }
    appState.statusMsg = "DEPLOYING " .. node.moduleId .. " -> " .. node.domainId
    render_if_available(appState)

    local ok, res = appState.server:deploy(
        {
            domainId = node.domainId,
            moduleId = node.moduleId,
            bayId = appState.server.bayId,
            overwriteConfig = appState.overwriteConfig,
            autoReboot = appState.autoReboot,
        },
        pkg,
        {
            onProgress = function(p)
                appState.progress = {
                    active = true,
                    sentChunks = p.sentChunks or 0,
                    totalChunks = math.max(1, p.totalChunks or 1),
                    stage = p.stage or "CHUNK",
                }
                render_if_available(appState)
            end,
        }
    )

    if ok then
        appState.statusMsg = "DEPLOY OK (" .. tostring(res and res.status or "APPLIED") .. ")"
    else
        appState.statusMsg = "DEPLOY FAIL: " .. tostring(res and res.reason or "ERR")
    end
end

local function run_cli(server, positional, flags)
    local cmd = positional[1]
    if cmd == "discover" then
        local nodes = server:discover({ bayId = flags.bayId or server.bayId })
        if #nodes == 0 then
            print("No OTA nodes discovered on bay " .. tostring(flags.bayId or server.bayId))
        else
            for _, n in ipairs(nodes) do
                print(string.format("%s\t%s\t%s\t%s\tsafe=%s", n.domainId, n.moduleId, n.version, n.controlState, tostring(n.safeForOta)))
            end
        end
        close_server_channels(server)
        return true, nodes
    elseif cmd == "sync" then
        local modId = positional[2]
        local ok, info = server:sync_remote({ moduleIds = modId and { modId } or nil })
        if ok then
            print("Synced: " .. table.concat(info.synced or {}, ", "))
        else
            print("Sync failed: " .. tostring(info and info.error or "UNKNOWN"))
        end
        close_server_channels(server)
        return ok, info
    elseif cmd == "deploy" then
        local moduleId = positional[2]
        local domainId = positional[3]
        local packageDir = positional[4] or (server.defaultSourceDir .. "/" .. tostring(moduleId or ""))
        if not moduleId or not domainId then
            print("Usage: main.lua deploy <moduleId> <domainId> <packageDir> [--bay=N] [--overwrite-config]")
            close_server_channels(server)
            return false, { reason = "INVALID_CLI_ARGS" }
        end
        local pkg, loadErr = server:load_package(packageDir)
        if not pkg then
            print("Package load failed: " .. tostring(loadErr))
            close_server_channels(server)
            return false, { reason = loadErr }
        end
        local ok, res = server:deploy(
            {
                domainId = domainId,
                moduleId = moduleId,
                bayId = flags.bayId or server.bayId,
                overwriteConfig = (flags.overwriteConfig == true),
                autoReboot = (flags.autoReboot == true),
            },
            pkg
        )
        if ok then
            print("Deploy OK: " .. tostring(res.txId) .. " (" .. tostring(res.status) .. ")")
        else
            print("Deploy FAILED: " .. tostring(res and res.reason or "UNKNOWN"))
        end
        close_server_channels(server)
        return ok, res
    end
    return nil, nil
end

--- Runs the OTA server CLI command or interactive 51x19 TUI / headless event loop.
-- @param args table|nil CLI argument list
-- @param deps table|nil Optional dependency overrides { fs, http, modem, term, config }
-- @return boolean ok, any result
function main.run(args, deps)
    deps = deps or {}
    local fsApi = deps.fs or _G.fs
    local cfg = deps.config or read_config(fsApi)
    local positional, flags = parse_cli_args(args)

    if flags.bayId then
        cfg.ota = cfg.ota or {}
        cfg.ota.bayId = flags.bayId
    end

    local server = ota_server.new({
        config = cfg,
        modem = deps.modem,
        fsApi = fsApi,
        httpApi = deps.http,
        rootDir = deps.rootDir,
        pollEventFn = deps.pollEventFn,
    })

    if server.modem and type(server.modem.open) == "function" then
        server.modem.open(server.ackCh)
    end

    if cfg.ota and cfg.ota.autoSyncOnBoot == true and server.httpApi then
        server:sync_remote({})
    end

    if #positional > 0 then
        local cliOk, cliRes = run_cli(server, positional, flags)
        if cliOk ~= nil then
            return cliOk, cliRes
        end
    end

    local termObj = deps.term
    if termObj == nil and not flags.headless then
        termObj = (peripheral and type(peripheral.find) == "function" and peripheral.find("monitor")) or _G.term
    end

    local appState = {
        server = server,
        termObj = termObj,
        headless = (flags.headless == true) or (termObj == nil),
        running = true,
        nodes = {},
        selectedIdx = 1,
        progress = { active = false, sentChunks = 0, totalChunks = 0 },
        statusMsg = "ICD " .. ota_protocol.ICD_VERSION .. " READY",
        overwriteConfig = (flags.overwriteConfig == true),
        autoReboot = (flags.autoReboot == true),
    }

    render_if_available(appState)

    local pullEv = deps.pollEventFn or (os and os.pullEventRaw)
    if type(pullEv) ~= "function" then
        close_server_channels(server)
        return true, appState
    end

    local upKey = (_G.keys and _G.keys.up) or 200
    local downKey = (_G.keys and _G.keys.down) or 208

    while appState.running do
        local ev, p1, _p2, _p3, _p4 = pullEv()
        if ev == nil or ev == "terminate" or ev == "shutdown" then
            appState.running = false
        elseif ev == "char" and not appState.headless then
            local ch = string.lower(tostring(p1 or ""))
            if ch == "q" then
                appState.running = false
            elseif ch == "d" then
                run_discover_action(appState)
            elseif ch == "s" then
                run_sync_action(appState, nil)
            elseif ch == "u" then
                run_deploy_selected(appState)
            elseif ch == "b" then
                local nextBay = (server.bayId % 10) + 1
                server:set_bay(nextBay)
                appState.statusMsg = "SWITCHED TO BAY " .. tostring(nextBay)
            elseif ch == "o" then
                appState.overwriteConfig = not appState.overwriteConfig
            elseif ch == "r" then
                appState.autoReboot = not appState.autoReboot
            end
            render_if_available(appState)
        elseif ev == "key" and not appState.headless then
            if p1 == upKey and #appState.nodes > 0 then
                appState.selectedIdx = math.max(1, appState.selectedIdx - 1)
                render_if_available(appState)
            elseif p1 == downKey and #appState.nodes > 0 then
                appState.selectedIdx = math.min(#appState.nodes, appState.selectedIdx + 1)
                render_if_available(appState)
            end
        end
    end

    close_server_channels(server)
    return true, appState
end

if _G.describe == nil and not _G.__HARNESS_HIL_MODE then
    main.run({ ... })
end

return main
