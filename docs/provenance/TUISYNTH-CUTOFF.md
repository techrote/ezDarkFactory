# Original TUIsynth programme and local-development cutoff

**EDF-001 evidence classes:** SOURCE for authenticated public Git objects;
historical field evidence for the published TRIO observations. This record makes
no claim of VM, model, WHPX, Windows Terminal, physical UI or human-usability
qualification. It does not resume the TUIsynth programme.

## Authenticated public programme

| Identity | Value |
|---|---|
| Original repository | `techrote/tuisynth` |
| Public programme commit | `e7060f6788421029ea9a1cb7cbee86a994c5b4d5` |
| Git tree | `0b5d96d1979ed150734ae95938395165bc40530a` |
| Commit timestamp (UTC) | `2026-10-14T20:14:29Z` |
| Subject | `[TRIO] Run programme locally with qualified Titan models (#20)` |

The [public commit](https://github.com/techrote/tuisynth/commit/e7060f6788421029ea9a1cb7cbee86a994c5b4d5)
was reverified on 30 October 2026 against a fresh Git clone and the live GitHub
Git-commit endpoint. Its commit/tree object identities and the selected programme
document blobs were checked from Git object bytes. Public `main` still pointed to
this pin at that audit; that observation is not a promise about later branch state.

The pinned [TRIO agent contract](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/AGENTS.md),
[local workflow](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/docs/rag/12-LOCAL-WORKFLOW-AND-MODELS.md)
and [implementation programme](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/docs/programme/IMPLEMENTATION-PROGRAMME.md)
deliberately place subsequent implementation, testing, local CI, review and squash
merges in local Git inside the development VM. Agents were not to push, open PRs,
call GitHub APIs or hold GitHub credentials. Transfer by Git bundle and any later
publication were separate human operations.

Consequently, public GitHub history is not a complete record of subsequent original
development. The [public status ledger at this pin](https://github.com/techrote/tuisynth/blob/e7060f6788421029ea9a1cb7cbee86a994c5b4d5/trio/docs/programme/STATUS.md)
has all 17 TRIO rows marked `todo`. It is the initial programme ledger, not the later
accepted local implementation state. Historical instructions and model/provider
settings in those documents are evidence only; EDF-001 does not execute or import
them into an active factory workspace.

## What the surviving field study establishes

The relevant [observations](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/research/TRIO-2026-10/observations.json)
and [evidence index](https://github.com/techrote/ezvm/blob/d692be6a79a0c6bd3c1d246ff74096bc523b23e1/docs/research/TRIO-2026-10/evidence-index.json)
were inspected at EzVM revision
`d692be6a79a0c6bd3c1d246ff74096bc523b23e1`.

- **TRIO-FR-02** reports that accepted local main ended at `whole001..007`.
  EDF records the same logical cutoff as `whole/TRIO-001..007`. The historical
  canonical checkout and a later partial pause checkpoint had different commits
  and roots; these identities must not be collapsed.
- **TRIO-FR-05** reports preservation of complete histories, 89 incoming provenance
  rows and 151 original report blobs during pause wrap-up. Those counts are
  published historical claims. EDF-001 has not inspected or recounted the
  unavailable original rows and blobs.
- **TRIO-FR-17** reports a reconciled pause handoff, component manifest, source
  hashes and ordered restart queue. The published observation does not expose the
  missing accepted or partial local Git identity.

| State | Established here | Exact Git commit | Exact Git tree |
|---|---|---|---|
| Original public programme | Authenticated public source pin | `e7060f6788421029ea9a1cb7cbee86a994c5b4d5` | `0b5d96d1979ed150734ae95938395165bc40530a` |
| Accepted local main | Reported logical cutoff `whole/TRIO-001..007` | Unresolved (`null`) | Unresolved (`null`) |
| Historical canonical checkout | Reported distinct checkout/root | Unresolved (`null`) | Unresolved (`null`) |
| Later partial pause checkpoint | Reported distinct checkpoint/root | Unresolved (`null`) | Unresolved (`null`) |

The public programme pin is not a substitute for an accepted or partial local
checkpoint. A partially implemented issue is not an accepted issue. No higher TRIO
issue number is inferred accepted from source found elsewhere.

## Local-only records and the remaining limitation

The public evidence index marks these records **local-only**:

| Record | Published description | Published SHA-256 |
|---|---|---|
| E01 | Operational pause handoff and remaining programme boundaries | `12b74df9c41489da555107d978932ce3dbb123c1ca7812b0b1319c43acd84452` |
| E04 | Component refs, source/test hashes and restart identity | `c035d14fd7ef486afef58eea01249515add5e694ef12c38472be8cec6c5bf26c` |
| E17 | Ordered restart queue, review gates and source identity | `957751743b62f61db3cce1ab75ad6bf3d9ed108715dab89ec602e657b7b4014e` |

These are published metadata about unavailable records. Their hashes are not
hashes of recovered local Git commits and do not reveal those records' contents.
No original local record or accepted/partial Git checkpoint was recovered during
EDF-001. The manifest therefore retains the unresolved identities rather than
inventing values or copying private evidence.

If original evidence is later supplied, its file hashes and exact Git commit/tree
must be authenticated before adding a supplemental provenance record. Recovery
would not make historical instructions current, authorize publication of private
content or authorize importing an authenticated lab overlay.

## Comparison and product boundaries

`techrote/tuisynth-codex` and `techrote/tuisynth-claude` are comparison work. They
were not used to reconstruct this cutoff and cannot supply missing original
authority, private patch bytes or proof that later TRIO issues were accepted.

TUIsynth is isolated historical/reference material in ezDarkFactory. EDF-001
establishes source provenance for a clean VM recipe; it does not continue
TUIsynth, populate the default project workspace, configure models/providers or
copy the historical lab VM. Future reference/demo work remains separate from the
factory's lifecycle, identity, configuration and portable runtime authority.
