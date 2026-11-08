"""Unjoined daemon futures for bounded, read-only EDF-006 observation jobs.

Only use behind the caller's separate concurrency and queue limits. The stock
ThreadPoolExecutor joins running threads at Python interpreter shutdown even
after shutdown(wait=False), which can prevent a terminal from returning when
a trusted adapter is stuck in an uninterruptible filesystem call.

Daemon status prevents a *Python thread* from indefinitely holding interpreter
exit. It does not terminate an external child: trusted collectors must still
enforce child deadlines and pipe caps. This is not a general-purpose executor.
"""
from __future__ import annotations

from concurrent.futures import Future
from threading import Thread
from typing import Callable, TypeVar

T = TypeVar("T")


def start_daemon_future(work: Callable[[], T], *, name: str) -> Future[T]:
    """Start one background read, preserving Future result/error semantics."""
    if not callable(work) or not isinstance(name, str) or not name:
        raise ValueError("callable job and thread name required")
    future: Future[T] = Future()

    def invoke() -> None:
        if not future.set_running_or_notify_cancel():
            return
        try:
            result = work()
        except BaseException as exc:
            future.set_exception(exc)
        else:
            future.set_result(result)

    Thread(target=invoke, name=name, daemon=True).start()
    return future
