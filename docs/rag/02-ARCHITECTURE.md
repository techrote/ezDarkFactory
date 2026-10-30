---
document_id: EDF-ARCH
status: authority
---

# Architecture

## Product boundary

ezDarkFactory is a clean development-VM factory, not a synth product and not an agent orchestration product.

The historical EzVM source provides the VM/storage/network/control-plane starting point. New work adds a fresh-project guest contract plus a host-side tile-native manager capable of operating multiple local factory roots from one interface.

## Layering

```text
Human operator
  |
  +--> host management TUI
  |      - multi-factory registry
  |      - semantic command layer
  |      - persistent tile workspace
  |      - observation/read model
  |      - root-scoped operation coordination
  |
  +--> helper scripts / documented CLI
            |
            v
Per-factory typed adapter/broker boundary
       /          |          \
      v           v           v
 Factory A    Factory B    Factory C
 control       control      control
 plane         plane        plane
   |             |            |
 QEMU/QCOW2/SSH/QMP per independent root
   |             |            |
 clean project workspaces per instance

Optional isolated reference material remains inside each relevant guest/profile
and never becomes manager authority or the default project.
```

The PowerShell lifecycle/storage layer inside each factory remains authoritative.

The host manager does not rewrite durable VM JSON, QCOW2 metadata, process evidence, trust files or backing-chain data directly.

## Factory identity

Every factory root must expose a stable factory identity through the accepted control/broker contract.

The manager keeps registration records containing factory ID, current path, alias and capability/version information.

A path is a locator, not stable identity.

Factory identity is opaque and stable. It is preserved by ordinary relocation/move. If an archived/copy of a factory is intentionally turned into a second independently writable factory, an explicit fork/rekey operation creates a new factory identity first.

If two reachable registered locations present the same identity, the manager holds mutations until the user resolves which copy/location is authoritative.

## Historical runtime seam

At EzVM `b6abdf8...`, `src/EzVm/Runtime.ps1` constructs QEMU with:

- explicit q35 machine;
- configured vCPU and RAM;
- `-display none`;
- serial and QEMU logs;
- localhost QMP;
- virtio block and network devices;
- user-mode networking and localhost-only SSH forwarding;
- `CreateNoWindow = $true` on the host process.

The v0.1 host manager preserves that headless guest-management seam.

A QEMU graphical console or guest desktop is not required for v0.1 human operation.

## Host management TUI

The primary UI architecture is defined by `docs/rag/03-HUMAN-CONTROL-SURFACE.md`.

The TUI runs on the Windows host and provides GUI-like tile/menu/pointer behavior without becoming the owner of VM state.

It is designed so a future native GUI may reuse semantic commands, root adapters and state models through an explicit spec/architecture delta.

## Per-factory control adapter

The host manager uses one versioned adapter per registered factory root.

Each adapter provides:

- stable factory identity;
- capability/version envelope;
- immutable observation/snapshot operations;
- typed mutations;
- bounded logs/diagnostics;
- operation/result reconciliation.

An unavailable/slow/malformed root affects only that root's observation state.

No root adapter may cause the UI event loop or unrelated factories to block.

## Control and operation ownership

The manager maintains:

- a portable factory registry/workspace when multi-root convenience is desired;
- UI/session state;
- bounded operation journal;
- per-root observation workers;
- root-scoped operation coordination.

No factory-critical state may exist only in a hidden machine-local application-data directory. A factory must remain directly openable and operable from its own transferred folder when the cross-factory manager workspace is absent.

The manager may run independent operations across different roots subject to a global budget.

Within a factory, the underlying control plane remains the lifecycle/storage lock authority.

Manager restart never blindly replays mutations. Pending operations are reconciled.

No permanent Windows service is required for v0.1.

## Portable bundle invariant

Each factory root is a self-contained portable unit.

Everything required to identify, configure, start, stop, diagnose, recover and continue that factory travels inside the factory folder, apart from host prerequisites that checked-in setup/doctor scripts can validate or reacquire.

Authoritative paths are root-relative where practical. Machine-specific absolute paths and transient process/QMP observations are treated as rebindable host state, not durable identity.

The intended relocation workflow is: stop → portability check → zip/archive one factory folder → transfer/extract → run setup/doctor → open/start.

A full stateful bundle may contain private keys and guest credentials and therefore must be treated as sensitive.

Cross-factory manager layout/registry state may live in a separate explicit portable manager-workspace folder, preferably alongside the factories. It is optional and reconstructible.

## VM/storage invariants

Preserve until an issue explicitly changes them with tests:

- Windows x86-64 primary host;
- repository-local verified QEMU per factory;
- normal WHPX acceleration with explicit TCG qualification lanes only where documented;
- pinned Ubuntu source and reviewed prepared-base build;
- one immutable managed base -> one mutable instance QCOW2 overlay;
- no arbitrary nested managed backing chains;
- process identity and lifecycle locks before storage mutation;
- localhost-only QMP;
- QEMU user-mode NAT;
- localhost-only SSH forwarding;
- clean stop before reset/clone/export/storage mutation;
- relocation-safe generated state.

## Guest interaction

Normal guest interaction remains the accepted SSH/control path.

The host manager may launch a separate Windows Terminal/SSH attach process using a typed descriptor from the selected factory.

The management TUI does not require an embedded PTY for v0.1.

Focusing a log/output view never forwards input to the guest.

## Guest separation

The active project workspace is `/home/coder/workspace` or a versioned successor documented by the guest contract. It starts empty except for generic kickoff metadata chosen by ezDarkFactory.

Reference material lives outside the active workspace. No reference repository branch, issue ledger, agent session, model configuration or task queue may become the active project automatically.

## Dependency direction

Allowed:

```text
TUI -> manager reducer/read model -> per-factory adapter -> factory control plane
TUI -> portable manager workspace registry/session/journal
factory control plane -> QEMU/storage/SSH/QMP
guest profile -> baseline provisioning recipes
reference demo -> isolated guest/reference installation
```

Forbidden:

```text
TUI -> direct QCOW2 mutation
TUI -> direct instance.json rewrite
TUI -> guessed PID kill
manager registry/workspace -> lifecycle authority
path string -> stable factory identity
reference demo -> project workspace authority
guest/log/model output -> host command authority
opening/registering a view/root -> start/inference/storage mutation
```

## Versioning

Control-plane JSON, factory identity/capability envelopes, manager registry/session/journal schemas, guest-profile identity and UI command metadata are versioned.

Unknown incompatible schemas fail closed or become read-only/incompatible observations rather than being silently rewritten.

Schema migrations retain preimages where persistent data is transformed.
