-- src/2_guidance/fcp/main.lua
-- FCP v2.0.0 SE(3) Outer-Loop Guidance Controller Main Entry
-- CC:Tweaked Lua 5.2 / Cobalt VM compliant: all functions <= 50 lines, Zero-Fallback

local network_manager = require("network_manager")
local state_propagator = require("state_propagator")
local flight_fsm = require("flight_fsm")
local outer_loop_controller = require("outer_loop_controller")
local ui_renderer = require("ui_renderer")

local fcp_main = {}

function fcp_main.parse_args(args)
    local opts = { daemon = false, baseChannel = nil, debug = nil }
    if not args then return opts end
    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--daemon" or a == "-d" then
            opts.daemon = true
        elseif a == "--debug" then
            opts.debug = true
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
    if fs and fs.exists and not fs.exists(targetPath) then
        targetPath = "src/2_guidance/fcp/config/fcp_config.json"
    end
    local cfg = {}
    if fs and fs.exists and fs.exists(targetPath) then
        local h = fs.open(targetPath, "r")
        if h then
            local raw = h.readAll()
            h.close()
            cfg = (textutils and textutils.unserializeJSON and textutils.unserializeJSON(raw)) or {}
        end
    end
    cfg.system = cfg.system or {}
    if cfg.system.debug == nil then cfg.system.debug = false end
    if not cfg.system.airframeType then cfg.system.airframeType = "VECTORED_VTOL" end
    cfg.channels = cfg.channels or {}
    if not cfg.channels.baseChannel then cfg.channels.baseChannel = 10000 end
    if not cfg.channels.trajectoryOffset then cfg.channels.trajectoryOffset = 4 end
    if not cfg.channels.telemetryOffset then cfg.channels.telemetryOffset = 2 end
    if not cfg.channels.guidanceOffset then cfg.channels.guidanceOffset = 1 end
    return cfg
end

function fcp_main.create_context(config, modemResolver)
    local cfg = config or fcp_main.load_config()
    local safe = cfg.safety or {}
    local net = network_manager.init(cfg, modemResolver)
    local fsm = flight_fsm.init(cfg, safe)
    local ctrl = outer_loop_controller.init(cfg)
    local nav = state_propagator.init(cfg.propagation)

    return {
        config = cfg,
        net = net,
        fsm = fsm,
        ctrl = ctrl,
        nav = nav,
        running = true,
        tick = 0,
        lastTickMs = 0,
        lastAmmSetpoint = nil,
        lastTelemPayload = nil,
        rampAlpha = 1.0,
        rampStartMs = nil,
        bumplessRampSec = tonumber(safe.bumplessRampSec) or 2.0,
        latestOuterLoopStatus = nil,
    }
end

local function handle_bumpless_ramp(ctx, events, now)
    if events.triggerBumpless then
        ctx.rampStartMs = now
        ctx.rampAlpha = 0.0
    end
    if ctx.rampStartMs then
        local elapsed = (now - ctx.rampStartMs) / 1000.0
        local rampSec = ctx.bumplessRampSec or 2.0
        if elapsed >= rampSec then
            ctx.rampStartMs = nil
            ctx.rampAlpha = 1.0
        else
            ctx.rampAlpha = elapsed / rampSec
        end
    else
        ctx.rampAlpha = 1.0
    end
end

local function compute_tracking_errors(nav, sp)
    local p = (nav and nav.pos) or { x = 0, y = 0, z = 0 }
    local v = (nav and nav.vel) or { vx = 0, vy = 0, vz = 0 }
    local tp = (sp and sp.targetPos) or p
    local tv = (sp and sp.targetVel) or { vx = 0, vy = 0, vz = 0 }
    local dx = (tp.x or p.x) - p.x
    local dy = (tp.y or p.y) - p.y
    local dz = (tp.z or p.z) - p.z
    local posErr = math.sqrt(dx * dx + dy * dy + dz * dz)
    local dvx = (tv.vx or tv.x or 0.0) - (v.vx or v.x or 0.0)
    local dvy = (tv.vy or tv.y or 0.0) - (v.vy or v.y or 0.0)
    local dvz = (tv.vz or tv.z or 0.0) - (v.vz or v.z or 0.0)
    local velErr = math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz)
    return posErr, velErr
