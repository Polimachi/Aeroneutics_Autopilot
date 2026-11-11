-- tests/0_infra/landing_pad/test_setup_and_tui.lua
local setup_wizard = require("setup_wizard")
local tui_view = require("tui_view")
local offset_transform = require("offset_transform")

describe("Landing pad commissioning setup wizard and 51x19 TUI view", function()
    it("derives channels correctly from sector and index in Step 1", function()
        local ch = setup_wizard.derive_channels(1, 1)
        assert_eq(ch.sectorChannel, 50201)
        assert_eq(ch.sectorFacilityChannel, 50202)
        assert_eq(ch.sectorGpsReplyChannel, 50206)
        assert_eq(ch.tacticalChannel, 50211)

        local ch2 = setup_wizard.derive_channels(2, 5)
        assert_eq(ch2.sectorChannel, 50401)
        assert_eq(ch2.sectorFacilityChannel, 50402)
        assert_eq(ch2.sectorGpsReplyChannel, 50406)
        assert_eq(ch2.tacticalChannel, 50415)
    end)

    it("evaluates Step 3 sensor health and triggers HALT_WITH_WARNING on missing dynamic sensor", function()
        local wizard = setup_wizard.create(offset_transform)
        local reportMissing = { gimbal = false, altitude = true, velocity = true }
        local ok, status = wizard:evaluate_sensors("DYNAMIC", reportMissing)
        assert_false(ok)
        assert_eq(status, "HALT_WITH_WARNING")

        local reportAll = { gimbal = true, altitude = true, velocity = true }
        local ok2, status2 = wizard:evaluate_sensors("DYNAMIC", reportAll)
        assert_true(ok2)
        assert_eq(status2, "READY")
    end)

    it("calculates live touchdown preview using offset transform in Step 4", function()
        local wizard = setup_wizard.create(offset_transform)
        local compPos = { x = 1240.0, y = 64.0, z = -824.5 }
        local bodyOffset = { forward = 12.0, right = -4.5, up = 1.2 }
        local preview = wizard:calculate_preview(compPos, 0.0, 90.0, bodyOffset)
        -- Heading: yaw 0 + mounting 90 = 90 deg (East: +X).
        -- fwd 12.0 moves in +X direction: 1240.0 + 12.0 = 1252.0.
        -- right -4.5 moves in -Z direction: -824.5 - (-4.5) ... wait, right in Minecraft:
        -- yaw 90: sin=1, cos=0.
        -- padX = cx + fwd*sin(90) + right*cos(90) = cx + 12.0
        -- padZ = cz - fwd*cos(90) + right*sin(90) = cz + right = -824.5 + (-4.5) = -829.0
        assert_near(preview.x, 1252.0, 1e-4)
        assert_near(preview.y, 65.2, 1e-4)
    end)

    it("renders 51x19 daemon view without terminal boundary violations", function()
        local termMock = mock.term(51, 19)
        local view = tui_view.create(termMock)

        local data = {
            padId = "PAD_BRAVO_01",
            mode = "DYNAMIC",
            sectorIndex = 1,
            tacticalChannel = 50211,
            state = "APPROACH_DYNAMIC",
            targetAircraft = "AIRCRAFT_01",
            touchdownPoint = { x = 840.25, y = 62.10, z = 1120.80 },
            velocity = { vx = 6.20, vy = -0.15, vz = 1.10 },
            tiltAngleDeg = 2.77,
            heaveRateMps = -0.15,
            deckStatus = "STABLE",
            landingPermitted = true,
            lastGacSyncSec = 0.2,
            slotRemainingSec = 45,
            slotDurationSec = 120,
            lastLog = "13:45:12 [TX] DYN_GUIDE seq=45120 -> AIRCRAFT_01"
        }

        view:render_daemon(data)
        -- Assert that screen buffer has width 51 and height 19 without errors
        local line1 = termMock._get_line(1)
        assert_eq(#line1, 51)
        local line19 = termMock._get_line(19)
        assert_eq(#line19, 51)
    end)

    it("renders countdown screen correctly", function()
        local termMock = mock.term(51, 19)
        local view = tui_view.create(termMock)
        view:render_countdown("PAD_BRAVO_01", "DYNAMIC", 2, 50201, 50211)

        local line1 = termMock._get_line(1)
        assert_eq(#line1, 51)
        local line7 = termMock._get_line(7)
        assert_true(string.find(line7, "%[ 2 %]") ~= nil)
    end)

    it("assembles schema-valid configuration passing config_store.validate_config", function()
        local config_store = require("config_store")
        local wizard = setup_wizard.create(offset_transform)
        local assembled = wizard:assemble_config({
            padId = "PAD_WIZ_01",
            sectorIndex = 2,
            padIndex = 4,
            mode = "DYNAMIC",
            x = 120, y = 70, z = -340,
        })
        local ok, err = config_store.validate_config(assembled)
        assert_true(ok, err)
        assert_eq(assembled.facilityId, "PAD_WIZ_01")
        assert_eq(assembled.padId, "PAD_WIZ_01")
        assert_eq(assembled.sectorId, 2)
        assert_eq(assembled.sectorIndex, 2)
        assert_eq(assembled.mobility, "DYNAMIC")
        assert_eq(assembled.mode, "DYNAMIC")
        assert_eq(assembled.version, "2.4.0")
        assert_eq(assembled.wirelessModemSide, "top")
        assert_eq(assembled.slotDurationSec, 120)
        assert_eq(assembled.gacChannel, 50401)
        assert_eq(assembled.sectorFacilityChannel, 50402)
        assert_eq(assembled.sectorGpsReplyChannel, 50406)
        assert_eq(assembled.tacticalChannel, 50414)
        assert_eq(assembled.channels.sectorGpsReplyChannel, 50406)
    end)
end)
