# ezDarkFactory programme status

This is a compact navigation ledger. Current GitHub issue/PR state and exact `main` remain authoritative.

| ID | GitHub | Status | Branch/PR | Dependency note |
|---|---|---|---|---|
| EDF-001 | [#1](https://github.com/techrote/ezDarkFactory/issues/1) | done | [PR #13](https://github.com/techrote/ezDarkFactory/pull/13) | accepted `538c8243be4d121a8834bdce99137dd33c7b41df`; post-merge green |
| EDF-002 | [#2](https://github.com/techrote/ezDarkFactory/issues/2) | todo | | EDF-001 accepted; dependency-ready, not started |
| EDF-003 | [#3](https://github.com/techrote/ezDarkFactory/issues/3) | todo | | EDF-002 |
| EDF-004 | [#4](https://github.com/techrote/ezDarkFactory/issues/4) | todo | | EDF-002 |
| EDF-005 | [#5](https://github.com/techrote/ezDarkFactory/issues/5) | todo | | EDF-003 + EDF-004 |
| EDF-006 | [#6](https://github.com/techrote/ezDarkFactory/issues/6) | todo | | EDF-003 + EDF-004 + EDF-005 |
| EDF-007 | [#7](https://github.com/techrote/ezDarkFactory/issues/7) | todo | | EDF-006 |
| EDF-008 | [#8](https://github.com/techrote/ezDarkFactory/issues/8) | todo | | EDF-004 + EDF-005 + EDF-007 |
| EDF-009 | [#9](https://github.com/techrote/ezDarkFactory/issues/9) | todo | | EDF-001 + EDF-004 + EDF-007 |
| EDF-010 | [#10](https://github.com/techrote/ezDarkFactory/issues/10) | todo | | EDF-003 + EDF-005 + EDF-007 + EDF-008 |
| EDF-011 | [#11](https://github.com/techrote/ezDarkFactory/issues/11) | todo | | EDF-008 + EDF-009 + EDF-010 |
| EDF-012 | [#12](https://github.com/techrote/ezDarkFactory/issues/12) | todo | | EDF-011 |

Allowed status words: `todo`, `in-progress`, `blocked`, `review`, `done`.

An issue is `done` only after its PR is merged and post-merge `main` verification required by that issue succeeds.

## EDF-001 accepted handoff

On 30 October 2026, PR #13 merged as
`538c8243be4d121a8834bdce99137dd33c7b41df`, tree
`db1efa22b9d01fb5b6045d4dab56272b436efba1`. Actual main matched the reviewed
PR tree and passed the local gate plus both exact-main
[Linux and Windows CI jobs](https://github.com/techrote/ezDarkFactory/actions/runs/41089647014):
144 authenticated records, 36 tests, zero failures/skips in each lane.

The [durable acceptance record](https://github.com/techrote/ezDarkFactory/issues/1#issuecomment-6527802150)
names the provenance artifacts, unresolved original local TUIsynth SHA/tree and
private patch bytes, both candidate-repair dispositions, and the EDF-002 handoff.
Evidence is SOURCE / FAST-CI only. EDF-002 implementation has not begun.
