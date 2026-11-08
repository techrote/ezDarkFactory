"""Real subprocess regression for EDF-006 bounded capture; no VM/TUI evidence."""

from pathlib import Path
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_bounded_process import (
    BoundedCaptureError, MAX_STDERR_BYTES, MAX_STDOUT_BYTES, run_bounded,
)


def invoke(source: str, *, timeout: float = 8.0):
    return run_bounded([sys.executable, "-c", source],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       timeout=timeout, check=False)


class BoundedProcessTests(unittest.TestCase):
    def test_normal_both_pipes_and_nonzero_exit(self):
        result = invoke("import sys;sys.stdout.buffer.write(b'ok');"
                        "sys.stderr.buffer.write(b'warn');sys.exit(4)")
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (4, b"ok", b"warn"))

    def test_exact_byte_budget_is_accepted(self):
        result = invoke(f"import sys;sys.stdout.buffer.write(b'x'*{MAX_STDOUT_BYTES});"
                        f"sys.stderr.buffer.write(b'y'*{MAX_STDERR_BYTES})")
        self.assertEqual((len(result.stdout), len(result.stderr)),
                         (MAX_STDOUT_BYTES, MAX_STDERR_BYTES))

    def test_stdout_overflow_kills_child_before_large_capture(self):
        started = time.monotonic()
        with self.assertRaises(BoundedCaptureError):
            invoke(f"import sys;sys.stdout.buffer.write(b'z'*{MAX_STDOUT_BYTES+8192});"
                   "sys.stdout.flush();__import__('time').sleep(20)")
        self.assertLess(time.monotonic() - started, 5)

    def test_stderr_overflow_kills_child(self):
        with self.assertRaises(BoundedCaptureError):
            invoke(f"import sys;sys.stderr.buffer.write(b'z'*{MAX_STDERR_BYTES+1})")

    def test_timeout_kills_blocked_child(self):
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            invoke("import time;time.sleep(20)", timeout=0.15)
        self.assertLess(time.monotonic() - started, 3)

    def test_concurrent_draining_prevents_pipe_deadlock(self):
        result = invoke("import os,sys;"
                        "sys.stdout.buffer.write(b'x'*65000);"
                        "sys.stderr.buffer.write(b'y'*6500)")
        self.assertEqual(len(result.stdout), 65000)
        self.assertEqual(len(result.stderr), 6500)

    def test_unsupported_mode_refused_before_spawn(self):
        with self.assertRaises(ValueError):
            run_bounded([sys.executable, "-c", "pass"], stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, check=True, timeout=1)
        with self.assertRaises(ValueError):
            run_bounded([sys.executable, "-c", "pass"], stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, timeout=float("nan"))


if __name__ == "__main__":
    unittest.main()
