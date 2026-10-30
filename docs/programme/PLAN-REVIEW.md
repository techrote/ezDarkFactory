# ezDarkFactory plan review

## Initial requested plan

The owner request can be summarised as:

1. locate the point at which original TUIsynth development ceased;
2. copy the VM setup at that point;
3. convert the VM from headless to GUI if practical;
4. otherwise provide a comprehensive control/monitoring TUI;
5. add helper scripts and human kickoff/operator documentation;
6. use the result for fresh projects, with TUIsynth retained only as reference/demo;
7. express the work as an autonomous issue-based programme with RAG authority, PRs, automated checks and merge completion.

## Review findings retained from the first planning pass

### GitHub is not the original TUIsynth implementation history

The original TUIsynth programme deliberately moved implementation into local Git inside the development VM. The public repository at `e7060f6...` describes that local-only workflow.

The surviving EzVM field-study establishes accepted local main as `whole/TRIO-001..007` and records a distinct later partial pause checkpoint, but the connected public evidence does not expose the exact local Git SHA/tree.

**Disposition:** never substitute `tuisynth-codex` or another comparison fork. Record the logical stop state and unresolved exact local hash honestly.

### The VM source baseline is identifiable separately

The field-study says the inspected local EzVM source was `b6abdf8...` plus owner-local `Keys.ps1` and `Runtime.ps1` patches.

**Disposition:** reconstruct from exact source/provisioning and reconcile the two patch classes through evidence rather than copying a historical authenticated disk.

### Copying the historical VM image is the wrong trust boundary

The lab VM accumulated experiments, project state and potentially credentials.

**Disposition:** reproduce the environment recipe; keep historical overlays out of the product.

### The UI must not become a second VM manager

A UI that edits `instance.json`, launches QEMU independently or kills stale PIDs would regress EzVM safety.

**Disposition:** all management UI actions use typed factory control/broker operations.

### TUIsynth can contaminate fresh-project semantics

**Disposition:** empty active project workspace is tested; TUIsynth remains separate reference/demo material.

### GUI and VM claims need different evidence classes

**Disposition:** SOURCE, FAST-CI, TCG-RUNTIME, WHPX-RUNTIME, PHYSICAL-UI and HUMAN-USABILITY remain separate.

### Human operation needs recovery paths

**Disposition:** diagnostics, identity, logs, portability, sensitive-state warnings and CLI recovery are first-class.

## Owner direction update — host-side tile-native manager

On 30 October 2026 the owner selected a **host-side management TUI with GUI-like tile/mouse interaction** as the primary UI direction.

The key rationale is that one host manager can operate multiple independent ezDarkFactory roots from one interface and gives a cleaner foundation for later extension than coupling management to one guest GUI.

This supersedes the earlier plan to choose between host GUI and TUI at EDF-006.

### Consequences

- V0.1 primary UI is a tile-native Windows Terminal TUI.
- Multi-factory root registration/identity/observation is a core requirement.
- Each factory remains independently authoritative for VM/storage/security.
- QEMU graphical console and guest desktop are not v0.1 management requirements.
- EDF-006 selects/qualifies the TUI implementation stack and multi-root adapter mechanics rather than deciding GUI vs TUI.
- EDF-007 implements the production multi-factory host manager.
- A future native GUI or remote-host adapter must be an explicit project/spec delta and should reuse semantic commands/adapters where appropriate.
- Embedded arbitrary PTY is not required for v0.1; external managed SSH/Windows Terminal attach is sufficient.

## specdocz tailoring decision

The host manager UI contract is tailored from:

- normative baseline: `techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265:tuiuiux/tile-native-gui-tui-uiux-spec.md`;
- implementation pattern library: the matching `tile-native-gui-tui-implementation-spec.md`;
- tailoring method: the matching `tile-native-gui-tui-spec-tailoring.md`.

The resulting authoritative project-specific contract is:

`docs/rag/03-HUMAN-CONTROL-SURFACE.md`

Future specdocz changes must be reviewed as explicit deltas.

## Revised implementation sequence

1. **Reconstruct and manifest the historical VM baseline** at EzVM `b6abdf8...`.
2. **Create the ezDarkFactory core fork/namespace and CI**.
3. **Reconcile the two historical private patch classes**.
4. **Build the fresh-project guest profile**.
5. **Expose typed per-factory control plus stable factory identity and multi-root manager substrate**.
6. **Qualify and pin the tile-native host-manager implementation stack**, native Windows Terminal event behavior, persistence model and multi-root observation/operation mechanics.
7. **Implement the production multi-factory host management TUI** to the tailored UI specification.
8. **Complete human kickoff/helpers/onboarding**.
9. **Add sealed TUIsynth reference/demo material**.
10. **Complete portability, backup and recovery UX** through the host manager.
11. **Qualify clean-host, WHPX and physical Windows Terminal behavior**.
12. **Package and release an exact-source candidate** only after applicable evidence is established.

## Why this is preferable

The revised plan keeps every factory's proven lifecycle/storage boundary intact while moving human control up to a host-level manager.

It avoids multiplying UI/controller clients per factory, gives the operator a coherent fleet view, permits independent factory failures without collapsing the whole interface, and creates a semantic layer that can later support remote roots or a native GUI without making those v0.1 dependencies.
