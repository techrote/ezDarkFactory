# ezDarkFactory RAG authority

This file is the entry point for project contracts. Issues incorporate this file and the documents they list under **Read first**.

## Core documents

1. [Project charter](docs/rag/00-PROJECT-CHARTER.md) — product purpose, scope, non-goals and success criteria.
2. [Baseline provenance](docs/rag/01-BASELINE-PROVENANCE.md) — original local-TUIsynth evidence boundary, EzVM reconstruction source and import rules.
3. [Architecture](docs/rag/02-ARCHITECTURE.md) — multi-factory host-manager layering, control plane, VM/storage/network and reference boundaries.
4. [Host management TUI specification](docs/rag/03-HUMAN-CONTROL-SURFACE.md) — authoritative project-specific tile-native UI/UX and implementation contract, pinned to specdocz.
5. [Lifecycle and security](docs/rag/04-LIFECYCLE-SECURITY.md) — VM ownership, storage, networking, destructive-action and secret contracts.
6. [Guest profile and reference demo](docs/rag/05-GUEST-REFERENCE.md) — clean project environment and isolated TUIsynth reference/demo behavior.
7. [Testing, CI and release](docs/rag/06-TESTING-CI-RELEASE.md) — merge gates, real-runtime lanes, human acceptance and packaging truthfulness.
8. [Operator workflows](docs/rag/07-OPERATOR-WORKFLOWS.md) — first run, project kickoff, helpers, recovery and portability UX.
9. [Plan review](docs/programme/PLAN-REVIEW.md) — initial plan, review findings and improved plan.
10. [Implementation programme](docs/programme/IMPLEMENTATION-PROGRAMME.md) — dependency graph and issue catalogue.
11. [Status ledger](docs/programme/STATUS.md) — compact implementation status; GitHub issue/PR state remains authoritative.

## UI specification precedence

The host-manager specification is the authoritative ezDarkFactory UI/UX and UI implementation contract, subject only to higher-priority project safety, lifecycle/storage/security, functional, compatibility, and repository requirements.

Issue bodies must conform to it unless the issue explicitly carries a reviewed specification amendment. Stale issue wording does not silently override the tailored specification.

Its shared baseline is pinned to:

`techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265`

Future specdocz changes have no automatic effect. They must be reviewed as explicit Adopt/Adapt/Reject/Extend deltas before this project specification is changed.

## Historical authority

Historical material is evidence, not current project authority.

- **Development-VM source:** `techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699`.
- **Development-VM local amendments:** owner-local `Keys.ps1` and `Runtime.ps1` patches recorded by the EzVM/TRIO field study. Their exact historical patch bytes are not assumed available; EDF-001 must reconcile them against surviving evidence and later upstream repairs.
- **Original TUIsynth remote programme source:** `techrote/tuisynth@e7060f6788421029ea9a1cb7cbee86a994c5b4d5`.
- **Original local synth stop evidence:** accepted local main `whole/TRIO-001..007`, plus a distinct later partial pause checkpoint. The exact local SHA is currently not established from connected public evidence.
- **Comparison repositories:** `techrote/tuisynth-codex` and `techrote/tuisynth-claude` are explicitly non-authoritative for reconstructing the original local-development cutoff.

Do not silently replace an unresolved historical identity with a comparison-fork commit. A later recovered local checkpoint may be added only through the provenance/reconstruction issue with hashes and an explicit authority decision.

## Retrieval rule for autonomous work

An issue must list the minimum complete set of RAG material needed to execute it. Agents should read those files in order, then inspect only the code and tests relevant to the change. When a contract is changed, update the owning RAG file in the same PR and call out the change in the PR body.
