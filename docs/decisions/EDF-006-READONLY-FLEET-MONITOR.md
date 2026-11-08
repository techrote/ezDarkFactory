# EDF-006 — real Textual read-only multi-root monitor spike

**Evidence boundary:** SOURCE / FAST-CI-HEADLESS only. This is not the EDF-007
production manager, physical Windows Terminal acceptance, guest/WHPX lifecycle
evidence, or real instance inventory. All displayed "current" observations
mean verified **static factory identity only**, never READY.

## Purpose

The prior EDF-006 components included a generation-safe observation scheduler,
real bounded worker threads and an independently deadline-bounded trusted
PowerShell per-root collector, but had no single executable Textual application
that composed them. The new `tools/edf006_fleet_monitor.py` demonstrates this
actual integration on the pinned Textual 8.2.8 runtime.

An operator with an existing portable EDF-005 manager workspace may launch it
with the pinned Python runtime installed by `Install-Edf006TuiRuntime.ps1`:

```powershell
$Python = @(& .\scripts\Install-Edf006TuiRuntime.ps1 -DestinationRoot 'D:\edf006-python') | Select-Object -Last 1
& $Python -I .\tools\edf006_fleet_monitor.py --workspace 'D:\portable manager'
```

The manager workspace must exist. This application never creates, registers,
removes, starts, stops, attaches to, or mutates any factory, VM or workspace.
Press **r** to reload the portable manager registry and then reobserve
its current enrolled roots; **q** to exit. There are no
mutation-capable commands or guest input forwarding.

The initial `collect_static()` is itself a bounded trusted process on a
**background** thread, not the Textual event loop. It supplies unverified
registry enrollment metadata only; no bootstrap row is a fresh root reading.
Unconflicted statuses start at **unknown**, regardless of registry history. Per-root
`collect_root()` calls use `ObservationPump`, two physical worker slots,
one worker per enrollment, 10-second independent subprocess deadlines and
generation-aware completion rejection. A stale/missing/failed root cannot
consume both worker slots. Static conflicts and incompatible roots are held
until authoritative full-fleet identity reconciliation; an isolated successful
read cannot clear those holds. Duplicate factory IDs display conflict.

The screen intentionally shows full factory IDs (so identical short suffixes
cannot make roots ambiguous), enrollment suffixes, freshness state and evidence labels, not paths, untrusted aliases, raw errors, credentials
or raw child output. The display uses Textual `Static(markup=False)`; the
session is a read-only view model and is never control authority. Closing
the UI stops launching workers and never waits on a hung callback.

**Limitations:** Unavailable/corrupt manager-workspace storage can still
stall the bounded bootstrap process. A physically disconnected/network-root
acceptance test has not been performed.
The monitor has no live instance inventory, operation dispatch, durable
layout, or manager-workspace editing. It does not replace the separate
EDF-006 physical operator fixture.

## Periodic bounded observation cadence (8 November 2026)

The executable monitor now schedules **automatic** summary re-observation of
unheld enrollments every 10 seconds, instead of observing only at startup or
after pressing **r**. The initial registry discovery still seeds only
`unknown`, and each subsequent `current` reading remains static identity
rather than an instance/READY claim. Failure retries occur at the same bounded
cadence, not every 50-ms UI tick. A pending or actively running sample is never
superseded by a timer; it retains its physical slot until actually reaped.
Changes to the trusted registry still require an explicit **r** reload;
automatic re-observation is not an implicit discovery or mutation operation.

The interval is an **attempt cadence**, not a promise of completion within 10
seconds. At many roots or with slow subprocesses the two-worker queue may take
longer to drain. Actual Windows Terminal event-to-frame latency and physical
unreachable-root behavior remain unmeasured and mandatory for EDF-006.

## Verification

`python -m unittest discover -s tests -p test_edf006_fleet_monitor.py -v`
tests bootstrap honesty, conflict holds, duplicate identities, actual threaded
peer isolation, refresh, malformed seeds, and unavailable states. The Windows
pinned-runtime workflow additionally executes:

```powershell
& $Python -I .\tools\edf006_fleet_monitor.py --headless-smoke
```

