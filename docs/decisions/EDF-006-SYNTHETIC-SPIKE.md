# EDF-006 synthetic layout/input pre-spike — source evidence only

**Status:** partial EDF-006 engineering increment; **not** a TUI framework decision, production manager, native Windows Terminal spike, or EDF-006 acceptance.

**Source:** `ezDarkFactory/main@ae2dd266b7118f68a28500c84def00a18a889d10` at branch creation. Implementation files: `tools/edf006_layout_spike.py` and `tests/test_edf006_layout_spike.py`.

## Authority and scope

This reference reducer targets selected behavior from `docs/rag/03-HUMAN-CONTROL-SURFACE.md` sections 4.3–4.4, 5.5, 10.6–10.8 and 14.5, interpreted using pinned `techrote/specdocz@2e95d6931cc23862a4176c9d8ccb4da78f00c265` (the project-specific specification takes precedence). It is a bounded synthetic proof of geometry and input transaction semantics before a framework is selected and physically tested.

No external packages, terminal driver, executable root discovery, control-plane calls, QEMU operations, filesystem writes, credentials, network operations, provider calls, or manager workspace are used. These reference Python modules must **not** be interpreted as the selected production language or runtime.

## Implemented and exercised

| Mechanism | Concrete invariant | Automated evidence |
|---|---|---|
| Split solver | Deterministic columns/rows; one-cell divider; clamped child minimums | Required 40x12 / 80x24 / 120x40 / 160x48 / 200x60 fixtures, rows and extreme ratios |
| Responsive recovery | Compact focused tile when below 120x40 or unsatisfiable minimums | Compact/focus test; no zero-size crushed panes |
| Hit map | Final solved rectangles determine tile/divider hits without gaps or outside hits | Every cell at all five viewports audited |
| Divider drag | Capture requires actual divider, preview may follow pointer outside original divider, release commits once; compact resize cancels capture | Clamp, non-divider refusal, finished-capture refusal and resize rollback |
| Transaction rollback | Escape or focus loss cancels preview | Dedicated rollback regression |
| Overlays | Topmost first, outside dismissal consumed, Escape removes exactly one logical layer | Dismissal/no-click-through, stack regression |
| Session recovery | Visible/hidden state independent from per-tile local state; invalid session does not mutate existing state | Hide/restore and corrupt/unknown/duplicate session regression |

Focused run, using a Linux Python 3.13.5 scratch environment that contains only these two exact Git-blob-identical files:

```text
python -m unittest discover -s tests -p test_edf006_layout_spike.py -v
Ran 13 tests in 0.013s — OK
python -m compileall -q tools tests — PASS
```

These checks are **SOURCE / synthetic FAST-CI**. The complete Windows `scripts/Invoke-FastCheck.ps1` gate was **NOT RUN** locally: no Windows/PowerShell 5.1 runtime or pinned upstream Git objects were available. The existing `tools/check.py` unittest discovery will include the new test file on exact-head CI.

## Second bounded increment: multi-root observation scheduling

The adjacent `tools/edf006_observation_spike.py` is another **synthetic, framework-neutral** state machine. Its `ObservationScheduler` neither executes a real collector nor reads a real factory. The EDF-005 contract remains the only mutation authority. Exact fixture inputs represent already-verified factory IDs and canonical paths; this code is not root discovery or identity verification.

Implemented/read-model contracts:

- Bounded global in-flight slots and waiting intents, FIFO coalescing of repeated root/class refreshes, and no second simultaneous ordinary class request for one enrollment. Work is **returned** for an external executor; nothing executes on the UI thread here.
- Immutable observation request tokens bind enrollment, factory ID, root epoch, class and monotonic per-class serial. Late results after a refresh, unregister/re-register/relocation, identity conflict or transient conflict resolution cannot become current. An active worker retains its slot until actual completion/termination; this prototype does **not** pretend to cancel it.
- Same-factory-ID collision across two verified path fixtures prevents publication; duplicate canonical paths and enrollment IDs refuse registration. Unregister removes only a manager record.
- Unknown, current, stale, unreachable, incompatible and identity-conflict read-model dispositions are distinct. Retained last-known rows remain visibly non-current after failures, and a clock regression cannot assert freshness.
- Bounded 10,000-row synthetic log cache acceptance (each input row at most 8,192 characters) and a 16-root/128-row fixture. Log content is **untrusted raw data** and must be sanitized by a production renderer before display.

Focused local qualification on isolated exact Git-blob-identical files:

```text
python -m unittest discover -s tests -p test_edf006_observation_spike.py -v
Ran 15 tests — OK (0 failures, 0 skips)
python -m compileall -q tools tests — PASS (on isolated scratch files)
```

The slow-root case holds one synthetic slot indefinitely while another factory completes and a third is dispatched. This proves admission/read-model isolation **only**, not actual process termination, a 10-second runtime timeout, scheduled refresh targets, p95 latency or Windows Terminal responsiveness. A real bounded executor must supply trustworthy timeouts, teardown, signed/typed adapters, result-channel backpressure, and safe stale-worker termination without exceeding the real concurrency budget. This implementation does not claim command parity, a chosen UI runtime, native input, persisted manager-state ownership, full repository fast-gate results or release qualification.

## Explicitly unproved EDF-006 obligations

- Framework/runtime comparison, reproducible dependency pins, packaging/license choice and final `docs/decisions/EDF-006-HOST-TUI-STACK.md` ADR.
- Real mouse button/move/wheel, focus-loss sequences, native paste, resize, Unicode/ASCII/color mode, terminal restoration, input-to-frame latency on actual Windows Terminal.
- Full semantic command registry/parity; persistent production layout tree; one-writer portable workspace; separate config/registry/session/journal files.
- EDF-005 typed adapter integration, real factory-by-path registration, a native bounded worker/timeout implementation, actual slow-root runtime isolation and physical/latency qualification. The synthetic identity-collision/generation/queue/16-root/128-row/10,000-row fixtures above cover only state-machine behavior.
- Full exact-head Windows merge gate; real TCG/WHPX, PHYSICAL-TUI and HUMAN-USABILITY.

**HOLD EDF-006 and the PR as Draft.** Next, select and run an actual Windows Terminal stack candidate against the accepted typed broker, then extend this reference as needed into a real native input/rendering spike and its CI/qualification evidence. Do not adopt a stack or merge solely from these synthetic tests.
