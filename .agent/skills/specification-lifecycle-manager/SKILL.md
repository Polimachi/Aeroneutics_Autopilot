---
name: specification-lifecycle-manager
description: >-
  Use whenever a request creates, modifies, refactors, deprecates, or audits system specifications,
  Interface Control Documents (ICDs), architecture/sequence diagrams, or protocol schemas—including
  mixed requests that combine specification changes with production codebase edits. Do NOT use when
  the task exclusively involves source code implementation, bug fixing, unit testing, or build/deployment
  configs without modifying any specification document.
---

# Specification Lifecycle & Cross-Sync Manager

Enforces Single Source of Truth (SSOT) integrity, bidirectional cross-document synchronization, and Zero-Fallback deprecation discipline across system specifications without interfering with normal codebase development.

---

## 1. Scope Dispatch & Pre-Execution Gates (EVALUATE FIRST)

Before modifying ANY file, classify the user's request into one of the three cases below and follow its gate strictly:

| Request Type | Condition | Mandatory Action |
| :--- | :--- | :--- |
| **Case A: Codebase-Only** | Request modifies ONLY source code, tests, scripts, or build configs; NO spec/ICD/diagram edits requested. | **EXIT SKILL IMMEDIATELY (No-op).** Apply none of the rules below. Write full production code normally. |
| **Case B: Spec-Only** | Request creates, modifies, deprecates, or audits ONLY specification documents (`docs/system/*.md`, `docs/specs/**/*.md`). | **PROCEED TO SECTION 2.** Enforce full SSOT synchronization. Do NOT modify production source code files. |
| **Case C: Mixed-Scope (Spec + Codebase)** | Request asks to modify specification documents AND production source code/tests in the same task. | **TRIGGER MIXED-SCOPE SAFETY INTERLOCK (Section 1.1).** Halt all file writes immediately, warn the user, and request explicit direction. |

### 1.1 Mixed-Scope Safety Interlock (Hard Stop)

Coupling specification mutations with runtime code edits in a single unreviewed pass risks implementing unverified schemas or propagating architectural conflicts into production code.

**When Case C is detected:**
1. **STOP BEFORE ANY WRITES**: Do NOT call file-creation or file-editing tools on EITHER specification files OR source code files. (Brief read-only inspection to identify affected files is permitted.)
2. **EMIT EXPLICIT WARNING**: Inform the user clearly that the request combines **Specification/ICD Lifecycle Modifications** with **Production Codebase Modifications**.
3. **REQUEST USER DECISION**: Ask the user how to proceed (using the `ask_question` tool if available, or structured plain-text options):
   - **Option 1 — Spec-First Only (Recommended)**: Update and synchronize all affected specifications first, output the Spec-to-Code Impact Report, and stop before touching production code.
   - **Option 2 — Sequential Two-Phase Execution**: Execute Phase 1 (full specification update, 6-domain cross-verification, and Conflict Safety Gate check) first, then immediately proceed to Phase 2 (codebase implementation strictly matching the newly synchronized specs, provided no spec conflicts arise).
   - **Option 3 — Codebase-Only (Skip Spec Changes)**: Leave all specification documents untouched and apply changes only to the codebase.

> **ANTI-RATIONALIZATION RULE**:
> - NEVER bypass this warning because *"the change is just renaming one field"* or *"the user explicitly asked for both in their prompt."* An explicit request to edit both spec and code IS the exact trigger for this warning.
> - **Continuation Exception**: Only bypass this warning when the user is directly replying to confirm an option from a Mixed-Scope Warning you raised in the immediately preceding turn.

---

## 2. Specification Maintenance Protocols

Execute all protocols below whenever editing or auditing specifications (Case B, or Phase 1 of user-approved Option 2).

### 2.1 Code Boundaries Inside Specifications
- Inside specification markdown files, restrict code blocks strictly to **packet/message envelopes, data structure schemas, enums/constants, interface signatures, and core algorithm pseudocode**.
- Never embed full runtime module implementations inside specification documents.

### 2.2 SSOT Hierarchy & Bidirectional Synchronization
Maintain strict consistency across the three specification tiers in `Create_Aeroneutics`:
1. **Tier 1 — Master ICD**: `docs/system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md` - System-wide interfaces, shared message envelopes, and cross-node contracts.
2. **Tier 2 — System Architecture & Relation Diagrams**: `docs/system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md` - Global node topology, Mermaid sequence/state diagrams, and channel/port/endpoint allocation maps.
3. **Tier 3 — Subsystem / Component Specifications**: `docs/specs/{approved,implemented}/**/*.md` - Component-internal FSMs, mathematical control laws, module responsibilities, and local timeouts.

**Bidirectional Rule**: Modifying ANY tier requires scanning all specifications in `docs/system/` and `docs/specs/` and automatically synchronizing every affected peer document in the same turn.

