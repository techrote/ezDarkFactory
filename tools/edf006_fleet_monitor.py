"""EDF-006 real Textual read-only multi-root observation integration spike.

Bootstrap uses the bounded trusted EDF-005 static adapter, OFF the UI thread.
Subsequent requests use independently deadline-bounded per-enrollment workers.
This is not a production host manager, instance readiness, or PHYSICAL-TUI proof.
No mutating command, guest access, or candidate executable is present.
"""
from __future__ import annotations

import argparse
from concurrent.futures import Future, ThreadPoolExecutor
import json
from math import isfinite
from pathlib import Path
import sys
import time
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
from edf006_observation_spike import ObservationScheduler
from edf006_readonly_bridge import (
    ENROLLMENT, FACTORY, StaticRoot, collect_static,
)
from edf006_root_collector import collect_root
from edf006_worker_pump import ObservationPump, WorkerResult

MAX_ROOTS = 128
BOOTSTRAP_DEADLINE = 10.0


class FleetSession:
    """Single UI-thread-owned read-only fleet, seeded by trusted static rows.

    A whole-fleet bootstrap result is *never* promoted into a fresh reading.
    Only a matching per-root callback can publish current static identity.
    Bootstrap conflicts/incompatibilities stay held for full-fleet operator
    reconciliation; a single-root callback cannot clear such a condition.
    """

    def __init__(self, rows: tuple[StaticRoot, ...], workspace: Path,
                 collector: Callable[..., WorkerResult] = collect_root,
                 timeout_seconds: float = 10.0) -> None:
        if (type(rows) is not tuple or len(rows) > MAX_ROOTS
                or any(type(row) is not StaticRoot for row in rows)
                or type(timeout_seconds) not in (int, float)
                or not isfinite(timeout_seconds)
                or not 0 < timeout_seconds <= 30):
            raise ValueError("invalid bounded fleet bootstrap")
        if not callable(collector):
            raise ValueError("collector must be callable")
        self.workspace = Path(workspace)
        self.scheduler = ObservationScheduler(max_inflight=2, max_pending=MAX_ROOTS)
        self._rows: dict[str, StaticRoot] = {}
        self._held: dict[str, str] = {}
        for row in rows:
            if (not ENROLLMENT.fullmatch(row.enrollment_id)
                    or not FACTORY.fullmatch(row.factory_id)
                    or row.enrollment_id in self._rows):
                raise ValueError("invalid or duplicate fleet identity")
            # Scheduler checks Windows path aliases as well as duplicate IDs.
            self.scheduler.register(row.enrollment_id, row.factory_id, row.canonical_path)
            self._rows[row.enrollment_id] = row
            if row.state in ("conflict", "incompatible"):
                self._held[row.enrollment_id] = row.state
        self.pump = ObservationPump(
            self.scheduler,
            lambda token, timeout: collector(self.workspace, token, timeout),
            timeout_seconds,
        )
        for enrollment in self._rows:
            self.refresh(enrollment)

    def refresh(self, enrollment: str):
        if enrollment not in self._rows:
            raise KeyError(enrollment)
        if enrollment in self._held:
            return None
        return self.pump.enqueue(enrollment, "summary")

    def poll(self, now: float):
        return self.pump.poll(now)

    def states(self, now: float) -> tuple[tuple[str, str, str], ...]:
        """No paths, untrusted aliases, raw records or guest output in display."""
        result = []
        for enrollment, row in self._rows.items():
            if enrollment in self._held:
                status = self._held[enrollment]
            else:
                status, _ = self.scheduler.view(enrollment, "summary", now)
            result.append((enrollment[-8:], row.factory_id[-8:], status))
        return tuple(result)

    def close(self):
        self.pump.close()


