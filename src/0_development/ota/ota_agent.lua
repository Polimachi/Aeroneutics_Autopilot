-- src/0_development/ota/ota_agent.lua
-- Self-contained Hangar Wireless OTA Slave Agent & IEEE 802.3 CRC32 (Zero external require)

local ota_agent = {}

ota_agent.AGENT_VERSION = "1.0.0"
ota_agent.ICD_VERSION = "1.9.5"
ota_agent.HANGAR_BAY_BASE = 101
ota_agent.HANGAR_BAY_BANDWIDTH = 10
ota_agent.OFFSET_CMD = 4
ota_agent.OFFSET_ACK = 5
ota_agent.DEFAULT_BOOT_CONFIRM_TICKS = 20

local ALLOWED_CONTROL_STATES = {
    DISARMED = true,
    BOOT = true,
    IDLE_ARMED = true,
}

local CRC32_POLY = 0xEDB88320
local CRC32_ALL_ONES = 0xFFFFFFFF
local _bit32CrcTable = nil
local _pureCrcTable = nil
local _pureXor4 = nil

-- =========================================================================
-- IEEE 802.3 CRC32 (bit32 primary + pure-Lua 5.2 fallback)
-- =========================================================================

local function get_pure_xor4()
    if _pureXor4 then
        return _pureXor4
    end
    local tbl = {}
    for a = 0, 15 do
        local row = {}
        for b = 0, 15 do
            local r, x, y, bitVal = 0, a, b, 1
            for _ = 1, 4 do
                local rx = x % 2
                local ry = y % 2
                if rx ~= ry then
                    r = r + bitVal
                end
                x = (x - rx) / 2
                y = (y - ry) / 2
                bitVal = bitVal * 2
            end
            row[b] = r
        end
        tbl[a] = row
    end
    _pureXor4 = tbl
    return tbl
end

local function pure_bxor32(a, b)
    local xor4 = get_pure_xor4()
    local res = 0
    local mul = 1
    while a > 0 or b > 0 do
        local ra = a % 16
        local rb = b % 16
        res = res + xor4[ra][rb] * mul
        a = (a - ra) / 16
        b = (b - rb) / 16
        mul = mul * 16
    end
    return res
end

local function get_pure_nibble_crc_table()
    if _pureCrcTable then
        return _pureCrcTable
    end
    local tbl = {}
    for i = 0, 15 do
        local c = i
        for _ = 1, 4 do
            if c % 2 == 1 then
                c = pure_bxor32((c - 1) / 2, CRC32_POLY)
            else
                c = c / 2
            end
        end
        tbl[i] = c
    end
    _pureCrcTable = tbl
    return tbl
end

local function get_bit32_crc_table(b32)
    if _bit32CrcTable then
        return _bit32CrcTable
    end
    local tbl = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if b32.band(c, 1) == 1 then
                c = b32.bxor(b32.rshift(c, 1), CRC32_POLY)
            else
                c = b32.rshift(c, 1)
            end
        end
        tbl[i] = c
    end
    _bit32CrcTable = tbl
    return tbl
end

local function crc32_update(crc, str)
    local b32 = _G.bit32
    if b32 and type(b32.bxor) == "function" and type(b32.rshift) == "function" and type(b32.band) == "function" then
        local tbl = get_bit32_crc_table(b32)
        local bxor, band, rshift = b32.bxor, b32.band, b32.rshift
        local n = #str
        for i = 1, n do
            local idx = band(bxor(crc, string.byte(str, i)), 0xFF)
            crc = bxor(rshift(crc, 8), tbl[idx])
        end
        return crc
    end

    local xor4 = get_pure_xor4()
    local tbl = get_pure_nibble_crc_table()
    local n = #str
    for i = 1, n do
        local b = string.byte(str, i)
        local lo = b % 16
        local hi = (b - lo) / 16
        crc = pure_bxor32(math.floor(crc / 16), tbl[xor4[crc % 16][lo]])
        crc = pure_bxor32(math.floor(crc / 16), tbl[xor4[crc % 16][hi]])
    end
    return crc
end

local function crc32_finalize(crc)
    local b32 = _G.bit32
    if b32 and type(b32.bxor) == "function" then
        return b32.bxor(crc, CRC32_ALL_ONES)
    end
    return CRC32_ALL_ONES - crc
end

--- Computes IEEE 802.3 CRC32 (0xEDB88320) over an arbitrary byte string.
-- Uses bit32 when present and falls back to pure-Lua 5.2 arithmetic when absent.
-- @param str string Input payload bytes
-- @return number Unsigned 32-bit CRC32 integer
function ota_agent.crc32(str)
    if type(str) ~= "string" then
        error("crc32 expects a string argument", 2)
    end
    return crc32_finalize(crc32_update(CRC32_ALL_ONES, str))
