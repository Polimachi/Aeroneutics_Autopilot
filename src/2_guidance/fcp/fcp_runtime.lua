-- src/fcp_runtime.lua
local network_manager = require("network_manager")
local channel_sentinel = require("channel_sentinel")
local thruster_profile = require("thruster_profile")
local nav_engine = require("nav_engine")
local facility_client = require("facility_client")
local operator_handler = require("operator_handler")
local flight_fsm = require("flight_fsm")
local guidance_controller = require("guidance_controller")
local ui_renderer = require("ui_renderer")

local fcp_runtime = {}

function fcp_runtime.create_context(config, modem_lookup)
    local cfg = config or {}
    return {
        config = cfg,
        running = true,
        tick = 0,
        net = network_manager.init(cfg, modem_lookup),
        channel = channel_sentinel.init(cfg),
        profile = thruster_profile.init(cfg),
        nav = nav_engine.init(cfg),
        facility = facility_client.init(cfg),
        operator = operator_handler.init(cfg),
        fsm = flight_fsm.init(cfg),
        guidance = guidance_controller.init(cfg),
        lastActiveSource = "FCP",
        pendingC2Cmd = nil,
        actuatorHealth = { tca = true, asa = true, allOk = true },
        mission_target = { x = 0.0, y = 64.0, z = -50.0 },
    }
end

local function ensure_modules(ctx)
    if not ctx.net then ctx.net = network_manager.init(ctx.config) end
    if not ctx.channel then ctx.channel = channel_sentinel.init(ctx.config) end
    if not ctx.profile then ctx.profile = thruster_profile.init(ctx.config) end
    if not ctx.nav then ctx.nav = nav_engine.init(ctx.config) end
    if not ctx.facility then ctx.facility = facility_client.init(ctx.config) end
    if not ctx.operator then ctx.operator = operator_handler.init(ctx.config) end
    if not ctx.fsm then ctx.fsm = flight_fsm.init(ctx.config) end
    if not ctx.guidance then ctx.guidance = guidance_controller.init(ctx.config) end
    if not ctx.mission_target then ctx.mission_target = { x = 0.0, y = 64.0, z = -50.0 } end
end

local function send_mfd_telemetry(ctx, nav_summary)
    local cur_x = nav_summary.pos and nav_summary.pos.x or 0.0
    local cur_z = nav_summary.pos and nav_summary.pos.z or 0.0
    local wp_x = ctx.mission_target and ctx.mission_target.x or 0.0
    local wp_z = ctx.mission_target and ctx.mission_target.z or 0.0
    local dx = wp_x - cur_x
    local dz = wp_z - cur_z
    local dist_wp = math.sqrt(dx * dx + dz * dz)

    local mfd_payload = {
        attitude = nav_summary.attitude or { pitch = 0, roll = 0, heading = 0 },
        dynamics = {
            altitudeY = nav_summary.pos and nav_summary.pos.y or 64.0,
            verticalSpeed = nav_summary.vel and nav_summary.vel.y or 0.0,
            groundSpeed = nav_summary.groundSpeed or 0.0,
        },
        fuel = nav_summary.fuel or 1.0,
        fsmState = ctx.fsm.current_state,
        activeSource = "FCP",
        navigation = {
            currentPos = { x = cur_x, z = cur_z },
            targetWaypoint = { x = wp_x, z = wp_z },
            crossTrackError = 0.0,
            distanceToWp = dist_wp,
        },
        actuatorHealth = ctx.actuatorHealth or { tca = true, asa = true, allOk = true },
    }
    network_manager.send_mfd_state(ctx.net, mfd_payload)
end

