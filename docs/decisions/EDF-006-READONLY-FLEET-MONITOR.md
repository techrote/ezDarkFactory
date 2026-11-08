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
Press **r** for a new static identity read; **q** to exit. There are no
mutation-capable commands or guest input forwarding.

The initial `collect_static()` is itself a bounded trusted process on a
**background** thread, not the Textual event loop; it supplies verified
enrollment/identity metadata. All statuses start at **unknown**, regardless of
the bootstrap state: initial provenance is not a per-root fresh read. Per-root
`collect_root()` calls use `ObservationPump`, two physical worker slots,
one worker per enrollment, 10-second independent subprocess deadlines and
generation-aware completion rejection. A stale/missing/failed root cannot
consume both worker slots. Static conflicts and incompatible roots are held
until authoritative full-fleet identity reconciliation; an isolated successful
read cannot clear those holds. Duplicate factory IDs display conflict.

The screen intentionally shows only enrollment/factory suffixes, freshness
state and evidence labels, not paths, untrusted aliases, raw errors, credentials
or raw child output. The display uses Textual `Static(markup=False)`; the
session is a read-only view model and is never control authority. Closing
the UI stops launching workers and never waits on a hung callback.

**Limitations:** The first whole-fleet discovery subprocess may still be
delayed by an inaccessible root before bounded timeout. This is a startup
availability limitation, not a claim of complete unresponsive-root isolation;
EDF-007 should source a trusted metadata-only registry listing when available.
The monitor has no live instance inventory, operation dispatch, durable
layout, or manager-workspace editing. It does not replace the separate
EDF-006 physical operator fixture.

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
