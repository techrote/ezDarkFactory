---
document_id: EDF-TEST
status: authority
---

# Testing, CI and release contract

## Evidence classes

Every acceptance claim is labelled as one of:

- **SOURCE** — static/source/configuration evidence;
- **FAST-CI** — deterministic unit/integration tests without a real long-lived guest;
- **TCG-RUNTIME** — real QEMU/guest orchestration using explicit TCG;
- **WHPX-RUNTIME** — real QEMU/guest execution on a supported Windows/WHPX host;
- **PHYSICAL-UI** — actual Windows Terminal/GUI/keyboard/mouse/display use;
- **HUMAN-USABILITY** — a person follows the operator guide and completes the stated workflow.

TCG is not WHPX performance evidence. Headless UI simulation is not PHYSICAL-UI. Documentation review is not HUMAN-USABILITY.

## Required fast merge gate

Once EDF-002 establishes the harness, every implementation PR must run one repository entry point that includes:

- repository/provenance contract tests;
- generated-runtime/binary/secret guards;
- PowerShell control-plane tests on Windows PowerShell 5.1 where applicable;
- pinned/current PowerShell 7 lane;
- broker tests;
- UI state/action tests for implemented control surfaces;
- guest-profile generation/readiness tests;
- documentation/RAG/programme integrity;
- package/source-content tests where applicable.

A zero-test or all-skipped lane fails the merge gate.

Each issue may add focused tests, but green focused tests do not replace the full gate before merge.

## Historical regression fixtures

EDF-003 must retain safe negative fixtures for:

- the standard-user private-DACL/key-management class;
- the captured-output/QEMU process-lifetime class;
- stale/reused PID/process identity;
- ambiguous lifecycle state;
- late readiness result after stop/reset/superseding launch.

Do not use the historical owner VM or real keys as fixtures.

## GUI/TUI testing

### Automated

UI logic must be separable from real display/input where possible. Test:

- state rendering;
- disabled/available action capability rules;
- stale revision refusal;
- confirmations;
- action dispatch identity;
- no mutation on view/open/refresh;
- slow-source responsiveness;
- log bounds/control-sequence handling;
- input ownership state;
- close/exit semantics;
- resize/layout bounds.

If a TUI is selected, inject real terminal input sequences in its headless driver where the framework supports it.

If a GUI is selected, use deterministic view-model/controller tests and the lightest reliable automation available for smoke coverage; do not claim physical display behavior from mocks.

### Physical UI

Record actual:

- Windows version/build;
- terminal/display backend;
- QEMU/runtime pin;
- source commit/tree;
- resolution/scaling where relevant;
- keyboard/mouse/focus/resize behavior;
- viewer close/reopen;
- standard-user launch;
- clean shutdown/recovery.

## Real guest lanes

### TCG

Use bounded TCG integration to prove portable orchestration where practical:

- verified acquisition/bootstrap;
- prepared-base build or a source-matched retained base when the issue contract explicitly allows it;
- instance create/start;
- authenticated identity/READY;
- exec/copy;
- stop/restart;
- fresh/reset/stateful semantics as required;
- relocation where required.

Record accelerator as TCG explicitly.

### WHPX

WHPX qualification is run on a supported physical Windows client. It proves at least:

- standard-user start/stop/READY;
- intended acceleration actually selected;
- process lifetime after controller/UI returns;
- normal human interaction path;
- relevant performance/latency sanity;
- clean resource release.

Unavailable WHPX is SKIP/UNMEASURED, never PASS.

## Clean-host/usability lane

Before a release candidate, a user or clean disposable Windows environment follows only the checked-in README/operator guide.

Measure/record:

- prerequisite discovery;
- bootstrap;
- base preparation;
- fresh project creation;
- primary UI start;
- guest interaction;
- stop/restart;
- clone/export or recovery exercise;
- errors/manual interventions;
- whether any undocumented historical TUIsynth knowledge was required.

The goal is not a benchmark score; it is evidence that the guide is sufficient.

## CI truthfulness

Workflow job titles and receipts state what actually ran.

Examples:

- `PASS: PowerShell 5.1 control-plane tests`
- `PASS: TCG end-to-end orchestration`
- `SKIP: WHPX unavailable on hosted runner`
- `HUMAN-PENDING: physical GUI interaction`

Do not name a hosted TCG job “WHPX qualification”.

## Packaging

Release artifacts contain first-party source/control plane, reviewed manifests, UI source/runtime bootstrap material as allowed, documentation and notices.

They exclude:

- QEMU provider binaries unless a separate redistribution decision explicitly permits them;
- Ubuntu source/base/overlay images;
- runtime databases/logs;
- keys and credentials;
- TUIsynth historical authenticated state;
- model weights;
- caches;
- test-generated evidence not intended for release.

If optional Python/GUI/TUI dependencies are used, their acquisition and hash/version policy is part of the package contract.

## Release gate

The final release issue requires:

- exact candidate source/tree;
- all programme implementation issues accepted;
- full fast merge gate green;
- deterministic package/content verification;
- applicable TCG runtime PASS;
- required WHPX/PHYSICAL-UI/HUMAN-USABILITY evidence, or an explicit decision that the named release excludes that capability;
- no unresolved blocker hidden as SKIP;
- README/operator/recovery docs matching the actual selected GUI/TUI path;
- source/runtime/reference provenance recorded;
- clean post-merge main verification before tag/release.

A release tag must never be used to manufacture missing qualification.