end

local function build_fsm_ctx(ctx, inbound)
    local telemPayload = (inbound.telemetry and inbound.telemetry.payload) or ctx.lastTelemPayload or {}
    local spPayload = (inbound.trajectory and inbound.trajectory.payload) or ctx.lastAmmSetpoint or {}
    return {
        setpoint = spPayload,
        telemetry = telemPayload,
        telemState = telemPayload,
        emergencyAlert = (inbound.emergencyAlert ~= nil) or (telemPayload.controlState == "E_STOP"),
        channelsReady = true,
        touchdownComplete = (telemPayload.touchdownComplete == true),
    }
end

local function dispatch_idle_armed(ctx, posErr, velErr, sp)
    local att_cmd = {
        source = "FCP",
        arm = ctx.fsm.arm or false,
        flightActive = false,
        flightMode = "IDLE_ARMED",
        commandType = "QUATERNION_RATE",
        targetQuaternion = { w = 1.0, x = 0.0, y = 0.0, z = 0.0 },
        targetAngularRates = { pitchRate = 0.0, rollRate = 0.0, yawRate = 0.0 },
        collectiveThrust = 0.0,
        acroActive = false,
    }
    network_manager.send_attitude_cmd(ctx.net, att_cmd)
    outer_loop_controller.reset_integrators(ctx.ctrl)

    local status_payload = {
        fsmState = "IDLE_ARMED",
        posError = posErr,
        velError = velErr,
        saturated = false,
        navStale = ctx.nav.navStale or false,
        activeConstraintProfile = sp.constraintProfile or "STRICT_LEVEL",
        commandedCollectiveThrust = 0.0,
    }
    network_manager.send_outer_loop_status(ctx.net, status_payload)
    ctx.latestOuterLoopStatus = status_payload
end

local function dispatch_active_flight(ctx, currState, dt, posErr, velErr, sp)
    local satFlags = {
        rampAlpha = ctx.rampAlpha,
        navStale = ctx.nav.navStale,
        actuatorHealth = ctx.nav.actuatorHealth,
        vasSat = ctx.lastTelemPayload and ctx.lastTelemPayload.satFlags,
        currentState = currState,
        arm = ctx.fsm.arm,
        flightActive = ctx.fsm.flightActive,
    }
    local cmd = outer_loop_controller.compute(ctx.ctrl, ctx.nav, sp, satFlags, dt)
    network_manager.send_attitude_cmd(ctx.net, cmd)

    local status_payload = {
        fsmState = currState,
        posError = posErr,
        velError = velErr,
        saturated = false,
        navStale = ctx.nav.navStale or false,
        activeConstraintProfile = sp.constraintProfile or "STRICT_LEVEL",
        commandedCollectiveThrust = cmd.collectiveThrust or 0.0,
    }
    network_manager.send_outer_loop_status(ctx.net, status_payload)
    ctx.latestOuterLoopStatus = status_payload
end

local function dispatch_outputs(ctx, dt, posErr, velErr)
    local currState = ctx.fsm.currentState or "BOOT"
    local sp = ctx.lastAmmSetpoint or {}

    if currState == "PASSIVE_TRACKING" then
        local status_payload = {
            fsmState = currState,
            posError = posErr,
            velError = velErr,
            saturated = false,
            navStale = ctx.nav.navStale or false,
            activeConstraintProfile = sp.constraintProfile or "STRICT_LEVEL",
            commandedCollectiveThrust = 0.0,
        }
        network_manager.send_outer_loop_status(ctx.net, status_payload)
        ctx.latestOuterLoopStatus = status_payload
    elseif currState == "IDLE_ARMED" then
        dispatch_idle_armed(ctx, posErr, velErr, sp)
    elseif currState == "ACTIVE_TRACKING" or currState == "AMM_TIMEOUT_HOLD" or currState == "EMERGENCY_LAND" then
        dispatch_active_flight(ctx, currState, dt, posErr, velErr, sp)
    end
