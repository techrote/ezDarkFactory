# Historical reconstruction evidence

EDF-001 reconstructs a **source recipe**, not the historical authenticated VM.
This companion records what the public evidence establishes and where it stops.
The audit is **SOURCE** evidence, including inspection of existing upstream
**FAST-CI** evidence. No EDF VM, WHPX, Windows Terminal, physical UI or human
usability qualification was performed.

Public GitHub status was last reconciled at **2026-10-30T16:11:14Z**. The dated
[audit snapshot](audit-2026-10-30.json) is historical evidence of that reconciliation;
future implementation must recheck live issue, PR and check state.

## Historical source and field-study pins

| Role | Exact commit | Exact tree |
|---|---|---|
| EzVM v0.1.0 reconstruction baseline | `b6abdf8c3edd61695db30894da991f275b39a699` | `78e5ce0db9c32972451add22d28c7d19983775ee` |
| Original TRIO field-study extraction | `d692be6a79a0c6bd3c1d246ff74096bc523b23e1` | `ab551beb502560fd065a8dfee1a9053bc3c17c00` |
| Later public dashboard programme | `20dfca35bdd2fc8eab0b5fc52ae1b612b14d0e5e` | `7bc9e11e83192911c2e58e29cf97ceba064cd2bd` |
| Later offline replay publication | `d5265c804d0d8494d8171482a85aca563b181e05` | `9416befc914dafcdefbc5c9bcc605b1ddd53e082` |

