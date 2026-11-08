# EDF-006 — host management TUI implementation stack

**Decision status:** selected/pinned candidate; **PHYSICAL-TUI PENDING**. Do not merge/close EDF-006 until the native Windows Terminal matrix below is executed against the exact candidate head and supports this decision.

**Decision source baseline:** `main@ae2dd266b7118f68a28500c84def00a18a889d10`; selection work began from EDF-006 PR head `a38fd7d7a67f7039481868e3e5767c8b297fbdf6` after its inherited 9-job merge gate and EDF-004/005 focused workflows were green.

## Decision

Select **Textual 8.2.8** as the host TUI runtime/framework, executed by a folder-local **CPython 3.12.10 Windows x64 embeddable runtime**. The exact runtime/wheel closure is locked in `manifests/edf006-tui-runtime.json`; acquisition is performed only by `scripts/Install-Edf006TuiRuntime.ps1`, which verifies SHA-256 before extracting any payload and does not run pip dependency resolution or sdists.

Textual is the **terminal/event/rendering shell**, not ezDarkFactory authority. EDF-007 must retain the project-owned seams already proven in this PR:

- semantic command catalogue/preflight: `tools/edf006_commands_spike.py`;
- layout/hit/capture/overlay reducer: `tools/edf006_layout_spike.py`;
- semantic scene/protection/fallback/damage model: `tools/edf006_scene_spike.py`;
- bounded generation-tagged observation scheduling: `tools/edf006_observation_spike.py`;
- optional portable one-writer manager workspace/session: `tools/edf006_workspace_spike.py`;
- bounded trusted EDF-005 read bridge: `tools/edf006_readonly_bridge.py`;
- accepted per-factory identity/mutation/reconciliation authority: EDF-005 PowerShell control plane.

The TUI never edits instance JSON, QCOW2 metadata, process evidence, trust files, keys or QMP state directly.

## Why Textual 8.2.8

The selected version is the current PyPI release at this decision checkpoint and is explicitly classified for Windows 10/11 and Python 3.12. Its own Windows driver enables VT200 button mouse, any-event mouse movement, SGR mouse coordinates, bracketed paste, FocusIn/FocusOut, alternate-screen rendering, and corresponding shutdown mode resets. The framework exposes `AppFocus`, `AppBlur`, `Paste`, `Resize`, mouse down/up/move/wheel events and a headless `run_test`/`Pilot` surface for synthetic key, pointer and resize qualification.

The checked-in integration probe does not merely inspect APIs: it routes Textual `AppBlur` into the first-party divider rollback contract, treats `Paste` as data rather than semantic command input, routes terminal resize into the first-party layout reducer, exercises a semantic key binding, and exercises synthetic pointer delivery. It also verifies the installed pinned Windows-driver source still contains the required enable/disable transitions.

Upstream identity:

- project: `textual`;
- version: `8.2.8`;
- Git tag: `v8.2.8`;
- Git commit: `1d99508b928a771b51e1a527319c6b87dcff9e05`;
- wheel SHA-256: `267375fd402dc8d981457212efa71f0e3365fd17bba144ba9bb3ed7563cb374a`;
- license: MIT.

## Alternatives considered

| Candidate | Decision | Reason |
|---|---|---|
| Textual 8.2.8 | **Select, pending physical gate** | Native Windows classification, async application model, explicit focus/paste/resize/mouse events, deterministic full-screen rendering, mature widgets, headless `Pilot`, and terminal-mode restoration source all align with the tailored contract. |
| prompt_toolkit 3.0.53 | Reject as primary runtime | Lightweight and mature on Windows, with mouse and bracketed paste, but its public key/input model does not provide a comparably direct terminal `FocusIn`/`FocusOut` application event seam. EDF would need extra native focus plumbing alongside its UI framework. Historical use is evidence only. |
| Urwid 5.1.0 | Reject | Current Windows notes explicitly describe partial support, unsupported terminal widget/render facilities, incorrect fast mouse handling under curses, and UTF-8-only support. Those are poor matches for the required pointer and deterministic fallback matrix. |
| first-party raw Win32/VT only | Retain as diagnostic/fallback seam, reject as production framework | The existing probe proves low-level events are accessible, but selecting it would require EDF to build and maintain the async UI runtime, widget/event loop, renderer lifecycle and synthetic test infrastructure that Textual already supplies. |

