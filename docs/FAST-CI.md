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
