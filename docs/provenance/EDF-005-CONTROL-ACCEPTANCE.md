# EDF-005 — Stable factory identity and multi-root control acceptance

> **Accepted — SOURCE / FAST-CI, 31 October 2026.** The reviewed implementation and narrowly scoped post-merge repairs passed **all 13 required jobs on the exact repaired main commit**, with original negative evidence preserved. Physical QEMU/WHPX and Windows Terminal acceptance remain UNMEASURED.

## Accepted implementation, guarded repair and source identity

- Authority issue: [EDF-005 #5](https://github.com/techrote/ezDarkFactory/issues/5); review and implementation [PR #25](https://github.com/techrote/ezDarkFactory/pull/25).
- Original literal reviewed implementation head `4a645c9d29cdc1b3e74d3747af9e820a51a444fd`, guarded squash-merged as `eb8b23d3f232be3d990a734b771fb8fc7ff68d06` (parent `ea3e8e67d1d8e64d36b29de9c1cba5370dca397e`). Exact head/merged tree: `b41ec99303d8c72a9dd949553ff9b96dba35ecaf`.
- Actual original post-merge fast gate [#41163205070](https://github.com/techrote/ezDarkFactory/actions/runs/41163205070) was **8/9, FAIL**: real Windows PS7 standard-user child 409 PASS / 1 FAIL. This was not silently accepted; issue #5 was explicitly reopened.
- Follow-up [repair PR #26](https://github.com/techrote/ezDarkFactory/pull/26), exact reviewed head `e042daf772117cab9073324da31b4fd051bc0df8`, guarded squash-merged as `4c11596894f19870771a970475727a39941945b8` (parent `eb8b23d3f232be3d990a734b771fb8fc7ff68d06`). Both reviewed repair head and actual new `main` have byte-identical Git tree `8194d377d07ac6e23ceb7c22454662dc511df0b8`.
- **SOURCE / FAST-CI acceptance is established** for this exact repaired tree by the successful actual-main 13-job gate on first attempt. Real QEMU/TCG/WHPX and physical Windows Terminal have not been executed as part of this acceptance.

## Public typed control, identity and trust contracts

Versioned API 1.0 resides in `src/EzDarkFactory/{Control,Manager,Edf005.psm1}` with a standalone JSON PowerShell launcher `ezdarkfactory-control.ps1`. All VM storage, QMP, SSH, guest provisioning, reset, clone and portability mutations reuse the accepted per-factory authoritative implementation; the manager/TUI neither reads nor edits private VM state directly.

The factory-local `runtime/factory-identity.json` records an opaque random `factory_id` (schema 1). Ordinary stopped relocation/restore preserves identity. Two reachable copies carrying the same ID cause an explicit collision; independently writable copies require cold fork/rekey, preserving the original identity/preimage and operation evidence. Every instance has an explicit opaque `instance_id` (schema 1), with the accepted existing durable `identityGeneration`; display names never authorize mutation or silently migrate unsupported legacy state.

Strict version/capability negotiation and exact command/response envelopes carry factory ID, opaque instance/generation, expected revision, typed arguments, operation ID, request SHA-256, and bounded progress/refusal. Unsupported majors are incompatible/read-only, stale targets fail before effects, and duplicate operation IDs return authoritative existing results, not replay. Read/observation is not a mutation.

The optional, explicit user-selected portable manager workspace stores enrollment IDs, aliases, canonical paths, last-known identity/API and convenience state; each factory works independently without it. Static candidate discovery executes no candidate scripts; first enrollment must authorize executing the local root's control plane. Duplicate path, duplicate ID, unavailable/unknown/incompatible and stale observations fail closed. Root-scoped file locks, durable worker operations and bounded host-budget leases permit independent factories concurrently without cross-factory batch mutation.

Detached `ezdarkfactory-worker.ps1` is a root-owned child process; the manager's `dispatched` response does not falsely imply `accepted`. Factory-local submissions, accepted/terminal journals and refusal records are reconciled without blind replay, even after manager exit. Private Windows ACLs protect transient request state; the official legacy CLI shares the root lock and refuses overlapping unresolved work or false cold portability. Fleet identity collisions are checked again after the worker acquires host budget.

`ezdarkfactory-attach.ps1` exposes an explicit identity/revision/generation-bound managed SSH shell descriptor with exact argv. `READY` is determined by authenticated current-launch SSH evidence, not simply RUNNING. Offline attach probe tests identity but does not launch a VM. Guest/log text remains untrusted; log tail reads are bounded to 32,768 source bytes with control-character/secret sanitization and truncation metadata.

The nine public schema-v1 files live in `docs/schemas/`: `factory-identity`, `instance-ref`, `control-request`, `control-response`, `manager-registry`, `manager-observation`, `operation-receipt`, `control-dispatch` and `shell-descriptor`. See [the complete public API contract](../rag/08-CONTROL-API.md).

## Historical source custody

No historical EDF-001/002/003/004 provenance records were modified to make changed bytes appear original. The sole reviewed imported-file supersession is `ezdarkfactory.ps1`, explicitly source-mapped in `docs/provenance/edf005-control-supersessions.json` and authenticated by `tests/test_edf002_import.py`:

- EDF-002 accepted original Git blob: `46357444e46417539210c960157ed49ce2f283bf`.
- Active EDF-005 reviewed launcher Git blob: `48afc2a8ba1daf074d68103ef37f522776c20bd3`.

The bounded post-merge receipt-race repair touches only EDF-005 `Control.ps1`, `Edf005Control.Tests.ps1`, and `docs/rag/08-CONTROL-API.md`; no inherited lifecycle, ACL, provenance or guest profile source was superseded for the repair.

## Source-matched software qualification and original failures

Original implementation PR #25 passed 13/13 literal-head checks: [nine-job fast #41162699515](https://github.com/techrote/ezDarkFactory/actions/runs/41162699515), [EDF-004 two-job #41162699487](https://github.com/techrote/ezDarkFactory/actions/runs/41162699487), [EDF-005 two-job #41162699534](https://github.com/techrote/ezDarkFactory/actions/runs/41162699534). Both full control-plane engines ran 410 PASS / 0 FAIL / 0 SKIP; both EDF-005 focused engines 29/29.

**Negative controls retained exactly:** Actual main `eb8b23d3...` ordinary-user PS7 failure [ZIP 13028207549](https://github.com/techrote/ezDarkFactory/actions/runs/41163205070/artifacts/13028207549), SHA-256 `30ae74b30795980770d2baaf3b378232660b436a67e388e675884deebebb3aab`, found atomic terminal receipt FileShare read contention (409/410). Initial repair `4afc76bb...` PS5 ordinary-user failure [ZIP 13028815312](https://github.com/techrote/ezDarkFactory/actions/runs/41163706946/artifacts/13028815312), SHA-256 `2bebfde609e67a33c92cd8057242a70225ec502a41ebd9d6b9dceca95a9c700c`, found transient submission deletion between Test-Path and Open (410/411). An intermediate `dc19201f...` attempt failed PowerShell parsing in [CI #41164274975](https://github.com/techrote/ezDarkFactory/actions/runs/41164274975) and was repaired from the last parse-clean source; none of these red attempts is counted as PASS.

The qualified repair reads completed journals with bounded 1-MiB strict JSON, delete-compatible file share and at most twenty 25-ms IO acquisition retries, without re-running any operation. `operation.get` checks authoritative journal, terminal refusal, then transient pending submission and rereads a bounded five×15-ms snapshot if a file disappears; malformed visible records fail closed. New real process-boundary tests prove exclusive journal lock recovery and submitted → absent/unknown → exact completed custody without replay.

Reviewed repair PR-head [nine-job fast #41164366175](https://github.com/techrote/ezDarkFactory/actions/runs/41164366175), [EDF-004 two-job #41164366180](https://github.com/techrote/ezDarkFactory/actions/runs/41164366180), [EDF-005 two-job #41164366187](https://github.com/techrote/ezDarkFactory/actions/runs/41164366187) **all passed 13/13** at literal head `e042daf772117cab9073324da31b4fd051bc0df8`. Full suites executed 411 PASS / 0 FAIL / 0 SKIP per PowerShell engine, and focused EDF-005 31 PASS / 0 FAIL in each.

## Actual repaired-main verification — 13/13 PASS

Actual `main` source/tree `4c11596894f19870771a970475727a39941945b8` / `8194d377d07ac6e23ceb7c22454662dc511df0b8`, bit-identical to the reviewed repair PR tree. Mandatory main-push runs:
- [Nine-job fast #41164831843](https://github.com/techrote/ezDarkFactory/actions/runs/41164831843): **9/9 PASS, attempt 1**. Both complete control-plane suites ran 411/411 PASS with 0 FAIL, 0 SKIP on Windows PowerShell 5.1 and pinned PowerShell 7.6.6; both real disposable standard-user ACL lanes passed; native process/timeout and Ubuntu/Windows provenance authentication retained.
- [Two-job EDF-004 #41164831870](https://github.com/techrote/ezDarkFactory/actions/runs/41164831870): **2/2 PASS, attempt 1**. Inherited fresh-profile first-ready/generation regression preserved.
- [Two-job EDF-005 #41164831877](https://github.com/techrote/ezDarkFactory/actions/runs/41164831877): **2/2 PASS, attempt 1**; 31/31 focused cases per PowerShell engine, with genuine independent Windows process and filesystem fixtures. No QEMU/WHPX workload is claimed.


Repaired-main EDF-005 focused evidence ZIP SHA-256:
- PS5 `fc379c0a42cdd2fc94b267a382d42ecde8ff7c9ff59bd7e191c5b0842f202ef6`.
- PS7 `be1291ea86bfbcd0b24d56f05ba8f1adf2cb13f8fe2362b9919a3193d7bdc0bf`.

Repaired-main EDF-004 focused evidence ZIP SHA-256:
- PS5 `92a17a04f095db01dfb7a1a73600885a3c70e131ae25a2426324c41272b4653f`.
- PS7 `16a3d80e7d7a8927ac631490ef20df47aaaaaffbc371bcc16ae58379b278b892`.

Repaired-main EDF-003 native-process ZIP SHA-256:
- PS5 `b23e4a38de6ac67a4705e7c321a2bd00db3d2087747c3a1ac544cf2fbbbb0f16`.
- PS7 `1ea27b65882c95b0b9a2e3e07a8a8ed97dd0c915c9980e46a230bd214262d3f0`.

Repaired-main **real ordinary-user ACL** ZIP SHA-256:
- PS5 `8bea1f197baae3e3975bd46e872bb290576464c4db48894c03382cec02043f3a`.
- PS7 `5462df77af8be21cc1c8423d23425d21afcb953c783c54a57cd98b2412e4b93d`.

The independently fetched literal merged commit `4c11596894f19870771a970475727a39941945b8` has parent `eb8b23d3f232be3d990a734b771fb8fc7ff68d06` and tree `8194d377d07ac6e23ceb7c22454662dc511df0b8`, byte-identical to the reviewed repair PR head. All actual-main workflow `head_sha` values match this literal merged revision; all 13 conclusions are SUCCESS, with no reliance on reruns or skipped suites.

## Deliberate physical/manual limitations

No TUI, remote-host transport, guest desktop, provider/agent orchestration or destructive cross-factory batch API was implemented. Real QEMU/TCG/WHPX, physical guest launch, Windows Terminal presentation and human UX remain **UNMEASURED / HUMAN-PENDING**, to be addressed under later runtime/release gates. The accepted software substrate does not imply physical VM qualifications. A direct caller bypassing both official launchers remains outside the shared root lock; EDF-006 must use the public typed boundary and may not infer authority from paths or names.
