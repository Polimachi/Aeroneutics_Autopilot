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

    local TICK_METHODS = {
        step = true,
        step_tick = true,
        tick = true,
        update = true,
        process_modem_message = true,
        run_step = true,
        handle_message = true,
        on_message = true,
    }
    local CONSTRUCTOR_METHODS = {
        create_app = true,
        create_context = true,
        init = true,
        new = true,
    }
    local wrapped_fns = setmetatable({}, { __mode = "k" })
    local wrapped_tbls = setmetatable({}, { __mode = "k" })

    local function prof_enabled()
        local p = _G.__AUDIT_PROFILE
        return type(p) == "table" and p.enabled == true
    end

    local function ensure_node_prof()
        local p = _G.__AUDIT_PROFILE
        p.nodes = p.nodes or {}
        p.stack = p.stack or {}
        local rec = p.nodes[nid]
        if not rec then
            rec = {
                base_dir = bdir,
                require_calls = 0,
                require_ms = 0,
                require_insns = 0,
                calls = 0,
                tick_calls = 0,
                cpu_ms = 0,
                insns = 0,
                _depth = 0,
            }
            p.nodes[nid] = rec
        end
        return p, rec
    end

    local orig_epoch = os and os.epoch
    local function now_ms()
        if type(orig_epoch) == "function" then
            return orig_epoch("utc")
        end
        return 0
    end

    local wrap_table_methods

    local function finish_call(p, rec, sp, t0, is_outer, is_ctor, ...)
        p.stack[sp] = nil
        rec._depth = rec._depth - 1
        if is_outer then
            local dt = now_ms() - t0
            if dt > 0 then
                rec.cpu_ms = rec.cpu_ms + dt
            end
        end
        if is_ctor and type((...)) == "table" then
            wrap_table_methods((...), 1)
        end
        return ...
    end

    local function wrap_callable(fn, method_name)
        if type(fn) ~= "function" or wrapped_fns[fn] then
            return fn
        end
        local is_tick = method_name ~= nil and TICK_METHODS[method_name] == true
        local is_ctor = method_name ~= nil and CONSTRUCTOR_METHODS[method_name] == true
        local wrapper = function(...)
            local p = _G.__AUDIT_PROFILE
            if type(p) ~= "table" or p.enabled ~= true then
                return fn(...)
            end
            local rec = p.nodes[nid]
            if not rec then
                p, rec = ensure_node_prof()
            end
            rec.calls = rec.calls + 1
            if is_tick then
                rec.tick_calls = rec.tick_calls + 1
            end
            local is_outer = (rec._depth == 0)
            rec._depth = rec._depth + 1
            local stack = p.stack
            local sp = #stack + 1
            stack[sp] = nid
            local t0 = is_outer and now_ms() or 0
            return finish_call(p, rec, sp, t0, is_outer, is_ctor, fn(...))
        end
        wrapped_fns[fn] = wrapper
        wrapped_fns[wrapper] = wrapper
        return wrapper
    end

    wrap_table_methods = function(tbl, depth)
        if type(tbl) ~= "table" or wrapped_tbls[tbl] or (depth or 0) > 1 then
            return tbl
        end
        wrapped_tbls[tbl] = true
        for k, v in pairs(tbl) do
            if type(v) == "function" then
                tbl[k] = wrap_callable(v, type(k) == "string" and k or nil)
            end
        end
        local mt = getmetatable(tbl)
        if type(mt) == "table" and type(mt.__index) == "table" and not wrapped_tbls[mt.__index] then
            wrap_table_methods(mt.__index, (depth or 0) + 1)
        end
        return tbl
    end

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
            local res
            if prof_enabled() then
                local p, rec = ensure_node_prof()
                rec.require_calls = rec.require_calls + 1
                local insns0 = rec.insns
                local t0 = now_ms()
                local stack = p.stack
                local sp = #stack + 1
                stack[sp] = nid
                local ok, r = pcall(fn, norm_name, found_path)
                stack[sp] = nil
                local dt = now_ms() - t0
                if dt > 0 then
                    rec.require_ms = rec.require_ms + dt
                end
                rec.require_insns = rec.require_insns + (rec.insns - insns0)
                if not ok then
                    error(r, 0)
                end
                res = r
            else
                res = fn(norm_name, found_path)
            end
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
        local res = env.require(modname)
        if prof_enabled() then
            if type(res) == "table" then
                wrap_table_methods(res, 0)
            elseif type(res) == "function" then
                res = wrap_callable(res, nil)
            end
        end
        return res
    end

    function node:call(fn_or_name, ...)
        local fn = fn_or_name
        if type(fn_or_name) == "string" then
            fn = env[fn_or_name]
            if type(fn) ~= "function" then
                error("No such function '" .. fn_or_name .. "' in node '" .. nid .. "'", 2)
            end
        end
        if type(fn) == "function" then
            return wrap_callable(fn, type(fn_or_name) == "string" and fn_or_name or nil)(...)
        end
    end

    function node:register_handler(channel, callback)
        self.handlers[channel] = callback
    end

    function node:step_tick(dt)
        local p = _G.__AUDIT_PROFILE
        if type(p) ~= "table" or p.enabled ~= true then
            local incoming = self.modem:drain()
            for _, msg in ipairs(incoming) do
                local h = self.handlers[msg.channel]
                if h then
                    h(msg)
                end
            end
            return #incoming
        end
        local rec = p.nodes[nid]
        if not rec then
            p, rec = ensure_node_prof()
        end
        rec.calls = rec.calls + 1
        rec.tick_calls = rec.tick_calls + 1
        local is_outer = (rec._depth == 0)
        rec._depth = rec._depth + 1
        local stack = p.stack
        local sp = #stack + 1
        stack[sp] = nid
        local t0 = is_outer and now_ms() or 0
        local incoming = self.modem:drain()
        for _, msg in ipairs(incoming) do
            local h = self.handlers[msg.channel]
            if h then
                h(msg)
            end
        end
        return finish_call(p, rec, sp, t0, is_outer, false, #incoming)
    end

    node.env = env
    return node
end

return M
