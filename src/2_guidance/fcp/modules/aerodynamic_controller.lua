-- [DEPRECATED in v1.8.0]: ASA control and Base+7 socket transferred to VAS Layer 3 (actuator_adapter_asa).
-- src/modules/aerodynamic_controller.lua
local aerodynamic_controller = {}

function aerodynamic_controller.is_enabled_for_airframe(airframe_type)
    if airframe_type == "FIXED_WING" or airframe_type == "WINGED_VTOL" then
        return true
    end
    return false
end

function aerodynamic_controller.init(config)
    local cfg = config or {}
    local sys = cfg.system or {}
    return {
        airframeType = sys.airframeType or "VECTORED_VTOL",
        flapPosition = 0.0,
    }
end

function aerodynamic_controller.compute_surfaces(state, attitude_cmd, dynamic_pressure)
    return {
        aileron = 0.0,
        elevator = 0.0,
        rudder = 0.0,
        flap = state and state.flapPosition or 0.0,
    }
end

function aerodynamic_controller.update_flaps(state, indicated_airspeed, flight_phase)
    if state then
        state.flapPosition = 0.0
    end
    return 0.0
end

function aerodynamic_controller.build_surface_packet(state, surfaces)
    if not state or not aerodynamic_controller.is_enabled_for_airframe(state.airframeType) then
        return nil
    end
    return {
        type = "MSG_SURFACE_CMD",
        payload = surfaces or {},
    }
end

function aerodynamic_controller.handle_surface_status(pkt, airframe_type)
    local p = (pkt and pkt.payload) or {}
    local health = p.healthStatus or "NOMINAL"
    local is_vtol = (airframe_type == "VECTORED_VTOL" or airframe_type == "ADVANCED_VTOL" or airframe_type == "QUADROTOR" or airframe_type == "HEXAROTOR")
    if health == "DEGRADED" then
        return {
            action = "WARN",
            alertBanner = "ASA_DEGRADED_WARN",
            requestFailsafe = not is_vtol,
            healthStatus = health,
        }
    elseif health == "TOTAL_LOSS" or p.isJammed then
        return {
            action = "WARN",
            alertBanner = "ASA_TOTAL_LOSS_WARN",
            requestFailsafe = not is_vtol,
            healthStatus = health,
        }
    end
    return {
        action = "NOMINAL",
        alertBanner = nil,
        requestFailsafe = false,
        healthStatus = health,
    }
end

return aerodynamic_controller