local function process_inbox(ctx, polled, now_ms)
    if polled.telemetry then
        nav_engine.integrate_dr(ctx.nav, polled.telemetry.payload, 0.05, now_ms)
        local p = polled.telemetry.payload
        if p then
            if p.activeSource then ctx.lastActiveSource = p.activeSource end
            if p.actuatorHealth then ctx.actuatorHealth = p.actuatorHealth end
        end
    end
    if polled.gps then
        nav_engine.filter_gps(ctx.nav, polled.gps.payload, 0.05, now_ms)
    end
    if polled.calibration then
        thruster_profile.on_profile_sync(ctx.profile, polled.calibration.payload, true)
    end
    if polled.actuator then
        thruster_profile.on_actuator_status(ctx.profile, polled.actuator.payload)
    end
    if polled.c2 then
        local c2_res = operator_handler.process_c2(ctx.operator, polled.c2, now_ms)
        if c2_res.accepted then
            if c2_res.action then
                if ctx.fsm and ctx.fsm.inFlight then
                    if c2_res.action == "EMERGENCY_LAND" then
                        flight_fsm.transition_to(ctx.fsm, "EMERGENCY_LAND", "C2_EMERGENCY_LAND")
                    elseif c2_res.action == "HOVER_HOLD" then
                        flight_fsm.transition_to(ctx.fsm, "FAILSAFE_HOLD", "C2_HOVER_HOLD")
                    elseif c2_res.action == "RTH" then
                        flight_fsm.transition_to(ctx.fsm, "FAILSAFE_RTH", "C2_RTH")
                    end
                end
            elseif c2_res.flightMode or c2_res.command then
                local mode = c2_res.flightMode or c2_res.command
                ctx.pendingC2Cmd = mode
                local in_flight = (ctx.fsm and ctx.fsm.inFlight == true)
                local entering_hold = in_flight and (mode == "LOITER" or mode == "POI_HOLD") and (ctx.fsm.current_state ~= mode)
                if not ctx.mission_target then
                    ctx.mission_target = { x = 0.0, y = 64.0, z = -50.0 }
                end
                local p = c2_res.params
                if p then
                    if p.targetWaypoint and p.targetWaypoint.x ~= nil and p.targetWaypoint.z ~= nil then
                        ctx.mission_target.x = p.targetWaypoint.x
                        ctx.mission_target.z = p.targetWaypoint.z
                    elseif entering_hold and ctx.nav and ctx.nav.pos then
                        ctx.mission_target.x = ctx.nav.pos.x
                        ctx.mission_target.z = ctx.nav.pos.z
                    end
                    if p.targetAlt ~= nil then
                        ctx.mission_target.y = p.targetAlt
                    elseif entering_hold and ctx.nav and ctx.nav.pos and ctx.nav.pos.y ~= nil then
                        ctx.mission_target.y = ctx.nav.pos.y
                    end
                    if p.targetSpeed ~= nil then ctx.mission_target.targetSpeed = p.targetSpeed end
                    if p.headingMode ~= nil then ctx.mission_target.headingMode = p.headingMode end
                    if p.fixedHeading ~= nil then
                        ctx.mission_target.fixedHeading = p.fixedHeading
                    elseif p.headingMode ~= nil and p.headingMode ~= "FIXED" then
                        ctx.mission_target.fixedHeading = nil
                    end
                    if p.poiTarget ~= nil then ctx.mission_target.poiTarget = p.poiTarget end
                    if p.loiterRadius ~= nil then ctx.mission_target.loiterRadius = p.loiterRadius end
                    if p.loiterDirection ~= nil then ctx.mission_target.loiterDirection = p.loiterDirection end
                    if p.designatedFacilityId ~= nil then ctx.mission_target.designatedFacilityId = p.designatedFacilityId end
                elseif entering_hold and ctx.nav and ctx.nav.pos then
                    ctx.mission_target.x = ctx.nav.pos.x
                    if ctx.nav.pos.y ~= nil then ctx.mission_target.y = ctx.nav.pos.y end
                    ctx.mission_target.z = ctx.nav.pos.z
                end
                if c2_res.bumplessTransition and in_flight then
                    guidance_controller.trigger_bumpless_transition(ctx.guidance, now_ms)
                end
            end
        end
    end
    if polled.facility and polled.facility.type == "MSG_FACILITY_BEACON" then
        facility_client.update_beacons(ctx.facility, polled.facility.payload, now_ms)
    end
    if polled.rebindAck then
        channel_sentinel.on_rebind_ack(ctx.channel, polled.rebindAck, now_ms)
    end
    if ctx.channel and ctx.channel.rebindTx then
        local rebind_pkt, status = channel_sentinel.step_rebind_transaction(ctx.channel, now_ms)
        if rebind_pkt and status == "COMMITTED" then
            if network_manager.send_channel_rebind then
                network_manager.send_channel_rebind(ctx.net, rebind_pkt.payload)
            end
            network_manager.rebind_aircraft_channels(ctx.net, ctx.channel.baseChannel)
        elseif rebind_pkt and status == "ROLLED_BACK" then
            if network_manager.send_channel_rebind then
                network_manager.send_channel_rebind(ctx.net, rebind_pkt.payload)
            end
        end
    end
end

