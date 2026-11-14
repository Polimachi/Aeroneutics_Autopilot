"""Automated unit, DOM-shim, and CraftOS-PC roundtrip tests for AMM WebUI Mission Editor."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[3]
EDITOR_HTML = WORKSPACE_ROOT / "tools" / "amm_mission_editor.html"


def extract_inline_script() -> str:
    html = EDITOR_HTML.read_text(encoding="utf-8")
    match = re.search(r"<script>([\s\S]*)</script>", html)
    if not match:
        raise AssertionError("Inline <script> block missing from tools/amm_mission_editor.html")
    return match.group(1)


def run_editor_js(js_tail: str, dom_setup: str = "") -> dict:
    node = shutil.which("node")
    if not node:
        raise AssertionError("node executable is required for AMM editor JS tests")
    script_body = extract_inline_script()
    harness_js = f"""
const __storage = Object.create(null);
const localStorage = {{
  getItem(k) {{ return Object.prototype.hasOwnProperty.call(__storage, k) ? __storage[k] : null; }},
  setItem(k, v) {{ __storage[k] = String(v); }},
  removeItem(k) {{ delete __storage[k]; }},
}};
const navigator = {{ clipboard: {{ writeText() {{ return Promise.resolve(); }} }} }};
const window = {{
  devicePixelRatio: 1,
  addEventListener() {{}},
  removeEventListener() {{}},
  requestAnimationFrame(fn) {{ return 0; }},
}};
const document = {{
  body: {{ classList: {{ add(){{}}, remove(){{}}, toggle(){{}} }} }},
  activeElement: null,
  addEventListener() {{}},
  removeEventListener() {{}},
  getElementById() {{ return null; }},
  querySelector() {{ return null; }},
  querySelectorAll() {{ return []; }},
  createElement() {{ return {{ style: {{}}, classList: {{ add(){{}}, remove(){{}} }}, setAttribute(){{}}, appendChild(){{}}, addEventListener(){{}} }}; }},
}};
{dom_setup}
{script_body}
const E = window.__AMM_EDITOR__;
const __out = (() => {{
{js_tail}
}})();
console.log(JSON.stringify(__out === undefined ? null : __out));
"""
    res = subprocess.run(
        [node, "-"],
        input=harness_js,
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=str(WORKSPACE_ROOT),
        timeout=30,
    )
    if res.returncode != 0:
        raise AssertionError(
            f"Node test harness failed (exit {res.returncode}):\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}"
        )
    lines = [ln for ln in res.stdout.splitlines() if ln.strip()]
    return json.loads(lines[-1]) if lines else None


class TestEditorBootstrap(unittest.TestCase):
    def test_single_file_exists_offline_and_exposes_nine_modules(self) -> None:
        self.assertTrue(EDITOR_HTML.is_file(), "tools/amm_mission_editor.html must exist")
        html = EDITOR_HTML.read_text(encoding="utf-8")
        self.assertIn('<meta name="theme-color" content="#0b0f17">', html)
        self.assertIn("color-scheme: dark", html)
        self.assertIsNone(re.search(r"https?://|fetch\s*\(|XMLHttpRequest|WebSocket", html))
        self.assertIsNone(re.search(r"\bwindow\.(alert|confirm|prompt)\s*\(", html))
        self.assertNotIn("transition: all", html)

        keys = run_editor_js("return Object.keys(E || {});")
        expected = [
            "SchemaConstants",
            "MacroExpander",
            "DefaultResolver",
            "Validator",
            "Store",
            "CanvasRenderer",
            "InspectorUI",
            "JsonIO",
            "AppBootstrap",
        ]
        for mod in expected:
            self.assertIn(mod, keys)


class TestTask2SchemaAndMacros(unittest.TestCase):
    def test_schema_counts_and_precondition_keys(self) -> None:
        res = run_editor_js(
            """
            const S = E.SchemaConstants;
            const preKeys = Object.values(S.PRECONDITION_CATEGORIES).flatMap((c) => c.fields.map((f) => f.key));
            return {
              activeCount: Object.keys(S.ACTIVE_ACTIONS).length,
              deferredCount: Object.keys(S.DEFERRED_ACTIONS).length,
              legacyCount: S.LEGACY_ACTIONS.length,
              activeDec: S.ACTIVE_DECORATORS.length,
              deferredDec: S.DEFERRED_DECORATORS.length,
              activeMac: S.ACTIVE_MACROS.length,
              deferredMac: S.DEFERRED_MACROS.length,
              preKeyCount: preKeys.length,
              condCount: S.CONDITION_TYPES.length,
              timeoutField: S.CONDITION_META.TIMEOUT_SEC.fields[0].key,
              hookCount: S.HOOK_TYPES.length,
              colorCount: S.BUNDLED_COLORS.length,
            };
            """
        )
        self.assertEqual(res["activeCount"], 36)
        self.assertEqual(res["deferredCount"], 22)
        self.assertEqual(res["legacyCount"], 13)
        self.assertEqual(res["activeDec"], 6)
        self.assertEqual(res["deferredDec"], 1)
        self.assertEqual(res["activeMac"], 3)
        self.assertEqual(res["deferredMac"], 2)
        self.assertEqual(res["preKeyCount"], 19)
        self.assertEqual(res["condCount"], 14)
        self.assertEqual(res["timeoutField"], "timeout")
        self.assertEqual(res["hookCount"], 4)
        self.assertEqual(res["colorCount"], 16)

    def test_default_resolver_and_channel_math(self) -> None:
        res = run_editor_js(
            """
            const D = E.DefaultResolver;
            const spline = D.resolveCheckpointDefaults({ action: "ACT_NAV_SPLINE_WP", params: {} }, { targetAlt: 150, cruiseSpeed: 18, acceptanceRadius: 15, headingMode: "AUTO" });
            const gotowp = D.resolveCheckpointDefaults({ action: "ACT_NAV_GOTO_WP", params: {} }, { targetAlt: 150, cruiseSpeed: 18, acceptanceRadius: 15, headingMode: "AUTO" });
            return {
              spline,
              gotowp,
              base1: D.computeBaseChannel(1),
              base3: D.computeBaseChannel(3),
              z3: D.resolveZone3Channel(22, 10080),
            };
            """
        )
        self.assertEqual(res["spline"]["acceptanceRadius"], 15.0)
        self.assertEqual(res["spline"]["settleTicks"], 0)
        self.assertEqual(res["gotowp"]["acceptanceRadius"], 5.0)
        self.assertEqual(res["gotowp"]["settleTicks"], 4)
        self.assertEqual(res["base1"], 10000)
        self.assertEqual(res["base3"], 10080)
        self.assertEqual(res["z3"], 10102)

    def test_macro_expansion_airframe_and_cargo_keys(self) -> None:
        res = run_editor_js(
            """
            const M = E.MacroExpander;
            const shipVtol = M.expandMacroCheckpoint({ checkpointId: "REC", action: "MAC_SHIP_RECOVERY", params: { facilityId: "CARRIER_01", targetPos: { x: 10, z: 20 } } }, "WINGED_VTOL");
            const shipMulti = M.expandMacroCheckpoint({ checkpointId: "REC", action: "MAC_SHIP_RECOVERY", params: { facilityId: "CARRIER_01", targetPos: { x: 10, z: 20 } } }, "MULTICOPTER");
            const cargo = M.expandMacroCheckpoint({ checkpointId: "CRG", action: "MAC_CARGO_SORTIE", params: { facilityId: "PAD_A", targetPos: { x: 50, z: -40 }, targetAlt: 120, channelOffset: 21, command: "DROP", payload: { bay: 1 }, awaitAck: true } }, "WINGED_VTOL");
            const recon = M.expandMacroCheckpoint({ checkpointId: "RCN", action: "MAC_RECON_ORBIT", params: { targetPos: { x: 200, z: -100 }, targetAlt: 140 } }, "WINGED_VTOL");
            return {
              shipVtolActions: shipVtol.map((s) => s.action),
              shipMultiActions: shipMulti.map((s) => s.action),
              cargoBusParams: cargo[2].params,
              reconDecs: [recon[2].decorators[0].decoratorId, recon[4].decorators[0].decoratorId],
            };
            """
        )
        self.assertEqual(
            res["shipVtolActions"],
            ["ACT_MOB_RV_TRACK", "ACT_TKL_TRANS_FW2MC", "ACT_MOB_DECK_SYNC", "ACT_TKL_LAND_PREC", "ACT_SYS_DISARM"],
        )
        self.assertEqual(
            res["shipMultiActions"],
            ["ACT_MOB_RV_TRACK", "ACT_MOB_DECK_SYNC", "ACT_TKL_LAND_PREC", "ACT_SYS_DISARM"],
        )
        self.assertEqual(res["cargoBusParams"]["payload"], {"bay": 1})
        self.assertTrue(res["cargoBusParams"]["awaitAck"])
        self.assertEqual(res["reconDecs"], ["DEC_SMOOTH_TRAJ", "DEC_ENERGY_ECO"])

    def test_shortcut_coords_and_extras_preservation(self) -> None:
        res = run_editor_js(
            """
            const M = E.MacroExpander;
            const norm = M.normalizeShortcutCoords({ x: 33, z: -44, targetAlt: 100 });
            const extras = M.extractExtras({ action: "ACT_NAV_SPLINE_WP", params: {}, _customTag: "keep-me" }, ["checkpointId", "action", "params", "preconditions", "decorators", "completeWhen", "abortWhen", "onEnter", "onExit", "onAbort", "fallbackPolicy"]);
            const merged = M.mergeExtras({ action: "ACT_NAV_SPLINE_WP" }, extras);
            return { norm, merged };
            """
        )
        self.assertEqual(res["norm"], {"targetPos": {"x": 33, "z": -44}, "targetAlt": 100})
        self.assertEqual(res["merged"]["_customTag"], "keep-me")


class TestTask3Validator(unittest.TestCase):
    def test_legacy_format_and_legacy_actions_rejected(self) -> None:
        res = run_editor_js(
            """
            const V = E.Validator;
            const r1 = V.validateMission({ missionId: "M1", items: [{ type: "FLY_TO" }] });
            const r2 = V.validateMission({
              missionId: "M2",
              checkpoints: [{ checkpointId: "C1", action: "FLY_OVER", params: { x: 10, z: 20 } }]
            });
            return { r1, r2 };
            """
        )
        self.assertFalse(res["r1"]["valid"])
        self.assertTrue(any(e["code"] == "LEGACY_MISSION_FORMAT" for e in res["r1"]["errors"]))
        self.assertFalse(res["r2"]["valid"])
        self.assertTrue(any(e["code"] == "LEGACY_ACTION_UNSUPPORTED" for e in res["r2"]["errors"]))

    def test_preconditions_19_keys_minalt_maxalt_and_airframe_conflict(self) -> None:
        res = run_editor_js(
            """
            const V = E.Validator;
            const validMission = {
              missionId: "M_PRE",
              checkpoints: [{
                checkpointId: "C1",
                action: "ACT_NAV_GOTO_WP",
                params: { targetPos: { x: 100, z: 200 }, targetAlt: 120 },
                preconditions: {
                  controlState: "AUTO",
                  activeSource: "AMM",
                  fsmState: ["CRUISE", "LOITER"],
                  allowedAirframes: ["WINGED_VTOL"],
                  disallowedAirframes: ["FIXED_WING"],
                  sensorOk: true,
                  gpsValid: true,
                  maxHdop: 2.5,
                  requireTap: true,
                  requireAsa: true,
                  requireGimbal: false,
                  minFuel: 0.25,
                  channelBound: true,
                  atcCleared: false,
                  zone3Available: true,
                  geofenceMarginM: 20,
                  minAlt: 50,
                  maxAlt: 300,
                  maxSpeed: 28
                }
              }]
            };
            const ok = V.validateMission(validMission, { targetAirframe: "WINGED_VTOL" });
            const badAlt = V.validateMission({
              missionId: "M_ALT",
              checkpoints: [{
                checkpointId: "C1",
                action: "ACT_NAV_GOTO_WP",
                params: { targetPos: { x: 100, z: 200 } },
                preconditions: { minAlt: 250, maxAlt: 100 }
              }]
            });
            const badAirframe = V.validateMission({
              missionId: "M_AF",
              checkpoints: [{
                checkpointId: "C1",
                action: "ACT_NAV_GOTO_WP",
                params: { targetPos: { x: 100, z: 200 } },
                preconditions: { allowedAirframes: ["MULTICOPTER"] }
              }]
            }, { targetAirframe: "FIXED_WING" });
            return { ok, badAlt, badAirframe };
            """
        )
        self.assertTrue(res["ok"]["valid"], res["ok"])
        self.assertEqual(res["ok"]["errors"], [])
        self.assertFalse(res["badAlt"]["valid"])
        self.assertTrue(any(e["code"] == "PRECONDITION_STATIC_INVALID" for e in res["badAlt"]["errors"]))
        self.assertFalse(res["badAirframe"]["valid"])
        self.assertTrue(any(e["code"] == "PRECONDITION_STATIC_INVALID" for e in res["badAirframe"]["errors"]))

    def test_deferred_three_way_warnings_and_domain_errors(self) -> None:
        res = run_editor_js(
            """
            const V = E.Validator;
            const deferred = V.validateMission({
              missionId: "M_DEF",
              checkpoints: [
                { checkpointId: "D1", action: "ACT_TKL_TAKEOFF_RWY", params: {} },
                { checkpointId: "D2", action: "ACT_NAV_GOTO_WP", params: { targetPos: { x: 0, z: 0 } }, decorators: [{ decoratorId: "DEC_TIME_CRIT" }] },
                { checkpointId: "D3", action: "MAC_PATROL_RADAR", params: { targetPos: { x: 10, z: 10 } } }
              ]
            });
            const badCorridor = V.validateMission({
              missionId: "M_COR",
              checkpoints: [{ checkpointId: "C1", action: "ACT_NAV_CORRIDOR", params: { startPos: { x: 0, z: 0 } } }]
            });
            const badPoi = V.validateMission({
              missionId: "M_POI",
              checkpoints: [{ checkpointId: "C1", action: "ACT_PAT_POI_HOLD", params: { targetPos: { x: 50, z: 50 } } }]
            });
            const badZone3 = V.validateMission({
              missionId: "M_Z3",
              checkpoints: [{ checkpointId: "C1", action: "ACT_PAY_BUS_CMD", params: { channelOffset: 12, command: "DROP" } }]
            });
            const badCond = V.validateMission({
              missionId: "M_COND",
              checkpoints: [{
                checkpointId: "C1",
                action: "ACT_NAV_GOTO_WP",
                params: { targetPos: { x: 10, z: 10 } },
                completeWhen: { all: [] },
                abortWhen: { type: "TIMEOUT_SEC", timeoutSec: 15 }
              }]
            });
            const warnCases = V.validateMission({
              missionId: "M_WARN",
              checkpoints: [
                { checkpointId: "W1", action: "ACT_PAT_LOITER_TIME", params: { targetPos: { x: 10, z: 10 }, radius: 12 } },
                { checkpointId: "W2", action: "ACT_PAT_HOLD_POS", params: {} }
              ]
            });
            const badHook = V.validateMission({
              missionId: "M_HOOK",
              checkpoints: [{
                checkpointId: "H1",
                action: "ACT_SYS_ARM",
                params: {},
                onEnter: [{ type: "REDSTONE_PULSE", side: "invalid_side", durationMs: 0 }],
                onExit: [{ type: "ZONE3_PAYLOAD_CMD", channelOffset: 5, command: "" }],
                onAbort: [{ type: "NOTIFY_OPERATOR", message: "" }]
              }]
            });
            return { deferred, badCorridor, badPoi, badZone3, badCond, warnCases, badHook };
            """
        )
        d_codes = {w["code"] for w in res["deferred"]["warnings"]}
        self.assertTrue({"DEFERRED_ACTION_UNSUPPORTED", "DEFERRED_DECORATOR_UNSUPPORTED", "DEFERRED_MACRO_UNSUPPORTED"}.issubset(d_codes))
        self.assertTrue(any(e["code"] == "INVALID_CORRIDOR_BOUNDS" for e in res["badCorridor"]["errors"]))
        self.assertTrue(any(e["code"] == "MISSING_POI_POS" for e in res["badPoi"]["errors"]))
        self.assertTrue(any(e["code"] == "INVALID_ZONE3_CHANNEL" for e in res["badZone3"]["errors"]))
        cond_codes = {e["code"] for e in res["badCond"]["errors"]}
        self.assertIn("EMPTY_CONDITION_GROUP", cond_codes)
        self.assertTrue(any(e["code"] in ("INVALID_TIMEOUT_FIELD", "INVALID_CONDITION_PARAM") for e in res["badCond"]["errors"]))
        warn_codes = {w["code"] for w in res["warnCases"]["warnings"]}
        self.assertIn("ORBIT_RADIUS_BELOW_FCP_MIN", warn_codes)
        self.assertIn("MISSING_DURATION_HOLD_MANUAL", warn_codes)
        hook_codes = {e["code"] for e in res["badHook"]["errors"]}
        self.assertIn("INVALID_HOOK_PARAM", hook_codes)
        self.assertIn("INVALID_ZONE3_CHANNEL", hook_codes)
        self.assertEqual(res["badHook"]["errors"][0]["fieldPath"].startswith("checkpoints[0].on"), True)

    def test_100_checkpoint_validation_under_50ms(self) -> None:
        res = run_editor_js(
            """
            const cps = [];
            for (let i = 0; i < 100; i++) {
              cps.push({
                checkpointId: "WP_" + i,
                action: "ACT_NAV_SPLINE_WP",
                params: { targetPos: { x: i * 50, z: (i % 5) * 30 }, targetAlt: 150, cruiseSpeed: 18 },
                onEnter: [{ type: "NOTIFY_OPERATOR", message: "Entering " + i }]
              });
            }
            const t0 = performance.now();
            const out = E.Validator.validateMission({ missionId: "PERF_100", version: "2.0.0", executionMode: "SINGLE", fallbackPolicy: "RTH", checkpoints: cps });
            const elapsedMs = performance.now() - t0;
            return { valid: out.valid, elapsedMs };
            """
        )
        self.assertTrue(res["valid"])
        self.assertLess(res["elapsedMs"], 50.0)


class TestTask4StoreAndJsonIO(unittest.TestCase):
    def test_undo_redo_50_deep_and_transactions(self) -> None:
        res = run_editor_js(
            """
            const S = E.Store;
            S.resetToEmptyDraft({ clearUndo: true });
            for (let i = 0; i < 60; i++) {
              S.addCheckpoint("ACT_NAV_SPLINE_WP", { targetPos: { x: i * 10, z: 0 } });
            }
            const lenAfter60 = S.getState().mission.checkpoints.length;
            let undoCount = 0;
            while (S.canUndo()) {
              S.undo();
              undoCount += 1;
            }
            const lenAfterUndo = S.getState().mission.checkpoints.length;
            while (S.canRedo()) S.redo();
            const lenAfterRedo = S.getState().mission.checkpoints.length;

            // Transaction coalesces multiple mutations into 1 undo entry
            S.resetToEmptyDraft({ clearUndo: true });
            S.addCheckpoint("ACT_NAV_GOTO_WP", { targetPos: { x: 0, z: 0 } });
            S.beginUndoTransaction();
            for (let k = 1; k <= 10; k++) {
              S.mutateMission((m) => { m.checkpoints[0].params.targetPos.x = k * 5; }, { pushUndo: false });
            }
            S.commitUndoTransaction();
            const afterDragX = S.getState().mission.checkpoints[0].params.targetPos.x;
            S.undo();
            const afterUndoDragX = S.getState().mission.checkpoints[0].params.targetPos.x;
            return { lenAfter60, undoCount, lenAfterUndo, lenAfterRedo, afterDragX, afterUndoDragX };
            """
        )
        self.assertEqual(res["lenAfter60"], 60)
        self.assertEqual(res["undoCount"], 50)
        self.assertEqual(res["lenAfterUndo"], 10)
        self.assertEqual(res["lenAfterRedo"], 60)
        self.assertEqual(res["afterDragX"], 50)
        self.assertEqual(res["afterUndoDragX"], 0)

    def test_presets_import_expand_undo_recoverable_and_zero_fallback(self) -> None:
        res = run_editor_js(
            """
            const S = E.Store;
            const J = E.JsonIO;
            S.resetToEmptyDraft({ clearUndo: true });
            S.loadPreset("MSN_RECON_001");
            const presetId = S.getState().mission.missionId;
            S.undo();
            const undoneId = S.getState().mission.missionId;

            S.addCheckpoint("MAC_RECON_ORBIT", { targetPos: { x: 100, z: 100 }, radius: 40 });
            const beforeExpandLen = S.getState().mission.checkpoints.length;
            S.expandSelectedMacro(0);
            const afterExpandLen = S.getState().mission.checkpoints.length;
            S.undo();
            const afterExpandUndoLen = S.getState().mission.checkpoints.length;

            const badLegacyItems = J.importJson(JSON.stringify({ missionId: "OLD", items: [{ type: "FLY_TO" }] }));
            const badLegacyAct = J.importJson(JSON.stringify({ missionId: "OLD2", checkpoints: [{ checkpointId: "C1", action: "FLY_OVER", params: {} }] }));
            const imported = J.importJson(JSON.stringify({
              missionId: "IMP_1",
              version: "1.9.0",
              _missionCustom: 77,
              checkpoints: [{ checkpointId: "C1", action: "ACT_NAV_GOTO_WP", params: { x: 25, z: -30 }, _cpNote: "alpha" }]
            }));
            const afterImportId = S.getState().mission.missionId;
            S.undo();
            const afterImportUndoId = S.getState().mission.missionId;
            return {
              presetId, undoneId,
              beforeExpandLen, afterExpandLen, afterExpandUndoLen,
              badLegacyItems, badLegacyAct, importedOk: imported.ok,
              afterImportId, afterImportUndoId
            };
            """
        )
        self.assertEqual(res["presetId"], "MSN_RECON_001")
        self.assertNotEqual(res["undoneId"], "MSN_RECON_001")
        self.assertEqual(res["beforeExpandLen"], 1)
        self.assertEqual(res["afterExpandLen"], 6)
        self.assertEqual(res["afterExpandUndoLen"], 1)
        self.assertFalse(res["badLegacyItems"]["ok"])
        self.assertEqual(res["badLegacyItems"]["errorCode"], "LEGACY_MISSION_FORMAT")
        self.assertFalse(res["badLegacyAct"]["ok"])
        self.assertEqual(res["badLegacyAct"]["errorCode"], "LEGACY_ACTION_UNSUPPORTED")
        self.assertTrue(res["importedOk"])
        self.assertEqual(res["afterImportId"], "IMP_1")
        self.assertNotEqual(res["afterImportUndoId"], "IMP_1")

    def test_build_export_object_clean_v2_and_autosave_roundtrip(self) -> None:
        res = run_editor_js(
            """
            const S = E.Store;
            const J = E.JsonIO;
            const exported = J.buildExportObject({
              missionId: "EXP_1",
              version: "1.2.0",
              description: "",
              targetAirframe: "FIXED_WING",
              _extra: { _missionMeta: "preserve" },
              checkpoints: [{
                checkpointId: "CP_1",
                action: "ACT_NAV_SPLINE_WP",
                params: { x: 12, z: 34 },
                decorators: [],
                preconditions: {},
                onEnter: [],
                onExit: [],
                onAbort: [],
                _extra: { _stepHint: "fast" }
              }]
            });
            S.resetToEmptyDraft({ clearUndo: true });
            S.addCheckpoint("ACT_NAV_GOTO_WP", { targetPos: { x: 40, z: 50 } });
            S.setUi({ aircraftNumber: 3, targetAirframe: "MULTICOPTER" });
            S.saveAutosave();
            const restored = S.loadAutosave();
            return { exported, restored, rawAutosave: localStorage.getItem("uafs_amm_editor_autosave_v1") };
            """
        )
        exp = res["exported"]
        self.assertEqual(exp["version"], "2.0.0")
        self.assertNotIn("description", exp)
        self.assertNotIn("targetAirframe", exp)
        self.assertEqual(exp["_missionMeta"], "preserve")
        cp = exp["checkpoints"][0]
        self.assertEqual(cp["params"]["targetPos"], {"x": 12, "z": 34})
        self.assertNotIn("decorators", cp)
        self.assertNotIn("preconditions", cp)
        self.assertNotIn("onEnter", cp)
        self.assertEqual(cp["_stepHint"], "fast")
        self.assertIsNotNone(res["rawAutosave"])
        self.assertTrue(res["restored"]["ok"])
        self.assertEqual(S_len := len(res["restored"]["mission"]["checkpoints"]), 1)
        self.assertEqual(res["restored"]["aircraftNumber"], 3)


class TestTask5CanvasAndAltProfile(unittest.TestCase):
    def test_coord_transforms_snap_repeat_loop_and_label_stack(self) -> None:
        res = run_editor_js(
            """
            const C = E.CanvasRenderer;
            const view = { offsetX: 100, offsetZ: -50, zoom: 2.0, width: 800, height: 600 };
            const s = C.worldToScreen(150, 0, view);
            const w = C.screenToWorld(s.sx, s.sy, view);
            const snapped = C.snapCoord(127, 10, true);
            const unsnapped = C.snapCoord(127.4, 10, false);

            const cps = [
              { checkpointId: "SYS_1", action: "ACT_SYS_LOAD", params: {} },
              { checkpointId: "ARM_1", action: "ACT_SYS_ARM", params: {} },
              { checkpointId: "TK_1", action: "ACT_TKL_TAKEOFF_VERT", params: { targetAlt: 150 } },
              { checkpointId: "MOB_1", action: "ACT_MOB_MOVING_TKOFF", params: {} },
              { checkpointId: "WP_1", action: "ACT_NAV_SPLINE_WP", params: { targetPos: { x: 100, z: 100 } } },
              { checkpointId: "WP_2", action: "ACT_NAV_GOTO_WP", params: { targetPos: { x: 300, z: 100 } } }
            ];
            const loopIdx = C.computeRepeatLoopTarget(cps);
            const offsets = C.computeLabelStackOffsets([
              { sx: 200, sy: 200 },
              { sx: 204, sy: 203 },
              { sx: 201, sy: 202 },
              { sx: 450, sy: 200 }
            ], 18, 15);
            return { s, w, snapped, unsnapped, loopIdx, offsets };
            """
        )
        self.assertEqual(res["s"], {"sx": 500, "sy": 400})
        self.assertEqual(res["w"], {"x": 150, "z": 0})
        self.assertEqual(res["snapped"], 130)
        self.assertEqual(res["unsnapped"], 127.4)
        self.assertEqual(res["loopIdx"], 4)
        self.assertEqual(res["offsets"], [0, 15, 30, 0])

    def test_hit_test_selected_node_priority_and_drag_single_undo(self) -> None:
        res = run_editor_js(
            """
            const C = E.CanvasRenderer;
            const S = E.Store;
            const makeMockCanvas = (w, h) => {
              const listeners = {};
              const ctx = {
                save(){}, restore(){}, clearRect(){}, beginPath(){}, moveTo(){}, lineTo(){},
                arc(){}, stroke(){}, fill(){}, fillRect(){}, strokeRect(){}, fillText(){},
                setLineDash(){}, measureText(t){ return { width: (t || "").length * 6 }; },
              };
              return {
                width: w, height: h, clientWidth: w, clientHeight: h, style: {},
                getContext(){ return ctx; },
                getBoundingClientRect(){ return { left: 0, top: 0, width: w, height: h }; },
                addEventListener(type, fn){ (listeners[type] = listeners[type] || []).push(fn); },
                emit(type, ev){ for (const fn of listeners[type] || []) fn(ev); },
              };
            };

            S.resetToEmptyDraft({ clearUndo: true });
            S.addCheckpoint("ACT_PAT_POI_HOLD", { targetPos: { x: 0, z: 0 }, poiPos: { x: 0, z: 0 }, targetAlt: 150 });
            S.addCheckpoint("ACT_NAV_CORRIDOR", { startPos: { x: 200, z: 0 }, endPos: { x: 300, z: 0 }, targetAlt: 160 });
            S.selectCheckpoint(0);

            const view = { offsetX: 0, offsetZ: 0, zoom: 1.0, width: 800, height: 600 };
            // Co-located targetPos & poiPos at (0,0) -> (400, 300): selected node 0 should prioritize POI handle or CP handle deterministically
            const hit0 = C.hitTestCanvas(S.getState().mission.checkpoints, 400, 300, view, 0);
            const hitCorrEnd = C.hitTestCanvas(S.getState().mission.checkpoints, 700, 300, view, 1);

            const mapCanvas = makeMockCanvas(800, 600);
            const altCanvas = makeMockCanvas(800, 120);
            C.attach(mapCanvas, altCanvas);

            const undoBeforeDrag = S.getState().undoStack.length;
            // Drag CP#1 corridor end from world (300, 0) -> screen (700, 300) to screen (750, 340) -> world (350, 40)
            mapCanvas.emit("mousedown", { clientX: 700, clientY: 300, button: 0, altKey: false });
            for (let i = 1; i <= 10; i++) {
              mapCanvas.emit("mousemove", { clientX: 700 + i * 5, clientY: 300 + i * 4, altKey: false });
            }
            mapCanvas.emit("mouseup", { clientX: 750, clientY: 340, button: 0 });
            const undoAfterMapDrag = S.getState().undoStack.length;
            const endAfterDrag = E.deepClone(S.getState().mission.checkpoints[1].params.endPos);

            // Alt profile drag: click & drag CP#0 (first CP at x ~ left margin) upward to raise targetAlt
            altCanvas.emit("mousedown", { clientX: C.getAltPointScreen(0, 800, 120).sx, clientY: C.getAltPointScreen(0, 800, 120).sy, button: 0, altKey: true });
            for (let i = 1; i <= 10; i++) {
              altCanvas.emit("mousemove", { clientX: C.getAltPointScreen(0, 800, 120).sx, clientY: C.getAltPointScreen(0, 800, 120).sy - i * 2, altKey: true });
            }
            altCanvas.emit("mouseup", { clientX: C.getAltPointScreen(0, 800, 120).sx, clientY: C.getAltPointScreen(0, 800, 120).sy - 20, button: 0, altKey: true });
            const undoAfterAltDrag = S.getState().undoStack.length;
            const altAfterDrag = S.getState().mission.checkpoints[0].params.targetAlt;
            S.undo();
            const altAfterUndo = S.getState().mission.checkpoints[0].params.targetAlt;

            return {
              hit0, hitCorrEnd,
              undoBeforeDrag, undoAfterMapDrag, endAfterDrag,
              undoAfterAltDrag, altAfterDrag, altAfterUndo
            };
            """
        )
        self.assertEqual(res["hit0"]["index"], 0)
        self.assertEqual(res["hitCorrEnd"]["kind"], "CORRIDOR_END")
        self.assertEqual(res["hitCorrEnd"]["index"], 1)
        self.assertEqual(res["undoAfterMapDrag"] - res["undoBeforeDrag"], 1)
        self.assertEqual(res["endAfterDrag"], {"x": 350, "z": 40})
        self.assertEqual(res["undoAfterAltDrag"] - res["undoAfterMapDrag"], 1)
        self.assertGreater(res["altAfterDrag"], 150)
        self.assertEqual(res["altAfterUndo"], 150)


class TestTask6UIAndAccessibility(unittest.TestCase):
    def test_css_guidelines_no_innerhtml_no_div_onclick_and_responsive(self) -> None:
        html = EDITOR_HTML.read_text(encoding="utf-8")
        self.assertIn("@media (max-width: 1150px)", html)
        self.assertIn("prefers-reduced-motion", html)
        self.assertIn("overscroll-behavior: contain", html)
        self.assertIn("overscroll-behavior: none", html)
        self.assertIn("user-select: none", html)
        self.assertIn(":focus-visible", html)
        self.assertIn("min-width: 0", html)
        self.assertNotIn("transition: all", html)
        self.assertNotRegex(html, r"<div[^>]*\bonclick=")
        script_body = extract_inline_script()
        self.assertNotIn("innerHTML", script_body)
        self.assertNotIn("insertAdjacentHTML", script_body)
        self.assertNotIn("outerHTML", script_body)
        self.assertNotIn("window.alert", script_body)
        self.assertNotIn("window.confirm", script_body)
        self.assertNotIn("window.prompt", script_body)

    def test_dom_shim_xss_safe_rendering_field_focus_picker_and_empty_cta(self) -> None:
        dom_setup = """
        const byId = Object.create(null);
        function makeEl(tag, id) {
          const listeners = {};
          let _text = "";
          const el = {
            tagName: String(tag || "DIV").toUpperCase(),
            id: id || "",
            className: "",
            type: "",
            value: "",
            checked: false,
            disabled: false,
            hidden: false,
            dataset: {},
            style: {},
            children: [],
            attributes: {},
            classList: {
              add(...c){}, remove(...c){}, toggle(c, force){}, contains(){ return false; }
            },
            focused: false,
            focus(){ el.focused = true; document.activeElement = el; },
            select(){},
            setAttribute(k, v){
              el.attributes[k] = String(v);
              if (k === "data-field-path") el.dataset.fieldPath = String(v);
            },
            getAttribute(k){ return Object.prototype.hasOwnProperty.call(el.attributes, k) ? el.attributes[k] : null; },
            appendChild(child){ el.children.push(child); return child; },
            removeChild(child){ const i = el.children.indexOf(child); if (i >= 0) el.children.splice(i, 1); },
            addEventListener(type, fn){ (listeners[type] = listeners[type] || []).push(fn); },
            click(){ el.emit("click", { target: el, currentTarget: el, preventDefault(){} }); },
            emit(type, ev){ for (const fn of listeners[type] || []) fn(ev || { target: el, currentTarget: el, preventDefault(){} }); },
            querySelector(sel){
              const m = sel.match(/^\\[data-field-path="([^"]+)"\\]$/);
              if (m) {
                const want = m[1];
                const stack = [el];
                while (stack.length) {
                  const cur = stack.shift();
                  if (cur.attributes && cur.attributes["data-field-path"] === want) return cur;
                  if (cur.children) stack.push(...cur.children);
                }
              }
              return null;
            },
            querySelectorAll(){ return []; },
            get textContent(){ return _text + (el.children || []).map((c) => c.textContent || "").join(""); },
            set textContent(v){ _text = String(v == null ? "" : v); if (v === "") el.children = []; },
            get innerHTML(){ throw new Error("innerHTML access forbidden"); },
            set innerHTML(v){ throw new Error("innerHTML assignment forbidden"); },
            getContext(){ return null; },
            getBoundingClientRect(){ return { left: 0, top: 0, width: 800, height: 600 }; },
          };
          if (id) byId[id] = el;
          return el;
        }
        const ids = [
          "missionIdInput", "execModeSingle", "execModeRepeat", "btnUndo", "btnRedo",
          "presetSelect", "btnImportJson", "fileImportInput", "btnRawJson", "btnCopyJson", "btnExportJson",
          "toastBanner", "cpCountBadge", "btnOpenAddPicker", "btnOpenMacroPicker", "actionPickerPopover",
          "pickerSearch", "pickerDomainTabs", "pickerList", "cpList", "emptyCanvasCta", "btnEmptyPreset",
          "btnEmptyAdd", "missionCanvas", "btnToggleSnap", "btnFitView", "btnToggleAltProfile",
          "zoomReadout", "altProfilePane", "altProfileCanvas", "modeCheckpointBtn", "modeSettingsBtn",
          "inspectorBody", "rawJsonDrawer", "rawJsonTextarea", "btnApplyJson", "btnFormatJson",
          "btnCloseRawJson", "validationBar", "validationSummary", "btnToggleValidation",
          "valFilterAll", "valFilterErrors", "valFilterWarnings", "validationList"
        ];
        for (const id of ids) makeEl("div", id);
        document.getElementById = (id) => byId[id] || null;
        document.createElement = (tag) => makeEl(tag, "");
        document.querySelector = (sel) => {
          for (const root of Object.values(byId)) {
            const found = root.querySelector(sel);
            if (found) return found;
          }
          return null;
        };
        """
        res = run_editor_js(
            """
            const S = E.Store;
            const I = E.InspectorUI;
            // Empty state CTA visibility
            S.resetToEmptyDraft({ clearUndo: true });
            const emptyVisible = !byId.emptyCanvasCta.hidden;

            // XSS payload safety: missionId & hook message with <img src=x onerror=alert(1)>
            const xss = '<img src=x onerror="alert(1)">';
            S.addCheckpoint("ACT_SYS_ARM", {});
            S.mutateMission((m) => {
              m.missionId = xss;
              m.checkpoints[0].checkpointId = xss;
              m.checkpoints[0].onEnter = [{ type: "NOTIFY_OPERATOR", message: xss }];
            });
            I.renderAll();

            // Action picker search & Macro Expand Now
            E.AppBootstrap.openActionPicker("MAC");
            byId.pickerSearch.value = "RECON";
            byId.pickerSearch.emit("input", { target: byId.pickerSearch });
            const pickerCount = byId.pickerList.children.length;
            S.addCheckpoint("MAC_RECON_ORBIT", { targetPos: { x: 50, z: 50 }, radius: 40 });
            const lenBeforeExpand = S.getState().mission.checkpoints.length;
            S.expandSelectedMacro(S.getState().ui.selectedIndex);
            const lenAfterExpand = S.getState().mission.checkpoints.length;

            // Clicking / focusing issue with fieldPath auto-switches Inspector mode/tab & focuses field
            const focused = I.activateValidationIssue({
              level: "ERROR",
              code: "INVALID_HOOK_PARAM",
              seq: 1,
              fieldPath: "checkpoints[0].onEnter[0].message"
            });

            return {
              emptyVisible,
              cpListText: byId.cpList.textContent,
              pickerCount,
              lenBeforeExpand,
              lenAfterExpand,
              rightMode: S.getState().ui.rightMode,
              rightTab: S.getState().ui.rightTab,
              selectedIndex: S.getState().ui.selectedIndex,
              focusedActivePath: document.activeElement && document.activeElement.attributes && document.activeElement.attributes["data-field-path"],
              focusedResult: focused,
            };
            """,
            dom_setup=dom_setup,
        )
        self.assertTrue(res["emptyVisible"])
        self.assertIn('<img src=x onerror="alert(1)">', res["cpListText"])
        self.assertGreaterEqual(res["pickerCount"], 1)
        self.assertEqual(res["lenBeforeExpand"], 2)
        self.assertEqual(res["lenAfterExpand"], 7)
        self.assertEqual(res["rightMode"], "CHECKPOINT")
        self.assertEqual(res["rightTab"], "HOOKS")
        self.assertEqual(res["selectedIndex"], 0)
        self.assertEqual(res["focusedActivePath"], "checkpoints[0].onEnter[0].message")


class TestTask7CraftOSRoundtrip(unittest.TestCase):
    def test_craftos_mission_engine_roundtrip(self) -> None:
        from harness.unit.config import resolve_craftos_paths
        from harness.unit.session import EphemeralCraftOSSession

        js_payload = run_editor_js(
            """
            const J = E.JsonIO;
            const S = E.Store;
            const presets = J.PRESETS.map((k) => J.buildExportObject(J.getPreset(k)));

            // Build mission exercising all 36 active ACT_*, 6 DEC_*, 19 preconditions, hooks, conditions
            const all36 = Object.keys(E.SchemaConstants.ACTIVE_ACTIONS).map((act, idx) => {
              const p = E.MacroExpander.cleanActionSwitchParams({ targetPos: { x: idx * 20, z: 50 }, targetAlt: 140 }, act);
              if (act === "ACT_PAT_LOITER_TIME") p.durationSec = 30;
              const cp = { checkpointId: "CP36_" + idx, action: act, params: p };
              if (idx === 0) {
                cp.decorators = E.SchemaConstants.ACTIVE_DECORATORS.map((d) => {
                  if (d === "DEC_RETRY_N") return { decoratorId: d, overrideParams: { maxAttempts: 3 } };
                  if (d === "DEC_TIMEOUT_GUARD") return { decoratorId: d, overrideParams: { timeoutSec: 45 } };
                  return { decoratorId: d };
                });
                cp.preconditions = {
                  controlState: "IDLE_ARMED", activeSource: "AMM", fsmState: ["CRUISE", "LOITER"],
                  allowedAirframes: ["WINGED_VTOL"], disallowedAirframes: ["FIXED_WING"],
                  sensorOk: true, gpsValid: true, maxHdop: 2.5, requireTap: true, requireAsa: true, requireGimbal: false,
                  minFuel: 0.2, channelBound: true, atcCleared: false, zone3Available: true,
                  geofenceMarginM: 15, minAlt: 40, maxAlt: 300, maxSpeed: 30
                };
                cp.onEnter = [{ type: "NOTIFY_OPERATOR", level: "INFO", message: "Roundtrip Enter" }];
                cp.completeWhen = { logic: "ALL", conditions: [{ type: "IMMEDIATE" }] };
                cp.abortWhen = { logic: "ANY", conditions: [{ type: "TIMEOUT_SEC", timeout: 45 }] };
              }
              return cp;
            });
            const m36 = J.buildExportObject({
              missionId: "RT_ALL_36",
              executionMode: "SINGLE",
              fallbackPolicy: "RTH",
              checkpoints: all36,
            });
            const m36Valid = E.Validator.validateMission(m36).valid;

            // Expanded macros
            const expandedMacros = [];
            for (const mac of E.SchemaConstants.ACTIVE_MACROS) {
              const steps = E.MacroExpander.expandMacroCheckpoint({
                checkpointId: mac,
                action: mac,
                params: { targetPos: { x: 100, z: 100 }, targetAlt: 150, facilityId: "PAD_1", radius: 40, durationSec: 30, channelOffset: 20, command: "DROP" }
              }, "WINGED_VTOL");
              expandedMacros.push(J.buildExportObject({
                missionId: "RT_" + mac,
                checkpoints: steps
              }));
            }

            const deferredCase = J.buildExportObject({
              missionId: "RT_DEFERRED",
              checkpoints: [{ checkpointId: "D1", action: "ACT_TKL_TAKEOFF_RWY", params: {} }]
            });
            const legacyCase = {
              missionId: "RT_LEGACY",
              version: "2.0.0",
              checkpoints: [{ checkpointId: "L1", action: "FLY_OVER", params: {} }]
            };

            return { presets, m36, m36Valid, expandedMacros, deferredCase, legacyCase };
            """
        )

        self.assertTrue(js_payload["m36Valid"])
        craftos_paths = resolve_craftos_paths()
        sessions_root = WORKSPACE_ROOT / ".runtime" / "sessions"
        cases = {
            "presets": js_payload["presets"],
            "m36": js_payload["m36"],
            "expandedMacros": js_payload["expandedMacros"],
            "deferredCase": js_payload["deferredCase"],
            "legacyCase": js_payload["legacyCase"],
        }

        lua_startup = """
