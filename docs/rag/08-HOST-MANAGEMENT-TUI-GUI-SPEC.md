---
document_id: EDF-HOST-UI
status: authority
spec_version: 1.0
audit_baseline: a756f9c1041e4e6a39cdfd951aebfd98857d15a8
specdocz_revision: 2e95d6931cc23862a4176c9d8ccb4da78f00c265
---

# ezDarkFactory Host Management TUI/GUI UI/UX and Implementation Specification

**Status:** Authoritative project-specific UI/UX and implementation contract  
**Version:** 1.0  
**Primary surface:** Host-side full-screen terminal application with GUI-like tile workspace ("TUI GUI")  
**Primary native environment:** Windows x86-64 host, Windows Terminal  
**Scope:** One host manager controlling and monitoring multiple explicitly enrolled local ezDarkFactory roots and their VM instances  
**Normative language:** **MUST**, **SHOULD**, and **MAY** are project requirements, recommendations, and optional capabilities.

This document is self-contained. It integrates the applicable requirements from the pinned shared standards into ezDarkFactory terminology and architecture. Readers do not need the shared documents to understand the required product behavior.

## Contents

1. **Authority, source pins, and lifecycle** — pins the shared baseline and defines project precedence and delta review.
2. **Current-project audit and status boundary** — records the architecture, workflows, platforms, tests, constraints, and what is not yet implemented.
3. **Product model and multi-factory scope** — defines factories, instances, operations, observations, and enrollment.
4. **Host-manager architecture** — defines the manager/control-plane boundary and multi-root isolation model.
5. **Workspace, tiles, and responsive layout** — defines persistent views, presets, split/stack behavior, and compact mode.
6. **Commands, input, pointer parity, and safety** — defines one semantic command system with mouse/keyboard parity and guarded mutations.
7. **Factory enrollment, observation, and concurrency** — defines safe discovery/enrollment, freshness, async work, and cross-root behavior.
8. **Lifecycle, project, recovery, and attach workflows** — defines the domain-specific workflows exposed by the manager.
9. **Themes, ANSI presentation, accessibility, and rendering** — defines safe semantic styling and constrained-environment behavior.
10. **Configuration, persistence, and safe start** — separates static preferences, factory registry, and dynamic session state.
11. **Implementation-pattern decisions** — records Adopt / Adapt / Reject / Extend decisions from the direct implementation specification.
12. **Material deviations and rationale** — records intentional differences from the generic baseline or pattern library.
13. **Project-specific acceptance and qualification** — defines automated, native, multi-root, performance, and failure/recovery gates.
14. **Implementation and qualification status** — distinguishes required behavior from current implementation evidence.

# 1. Authority, source pins, and lifecycle

## 1.1 Pinned shared basis

This specification was tailored against exact `techrote/specdocz` revision:

`2e95d6931cc23862a4176c9d8ccb4da78f00c265` — **Improve GUI/TUI specification tailoring guide**.

Pinned source files:

| Role | Path | Git blob SHA | Treatment |
|---|---|---|---|
| Normative design baseline | `tuiuiux/tile-native-gui-tui-uiux-spec.md` | `4c0d668fba6824d0109d3a774364e4ddb3e4af61` | Normative baseline, tailored here |
| Implementation pattern library | `tuiuiux/tile-native-gui-tui-implementation-spec.md` | `758a1383b5bef72ed9c71952659e48d7fd90a0ff` | Reviewed pattern-by-pattern, not mandatory architecture |
| Tailoring procedure | `tuiuiux/tile-native-gui-tui-spec-tailoring.md` | `b0880fe38c243adb16ab6868970f8e6f977b8c81` | Procedure used to produce this document |

**MDBM-referenced variants consulted in this tailoring pass:** none. The pinned baseline and pattern library were sufficient for the current decisions. This is deliberate: no MDBM-specific behavior is inherited by implication. A future decision may consult a concrete MDBM precedent only when a specific edge case warrants it, and that consultation MUST be recorded as evidence rather than authority.

## 1.2 Project audit baseline

The project was audited at ezDarkFactory `main` commit:

`a756f9c1041e4e6a39cdfd951aebfd98857d15a8`.

The audit included:

- `README.md`;
- `AGENTS.md`;
- `RAG.md`;
- RAG documents `00` through `07`;
- `docs/programme/PLAN-REVIEW.md`;
- `docs/programme/IMPLEMENTATION-PROGRAMME.md`;
- `docs/programme/STATUS.md`;
- open implementation issues #1 through #12, with detailed review of the UI/broker/qualification issues.

