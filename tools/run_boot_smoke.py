"""
CraftOS-PC Boot Smoke Test Runner for Create_Aeroneutics active subsystems.

Performs live headless boot smoke verification for all 10 active subsystem main.lua
entrypoints in isolated CraftOS-PC sessions with mock peripherals and non-blocking configs.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from harness.unit.config import CraftOSPaths, resolve_craftos_paths
from harness.unit.session import EphemeralCraftOSSession, clean_workspace_orphans


@dataclass
class SmokeTarget:
    target_id: str
    source_dir: Path
    expected_channels: list[int]
    cli_args: list[str] = field(default_factory=list)
    deferred: bool = False
    workspace_root: Path | None = None


@dataclass
class TargetSmokeReport:
    target_id: str
    status: str  # "PASS" | "FAIL"
    duration_ms: float = 0.0
    error: str | None = None
    opened_channels: list[int] = field(default_factory=list)
    expected_channels: list[int] = field(default_factory=list)
    missing_channels: list[int] = field(default_factory=list)
    timed_out: bool = False
    session_id: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def build_smoke_targets(workspace_root: Path, include_deferred: bool = False) -> list[SmokeTarget]:
    """
    Constructs the standard list of boot smoke targets.
    Active subsystems (12): alignment, fdr, installer, ota, gps, gac, gcs, landing_pad, tca, vas, fcp, amm.
    Deferred subsystems (1): asa (TASK-105).
    """
    root = workspace_root.resolve()
    src = root / "src"

    all_targets = [
        SmokeTarget(
            target_id="0_development/alignment",
            source_dir=src / "0_development" / "alignment",
            expected_channels=[101, 102, 104],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_development/fdr",
            source_dir=src / "0_development" / "fdr",
            expected_channels=[10001, 10002, 10004, 10010, 10011],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_development/installer",
            source_dir=src / "0_development" / "installer",
            expected_channels=[],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_development/ota",
            source_dir=src / "0_development" / "ota",
            expected_channels=[106],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_infra/gps",
            source_dir=src / "0_infra" / "gps",
            expected_channels=[60002, 60003, 60004],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_infra/gac",
            source_dir=src / "0_infra" / "gac",
            expected_channels=[50001, 50002, 50004, 50201, 50202],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_infra/gcs",
            source_dir=src / "0_infra" / "gcs",
            expected_channels=[50000],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="0_infra/landing_pad",
            source_dir=src / "0_infra" / "landing_pad",
            expected_channels=[50202, 50206, 50211],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="1_control/tca",
            source_dir=src / "1_control" / "tca",
            expected_channels=[10010],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="1_control/vas",
            source_dir=src / "1_control" / "vas",
            expected_channels=[10001, 10010, 10011],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="2_guidance/fcp",
            source_dir=src / "2_guidance" / "fcp",
            expected_channels=[10001, 10002, 10004],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="3_planning/amm",
            source_dir=src / "3_planning" / "amm",
            expected_channels=[10000, 10002, 10003, 10004, 10005],
            cli_args=[],
            deferred=False,
            workspace_root=root,
        ),
        SmokeTarget(
            target_id="1_control/asa",
            source_dir=src / "1_control" / "asa",
            expected_channels=[10011],
            cli_args=[],
            deferred=True,
            workspace_root=root,
        ),
    ]

    if not include_deferred:
        return [t for t in all_targets if not t.deferred]
    return all_targets


def _stage_shared_sensors(computer_dir: Path, workspace_root: Path) -> None:
    shared_sensors = workspace_root / "src" / "0_development" / "sensors" / "avionics_sensors.lua"
    if not shared_sensors.is_file():
        raise FileNotFoundError(f"Required shared sensor library missing at {shared_sensors}")
    lib_dest = computer_dir / "lib"
    lib_dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(shared_sensors, lib_dest / "avionics_sensors.lua")

    shared_ota = workspace_root / "src" / "0_development" / "ota" / "ota_agent.lua"
    if not shared_ota.is_file():
        raise FileNotFoundError(f"Required shared OTA agent library missing at {shared_ota}")
    shutil.copy2(shared_ota, lib_dest / "ota_agent.lua")


def _stage_minimal_configs(computer_dir: Path) -> None:
    """
    Stages minimal, non-blocking configuration files to avoid interactive setup wizards
    or missing configuration aborts during boot smoke.
    """
    config_dir = computer_dir / "config"
    config_dir.mkdir(parents=True, exist_ok=True)

    # 1. TCA / Root config.json
    root_cfg = {
        "schemaVersion": "1.2.0",
        "groupId": "THR_MAIN_L",
        "interactionMode": "REDSTONE",
        "aircraftIndexN": 1,
        "baseChannel": 10000,
        "channels": {"thrustActuation": 10010},
        "watchdogTimeoutMs": 300,
        "nominalActuatorCount": 4,
        "aircraftDomainId": "AIRCRAFT_01",
        "ports": {
            "modemSide": "top",
            "redstoneSide": "bottom",
            "apiSides": ["left", "right", "front", "back"],
        },
        "deadband": 0,
        "debug": False,
    }
    (computer_dir / "config.json").write_text(json.dumps(root_cfg, indent=2), encoding="utf-8")

    # 2. GAC config
    gac_dir = computer_dir / "gac"
    gac_dir.mkdir(parents=True, exist_ok=True)
    gac_cfg = {
        "sectorId": "SECTOR_ALPHA",
        "towerAtcChannel": 50001,
        "baseSecChannel": 50201,
        "facilities": [],
        "surfaceWind": {"speed": 0, "heading": 0},
    }
    (gac_dir / "config.json").write_text(json.dumps(gac_cfg, indent=2), encoding="utf-8")

    # 3. Landing pad config
    pad_dir = computer_dir / "landing_pad"
    pad_dir.mkdir(parents=True, exist_ok=True)
    pad_cfg = {
        "padId": "PAD_01",
        "mode": "RADAR",
        "channels": {
            "sectorFacilityChannel": 50202,
            "sectorGpsReplyChannel": 50206,
            "tacticalChannel": 50211,
        },
    }
    (pad_dir / "config.json").write_text(json.dumps(pad_cfg, indent=2), encoding="utf-8")

    # 4. GCS config
    gcs_cfg = {
        "system": {
            "id": "GCS_01",
            "name": "Ground Control Station",
            "domainId": "GCS_01",
            "loopFrequencyHz": 20,
            "uiRefreshRateHz": 5,
            "modemSide": "top",
        },
        "channels": {
            "bootstrapChannel": 50000,
            "bandwidth": 40,
            "baseChannelMin": 10000,
            "baseChannelMax": 49960,
            "maxCraftBlocks": 1000,
        },
        "ui": {"screenWidth": 51, "screenHeight": 19, "telemetryTimeoutSec": 5.0},
    }
    (config_dir / "gcs_config.json").write_text(json.dumps(gcs_cfg, indent=2), encoding="utf-8")

    # 5. FCP config
    fcp_cfg = {
        "system": {"debug": False, "airframeType": "VECTORED_VTOL"},
        "channels": {
            "baseChannel": 10000,
            "trajectoryOffset": 4,
            "telemetryOffset": 2,
            "guidanceOffset": 1,
        },
    }
    (config_dir / "fcp_config.json").write_text(json.dumps(fcp_cfg, indent=2), encoding="utf-8")

    # 6. AMM config
    amm_cfg = {
        "domainId": "AIRCRAFT_01",
        "baseChannel": 10000,
        "defaultAlt": 150.0,
        "defaultSpeed": 18.0,
        "arrivalRadius": 15.0,
        "headless": True,
    }
    (config_dir / "amm_config.json").write_text(json.dumps(amm_cfg, indent=2), encoding="utf-8")

    # 7. VAS config
    (config_dir / "sensors.json").write_text(json.dumps({"roles": {}}, indent=2), encoding="utf-8")
    (config_dir / "system.json").write_text(
        json.dumps({"debug": False, "baseChannel": 10000}, indent=2),
        encoding="utf-8",
    )

    # 8. FDR config
    fdr_cfg = {
        "schemaVersion": "1.1.0",
        "aircraftIndexN": 1,
        "baseChannel": 10000,
        "recordMode": "STREAMING",
        "autoStartOnBoot": True,
        "storage": {"allowLocalFallback": True},
    }
    (config_dir / "fdr_config.json").write_text(json.dumps(fdr_cfg, indent=2), encoding="utf-8")

    # 9. OTA config
    ota_cfg = {
        "version": "0.1.0",
        "ota": {
            "bayId": 1,
            "chunkSize": 2048,
            "ackTimeoutSec": 1.5,
            "maxRetries": 3,
            "defaultSourceDir": "/ota_packages",
            "autoSyncOnBoot": False,
        },
        "network": {
            "domainId": "HANGAR-OTA-01",
        },
    }
    (config_dir / "ota_config.json").write_text(json.dumps(ota_cfg, indent=2), encoding="utf-8")


def _build_guest_startup_lua() -> str:
    return """
