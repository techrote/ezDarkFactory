# ezDarkFactory

A fresh-project, human-operated development VM factory derived from the EzVM environment used for the original local TUIsynth/TRIO run.

## Status

Planning programme published; VM/runtime implementation has not yet been imported.

Start with:

- `AGENTS.md` — autonomous implementation/PR/merge contract;
- `RAG.md` — project authority index;
- `docs/programme/PLAN-REVIEW.md` — initial plan, review findings and improved plan;
- `docs/programme/IMPLEMENTATION-PROGRAMME.md` — dependency graph and issues [#1](https://github.com/techrote/ezDarkFactory/issues/1) through [#12](https://github.com/techrote/ezDarkFactory/issues/12).

## Historical reconstruction

- **VM source baseline:** `techrote/ezvm@b6abdf8c3edd61695db30894da991f275b39a699` (EzVM v0.1.0).
- The October 2026 TRIO field-study explicitly records that the inspected development VM used that EzVM source **plus owner-local `Keys.ps1` and `Runtime.ps1` patches**.
- **Original TUIsynth programme pin:** `techrote/tuisynth@e7060f6788421029ea9a1cb7cbee86a994c5b4d5`. Its own instructions state that subsequent implementation, testing, review and merges happened in **local Git inside the development VM**, without GitHub pushes.
- The surviving field-study says the accepted local synth main ended at **whole/TRIO-001..007** and that a **later partial pause checkpoint** existed at a different commit/root. The exact local checkpoint SHA is not present in the currently connected public evidence and must not be invented.
- `techrote/tuisynth-codex` and `techrote/tuisynth-claude` are comparison work and are **not authority for the original local development cutoff**.
- ezDarkFactory is not a continuation of TUIsynth. TUIsynth may exist in the finished VM only as isolated, pinned reference/demo material.

See `docs/rag/01-BASELINE-PROVENANCE.md` for the evidence boundary and reconstruction rules.

## Product direction

The preferred human experience is a GUI where it can be delivered without weakening portability, deterministic VM state, automated qualification or clean-host operation. A dedicated feasibility gate evaluates host GUI management, QEMU graphical console/display and an optional desktop guest profile independently.

If a practical GUI path is not established, the required product is a comprehensive control and monitoring TUI, not a return to script-only operation.

The authoritative VM lifecycle remains a testable control plane. Human UI code must call typed commands/broker interfaces; it must not edit instance JSON or QCOW2 state directly.
