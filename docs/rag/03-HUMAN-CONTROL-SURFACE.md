---
document_id: EDF-HOST-MANAGER-UI
status: authority
version: 1.0
tailored_at_utc: 2026-10-30
project_audit_base: a756f9c1041e4e6a39cdfd951aebfd98857d15a8
specdocz_revision: 2e95d6931cc23862a4176c9d8ccb4da78f00c265
---

# ezDarkFactory host management TUI/GUI UI/UX and implementation specification

## Status and authority

This document is the authoritative ezDarkFactory project-specific UI/UX and implementation specification for the **host-side tile-native management TUI**.

The product direction is fixed for the current programme:

> **ezDarkFactory SHALL provide one host-side, mouse-and-keyboard, tile-native terminal GUI that can register, observe, and safely operate multiple local ezDarkFactory roots from one interface.**

The primary management interface is a **TUI with GUI-style workspace, pointer interaction, menus, overlays, tiles, direct manipulation, and semantic commands**. It runs on the Windows host. It is not a guest desktop and it does not make QEMU graphical display a prerequisite for human operation.

The CLI/helper path remains a recovery and automation surface.

This specification is subordinate to higher-priority project safety, lifecycle, storage, security, compatibility, repository, and issue requirements. Where those conflict with generic UI guidance, the project-specific rule here wins and the deviation is recorded.

Writing a requirement here is **not** evidence that it is implemented or qualified.

## Basis and exact source pin

Tailoring basis:

- `techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`
  - `tuiuiux/tile-native-gui-tui-uiux-spec.md`
  - Git blob `4c0d668fba6824d0109d3a774364e4ddb3e4af61`
  - role: **normative UI/UX baseline**
- `techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`
  - `tuiuiux/tile-native-gui-tui-implementation-spec.md`
  - Git blob `758a1383b5bef72ed9c71952659e48d7fd90a0ff`
  - role: **implementation pattern library**
- `techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`
  - `tuiuiux/tile-native-gui-tui-spec-tailoring.md`
  - Git blob `b0880fe38c243adb16ab6868970f8e6f977b8c81`
  - role: tailoring procedure used for this document

No MDBM-referenced variant was required for this tailoring pass. No MDBM-specific control, layout default, editor selection rule, or implementation constraint is inherited by implication. If a later design decision consults MDBM material, the exact source and the concrete lesson used MUST be recorded.

Project audit basis:

- ezDarkFactory `main` at `a756f9c1041e4e6a39cdfd951aebfd98857d15a8`;
- `AGENTS.md`;
- `RAG.md`;
- RAG documents 00 through 07;
- `docs/programme/PLAN-REVIEW.md`;
- `docs/programme/IMPLEMENTATION-PROGRAMME.md`;
- open implementation issues #1 through #12;
- historical EzVM architecture and TRIO field-study requirements already incorporated by the project RAG.

At that audit base the repository contained planning/RAG documents only: no active UI code, no broker implementation, no tests/workflows, and no PRs.

## Contents

1. **Product role and scope** — Defines the host manager, multi-factory boundary, and explicit non-goals.
2. **Domain and identity model** — Defines factories, instances, selections, observations, operations, and collision safety.
3. **Architecture and ownership** — Defines the manager/control-plane boundary and multi-root adapter model.
4. **Workspace and tile model** — Defines persistent views, default layouts, compact mode, and recovery.
5. **Command and input model** — Defines semantic commands, mouse/keyboard parity, focus, menus, and safety metadata.
6. **Multi-factory workflows** — Defines registration, fleet observation, selection, project creation, lifecycle, and diagnostics.
7. **Operations and destructive-action safety** — Defines confirmation, command ownership, concurrency, restart reconciliation, and batch limits.
8. **Logs, terminal interaction, and evidence** — Defines bounded logs, external attach, output safety, and provenance display.
9. **Theme, ANSI/ASCII, accessibility, and presentation** — Defines semantic styling, capability fallbacks, and restrained decoration.
10. **Persistence and recovery** — Separates manager configuration, root registry, session state, operation journal, and factory state.
11. **Responsiveness, polling, damage, and concurrency budgets** — Defines async collection, freshness, latency, memory, and stale-result rules.
12. **Implementation pattern decisions** — Records Adopt/Adapt/Reject/Extend decisions from the direct implementation specification.
13. **Material deviations from the reusable baseline** — Records project-specific differences and rationale.
14. **Project-specific acceptance criteria** — Defines automated, native Windows Terminal, lifecycle, multi-root, accessibility, and performance gates.
15. **Implementation and qualification status** — Separates required behavior from current implementation and evidence.
16. **Future specdocz delta policy** — Prevents silent inheritance from later shared-spec revisions.

# 1. Product role and scope

## 1.1 Primary product surface

The primary management surface SHALL be a host-side terminal application with GUI-like interaction.

