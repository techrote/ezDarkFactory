# EDF-002 fast merge gate

The **single complete Windows developer entry point** is:

```powershell
.\scripts\Invoke-FastCheck.ps1
```

It runs the authenticated source/FAST-CI Python gate (fresh exact-source Git
objects), Windows PowerShell 5.1 repository contract, Windows PowerShell 5.1
control-plane suite, and verified PowerShell 7.6.6 control-plane suite, failing
on any nonzero exit. It may download the pinned public PowerShell test runtime
into this factory's Git-ignored `runtime/test-tools/`; no private data is
needed. The CLI harness also works from a path with spaces.

The five required exact-head GitHub jobs in `.github/workflows/ci.yml` are:
`Provenance (ubuntu-24.04)`, `Provenance (windows-2022)`,
`Repository contract (Windows PowerShell 5.1)`,
`Control plane (Windows PowerShell 5.1)`, and
`Control plane (PowerShell 7.6.6)`. (The two provenance jobs form one
matrix.) All are required for EDF-002 acceptance; zero/all-skipped is not PASS.

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
