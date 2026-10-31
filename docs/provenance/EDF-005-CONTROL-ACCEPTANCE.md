# EDF-005 — Stable factory identity, typed control and multi-root substrate

> Acceptance custody record prepared 31 October 2026. **Post-merge fast gate is still pending** as of this draft revision. Do not interpret the merged PR itself as full acceptance until all nine actual-main fast jobs succeed.

## Exact-source and merge identity

- Issue: [EDF-005 #5](https://github.com/techrote/ezDarkFactory/issues/5).
- Implementation: [PR #25](https://github.com/techrote/ezDarkFactory/pull/25), branch `edf-005-multiroot-control`.
- Guarded reviewed PR head: `4a645c9d29cdc1b3e74d3747af9e820a51a444fd`.
- Accepted pre-merge `main`: `ea3e8e67d1d8e64d36b29de9c1cba5370dca397e`.
- Guarded squash-merge commit: `eb8b23d3f232be3d990a734b771fb8fc7ff68d06`.
- **Exact reviewed PR tree = exact actual merged-main tree:** `b41ec99303d8c72a9dd949553ff9b96dba35ecaf`. Actual merged commit has the accepted pre-merge main as its sole parent.
- Acceptance is bounded to accepted checked-in source and software CI. It is not a real QEMU/TCG/WHPX or physical Windows Terminal pass.

## Public compatibility and authority

- Root-owned, opaque, random `factory_id`: `runtime/factory-identity.json`, schema 1, API 1.0; explicit cold fork/rekey only. Moving/restoring a *stopped* folder preserves identity; two simultaneously reachable copies cause collision/refusal rather than silent identity change. Previous source/operation receipts and rekey preimage remain historical evidence.
- Stable opaque `instance_id` in `runtime/instances/<name>/control-instance.json`, schema 1. Generation remains the accepted EDF-004 `identityGeneration` and changes on reset. Legacy schema without a durable generation is refused rather than silently adopted.
- Closed/versioned control request/response envelopes carry API major/minor, capability IDs, exact factory and instance/generation, `operation_id`, expected revision, typed arguments, bounded progress/refusal. Unknown major is incompatible/read-only; negotiated minor features require advertised capabilities.
- Typed in-process and standalone `ezdarkfactory-control.ps1` paths delegate to the accepted existing VM lifecycle/storage/QMP/SSH/reset/clone/export/import implementations, not to manager-managed private-file edits.
- Optional portable manager workspace `registry.json`, schema 1, stores explicit enrollment, alias, canonical locator, last verified factory/API, and authorization. Candidate discovery inspects static data only and executes no unregistered code. Duplicate path/identity and stale/unavailable/incompatible roots fail closed.
- Root-worker `ezdarkfactory-worker.ps1` receives a bounded, private-ACL root-local submission and owns a separate PowerShell process. Dispatch response `dispatched` is not a fabricated accepted mutation. Reconciliation follows root-local submitted/accepted/completed/refused states, full request SHA-256, root lock and independent host-budget leases; no blind replay. The worker rechecks registered-fleet collisions immediately before effects, even after budget wait.
- `ezdarkfactory-attach.ps1` receives exact-argv identity/generation/revision-bound shell descriptor and rechecks accepted managed SSH trust/READY before any real shell; `-ProbeOnly` is an offline contract check, not a guest workload.
- Readiness distinguishes running process evidence from authenticated SSH READY. Logs have bounded seek-tail reads, sanitized control/credential-like text, explicit truncation/source size. Discover/select/read/refresh do not modify VM/runtime storage.

The public machine-readable schemas are `docs/schemas/factory-identity.v1.schema.json`, `instance-ref.v1.schema.json`, `control-request.v1.schema.json`, `control-response.v1.schema.json`, `manager-registry.v1.schema.json`, `manager-observation.v1.schema.json`, `operation-receipt.v1.schema.json`, `control-dispatch.v1.schema.json` and `shell-descriptor.v1.schema.json`. Semantic contract and invocation examples are in [the control API RAG](../rag/08-CONTROL-API.md).

## Historical import custody

Historical EDF-001/002/003/004 manifests and source claims were **not rewritten**. The single reviewed current imported-source replacement is the official direct CLI launcher `ezdarkfactory.ps1`, which coordinates identity-initialized mutations/cold portability with the root lock and pending-operation custody.

- Original accepted EDF-002 launcher Git blob: `46357444e46417539210c960157ed49ce2f283bf`.
- Reviewed EDF-005 active launcher Git blob: `48afc2a8ba1daf074d68103ef37f522776c20bd3`.
- Immutable before/after source mapping: `docs/provenance/edf005-control-supersessions.json`; `tests/test_edf002_import.py` requires original and current blob correctness, not historical backdating.

## Positive and negative software qualification

**Reviewed literal PR-head gate: 13/13 green.**

- [EDF fast nine-job gate #41162699515](https://github.com/techrote/ezDarkFactory/actions/runs/41162699515), exact source `4a645c9d29cdc1b3e74d3747af9e820a51a444fd`: Ubuntu/Windows historical provenance, repository boundary, native process both engines, full Windows PS5.1/pinned PS7.6.6, and real temporary standard-user ACL both engines. Each full control-plane suite ran **410 PASS / 0 FAIL / 0 SKIP**.
- [EDF-004 fresh-guest #41162699487](https://github.com/techrote/ezDarkFactory/actions/runs/41162699487): 2/2 PASS, no missing inherited guest/source/generation regression.
- [EDF-005 two-engine contract #41162699534](https://github.com/techrote/ezDarkFactory/actions/runs/41162699534): 2/2 PASS, **29/29 focused cases per engine**, zero failures/skips. Real Windows disposable roots and independent PowerShell child processes exercise identity persistence/fork, duplicate copy collision, malformed/incompatible roots, stale factory/instance revision/generation, typed invocation, denied unregistered execution, manager-root isolation, accepted-worker survival after manager exit, root lock/no-replay, late collision while waiting for host budget, ordinary-user private ACLs, Unicode paths, exact shell identity probe, safe transfer path refusal, bounded multi-MiB log and control-character sanitization.

**Retained negative evidence:** earlier candidate `2dde719c08aeedc12e7fe5d94fb4a0752c9fde0d` failed 3/410 full control-plane cases and 3/29 focused cases, caused by premature acceptance of `accepted` as terminal and OS lock lifetime during child cleanup. The corrective change `0bdf7f95f9af9f98093b6ebf50bb44596d9524e8` tests *terminal* receipts and actual worker process exit. Later PR head `4a645c9d29cdc1b3e74d3747af9e820a51a444fd` additionally rejects treating mere `RUNNING` as managed shell READY. Red logs have not been deleted/relabelled.

PR-head focused archive ZIP SHA-256: PS5 `d47d90fcce7d0a9c2dba709de8a2b811ab329ebfdf102e216091f6bb2fab1c3c`; PS7 `ce3d1c2f940bbc93fad442edde618fd5140a65502a8bd5bd5fc63aca47bbbbe9`. The focused run’s own JSON receipts include the checkout SHA/tree, source file SHA-256, PowerShell engine, case-level results and explicit QEMU/WHPX `UNMEASURED`.

## Post-merge verification — pending final fast gate

Actual merged-main push workflows have the same Git tree as the reviewed PR head:

- [Nine-job fast gate #41163205070](https://github.com/techrote/ezDarkFactory/actions/runs/41163205070): **PENDING final all-nine job conclusion at this draft revision**.
- [EDF-004 two-job fresh-guest #41163205147](https://github.com/techrote/ezDarkFactory/actions/runs/41163205147): **2/2 PASS**.
- [EDF-005 two-job identity/manager #41163205163](https://github.com/techrote/ezDarkFactory/actions/runs/41163205163): **2/2 PASS**, 29/29 cases per engine.

Post-merge focused archive SHA-256: PS5 `b3a435f62c9c7962a98ca19f12d8e3194e255b395554cc7c8696e26bf2014b63`; PS7 `833a1971d0027b8bdfe250433ff1232f3b20b6cc0b98ad67f4c3346da983187e`. EDF-004 post-merge archive SHA-256: PS5 `f1c6822592b8ae9227410e81c4e3fdc07930ad76376c14de1ef6ccfb024df047`; PS7 `0326b1421899f47deb593e7abd01e56f6ebc11db352f7fc2a9da26111e490f97`.

## Deliberately unmeasured and later milestones

No production TUI, remote transport, provider/agent orchestration, shared destructive batch API or physical WHPX acceptance was added. Real QEMU/TCG/WHPX, managed guest launch, physical Windows Terminal and human UX **remain UNMEASURED / HUMAN-PENDING** for the applicable future runtime/release gates. This acceptance does not claim a physical VM/workload PASS. Direct external module callers bypassing both accepted official launchers are outside the shared CLI/typed root-lock contract; future callers must use the public API.
