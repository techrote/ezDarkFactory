# EDF fast merge gate and EDF-003 qualification

The **single baseline Windows developer entry point** (SOURCE and inherited control-plane) is:

```powershell
.\scripts\Invoke-FastCheck.ps1
```

It runs the authenticated source/FAST-CI Python gate (fresh exact-source Git
objects), Windows PowerShell 5.1 repository contract, Windows PowerShell 5.1
control-plane suite, and verified PowerShell 7.6.6 control-plane suite, failing
on any nonzero exit. It may download the pinned public PowerShell test runtime
into this factory's Git-ignored `runtime/test-tools/`; no private data is
needed. The CLI harness also works from a path with spaces.

The five inherited required exact-head GitHub jobs in `.github/workflows/ci.yml` are:
`Provenance (ubuntu-24.04)`, `Provenance (windows-2022)`,
`Repository contract (Windows PowerShell 5.1)`,
`Control plane (Windows PowerShell 5.1)`, and
`Control plane (PowerShell 7.6.6)`. (The two provenance jobs form one
matrix.) All are required on every implementation PR; zero/all-skipped is not PASS.

For focused offline checks with previously fetched public pinned Git objects:

```powershell
python tools/check.py --ezvm ..\ezvm-upstream --tuisynth ..\tuisynth-upstream
.\scripts\Invoke-CiCheck.ps1 -Check Repository -ExpectedMajor 5
.\scripts\Invoke-CiCheck.ps1 -Check ControlPlane -ExpectedMajor 5
```

These checks validate source, configuration, schemas, lifecycle/storage/security
unit fixtures and repository boundaries. **No real guest, QEMU/WHPX execution,
Windows Terminal user interaction or human qualification is performed.**
The imported historical Keys/Runtime owner patches remain unproven until EDF-003.

## Pinned PowerShell 7 test-runtime transport resilience

The original EDF-002 imported `scripts/Install-TestPowerShell.ps1` remains byte-identical to accepted historical provenance. Current hosted/developer lanes use the EDF-006-owned `scripts/Install-Edf006ResilientTestPowerShell.ps1` instead.

The exact `7.6.6` Windows x64 ZIP, expected byte length and SHA-256 remain
locked in `tests/tooling.json`. `scripts/Install-Edf006ResilientTestPowerShell.ps1` first
attempts the official GitHub Releases URL (up to three bounded transports).
Only if all official requests fail at the transport layer does it attempt
the exact-version SourceForge project mirror (up to two bounded requests).
The mirror is **not** an independent version or trust authority: both routes
are checked against the **same reviewed upstream bytes and digest** before
extraction or execution. A completed download with the wrong size or hash
fails immediately, with no fallback to a different archive or system `pwsh`.
Acquisition still writes only outside the source tree, and failed downloads
are removed. SourceForge is an availability dependency, not an authentication
substitute.

The Windows PowerShell 5.1 repository-contract lane runs an entirely offline
mocked-transport fixture at
`tests/Invoke-Edf006PinnedPowerShellAcquisitionFixture.ps1`. It verifies
official-first ordering, exact-version fallback after transport exhaustion,
refusal of mismatching archive bytes without extraction, all-sources-down
refusal and temporary-file cleanup. Normal PowerShell 7 CI lanes remain the
actual-download/hash/version integration qualification.

## EDF-003 additional Windows gates

The Keys/Runtime public-source repair adds **four** required Windows jobs to
the five inherited jobs: focused native-process qualification (PS5.1 and
verified PS7.6.6), and disposable **ordinary-user** DACL qualification
(one job for each engine). Both run against the exact PR/merged main head.

The 11 native synthetic child/loopback-QMP cases can be reproduced
on a Windows x64 developer machine without creating accounts:

```powershell
.\scripts\Invoke-Edf003SoftwareQualification.ps1 -ExpectedMajor 5 -OutputDirectory "$env:TEMP\edf003-native-proof-ps5"
```

Repeat under the exact pinned PS7.6.6 executable with `ExpectedMajor 7`
and a different new destination. Its receipt is source-hash-bound; it is
not a real guest/WHPX proof.

The [ordinary-user qualification](provenance/EDF-003-REPAIRS.md)
must not be inferred from a developer session or the normal administrator
runner. GitHub-hosted CI alone invokes
`scripts/Invoke-Edf003PrivateAclHosted.ps1` in a disposable runner,
creates and removes its own synthetic test-only account, checks the token,
and proves negative baseline vs corrected DACL behavior. This helper
**refuses execution outside GitHub-hosted Windows**; do not copy its account
setup procedure to an owner's PC.

The local `Invoke-FastCheck.ps1` validates the complete five-job baseline.
EDF-003 acceptance additionally needs **all four** special CI lanes, for
**nine** exact PR-head jobs and a fresh post-merge main run. Retained
upstream DASH-08 TCG failures and unmeasured physical-WHPX status are not
converted into software PASS.

## EDF-004 focused guest contract

EDF-004 adds two required Windows FAST-CI jobs (PS5.1 and pinned PS7.6.6)
running `scripts/Invoke-Edf004Qualification.ps1`. They do not launch QEMU;
they prove source/generated seed/readiness and reset/fresh-clone contracts.
Together with the inherited nine jobs, EDF-004 acceptance requires **11**
literal-head checks and the same 11 checks on actual merged `main`.