## 1.3 Project precedence

For UI/UX and host-manager behavior, conflicts are resolved in this order:

1. repository safety, lifecycle, storage-integrity, secret, compatibility, and accepted control-plane requirements;
2. this project-specific host-management specification;
3. current issue-specific requirements that do not conflict with items 1–2;
4. other current ezDarkFactory RAG/programme documents;
5. the pinned standalone specdocz UI/UX baseline;
6. adopted/adapted patterns from the pinned direct implementation specification;
7. MDBM or other examples, if explicitly consulted.

An issue MUST NOT silently weaken this specification. A deliberate project change requires an explicit specification amendment with rationale and acceptance impact.

## 1.4 Future specdocz changes

This project is pinned to the revision above. Future `specdocz` changes are **not** inherited automatically.

A future update MUST:

1. compare the recorded pin with the proposed newer revision;
2. review only the relevant delta;
3. classify each material change as Adopt, Adapt, Reject, or Extend;
4. update this document deliberately;
5. record the new revision and rationale;
6. identify tests/qualification invalidated by the change.

# 2. Current-project audit and status boundary

## 2.1 Current architecture

ezDarkFactory is currently a planning programme. The VM/runtime implementation has **not yet been imported**.

The accepted architecture direction is Windows-first and preserves the EzVM lineage:

- repository-local QEMU;
- immutable managed base → one mutable QCOW2 instance overlay;
- lifecycle locks and exact process-identity reconciliation;
- QMP bound to localhost;
- QEMU user-mode NAT;
- SSH forwarding bound to localhost;
- versioned guest identity/readiness;
- reset/clone/export/import/portability semantics;
- typed broker/control operations above the PowerShell VM control plane;
- UI code prohibited from direct instance JSON, QCOW2, PID, trust-file, or backing-chain mutation.

## 2.2 Existing workflows

The project requirements already define:

- host doctor and prerequisite remediation;
- verified QEMU/extractor/bootstrap;
- Ubuntu source acquire and prepared-base build;
- fresh project VM creation;
- start → authenticated READY;
- stop/restart;
- exec/file transfer/guest attach;
- bounded logs and diagnostics;
- reset;
- fresh and stateful clone;
- export/import;
- cold portability;
- recovery from ambiguous lifecycle state;
- isolated TUIsynth reference/demo access.

The host manager MUST present these workflows without replacing their underlying control-plane semantics.

## 2.3 Platform and input constraints

Required v0.1 host baseline:

- Windows x86-64;
- supported Windows 10/11 client for physical qualification;
- Windows Terminal as the primary native TUI qualification target;
- PowerShell 5.1 and current/pinned PowerShell 7 remain control-plane compatibility targets;
- normal operation after prerequisite setup MUST be available as a standard user.

The primary manager MUST be usable from a compact TKL keyboard. Core operations MUST NOT require:

- function keys;
- numpad keys;
- PageUp/PageDown.

Those inputs MAY exist as optional aliases only.

Mouse/pointer support is first-class and command parity is required.

## 2.4 Existing UI implementation

Current ezDarkFactory UI implementation: **none**.

The historical EzVM read-only dashboard is useful research only. It is not imported implementation authority and its TRIO/provider-specific behavior is not inherited.

The current issue programme contains planned broker/UI work but no accepted ezDarkFactory TUI code, geometry engine, command registry, theme engine, session store, or native Windows Terminal qualification.

## 2.5 Existing tests and qualification

Current ezDarkFactory executable test implementation: **none yet**.

The project RAG requires future coverage for:

- Windows PowerShell 5.1;
- pinned/current PowerShell 7;
- provenance/repository/secret guards;
- broker and UI state/action tests;
- TCG runtime where appropriate;
- real WHPX runtime;
- physical UI;
- human usability.

Writing those requirements into this specification is not evidence that they currently pass.

## 2.6 Direction selected by owner

The project no longer treats native host GUI versus TUI as an open product choice.

**Selected v0.1 direction:** one **host-side management TUI GUI** capable of managing multiple ezDarkFactory roots from a single interface.

“TUI GUI” means a full-screen terminal application with persistent tiles, mouse and keyboard interaction, menus/overlays, command palette, direct manipulation, responsive layout, semantic styling, and safe session persistence. It is not a line-oriented menu.

