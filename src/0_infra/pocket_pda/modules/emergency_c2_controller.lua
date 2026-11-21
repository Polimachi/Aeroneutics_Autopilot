-- src/0_infra/pocket_pda/modules/emergency_c2_controller.lua
-- Pocket PDA single-key E_STOP+dump, tactical C2, and PBIT request controller (ICD v1.9.5)

local pda_network = require("pda_network")

local emergency_c2_controller = {}

local TACTICAL_COMMANDS = {
    HOLD = { command = "HOLD", flightMode = "HOVER_HOLD" },
    RTB = { command = "RTH", flightMode = "FAILSAFE_RTH" },
    RTH = { command = "RTH", flightMode = "FAILSAFE_RTH" },
    LAND_NEAREST = { command = "LAND_NEAREST", flightMode = "LANDING" },
    LAND = { command = "LAND", flightMode = "EMERGENCY_LAND" },
    ARM = { command = "ARM", flightMode = "IDLE_ARMED" },
    DISARM = { command = "DISARM", flightMode = "IDLE_ARMED" },
    TAKEOFF = { command = "TAKEOFF", flightMode = "TAKEOFF" },
}

local function get_time_ms(now_ms)
    if type(now_ms) == "number" then return now_ms end
    if os and os.epoch then return os.epoch("utc") end
    if os and os.time then return math.floor(os.time() * 1000) end
    return 0
end

--- Transmit E_STOP on Base+9 followed immediately by FDR DUMP_NOW on Base+9 (+ fdrBoundBase+9 if different).
function emergency_c2_controller.trigger_estop_and_fdr_dump(net_ctx, hud_state, link_state, reason, now_ms)
    if type(net_ctx) ~= "table" or not net_ctx.modem then
        return false
    end
    local estop_ok = pda_network.transmit_to_aircraft(net_ctx, 9, 9, "MSG_EMERGENCY_OVERRIDE", {
        action = "E_STOP",
        authKey = "ESTOP_CONFIRM_KEY",
        source = "POCKET_PDA",
        targetCraft = net_ctx.targetDomainId,
        reason = reason or "PDA_OPERATOR_ESTOP",
    }, now_ms)
    if not estop_ok then
        return false
    end

    local dump_payload = {
        action = "DUMP_NOW",
        targetAircraftIndexN = net_ctx.aircraftIndexN,
        targetDomainId = net_ctx.targetDomainId,
        source = "POCKET_PDA",
        reason = "PDA_ESTOP_DUMP",
    }
    local dump_ok = pda_network.transmit_to_aircraft(net_ctx, 9, 9, "MSG_FDR_REMOTE_CMD", dump_payload, now_ms)
    if type(link_state) == "table" and type(link_state.fdr) == "table" then
        local fdr_base = pda_network.compute_craft_base(link_state.fdr.boundIndexN)
        if fdr_base and fdr_base ~= net_ctx.baseChannel then
            pda_network.transmit_raw_channel(net_ctx, fdr_base + 9, fdr_base + 9, "MSG_FDR_REMOTE_CMD", dump_payload, nil, now_ms)
        end
        link_state.fdr.lastCmd = "DUMP_NOW"
        link_state.fdr.lastCmdMs = get_time_ms(now_ms)
    end
    if type(hud_state) == "table" then
        hud_state.lastCommand = "E_STOP"
    end
    return dump_ok == true
end

--- Transmit GCS_OVERRIDE MSG_OPERATOR_CMD on Base+0 for HOLD, RTB/RTH, LAND_NEAREST, LAND, ARM, DISARM, TAKEOFF.
function emergency_c2_controller.send_tactical_c2(net_ctx, hud_state, command, params, now_ms)
    if type(net_ctx) ~= "table" or not net_ctx.modem then
        return false, "ERR_NO_MODEM"
    end
    local spec = (type(command) == "string") and TACTICAL_COMMANDS[string.upper(command)] or nil
    if not spec then
        return false, "ERR_UNKNOWN_C2_COMMAND"
    end

    local cmd_params = {}
    if type(params) == "table" then
        for k, v in pairs(params) do
            cmd_params[k] = v
        end
    end
    if cmd_params.source == nil then
        cmd_params.source = "POCKET_PDA"
    end
    if spec.command == "LAND_NEAREST" and cmd_params.facilityTypeFilter == nil then
        cmd_params.facilityTypeFilter = "ANY"
    end

    local ok = pda_network.transmit_to_aircraft(net_ctx, 0, 0, "MSG_OPERATOR_CMD", {
        authority = "GCS_OVERRIDE",
        command = spec.command,
        flightMode = spec.flightMode,
        targetCraft = net_ctx.targetDomainId,
        params = cmd_params,
    }, now_ms)
    if not ok then
        return false, "ERR_TX_FAILED"
    end
    if type(hud_state) == "table" then
        hud_state.lastCommand = spec.command
    end
    return true, nil
end

--- Transmit MSG_PBIT_REQ on Base+8 to request pre-flight PBIT diagnostics.
function emergency_c2_controller.send_pbit_request(net_ctx, run_wiggle, now_ms)
    if type(net_ctx) ~= "table" or not net_ctx.modem then
        return false
    end
    local next_seq = (net_ctx.seq or 0) + 1
    local ok = pda_network.transmit_to_aircraft(net_ctx, 8, 8, "MSG_PBIT_REQ", {
        requestId = "PDA-PBIT-" .. tostring(next_seq),
        source = "POCKET_PDA",
        runWiggle = (run_wiggle == true),
    }, now_ms)
    return ok == true
end

return emergency_c2_controller
