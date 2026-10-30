---
document_id: EDF-BASELINE
status: authority
---

# Baseline provenance and historical cutoff

## Why this document exists

ezDarkFactory is intended to reproduce the **development VM environment** used for the original TUIsynth/TRIO work near the point that work was paused, then turn that environment into a clean general-purpose factory for fresh projects.

The historical TUIsynth repository state and the VM source are related but are not the same identity. In particular, later comparison repositories must not be substituted for the original local Git history.

## What GitHub can and cannot show

The original `techrote/tuisynth` repository reached:

- commit `e7060f6788421029ea9a1cb7cbee86a994c5b4d5`;
- subject: `[TRIO] Run programme locally with qualified Titan models (#20)`;
- a workflow contract in which agents clone/develop/test/review and squash-merge **locally inside the development VM**, without GitHub credentials or pushes.

Therefore GitHub commit history after that point is not a complete record of original TUIsynth implementation progress.

The repositories `techrote/tuisynth-codex` and `techrote/tuisynth-claude` are comparison work. Their commit sequences are useful comparative evidence only. They are **not** the original TUIsynth implementation line and must not be used to select the ezDarkFactory baseline.

## Surviving original local-development evidence

The EzVM TRIO field-study was extracted on 16 October 2026 after the original local development run had been paused. Its retained evidence records the following:

- **TRIO-FR-02:** accepted local main ended at `whole001..007`; the historical canonical checkout and a later partial pause checkpoint were different commits and roots.
- **TRIO-FR-05:** pause wrap-up preserved complete histories plus 89 incoming provenance rows and 151 original report blobs.
- **TRIO-FR-17:** pause wrap-up reconciled a concise handoff, component manifest, source hashes and ordered restart queue.
- The evidence index describes local-only source records E01 (pause handoff), E04 (component refs/source-test hashes/restart identity) and E17 (ordered restart queue/review gates/source identity).

Those raw local-only records are not currently available through the connected public repository evidence used to bootstrap ezDarkFactory. Consequently:

- the accepted **logical** cutoff `whole/TRIO-001..007` is established by the field-study;
- a later **partial** checkpoint is established to have existed;
- the exact local Git SHA/tree for either is **not established here**;
- no higher TRIO issue number may be inferred as accepted from a comparison repository;
- EDF-001 must record any newly recovered local checkpoint exactly if it becomes available, but implementation must remain possible without fabricating it.

## Development-VM source baseline

The same field-study's EzVM dashboard design explicitly records:

> Inspected local EzVM source: `b6abdf8`, with the owner's existing Keys.ps1 and Runtime.ps1 patches.

The full source identity is:

- repository: `techrote/ezvm`
- commit: `b6abdf8c3edd61695db30894da991f275b39a699`
- subject: `EZVM-012: qualify and package ezvm v0.1.0 (#26)`

This is the **historical source baseline for the VM reconstruction**.

It is not sufficient by itself to reproduce the observed development VM because two owner-local amendments existed:

1. `src/EzVm/Keys.ps1` — associated by later evidence with standard-user private-key/DACL handling.
2. `src/EzVm/Runtime.ps1` — associated by later evidence with the captured-start/QEMU lifetime problem.

The exact historical patch bytes are not assumed to be recoverable. ezDarkFactory must reconstruct their *required behavior*, not invent their contents.

## Later repair evidence: candidate inputs, not historical baseline

Later EzVM work is useful for replacing the two private amendments with reviewable public source:

- `7b829f8352a9fa30c965e57386965767c5969e0d` later changed `src/EzVm/Keys.ps1` and added standard-user DACL qualification.
- DASH-08 / EzVM issue #34 and its software child/PR later developed explicit native process handles, direct logs, exact process handoff and bounded lifecycle/readiness behavior for the start-pipe class of problem. The recorded software qualification passed its stated PowerShell lanes, while the parent physical standard-user/WHPX gate remained open.

These are **repair candidates to audit and selectively port**. Importing them wholesale would move the historical baseline forward and conflate later EzVM development with the requested reconstruction.

EDF-001/EDF-004 must produce a source/behavior matrix with four columns:

| Concern | Historical b6abdf8 source | Observed owner-local amendment | Later public repair evidence | ezDarkFactory disposition |
|---|---|---|---|---|
| private-key/DACL | inspect exact source | bytes may be unavailable | inspect `7b829f...` | port/reimplement only after regression evidence |
| QEMU start/output lifetime | inspect exact source | bytes may be unavailable | inspect DASH-08 candidate | port/reimplement only after regression evidence |

No historical owner patch may be described as byte-recovered unless its actual bytes and hash are obtained.

## Fresh-project import policy

EDF-001 must create a reviewed source manifest before adaptation.

The import must:

1. fetch exact EzVM source at `b6abdf8c3edd61695db30894da991f275b39a699`;
2. record repository, commit, tree identifier, retrieval time and per-file hashes for imported first-party files;
3. classify every imported file as unchanged baseline, adapted baseline, later repair, new ezDarkFactory source, historical reference or excluded;
4. exclude generated `runtime/` state, VM disks, installers, QEMU payloads, private keys, tokens, credentials, caches and the historical authenticated overlay;
5. retain only the VM/control-plane source needed to rebuild a clean environment;
6. preserve a path/namespace mapping for renamed EzVM source;
7. prevent TUIsynth from becoming the active/default project workspace;
8. keep TUIsynth reference/demo material isolated and opt-in;
9. record the unresolved exact local TUIsynth checkpoint instead of substituting comparison-fork bytes.

The historical VM is a **recipe and evidence source**, not a redistributable golden image.

## Provenance truth rule

Keep these categories distinct in every issue and PR:

- **historical source evidence** — bytes in a pinned upstream Git source;
- **historical field evidence** — recorded observations/hashes from the original local VM;
- **current source evidence** — what ezDarkFactory currently implements;
- **automated runtime evidence** — what was actually executed in CI or a retained harness;
- **physical/human evidence** — WHPX/GUI/Windows Terminal/usability checks performed on the stated machine.

Never promote one category into another.