A future native GUI renderer MAY be added, but dual GUI/TUI rendering is not a v0.1 requirement and MUST NOT delay the host manager.

A graphical QEMU guest console or guest desktop is not required for the host-manager release. Guest interaction may remain SSH/terminal based.

# 3. Product model and multi-factory scope

## 3.1 Domain entities

The host manager manipulates these domain entities; tiles are presentation, not the product model.

### Manager

One running host-side application with its own configuration, enrolled-factory registry, session state, collectors, and command registry.

### Factory

One explicitly enrolled ezDarkFactory root on the same Windows host.

A factory has at least:

- manager-local enrollment ID;
- canonical root path;
- displayed alias;
- product/control API version;
- source/build identity where exposed;
- factory/bundle identity where the control plane provides one;
- current reachability/capability/freshness;
- zero or more instances.

A path string alone MUST NOT be treated as durable runtime identity.

### Instance

An instance is scoped by its factory identity plus its own name and generation/identity.

Two instances with the same name in different factories are distinct.

### Project

A project is human-facing intent associated with an instance/workspace. A project label does not replace VM identity.

### Operation

A typed command intent/result scoped to one factory and, where applicable, one exact instance generation.

### Observation

A timestamped, source-identified read result. Observation freshness and error state are distinct from durable intent.

## 3.2 v0.1 locality

v0.1 supports **multiple local factory roots on one Windows host**.

Remote-host control is explicitly future work. The architecture SHOULD keep adapter boundaries clean enough to add a remote transport later, but no current UI element may imply remote management is supported.

## 3.3 Enrollment, not implicit authority

The manager MUST control only explicitly enrolled factory roots.

A candidate-root scan MAY identify likely ezDarkFactory directories without executing code. Candidate discovery is read-only and non-authoritative.

Before the manager executes a factory's control plane for the first time, enrollment MUST show:

- canonical path;
- detected manifest/product identity where readable without execution;
- what local code will be invoked;
- manager permissions/authority being granted.

Enrollment confirmation grants control authority for that root; merely discovering a directory does not.

Removing a factory from the manager registry MUST NOT delete or modify the factory, its VMs, or its runtime state.

## 3.4 Duplicate and relocation detection

The manager MUST detect and surface:

- the same canonical root enrolled twice;
- two paths that report the same live factory/bundle identity;
- a moved root whose prior path disappeared;
- an unavailable root;
- a copied bundle whose simultaneous use would violate the underlying portability contract.

The manager MUST NOT silently merge these identities or choose one path.

# 4. Host-manager architecture

## 4.1 Required boundary

The host manager sits above per-factory typed control APIs:

```text
Windows Terminal input
        ↓
Host Manager TUI
        ↓
semantic commands / manager reducer
        ↓
Factory Registry + per-factory adapters
        ↓
versioned ezDarkFactory broker/control API
        ↓
PowerShell lifecycle/storage control plane
        ↓
QEMU / QCOW2 / QMP / SSH / guest
```

The TUI MUST NOT:

- dot-source managed factory PowerShell modules into the TUI process as a shortcut;
- edit managed JSON directly;
- open or modify QCOW2 files directly;
- kill a PID based on display data;
- rewrite SSH trust files;
- bypass lifecycle locks;
- infer capability from filename/version text when a capability API exists.

## 4.2 Per-factory adapter

Each enrolled root is represented by a versioned adapter with:

- identity/capability handshake;
- read-only observation calls;
- typed mutation calls;
- bounded timeouts;
- structured errors;
- source/factory identity attached to every result.

Untrusted stdout/stderr and guest output are data, never host command authority.

## 4.3 Manager reducer

The host manager SHOULD use one authoritative controller/reducer for manager UI state.

Domain mutation is different: the reducer dispatches typed control operations but the per-factory control plane remains the authority for VM state.

This distinction prevents the TUI from becoming a second VM manager.

## 4.4 No mandatory background service

v0.1 MUST NOT require a Windows service or always-on daemon.

A user-launched manager process owns its UI collectors and manager session. Managed VMs remain independently alive according to the VM lifecycle contract when the manager exits.

# 5. Workspace, tiles, and responsive layout

## 5.1 Persistent tile identities

Required core tiles:

