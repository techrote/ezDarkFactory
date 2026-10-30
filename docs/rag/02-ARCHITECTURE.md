---
document_id: EDF-ARCH
status: authority
---

# Architecture

## Product boundary

ezDarkFactory is a clean development-VM factory, not a synth product and not an agent orchestration product.

The historical EzVM source provides the VM/storage/network/control-plane starting point. New work adds a fresh-project guest contract and a human-facing control surface.

## Layering

```text
Human operator
  |
  +--> primary human control surface
  |      - GUI if EDF-006 qualifies it
  |      - otherwise comprehensive TUI
  |
  +--> helper scripts / documented CLI
            |
            v
Typed local control broker / read model
            |
            v
Versioned PowerShell VM control plane
  |              |                |
  v              v                v
QEMU/WHPX     QCOW2 state      SSH + QMP
  |                               |
  +------------ guest ------------+
                   |
          clean project workspace

Optional isolated reference layer
  |
  +--> pinned original TUIsynth material
       (reference/demo only; never active project state)
```

The PowerShell lifecycle/storage layer remains authoritative. The broker and UI do not rewrite durable VM JSON, QCOW2 metadata, process evidence, trust files or backing-chain data directly.

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

Therefore GUI conversion is an explicit presentation/device-profile change. It must not be implemented by bypassing the lifecycle state machine or launching an unrelated QEMU command outside it.

## Three independent GUI questions

EDF-006 must not treat “GUI” as one binary choice.

### Host management GUI

A Windows application/window for VM inventory, create/start/stop, logs, resource status, diagnostics, clone/export and project kickoff.

It may be implemented only over the typed broker/control plane.

### QEMU graphical guest console

A QEMU display/input path for the selected guest instead of `-display none`. The feasibility work must discover the graphical backend(s) actually present in the pinned/reviewed Windows QEMU payload and test them rather than assuming a particular backend.

A visible console must have explicit ownership/lifetime semantics: closing a viewer must not corrupt storage or silently change durable VM intent.

### Full guest desktop

An optional guest profile that provides a lightweight graphical Linux desktop and the packages/services required to make a graphical QEMU console useful for ordinary human operation.

This is the heaviest option and is independently rejectable. A QEMU window is not evidence that a desktop profile is maintainable, and a desktop profile must not become mandatory merely because a display backend exists.

## Control broker

The human control surface uses one typed broker/read model. It must provide at least:

- immutable snapshot/read operations for host prerequisites, instances, lifecycle/process identity, resources, readiness, logs and diagnostics;
- typed mutations for create/start/stop/reset/clone/export/import and any later supported operation;
- expected target identity/revision on destructive actions;
- bounded operation progress/result records;
- explicit current/last-known/unknown states;
- one command owner per managed bundle to prevent duplicate UI actions;
- no side effect from opening a view or refreshing observations.

The broker may use a small local journal/read model if needed. Persistent broker state is generated runtime state and is never repository authority.

## VM/storage invariants

Preserve until an issue explicitly changes them with tests:

- Windows x86-64 primary host;
- repository-local verified QEMU;
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

## Guest separation

The active project workspace is `/home/coder/workspace` or a versioned successor documented by the guest contract. It starts empty except for generic kickoff metadata chosen by ezDarkFactory.

Reference material lives outside the active workspace, for example under a dedicated read-only/reference root. No reference repository branch, issue ledger, agent session, model configuration or task queue may become the active project automatically.

## Dependency direction

Allowed:

```text
UI -> broker -> control plane -> QEMU/storage/SSH/QMP
UI -> read model
guest profile -> baseline provisioning recipes
reference demo -> isolated guest/reference installation
```

Forbidden:

```text
UI -> direct QCOW2 mutation
UI -> direct instance.json rewrite
UI -> guessed PID kill
reference demo -> project workspace authority
guest output/model text -> host command authority
opening a view -> start/inference/network mutation
```

## Versioning

Control-plane JSON, broker records, guest-profile identity and UI capability descriptors are versioned. A new UI must negotiate actual supported capabilities rather than making buttons from assumed state.

Schema migrations retain preimages and fail closed. Unknown schema versions are not rewritten silently.
