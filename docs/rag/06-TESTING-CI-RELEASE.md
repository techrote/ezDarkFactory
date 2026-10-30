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
- **PHYSICAL-TUI** — actual Windows Terminal keyboard/mouse/focus/resize/terminal behavior;
- **HUMAN-USABILITY** — a person follows checked documentation and completes the stated workflow.

TCG is not WHPX performance evidence. Headless TUI simulation is not PHYSICAL-TUI. Documentation review is not HUMAN-USABILITY.

## Required fast merge gate

Once EDF-002 establishes the harness, every implementation PR must run one repository entry point covering applicable:

- repository/provenance contract tests;
- generated-runtime/binary/secret guards;
- Windows PowerShell 5.1 control-plane tests;
- pinned/current PowerShell 7 tests;
- typed broker/adapter tests;
- multi-factory identity/isolation tests;
- TUI command-registry parity tests;
- TUI geometry/hit/overlay/capture/session tests;
- guest-profile generation/readiness tests;
- documentation/RAG/programme integrity;
- package/source-content tests.

A zero-test or all-skipped lane fails.

Focused tests do not replace the full merge gate.

## Historical regression fixtures

EDF-003 retains safe negative fixtures for:

- standard-user private-key/DACL handling;
- captured-output/QEMU process-lifetime ownership;
- stale/reused PID/process identity;
- ambiguous lifecycle state;
- late readiness result after stop/reset/superseding launch.

Do not use the historical owner VM or real keys.

## Host-manager TUI automated testing

The authoritative UI test matrix is `docs/rag/03-HUMAN-CONTROL-SURFACE.md`.

At minimum automate:

- semantic command metadata and mouse/keyboard parity;
- factory registration, duplicate identity, moved-root, and incompatible-root handling;
- exact factory + instance-generation dispatch identity;
- cross-root mutation isolation;
- lifecycle state rendering and stale/unknown distinction;
- persistent tile state;
- deterministic layout at required viewport sizes;
- final-geometry hit maps;
- divider capture/commit/Escape/focus-loss rollback;
- overlay no-click-through;
- bounded log rendering/control-sequence safety;
- config/registry/session/journal separation;
- safe-start behavior;
- generation-tagged stale-result rejection;
- one slow factory while other factories and UI remain responsive;
- manager close/restart without VM mutation or blind replay;
- direct factory open after relocation with no prior manager registry;
- detection of forbidden hidden host-profile/absolute dependencies;
- destination ACL/runtime revalidation without changing factory/instance identity;
- theme/color/ASCII/high-contrast/reduced-motion fallbacks;
- zero logical damage for unchanged scenes where supported.

Use real terminal input sequences/pipe or PTY-like test facilities supported by the selected framework.

## Physical Windows Terminal qualification

PHYSICAL-TUI evidence must record:

- Windows version/build;
- Windows Terminal version;
- TUI runtime/framework version;
- exact source commit/tree;
- viewport/scaling;
- color and Unicode capability;
- user privilege class.

Exercise:

- mouse press/release/move/wheel;
- keyboard navigation and command palette;
- focus loss during drag;
- terminal resize during interaction;
- context menus and overlays;
- paste into allowed fields;
- 80×24 and 160×48 required layouts;
- high contrast/reduced motion;
- crash/normal-exit terminal restoration;
- external guest-shell launch/return;
- manager close/reopen while a managed VM remains running.

Headless logical tests alone are not PHYSICAL-TUI PASS.

## One-folder portability qualification

Before v0.1 release, prove a stopped, working factory can be archived/copied as one folder to a different supported absolute path and reopened without the previous manager workspace.

The real campaign must demonstrate:

- same factory/instance identities after relocation;
- root-relative configuration remains valid;
- old host process/PID/QMP observations are not reused as authority;
- current-user private-key ACLs are revalidated/reapplied;
- setup/doctor handles host-specific prerequisites;
- direct open by path works without old registry/session state;
- start → READY → stop succeeds after relocation;
- a second simultaneously writable copy is blocked as duplicate identity until explicit fork/rekey;
- the stateful folder/archive is visibly classified sensitive when it contains keys/credentials.

Where suitable two-host hardware is available, repeat the transfer onto another compatible Windows machine; otherwise the same-machine different-root test is automated/TCG evidence and the true cross-host move remains part of EDF-011 HUMAN/PHYSICAL qualification.

## Multi-factory qualification

Before v0.1 release, prove one manager session can register and observe at least two independent disposable real factory roots.

At least one real campaign must demonstrate:

- distinct stable factory identities;
- overlapping instance display names do not collide;
- one root can start/stop/reach READY while the other remains independently observable;
- one root failure/unavailability does not change the other;
- manager exit does not stop either root's running VM;
- duplicate/copy identity conflict is held rather than silently mutated.

Synthetic scale/performance gates in the host-manager spec remain separate from real-root evidence.

## Real guest lanes

### TCG

Use bounded TCG integration for portable orchestration where practical:

- verified acquisition/bootstrap;
- prepared base;
- instance create/start;
- authenticated identity/READY;
- exec/copy;
- stop/restart;
- reset/fresh/stateful semantics as required;
- relocation where required.

Always label the accelerator TCG.

### WHPX

WHPX qualification runs on a supported physical Windows client and proves at least:

- standard-user start/stop/READY;
- intended acceleration actually selected;
- process lifetime after controller/TUI returns;
- normal host-manager operation;
- clean resource release.

Unavailable WHPX is SKIP/UNMEASURED, never PASS.

## Clean-host/usability lane

Before release, a user or clean disposable Windows environment follows checked docs only.

Measure/record:

- prerequisite discovery;
- bootstrap/base preparation;
- TUI launch;
- registration of multiple local roots;
- fresh project creation in the intended root;
- READY;
- guest attach;
- stop/restart;
- one-folder portability exercise;
- clone/export/recovery exercise;
- reference/demo discovery;
- errors/manual interventions;
- any undocumented historical knowledge required.

## CI truthfulness

Examples:

- `PASS: PowerShell 5.1 control-plane tests`
- `PASS: host-manager parity/geometry fixtures`
- `PASS: TCG end-to-end orchestration`
- `SKIP: WHPX unavailable on hosted runner`
- `HUMAN-PENDING: physical Windows Terminal qualification`

Do not describe hosted/headless evidence as physical TUI or WHPX PASS.

## Packaging

Release artifacts contain appropriate first-party source/control plane, reviewed manifests, host-manager source/runtime bootstrap material, documentation, and notices.

Exclude:

- QEMU provider binaries unless separately approved for redistribution;
- Ubuntu source/base/overlay images;
- runtime databases/logs;
- keys and credentials;
- TUIsynth authenticated/historical runtime state;
- model weights;
- caches;
- private evidence.

Any TUI framework/runtime acquisition/version policy is part of the release contract.

## Release gate

EDF-012 requires:

- exact candidate source/tree;
- all programme issues accepted;
- full fast gate green;
- deterministic package/content verification;
- applicable TCG runtime PASS;
- required WHPX-RUNTIME PASS;
- required PHYSICAL-TUI PASS;
- HUMAN-USABILITY PASS;
- multi-factory real-root qualification;
- one-folder portability qualification;
- no blocker hidden as SKIP;
- docs matching the actual host-manager workflow;
- exact source/runtime/reference/specdocz provenance;
- clean post-merge main verification.

A release tag cannot manufacture missing qualification.
