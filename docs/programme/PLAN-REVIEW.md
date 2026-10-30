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

That product direction is retained.

## Review finding: GitHub is not the original TUIsynth implementation history

The original TUIsynth programme deliberately moved implementation into local Git inside the development VM. The public repository at `e7060f6...` describes that local-only workflow.

The surviving EzVM field-study establishes accepted local main as `whole/TRIO-001..007` and records a distinct later partial pause checkpoint, but the connected public evidence does not expose the exact local Git SHA/tree.

**Improvement:** never substitute `tuisynth-codex` or another comparison fork. Record the logical stop state and unresolved exact local hash honestly. The new factory does not need TUIsynth implementation bytes as its active workload.

## Review finding: the VM source baseline is identifiable separately

The same field-study explicitly says the inspected local EzVM source was `b6abdf8...` plus owner-local `Keys.ps1` and `Runtime.ps1` patches.

**Improvement:** reconstruct the VM from exact EzVM v0.1.0 source and auditable provisioning, not from a copied historical disk. Treat the two local patches as behavior to reconcile. Use later public EzVM repairs as candidate evidence, not as permission to move the baseline silently.

## Review finding: copying the historical VM image is the wrong trust boundary

The lab VM accumulated experiments, project state and potentially credentials. A bit-for-bit disk copy would make TUIsynth state the default and would be difficult to audit or distribute safely.

**Improvement:** reproduce the environment recipe: verified QEMU, clean Ubuntu source, prepared base, coding profile, resource model and needed lifecycle fixes. Keep historical overlays out of the product.

## Review finding: “make it GUI” contains three different engineering tasks

A host manager GUI, a QEMU graphical console and a full guest Linux desktop have different dependencies, risks and benefits.

The historical source explicitly uses `-display none` and creates no host window, but lifecycle/QMP/SSH are already separated.

**Improvement:** qualify those three options independently. The GUI preference remains real, but no GUI is accepted merely because a window can be made to appear.

## Review finding: the UI must not become a second VM manager

A GUI/TUI that edits `instance.json`, launches QEMU separately or kills PIDs from a stale screen would regress the strongest EzVM properties.

**Improvement:** add a typed local broker/read model above the authoritative PowerShell control plane. Every UI uses that seam.

## Review finding: the old dashboard is useful research, not the finished product

EzVM's read-only dashboard and TRIO field study capture useful interaction, observation and recovery lessons. They also include TRIO-specific adapters and unfinished control proposals.

**Improvement:** reuse concepts deliberately; do not import the TRIO dashboard as an orchestration dependency. ezDarkFactory's first UI scope is VM/project human operation, not worker/provider fleet control.

## Review finding: a fallback decided too late could leave no usable interface

If the programme spends most of its effort on a graphical desktop and later discovers unacceptable portability or maintenance cost, a last-minute TUI would be poor.

**Improvement:** helper/CLI and typed control primitives are completed before the GUI decision. EDF-007 then implements the selected primary UI against a fixed parity matrix. The TUI fallback is fully specified in advance.

## Review finding: TUIsynth can contaminate “fresh project” semantics accidentally

Cloning a historical guest or installing reference source in the normal workspace could cause scripts, agents and humans to treat TUIsynth as the current task.

**Improvement:** make an empty project workspace a tested invariant. Reference/demo material has a distinct root, source pin and launcher. No historical queue/session/provider state is present.

## Review finding: GUI and VM claims need different evidence classes

A hosted test can prove a view model or TCG orchestration but cannot prove WHPX acceleration, Windows mouse/focus behavior or a human-readable guide.

**Improvement:** use SOURCE, FAST-CI, TCG-RUNTIME, WHPX-RUNTIME, PHYSICAL-UI and HUMAN-USABILITY evidence categories. Final release cannot collapse them.

## Review finding: human operation needs recovery paths, not just happy-path buttons

The inherited VM manager is intentionally fail-closed around ambiguous process/storage state. A polished UI that hides that evidence would make recovery worse.

**Improvement:** diagnostics, logs, exact target identity, portability, sensitive-state warnings and CLI recovery are first-class operator workflows.

## Improved plan

The improved sequence is:

1. **Reconstruct and manifest the historical VM baseline** at EzVM `b6abdf8...`, preserving the unresolved local-TUIsynth hash and local-patch evidence boundary.
2. **Create the ezDarkFactory core fork/namespace and CI** without changing behavior accidentally.
3. **Reconcile the two historical private patch classes** using safe regressions and later public repair evidence.
4. **Build the fresh-project guest profile** with an empty workspace and no TUIsynth active state.
5. **Expose one typed broker/helper control seam** for all future human interfaces.
6. **Run the GUI feasibility/ADR gate** across host manager, QEMU graphical console and full guest desktop.
7. **Implement the selected primary human control surface**: GUI path when qualified, otherwise the comprehensive TUI contract.
8. **Complete human kickoff/helpers/onboarding** for fresh projects.
9. **Add sealed TUIsynth reference/demo material** without making it active work.
10. **Complete portability, backup and recovery UX** through the selected interface.
11. **Qualify clean-host, WHPX and physical UI behavior** with exact evidence.
12. **Package and release an exact-source candidate** only after the applicable evidence is established.

## Why this is preferable

This sequence preserves the useful engineering already paid for in EzVM while removing the historical project's accidental state. It creates a usable control seam before UI selection, makes a GUI failure non-catastrophic, and ensures the final VM is a general development appliance rather than a TUIsynth snapshot with a new name.