local function build_fsm_context(ctx, nav_summary)
    return {
        cmd = ctx.pendingC2Cmd,
        airframeSupported = guidance_controller.is_airframe_supported(ctx.config.system and ctx.config.system.airframeType or "VECTORED_VTOL"),
        channelAcquired = channel_sentinel.is_acquired(ctx.channel),
        channelLocked = channel_sentinel.is_locked(ctx.channel),
        takeoffGate = thruster_profile.evaluate_takeoff_gate(ctx.profile),
        hasSwayLoss = thruster_profile.has_sway_loss(ctx.profile),
        fuel = nav_summary.fuel,
        coreAlive = nav_summary.coreAlive,
        coreArmed = nav_summary.coreArmed,
        gpsTimedOut = nav_summary.gpsTimedOut,
        gpsRecovered = nav_summary.gpsRecovered,
        activeSource = ctx.lastActiveSource or "FCP",
    }
end

function fcp_runtime.step_tick(ctx, dt, now_ms)
    if not ctx or not ctx.running then return false end
    ensure_modules(ctx)
    local now = now_ms or (os.epoch and os.epoch("utc") or 0)
    ctx.tick = (ctx.tick or 0) + 1

    local polled = network_manager.poll_all(ctx.net)
    process_inbox(ctx, polled, now)

    local need_gps, req_id = nav_engine.should_query_gps(ctx.nav, now)
    if need_gps then
        network_manager.send_gps_request(ctx.net, {
            replyChannel = ctx.net.baseChannel + 5,
            altitudeY = ctx.nav.pos.y,
            clientType = "AIRCRAFT",
            clientSeq = req_id,
        })
    end

    local nav_summary = nav_engine.update(ctx.nav, dt or 0.05, now)
    local fsm_ctx = build_fsm_context(ctx, nav_summary)
    flight_fsm.evaluate(ctx.fsm, fsm_ctx, now)
    ctx.pendingC2Cmd = nil

    if ctx.fsm.current_state == "FAILSAFE_RTH" then
        local rth_eval = flight_fsm.evaluate_rth(ctx.fsm, ctx.facility, nav_summary.pos, now)
        if rth_eval and rth_eval.position then
            ctx.mission_target = rth_eval.position
        end
    end

    if ctx.fsm.current_state ~= "PASSIVE_TRACKING" then
        local is_active = flight_fsm.is_flight_active(ctx.fsm)
        local g_cmd, _ = guidance_controller.compute(ctx.guidance, nav_summary, ctx.mission_target, {
            state = ctx.fsm.current_state,
            now_ms = now,
            flightActive = is_active,
        }, dt or 0.05)
        if g_cmd and flight_fsm.is_armed(ctx.fsm) then
            network_manager.send_guidance_cmd(ctx.net, g_cmd)
        end
        if (ctx.tick % 4 == 0) then
            send_mfd_telemetry(ctx, nav_summary)
        end
    end
    return true
end

local function make_rx_worker(ctx)
    return function()
        while ctx.running do
            local event, side, ch, reply_ch, msg, dist = os.pullEvent("modem_message")
            if event == "modem_message" then
                network_manager.ingest_modem_event(ctx.net, side, ch, reply_ch, msg, dist, os.epoch and os.epoch("utc") or 0)
            end
        end
    end
end

local function make_control_worker(ctx, max_ticks)
    return function()
        while ctx.running do
            sleep(0.05)
            fcp_runtime.step_tick(ctx, 0.05, os.epoch and os.epoch("utc") or 0)
            if max_ticks and ctx.tick >= max_ticks then
                ctx.running = false
                break
            end
        end
    end
end

local function make_hud_worker(ctx)
    return function()
        while ctx.running do
            sleep(0.2)
            if term and term.blit then
                ui_renderer.render(term, ctx)
            end
        end
    end
end

local function make_event_listener(ctx)
    return function()
        while ctx.running do
            local ev = os.pullEvent()
            if ev == "key" or ev == "char" or ev == "terminate" then
                ctx.running = false
                break
            end
        end
    end
end

function fcp_runtime.run(ctx, opts)
    local options = opts or {}
    ensure_modules(ctx)
    if options.baseChannel then
        ctx.channel.baseChannel = options.baseChannel
        ctx.channel.candidateBase = options.baseChannel
        ctx.net.baseChannel = options.baseChannel
        ctx.net.mfdInstrumentChannel = options.baseChannel + 3
    end
    network_manager.bind_bootstrap_channels(ctx.net)
    network_manager.bind_aircraft_channels(ctx.net, ctx.channel.baseChannel)

    if term and term.blit then
        ui_renderer.render(term, ctx)
    end
    if options.single_tick or options.non_blocking then
        return fcp_runtime.step_tick(ctx, 0.05, 0)
    end

    parallel.waitForAny(
        make_rx_worker(ctx),
        make_control_worker(ctx, options.max_ticks),
        make_hud_worker(ctx),
        make_event_listener(ctx)
    )
    return true
end

return fcp_runtime
