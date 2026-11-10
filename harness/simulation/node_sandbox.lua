-- harness/simulation/node_sandbox.lua
-- Isolated guest sandbox for running CC:Tweaked Lua codebases independently
local M = {}

local function strip_self(self_tbl, a1, ...)
    if a1 == self_tbl then
        return ...
    end
    return a1, ...
end

local function normalize_path(p)
    local s = tostring(p or ""):gsub("\\", "/")
    if s:sub(1, 1) == "/" then
        s = s:sub(2)
    end
    return s
end

function M.create_node(bus, node_id, base_dir, options)
    local opts = options or {}
    local nid = tostring(node_id or "NODE")
    local bdir = normalize_path(base_dir or "")
    local side = tostring(opts.side or "top")
    local vfiles = opts.virtual_files or {}

    local modem = bus:create_modem(nid, side)

    local node = {
        node_id = nid,
        base_dir = bdir,
        modem = modem,
        bus = bus,
        options = opts,
        handlers = {},
    }

    -- Create sandboxed environment
    local env = {}
    for k, v in pairs(_G) do
        env[k] = v
    end
    env._G = env
    env._ENV = env

    -- Private package table
    local loaded = {}
    local pkg = {
        loaded = loaded,
        preload = {},
        path = bdir .. "/?.lua;" .. bdir .. "/modules/?.lua;" .. bdir .. "/hal/?.lua;/lib/?.lua",
    }
    env.package = pkg

    -- Custom filesystem wrapper
    local custom_fs = {}
    if fs then
        for k, v in pairs(fs) do
            custom_fs[k] = v
        end
    end

    function custom_fs.exists(a1, ...)
        local path = normalize_path(strip_self(custom_fs, a1, ...))
        if vfiles[path] ~= nil then return true end
        if bdir ~= "" and vfiles[bdir .. "/" .. path] ~= nil then return true end
        if fs and fs.exists then
            if fs.exists(path) then return true end
            if bdir ~= "" and fs.exists(bdir .. "/" .. path) then return true end
        end
        return false
    end

    function custom_fs.open(a1, a2, ...)
        local path, mode
        if a1 == custom_fs then
            path, mode = a2, ...
        else
            path, mode = a1, a2
        end
        path = normalize_path(path)
        mode = tostring(mode or "r")

        -- Check virtual_files first
        local vf_content = vfiles[path]
        if vf_content == nil and bdir ~= "" then
            vf_content = vfiles[bdir .. "/" .. path]
        end

        if vf_content ~= nil then
            local pos = 1
            return {
                readAll = function() return vf_content end,
                readLine = function()
                    if pos > #vf_content then return nil end
                    local nl = vf_content:find("\n", pos, true)
                    local line
                    if nl then
                        line = vf_content:sub(pos, nl - 1)
                        pos = nl + 1
                    else
                        line = vf_content:sub(pos)
                        pos = #vf_content + 1
                    end
                    return line
                end,
                close = function() end,
            }
        end

        -- Check host / guest filesystem
        if fs and fs.open then
            if fs.exists(path) then
                return fs.open(path, mode)
            end
            if bdir ~= "" and fs.exists(bdir .. "/" .. path) then
                return fs.open(bdir .. "/" .. path, mode)
            end
        end

        return nil
    end

    env.fs = custom_fs

    -- Custom peripheral wrapping
    local custom_peripheral = {
        wrap = function(side_req)
            if side_req == side or side_req == "top" or side_req == "modem" or side_req == "wireless" then
                return modem
            end
            if peripheral and peripheral.wrap then
                return peripheral.wrap(side_req)
            end
            return nil
        end,
        find = function(ptype, fnFilter)
            if ptype == "modem" then
                if fnFilter == nil or fnFilter(side, modem) then
                    return modem
                end
            end
            if peripheral and peripheral.find then
                return peripheral.find(ptype, fnFilter)
            end
            return nil
        end,
        isPresent = function(side_req)
            if side_req == side or side_req == "top" then return true end
            if peripheral and peripheral.isPresent then
                return peripheral.isPresent(side_req)
            end
            return false
        end,
        getType = function(side_req)
            if side_req == side or side_req == "top" then return "modem" end
            if peripheral and peripheral.getType then
                return peripheral.getType(side_req)
            end
            return nil
        end,
        getNames = function()
            return { side }
        end,
        call = function(side_req, method, ...)
            if side_req == side or side_req == "top" then
                if type(modem[method]) == "function" then
                    return modem[method](...)
                end
            end
            if peripheral and peripheral.call then
                return peripheral.call(side_req, method, ...)
            end
            return nil
        end,
    }
    env.peripheral = custom_peripheral

    -- Node require loader
    function env.require(modname)
        local norm_name = tostring(modname or "")
        if loaded[norm_name] ~= nil then
            return loaded[norm_name]
        end

        -- Search candidates
        local candidates = {
            norm_name,
            norm_name .. ".lua",
            "modules/" .. norm_name .. ".lua",
            "hal/" .. norm_name .. ".lua",
            "lib/" .. norm_name .. ".lua",
        }
        if bdir ~= "" then
            table.insert(candidates, 1, bdir .. "/" .. norm_name .. ".lua")
            table.insert(candidates, 2, bdir .. "/modules/" .. norm_name .. ".lua")
            table.insert(candidates, 3, bdir .. "/hal/" .. norm_name .. ".lua")
            table.insert(candidates, 4, bdir .. "/" .. norm_name)
        end

        local code_to_run = nil
        local found_path = nil

        for _, cand in ipairs(candidates) do
            local clean = normalize_path(cand)
            if vfiles[clean] ~= nil then
                code_to_run = vfiles[clean]
                found_path = clean
                break
            elseif fs and fs.exists and fs.exists(clean) then
                local h = fs.open(clean, "r")
                if h then
                    code_to_run = h.readAll()
                    h.close()
                    found_path = clean
                    break
                end
            end
        end

        if code_to_run then
            local fn, err = load(code_to_run, "@" .. tostring(found_path), "t", env)
            if not fn then
                error("Error loading module '" .. norm_name .. "': " .. tostring(err), 2)
            end
            local res = fn(norm_name, found_path)
            loaded[norm_name] = (res ~= nil) and res or true
            return loaded[norm_name]
        end

        -- Fallback to global require if available (for standard libs like bit32)
        if _G.require and _G.require ~= env.require then
            local ok, sys_res = pcall(_G.require, norm_name)
            if ok then
                loaded[norm_name] = sys_res
                return sys_res
            end
        end

        error("Module '" .. norm_name .. "' not found in node '" .. nid .. "' sandbox", 2)
    end

    function node:require(modname)
        return env.require(modname)
    end

    function node:call(fn_or_name, ...)
        if type(fn_or_name) == "function" then
            return fn_or_name(...)
        elseif type(fn_or_name) == "string" then
            local fn = env[fn_or_name]
            if type(fn) == "function" then
                return fn(...)
            end
            error("No such function '" .. fn_or_name .. "' in node '" .. nid .. "'", 2)
        end
    end

    function node:register_handler(channel, callback)
        self.handlers[channel] = callback
    end

    function node:step_tick(dt)
        local incoming = self.modem:drain()
        for _, msg in ipairs(incoming) do
            local h = self.handlers[msg.channel]
            if h then
                h(msg)
            end
        end
        return #incoming
    end

    node.env = env
    return node
end

return M
