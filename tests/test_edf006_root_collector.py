"""EDF-006 per-root static collector: trust, deadline, identity, and fairness.

Inert runner mocks exercise the source contract. Windows also executes a
real trusted PowerShell negative-path smoke; no physical terminal/VM evidence.
"""

import json
import sys
from pathlib import Path
from types import SimpleNamespace
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_observation_spike import ObservationScheduler, Request
from edf006_readonly_bridge import StaticReadError
from edf006_root_collector import collect_root
from edf006_worker_pump import ObservationPump

ENR_A = "enr_" + "a" * 32
ENR_B = "enr_" + "b" * 32
FCT_A = "fct_" + "a" * 32
FCT_B = "fct_" + "b" * 32


def token(enrollment=ENR_A, factory=FCT_A, kind="summary", serial=1):
    return Request(enrollment, factory, 1, kind, serial)


def payload(enrollment=ENR_A, factory=FCT_A, state="current", records=1):
    row = {
        "schemaVersion": 1, "enrollment_id": enrollment, "alias": "Alpha",
        "canonical_path": "C:\\fixtures\\alpha", "factory_id": factory,
        "observed_factory_id": factory, "api": {"major": 1, "minor": 0},
        "state": state, "inventory_state": "unknown",
        "last_known": {
            "factory_id": factory, "api_major": 1, "api_minor": 0,
            "verified_at": "2026-11-08T00:00:00Z", "freshness": "stale",
        },
        "observed_at": "2026-11-08T00:00:01Z", "reason": "Static only",
    }
    return json.dumps({"schemaVersion": 1, "kind": "edf005-static-roots",
                       "records": [row] * records}).encode()