| Tile ID | Purpose | Minimum persistent local state |
|---|---|---|
| `factories` | enrolled roots and aggregate health | selected factory, filter, scroll |
| `instances` | instances for selected/all factories | selected instance, filter/sort, scroll |
| `inspector` | selected factory/instance identity, readiness, resources, actions | active section/tab, scroll |
| `activity` | in-flight/recent operations, attention/errors | filters, selected operation, follow state |
| `logs` | bounded serial/QEMU/control/diagnostic text | selected source, search/filter, scroll/follow |
| `resources` | host/factory/instance resource summaries where available | scope, sort/filter, scroll |

Project kickoff, enrollment, confirmations, help, settings, and destructive previews SHOULD normally be overlays/wizards rather than permanent tiles.

Moving, hiding, stacking, maximizing, or compacting a tile MUST preserve its relevant local state.

## 5.2 Workspace scopes

The manager MUST support at least:

- **All factories** scope;
- **One factory** scope;
- **One instance** scope.

Changing scope updates applicable tiles without destroying their independent state.

## 5.3 Workspace presets

Provide named presets:

- **Fleet** — factories + aggregate instances + attention/activity;
- **Factory** — one root with instances, inspector, and logs/activity;
- **Instance** — deep selected-instance inspector with logs/activity;
- **Recovery** — identity/diagnostics/logs emphasized.

Presets are default arrangements, not separate application modes.

## 5.4 Layout model

Use a deterministic split/stack layout or equivalent constraint model.

v0.1 MUST support:

- horizontal/vertical splits;
- persistent split ratios;
- hide/show;
- swap/reposition;
- maximize/restore;
- tab/stack groups where useful;
- layout reset;
- compact focused-tile mode.

Detachable native windows are not required.

## 5.5 Responsive priorities

Space allocation priority is:

**critical host controls/status → minimum usable tile content → user spacing → decoration**.

At minimum, qualify these viewport classes:

- **40×12** — constrained recovery/focused-tile mode;
- **80×24** — minimum normal operator mode;
- **120×40** — standard overview;
- **200×60** — large/fleet overview.

At small sizes, the manager MUST enter focused compact mode rather than rendering unusable fragments of every tile.

An all-hidden/corrupted layout MUST retain an obvious restore-default route.

## 5.6 Divider transactions

Divider drag MUST:

1. capture the pointer;
2. continue outside the divider;
3. preview only legal geometry;
4. commit once on release;
5. roll back on Escape;
6. roll back on terminal focus loss.

The divider's hit target derives from solved geometry.

# 6. Commands, input, pointer parity, and safety

## 6.1 One semantic command registry

Every meaningful application action MUST have a stable command ID.

Required command families include:

```text
app.*
workspace.*
factory.*
instance.*
project.*
diagnose.*
portability.*
reference.*
help.*
```

Representative commands:

```text
factory.enroll
factory.remove_from_manager
factory.refresh
factory.select
instance.create
instance.start
instance.stop
instance.open_shell
instance.diagnose
instance.reset
instance.clone_fresh
instance.clone_stateful
instance.export
instance.import
project.kickoff
workspace.focus_next
workspace.hide_tile
workspace.restore_all
workspace.maximize
workspace.reset_layout
app.safe_start
app.quit
```

Keyboard, pointer, menu, context, palette, and direct-manipulation routes MUST converge on the same command IDs.

## 6.2 Pointer/keyboard parity

Every keyboard-accessible application command MUST have a practical pointer route.

Every meaningful pointer-only command SHOULD have a keyboard route.

Automated parity tests MUST fail accidental keyboard-only or mouse-only semantic commands.

Core command defaults MUST be usable without function keys, PageUp/PageDown, or numpad keys.

## 6.3 Discoverability

The TUI MUST provide:

- visible top-level menus or equivalent spatial command surface;
- searchable command palette;
- context menus where local actions benefit;
- help/shortcut view.

Reserved recovery commands for command palette, overlay dismissal, layout restore/safe start, and guarded quit MUST remain reachable after user key-binding customization.

## 6.4 Focus and click behavior

Clicking an actionable control in an unfocused non-destructive tile SHOULD focus and act in one gesture.

For destructive or high-consequence VM operations, a click MAY focus/select and open a confirmation/preview instead of executing immediately. This is an intentional safety exception, not a double-click requirement.

Wheel scrolling belongs to the tile under the pointer and MUST NOT silently move keyboard selection elsewhere.

## 6.5 Destructive confirmation

Destructive/high-consequence confirmation MUST include:

- factory alias plus canonical/root identity hint;
- instance name and generation where applicable;
- operation;
- state consequence;
- whether mutable guest state or credentials are preserved/discarded.