It MUST:

- run on the Windows host without requiring WSL, Docker, a browser, or a guest desktop;
- manage more than one local ezDarkFactory root from one process;
- preserve each registered factory root as an independent lifecycle/storage/security authority;
- provide mouse and keyboard command parity;
- provide persistent tile identities and configurable workspace layout;
- support safe observation even when one or more factory roots are missing, stale, incompatible, slow, or partially broken;
- remain useful when no AI provider/model/agent is configured;
- remain recoverable through the underlying CLI/helpers if the TUI cannot launch.

The TUI MUST NOT become a second VM implementation.

## 1.2 V0.1 managed scope

V0.1 manages **local factory roots on the same Windows host**.

A factory root is an ezDarkFactory checkout/bundle that exposes the versioned control/broker capability required by this project.

Remote-host management is intentionally deferred. The multi-root identity and adapter design MUST leave room for a later remote transport without changing semantic command IDs or tile/workspace concepts.

## 1.3 Explicit non-goals for the primary manager

V0.1 does not require:

- a QEMU graphical console;
- a Linux guest desktop;
- embedded browser views;
- a general autonomous agent/provider dashboard;
- remote-host control;
- destructive batch operations across multiple factories;
- an embedded arbitrary PTY terminal emulator;
- detachable native GUI windows;
- drag/drop task routing between agents;
- a node/topology canvas.

These are not forbidden forever. They require explicit later specifications or deltas.

# 2. Domain and identity model

## 2.1 FactoryRoot

The manager manipulates registered **FactoryRoot** records.

A factory record MUST contain or resolve:

- stable `factory_id`;
- canonical current root path;
- human alias;
- product/control API version;
- capability set;
- last successful observation time;
- current observation state;
- source/runtime identity summaries where exposed;
- registration status.

The manager MUST NOT infer stable factory identity from a path alone.

The EDF control plane SHALL provide a stable factory identity suitable for registration. A cold relocation preserves that identity.

If two simultaneously reachable registered paths report the same `factory_id`, the manager MUST show an **identity collision / relocated-copy conflict** and disable mutations for those records until the user explicitly resolves which location is authoritative.

Registration itself MUST NOT start a VM or mutate guest/storage state.

## 2.2 InstanceRef

An instance target is composite:

```text
(factory_id, instance_name, instance_generation)
```

or a versioned equivalent with equal or stronger uniqueness.

Commands that can discard or preserve mutable guest state MUST bind to the exact target generation expected when the action was presented.

A stale UI selection MUST NOT reset, stop, clone, export, import into, or otherwise mutate a replacement instance that reused the same display name.

## 2.3 Observation state

Observation state is not lifecycle intent.

The manager MUST distinguish at least:

- `current` — fresh successful observation;
- `last-known` — retained previous valid observation;
- `stale` — age exceeds the declared freshness budget;
- `unknown` — no trustworthy current conclusion;
- `unreachable` — root/adapter cannot currently be contacted or executed;
- `incompatible` — root exists but control/capability contract is unsupported;
- `conflict` — identity or ownership ambiguity requires human reconciliation.

Persisted RUNNING/READY text is never displayed as current truth without current supporting observation.

## 2.4 Operation record

Every mutation visible through the manager MUST have an operation identity and target scope.

Minimum record:

- operation ID;
- command ID;
- factory ID;
- optional instance name/generation;
- requested arguments;
- requested time;
- expected revision/generation;
- operation state;
- current stage;
- final result/refusal/error category;
- evidence/log references;
- completion time.

Model/guest/log text is data and MUST NOT create operation authority.

# 3. Architecture and ownership

## 3.1 Required layering

```text
Windows Terminal
      |
tile-native host management TUI
      |
semantic command layer + manager reducer
      |
multi-factory registry/read model + root-scoped operation coordinator
      |
      +--> Factory A adapter --> Factory A control/broker --> QEMU/QCOW2/SSH/QMP
      +--> Factory B adapter --> Factory B control/broker --> QEMU/QCOW2/SSH/QMP
      +--> Factory C adapter --> Factory C control/broker --> QEMU/QCOW2/SSH/QMP
```

The manager reducer owns **manager UI/session state**.

Each factory control plane owns **factory domain mutation**.

The TUI, manager reducer, theme renderer, and root registry MUST NOT directly edit managed instance JSON, process evidence, QCOW2 metadata, keys, known-hosts, QMP state, or guest files outside accepted typed operations.

## 3.2 Factory adapter boundary

Each registered root is accessed through a versioned adapter.

An adapter MUST expose:

- identity/capabilities;
- observation/snapshot operations;
- typed mutation dispatch;
- bounded logs/diagnostics;
- operation/result reconciliation.

An adapter timeout or malformed response affects that root's state only. It MUST NOT block UI input or make unrelated roots appear idle/free.

