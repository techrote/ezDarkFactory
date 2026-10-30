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

**Status when authored:** implementation staged; CI/merge/post-merge receipts
pending. The final issue/PR handoff must bind exact final source/tree, raw
receipt hashes where retained, all failures and the final gate disposition.
