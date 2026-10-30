# ezDarkFactory

A Windows-first, **folder-portable** development-VM factory for fresh projects, with one host-side management TUI capable of operating multiple local ezDarkFactory roots.

## Status

EDF-001 provenance is accepted. EDF-002 imports the namespaced source control plane and first-party tests as a **development build**; the host multi-factory TUI, clean guest profile, owner-local amendment fixes and physical/runtime qualification remain later issues.

EDF-001 adds a deterministic [baseline provenance and import plan](docs/provenance/README.md)
with source authentication and automated negative tests. It inventories the exact
historical recipe without importing the VM implementation or private runtime state.

Start with:

- `AGENTS.md` — autonomous implementation/PR/merge contract;
- `RAG.md` — project authority index;
- `docs/rag/03-HUMAN-CONTROL-SURFACE.md` — authoritative multi-factory host-management TUI UI/UX and implementation specification;
- `docs/programme/PLAN-REVIEW.md` — plan review and revised execution direction;
- `docs/programme/IMPLEMENTATION-PROGRAMME.md` — dependency graph and issues #1–#12.

## Historical reconstruction

- **VM source baseline:** `techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699` (EzVM v0.1.0).
- The October 2026 TRIO field study records that the inspected development VM used that source plus owner-local `Keys.ps1` and `Runtime.ps1` patches.
- **Original TUIsynth programme pin:** `techrote/tuisynth@e7060f6788421029ea9a1cb7cbee86a994c5b4d5`; later original implementation work occurred in local Git inside the VM.
- The field study records accepted local synth main as `whole/TRIO-001..007` and a distinct later partial pause checkpoint. The exact local SHA is not currently established and must not be guessed.
- `tuisynth-codex` and `tuisynth-claude` are comparison work, not original-development authority.
- TUIsynth is reference/demo material only in ezDarkFactory.

See `docs/rag/01-BASELINE-PROVENANCE.md`.

## Portability goal

A specific working ezDarkFactory is a self-contained portable folder.

The intended move is deliberately simple:

1. stop its VMs and run the portability check;
2. zip/archive the factory folder;
3. move/extract it on another compatible Windows computer;
4. run the checked-in setup/doctor step;
5. open/start it from the new path.

Factory/instance identities and working state travel with the folder. Host-specific process state, endpoints and ACLs are revalidated on the destination.

No critical factory configuration or recovery state may exist only in `%LOCALAPPDATA%` or another hidden machine-local location.

A stateful working bundle may contain SSH keys or guest credentials, so transferred archives are sensitive.

Cross-factory manager layout/registry state is optional, portable convenience state; a factory remains directly operable without it.

## Primary host interface

v0.1 uses a **tile-native, mouse-and-keyboard TUI GUI** on the Windows host.

One manager process can explicitly register, observe, and safely operate multiple local ezDarkFactory roots. Each root remains authoritative for its own VM lifecycle, images, keys, storage locks, and control semantics.

The manager provides persistent tiles, semantic commands, menus/overlays, command palette, direct manipulation, bounded asynchronous observation, per-root operation reconciliation, logs/resources, and project/lifecycle/recovery workflows.

A graphical QEMU console or guest desktop is not required for v0.1. Guest interaction can use the accepted managed SSH/external-terminal path.

The authoritative VM lifecycle remains a testable control plane. The TUI calls typed broker/control operations and never edits instance JSON, QCOW2 state, process evidence, or trust files directly.

## Shared UI specification pin

The tailored host-manager specification is pinned to:

`techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`.

Future specdocz changes are reviewed as explicit deltas; they are not silently inherited.

## EDF-002 developer CLI (no TUI yet)

From an **unelevated Windows PowerShell 5.1** window in this checkout:

```powershell
.\ezdarkfactory.ps1 help
.\ezdarkfactory.ps1 version -Json
.\ezdarkfactory.ps1 doctor -Json
.\scripts\Test-Repository.ps1
.\scripts\Invoke-CiCheck.ps1 -Check ControlPlane -ExpectedMajor 5
```

The direct CLI is the recovery/automation surface and currently reports
**0.0.0-dev**. Its authority is always this factory root, not another EzVM
checkout, profile-local application-data folder or external manager workspace.
`doctor` may report missing optional QEMU/SSH/Windows prerequisites. Acquiring
verified VM dependencies and building/starting a real guest is a deliberate
operator operation; source/FAST-CI tests make no WHPX/guest success claim.

The inherited baseline implementation exposes bootstrap, base, instance
lifecycle, SSH/readiness, storage, clone, import/export and portability
primitives. See [getting started](docs/GETTING-STARTED.md),
[portability](docs/PORTABILITY.md) and [development source limits](docs/DEVELOPMENT.md).
EDF-003 and EDF-004 will repair the historical local amendment classes and
implement the clean fresh-project guest contract. The host-side multi-factory
tile-native TUI is a later milestone and is **not** claimed to exist yet.

New factory state is root-local under `runtime/`, deliberately Git-ignored.
Source trees and releases exclude generated disks, keys, accounts and caches.
A relocated *stopped working folder* preserves its persisted instance identity;
an independently writable duplicate requires an explicit later fork/rekey.
Do not present unqualified dev source packaging as an EDF v0.1 release.