package.path = "/?.lua;/modules/?.lua;" .. package.path
local mission_engine = require("mission_engine")

local f = fs.open("/cases.json", "r")
local raw = f.readAll()
f.close()
local cases = textutils.unserialiseJSON(raw)

local results = { presets = {}, m36 = nil, expandedMacros = {}, deferred = nil, legacy = nil }

for _, m in ipairs(cases.presets) do
  local ok, res = mission_engine.validate_mission(m, { baseChannel = 10000 })
  table.insert(results.presets, { id = m.missionId, ok = ok == true, err = type(res) == "table" and res.error or tostring(res) })
end

local ok36, res36 = mission_engine.validate_mission(cases.m36, { baseChannel = 10000 })
results.m36 = { ok = ok36 == true, err = type(res36) == "table" and res36.error or tostring(res36) }

for _, m in ipairs(cases.expandedMacros) do
  local okM, resM = mission_engine.validate_mission(m, { baseChannel = 10000 })
  table.insert(results.expandedMacros, { id = m.missionId, ok = okM == true, err = type(resM) == "table" and resM.error or tostring(resM) })
end

local okD, resD = mission_engine.validate_mission(cases.deferredCase, { baseChannel = 10000 })
results.deferred = { ok = okD == true, err = type(resD) == "table" and resD.error or tostring(resD) }

