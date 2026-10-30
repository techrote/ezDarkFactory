# EDF-002 development source and acquisition contract

**Status: 0.0.0-dev, not an ezDarkFactory release.** This repository contains
a traceable import of the EzVM v0.1.0 source. EDF-002 qualifies source/FAST-CI
only. No real QEMU guest, WHPX, Windows Terminal or human use was exercised
by this issue. In particular **WHPX is UNMEASURED**.

The pinned upstream reference is `techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699`,
tree `78e5ce0db9c32972451add22d28c7d19983775ee`.
Read [the provenance manifest](provenance/README.md) for all original Git blobs,
SHA-256, root-relative import destinations and transformations.

The following unchanged manifests are retained as **source acquisition pins**,
not evidence that the corresponding third-party payload was downloaded, built
or verified in EDF-002:

- QEMU version: `11.1.0`; build: `20260811`; provider digest: `5bcf9eed634e8575a37b74f445af41a2fe4106da512d0c30c368301d4c105037fdfab40a5287367a28a957624cddebbc8c07e16c88ab6634f554cdf3d16bf543`.
- 7-Zip extractor: `26.04`; bootstrap digest: `256feca8e274e5da655e2a284fabafd9f554365eb164862089dacd4e8276d282`; full package digest: `d54bf805f9f3704d1e8db2fa3498ae7ef2df0312b40b558e7c71c734430a665d`.
- Ubuntu noble publication: `20260926`; image SHA-256: `6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2`.
- Pinned test PowerShell version: `7.6.6`.

The guest recipe uses Ubuntu package names without frozen versions and runs
`package_update`, so this source pin does not produce a byte-for-byte copy
of the original prepared devbox by itself.

The two historical owner-local Keys.ps1 and Runtime.ps1 amendments remain
candidate repairs for EDF-003, not imported patches. No historical provider
identity, model cache, worktree, key or mutable overlay is present.

The source-only development ZIP is an offline test artifact. The guarded
GitHub publisher is disabled until EDF-012; no release workflow is installed.

## Execute fast checks

```powershell
python tools/check.py --fetch --sources .provenance-cache
.\scripts\Test-Repository.ps1
.\scripts\Invoke-CiCheck.ps1 -Check ControlPlane -ExpectedMajor 5
```

GitHub checks use Windows PowerShell 5.1 and separately acquired verified
PowerShell 7.6.6; zero/all-skipped lanes fail. A normal working factory keeps
generated `runtime/` state, including sensitive key/disk material, within
its folder; source Git never includes it. Preserve identity on relocation;
do not run independently writable duplicates without future fork/rekey.
