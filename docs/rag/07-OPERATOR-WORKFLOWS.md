---
document_id: EDF-OPS
status: authority
---

# Human operator workflows and helper-script contract

## Design rule

A new operator should be able to succeed without remembering the historical EzVM/TUIsynth workflow.

Normal human operation begins in the **host management TUI**. Small scripts remain for first-run setup, direct recovery and automation-friendly operation.

One manager may control multiple explicitly registered local factory roots.

## Required helper surface

Final names may change during implementation, but the product must provide obvious equivalents to:

- **manager setup/doctor** — verify manager runtime/Windows Terminal prerequisites and an explicit portable manager workspace when one is used;
- **factory bootstrap** — obtain reviewed QEMU/extractor and pinned guest source for a selected factory;
- **factory build-base** — build/reuse the reviewed clean prepared base in the selected factory;
- **manager open** — launch the host management TUI;
- **factory register** — validate/register a local factory root without VM/storage mutation;
- **new-project** — create a fresh named instance/project in an explicitly selected factory;
- **start** — start and reach READY in the selected factory;
- **open-shell** — launch/present the exact managed SSH/external-terminal path;
- **stop** — graceful stop;
- **status/diagnose** — read-only status and bounded diagnostics;
- **backup/export** — explicit sensitive stateful export where requested;
- **fresh-clone** — clean project clone from immutable baseline;
- **recover** — guide/refuse based on lifecycle/transaction evidence; never guess.

Helpers call the authoritative per-factory control/broker path. They do not duplicate storage logic.

## First-run workflow

The README must support:

1. obtain/clone ezDarkFactory source/tooling;
2. open normal unelevated PowerShell;
3. verify host and manager prerequisites;
4. set up the pinned manager TUI runtime;
5. launch the host management TUI;
6. register an existing compatible factory root or create/bootstrap the first factory root;
7. run factory doctor and resolve explicit Windows prerequisites;
8. bootstrap verified VM dependencies for that factory;
9. acquire/build the clean guest base;
10. create a fresh project VM in the selected factory;
11. start to READY;
12. open the exact managed guest shell path;
13. verify the empty workspace;
14. optionally initialise/clone/copy a project;
15. stop cleanly.

The guide states disk/download estimates before large acquisition where practical.

A second local factory root can then be registered into the same manager without changing the first factory's authority.

## Everyday workflow

The operator:

1. opens the host manager;
2. sees all registered roots and freshness/error/conflict state;
3. selects the intended factory and project/instance;
4. observes current lifecycle/readiness/resource state;
5. starts it if stopped;
6. opens guest interaction;
7. works;
8. either leaves it running deliberately or stops it.

The TUI always makes factory identity and final VM state clear.

## Factory registration workflow

Registration is read-only with respect to factory VM/storage state.

The operator selects/enters a local root, reviews:

- stable factory ID;
- path;
- alias;
- product/control version;
- compatibility;
- duplicate identity/conflict warnings.

Only the manager registry is changed after confirmation.

Unregistering a root removes it from the manager registry. It never deletes the root.

## Fresh project kickoff

The project wizard/helper asks only for information needed now:

- target factory;
- project/instance name;
- resource profile or accepted default;
- optional source choice: empty / clone URL / local copy;
- optional later tool/agent setup.

It previews the exact target and action before mutation.

It does not ask for TUIsynth, provider or model details unless the human explicitly enters the relevant optional flow.

The default source is **empty workspace**.

## Guest interaction

The v0.1 manager does not require an embedded terminal emulator.

Open-shell uses the selected factory's typed attach descriptor and either:

- launches a separate qualified Windows Terminal/SSH session; or
- displays/copies the exact command when automatic launch is unavailable.

Logs remain read-only and never capture guest input.

## Reference/demo workflow

Reference material is available from a distinct **Reference/Demo** action.

The operator is shown:

- historical/source pin;
- whether the source is original public, recovered-local, or documentation-only;
- that it is not the active project;
- any runtime/device limitations.

Launching it cannot alter the current project workspace.

## Recovery workflow

On UNKNOWN/CONFLICT/ambiguous state:

1. suppress destructive storage actions for the affected target;
2. show exact factory/instance identity plus observed/persisted discrepancy;
3. run only bounded diagnostics;
4. show the checked-in recovery path;
5. preserve evidence until ownership is reconciled.

Do not instruct users to delete PID/runtime files as a generic fix.

Failure in one factory does not hide or disable safe operations for unrelated factories.

## Portability workflow

**Primary portability goal:** a specific ezDarkFactory can be moved to another compatible Windows computer by archiving its folder, transferring/extracting it, then running one or two checked-in setup/doctor/launch steps.

Before moving a factory bundle:

1. positively stop every VM in that factory;
2. run portability validation;
3. verify there are no unresolved external/absolute dependencies required for operation;
4. show which generated/runtime files and credentials/private keys will travel;
5. warn that a stateful working bundle is sensitive;
6. archive/copy the complete factory root;
7. transfer/extract at any supported path, including a different drive/root;
8. run the checked-in destination setup/doctor step to revalidate prerequisites and current-user ACLs;
9. open the factory directly by its new path, even if no previous manager registry/workspace exists;
10. preserve/detect the existing factory and instance identities;
11. start one selected VM and verify identity/READY.

The old source copy remains stopped while the same factory identity is in use elsewhere.

If the user wants both copies to become independently writable factories, use an explicit fork/rekey workflow before operating both.

Cross-factory manager workspace/layout/registry files are optional convenience state. They may be stored in a separate portable folder alongside the factories and can be copied too, but losing them must never make a factory unusable.

## Documentation set

By EDF-008/EDF-010 the repository contains:

- root README quick start;
- first-run guide;
- operator guide;
- host-manager controls/keymap reference;
- factory registration guide;
- guest/project guide;
- reference/demo guide;
- portability/backup guide;
- troubleshooting/recovery guide;
- security/credential notes;
- clean-host acceptance worksheet.

Commands in docs are exercised by tests where practical. Stale screenshots are never the only instruction source.

## Errors

Human-facing errors contain:

- operation;
- factory/target;
- actual failed stage;
- preserved state;
- safe next action.

Avoid raw stack traces as the only message, but retain detailed logs for diagnosis.

## No hidden automation

The factory may later host coding agents, but initial kickoff does not auto-create an agent fleet, scheduler, model service or provider account.

Human operation remains useful with no AI service configured.