local okL, resL = mission_engine.validate_mission(cases.legacyCase, { baseChannel = 10000 })
results.legacy = { ok = okL == true, err = type(resL) == "table" and resL.error or tostring(resL) }

fs.makeDir("/_harness_out")
local out = fs.open("/_harness_out/result.json", "w")
out.write(textutils.serialiseJSON(results))
out.close()
local flag = fs.open("/_harness_out/done.flag", "w")
flag.write("done")
flag.close()
os.shutdown()
"""
        with EphemeralCraftOSSession(sessions_root, craftos_paths, prefix="amm_editor_rt") as sess:
            sess.stage_tree(WORKSPACE_ROOT / "src" / "3_planning" / "amm", computer_id=0)
            c0 = sess.computer_dir(0)
            (c0 / "cases.json").write_text(json.dumps(cases), encoding="utf-8")
            (c0 / "startup.lua").write_text(lua_startup, encoding="utf-8")
            run_res = sess.run(mode="headless", timeout_sec=10.0)
            self.assertFalse(run_res.timed_out, f"CraftOS-PC timed out: {run_res.stderr_raw}")
            res_file = c0 / "_harness_out" / "result.json"
            self.assertTrue(res_file.is_file(), f"Missing CraftOS output. stdout={run_res.stdout_raw} stderr={run_res.stderr_raw}")
            lua_out = json.loads(res_file.read_text(encoding="utf-8"))

        for p in lua_out["presets"]:
            self.assertTrue(p["ok"], f"Preset failed Lua validate_mission: {p}")
        self.assertTrue(lua_out["m36"]["ok"], f"All-36 mission failed Lua validate_mission: {lua_out['m36']}")
        for m in lua_out["expandedMacros"]:
            self.assertTrue(m["ok"], f"Expanded macro failed Lua validate_mission: {m}")
        self.assertFalse(lua_out["deferred"]["ok"])
        self.assertEqual(lua_out["deferred"]["err"], "DEFERRED_ACTION_UNSUPPORTED")
        self.assertFalse(lua_out["legacy"]["ok"])
        self.assertEqual(lua_out["legacy"]["err"], "SCHEMA_INVALID")


class TestOperabilityRegressions(unittest.TestCase):
    def test_css_hidden_precedence_and_responsive_layout_invariants(self) -> None:
        html = EDITOR_HTML.read_text(encoding="utf-8")
        self.assertRegex(
            html,
            r"\[hidden\]\s*\{\s*display:\s*none\s*!important;\s*\}",
            "Global [hidden] { display: none !important; } is required so flex/grid panels respect [hidden]",
        )
        self.assertRegex(
            html,
            r"\.toast-banner\s*\{[^}]*position:\s*fixed;",
            "Toast banner must be out of .top-header flex flow so showing toasts never clips header buttons",
        )
        self.assertRegex(
            html,
            r"\.top-header\s*>\s*\.(?:segmented|brand-pill)[^}]*flex-shrink:\s*0",
            "Header buttons and segmented toggle must not shrink and clip REPEAT",
        )
        media_match = re.search(r"@media\s*\(max-width:\s*1150px\)\s*\{([\s\S]*?)\n\s*\}", html)
        self.assertIsNotNone(media_match, "@media (max-width: 1150px) block must exist")
        media_block = media_match.group(1)
        self.assertIn("overflow: hidden", media_block)
        self.assertRegex(media_block, r"#centerColumn\s*\{[^}]*flex:\s*0\s+0")

    def test_copy_json_fallback_when_clipboard_rejects(self) -> None:
        node = shutil.which("node")
        self.assertIsNotNone(node)
        script_body = extract_inline_script()
        async_harness = f"""