end

-- =========================================================================
-- Hangar Bay Channels & Safety Gate
-- =========================================================================

--- Computes hangar OTA command (+4) and ACK (+5) channels for a given bay.
-- @param bayId number Hangar bay index (1..10)
-- @return number cmdCh, number ackCh
function ota_agent.get_channels(bayId)
    local id = tonumber(bayId)
    if not id or id < 1 or id > 10 or math.floor(id) ~= id then
        error("Invalid hangar bayId (expected integer 1..10): " .. tostring(bayId), 2)
    end
    local base = ota_agent.HANGAR_BAY_BASE + (id - 1) * ota_agent.HANGAR_BAY_BANDWIDTH
    return base + ota_agent.OFFSET_CMD, base + ota_agent.OFFSET_ACK
end

--- Enforces the slave OTA safety gate truth table.
-- Allows OTA only when status.isAirborne ~= true and controlState is DISARMED, BOOT, or IDLE_ARMED.
-- @param status table|nil Current node flight/control status
-- @return boolean safe, string|nil denyReason
function ota_agent.is_safe_for_ota(status)
    if type(status) ~= "table" then
        return false, "NOT_DISARMED"
    end
    if status.isAirborne == true then
        return false, "NOT_DISARMED"
    end
    if type(status.controlState) ~= "string" or not ALLOWED_CONTROL_STATES[status.controlState] then
        return false, "NOT_DISARMED"
    end
    return true, nil
end

-- =========================================================================
-- Path & File System Helpers
-- =========================================================================

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

local function normalize_rel_path(rawPath)
    if type(rawPath) ~= "string" or rawPath == "" then
        return nil
    end
    local p = rawPath:gsub("\\", "/")
    if p:find("..", 1, true) then
        return nil
    end
    while p:sub(1, 1) == "/" do
        p = p:sub(2)
    end
    while #p > 0 and p:sub(-1) == "/" do
        p = p:sub(1, -2)
    end
    if p == "" then
        return nil
    end
    return "/" .. p
end

local function resolve_path(rootDir, relPath)
    local norm = normalize_rel_path(relPath)
    if not norm then
        return nil
    end
    if rootDir == "/" then
        return norm
    end
    return rootDir .. norm
end

local function is_config_path(normPath)
    return type(normPath) == "string" and normPath:match("/config/.*%.json$") ~= nil
end

local function is_lib_path(normPath)
    return type(normPath) == "string" and normPath:sub(1, 5) == "/lib/"
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

local function safe_delete(fsApi, path)
    if not path or not fsApi.exists(path) then
        return true, nil
    end
    local okDel, errDel = pcall(fsApi.delete, path)
    if not okDel then
        return false, tostring(errDel)
    end
    return true, nil
end

local function safe_copy(fsApi, srcPath, destPath)
    local okDir, errDir = ensure_parent_dir(fsApi, destPath)
    if not okDir then
        return false, errDir
    end
    local okDel, errDel = safe_delete(fsApi, destPath)
    if not okDel then
        return false, errDel
    end
    local okCp, errCp = pcall(fsApi.copy, srcPath, destPath)
    if not okCp then
        return false, tostring(errCp)
    end
    return true, nil
end

local function read_all_file(fsApi, path)
    if not fsApi.exists(path) then
        return nil, "NOT_FOUND"
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
        return nil, errRead
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

local function write_json_atomic(fsApi, path, tbl)
    if not textutils or type(textutils.serializeJSON) ~= "function" then
        return false, "JSON_UNAVAILABLE"
    end
    local okDir, errDir = ensure_parent_dir(fsApi, path)
    if not okDir then
        return false, errDir
    end
    local okSer, jsonStr = pcall(textutils.serializeJSON, tbl)
    if not okSer or type(jsonStr) ~= "string" then
        return false, "JSON_SERIALIZE_FAILED"
    end
    local tmpPath = path .. ".tmp"
    local h = fsApi.open(tmpPath, "w")
    if not h then
        return false, "OPEN_TMP_FAILED"
    end
    h.write(jsonStr)
    h.close()

    local okDel, errDel = safe_delete(fsApi, path)
    if not okDel then
        safe_delete(fsApi, tmpPath)
        return false, errDel
    end
    local okMv, errMv = pcall(fsApi.move, tmpPath, path)
    if not okMv then
        safe_delete(fsApi, tmpPath)
        return false, tostring(errMv)
    end
    return true, nil
end

-- =========================================================================
-- Envelope & Messaging Helpers (ICD 1.9.5 Zero-Fallback)
-- =========================================================================

