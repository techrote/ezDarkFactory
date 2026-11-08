# EDF-006 — independently bounded static root observation

**Status:** implementation spike / SOURCE and FAST-CI only. Not a production TUI,
native Windows Terminal acceptance, live instance collector, or WHPX evidence.

## Why this boundary exists

The existing EDF-005 `Get-EzDarkFactoryManagerObservations` and EDF-006
`collect_static` read the complete registry in one trusted PowerShell child.
Wrapping that whole-fleet call in several Python threads would **not** provide
per-root latency isolation: a single inaccessible root could hold up the
combined result. `ObservationScheduler` and `ObservationPump` already reserve
one true worker slot per enrolled root and permit independent-root concurrency;
they need a truly per-root callback to obtain that benefit.

`tools/edf006_root_collector.py::collect_root(workspace, token, deadline)` is
an optional injected `ObservationPump` callback. It invokes the new trusted
`scripts/Invoke-Edf006RootObservation.ps1` with **only the enrollment ID**.
The trusted adapter resolves that ID in the portable EDF-005 registry, checks
enrollment/authorization and bounded registry metadata, and probes only that
candidate with the accepted manager module. It never imports candidate code
or runs a guest/factory operation. The full-fleet static adapter is retained
unmodified as the separate existing diagnostic path.

Each attempt uses a separate `run_bounded` subprocess: at most 256 KiB
stdout/16 KiB stderr, 0–30 s configured deadline, kill/reap on overflow or
deadline. The Python parser requires exactly one schema-1 static observation
whose enrollment and factory IDs match the request. Exceptions, malformed
JSON, missing roots and identity mismatch fail closed. A known duplicate
factory ID in registry metadata is held as conflict without probing another
root; the manager's stronger **full-fleet** fresh revalidation remains
authoritative for all mutations.

Only `summary` can return `current`, which means *compatible static factory
identity observed now*, **not** running instances, authenticated READY, logs,
or a fresh control revision. The summary explicitly says inventory unknown.
`instances` and `logs` never launch a child and return unavailable. An
observer callback must run in the worker pool, never synchronously from TUI
render/event handlers. The root-specific bridge does not acquire any manager
operation lease or write any registry/config/control file.

## Evidence and remaining limits

Python source regressions test exact argv and deadline, immutable one-root
identity/schema checks, misleading states, no unsupported live reads, refusal,
timeout, and threaded isolation with an inert blocked runner. The Windows
lane additionally executes a real trusted PowerShell negative-path smoke.
No physical Windows Terminal input/presentation/p95 measurement is produced.
A registry read still checks all registered path **metadata** in the accepted
EDF-005 module; this is not proof of isolation against a filesystem metadata
operation that itself hangs. No real unavailable network root is probed by CI.
The current static APIs cannot supply live instance state; EDF-007 must use
typed EDF-005 read operations with fresh identity and revision, and preserve
separate control-plane dispatch validation. A forked/rekeyed identity may
require full-fleet reconciliation before mutation.

**HOLD:** EDF-006 #6 and draft PR #28 require independently witnessed
PHYSICAL-TUI Windows Terminal qualification before merge or closure.
