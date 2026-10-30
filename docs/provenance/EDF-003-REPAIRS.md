# EDF-003 — public repairs for historical Keys / Runtime amendment classes

**Scope:** source-selected software repair and deterministic/native Windows
qualification; NOT a recovered owner patch, original lab VM recreation, guest
qualification, physical WHPX, or an acceptance of upstream DASH-08 PR #45.

## Source identities and historical negative controls

Original immutable EzVM source:
`techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699`,
tree `78e5ce0db9c32972451add22d28c7d19983775ee`.

| Class | Original source blob / SHA-256 | Owner field evidence | Public repair selected |
| --- | --- | --- | --- |
| Controller key DACL | `Keys.ps1` `da6bcf712ff2b4fd05bb6d3ad8593389c7738f28` / `7a76dd9b47b2c9665535e856f567faf309c489e9683738cf42b9e67c3d62ee1f` | Owner-local Keys patch claimed by field study, exact private bytes unavailable; reported normal-user DACL problem (FR-15) | merged `7b829f8352a9fa30c965e57386965767c5969e0d`, public source `6dc9257a8dd8f078f95ae76066f798e888f99b2a` |
| Captured-output child lifetime | `Runtime.ps1` `59cae4784a0d36b7b3a964a0f495772fbf61f801` / `b86122f56df1f849d0f5110828519718882e9ea4fd254bff0fb252c7b68a163b` | Owner-local Runtime patch claimed by field study, exact private bytes unavailable; start pipe remained open (FR-14) | unmerged DASH-08 PR #45 head `8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46`; software-only candidate `Runtime.ps1` + `RuntimeProcess.cs` |

The accepted EDF-002 preimages are the exact baseline namespace adaptations.
The source map [edf003-repairs.json](edf003-repairs.json) records every one of
the 13 selectively imported public repair and test/helper source files by
pinned upstream commit/tree, original blob/SHA-256, destination and current
destination Git blob. It does not mutate the immutable EDF-001 manifest or
the EDF-002 import provenance.

## DACL selected behavior

Keep original keypair derivation, public/private matching, lock, new-key
rollback, native `icacls` failure and hardlink/path checks. Replace only the
PowerShell filesystem-provider `Set-Acl`/full readback persistence with
supported Windows `FileInfo/DirectoryInfo.SetAccessControl` on Windows
PowerShell 5.1 and `FileSystemAclExtensions` on PowerShell 7.

A single protected, explicit current-user FullControl allow ACE is required;
the owner/Access sections alone are read back. Broad/inherited access, wrong
object type, missing target and denied WRITE_DAC fail closed. Do not touch
SACL, privilege assignments, administrator tokens or primary group.
Repeated application preserves synthetic bytes and private access.

The original baseline negative mechanism is the PowerShell provider requesting
SACL audit sections after `icacls` has protected the DACL, which can throw
`SeSecurityPrivilege` under an ordinary Windows user. The hosted standard
user test explicitly replays the original EDF-002 baseline source from
`d49affee3624b81f952f68cb9c7ca5149d85e015` in a disposable local account
before qualifying the corrected source in that *same user class*. Unlike
ordinary runner tests, this does **not** infer a standard-user result from an
administrator token; evidence requires the token's administrator-group and
audit/ownership/backup/restore privileges to be absent.

## Runtime selected behavior

Retain all existing exact executable/argv/start-time process identity,
localhost QMP, immutable base + one overlay, lock, STARTING/STOPPING holds,
guest readiness and no-guessed-PID-kill semantics.

Select the source-bound `RuntimeProcess.cs` helper: explicit Windows
`CreateProcessW` without a shell/service/elevation/job breakaway,
NUL stdin, direct new stdout/stderr files, an allowlist of exactly three
inheritable standard handles, and precise newly created process-handle to
managed-process creation identity comparison. The spawned process does not
depend on the PowerShell caller's capture pipes. If pre-publication handoff
fails, cleanup uses only the exact process handle created in this call; after
durable runtime publication a timeout leaves STARTING/STOPPING and preserves
disk ownership for reconciliation.

Use monotonic Stopwatch remaining-budget calculations across QMP connect,
greeting, capabilities, command and response; one QMP operation cannot multiply
per-stage timeouts. Reject positive startup/shutdown observation that arrives
after its deadline or whose process identity changed. The real Windows
legacy pipe-negative and corrected native child tests use a disposable
30-second simulated VM executable and loopback-only QMP fixture, including
interrupted caller, direct logs, flood, stdin EOF, unrelated handle,
Unicode/spaces/quoted argv, stale identity and publication boundaries.