local function is_valid_envelope(pkt)
    if type(pkt) ~= "table" then
        return false
    end
    if pkt.ver ~= ota_agent.ICD_VERSION then
        return false
    end
    if type(pkt.domainId) ~= "string" or pkt.domainId == "" then
        return false
    end
    if type(pkt.seq) ~= "number" then
        return false
    end
    if type(pkt.type) ~= "string" or pkt.type == "" then
        return false
    end
    if type(pkt.time) ~= "number" then
        return false
    end
    if type(pkt.payload) ~= "table" then
        return false
    end
    return true
end

local function build_envelope(self, msgType, payload)
    return {
        ver = ota_agent.ICD_VERSION,
        domainId = self.domainId,
        seq = self.seqFn(),
        type = msgType,
        time = self.clockFn(),
        payload = payload,
    }
end

local function transmit_reply(self, cmdCh, msgType, payload)
    local modem = self.modemApi
    if not modem or type(modem.transmit) ~= "function" then
        return
    end
    local txCh = self.cmdChToAckCh[cmdCh] or self.primaryAckCh
    local replyCh = cmdCh or self.primaryCmdCh
    pcall(modem.transmit, txCh, replyCh, build_envelope(self, msgType, payload))
end

local function send_ack(self, cmdCh, txId, phase, status, extra)
    local payload = {
        txId = tostring(txId or ""),
        moduleId = self.moduleId,
        phase = phase,
        status = status,
    }
    if type(extra) == "table" then
        if extra.fileIndex ~= nil then
            payload.fileIndex = extra.fileIndex
        end
        if extra.chunkIndex ~= nil then
            payload.chunkIndex = extra.chunkIndex
        end
    end
    transmit_reply(self, cmdCh, "MSG_OTA_ACK", payload)
end

local function send_nack(self, cmdCh, txId, phase, reason, expectedIndex)
    local payload = {
        txId = tostring(txId or ""),
        moduleId = self.moduleId,
        phase = phase,
        reason = reason,
    }
    if expectedIndex ~= nil then
        payload.expectedIndex = expectedIndex
    end
    transmit_reply(self, cmdCh, "MSG_OTA_NACK", payload)
end

local function send_boot_status(self, txId, moduleId, statusStr, versionStr, rollbackReason)
    local payload = {
        txId = tostring(txId or ""),
        moduleId = tostring(moduleId or self.moduleId),
        status = statusStr,
        version = tostring(versionStr or "0.0.0-untracked"),
    }
    if rollbackReason ~= nil then
        payload.rollbackReason = tostring(rollbackReason)
    end
    transmit_reply(self, self.primaryCmdCh, "MSG_OTA_BOOT_STATUS", payload)
end

-- =========================================================================
-- Staging, Verification & Atomic Apply Helpers
-- =========================================================================

local function staged_file_path(stagingDir, fileIndex)
    return stagingDir .. "/file_" .. tostring(fileIndex) .. ".part"
end

local function cleanup_active_tx(self)
    if self.activeTx and self.activeTx.stagingDir then
        safe_delete(self.fsApi, self.activeTx.stagingDir)
    end
    self.activeTx = nil
end

local function advance_empty_files(self, tx)
    while tx.expectedFileIndex <= #tx.files do
        local fSpec = tx.files[tx.expectedFileIndex]
        if fSpec.chunkCount > 0 then
            break
        end
        local sPath = staged_file_path(tx.stagingDir, tx.expectedFileIndex)
        local h = self.fsApi.open(sPath, "w")
        if not h then
            return false, "DISK_ERROR"
        end
        h.close()
        tx.expectedFileIndex = tx.expectedFileIndex + 1
        tx.expectedChunkIndex = 1
    end
    return true, nil
end

local function verify_staged_package(self, tx)
    if tx.expectedFileIndex <= #tx.files then
        return false, "CRC_MISMATCH"
    end
    local runningCrc = CRC32_ALL_ONES
    local totalBytes = 0
    for idx, fSpec in ipairs(tx.files) do
        local sPath = staged_file_path(tx.stagingDir, idx)
        local content, errRead = read_all_file(self.fsApi, sPath)
        if not content then
            return false, errRead or "CRC_MISMATCH"
        end
        if #content ~= fSpec.size then
            return false, "CRC_MISMATCH"
        end
        if ota_agent.crc32(content) ~= fSpec.crc32 then
            return false, "CRC_MISMATCH"
        end
        runningCrc = crc32_update(runningCrc, content)
        totalBytes = totalBytes + #content
    end
    if totalBytes ~= tx.totalBytes then
        return false, "CRC_MISMATCH"
    end
    if crc32_finalize(runningCrc) ~= tx.totalCrc32 then
        return false, "CRC_MISMATCH"
    end
    return true, nil
end

