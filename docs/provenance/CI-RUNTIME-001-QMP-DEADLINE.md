# CI-RUNTIME-001 — QMP startup deadline diagnostic supersession

Issue: https://github.com/techrote/ezDarkFactory/issues/20

## Provenance and historical source identity

This is a **subsequent EDF change**, not a rewrite of the accepted EDF-002
namespace adaptation or EDF-003 source-selection records.

- Accepted base main: `4ca42999081f6253e9701821f1c378f439fca9a9`.
- Accepted EDF-003 technical merge: `d7b7debbaf66d5b50136342d26634ff05ea34d3f`.
- Superseded current implementation blobs at base:
  - `src/EzDarkFactory/Runtime.ps1`: Git blob to be verified from the base commit.
  - `tests/Runtime.Tests.ps1`: Git blob to be verified from the base commit.
- Original EDF-001 baseline and EDF-002/EDF-003 imported-source/blob/hash
  manifests remain immutable. This document records later deviations; it
  does not claim altered bytes match the original imported source.

## Negative CI receipt — do not erase

[Run 41115782284 attempt 1](https://github.com/techrote/ezDarkFactory/actions/runs/41115782284):
Windows PowerShell 5.1 first-party suite **371 PASS / 1 FAIL / 0 SKIP**,
at literal PR head `19f230b08310b4b53b8f98750fd1745b0df65f92`.
The expected `paused` status was replaced by a generic
`QEMU startup exceeded its 1000 ms total deadline` diagnostic.
Attempt 2 on unchanged source was **372 PASS / 0 FAIL / 0 SKIP**.
Neither retry success nor later merge erases the original failure.

## Mechanism and correction

The source loop has one monotonic Stopwatch covering native launch, durable
STARTING publication, QMP observation, process-identity revalidation and
RUNNING publication. Its catch block previously replaced `$lastError` on
every iteration, even when a preceding within-budget query had returned
a valid `paused` result. A later budget expiry could therefore destroy
the diagnostically useful result; the exact originating-run call ordering
was not measured, so the scheduling mechanism is a hypothesis, while the
source-level overwrite mechanism is demonstrated by inspection.

Record a non-running QMP status **only after** the QMP result passes the
existing monotonic total-budget check, and append the last valid semantic
observation to the final timeout error independently of a subsequent
transport/deadline error. Do not cache late results. Do not alter the
deadline, positive RUNNING gates, executable/argv/start-time comparison,
storage ownership, lifecycle holds, QMP surface or PID termination.

The existing single-second test is a semantic paused-state test, not a
deadline-stress oracle; grant it three seconds to reach the intended path.
The new dedicated negative fixture returns `paused` first, then delays a
positive `running` result beyond the **unchanged** three-second total budget
and checks the paused diagnostic, STARTING ownership and storage hold.
Inherited strict late-running, identity-change and one-deadline negative
tests remain mandatory. Timing is bounded but Windows scheduler overhead
is not completely deterministic; execution evidence must be reported as
such.

## Qualification

At merge, record the final literal PR head, all nine independent job results,
exact original/final source IDs, test counts, substantive diff review,
merge SHA, and the nine actual post-merge results in the PR/issue discussion.
No unexecuted Windows, QEMU/TCG/WHPX, physical terminal or human tests
may be promoted to PASS.
