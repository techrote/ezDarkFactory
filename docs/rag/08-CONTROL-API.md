# EDF-005 factory identity, typed control and portable manager API

Status: EDF-005 candidate; acceptance requires exact-head and post-merge CI. This document defines the public non-UI seam for EDF-006/007.

## State and authority

A factory's authoritative identity lives at runtime/factory-identity.json (schema 1); it is **not** the checkout path, machine name, enrollment ID, or a generated UI registry entry. New roots initialize explicitly:

    .\ezdarkfactory-control.ps1 -InitializeFactory

The command creates a random fct_<32 lowercase hex> identifier. It refuses malformed existing identity documents, unsafe links, ambiguous lifecycle/storage ownership, or incomplete state. Ordinary stopped relocation/archive retains identity. Copying a still-reachable root produces an identity collision; the portable manager marks both registrations CONFLICT and disables dispatch. Explicit factory.rekey, requiring the current identity and revision, a cold factory, no unresolved lifecycle journals and no accepted/ambiguous control operations, creates an independent identity. Previously completed/refused operation receipts remain immutable historical records of the pre-fork factory. A preimage is retained at runtime/control/rekey-<operation_id>.json. If rekey is interrupted, retain the preimage and accepted receipt for manual reconciliation: no silent replay/repair. Historical operation records remain as historical identity evidence rather than being rewritten to claim new provenance.

Older roots without the identity document are not implicitly adopted. Existing EDF-004 schema-2 instance intents have a durable identityGeneration but no stable instance ID. A one-time explicit instance.adopt under cold ownership adds runtime/instances/<name>/control-instance.json (schema 1, random ins_<32 lowercase hex>). Schema-1 intent without a durable generation is not silently migrated. The instance ID persists across a normal reset; the generation is the existing intent identityGeneration, and reset changes it. A composite (factory_id, instance_id, instance_generation) is required for all instance mutations and typed detail requests. Names are display metadata and must agree if supplied.

Manager workspace is optional. It contains only portable convenience files, starting with registry.json (schema 1). No hidden %LOCALAPPDATA%, registry-only or hostname-derived authority is used.

## Control entry points and compatibility

The PowerShell 5.1-compatible public entry is ezdarkfactory-control.ps1. Use -RequestFile <path> or -RequestJson <JSON>; do not use both. Both produce one JSON result object on stdout with a meaningful exit code (0 on completed, 2 on refusal or accepted/ambiguous). A request must be <=64 KiB. The standalone legacy ezdarkfactory.ps1 continues to work without the manager/TUI; the typed interface is the **only** supported route for future manager-originated mutations.

The module functions are Initialize-EzDarkFactoryIdentity, Get-EzDarkFactoryIdentity, Get-EzDarkFactoryControlCapabilities, Get-EzDarkFactoryControlRevision, Get-EzDarkFactoryInstanceRef, Get-EzDarkFactoryControlOperation and Invoke-EzDarkFactoryControl. For manager clients: Initialize-EzDarkFactoryManagerWorkspace, Get-EzDarkFactoryManagerRegistry, Get-EzDarkFactoryCandidate, Register-EzDarkFactoryManagerRoot, Unregister-EzDarkFactoryManagerRoot, Get-EzDarkFactoryManagerObservations and Invoke-EzDarkFactoryManagerControl.

Control API major/minor is 1.0; serialized schemas are 1. Unknown major or newer unsupported minor are refused; clients must negotiate the capability strings advertised by factory.info rather than guessing. The static root manifest has no executable discovery requirement. An incompatible or malformed root is read-only, not converted.

A complete typed request shape:

    {
      "schemaVersion": 1,
      "api": { "major": 1, "minor": 0 },
      "factory_id": "fct_<32-lowercase-hex>",
      "operation_id": "<32-lowercase-hex>",
      "command": "factory.info",
      "capabilities": ["factory.info"],
      "expected_revision": "<latest factory revision hash>",
      "instance_id": "",
      "instance_generation": "",
      "arguments": {}
    }

For reads, operation_id is a correlation ID; reads do not create journals. For mutations, pass the latest expected_revision from factory.info. For instance-scoped commands, the target must match the exact existing stable instance_id and current instance_generation (the name may additionally be supplied as an exact-match hint). Missing adoption is refused. Always obtain fresh observations before a user confirmation. An unsupported API version, unadvertised command/capability, stale factory ID, revision, target ID, or generation refuses before any operation journal or domain mutation. Existing per-factory lifecycle/storage/QMP/SSH functions execute effects; the manager does not rewrite private state.

Typed command families:

