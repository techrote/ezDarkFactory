"""Deterministic EDF-006 synthetic scheduling tests, not Windows Terminal proof."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_observation_spike import ObservationScheduler


class ObservationTests(unittest.TestCase):
    def setUp(self):
        self.scheduler = ObservationScheduler(max_inflight=2, max_pending=16)
        for i in range(3):
            self.scheduler.register(f"enr{i}", f"fct_{i}", f"C:/fixtures/root{i}")

    def test_registration_is_nonexecuting_and_duplicate_path_refused(self):
        with self.assertRaises(ValueError):
            self.scheduler.register("enr0", "new", "C:/fixtures/new")
        with self.assertRaises(ValueError):
            self.scheduler.register("enr4", "new", "C:/fixtures/root0")
        self.assertEqual((self.scheduler.active_count, self.scheduler.pending_count), (0, 0))
        self.scheduler.unregister("enr0")
        self.assertEqual(self.scheduler.active_count, 0)

    def test_queue_capacity_is_bounded_without_invalidating_rejected_request(self):
        s = ObservationScheduler(max_inflight=2, max_pending=1)
        s.register("a", "factory-a", "C:/a")
        s.register("b", "factory-b", "C:/b")
        first = s.request("a", "summary")
        self.assertIsNone(s.request("b", "summary"))
        self.assertEqual(s.pending_count, 1)
        self.assertEqual(s.dispatch(), (first,))
        self.assertTrue(s.complete(first, "current", 1.0, ("a",)))
        self.assertEqual(s.view("a", "summary", 1), ("current", ("a",)))

    def test_pending_refresh_coalesces_but_retains_fifo_position(self):
        first = self.scheduler.request("enr0", "summary")
        second = self.scheduler.request("enr1", "summary")
        latest = self.scheduler.request("enr0", "summary")
        self.assertGreater(latest.serial, first.serial)
        self.assertEqual(self.scheduler.pending_count, 2)
        self.assertEqual(self.scheduler.dispatch(), (latest, second))

    def test_superseded_inflight_result_does_not_publish_or_free_early(self):
        first = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        replacement = self.scheduler.request("enr0", "summary")
        self.assertEqual(self.scheduler.dispatch(), ())  # old worker still occupies slot
        self.assertFalse(self.scheduler.complete(first, "current", 1, ("obsolete",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 1), ("unknown", ()))
        self.assertEqual(self.scheduler.dispatch(), (replacement,))
        self.assertTrue(self.scheduler.complete(replacement, "current", 2, ("current",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 2), ("current", ("current",)))

    def test_duplicate_completions_cannot_release_another_request(self):
        first = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertTrue(self.scheduler.complete(first, "current", 1))
        later = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertFalse(self.scheduler.complete(first, "current", 2))
        self.assertEqual(self.scheduler.active_count, 1)
        self.assertTrue(self.scheduler.complete(later, "current", 2))

    def test_unregistration_and_reenrollment_rejects_late_worker(self):
        old = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.scheduler.unregister("enr0")
        self.scheduler.register("enr0", "fct_0", "D:/moved/root0")
        new = self.scheduler.request("enr0", "summary")
        self.assertEqual(self.scheduler.dispatch(), ())
        self.assertFalse(self.scheduler.complete(old, "current", 1, ("old",)))
        self.assertEqual(self.scheduler.dispatch(), (new,))
        self.assertTrue(self.scheduler.complete(new, "current", 2, ("new",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 2), ("current", ("new",)))

    def test_collision_holds_both_and_discards_inflight(self):
        first = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.scheduler.register("copy", "fct_0", "D:/copied/root0")
        self.assertEqual(self.scheduler.view("enr0", "summary", 0), ("conflict", ()))
        self.assertEqual(self.scheduler.view("copy", "summary", 0), ("conflict", ()))
        self.assertIsNone(self.scheduler.request("enr0", "summary"))
        self.assertFalse(self.scheduler.complete(first, "current", 1, ("unsafe",)))
        self.scheduler.unregister("copy")
        self.assertEqual(self.scheduler.view("enr0", "summary", 1), ("unknown", ()))

    def test_transient_identity_collision_invalidates_previous_success_and_worker(self):
        prior = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertTrue(self.scheduler.complete(prior, "current", 1, ("old-current",)))
        late = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.scheduler.register("copy", "fct_0", "D:/copied/root0")
        self.scheduler.unregister("copy")
        self.assertFalse(self.scheduler.complete(late, "current", 2, ("stale-after-conflict",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 2), ("unknown", ()))

    def test_10000_bounded_log_rows_and_large_payload_refusal(self):
        s = ObservationScheduler(max_inflight=2, max_pending=1, max_records=10_000)
        s.register("root", "fct", "C:/logs")
        token = s.request("root", "logs")
        s.dispatch()
        log_rows = tuple(f"line-{i}" for i in range(10_000))
        self.assertTrue(s.complete(token, "current", 1, log_rows))
        self.assertEqual(len(s.view("root", "logs", 1)[1]), 10_000)
        token = s.request("root", "logs")
        s.dispatch()
        for malicious_rows in (("x" * 8193,), log_rows + ("extra",)):
            with self.assertRaises(ValueError):
                s.complete(token, "current", 2, malicious_rows)
            self.assertEqual(s.active_count, 1)
        self.assertTrue(s.complete(token, "current", 2, ()))

    def test_collision_discards_waiting_intents(self):
        self.scheduler.request("enr0", "summary")
        self.scheduler.register("copy", "fct_0", "D:/copied/root0")
        self.assertEqual(self.scheduler.pending_count, 0)
        self.assertEqual(self.scheduler.dispatch(), ())

    def test_slow_root_does_not_block_other_dispatch_when_slot_available(self):
        slow = self.scheduler.request("enr0", "summary")
        fast = self.scheduler.request("enr1", "summary")
        self.assertEqual(self.scheduler.dispatch(), (slow, fast))
        # Slow worker is intentionally never completed; the UI-side model is nonblocking.
        self.assertTrue(self.scheduler.complete(fast, "current", 1, ("ready",)))
        third = self.scheduler.request("enr2", "summary")
        self.assertEqual(self.scheduler.dispatch(), (third,))
        self.assertTrue(self.scheduler.complete(third, "current", 2, ("ready",)))
        self.assertEqual(self.scheduler.active_count, 1)
        self.assertEqual(self.scheduler.view("enr2", "summary", 2), ("current", ("ready",)))

    def test_per_root_single_flight_even_for_distinct_classes(self):
        summary = self.scheduler.request("enr0", "summary")
        self.assertEqual(self.scheduler.dispatch(), (summary,))
        self.scheduler.request("enr0", "summary")
        instances = self.scheduler.request("enr0", "instances")
        other = self.scheduler.request("enr1", "summary")
        self.assertEqual(self.scheduler.dispatch(), (other,))
        self.assertEqual(self.scheduler.active_count, 2)
        self.assertEqual(self.scheduler.pending_count, 2)
        # An obsolete completion cannot publish but still releases its true slot.
        self.assertFalse(self.scheduler.complete(summary, "current", 1))
        refreshed = self.scheduler.dispatch()
        self.assertEqual(len(refreshed), 1)
        self.assertEqual(refreshed[0].enrollment, "enr0")
        self.assertEqual(self.scheduler.active_count, 2)
        self.assertEqual(self.scheduler.dispatch(), ())
        self.assertTrue(self.scheduler.complete(refreshed[0], "current", 2))
        self.assertEqual(self.scheduler.dispatch(), (instances,))
        self.assertTrue(self.scheduler.complete(instances, "current", 3))
        self.assertTrue(self.scheduler.complete(other, "current", 4))

    def test_two_slow_classes_on_one_root_cannot_starve_unrelated_roots(self):
        slow = self.scheduler.request("enr0", "summary")
        same_root_logs = self.scheduler.request("enr0", "logs")
        fast = self.scheduler.request("enr1", "summary")
        self.assertEqual(self.scheduler.dispatch(), (slow, fast))
        self.assertEqual(self.scheduler.pending_count, 1)
        self.assertTrue(self.scheduler.complete(fast, "current", 1, ("healthy",)))
        new_factory = self.scheduler.request("enr2", "summary")
        self.assertEqual(self.scheduler.dispatch(), (new_factory,))
        self.assertEqual(self.scheduler.view("enr1", "summary", 1),
                         ("current", ("healthy",)))
        self.assertTrue(self.scheduler.complete(new_factory, "current", 2))
        self.assertEqual(self.scheduler.dispatch(), ())
        self.assertEqual(self.scheduler.pending_count, 1)
        self.assertTrue(self.scheduler.complete(slow, "unreachable", 3))
        self.assertEqual(self.scheduler.dispatch(), (same_root_logs,))

    def test_windows_path_alias_cannot_register_same_root_twice(self):
        self.scheduler.register("new", "factory-new", r"C:\\Fixtures\\New\\.")
        with self.assertRaises(ValueError):
            self.scheduler.register("alias", "factory-other", "c:/fixtures/new")
        with self.assertRaises(ValueError):
            self.scheduler.register("alias", "factory-other", "C:/FIXTURES/root0/")
        self.assertEqual(self.scheduler.active_count, 0)

    def test_total_record_character_budget_does_not_retain_large_cache(self):
        s = ObservationScheduler(max_inflight=2, max_pending=4,
                                 max_records=10_000, max_record_chars=8)
        s.register("a", "f-a", "C:/a")
        token = s.request("a", "logs")
        self.assertEqual(s.dispatch(), (token,))
        with self.assertRaises(ValueError):
            s.complete(token, "current", 1, ("123456789",))
        self.assertEqual(s.active_count, 1)
        self.assertTrue(s.complete(token, "current", 2, ("1234", "5678")))
        self.assertEqual(s.view("a", "logs", 2), ("current", ("1234", "5678")))
        for invalid in (False, 0, -1, 1.5):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    ObservationScheduler(max_record_chars=invalid)

    def test_unknown_stale_unreachable_and_incompatible_are_distinct(self):
        self.assertEqual(self.scheduler.view("enr0", "summary", 10), ("unknown", ()))
        request = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertTrue(self.scheduler.complete(request, "current", 1, ("RUNNING-not-authority",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 11), ("current", ("RUNNING-not-authority",)))
        self.assertEqual(self.scheduler.view("enr0", "summary", 12), ("stale", ("RUNNING-not-authority",)))
        next_request = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertTrue(self.scheduler.complete(next_request, "unreachable", 13))
        self.assertEqual(self.scheduler.view("enr0", "summary", 13),
                         ("unreachable", ("RUNNING-not-authority",)))
        next_request = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        self.assertTrue(self.scheduler.complete(next_request, "incompatible", 14))
        self.assertEqual(self.scheduler.view("enr0", "summary", 14)[0], "incompatible")
        self.assertEqual(self.scheduler.view("enr0", "summary", 0)[0], "incompatible")

    def test_bad_status_or_clock_cannot_consume_active_slot(self):
        request = self.scheduler.request("enr0", "summary")
        self.scheduler.dispatch()
        for state, at, rows in (("READY", 1, ()), ("current", float("nan"), ()),
                                ("current", -1, ()), ("current", 1, ["mutable"])):
            with self.subTest(state=state, at=at):
                with self.assertRaises(ValueError):
                    self.scheduler.complete(request, state, at, rows)
                self.assertEqual(self.scheduler.active_count, 1)
        with self.assertRaises(ValueError):
            self.scheduler.view("enr0", "summary", float("nan"))
        self.assertTrue(self.scheduler.complete(request, "current", 1))

    def test_reference_scale_16_factories_128_rows_and_bounded_queue(self):
        s = ObservationScheduler(max_inflight=2, max_pending=16)
        for i in range(16):
            s.register(f"e{i}", f"f{i}", f"C:/roots/{i}")
            self.assertIsNotNone(s.request(f"e{i}", "instances"))
        self.assertEqual(s.pending_count, 16)
        self.assertIsNone(s.request("e0", "summary"))
        self.assertIsNotNone(s.request("e0", "instances"))  # coalesce without growth
        observed = []
        for _ in range(8):
            batch = s.dispatch()
            self.assertEqual(len(batch), 2)
            for token in batch:
                rows = tuple(f"instance-{token.enrollment}-{n}" for n in range(8))
                self.assertTrue(s.complete(token, "current", 1, rows))
                observed.extend(rows)
        self.assertEqual((s.pending_count, s.active_count), (0, 0))
        self.assertEqual(len(observed), 128)
        self.assertEqual(len(set(observed)), 128)


if __name__ == "__main__":
    unittest.main()
