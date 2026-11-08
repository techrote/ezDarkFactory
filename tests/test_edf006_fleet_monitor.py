"""EDF-006 real composition seam, with synthetic roots (not WHPX/physical UI)."""
from pathlib import Path
import sys
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_fleet_monitor import FleetSession
from edf006_readonly_bridge import StaticRoot
from edf006_worker_pump import WorkerResult


def row(char, state="current", path=None, factory=None):
    fct = factory or "fct_" + char * 32
    return StaticRoot("enr_" + char * 32, fct, fct,
                      path or "C:/fixtures/" + char, "alias", state, "now", "test")


def wait_until(session, predicate, seconds=2):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        session.poll(time.monotonic())
        if predicate():
            return
        time.sleep(.005)
    raise AssertionError("fleet did not converge")


class FleetMonitorTests(unittest.TestCase):
    def test_static_bootstrap_never_claims_current_without_root_read(self):
        entered = threading.Event()
        release = threading.Event()
        def collect(workspace, token, timeout):
            entered.set()
            release.wait(1)
            return WorkerResult("current")
        fleet = FleetSession((row("a"),), Path("C:/synthetic"), collect)
        try:
            self.assertEqual(fleet.states(time.monotonic())[0][2], "unknown")
            fleet.poll(time.monotonic())
            self.assertTrue(entered.wait(.5))
            self.assertEqual(fleet.states(time.monotonic())[0][2], "unknown")
        finally:
            release.set()
            fleet.close()

    def test_periodic_reobservation_has_bounded_cadence(self):
        serials = []
        def collect(workspace, token, timeout):
            serials.append(token.serial)
            return WorkerResult("current")
        fleet = FleetSession((row("a"),), Path("C:/synthetic"), collect)
        try:
            start = time.monotonic()
            self.assertEqual(fleet.poll(start).launched, 1)
            wait_until(fleet, lambda: fleet.scheduler.active_count == 0)
            self.assertEqual(serials, [1])
            self.assertEqual(fleet.poll(start + 9.9).launched, 0)
            self.assertEqual(fleet.poll(start + 10.1).launched, 1)
            wait_until(fleet, lambda: (fleet.scheduler.active_count == 0
                                      and len(serials) == 2))
            self.assertEqual(serials, [1, 2])
            for _ in range(25):
                fleet.poll(start + 10.2)
            self.assertEqual(serials, [1, 2])
            self.assertEqual(fleet.scheduler.pending_count, 0)
        finally:
            fleet.close()

    def test_periodic_retry_never_discards_inflight_result(self):
        entered, release = threading.Event(), threading.Event()
        serials = []
        def collect(workspace, token, timeout):
            serials.append(token.serial)
            if token.serial == 1:
                entered.set()
                release.wait(2)
            return WorkerResult("current")
        fleet = FleetSession((row("a"),), Path("C:/synthetic"), collect)
        try:
            start = time.monotonic()
            self.assertEqual(fleet.poll(start).launched, 1)
            self.assertTrue(entered.wait(.5))
            for dt in (11, 20, 31):
                self.assertEqual(fleet.poll(start + dt).launched, 0)
                self.assertEqual(fleet.scheduler.pending_count, 0)
                self.assertEqual(fleet.scheduler.active_count, 1)
            release.set()
            wait_until(fleet, lambda: fleet.scheduler.active_count == 0)
            self.assertEqual(serials, [1])
            self.assertEqual(fleet.poll(start + 31.1).launched, 1)
            wait_until(fleet, lambda: (fleet.scheduler.active_count == 0
                                      and len(serials) == 2))
            self.assertEqual(serials, [1, 2])
        finally:
            release.set()
            fleet.close()

    def test_one_blocked_root_allows_peer_and_refresh(self):
        entered = threading.Event()
        release = threading.Event()
        def collect(workspace, token, timeout):
            self.assertEqual(timeout, 10)
            if token.enrollment.endswith("a" * 32):
                entered.set()
                release.wait(1)
            return WorkerResult("current", ("Static identity, not READY",))
        fleet = FleetSession((row("a"), row("b")), Path("C:/synthetic"), collect)
        try:
            self.assertEqual(fleet.poll(time.monotonic()).launched, 2)
            self.assertTrue(entered.wait(.5))
            wait_until(fleet, lambda: fleet.states(time.monotonic())[1][2] == "current")
            self.assertEqual([r[2] for r in fleet.states(time.monotonic())],
                             ["unknown", "current"])
        finally:
            release.set()
        wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
        fleet.refresh("b" * 0 + "enr_" + "b" * 32)
        fleet.poll(time.monotonic())
        wait_until(fleet, lambda: fleet.scheduler.active_count == 0)
        fleet.close()

    def test_conflict_and_incompatibility_remain_held(self):
        seen = []
        def collect(workspace, token, timeout):
            seen.append(token.enrollment)
            return WorkerResult("current")
        fleet = FleetSession((row("a", "conflict"), row("b", "incompatible"),
                              row("c")), Path("C:/synthetic"), collect)
        try:
            fleet.poll(time.monotonic())
            wait_until(fleet, lambda: fleet.states(time.monotonic())[2][2] == "current")
            self.assertEqual([r[2] for r in fleet.states(time.monotonic())],
                             ["conflict", "incompatible", "current"])
            self.assertEqual(len(seen), 1)
            self.assertIsNone(fleet.refresh("enr_" + "a"*32))
        finally:
            fleet.close()

    def test_duplicate_factory_ids_hold_both_without_running(self):
        seen = []
        def collect(*args):
            seen.append(1)
            return WorkerResult("current")
        same = "fct_" + "f"*32
        fleet = FleetSession((row("a", factory=same), row("b", factory=same)),
                             Path("C:/synthetic"), collect)
        try:
            self.assertEqual(fleet.poll(time.monotonic()).launched, 0)
            self.assertEqual([r[2] for r in fleet.states(time.monotonic())],
                             ["conflict", "conflict"])
            self.assertFalse(seen)
        finally:
            fleet.close()

    def test_malformed_bootstrap_is_refused_without_worker_start(self):
        for roots in ((row("a"), row("b", path="c:\\FIXTURES\\a")),
                      (row("a"), row("a")),
                      (row("a"), row("b", factory="bad")),
                      tuple(row("a") for _ in range(129)),
                      [row("a")]):
            with self.subTest(roots=str(type(roots))):
                with self.assertRaises(ValueError):
                    FleetSession(roots, Path("C:/synthetic"), lambda *a: None)

    def test_full_factory_ids_remain_distinct_when_suffixes_collide(self):
        one = "fct_" + "a" * 24 + "deadbeef"
        two = "fct_" + "b" * 24 + "deadbeef"
        fleet = FleetSession((row("a", factory=one), row("b", factory=two)),
                             Path("C:/synthetic"),
                             lambda *a: WorkerResult("unreachable"))
        try:
            states = fleet.states(time.monotonic())
            self.assertEqual((states[0][1], states[1][1]), (one, two))
            self.assertNotEqual(states[0][1], states[1][1])
        finally:
            fleet.close()

    def test_stale_state_and_noncurrent_errors_never_become_ready(self):
        fleet = FleetSession((row("a", "stale"),),
                             Path("C:/synthetic"),
                             lambda *a: WorkerResult("unreachable"))
        try:
            fleet.poll(time.monotonic())
            wait_until(fleet, lambda: fleet.scheduler.active_count == 0)
            self.assertEqual(fleet.states(time.monotonic())[0][2], "unreachable")
        finally:
            fleet.close()


    def test_registry_refresh_add_remove_and_relocate_discards_late_result(self):
        entered, release = threading.Event(), threading.Event()
        calls = []
        a = "enr_" + "a"*32
        def collect(workspace, token, timeout):
            calls.append((token.enrollment, token.root_epoch))
            if token.enrollment == a and token.root_epoch == 1:
                entered.set()
                release.wait(1)
                return WorkerResult("incompatible")
            return WorkerResult("current")
        fleet = FleetSession((row("a"), row("b")), Path("C:/synthetic"), collect)
        try:
            fleet.poll(time.monotonic())
            self.assertTrue(entered.wait(.5))
            wait_until(fleet, lambda: fleet.states(time.monotonic())[1][2] == "current")
            fleet.reconcile((row("a", path="D:/relocated-a"), row("c")))
            self.assertEqual([r[2] for r in fleet.states(time.monotonic())],
                             ["unknown", "unknown"])
            wait_until(fleet, lambda: fleet.states(time.monotonic())[1][2] == "current")
            self.assertEqual([r[1] for r in fleet.states(time.monotonic())],
                             [row("a").factory_id, row("c").factory_id])
            release.set()
            wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
            self.assertGreater(len([x for x in calls if x[0] == a]), 1)
        finally:
            release.set()
            fleet.close()

    def test_registry_refresh_conflict_resolution_needs_fresh_read(self):
        shared = "fct_" + "d"*32
        fleet = FleetSession((row("a", factory=shared),
                              row("b", factory=shared)),
                             Path("C:/synthetic"),
                             lambda *args: WorkerResult("current"))
        try:
            self.assertEqual([r[2] for r in fleet.states(time.monotonic())],
                             ["conflict", "conflict"])
            fleet.reconcile((row("a", factory=shared),))
            self.assertEqual(fleet.states(time.monotonic())[0][2], "unknown")
            wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
        finally:
            fleet.close()

    def test_refresh_incompatible_invalidates_successful_old_read(self):
        fleet = FleetSession((row("a"),), Path("C:/synthetic"),
                             lambda *args: WorkerResult("current"))
        try:
            wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
            fleet.reconcile((row("a", state="incompatible"),))
            self.assertEqual(fleet.states(time.monotonic())[0][2], "incompatible")
            self.assertIsNone(fleet.refresh("enr_" + "a"*32))
            fleet.reconcile((row("a"),))
            self.assertEqual(fleet.states(time.monotonic())[0][2], "unknown")
            wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
        finally:
            fleet.close()

    def test_bad_refresh_is_atomic_and_preserves_existing_scheduler(self):
        fleet = FleetSession((row("a"),), Path("C:/synthetic"),
                             lambda *args: WorkerResult("current"))
        try:
            for bad in ((row("a"), row("b", path="c:\\FIXTURES\\a")),
                        (row("a"), row("a")),
                        (row("a"), row("b", state="invented")),
                        [row("a")]):
                with self.subTest(bad=repr(bad)):
                    with self.assertRaises(ValueError):
                        fleet.reconcile(bad)
                    self.assertEqual(len(fleet.states(time.monotonic())), 1)
            wait_until(fleet, lambda: fleet.states(time.monotonic())[0][2] == "current")
        finally:
            fleet.close()


    def test_invalidated_registry_keeps_old_busy_slot_until_reaped(self):
        started, release = threading.Event(), threading.Event()
        a = "enr_" + "a"*32
        def collect(workspace, token, timeout):
            if token.enrollment == a:
                started.set()
                release.wait(1)
                return WorkerResult("current")
            return WorkerResult("current")
        fleet = FleetSession((row("a"),), Path("C:/synthetic"), collect)
        try:
            self.assertEqual(fleet.poll(time.monotonic()).launched, 1)
            self.assertTrue(started.wait(.5))
            fleet.invalidate_registry()
            self.assertEqual(fleet.states(time.monotonic()), ())
            self.assertEqual(fleet.scheduler.active_count, 1)
            fleet.reconcile((row("b"), row("c")))
            first = fleet.poll(time.monotonic())
            self.assertEqual(first.launched, 1)
            self.assertEqual(first.active, 2)
            wait_until(fleet, lambda: any(
                x[2] == "current" for x in fleet.states(time.monotonic())))
            self.assertLessEqual(fleet.scheduler.active_count, 2)
            release.set()
            wait_until(fleet, lambda: all(
                x[2] == "current" for x in fleet.states(time.monotonic())))
        finally:
            release.set()
            fleet.close()


if __name__ == "__main__":
    unittest.main()
