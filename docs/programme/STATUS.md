# ezDarkFactory programme status

This is a compact navigation ledger. Current GitHub issue/PR state and exact `main` remain authoritative.

| ID | GitHub | Status | Branch/PR | Dependency note |
|---|---|---|---|---|
| EDF-001 | [#1](https://github.com/techrote/ezDarkFactory/issues/1) | done | [PR #13](https://github.com/techrote/ezDarkFactory/pull/13) | accepted `538c8243be4d121a8834bdce99137dd33c7b41df`; post-merge green |
| EDF-002 | [#2](https://github.com/techrote/ezDarkFactory/issues/2) | done | [PR #15](https://github.com/techrote/ezDarkFactory/pull/15) | accepted `978288496aa5d328f0d79712c74e69cf769689e4`; five exact-main jobs green |
| EDF-003 | [#3](https://github.com/techrote/ezDarkFactory/issues/3) | done | [PR #18](https://github.com/techrote/ezDarkFactory/pull/18) | accepted `d7b7debbaf66d5b50136342d26634ff05ea34d3f`; nine exact-main checks PASS |
| EDF-004 | [#4](https://github.com/techrote/ezDarkFactory/issues/4) | done | [PR #23](https://github.com/techrote/ezDarkFactory/pull/23) | accepted `a983c957fb65acfd781ac131733512658b3e9927`; eleven exact-main checks PASS |
| EDF-005 | [#5](https://github.com/techrote/ezDarkFactory/issues/5) | todo | | EDF-003 + EDF-004 accepted; dependency-ready, unstarted |
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

This is **SOURCE / FAST-CI** acceptance only. The owner-local `Keys.ps1`/`Runtime.ps1` **software repair classes**
were subsequently selected and qualified in EDF-003, described below.
The clean fresh-project guest contract has subsequently been accepted
under EDF-004, documented in its handoff below. The multi-factory TUI, real QEMU/TCG/WHPX, physical
Windows Terminal, human usability, and final release remain later gates;
no such PASS is implied.

## EDF-003 accepted handoff

On 30 October 2026, [EDF-003 PR #18](https://github.com/techrote/ezDarkFactory/pull/18)
was guarded-squash merged as source commit
`d7b7debbaf66d5b50136342d26634ff05ea34d3f`, Git tree
`50670a3f84c0ee7efbebf73077a79b566436feff`. This is byte-identical
to reviewed PR head `90c68f30a604afbf721cc2e9274c539c02c18a38`.
All nine required [PR-head checks](https://github.com/techrote/ezDarkFactory/actions/runs/41113777568)
and nine [actual main post-merge checks](https://github.com/techrote/ezDarkFactory/actions/runs/41114714613)
passed on their respective literal SHA values, with post-merge passing on
**attempt 1**.

Both Windows PowerShell 5.1 and pinned PS7.6.6 full control-plane suites
reported **372 PASS, 0 FAIL, 0 SKIP**. Both Ubuntu/Windows provenance
jobs reported **44 Python PASS, 0 FAIL, 0 SKIP** and authenticated 144
historic source records. The native Windows runtime/process deadline
lanes passed **11/11** each, including the retained legacy captured-output
negative control. Actual disposable **non-admin** Windows user DACL
lanes in both engines first reproduced **four** original
`SeSecurityPrivilege` failures per engine at immutable EDF-002,
then passed the corrected **372/372** suites without elevation.
Source identity, original artifact ZIP/receipt digests, token privileges,
child exit and temporary account/fixture cleanup are recorded in
[EDF-003 repair report](../provenance/EDF-003-REPAIRS.md) and the
[durable issue acceptance record](https://github.com/techrote/ezDarkFactory/issues/3#issuecomment-6531745348).

The 13 selected later-public repair/test/helper inputs are source-pinned
and hash-mapped in [edf003-repairs.json](../provenance/edf003-repairs.json).
These replace only the public owner/DACL and native process/deadline
software behavior. Neither owner-local historical patch byte sequence
was recovered or claimed equivalent. The upstream DASH-08 full real TCG
release failure remains failed evidence; physical supported-host WHPX,
Windows Terminal and human use remain UNMEASURED/HUMAN-PENDING and
require EDF-011. EDF-004 is subsequently **accepted at SOURCE/FAST-CI**.
EDF-005 now has both EDF-003 and EDF-004 accepted prerequisites.

## EDF-004 accepted handoff

On 30 October 2026, [EDF-004 PR #23](https://github.com/techrote/ezDarkFactory/pull/23)
was guarded-squash merged as
`a983c957fb65acfd781ac131733512658b3e9927`, Git tree
`b9bdfeb9c1760f0d8bea0028dafae71104fa92a6`. This tree exactly
matches the reviewed final PR head
`a4fa6f5f6a27f570340a966a9c10bfe6e23fece2`. The final head reconciled
both preceding maintenance fixes: merged CI-PROV-001 #17 and
CI-RUNTIME-001 #20, preserving their exact immutable provenance layers
and preimage/supersession safety checks.

The two [PR-head runs](https://github.com/techrote/ezDarkFactory/actions/runs/41136392760)
and [focused guest qualification](https://github.com/techrote/ezDarkFactory/actions/runs/41136392863)
passed all **11 required exact-head jobs**. Both corresponding actual
`main` runs [full nine-job merge gate](https://github.com/techrote/ezDarkFactory/actions/runs/41137100823)
and [focused EDF-004 guest gates](https://github.com/techrote/ezDarkFactory/actions/runs/41137100701)
completed **SUCCESS on attempt 1**, 11/11 checks tied to the literal
merged commit. Full Windows PowerShell 5.1 and pinned PS7.6.6 suites
passed **381/381** with zero skips; each dedicated EDF-004 profile lane
passed **8/8**. Native process and real disposable standard-user DACL lanes
from EDF-003 remained green.

The EDF-owned `fresh-project/v1` profile is selected for new managed
instances based on validated schema-1 clean prepared bases; historical
`coding-default/v1` remains for schema-2 derived/imported bases and
existing durable intents. Fresh first-READY requires empty writable
coder-owned workspace; validated general build tools; locked passwords,
public-key SSH and sudo policy; no known historical TUIsynth/TRIO,
provider/model/credential or autostart state; and exact base, profile
name/version/digest, instance and durable generation identity. Reset,
fresh-clone and stale READY refusals are covered. No user workspace is
silently deleted or recursively chowned. Base machine/SSH/cloud identity
scrubbing and controller-key separation remain.

The [EDF-004 import provenance map](../provenance/edf004-fresh-profile.json)
binds original EzVM/EDF-002 accepted source bytes and the seven EDF-004
source adaptations to exact destination Git blobs. The
[guest qualification report](../provenance/EDF-004-FRESH-GUEST.md) and
[issue #4 durable acceptance record](https://github.com/techrote/ezDarkFactory/issues/4)
record source identities, negative controls and retained artifacts.

**Evidence boundary: SOURCE / FAST-CI only.** The focused guest lanes
explicitly report `realGuestExecuted=false`, with actual QEMU/TCG/WHPX,
physical Windows Terminal and human usability **UNMEASURED**; these
are later EDF-011/runtime/release gates under the governing test contract,
not unperformed EDF-004 passes.

EDF-001 through EDF-004 are accepted. EDF-005 #5 is now
**dependency-ready but unstarted**, with both required EDF-003/EDF-004
prerequisites satisfied. EDF-006 and later manager/TUI milestones retain
their separate dependencies.
