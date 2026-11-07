-- src/main.lua
local fcp_runtime = require("fcp_runtime")
local ui_renderer = require("ui_renderer")

local fcp_main = {}

function fcp_main.parse_args(args)
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

function fcp_main.load_config(path)
    local targetPath = path or "config/fcp_config.json"
    if not fs.exists(targetPath) then
        targetPath = "src/2_guidance/fcp/config/fcp_config.json"
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

function fcp_main.create_context(config)
    return fcp_runtime.create_context(config)
end

function fcp_main.step_tick(context)
    return fcp_runtime.step_tick(context, 0.05, os.epoch and os.epoch("utc") or 0)
end

function fcp_main.run(opts)
    local options = opts or {}
    local config = fcp_main.load_config("config/fcp_config.json")
    if options.baseChannel then
        config.channels = config.channels or {}
        config.channels.baseChannel = options.baseChannel
    end
    local ctx = fcp_main.create_context(config)
    if term and term.blit then
        ui_renderer.render(term, ctx)
    end
    if options.daemon then
        return fcp_runtime.run(ctx, options)
    end
    fcp_runtime.step_tick(ctx, 0.05, os.epoch and os.epoch("utc") or 0)
    return ctx
end

local args = { ... }
local is_required = (select("#", ...) > 0 and args[1] == "main")
if not is_required then
    local parsed = fcp_main.parse_args(args)
    fcp_main.run(parsed)
end

return fcp_main
