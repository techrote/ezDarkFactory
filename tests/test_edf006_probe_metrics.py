"""Deterministic EDF-006 read-to-flush telemetry, not PHYSICAL-TUI evidence."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_probe_metrics import ProbeMetrics, write_receipt


class ProbeMetricsTests(unittest.TestCase):
    def test_navigation_percentiles_are_bounded_upper_estimates(self):
        metrics = ProbeMetrics()
        for duration_ms in [0.1] * 19 + [80.3]:
            metrics.record("key", 10, 20, 20, 10 + int(duration_ms * 1_000_000))
        summary = metrics.summary()
        self.assertEqual(summary["event_kind_counts"]["key"], 20)
        self.assertEqual(summary["navigation_read_to_flush_ms"]["p50_upper_ms"], 1)
        self.assertEqual(summary["navigation_read_to_flush_ms"]["p95_upper_ms"], 1)
        self.assertEqual(summary["navigation_read_to_flush_ms"]["p99_upper_ms"], 81)
        self.assertEqual(summary["composition_ms"]["p95_upper_ms"], 1)

    def test_overflow_cannot_be_misrepresented_as_passing_latency(self):
        metrics = ProbeMetrics()
        metrics.record("press", 0, 0, 0, 5_000_000_000)
        value = metrics.summary()["navigation_read_to_flush_ms"]
        self.assertEqual(value["count"], 1)
        self.assertEqual(value["overflow_ge_1024ms"], 1)
        self.assertIsNone(value["p95_upper_ms"])

    def test_dropped_or_quit_event_is_counted_without_fake_frame(self):
        metrics = ProbeMetrics()
        metrics.record("key", 11)
        summary = metrics.summary()
        self.assertEqual(summary["event_kind_counts"]["key"], 1)
        self.assertEqual(summary["rendered_frames"], 0)
        self.assertIsNone(summary["read_to_flush_ms"]["p95_upper_ms"])

    def test_invalid_timing_and_unknown_kind_fail_closed(self):
        for args in [("key", 7, 6, 9, 10), ("key", 7, 9, 8, 10),
                     ("key", 7, 9, 10, 8), ("key", 5, 7),
                     ("not-normalized", 5)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                ProbeMetrics().record(*args)

    def test_fixed_storage_and_no_payload_values(self):
        metrics = ProbeMetrics()
        for _ in range(50000):
            metrics.record("move", 0, 0, 0, 50_000)
        summary = metrics.summary()
        self.assertEqual(summary["rendered_frames"], 50000)
        self.assertEqual(summary["navigation_read_to_flush_ms"]["count"], 0)
        self.assertEqual(len(metrics.flush.buckets), 1025)
        self.assertNotIn("raw_key", json.dumps(summary))
        self.assertEqual(summary["qualification"], "UNVERIFIED_NATIVE_DIAGNOSTIC")

    def test_opt_in_receipt_create_only_and_without_event_payload(self):
        metrics = ProbeMetrics()
        metrics.record("key", 1, 2, 3, 4)
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "native.json")
            write_receipt(path, metrics)
            data = json.loads(Path(path).read_text(encoding="utf-8"))
            self.assertEqual(data["schemaVersion"], 1)
            self.assertNotIn("C:\\", json.dumps(data))
            self.assertEqual(data["event_kind_counts"]["key"], 1)
            with self.assertRaises(FileExistsError):
                write_receipt(path, metrics)

    def test_relative_output_path_refused(self):
        with self.assertRaises(ValueError):
            write_receipt("receipt.json", ProbeMetrics())


if __name__ == "__main__":
    unittest.main()
