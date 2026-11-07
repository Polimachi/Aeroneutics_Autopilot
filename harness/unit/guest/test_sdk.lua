-- Universal Create: Aeronautics and CC:Tweaked Assertion & Mock SDK
-- Compatible with CC:Tweaked 1.109+ / Cobalt Lua 5.2

local M = {}

local function is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- =========================================================================
-- Extended Assertions
-- =========================================================================

function _G.assert_ne(actual, unexpected, msg)
    if actual == unexpected then
        error((msg and (msg .. ": ") or "") .. "expected value not to equal " .. textutils.serialize(unexpected), 2)
    end
end

function _G.assert_false(val, msg)
    if val then
        error((msg or "assert_false failed") .. " (got " .. tostring(val) .. ")", 2)
    end
end

function _G.assert_nil(val, msg)
    if val ~= nil then
        error((msg or "assert_nil failed") .. " (got " .. tostring(val) .. ")", 2)
    end
end

function _G.assert_not_nil(val, msg)
    if val == nil then
        error((msg or "assert_not_nil failed") .. " (got nil)", 2)
    end
end

function _G.assert_near(actual, expected, eps, msg)
    if not is_finite_number(actual) or not is_finite_number(expected) then
        error((msg and (msg .. ": ") or "") .. "assert_near received non-finite number: actual=" .. tostring(actual) .. ", expected=" .. tostring(expected), 2)
    end
    local tolerance = tonumber(eps) or 1e-6
    if math.abs(actual - expected) > tolerance then
        error(
            string.format(
                "%sexpected %f +/- %f, got %f (diff: %f)",
                msg and (msg .. ": ") or "",
                expected,
                tolerance,
                actual,
                math.abs(actual - expected)
            ),
            2
        )
    end
end

local function deep_compare(a, b, path, visited)
    if a == b then return true end
    local type_a, type_b = type(a), type(b)
    if type_a ~= type_b then
        return false, string.format("type mismatch at %s: expected %s, got %s", path, type_b, type_a)
    end
    if type_a ~= "table" then
        return false, string.format("value mismatch at %s: expected %s, got %s", path, tostring(b), tostring(a))
    end

    visited = visited or {}
    local pair_key = tostring(a) .. "::" .. tostring(b)
    if visited[pair_key] then
        return true
    end
    visited[pair_key] = true

    for k, v in pairs(a) do
        local sub_path = path .. "." .. tostring(k)
        if b[k] == nil and v ~= nil then
            return false, string.format("key %s missing in expected", sub_path)
        end
        local ok, err = deep_compare(v, b[k], sub_path, visited)
        if not ok then return false, err end
    end

    for k, v in pairs(b) do
        local sub_path = path .. "." .. tostring(k)
        if a[k] == nil and v ~= nil then
            return false, string.format("key %s missing in actual", sub_path)
        end
    end

    return true
end

function _G.assert_deep_eq(actual, expected, msg)
    local ok, detail = deep_compare(actual, expected, "root", {})
    if not ok then
        error((msg and (msg .. ": ") or "") .. detail, 2)
    end
end

function _G.assert_throws(fn, expected_substr, msg)
    local ok, err = pcall(fn)
    if ok then
        error((msg or "expected function to throw error, but succeeded"), 2)
    end
    if expected_substr then
        local s = tostring(err or "")
        if not string.find(s, tostring(expected_substr), 1, true) then
            error(
                string.format(
                    "%sexpected error containing '%s', got '%s'",
                    msg and (msg .. ": ") or "",
                    tostring(expected_substr),
                    s
                ),
                2
            )
        end
    end
end

-- =========================================================================
-- Dual-call normalization helper (. vs :)
-- =========================================================================

local function strip_self(self_obj, first, ...)
    if first == self_obj then
        return ...
    end
    return first, ...
end

-- =========================================================================
-- Universal CC:Tweaked & Domain Mocks
-- =========================================================================

_G.mock = _G.mock or {}

