-- src/0_development/ota/modules/ota_server.lua
-- Hangar Wireless OTA Deployment Server: Remote Sync, Discovery, Chunked Transfer & Safe Abort

local ota_agent = require("ota_agent")
local ota_protocol = require("ota_protocol")

local ota_server = {}

local ServerMT = {}
ServerMT.__index = ServerMT

local DEFAULT_MANIFEST_URL = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/src/0_development/installer/modules/manifest.lua"
local DEFAULT_GITHUB_RAW_BASE = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/"
local DEFAULT_SYNC_MODULES = { "vas", "tca", "fcp", "amm" }
local MAX_HTTP_REDIRECTS = 5
local MAX_POLL_ITERATIONS = 10000

local FATAL_NACK_REASONS = {
    NOT_DISARMED = true,
    MODULE_MISMATCH = true,
    DOMAIN_MISMATCH = true,
    DISK_ERROR = true,
    TX_NOT_FOUND = true,
}

local function normalize_root(rootDir)
    local root = (rootDir or "/"):gsub("\\", "/")
    while #root > 1 and root:sub(-1) == "/" do
        root = root:sub(1, -2)
    end
    if root == "" then
        root = "/"
    end
    return root
end

local function resolve_server_path(rootDir, rawPath)
    local norm = ota_protocol.normalize_rel_path(rawPath)
    if not norm then
        return nil
    end
    local root = normalize_root(rootDir)
    if root == "/" then
        return norm
    end
    if norm == root or norm:sub(1, #root + 1) == root .. "/" then
        return norm
    end
    return root .. norm
end

local function ensure_parent_dir(fsApi, path)
    local parent = fsApi.getDir(path)
    if parent and parent ~= "" and not fsApi.exists(parent) then
        local okMk, errMk = pcall(fsApi.makeDir, parent)
        if not okMk then
            return false, tostring(errMk)
        end
    end
    return true, nil
end

local function write_file_atomic(fsApi, path, content)
    local okDir, errDir = ensure_parent_dir(fsApi, path)
    if not okDir then
        return false, errDir
    end
    local tmpPath = path .. ".tmp"
    local h = fsApi.open(tmpPath, "w")
    if not h then
        return false, "OPEN_WRITE_FAILED"
    end
    h.write(content)
    h.close()
    if fsApi.exists(path) then
        local okDel, errDel = pcall(fsApi.delete, path)
        if not okDel then
            pcall(fsApi.delete, tmpPath)
            return false, tostring(errDel)
        end
    end
    local okMv, errMv = pcall(fsApi.move, tmpPath, path)
    if not okMv then
        pcall(fsApi.delete, tmpPath)
        return false, tostring(errMv)
    end
    return true, nil
end

local function read_all_file(fsApi, path)
    if not fsApi.exists(path) then
        return nil, "FILE_NOT_FOUND"
    end
    local h = fsApi.open(path, "r")
    if not h then
        return nil, "OPEN_READ_FAILED"
    end
    local data = h.readAll()
    h.close()
    return data or "", nil
end

local function read_json_file(fsApi, path)
    local raw, errRead = read_all_file(fsApi, path)
    if not raw or raw == "" then
        return nil, errRead or "EMPTY_FILE"
    end
    if not textutils or type(textutils.unserializeJSON) ~= "function" then
        return nil, "JSON_UNAVAILABLE"
    end
    local okParse, parsed = pcall(textutils.unserializeJSON, raw)
    if not okParse or type(parsed) ~= "table" then
        return nil, "JSON_INVALID"
    end
    return parsed, nil
end

local function http_fetch_string(httpApi, url)
    if type(httpApi) ~= "table" or type(httpApi.get) ~= "function" then
        return nil, "HTTP_DISABLED"
    end
    if type(url) ~= "string" or url == "" then
        return nil, "INVALID_URL"
    end

    local currentUrl = url
    local hops = 0
    while true do
        local resp, getErr = httpApi.get(currentUrl)
        if not resp then
            return nil, tostring(getErr or "HTTP_REQUEST_FAILED")
        end

        local code = 200
        if type(resp.getResponseCode) == "function" then
            code = resp.getResponseCode() or 200
        end

        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            hops = hops + 1
            if hops > MAX_HTTP_REDIRECTS then
                if type(resp.close) == "function" then
                    resp.close()
                end
                return nil, "TOO_MANY_REDIRECTS"
            end
            local headers = (type(resp.getResponseHeaders) == "function" and resp.getResponseHeaders()) or {}
            local loc = nil
            for k, v in pairs(headers) do
                if type(k) == "string" and string.lower(k) == "location" then
                    loc = v
                    break
                end
            end
            if type(resp.close) == "function" then
                resp.close()
            end
            if type(loc) ~= "string" or loc == "" then
                return nil, "REDIRECT_WITHOUT_LOCATION"
            end
            currentUrl = loc
        elseif code >= 400 then
            if type(resp.close) == "function" then
                resp.close()
            end
            return nil, "HTTP_ERROR_" .. tostring(code)
        else
            local body = ""
            if type(resp.readAll) == "function" then
                body = resp.readAll() or ""
            end
            if type(resp.close) == "function" then
                resp.close()
            end
            return body, nil
        end
    end
end

local function load_sandboxed_manifest(manifestSource)
    if type(manifestSource) ~= "string" or manifestSource == "" then
        return nil, "EMPTY_MANIFEST"
    end
    local emptyEnv = {}
    local loader, loadErr = load(manifestSource, "=remote_manifest", "t", emptyEnv)
    if not loader then
        return nil, "MANIFEST_SYNTAX_ERROR: " .. tostring(loadErr)
    end
    local okExec, result = pcall(loader)
    if not okExec then
        return nil, "MANIFEST_EXEC_ERROR: " .. tostring(result)
    end
    if type(result) ~= "table" or type(result.MODULES) ~= "table" then
        return nil, "INVALID_REMOTE_MANIFEST"
    end
    return result, nil
end

local function build_config_defaults(rawCfg)
    local cfg = type(rawCfg) == "table" and rawCfg or {}
    local ota = type(cfg.ota) == "table" and cfg.ota or {}
    local net = type(cfg.network) == "table" and cfg.network or {}

    return {
        version = type(cfg.version) == "string" and cfg.version or "0.1.0",
        ota = {
            bayId = math.floor(tonumber(ota.bayId) or 1),
            chunkSize = math.max(1, math.floor(tonumber(ota.chunkSize) or ota_protocol.DEFAULT_CHUNK_SIZE)),
            ackTimeoutSec = tonumber(ota.ackTimeoutSec) or 1.5,
            maxRetries = math.max(0, math.floor(tonumber(ota.maxRetries) or 3)),
            defaultSourceDir = type(ota.defaultSourceDir) == "string" and ota.defaultSourceDir or "/ota_packages",
            autoSyncOnBoot = (ota.autoSyncOnBoot == true),
            manifestUrl = type(ota.manifestUrl) == "string" and ota.manifestUrl or DEFAULT_MANIFEST_URL,
            githubRawBase = type(ota.githubRawBase) == "string" and ota.githubRawBase or DEFAULT_GITHUB_RAW_BASE,
        },
        network = {
            domainId = (type(net.domainId) == "string" and net.domainId ~= "") and net.domainId or "HANGAR-OTA-01",
        },
    }
end

--- Constructs a Hangar Wireless OTA Deployment Server instance.
-- @param opts table|nil { config, modem, fsApi, httpApi, rootDir, clockFn, sleepFn, pollEventFn, seqFn }
-- @return table server
function ota_server.new(opts)
    opts = opts or {}
    local cfg = build_config_defaults(opts.config)
    local cmdCh, ackCh = ota_agent.get_channels(cfg.ota.bayId)
    local seqCounter = 0

    local modem = opts.modem
    if modem == nil and peripheral and type(peripheral.find) == "function" then
        modem = peripheral.find("modem")
    end

    local httpApi = opts.httpApi
    if httpApi == nil then
        httpApi = _G.http
    elseif httpApi == false then
        httpApi = nil
    end

    local instance = {
        config = cfg,
        bayId = cfg.ota.bayId,
        cmdCh = cmdCh,
        ackCh = ackCh,
        domainId = cfg.network.domainId,
        chunkSize = cfg.ota.chunkSize,
        ackTimeoutSec = cfg.ota.ackTimeoutSec,
        maxRetries = cfg.ota.maxRetries,
        defaultSourceDir = cfg.ota.defaultSourceDir,
        manifestUrl = cfg.ota.manifestUrl,
        githubRawBase = cfg.ota.githubRawBase,
        modem = modem,
        fsApi = opts.fsApi or _G.fs,
        httpApi = httpApi,
        rootDir = normalize_root(opts.rootDir),
        clockFn = opts.clockFn or function()
            if os and os.epoch then
                return os.epoch("utc")
            end
            if os and os.time then
                return os.time() * 1000
            end
            return 0
        end,
        sleepFn = opts.sleepFn or function(sec)
            if _G.sleep then
                _G.sleep(sec)
            end
        end,
        pollEventFn = opts.pollEventFn,
        seqFn = opts.seqFn or function()
            seqCounter = seqCounter + 1
            return seqCounter
        end,
    }

    return setmetatable(instance, ServerMT)
end

function ServerMT:_next_seq()
    return self.seqFn()
end

function ServerMT:_ensure_bay_channels(bayIdOverride)
    local targetBay = bayIdOverride or self.bayId
    local cmdCh, ackCh = ota_agent.get_channels(targetBay)
    if self.modem and type(self.modem.open) == "function" then
        if type(self.modem.isOpen) ~= "function" or not self.modem.isOpen(ackCh) then
            self.modem.open(ackCh)
        end
    end
    return targetBay, cmdCh, ackCh
end

function ServerMT:_transmit(cmdCh, ackCh, msgType, payload)
    local env = ota_protocol.build_envelope(self.domainId, self:_next_seq(), msgType, payload, self.clockFn())
    self.modem.transmit(cmdCh, ackCh, env)
    return env
end

function ServerMT:_wait_for_packet(ackCh, timeoutSec, matchFn)
    local waitSec = math.max(0.01, tonumber(timeoutSec) or self.ackTimeoutSec)

    if type(self.pollEventFn) == "function" then
        local deadlineMs = self.clockFn() + math.floor(waitSec * 1000)
        for _ = 1, MAX_POLL_ITERATIONS do
            local remainingSec = math.max(0, (deadlineMs - self.clockFn()) / 1000)
            local ev, p1, p2, p3, p4, p5 = self.pollEventFn(remainingSec)
            if ev == nil then
                return nil, "TIMEOUT"
            elseif ev == "terminate" or ev == "shutdown" then
                return nil, "ABORTED_BY_SIGNAL"
            elseif ev == "modem_message" and tonumber(p2) == ackCh then
                local parsed = ota_protocol.parse_envelope(p4)
                if parsed then
                    local matched, res = matchFn(parsed, tonumber(p2), p3, p5)
                    if matched then
                        return parsed, res
                    end
                end
            elseif ev == "timer" then
                if p1 == nil or p1 == "timeout" or self.clockFn() >= deadlineMs then
                    return nil, "TIMEOUT"
                end
            end
        end
        return nil, "TIMEOUT"
    end

    if not os or type(os.startTimer) ~= "function" or type(os.pullEventRaw) ~= "function" then
        return nil, "EVENT_LOOP_UNAVAILABLE"
    end

    local timerId = os.startTimer(waitSec)
    while true do
        local ev, p1, p2, p3, p4, p5 = os.pullEventRaw()
        if ev == "terminate" or ev == "shutdown" then
            if os.cancelTimer then
                pcall(os.cancelTimer, timerId)
            end
            return nil, "ABORTED_BY_SIGNAL"
        elseif ev == "timer" and p1 == timerId then
            return nil, "TIMEOUT"
        elseif ev == "modem_message" and tonumber(p2) == ackCh then
            local parsed = ota_protocol.parse_envelope(p4)
            if parsed then
                local matched, res = matchFn(parsed, tonumber(p2), p3, p5)
                if matched then
                    if os.cancelTimer then
                        pcall(os.cancelTimer, timerId)
                    end
                    return parsed, res
                end
            end
        end
    end
end

--- Switches the active hangar bay ID (1..10) and opens its ACK channel if a modem is attached.
-- @param bayId number Hangar bay index (1..10)
-- @return number bayId, number cmdCh, number ackCh
function ServerMT:set_bay(bayId)
    local cmdCh, ackCh = ota_agent.get_channels(bayId)
    if self.modem and type(self.modem.close) == "function" and self.ackCh and self.ackCh ~= ackCh then
        pcall(self.modem.close, self.ackCh)
    end
    self.bayId = tonumber(bayId)
    self.cmdCh = cmdCh
    self.ackCh = ackCh
    if self.modem and type(self.modem.open) == "function" then
        self.modem.open(ackCh)
    end
    return self.bayId, cmdCh, ackCh
end

--- Downloads remote manifest.lua in a sandboxed environment and stages /ota_packages/<moduleId>/.
-- @param opts table|nil { moduleIds, rootDir, sourceDir, manifestUrl, githubRawBase, httpApi }
-- @return boolean ok, table info
function ServerMT:sync_remote(opts)
    opts = opts or {}
    local httpApi = opts.httpApi
    if httpApi == nil then
        httpApi = self.httpApi
    end
    if type(httpApi) ~= "table" or type(httpApi.get) ~= "function" then
        return false, { error = "HTTP_DISABLED" }
    end
    if not self.fsApi then
        return false, { error = "FS_DISABLED" }
    end

    local manifestUrl = opts.manifestUrl or self.manifestUrl
    local githubRawBase = opts.githubRawBase or self.githubRawBase
    if githubRawBase:sub(-1) ~= "/" then
        githubRawBase = githubRawBase .. "/"
    end

    local manifestSrc, fetchErr = http_fetch_string(httpApi, manifestUrl)
    if not manifestSrc then
        return false, { error = fetchErr, url = manifestUrl }
    end

    local manifestTbl, parseErr = load_sandboxed_manifest(manifestSrc)
    if not manifestTbl then
        return false, { error = parseErr }
    end

    local targetModules = {}
    if type(opts.moduleIds) == "table" and #opts.moduleIds > 0 then
        for _, mId in ipairs(opts.moduleIds) do
            targetModules[#targetModules + 1] = tostring(mId)
        end
    else
        for _, mId in ipairs(DEFAULT_SYNC_MODULES) do
            if type(manifestTbl.MODULES[mId]) == "table" then
                targetModules[#targetModules + 1] = mId
            end
        end
        if #targetModules == 0 then
            for mId, mSpec in pairs(manifestTbl.MODULES) do
                if type(mSpec) == "table" then
                    targetModules[#targetModules + 1] = tostring(mId)
                end
            end
            table.sort(targetModules)
        end
    end

    if #targetModules == 0 then
        return false, { error = "NO_MODULES_TO_SYNC" }
    end

    local rootDir = opts.rootDir or self.rootDir
    local sourceBase = opts.sourceDir or self.defaultSourceDir
    local synced = {}
    local packageDirs = {}

    for _, moduleId in ipairs(targetModules) do
        local modSpec = manifestTbl.MODULES[moduleId]
        if type(modSpec) ~= "table" or type(modSpec.files) ~= "table" then
            return false, { error = "MODULE_NOT_FOUND", moduleId = moduleId }
        end

        local stagedFiles = {}
        local rawContents = {}
        local totalBytes = 0

        for _, fEntry in ipairs(modSpec.files) do
            if type(fEntry) ~= "table" or type(fEntry.repoPath) ~= "string" then
                return false, { error = "INVALID_MANIFEST_FILE_ENTRY", moduleId = moduleId }
            end
            local normDest = ota_protocol.normalize_rel_path(fEntry.dest)
            if not normDest then
                return false, { error = "INVALID_DEST_PATH", moduleId = moduleId, dest = tostring(fEntry.dest) }
            end

            local cleanRepo = fEntry.repoPath
            while cleanRepo:sub(1, 1) == "/" do
                cleanRepo = cleanRepo:sub(2)
            end
            local fileUrl = githubRawBase .. cleanRepo
            local content, fileErr = http_fetch_string(httpApi, fileUrl)
            if not content then
                return false, { error = fileErr, moduleId = moduleId, url = fileUrl }
            end

            stagedFiles[#stagedFiles + 1] = {
                path = normDest,
                localPath = "files" .. normDest,
                size = #content,
                crc32 = ota_agent.crc32(content),
                content = content,
            }
            rawContents[#rawContents + 1] = content
            totalBytes = totalBytes + #content
        end

        local pkgRelDir = ota_protocol.normalize_rel_path(sourceBase .. "/" .. moduleId)
        local pkgDir = resolve_server_path(rootDir, pkgRelDir)
        if not pkgDir then
            return false, { error = "INVALID_PACKAGE_DIR", moduleId = moduleId }
        end

        local manifestFiles = {}
        for idx, item in ipairs(stagedFiles) do
            local destFilePath = pkgDir .. "/" .. item.localPath
            local okW, errW = write_file_atomic(self.fsApi, destFilePath, item.content)
            if not okW then
                return false, { error = errW, moduleId = moduleId, path = destFilePath }
            end
            manifestFiles[idx] = {
                path = item.path,
                localPath = item.localPath,
                size = item.size,
                crc32 = item.crc32,
            }
        end

        local pkgManifest = {
            schemaVersion = "1.0.0",
            moduleId = moduleId,
            version = tostring(modSpec.version or "0.0.0"),
            totalBytes = totalBytes,
            totalCrc32 = ota_agent.crc32(table.concat(rawContents)),
            syncedAt = self.clockFn(),
            files = manifestFiles,
        }
        if not textutils or type(textutils.serializeJSON) ~= "function" then
            return false, { error = "JSON_UNAVAILABLE" }
        end
        local okSer, jsonStr = pcall(textutils.serializeJSON, pkgManifest)
        if not okSer or type(jsonStr) ~= "string" then
            return false, { error = "JSON_SERIALIZE_FAILED" }
        end
        local okMeta, errMeta = write_file_atomic(self.fsApi, pkgDir .. "/ota_package.json", jsonStr)
        if not okMeta then
            return false, { error = errMeta, moduleId = moduleId }
        end

        synced[#synced + 1] = moduleId
        packageDirs[moduleId] = pkgDir
    end

    return true, { synced = synced, packageDirs = packageDirs }
end

--- Loads and verifies a staged package directory or ota_package.json manifest.
-- @param packageDirOrManifest string Directory path or path to ota_package.json
-- @return table|nil package
-- @return string|nil errorReason
function ServerMT:load_package(packageDirOrManifest)
    if not self.fsApi then
        return nil, "FS_DISABLED"
    end
    local resolved = resolve_server_path(self.rootDir, packageDirOrManifest)
    if not resolved then
        return nil, "INVALID_PACKAGE_PATH"
    end

    local manifestPath
    local pkgDir
    if resolved:sub(-5) == ".json" then
        manifestPath = resolved
        pkgDir = self.fsApi.getDir(resolved)
    else
        pkgDir = resolved
        manifestPath = resolved .. "/ota_package.json"
    end

    if not self.fsApi.exists(manifestPath) then
        return nil, "PACKAGE_NOT_FOUND"
    end

    local meta, errMeta = read_json_file(self.fsApi, manifestPath)
    if not meta then
        return nil, errMeta or "INVALID_PACKAGE_MANIFEST"
    end
    if type(meta.moduleId) ~= "string" or meta.moduleId == ""
        or type(meta.version) ~= "string" or meta.version == ""
        or type(meta.files) ~= "table" or #meta.files == 0 then
        return nil, "INVALID_PACKAGE_MANIFEST"
    end

    local loadedFiles = {}
    local rawContents = {}
    local totalBytes = 0

    for idx, entry in ipairs(meta.files) do
        if type(entry) ~= "table" then
            return nil, "INVALID_PACKAGE_MANIFEST"
        end
        local normTarget = ota_protocol.normalize_rel_path(entry.path)
        if not normTarget then
            return nil, "INVALID_PACKAGE_MANIFEST"
        end
        local relLocal = type(entry.localPath) == "string" and ota_protocol.normalize_rel_path(entry.localPath) or normTarget
        if not relLocal then
            return nil, "INVALID_PACKAGE_MANIFEST"
        end
        local diskPath = (pkgDir == "/" and "" or pkgDir) .. relLocal
        local content, errRead = read_all_file(self.fsApi, diskPath)
        if not content then
            return nil, errRead or "FILE_NOT_FOUND"
        end
        local actualCrc = ota_agent.crc32(content)
        if type(entry.size) == "number" and #content ~= entry.size then
            return nil, "CRC_MISMATCH"
        end
        if type(entry.crc32) == "number" and actualCrc ~= entry.crc32 then
            return nil, "CRC_MISMATCH"
        end
        loadedFiles[idx] = {
            path = normTarget,
            size = #content,
            crc32 = actualCrc,
            content = content,
        }
        rawContents[idx] = content
        totalBytes = totalBytes + #content
    end

    local totalCrc32 = ota_agent.crc32(table.concat(rawContents))
    if type(meta.totalBytes) == "number" and totalBytes ~= meta.totalBytes then
        return nil, "CRC_MISMATCH"
    end
    if type(meta.totalCrc32) == "number" and totalCrc32 ~= meta.totalCrc32 then
        return nil, "CRC_MISMATCH"
    end

    return {
        moduleId = meta.moduleId,
        version = meta.version,
        packageDir = pkgDir,
        totalBytes = totalBytes,
        totalCrc32 = totalCrc32,
        files = loadedFiles,
    }, nil
end

--- Broadcasts MSG_OTA_DISCOVER_REQ on the target bay and collects MSG_OTA_DISCOVER_ACK responses.
-- @param opts table|nil { targetModuleId, targetDomainId, bayId, windowSec }
-- @return table discoveredNodes, string|nil waitErr
function ServerMT:discover(opts)
    opts = opts or {}
    if not self.modem or type(self.modem.transmit) ~= "function" then
        return {}, "NO_MODEM"
    end

    local bayId, cmdCh, ackCh = self:_ensure_bay_channels(opts.bayId)
    self:_transmit(cmdCh, ackCh, "MSG_OTA_DISCOVER_REQ", {
        targetModuleId = opts.targetModuleId or "*",
        targetDomainId = opts.targetDomainId or "*",
    })

    local byKey = {}
    local windowSec = tonumber(opts.windowSec) or self.ackTimeoutSec

    local _, waitErr = self:_wait_for_packet(ackCh, windowSec, function(pkt)
        if pkt.type ~= "MSG_OTA_DISCOVER_ACK" then
            return false
        end
        local p = pkt.payload
        if type(p.moduleId) ~= "string" or p.moduleId == "" then
            return false
        end
        local versions = type(p.versions) == "table" and p.versions or {}
        local modVersion = type(versions[p.moduleId]) == "string" and versions[p.moduleId] or "0.0.0-untracked"
        local safe, denyReason = ota_agent.is_safe_for_ota({
            controlState = p.controlState,
            isAirborne = p.isAirborne,
        })
        local key = pkt.domainId .. ":" .. p.moduleId
        byKey[key] = {
            domainId = pkt.domainId,
            moduleId = p.moduleId,
            version = modVersion,
            versions = versions,
            filesCount = tonumber(p.filesCount) or 0,
            controlState = tostring(p.controlState or "UNKNOWN"),
            isAirborne = (p.isAirborne == true),
            freeSpace = tonumber(p.freeSpace) or 0,
            agentVer = tostring(p.agentVer or "0.0.0"),
            bayId = bayId,
            safeForOta = safe,
            denyReason = denyReason,
        }
        return false
    end)

    local nodes = {}
    for _, item in pairs(byKey) do
        nodes[#nodes + 1] = item
    end
    table.sort(nodes, function(a, b)
        if a.domainId ~= b.domainId then
            return a.domainId < b.domainId
        end
        return a.moduleId < b.moduleId
    end)
    return nodes, waitErr
end

function ServerMT:_abort_tx(cmdCh, ackCh, txId, targetDomainId, targetModuleId, reason)
    self:_transmit(cmdCh, ackCh, "MSG_OTA_ABORT", {
        txId = txId,
        targetDomainId = targetDomainId,
        targetModuleId = targetModuleId,
        reason = tostring(reason or "ABORTED"),
    })
end

function ServerMT:_send_with_retry(cmdCh, ackCh, txId, targetDomainId, targetModuleId, msgType, payload, matchFn, maxRetries, ackTimeoutSec, progressInfo, expectedNext)
    local lastReason = "TIMEOUT"
    for attempt = 0, maxRetries do
        self:_transmit(cmdCh, ackCh, msgType, payload)
        local replyPkt, waitErr = self:_wait_for_packet(ackCh, ackTimeoutSec, function(pkt)
            if pkt.type ~= "MSG_OTA_ACK" and pkt.type ~= "MSG_OTA_NACK" then
                return false
            end
            local p = pkt.payload
            if p.txId ~= txId or p.moduleId ~= targetModuleId then
                return false
            end
            return matchFn(pkt)
        end)

        if replyPkt then
            local p = replyPkt.payload
            if replyPkt.type == "MSG_OTA_ACK" then
                return true, replyPkt, nil
            end
            -- Handle MSG_OTA_NACK
            local reason = tostring(p.reason or "NACK")
            lastReason = reason
            if msgType == "MSG_OTA_CHUNK" and reason == "SEQ_OUT_OF_ORDER"
                and attempt > 0 and type(p.expectedIndex) == "number" then
                local targetNext = expectedNext or (payload.chunkIndex + 1)
                if p.expectedIndex == targetNext then
                    return true, replyPkt, nil
                end
            end
            if FATAL_NACK_REASONS[reason] or msgType ~= "MSG_OTA_CHUNK" then
                return false, nil, reason
            end
        else
            lastReason = tostring(waitErr or "TIMEOUT")
            if lastReason == "ABORTED_BY_SIGNAL" then
                return false, nil, lastReason
            end
        end

        if attempt < maxRetries and progressInfo and type(progressInfo.onProgress) == "function" then
            progressInfo.onProgress({
                stage = "RETRY",
                attempt = attempt + 1,
                txId = txId,
                sentChunks = progressInfo.sentChunks,
                totalChunks = progressInfo.totalChunks,
            })
        end
    end

    return false, nil, lastReason
end

--- Deploys a verified package wirelessly to a target onboard node.
-- @param targetSpec table { domainId, moduleId, bayId, overwriteConfig, autoReboot }
-- @param package table Package table from load_package() or { moduleId, version, files = {{ path, content }} }
-- @param opts table|nil { bayId, chunkSize, ackTimeoutSec, maxRetries, overwriteConfig, autoReboot, awaitBootStatus, bootStatusTimeoutSec, txId, onProgress }
-- @return boolean success, table result
function ServerMT:deploy(targetSpec, package, opts)
    opts = opts or {}
    if not self.modem or type(self.modem.transmit) ~= "function" then
        return false, { reason = "NO_MODEM" }
    end
    if type(targetSpec) ~= "table" or type(targetSpec.domainId) ~= "string" or targetSpec.domainId == "" then
        return false, { reason = "INVALID_DEPLOY_ARGS" }
    end
    if type(package) ~= "table" or type(package.files) ~= "table" or #package.files == 0 then
        return false, { reason = "INVALID_DEPLOY_ARGS" }
    end

    local targetDomainId = targetSpec.domainId
    local targetModuleId = (type(targetSpec.moduleId) == "string" and targetSpec.moduleId ~= "")
        and targetSpec.moduleId
        or tostring(package.moduleId or "")
    if targetModuleId == "" then
        return false, { reason = "INVALID_DEPLOY_ARGS" }
    end

    local bayId = opts.bayId or targetSpec.bayId or self.bayId
    local _, cmdCh, ackCh = self:_ensure_bay_channels(bayId)
    local chunkSize = math.max(1, math.floor(tonumber(opts.chunkSize) or self.chunkSize))
    local ackTimeoutSec = tonumber(opts.ackTimeoutSec) or self.ackTimeoutSec
    local maxRetries = math.max(0, math.floor(tonumber(opts.maxRetries) or self.maxRetries))
    local overwriteConfig = (opts.overwriteConfig == true) or (targetSpec.overwriteConfig == true) or false
    local autoReboot = (opts.autoReboot == true) or (targetSpec.autoReboot == true) or false
    local txId = (type(opts.txId) == "string" and opts.txId ~= "")
        and opts.txId
        or ("tx-" .. tostring(math.floor(self.clockFn())) .. "-" .. tostring(self:_next_seq()))

    local fileManifests = {}
    local fileChunks = {}
    local allContents = {}
    local totalBytes = 0
    local totalChunks = 0

    for idx, fileEntry in ipairs(package.files) do
        local content = tostring(fileEntry.content or "")
        local fMan, chunks = ota_protocol.chunk_file(fileEntry.path, content, chunkSize)
        fileManifests[idx] = fMan
        fileChunks[idx] = chunks
        allContents[idx] = content
        totalBytes = totalBytes + fMan.size
        totalChunks = totalChunks + fMan.chunkCount
    end
    local totalCrc32 = ota_agent.crc32(table.concat(allContents))

    local onProgress = opts.onProgress
    if type(onProgress) == "function" then
        onProgress({ stage = "BEGIN", txId = txId, sentChunks = 0, totalChunks = totalChunks })
    end

    -- 1. MSG_OTA_BEGIN
    local okBegin, _, beginErr = self:_send_with_retry(
        cmdCh, ackCh, txId, targetDomainId, targetModuleId,
        "MSG_OTA_BEGIN",
        {
            txId = txId,
            targetDomainId = targetDomainId,
            targetModuleId = targetModuleId,
            targetVersion = tostring(package.version or "0.0.0"),
            files = fileManifests,
            totalBytes = totalBytes,
            totalCrc32 = totalCrc32,
            overwriteConfig = overwriteConfig,
        },
        function(pkt)
            return pkt.payload.phase == "BEGIN"
        end,
        maxRetries,
        ackTimeoutSec
    )
    if not okBegin then
        self:_abort_tx(cmdCh, ackCh, txId, targetDomainId, targetModuleId, beginErr)
        return false, { reason = beginErr, phase = "BEGIN", txId = txId }
    end

    -- 2. MSG_OTA_CHUNK loop
    local sentChunks = 0
    for fileIdx, chunks in ipairs(fileChunks) do
        local chunkCount = #chunks
        for _, chunk in ipairs(chunks) do
            local expectedNext = (chunk.chunkIndex == chunkCount) and 1 or (chunk.chunkIndex + 1)
            local okChunk, _, chunkErr = self:_send_with_retry(
                cmdCh, ackCh, txId, targetDomainId, targetModuleId,
                "MSG_OTA_CHUNK",
                {
                    txId = txId,
                    targetDomainId = targetDomainId,
                    targetModuleId = targetModuleId,
                    fileIndex = fileIdx,
                    chunkIndex = chunk.chunkIndex,
                    chunkCrc32 = chunk.chunkCrc32,
                    data = chunk.data,
                },
                function(pkt)
                    if pkt.type == "MSG_OTA_NACK" then
                        return pkt.payload.phase == "CHUNK"
                    end
                    return pkt.payload.phase == "CHUNK"
                        and pkt.payload.fileIndex == fileIdx
                        and pkt.payload.chunkIndex == chunk.chunkIndex
                end,
                maxRetries,
                ackTimeoutSec,
                { onProgress = onProgress, sentChunks = sentChunks, totalChunks = totalChunks },
                expectedNext
            )
            if not okChunk then
                self:_abort_tx(cmdCh, ackCh, txId, targetDomainId, targetModuleId, chunkErr)
                return false, {
                    reason = chunkErr,
                    phase = "CHUNK",
                    fileIndex = fileIdx,
                    chunkIndex = chunk.chunkIndex,
                    txId = txId,
                }
            end
            sentChunks = sentChunks + 1
            if type(onProgress) == "function" then
                onProgress({
                    stage = "CHUNK",
                    txId = txId,
                    fileIndex = fileIdx,
                    chunkIndex = chunk.chunkIndex,
                    sentChunks = sentChunks,
                    totalChunks = totalChunks,
                })
            end
        end
    end

    -- 3. MSG_OTA_COMMIT
    if type(onProgress) == "function" then
        onProgress({ stage = "COMMIT", txId = txId, sentChunks = sentChunks, totalChunks = totalChunks })
    end
    local okCommit, commitAck, commitErr = self:_send_with_retry(
        cmdCh, ackCh, txId, targetDomainId, targetModuleId,
        "MSG_OTA_COMMIT",
        {
            txId = txId,
            targetDomainId = targetDomainId,
            targetModuleId = targetModuleId,
            autoReboot = autoReboot,
        },
        function(pkt)
            return pkt.payload.phase == "APPLIED" or pkt.payload.phase == "COMMIT"
        end,
        0,
        ackTimeoutSec
    )
    if not okCommit then
        self:_abort_tx(cmdCh, ackCh, txId, targetDomainId, targetModuleId, commitErr)
        return false, { reason = commitErr, phase = "COMMIT", txId = txId }
    end

    -- 4. Optional Stage 2 MSG_OTA_BOOT_STATUS wait
    if opts.awaitBootStatus == true then
        local bootWait = tonumber(opts.bootStatusTimeoutSec) or 10.0
        local bootPkt, bootErr = self:_wait_for_packet(ackCh, bootWait, function(pkt)
            if pkt.type ~= "MSG_OTA_BOOT_STATUS" then
                return false
            end
            local p = pkt.payload
            return p.txId == txId and p.moduleId == targetModuleId
        end)
        if not bootPkt then
            return false, {
                reason = (bootErr == "ABORTED_BY_SIGNAL") and "ABORTED_BY_SIGNAL" or "BOOT_STATUS_TIMEOUT",
                phase = "BOOT_STATUS",
                txId = txId,
            }
        end
        if bootPkt.payload.status ~= "COMMITTED" then
            return false, {
                reason = tostring(bootPkt.payload.status or "ROLLED_BACK"),
                rollbackReason = bootPkt.payload.rollbackReason,
                version = bootPkt.payload.version,
                phase = "BOOT_STATUS",
                txId = txId,
            }
        end
        return true, {
            txId = txId,
            phase = "BOOT_STATUS",
            status = "COMMITTED",
            version = bootPkt.payload.version,
            sentChunks = sentChunks,
            totalChunks = totalChunks,
            bayId = bayId,
        }
    end

    return true, {
        txId = txId,
        phase = "APPLIED",
        status = commitAck.payload.status,
        sentChunks = sentChunks,
        totalChunks = totalChunks,
        bayId = bayId,
    }
end

return ota_server
