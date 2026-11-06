"""Bounded single-child capture for the trusted EDF-006 static adapter.

Capture is deliberately capped *while reading*, not after subprocess.run has
buffered an untrusted amount of output. This does not promise to terminate
arbitrary grandchildren: the trusted static PowerShell adapter must not spawn
any. Use on a worker, never the UI thread. No shell or inherited stdin.
"""

from __future__ import annotations

import subprocess
import threading
import time

MAX_STDOUT_BYTES = 256 * 1024
MAX_STDERR_BYTES = 16 * 1024
CHUNK_SIZE = 8192


class BoundedCaptureError(ValueError):
    """The trusted adapter exceeded its output budget or could not be drained."""


def run_bounded(argv: list[str], *, stdout: int, stderr: int,
                timeout: float, check: bool = False) -> subprocess.CompletedProcess[bytes]:
    """Drop-in *restricted* subprocess.run replacement for the EDF-006 bridge.

    Reader threads independently drain both pipes to avoid a pipe deadlock.
    At most the configured bytes are retained in each channel. A child that
    exceeds either budget is killed/reaped rather than read into memory.
    """
    if (stdout != subprocess.PIPE or stderr != subprocess.PIPE or check
            or not isinstance(argv, list) or not argv
            or isinstance(timeout, bool) or not isinstance(timeout, (int, float))
            or not 0 < timeout <= 30):
        raise ValueError("unsupported bounded process invocation")

    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               shell=False)
    buffers = [bytearray(), bytearray()]
    limits = (MAX_STDOUT_BYTES, MAX_STDERR_BYTES)
    exceeded = threading.Event()
    errors: list[OSError] = []

    def drain(pipe, index: int) -> None:
        try:
            with pipe:
                while True:
                    chunk = pipe.read(CHUNK_SIZE)
                    if not chunk:
                        return
                    if len(buffers[index]) + len(chunk) > limits[index]:
                        exceeded.set()
                        return
                    buffers[index].extend(chunk)
        except OSError as exc:
            errors.append(exc)
            exceeded.set()

    threads = [threading.Thread(target=drain, args=(pipe, index), daemon=True)
               for index, pipe in enumerate((process.stdout, process.stderr))]
    for worker in threads:
        worker.start()
    deadline = time.monotonic() + timeout
    timed_out = False
    try:
        while True:
            if exceeded.is_set():
                break
            if process.poll() is not None and all(not t.is_alive() for t in threads):
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            exceeded.wait(min(remaining, 0.025))
    finally:
        if process.poll() is None:
            process.kill()
        try:
            process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            # Never wait indefinitely for a wedged child.
            timed_out = True
        for worker in threads:
            worker.join(timeout=0.2)

    if any(t.is_alive() for t in threads):
        raise BoundedCaptureError("trusted adapter streams could not be drained")
    if exceeded.is_set() or errors:
        raise BoundedCaptureError("trusted adapter output budget or pipe read failed")
    if timed_out:
        raise subprocess.TimeoutExpired(argv, timeout)
    return subprocess.CompletedProcess(argv, process.returncode,
                                       bytes(buffers[0]), bytes(buffers[1]))
