-- tests/3_planning/amm/test_main_loop.lua
local waypoint_queue = require("waypoint_queue")
local network_manager = require("network_manager")
local c2_arbiter = require("c2_arbiter")
local input_handler = require("input_handler")
local ui_renderer = require("ui_renderer")

describe("AMM Main Event Pump and Command Processing", function()
    local function create_app()
        local q = waypoint_queue.new({ defaultAlt = 150, defaultSpeed = 18, arrivalRadius = 15 })
        local net = network_manager.new({ domainId = "AIRCRAFT_01", baseChannel = 10000 })
        local arb = c2_arbiter.new(q, net)
        local inp = input_handler.new()
        local buf = ui_renderer.create_buffer(51, 19)
        local tx = {}
        net.modem = {
            transmit = function(c, r, p) table.insert(tx, { chan = c, payload = p }) end,
            open = function(c) end
        }
        return {
            q = q, net = net, arb = arb, inp = inp, buf = buf, tx = tx,
            handle_command = function(self, cmd)
                if not cmd or cmd.type ~= "COMMAND" then return end
                local name = cmd.name
                local a = cmd.args
                if name == "add" then
                    self.q:add(a[1], a[2], a[3], a[4], a[5])
                elseif name == "del" then
                    self.q:del(a[1])
                elseif name == "clear" then
                    self.q:clear()
                elseif name == "goto" then
                    self.q:set_active_index(a[1])
                elseif name == "pause" then
                    self.arb:handle_pilot_action("PAUSE")
                elseif name == "resume" then
                    self.arb:handle_pilot_action("RESUME")
                elseif name == "alt" then
                    self.q.defaultAlt = tonumber(a[1]) or self.q.defaultAlt
                elseif name == "spd" then
                    self.q.defaultSpeed = tonumber(a[1]) or self.q.defaultSpeed
                elseif name == "rad" then
                    self.q.arrivalRadius = tonumber(a[1]) or self.q.arrivalRadius
                end
            end
        }
    end

    it("executes CLI commands to modify waypoint queue and settings", function()
        local app = create_app()
        app:handle_command({ type = "COMMAND", name = "add", args = { "100", "200", "160", "20" } })
        assert_eq(app.q:count(), 1)
        assert_eq(app.q:get_active().x, 100)
        assert_eq(app.q:get_active().alt, 160)

        app:handle_command({ type = "COMMAND", name = "alt", args = { "180" } })
        assert_eq(app.q.defaultAlt, 180)

        app:handle_command({ type = "COMMAND", name = "spd", args = { "22" } })
        assert_eq(app.q.defaultSpeed, 22)

        app:handle_command({ type = "COMMAND", name = "rad", args = { "25" } })
        assert_eq(app.q.arrivalRadius, 25)

        app:handle_command({ type = "COMMAND", name = "clear", args = {} })
        assert_eq(app.q:count(), 0)
    end)

    it("routes incoming HUD telemetry and GCS commands accurately", function()
        local app = create_app()
        app.q:add(500, 500)

        -- Simulating incoming Base+0 GCS command
        local gcs_pkt = {
            ver = "1.9.5",
            type = "MSG_OPERATOR_CMD",
            payload = { authority = "GCS_OVERRIDE", command = "HOLD" }
        }
        app.arb:handle_gcs_packet(gcs_pkt)
        assert_eq(app.arb.authority, "GCS_OVERRIDE")
        assert_eq(app.q.state, "SUSPENDED")

        -- Simulating pilot resume CLI command
        app:handle_command({ type = "COMMAND", name = "resume", args = {} })
        assert_eq(app.arb.authority, "PILOT_PRIMARY")
        assert_eq(app.q.state, "EN_ROUTE")
    end)
end)