A generic “Are you sure?” is insufficient.

v0.1 does not provide generic batch destructive operations across multiple factories.

## 6.6 Overlay safety

Top overlay receives input first.

Outside-click dismissal consumes the click and MUST NOT click through.

Escape closes one logical overlay level at a time.

Menus/submenus MUST remain in the visible viewport.

# 7. Factory enrollment, observation, and concurrency

## 7.1 Collector model

Collectors operate per enrolled factory.

A slow/unavailable factory MUST NOT freeze:

- keyboard/mouse input;
- rendering;
- observation of other factories;
- completion display for unrelated operations.

Each source SHOULD have bounded in-flight work. The manager MUST NOT create an unbounded poll/result queue.

## 7.2 Generation-tagged results

Every asynchronous refresh/request MUST carry a generation/version.

Late results from an older generation MUST be discarded if the factory was:

- refreshed again;
- removed;
- relocated/re-enrolled;
- superseded by a newer instance generation;
- closed/reset in a way that invalidates the observation.

## 7.3 Freshness states

The UI MUST distinguish at least:

- current;
- last-known/stale;
- unknown;
- unavailable/error.

Unknown is never rendered as idle or stopped.

Persisted VM intent is visually distinct from observed process/readiness truth.

## 7.4 Cross-factory operation isolation

An operation against Factory A MUST carry Factory A identity through dispatch and result validation.

Tests MUST prove Factory B remains unchanged.

One factory's locks MUST NOT be replaced by a manager-global mutation lock, although the manager MAY limit total concurrency for resource protection.

## 7.5 Operation journal

The activity surface MUST retain bounded manager-local records of:

- operation ID;
- factory;
- target;
- requested action;
- start/end;
- result/refusal;
- source/control API version;
- reconciliation state if result delivery was ambiguous.

This journal is UI/recovery evidence, not a replacement for factory runtime authority.

Manager restart MUST NOT blindly replay pending mutations.

# 8. Lifecycle, project, recovery, and attach workflows

## 8.1 Start/stop

Start shows distinct stages where exposed:

- validation;
- process launch;
- QMP/process ownership;
- SSH;
- cloud-init/current boot;
- profile READY.

Stop shows graceful shutdown progress and preserves STOPPING/unknown state if the underlying contract cannot prove completion.

Manager exit does not stop running VMs.

## 8.2 Fresh project creation

Project kickoff MUST support:

- target factory;
- new instance/project name;
- resource profile/overrides;
- source choice: empty workspace by default, explicit clone URL, or accepted local copy path;
- preview before mutation.

TUIsynth, agent providers, and model runtimes are never default choices.

## 8.3 Reset/clone/export/import

The manager MUST expose the underlying semantics accurately.

It MUST distinguish:

- reset;
- fresh clone;
- stateful clone;
- export;
- import.

Stateful copy/export is visibly marked sensitive because guest credentials may be included.

## 8.4 Recovery

When ownership/state is ambiguous:

- destructive storage actions are disabled;
- persisted and observed identities are shown separately;
- bounded diagnostics remain available;
- exact safe next steps are shown;
- the UI MUST NOT offer “delete runtime files” as generic recovery.

## 8.5 Guest attach

v0.1 does **not** require an embedded PTY terminal emulator.

`instance.open_shell` MUST enter an explicit attach/handoff path using the accepted managed SSH identity/trust.

If the manager temporarily yields the current terminal, it MUST restore terminal modes on return. If it launches a separate console process, the lifetime relation MUST be explicit.

Read-only log tiles never forward guest input.

## 8.6 Reference/demo

TUIsynth is available only through a distinct Reference/Demo workflow, with source identity and historical status shown before launch.

Reference/demo actions cannot mutate the active project workspace by default.

# 9. Themes, ANSI presentation, accessibility, and rendering

## 9.1 Semantic styling

Themes are declarative data and MUST NOT execute code or contain arbitrary terminal escape sequences.

Required semantic roles include:

`background, text, muted, border, title, accent, selection, focus, status, diagnostic, warning, error, success, busy, destructive, stale, unknown`.

Critical states MUST remain legible even under poor user themes.

An embedded safe theme is mandatory.

## 9.2 Colour and glyph fallbacks

Support deterministic:

**truecolour → ANSI-256 → ANSI-16 → monochrome**.

Support Unicode and ASCII-only presentation.

Important state is never colour-only.

