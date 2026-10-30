# ezDarkFactory programme status

This is a compact navigation ledger. Current GitHub issue/PR state and exact `main` remain authoritative.

| ID | GitHub | Status | Branch/PR | Dependency note |
|---|---|---|---|---|
| EDF-001 | [#1](https://github.com/techrote/ezDarkFactory/issues/1) | done | [PR #13](https://github.com/techrote/ezDarkFactory/pull/13) | accepted `538c8243be4d121a8834bdce99137dd33c7b41df`; post-merge green |
| EDF-002 | [#2](https://github.com/techrote/ezDarkFactory/issues/2) | done | [PR #15](https://github.com/techrote/ezDarkFactory/pull/15) | accepted `978288496aa5d328f0d79712c74e69cf769689e4`; five exact-main jobs green |
| EDF-003 | [#3](https://github.com/techrote/ezDarkFactory/issues/3) | todo | | EDF-002 accepted; dependency-ready |
| EDF-004 | [#4](https://github.com/techrote/ezDarkFactory/issues/4) | todo | | EDF-002 accepted; dependency-ready |
| EDF-005 | [#5](https://github.com/techrote/ezDarkFactory/issues/5) | todo | | EDF-003 + EDF-004 |
| EDF-006 | [#6](https://github.com/techrote/ezDarkFactory/issues/6) | todo | | EDF-003 + EDF-004 + EDF-005 |
| EDF-007 | [#7](https://github.com/techrote/ezDarkFactory/issues/7) | todo | | EDF-006 |
| EDF-008 | [#8](https://github.com/techrote/ezDarkFactory/issues/8) | todo | | EDF-004 + EDF-005 + EDF-007 |
| EDF-009 | [#9](https://github.com/techrote/ezDarkFactory/issues/9) | todo | | EDF-001 + EDF-004 + EDF-007 |
| EDF-010 | [#10](https://github.com/techrote/ezDarkFactory/issues/10) | todo | | EDF-003 + EDF-005 + EDF-007 + EDF-008 |
| EDF-011 | [#11](https://github.com/techrote/ezDarkFactory/issues/11) | todo | | EDF-008 + EDF-009 + EDF-010 |
| EDF-012 | [#12](https://github.com/techrote/ezDarkFactory/issues/12) | todo | | EDF-011 |

Allowed status words: `todo`, `in-progress`, `blocked`, `review`, `done`.

An issue is `done` only after its PR is merged and post-merge `main` verification required by that issue succeeds.

## EDF-001 accepted handoff

On 30 October 2026, PR #13 merged as
`538c8243be4d121a8834bdce99137dd33c7b41df`, tree
`db1efa22b9d01fb5b6045d4dab56272b436efba1`. Actual main matched the reviewed
PR tree and passed the local gate plus both exact-main
[Linux and Windows CI jobs](https://github.com/techrote/ezDarkFactory/actions/runs/41089647014):
144 authenticated records, 36 tests, zero failures/skips in each lane.

The [durable acceptance record](https://github.com/techrote/ezDarkFactory/issues/1#issuecomment-6527802150)
names the provenance artifacts, unresolved original local TUIsynth SHA/tree and
private patch bytes, both candidate-repair dispositions, and the EDF-002 handoff.
Evidence is SOURCE / FAST-CI only. EDF-002 has since been accepted as described below.

## EDF-002 accepted handoff

On 30 October 2026, [PR #15](https://github.com/techrote/ezDarkFactory/pull/15)
merged by exact-head-guarded squash as
`978288496aa5d328f0d79712c74e69cf769689e4`, tree
`6db732c24b6da5e80157310f43ebc67955e8ec3e`. The merged tree is
identical to reviewed PR head
`d7c359246e7bfad497a1ab1692748844bf408d47`. The five exact PR-head
[CI jobs](https://github.com/techrote/ezDarkFactory/actions/runs/41104304654)
all passed: both source/provenance lanes ran 40 Python tests (zero failures/skips),
the Windows PowerShell 5.1 repository contract passed, and each of the
Windows PowerShell 5.1 and pinned PowerShell 7.6.6 control-plane suites ran
350 tests (zero failures/skips).

The actual merged-main
[CI run](https://github.com/techrote/ezDarkFactory/actions/runs/41105320431)
passed all five jobs at the exact main commit (run attempt 2). The initial
Ubuntu provenance attempt failed during public Git acquisition with
`fatal: shallow file has changed since we read it`, before test execution;
the single-job retry succeeded against the unchanged merged main.
This negative/retry receipt is retained rather than represented as a
first-attempt clean pass.

The accepted source fork contains the 87 audited first-party imports from
`techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699`:
8 original-byte-identical files, 62 deterministic namespace adaptations,
and 17 reviewed integration adaptations. All imported destinations have
machine-readable upstream blob/SHA-256 and current destination Git-blob
identity in [the EDF-002 import map](../provenance/edf002-imports.json).
The new public launcher is `ezdarkfactory.ps1` and its distinct module
identifies as `0.0.0-dev`. Original root-relative QEMU/QCOW2/lifecycle/
SSH/QMP/security behavior and inherited tests remain; no historical
runtime, private keys, guest images or comparison-fork state was imported.
See [the durable issue acceptance trail](https://github.com/techrote/ezDarkFactory/issues/2).

This is **SOURCE / FAST-CI** acceptance only. The owner-local
`Keys.ps1`/ `Runtime.ps1` amendments and physical standard-user process
semantics are EDF-003 work. The fresh, clean project guest contract is
EDF-004. Both issues are now **dependency-ready** but unstarted. The
multi-factory TUI, TCG/WHPX, physical Windows Terminal, human usability,
and final public release remain later programme gates; no such PASS is implied.