function _G.mock.modem(opts)
    local m = {
        _opened = {},
        _transmitted = {},
        _isWireless = (opts and opts.wireless == true),
    }

    m.open = function(a1, ...)
        local ch = strip_self(m, a1, ...)
        m._opened[tonumber(ch)] = true
    end

    m.close = function(a1, ...)
        local ch = strip_self(m, a1, ...)
        m._opened[tonumber(ch)] = nil
    end

    m.closeAll = function()
        m._opened = {}
    end

    m.isOpen = function(a1, ...)
        local ch = strip_self(m, a1, ...)
        return m._opened[tonumber(ch)] == true
    end

    m.isWireless = function()
        return m._isWireless
    end

    m.transmit = function(a1, a2, a3, ...)
        local tx, rx, pkt
        if a1 == m then
            tx, rx, pkt = a2, a3, ...
        else
            tx, rx, pkt = a1, a2, a3
        end
        table.insert(m._transmitted, { tx = tonumber(tx), rx = tonumber(rx), pkt = pkt })
    end

    return m
end

function _G.mock.term(width, height)
    local w, h = width or 51, height or 19
    local lines, fgs, bgs = {}, {}, {}
    for y = 1, h do
        lines[y] = string.rep(" ", w)
        fgs[y] = string.rep("0", w)
        bgs[y] = string.rep("f", w)
    end

    local scr = {
        _w = w,
        _h = h,
        _cx = 1,
        _cy = 1,
        _blink = false,
        _lines = lines,
        _fg = fgs,
        _bg = bgs,
        _cur_fg = "0",
        _cur_bg = "f",
    }

    scr.getSize = function() return scr._w, scr._h end
    scr.getCursorPos = function() return scr._cx, scr._cy end
    scr.getCursorBlink = function() return scr._blink end
    scr.isColor = function() return true end
    scr.isColour = scr.isColor

    scr.setCursorPos = function(a1, a2, ...)
        local x, y = a1, a2
        if a1 == scr then x, y = a2, ... end
        scr._cx = tonumber(x) or 1
        scr._cy = tonumber(y) or 1
    end

    scr.setCursorBlink = function(a1, ...)
        local b = strip_self(scr, a1, ...)
        scr._blink = (b == true)
    end

    scr.write = function(a1, ...)
        local txt = tostring(strip_self(scr, a1, ...) or "")
        local y = scr._cy
        if y >= 1 and y <= scr._h then
            local row = scr._lines[y]
            local x = scr._cx
            if x <= scr._w then
                local left = string.sub(row, 1, math.max(0, x - 1))
                local right = string.sub(row, x + #txt)
                scr._lines[y] = string.sub(left .. txt .. right, 1, scr._w)
                scr._cx = x + #txt
            end
        end
    end

    scr.blit = function(a1, a2, a3, ...)
        local txt, fg, bg
        if a1 == scr then txt, fg, bg = a2, a3, ... else txt, fg, bg = a1, a2, a3 end
        local t_str, f_str, b_str = tostring(txt or ""), tostring(fg or ""), tostring(bg or "")
        local y = scr._cy
        if y >= 1 and y <= scr._h then
            local row = scr._lines[y]
            local row_f = scr._fg[y]
            local row_b = scr._bg[y]
            local x = scr._cx
            if x <= scr._w then
                local left = string.sub(row, 1, math.max(0, x - 1))
                local right = string.sub(row, x + #t_str)
                scr._lines[y] = string.sub(left .. t_str .. right, 1, scr._w)

                local left_f = string.sub(row_f, 1, math.max(0, x - 1))
                local right_f = string.sub(row_f, x + #f_str)
                scr._fg[y] = string.sub(left_f .. f_str .. right_f, 1, scr._w)

                local left_b = string.sub(row_b, 1, math.max(0, x - 1))
                local right_b = string.sub(row_b, x + #b_str)
                scr._bg[y] = string.sub(left_b .. b_str .. right_b, 1, scr._w)

                scr._cx = x + #t_str
            end
        end
    end

    scr.clear = function()
        for y = 1, scr._h do
            scr._lines[y] = string.rep(" ", scr._w)
            scr._fg[y] = string.rep(scr._cur_fg, scr._w)
            scr._bg[y] = string.rep(scr._cur_bg, scr._w)
        end
    end

    scr.clearLine = function()
        local y = scr._cy
        if y >= 1 and y <= scr._h then
            scr._lines[y] = string.rep(" ", scr._w)
            scr._fg[y] = string.rep(scr._cur_fg, scr._w)
            scr._bg[y] = string.rep(scr._cur_bg, scr._w)
        end
    end

    scr.setTextColor = function(a1, ...)
        local c = strip_self(scr, a1, ...)
        scr._cur_fg = string.format("%x", math.log(tonumber(c) or 1) / math.log(2)):sub(1, 1)
    end
    scr.setTextColour = scr.setTextColor

    scr.setBackgroundColor = function(a1, ...)
        local c = strip_self(scr, a1, ...)
        scr._cur_bg = string.format("%x", math.log(tonumber(c) or 1) / math.log(2)):sub(1, 1)
    end
    scr.setBackgroundColour = scr.setBackgroundColor

    scr._get_line = function(a1, ...)
        local y = tonumber(strip_self(scr, a1, ...) or 1)
        return scr._lines[y] or ""
    end

    scr._contains = function(a1, ...)
        local substr = tostring(strip_self(scr, a1, ...) or "")
        for y = 1, scr._h do
            if string.find(scr._lines[y], substr, 1, true) then
                return true
            end
        end
        return false
    end

    return scr
end

function _G.mock.redstone()
    local rs = {
        _analogOut = {},
        _analogIn = {},
        _digitalOut = {},
        _digitalIn = {},
    }

    rs.setAnalogOutput = function(a1, a2, ...)
        local side, val = a1, a2
        if a1 == rs then side, val = a2, ... end
        rs._analogOut[tostring(side)] = tonumber(val) or 0
    end

    rs.getAnalogOutput = function(a1, ...)
        local side = strip_self(rs, a1, ...)
        return rs._analogOut[tostring(side)] or 0
    end

    rs.setAnalogInput = function(a1, a2, ...)
        local side, val = a1, a2
        if a1 == rs then side, val = a2, ... end
        rs._analogIn[tostring(side)] = tonumber(val) or 0
    end

    rs.getAnalogInput = function(a1, ...)
        local side = strip_self(rs, a1, ...)
        return rs._analogIn[tostring(side)] or 0
    end

    rs.setOutput = function(a1, a2, ...)
        local side, val = a1, a2
        if a1 == rs then side, val = a2, ... end
        rs._digitalOut[tostring(side)] = (val == true)
    end

    rs.getOutput = function(a1, ...)
        local side = strip_self(rs, a1, ...)
        return rs._digitalOut[tostring(side)] == true
    end

    rs.setInput = function(a1, a2, ...)
        local side, val = a1, a2
        if a1 == rs then side, val = a2, ... end
        rs._digitalIn[tostring(side)] = (val == true)
    end

    rs.getInput = function(a1, ...)
        local side = strip_self(rs, a1, ...)
        return rs._digitalIn[tostring(side)] == true
    end

    return rs
end

function _G.mock.clock(start_ms)
    local cur = tonumber(start_ms) or 1000
    local clk = {}
    clk.now = function() return cur end
    clk.advance = function(a1, ...)
        local dt = tonumber(strip_self(clk, a1, ...) or 0)
        cur = cur + dt
        return cur
    end
    clk.set = function(a1, ...)
        local v = tonumber(strip_self(clk, a1, ...) or 0)
        cur = v
        return cur
    end
    clk.epoch = function(a1, ...)
        return cur
    end
    return clk
end

function _G.mock.avionics_gimbal(initial)
    local state = initial or {}
    local g = {
        _pitch = tonumber(state.pitch or 0.0),
        _roll = tonumber(state.roll or 0.0),
        _yaw = tonumber(state.yaw or 0.0),
        _pitchRate = tonumber(state.pitchRate or 0.0),
        _rollRate = tonumber(state.rollRate or 0.0),
        _yawRate = tonumber(state.yawRate or 0.0),
    }
    g.getAngles = function()
        return { pitch = g._pitch, roll = g._roll, yaw = g._yaw }
    end
    g.getAngularRates = function()
        return { pitchRate = g._pitchRate, rollRate = g._rollRate, yawRate = g._yawRate }
    end
    g.getReading = function()
        return {
            pitch = g._pitch, roll = g._roll, yaw = g._yaw,
            pitchRate = g._pitchRate, rollRate = g._rollRate, yawRate = g._yawRate,
        }
    end
    return g
end

function _G.mock.avionics_altitude(initial)
    local state = initial or {}
    local a = {
        _altitude = tonumber(state.altitude or 100.0),
        _verticalSpeed = tonumber(state.verticalSpeed or 0.0),
    }
    a.getAltitude = function() return a._altitude end
    a.getVerticalSpeed = function() return a._verticalSpeed end
    a.getReading = function()
        return { altitude = a._altitude, verticalSpeed = a._verticalSpeed }
    end
    return a
end

function _G.mock.avionics_velocity(initial)
    local state = initial or {}
    local v = {
        _vx = tonumber(state.vx or state.x or 0.0),
        _vy = tonumber(state.vy or state.y or 0.0),
        _vz = tonumber(state.vz or state.z or 0.0),
    }
    v.getVelocity = function()
        return { x = v._vx, y = v._vy, z = v._vz, vx = v._vx, vy = v._vy, vz = v._vz }
    end
    v.getReading = function()
        return { x = v._vx, y = v._vy, z = v._vz, vx = v._vx, vy = v._vy, vz = v._vz }
    end
    return v
end

function _G.mock.fuel_tank(amount, capacity)
    local am = tonumber(amount or 1000)
    local cap = tonumber(capacity or 1000)
    local t = { _amount = am, _capacity = cap }
    t.tanks = function()
        return { { amount = t._amount, capacity = t._capacity } }
    end
    t.getReading = function()
        return { amount = t._amount, capacity = t._capacity }
    end
    return t
end

function _G.mock.actuator(kind)
    local act = {
        _kind = kind or "bearing",
        _lastSpeed = 0,
        _lastPower = 0,
        _lastThrust = 0,
        _lastPitch = 0,
        _lastYaw = 0,
    }

    act.setSpeed = function(a1, ...)
        local v = strip_self(act, a1, ...)
        act._lastSpeed = tonumber(v) or 0
    end

    act.setPower = function(a1, ...)
        local v = strip_self(act, a1, ...)
        act._lastPower = tonumber(v) or 0
    end

    act.setThrust = function(a1, ...)
        local v = strip_self(act, a1, ...)
        act._lastThrust = tonumber(v) or 0
    end

    act.setTargetPitch = function(a1, ...)
        local v = strip_self(act, a1, ...)
        act._lastPitch = tonumber(v) or 0
    end

    act.setTargetYaw = function(a1, ...)
        local v = strip_self(act, a1, ...)
        act._lastYaw = tonumber(v) or 0
    end

    return act
end

function _G.mock.peripheral_registry(side_map)
    local reg = side_map or {}
    local p = {}

    p.getNames = function()
        local names = {}
        for side, _ in pairs(reg) do
            names[#names + 1] = side
        end
        table.sort(names)
        return names
    end

    p.isPresent = function(side)
        return reg[side] ~= nil
    end

    p.getType = function(side)
        local ent = reg[side]
        if not ent then return nil end
        if type(ent) == "table" and ent.type then
            return ent.type
        end
        return "generic"
    end

    p.wrap = function(side)
        local ent = reg[side]
        if not ent then return nil end
        if type(ent) == "table" and ent.dev ~= nil then
            return ent.dev
        end
        return ent
    end

    p.find = function(ptype, fnFilter)
        local matched = {}
        for side, ent in pairs(reg) do
            local cur_type = (type(ent) == "table" and ent.type) or nil
            if cur_type == ptype or ptype == nil or string.find(cur_type or "", ptype, 1, true) then
                local wrapped = p.wrap(side)
                if not fnFilter or fnFilter(side, wrapped) then
                    matched[#matched + 1] = wrapped
                end
            end
        end
        return table.unpack(matched)
    end

    p.call = function(side, method, ...)
        local dev = p.wrap(side)
        if not dev or type(dev[method]) ~= "function" then
            error("No such method " .. tostring(method) .. " on peripheral " .. tostring(side), 2)
        end
        return dev[method](...)
    end

    sdk.patch(_G, "peripheral", p)
    return p
end

return M