## 9.3 Decoration policy

The generic baseline's rich adaptive ANSI/ASCII art capability is **adapted down** for v0.1.

The manager MAY provide restrained frames, motifs, banners, and deterministic decoration, but:

- functional content has priority;
- decoration disappears before useful content;
- no complex artwork is required for product completeness;
- no decoration may overwrite critical/interactive cells;
- animation is nonessential.

## 9.4 Motion

Reduced-motion and motion-off modes are required.

Default operational status animation SHOULD be minimal: bounded spinners/progress indicators and state transitions only.

Motion-off produces a stable deterministic frame.

## 9.5 Log safety

Logs, guest output, project text, and external command output are untrusted display data.

Control sequences capable of changing terminal title, clipboard, input modes, or other terminal state MUST NOT execute merely because content is viewed in a tile.

## 9.6 Rendering/damage

Final solved geometry is authoritative for hit testing.

Identical frames SHOULD produce zero logical damage.

A local cursor/status change SHOULD NOT force an unconditional whole-terminal clear.

Resize and capability changes re-solve geometry and hit maps completely.

# 10. Configuration, persistence, and safe start

## 10.1 Static configuration

Manager configuration SHOULD contain defaults/policy such as:

- initial workspace preset;
- tile minimums/default visibility;
- key bindings;
- theme;
- Unicode/ASCII policy;
- colour override;
- accessibility;
- motion;
- collector/performance budgets;
- optional candidate-root scan locations.

Hand-maintained config is not silently rewritten by normal layout changes.

## 10.2 Factory registry

The manager-owned enrolled-root registry is distinct from per-factory runtime state.

It records manager metadata such as:

- enrollment ID;
- alias;
- canonical path;
- last verified factory identity/version;
- display preferences.

It MUST NOT copy or become authoritative for instance runtime JSON.

## 10.3 Session state

Dynamic session state may retain:

- active scope;
- tile visibility/placement;
- split ratios/stacks;
- focused tile;
- per-tile scroll/filter/selection;
- committed theme;
- active workspace preset.

Session restoration is bounded and individually validated.

## 10.4 Safe start

Provide a safe-start launch path with:

- default layout;
- embedded safe theme;
- no dynamic session restore;
- no automatic factory mutation;
- enrolled factory registry retained unless the user explicitly requests a registry-free mode.

Corrupt session state must not prevent manager startup.

# 11. Implementation-pattern decisions

The direct implementation specification is a pattern library. The following decisions are authoritative for v0.1.

| Pattern | Decision | ezDarkFactory treatment |
|---|---|---|
| Semantic `CommandRegistry` | **Adopt** | One stable command ID system across keyboard, mouse, menus, context, palette, and direct manipulation |
| Controller/Reducer owns application state | **Adapt** | Reducer owns manager/UI state; VM domain mutation remains owned by the per-factory control plane |
| Persistent `TileRegistry` | **Adopt** | Factories, Instances, Inspector, Activity, Logs, Resources have stable identities/state |
| Split-tree layout | **Adapt** | Deterministic split + stack/tab groups; detachable windows not required |
| Geometry-derived `HitMapBuilder` | **Adopt** | Pointer targets rebuilt from final solved cell geometry |
| `InputRouter` normalization | **Adopt** | Key/text/pointer/wheel/focus/resize/paste normalized before command routing |
| Pointer capture / transactional drag | **Adopt** | Divider and any future tile/continuous drag use capture, Escape/focus-loss rollback |
| `OverlayManager` | **Adopt** | Explicit overlay stack, no click-through, one-level Escape |
| Semantic theme compiler | **Adapt** | Data-only semantic themes with restrained decoration; complex art is optional |
| Shared GUI/TUI scene abstraction | **Reject for v0.1** | v0.1 has one TUI surface; future GUI must justify its own renderer while preserving semantics |
| Cell compositor | **Adapt** | TUI-specific semantic cells/protection; no requirement for a dual native-GUI scene model |
| Configuration/session separation | **Adopt** | Hand-maintained config, factory registry, and machine-written session state are separate |
| `JobCoordinator` generation tags | **Extend** | Per-factory generations, removal/relocation invalidation, bounded cross-root collectors |
| Logical damage tracking | **Adopt** | Unchanged frame zero-damage target; bounded local repaint |
| Rich adaptive ANSI artwork | **Adapt** | Safe/responsive theme decoration supported but not a release-critical content system |
| Text editor selection semantics | **Reject generally** | Apply only inside log/text surfaces where actual text selection is implemented |
| Double/triple-click generic semantics | **Adapt** | Only implemented for controls/text where a project-specific action is defined |
| Source/preview synchronization | **Reject** | No equivalent domain concept |
| Native detachable windows | **Reject for v0.1** | Terminal-only workspace; future native GUI/windowing is separate scope |
| Embedded terminal emulator | **Reject for v0.1** | Explicit managed SSH attach/handoff; logs remain read-only |
| Generic batch destructive commands | **Reject for v0.1** | Single-target mutations only until group intent/rollback semantics are separately designed |
| Multi-factory registry | **Extend** | Explicit enrollment, aliases, capability handshakes, identity collision/relocation handling |
| Fleet overview | **Extend** | Aggregate factories/instances/attention without collapsing identity |
| Factory adapter boundary | **Extend** | One versioned adapter per root; local v0.1, future transport expansion possible |
| Operation journal/reconciliation | **Extend** | Manager-local bounded record of typed operations; no blind replay |
| Stale/unknown observation semantics | **Extend** | Freshness is first-class and never collapsed to idle/stopped |
| VM lifecycle controls | **Extend** | Exact factory+instance generation, guarded confirmations, underlying locks remain authoritative |
| Project kickoff | **Extend** | Factory-scoped new-project wizard with empty-workspace default |
| Reference/demo surface | **Extend** | TUIsynth shown as historical opt-in reference, never active project authority |

