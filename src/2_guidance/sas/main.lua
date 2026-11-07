-- src/main.lua
local sas_runtime = require("sas_runtime")
local ui_renderer = require("ui_renderer")

local sas_main = {}

function sas_main.parse_args(args)
    local opts = { daemon = false, baseChannel = nil }
    if not args then return opts end
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--daemon" or a == "-d" then
            opts.daemon = true
        elseif a == "--base" or a == "-b" then
            i = i + 1
            opts.baseChannel = tonumber(args[i])
        elseif tonumber(a) then
            opts.baseChannel = tonumber(a)
        end
        i = i + 1
    end
    return opts
end

function sas_main.load_config(path)
    local targetPath = path or "config/sas_config.json"
    if not fs.exists(targetPath) then
        targetPath = "src/config/sas_config.json"
    end
    if not fs.exists(targetPath) then
        return {}
    end
    local h = fs.open(targetPath, "r")
    if not h then return {} end
    local content = h.readAll()
    h.close()
    return textutils.unserializeJSON(content) or {}
end

function sas_main.create_context(config)
    return sas_runtime.create_context(config)
end

function sas_main.step_tick(context)
    return sas_runtime.step_tick(context, 0.05, os.epoch and os.epoch("utc") or 0)
end

function sas_main.run(opts)
    local options = opts or {}
    local config = sas_main.load_config("config/sas_config.json")
    if options.baseChannel then
        config.channels = config.channels or {}
        config.channels.baseChannel = options.baseChannel
    end
    local ctx = sas_main.create_context(config)
    if term and term.blit then
        ui_renderer.render(term, ctx)
    end
    if options.daemon then
        return sas_runtime.run(ctx, options)
    end
    sas_runtime.step_tick(ctx, 0.05, os.epoch and os.epoch("utc") or 0)
    return ctx
end

local args = { ... }
local is_required = (select("#", ...) > 0 and args[1] == "main")
if not is_required then
    local parsed = sas_main.parse_args(args)
    sas_main.run(parsed)
end

return sas_main
