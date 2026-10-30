# ezDarkFactory

A fresh-project, human-operated development VM factory derived from a pinned EzVM checkpoint.

## Status

Planning programme only. No VM/runtime implementation has been imported yet.

The authoritative implementation programme is in `docs/programme/IMPLEMENTATION-PROGRAMME.md`.
Read `AGENTS.md` and `RAG.md` before changing the repository.

## Historical pins

- EzVM source baseline: `techrote/ezvm@7b829f8352a9fa30c965e57386965767c5969e0d` (2026-10-17 17:32:34 UTC).
- Last observed TUIsynth implementation commit: `techrote/tuisynth-codex@357215781ba0b82694e62dd4d7ba1c3697ac3159` (2026-10-18 09:25:55 UTC), completing TRIO-016.
- TRIO-017 remained open. ezDarkFactory is not a continuation of TRIO/TUIsynth.
- TUIsynth may exist in the finished VM only as an isolated, pinned reference/demo corpus.

## Product direction

The preferred human experience is a GUI where it can be delivered without weakening portability, deterministic VM state, automated qualification or clean-host operation. A dedicated feasibility gate decides whether a graphical guest/control surface is practical. If it is not, the required fallback is a comprehensive control and monitoring TUI, not a return to script-only operation.

The authoritative VM lifecycle remains a testable control plane. Human UI code must call typed commands/broker interfaces; it must not edit instance JSON or QCOW2 state directly.