# 12. Material deviations and rationale

## 12.1 TUI-only v0.1 surface

**Deviation:** the generic baseline supports GUI, TUI, or shared GUI/TUI rendering. ezDarkFactory v0.1 selects the host-side TUI GUI only.

**Rationale:** one terminal manager can control multiple independent factory roots with lower packaging complexity while retaining mouse/keyboard interaction and a strong recovery path.

**Status:** owner-selected; required.

## 12.2 Host manager replaces per-factory UI assumption

**Extension:** the UI is not scoped to one ezDarkFactory checkout. It is a host manager with an explicit multi-root registry.

**Rationale:** central management avoids one dashboard process per factory and enables future fleet/resource/recovery features.

## 12.3 No required graphical guest/desktop

**Deviation:** a QEMU graphical console or Linux desktop is no longer on the v0.1 critical path.

**Rationale:** host management and guest presentation are separable. SSH/terminal interaction preserves the existing lifecycle/security model and does not block multi-factory management.

## 12.4 Restrained ANSI art

**Deviation:** the generic baseline contains extensive adaptive ANSI/ASCII artwork requirements. ezDarkFactory requires semantic theming/fallbacks/protected cells, but not rich artwork as a release gate.

**Rationale:** lifecycle identity, safety, logs, and fleet density matter more than decoration.

## 12.5 No generic batch destructive operations

**Deviation/extension:** fleet visibility is multi-root, but v0.1 mutations are single-target.

**Rationale:** start/stop/reset/export across multiple independent factories needs explicit group-intent, partial-failure, and rollback semantics not yet designed.

## 12.6 Safety exception to focus-and-act

**Adaptation:** ordinary controls focus-and-act in one gesture. Destructive controls may focus/select and open a confirmation rather than execute immediately.

**Rationale:** the baseline explicitly permits a deliberate safety exception.

## 12.7 No embedded PTY

**Deviation:** monitoring is in-app; interactive shell control is explicit attach/handoff.

**Rationale:** terminal emulation/input ownership materially increases complexity and failure surface. It can be revisited later as an explicit delta.

# 13. Project-specific acceptance and qualification

A release claiming conformance MUST satisfy the applicable gates below on exact source.

## 13.1 Command and input parity

Automated:

- every keyboard semantic command has a pointer route;
- every meaningful pointer command has a keyboard route;
- no core command requires F-key, PgUp/PgDn, or numpad input;
- disabled commands expose a reason where actionable;
- destructive commands include exact target/consequence metadata.

Native Windows Terminal:

- mouse press/release;
- context menu;
- wheel locality;
- divider drag;
- focus loss during drag;
- overlay dismissal;
- resize;
- keyboard navigation;
- command palette.

## 13.2 Multi-factory identity/isolation

Automated synthetic gate:

- at least 16 enrolled factory fixtures;
- at least 256 aggregate instance records;
- duplicate canonical root detection;
- duplicate reported factory identity detection;
- unavailable/moved root;
- same instance name in multiple factories;
- stale generation result rejection.