## 3.3 No mandatory background service

V0.1 MUST NOT require a permanent Windows service.

The user-launched manager owns observation workers.

A mutation MAY use a root-scoped operation runner process that outlives the visible TUI long enough to preserve an already-authorized operation. Such a runner MUST be identified by operation ID and durable result location and MUST be reconcilable after manager restart.

Closing the TUI MUST NOT kill independently running QEMU processes.

## 3.4 Framework boundary

This specification does not mandate one TUI framework.

EDF-006 SHALL select and pin the implementation stack after a bounded native Windows Terminal spike.

The selected stack MUST support:

- real mouse press/release/move/wheel;
- focus-loss handling;
- async/bounded background observation;
- deterministic full-screen rendering;
- Unicode and ASCII fallback;
- terminal resize;
- bracketed/native paste control;
- testable synthetic/pipe input;
- clean terminal restoration after crash/exit.

Prior EzVM/prompt_toolkit experience is evidence, not automatic authority.

# 4. Workspace and tile model

## 4.1 Persistent tile identities

V0.1 SHALL define these persistent logical tiles:

| Tile ID | Purpose |
|---|---|
| `fleet` | Cross-factory overview of registered roots and instances |
| `navigator` | Hierarchical factory → project/instance navigation and filter |
| `inspector` | Selected factory/instance identity, lifecycle, readiness, capabilities, and safe actions |
| `operations` | Active/recent operation progress, results, refusals, and recovery state |
| `logs` | Bounded selected-root/instance logs, diagnostics, and evidence |
| `resources` | Host/factory/instance allocation and observed resource summaries |

A tile retains its local state across hide/show, resize, swap, stack, maximize, responsive collapse, and workspace preset changes.

Local state includes where relevant:

- selected row;
- filter;
- sort;
- expanded nodes;
- scroll position;
- active tab/subview;
- follow mode;
- navigation history.

## 4.2 Default layouts

Built-in workspace presets SHALL include:

- **Overview** — navigator + fleet + inspector with operations/log summary;
- **Operations** — fleet/inspector + expanded operations;
- **Diagnostics** — inspector + logs + operations;
- **Resources** — fleet + resources + inspector;
- **Recovery** — inspector + operations + logs with destructive actions prominently gated.

User-defined layout persistence MAY be added in v0.1 if the selected framework supports it cleanly; built-in presets and current-session custom layout are REQUIRED.

## 4.3 Layout model

The workspace SHALL use a deterministic split/stack constraint model.

A split stores:

- orientation;
- ratio;
- child identities;
- minimum sizes;
- persisted preference;
- one-cell structural divider in TUI presentation.

Divider drag is transactional:

- pointer capture on press;
- tracking outside original divider;
- clamped preview;
- single commit on release;
- Escape rollback;
- focus-loss rollback.

Final solved geometry is authoritative for hit testing.

## 4.4 Responsive modes

Required viewport fixtures:

- **40×12** — emergency recovery/compact mode only; one focused tile plus command/help/restore routes;
- **80×24** — minimum useful focused management mode;
- **120×40** — normal multi-tile operation;
- **160×48** — preferred fleet workspace;
- **200×60** — large-layout stress/expansive mode.

When multi-tile minimums fail, the manager MUST enter focused-tile compact mode rather than crushing multiple tiles into unusable rectangles.

Decoration yields before content.

An all-hidden/corrupt layout always retains:

- command palette;
- restore-all;
- safe layout reset;
- help;
- guarded quit.

# 5. Command and input model

## 5.1 Semantic command registry

Every application action SHALL have a stable semantic command ID.

Minimum command families include:

```text
factory.register
factory.unregister
factory.refresh
factory.rename_alias
factory.open_root
factory.resolve_identity_conflict

instance.create
instance.start
instance.stop
instance.open_shell
instance.exec
instance.copy_to
instance.copy_from
instance.diagnose
instance.reset
instance.clone_fresh
instance.clone_stateful
instance.export
instance.import
factory.portability_check

view.focus_next
view.focus_previous
tile.hide
tile.restore_all
tile.maximize_toggle
layout.preset_select
layout.reset
theme.select
filter.open
help.open
command_palette.open
app.quit_guarded
```

Actual IDs may be refined before implementation but MUST remain semantic and stable once released.

## 5.2 Command metadata extensions

Each command spec MUST include, directly or through typed metadata:

- ID;
- label/category/help;
- enabled predicate;
- keyboard route(s);
- pointer route(s);
- discoverability;
- target scope;
- required capabilities;
- destructive class;
- confirmation policy;
- concurrency class;
- safe retry/reconciliation policy.

## 5.3 Mouse/keyboard parity

Every keyboard-accessible application command MUST have a practical pointer route.

