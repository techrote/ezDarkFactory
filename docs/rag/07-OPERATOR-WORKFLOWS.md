---
document_id: EDF-OPS
status: authority
---

# Human operator workflows and helper-script contract

## Design rule

A new operator should be able to succeed from the repository root without remembering the historical EzVM/TUIsynth workflow.

The selected primary UI handles normal use. Small scripts remain for first-run setup, direct recovery and automation-friendly operation.

## Required helper surface

Final names may change during implementation, but the product must provide obvious equivalents to:

- **setup/doctor** — verify host prerequisites and acquire verified optional UI/runtime dependencies;
- **bootstrap** — obtain reviewed QEMU/extractor and pinned guest source;
- **build-base** — build/reuse the reviewed clean prepared base;
- **new-project** — create a fresh named instance and optional project source;
- **start** — start and reach READY;
- **open** — open the selected primary human interface/guest interaction path;
- **stop** — graceful stop;
- **status/diagnose** — read-only status and bounded diagnostics;
- **backup/export** — explicit sensitive stateful export where requested;
- **fresh-clone** — clean project clone from immutable baseline;
- **recover** — guide/refuse based on lifecycle/transaction evidence; never guess.

Helpers call the authoritative control plane/broker. They do not duplicate storage logic.

## First-run workflow

The README must support:

1. obtain/clone ezDarkFactory;
2. open normal unelevated PowerShell;
3. run doctor;
4. resolve explicit Windows prerequisites;
5. bootstrap verified dependencies;
6. acquire/build the clean guest base;
7. create one project VM;
8. start to READY;
9. open the selected GUI/TUI/guest interaction;
10. verify the empty workspace;
11. optionally initialise/clone a project;
12. stop cleanly.

The guide states disk/download estimates before large acquisition where practical.

## Everyday workflow

Human chooses a project/instance, observes its current state, starts it if stopped, opens guest interaction, works, then either leaves it running deliberately or stops it.

The UI always makes that final state clear.

## Fresh project kickoff

The kickoff wizard/helper asks only for information needed now:

- project/instance name;
- resource profile or accepted default;
- optional source choice: empty / clone URL / local copy;
- optional graphical guest profile if supported;
- optional later tool/agent setup.

It previews actions before mutation.

It does not ask for TUIsynth, provider or model details unless the human explicitly enters the relevant optional flow.

## Reference/demo workflow

Reference material is available from a distinct **Reference/Demo** action.

The operator is shown:

- historical/source pin;
- whether the source is original public, recovered-local, or documentation-only;
- that it is not the active project;
- any runtime/device limitations.

Launching it cannot alter the current project workspace.

## Recovery workflow

On UNKNOWN/ambiguous state:

1. stop offering destructive storage actions;
2. show exact observed/persisted identities and last error;
3. run only bounded diagnostics;
4. give the operator the checked-in recovery path;
5. preserve evidence until ownership is reconciled.

Do not instruct users to delete PID/runtime files as a generic fix.

## Portability workflow

Before moving the bundle:

- stop every managed VM positively;
- run portability validation;
- state which runtime/generated files are included;
- warn that stateful overlays may include credentials;
- copy the complete intended bundle;
- run doctor/portability checks at destination;
- start one selected VM and verify identity/READY.

The old source copy remains stopped while the same bundle identity is in use elsewhere.

## Documentation set

By EDF-008/EDF-010 the repository contains:

- root README quick start;
- first-run guide;
- operator guide;
- GUI/TUI controls reference;
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
- target;
- actual failed stage;
- preserved state;
- safe next action.

Avoid raw stack traces as the only message, but retain detailed logs for diagnosis.

## No hidden automation

The factory may later host coding agents, but initial kickoff does not auto-create an agent fleet, scheduler, model service or provider account.

Human operation remains useful with no AI service configured.
