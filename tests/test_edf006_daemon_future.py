"""EDF-006 interpreter-exit tests for read-only observation worker shutdown.

Subprocess fixtures block only synthetic Python Events; no factory, network,
PowerShell or VM is accessed. This is FAST-CI, not physical terminal evidence.
"""
from pathlib import Path
import subprocess
import sys
import threading
import unittest

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from edf006_daemon_future import start_daemon_future


class DaemonFutureTests(unittest.TestCase):
    def test_preserves_result_exception_and_daemon_identity(self):
        def inspect_worker():
            worker = threading.current_thread()
            return worker.daemon, worker.name
        self.assertEqual(
            start_daemon_future(inspect_worker, name="edf006-check").result(timeout=2),
            (True, "edf006-check"),
        )
        def fail():
            raise ValueError("synthetic only")
        with self.assertRaisesRegex(ValueError, "synthetic only"):
            start_daemon_future(fail, name="edf006-fail").result(timeout=2)

    def test_rejects_invalid_invocations(self):
        for job, name in ((None, "read"), (lambda: None, ""),
                          (lambda: None, 42)):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    start_daemon_future(job, name=name)

    def _isolated_exit(self, script):
        # An ordinary non-daemon ThreadPoolExecutor blocks process shutdown
        # for the full 45-second synthetic wait even with shutdown(wait=False).
        # A genuinely non-joining worker exits promptly; timeout kills a
        # broken subprocess rather than hanging the entire CI job.
        completed = subprocess.run(
            [sys.executable, "-I", "-c", script, str(TOOLS)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8,
            check=False,
        )
        self.assertEqual(completed.returncode, 0,
                         completed.stderr.decode("utf-8", "replace")[-1000:])

    def test_closing_pump_does_not_join_blocked_root_worker_at_process_exit(self):
        script = """
import sys, threading, time
sys.path.insert(0, sys.argv[1])
from edf006_observation_spike import ObservationScheduler
from edf006_worker_pump import ObservationPump, WorkerResult
started = threading.Event()
blocked = threading.Event()
def collect(token, timeout):
    started.set()
    blocked.wait(45)
    return WorkerResult("current")
scheduler = ObservationScheduler(max_inflight=1, max_pending=2)
scheduler.register("enr", "fct", "C:/fixture")
pump = ObservationPump(scheduler, collect)
pump.enqueue("enr", "summary")
assert pump.poll(time.monotonic()).launched == 1
assert started.wait(2)
pump.close()
assert scheduler.active_count == 1
"""
        self._isolated_exit(script)

    def test_closing_bootstrap_does_not_join_blocked_registry_reader(self):
        # Same background future primitive is used by FleetApp's single
        # metadata loader. It must not hold terminal process teardown either.
        script = """
import sys, threading
sys.path.insert(0, sys.argv[1])
from edf006_daemon_future import start_daemon_future
started = threading.Event()
blocked = threading.Event()
def read_metadata():
    started.set()
    blocked.wait(45)
    return ()
future = start_daemon_future(read_metadata, name="edf006-bootstrap")
assert started.wait(2)
assert not future.cancel()  # already running; still must not join on exit
"""
        self._isolated_exit(script)


if __name__ == "__main__":
    unittest.main()