Every meaningful pointer-only semantic action MUST have a keyboard route unless the action is inherently continuous pointer input and has a semantic keyboard equivalent.

Pointer routes may use:

- menu;
- command palette;
- tile title control;
- context menu;
- clickable row/control;
- divider drag;
- local wheel.

No core operation requires an F-key, numpad key, PageUp, or PageDown.

Required permanent recovery routes:

- `Ctrl+P` or an accepted equivalent: command palette;
- `Ctrl+T` or accepted equivalent: restore hidden tiles/layout recovery;
- `Tab` / `Shift+Tab`: focus traversal;
- `Escape`: cancel drag / dismiss one overlay level / return from transient mode;
- a guarded quit command with both keyboard and pointer routes.

Exact bindings are configurable except reserved recovery routes.

## 5.4 Focus and pointer behavior

A click on an actionable control in an unfocused tile MUST focus and act in one gesture unless the specific action has a documented safety reason to require a second step.

Wheel scrolling belongs to the tile under the pointer and MUST NOT move keyboard selection in another tile.

Right-click opens a context menu appropriate to the pointed factory/instance/row. Right-clicking inside an existing text/log selection preserves that selection.

## 5.5 Overlays

Command palette, menus, confirmation dialogs, add-factory flow, project creation flow, help, and other transient UI use an explicit overlay stack.

Top overlay receives input first.

Outside-click dismissal is consumed and cannot click through.

Escape closes exactly one logical overlay level.

Menus clamp to the visible terminal rectangle.

# 6. Multi-factory workflows

## 6.1 Register factory

The user can register a factory through:

- pointer-accessible **Add Factory** action;
- command palette;
- keyboard command route.

Registration flow:

1. choose/enter local root;
2. canonicalize path without losing the user-visible form;
3. invoke read-only identity/capability probe;
4. show factory ID, product version, compatibility, path, and basic state;
5. warn on duplicate path or factory-ID collision;
6. save only after explicit confirmation.

Registration MUST NOT bootstrap, start, repair, reset, or otherwise mutate the root.

Unregistering removes it from the manager registry only; it MUST NOT delete the factory directory or its VM state.

## 6.2 Fleet overview

The fleet view shows all registered roots, including unreachable/incompatible/conflicting roots.

For each root it SHOULD summarize:

- alias;
- path tail;
- compatibility;
- freshness/age;
- number of instances by meaningful state;
- active operation count;
- important warning/error state.

Unknown values render as unknown/em dash, never zero.

## 6.3 Instance selection

Selecting an instance updates inspector/log/resource context but does not trigger mutation.

Selection is bound to factory + instance identity, not display name alone.

Cross-factory filters/sorts MUST retain factory identity visibly enough to prevent acting on the wrong root.

## 6.4 Create fresh project

The manager provides a guided project/instance creation flow using the accepted project kickoff contract.

At minimum:

- choose target factory;
- enter project/instance name;
- select resource profile/overrides;
- select empty workspace by default;
- optional explicit Git clone/local-copy source;
- preview action;
- confirm target root and consequences;
- dispatch typed operation;
- track progress/result.

No TUIsynth/provider/model/agent is selected automatically.

## 6.5 Lifecycle

Start/stop/diagnose and later accepted lifecycle actions are root-scoped typed operations.

The interface MUST display stage and evidence rather than freezing while a start waits for readiness.

Close/reopen of the manager does not imply stop.

## 6.6 Diagnostics and recovery

When a target is UNKNOWN, CONFLICT, or otherwise unsafe:

- destructive commands are disabled;
- inspector shows exact persisted/observed discrepancy;
- bounded diagnostics remain available;
- Recovery workspace/preset is offered;
- unsafe “repair by deleting runtime files” is never a default action.

# 7. Operations and destructive-action safety

## 7.1 Confirmation classes

Commands are classified at minimum:

- **read-only** — no confirmation;
- **ordinary mutation** — explicit target visible; one action confirmation where appropriate;
- **state-sensitive** — confirmation states what is preserved/discarded;
- **destructive** — exact factory/instance/generation and consequence; may require typing/choosing the exact target name for high-risk cases.

Generic “Are you sure?” is insufficient for reset/import replacement/stateful-sensitive operations.

## 7.2 Per-root operation ownership

The manager MAY run independent operations concurrently on different factory roots subject to a global budget.

Within one factory root, the manager MUST respect root locks and declared concurrency classes.

A duplicate click/request with the same operation intent MUST NOT create two destructive operations.

## 7.3 Batch operations

V0.1 MAY provide multi-select for comparison/filtering/read-only inspection.

V0.1 MUST NOT provide one-click batch reset, batch stop, batch import, or other destructive multi-factory operations.

If later introduced, each target must have explicit identity and per-target result/reconciliation.

## 7.4 Manager restart

The manager maintains a bounded operation journal.

On restart it:

- does not blindly replay mutation requests;
- reconciles pending operations with the root;
- marks uncertain operations as needing reconciliation;
- preserves final results/evidence;
- never interprets missing UI acknowledgement as permission to rerun.

# 8. Logs, terminal interaction, and evidence

## 8.1 Logs

The logs tile is read-only.

It supports:

- bounded tail/history;
- source selector;
- filter/search;
- follow toggle;
- visible truncation/rotation indication;
- copy-safe text;
- freshness and source identity.

Terminal escape/control sequences from logs are data and MUST NOT execute terminal, clipboard, title, or cursor-control effects.

## 8.2 Guest shell/terminal

V0.1 **rejects an embedded arbitrary PTY terminal as a release requirement**.

`instance.open_shell` uses the accepted root control API to obtain the exact managed SSH/attach command and then:

1. opens a separate Windows Terminal tab/window through a typed launcher when that capability is available and qualified; or
2. presents/copies the exact command for the user.

The manager remains responsive and retains the selected target.

Launching an external shell is explicit. Merely focusing the logs tile never forwards input to the guest.

An embedded terminal may be added only through a future delta with explicit input-ownership, paste, resize, scrollback, terminal restoration, and process-lifetime tests.

## 8.3 Evidence

Where operations expose source/runtime/check evidence, the UI presents:

- operation/source identity;
- actual result class;
- evidence/log reference;
- whether evidence is current/stale;
- explicit SKIP/UNMEASURED/HUMAN-PENDING distinctions where relevant.

The TUI does not decide release acceptance by parsing success-like prose from logs.

# 9. Theme, ANSI/ASCII, accessibility, and presentation

## 9.1 Semantic styling

Presentation uses semantic roles, not hard-coded per-control colors.

Required roles include:

- background;
- text;
- muted;
- border;
- title;
- accent;
- heading;
- code;
- link;
- selection;
- diagnostic;
- status;
- warning;
- error;
- success;
- stale;
- unknown;
- conflict;
- destructive.

Required state modifiers include focused, hover, pressed, selected, disabled, busy, caution, and destructive.

## 9.2 Capability degradation

The TUI SHALL degrade deterministically:

```text
truecolour → ANSI-256 → ANSI-16 → monochrome
Unicode → ASCII
motion → reduced motion → motion off
```

Text labels MUST carry status meaning; color/glyph alone is insufficient.

Wide glyphs are clipped atomically and never split across tile boundaries.

## 9.3 Themes

V0.1 MUST ship an embedded safe theme, high-contrast behavior, and monochrome/ASCII-safe presentation.

A closed data-only external theme format MAY be implemented if it does not delay core management. If implemented:

- theme input is non-executable;
- invalid themes fail atomically;
- preview is transactional;
- safe theme recovery remains available.

No theme may change command semantics or cover critical controls.

## 9.4 Decoration and ANSI art

ezDarkFactory MAY use restrained factory/cyberpunk ANSI/ASCII decoration.

Decoration is subordinate to management content.

It MUST:

- render only inside layout-approved decorative masks;
- shrink/disappear before usable content;
- never overwrite critical/interactive cells;
- have deterministic ASCII/mono fallbacks;
- be disabled or frozen by reduced-motion/motion-off;
- not change hit geometry unexpectedly.

No animation is required for v0.1.

# 10. Persistence and recovery

## 10.1 Four distinct state classes

The manager SHALL keep these conceptually and physically separable.

### Manager configuration

User policy/defaults:

- refresh budgets;
- theme/accessibility;
- input bindings;
- default workspace;
- concurrency limits;
- optional configured state directory.

Normal layout interaction does not rewrite hand-maintained config silently.

### Factory registry

Manager-owned durable list:

- factory ID;
- alias;
- canonical path;
- last known adapter/control version;
- registration metadata.

Registry data is not stored inside one selected factory as the sole authority.

### Session state

Machine-written dynamic UI state:

- active workspace;
- tile visibility/placement/ratios;
- focused tile;
- selections/filters/scroll memory;
- committed theme;
- last selected factory/instance where safe.

### Operation journal

Bounded generated operation/reconciliation records.

It is not VM lifecycle authority.

## 10.2 Host storage

Default manager state SHOULD live in a user-local application-data location such as:

```text
%LOCALAPPDATA%\ezDarkFactory\manager\v1\
```

or a versioned equivalent selected during implementation.

A `--state-dir`/test/portable override MAY be supported.

This user-local manager state does not violate the portable factory-root model because it stores only manager registry/session/journal data, not QEMU/base/overlay authority.

## 10.3 Safe start

A safe-start mode is REQUIRED:

- embedded safe theme;
- default layout;
- no prior session restore;
- registry validation before use;
- no mutation;
- clear route to repair/reset manager session state.

A further no-refresh/offline test mode MAY be supplied for recovery.