-- Guest Boot Smoke Startup Harness
if term then
    local noop = function() end
    term.write = noop
    term.blit = noop
    term.scroll = noop
    term.clear = noop
    term.clearLine = noop
    term.setCursorPos = noop
    term.setTextColor = noop
    term.setTextColour = noop
    term.setBackgroundColor = noop
    term.setBackgroundColour = noop
end
_G.print = function() end

if package then
    package.path = "?.lua;modules/?.lua;hal/?.lua;lib/?.lua;/?.lua;/?/init.lua;/modules/?.lua;/modules/?/init.lua;/hal/?.lua;/tools/?.lua;/lib/?.lua;" .. (package.path or "")
end

local opened_channels = {}
local current_opened = {}

local mock_modem
mock_modem = {
    opened = current_opened,
    open = function(a1, a2)
        local c = tonumber(type(a1) == "number" and a1 or a2)
        if c and c >= 0 and c <= 65535 then
            opened_channels[c] = true
            current_opened[c] = true
        end
    end,
    close = function(a1, a2)
        local c = tonumber(type(a1) == "number" and a1 or a2)
        if c then
            current_opened[c] = nil
        end
    end,
    closeAll = function()
        for k, _ in pairs(current_opened) do current_opened[k] = nil end
    end,
    isOpen = function(a1, a2)
        local c = tonumber(type(a1) == "number" and a1 or a2)
        return c ~= nil and current_opened[c] == true
    end,
    isWireless = function() return true end,
    transmit = function() end,
    getNamesRemote = function() return {} end,
    isPresentRemote = function() return false end,
    getTypeRemote = function() return nil end,
}

