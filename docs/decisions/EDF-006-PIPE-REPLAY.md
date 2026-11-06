# EDF-006 — Deterministic pipe replay for the native layout diagnostic

**Status: synthetic SOURCE/FAST-CI test seam only. Not PHYSICAL-TUI proof, not a selected/pinned production TUI runtime.** This deliberately bounded increment supplements the opt-in native probe described in [EDF-006-WINCONSOLE-PROBE.md](EDF-006-WINCONSOLE-PROBE.md); it does not replace that probe or satisfy the EDF-006 native acceptance gate.

## Purpose and execution

The replay tool imports the **same** `Demo`, `Event` reducer, and `frame_text` composer used by `tools/edf006_winconsole_probe.py`, but reads synthetic, allowlisted normalized events from stdin instead of opening a Windows console. This allows Linux/Windows CI and deterministic pipe-driven tests to exercise native-probe layout, focused compact mode, transactional divider capture, overlay click consumption, resize, and output composition.

Example, from a trusted repository checkout:

```sh
printf '%s\n' '{"kind":"key","value":"m"}' '{"kind":"key","value":"Escape"}' '{"kind":"wheel","x":5,"y":5,"value":-120}' | python tools/edf006_replay_probe.py --width 160 --height 48
```

On Windows PowerShell, emit one JSON object per line to the interpreter's stdin or use the Python `replay(io.BytesIO(...), width, height)` function from a test. The five contract viewport fixtures are 40x12, 80x24, 120x40, 160x48 and 200x60.

Supported events: `key` with `value` in `Escape/q/m/t`; `press`, `move`, `release` with integer `x,y`; `wheel` with integer `x,y,value`; `resize` with integer `x,y`; and `focus_gain` / `focus_loss` with no additional fields. Pointer coordinates are **viewport-relative** in this normalized synthetic protocol. Physical Win32 screen-buffer-to-viewport translation is tested separately in the native decoder.

Replay is fail-closed for unknown or extra JSON fields, duplicate members, invalid UTF-8, nonfinite numbers, Boolean-as-integer confusion, unsupported commands, overlong/blank lines, 129+ events, or further events after quit. Limits: 128 events, 512 bytes per line, 32768 aggregate input bytes, and 300x100 maximum viewport. No factory identity, project, runtime, shell, or command dispatch fields are admitted.

## Evidence boundary and output

The tool returns a stable JSON summary with `evidence=SYNTHETIC-PIPE-ONLY`, the input event count, starting viewport, and one SHA-256 of the **trusted ASCII frame** for startup and each event. It also reports resulting visible geometry, compact mode, focus, divider x, drag capture, overlay stack depth and running state. This summary is intentionally not a copy of a live screen, not a raw native input capture and not input-to-visible-frame latency evidence.

The replay makes no filesystem writes; redirecting its JSON output is an explicit operator choice. It imports no candidate-root code, does not enroll factories, does not read private state and cannot dispatch EDF-005 mutations. It accepts no log/guest text. Do not store private host/interaction traces in the repository or present synthetic frame hashes as physical screen observations.

## Qualification and remaining gates

`tests/test_edf006_replay_probe.py` covers the bounded parser, refusal controls, deterministic repeated rendering across all five viewport fixtures, focus-loss and resize drag rollback, divider commit, overlay outside-click consumption, quit and trailing-event refusal. Run:

```sh
python -W error -m unittest discover -s tests -p test_edf006_replay_probe.py -v
python -m compileall -q tools tests
```

A real Windows Terminal operator still must exercise the native Win32 diagnostic at 80x24 and 160x48, with physical mouse, focus, paste, resize, Unicode/theme, restoration and timing observations. The production runtime/framework, acquisition pins, ADR and full EDF-006 acceptance remain **HOLD** until independently evidenced. A replay PASS never substitutes for a PHYSICAL-TUI PASS.