# 11. Responsiveness, polling, damage, and concurrency budgets

## 11.1 Event loop

No factory observation, PowerShell invocation, SSH read, log read, or filesystem scan may block the UI event loop.

Collectors publish immutable results tagged with factory identity and generation.

Late/stale results are discarded if a newer request/generation exists.

## 11.2 Observation scheduling

Default scheduling SHALL be bounded and fair.

Target behavior for the qualified reference configuration:

- selected factory/instance: visible data refresh target no slower than about 2 seconds when the underlying operation supports it;
- unselected registered factories: complete observation cycle target no slower than about 10 seconds for the supported reference scale;
- at most one ordinary observation request of a given class in flight per factory;
- bounded global observation concurrency, configurable with a conservative default;
- one slow/unreachable root cannot starve the others.

Each sample carries observed time/age and error/freshness state.

These are UI observation targets, not VM readiness deadlines.

## 11.3 Reference scale

Automated load fixtures SHALL cover at least:

- 16 registered factory roots;
- 128 aggregate instance rows;
- mixed reachable/unreachable/incompatible/conflicting roots;
- active operations on multiple independent roots;
- at least 10,000 bounded log/history records through the display/cache test path.

This scale is a qualification fixture, not a claim that higher scale is unsupported.

## 11.4 Latency targets

On the supported Windows Terminal qualification host:

- p95 command/navigation input-to-frame target: **< 100 ms** while background collectors are active;
- no deliberate collector wait on the UI thread;
- composition p50/p95/p99 recorded separately from terminal presentation;
- rapid resize/pointer movement MUST remain bounded and recover;
- unchanged frame SHOULD produce zero logical damage;
- local control/focus changes SHOULD produce bounded logical damage instead of unconditional clear/repaint.

If native measurements require revised thresholds, the change requires a reviewed decision with exact method/results; thresholds may not drift silently.

## 11.5 Resource target

Manager TUI + collectors, excluding QEMU guests and intentionally launched external terminals, SHOULD remain below **200 MiB RSS** in the reference-scale idle/observation test.

This is a review target until measured. Exceeding it requires a recorded design decision rather than hiding child-process memory or changing the denominator.

# 12. Implementation pattern decisions

The following table classifies relevant patterns from the pinned direct implementation specification.

| Pattern | Decision | ezDarkFactory result |
|---|---|---|
| Semantic `CommandRegistry` | **Adopt** | One stable command layer for menu, keyboard, context, pointer controls, palette, and help |
| Controller/reducer as sole mutable application owner | **Adapt** | Manager reducer owns UI/registry/session state; factory mutation remains exclusively in each root control plane |
| Persistent `TileRegistry` | **Adopt** | Fleet, Navigator, Inspector, Operations, Logs, Resources have stable identities independent of geometry |
| Immutable application snapshot model | **Adapt** | UI snapshots are immutable; external operational truth is versioned root observations rather than reducer-owned VM state |
| Split-tree/constraint layout | **Adopt** | Deterministic splits + stacks with one-cell dividers, minimums, compact mode, and persisted ratios |
| Detachable native windows | **Reject** | Primary surface is one terminal workspace; future native GUI/windowing is a later delta |
| Geometry-derived `HitMapBuilder` | **Adopt** | Hit regions are generated from final solved/rendered geometry |
| Pointer capture / transactional drags | **Adopt** | Divider and future continuous controls capture, preview, commit once, Escape/focus-loss rollback |
| `InputRouter` normalization | **Adopt** | Key/text/pointer/wheel/focus/resize/paste normalized before semantic dispatch |
| Overlay/modal stack | **Adopt** | Menus, command palette, help, add-factory, create-project, confirmations use deterministic z-order/no-click-through |
| Shared semantic cell/scene compositor | **Adopt** | Cell scene carries semantic role/state/protection independent of final ANSI encoding |
| Protection classes for decoration/content/critical UI | **Adopt** | Theme/ANSI layers cannot overwrite lifecycle status, confirmations, selection, focus, or destructive controls |
| Data-only `ThemeCompiler` | **Adapt** | Built-in safe/high-contrast themes required; external theme loading optional until closed-schema safety is implemented |
| Adaptive ANSI/ASCII compositor | **Adapt** | Restrained management decoration only; content priority, ASCII/mono fallback, no required animation |
| Text-editor global selection conventions | **Reject** | Apply text-selection rules only inside actual log/text surfaces; no editor semantics for fleet/inspector controls |
| Configuration/session separation | **Extend** | Four-way separation: config, factory registry, session, operation journal, plus factory-owned runtime state outside manager authority |
| Safe launch/reset layout | **Adopt** | Safe theme + default layout + no session restore + zero mutation |
| Generation-tagged background work | **Extend** | Results keyed by factory + request generation; per-root fairness and stale-result rejection |
| Logical damage tracking | **Adopt** | Zero-damage unchanged scene and bounded local updates are testable requirements |
| Bounded background queue | **Adopt** | Replaceable observation requests and bounded root concurrency; no unbounded polling queue |
| One authoritative renderer | **Adopt** | One TUI renderer owns terminal state; external shell/guest windows are separate processes |
| Embedded live PTY terminal pane | **Reject** for v0.1 | Use explicit external Windows Terminal/SSH attach; embedded PTY requires a future spec delta |
| Job queue visualization | **Adapt** | Operations tile shows manager/root operations and reconciliation, not AI-agent jobs |
| Agent topology canvas | **Reject** | No agent topology domain in v0.1 |
| Drag/drop task routing | **Reject** | No task-routing domain in v0.1 |
| Multi-selection | **Adapt** | Read-only compare/filter selection allowed; destructive batch mutation prohibited in v0.1 |
| Conformance parity audit | **Adopt** | Registry tests fail missing keyboard/pointer routes except explicitly justified input-only semantics |
| Native terminal acceptance | **Extend** | Windows Terminal is the primary release-qualified TUI surface with multi-factory and lifecycle-specific gates |

