# ezDarkFactory RAG authority

This file is the entry point for project contracts. Issues incorporate this file and the documents they list under **Read first**.

## Core documents

1. [Project charter](docs/rag/00-PROJECT-CHARTER.md) — product purpose, scope, non-goals and success criteria.
2. [Baseline provenance](docs/rag/01-BASELINE-PROVENANCE.md) — exact EzVM/TUIsynth historical boundary and source-import rules.
3. [Architecture](docs/rag/02-ARCHITECTURE.md) — control plane, broker, UI, VM/storage/network and reference-layer boundaries.
4. [Human control surface](docs/rag/03-HUMAN-CONTROL-SURFACE.md) — GUI feasibility gate and mandatory comprehensive TUI fallback.
5. [Lifecycle and security](docs/rag/04-LIFECYCLE-SECURITY.md) — VM ownership, storage, networking, destructive-action and secret contracts.
6. [Guest profile and reference demo](docs/rag/05-GUEST-REFERENCE.md) — clean project environment and isolated TUIsynth reference/demo behavior.
7. [Testing, CI and release](docs/rag/06-TESTING-CI-RELEASE.md) — merge gates, real-runtime lanes, human acceptance and packaging truthfulness.
8. [Plan review](docs/programme/PLAN-REVIEW.md) — initial plan, review findings and improved plan.
9. [Implementation programme](docs/programme/IMPLEMENTATION-PROGRAMME.md) — dependency graph and issue catalogue.
10. [Status ledger](docs/programme/STATUS.md) — compact implementation status; GitHub issue/PR state remains authoritative.

## Historical authority

Historical source is evidence, not current project authority.

- EzVM baseline: `techrote/ezvm@7b829f8352a9fa30c965e57386965767c5969e0d`.
- TUIsynth implemented reference: `techrote/tuisynth-codex@357215781ba0b82694e62dd4d7ba1c3697ac3159`.
- TUIsynth programme/local-workflow reference: `techrote/tuisynth@e7060f6788421029ea9a1cb7cbee86a994c5b4d5`.

Do not update those pins merely because upstream repositories move. A change requires an explicit provenance decision issue.

## Retrieval rule for autonomous work

An issue must list the minimum complete set of RAG material needed to execute it. Agents should read those files in order, then inspect only the code and tests relevant to the change. When a contract is changed, update the owning RAG file in the same PR and call out the change in the PR body.