Mutation isolation:

- an operation on Factory A changes no tracked fixture state for Factory B;
- target factory and instance generation survive every dispatch/result layer.

Native/runtime gate:

- at least two independent disposable real ezDarkFactory roots enrolled and observed in one manager session;
- start/stop/READY on one root while the other remains independently observable.

## 13.3 Layout and persistence

Golden/deterministic tests at:

- 40×12;
- 80×24;
- 120×40;
- 200×60.

Verify:

- persistent tile state across hide/show/swap/maximize/compact;
- split clamping;
- divider transaction rollback;
- all-hidden recovery;
- corrupt session safe start;
- factory registry retained independently of layout state.

## 13.4 Theme/accessibility

Test:

- truecolour;
- ANSI-256;
- ANSI-16;
- monochrome;
- Unicode;
- ASCII-only;
- high contrast;
- reduced motion;
- motion off.

Invalid theme leaves previous valid theme intact.

Critical states remain textually distinguishable.

## 13.5 Async/failure responsiveness

Fixture gate:

- one factory collector stalls for 10 seconds;
- another factory continues refreshing;
- UI input remains responsive;
- stale late result is discarded;
- repeated refresh does not create an unbounded queue.

Performance target for the standard 120×40 synthetic fleet fixture:

- p95 input-to-frame latency **≤ 100 ms** during normal navigation/selection with collectors active;
- no unbounded memory growth across repeated refresh and tile open/close cycles.

Composition time MUST be reported separately from native input-to-frame latency.

## 13.6 Lifecycle and manager lifetime

Verify:

- opening/refeshing the manager performs zero VM mutation;
- manager exit leaves deliberately running VMs alive;
- manager restart reconciles them from current factory evidence;
- stale/unknown state disables unsafe storage actions;
- start/stop progress cannot convert a late result into current state;
- manager does not blindly replay an ambiguous mutation after restart.

## 13.7 Log and terminal safety

Verify hostile displayed output cannot trigger:

- terminal-title changes;
- clipboard writes;
- input-mode changes;
- command execution;
- unbounded render work.

Interactive SSH attach has explicit input ownership and returns/restores terminal state.

## 13.8 Native qualification

Physical qualification MUST use an actual supported Windows client and Windows Terminal.

Record:

- Windows build;
- Windows Terminal version;
- source commit/tree;
- manager runtime/dependency versions;
- viewport/scaling;
- color/Unicode capability;
- mouse/keyboard/focus/resize results;
- manager close/reopen;
- at least two enrolled real factory roots;
- WHPX evidence separately from TUI evidence.

Passing logical/headless tests alone is not native TUI PASS.

# 14. Implementation and qualification status

Status at the audit baseline `a756f9c1041e4e6a39cdfd951aebfd98857d15a8`:

| Area | Required by this spec | Current implementation | Qualification |
|---|---|---|---|
| Multi-factory host manager | Yes | Not implemented | NOT RUN |
| Typed per-factory broker API | Yes | Planned in EDF-005 | NOT RUN |
| Factory registry/enrollment | Yes | Not implemented | NOT RUN |
| Tile workspace | Yes | Not implemented | NOT RUN |
| Command registry/parity | Yes | Not implemented | NOT RUN |
| Mouse/keyboard TUI | Yes | Not implemented | NOT RUN |
| Session/config persistence | Yes | Not implemented | NOT RUN |
| Themes/accessibility | Yes | Not implemented | NOT RUN |
| Multi-root async collectors | Yes | Not implemented | NOT RUN |
| Lifecycle/project/recovery UI | Yes | Not implemented | NOT RUN |
| Guest SSH attach handoff | Yes | Underlying historical capability only; EDF implementation pending | NOT RUN in EDF |
| Windows Terminal native qualification | Yes | No EDF UI exists | NOT RUN |
| WHPX runtime qualification | Yes for release, separate evidence class | EDF runtime not yet imported | NOT RUN |
| Native host GUI | No for v0.1 | Not implemented | OUT OF SCOPE |
| Graphical guest desktop | No for v0.1 | Not implemented | OUT OF SCOPE |
| TUIsynth reference/demo entry | Yes later | Planned EDF-009 | NOT RUN |

The specification is a requirements contract, not completion evidence. Future issue/PR reports MUST continue to distinguish **required**, **implemented**, **tested**, **native-qualified**, and **human-qualified** states.