# 13. Material deviations from the reusable baseline

## 13.1 Host TUI is selected, not merely one possible front end

**Deviation:** the reusable baseline is GUI/TUI-neutral; ezDarkFactory selects a host-side tile-native TUI as the current programme's primary management UI.

**Rationale:** one process can manage multiple factory roots without altering each guest/base, it preserves the proven headless VM boundary, and it leaves room for future native GUI/remote adapters.

**Status:** permanent for v0.1; revisitable only by explicit project/spec delta.

## 13.2 Multi-factory registry extends the generic tile model

**Extension:** the manager has stable FactoryRoot identities, collision detection, per-root adapters, fair polling, and root-scoped operations.

**Rationale:** managing multiple ezDarkFactories is a core product requirement, not a presentation detail.

## 13.3 Guest GUI/desktop is removed from the v0.1 management requirement

**Deviation:** a QEMU graphical console or guest desktop is not required for primary operation.

**Rationale:** host management does not need to couple product usefulness to guest graphics. SSH/external terminal remains the normal guest interaction path.

This does not prohibit future graphical guest profiles.

## 13.4 Embedded PTY is not required in v0.1

**Deviation:** the generic implementation patterns permit terminal panes; ezDarkFactory uses external attach for v0.1.

**Rationale:** explicit process/input ownership and terminal restoration are high-risk complexity not needed to satisfy multi-factory management.

## 13.5 Destructive batch operations are prohibited

**Extension/safety restriction:** no batch reset/stop/import across factories in v0.1.

**Rationale:** composite target identity and independent root ownership make accidental bulk mutation disproportionately risky.

## 13.6 40×12 is recovery-only

**Adaptation:** generic small-screen testing is retained, but 40×12 need not show a useful multi-factory dashboard.

**Rationale:** honest single-tile recovery mode is better than compressing operational state into unreadable geometry.

## 13.7 Manager state is user-local rather than owned by one factory root

**Adaptation:** registry/session/journal state SHOULD live in user-local application data.

**Rationale:** a manager that controls multiple roots must not make one managed root its configuration authority.

Factory VM/runtime state remains portable and root-local.

# 14. Project-specific acceptance criteria

## 14.1 Command parity

Automated registry audit MUST prove:

- every keyboard semantic command has a pointer route;
- every meaningful pointer semantic command has a keyboard route;
- reserved recovery commands are present;
- no destructive command lacks safety metadata and target scope;
- no core action requires F-keys, numpad, PageUp, or PageDown.

Native tests MUST verify focus-and-act, context menu, wheel locality, overlay click consumption, divider capture/rollback, and focus-loss cleanup.

## 14.2 Multi-factory identity and isolation

Tests MUST cover:

- register 16 distinct roots;
- duplicate path registration;
- same `factory_id` at two locations;
- moved/offline root;
- incompatible control version;
- malformed root response;
- one slow root while others remain fresh;
- simultaneous independent operations on different roots;
- root A failure never mutates or corrupts root B manager state;
- unregister does not delete/mutate root;
- stale instance generation refuses destructive action.

## 14.3 Lifecycle safety

Using synthetic/native fixtures and later real roots:

- opening/refreshing manager starts zero VMs;
- manager exit starts/stops zero VMs unless an explicit command was confirmed;
- a started VM survives manager close/reopen;
- operation restart reconciliation does not duplicate mutation;
- UNKNOWN/CONFLICT disables destructive storage actions;
- persisted lifecycle text never overrides contradictory current process evidence.

## 14.4 Workspace/layout

Test 40×12, 80×24, 120×40, 160×48, and 200×60.

Verify:

- tile state survives hide/show/swap/resize/maximize/compact;
- split ratios clamp;
- decorations yield first;
- all-hidden layout is recoverable;
- safe-start ignores corrupt session layout;
- scroll/filter/selection remain bound to the correct tile and target identity.

## 14.5 Logs/output safety

Tests MUST replay hostile and large output containing:

- ANSI cursor/title sequences;
- OSC clipboard-like sequences;
- malformed Unicode;
- very long lines;
- output flood;
- rotation/truncation.

No replayed log content may execute terminal control side effects.

## 14.6 Theme/accessibility

Test:

- truecolour;
- ANSI-256;
- ANSI-16;
- monochrome;
- Unicode;
- ASCII-only;
- high contrast;
- reduced motion;
- motion off;
- keyboard-only;
- mouse command routes.

Status meaning cannot depend solely on color.

Invalid external theme data, if supported, leaves the previous valid theme unchanged.

## 14.7 Performance and scale

At reference scale (16 factories / 128 instance rows / 10,000 history records):

- input-to-frame p95 target <100 ms on qualified Windows Terminal host;
- composition p50/p95/p99 recorded separately;
- one 10-second simulated root stall does not block input or other root refresh;
- no unbounded observation/job queue;
- unchanged frame gives zero logical damage;
- idle/observation manager RSS target <200 MiB excluding guests/external attach processes.

## 14.8 Native Windows Terminal qualification

On exact release candidate, record:

- Windows build;
- Windows Terminal version;
- TUI runtime/framework version;
- source commit/tree;
- terminal size/scaling;
- color/Unicode mode.

Exercise:

- mouse press/release/move/wheel;
- focus loss during drag;
- resize during drag;
- context menus;
- paste into allowed fields;
- overlay dismissal;
- 80×24 compact and 160×48 fleet modes;
- high contrast/reduced motion;
- crash/normal exit terminal restoration;
- external shell launch/return;
- manager close while a fixture/real VM remains running.

Headless test evidence alone is not PHYSICAL-UI PASS.

## 14.9 Human workflow

A person using only checked documentation must be able to:

1. launch manager;
2. register at least two local factory roots;
3. identify reachable/unreachable/conflicting state;
4. create/select a project/instance in the intended factory;
5. start and observe readiness;
6. open the exact guest shell path;
7. inspect logs/resources;
8. stop/restart safely;
9. perform one clone/export/recovery workflow when that feature is implemented;
10. quit the manager without accidental VM termination.

# 15. Implementation and qualification status

Audit base: ezDarkFactory `a756f9c1041e4e6a39cdfd951aebfd98857d15a8`.

| Area | Required by this spec | Current implementation at audit base | Qualification |
|---|---|---|---|
| Multi-factory host manager | Yes | Not implemented | NOT RUN |
| Factory identity/registry | Yes | Not implemented | NOT RUN |
| Typed per-root adapter/broker | Yes | Planned in EDF-005; no code | NOT RUN |
| Semantic command registry | Yes | Not implemented | NOT RUN |
| Persistent tile workspace | Yes | Not implemented | NOT RUN |
| Mouse/keyboard parity | Yes | Not implemented | NOT RUN |
| Windows Terminal TUI | Yes | Not implemented | NOT RUN |
| Theme/accessibility fallbacks | Yes | Not implemented | NOT RUN |
| Operation journal/reconciliation | Yes | Not implemented | NOT RUN |
| External managed SSH attach | Yes | Historical EzVM behavior exists upstream; EDF implementation absent | NOT RUN in EDF |
| VM lifecycle/storage control | Yes, via root control plane | Historical source only; EDF import pending | NOT RUN in EDF |
| GUI guest display/desktop | No v0.1 requirement | Not implemented | OUT OF SCOPE |
| Embedded PTY | No v0.1 requirement | Not implemented | REJECTED FOR V0.1 |
| Multi-root destructive batch actions | No | Not implemented | PROHIBITED FOR V0.1 |
| Automated UI tests | Yes | No test suite yet | NOT RUN |
| Physical UI qualification | Yes | Not performed | HUMAN/PHYSICAL PENDING |

EDF issues SHALL treat “required, unimplemented” as work to deliver, not as a reason to weaken this specification.

# 16. Future specdocz delta policy

This project is pinned to `specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`.

A future `specdocz` change has **no automatic effect** on ezDarkFactory.

To update the baseline:

1. record old and proposed new specdocz commit SHAs;
2. diff the normative UI/UX and implementation-pattern files;
3. identify only material relevant changes;
4. classify each as Adopt, Adapt, Reject, or Extend;
5. update this project-specific document deliberately;
6. update the recorded source pin;
7. add/modify acceptance tests where the change affects behavior;
8. review the change under normal project PR/merge rules.

A new specdocz version MUST NOT silently reinterpret an already accepted ezDarkFactory release or issue.