end

function fcp_main.step_tick(ctx, dt, now_ms)
    local now = tonumber(now_ms) or (os.epoch and os.epoch("utc") or 0)
    local d_t = (tonumber(dt) and dt > 0) and dt or 0.05

    local inbound = network_manager.poll_all(ctx.net)
    network_manager.step_rebind_watchdog(ctx.net, now)

    if inbound.telemetry and inbound.telemetry.payload then
        ctx.lastTelemPayload = inbound.telemetry.payload
        state_propagator.on_telemetry(ctx.nav, inbound.telemetry.payload, now)
    end
    if inbound.trajectory and inbound.trajectory.payload then
        local p = inbound.trajectory.payload
        p.lastRxMs = p.lastRxMs or now
        ctx.lastAmmSetpoint = p
        state_propagator.on_setpoint_epoch(ctx.nav, p, now)
    end

    state_propagator.propagate(ctx.nav, now)

    local fsm_ctx = build_fsm_ctx(ctx, inbound)
    local new_fsm, events = flight_fsm.step(ctx.fsm, fsm_ctx, now)
    ctx.fsm = new_fsm

    if events and events.resetIntegrators then
        outer_loop_controller.reset_integrators(ctx.ctrl)
    end
    handle_bumpless_ramp(ctx, events or {}, now)

    local posErr, velErr = compute_tracking_errors(ctx.nav, ctx.lastAmmSetpoint)
    dispatch_outputs(ctx, d_t, posErr, velErr)

    ctx.tick = (ctx.tick or 0) + 1
    ctx.lastTickMs = now
    return ctx
end

local function run_control_loop(ctx)
    local timer_id = os.startTimer(0.05)
    while ctx.running do
        local event_data = { os.pullEventRaw() }
        local ev = event_data[1]
        if ev == "timer" and event_data[2] == timer_id then
            fcp_main.step_tick(ctx, 0.05, os.epoch and os.epoch("utc") or 0)
            timer_id = os.startTimer(0.05)
        elseif ev == "modem_message" then
            network_manager.ingest_modem_event(ctx.net, event_data[2], event_data[3], event_data[4], event_data[5], event_data[6], os.epoch and os.epoch("utc") or 0)
        elseif ev == "terminate" then
            ctx.running = false
        end
    end
end

local function run_ui_loop(ctx)
    local ui_timer = os.startTimer(0.20)
    while ctx.running do
        local event_data = { os.pullEventRaw() }
        local ev = event_data[1]
        if ev == "timer" and event_data[2] == ui_timer then
            if term and term.blit then
                ui_renderer.render(term, ctx)
            end
            ui_timer = os.startTimer(0.20)
        elseif ev == "key" or ev == "char" or ev == "terminate" then
            ctx.running = false
        end
    end
end

function fcp_main.run(opts)
    local options = opts or {}
    local config = fcp_main.load_config("config/fcp_config.json")
    if options.baseChannel then
        config.channels.baseChannel = options.baseChannel
    end
    if options.debug ~= nil then
        config.system.debug = options.debug
    end
    local ctx = fcp_main.create_context(config)

    local is_debug = (config.system and config.system.debug == true)
    if is_debug and parallel and parallel.waitForAny then
        parallel.waitForAny(
            function() run_control_loop(ctx) end,
            function() run_ui_loop(ctx) end
        )
    else
        run_control_loop(ctx)
    end
    return ctx
end

local args = { ... }
local is_required = (select("#", ...) > 0 and args[1] == "main")
if not is_required then
    local parsed = fcp_main.parse_args(args)
    fcp_main.run(parsed)
end

return fcp_main
