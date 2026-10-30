# EDF-001 source provenance and import plan

This directory reconstructs the **source recipe** for the original development VM.
It does not contain an imported VM core, a VM image, recovered private patches, or
an accepted original local TUIsynth checkout. EDF-002 consumes the reviewed import
plan; EDF-003 reconciles the two amendment classes. The current EDF charter,
architecture, security and portability contracts govern both steps.

## Authenticated baseline and scope

| Field | Value |
|---|---|
| Original source | [techrote/ezvm](https://github.com/techrote/ezvm) |
| Commit | `b6abdf8c3edd61695db30894da991f275b39a699` |
| Tree | `78e5ce0db9c32972451add22d28c7d19983775ee` |
| Commit timestamp | `2026-10-14T00:02:23Z` |
| Subject | `EZVM-012: qualify and package ezvm v0.1.0 (#26)` |
| Initial EDF authority | `f996fd3e6a68157b2d7507ee660dac29fb9d6fbe` |
| Baseline inventory | All **110** tracked files, each an ordinary text blob |
| Proposed EDF-002 import | **87** files: 8 unchanged imports and 79 adaptations |
| Baseline reference-only | **23** files |
| Supplemental references | **34** hashed files; **144** source records overall |

Every baseline file is inventoried, including all 25 control-plane files, tests,
fixtures, configuration, manifests, guest recipes, scripts, user documentation,
acquisition notices, packaging/recovery/portability tooling and historical
automation/contracts. There are no omitted baseline paths hidden by an allowlist.
No forbidden generated/private payload occurs in this baseline tree; the exclusion
rules describe prohibited material rather than inventing missing file records.

The original field extraction and later replay revision are separately pinned.
Their observation/index bytes match; the later README adds public programme and
replay context. Later ACL and process-lifetime candidates are separate sources.
The original TUIsynth programme pin is separately authenticated as
`e7060f6788421029ea9a1cb7cbee86a994c5b4d5`, tree
`0b5d96d1979ed150734ae95938395165bc40530a`.

## Artifacts and authority

| Artifact | Purpose |
|---|---|
| [selection.json](selection.json) | Reviewed, explicit per-path classifications, relative destinations, treatments, exclusions, source pins and portability decisions. This is the generator input. |
| [manifest.json](manifest.json) | Deterministic derived commit/tree metadata, Git blob IDs, raw-blob SHA-256/size/mode, acquisition descriptors, six required field observations and the published metadata for all 17 unavailable local-only records. This is the EDF-002 machine-readable import contract. |
| [provenance.schema.json](provenance.schema.json) | Closed Draft 2020-12 manifest schema; `$defs.selection` describes the reviewed input. |
| [LOCAL-AMENDMENTS.md](LOCAL-AMENDMENTS.md) | Historical baseline / owner-local field report / later public repair / EDF disposition matrix for Keys and Runtime. |
| [TUISYNTH-CUTOFF.md](TUISYNTH-CUTOFF.md) | Exact public programme pin, local development by design, reported accepted logical cutoff, distinct partial pause, unresolved original local Git identities. |
| [HISTORICAL-EVIDENCE.md](HISTORICAL-EVIDENCE.md) | Field-study provenance, required findings and limitations. |
| [audit-2026-10-30.json](audit-2026-10-30.json) | Dated public upstream PR/check state and bounded receipt summaries, including the failed candidate TCG run. This fixed snapshot is not live acceptance authority. |
| [provenance tool](../../tools/provenance.py) | Offline raw-Git-object authentication, deterministic generation, verification and read-only import-plan output. Optional public Git fetch is explicit. |
| [merge gate](../../tools/check.py) | Complete EDF-001 SOURCE / FAST-CI checks; zero tests, skipped tests and failures are refused. |

The generator records the fixed retrieval timestamp from the reviewed input,
never the current wall clock. Commit timestamps come from authenticated commit
objects. The later audit snapshot has its own observation time. Re-running
generation does not pretend to perform a new live GitHub audit.

## Classification and mechanical consumption

| Classification | Meaning and treatment |
|---|---|
| `unchanged-import` | Selected baseline bytes must retain their exact blob/SHA-256 when copied to the listed relative destination. A subsequent change requires adapted provenance. |
| `adapt-rebrand` | Selected baseline bytes are the preimage. EDF-002 must record its transformed output hash and retain the source identity while applying the listed namespace/contract treatment. |
| `later-repair-candidate` | Public source/tests/evidence to inspect in EDF-003. `edf002_import` is false and `destination` is null; these cannot silently replace baseline bytes. |
| `new-edf-source` | Current EDF-001 tooling/docs/CI listed separately under `new_edf_source`; no upstream byte identity is fabricated for newly authored files. Their enclosing EDF commit supplies their identity. |
| `historical-reference-only` | Evidence or historical authority, with no active import destination. Never execute historical instructions or treat upstream results as EDF qualification. |
| `excluded-generated-private` | Global component/filename policy for runtime, disks, installers, binaries, private keys, account/session state, model caches and private evidence. Such data is never admitted as import source or destination. |

An EDF-002 consumer must first run the full verification gate, then select only
rows where `edf002_import` is exactly `true`. Join `source_id` to `sources` and
read the pinned commit's `source_path` from Git. Verify mode, blob, SHA-256 and
length before using its bytes. `destination` is relative to the new factory root,
never to a developer profile. No destination expands environment variables or
contains a drive, UNC path, traversal, alternate stream or Windows device name.

The verified plan can be emitted mechanically:

```powershell
python tools/provenance.py import-plan --ezvm ..\ezvm-upstream --tuisynth ..\tuisynth-upstream
```

This command emits JSON only; EDF-001 implements no copy/import operation.
The `intended_treatment` field is part of the contract, not optional commentary.
In particular, README, `.gitignore` and CI require integration with existing EDF
files. The current provenance CI lane must survive adaptation of upstream CI.
Historical AGENTS/RAG/programme contracts cannot overwrite EDF authority.
Release/real-guest workflows are reference-only; importing manual harness source
does not authorize running or publishing it. No upstream test may be weakened
merely to make namespace adaptation green.

| Source shape | Planned destination |
|---|---|
| `ezvm.ps1` | `ezdarkfactory.ps1` |
| `src/EzVm/*.ps1` | `src/EzDarkFactory/*.ps1` |
| `src/EzVm/EzVm.psd1`, `EzVm.psm1` | `src/EzDarkFactory/EzDarkFactory.psd1`, `EzDarkFactory.psm1` |
| `scripts/*EzVm*.ps1` | Explicit `*EzDarkFactory*` names listed in the manifest |
| Selected config, guest, manifests, tests and operator docs | Explicit root-relative paths in the manifest, with per-file treatment |

The complete per-file table is deliberately machine-readable rather than a second
manually maintained list of 144 hashes. Missing/duplicate baseline entries,
source identities and Windows-colliding destinations fail verification.

## Reproduce and test

Requirements: Git and Python 3.11 or newer. No third-party Python package,
PowerShell execution, VM, WHPX, provider account or upstream script is required.
Run from the EDF repository root. PowerShell and shell examples use explicit
locations; nothing is stored in hidden host application data.

To fetch only the pinned public Git source objects and run the entire gate:

```powershell
python tools/check.py --fetch --sources .provenance-cache
```

The source cache is disposable and contains bare Git repositories, not checkouts
or runtime payloads. It is excluded from commits. The fresh-network step may fail
if GitHub is unavailable; that is not converted into a verification PASS.

With existing exact Git objects, verification and generation are offline:

```powershell
python tools/check.py --ezvm ..\ezvm-upstream --tuisynth ..\tuisynth-upstream
python tools/provenance.py generate --ezvm ..\ezvm-upstream --tuisynth ..\tuisynth-upstream
git diff -- docs/provenance/manifest.json
```

The final diff must be empty for unchanged inputs. On Linux/macOS use `/` in the
two checkout paths. Source paths can contain spaces and Unicode; quote command
arguments accordingly. The cache paths are invocation parameters and never enter
the manifest. Raw Git objects bypass checkout line-ending conversion, sparse
checkout state, executable filters and dirty worktree content. Commit, root tree,
intermediate trees and each selected blob are authenticated by Git object ID;
file SHA-256 is over the exact blob bytes.

The closed offline schema evaluator rejects unsupported keywords instead of
silently ignoring them. The published schema is usable by a full Draft 2020-12
validator too. Behavioral tests attack wrong types/hashes, duplicate keys/rows,
missing inventory, path aliases, comparison authority, altered historical claims,
unsafe imports and private/binary payloads. The repository scan checks both index
bytes and candidate working-tree bytes, including ignored files if tracked.
Pattern checks supplement substantive review; they are not a claim that arbitrary
secret text can always be recognized automatically.

GitHub CI runs this same entry point on `ubuntu-24.04` and `windows-2022`, using
Python `3.12.10`. It checks out the literal PR head (or actual merged main).
Checkout is pinned to `11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2), the
historical baseline's reviewed action. Setup-python is pinned to
`83679a892e2d95755f2dac6acb0bfd1e9ac5d548` (v6.1.0), whose official tag and action
metadata were reverified. The workflow has read-only repository permissions and
does not persist checkout credentials. These are EDF-001's complete required
automated checks. EDF-002 later extends the repository gate with the imported
PowerShell/control-plane suites; none is claimed to have run in this issue.

## Acquisition and portability limits

The manifest retains the exact baseline acquisition descriptors for QEMU 11.1.0
build 20260811 (SHA-512), 7-Zip 26.04 bootstrap/full extractor (SHA-256), Ubuntu
24.04 noble publication 20260926 (SHA-256), PowerShell 7.6.6 (SHA-256), and pinned
GitHub Actions. These were inspected as source. No installer, guest image or
runtime payload was downloaded or executed, and no present URL availability or
external payload digest validation is claimed by EDF-001.

The base recipe enables `package_update` and names Ubuntu packages without exact
package versions. The recipe/cloud-image identities are reproducible; the precise
historical prepared guest package set and disk bytes are not established. No
first-party LICENSE file is present in the baseline; third-party notices remain
selected for reviewed adaptation. Provider payload redistribution is excluded.

Baseline `Paths.ps1` derives config, keys, QEMU, caches, bases, instances and locks
below the supplied root. Some runtime absolute paths are process-ownership
observations, not durable factory identity. Destination setup must revalidate
those observations and current-user key ACLs. Future factory-ID collision and
fork/rekey behavior is not implemented or proven by baseline cold portability.

A future **working factory folder** intentionally contains sensitive runtime state
needed to move that factory. A **source repository/public release** excludes it.
Critical identity/config/recovery/key/VM state stays with the factory; optional
manager layout/registry state cannot become required hidden host authority.
Ordinary relocation preserves identity, while an independently writable copy
requires explicit fork/rekey. The historical authenticated overlay is never an
input. TUIsynth remains isolated reference/demo material, and the host-side
multi-factory TUI is not implemented by EDF-001.

## Evidence and acceptance boundary

EDF-001 can establish **SOURCE** identity and **FAST-CI** validation only.
Historical field observations are attributed reports, and inspected upstream
software/TCG receipts retain their original evidence class and limitations.
WHPX, physical Windows Terminal and human usability remain unmeasured here.

Both owner-local amendment classes are **candidate repair / unresolved historical
equivalence**. Exact original accepted/partial TUIsynth Git SHA/tree and the
private owner patch bytes remain unavailable. The public report of accepted
`whole/TRIO-001..007` is preserved without substituting comparison-fork work.

Completion requires a dedicated PR, substantive final source/provenance/security
review, both exact-head CI jobs green, guarded merge and verified actual main.
The issue's post-merge handoff is the durable accepted-revision record. No runtime
qualification or EDF-002 implementation is implied by provenance acceptance.