- Factory: factory.info, factory.doctor, factory.portability, factory.rekey.
- Observation: instance.list, instance.get, instance.resources, instance.readiness, instance.diagnose, instance.logs (serial or qemu, 1–8192 characters), instance.shell_descriptor (managed SSH attach descriptor; no shell execution).
- State: instance.adopt, instance.create, instance.start, instance.stop, instance.reset, instance.clone (explicit fresh/stateful), instance.import, instance.export, instance.exec (bounded argv), instance.copy_to and instance.copy_from.
- Recovery: operation.get by arguments.operation_id.

Request argument fields are exact (unknown fields refused). All mutations write a root-local durable operation receipt at runtime/control/operations/<operation_id>.json. States: accepted, completed, refused; responses and journals include bounded typed progress (stage and terminal status), and the journal authenticates the full original request with a SHA-256 fingerprint. A previous operation ID is never blindly replayed: a completed result is returned, and an accepted/pending record remains ambiguous until explicitly reconciled. Results include the factory ID, command, operation ID, optional instance ID and generation, typed data, and bounded diagnostic/refusal.

A root-scoped file lock serializes typed mutations inside that root, while independent roots may execute in parallel. A portable manager host-budget lease limits simultaneously active dispatches (default 2, allowed 1–8). Root identity/revision is rechecked after the budget lease is obtained. Existing per-instance lifecycle and storage safeguards remain authoritative.

## Discovery and manager registration

    $ws = 'D:\portable-edf-manager'
    Initialize-EzDarkFactoryManagerWorkspace -Workspace $ws
    Get-EzDarkFactoryCandidate -Root 'D:\factories\alpha'
    Register-EzDarkFactoryManagerRoot -Workspace $ws -Root 'D:\factories\alpha' -Alias 'Alpha' -AuthorizeLocalExecution
    Get-EzDarkFactoryManagerObservations -Workspace $ws

Static candidate inspection never dot-sources or runs candidate scripts; enrollment explicitly authorizes local execution as the current user for any future root-specific adapter. The current module adapter uses the enrolled manager's accepted code and root-local paths, not candidate executable code. The portable registry stores enrollment ID, alias, canonical path, last identity/API, authorization, and timestamps. Unregister only removes a registration. A relocated/unavailable, incompatible, or conflicting root never receives manager mutations. Duplicate canonical path cannot be enrolled twice. Re-enroll after an explicit rekey or relocation rather than automatically rebinding a stale path.

Observations follow `docs/schemas/manager-observation.v1.schema.json`: schemaVersion, enrollment, verified and last-known identity/version/time, static-root state, reason, timestamp, `inventory_state=unknown` and `last_known.freshness=stale`. Static-root states distinguish current, incompatible, unreachable and conflict; the schema additionally defines stale and unknown for future observation adapters. Live factory-root identity verification does **not** imply live VM inventory or readiness. On every static refresh, the last persisted registration metadata remains last-known/stale until an explicit update; no runtime mutation occurs.

## Safety and limitations

The typed layer uses fresh factory and instance references, checks the current root revision under an exclusive root-scoped lock, and delegates effects to accepted lifecycle operations. It does not execute scripts from discovered roots, open a TUI, silently repair interrupted legacy state, or bulk-mutate factories. Logging and diagnosis must not be interpreted as authority; untrusted control characters are sanitized.

The reviewed EDF-005 supersession of the official `ezdarkfactory.ps1` launcher shares the typed root lock for CLI mutations on identity-initialized roots. Legacy uninitialized roots and pure CLI reads retain original behavior. Direct imports of the accepted historical module (bypassing the launcher) remain outside this lock; typed dispatch also rejects stale durable runtime revisions and stale instance generations. Full external-module-caller atomicity remains an explicit limitation. In-process manager dispatch completes synchronously and must run on EDF-006's worker scheduler, never the UI render loop. There is no detached per-root command runner in this initial implementation; if the process dies mid-mutation, an accepted record persists and **must not be automatically replayed**. A permanently held manager session lock, manager session/layout persistence and full observation scheduling belong to EDF-006. Real QEMU, WHPX and human Windows Terminal use are unmeasured here.

The new JSON schema source is docs/schemas/*.v1.schema.json. No stored EDF-001–004 source provenance is rewritten. The sole reviewed imported-source supersession is authenticated with historical and current Git blobs in `docs/provenance/edf005-control-supersessions.json` and independently checked by `tests/test_edf002_import.py`.

## Qualification

Run the inherited full Windows PowerShell test harness on 5.1 and pinned 7.6.6, plus:

    .\scripts\Invoke-Edf005Qualification.ps1 -ExpectedMajor 5 -OutputDirectory $env:TEMP\edf005-proof

The focused source-matched receipts include at least nineteen mandatory cases across real disposable filesystem roots, child-process parallel independent roots, duplicate-operation races, negative controls, identity collision/rekey, manager registration isolation and stale requests. These are real filesystem/software tests, **not** real QEMU or physical WHPX/TUI proof.