The [baseline commit](https://github.com/techrote/ezvm/commit/b6abdf8c3edd61695db30894da991f275b39a699)
is titled `EZVM-012: qualify and package ezvm v0.1.0 (#26)`, committed at
`2026-10-14T01:02:23+01:00`. Later repair or dashboard commits do not advance this
baseline.

The original
[VM/dashboard design](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/design/VM-AI-DASHBOARD.md)
identifies inspected local EzVM as `b6abdf8` with the owner's existing `Keys.ps1`
and `Runtime.ps1` patches, which were read and left untouched. This establishes
two amendment classes, not their private patch bytes. Its companion
[record/control contracts](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/design/VM-AI-DASHBOARD-CONTRACTS.md)
and [delivery design](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/design/VM-AI-DASHBOARD-DELIVERY.md)
are historical proposals. They do not override EDF's current architecture or
authorize resuming the TRIO programme.

The field study records an extraction time of
`2026-10-16T15:07:10.089132+00:00`. Both primary JSON records are byte-identical at
the original extraction, public programme, later replay revision and audited
EzVM main:

| Public record | Git blob | SHA-256 |
|---|---|---|
| [observations.json](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/research/TRIO-2026-10/observations.json) | `d2ef3057d8f68fd6eacd0bdc097fd89c4d4fdec5` | `f5a9fb7090e94bc3021eb61a8fec2f3016c5be41bfdf940889271fa3d70b3679` |
| [evidence-index.json](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/research/TRIO-2026-10/evidence-index.json) | `3438550d210633cf6375f98c9dbe596b0f3a6942` | `1a81f791456273bde8f99c8804fdfe4f1b4f64a4beaecb7b17844eb0accfb7a8` |

The [original README](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/research/TRIO-2026-10/README.md)
states that the coding programme is paused and distinguishes accepted TRIO-001
through TRIO-007 from the partial restart checkpoint. The
[later README](https://github.com/techrote/ezvm/blob/d5265c804d0d8494d8171482a85aca563b181e05/docs/research/TRIO-2026-10/README.md)
adds programme/replay links and bounded replay results; it does not establish a
new original local cutoff or disclose the missing local Git identities.

## Required field observations

All rows below summarize the original pinned observations. None is a newly
executed EDF test. The field study covers one Windows host and one project, and
the observations retain their own confidence and limitation labels.

| Record | What the published evidence establishes | Limitation preserved |
|---|---|---|
| TRIO-FR-02 | Accepted local main ended at `whole001..007`; the historical canonical checkout and later partial pause checkpoint were different commits and roots. | Logical acceptance is reported; exact local accepted/partial SHA and tree are not published. |
| TRIO-FR-05 | Pause wrap-up preserved full histories, 89 incoming provenance rows and 151 original report blobs after earlier integration loss. | This reports preservation; EDF-001 has not obtained or rehashed those original histories/reports. |
| TRIO-FR-14 | An earlier audit reported a captured start pipe held open by QEMU; field instructions retained a file-redirection workaround and protected the original start session. | Historical report, explicitly not rerun by the field extraction. The private Runtime patch bytes remain unavailable. |
| TRIO-FR-15 | Earlier onboarding encountered standard-user ACL, WHPX reboot, SSH-tool selection, CPU-feature and timeout problems; the field host used owner patches/workarounds. | Host-specific historical audit needing current triage. It does not establish the detailed private DACL implementation or the cause of every failure. |
| TRIO-FR-17 | Pause wrap-up reconciled a concise handoff, component manifest, source hashes and ordered restart queue while archiving contradictory chronological documents. | Their existence and purpose are reported; local-only source contents are not reconstructed. |
| TRIO-FR-19 | The mature environment accumulated providers, model runtimes, worktrees, evidence and operator scripts; recovery exports intentionally excluded credentials and whole databases. | Explicit design inference from recorded environment: the lab overlay is not automatically a clean distributable devbox. |

## Unavailable original records

The public evidence index describes 17 records as **local-only**, with hashes and
descriptions. No original local record became available during this audit. The
following hashes were verified as text in the public index; the unavailable
private bytes were **not** obtained or authenticated.

| ID | Published description | Published SHA-256 | Published bytes |
|---|---|---|---:|
| E01 | Operational pause handoff and remaining programme boundaries | `12b74df9c41489da555107d978932ce3dbb123c1ca7812b0b1319c43acd84452` | 7537 |
| E04 | Component refs, source/test hashes and restart identity | `c035d14fd7ef486afef58eea01249515add5e694ef12c38472be8cec6c5bf26c` | 25928 |
| E12 | Earlier standard-user Windows/WHPX EzVM audit; not rerun for this plan | `9769d449083aee797eb1d43848ca7ba321a53365e75f2c4c927fbbb3ec730ac6` | 11385 |
| E17 | Ordered restart queue, review gates and source identity | `957751743b62f61db3cce1ab75ad6bf3d9ed108715dab89ec602e657b7b4014e` | 7023 |

These references cannot establish unpublished source hashes, accepted commits,
private amendments or authenticated runtime state. If original records later
become available, verify their exact bytes and Git commit/tree identities before
adding supplemental provenance. Their historical actor lists and restart queues
remain evidence, not executable instructions.

## Truthful original TUIsynth cutoff

The [original public programme pin](https://github.com/techrote/tuisynth/commit/e7060f6788421029ea9a1cb7cbee86a994c5b4d5)
is `e7060f6788421029ea9a1cb7cbee86a994c5b4d5`, tree
`0b5d96d1979ed150734ae95938395165bc40530a`, committed at
`2026-10-14T21:14:29+01:00` with subject
`[TRIO] Run programme locally with qualified Titan models (#20)`.

Its [local workflow contract](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/docs/rag/12-LOCAL-WORKFLOW-AND-MODELS.md)
and [TRIO agent contract](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/AGENTS.md)
deliberately place subsequent cloning, branching, tests, CI, reviews and merges
inside local Git in the development VM. They prohibit agent pushes/GitHub
credentials and reserve any later publication for a separate human action.
Therefore later public GitHub history is not a complete original development
record.

| Boundary | Recorded disposition |
|---|---|
| Public original programme source | Exact public pin above, authenticated independently of local continuation. |
| Subsequent original implementation | Local Git by design. |
| Accepted local main | Reported logical cutoff `whole/TRIO-001..007`; the field observation writes `whole001..007`. |
| Partial pause checkpoint | Reported to exist separately from accepted main and the historical canonical checkout. |
| Exact accepted local Git SHA/tree | **Unresolved**; no authenticated original local checkpoint recovered. |
| Exact partial local Git SHA/tree | **Unresolved**; no authenticated original local checkpoint recovered. |
| Comparison repositories | `techrote/tuisynth-codex` and `techrote/tuisynth-claude` are non-authoritative for original reconstruction and were not substituted. |

A later TRIO issue number or implementation in a comparison repository does not
prove acceptance in the original local programme. No TUIsynth implementation is
admitted as the active EDF workload by this record.

## Consequences for the portable factory

The source import is the material needed to rebuild a clean VM environment.
The historical overlay, runtime directories, controller keys, authenticated
provider/agent state, credentials, model caches, raw local evidence and operator
machine paths are excluded.

EDF's current contracts govern future adaptation: a working factory is a
self-contained portable folder, ordinary relocation preserves identity, and an
independently writable duplicate requires explicit fork/rekey. Required identity,
configuration, recovery, keys and VM state cannot depend solely on hidden
machine-local application data. Generated state may belong in a future working
factory while remaining excluded from source Git and public release artifacts.

The primary future UI is the host-side multi-factory Windows Terminal TUI.
Historical dashboard proposals do not authorize its implementation in EDF-001.
TUIsynth remains isolated historical reference/demo material. The
[local-amendment matrix](LOCAL-AMENDMENTS.md) keeps later public repair candidates
separate from the historical source baseline.
