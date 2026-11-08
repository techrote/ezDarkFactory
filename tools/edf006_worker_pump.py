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

from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from math import isfinite
from typing import Callable

if __package__:
    from .edf006_observation_spike import ObservationScheduler, Request
else:
    from edf006_observation_spike import ObservationScheduler, Request


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
        self._executor = ThreadPoolExecutor(max_workers=scheduler.max_inflight,
                                            thread_name_prefix="edf006-readonly")
        self._futures: dict[Future[WorkerResult], Request] = {}
        self._closed = False

    def enqueue(self, enrollment: str, kind: str) -> Request | None:
        """Queue bounded intent; never access a factory or launch a VM."""
        if self._closed:
            raise RuntimeError("observation pump closed")
        return self.scheduler.request(enrollment, kind)

    def _collect(self, token: Request) -> WorkerResult:
        # The only method run on a worker. Scheduler state never crosses into it.
        return self._collector(token, self._timeout)

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
                result = future.result()  # done() guarantees this never waits
                if type(result) is not WorkerResult:
                    raise ValueError("unrecognised collector result")
                accepted = self.scheduler.complete(token, result.state,
                                                    observed_at, result.records)
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
            self._futures[self._executor.submit(self._collect, token)] = token
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
            self._executor.shutdown(wait=False, cancel_futures=True)