## Selection/rejection and evidence-class limits

Selected public software changes: owner/Access DACL persistence and strict
readback; explicit native launch/log/handle ownership; monotonic QMP deadlines
and post-observation identity/result publication validation; associated
synthetic negative/positive tests, disposable hosted standard-user and
source-matched native qualification helpers.

**Not selected:** any unknown historical owner patch bytes, unrelated EzVM
dashboard/guest/release workflows, QEMU/Ubuntu binary/VM image, force-kill on
unknown PID, shell job breakaway, private TUIsynth state or manager/UI
implementation. EDF source contains no token/account/VM disk artifact; the
hosted ordinary test creates a short-lived local user only on a disposable
GitHub Windows runner and confirms removal.

Upstream historical receipts, not current EDF PASS:
- Keys repair: exact merged `7b829f8...` Windows private-ACL and core CI PASS.
- DASH-08 #44/#34 and PR #45 remain **open**, PR merge state dirty as
  observed 30 October 2026. Native software 11/11 PASS in each PS5.1/PS7
  upstream lane, but full real-release TCG **FAIL**: fresh guest failed
  SSH READY after 676 seconds, an output-stream timeout occurred during SSH,
  graceful stop retained STOPPING, and serial output showed an IO-APIC/timer
  panic. No root cause is assigned from that mixed observation.
- Physical ordinary-user Windows/WHPX runtime, first-boot, Windows Terminal
  and human usability **UNMEASURED / HUMAN-PENDING** for EDF-003; these are
  later EDF-011/release gates.

## EDF qualification

The mandatory full merge gate remains the current Python provenance checks,
PowerShell 5.1 repository guard and full suites on PS5.1 + pinned PS7.6.6.
The EDF-003 dedicated CI lanes additionally run the native process 11-case
source-matched software receipt in both PowerShell engines and a disposable
ordinary-user ACL regression in each engine, with retained receipts.
No zero/all-skipped suite qualifies. Hosted Windows account creation is
deliberately gated to `GITHUB_ACTIONS=true` and
`RUNNER_ENVIRONMENT=github-hosted` and must never run on the owner's host.

## Executed EDF source qualification — first complete green head