local mock_monitor = {
    write = function() end,
    blit = function() end,
    clear = function() end,
    clearLine = function() end,
    getCursorPos = function() return 1, 1 end,
    setCursorPos = function() end,
    setCursorBlink = function() end,
    isColor = function() return true end,
    isColour = function() return true end,
    setTextColor = function() end,
    setTextColour = function() end,
    setBackgroundColor = function() end,
    setBackgroundColour = function() end,
    getSize = function() return 51, 19 end,
    scroll = function() end,
    setTextScale = function() end,
}

local mock_velocity_sensor = {
    getVelocity = function() return 0.0 end,
    getAxis = function() return "x" end,
}

local mock_altitude_sensor = {
    getHeight = function() return 100.0 end,
    getAirPressure = function() return 1.0 end,
    getVerticalSpeed = function() return 0.0 end,
}

local mock_gimbal_sensor = {
    getAngles = function() return { 0.0, 0.0 } end,
    getAnglesRad = function() return { 0.0, 0.0 } end,
    getAngularRates = function() return { 0.0, 0.0, 0.0 } end,
    getAngularRatesRad = function() return { 0.0, 0.0, 0.0 } end,
    getGravity = function() return { 0.0, -11.0, 0.0 } end,
    getLinearAcceleration = function() return { 0.0, 11.0, 0.0 } end,
}

