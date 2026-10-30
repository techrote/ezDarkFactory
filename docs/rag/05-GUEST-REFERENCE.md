---
document_id: EDF-GUEST
status: authority
---

# Fresh guest profile and TUIsynth reference contract

## Default guest purpose

The default guest exists to start **new software projects**. It is not a restored TRIO worker and it is not pre-bound to any particular repository, model provider or agent.

The historical EzVM coding profile is the starting point because it already provides a general coding environment, versioned readiness, a normal `coder` account and `/home/coder/workspace`.

## Fresh workspace invariant

After creating a new project instance and reaching READY:

- `/home/coder/workspace` exists and is owned/writable by `coder`;
- the active workspace contains no TUIsynth checkout unless the human explicitly chooses to copy/clone it there later;
- no TRIO `STATUS.md` state is treated as a current work queue;
- no OpenCode/LM Studio/provider session is started automatically;
- no historical credentials or authenticated config exist;
- no historical Git branch is checked out as the active project;
- no project-specific background service is running solely because the reference demo exists.

A small generic welcome/kickoff file may be generated outside or inside the empty workspace only if its schema/content is documented and project-neutral.

## EDF-004 default fresh-project profile

New managed instances use EDF-owned profile **`fresh-project` version 1**.
The inherited `coding-default` version 1 source remains readable only for
already durable historical intents; EDF does not silently rewrite those overlays.

The fresh profile is identified by its reviewed manifest + provision-script
SHA-256 digest. Its authenticated READY marker is the exact guest identity
(documenting instance name, immutable base, resource profile, generated
cloud-instance identity, `fresh-project` name/version and digest) plus
`provisioningState: "complete"`. Because the cloud identity includes the
durable `identityGeneration`, an old READY marker cannot authorize a reset,
fresh clone or replacement generation.

On the **first** successful provisioning of each identity generation,
`/home/coder/workspace` must be empty and the guest refuses known historical
TUIsynth/TRIO state, provider/model credential locations and coder autostart
state before publishing READY. A same-generation re-provision may validate
after the human has added project files only when a matching completed marker
already proved that generation's fresh start; a failed live validation removes
the marker before returning failure. Validation never deletes user project data.

Explicit **stateful clone** and **import** are preservation operations, not
fresh-project creation. They use the retained `coding-default/v1` validation
contract so preserved workspace/authentication state is not misrepresented as
empty. Ordinary create and **fresh clone** use `fresh-project/v1`.

### Profile extension seam

Later optional profiles are new named/versioned manifests, not mutations of
`fresh-project/v1`:

- graphical desktop: only after the EDF-006 stack decision explicitly GOes it;
- optional language/developer stacks: inherit the same identity/readiness and
  workspace ownership contracts and add separately pinned capabilities;
- reference/demo material: installed outside the active workspace, opt-in,
  source-pinned and unable to satisfy or alter project READY.

Unknown profile names/versions fail closed. A profile extension cannot weaken
locked-password/public-key SSH, root-login refusal, required-tool validation,
workspace ownership, current-generation identity or stale-READY rejection.

## Stable coding baseline

Preserve or explicitly supersede the historical general-purpose baseline:

- Git;
- compiler/build essentials;
- CMake/Ninja;
- Python with venv/pip;
- curl/wget;
- jq;
- ripgrep;
- archive tools;
- rsync;
- tmux;
- OpenSSH;
- predictable `coder` home/workspace;
- versioned READY validation.

Rapidly changing agent CLIs, Node/Rust toolchains and local-model runtimes are opt-in profiles or human kickoff steps unless their acquisition/pinning policy is explicitly accepted.

## Future graphical guest profile

A graphical guest desktop is **not a v0.1 management requirement**. The host-side management TUI and managed SSH/external-terminal path are sufficient for the current programme.

If a later explicit project/spec delta introduces a graphical guest profile, add it as a versioned profile/variant rather than silently bloating the minimal coding baseline.

Any future graphical profile must:

- inherit the same instance identity/readiness/security contract;
- use repository-controlled provisioning;
- pin/record relevant packages and sources;
- have a deterministic capability marker checked by readiness;
- record incremental disk/base size and startup/RAM overhead;
- preserve SSH as the recovery/control path;
- disable unreviewed host sharing/clipboard integrations by default;
- keep the minimal/headless coding profile supported unless a separately reviewed compatibility decision retires it.

A desktop that merely boots is not READY until the required graphical session components and normal coding tools are validated.

## TUIsynth reference purpose

TUIsynth is retained only to demonstrate/reference the workload that exercised the historical VM.

It may help a human understand:

- the original local multi-agent workflow;
- a nontrivial Python/TUI/audio project shape;
- historical VM/resource/recovery lessons;
- how to launch a harmless reference/demo if a runnable, source-authenticated snapshot is available.

It is not the next project and it has no implementation priority in ezDarkFactory.

## Reference source hierarchy

Use, in order:

1. any exact original local TUIsynth checkpoint later recovered and authenticated by EDF-001;
2. original `techrote/tuisynth` public source at `e7060f6788421029ea9a1cb7cbee86a994c5b4d5` plus its preserved recovered synth sources/programme documents;
3. public EzVM TRIO field-study material as historical explanatory evidence.

Comparison repositories such as `tuisynth-codex` or `tuisynth-claude` are not substituted for the original reference. If ever included for comparison, they must live in a separately labelled comparison area and remain opt-in.

## Reference installation

Preferred shape:

```text
/opt/ezdarkfactory/reference/
  tuisynth/
    SOURCE-PIN.json
    README.md
    ...reference source...
```

or an equivalent versioned read-only/reference root owned by the guest profile.

Do not place reference source under `/home/coder/workspace` by default.

The reference install manifest records repository, commit/tree/hash or recovered-packet hash, license/provenance status and whether it is runnable or documentation-only.

## Demo behavior

A reference/demo launcher:

- is explicitly selected by the human;
- identifies the source pin before launch;
- uses isolated demo state;
- does not mutate the fresh project workspace;
- does not resume historical workers/queues;
- does not require provider credentials;
- defaults to offline/device-free operation where practical;
- exits back to the normal operator workflow cleanly.

If a runnable original checkpoint cannot be authenticated, ship a documentation/reference browser rather than quietly substituting Luna/comparison output.

## New project bootstrap

The human can choose:

- empty workspace;
- clone an explicitly entered Git URL;
- copy a local project through the accepted file-transfer path;
- later, a reviewed template.

The default is **empty workspace**.

Project kickoff records only project-neutral metadata required for operator convenience. It must not add an AI agent, model or provider unless the human explicitly chooses that step.

## Credentials

Authentication performed by the user inside a mutable guest may survive restart and stateful copies. It is discarded by clean reset/fresh clone according to the underlying base semantics.

The README/UI must explain this before stateful export/clone.

No reference/demo content is permitted to supply credentials.
