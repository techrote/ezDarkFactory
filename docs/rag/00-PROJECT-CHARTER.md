---
document_id: EDF-CHARTER
status: authority
---

# Project charter

## Mission

Create a portable, reproducible development-VM factory for **new projects** that a human can understand, start, monitor, control, reset, clone and recover without remembering a collection of low-level PowerShell commands.

The system inherits proven EzVM lifecycle/storage/security behavior from the pinned historical checkpoint, then adds a human-facing control surface and guided project kickoff.

## Product requirements

A finished release must provide:

- one-folder Windows-first setup with repository-local dependencies and verified acquisition;
- clean immutable base construction and disposable/stateful per-project instances;
- safe start/status/stop/reset/clone/export/import operations;
- a human control surface showing instance state, resources, logs, evidence and available actions;
- guided creation of a fresh project VM and empty project workspace;
- helper scripts for common setup, launch, attach, diagnostics, backup/export and recovery;
- readable operator documentation that assumes no prior TUIsynth knowledge;
- an isolated TUIsynth reference/demo area that is never the active project by default;
- deterministic automated checks plus explicit physical/human qualification where automation cannot prove the claim.

## GUI preference and fallback

The preferred experience is graphical **if** it can be delivered without turning the VM into an opaque, heavy or weakly tested appliance.

The programme therefore has a required feasibility gate. It tests host GUI management, interactive QEMU display and an optional desktop guest profile separately.

If the accepted GUI criteria are not met, the release must ship a comprehensive mouse/keyboard TUI with equivalent management and monitoring coverage. Script-only operation is not an acceptable fallback.

## Fresh-project contract

A newly created project instance:

- has a unique instance/project identity;
- starts from an immutable reviewed base;
- uses an empty writable project workspace;
- contains no TUIsynth branch, issue state, pending task, worker session, credential or cached provider state in that workspace;
- may expose the pinned TUIsynth demo/reference from a separate read-only/reference location;
- does not automatically start agents, inference engines or external providers;
- presents next-step instructions to the human.

Project templates may later add explicit opt-in stacks, but the default remains general-purpose.

## Non-goals

The initial programme does not:

- resume or finish TRIO-017;
- treat TUIsynth as the product workload;
- distribute the historical lab VM image;
- bundle user credentials or authenticated overlays;
- require Docker, WSL, Hyper-V virtual switches or bridged networking;
- silently use paid AI services;
- provide arbitrary nested QCOW2 backing chains;
- claim WHPX, GUI, Windows Terminal or human usability PASS from headless/TCG-only automation.

## Definition of product success

A clean compatible Windows machine can follow the README, acquire verified dependencies, build/acquire the reviewed base, create a new project instance, start it, reach READY, open the human control surface, launch/attach to the workspace, observe resources/logs, stop/restart safely, clone/export it and recover from a documented failure.

A second user should be able to complete that flow from documentation without project-specific helper knowledge.

The release record must bind all automated and manual evidence to exact source/runtime versions.