const __storage = Object.create(null);
const localStorage = {{
  getItem(k) {{ return Object.prototype.hasOwnProperty.call(__storage, k) ? __storage[k] : null; }},
  setItem(k, v) {{ __storage[k] = String(v); }},
  removeItem(k) {{ delete __storage[k]; }},
}};
let execCopyResult = true;
let execCopyCalls = 0;
let copiedText = "";
const byId = Object.create(null);
function makeEl(tag, id) {{
  const listeners = {{}};
  let _text = "";
  const el = {{
    tagName: String(tag || "DIV").toUpperCase(),
    id: id || "",
    className: "",
    type: "",
    value: "",
    checked: false,
    disabled: false,
    hidden: id === "toastBanner" || id === "rawJsonDrawer" || id === "actionPickerPopover" || id === "altProfilePane" || id === "validationList",
    dataset: {{}},
    style: {{}},
    children: [],
    attributes: {{}},
    classList: {{ add(){{}}, remove(){{}}, toggle(){{}}, contains(){{ return false; }} }},
    focus(){{ document.activeElement = el; }},
    select(){{ copiedText = el.value; }},
    setSelectionRange(){{}},
    setAttribute(k, v){{ el.attributes[k] = String(v); }},
    getAttribute(k){{ return Object.prototype.hasOwnProperty.call(el.attributes, k) ? el.attributes[k] : null; }},
    appendChild(child){{ el.children.push(child); return child; }},
    removeChild(child){{ const i = el.children.indexOf(child); if (i >= 0) el.children.splice(i, 1); }},
    addEventListener(type, fn){{ (listeners[type] = listeners[type] || []).push(fn); }},
    click(){{ for (const fn of listeners.click || []) fn({{ target: el, currentTarget: el, preventDefault(){{}} }}); }},
    querySelector(){{ return null; }},
    querySelectorAll(){{ return []; }},
    get textContent(){{ return _text + (el.children || []).map((c) => c.textContent || "").join(""); }},
    set textContent(v){{ _text = String(v == null ? "" : v); if (v === "") el.children = []; }},
    getContext(){{ return null; }},
    getBoundingClientRect(){{ return {{ left: 0, top: 0, width: 800, height: 600 }}; }},
  }};
  if (id) byId[id] = el;
  return el;
}}
const ids = [
  "missionIdInput", "execModeSingle", "execModeRepeat", "btnUndo", "btnRedo",
  "presetSelect", "fileImportInput", "btnImportJson", "btnRawJson", "btnCopyJson", "btnExportJson",
  "toastBanner", "btnOpenAddPicker", "btnOpenMacroPicker", "cpList", "actionPickerPopover",
  "pickerSearch", "btnClosePicker", "pickerDomainTabs", "pickerList", "btnToggleSnap", "btnFitView",
  "btnToggleAltProfile", "altProfilePane", "altProfileCanvas", "emptyCanvasCta", "btnEmptyPreset",
  "btnEmptyAdd", "missionCanvas", "modeCheckpointBtn", "modeSettingsBtn", "inspectorBody",
  "rawJsonDrawer", "btnFormatJson", "btnApplyJson", "btnCloseRawJson", "rawJsonTextarea",
  "validationBar", "validationSummary", "valFilterAll", "valFilterErrors", "valFilterWarnings",
  "btnToggleValidation", "validationList"
];
for (const id of ids) makeEl("DIV", id);
const navigator = {{ clipboard: {{ writeText() {{ return Promise.reject(new Error("NotAllowedError")); }} }} }};
const window = {{ devicePixelRatio: 1, addEventListener(){{}}, removeEventListener(){{}}, requestAnimationFrame(){{ return 0; }} }};
const document = {{
  body: makeEl("BODY"),
  activeElement: null,
  addEventListener(){{}},
  removeEventListener(){{}},
  getElementById(id){{ return byId[id] || null; }},
  querySelector(){{ return null; }},
  querySelectorAll(){{ return []; }},
  createElement(tag){{ return makeEl(tag); }},
  execCommand(cmd){{ if (cmd === "copy") {{ execCopyCalls += 1; return execCopyResult; }} return false; }},
}};
{script_body}
(async () => {{
  const E = window.__AMM_EDITOR__;
  E.AppBootstrap.init();
  byId.btnCopyJson.click();
  await new Promise((r) => setTimeout(r, 30));
  const fallbackSuccess = {{
    execCopyCalls,
    toastHidden: byId.toastBanner.hidden,
    toastText: byId.toastBanner.textContent,
    hasMissionJson: copiedText.includes('"version": "2.0.0"') && copiedText.includes('"checkpoints"'),
  }};
  execCopyResult = false;
  byId.toastBanner.hidden = true;
  byId.toastBanner.textContent = "";
  byId.btnCopyJson.click();
  await new Promise((r) => setTimeout(r, 30));
  const totalFailureFallback = {{
    rawDrawerOpen: byId.rawJsonDrawer.hidden === false,
    toastHidden: byId.toastBanner.hidden,
    toastText: byId.toastBanner.textContent,
  }};
  console.log(JSON.stringify({{ fallbackSuccess, totalFailureFallback }}));
}})();
"""
        res = subprocess.run(
            [node, "-"],
            input=async_harness,
            capture_output=True,
            text=True,
            encoding="utf-8",
            cwd=str(WORKSPACE_ROOT),
            timeout=30,
        )
        self.assertEqual(res.returncode, 0, f"Node failed: {res.stderr}")
        out = json.loads(res.stdout.splitlines()[-1])
        self.assertEqual(out["fallbackSuccess"]["execCopyCalls"], 1)
        self.assertFalse(out["fallbackSuccess"]["toastHidden"])
        self.assertTrue(out["fallbackSuccess"]["hasMissionJson"])
        self.assertTrue(out["totalFailureFallback"]["rawDrawerOpen"])
        self.assertFalse(out["totalFailureFallback"]["toastHidden"])

    def test_snap_toggle_updates_visual_css_aria_and_label(self) -> None:
        html = EDITOR_HTML.read_text(encoding="utf-8")
        self.assertRegex(
            html,
            r"(?m)^\s*button\[aria-pressed=\"true\"\]",
            "Standalone toggle buttons like #btnToggleSnap require non-segmented button[aria-pressed=\"true\"] active CSS",
        )
        self.assertRegex(
            html,
            r"button\[aria-expanded=\"true\"\]",
            "Expandable toggle buttons require button[aria-expanded=\"true\"] active CSS",
        )

        dom_setup = """
        const byId = Object.create(null);
        function makeEl(tag, id) {
          const listeners = {};
          let _text = "";
          const el = {
            tagName: String(tag || "DIV").toUpperCase(),
            id: id || "",
            className: "",
            type: "",
            title: "",
            value: "",
            hidden: false,
            children: [],
            attributes: {},
            style: {},
            classList: { add(){}, remove(){}, toggle(){} },
            focus(){},
            setAttribute(k, v){ el.attributes[k] = String(v); },
            getAttribute(k){ return Object.prototype.hasOwnProperty.call(el.attributes, k) ? el.attributes[k] : null; },
            appendChild(c){ el.children.push(c); return c; },
            addEventListener(type, fn){ (listeners[type] = listeners[type] || []).push(fn); },
            click(){ for (const fn of listeners.click || []) fn({ target: el, currentTarget: el, preventDefault(){} }); },
            querySelector(){ return null; },
            querySelectorAll(){ return []; },
            get textContent(){ return _text; },
            set textContent(v){ _text = String(v == null ? "" : v); },
            getContext(){ return null; },
            getBoundingClientRect(){ return { left: 0, top: 0, width: 800, height: 600 }; },
          };
          if (id) byId[id] = el;
          return el;
        }
        [
          "missionIdInput", "execModeSingle", "execModeRepeat", "btnUndo", "btnRedo",
          "presetSelect", "fileImportInput", "btnImportJson", "btnRawJson", "btnCopyJson", "btnExportJson",
          "toastBanner", "btnOpenAddPicker", "btnOpenMacroPicker", "cpList", "actionPickerPopover",
          "pickerSearch", "btnClosePicker", "pickerDomainTabs", "pickerList", "btnToggleSnap", "btnFitView",
          "btnToggleAltProfile", "altProfilePane", "altProfileCanvas", "emptyCanvasCta", "btnEmptyPreset",
          "btnEmptyAdd", "missionCanvas", "modeCheckpointBtn", "modeSettingsBtn", "inspectorBody",
          "rawJsonDrawer", "btnFormatJson", "btnApplyJson", "btnCloseRawJson", "rawJsonTextarea",
          "validationBar", "validationSummary", "valFilterAll", "valFilterErrors", "valFilterWarnings",
          "btnToggleValidation", "validationList"
        ].forEach((id) => makeEl("DIV", id));
        document.getElementById = (id) => byId[id] || null;
        document.createElement = (tag) => makeEl(tag);
        """
        out = run_editor_js(
            """
            const snapBtn = document.getElementById("btnToggleSnap");
            const init = {
              gridSnap: E.Store.getState().ui.gridSnap,
              pressed: snapBtn.getAttribute("aria-pressed"),
              text: snapBtn.textContent,
            };
            snapBtn.click();
            const afterOff = {
              gridSnap: E.Store.getState().ui.gridSnap,
              pressed: snapBtn.getAttribute("aria-pressed"),
              text: snapBtn.textContent,
            };
            snapBtn.click();
            const afterOn = {
              gridSnap: E.Store.getState().ui.gridSnap,
              pressed: snapBtn.getAttribute("aria-pressed"),
              text: snapBtn.textContent,
            };
            return { init, afterOff, afterOn };
            """,
            dom_setup=dom_setup,
        )
        self.assertEqual(out["init"], {"gridSnap": True, "pressed": "true", "text": "Snap 10m"})
        self.assertEqual(out["afterOff"], {"gridSnap": False, "pressed": "false", "text": "Snap Off"})
        self.assertEqual(out["afterOn"], {"gridSnap": True, "pressed": "true", "text": "Snap 10m"})


if __name__ == "__main__":
    unittest.main()
