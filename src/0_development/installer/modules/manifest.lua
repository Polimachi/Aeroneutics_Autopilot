-- src/0_development/installer/modules/manifest.lua
-- Declarative module registry, bootstrap file list, and URL resolver for Create_Aeroneutics

local manifest = {}

manifest.VERSION = "1.1.0"

manifest.CATEGORY_ORDER = {
    "development",
    "infra",
    "control",
    "guidance",
    "planning",
    "mission",
}

manifest.CATEGORIES = {
    development = {
        id = "development",
        code = "0_development",
        name = "Development & Calibration",
        shortName = "Dev & Align",
        description = "Hangar calibration, sensors library, and diagnostics",
    },
    infra = {
        id = "infra",
        code = "0_infra",
        name = "Ground Infrastructure",
        shortName = "Ground Infra",
        description = "GPS cluster, GCS, GAC, landing pads, and runway",
    },
    control = {
        id = "control",
        code = "1_control",
        name = "Flight Control",
        shortName = "Flight Control",
        description = "Onboard 20Hz attitude, thruster, and aero adapters",
    },
    guidance = {
        id = "guidance",
        code = "2_guidance",
        name = "Guidance & Navigation",
        shortName = "Guidance (FCP)",
        description = "Outer-loop flight computer and airframe drivers",
    },
    planning = {
        id = "planning",
        code = "3_planning",
        name = "Mission Planning & MFD",
        shortName = "Planning (AMM)",
        description = "Cockpit MFD terminal and waypoint mission manager",
    },
    mission = {
        id = "mission",
        code = "4_mission",
        name = "Swarm & Payload Mission",
        shortName = "Swarm Mission",
        description = "Multi-craft formation and payload orchestration",
    },
}

manifest.SOURCES = {
    GITHUB = "github",
    GDRIVE = "gdrive",
}

manifest.BASE_URLS = {
    github = "https://raw.githubusercontent.com/Polimachi/Aeroneutics_Autopilot/main/",
    gdrive = "https://drive.usercontent.google.com/download?id=",
}

manifest.BOOTSTRAP_FILES = {
    { repoPath = "src/0_development/installer/installer_app.lua", cacheRelPath = "installer_app.lua", gdriveId = "1j9NXsI05yH7msK3tKX-JX3nHDObRVCDx" },
    { repoPath = "src/0_development/installer/modules/manifest.lua", cacheRelPath = "modules/manifest.lua", gdriveId = "1Lj-L-ZAIydyVxQWCVTEzT1qCDDIrCWwX" },
    { repoPath = "src/0_development/installer/modules/version_registry.lua", cacheRelPath = "modules/version_registry.lua", gdriveId = "1jognQdVANYbEWefN8ET31YHgKUtNOQUO" },
    { repoPath = "src/0_development/installer/modules/migration_engine.lua", cacheRelPath = "modules/migration_engine.lua", gdriveId = "1YcYOmM3qK2cd9HXmPXHUvxTMkfvL9kKk" },
    { repoPath = "src/0_development/installer/modules/startup_generator.lua", cacheRelPath = "modules/startup_generator.lua", gdriveId = "1RLN2cvyI7_1X1HTo5tGcOWx66dYkfhII" },
    { repoPath = "src/0_development/installer/modules/downloader.lua", cacheRelPath = "modules/downloader.lua", gdriveId = "1EIS_Ife6L12eCijlDPDKx8Z5GVdnYU4F" },
    { repoPath = "src/0_development/installer/modules/tui_view.lua", cacheRelPath = "modules/tui_view.lua", gdriveId = "1O6TC-Teg0_VIifb-DzcsfCyeGrBylzRt" },
}

manifest.SHARED_LIBS = {
    avionics_sensors = {
        repoPath = "src/0_development/sensors/avionics_sensors.lua",
        dest = "/lib/avionics_sensors.lua",
        gdriveId = nil,
    },
}

manifest.MODULE_ORDER = {
    "vas",
    "tca",
    "fcp",
    "alignment",
    "gps_server",
    "gps_node",
    "gps_client",
    "sensors",
    "gac",
    "landing_pad",
    "amm",
    "gcs",
}

