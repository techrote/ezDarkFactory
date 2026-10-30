---
document_id: EDF-BASELINE
status: authority
---

# Baseline provenance and historical cutoff

## Why this document exists

ezDarkFactory intentionally begins from the VM environment that surrounded the end of TUIsynth implementation, but the new project must not accidentally inherit TUIsynth as its active workload.

The cutoff is evidence-based and fixed.

## TUIsynth implementation cutoff

Current repository history was inspected on 30 October 2026.

The last implementation commit in the active implementation fork is:

- repository: `techrote/tuisynth-codex`
- commit: `357215781ba0b82694e62dd4d7ba1c3697ac3159`
- timestamp: **2026-10-18 09:25:55 UTC**
- subject: `TRIO-016: synchronize headless input completion (#34)`

Immediately before it, TRIO-016's modulation/FX implementation landed at `a3cb0b2a0ad9d8098234c1d00a6ef16ead0717de`.

The next planned item, **TRIO-017 Packaging, launchers, documentation and v0.1 software release qualification**, remained open. No later synth implementation commit was found in `tuisynth`, `tuisynth-codex` or `tuisynth-claude` through the inspection date.

Therefore ezDarkFactory treats TRIO-016 completion as the point at which synth development ceased. It does **not** absorb TRIO-017 as pending work.

## Matching EzVM checkpoint

The last EzVM commit before the synth implementation burst and before the above cutoff is:

- repository: `techrote/ezvm`
- commit: `7b829f8352a9fa30c965e57386965767c5969e0d`
- timestamp: **2026-10-17 17:32:34 UTC**
- subject: `Fix standard-user private DACL handling and defer hosted TCG for CI-PoC (#48)`

The next EzVM commits are after synth development ceased, beginning with `62038cf8db68e8b863054c112d79b727e8776031` at **2026-10-18 12:00:05 UTC**. Those later CI-PoC changes are not part of the historical baseline unless a later ezDarkFactory issue explicitly evaluates and imports them.

The baseline already contains the EzVM v0.1 control plane and the read-only dashboard prototype. It also contains TRIO field-research documentation. Importing a checkpoint does not make all checkpoint documents/product assumptions current ezDarkFactory policy.

## TUIsynth reference pins

Two different historical references serve different purposes:

- `techrote/tuisynth@e7060f6788421029ea9a1cb7cbee86a994c5b4d5`: programme/local-workflow documentation showing the development-VM execution model.
- `techrote/tuisynth-codex@357215781ba0b82694e62dd4d7ba1c3697ac3159`: implemented synth state through TRIO-016, suitable as the optional runnable demo/reference.

Do not merge their histories or pretend the main TUIsynth repository contains the implementation-fork state.

## Import policy

EDF-001 must create a reviewed source manifest before adaptation.

The import must:

1. fetch the exact EzVM baseline commit;
2. record source repository, commit, tree identifier when available, retrieval time and per-file hashes for imported first-party files;
3. copy only source/config/docs/tests needed to reproduce the VM control plane and its accepted acquisition/build/lifecycle behavior;
4. exclude generated `runtime/` state, VM disks, installers, QEMU payloads, private keys, tokens, credentials and caches;
5. explicitly classify historical dashboard/TRIO-specific material as either adapted source, retained reference or excluded material;
6. keep an auditable path mapping when namespaces/paths are renamed;
7. add a regression that prevents accidental reintroduction of TUIsynth as the default workspace.

No runtime behavior may be claimed merely because the historical source had documentation for it. ezDarkFactory must requalify applicable automated/runtime behavior under its own exact source.

## Provenance truth rule

Keep these distinct in every issue and PR:

- **historical source evidence**: what a pinned upstream source says or contains;
- **current source evidence**: what ezDarkFactory currently implements;
- **automated runtime evidence**: what was actually executed in CI or a recorded harness;
- **physical/human evidence**: WHPX/UI/usability checks performed on the stated machine.

Never promote one category into another.