No MDBM behavior/source was consulted or imported.

## Reproducible acquisition and portability

The manager runtime is generated **outside the source repository** inside an explicit portable manager-workspace/setup destination. It is convenience/runtime material, not factory authority. Loss of the manager runtime or manager workspace cannot make a factory unusable through its checked-in CLI/control path.

Pinned CPython:

- CPython `3.12.10`, Windows x64 embeddable package;
- official versioned URL under `www.python.org`;
- SHA-256 and official release-page MD5 recorded in the lock;
- license: PSF-2.0.

Pinned Textual dependency closure is copied from the Textual 8.2.8 project lock and reduced to non-optional pure-Python runtime wheels only. Syntax/tree-sitter extras are deliberately excluded. Each wheel is identified by project, exact version, exact `py3-none-any.whl` filename and SHA-256. Installation resolves only the exact filename through PyPI metadata, requires `files.pythonhosted.org`, independently checks the metadata hash against the checked-in lock, downloads once, verifies SHA-256, and extracts without executing package build hooks. No `pip install`, dependency resolver, sdist or hidden user-site state is used.

The generated runtime enables only its own `Lib/site-packages` from the embedded `python312._pth`. It does not alter machine PATH, registry, `%LOCALAPPDATA%` or `%APPDATA%`.

## Persistence and one-writer ownership

Authoritative factory identity, instance state, lifecycle/storage locks, operation receipts and credentials remain inside each factory root under the EDF-005 contracts.

The optional portable manager workspace owns only cross-factory convenience state: configuration, registry, session/layout and bounded manager journal. The existing EDF-006 one-writer spike uses an OS-backed cooperative writer lock; read-only observers may still inspect safely. Corrupt/missing/oversize session state enters safe-start defaults rather than becoming authority. No critical factory state depends on this workspace.

## Input, renderer and command seams for EDF-007

EDF-007 must normalize Textual events before semantic dispatch:

- `MouseDown` / `MouseUp` / `MouseMove` / wheel → first-party pointer router/capture;
- `AppBlur` → mandatory rollback of active continuous capture;
- `Resize` → first-party deterministic layout solve, rolling back stale capture;
- `Paste` → data event allowed only in explicit text fields, never implicitly reinterpreted as a command;
- key bindings → semantic command IDs from the first-party registry;
- Textual renderable/widget state → first-party semantic scene roles/protection, then final renderer encoding.

One Textual application owns terminal state. External managed SSH attach remains a separate process from the typed EDF-005 shell descriptor; v0.1 does not embed an arbitrary PTY.

## Automated evidence at selection checkpoint

Before this decision increment, PR head `a38fd7d7a67f7039481868e3e5767c8b297fbdf6` had:

- EDF fast merge gate: PASS, all 9 jobs;
- EDF-004 focused workflow: PASS, 2/2;
- EDF-005 focused workflow: PASS, 2/2;
- hosted Ubuntu/Windows Python suite: 190/190 PASS on each, including the semantic scene/theme/damage tests;
- synthetic/native probes for layout, pointer normalization, paste refusal boundaries, workspace locking, bounded observation, read bridge and console restoration instrumentation.

This decision adds a separate Windows exact-head workflow that installs the **actual locked runtime** and executes the Textual/first-party integration probe. Its result is FAST-CI only.

## Native Windows Terminal evidence — required before merge

**PHYSICAL-TUI PENDING.** Headless CI cannot close this gate.

On the exact final candidate, record:

- Windows build and privilege class;
- Windows Terminal version;
- Textual `8.2.8`, CPython `3.12.10`, source commit/tree and lock hash;
- 80×24 and 160×48 viewport/scaling;
- color/Unicode mode and high-contrast/reduced-motion settings.

Exercise and retain observations for:

1. mouse press/release/move/wheel;
2. divider drag, including focus loss and resize during capture;
3. overlays/context dismissal with no click-through;
4. bracketed paste into an allowed field, including command-like text such as `q`/`Ctrl+P` literals;
5. Unicode/ASCII and truecolour/256/16/mono fallbacks;
6. normal exit and deliberate crash/exception terminal restoration;
7. input-to-visible-frame p95 target `<100 ms`, with composition percentiles recorded separately;
8. external managed-shell launch/return;
9. manager close/reopen while a fixture/real VM continues independently.

The existing native probe remains useful as an independent low-level comparison, but it does not substitute for this selected Textual runtime gate.

