# ezDarkFactory implementation programme

## Objective

Deliver a Windows-first, portable, human-operated factory for fresh coding VMs, reconstructed from the original TUIsynth development-VM environment but free of TUIsynth active-project state.

The primary human interface is the host-side multi-factory tile-native TUI specified by `docs/rag/03-HUMAN-CONTROL-SURFACE.md`.

Every EDF issue is an execution prompt. It must be taken from current `main` through implementation, tests, review, PR, exact-head green checks, merge and post-merge verification according to `AGENTS.md`.

## Authority

Before any issue:

1. read current `AGENTS.md`;
2. read current `RAG.md`;
3. read the issue and every document under its **Read first** section;
4. reconcile current `main`, dependency issues/PRs and CI;
5. do not rely on stale hashes in this catalogue without re-verifying repository state.

Historical pins in the RAG are provenance inputs and do not override current ezDarkFactory source.

## Dependency graph

```text
EDF-001  historical baseline reconstruction/import
   |
EDF-002  core fork/namespace + CI
   |
   +--------------------+
   |                    |
EDF-003 lifecycle       EDF-004 fresh guest
 patch reconciliation     profile
   |                    |
   +----------+---------+
              |
           EDF-005
 per-factory typed broker
 + stable factory identity
 + multi-root substrate
              |
           EDF-006
 qualify/pin TUI stack
 + native input/persistence
 + multi-root mechanics
              |
           EDF-007
 production multi-factory
 host management TUI
          /       \
         v         v
     EDF-008     EDF-009
     kickoff     TUIsynth reference
         \         /
          +---+----+
              |
           EDF-010
      portability/recovery UX
              |
           EDF-011
 clean-host/WHPX/Windows
 Terminal qualification
              |
           EDF-012
       package/release gate
```

EDF-003 and EDF-004 may proceed in parallel after EDF-002 if they do not modify the same files. All other dependency edges are hard unless the current issue explicitly revises the graph through a reviewed programme change.

## Issue catalogue

