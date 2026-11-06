"""Bounded, privacy-minimal diagnostic timing receipts for EDF-006.

A console-read return is NOT the physical event timestamp, and a successful
stdout.flush is NOT proof of terminal presentation. These receipts are not
PHYSICAL-TUI acceptance without independent native operator evidence.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

# One-millisecond quantization with a dedicated >=1024 ms overflow bin.
# Fixed memory regardless of how long the interactive diagnostic runs.
_BUCKETS = 1025
_KINDS = frozenset({"key", "press", "move", "release", "wheel",
                    "focus_gain", "focus_loss", "resize"})
_NAVIGATION = frozenset({"key", "press", "release", "wheel"})


class _Histogram:
    def __init__(self) -> None:
        self.buckets = [0] * _BUCKETS
        self.count = 0

    def add(self, duration_ns: int) -> None:
        if duration_ns < 0:
            raise ValueError("negative time interval")
        index = min(duration_ns // 1_000_000, _BUCKETS - 1)
        self.buckets[index] += 1
        self.count += 1

    def summary(self) -> dict:
        def bound(percent: int) -> int | None:
            if not self.count:
                return None
            target = math.ceil(self.count * percent / 100)
            cumulative = 0
            for index, quantity in enumerate(self.buckets):
                cumulative += quantity
                if cumulative >= target:
                    return None if index == _BUCKETS - 1 else index + 1
            raise AssertionError("histogram inconsistent")

        return {"count": self.count, "overflow_ge_1024ms": self.buckets[-1],
                "p50_upper_ms": bound(50), "p95_upper_ms": bound(95),
                "p99_upper_ms": bound(99)}


class ProbeMetrics:
    """No individual input values, terminal output, factory data, or paths."""

    def __init__(self) -> None:
        self.kind_counts = {kind: 0 for kind in sorted(_KINDS)}
        self.rendered = 0
        self.compose = _Histogram()
        self.flush = _Histogram()
        self.navigation = _Histogram()

    def record(self, kind: str, read_return_ns: int,
               compose_start_ns: int | None = None,
               compose_end_ns: int | None = None,
               flush_end_ns: int | None = None) -> None:
        if kind not in _KINDS:
            raise ValueError("unsupported normalized event kind")
        times = (compose_start_ns, compose_end_ns, flush_end_ns)
        if any(value is None for value in times):
            if any(value is not None for value in times):
                raise ValueError("incomplete frame timing")
        else:
            assert compose_start_ns is not None
            assert compose_end_ns is not None
            assert flush_end_ns is not None
            if not (0 <= read_return_ns <= compose_start_ns <= compose_end_ns <= flush_end_ns):
                raise ValueError("nonmonotonic timing")
            self.compose.add(compose_end_ns - compose_start_ns)
            self.flush.add(flush_end_ns - read_return_ns)
            if kind in _NAVIGATION:
                self.navigation.add(flush_end_ns - read_return_ns)
            self.rendered += 1
        self.kind_counts[kind] += 1

    def summary(self) -> dict:
        return {
            "schemaVersion": 1,
            "qualification": "UNVERIFIED_NATIVE_DIAGNOSTIC",
            "method": "ReadConsoleInputW return to stdout.flush completion; not physical event arrival or presentation",
            "quantization": "upper-bound 1ms bins; >=1024ms reported as overflow (null percentile)",
            "event_kind_counts": dict(self.kind_counts),
            "rendered_frames": self.rendered,
            "composition_ms": self.compose.summary(),
            "read_to_flush_ms": self.flush.summary(),
            "navigation_read_to_flush_ms": self.navigation.summary(),
        }


def write_receipt(path: str, metrics: ProbeMetrics) -> None:
    """Opt-in, create-only file; never overwrite an existing evidence record."""
    destination = Path(path)
    if not destination.is_absolute() or not destination.parent.is_dir():
        raise ValueError("receipt needs an absolute path in an existing directory")
    payload = (json.dumps(metrics.summary(), ensure_ascii=True, sort_keys=True,
                          allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(payload) > 8192:
        raise ValueError("receipt size cap exceeded")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(destination, flags, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(payload)
        output.flush()
        os.fsync(output.fileno())