def make_app(workspace: Path, *,
             loader: Callable[..., tuple[StaticRoot, ...]] = collect_static,
             collector: Callable[..., WorkerResult] = collect_root):
    """Build the selected, source-verified Textual host UI (read-only)."""
    from textual.app import App, ComposeResult
    from textual.widgets import Static
    from edf006_textual_probe import verify_installed_runtime_source

    verify_installed_runtime_source()
    workspace = Path(workspace)

    class FleetApp(App[None]):
        CSS = "#surface { width: 100%; height: 100%; overflow: hidden; }"
        BINDINGS = [("r", "refresh_fleet", "Refresh"), ("q", "quit", "Quit")]

        def __init__(self):
            super().__init__()
            self._loader_pool: ThreadPoolExecutor | None = None
            self._bootstrap: Future | None = None
            self.fleet: FleetSession | None = None
            self.bootstrap_state = "starting"
            self.last_poll = None

        def compose(self) -> ComposeResult:
            yield Static("EDF-006 read-only static fleet / initializing", id="surface",
                         markup=False)

        def on_mount(self):
            # Even the initial whole-fleet discovery is never a TUI-loop call.
            self._loader_pool = ThreadPoolExecutor(
                max_workers=1, thread_name_prefix="edf006-bootstrap"
            )
            self._bootstrap = self._loader_pool.submit(
                loader, workspace, timeout=BOOTSTRAP_DEADLINE
            )
            self.set_interval(0.05, self._tick)
            self._show()

        def _tick(self):
            if self.bootstrap_state == "starting" and self._bootstrap.done():
                try:
                    rows = self._bootstrap.result()
                    self.fleet = FleetSession(rows, workspace, collector)
                    self.bootstrap_state = "ready"
                except Exception:
                    # Do not print exceptions, root paths, stdout or secrets.
                    self.bootstrap_state = "refused"
            if self.fleet is not None:
                self.last_poll = self.fleet.poll(time.monotonic())
            self._show()

        def _show(self):
            lines = [
                "EDF-006 STATIC MULTI-ROOT MONITOR / NOT PHYSICAL-TUI PASS",
                "READ ONLY / NO VM COMMANDS / q quit / r refresh",
                "Bootstrap: " + self.bootstrap_state,
            ]
            if self.fleet is not None:
                lines.extend(
                    f"enr ...{enr} / fct ...{factory}: {state}"
                    for enr, factory, state in self.fleet.states(time.monotonic())
                )
            else:
                lines.append("Static registry discovery pending or refused")
            self.query_one("#surface", Static).update("\n".join(lines))

        def action_refresh_fleet(self):
            if self.fleet is not None:
                for enrollment in self.fleet._rows:
                    self.fleet.refresh(enrollment)
            self._show()

        def on_unmount(self):
            if self.fleet is not None:
                self.fleet.close()
            if self._loader_pool is not None:
                # A native subprocess has its own deadline; never block exit.
                self._loader_pool.shutdown(wait=False, cancel_futures=True)

    return FleetApp


async def headless_smoke():
    """Actual Textual event loop + asynchronous two-root session, synthetic I/O.

    This explicitly cannot prove native terminal presentation or WHPX.
    """
    import asyncio
    from edf006_readonly_bridge import StaticRoot

    def row(char: str, state: str = "current"):
        return StaticRoot("enr_" + char * 32, "fct_" + char * 32,
                          "fct_" + char * 32, "C:/fixtures/" + char, char,
                          state, "synthetic", "synthetic")

    def seed(path, timeout):
        assert timeout == BOOTSTRAP_DEADLINE
        return (row("a"), row("b"), row("c", "conflict"))

    def collect(path, token, timeout):
        assert timeout == 10.0 and token.kind == "summary"
        if token.enrollment.endswith("a" * 32):
            return WorkerResult("unreachable")
        return WorkerResult("current", ("Static identity, not READY",))

    app = make_app(Path("C:/synthetic"), loader=seed, collector=collect)()
    async with app.run_test(size=(80, 24)) as pilot:
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            await asyncio.sleep(0.05)
            await pilot.pause()
            if (app.bootstrap_state == "ready" and app.fleet is not None
                    and [r[2] for r in app.fleet.states(time.monotonic())]
                    == ["unreachable", "current", "conflict"]):
                break
        else:
            raise AssertionError("two-root Textual observation did not converge")
        await pilot.press("r")
        await pilot.pause()
        screen = str(app.query_one("#surface").render())
        if ("PHYSICAL-TUI PASS" not in screen or
                "READ ONLY" not in screen or
                app.fleet.scheduler.active_count > 2):
            raise AssertionError("read-only UI or bounded worker state absent")
    return {
        "schemaVersion": 1, "evidence": "FAST-CI-HEADLESS",
        "physical_tui": False, "live_instances_observed": False,
        "bootstrap": "synthetic", "peer_states": ["unreachable", "current", "conflict"],
        "input_to_visible_frame_p95_ms": None,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path)
    parser.add_argument("--headless-smoke", action="store_true")
    args = parser.parse_args(argv)
    if args.headless_smoke:
        import asyncio
        print(json.dumps(asyncio.run(headless_smoke()), sort_keys=True))
        return 0
    if args.workspace is None or not args.workspace.is_absolute():
        parser.error("--workspace must be an explicit absolute portable manager workspace")
    make_app(args.workspace)().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
