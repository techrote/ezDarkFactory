---
document_id: EDF-CHARTER
status: authority
---

# Project charter

## Mission

Create a portable, reproducible development-VM factory for **new projects** that a human can understand, start, monitor, control, reset, clone and recover without remembering a collection of low-level PowerShell commands.

The system inherits proven EzVM lifecycle/storage/security behavior from the pinned historical checkpoint, then adds a host-side tile-native management TUI and guided project kickoff.

## Product requirements

A finished release must provide:

- one-folder Windows-first factory setup with repository-local VM dependencies and verified acquisition;
- a self-contained working-factory portability model: stop → portability check → zip/copy one factory folder → transfer/extract → setup/doctor → run from the new path;
- no critical factory configuration, identity, recovery, key, or VM state stored only in hidden machine-local application data;
- clean immutable base construction and disposable/stateful per-project instances;
- safe start/status/stop/reset/clone/export/import operations;
- one host-side management TUI capable of registering and observing multiple local ezDarkFactory roots;
- a persistent tile workspace with mouse/keyboard command parity;
- explicit per-factory and per-instance identity so cross-root actions cannot target the wrong factory;
- human-visible instance state, resources, logs, evidence and available/refused actions;
- guided creation of a fresh project VM and empty project workspace;
- helper scripts for common setup, launch, attach, diagnostics, backup/export and recovery;
- readable operator documentation that assumes no prior TUIsynth knowledge;
- an isolated TUIsynth reference/demo area that is never the active project by default;
- deterministic automated checks plus explicit physical Windows Terminal/WHPX/human qualification where automation cannot prove the claim.

## Primary human interface

The v0.1 primary interface is the **host-side tile-native management TUI** defined by `docs/rag/03-HUMAN-CONTROL-SURFACE.md`.

It is GUI-like in interaction model: tiles, menus, pointer controls, overlays, direct manipulation, persistent layout, command palette and semantic commands.

It MUST remain usable without a graphical guest desktop or QEMU display window.

The underlying CLI/helper path remains a first-class recovery/automation route.

A future native GUI or remote-host manager may reuse the semantic layer only through an explicit project/spec delta.

## Fresh-project contract

A newly created project instance:

- has a unique instance/project identity within an explicitly identified factory root;
- starts from an immutable reviewed base;
- uses an empty writable project workspace;
- contains no TUIsynth branch, issue state, pending task, worker session, credential or cached provider state in that workspace;
- may expose the pinned TUIsynth demo/reference from a separate read-only/reference location;
- does not automatically start agents, inference engines or external providers;
- presents next-step instructions to the human.

Project templates may later add explicit opt-in stacks, but the default remains general-purpose.

## Multi-factory contract

The manager may register multiple local factory roots on one Windows host.

Registration is read-only with respect to VM/storage state.

Each factory root remains independently authoritative for its own instances, lifecycle locks, images, keys, configuration, recovery evidence and operation semantics.

A working factory is self-describing and directly operable from its own folder even if the cross-factory manager registry/workspace is missing.

Cross-factory manager layout/registry state is optional portable convenience state and should live in an explicit folder alongside the managed factories rather than being required under a hidden user-profile path.

If two reachable roots claim the same stable factory identity, the manager must hold mutations until the collision/relocation is explicitly reconciled.

V0.1 does not require remote-host management or destructive multi-factory batch actions.

## Non-goals

The initial programme does not:

- resume or finish TRIO-017;
- treat TUIsynth as the product workload;
- distribute the historical lab VM image;
- bundle user credentials or authenticated overlays;
- require Docker, WSL, Hyper-V virtual switches or bridged networking;
- silently use paid AI services;
- provide arbitrary nested QCOW2 backing chains;
- require QEMU graphical display or a guest desktop;
- provide remote-host factory management;
- provide bulk destructive operations across registered factories;
- claim WHPX, Windows Terminal or human usability PASS from headless/TCG-only automation.

## Definition of product success

A clean compatible Windows machine can follow the README, acquire verified dependencies, build/acquire a reviewed factory base, launch the host management TUI, register more than one local factory root, create a new project instance in the intended factory, start it, reach READY, open/attach to the workspace, observe resources/logs, stop/restart safely, clone/export it and recover from a documented failure.

A stopped working factory can then be zipped/copied as one folder to another compatible Windows machine/path, opened without the old manager registry, revalidated with the checked-in setup/doctor path, and started to the same factory/instance identity.

A second user should be able to complete that flow from documentation without project-specific helper knowledge.

The release record must bind all automated and manual evidence to exact source/runtime versions.
