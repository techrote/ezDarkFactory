---
document_id: EDF-LIFECYCLE
status: authority
---

# Lifecycle, storage and security contract

## Baseline

Start from the EzVM `b6abdf8...` lifecycle/storage/network model, then reconcile the two owner-local amendment classes through public regression-tested source.

Do not copy the historical runtime directory or authenticated VM overlay.

## Lifecycle truth

Durable intent, observed process identity, QMP state, readiness and guest interaction are separate facts.

A stored PID is never sufficient ownership proof. Where the inherited control plane records executable path, process start time, argv fingerprint, launch ID and instance marker, preserve that strength or improve it with tests.

Unknown or ambiguous identity fails closed.

## Start

A start operation:

1. validates durable instance/base/profile identity;
2. validates the complete backing chain;
3. allocates/binds management endpoints safely;
4. launches the reviewed QEMU executable;
5. publishes runtime ownership only according to the transaction contract;
6. proves QMP/process state;
7. proves authenticated SSH and current guest identity;
8. proves cloud-init/current-boot/profile readiness;
9. returns a bounded result while the VM remains independently alive.

The historical captured-output/start-pipe behavior is a specific regression target. A caller, UI, redirected stdout reader or broker must not accidentally own the long-lived QEMU stdout/stderr handles.

## Stop

Normal stop uses the accepted graceful guest/QMP path and waits for the intended owned process to exit.

A timeout does not silently become force kill. Force/abandon recovery, if later implemented, is a separate explicit operation with stricter evidence.

## Storage mutation

Reset, clone, export/import and any future disk growth require positive stopped ownership/reconciliation.

Do not modify a backing base. Do not copy a live overlay as a clean backup. Interrupted mutation preserves enough transaction evidence to diagnose/recover without guessing.

## Private key and ACL behavior

Controller SSH private state is generated runtime data. It must be accessible only to the intended current user under the supported Windows policy.

EDF-003 must test the historical standard-user DACL failure and the selected replacement behavior. Later EzVM fixes are evidence/candidate source, not inherited PASS.

No test may use a real user's key as a fixture.

## Network boundary

Default guest networking remains QEMU user-mode NAT.

- SSH: explicit `127.0.0.1` host forward.
- QMP: explicit `127.0.0.1`.
- Any GUI remote display protocol, if selected, must also default to a host-local transport and have explicit authentication/exposure policy where relevant.
- No TAP, bridge, Hyper-V virtual switch or LAN listener is introduced merely for GUI convenience.

Outbound guest Internet is allowed for ordinary development according to the documented guest policy; it is not equivalent to exposing inbound host services.

## Secrets

Never commit or package:

- controller private keys;
- vendor/provider API keys;
- authenticated agent config;
- private SSH identities;
- historical VM overlay state;
- raw private prompts/transcripts;
- cached model weights;
- browser/session cookies.

Stateful clone/export may contain credentials because it intentionally preserves guest state. The UI/docs must label it sensitive.

## Guest privilege

The historical coding profile uses a locked-password `coder` account, public-key SSH and passwordless sudo inside the disposable guest.

Preserving or changing that policy is an explicit guest-profile decision. Guest sudo does not grant Windows host administrator rights and does not authorize host filesystem access.

## GUI/Desktop security

A graphical guest profile must not weaken SSH/host trust boundaries merely for convenience.

Clipboard/shared-folder integration is disabled by default until separately specified and tested. Host filesystem sharing is not implied by a desktop.

A graphical console is a presentation channel, not permission to bypass identity/readiness checks.

## Patch-reconciliation rule

For `Keys.ps1` and `Runtime.ps1` classes:

1. capture the exact historical baseline behavior from `b6abdf8...`;
2. reproduce the documented failure with a safe fixture where feasible;
3. inspect later public EzVM repairs and tests;
4. port the smallest sufficient behavior into ezDarkFactory;
5. add negative controls proving the old failure;
6. run current exact-head tests;
7. preserve explicit physical-WHPX/non-admin evidence boundaries.

If an original owner-local patch is later recovered, hash and compare it. Do not overwrite current corrected code merely to match old bytes.

## Destructive operation authority

The UI/broker supplies typed identifiers and expected revision/generation. Guest text, project files and model output are untrusted data and never become host action arguments without typed validation.

A stale UI row cannot kill a newly reused PID or reset a replacement instance.