The first **fully green nine-job** exact-head run occurred on 30 October 2026:
[EDF-003 run 41112542355](https://github.com/techrote/ezDarkFactory/actions/runs/41112542355)
at source commit `6c850db5fda925bd06d1960c4cd5c88407dbd5c4`, Git tree
`62ffb05d1fa9714d04ff8f6e2fdead0874cd31c4`.
It is a verified **pre-merge software checkpoint**, not the final revision
of this documentation change. The new report commit, if different, needs its
own complete exact-head and post-merge qualification before issue closure.

| Hosted lane / exact source | Executed result |
| --- | --- |
| Python provenance on Ubuntu 24.04 and Windows Server 2022 | Each 44 PASS, 0 FAIL, 0 SKIP; all 144 original source records authenticated; 131 safe tracked EDF sources |
| PowerShell 5.1 source contract | PASS; tracked-source, JSON, PowerShell parsing, secret/binary/VM-state guards |
| Full Windows PowerShell 5.1 control plane | 372 PASS, 0 FAIL, 0 SKIP |
| Full pinned PowerShell 7.6.6 control plane | 372 PASS, 0 FAIL, 0 SKIP |
| Real native Windows process/deadline PS5.1 + PS7.6.6 | 11/11 PASS in each engine, no software skips, T04 physical WHPX SKIP |
| Disposable ordinary non-admin Windows DACL PS5.1 + PS7.6.6 | 4 mandatory baseline negative cases each reproduced `SeSecurityPrivilege` on the old EDF-002 source; then 372 PASS, 0 FAIL, 0 SKIP using the repaired source in the **same non-admin user class** |

I independently downloaded and inspected the four retained **original ZIP**
artifacts from that run, checked their ZIP SHA-256 against the GitHub job logs,
and inspected JSON source commit, source tree, child exit, privilege class,
case outcomes and cleanup. The baseline source ID is
`d49affee3624b81f952f68cb9c7ca5149d85e015`, tree
`a28a054ffd1296c51b5f7e0bbe33248aae5edb8a`.
Both ordinary-user receipts record no administrator membership and no
audit/ownership/backup/restore privileges, `sourceUnchanged=true`,
`outcome=pass`, child exit zero, temporary account removed and isolated
fixture removed. The four baseline negative cases are recorded individually,
not inferred from a suite count.

| Original evidence | Hosted ZIP artifact ID | ZIP SHA-256 | Inside JSON SHA-256 |
| --- | ---: | --- | --- |
| PS5.1 ordinary-user DACL | [13003549179](https://github.com/techrote/ezDarkFactory/actions/runs/41112542355/artifacts/13003549179) | `080ab8bcd38391762c443d44c651bdcb77b3ed89e39b0ff171165a28a3c83524` | `ada1e66cab823dfadeabb66a2fc44fecc627c376d4ec075ae3f83e3147cf1209` |
| PS7.6.6 ordinary-user DACL | [13006225232](https://github.com/techrote/ezDarkFactory/actions/runs/41112542355/artifacts/13006225232) | `d8c29d26f29234bff493b2f9d160712c39650c1f318c4ce60c6660bf4be7f29c` | `2f44318e57005f99625f1f42d24ccfec2b0ef78ce85c8767e86f6b51762199b5` |
| PS5.1 native process/QMP | [13002404859](https://github.com/techrote/ezDarkFactory/actions/runs/41112542355/artifacts/13002404859) | `43b5b1816b99caded6e3b3e0918add926306a7894a3c6e44be3e5b7178e7973f` | `4af371fb2b3be07342b9861ba24b66ef500307cce1673d8dd68e8830fef5eba1` |
| PS7.6.6 native process/QMP | [13004935831](https://github.com/techrote/ezDarkFactory/actions/runs/41112542355/artifacts/13004935831) | `3e377517748d269a42878ff33dab93bacae28a3f83b149c7fedafa2ac3eec126` | `3977853babff4ca2ff88ae8cd655bf9e2b0c25ee283e6c118e954ea04e86a9fb` |

Reproduction entry points (from an exact-source checkout):

```powershell
python tools/check.py --fetch --sources .provenance-cache
.\scripts\Invoke-CiCheck.ps1 -Check Repository -ExpectedMajor 5
.\scripts\Invoke-CiCheck.ps1 -Check ControlPlane -ExpectedMajor 5
.\scripts\Invoke-Edf003SoftwareQualification.ps1 -ExpectedMajor 5 -OutputDirectory "$env:TEMP\edf003-native-ps5-new"
```

Run the full control plane and native qualification separately in verified
PowerShell 7.6.6 with `-ExpectedMajor 7`. The disposable ordinary-user
account harness runs **only** on a GitHub-hosted ephemeral Windows runner,
and its qualification child validates token privileges before comparing
legacy/repaired ACL behavior. It is not a local owner setup command.

### Preserved negative evidence

The earliest authored-head run [41111788727](https://github.com/techrote/ezDarkFactory/actions/runs/41111788727)
was RED: EDF-002's historical-import verifier initially assumed original
Keys/Runtime/CI current blobs could never change, and the hosted ordinary-user
account was named with a 28-character expanded prefix beyond Windows' limit.
These were corrected with immutable EDF-002 accepted-commit verification,
explicit EDF-003 supersession mapping, full checkout history and a bounded
18-character disposable test username. Later real Windows source/negative
tests passed; no assertion was deleted, skipped or xfailed. The upstream
DASH-08 real TCG failure and the unmeasured physical WHPX gate remain unchanged.

**Status:** EDF-003 source/native/ordinary-user software ACCEPTED after
[reviewed PR #18](https://github.com/techrote/ezDarkFactory/pull/18)
merged as `d7b7debbaf66d5b50136342d26634ff05ea34d3f` (Git tree
`50670a3f84c0ee7efbebf73077a79b566436feff`), followed by all nine
literal-main checks **PASS on run attempt 1**:
[run #41114714613](https://github.com/techrote/ezDarkFactory/actions/runs/41114714613).
The original artifact archive digests and main-source handoff are recorded in
[issue #3's acceptance record](https://github.com/techrote/ezDarkFactory/issues/3#issuecomment-6531745348).
This acceptance is limited to **SOURCE, FAST-CI, actual Windows-native child
fixtures, and disposable ordinary-user DACL execution**; it does not
accept upstream DASH-08 full TCG, actual QEMU/Ubuntu/WHPX, physical Windows
Terminal or human usability.
