# EDF-006 — Native Windows console input candidate probe (not accepted)

**Status: diagnostic only / EDF-006 DRAFT-HOLD.** This is an opt-in, non-production, Windows-native candidate probe, not the selected or pinned TUI stack and not PHYSICAL-TUI evidence. The authoritative contract is docs/rag/03-HUMAN-CONTROL-SURFACE.md sections 3.7, 4, 5, 9, 11, 14 and issue #6.

## Execute on an actual Windows Terminal host

From the repository checkout, using a trusted, explicitly installed Python interpreter:

    python .\tools\edf006_winconsole_probe.py

Open at 80×24 and 160×48 (the script initially uses the current physical console viewport), then record Windows build, Windows Terminal version, interpreter build, source SHA/tree, permissions, input mode, and outcomes. Use m for a dismissible modal, t to switch focus, left-drag the separator, Escape to cancel or quit, q to quit; observe wheel events and resize/focus loss during an active drag. Do not interpret a successful automated test as proof that any of these physical events arrived.

The script calls Windows Console ReadConsoleInputW with mouse/window events enabled; it explicitly disables Quick Edit and VT input so its input path remains native console records. It draws a trusted ASCII-only split demonstration using the existing EDF-006 geometry/drag/overlay reducer and VT output. Both original console input/output modes and the alternate screen/cursor are restored in finally-equivalent context cleanup on normal or exceptional exit. Forced process termination, power loss, terminal-host crashes, and terminals that do not forward focus events are not proved restored. Actual Windows Terminal behavior, paste, IME, color/Unicode degradation, latency, real-root observation, API integration, async renderer, and packaging remain unqualified.

This probe does not enroll or inspect roots, import executable root code, dispatch typed operations, modify the manager registry/workspace, persist key events, or touch QEMU. It deliberately has no network, external Python package, or credential acquisition. A future decision must compare this Win32-console/VT candidate with a maintained TUI framework and record exact interpreter/framework acquisition/version/license and Windows Terminal qualification before naming a selected stack.

## Automated source qualification

tests/test_edf006_winconsole_probe.py exercises native record decoding (press/move/release, signed wheel, focus loss, resize, key-up filtering), geometry drag transaction, overlay click consumption, small-viewport rollback, oversized-viewport refusal, ASCII-only trusted output and non-Windows import/entry refusal. It also verifies the native INPUT_RECORD ABI is 20 bytes only on Windows, where that check executes. A Linux Python 3.13.5 focused scratch run executed 14 cases: 13 PASS, one Windows-only ABI case SKIP, 0 FAIL. Python compileall PASS. These are software/synthetic checks; no native console input or Windows Terminal visual test was executed in the scratch environment.

## Admission limits

This diagnostic is intentionally not connected to the EDF-005 observation bridge: real-root display, immutable command dispatch, concurrency, durable operation reconciliation and all mutations remain outside this source. It does not establish terminal restoration after forcible kill, arbitrary-input paste handling or the spec's p95 budget. Do not mark EDF-006 Ready, merge PR #28 or close #6 from this evidence. Next run must qualify the candidate on an actual Windows Terminal host and then select/pin a production runtime based on measured results rather than assumptions.