| ID | GitHub | Title | Depends on | Primary outcome |
|---|---|---|---|---|
| EDF-001 | [#1](https://github.com/techrote/ezDarkFactory/issues/1) | Reconstruct and manifest the original development-VM baseline | — | Exact `b6abdf8` import/provenance plan, local-patch evidence matrix, honest local-TUIsynth cutoff |
| EDF-002 | [#2](https://github.com/techrote/ezDarkFactory/issues/2) | Establish ezDarkFactory core namespace, repository contract and CI | 001 | Buildable/testable fork with no generated historical state |
| EDF-003 | [#3](https://github.com/techrote/ezDarkFactory/issues/3) | Reconcile private-key ACL and QEMU process-lifetime amendments | 002 | Public regression-tested replacement for the two historical owner patch classes |
| EDF-004 | [#4](https://github.com/techrote/ezDarkFactory/issues/4) | Build the clean fresh-project guest profile | 002 | Empty general-purpose coding workspace and versioned READY contract |
| EDF-005 | [#5](https://github.com/techrote/ezDarkFactory/issues/5) | Add per-factory typed control, stable factory identity and multi-root manager substrate | 003, 004 | Safe versioned seam for one manager to observe/control multiple independent factory roots |
| EDF-006 | [#6](https://github.com/techrote/ezDarkFactory/issues/6) | Qualify and pin the host management TUI implementation stack | 003, 004, 005 | Evidence-backed framework/persistence/input/concurrency design for Windows Terminal and multi-root operation |
| EDF-007 | [#7](https://github.com/techrote/ezDarkFactory/issues/7) | Implement the tile-native multi-factory host management TUI | 006 | Production persistent tile manager with mouse/keyboard parity and safe multi-root operations |
| EDF-008 | [#8](https://github.com/techrote/ezDarkFactory/issues/8) | Deliver fresh-project kickoff helpers and human onboarding | 004, 005, 007 | One documented first-run/project workflow usable without TUIsynth knowledge |
| EDF-009 | [#9](https://github.com/techrote/ezDarkFactory/issues/9) | Seal TUIsynth as an isolated reference/demo | 001, 004, 007 | Authenticated, opt-in historical reference that cannot become active project state |
| EDF-010 | [#10](https://github.com/techrote/ezDarkFactory/issues/10) | Integrate portability, backup, clone/export and recovery UX | 003, 005, 007, 008 | Human-safe lifecycle/storage recovery through the host manager and helpers |
| EDF-011 | [#11](https://github.com/techrote/ezDarkFactory/issues/11) | Run clean-host, WHPX, physical Windows Terminal and usability qualification | 008, 009, 010 | Exact-source real-host evidence and remaining limitation ledger |
| EDF-012 | [#12](https://github.com/techrote/ezDarkFactory/issues/12) | Deterministic packaging, final end-to-end gate and v0.1 release | 011 | Release only from accepted exact source with truthful evidence matrix |

Stable EDF IDs never change when issue numbers do.

## Common issue completion contract

Every issue must:

- start from fresh current-state reconciliation;
- create/resume one dedicated issue branch;
- implement all in-scope behavior and machine-verifiable acceptance tests;
- update RAG/programme/operator docs when contracts change;
- run focused tests during development;
- run the current full merge gate before PR acceptance;
- perform a final diff/security/scope review;
- open a dedicated PR containing `Closes #<issue>`;
- monitor the exact-head automated checks and fix applicable failures;
- resolve blocking review findings;
- update/rebase against current main if required and rerun affected checks;
- merge only with required checks green and mergeability established;
- verify actual post-merge `main` and required checks;
- retain negative/failing evidence rather than rewriting history;
- distinguish unperformed physical/human gates from PASS.

The issue itself may define a physical gate. If so, it must actually run in an appropriate environment or finish with the exact explicit disposition allowed by that issue; automated evidence cannot impersonate it.

## Host manager contract

Implementation issues EDF-005 through EDF-011 must treat `docs/rag/03-HUMAN-CONTROL-SURFACE.md` as the authoritative UI/manager behavior contract.

In particular:

- one manager may register multiple local factory roots;
- a path is not stable factory identity;
- duplicate factory identities at multiple reachable paths hold mutations;
- root failure cannot block other root observations or the UI event loop;
- destructive operations are exact-target and root-scoped;
- v0.1 has no destructive cross-factory batch action;
- v0.1 guest interaction uses explicit external managed SSH/Windows Terminal attach rather than requiring an embedded PTY;
- GUI guest display/desktop is not a release dependency;
- Windows Terminal physical qualification is required for the primary TUI.

## Branch and PR convention

Preferred branch:

```text
edf-NNN-short-slug
```

Preferred commit/PR language includes the stable EDF ID.

Do not combine dependency-independent issues into one PR merely to reduce issue count.

## Scope control

The programme intentionally does **not** implement:

- continued TRIO/TUIsynth development;
- a generic autonomous agent/provider fleet dashboard;
- model/provider orchestration as a prerequisite for VM usefulness;
- bridged guest networking;
- live migration;
- arbitrary backing chains;
- silent paid inference;
- distribution of the historical authenticated lab image;
- remote-host management in v0.1;
- guest graphical desktop/display as a v0.1 management requirement;
- destructive bulk actions across multiple factories.

Those capabilities need later explicit programmes/spec deltas.

## Final product acceptance

EDF-012 may call v0.1 release-ready only when a clean compatible Windows host can, from checked-in instructions:

1. verify prerequisites;
2. bootstrap reviewed dependencies;
3. build/acquire clean prepared bases for the selected factory roots as needed;
4. launch the host management TUI;
5. register at least two local factory roots and identify their current state;
6. create a fresh project VM in the intended factory;
7. start to exact READY;
8. open the exact managed guest shell path;
9. observe logs/resources/errors without confusing roots;
10. stop and restart safely;
11. clone/export/recover according to documented semantics;
12. inspect/run TUIsynth only as a separate reference/demo;
13. reproduce the applicable automated, WHPX, Windows Terminal and human evidence at the exact candidate revision.

No historical success claim substitutes for this gate.