## Known limitations / risk controls

- Textual release artifacts on PyPI do not carry PyPI provenance attestations at 8.2.8; therefore EDF pins the upstream signed Git tag/commit **and** exact PyPI wheel hash, and executes only the verified wheel closure.
- Framework terminal/parser defects remain possible. Physical Windows Terminal acceptance is therefore a merge gate rather than a documentation-only follow-up.
- Textual/platformdirs defaults must never be used as factory or manager authority. EDF-007 must pass explicit manager-workspace paths into all persistent state owners.
- External theme loading remains optional and intentionally absent until a closed data-only schema can be justified; embedded safe/high-contrast/mono/ASCII behavior is authoritative for v0.1.
- Real QEMU/WHPX and final human usability remain EDF-011/EDF-012 evidence classes; EDF-006 physical TUI is specifically framework/input/render qualification.

## Packaging/licensing implications

The selected runtime introduces CPython (PSF) plus Textual (MIT) and its locked pure-Python runtime dependencies. EDF-012 packaging must carry the applicable license/notice texts and must not redistribute any unpinned wheel or optional syntax dependency. Runtime downloads/caches remain generated artifacts and are not committed. The exact lock is release provenance; an update to Textual, CPython or any transitive package requires a reviewed lock/ADR delta and requalification, not an implicit resolver refresh.

## Acceptance disposition

The implementation stack is now **selected and reproducibly pinned**, and the automated integration seam is defined. EDF-006 is **not accepted yet** because the required exact-candidate PHYSICAL-TUI campaign has not been run. Do not mark PR #28 Ready, merge it, or close issue #6 until that evidence is attached and the final exact-head automated checks are green.

## Bounded asynchronous observation worker seam (8 November 2026)

The issue branch additionally carries `tools/edf006_worker_pump.py` and
`tests/test_edf006_worker_pump.py`. Unlike the scheduler's earlier
dispatch-only model, this executes an injected read-only collector on
at most `max_inflight` actual Python worker threads. The Textual/UI thread
alone queues requests, harvests only already-finished futures and updates
the immutable observation read model. A slow root cannot occupy a second
worker slot under another observation class, and independent roots can
still progress. Exceptions and oversized/malformed records fail closed to
`unreachable`, retaining prior records only as noncurrent. Refreshed,
removed or relocated enrollment tokens cannot publish late results.
Closing the pump stops new work without falsely releasing running worker
capacity or waiting on a stuck adapter. Tests use inert threaded collectors;
no factory or VM is touched.

**Critical execution boundary:** This is a concrete concurrent
orchestration test, **not yet a production per-root adapter**. The collector
injection is trusted and must enforce its own independent process deadline
and in-stream capture limits; no Python thread can safely force-kill a
wedged collector. `tools/edf006_bounded_process.py` already provides a
restricted trusted *single-process* capture for the existing static
workspace bridge, but actual per-root EDF-005 adapter invocation,
root-isolated live observation, close/reap on physical Windows, idle memory,
and the under-100-ms presented-frame budget remain unmeasured. EDF-007
must not map a workspace-wide sequential static read onto separate
per-root thread tasks and claim isolation. The selected native framework,
physical operator and final acceptance gates above remain unchanged.

## Interpreter-exit behavior of concurrent observation workers

The EDF-006 read-only monitor previously used `ThreadPoolExecutor` workers
for the portable registry reader and per-root static collectors. Calling
`shutdown(wait=False)` is nonblocking to the UI thread but does **not**
prevent CPython from joining those worker threads when the interpreter exits.
A hung filesystem read could therefore prevent the host terminal from
returning even after the Textual application visibly closed.

The spike now launches daemon-backed `Future` tasks through
`edf006_daemon_future.py`; its existing scheduler and single-bootstrap
coalescing strictly bound runnable workers. Offline subprocess regressions
verify that closing while a synthetic reader is blocked does not wait for
the 45-second blocked task at interpreter exit.

The remedy is narrowly scoped to read-only diagnostics. Daemon termination
does not prove that a launched trusted PowerShell child was terminated: native
Windows Terminal tests must check process-tree cleanup for normal exit and
unavailable registered drives. EDF-007's effectful operation broker must
instead use explicit, cooperatively cancellable and reaped process ownership.
The PHYSICAL-TUI acceptance requirement and exact-head CI gate are unchanged.
