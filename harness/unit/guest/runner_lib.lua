-- Universal CraftOS-PC Unit Test Runner Library
-- Compatible with CC:Tweaked 1.109+ / Cobalt Lua 5.2

local R = {}

R.logs = {}
R.errors = {}
R.suites = {}
R._current_suite = nil
R.ui_violations = {}
R.max_insns_observed = 0
R.event_swallow_count = 0
R.instruction_budget = 50000
R.filter_substr = nil

local orig_print = print
local orig_printError = printError
local orig_pwrap = peripheral and peripheral.wrap
local orig_pfind = peripheral and peripheral.find
local orig_pullEvent = os.pullEvent
local orig_pullEventRaw = os.pullEventRaw
local orig_sleep = sleep

local function safe_tostring(v)
    local ok, s = pcall(tostring, v)
    if ok then return s end
    return "<unprintable>"
end

function R.install_log_hooks()
    _G.print = function(...)
        local parts = {}
        local n = select("#", ...)
        for i = 1, n do
            parts[i] = safe_tostring(select(i, ...))
        end
        local line = table.concat(parts, "\t")
        R.logs[#R.logs + 1] = line
        return orig_print(...)
    end

    _G.printError = function(...)
        local parts = {}
        local n = select("#", ...)
        for i = 1, n do
            parts[i] = safe_tostring(select(i, ...))
        end
        local line = table.concat(parts, "\t")
        R.errors[#R.errors + 1] = line
        return orig_printError(...)
    end
end

function R.install_surface_auditor(win, label)
    if not win or type(win) ~= "table" then return win end
    local orig_blit = win.blit
    local orig_setCursorPos = win.setCursorPos

    if type(orig_blit) == "function" then
        win.blit = function(text, fg, bg)
            local t_str = tostring(text or "")
            local f_str = tostring(fg or "")
            local b_str = tostring(bg or "")
            if #t_str ~= #f_str or #t_str ~= #b_str then
                R.ui_violations[#R.ui_violations + 1] = {
                    target = label or "term",
                    kind = "BLIT_LENGTH_MISMATCH",
                    detail = string.format(
                        "term.blit length mismatch on '%s': #text=%d, #fg=%d, #bg=%d",
                        tostring(label or "term"),
                        #t_str,
                        #f_str,
                        #b_str
                    ),
                }
            end
            return orig_blit(text, fg, bg)
        end
    end

    if type(orig_setCursorPos) == "function" then
        win.setCursorPos = function(x, y)
            if type(x) ~= "number" or type(y) ~= "number" then
                R.ui_violations[#R.ui_violations + 1] = {
                    target = label or "term",
                    kind = "CURSOR_OUT_OF_BOUNDS",
                    detail = string.format(
                        "setCursorPos non-numeric coordinates on '%s': (%s, %s)",
                        tostring(label or "term"),
                        tostring(x),
                        tostring(y)
                    ),
                }
            end
            return orig_setCursorPos(x, y)
        end
    end

    return win
end

function R.profile_execution(fn, budget_limit, forbid_event_swallow)
    local limit = tonumber(budget_limit) or R.instruction_budget or 50000
    local insn_count = 0
    local step_quantum = 100
    local swallowed = 0

    local function count_hook()
        insn_count = insn_count + step_quantum
        if insn_count > R.max_insns_observed then
            R.max_insns_observed = insn_count
        end
        if insn_count > limit then
            error(
                string.format(
                    "YIELD_BUDGET_EXCEEDED: execution exceeded %d bytecode instructions (%d observed)",
                    limit,
                    insn_count
                ),
                2
            )
        end
    end

    if forbid_event_swallow then
        os.pullEvent = function(...)
            swallowed = swallowed + 1
            R.event_swallow_count = R.event_swallow_count + 1
            error("EVENT_SWALLOW_VIOLATION: unauthorized os.pullEvent() inside unit test", 2)
        end
        os.pullEventRaw = function(...)
            swallowed = swallowed + 1
            R.event_swallow_count = R.event_swallow_count + 1
            error("EVENT_SWALLOW_VIOLATION: unauthorized os.pullEventRaw() inside unit test", 2)
        end
        _G.sleep = function(...)
            swallowed = swallowed + 1
            R.event_swallow_count = R.event_swallow_count + 1
            error("EVENT_SWALLOW_VIOLATION: unauthorized sleep() inside unit test", 2)
        end
        os.sleep = _G.sleep
    end

    local prev_hook, prev_mask, prev_count
    if debug and type(debug.gethook) == "function" then
        prev_hook, prev_mask, prev_count = debug.gethook()
    end

    if debug and type(debug.sethook) == "function" then
        debug.sethook(count_hook, "", step_quantum)
    end

    local ok, err = xpcall(fn, debug.traceback)

    if debug and type(debug.sethook) == "function" then
        if prev_hook then
            debug.sethook(prev_hook, prev_mask, prev_count)
        else
            debug.sethook()
        end
    end

    if forbid_event_swallow then
        os.pullEvent = orig_pullEvent
        os.pullEventRaw = orig_pullEventRaw
        _G.sleep = orig_sleep
        os.sleep = orig_sleep
    end

    if insn_count > R.max_insns_observed then
        R.max_insns_observed = insn_count
    end

    return ok, err, insn_count, swallowed
end

function R.setup_peripherals(spec_list)
    local attached = {}
    if not spec_list or not periphemu then
        return attached
    end
    for _, spec in ipairs(spec_list) do
        local side = spec.side
        local ptype = spec.peripheral_type or spec.type
        local args = spec.args or {}
        local ok, res = pcall(function()
            return periphemu.create(side, ptype, table.unpack(args))
        end)
        attached[#attached + 1] = {
            side = side,
            type = ptype,
            ok = (ok and res == true),
            error = (not ok and tostring(res)) or nil,
        }
    end
    return attached
end

local function copy_table_shallow(t)
    if type(t) ~= "table" then return t end
    local cp = {}
    for k, v in pairs(t) do
        cp[k] = v
    end
    return cp
end

function R.install_dsl()
    local undo_stack = {}
    local temp_files = {}

    _G.sdk = _G.sdk or {}

    _G.sdk.patch = function(tbl, key, val)
        local had = (tbl[key] ~= nil)
        local old = tbl[key]
        undo_stack[#undo_stack + 1] = function()
            if had then
                tbl[key] = old
            else
                tbl[key] = nil
            end
        end
        tbl[key] = val
    end

    _G.sdk.mock_module = function(name, stub_table)
        local had = (package.loaded[name] ~= nil)
        local old = package.loaded[name]
        undo_stack[#undo_stack + 1] = function()
            if had then
                package.loaded[name] = old
            else
                package.loaded[name] = nil
            end
        end
        package.loaded[name] = stub_table
    end

    _G.sdk.temp_path = function(name)
        if not fs.exists("/_tmp") then
            fs.makeDir("/_tmp")
        end
        local p = "/_tmp/" .. tostring(name)
        temp_files[#temp_files + 1] = p
        return p
    end

    _G.sdk.with_events_allowed = function(fn, budget)
        local cur_pe = os.pullEvent
        local cur_per = os.pullEventRaw
        local cur_sl = _G.sleep

        os.pullEvent = orig_pullEvent
        os.pullEventRaw = orig_pullEventRaw
        _G.sleep = orig_sleep
        os.sleep = orig_sleep

        local ok, err, insns = R.profile_execution(fn, budget or R.instruction_budget, false)

        os.pullEvent = cur_pe
        os.pullEventRaw = cur_per
        _G.sleep = cur_sl
        os.sleep = cur_sl

        if not ok then
            error(err, 2)
        end
        return insns
    end

    _G.sdk.profile_budget = function(budget, fn)
        local ok, err, insns = R.profile_execution(fn, budget, false)
        if not ok then
            error(err, 2)
        end
        return insns
    end

    _G.describe = function(name, fn)
        local suite = {
            name = name,
            tests = {},
            passed = 0,
            failed = 0,
            before_each = {},
            after_each = {},
        }
        R.suites[#R.suites + 1] = suite
        local prev = R._current_suite
        R._current_suite = suite
        local ok, err = xpcall(fn, debug.traceback)
        R._current_suite = prev
        if not ok then
            suite.failed = suite.failed + 1
            suite.tests[#suite.tests + 1] = {
                name = "<suite_setup>",
                status = "FAIL",
                error = tostring(err),
            }
        end
    end

    _G.before_each = function(fn)
        if R._current_suite and type(fn) == "function" then
            if type(R._current_suite.before_each) ~= "table" then
                R._current_suite.before_each = {}
            end
            table.insert(R._current_suite.before_each, fn)
        end
    end

    _G.after_each = function(fn)
        if R._current_suite and type(fn) == "function" then
            if type(R._current_suite.after_each) ~= "table" then
                R._current_suite.after_each = {}
            end
            table.insert(R._current_suite.after_each, fn)
        end
    end

    _G.it = function(name, fn)
        local suite = R._current_suite
        if not suite then
            suite = { name = "default", tests = {}, passed = 0, failed = 0, before_each = {}, after_each = {} }
            R.suites[#R.suites + 1] = suite
            R._current_suite = suite
        end

        if R.filter_substr and R.filter_substr ~= "" then
            local full_tag = string.lower((suite.name or "") .. " " .. (name or ""))
            if not string.find(full_tag, string.lower(R.filter_substr), 1, true) then
                return
            end
        end

        -- Capture state snapshot before test
        local snap_term = _G.term
        local snap_periph = _G.peripheral
        local snap_rednet = _G.rednet
        local snap_redstone = _G.redstone
        local snap_http = _G.http
        local snap_read = _G.read
        local snap_sleep = _G.sleep
        local snap_os = copy_table_shallow(_G.os)
        local snap_loaded = (package and type(package.loaded) == "table") and copy_table_shallow(package.loaded) or nil

        undo_stack = {}
        temp_files = {}

        local t0 = os.epoch and os.epoch("utc") or 0
        local ok, err, insns = false, nil, 0

        local runner = function()
            if type(suite.before_each) == "table" then
                for _, hook in ipairs(suite.before_each) do
                    hook()
                end
            elseif type(suite.before_each) == "function" then
                suite.before_each()
            end
            fn()
            if type(suite.after_each) == "table" then
                for _, hook in ipairs(suite.after_each) do
                    hook()
                end
            elseif type(suite.after_each) == "function" then
                suite.after_each()
            end
        end

        ok, err, insns = R.profile_execution(runner, R.instruction_budget, true)
        local dt = (os.epoch and os.epoch("utc") or 0) - t0

        -- Unwind registered undo actions in reverse
        for idx = #undo_stack, 1, -1 do
            pcall(undo_stack[idx])
        end
        undo_stack = {}

        -- Clean temporary files
        for _, tmp_p in ipairs(temp_files) do
            if fs.exists(tmp_p) then
                pcall(fs.delete, tmp_p)
            end
        end
        temp_files = {}

        -- Restore top-level globals and package.loaded
        _G.term = snap_term
        _G.peripheral = snap_periph
        _G.rednet = snap_rednet
        _G.redstone = snap_redstone
        _G.http = snap_http
        _G.read = snap_read
        _G.sleep = snap_sleep
        if type(snap_os) == "table" then
            for k, v in pairs(snap_os) do
                _G.os[k] = v
            end
        end
        if package and type(package.loaded) == "table" and type(snap_loaded) == "table" then
            for k in pairs(package.loaded) do
                if snap_loaded[k] == nil then
                    package.loaded[k] = nil
                end
            end
            for k, v in pairs(snap_loaded) do
                package.loaded[k] = v
            end
        end

        if ok then
            suite.passed = suite.passed + 1
            suite.tests[#suite.tests + 1] = {
                name = name,
                status = "PASS",
                duration_ms = dt,
                instructions = insns,
            }
        else
            suite.failed = suite.failed + 1
            suite.tests[#suite.tests + 1] = {
                name = name,
                status = "FAIL",
                duration_ms = dt,
                instructions = insns,
                error = tostring(err),
            }
        end
    end

    _G.assert_eq = function(actual, expected, msg)
        if actual ~= expected then
            error(
                (msg and (msg .. ": ") or "")
                    .. "expected "
                    .. textutils.serialize(expected)
                    .. ", got "
                    .. textutils.serialize(actual),
                2
            )
        end
    end

    _G.assert_true = function(val, msg)
        if not val then
            error((msg or "assert_true failed") .. " (got " .. tostring(val) .. ")", 2)
        end
    end

    _G.assert_contains = function(haystack, needle, msg)
        local s = tostring(haystack or "")
        if not string.find(s, tostring(needle), 1, true) then
            error(
                (msg and (msg .. ": ") or "")
                    .. "expected string to contain '"
                    .. tostring(needle)
                    .. "', got '"
                    .. s
                    .. "'",
                2
            )
        end
    end

    _G.assert_error = function(fn, msg)
        local ok = pcall(fn)
        if ok then
            error(msg or "expected function to raise an error, but it succeeded", 2)
        end
    end
end

function R.write_result(payload)
    if not fs.exists("/_harness_out") then
        fs.makeDir("/_harness_out")
    end
    local f = fs.open("/_harness_out/result.json", "w")
    f.write(textutils.serializeJSON(payload))
    f.close()
    local df = fs.open("/_harness_out/done.flag", "w")
    df.write("OK")
    df.close()
end

return R
