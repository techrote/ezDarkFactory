"""EDF-006 real thread scheduling, with inert fixture readers only.

These tests prove event-loop nonblocking behavior; not live EDF-005 roots,
Windows Terminal presentation or real QEMU/WHPX evidence.
"""

import sys
from pathlib import Path
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_observation_spike import ObservationScheduler
from edf006_worker_pump import ObservationPump, WorkerResult


class PumpTests(unittest.TestCase):
    def setUp(self):
        self.s = ObservationScheduler(max_inflight=2, max_pending=16)
        for n in range(3):
            self.s.register(f"e{n}", f"f{n}", f"C:/fixtures/{n}")
        self.pumps = []

    def tearDown(self):
        for pump in self.pumps:
            pump.close()

    def make_pump(self, collector, **options):
        pump = ObservationPump(self.s, collector, **options)
        self.pumps.append(pump)
        return pump

    def _until(self, pump, predicate, deadline=3.0):
        end = time.monotonic() + deadline
        while time.monotonic() < end:
            result = pump.poll(time.monotonic())
            if predicate(result):
                return result
            time.sleep(.002)
        self.fail("worker did not finish in bounded test time")

    def test_normal_dispatch_publication_and_exact_timeout(self):
        seen = []
        def collect(token, timeout):
            seen.append((token.enrollment, token.kind, timeout))
            return WorkerResult("current", ("read-only",))
        pump = self.make_pump(collect, timeout_seconds=2.5)
        pump.enqueue("e0", "summary")
        started = pump.poll(time.monotonic())
        self.assertEqual((started.launched, started.active), (1, 1))
        end = self._until(pump, lambda p: p.finished == 1)
        self.assertEqual((end.published, end.failed_closed, end.active), (1, 0, 0))
        self.assertEqual(seen, [("e0", "summary", 2.5)])
        self.assertEqual(self.s.view("e0", "summary", time.monotonic())[0], "current")

    def test_blocked_root_does_not_block_ui_or_other_root(self):
        gate = threading.Event()
        entered = threading.Event()
        def collect(token, timeout):
            if token.enrollment == "e0":
                entered.set()
                gate.wait(2.0)  # inert simulated stall; unblocked in finally
            return WorkerResult("current", (token.enrollment,))
        pump = self.make_pump(collect)
        try:
            pump.enqueue("e0", "summary")
            pump.enqueue("e1", "summary")
            self.assertEqual(pump.poll(time.monotonic()).launched, 2)
            self.assertTrue(entered.wait(1.0))
            start = time.monotonic()
            self._until(pump, lambda p: self.s.view("e1", "summary", time.monotonic())[0] == "current")
            self.assertLess(time.monotonic() - start, 1.0)
            self.assertEqual(self.s.view("e0", "summary", time.monotonic())[0], "unknown")
            start = time.monotonic()
            for _ in range(100):
                pump.poll(time.monotonic())
            self.assertLess(time.monotonic() - start, 0.5)
        finally:
            gate.set()
        self._until(pump, lambda p: p.active == 0)

    def test_same_root_second_class_waits_without_starving_third_root(self):
        slow = threading.Event()
        entered = threading.Event()
        def collect(token, timeout):
            if token.enrollment == "e0" and token.kind == "summary":
                entered.set()
                slow.wait(2)
            return WorkerResult("current", (token.kind,))
        pump = self.make_pump(collect)
        try:
            pump.enqueue("e0", "summary")
            pump.poll(time.monotonic())
            self.assertTrue(entered.wait(1))
            pump.enqueue("e0", "logs")
            pump.enqueue("e1", "instances")
            self.assertEqual(pump.poll(time.monotonic()).launched, 1)
            self._until(pump, lambda p: self.s.view("e1", "instances", time.monotonic())[0] == "current")
            self.assertEqual(self.s.view("e0", "logs", time.monotonic())[0], "unknown")
            self.assertEqual(self.s.active_count, 1)
        finally:
            slow.set()
        self._until(pump, lambda p: self.s.view("e0", "logs", time.monotonic())[0] == "current")

    def test_error_and_bad_response_fail_closed_and_free_capacity(self):
        for bad in (lambda: (_ for _ in ()).throw(RuntimeError("secret path")),
                    lambda: WorkerResult("current", ("x" * 8193,)),
                    lambda: WorkerResult("READY", ()),
                    lambda: ["not immutable"]):
            with self.subTest(bad=bad):
                pump = self.make_pump(lambda token, timeout: bad())
                pump.enqueue("e0", "summary")
                pump.poll(time.monotonic())
                result = self._until(pump, lambda p: p.finished == 1)
                self.assertEqual((result.failed_closed, result.active), (1, 0))
                self.assertEqual(self.s.view("e0", "summary", time.monotonic())[0],
                                 "unreachable")
                pump.close()

    def test_failed_refresh_preserves_prior_records_as_noncurrent(self):
        responses = iter([WorkerResult("current", ("old",)),
                          WorkerResult("bad-state", ("new",))])
        pump = self.make_pump(lambda token, timeout: next(responses))
        pump.enqueue("e0", "summary")
        pump.poll(time.monotonic())
        self._until(pump, lambda p: p.finished == 1)
        pump.enqueue("e0", "summary")
        pump.poll(time.monotonic())
        self._until(pump, lambda p: p.finished == 1)
        self.assertEqual(self.s.view("e0", "summary", time.monotonic()),
                         ("unreachable", ("old",)))

    def test_refresh_coalescing_discards_obsolete_completed_result(self):
        gate = threading.Event()
        entered = threading.Event()
        def collect(token, timeout):
            if token.serial == 1:
                entered.set()
                gate.wait(2)
            return WorkerResult("current", (f"rev-{token.serial}",))
        pump = self.make_pump(collect)
        try:
            pump.enqueue("e0", "summary")
            pump.poll(time.monotonic())
            self.assertTrue(entered.wait(1))
            pump.enqueue("e0", "summary")
        finally:
            gate.set()
        self._until(pump, lambda p: p.dropped == 1)
        self.assertEqual(self.s.view("e0", "summary", time.monotonic())[0], "unknown")
        self._until(pump, lambda p: self.s.view("e0", "summary", time.monotonic())[0] == "current")
        self.assertEqual(self.s.view("e0", "summary", time.monotonic())[1], ("rev-2",))

    def test_unregister_reenroll_late_reply_cannot_republish(self):
        gate = threading.Event()
        entered = threading.Event()
        def collect(token, timeout):
            if token.root_epoch == 1:
                entered.set()
                gate.wait(2)
            return WorkerResult("current", (str(token.root_epoch),))
        pump = self.make_pump(collect)
        try:
            pump.enqueue("e0", "summary")
            pump.poll(time.monotonic())
            self.assertTrue(entered.wait(1))
            self.s.unregister("e0")
            self.s.register("e0", "f0", "D:/relocated")
            pump.enqueue("e0", "summary")
            self.assertEqual(pump.poll(time.monotonic()).launched, 0)
        finally:
            gate.set()
        self._until(pump, lambda p: p.dropped == 1)
        self._until(pump, lambda p: self.s.view("e0", "summary", time.monotonic())[0] == "current")
        self.assertEqual(self.s.view("e0", "summary", time.monotonic())[1], ("3",))

    def test_queue_bounds_and_close_prevent_extra_launch(self):
        self.s = ObservationScheduler(max_inflight=1, max_pending=1)
        self.s.register("one", "f-one", "C:/one")
        self.s.register("two", "f-two", "C:/two")
        gate = threading.Event()
        pump = self.make_pump(lambda token, timeout: (gate.wait(2), WorkerResult("current"))[1])
        try:
            self.assertIsNotNone(pump.enqueue("one", "summary"))
            self.assertIsNone(pump.enqueue("two", "summary"))
            self.assertEqual(pump.poll(time.monotonic()).launched, 1)
            pump.close()
            with self.assertRaises(RuntimeError):
                pump.enqueue("one", "summary")
            with self.assertRaises(RuntimeError):
                pump.poll(time.monotonic())
            self.assertEqual(self.s.active_count, 1)  # never prematurely reaped
        finally:
            gate.set()

    def test_invalid_budgets_refused_before_worker_submission(self):
        for invalid in (float("nan"), float("inf"), 0, -1, 31, True, "2"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    ObservationPump(self.s, lambda token, timeout: WorkerResult("current"), invalid)
        pump = self.make_pump(lambda token, timeout: WorkerResult("current"))
        for invalid in (float("nan"), float("inf"), -1, True, "1"):
            with self.subTest(clock=invalid):
                with self.assertRaises(ValueError):
                    pump.poll(invalid)
        self.assertEqual(self.s.active_count, 0)


if __name__ == "__main__":
    unittest.main()
