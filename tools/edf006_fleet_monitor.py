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
    ENROLLMENT, FACTORY, STATES, StaticRoot, collect_static,
)
from edf006_root_collector import collect_root
from edf006_worker_pump import ObservationPump, WorkerResult

MAX_ROOTS = 128
BOOTSTRAP_DEADLINE = 10.0
AUTO_REFRESH_SECONDS = 10.0  # bounded per-root retry cadence, not a completion SLA
REGISTRY_RELOAD_SECONDS = 30.0  # metadata-only; independent of root observations


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
        self._next_auto: dict[str, float | None] = {}
        self.pump = ObservationPump(
            self.scheduler,
            lambda token, timeout: collector(self.workspace, token, timeout),
            timeout_seconds,
        )
        self.reconcile(rows)

    @staticmethod
    def _validate_rows(rows: tuple[StaticRoot, ...]):
        """Validate the whole new registry BEFORE changing any live scheduler state."""
        if (type(rows) is not tuple or len(rows) > MAX_ROOTS
                or any(type(row) is not StaticRoot for row in rows)):
            raise ValueError("invalid bounded registry refresh")
        candidate: dict[str, StaticRoot] = {}
        validator = ObservationScheduler(max_inflight=2, max_pending=MAX_ROOTS)
        for row in rows:
            if (not ENROLLMENT.fullmatch(row.enrollment_id)
                    or not FACTORY.fullmatch(row.factory_id)
                    or row.state not in STATES or row.enrollment_id in candidate):
                raise ValueError("invalid or duplicate refreshed fleet identity")
            # Reject Windows-equivalent duplicate paths before any live mutation.
            validator.register(row.enrollment_id, row.factory_id, row.canonical_path)
            candidate[row.enrollment_id] = row
        counts: dict[str, int] = {}
        for row in rows:
            counts[row.factory_id] = counts.get(row.factory_id, 0) + 1
        held = {
            row.enrollment_id: ("conflict" if counts[row.factory_id] > 1 else row.state)
            for row in rows
            if counts[row.factory_id] > 1 or row.state in ("conflict", "incompatible")
        }
        return candidate, held

    def reconcile(self, rows: tuple[StaticRoot, ...], *,
                  refresh_unchanged: bool = True) -> None:
        """Apply fresh portable registry metadata without resurrecting stale reads.

        Changed/removed roots invalidate generations. Old worker threads retain
        physical slots until reaped; their late completions cannot publish into
        a relocated/re-keyed enrollment. Unchanged roots retain recent readings.
        A corrupt refresh is rejected atomically, leaving the previous model
        available only until the owning application fail-closes the session.
        """
        if type(refresh_unchanged) is not bool:
            raise ValueError("invalid registry refresh policy")
        candidate, held = self._validate_rows(rows)
        previous_auto = self._next_auto
        removed: set[str] = set()
        for enrollment, previous in tuple(self._rows.items()):
            current = candidate.get(enrollment)
            if (current is None or previous.factory_id != current.factory_id
                    or previous.canonical_path != current.canonical_path
                    or self._held.get(enrollment) != held.get(enrollment)):
                self.scheduler.unregister(enrollment)
                removed.add(enrollment)
        for enrollment, row in candidate.items():
            if enrollment not in self._rows or enrollment in removed:
                self.scheduler.register(enrollment, row.factory_id, row.canonical_path)
        self._rows = candidate
        self._held = held
        # A metadata-only automatic reload must not cancel slow-but-valid
        # observations or reset unchanged roots' retry clocks. Explicit r
        # retains its previous force-refresh semantics.
        self._next_auto = {
            key: (previous_auto[key] if key in previous_auto and key not in removed
                  else None)
            for key in candidate if key not in held
        }
        for enrollment in self._rows:
            if (enrollment not in held
                    and (refresh_unchanged or enrollment in removed
                         or enrollment not in previous_auto)):
                self.refresh(enrollment)

    def invalidate_registry(self) -> None:
        """Withdraw every old registration without releasing live worker slots.

        A malformed/unavailable registry must never leave prior 'current'
        observations on screen. Retain the pump so retries cannot spawn a
        second pool before the previous bounded workers have been reaped.
        """
        self.reconcile(())

    def refresh(self, enrollment: str):
        if enrollment not in self._rows:
            raise KeyError(enrollment)
        if enrollment in self._held:
            return None
        return self.pump.enqueue(enrollment, "summary")

    def poll(self, now: float):
        """Resample enrolled roots on a bounded cadence without UI waits.

        The bootstrap already enqueued one sample. Arm the next cycle on the
        first poll; if a worker is still running or its intent is queued, do
        not supersede that generation merely because its interval elapsed.
        A failed root is retried, not spun on every 50-ms Textual tick.
        """
        if type(now) not in (float, int) or not isfinite(now) or now < 0:
            raise ValueError("finite nonnegative observation clock required")
        for enrollment, due in tuple(self._next_auto.items()):
            if due is None:
                self._next_auto[enrollment] = now + AUTO_REFRESH_SECONDS
            elif (now >= due
                  and not self.scheduler.has_outstanding(enrollment, "summary")):
                self.refresh(enrollment)
                self._next_auto[enrollment] = now + AUTO_REFRESH_SECONDS
        return self.pump.poll(now)

    def states(self, now: float) -> tuple[tuple[str, str, str], ...]:
        """No paths, untrusted aliases, raw records or guest output in display."""
        result = []
        for enrollment, row in self._rows.items():
            if enrollment in self._held:
                status = self._held[enrollment]
            else:
                status, _ = self.scheduler.view(enrollment, "summary", now)
            result.append((enrollment[-8:], row.factory_id, status))
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
            self._reload_pending = False
            self._bootstrap_force_refresh = True
            self._next_registry_reload = 0.0
            self.last_poll = None

        def compose(self) -> ComposeResult:
            yield Static("EDF-006 read-only static fleet / initializing", id="surface",
                         markup=False)

        def on_mount(self):
            # All registry discovery/reconciliation runs away from the UI loop.
            self._loader_pool = ThreadPoolExecutor(
                max_workers=1, thread_name_prefix="edf006-bootstrap"
            )
            self._request_bootstrap()
            self.set_interval(0.05, self._tick)
            self._show()

        def _request_bootstrap(self, *, force_refresh=True):
            if self._loader_pool is None:
                return
            if self._bootstrap is not None:
                # Only an explicit request queues a second scan; automatic
                # cycles never build up behind a slow bounded loader.
                if force_refresh:
                    self._reload_pending = True
                return
            self._bootstrap_force_refresh = force_refresh
            self._next_registry_reload = time.monotonic() + REGISTRY_RELOAD_SECONDS
            self.bootstrap_state = "refreshing" if self.fleet is not None else "starting"
            self._bootstrap = self._loader_pool.submit(
                loader, workspace, timeout=BOOTSTRAP_DEADLINE
            )

        def _tick(self):
            if self._bootstrap is not None and self._bootstrap.done():
                finished = self._bootstrap
                self._bootstrap = None
                try:
                    rows = finished.result()
                    if self.fleet is None:
                        self.fleet = FleetSession(rows, workspace, collector)
                    else:
                        self.fleet.reconcile(
                            rows, refresh_unchanged=self._bootstrap_force_refresh
                        )
                    self.bootstrap_state = "ready"
                except Exception:
                    # A failed/invalid new registry cannot leave old 'current'
                    # claims visible as if the registration were still trusted.
                    if self.fleet is not None:
                        self.fleet.invalidate_registry()
                    self.bootstrap_state = "refused"
                if self._reload_pending:
                    self._reload_pending = False
                    self._request_bootstrap()
            # Automatic metadata-only reconciliation is independent of the
            # per-root 10-second observation cadence and cannot block the UI.
            if (self._bootstrap is None
                    and time.monotonic() >= self._next_registry_reload):
                self._request_bootstrap(force_refresh=False)
            if self.fleet is not None:
                self.last_poll = self.fleet.poll(time.monotonic())
            self._show()

        def _show(self):
            lines = [
                "EDF-006 STATIC MULTI-ROOT MONITOR / NOT PHYSICAL-TUI PASS",
                "READ ONLY / NO VM COMMANDS / q quit / r refresh",
                "Registry: " + self.bootstrap_state +
                (" / prior snapshot while revalidating"
                 if self.bootstrap_state == "refreshing" else ""),
            ]
            if self.fleet is not None and self.fleet._rows:
                lines.extend(
                    f"fct {factory} / enr ...{enr}: {state}"
                    for enr, factory, state in self.fleet.states(time.monotonic())
                )
            else:
                lines.append("Static registry discovery pending or refused")
            self.query_one("#surface", Static).update("\n".join(lines))

        def action_refresh_fleet(self):
            # A real registry reload, not merely a reread of cached enrollments.
            # Newly registered/moved/removed roots and resolved conflicts appear
            # without restarting the monitor. No candidate root access on UI.
            self._request_bootstrap()
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

    loads = [0]
    calls = []
    def seed(path, timeout):
        assert timeout == BOOTSTRAP_DEADLINE
        loads[0] += 1
        if loads[0] == 1:
            return (row("a"), row("b"), row("c", "conflict"))
        if loads[0] == 2:
            return (row("b"), row("d"))
        if loads[0] == 3:
            raise ValueError("PRIVATE-REGISTRY-DIAGNOSTIC")
        return (row("d"),)

    def collect(path, token, timeout):
        assert timeout == 10.0 and token.kind == "summary"
        calls.append(token.enrollment)
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
        initial_states = [r[2] for r in app.fleet.states(time.monotonic())]
        await pilot.press("r")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            await asyncio.sleep(.05)
            await pilot.pause()
            if (loads[0] == 2 and app.bootstrap_state == "ready"
                    and app.fleet is not None
                    and [x[1] for x in app.fleet.states(time.monotonic())]
                    == [row("b").factory_id, row("d").factory_id]
                    and [x[2] for x in app.fleet.states(time.monotonic())]
                    == ["current", "current"]):
                break
        else:
            raise AssertionError("registry refresh did not add/remove enrollments")
        await pilot.press("r")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            await asyncio.sleep(.05)
            await pilot.pause()
            if loads[0] == 3 and app.bootstrap_state == "refused":
                break
        else:
            raise AssertionError("failed registry refresh retained old fresh rows")
        screen = str(app.query_one("#surface").render())
        if (app.fleet is not None
                and app.fleet.states(time.monotonic())
                or "PRIVATE-REGISTRY-DIAGNOSTIC" in screen
                or "Static registry discovery pending or refused" not in screen):
            raise AssertionError("registry error exposed stale rows or diagnostics")
        await pilot.press("r")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            await asyncio.sleep(.05)
            await pilot.pause()
            if (loads[0] == 4 and app.bootstrap_state == "ready"
                    and app.fleet is not None
                    and [x[2] for x in app.fleet.states(time.monotonic())]
                    == ["current"]):
                break
        else:
            raise AssertionError("registry reload could not recover after refusal")
        screen = str(app.query_one("#surface").render())
        if ("PHYSICAL-TUI PASS" not in screen or
                "READ ONLY" not in screen or
                app.fleet.scheduler.active_count > 2):
            raise AssertionError("read-only UI or bounded worker state absent")
        # Force the timer without sleeping 30 seconds. The real Textual tick
        # reloads metadata, but unchanged roots must not be requeued.
        observations_before = calls.count(row("d").enrollment_id)
        app._next_registry_reload = 0.0
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            await asyncio.sleep(.05)
            await pilot.pause()
            if loads[0] == 5 and app.bootstrap_state == "ready":
                break
        else:
            raise AssertionError("periodic registry metadata reload did not execute")
        if (calls.count(row("d").enrollment_id) != observations_before
                or app.fleet.states(time.monotonic())[0][2] != "current"):
            raise AssertionError("unchanged registry auto reload superseded observation")
    return {
        "schemaVersion": 1, "evidence": "FAST-CI-HEADLESS",
        "physical_tui": False, "live_instances_observed": False,
        "bootstrap": "synthetic", "peer_states": initial_states,
        "registry_reload": "add-remove-refuse-recover",
        "periodic_registry_reload": "unchanged-preserved",
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
