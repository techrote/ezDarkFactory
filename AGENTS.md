# AGENTS.md

## Purpose

ezDarkFactory is a Windows-first, portable QEMU/QCOW2 development-VM factory for starting fresh software projects under human control. It is derived from a pinned EzVM source checkpoint, but it is a new project with its own namespace, runtime state, documentation, tests and release history.

TUIsynth/TRIO is historical reference material only. No ezDarkFactory issue may resume, complete or extend the TUIsynth programme unless the issue explicitly says the task is a reference-fixture maintenance action.

## Authority order

For every issue, use this order:

1. current `main` source, tests and CI;
2. higher-priority repository safety, lifecycle/storage/security, functional and compatibility contracts in this `AGENTS.md` and `RAG.md`;
3. the current GitHub issue body and all issue comments, provided they do not silently conflict with item 2;
4. other RAG documents listed by the issue;
5. `docs/programme/IMPLEMENTATION-PROGRAMME.md`;
6. historical EzVM/TUIsynth material.

For host-manager/UI work, `docs/rag/03-HUMAN-CONTROL-SURFACE.md` is the authoritative project-specific UI/UX and UI implementation contract. An issue may change it only through an explicit, reviewed specification amendment; stale issue wording does not override it.

Never rely on a checkpoint in prose without rechecking current repository and issue state.

## Mandatory pre-work

Before editing:

1. fetch current `main`, record its exact SHA and require a clean worktree;
2. read the complete issue and comments;
3. read this file, `RAG.md`, and every document under **Read first** in the issue;
4. inspect open/recent PRs touching the same subsystem;
5. inspect exact-head CI, current tests and dependency issue status;
6. reconcile historical pins against `docs/rag/01-BASELINE-PROVENANCE.md`;
7. state what is source evidence, what is automated-runtime evidence, and what still requires a physical/human acceptance check.

If a dependency is not merged and green, stop and record the block instead of working around it.

## Branch, implementation and review

Use one branch per issue: `edf-NNN-short-slug`.

Implement the smallest complete change that satisfies the issue. Add or update tests for every machine-verifiable acceptance criterion. Do not weaken, delete, skip or xfail an existing test merely to obtain green CI.

Before opening the PR:

- rebase or otherwise update against current `main`;
- run the issue's focused tests;
- run the repository merge gate named by the current testing contract;
- inspect `git diff main...HEAD` for accidental runtime data, credentials, generated images, binaries and unrelated changes;
- update documentation/RAG when a contract changes;
- record exact commands and results in the PR body.

Perform a substantive source and risk review of the final diff. If another reviewer is available, incorporate that review; absence of a second account does not excuse the author from reviewing the actual code and evidence.

## PR, CI, merge and post-merge completion

Every implementation issue is an end-to-end execution prompt. Do **not** stop after opening a PR.

1. Open a dedicated PR with `Closes #<issue>`.
2. Wait only by actively polling current PR/check state in the same execution; do not claim work will continue later.
3. Fix all applicable failed automated checks and all blocking review findings.
4. Re-run or verify exact-head required checks after each fix.
5. Merge only when the PR is mergeable and every required automated check for the exact head is green.
6. Fetch current `main` after merge and verify the merged commit and required checks.
7. If post-merge validation fails, create the smallest corrective follow-up immediately or revert where that is safer. Never label a broken merge accepted.
8. Close only when the issue acceptance criteria are evidenced. Manual/physical gates may remain explicitly pending only when the issue contract permits that state; release qualification may not convert an unperformed manual gate into PASS.

## Non-negotiable architecture rules

- Primary host: Windows x86-64.
- Preserve the EzVM baseline's repository-local QEMU model, immutable managed base -> one mutable QCOW2 overlay, lifecycle locks, process-identity checks, relocation-safe state and localhost-only SSH forwarding unless an issue explicitly changes a contract with tests.
- A working factory is a self-contained portable folder. No critical factory identity/configuration/recovery/key/VM state may exist only in hidden host-local application data.
- Runtime images, QEMU/7-Zip payloads, keys, credentials, tokens, caches, downloaded model weights and generated VM state are never committed.
- External acquisition is pinned and hash-verified.
- UI code never edits instance JSON, process evidence, QCOW2 metadata or trust files directly. It calls typed control-plane/broker operations.
- The primary UI is the host-side tile-native management TUI specified by `docs/rag/03-HUMAN-CONTROL-SURFACE.md`.
- One manager may register and observe multiple local ezDarkFactory roots; each root remains its own lifecycle/storage/security authority.
- The manager must not infer factory identity from path alone or silently mutate two reachable copies with the same factory identity.
- Ordinary relocation preserves factory/instance identities; creating a second independently writable copy requires explicit fork/rekey.
- Cross-factory manager registry/layout state is optional portable convenience state, not factory authority. A factory must remain directly operable by path without it.
- No automatic paid inference, provider registration or credential import.
- A clean project VM starts with an empty project workspace. Reference/demo content is isolated from the active workspace and is never the default working directory.
- TUIsynth reference material must remain pinned, labelled historical/demo-only and unable to affect normal project creation.
- Opening a dashboard/view or registering a factory must not start a VM, worker, inference job or network mutation.
- Destructive actions require explicit target identity, lifecycle validation and the confirmation model defined by the host-manager specification.

## Host management TUI direction

The owner has selected a **host-side, GUI-like TUI manager** as the v0.1 primary interface.

This is no longer a GUI-vs-TUI product decision.

Implementation work must preserve the semantic UI contract in `docs/rag/03-HUMAN-CONTROL-SURFACE.md`, including:

- multiple registered local factory roots;
- one semantic command layer;
- persistent tile workspace;
- mouse/keyboard command parity;
- bounded asynchronous observation;
- per-root operation ownership and reconciliation;
- Windows Terminal native qualification;
- CLI/helper recovery when the TUI cannot launch.

A future native GUI or remote-host adapter may reuse the semantic layer only through an explicit project/spec delta.

QEMU graphical display and a guest desktop are not v0.1 management requirements.

## Testing truthfulness

Fast CI must not claim physical WHPX, Windows Terminal, real GUI interaction, audio/MIDI, GPU/model or human usability evidence it did not execute.

Use explicit labels such as PASS, FAIL, SKIP, UNMEASURED and HUMAN-PENDING. TCG orchestration evidence is not WHPX performance evidence. Headless UI simulation is not physical Windows Terminal acceptance.

## Secrets and reference data

Never place private keys, provider tokens, authenticated overlays, raw private transcripts or personal account state in the repository or release artifacts.

The TUIsynth demo/reference may contain only public source material pinned by commit plus synthetic/demo data. It must not inherit the historical lab VM's credentials, caches or runtime state.