### 2.3 Zero-Fallback & Explicit Deprecation Policy (`Sender-Immediate-Patch`)
1. **Explicit `[DEPRECATED]` Retention**: When renaming or retiring a message type, API endpoint, payload field, or enum value, do NOT silently delete the legacy identifier from specifications. Retain it inline with a `[DEPRECATED]` badge, naming the exact replacement and reason:
   ```markdown
   | Field | Type | Range / Unit | Description |
   | :--- | :---: | :---: | :--- |
   | `padId` | string | Non-empty ID | Target landing pad identifier (Standard) |
   | `runwayId` `[DEPRECATED]` | string | Non-empty ID | Replaced by `padId`. Zero-Fallback applies. |
   ```
2. **Zero-Fallback Mandate**: Specify single-key parsing of the latest standard identifier ONLY. Never specify or permit dual-key fallback wrappers (e.g., `payload.newKey or payload.oldKey`, `data.padId or data.runwayId`) in specifications or downstream receiver code.
3. **Sender-Immediate-Patch Rule**: Specify that runtime deserialization or `nil`/null errors caused by legacy payloads must be fixed by immediately patching and redeploying the outdated **sender** component—never by adding legacy fallback shims to receivers.

### 2.4 Six-Domain Cross-Verification Checklist
Verify alignment across all modified and peer specifications on all six dimensions:
1. **Protocol & Schemas**: Top-level message envelope fields (`ver`, `domainId`, `seq`, `type`, `time`, `payload`), exact message/event `type` string constants, payload key names, data types, and nesting structure.
2. **Channels, Ports & Addressing**: Shared infrastructure channels/topics (`30004`~`30007`), base channel offset formulas (`Base = 10000 + N*20`), node/service IDs, and physical/logical port bindings.
3. **Physical Units, Coordinates & Conventions**: Reference coordinate frames (NED), sign conventions (pitch nose-up +, roll right-bank +, yaw clockwise from North), physical units (`m/s`, `deg/s`, `blocks`, etc.), and actuator signal bounds (0~15).
4. **Metadata, Versioning & Cross-Links**:
   - Bump **Semantic Version (`vX.Y.Z`)** on every modified spec:
     - `Patch (+0.0.1)`: Cross-sync alignment, wording clarifications, typo fixes, or `[DEPRECATED]` badge formatting.
     - `Minor (+0.1.0)`: New/renamed packets, added payload fields, FSM state additions, or non-breaking interface extensions.
     - `Major (+1.0.0)`: Breaking top-level envelope changes or fundamental architectural restructuring.
   - Update `Last Updated` / modification date to the current date (`YYYY-MM-DD`).
   - Update cross-referenced document version badges and verify all relative markdown links (`../system/...`, `../specs/...`) and section anchors.
5. **FSM & Algorithmic Parameters**: Exact FSM state identifiers, state transition conditions, control loop frequencies (20Hz / 50ms), watchdog timeouts, filter coefficients, and safety thresholds.
6. **Deprecation Hygiene**: Consistent `[DEPRECATED]` badges across Master ICD, diagrams, and subsystem specs, with zero dual-key fallback logic.

### 2.5 Conflict Safety Gate (Architectural Contradiction Stop)
Distinguish between **routine synchronization** (updating peer specs to reflect an intentional interface change) and **design conflicts** (incompatible mathematical equations, contradictory control authority hierarchies, or mutually exclusive safety invariants across documents).

- **If a design conflict is detected**:
  1. **STOP IMMEDIATELY**. Do NOT overwrite peer documents by guessing architectural intent.
  2. Report the exact conflicting files, sections, and underlying contradiction to the user.
  3. Wait for explicit user resolution before applying edits.

---

## 3. Execution Workflow & Required Output

```mermaid
flowchart TD
    Start["Request Received"] --> Gate{"Classify Scope"}
    Gate -- "Codebase-Only" --> Exit["Exit Skill (Normal Coding)"]
    Gate -- "Mixed (Spec + Code)" --> Warn["HALT: Emit Mixed-Scope Warning<br/>& Ask User Decision"]
    Gate -- "Spec-Only (or Confirmed Phase 1)" --> Impact["1. Analyze Interface/Param Impact"]
    Impact --> Scan["2. Scan docs/system/ & docs/specs/"]
    Scan --> Conflict{"3. Design Conflict?"}
    Conflict -- "Yes" --> StopConflict["HALT: Report Conflict Safety Gate"]
    Conflict -- "No" --> Sync["4. Apply Bidirectional Edits Across Specs"]
    Sync --> Meta["5. Bump SemVer & Update YYYY-MM-DD Dates"]
    Meta --> Report["6. Output Sync Summary & Spec-to-Code Impact Report"]
```

Upon completing specification updates, always conclude with two structured summaries:
1. **Specification Synchronization Summary**: Table listing every modified `.md` specification, version bump (`vOld -> vNew`), and key synchronized items.
2. **Spec-to-Code Impact Report**: Read-only inventory of production source files in `src/`, structs/interfaces, and sender/receiver handlers that will require updates (highlighting any `Sender-Immediate-Patch` targets created by newly `[DEPRECATED]` identifiers).
