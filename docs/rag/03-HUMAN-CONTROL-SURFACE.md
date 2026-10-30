---
document_id: EDF-HUMAN-UI
status: authority
---

# Human control surface contract

## Goal

A person must be able to operate the VM factory without memorising low-level EzVM commands.

The preferred outcome is a useful graphical experience. The fallback, if graphical conversion is not practical under the project's portability and qualification constraints, is a comprehensive control/monitoring TUI.

Script-only operation is always retained as a recovery path but is not the intended everyday interface.

## Required operator jobs

The selected primary UI must let a human:

- see host prerequisite/capability state;
- list instances/projects and distinguish STOPPED/STARTING/RUNNING/READY/STOPPING/UNKNOWN;
- see exact lifecycle/process identity without treating stale persisted text as live truth;
- create a fresh project VM with resource profile/overrides;
- start, monitor readiness and stop it;
- open the supported guest interaction path;
- inspect serial/QEMU/control-plane logs and bounded diagnostics;
- see allocated and observed CPU/RAM/disk information where available;
- copy files or open a documented shell/terminal workflow;
- reset, clone, export/import and portability-check with explicit consequences;
- launch a fresh-project kickoff workflow;
- browse TUIsynth only as a clearly labelled reference/demo;
- get actionable error/remediation guidance;
- exit the UI without killing a running VM unless the human explicitly requested stop.

Every mouse action has a keyboard path. Destructive actions show the exact target and consequence.

## EDF-006 GUI feasibility gate

Evaluate three candidates independently:

1. **Host management GUI**.
2. **QEMU graphical console/display**.
3. **Full guest desktop profile**.

For each candidate record:

- exact source/QEMU/guest-profile revision;
- dependencies and packaged size;
- whether system installation/elevation is required;
- clean-start and repeated-start behavior;
- process/viewer lifetime;
- keyboard/mouse/resize/clipboard behavior where applicable;
- resource overhead;
- behavior under spaces/Unicode paths;
- standard-user operation;
- failure/recovery behavior;
- automated coverage available;
- physical Windows evidence required;
- security/network exposure;
- maintenance burden.

Do not decide by screenshot quality alone.

## GUI GO criteria

A candidate is GO only when:

- it uses reviewed/pinned dependencies;
- ordinary launch is non-elevated after documented host prerequisites;
- it does not require a system-wide QEMU install or change the portable bundle model;
- UI/display closure cannot silently corrupt or mutate VM state;
- normal management still passes through the typed broker/control plane;
- guest graphical transport is not exposed to the LAN by default;
- clean checkout/setup is reproducible;
- failure leaves a usable CLI recovery path;
- automated tests cover its state/control contract;
- physical Windows checks establish the interaction claims that automation cannot;
- the measured overhead is acceptable for a coding VM and is recorded rather than assumed.

A full guest desktop additionally requires deterministic/reviewed provisioning, a bounded base-size/startup-cost increase and clear separation from the minimal/headless profile.

## GUI NO-GO is a valid result

A measured NO-GO must name the failed criterion and preserve the evidence. It does not stall the programme.

If host GUI management is NO-GO, EDF-007 implements the comprehensive TUI.

If QEMU graphical display or the desktop guest is NO-GO, the selected primary UI must provide an obvious SSH/terminal attach path and monitoring sufficient for human operation.

Different GUI components may have different decisions; for example a host GUI can be accepted while a full guest desktop is rejected.

## Comprehensive TUI fallback

If selected, the TUI is not a thin menu wrapper. It must provide at least:

- overview/inventory pane;
- selected-instance lifecycle/readiness pane;
- resource/status pane;
- bounded live/refreshable logs;
- actions/command palette;
- create/project kickoff wizard;
- confirmation overlays for destructive actions;
- diagnostics/recovery view;
- clone/export/import workflow;
- help/keymap;
- reference/demo launcher;
- attach/SSH handoff that clearly changes input ownership;
- responsive asynchronous collectors so slow guest reads do not block keyboard input;
- visible freshness/age/error state for observations;
- 80x24 focused mode plus useful wide-screen layouts;
- Windows Terminal keyboard and mouse qualification.

The historical EzVM dashboard is research/reference, not automatic implementation authority. Reuse concepts only after reviewing source/license/dependency fit.

## Host GUI candidate guidance

The feasibility issue should compare at least one option that does not impose a new system runtime against any richer alternative considered. Selection must be based on the contract above, not framework preference.

A host GUI may open or focus the separately managed QEMU guest console. It must not become the owner of the QEMU process unless the lifecycle contract explicitly defines that ownership.

## Input ownership

Read-only monitor views forward zero guest input.

Any interactive console/terminal/desktop mode has a visible input-owner state and a reliable escape back to management. Switching panes must not leak keystrokes or paste into the wrong guest/session.

## Confirmation model

Non-destructive reads and ordinary start may be one action.

Stop, reset, stateful clone, export/import replacement, deletion and future storage growth use a confirmation appropriate to their consequence. Confirmation includes the exact instance name/generation and whether guest mutable state/credentials will be preserved or discarded.

Do not use generic “Are you sure?” without the consequence.

## Accessibility and recovery

Status is textual as well as visual. Color is never the only distinction. The UI has a safe minimal/mono mode where applicable.

If the UI itself fails, the operator guide gives the exact CLI/helper commands to inspect and stop/recover the VM without modifying UI state by hand.
