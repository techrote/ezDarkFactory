# EDF-006 semantic scene/theme/damage spike

Status: **SOURCE / synthetic automated evidence only**. This is not the selected production TUI runtime and is not PHYSICAL-TUI evidence.

## Purpose

This bounded spike closes the machine-verifiable semantic presentation seam required by `docs/rag/03-HUMAN-CONTROL-SURFACE.md` sections 9, 11.4, 12 and 14.7. It deliberately performs no terminal probing, factory discovery, root registration, broker dispatch, subprocess launch, filesystem mutation or VM operation.

The spike provides:

- the complete required semantic role and state-modifier catalogue;
- embedded safe and high-contrast presentation data;
- deterministic `truecolor -> ANSI-256 -> ANSI-16 -> monochrome` capability degradation;
- deterministic Unicode -> ASCII fallback while preserving cell geometry;
- `full -> reduced -> off` motion capability degradation;
- status labels whose meaning remains textual rather than color/glyph-only;
- protection classes preventing decoration/content from overwriting critical UI cells;
- atomic clipping of two-cell wide glyphs;
- a fixed-size semantic scene independent of final ANSI encoding; and
- logical-damage comparison where unchanged scenes produce zero damage and local focus changes remain local.

External theme loading is intentionally **not implemented**. The v0.1 contract makes it optional, and omitting it avoids adding an executable/configuration attack surface before the production renderer is selected.

## Files

- `tools/edf006_scene_spike.py` — inert semantic scene, built-in theme/capability resolution, safe text/status helpers and logical damage.
- `tests/test_edf006_scene_spike.py` — deterministic cross-platform regression suite.

## Automated acceptance mapping

The focused suite covers:

- all 19 required semantic roles;
- truecolour, ANSI-256, ANSI-16 and monochrome rendering modes;
- Unicode and ASCII-only output;
- high-contrast mode;
- reduced-motion and motion-off negotiation;
- textual status meaning independent of color;
- control-character refusal in semantic text;
- decoration/content/critical protection ordering;
- atomic wide-glyph clipping;
- zero logical damage for unchanged frames; and
- bounded damage for a local focus indicator change.

Mouse/keyboard command-route parity remains covered by the existing EDF-006 command spike. Physical Windows Terminal color/Unicode rendering, actual terminal capability detection, presentation latency, selected runtime/framework behavior and human accessibility remain **NOT RUN**.

## Evidence boundary

Focused local execution for this increment:

```text
python -W error -m unittest discover -s tests -p test_edf006_scene_spike.py -v
15 tests: PASS, 0 FAIL, 0 SKIP

python -m compileall -q tools tests
PASS
```

This local run used the exact source/test bytes prepared for publication in an isolated Python workspace. Exact published-head repository CI must be re-run after the branch update; earlier-head green checks do not transfer.

## EDF-007 seam

If EDF-006 later accepts a concrete runtime, EDF-007 should retain this separation:

1. reducer/control state produces semantic cells and protected regions;
2. capability/theme resolution maps semantic roles to presentation;
3. renderer encodes the final ANSI/Unicode representation; and
4. logical damage compares semantic scenes before terminal output.

The selected runtime may replace this spike implementation, but it must preserve these behaviors and tests or provide equivalent stronger coverage.
