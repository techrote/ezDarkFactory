"""EDF-006 bounded deterministic pipe replay of the native layout probe.

Synthetic SOURCE/FAST-CI evidence only. Does not open the Windows console,
load factory code, use the EDF-005 control plane, or alter runtime state.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from typing import BinaryIO

MAX_EVENTS = 128
MAX_LINE_BYTES = 512
MAX_TOTAL_BYTES = 32768
POINTER = frozenset({"press", "move", "release"})
FOCUS = frozenset({"focus_loss", "focus_gain"})
KEYS = frozenset({"Escape", "q", "m", "t"})


class ReplayRefusal(ValueError):
    """Input is outside the finite, inert replay protocol."""


def _unique_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ReplayRefusal("duplicate JSON member")
        result[key] = value
    return result


def _integer(value: object, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def parse_event(raw: bytes) -> tuple[str, int, int, int | str]:
    """Only an exact allowlisted event vocabulary can reach Demo.apply."""
    try:
        obj = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_pairs,
                         parse_constant=lambda _x: (_ for _ in ()).throw(
                             ReplayRefusal("nonfinite number")))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ReplayRefusal("invalid JSONL record") from exc
    if not isinstance(obj, dict) or type(obj.get("kind")) is not str:
        raise ReplayRefusal("missing event kind")
    kind = obj["kind"]
    if kind in FOCUS:
        if set(obj) != {"kind"}:
            raise ReplayRefusal("unexpected focus fields")
        return kind, 0, 0, 0
    if kind == "key":
        if set(obj) != {"kind", "value"} or type(obj["value"]) is not str or obj["value"] not in KEYS:
            raise ReplayRefusal("unsupported key")
        return kind, 0, 0, obj["value"]
    if kind == "resize":
        if set(obj) != {"kind", "x", "y"} or not _integer(obj["x"], 1, 300) or not _integer(obj["y"], 1, 100):
            raise ReplayRefusal("invalid resize")
        return kind, obj["x"], obj["y"], 0
    if kind in POINTER or kind == "wheel":
        expected = {"kind", "x", "y", "value"} if kind == "wheel" else {"kind", "x", "y"}
        if set(obj) != expected or not _integer(obj["x"], -32768, 32767) or not _integer(obj["y"], -32768, 32767):
            raise ReplayRefusal("invalid pointer")
        if kind == "wheel":
            if not _integer(obj["value"], -1200, 1200):
                raise ReplayRefusal("invalid wheel delta")
            return kind, obj["x"], obj["y"], obj["value"]
        return kind, obj["x"], obj["y"], 0
    raise ReplayRefusal("unsupported event kind")


def read_events(source: BinaryIO):
    """Bound input before decoding; no silent truncation or ignored tail."""
    total = 0
    for index in range(MAX_EVENTS + 1):
        raw = source.readline(MAX_LINE_BYTES + 1)
        if not raw:
            return
        total += len(raw)
        if index == MAX_EVENTS or len(raw) > MAX_LINE_BYTES or total > MAX_TOTAL_BYTES:
            raise ReplayRefusal("replay budget exceeded")
        if not raw.endswith(b"\n") and len(raw) == MAX_LINE_BYTES + 1:
            raise ReplayRefusal("overlong record")
        if not raw.strip():
            raise ReplayRefusal("empty record")
        yield parse_event(raw)
    raise ReplayRefusal("replay event limit exceeded")


def replay(source: BinaryIO, width: int, height: int) -> dict[str, object]:
    if not _integer(width, 1, 300) or not _integer(height, 1, 100):
        raise ReplayRefusal("invalid starting viewport")
    # Deliberately import the *same* reducer and frame composer as the native
    # probe. No independent layout or false physical-viewport simulation.
    from edf006_winconsole_probe import Demo, Event, frame_text

    demo = Demo(width, height)
    frames = []

    def snapshot(sequence: int, kind: str):
        encoded = frame_text(demo).encode("ascii", "strict")
        frames.append({
            "sequence": sequence, "event": kind,
            "sha256": hashlib.sha256(encoded).hexdigest(),
            "width": demo.width, "height": demo.height,
            "compact": demo.frame.compact, "focus": demo.focus,
            "dividerX": demo.frame.divider.x if demo.frame.divider else None,
            "dragActive": demo.drag is not None and demo.drag.active,
            "overlayDepth": len(demo.overlays.overlays),
            "running": demo.running,
        })

    snapshot(0, "startup")
    count = 0
    for kind, x, y, value in read_events(source):
        if not demo.running:
            raise ReplayRefusal("events after quit")
        demo.apply(Event(kind, x, y, value))
        count += 1
        snapshot(count, kind)
    return {
        "schemaVersion": 1, "evidence": "SYNTHETIC-PIPE-ONLY",
        "inputEvents": count, "initialViewport": [width, height],
        "frames": frames,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="EDF-006 deterministic synthetic pipe replay")
    parser.add_argument("--width", required=True, type=int)
    parser.add_argument("--height", required=True, type=int)
    opts = parser.parse_args(argv)
    try:
        result = replay(sys.stdin.buffer, opts.width, opts.height)
    except (ReplayRefusal, ValueError) as exc:
        print("EDF-006 replay refused: " + str(exc), file=sys.stderr)
        return 2
    json.dump(result, sys.stdout, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
