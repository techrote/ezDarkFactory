# Owner-local amendment evidence matrix

**Disposition: both amendment classes have public candidate repairs; neither
historical private patch has been recovered or demonstrated equivalent.**
EDF-001 records provenance only. EDF-002 imports/adapts the historical baseline;
EDF-003 owns selective repair and current EDF regression qualification.

This is a **SOURCE** audit of exact public source and existing upstream
**FAST-CI** evidence. The upstream full TCG failure is retained as negative
**TCG-RUNTIME** evidence. No EDF runtime, WHPX, Windows Terminal, physical UI or
human-usability execution is claimed.

GitHub status below is an **as-of 2026-10-30T16:11:14Z snapshot**. Reverify it before
using a repair candidate. See the [machine-readable audit](audit-2026-10-30.json)
and [historical evidence limitations](HISTORICAL-EVIDENCE.md).

## Exact historical source

Repository: [techrote/ezvm](https://github.com/techrote/ezvm).
Baseline commit: `b6abdf8c3edd61695db30894da991f275b39a699`.
Baseline tree: `78e5ce0db9c32972451add22d28c7d19983775ee`.

| Source path | Git blob | SHA-256 |
|---|---|---|
| [src/EzVm/Keys.ps1](https://github.com/techrote/ezvm/blob/b6abdf8c3edd61695db30894da991f275b39a699/src/EzVm/Keys.ps1) | `da6bcf712ff2b4fd05bb6d3ad8593389c7738f28` | `7a76dd9b47b2c9665535e856f567faf309c489e9683738cf42b9e67c3d62ee1f` |
| [src/EzVm/Runtime.ps1](https://github.com/techrote/ezvm/blob/b6abdf8c3edd61695db30894da991f275b39a699/src/EzVm/Runtime.ps1) | `59cae4784a0d36b7b3a964a0f495772fbf61f801` | `b86122f56df1f849d0f5110828519718882e9ea4fd254bff0fb252c7b68a163b` |

## Four evidence/disposition columns

The concern column names the amendment; the remaining four columns keep source,
field claims, later repair evidence and current EDF disposition distinct.

| Concern | Exact historical baseline | Owner-local field evidence | Later public repair evidence | Current EDF disposition |
|---|---|---|---|---|
| Private key / DACL (`Keys.ps1`) | `Set-EzVmPrivateAcl` constructs a fresh protected current-owner-only DACL, persists with PowerShell `Set-Acl`, and verifies with `Get-Acl`. Private-key protection first invokes bounded `icacls` inheritance removal/grant, then this helper. | The field design identifies an existing owner `Keys.ps1` patch. FR-15 reports standard-user ACL problems among other onboarding failures and owner patches/workarounds. The private patch implementation and bytes are unavailable. | Merged public `7b829f8…` uses supported .NET ACL persistence and Owner/Access readback, avoiding the PowerShell provider's unrelated SACL access. Exact owner, one explicit allow ACE and inheritance/propagation are checked; standard-user regression evidence exists. | **Candidate repair.** Private byte identity/equivalence remains unresolved. Select/reimplement in EDF-003 with EDF regression evidence; no silent baseline replacement. |
| Captured start / process lifetime (`Runtime.ps1`) | `Start-EzVmRuntimeProcess` uses `ProcessStartInfo`, `UseShellExecute=false` and `CreateNoWindow=true` without explicit standard handles. It records process/PID/start time; those flags alone do not establish independent capture lifetime. | FR-14 reports QEMU retaining a captured start pipe and a file-redirection workaround; the original start session was protected. The design names an owner `Runtime.ps1` patch but exposes no private patch bytes. | Unmerged PR #45 at `8d4bacb…` supplies NUL input/direct output logs through a three-handle allowlist, source-bound native launch and exact handle/creation handoff. It adds shared QMP deadlines and late-publication guards. Both native suites pass; full real-release TCG fails. | **Candidate repair.** Private byte identity/equivalence remains unresolved. Preserve the failed full-release result and open upstream gates; EDF-003 must review and qualify its selected implementation. |

The field study is not evidence that the owner used the later public implementation.
The original owner patches, private preimages and authenticated VM are not test
fixtures. A safe current regression may reproduce a failure mechanism without
reproducing the historical private session.

## Private-DACL candidate

[PR #48](https://github.com/techrote/ezvm/pull/48) merged as
`7b829f8352a9fa30c965e57386965767c5969e0d`, tree
`2aa3170d8ba0a60ae98bb07803f63d9c04d41de0`. The relevant
[Keys.ps1](https://github.com/techrote/ezvm/blob/7b829f8352a9fa30c965e57386965767c5969e0d/src/EzVm/Keys.ps1)
blob is `6dc9257a8dd8f078f95ae76066f798e888f99b2a`, SHA-256
`89e437ce908695b9d90ddaa5cb590c3aa44c1a7c52d3696ebe9e7ae218f04fe5`.

The source persists the freshly constructed owner/DACL through
`FileSystemInfo.SetAccessControl` on Windows PowerShell 5.1 or
`FileSystemAclExtensions.SetAccessControl` on PowerShell 7. Readback requests
Owner/Access sections and requires a protected DACL, current owner, exactly one
explicit FullControl allow ACE, and the expected inheritance/propagation flags.
It checks target type and retains safe-path/hardlink/native-ACL failure guards.
No privilege grant, elevation, broad ACE or audit-policy change is the repair.

Reviewed source includes
[PrivateAcl.Tests.ps1](https://github.com/techrote/ezvm/blob/7b829f8352a9fa30c965e57386965767c5969e0d/tests/PrivateAcl.Tests.ps1),
[PrivateAclHosted.Tests.ps1](https://github.com/techrote/ezvm/blob/7b829f8352a9fa30c965e57386965767c5969e0d/tests/PrivateAclHosted.Tests.ps1),
the [qualification harness](https://github.com/techrote/ezvm/blob/7b829f8352a9fa30c965e57386965767c5969e0d/scripts/Invoke-PrivateAclQualification.ps1)
and [evidence contract](https://github.com/techrote/ezvm/blob/7b829f8352a9fa30c965e57386965767c5969e0d/docs/research/CI-POC-001-PRIVATE-DACL.md).
These retain the old failure and test broad/inherited access, protected
reapplication, unchanged synthetic bytes, child inheritance, wrong target types,
denied persistence and native restriction failure before key derivation.

All seven recorded checks at merged `7b829f8…` are successful, including
[both standard-user ACL lanes](https://github.com/techrote/ezvm/actions/runs/39054219124),
[repository/core Windows lanes](https://github.com/techrote/ezvm/actions/runs/39054219143)
and [offline replay](https://github.com/techrote/ezvm/actions/runs/39054219122).
This audit verifies the public check state and source; it does not rerun those
Windows tests or inherit their result as an EDF test result.

The same upstream commit also carries a temporary hosted-TCG deferral and
associated upstream policy. Those unrelated changes are not repair requirements
or EDF permissions and must not be ported as part of the ACL candidate.

## Native process / deadline candidate

[PR #45](https://github.com/techrote/ezvm/pull/45) is **open and unmerged** at
`8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46`, tree
`ef550dcba1aa386500c50506d0af5aa3a8ac448f`. Its
[software child #44](https://github.com/techrote/ezvm/issues/44) and
[physical parent #34](https://github.com/techrote/ezvm/issues/34) are both open.

| Candidate source | Git blob | SHA-256 |
|---|---|---|
| [Runtime.ps1](https://github.com/techrote/ezvm/blob/8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46/src/EzVm/Runtime.ps1) | `d84f0740a86652dd9c5b233110947081b2482117` | `f1fa7c9fe92a8dba4f0ee3497050b1fd633886008b488582b32b00c3fe91b73d` |
| [RuntimeProcess.cs](https://github.com/techrote/ezvm/blob/8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46/src/EzVm/RuntimeProcess.cs) | `649ea07a9a27977d3f4512dbe1ba0858fb3a2043` | `5b91e6624487d1da8d54b0d78c8ccc4c128d9668a72515cea0b8be0a6958203d` |

The native helper uses `CreateProcessW`, explicit NUL stdin, newly created direct
stdout/stderr files and a three-handle inheritance allowlist. It compares original
and managed process creation identities during handoff. The PowerShell wrapper
loads the helper under a source-hash-bound type identity, validates paths, and
keeps log preimages. It introduces no service, shell, job breakaway or persistent
caller-side output reader.

The companion changes give QMP connection/greeting/capabilities/command a shared
deadline and reject late positive start/stop results before publication. These
are separate behaviors to review, not permission to increase timeouts or weaken
ownership/storage guards. Before-publication cleanup and after-publication
STARTING timeout remain distinct cases.

The [11-test source suite](https://github.com/techrote/ezvm/blob/8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46/tests/Dash08Lifecycle.Tests.ps1)
retains a legacy pipe-EOF negative control and checks caller exit/interruption,
continuing child lifetime/logging, EOF-only input, unrelated handle isolation,
argument fidelity, no-clobber refusal, QMP deadlines and publication boundaries.
The [upstream investigation](https://github.com/techrote/ezvm/blob/8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46/docs/research/TRIO-2026-10/DASH-08-LIFECYCLE.md)
distinguishes this software work from the owner's historical session and the
unperformed physical gate.

### Authenticated public software receipts

Both tiny JSON artifacts from
[exact-head run 38985065979](https://github.com/techrote/ezvm/actions/runs/38985065979)
were retrieved on 30 October 2026. Their archive digests agree with GitHub's
artifact digests, their JSON hashes agree with the
[published checkpoint](https://github.com/techrote/ezvm/pull/45#issuecomment-6227174935),
and every one of their ten recorded source SHA-256 values agrees with literal
Git blobs at `8d4bacb…`. Only digest summaries are retained here; the ZIPs and raw
runtime receipts are not source-import payloads.

| Engine | Artifact ID | ZIP SHA-256 | Raw JSON SHA-256 |
|---|---:|---|---|
| PowerShell 5.1.20348.5622 | 12082449079 | `1f687ed1c62451cd5e132b93ad8a0af435049b5b94228b6c03333a1cf6e93591` | `3012fa605b3a6042c1f152c1284be4c6e3019e2b73252f1e2d934ff1c15a3b2c` |
| PowerShell 7.6.6 | 12083070841 | `0cd61983f36f3c6f4dc95eb379aea29583bd5e791b5bf251caeecbea0493871c` | `d3e70610e80ba71f96667ba8cf747856682e087bdb4d291412c92fc1ca702757` |

Each receipt records 11/11 software tests PASS with no software failures,
`softwarePass=true`, `originalIssueAcceptance=false`,
`standardUserWhpxExecuted=false` and physical case DASH-08-T04 **SKIP**.
The artifacts were available at the audit time, with expiry on 31 October 2026;
future availability must not be assumed.

### Failed full-release evidence and held acceptance

At that same exact candidate head, the
[core Windows CI](https://github.com/techrote/ezvm/actions/runs/38985065988) and
[offline replay](https://github.com/techrote/ezvm/actions/runs/38985066003) passed,
but the required
[full real-release Windows TCG job](https://github.com/techrote/ezvm/actions/runs/38985066027/job/117254507101)
**failed**. Its public log was inspected during this audit and reports:

- Fresh instance `ezvm012-fresh` did not reach authenticated SSH READY within
  676 seconds.
- A seven-second SSH process timeout reported that the child exited while its
  output streams remained unfinished.
- Graceful cleanup failed to stop that instance within 30 seconds and retained
  `STOPPING` rather than claiming a proven stopped owner.
- Guest serial diagnostics also recorded an IO-APIC/timer kernel panic. This is
  retained as an observed guest failure, without assigning a cause to the combined
  launcher/readiness/cleanup result.

The cause of this combined full-release failure is not established by EDF-001.
It must not be attributed speculatively to the QEMU launcher fix, omitted, or
turned into full candidate acceptance by the green native tests. PR #45 is
candidate evidence with an unresolved release failure, not accepted upstream
main. TCG evidence cannot supply the missing standard-user physical WHPX gate.

## Future selective repair boundary

EDF-002 must consume historical baseline entries, retaining traceable namespace
adaptation. It must not substitute these later files because their tests look
promising. EDF-003 can inspect the candidates, reproduce the relevant failures
with safe synthetic fixtures, select the smallest sufficient behavior, and run
its own current exact-head regressions. Preserve negative evidence and physical
qualification limits throughout that work.

No private historical patch bytes, key, overlay, authenticated agent state,
provider token, raw local-only record or comparison-fork source enters this
matrix or the product. Source paths and import destinations remain relative to
the factory/repository root; no original developer machine path is required.
