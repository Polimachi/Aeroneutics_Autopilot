-- src/0_development/installer/modules/manifest.lua
-- Declarative module registry and URL resolver for Create_Aeroneutics

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

manifest.SHARED_LIBS = {
    avionics_sensors = {
        repoPath = "src/0_development/sensors/avionics_sensors.lua",
        dest = "/lib/avionics_sensors.lua",
        gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL",
    },
}

manifest.MODULE_ORDER = {
    "vas",
    "tca",
    "fcp",
    "alignment",
    "fdr",
    "ota",
    "gps_server",
    "gps_node",
    "gps_client",
    "sensors",
    "gac",
    "landing_pad",
    "amm",
    "gcs",
    "runway",
    "pocket_pda",
}

manifest.MODULES = {
    vas = {
        id = "vas",
        name = "VAS",
        category = "control",
        version = "1.19.0",
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
                channels = {
                    guidance = 1,
                    telemetry = 2,
                    mfd = 3,
                    trajectory = 4,
                    clientReply = 5,
                    calibration = 8,
                    emergency = 9,
                    actuation = 10,
                    asaActuation = 11,
                },
                timeouts = {
                    fcpCommandTimeoutMs = 1500,
                    sensorLossDebounceTicks = 1,
                    calibrationTimeoutSec = 120,
                },
                stallGuard = {
                    flapVfeLimit = 15.0,
                },
                debug = false,
            },
        },
        files = {
            { repoPath = "src/1_control/vas/main.lua", dest = "/main.lua", gdriveId = "1DbJlRF0bvr0L8A71HD4Q0LY-qOp_2efD" },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_tca.lua", dest = "/modules/actuator_adapter_tca.lua", gdriveId = "1V6DU2fbjYVLNWnV-iunMSrL3JI1tsjoK" },
            { repoPath = "src/1_control/vas/modules/actuator_adapter_asa.lua", dest = "/modules/actuator_adapter_asa.lua", gdriveId = "1Est8Gm_IIv3-iehK-QwK9D8wOJewJF77" },
            { repoPath = "src/1_control/vas/modules/core_daemon.lua", dest = "/modules/core_daemon.lua", gdriveId = "1RW9YNZI5w_FhA58aAwbUY2lQF7W0cAuE" },
            { repoPath = "src/1_control/vas/modules/flight_dynamics_core.lua", dest = "/modules/flight_dynamics_core.lua", gdriveId = "1MQnRr1It0iMvUAebEgTAHzg9arFIVVVH" },
            { repoPath = "src/1_control/vas/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = "1dA_g5anRkvP-wuRNN7wHrXw2IAGzyajH" },
            { repoPath = "src/1_control/vas/modules/quat.lua", dest = "/modules/quat.lua", gdriveId = "1TZSyjtkzrtGEfPC1zVj1SdW-vhBlGYtx" },
            { repoPath = "src/1_control/vas/modules/sensor_pipeline.lua", dest = "/modules/sensor_pipeline.lua", gdriveId = "1J95PdSrgCSv2Hrh6Pzxw1_xf2nYhvDUP" },
            { repoPath = "src/1_control/vas/modules/state_machine.lua", dest = "/modules/state_machine.lua", gdriveId = "1xiQx0vuAxOS2K1oMMp6sEJ4F2gYh_WLK" },
            { repoPath = "src/1_control/vas/modules/telemetry_feeder.lua", dest = "/modules/telemetry_feeder.lua", gdriveId = "1FfcWK1tEuU66q8X1vs_jBqTTtfGq8T8U" },
            { repoPath = "src/1_control/vas/modules/thrust_mixer.lua", dest = "/modules/thrust_mixer.lua", gdriveId = "1Qfp_FMztHqJiwsX1u80B0q-E3DrVsqLG" },
            { repoPath = "src/1_control/vas/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = "1-FinhAfvHxQgEdznS33znTzZQWLAdIsu" },
            { repoPath = "src/1_control/vas/modules/vec3.lua", dest = "/modules/vec3.lua", gdriveId = "1cvHN07z2At4OcE9bctLOHiGRQdM45wHp" },
            { repoPath = "src/1_control/vas/modules/vehicle_policy.lua", dest = "/modules/vehicle_policy.lua", gdriveId = "13RQvS-hsaMbaeH9w8WMiBlDzMCQOo7OR" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
            { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = "1av9t1QqFdiSUBSlkQ_RMMEmqriY44uqX" },
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
            { repoPath = "src/1_control/tca/main.lua", dest = "/main.lua", gdriveId = "1cXXsKHmzHoV6A8AQf89OxVdwNoFDJYAP" },
            { repoPath = "src/1_control/tca/tools/tca_setup.lua", dest = "/tools/tca_setup.lua", gdriveId = "1MUhc4csOLouqUclLgtJpwEk73C9n_6hq" },
            { repoPath = "src/1_control/tca/modules/actuator_adapter.lua", dest = "/modules/actuator_adapter.lua", gdriveId = "1rOkeE4ZQChNfVWsJKCEHXCo3M6T1TmmT" },
            { repoPath = "src/1_control/tca/modules/channel_rebind_handler.lua", dest = "/modules/channel_rebind_handler.lua", gdriveId = "1K_ZRdIKVZB1hneB0x-qzPSRErh83n-f5" },
            { repoPath = "src/1_control/tca/modules/config_manager.lua", dest = "/modules/config_manager.lua", gdriveId = "1mqn6ur0pLkYAkuMN3-L0n7L93OZErU5y" },
            { repoPath = "src/1_control/tca/modules/discovery_handler.lua", dest = "/modules/discovery_handler.lua", gdriveId = "16vnT_DxoNZ0nO1K45f-f1MUn2gZ7K1x9" },
            { repoPath = "src/1_control/tca/modules/group_allocator.lua", dest = "/modules/group_allocator.lua", gdriveId = "16DLrkpoMFyuMKmFjbmZ1Xu2cZBCitSUE" },
            { repoPath = "src/1_control/tca/modules/packet_protocol.lua", dest = "/modules/packet_protocol.lua", gdriveId = "14W3ldI89hZudL0-zay8BFTwWQ6LeLY-K" },
            { repoPath = "src/1_control/tca/modules/status_reporter.lua", dest = "/modules/status_reporter.lua", gdriveId = "1hompaYxGMXtvp1M8zYawFImvvxem5jeC" },
            { repoPath = "src/1_control/tca/modules/tca_daemon.lua", dest = "/modules/tca_daemon.lua", gdriveId = "12IuZWXfk_zUbu9fvQBJR_9RApO00nYOI" },
            { repoPath = "src/1_control/tca/modules/tui_dashboard.lua", dest = "/modules/tui_dashboard.lua", gdriveId = "1RQn1Y6UYoB_nJJkYS2QjHVABeFuaPO3h" },
            { repoPath = "src/1_control/tca/modules/watchdog_sentinel.lua", dest = "/modules/watchdog_sentinel.lua", gdriveId = "1YH0QAz8jKbPiLamNxx-XI9OJhQ20Pvdx" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
            { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = "1av9t1QqFdiSUBSlkQ_RMMEmqriY44uqX" },
        },
    },

    fcp = {
        id = "fcp",
        name = "FCP",
        category = "guidance",
        version = "2.0.0",
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
                version = "2.0.0",
                system = {
                    domainId = "AIRCRAFT_01",
                    hardwareUuid = "FCP-04",
                    airframeType = "VECTORED_VTOL",
                    loopFrequencyHz = 20,
                    primaryModemSide = "top",
                    debug = false,
                },
                channels = {
                    baseChannel = 10000,
                    bandwidth = 40,
                    trajectoryOffset = 4,
                    telemetryOffset = 2,
                    guidanceOffset = 1,
                    emergencyOffset = 9,
                },
                propagation = {
                    maxDtSec = 0.1,
                    posMergeMaxStepM = 2.0,
                    navStaleTimeoutMs = 500,
                },
                se3 = {
                    gravityMps2 = 11.0,
                    kp = { x = 1.6, y = 2.2, z = 1.6 },
                    kd = { x = 1.4, y = 1.8, z = 1.4 },
                    ki = { x = 0.08, y = 0.12, z = 0.08 },
                    drag = { x = 0.02, y = 0.0, z = 0.02 },
                    integralLimit = { x = 3.0, y = 4.0, z = 3.0 },
                    maxThrustAccel = 22.0,
                    minThrustAccel = 2.0,
                    hoverThrustRatio = 0.635,
                    tiltAssistedMaxPitchDeg = 10.0,
                    tiltAssistedThresholdSpeedMps = 15.0,
                    tiltSlewRateDegPerSec = 15.0,
                    gimbalSlewRate = 2.0,
                    multirotorMaxTiltDeg = 25.0,
                    wingedVtolVLowMps = 8.0,
                    wingedVtolVHighMps = 18.0,
                    fixedWingRotationSpeedMps = 12.0,
                    fixedWingStallSpeedMps = 10.0,
                },
                safety = {
                    ammSetpointTimeoutMs = 500,
                    ammTimeoutHoldToEmgMs = 10000,
                    rebindAckTimeoutMs = 500,
                    bumplessRampSec = 2.0,
                    emergencyDescentRateMps = -2.0,
                },
            },
        },
        files = {
            { repoPath = "src/2_guidance/fcp/main.lua", dest = "/main.lua", gdriveId = "1sGLn5sHzvPIrHrJHG-zNvJ9sVwkrkL5U" },
            { repoPath = "src/2_guidance/fcp/config/fcp_config.json", dest = "/config/fcp_config.json", gdriveId = "1HQpjGiZAfXbn4UqNriky_xYGwoF_4wyo" },
            { repoPath = "src/2_guidance/fcp/modules/flight_fsm.lua", dest = "/modules/flight_fsm.lua", gdriveId = "1g8SmGdT8dY9Fm62fvg_adaJ9cWgxl4Ib" },
            { repoPath = "src/2_guidance/fcp/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = "1poah4I0VyHpkO5zyr-OD6wGCNQAjRY3D" },
            { repoPath = "src/2_guidance/fcp/modules/outer_loop_controller.lua", dest = "/modules/outer_loop_controller.lua", gdriveId = "1pu1EVQwxD22p5MD8yaSz3kpR9t5nKEXv" },
            { repoPath = "src/2_guidance/fcp/modules/state_propagator.lua", dest = "/modules/state_propagator.lua", gdriveId = "1VyPaMxjh47ZF15pJMev3OXB72RnJtGy1" },
            { repoPath = "src/2_guidance/fcp/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = "1UTxx4xW_lJxKutkGHMQbIWcYtDw6uCXt" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
            { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = "1av9t1QqFdiSUBSlkQ_RMMEmqriY44uqX" },
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
            { repoPath = "src/0_development/alignment/main.lua", dest = "/main.lua", gdriveId = "1ufrk8V7WW1poMLnr8Yg_Xi-vGY8aX7_o" },
            { repoPath = "src/0_development/alignment/modules/align_master.lua", dest = "/modules/align_master.lua", gdriveId = "1J4a3Lq6GTSRBa3JMSJ57j5d556qO-CW1" },
            { repoPath = "src/0_development/alignment/modules/controllability_checker.lua", dest = "/modules/controllability_checker.lua", gdriveId = "121bVco07Ah-NquPmO7MP6ZuRy_IQyOjT" },
            { repoPath = "src/0_development/alignment/modules/discovery_client.lua", dest = "/modules/discovery_client.lua", gdriveId = "14SQnGMQSDQ-RPmRAKvw29cyf3frR_Bbk" },
            { repoPath = "src/0_development/alignment/modules/hud_renderer.lua", dest = "/modules/hud_renderer.lua", gdriveId = "1R-Smk5_GPLU9vwmZh_6tQYveY7Qibz0V" },
            { repoPath = "src/0_development/alignment/modules/impulse_integrator.lua", dest = "/modules/impulse_integrator.lua", gdriveId = "1QW0RWsyrwbpNt-YkBwK3zznRJOH9X_1h" },
            { repoPath = "src/0_development/alignment/modules/multi_pulse_sequencer.lua", dest = "/modules/multi_pulse_sequencer.lua", gdriveId = "1bMARylGydl4bOsbADjVJTf1eVhWjx6MG" },
            { repoPath = "src/0_development/alignment/modules/ols_regression_engine.lua", dest = "/modules/ols_regression_engine.lua", gdriveId = "1SkWChaFEGRA3FTI1haMvIAZ5YqDerYH5" },
            { repoPath = "src/0_development/alignment/modules/profile_exporter.lua", dest = "/modules/profile_exporter.lua", gdriveId = "1pyB9Q-E9cDc-vry6wKtsR10NyMAm9c58" },
            { repoPath = "src/0_development/alignment/modules/safety_sentinel.lua", dest = "/modules/safety_sentinel.lua", gdriveId = "1T96dvV_Z6D0jtSbir-BpNs6IvdRH3vQC" },
            { repoPath = "src/0_development/alignment/modules/settling_guard.lua", dest = "/modules/settling_guard.lua", gdriveId = "1S7F4tP40ldoiLXu145sL4fH-5KmRRFO9" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
            { repoPath = "src/0_infra/gps/main.lua", dest = "/gps/main.lua", gdriveId = "1qwdkXwaHc95KP1HpAwqnvW8tXVuf82JO" },
            { repoPath = "src/0_infra/gps/server.lua", dest = "/gps/server.lua", gdriveId = "1g9Pjpv-G2N0qxARsUcB-6zlDgs558icq" },
            { repoPath = "src/0_infra/gps/hal/storage_hal.lua", dest = "/gps/hal/storage_hal.lua", gdriveId = "1jDf94JrI1KLE48PRmx8M-sHL8co7i2j5" },
            { repoPath = "src/0_infra/gps/modules/config_store.lua", dest = "/gps/modules/config_store.lua", gdriveId = "17J_XpBVtPBu6PGGL3JSaNUdAu8TJASNf" },
            { repoPath = "src/0_infra/gps/modules/monitor_ui.lua", dest = "/gps/modules/monitor_ui.lua", gdriveId = "1uHL-jWAZ4gsy9S23NbQwrQEXY-DEUP9F" },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = "1iz4g_nou1nRu9ipWU3XxOxrfrX2rUyP3" },
            { repoPath = "src/0_infra/gps/modules/radar_math.lua", dest = "/gps/modules/radar_math.lua", gdriveId = "1ftqvegHnxjQG9nSl2HBrvYfwxi2MX0yy" },
            { repoPath = "src/0_infra/gps/modules/session_scheduler.lua", dest = "/gps/modules/session_scheduler.lua", gdriveId = "1o10mp5w6HjHOW8-1UWPb33DEZ9pN7fTk" },
            { repoPath = "src/0_infra/gps/modules/trilateration.lua", dest = "/gps/modules/trilateration.lua", gdriveId = "1FbXaif4rlJEjdOeZGQsvVRMWGf4-rDiL" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
            { repoPath = "src/0_infra/gps/main.lua", dest = "/gps/main.lua", gdriveId = "1qwdkXwaHc95KP1HpAwqnvW8tXVuf82JO" },
            { repoPath = "src/0_infra/gps/node.lua", dest = "/gps/node.lua", gdriveId = "1qjNi-QPO4rHPBBQV6x2Bp7DOJ7Cars0p" },
            { repoPath = "src/0_infra/gps/hal/storage_hal.lua", dest = "/gps/hal/storage_hal.lua", gdriveId = "1jDf94JrI1KLE48PRmx8M-sHL8co7i2j5" },
            { repoPath = "src/0_infra/gps/hal/wizard_cli.lua", dest = "/gps/hal/wizard_cli.lua", gdriveId = "1CUecU4hMf9hGnRdNhGej9VOMcqF93quH" },
            { repoPath = "src/0_infra/gps/modules/commissioning.lua", dest = "/gps/modules/commissioning.lua", gdriveId = "1Q2QafEd1SqtzI_NBq8g8gvG3P0MLmgWi" },
            { repoPath = "src/0_infra/gps/modules/config_store.lua", dest = "/gps/modules/config_store.lua", gdriveId = "17J_XpBVtPBu6PGGL3JSaNUdAu8TJASNf" },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = "1iz4g_nou1nRu9ipWU3XxOxrfrX2rUyP3" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
            { repoPath = "src/0_infra/gps/hal/gps_client.lua", dest = "/apis/gps_client.lua", gdriveId = "1R9-tDxEOG9BjR1BRolWVckcWcO4SESgZ" },
            { repoPath = "src/0_infra/gps/client_entry.lua", dest = "/gps/client_entry.lua", gdriveId = "1Fb0HXfXJ8mefarzoK67wX6LLbq0inZHc" },
            { repoPath = "src/0_infra/gps/modules/client_core.lua", dest = "/gps/modules/client_core.lua", gdriveId = "1bTaiJG8L27tUftjoWuS9VxAvSE5fcByF" },
            { repoPath = "src/0_infra/gps/modules/protocol.lua", dest = "/gps/modules/protocol.lua", gdriveId = "1iz4g_nou1nRu9ipWU3XxOxrfrX2rUyP3" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
                position = { x = 1275.0, y = 65.0, z = -810.0 },
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
            { repoPath = "src/0_infra/gac/main.lua", dest = "/main.lua", gdriveId = "1yyB_X2A0Dq-EOHZZv55zv3wk9teL17Ng" },
            { repoPath = "src/0_infra/gac/config.lua", dest = "/config.lua", gdriveId = "1SSoOakqbSdi1OWamzZLp-mQj2d5ZUAAN" },
            { repoPath = "src/0_infra/gac/modules/config_loader.lua", dest = "/modules/config_loader.lua", gdriveId = "1w-ZKzKjBvFsLtamro6XlKSyZGXbp27Ll" },
            { repoPath = "src/0_infra/gac/modules/facility_inventory.lua", dest = "/modules/facility_inventory.lua", gdriveId = "1aqekpEUA_Zi_9caoMZKiEq9Y7TPo77d4" },
            { repoPath = "src/0_infra/gac/modules/allocation_engine.lua", dest = "/modules/allocation_engine.lua", gdriveId = "1863Xjn_fYC6tsOpDWZZZfgA3swaJo6tu" },
            { repoPath = "src/0_infra/gac/modules/beacon_broadcaster.lua", dest = "/modules/beacon_broadcaster.lua", gdriveId = "1MC6QVJRv2SKX5WGbNpgxKEdT0mQ1c17o" },
            { repoPath = "src/0_infra/gac/modules/gac_fsm.lua", dest = "/modules/gac_fsm.lua", gdriveId = "1lroLZ56ckrI-OUThbFk9iP-ymb0BqckE" },
            { repoPath = "src/0_infra/gac/modules/tui_view.lua", dest = "/modules/tui_view.lua", gdriveId = "15FIrnusK_TxOTerRcUD_TS21Ug2wGOw2" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
            { repoPath = "src/0_infra/landing_pad/main.lua", dest = "/main.lua", gdriveId = "1cz2Tar0_EN1GP7bOrRB446Od_wpsqHDp" },
            { repoPath = "src/0_infra/landing_pad/config.lua", dest = "/config.lua", gdriveId = "1mMINj_22uuOwJJ3VHViWGkzrXjlgW2wH" },
            { repoPath = "src/0_infra/landing_pad/modules/config_store.lua", dest = "/modules/config_store.lua", gdriveId = "13ScLe2gKeI7tqSBxJVcAqrkEmh_Rxy65" },
            { repoPath = "src/0_infra/landing_pad/modules/offset_transform.lua", dest = "/modules/offset_transform.lua", gdriveId = "1wqWa45oTs3iNl1172dZ8vdiHn4Beo6Gb" },
            { repoPath = "src/0_infra/landing_pad/modules/sensor_adapter.lua", dest = "/modules/sensor_adapter.lua", gdriveId = "1Y1O2aaymF5Z5mLx4RJvsrf7ZpAx2QVot" },
            { repoPath = "src/0_infra/landing_pad/modules/gps_client.lua", dest = "/modules/gps_client.lua", gdriveId = "1CNlXqIz5QuEPGeiPoG6bQCvHZzD_CLYY" },
            { repoPath = "src/0_infra/landing_pad/modules/tactical_streamer.lua", dest = "/modules/tactical_streamer.lua", gdriveId = "1ZPWqV3G5PCdrVn3NUSEtJLFssaKBJ57K" },
            { repoPath = "src/0_infra/landing_pad/modules/pad_fsm.lua", dest = "/modules/pad_fsm.lua", gdriveId = "1DGpTXBDlwbHVFKwLD2BSatkfDC9-Sno1" },
            { repoPath = "src/0_infra/landing_pad/modules/setup_wizard.lua", dest = "/modules/setup_wizard.lua", gdriveId = "13UkSI5mhuxXko_ehDYbiGjEPDKjq6lwN" },
            { repoPath = "src/0_infra/landing_pad/modules/tui_view.lua", dest = "/modules/tui_view.lua", gdriveId = "1XH5J3riloKmW-x-SmuFKyQDFt1ZT258M" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
        },
    },
    runway = {
        id = "runway",
        name = "RUNWAY",
        category = "infra",
        version = "1.12.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_runway.lua",
            target = "/main.lua",
            name = "RUNWAY",
        },
        defaultConfigs = {
            ["/runway/config.json"] = {
                version = "1.12.0",
                facilityId = "RWY_ALPHA_09L",
                sectorId = 1,
                runwayIndex = 1,
                mobility = "DYNAMIC",
                gacChannel = 50201,
                sectorFacilityChannel = 50202,
                sectorGpsReplyChannel = 50206,
                tacticalChannel = 50211,
                mountingYawOffset = 0.0,
                position = { x = 0.0, y = 64.0, z = 0.0 },
                touchdownOffset = { forward = 0.0, right = 0.0, up = 0.0 },
                endOffset = { forward = 200.0, right = 0.0, up = 0.0 },
                approachHeading = 90.0,
                approachDirection = "FRONT",
                glideSlopeAngle = 3.0,
                touchdownZoneLength = 80.0,
                wirelessModemSide = "top",
                slotDurationSec = 120
            }
        },
        files = {
            { repoPath = "src/0_infra/runway/main.lua", dest = "/main.lua", gdriveId = "1IG8WbyE1FXP09BcqhuoJDCMULJC88Bvm" },
            { repoPath = "src/0_infra/runway/modules/config_store.lua", dest = "/modules/config_store.lua", gdriveId = "1uAWaIeqNCPgoiZ6S5ZsdnhdFoozFr6nE" },
            { repoPath = "src/0_infra/runway/modules/offset_transform.lua", dest = "/modules/offset_transform.lua", gdriveId = "15B5huPd0AUYVu4XeWs00X_vMy82Vka_n" },
            { repoPath = "src/0_infra/runway/modules/sensor_adapter.lua", dest = "/modules/sensor_adapter.lua", gdriveId = "1RtFah4PscIvPg8mQDcSEjSW_e-Fxfsal" },
            { repoPath = "src/0_infra/runway/modules/lighting_controller.lua", dest = "/modules/lighting_controller.lua", gdriveId = "1BXJo0dgAqlTXpvJHxxTqdHG6SwNJCh4T" },
            { repoPath = "src/0_infra/runway/modules/gps_client.lua", dest = "/modules/gps_client.lua", gdriveId = "1rWHnKtqVe_gJZgOYnTw2_aIRil_WW_fM" },
            { repoPath = "src/0_infra/runway/modules/tactical_streamer.lua", dest = "/modules/tactical_streamer.lua", gdriveId = "13NFvG_YbERQ_2YZbQ_F5NTM0d5eHJDwh" },
            { repoPath = "src/0_infra/runway/modules/runway_fsm.lua", dest = "/modules/runway_fsm.lua", gdriveId = "1YAI62mOg2BGbjPFWx02tIt27sHYj-bki" },
            { repoPath = "src/0_infra/runway/modules/setup_wizard.lua", dest = "/modules/setup_wizard.lua", gdriveId = "1gQHUrkzVh85lY809kpwhrvf5f_J9ryz_" },
            { repoPath = "src/0_infra/runway/modules/tui_view.lua", dest = "/modules/tui_view.lua", gdriveId = "12xZPuwEwk71H5XYC3WhMEb4LHk0qLQ0R" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
        },
    },
    amm = {
        id = "amm",
        name = "AMM",
        category = "planning",
        version = "2.0.0",
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
                version = "2.0.0",
                domainId = "AIRCRAFT_01",
                baseChannel = 10000,
                defaultAlt = 150.0,
                defaultSpeed = 18.0,
                arrivalRadius = 15.0,
                safety = {
                    acroRecoveryHoldMs = 300,
                    channelProbeWaitMs = 200,
                    probeJitterMaxMs = 100,
                    probeRetryCount = 2,
                    maxReassignAttempts = 3,
                    gcsBootstrapTimeoutMs = 2000,
                    intrusionAlertWindowMs = 30000,
                },
            }
        },
        files = {
            { repoPath = "src/3_planning/amm/main.lua", dest = "/main.lua", gdriveId = "1bW8QGRKS3PZVNoLOhK1ddb-txD_lu7tK" },
            { repoPath = "src/3_planning/amm/config/amm_config.json", dest = "/config/amm_config.json", gdriveId = "1zqS8CSCfewvwEvBy-5lgIBk6avAp1-S6" },
            { repoPath = "src/3_planning/amm/modules/action_registry.lua", dest = "/modules/action_registry.lua", gdriveId = "1-GgFtHgDkzJleh6AFhshvGnnQm-y-3mG" },
            { repoPath = "src/3_planning/amm/modules/chattering_guard.lua", dest = "/modules/chattering_guard.lua", gdriveId = "1QHjJ565NwPagq-2NpWvG6T-oTyu1DYiW" },
            { repoPath = "src/3_planning/amm/modules/channel_sentinel.lua", dest = "/modules/channel_sentinel.lua", gdriveId = "1y1pOG4c0trA4iV-y_OViDhB-SMemaCLM" },
            { repoPath = "src/3_planning/amm/modules/facility_client.lua", dest = "/modules/facility_client.lua", gdriveId = "1u2E8pHSNSRAJ3H6UPBTYKagMYkK3XxHm" },
            { repoPath = "src/3_planning/amm/modules/nav_engine.lua", dest = "/modules/nav_engine.lua", gdriveId = "1rN4aWIItR_za9K4Xs-YwKzZW-baI8Vn0" },
            { repoPath = "src/3_planning/amm/modules/waypoint_queue.lua", dest = "/modules/waypoint_queue.lua", gdriveId = "15d5_A8GuLrtWiMPwhKGt3XLBiM2su8mZ" },
            { repoPath = "src/3_planning/amm/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = "1UHA3CwFWuAbMTYOdlwbfHrUhHJmEfAkM" },
            { repoPath = "src/3_planning/amm/modules/mission_engine.lua", dest = "/modules/mission_engine.lua", gdriveId = "1s8NbAGcXLwh3T9Ht_v-CfhlmgnGugVuo" },
            { repoPath = "src/3_planning/amm/modules/condition_evaluator.lua", dest = "/modules/condition_evaluator.lua", gdriveId = "11FKssYezhRL_hdZtrwYQ2frfZRzSbfVf" },
            { repoPath = "src/3_planning/amm/modules/hook_runner.lua", dest = "/modules/hook_runner.lua", gdriveId = "1OI1RugCxDgeOGmML9o7K5ryKmMTO6aAg" },
            { repoPath = "src/3_planning/amm/modules/c2_arbiter.lua", dest = "/modules/c2_arbiter.lua", gdriveId = "1kT2slrUNo97veikRZHE_d3RN2Lsk3Hqr" },
            { repoPath = "src/3_planning/amm/modules/input_handler.lua", dest = "/modules/input_handler.lua", gdriveId = "1hGs88n0M5kzqtzEO7a21BUtq2aarjmTd" },
            { repoPath = "src/3_planning/amm/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = "1sKY6vyh0SGO8PkY-ZBL8GoSnoRUCbQn8" },
            { repoPath = "src/3_planning/amm/modules/trajectory_generator.lua", dest = "/modules/trajectory_generator.lua", gdriveId = "1Lxljo38VHV927_BATPBNTWcfo7P1ZGMG" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
            { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = "1av9t1QqFdiSUBSlkQ_RMMEmqriY44uqX" },
        },
    },
    gcs = {
        id = "gcs",
        name = "GCS",
        category = "infra",
        version = "1.2.0",
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
                    facilityBeaconChannel = 50003,
                    missionAckChannel = 50004,
                    gpsHeartbeatChannel = 60003,
                    bandwidth = 40,
                    baseChannelMin = 10000,
                    baseChannelMax = 49960,
                    maxCraftBlocks = 1000
                },
                liveBridge = {
                    enabled = false,
                    url = "ws://127.0.0.1:8765",
                    telemetrySyncHz = 5
                },
                ui = {
                    screenWidth = 51,
                    screenHeight = 19,
                    telemetryTimeoutSec = 5.0
                }
            }
        },
        files = {
            { repoPath = "src/0_infra/gcs/main.lua", dest = "/main.lua", gdriveId = "1mv0BYqmSdziuZFe77zxaW-F1NxXlEUb-" },
            { repoPath = "src/0_infra/gcs/config/gcs_config.json", dest = "/config/gcs_config.json", gdriveId = "1jJ5aCq2uUh52x519ZAH9VpVqPGUQokk0" },
            { repoPath = "src/0_infra/gcs/config/channel_registry.json", dest = "/config/channel_registry.json", gdriveId = "1kP80bOVaq1HndP__9UjlQKrEUH7C502b" },
            { repoPath = "src/0_infra/gcs/modules/channel_manager.lua", dest = "/modules/channel_manager.lua", gdriveId = "14B8LSFjr8P2I5rfEW6RbK38Z3Ce-55Vc" },
            { repoPath = "src/0_infra/gcs/modules/network_manager.lua", dest = "/modules/network_manager.lua", gdriveId = "1Pb-62eLGHLl9oMTqZxAUoouyJEzsgaaA" },
            { repoPath = "src/0_infra/gcs/modules/c2_commander.lua", dest = "/modules/c2_commander.lua", gdriveId = "13pWwtJUnLfJysSiiRWB64B_Sy3NGSRw8" },
            { repoPath = "src/0_infra/gcs/modules/fleet_tracker.lua", dest = "/modules/fleet_tracker.lua", gdriveId = "1u2moRTCEinZxvDLblPQ9oNKAcl4uV1JA" },
            { repoPath = "src/0_infra/gcs/modules/live_bridge_client.lua", dest = "/modules/live_bridge_client.lua", gdriveId = "1GUUZRXKcGWy-UZTJLANoekeysBSeVw6T" },
            { repoPath = "src/0_infra/gcs/modules/ui_renderer.lua", dest = "/modules/ui_renderer.lua", gdriveId = "1qqu-ZTmQm9JmIO7g7hjo3mOLyidjVArB" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
        },
    },
    fdr = {
        id = "fdr",
        name = "FDR",
        category = "development",
        version = "0.3.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_fdr.lua",
            target = "/main.lua",
            name = "FDR",
        },
        description = "Ground In-Flight Aligner & Multi-Disk VFS Logger (Receive-Only)",
        roles = { "Ground Aligner", "Blackbox", "Dev Layer 0" },
        files = {
            { repoPath = "src/0_development/fdr/main.lua", dest = "/main.lua", gdriveId = "1v94Tzl5p043E8v-LPFBPesX6ByN6fU51" },
            { repoPath = "src/0_development/fdr/config/fdr_config.json", dest = "/config/fdr_config.json", gdriveId = "1x8KSJPVm-SiXHZaRx4kMGuw_-30lWlBQ" },
            { repoPath = "src/0_development/fdr/modules/ring_buffer.lua", dest = "/modules/ring_buffer.lua", gdriveId = "18RO9IL9OIwUmRDnX2-xC_LN4gY43o6Hj" },
            { repoPath = "src/0_development/fdr/modules/packet_tap.lua", dest = "/modules/packet_tap.lua", gdriveId = "1yLuvhPqD85rX0CqB97qzwLjRAvw1zsCT" },
            { repoPath = "src/0_development/fdr/modules/storage_pool.lua", dest = "/modules/storage_pool.lua", gdriveId = "1fQngSpgES5cAopgIl0X5wj8Eyz0wu7Zo" },
            { repoPath = "src/0_development/fdr/modules/jsonl_dumper.lua", dest = "/modules/jsonl_dumper.lua", gdriveId = "1XWozQpozXgE8rcJtK4SyX8rH6Rlojui1" },
            { repoPath = "src/0_development/fdr/modules/cloud_exporter.lua", dest = "/modules/cloud_exporter.lua", gdriveId = "1igAMGGXaOwBdCq_FJiIXOYxS7FEboaUg" },
            { repoPath = "src/0_development/fdr/modules/fdr_ui.lua", dest = "/modules/fdr_ui.lua", gdriveId = "12R_sdksjBi64P5zb8lsErQEwE-eganeg" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
        },
    },

    ota = {
        id = "ota",
        name = "Wireless OTA Server",
        category = "development",
        version = "0.1.0",
        installDir = "/ota",
        entry = "main.lua",
        autorun = false,
        startup = {
            enabled = false,
            path = "/startup/00_ota.lua",
            target = "/ota/main.lua",
            name = "OTA Server",
        },
        description = "Hangar Wireless OTA Deployment Server & Atomic Rollback Guard",
        roles = { "OTA Server", "Dev Layer 0" },
        files = {
            { repoPath = "src/0_development/ota/main.lua", dest = "/ota/main.lua", gdriveId = "16pef9rYqI_0cMlQPlke4GaE4kvuMJ61G" },
            { repoPath = "src/0_development/ota/config/ota_config.json", dest = "/ota/config/ota_config.json", isConfig = true, gdriveId = "1-ItvHsoMBO-5EgG14EMvK_TdYg4_H3Xq" },
            { repoPath = "src/0_development/ota/modules/ota_protocol.lua", dest = "/ota/modules/ota_protocol.lua", gdriveId = "1W_g1JN5cdfSoI5Itgs9vvCWoNDS3C8XT" },
            { repoPath = "src/0_development/ota/modules/ota_server.lua", dest = "/ota/modules/ota_server.lua", gdriveId = "1XZ72aBMoYXP3dwh1p0GSImHIDtge_ZeG" },
            { repoPath = "src/0_development/ota/modules/ota_ui.lua", dest = "/ota/modules/ota_ui.lua", gdriveId = "18aenQSFUx1BdgjUx5X2mmQssnlXOpYz6" },
            { repoPath = "src/0_development/ota/ota_agent.lua", dest = "/lib/ota_agent.lua", gdriveId = "1av9t1QqFdiSUBSlkQ_RMMEmqriY44uqX" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
        },
    },

    pocket_pda = {
        id = "pocket_pda",
        name = "Pocket PDA",
        category = "infra",
        version = "1.0.0",
        installDir = "/",
        startup = {
            enabled = true,
            path = "/startup/00_pocket_pda.lua",
            target = "/main.lua",
            name = "Pocket PDA",
        },
        description = "Pocket Computer 26x20 Remote C2, Telemetry HUD, Alignment & FDR Console",
        roles = { "Pocket Console", "Remote C2", "Infra Layer 0" },
        defaultConfigs = {
            ["/config/pda_config.json"] = {
                schemaVersion = "1.0.0",
                system = {
                    id = "PDA_01",
                    domainId = "POCKET_PDA_01",
                    modemSide = "back",
                    loopFrequencyHz = 20,
                    uiRefreshRateHz = 5,
                },
                defaults = {
                    aircraftIndexN = 1,
                    targetDomainId = "AIRCRAFT_01",
                    hangarBayId = 1,
                    fdrBoundIndexN = 1,
                },
                channels = {
                    gcsBootstrapChannel = 50000,
                    missionAckChannel = 50004,
                    aircraftBaseMin = 10000,
                    aircraftBandwidth = 40,
                    maxAircraft = 1000,
                    hangarBaseMin = 101,
                    hangarBandwidth = 10,
                    maxHangarBays = 10,
                },
                linkQuality = {
                    telemetryTimeoutMs = 2000,
                    nodeStaleMs = 3000,
                    strongMaxDistM = 80.0,
                    goodMaxDistM = 200.0,
                },
                ui = {
                    screenWidth = 26,
                    screenHeight = 20,
                },
            },
        },
        files = {
            { repoPath = "src/0_infra/pocket_pda/main.lua", dest = "/main.lua", gdriveId = "1Pda30da59942047e2455bfa5dba0ab19" },
            { repoPath = "src/0_infra/pocket_pda/config/pda_config.json", dest = "/config/pda_config.json", gdriveId = "1Pda13e059ff54567af1e8427088a22d8" },
            { repoPath = "src/0_infra/pocket_pda/modules/pda_network.lua", dest = "/modules/pda_network.lua", gdriveId = "1Pda3a4163e62386211a7a001c8ec767a" },
            { repoPath = "src/0_infra/pocket_pda/modules/telemetry_hud_state.lua", dest = "/modules/telemetry_hud_state.lua", gdriveId = "1Pdae4c87cf201e0a1584c3df809d6682" },
            { repoPath = "src/0_infra/pocket_pda/modules/emergency_c2_controller.lua", dest = "/modules/emergency_c2_controller.lua", gdriveId = "1Pda0711fe04b362169a2a63768dc6226" },
            { repoPath = "src/0_infra/pocket_pda/modules/remote_link_controller.lua", dest = "/modules/remote_link_controller.lua", gdriveId = "1Pdac7e3ba0939f0713616a47d85d790f" },
            { repoPath = "src/0_infra/pocket_pda/modules/pocket_tui.lua", dest = "/modules/pocket_tui.lua", gdriveId = "1Pda305e11af9d645d768258c46295e08" },
            { repoPath = "src/0_development/sensors/avionics_sensors.lua", dest = "/lib/avionics_sensors.lua", gdriveId = "1um2uK-ZT0IaxCSQhorkeyTE7dUYlLXCL" },
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
                telemetryDiag = false,
                debug = false,
            },
            channels = {
                baseChannel = 10000,
                bandwidth = 40,
                trajectoryOffset = 4,
                telemetryOffset = 2,
                guidanceOffset = 1,
                emergencyOffset = 9,
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
                telemetryDiag = false,
                debug = false,
            },
            channels = {
                baseChannel = 10000,
                bandwidth = 40,
                trajectoryOffset = 4,
                telemetryOffset = 2,
                guidanceOffset = 1,
                emergencyOffset = 9,
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
