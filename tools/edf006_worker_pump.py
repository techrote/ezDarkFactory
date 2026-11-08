"""EDF-006 bounded asynchronous adapter orchestration for a TUI event loop.

The event loop alone calls enqueue()/poll() and owns ObservationScheduler.
Worker threads execute only an injected, read-only, independently deadline-
bounded collector. They never touch the scheduler or mutate any factory.

This is an architectural spike, NOT a production per-root adapter, live VM
observation or native Windows Terminal latency proof. The collector MUST honor
its deadline, bound output before allocating it and never invoke candidate code.
A Python thread cannot interrupt a wedged collector; a real process collector
must enforce termination independently (e.g. run_bounded).
"""

from __future__ import annotations

from concurrent.futures import Future
from dataclasses import dataclass
from math import isfinite
import time
from typing import Callable

if __package__:
    from .edf006_observation_spike import ObservationScheduler, Request
    from .edf006_daemon_future import start_daemon_future
else:
    from edf006_observation_spike import ObservationScheduler, Request
    from edf006_daemon_future import start_daemon_future


@dataclass(frozen=True)
class WorkerResult:
    """Already validated, bounded read-only adapter data; never VM authority."""

    state: str
    records: tuple[str, ...] = ()


@dataclass(frozen=True)
class PollResult:
    """Diagnostic counts for one nonblocking main-thread poll."""

    finished: int
    published: int
    dropped: int
    failed_closed: int
    launched: int
    active: int
    pending: int


@dataclass(frozen=True)
class _CollectedSample:
    """Conservative sample time captured on the worker, not when UI harvests."""

    result: WorkerResult
    started_at: float


class ObservationPump:
    """Single-thread-owned scheduler/worker bridge with bounded in-flight work.

    collector(request, timeout_seconds) must perform a safe, finite read.
    This pump cannot force-stop an arbitrary Python thread. The trusted
    subprocess boundary is responsible for enforcing its real deadline.
    """

    def __init__(self, scheduler: ObservationScheduler,
                 collector: Callable[[Request, float], WorkerResult],
                 timeout_seconds: float = 10.0) -> None:
        if not isinstance(scheduler, ObservationScheduler) or not callable(collector):
            raise ValueError("scheduler and callable read-only collector required")
        if (type(timeout_seconds) not in (float, int)
                or not isfinite(timeout_seconds) or not 0 < timeout_seconds <= 30):
            raise ValueError("finite collector deadline required")
        self.scheduler = scheduler
        self._collector = collector
        self._timeout = float(timeout_seconds)
        self._futures: dict[Future[_CollectedSample], Request] = {}
        self._closed = False

    def enqueue(self, enrollment: str, kind: str) -> Request | None:
        """Queue bounded intent; never access a factory or launch a VM."""
        if self._closed:
            raise RuntimeError("observation pump closed")
        return self.scheduler.request(enrollment, kind)

    def _collect(self, token: Request) -> _CollectedSample:
        # Time is captured BEFORE the read. Its actual observation instant is
        # unknown within the read interval; the start is a conservative bound.
        # A suspended/blocked UI must not make an old sample freshly 'current'.
        started_at = time.monotonic()
        return _CollectedSample(self._collector(token, self._timeout), started_at)

    def poll(self, observed_at: float) -> PollResult:
        """Harvest only finished futures, then fill free worker slots.

        Call on the UI thread with a monotonic, nonnegative observation clock.
        This method never awaits a collector, including a timed-out one.
        """
        if self._closed:
            raise RuntimeError("observation pump closed")
        if (type(observed_at) not in (int, float)
                or not isfinite(observed_at) or observed_at < 0):
            raise ValueError("finite nonnegative observation clock required")
        finished = published = dropped = failed_closed = 0
        for future, token in tuple(self._futures.items()):
            if not future.done():
                continue
            del self._futures[future]
            finished += 1
            try:
                sample = future.result()  # done() guarantees this never waits
                if type(sample) is not _CollectedSample or type(sample.result) is not WorkerResult:
                    raise ValueError("unrecognised collector result")
                # A late UI poll can only age a sample, never renew freshness.
                # Clamp for a poll clock captured just before worker completion.
                sample_at = min(observed_at, sample.started_at)
                accepted = self.scheduler.complete(token, sample.result.state,
                                                    sample_at, sample.result.records)
            except Exception:
                # Do not include exception text, root path, raw stdout or guest
                # data in logs or the read model. Even a malformed completion
                # must relinquish its real slot, without publishing current.
                failed_closed += 1
                accepted = self.scheduler.complete(token, "unreachable", observed_at)
            if accepted:
                published += 1
            else:
                dropped += 1
        launched = 0
        for token in self.scheduler.dispatch():
            # Active ownership was registered by dispatch() before submission.
            # dispatch() already reserved at most max_inflight physical slots.
            # A daemon worker cannot make Python shutdown wait indefinitely
            # for a blocked external read; the child has its own deadline.
            future = start_daemon_future(
                lambda token=token: self._collect(token), name="edf006-readonly"
            )
            self._futures[future] = token
            launched += 1
        return PollResult(finished, published, dropped, failed_closed, launched,
                          self.scheduler.active_count, self.scheduler.pending_count)

    def close(self) -> None:
        """Stop new submissions without waiting on a potentially stuck adapter.

        The owning UI discards this pump/scheduler after close. A running
        collector is not considered cancelled or reaped; it must implement its
        own process deadline. No completed result is published after closing.
        """
        if not self._closed:
            self._closed = True
            for future in self._futures:
                future.cancel()  # running jobs remain owned until process exit