class SingleRootCollectorTests(unittest.TestCase):
    def test_only_selected_enrollment_is_passed_as_argv_with_deadline(self):
        with tempfile.TemporaryDirectory(prefix="edf006 per-root ;") as folder:
            calls = []
            def fake_run(argv, **kwargs):
                calls.append((argv, kwargs))
                return SimpleNamespace(returncode=0, stdout=payload(), stderr=b"")
            result = collect_root(Path(folder), token(), 2.5, runner=fake_run)
            self.assertEqual(result.state, "current")
            self.assertEqual(result.records, (
                "Static factory identity: " + FCT_A,
                "Instance inventory: unknown (not observed)",
            ))
            argv, kwargs = calls[0]
            self.assertEqual(argv[:5], ["powershell.exe", "-NoLogo", "-NoProfile",
                                        "-NonInteractive", "-File"])
            self.assertTrue(argv[5].endswith("Invoke-Edf006RootObservation.ps1"))
            self.assertEqual(argv[-4:], ["-Workspace", folder, "-EnrollmentId", ENR_A])
            self.assertNotIn("-Command", argv)
            self.assertEqual(kwargs["timeout"], 2.5)
            self.assertIs(kwargs["check"], False)

    def test_result_must_match_exact_enrollment_and_factory_and_one_record(self):
        for response in (payload(ENR_B), payload(factory=FCT_B),
                         payload(records=0), payload(records=2), b"not JSON"):
            with self.subTest(response=response[:55]):
                with tempfile.TemporaryDirectory() as folder:
                    with self.assertRaises(StaticReadError):
                        collect_root(Path(folder), token(), 3,
                                     runner=lambda *a, **kw: SimpleNamespace(
                                         returncode=0, stdout=response, stderr=b""))

    def test_noncurrent_states_are_never_promoted_to_current(self):
        with tempfile.TemporaryDirectory() as folder:
            for state, expected in (("conflict", "incompatible"),
                                    ("incompatible", "incompatible"),
                                    ("stale", "unreachable"),
                                    ("unknown", "unreachable"),
                                    ("unreachable", "unreachable")):
                with self.subTest(state=state):
                    result = collect_root(Path(folder), token(), 3,
                                          runner=lambda *a, **kw: SimpleNamespace(
                                              returncode=0, stdout=payload(state=state),
                                              stderr=b""))
                    self.assertEqual((result.state, result.records), (expected, ()))

    def test_unsupported_classes_do_not_launch_unimplemented_live_reads(self):
        for kind in ("instances", "logs"):
            def forbidden(*a, **kw):
                self.fail("unsupported class launched a child")
            self.assertEqual(collect_root(Path("/unused"), token(kind=kind), 1,
                                          runner=forbidden).state, "unreachable")

    def test_invalid_inputs_and_refused_or_timed_out_child_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            seen = []
            def forbidden(*a, **kw):
                seen.append(1)
                raise AssertionError("must refuse before launching a child")
            for bad_token, timeout in (
                (token(enrollment="bad"), 1), (token(factory="bad"), 1),
                (token(kind="execute"), 1), (token(), 0),
                (token(), 31), (token(), float("nan")), (token(), True),
                (Request(ENR_A, FCT_A, True, "summary", 1), 1),
            ):
                with self.subTest(bad_token=bad_token, timeout=timeout):
                    with self.assertRaises(StaticReadError):
                        collect_root(Path(folder), bad_token, timeout, runner=forbidden)
            self.assertEqual(seen, [])
            with self.assertRaises(StaticReadError):
                collect_root(Path("relative"), token(), 1, runner=forbidden)
            with self.assertRaises(StaticReadError):
                collect_root(Path(folder), token(), 1, runner=lambda *a, **kw:
                             SimpleNamespace(returncode=2, stdout=payload(), stderr=b"secret"))
            def timed_out(*args, **kw):
                raise __import__("subprocess").TimeoutExpired(args[0], 1)
            with self.assertRaises(StaticReadError):
                collect_root(Path(folder), token(), 1, runner=timed_out)

    def test_actual_threaded_pump_one_blocked_root_does_not_stall_peer(self):
        with tempfile.TemporaryDirectory() as folder:
            slow = threading.Event()
            entered = threading.Event()
            def fake_run(argv, **kw):
                enrollment = argv[-1]
                if enrollment == ENR_A:
                    entered.set()
                    slow.wait(2.0)
                result = payload(enrollment=enrollment,
                                 factory=FCT_A if enrollment == ENR_A else FCT_B)
                return SimpleNamespace(returncode=0, stdout=result, stderr=b"")
            scheduler = ObservationScheduler(max_inflight=2)
            scheduler.register(ENR_A, FCT_A, "C:/fixtures/alpha")
            scheduler.register(ENR_B, FCT_B, "C:/fixtures/beta")
            pump = ObservationPump(scheduler, lambda t, timeout:
                                   collect_root(Path(folder), t, timeout, runner=fake_run))
            try:
                pump.enqueue(ENR_A, "summary")
                pump.enqueue(ENR_B, "summary")
                self.assertEqual(pump.poll(time.monotonic()).launched, 2)
                self.assertTrue(entered.wait(1))
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    pump.poll(time.monotonic())
                    if scheduler.view(ENR_B, "summary", time.monotonic())[0] == "current":
                        break
                    time.sleep(.005)
                self.assertEqual(scheduler.view(ENR_B, "summary", time.monotonic())[0],
                                 "current")
                self.assertEqual(scheduler.view(ENR_A, "summary", time.monotonic())[0],
                                 "unknown")
            finally:
                slow.set()
                pump.close()

    def test_trusted_powershell_source_and_windows_absent_enrollment(self):
        script = Path(__file__).resolve().parents[1] / "scripts" / "Invoke-Edf006RootObservation.ps1"
        source = script.read_text(encoding="utf-8")
        self.assertIn("Get-EzDarkFactoryCandidate -Root $entry.canonical_path", source)
        self.assertNotIn("Get-EzDarkFactoryManagerObservations", source)
        self.assertNotIn("Invoke-Expression", source)
        if sys.platform == "win32":
            # Hosted Windows runs the actual trusted module/child refusal path.
            with tempfile.TemporaryDirectory() as folder:
                (Path(folder) / "registry.json").write_text(
                    '{"schemaVersion":1,"roots":[]}', encoding="utf-8")
                with self.assertRaises(StaticReadError):
                    collect_root(Path(folder), token(), 10)
        else:
            # Linux only verifies source structure, never claims PowerShell execution.
            self.assertIn("EDF006_ROOT_STATIC_READ_REFUSED", source)


if __name__ == "__main__":
    unittest.main()