local mock_physics_assembler = {
    isAssembled = function() return true end,
    getMass = function() return 1000.0 end,
    getCenterOfMass = function() return { 0.0, 0.0, 0.0 } end,
    getInertiaTensor = function() return { 100.0, 0.0, 0.0, 0.0, 200.0, 0.0, 0.0, 0.0, 150.0 } end,
    getSubLevelId = function() return "BASE" end,
    getSubLevelName = function() return "Base" end,
}

local mock_thruster = {
    setSpeed = function() end,
    setPower = function() end,
    setThrust = function() end,
    setTargetPitch = function() end,
    setTargetYaw = function() end,
}

local mock_fuel_tank = {
    tanks = function() return { { amount = 1000, capacity = 1000 } } end,
    getReading = function() return { amount = 1000, capacity = 1000 } end,
}

local registry = {
    top = { type = "modem", dev = mock_modem },
    bottom = { type = "modem", dev = mock_modem },
    back = { type = "monitor", dev = mock_monitor },
    front = { type = "velocity_sensor", dev = mock_velocity_sensor },
    left = { type = "altitude_sensor", dev = mock_altitude_sensor },
    right = { type = "gimbal_sensor", dev = mock_gimbal_sensor },
    thruster_0 = { type = "ion_thruster", dev = mock_thruster },
    thruster_1 = { type = "thruster", dev = mock_thruster },
    tank_0 = { type = "fuel_tank", dev = mock_fuel_tank },
    assembler_0 = { type = "physics_assembler", dev = mock_physics_assembler },
}