That is a **synthetic, actual-Textual event-loop integration**, labelled
`FAST-CI-HEADLESS` with `physical_tui=false` and null externally measured
input-to-visible-frame p95. Native Windows Terminal acceptance and EDF-006
physical sign-off are still required before PR #28 may merge.

## Read-only registry bootstrap isolation (8 November 2026)

The trusted EDF-005 metadata reader `Get-EzDarkFactoryManagerRegistryMetadata`
uses the bounded schema-1 registry loader on the *manager workspace* without
following registered candidate paths. This removes the old full-fleet
`Get-EzDarkFactoryManagerObservations` serial root scan. The initial seed
cannot assert fresh identity, reachability, API compatibility, or READY:
all unconflicted registrations are `unknown`, with null observed identity
and API. Duplicate enrolled factory IDs are held as `conflict`; unauthorized
registrations are `incompatible`. Per-enrollment trusted reads use the same
metadata seam and inspect only their selected registered path under an
independently bounded child process. EDF-005's effectful dispatch still uses
authoritative full-fleet checks and remains unchanged.

The focused Windows PowerShell test edits only disposable registry fixtures:
one enrollment is on an unmapped drive while the other remains observable,
and a synthetic duplicate enrolled identity holds both rows. This proves
the read-only software path, not real network-drive hang performance,
native Windows Terminal PHYSICAL-TUI behavior or live VM readiness.

## Live registry refresh and generation safety (8 November 2026)

The prior **r** shortcut only enqueued new observations for enrollments held
in memory. It did not reload the EDF-005 registry. Thus new registrations were
invisible until restart, removed roots persisted on screen, relocated paths
could retain old static identity, and a resolved duplicate-ID hold remained
permanently stuck.

The read-only monitor now rereads registry metadata on its existing bounded
background executor when **r** is pressed. A whole new envelope and all root
identities/Windows path equivalences are validated before any change is made.
The same session and physical worker budget are retained across refreshes:
unchanged enrolled roots keep eligible recent observations, whereas removed,
re-keyed, relocated, or newly held/unheld roots invalidate their generations.
Already-running old collectors still count against the two-slot limit until
they finish; a late completion cannot restore an old enrollment or path.
Known duplicate factory IDs are held until registry metadata resolves them
and then require **new** per-root evidence before any current status.

Rapid repeated refresh requests coalesce to at most one follow-up reload.
If trusted registry bootstrap fails or returns invalid metadata, the monitor
withdraws all old registered rows and explicitly shows `refused` rather than
preserving apparently-current data from a no-longer-trusted registry. It retains
the original worker pool and counts previously launched reads against the
same two-slot budget until they finish; a later **r** retries bootstrap without
creating a second worker pool. These transitions are exercised by Python model tests and the
pinned real-Textual synthetic event-loop smoke, including failure and recovery.

This is SOURCE/FAST-CI-HEADLESS safety behavior, not physical native Windows
Terminal acceptance and not a guarantee that a real unavailable drive meets
the specified latency budget.

## Inaccessible-workspace deadline isolation (8 November 2026)

The metadata bootstrap and individual-root worker previously called Python
`Path.is_symlink()` and `Path.is_dir()` on the **portable manager workspace**
*before* launching their deadline-bounded PowerShell children. These are
filesystem operations; a stalled network/missing-volume path could occupy
the bootstrap or one of the two observation threads indefinitely, even though
the subsequent child had a ten-second deadline.

The read-only Python bridges now validate only **path spelling and bounded
argument length** without probing the workspace. The local checked-in script
still undergoes its own source-file/reparse check. The trusted PowerShell
child uses EDF-005 `Assert-EzDarkFactorySafePath` to check the workspace,
its ancestors and registry under the bounded subprocess lifetime; invalid,
reparse-point or absent workspaces remain **refused**, never `current`.
No untrusted root code is executed. Linux synthetic-runner tests deliberately
prohibit Python workspace stat calls; Windows tests use the actual trusted
PowerShell child to reject missing workspaces. This reduces a pre-deadline
hang path but does **not** prove physical disconnected-drive behavior,
Windows process-launch latency or whole-system real-time guarantees.