local function load_version_meta(self)
    local verPath = resolve_path(self.rootDir, "/.version.json")
    local meta = read_json_file(self.fsApi, verPath)
    if type(meta) ~= "table" then
        meta = { modules = {} }
    end
    if type(meta.modules) ~= "table" then
        meta.modules = {}
    end
    return verPath, meta
end

local function collect_orphans(self, meta, newFilesSet)
    local modRec = meta.modules[self.moduleId]
    if type(modRec) ~= "table" or type(modRec.files) ~= "table" then
        return {}
    end
    local otherSet = {}
    for mId, mInfo in pairs(meta.modules) do
        if mId ~= self.moduleId and type(mInfo) == "table" and type(mInfo.files) == "table" then
            for _, fPath in ipairs(mInfo.files) do
                local norm = normalize_rel_path(fPath)
                if norm then
                    otherSet[norm] = true
                end
            end
        end
    end

    local orphans = {}
    for _, prevPath in ipairs(modRec.files) do
        local norm = normalize_rel_path(prevPath)
        if norm and not newFilesSet[norm] and not otherSet[norm] and not is_lib_path(norm) and not is_config_path(norm) then
            local livePath = resolve_path(self.rootDir, norm)
            if livePath and self.fsApi.exists(livePath) and not self.fsApi.isDir(livePath) then
                orphans[#orphans + 1] = { norm = norm, live = livePath }
            end
        end
    end
    return orphans
end

local function rollback_inline(fsApi, restoredFiles, versionBackupPath, verPath, backupDir, pendingPath)
    for _, item in ipairs(restoredFiles) do
        if item.existed == true then
            if item.src and fsApi.exists(item.src) then
                safe_copy(fsApi, item.src, item.dest)
            end
        elseif item.existed == false then
            safe_delete(fsApi, item.dest)
        end
    end
    if versionBackupPath and fsApi.exists(versionBackupPath) then
        safe_copy(fsApi, versionBackupPath, verPath)
    end
    safe_delete(fsApi, pendingPath)
    safe_delete(fsApi, backupDir)
end

local function apply_committed_tx(self, tx)
    local fsApi = self.fsApi
    local verPath, meta = load_version_meta(self)
    local backupDir = resolve_path(self.rootDir, "/ota_backup/" .. tx.txId)
    local versionBackupPath = backupDir .. "/.version.json"
    local pendingPath = resolve_path(self.rootDir, "/.ota_pending.json")

    safe_delete(fsApi, backupDir)
    local okMk, errMk = pcall(fsApi.makeDir, backupDir)
    if not okMk then
        return false, tostring(errMk)
    end

    if fsApi.exists(verPath) then
        local okVerBak, errVerBak = safe_copy(fsApi, verPath, versionBackupPath)
        if not okVerBak then
            safe_delete(fsApi, backupDir)
            return false, errVerBak
        end
    end

    local newFilesSet = {}
    local newFilesList = {}
    local applyPlan = {}
    local restoredFiles = {}

    for idx, fSpec in ipairs(tx.files) do
        local norm = fSpec.normPath
        newFilesSet[norm] = true
        newFilesList[#newFilesList + 1] = norm
        local livePath = resolve_path(self.rootDir, norm)
        local shouldSkipConfig = is_config_path(norm) and fsApi.exists(livePath) and not tx.overwriteConfig
        if not shouldSkipConfig then
            local existed = fsApi.exists(livePath)
            if existed then
                local bakPath = backupDir .. "/files" .. norm
                local okBak, errBak = safe_copy(fsApi, livePath, bakPath)
                if not okBak then
                    safe_delete(fsApi, backupDir)
                    return false, errBak
                end
                restoredFiles[#restoredFiles + 1] = { src = bakPath, dest = livePath, existed = true }
            else
                restoredFiles[#restoredFiles + 1] = { src = "", dest = livePath, existed = false }
            end
            applyPlan[#applyPlan + 1] = {
                staged = staged_file_path(tx.stagingDir, idx),
                dest = livePath,
            }
        end
    end

    local orphans = collect_orphans(self, meta, newFilesSet)
    for _, orph in ipairs(orphans) do
        local bakPath = backupDir .. "/files" .. orph.norm
        local okBak, errBak = safe_copy(fsApi, orph.live, bakPath)
        if not okBak then
            safe_delete(fsApi, backupDir)
            return false, errBak
        end
        restoredFiles[#restoredFiles + 1] = { src = bakPath, dest = orph.live, existed = true }
    end

    local pendingRecord = {
        txId = tx.txId,
        moduleId = self.moduleId,
        targetVersion = tx.targetVersion,
        backupDir = backupDir,
        versionBackupPath = versionBackupPath,
        restoredFiles = restoredFiles,
        bootAttempts = 0,
        maxBootAttempts = 1,
        status = "PENDING_COMMIT",
    }
    local okPend, errPend = write_json_atomic(fsApi, pendingPath, pendingRecord)
    if not okPend then
        safe_delete(fsApi, backupDir)
        return false, errPend
    end

    for _, item in ipairs(applyPlan) do
        local okSw, errSw = safe_copy(fsApi, item.staged, item.dest)
        if not okSw then
            rollback_inline(fsApi, restoredFiles, versionBackupPath, verPath, backupDir, pendingPath)
            return false, errSw
        end
    end

    for _, orph in ipairs(orphans) do
        local okDel, errDel = safe_delete(fsApi, orph.live)
        if not okDel then
            rollback_inline(fsApi, restoredFiles, versionBackupPath, verPath, backupDir, pendingPath)
            return false, errDel
        end
    end

    meta.modules[self.moduleId] = {
        id = self.moduleId,
        version = tx.targetVersion,
        files = newFilesList,
        source = "ota",
        installedAt = self.clockFn(),
    }
    local okVerSave, errVerSave = write_json_atomic(fsApi, verPath, meta)
    if not okVerSave then
        rollback_inline(fsApi, restoredFiles, versionBackupPath, verPath, backupDir, pendingPath)
        return false, errVerSave
    end

    return true, nil
end

-- =========================================================================
-- Packet Type Handlers
-- =========================================================================

local function check_target_addressing(self, cmdCh, p, phase)
    if type(p.targetModuleId) ~= "string" or type(p.targetDomainId) ~= "string" then
        return false, "INVALID_PAYLOAD"
    end
    if p.targetModuleId ~= self.moduleId then
        return false, "IGNORED"
    end
    if p.targetDomainId ~= self.domainId then
        send_nack(self, cmdCh, p.txId, phase, "DOMAIN_MISMATCH")
        return false, "DOMAIN_MISMATCH"
    end
    return true, nil
end

local function handle_discover(self, cmdCh, p)
    if type(p.targetModuleId) ~= "string" or type(p.targetDomainId) ~= "string" then
        return false, "INVALID_PAYLOAD"
    end
    if p.targetModuleId ~= "*" and p.targetModuleId ~= self.moduleId then
        return false, "IGNORED"
    end
    if p.targetDomainId ~= "*" and p.targetDomainId ~= self.domainId then
        return false, "IGNORED"
    end

    local _, meta = load_version_meta(self)
    local versions = {}
    for mId, mInfo in pairs(meta.modules) do
        if type(mInfo) == "table" and type(mInfo.version) == "string" then
            versions[mId] = mInfo.version
        end
    end
    if versions[self.moduleId] == nil then
        versions[self.moduleId] = "0.0.0-untracked"
    end

    local filesCount = 0
    local ownMod = meta.modules[self.moduleId]
    if type(ownMod) == "table" and type(ownMod.files) == "table" then
        filesCount = #ownMod.files
    end

    local status = self.getStatusFn()
    local controlState = (type(status) == "table" and type(status.controlState) == "string") and status.controlState or "UNKNOWN"
    local isAirborne = (type(status) == "table" and status.isAirborne == true) or false

    local freeSpace = 0
    if self.fsApi.getFreeSpace then
        local okFs, spaceVal = pcall(self.fsApi.getFreeSpace, self.rootDir)
        if okFs and type(spaceVal) == "number" then
            freeSpace = spaceVal
        end
    end

    transmit_reply(self, cmdCh, "MSG_OTA_DISCOVER_ACK", {
        moduleId = self.moduleId,
        versions = versions,
        filesCount = filesCount,
        controlState = controlState,
        isAirborne = isAirborne,
        freeSpace = freeSpace,
        agentVer = ota_agent.AGENT_VERSION,
    })
    return true, "DISCOVER_ACK"
end

local function validate_begin_files(rawFiles)
    if type(rawFiles) ~= "table" or #rawFiles == 0 then
        return nil
    end
    local normalized = {}
    for idx, entry in ipairs(rawFiles) do
        if type(entry) ~= "table" then
            return nil
        end
        local norm = normalize_rel_path(entry.path)
        if not norm or type(entry.size) ~= "number" or entry.size < 0
            or type(entry.crc32) ~= "number"
            or type(entry.chunkCount) ~= "number" or entry.chunkCount < 0 then
            return nil
        end
        normalized[idx] = {
            normPath = norm,
            size = entry.size,
            crc32 = entry.crc32,
            chunkCount = entry.chunkCount,
        }
    end
    return normalized
end

local function handle_begin(self, cmdCh, p)
    local okAddr, errAddr = check_target_addressing(self, cmdCh, p, "BEGIN")
    if not okAddr then
        return false, errAddr
    end
    local safe, denyReason = ota_agent.is_safe_for_ota(self.getStatusFn())
    if not safe then
        send_nack(self, cmdCh, p.txId, "BEGIN", denyReason)
        return false, denyReason
    end

    local parsedFiles = validate_begin_files(p.files)
    if type(p.txId) ~= "string" or p.txId == ""
        or type(p.targetVersion) ~= "string" or p.targetVersion == ""
        or type(p.totalBytes) ~= "number" or p.totalBytes < 0
        or type(p.totalCrc32) ~= "number"
        or not parsedFiles then
        return false, "INVALID_PAYLOAD"
    end

    if self.fsApi.getFreeSpace then
        local okFs, freeVal = pcall(self.fsApi.getFreeSpace, self.rootDir)
        if okFs and type(freeVal) == "number" and freeVal < p.totalBytes then
            send_nack(self, cmdCh, p.txId, "BEGIN", "DISK_ERROR")
            return false, "DISK_ERROR"
        end
    end

    cleanup_active_tx(self)
    local stagingDir = resolve_path(self.rootDir, "/ota_staging/" .. p.txId)
    if not stagingDir then
        send_nack(self, cmdCh, p.txId, "BEGIN", "DISK_ERROR")
        return false, "DISK_ERROR"
    end
    safe_delete(self.fsApi, stagingDir)
    local okMk = pcall(self.fsApi.makeDir, stagingDir)
    if not okMk then
        send_nack(self, cmdCh, p.txId, "BEGIN", "DISK_ERROR")
        return false, "DISK_ERROR"
    end

    local tx = {
        txId = p.txId,
        targetVersion = p.targetVersion,
        files = parsedFiles,
        totalBytes = p.totalBytes,
        totalCrc32 = p.totalCrc32,
        overwriteConfig = (p.overwriteConfig == true),
        stagingDir = stagingDir,
        expectedFileIndex = 1,
        expectedChunkIndex = 1,
    }

    local okAdv, errAdv = advance_empty_files(self, tx)
    if not okAdv then
        safe_delete(self.fsApi, stagingDir)
        send_nack(self, cmdCh, p.txId, "BEGIN", errAdv)
        return false, errAdv
    end

    self.activeTx = tx
    send_ack(self, cmdCh, p.txId, "BEGIN", "READY")
    return true, "BEGIN_ACK"
end

local function handle_chunk(self, cmdCh, p)
    local okAddr, errAddr = check_target_addressing(self, cmdCh, p, "CHUNK")
    if not okAddr then
        return false, errAddr
    end
    local safe, denyReason = ota_agent.is_safe_for_ota(self.getStatusFn())
    if not safe then
        send_nack(self, cmdCh, p.txId, "CHUNK", denyReason)
        return false, denyReason
    end

    local tx = self.activeTx
    if not tx or tx.txId ~= p.txId then
        send_nack(self, cmdCh, p.txId, "CHUNK", "TX_NOT_FOUND")
        return false, "TX_NOT_FOUND"
    end

    if p.fileIndex ~= tx.expectedFileIndex or p.chunkIndex ~= tx.expectedChunkIndex then
        send_nack(self, cmdCh, p.txId, "CHUNK", "SEQ_OUT_OF_ORDER", tx.expectedChunkIndex)
        return false, "SEQ_OUT_OF_ORDER"
    end

    if type(p.data) ~= "string" or type(p.chunkCrc32) ~= "number" or ota_agent.crc32(p.data) ~= p.chunkCrc32 then
        send_nack(self, cmdCh, p.txId, "CHUNK", "CRC_MISMATCH")
        return false, "CRC_MISMATCH"
    end

    local sPath = staged_file_path(tx.stagingDir, tx.expectedFileIndex)
    local mode = (tx.expectedChunkIndex == 1) and "w" or "a"
    local h = self.fsApi.open(sPath, mode)
    if not h then
        send_nack(self, cmdCh, p.txId, "CHUNK", "DISK_ERROR")
        return false, "DISK_ERROR"
    end
    h.write(p.data)
    h.close()

    local curSpec = tx.files[tx.expectedFileIndex]
    if tx.expectedChunkIndex >= curSpec.chunkCount then
        tx.expectedFileIndex = tx.expectedFileIndex + 1
        tx.expectedChunkIndex = 1
        local okAdv, errAdv = advance_empty_files(self, tx)
        if not okAdv then
            send_nack(self, cmdCh, p.txId, "CHUNK", errAdv)
            return false, errAdv
        end
    else
        tx.expectedChunkIndex = tx.expectedChunkIndex + 1
    end

    send_ack(self, cmdCh, p.txId, "CHUNK", "OK", {
        fileIndex = p.fileIndex,
        chunkIndex = p.chunkIndex,
    })
    return true, "CHUNK_ACK"
end

local function handle_commit(self, cmdCh, p)
    local okAddr, errAddr = check_target_addressing(self, cmdCh, p, "COMMIT")
    if not okAddr then
        return false, errAddr
    end
    local safe, denyReason = ota_agent.is_safe_for_ota(self.getStatusFn())
    if not safe then
        send_nack(self, cmdCh, p.txId, "COMMIT", denyReason)
        return false, denyReason
    end

    local tx = self.activeTx
    if not tx or tx.txId ~= p.txId then
        send_nack(self, cmdCh, p.txId, "COMMIT", "TX_NOT_FOUND")
        return false, "TX_NOT_FOUND"
    end

    local okVerify, errVerify = verify_staged_package(self, tx)
    if not okVerify then
        cleanup_active_tx(self)
        send_nack(self, cmdCh, p.txId, "COMMIT", "CRC_MISMATCH")
        return false, errVerify
    end

    local okApply, errApply = apply_committed_tx(self, tx)
    cleanup_active_tx(self)
    if not okApply then
        send_nack(self, cmdCh, p.txId, "COMMIT", "DISK_ERROR")
        return false, errApply
    end

    send_ack(self, cmdCh, p.txId, "APPLIED", "PENDING_COMMIT")
    if p.autoReboot == true and type(self.onRebootFn) == "function" then
        self.onRebootFn()
    end
    return true, "APPLIED"
end

local function handle_abort(self, cmdCh, p)
    local okAddr, errAddr = check_target_addressing(self, cmdCh, p, "ABORT")
    if not okAddr then
        return false, errAddr
    end
    if self.activeTx and self.activeTx.txId == p.txId then
        cleanup_active_tx(self)
        return true, "ABORTED"
    end
    local orphanStaging = resolve_path(self.rootDir, "/ota_staging/" .. tostring(p.txId or ""))
    if orphanStaging then
        safe_delete(self.fsApi, orphanStaging)
    end
    return true, "ABORTED"
end

local function handle_reboot(self, cmdCh, p)
    local okAddr, errAddr = check_target_addressing(self, cmdCh, p, "REBOOT")
    if not okAddr then
        return false, errAddr
    end
    local safe, denyReason = ota_agent.is_safe_for_ota(self.getStatusFn())
    if not safe then
        send_nack(self, cmdCh, p.txId, "REBOOT", denyReason)
        return false, denyReason
    end
    if type(self.onRebootFn) == "function" then
        self.onRebootFn()
    end
    return true, "REBOOTING"
end

-- =========================================================================
-- Agent Constructor & Public Methods
-- =========================================================================

local AgentMT = {}
AgentMT.__index = AgentMT

local function build_bay_pairs(bayId, bayIds)
    local list = (type(bayIds) == "table" and #bayIds > 0) and bayIds or { bayId }
    local seen = {}
    local pairsOut = {}
    local cmdMap = {}
    for _, rawId in ipairs(list) do
        local id = tonumber(rawId)
        local cmdCh, ackCh = ota_agent.get_channels(id)
        if not seen[id] then
            seen[id] = true
            pairsOut[#pairsOut + 1] = {
                bayId = id,
                cmdCh = cmdCh,
                ackCh = ackCh,
            }
            cmdMap[cmdCh] = ackCh
        end
    end
    return pairsOut, cmdMap
end

--- Constructs a new slave OTA agent bound to a module, domain, and hangar bay(s).
-- @param opts table Configuration options
-- @return table agent instance
function ota_agent.new(opts)
    opts = opts or {}
    assert(type(opts.moduleId) == "string" and opts.moduleId ~= "", "ota_agent.new requires non-empty moduleId")

    local bayPairs, cmdMap = build_bay_pairs(opts.bayId or 1, opts.bayIds)
    local seqCounter = 0

    local instance = {
        moduleId = opts.moduleId,
        domainId = (type(opts.domainId) == "string" and opts.domainId ~= "") and opts.domainId or "AIRCRAFT_01",
        bayPairs = bayPairs,
        cmdChToAckCh = cmdMap,
        primaryCmdCh = bayPairs[1].cmdCh,
        primaryAckCh = bayPairs[1].ackCh,
        bootConfirmTicks = math.max(1, math.floor(tonumber(opts.bootConfirmTicks) or ota_agent.DEFAULT_BOOT_CONFIRM_TICKS)),
        fsApi = opts.fsApi or fs,
        modemApi = opts.modemApi,
        rootDir = normalize_root(opts.rootDir),
        getStatusFn = opts.getStatusFn or function()
            return { controlState = "UNKNOWN", isAirborne = false }
        end,
        onRebootFn = opts.onRebootFn or function()
            if os and os.reboot then
                os.reboot()
            end
        end,
        seqFn = opts.seqFn or function()
            seqCounter = seqCounter + 1
            return seqCounter
        end,
        clockFn = opts.clockFn or function()
            if os and os.epoch then
                return os.epoch("utc")
            end
            if os and os.time then
                return os.time() * 1000
            end
            return 0
        end,
        bootTicks = 0,
        activeTx = nil,
    }

    return setmetatable(instance, AgentMT)
end

--- Opens configured hangar OTA command channels on the attached modem.
-- @return number primaryCmdCh, number primaryAckCh, table bayPairs
function AgentMT:open_channels()
    if self.modemApi and type(self.modemApi.open) == "function" then
        for _, pair in ipairs(self.bayPairs) do
            self.modemApi.open(pair.cmdCh)
        end
    end
    return self.primaryCmdCh, self.primaryAckCh, self.bayPairs
end

--- Handles an incoming modem packet against ICD 1.9.5 Interface I-13.
-- @param channel number Channel on which packet arrived
-- @param _replyChannel number Modem reply channel (unused; routes to bay ackCh)
-- @param rawPacket any Decoded packet payload
-- @return boolean handled, string|nil statusOrReason
function AgentMT:handle_packet(channel, _replyChannel, rawPacket)
    local cmdCh = tonumber(channel)
    if not cmdCh or not self.cmdChToAckCh[cmdCh] then
        return false, "UNKNOWN_CHANNEL"
    end
    if not is_valid_envelope(rawPacket) then
        return false, "INVALID_ENVELOPE"
    end

    local msgType = rawPacket.type
    local p = rawPacket.payload

    if msgType == "MSG_OTA_DISCOVER_REQ" then
        return handle_discover(self, cmdCh, p)
    elseif msgType == "MSG_OTA_BEGIN" then
        return handle_begin(self, cmdCh, p)
    elseif msgType == "MSG_OTA_CHUNK" then
        return handle_chunk(self, cmdCh, p)
    elseif msgType == "MSG_OTA_COMMIT" then
        return handle_commit(self, cmdCh, p)
    elseif msgType == "MSG_OTA_ABORT" then
        return handle_abort(self, cmdCh, p)
    elseif msgType == "MSG_OTA_REBOOT" then
        return handle_reboot(self, cmdCh, p)
    end

    return false, "UNSUPPORTED_TYPE"
end

--- Confirms a pending OTA boot commit or reports a Stage 1 rollback marker.
-- @return boolean reported, table|nil statusRecord
function AgentMT:confirm_boot_commit()
    local fsApi = self.fsApi
    local rollbackPath = resolve_path(self.rootDir, "/.ota_rollback.json")
    if fsApi.exists(rollbackPath) then
        local rec = read_json_file(fsApi, rollbackPath) or {}
        safe_delete(fsApi, rollbackPath)
        self.bootTicks = 0
        local outRec = {
            txId = tostring(rec.txId or ""),
            moduleId = tostring(rec.moduleId or self.moduleId),
            status = "ROLLED_BACK",
            version = tostring(rec.targetVersion or "0.0.0-untracked"),
            rollbackReason = tostring(rec.reason or "BOOT_ROLLBACK"),
        }
        send_boot_status(self, outRec.txId, outRec.moduleId, outRec.status, outRec.version, outRec.rollbackReason)
        return true, outRec
    end

    local pendingPath = resolve_path(self.rootDir, "/.ota_pending.json")
    if fsApi.exists(pendingPath) then
        local pending = read_json_file(fsApi, pendingPath) or {}
        if type(pending.backupDir) == "string" and pending.backupDir ~= "" then
            safe_delete(fsApi, pending.backupDir)
        end
        safe_delete(fsApi, pendingPath)
        self.bootTicks = 0
        local outRec = {
            txId = tostring(pending.txId or ""),
            moduleId = tostring(pending.moduleId or self.moduleId),
            status = "COMMITTED",
            version = tostring(pending.targetVersion or "0.0.0-untracked"),
        }
        send_boot_status(self, outRec.txId, outRec.moduleId, outRec.status, outRec.version, nil)
        return true, outRec
    end

    return false, nil
end

--- Advances the Stage 2 healthy-tick boot counter and commits once stabilized.
-- @return boolean committedOrReported, table|nil statusRecord
function AgentMT:tick_boot_commit()
    local fsApi = self.fsApi
    local rollbackPath = resolve_path(self.rootDir, "/.ota_rollback.json")
    if fsApi.exists(rollbackPath) then
        return self:confirm_boot_commit()
    end

    local pendingPath = resolve_path(self.rootDir, "/.ota_pending.json")
    if not fsApi.exists(pendingPath) then
        self.bootTicks = 0
        return false, nil
    end

    self.bootTicks = self.bootTicks + 1
    if self.bootTicks >= self.bootConfirmTicks then
        return self:confirm_boot_commit()
    end
    return false, nil
end

return ota_agent