manifest.MODULES = {
    vas = {
        id = "vas",
        name = "VAS",
        category = "control",
        version = "1.15.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_vas.lua",
            target = "/main.lua",
            name = "VAS",
        },
        defaultConfigs = {
            ["/config/system.json"] = {
                aircraftIndexN = 1,
                baseChannel = 10000,
                bandwidth = 40,
            },
        },
        files = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_tca.lua", dest = "/modules/actuator_adapter_tca.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_asa.lua", dest = "/modules/actuator_adapter_asa.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/core_daemon.lua", dest = "/modules/core_daemon.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/dynamic_trim_compensator.lua", dest = "/modules/dynamic_trim_compensator.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/flight_dynamics_core.lua", dest = "/modules/flight_dynamics_core.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/preflight_bit.lua", dest = "/modules/preflight_bit.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/quat.lua", dest = "/modules/quat.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/sensor_pipeline.lua", dest = "/modules/sensor_pipeline.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/state_machine.lua", dest = "/modules/state_machine.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/telemetry_feeder.lua", dest = "/modules/telemetry_feeder.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/thrust_mixer.lua", dest = "/modules/thrust_mixer.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/vec3.lua", dest = "/modules/vec3.lua", gdriveId = nil },
            { repoPath = "src/1_control/vas/modules/vehicle_policy.lua", dest = "/modules/vehicle_policy.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    tca = {
        id = "tca",
        name = "TCA",
        category = "control",
        version = "1.9.1",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_tca.lua",
            target = "/main.lua",
            name = "TCA",
        },
        defaultConfigs = {
            ["/config.json"] = {
                schemaVersion = "1.2.0",
                groupId = "THR_MAIN_L",
                interactionMode = "REDSTONE",
                aircraftIndexN = 1,
                baseChannel = 10000,
                channels = { thrustActuation = 10010 },
                watchdogTimeoutMs = 300,
                nominalActuatorCount = 4,
                aircraftDomainId = "AIRCRAFT_01",
                ports = {
                    modemSide = "top",
                    redstoneSide = "bottom",
                    apiSides = { "left", "right", "front", "back" },
                },
                deadband = 0,
            },
        },
        files = {
            { repoPath = "src/1_control/tca/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/tools/tca_setup.lua", dest = "/tools/tca_setup.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/actuator_adapter.lua", dest = "/modules/actuator_adapter.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/channel_rebind_handler.lua", dest = "/modules/channel_rebind_handler.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/config_manager.lua", dest = "/modules/config_manager.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/discovery_handler.lua", dest = "/modules/discovery_handler.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/group_allocator.lua", dest = "/modules/group_allocator.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/packet_protocol.lua", dest = "/modules/packet_protocol.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/status_reporter.lua", dest = "/modules/status_reporter.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/tca_daemon.lua", dest = "/modules/tca_daemon.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/tui_dashboard.lua", dest = "/modules/tui_dashboard.lua", gdriveId = nil },
            { repoPath = "src/1_control/tca/modules/watchdog_sentinel.lua", dest = "/modules/watchdog_sentinel.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    fcp = {
        id = "fcp",
        name = "FCP",
        category = "guidance",
        version = "1.11.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_fcp.lua",
            target = "/main.lua",
            args = { "--daemon" },
            name = "FCP",
        },
        defaultConfigs = {
            ["/config/fcp_config.json"] = {
                system = {
                    domainId = "AIRCRAFT_01",
                    hardwareUuid = "FCP-04",
                    airframeType = "VECTORED_VTOL",
                    loopFrequencyHz = 20,
                    primaryModemSide = "top",
                    infraModemSide = "back",
                },
                channels = {
                    bootstrapChannel = 50000,
                    baseChannel = 10000,
                    bandwidth = 40,
                    mfdInstrumentChannel = 10003,
                    facilityBeaconChannel = 50003,
                    atcCommChannel = 50001,
                    gpsPingChannel = 60001,
                    gpsServiceChannel = 60002,
                },
            },
        },
        files = {
            { repoPath = "src/2_guidance/fcp/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/fcp_runtime.lua", dest = "/fcp_runtime.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/aerodynamic_controller.lua", dest = "/modules/aerodynamic_controller.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/channel_sentinel.lua", dest = "/modules/channel_sentinel.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/facility_client.lua", dest = "/modules/facility_client.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/flight_fsm.lua", dest = "/modules/flight_fsm.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/guidance_controller.lua", dest = "/modules/guidance_controller.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/nav_engine.lua", dest = "/modules/nav_engine.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/operator_handler.lua", dest = "/modules/operator_handler.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/thruster_profile.lua", dest = "/modules/thruster_profile.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/vectored_vtol_driver.lua", dest = "/modules/vectored_vtol_driver.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/advanced_vtol_driver.lua", dest = "/modules/advanced_vtol_driver.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/drivers/drone_driver.lua", dest = "/modules/drivers/drone_driver.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/drivers/fixed_wing_driver.lua", dest = "/modules/drivers/fixed_wing_driver.lua", gdriveId = nil },
            { repoPath = "src/2_guidance/fcp/modules/drivers/helicopter_driver.lua", dest = "/modules/drivers/helicopter_driver.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    alignment = {
        id = "alignment",
        name = "Alignment",
        category = "development",
        version = "2.5.1",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_alignment.lua",
            target = "/main.lua",
            name = "Alignment",
        },
        defaultConfigs = {
            ["/config.json"] = {
                station = {
                    stationId = "HANGAR_BAY_01",
                    bayId = 1,
                    baseHangarChannel = 101,
                    channels = {
                        calibrationCmd = 101,
                        calibrationTelem = 102,
                        facilityInterlock = 103,
                        tapDirect = 104,
                    },
                },
                safety = {
                    tiltAbortDeg = 12.0,
                    tiltWarnDeg = 8.0,
                    watchdogTimeoutMs = 300,
                    maxDeadband = 6.0,
                    minR2Warning = 0.85,
                },
            },
        },
        files = {
            { repoPath = "src/0_development/alignment/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/align_master.lua", dest = "/modules/align_master.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/controllability_checker.lua", dest = "/modules/controllability_checker.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/discovery_client.lua", dest = "/modules/discovery_client.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/hud_renderer.lua", dest = "/modules/hud_renderer.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/impulse_integrator.lua", dest = "/modules/impulse_integrator.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/multi_pulse_sequencer.lua", dest = "/modules/multi_pulse_sequencer.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/ols_regression_engine.lua", dest = "/modules/ols_regression_engine.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/profile_exporter.lua", dest = "/modules/profile_exporter.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/safety_sentinel.lua", dest = "/modules/safety_sentinel.lua", gdriveId = nil },
            { repoPath = "src/0_development/alignment/modules/settling_guard.lua", dest = "/modules/settling_guard.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    gps_server = {
        id = "gps_server",
        name = "GPS Server",
        category = "infra",
        version = "2.2.0",
        installDir = "/gps",
        startup = {
            enabled = true,
            path = "/startup/00_gps.lua",
            target = "/gps/server.lua",
            name = "GPS Server",
        },
        defaultConfigs = {
            ["/gps_data/nodes.json"] = {
                version = "1.9.5",
                nodes = {},
            },
        },
        files = {
            { repoPath = "src/0_infra/gps/main.lua", dest = "/gps/main.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/server.lua", dest = "/gps/server.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/hal/storage_hal.lua", dest = "/gps/hal/storage_hal.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/config_store.lua", dest = "/gps/modules/config_store.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/monitor_ui.lua", dest = "/gps/modules/monitor_ui.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/radar_math.lua", dest = "/gps/modules/radar_math.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/session_scheduler.lua", dest = "/gps/modules/session_scheduler.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/trilateration.lua", dest = "/gps/modules/trilateration.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    gps_node = {
        id = "gps_node",
        name = "GPS Node",
        category = "infra",
        version = "2.2.0",
        installDir = "/gps",
        startup = {
            enabled = true,
            path = "/startup/00_gps.lua",
            target = "/gps/node.lua",
            name = "GPS Node",
        },
        defaultConfigs = {
            ["/gps_data/node_cfg.json"] = {
                role = "NODE",
                channels = {
                    ping = 60001,
                    service = 60002,
                    nodeIn = 60003,
                    mgmt = 60004,
                },
                networkKey = "GPS_BASE_NET",
                heartbeatSec = 10,
                position = { x = 0, y = 0, z = 0 },
            },
        },
        files = {
            { repoPath = "src/0_infra/gps/main.lua", dest = "/gps/main.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/node.lua", dest = "/gps/node.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/hal/storage_hal.lua", dest = "/gps/hal/storage_hal.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/hal/wizard_cli.lua", dest = "/gps/hal/wizard_cli.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/commissioning.lua", dest = "/gps/modules/commissioning.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/config_store.lua", dest = "/gps/modules/config_store.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    gps_client = {
        id = "gps_client",
        name = "GPS Client",
        category = "infra",
        version = "2.2.0",
        installDir = "/gps",
        startup = {
            enabled = false,
        },
        defaultConfigs = {},
        files = {
            { repoPath = "src/0_infra/gps/hal/gps_client.lua", dest = "/apis/gps_client.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/client_entry.lua", dest = "/gps/client_entry.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/client_core.lua", dest = "/gps/modules/client_core.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    sensors = {
        id = "sensors",
        name = "Sensors API",
        category = "development",
        version = "1.0.0",
        installDir = "/",
        startup = {
            enabled = false,
        },
        defaultConfigs = {},
        files = {
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    gac = {
        id = "gac",
        name = "GAC",
        category = "infra",
        version = "1.3.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_gac.lua",
            target = "/main.lua",
            name = "GAC",
        },
        defaultConfigs = {
            ["/gac/config.json"] = {
                sectorId = "BASE_ALPHA_SECTOR_01",
                sectorName = "Alpha Base Central Vertiport",
                sectorType = "VERTIPORT",
                sectorIndex = 1,
                baseSecChannel = 50201,
                towerAtcChannel = 50001,
                beaconChannel = 50003,
                dispatchChannel = 50004,
                checkinTimeoutSec = 60,
                slotDurationSec = 120,
                surfaceWind = {
                    speed = 2.4,
                    direction = 195.0,
                },
                facilities = {
                    {
                        facilityId = "PAD_01",
                        type = "LANDING_PAD",
                        tacticalChannel = 50211,
                        maxSupportWeight = 40000.0,
                        maxSupportRadius = 12.0,
                        coordinates = { x = 1250.0, y = 65.0, z = -820.0 },
                        status = "FREE",
                        mobility = "STATIC",
                    },
                    {
                        facilityId = "PAD_02",
                        type = "LANDING_PAD",
                        tacticalChannel = 50212,
                        maxSupportWeight = 25000.0,
                        maxSupportRadius = 8.0,
                        coordinates = { x = 1300.0, y = 65.0, z = -800.0 },
                        status = "FREE",
                        mobility = "STATIC",
                    },
                },
            },
        },
        files = {
            { repoPath = "src/0_infra/gac/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/config.lua", dest = "/config.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/config_loader.lua", dest = "/modules/config_loader.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/facility_inventory.lua", dest = "/modules/facility_inventory.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/allocation_engine.lua", dest = "/modules/allocation_engine.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/beacon_broadcaster.lua", dest = "/modules/beacon_broadcaster.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/gac_fsm.lua", dest = "/modules/gac_fsm.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gac/modules/tui_view.lua", dest = "/modules/tui_view.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },

    landing_pad = {
        id = "landing_pad",
        name = "LANDING_PAD",
        category = "infra",
        version = "2.4.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_landing_pad.lua",
            target = "/main.lua",
            name = "LANDING_PAD",
        },
        defaultConfigs = {
            ["/landing_pad/config.json"] = {
                version = "2.4.0",
                facilityId = "PAD_BRAVO_01",
                sectorId = 1,
                padIndex = 1,
                mobility = "DYNAMIC",
                gacChannel = 50201,
                sectorFacilityChannel = 50202,
                sectorGpsReplyChannel = 50206,
                tacticalChannel = 50211,
                mountingYawOffset = 0.0,
                bodyOffset = { forward = 0.0, right = 0.0, up = 0.0 },
                approachHeading = 180.0,
                safeDescentRate = 1.0,
                clearanceZoneRadius = 5.0,
                maxSupportedWeight = 45000.0,
                wirelessModemSide = "top",
                slotDurationSec = 120
            }
        },
        files = {
            { repoPath = "src/0_infra/landing_pad/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/config.lua", dest = "/config.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/config_store.lua", dest = "/modules/config_store.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/offset_transform.lua", dest = "/modules/offset_transform.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/sensor_adapter.lua", dest = "/modules/sensor_adapter.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/gps_client.lua", dest = "/modules/gps_client.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/tactical_streamer.lua", dest = "/modules/tactical_streamer.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/pad_fsm.lua", dest = "/modules/pad_fsm.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/setup_wizard.lua", dest = "/modules/setup_wizard.lua", gdriveId = nil },
            { repoPath = "src/0_infra/landing_pad/modules/tui_view.lua", dest = "/modules/tui_view.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },
    amm = {
        id = "amm",
        name = "AMM",
        category = "planning",
        version = "1.0.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_amm.lua",
            target = "/main.lua",
            name = "AMM",
        },
        description = "Aircraft Mission Manager & Cockpit MFD Terminal (Node 03)",
        roles = { "Node 03", "Mission Terminal", "Planning Layer 3" },
        configTemplate = {
            targetPath = "/config/amm_config.json",
            content = {
                version = "1.0.0",
                domainId = "AIRCRAFT_01",
                baseChannel = 10000,
                defaultAlt = 150.0,
                defaultSpeed = 18.0,
                arrivalRadius = 15.0,
            }
        },
        files = {
            { repoPath = "src/3_planning/amm/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/config/amm_config.json", dest = "/config/amm_config.json", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/waypoint_queue.lua", dest = "/modules/waypoint_queue.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/mission_engine.lua", dest = "/modules/mission_engine.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/condition_evaluator.lua", dest = "/modules/condition_evaluator.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/hook_runner.lua", dest = "/modules/hook_runner.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/c2_arbiter.lua", dest = "/modules/c2_arbiter.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/input_handler.lua", dest = "/modules/input_handler.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = nil },
            { repoPath = "src/3_planning/amm/modules/mission_controller.lua", dest = "/modules/mission_controller.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },
    gcs = {
        id = "gcs",
        name = "GCS",
        category = "infra",
        version = "1.0.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_gcs.lua",
            target = "/main.lua",
            name = "GCS",
        },
        description = "Ground Control Station & RF Channel Manager (Node 08)",
        roles = { "Node 08", "Ground Station", "Infra Layer 0" },
        configTemplate = {
            targetPath = "/config/gcs_config.json",
            content = {
                system = {
                    id = "GCS_01",
                    name = "Ground Control Station",
                    domainId = "GCS_01",
                    loopFrequencyHz = 20,
                    uiRefreshRateHz = 5,
                    modemSide = "top"
                },
                channels = {
                    bootstrapChannel = 50000,
                    bandwidth = 40,
                    baseChannelMin = 10000,
                    baseChannelMax = 49960,
                    maxCraftBlocks = 1000
                },
                ui = {
                    screenWidth = 51,
                    screenHeight = 19,
                    telemetryTimeoutSec = 5.0
                }
            }
        },
        files = {
            { repoPath = "src/0_infra/gcs/main.lua", dest = "/main.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/config/gcs_config.json", dest = "/config/gcs_config.json", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/config/channel_registry.json", dest = "/config/channel_registry.json", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/modules/channel_manager.lua", dest = "/modules/channel_manager.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/modules/c2_commander.lua", dest = "/modules/c2_commander.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/modules/fleet_tracker.lua", dest = "/modules/fleet_tracker.lua", gdriveId = nil },
            { repoPath = "src/0_infra/gcs/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = nil },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = nil },
        },
    },
}

function manifest.getModule(id)
    return manifest.MODULES[id]
end

function manifest.listModules()
    local list = {}
    for i, id in ipairs(manifest.MODULE_ORDER) do
        list[i] = manifest.MODULES[id]
    end
    return list
end

function manifest.getCategory(categoryId)
    return manifest.CATEGORIES[categoryId]
end

function manifest.listModulesByCategory(categoryId)
    local list = {}
    if type(categoryId) ~= "string" or categoryId == "" then
        return list
    end
    for _, id in ipairs(manifest.MODULE_ORDER) do
        local mod = manifest.MODULES[id]
        if mod and mod.category == categoryId then
            list[#list + 1] = mod
        end
    end
    return list
end

function manifest.listCategories(includeEmpty)
    local list = {}
    for _, catId in ipairs(manifest.CATEGORY_ORDER) do
        local cat = manifest.CATEGORIES[catId]
        if cat then
            local mods = manifest.listModulesByCategory(catId)
            if includeEmpty or #mods > 0 then
                local entry = {}
                for k, v in pairs(cat) do
                    entry[k] = v
                end
                entry.modules = mods
                entry.moduleCount = #mods
                list[#list + 1] = entry
            end
        end
    end
    return list
end

function manifest.resolveUrl(sourceType, fileEntry, gdriveOverrides)
    if not fileEntry or not fileEntry.repoPath then
        return nil, "INVALID_FILE_ENTRY"
    end

    if sourceType == "github" or sourceType == manifest.SOURCES.GITHUB then
        return manifest.BASE_URLS.github .. fileEntry.repoPath, nil
    elseif sourceType == "gdrive" or sourceType == manifest.SOURCES.GDRIVE then
        local fileId = (gdriveOverrides and gdriveOverrides[fileEntry.repoPath]) or fileEntry.gdriveId
        if not fileId or fileId == "" then
            return nil, "GDRIVE_ID_UNCONFIGURED"
        end
        return manifest.BASE_URLS.gdrive .. fileId .. "&export=download&confirm=t", nil
    else
        return nil, "UNKNOWN_SOURCE_TYPE: " .. tostring(sourceType)
    end
end


manifest.AIRFRAME_PRESETS = {
    ADVANCED_VTOL = {
        airframeType = "ADVANCED_VTOL",
        name = "Advanced Vectored VTOL",
        description = "High-agility 2D gimbal thruster VTOL with pseudo-inverse allocation",
        requiredModules = { "vas", "tca", "fcp", "alignment" },
        configTemplate = {
            system = {
                domainId = "AIRCRAFT_01",
                airframeType = "ADVANCED_VTOL",
                loopFrequencyHz = 20,
                primaryModemSide = "top",
                infraModemSide = "back",
            },
            channels = {
                bootstrapChannel = 50000,
                baseChannel = 10000,
                bandwidth = 40,
                mfdInstrumentChannel = 10003,
                facilityBeaconChannel = 50003,
                atcCommChannel = 50001,
                gpsPingChannel = 60001,
                gpsServiceChannel = 60002,
            },
        },
    },
    VECTORED_VTOL = {
        airframeType = "VECTORED_VTOL",
        name = "Standard Vectored VTOL",
        description = "6-DoF multi-directional fixed thruster VTOL",
        requiredModules = { "vas", "tca", "fcp" },
        configTemplate = {
            system = {
                domainId = "AIRCRAFT_01",
                airframeType = "VECTORED_VTOL",
                loopFrequencyHz = 20,
                primaryModemSide = "top",
                infraModemSide = "back",
            },
            channels = {
                bootstrapChannel = 50000,
                baseChannel = 10000,
                bandwidth = 40,
                mfdInstrumentChannel = 10003,
                facilityBeaconChannel = 50003,
                atcCommChannel = 50001,
                gpsPingChannel = 60001,
                gpsServiceChannel = 60002,
            },
        },
    },
}

function manifest.getAirframePreset(airframeType)
    return manifest.AIRFRAME_PRESETS[airframeType]
end

function manifest.listAirframePresets()
    local list = {}
    for _, preset in pairs(manifest.AIRFRAME_PRESETS) do
        table.insert(list, preset)
    end
    table.sort(list, function(a, b) return tostring(a.airframeType) < tostring(b.airframeType) end)
    return list
end

return manifest
