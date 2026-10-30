# EDF-004 — clean fresh-project guest profile

## Scope and authority

EDF-004 creates the first **EDF-owned default guest provisioning identity**:
`fresh-project/v1`. It is derived from the useful general coding contract at
historical EzVM `b6abdf8c3edd61695db30894da991f275b39a699`, but it is
not a silent rewrite of the inherited `coding-default/v1` profile. Existing
durable `coding-default` intents remain readable; new managed instances select
`fresh-project/v1`.

The machine-readable [source map](edf004-fresh-profile.json) preserves the exact
historical Git blob/SHA-256, accepted EDF-002 destination blob and current
EDF-004 destination blob for the adapted Profiles/Registry/test source and both
new profile files. Historical source identity remains immutable.

## Fresh first-READY contract

The new profile preserves the stable general-purpose tool set, normal
`coder` account, locked passwords, public-key-only SSH, root-login refusal,
passwordless guest sudo and `/home/coder/workspace`.

Before the **first** READY marker for each durable guest `identityGeneration`,
the profile requires:

- workspace exists with exact coder ownership/mode and contains zero entries;
- no TUIsynth/TRIO-named home state;
- no reviewed provider/model credential locations (OpenCode/OpenAI/Anthropic,
  GitHub CLI credential file, Hugging Face/LM Studio/Ollama, AWS/Azure/GCloud,
  netrc/npmrc);
- no coder user systemd/autostart or crontab;
- no known TUIsynth/TRIO/agent/model system service names;
- all required development commands execute as `coder`;
- locked coder/root passwords, noninteractive guest sudo and effective
  public-key-only SSH policy;
- a real temporary Python venv/pip functional check.

The generated READY document remains exact identity + `provisioningState:
"complete"`; therefore its `provisioningProfile=fresh-project`, version,
source digest, base identity and generated cloud identity are authenticated by
the existing host parser. The cloud identity includes durable
`identityGeneration`, so reset/fresh clone cannot reuse a stale READY marker.

A matching same-generation READY marker permits idempotent re-provisioning after
the user has created project files. The marker is first removed and all live
tool/account/SSH/workspace-write checks run again. A missing/different marker
does **not** bypass the empty-workspace first-READY requirement. Validation
never recursively deletes or rewrites project content.

Provisioning identity follows the validated immutable base. Schema-1 clean
prepared bases select `fresh-project/v1`; schema-2 derived/imported sensitive
bases select retained `coding-default/v1`, even when explicitly selected or
used by a “fresh clone.” Stateful clone/import produce schema-2 bases. This
prevents a preserved workspace from being silently described as a freshly empty
project.

## Base hygiene and extension seam

Prepared-base construction remains unchanged and continues to remove SSH host
keys, all guest authorized_keys, cloud seed/log/machine identity before
publication. No controller private key enters base/profile source.

Optional future profiles must use a new name/version. Desktop may be added only
after the EDF-006 stack decision; optional developer stacks must retain
identity/readiness/security; TUIsynth/reference content remains isolated,
source-pinned and outside the active workspace.

## Evidence boundary

EDF-004 adds focused PS5.1 and pinned PS7.6.6 FAST-CI lanes that exercise
profile source, managed default selection, seed identity, fresh refusal
semantics, base hygiene, reset/fresh-clone generation and stale READY refusal.
The existing full EDF merge gate remains required.

These tests do **not** execute a real QEMU guest. Under the current test
contract real supported-host runtime is an EDF-011 qualification class.
No TCG/WHPX/physical Windows Terminal/human PASS is claimed here.

## Final EDF-004 acceptance receipt

EDF-004 was guarded-squash merged by [PR #23](https://github.com/techrote/ezDarkFactory/pull/23)
as `a983c957fb65acfd781ac131733512658b3e9927` (tree
`b9bdfeb9c1760f0d8bea0028dafae71104fa92a6`), matching reviewed
head `a4fa6f5f6a27f570340a966a9c10bfe6e23fece2`.

All **11** literal PR-head checks passed:
[base/native/ACL nine-job run](https://github.com/techrote/ezDarkFactory/actions/runs/41136392760)
and [focused EDF-004 two-job run](https://github.com/techrote/ezDarkFactory/actions/runs/41136392863).
All **11** actual merged-main checks passed on attempt 1:
[nine-job run](https://github.com/techrote/ezDarkFactory/actions/runs/41137100823)
and [focused guest run](https://github.com/techrote/ezDarkFactory/actions/runs/41137100701).
The full PowerShell 5.1 and pinned PS7.6.6 suites each passed
**381/381 (0 FAIL / 0 SKIP)**. Both EDF-004 focused profile suites
passed **8/8**, with source-matched JSON receipts.
Original focused PR-head archives: PowerShell 5
[artifact #13015928335](https://github.com/techrote/ezDarkFactory/actions/runs/41136392863/artifacts/13015928335),
ZIP SHA-256 `9d039d1b1328d11f9a85ea51cbcd5316418abd8a48ddd5c7335485acb18ebf1a`;
PowerShell 7
[artifact #13016797242](https://github.com/techrote/ezDarkFactory/actions/runs/41136392863/artifacts/13016797242),
ZIP SHA-256 `cef52f900a13a67efbea3db7a49a4b60e8cba47b47c514c54af9a34886093361`.

This is a **SOURCE / FAST-CI** profile/readiness contract acceptance,
not an actual QEMU guest execution. Both focused receipts state
`realGuestExecuted=false` / `EDF-004-REAL-GUEST: UNMEASURED`.
The later EDF-011 real runtime, WHPX and physical/human gates remain
outstanding. [Issue #4's durable handoff](https://github.com/techrote/ezDarkFactory/issues/4)
is authoritative for its acceptance history. EDF-005 is now dependency-ready.