local p_orig = _G.peripheral
local mock_p = {
    getNames = function()
        local names = {}
        for k, _ in pairs(registry) do names[#names + 1] = k end
        table.sort(names)
        return names
    end,
    isPresent = function(side)
        return registry[side] ~= nil or (p_orig and p_orig.isPresent and p_orig.isPresent(side))
    end,
    getType = function(side)
        if registry[side] then return registry[side].type end
        if p_orig and p_orig.getType then return p_orig.getType(side) end
        return nil
    end,
    wrap = function(side)
        if registry[side] then return registry[side].dev end
        if p_orig and p_orig.wrap then return p_orig.wrap(side) end
        return nil
    end,
    hasType = function(side, ptype)
        local actual = (registry[side] and registry[side].type)
        if not actual and p_orig and p_orig.getType then
            actual = p_orig.getType(side)
        end
        if not actual then return false end
        return actual == ptype or string.find(actual, ptype, 1, true) ~= nil
    end,
    getMethods = function(side)
        local dev = (registry[side] and registry[side].dev)
        if not dev and p_orig and p_orig.wrap then
            dev = p_orig.wrap(side)
        end
        if not dev then return nil end
        local methods = {}
        for k, v in pairs(dev) do
            if type(v) == "function" then methods[#methods + 1] = k end
        end
        table.sort(methods)
        return methods
    end,
    getName = function(dev)
        for side, ent in pairs(registry) do
            if ent.dev == dev then return side end
        end
        if p_orig and p_orig.getName then return p_orig.getName(dev) end
        return nil
    end,
    find = function(ptype, fnFilter)
        local matched = {}
        for side, ent in pairs(registry) do
            if ent.type == ptype or string.find(ent.type, ptype, 1, true) then
                if not fnFilter or fnFilter(side, ent.dev) then
                    matched[#matched + 1] = ent.dev
                end
            end
        end
        if #matched > 0 then
            return table.unpack(matched)
        end
        if p_orig and p_orig.find then
            return p_orig.find(ptype, fnFilter)
        end
        return nil
    end,
    call = function(side, method, ...)
        local dev = (registry[side] and registry[side].dev)
        if dev and type(dev[method]) == "function" then
            return dev[method](...)
        end
        if p_orig and p_orig.call then
            return p_orig.call(side, method, ...)
        end
        error("No such method " .. tostring(method) .. " on peripheral " .. tostring(side), 2)
    end,
}
_G.peripheral = mock_p

-- Safe mock http
if not _G.http then _G.http = {} end
_G.http.checkURL = function() return true end
_G.http.get = function(url)
    return {
        getResponseCode = function() return 200 end,
        readAll = function() return "{}" end,
        readLine = function() return nil end,
        close = function() end,
    }
end
_G.http.post = function() return _G.http.get() end

-- Safe mock redstone
if not _G.redstone then _G.redstone = {} end
_G.redstone.setOutput = function() end
_G.redstone.getOutput = function() return false end
_G.redstone.getInput = function() return false end
_G.redstone.setAnalogueOutput = function() end
_G.redstone.setAnalogOutput = function() end
_G.redstone.getAnalogueInput = function() return 0 end
_G.redstone.getAnalogInput = function() return 0 end
_G.rs = _G.redstone

-- Set up global shell
_G.shell = _G.shell or shell or {}
_G.shell.run = function(prog, ...)
    local path = prog
    if not path:match("^/") then path = "/" .. path end
    local fn, err = loadfile(path, nil, _ENV)
    if not fn then error("shell.run failed to load " .. tostring(prog) .. ": " .. tostring(err), 2) end
    return fn(...)
end
_G.shell.getRunningProgram = function() return "/main.lua" end
_G.shell.dir = function() return "/" end
_G.shell.resolve = function(p) return p end
shell = _G.shell

-- Read runner configuration
local cf = fs.open("/_harness/smoke_config.json", "r")
local cfg = cf and textutils.unserializeJSON(cf.readAll()) or {}
if cf then cf.close() end

local cli_args = cfg.cli_args or {}
local tick_window = tonumber(cfg.tick_window) or 0.35

local boot_err = nil
local completed_early = false

local function run_main()
    local fn, load_err = loadfile("/main.lua", nil, _ENV)
    if not fn then
        boot_err = "LOAD_ERROR: " .. tostring(load_err)
        return
    end
    local ok, run_err = pcall(fn, table.unpack(cli_args))
    if not ok then
        local err_str = tostring(run_err)
        if not (err_str:find("Terminated") or err_str:find("terminate")) then
            boot_err = "RUNTIME_ERROR: " .. err_str
        end
    else
        completed_early = true
    end
end

local function watchdog()
    local t1 = os.startTimer(tick_window)
    while true do
        local ev, p1 = os.pullEventRaw()
        if ev == "timer" and p1 == t1 then break end
    end
    os.queueEvent("terminate")
    local t2 = os.startTimer(0.2)
    while true do
        local ev, p1 = os.pullEventRaw()
        if ev == "timer" and p1 == t2 then break end
    end
end

pcall(function()
    parallel.waitForAny(run_main, watchdog)
end)

local ch_list = {}
for ch, _ in pairs(opened_channels) do
    ch_list[#ch_list + 1] = ch
end
table.sort(ch_list)

local result_payload = {
    status = (boot_err == nil) and "PASS" or "FAIL",
    error = boot_err,
    opened_channels = ch_list,
    completed_early = completed_early,
}

fs.makeDir("/_harness_out")
local rf = fs.open("/_harness_out/result.json", "w")
if rf then
    rf.write(textutils.serializeJSON(result_payload))
    rf.close()
end
local df = fs.open("/_harness_out/done.flag", "w")
if df then
    df.write("DONE")
    df.close()
end

os.shutdown()
"""


def run_target_boot_smoke(
    target: SmokeTarget,
    craftos_paths: CraftOSPaths,
    sessions_root: Path,
    timeout_sec: float = 30.0,
    tick_window: float = 0.35,
) -> dict[str, Any]:
    t0 = time.perf_counter()

    if not target.source_dir.is_dir() or not (target.source_dir / "main.lua").is_file():
        dur = round((time.perf_counter() - t0) * 1000.0, 2)
        return TargetSmokeReport(
            target_id=target.target_id,
            status="FAIL",
            duration_ms=dur,
            error=f"Source directory or main.lua missing at {target.source_dir}",
            expected_channels=target.expected_channels,
            missing_channels=target.expected_channels,
        ).to_dict()

    if target.workspace_root is not None:
        workspace_root = target.workspace_root
    else:
        resolved_src = target.source_dir.resolve()
        if (
            len(resolved_src.parents) > 2
            and (resolved_src.parents[2] / "src" / "0_development" / "sensors" / "avionics_sensors.lua").is_file()
        ):
            workspace_root = resolved_src.parents[2]
        else:
            workspace_root = Path(__file__).resolve().parent.parent

    session_prefix = f"smoke_{target.target_id.replace('/', '_')}"

    with EphemeralCraftOSSession(
        sessions_root=sessions_root,
        craftos_paths=craftos_paths,
        prefix=session_prefix,
        abort_timeout_ms=int(timeout_sec * 1000),
    ) as session:
        c0 = session.computer_dir(0)

        # 1. Stage shared sensors
        _stage_shared_sensors(c0, workspace_root)

        # 2. Stage target source tree
        session.stage_tree(target.source_dir, computer_id=0, dest_subdir="")

        # 3. Stage minimal configs
        _stage_minimal_configs(c0)

        # 4. Stage harness config
        harness_dir = c0 / "_harness"
        harness_dir.mkdir(parents=True, exist_ok=True)
        harness_cfg = {
            "cli_args": target.cli_args,
            "tick_window": tick_window,
        }
        (harness_dir / "smoke_config.json").write_text(
            json.dumps(harness_cfg, indent=2), encoding="utf-8"
        )

        # 5. Write startup.lua
        startup_script = _build_guest_startup_lua()
        (c0 / "startup.lua").write_text(startup_script, encoding="utf-8")

        # 6. Run headless session
        res = session.run(mode="headless", timeout_sec=timeout_sec)
        dur = round((time.perf_counter() - t0) * 1000.0, 2)

        guest = res.guest_result or {}
        guest_status = guest.get("status")
        guest_err = guest.get("error")
        opened = guest.get("opened_channels", [])

        if res.timed_out and not guest:
            return TargetSmokeReport(
                target_id=target.target_id,
                status="FAIL",
                duration_ms=dur,
                error="CraftOS-PC session timed out before guest completed",
                expected_channels=target.expected_channels,
                missing_channels=target.expected_channels,
                timed_out=True,
                session_id=session.session_id,
            ).to_dict()

        if guest_status != "PASS" or guest_err:
            return TargetSmokeReport(
                target_id=target.target_id,
                status="FAIL",
                duration_ms=dur,
                error=guest_err or "Guest reported failure during boot smoke",
                opened_channels=opened,
                expected_channels=target.expected_channels,
                missing_channels=[c for c in target.expected_channels if c not in opened],
                session_id=session.session_id,
            ).to_dict()

        missing = [c for c in target.expected_channels if c not in opened]
        if missing:
            return TargetSmokeReport(
                target_id=target.target_id,
                status="FAIL",
                duration_ms=dur,
                error=f"Subsystem did not open expected channels: {missing}",
                opened_channels=opened,
                expected_channels=target.expected_channels,
                missing_channels=missing,
                session_id=session.session_id,
            ).to_dict()

        return TargetSmokeReport(
            target_id=target.target_id,
            status="PASS",
            duration_ms=dur,
            error=None,
            opened_channels=opened,
            expected_channels=target.expected_channels,
            missing_channels=[],
            session_id=session.session_id,
        ).to_dict()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run isolated CC:Tweaked boot smoke tests across Create_Aeroneutics subsystems."
    )
    parser.add_argument(
        "--filter",
        "-f",
        type=str,
        default=None,
        help="Substring filter applied to target subsystem IDs.",
    )
    parser.add_argument(
        "--include-deferred",
        action="store_true",
        help="Include deferred subsystems (e.g. 1_control/asa).",
    )
    parser.add_argument(
        "--clean-orphans",
        action="store_true",
        help="Terminate any lingering CraftOS-PC console processes for this workspace before running.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output structured JSON results instead of text summary.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=30.0,
        help="Timeout per subsystem session in seconds (default: 30.0).",
    )
    parser.add_argument(
        "--tick-window",
        type=float,
        default=0.35,
        help="Guest execution duration in seconds before watchdog terminates (default: 0.35).",
    )
    return parser


def run_boot_smoke_cli(
    argv: list[str] | None = None, workspace_root: Path | None = None
) -> tuple[int, dict[str, Any]]:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    root = (workspace_root or WORKSPACE_ROOT).resolve()
    sessions_root = root / ".runtime" / "sessions"

    cleaned_summary = None
    if args.clean_orphans:
        cleaned_summary = clean_workspace_orphans(sessions_root)

    try:
        craftos_paths = resolve_craftos_paths()
    except FileNotFoundError as exc:
        err_payload = {
            "overall_status": "FAIL",
            "error": str(exc),
            "cleaned_orphans": cleaned_summary,
            "targets": [],
        }
        if args.json:
            print(json.dumps(err_payload, indent=2))
        else:
            print(f"[FAIL] {exc}")
        return 1, err_payload

    targets = build_smoke_targets(root, include_deferred=args.include_deferred)

    if args.filter:
        flt = args.filter.lower().strip()
        targets = [t for t in targets if flt in t.target_id.lower()]

    if not targets:
        empty_payload = {
            "overall_status": "PASS",
            "message": "No targets matched filter",
            "targets": [],
        }
        if args.json:
            print(json.dumps(empty_payload, indent=2))
        else:
            print("No targets matched filter.")
        return 0, empty_payload

    t_all_start = time.perf_counter()
    reports: list[dict[str, Any]] = []
    failed_count = 0

    if not args.json:
        print(f"=== Create_Aeroneutics Boot Smoke Runner ({len(targets)} targets) ===")

    for target in targets:
        report = run_target_boot_smoke(
            target=target,
            craftos_paths=craftos_paths,
            sessions_root=sessions_root,
            timeout_sec=args.timeout,
            tick_window=args.tick_window,
        )
        reports.append(report)
        st = report["status"]
        dur = report["duration_ms"]
        chans = report.get("opened_channels", [])

        if st == "PASS":
            if not args.json:
                print(f"  [PASS] {target.target_id:<28} ({dur:>7.1f}ms) channels: {chans}")
        else:
            failed_count += 1
            err_msg = report.get("error") or "Unknown error"
            if not args.json:
                print(f"  [FAIL] {target.target_id:<28} ({dur:>7.1f}ms) error: {err_msg}")

    total_dur = round((time.perf_counter() - t_all_start) * 1000.0, 2)
    passed_count = len(targets) - failed_count
    overall = "PASS" if failed_count == 0 else "FAIL"

    summary_payload = {
        "overall_status": overall,
        "total_targets": len(targets),
        "passed_targets": passed_count,
        "failed_targets": failed_count,
        "duration_ms": total_dur,
        "cleaned_orphans": cleaned_summary,
        "targets": reports,
    }

    if args.json:
        print(json.dumps(summary_payload, indent=2))
    else:
        print(f"\nBoot smoke completed: {passed_count}/{len(targets)} PASS ({total_dur:.1f}ms)")

    return (0 if failed_count == 0 else 1), summary_payload


def main() -> None:
    code, _ = run_boot_smoke_cli(sys.argv[1:])
    sys.exit(code)


if __name__ == "__main__":
    main()
