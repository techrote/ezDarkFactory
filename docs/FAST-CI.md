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

The EDF-003 hosted ordinary-user test script is also recorded in immutable repair provenance. The EDF-006 workflow therefore uses a source-identical `scripts/Invoke-Edf006PrivateAclHosted.ps1` qualification wrapper, differing only in its call to the new pinned-runtime acquisition helper, while retaining the original EDF-003 script byte-for-byte for historical verification.

The original EDF-002 imported `scripts/Install-TestPowerShell.ps1` remains byte-identical to accepted historical provenance. Current hosted/developer lanes use the EDF-006-owned `scripts/Install-Edf006ResilientTestPowerShell.ps1` instead.

The checked-in developer `Invoke-FastCheck.ps1` now acquires its pinned test
runtime in a unique OS temporary directory outside the repository and cleans
that directory in a `finally` block. The previous repository-internal
`runtime/test-tools` target contradicted the verified installer's deliberate
outside-repository guard and prevented the documented entry point from running
unless an executable path was supplied explicitly.

The GitHub-hosted PowerShell 7 lanes now use the SHA-pinned `actions/cache`
v5.0.1 action to retain the **exact official ZIP bytes** under an immutable
key tied to `tests/tooling.json`. Every cache hit is treated as untrusted:
the installer verifies the same official byte length and SHA-256 before
copying or executing any file. A corrupted cache is discarded and normal
pinned-source acquisition is attempted. A successful verified download
atomically populates the temporary archive cache. A failed cache save cannot
silently change the test result or bypass pin verification. This reduces
repeated dependency on intermittently failing upstream GitHub Releases
downloads; cold-cache jobs still require a reviewed transport.

The exact `7.6.6` Windows x64 ZIP, byte length (106328873) and official
SHA-256 remain locked in `tests/tooling.json`. The EDF-006 test installer
tries only fixed, reviewed transport routes for that **same** package, in
order: GitHub Releases (two attempts; 90-second per-request deadline), the official GitHub REST release asset
`551207033` (two attempts), the SourceForge versioned routed mirror (two
attempts), and its versioned direct mirror (one attempt). The official REST
asset ID was reconciled against the PowerShell v7.6.6 release metadata;
changing the pin requires explicit review of that route. SourceForge is a
third-party bit courier, not independent version or signature authority.

**Every completed download is checked against the official byte length and
SHA-256 before it can be extracted or executed.** A failed transport or
nonmatching HTTP payload (including a mirror-supplied HTML error page) is
discarded and its temporary archive removed before another reviewed route
is attempted. A source that returns nonmatching bytes is not retried; none
of its bytes are executed. If every route fails, acquisition refuses closed.
A second byte-length/hash check immediately precedes extraction, followed
by a pinned `pwsh` version check. No fallback to the runner's unpinned
system PowerShell or arbitrary downloaded payload is permitted. CI payloads
are installed outside the repository; historical EDF-002/003 imported
installer files remain untouched.

The Windows PowerShell 5.1 repository-contract job executes the offline
`tests/Invoke-Edf006PinnedPowerShellAcquisitionFixture.ps1` mock, checking
official-first and reviewed fallback order, malformed payload rejection,
all-routes-down refusal and cleanup. Actual pinned-runtime jobs exercise the
real network, SHA and version verification. **An offline mock PASS does not
establish that any particular external download endpoint is reachable.**

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
