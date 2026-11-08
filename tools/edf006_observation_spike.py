"""Synthetic EDF-006 multi-root observation scheduler and read-model contract.

No threads, I/O, PowerShell calls, factory authority, or terminal rendering.
The eventual runtime drives dispatch() off the UI thread and calls complete()
from a bounded result channel. Completing a request does not cancel a worker.
"""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass, field
from math import isfinite
import ntpath


KINDS = frozenset({"summary", "instances", "logs"})
RESULT_STATES = frozenset({"current", "unreachable", "incompatible"})
DEFAULT_RECORD_CHAR_BUDGET = 2_000_000  # UTF-8/Rich output may allocate more than input size.


@dataclass(frozen=True)
class Request:
    enrollment: str
    factory_id: str
    root_epoch: int
    kind: str
    serial: int
    # Frozen enrolled locator; empty only in scheduler-only fixture tokens.
    canonical_path: str = ""

    @property
    def key(self) -> tuple[str, str]:
        return self.enrollment, self.kind


@dataclass(frozen=True)
class Observation:
    state: str
    observed_at: float
    records: tuple[str, ...]
    serial: int


@dataclass
class _Root:
    factory_id: str
    canonical_path: str
    epoch: int
    snapshots: dict[str, Observation] = field(default_factory=dict)


class ObservationScheduler:
    """Bounded FIFO intents with per-enrollment/class coalescing.

    Factory IDs and canonical paths are **verified fixture inputs**, not values
    discovered by this class. Identity collision blocks reads and publishes no
    results; actual mutation guards remain exclusively in the EDF-005 broker.
    """

    def __init__(self, max_inflight: int = 2, max_pending: int = 32,
                 max_records: int = 10_000,
                 max_record_chars: int = DEFAULT_RECORD_CHAR_BUDGET) -> None:
        if (type(max_inflight) is not int or max_inflight < 1
                or type(max_pending) is not int or max_pending < 1
                or type(max_records) is not int or max_records < 1
                or type(max_record_chars) is not int or max_record_chars < 1):
            raise ValueError("positive integer observation budgets required")
        self.max_inflight = max_inflight
        self.max_pending = max_pending
        self.max_records = max_records
        self.max_record_chars = max_record_chars
        self._epochs: dict[str, int] = {}
        self._roots: dict[str, _Root] = {}
        self._serials: dict[tuple[str, str], int] = {}
        self._pending: OrderedDict[tuple[str, str], Request] = OrderedDict()
        self._active: dict[tuple[str, str], Request] = {}

    @property
    def pending_count(self) -> int:
        return len(self._pending)

    @property
    def active_count(self) -> int:
        return len(self._active)

    def register(self, enrollment: str, factory_id: str, canonical_path: str) -> None:
        """Admit an already verified root; registration has zero side effects."""
        # The accepted EDF-005 adapter supplies verified canonical Windows paths.
        # Compare their *locator* equivalence, not their display spelling:
        # C:/root, c:\\ROOT and paths with redundant separators are one root.
        path_key = ntpath.normcase(ntpath.normpath(canonical_path)) if isinstance(canonical_path, str) else ""
        if (not all(isinstance(v, str) and bool(v.strip())
                    for v in (enrollment, factory_id, canonical_path))
                or enrollment in self._roots
                or any(ntpath.normcase(ntpath.normpath(root.canonical_path)) == path_key
                       for root in self._roots.values())):
            raise ValueError("invalid or duplicate enrollment/path")
        epoch = self._epochs.get(enrollment, 0) + 1
        self._epochs[enrollment] = epoch
        self._roots[enrollment] = _Root(factory_id, canonical_path, epoch)
        # Collision history invalidates both copies even if conflict resolves
        # before a late collector finishes. Previously cached readings cannot
        # become fresh again solely because the duplicate was unregistered.
        if self._is_conflict(enrollment):
            for key, item in self._roots.items():
                if item.factory_id == factory_id:
                    self._epochs[key] += 1
                    item.epoch = self._epochs[key]
                    item.snapshots.clear()
        self._remove_conflicting_pending(factory_id)

    def unregister(self, enrollment: str) -> None:
        """Forget a registry record, never its factory data or active workers."""
        if enrollment not in self._roots:
            raise KeyError(enrollment)
        del self._roots[enrollment]
        self._epochs[enrollment] += 1
        self._discard_pending(enrollment)
        # Do not release worker capacity before an actual completion/termination.

    def _is_conflict(self, enrollment: str) -> bool:
        root = self._roots[enrollment]
        return sum(x.factory_id == root.factory_id for x in self._roots.values()) > 1

    def _discard_pending(self, enrollment: str) -> None:
        for key in tuple(self._pending):
            if key[0] == enrollment:
                del self._pending[key]

    def _remove_conflicting_pending(self, factory_id: str) -> None:
        for key in tuple(self._pending):
            root = self._roots.get(key[0])
            if root is not None and root.factory_id == factory_id and self._is_conflict(key[0]):
                del self._pending[key]

    def request(self, enrollment: str, kind: str) -> Request | None:
        """Queue at most one latest intent per root/kind; None means bounded refusal."""
        if kind not in KINDS:
            raise ValueError("unknown observation class")
        root = self._roots[enrollment]
        if self._is_conflict(enrollment):
            return None
        key = (enrollment, kind)
        if key not in self._pending and len(self._pending) >= self.max_pending:
            return None
        serial = self._serials.get(key, 0) + 1
        self._serials[key] = serial
        intent = Request(enrollment, root.factory_id, root.epoch, kind, serial,
                         root.canonical_path)
        # OrderedDict assignment preserves existing FIFO position; no flood priority.
        self._pending[key] = intent
        return intent

    def dispatch(self) -> tuple[Request, ...]:
        """Return work for an external executor; never run a collector here."""
        dispatched: list[Request] = []
        # Reserve at most one physical worker per enrollment. Without this,
        # summary+logs of a single hung root can consume the entire default
        # two-worker budget and starve a newly arriving healthy factory.
        # Count stale in-flight workers until they really complete/reap.
        busy_enrollments = {key[0] for key in self._active}
        for key, intent in tuple(self._pending.items()):
            if len(self._active) >= self.max_inflight:
                break
            if intent.enrollment in busy_enrollments:
                continue  # a different class is not another worker slot
            root = self._roots.get(intent.enrollment)
            if (root is None or root.epoch != intent.root_epoch
                    or root.factory_id != intent.factory_id
                    or self._is_conflict(intent.enrollment)):
                del self._pending[key]
                continue
            self._active[key] = intent
            busy_enrollments.add(intent.enrollment)
            del self._pending[key]
            dispatched.append(intent)
        return tuple(dispatched)

    def complete(self, intent: Request, state: str, observed_at: float,
                 records: tuple[str, ...] = ()) -> bool:
        """Acknowledge actual worker completion. False means drop obsolete result."""
        if state not in RESULT_STATES:
            raise ValueError("unrecognised status")
        if (not isinstance(observed_at, (int, float)) or not isfinite(observed_at)
                or observed_at < 0 or not isinstance(records, tuple)
                or len(records) > self.max_records
                or any(not isinstance(x, str) or len(x) > 8192 for x in records)
                or sum(len(x) for x in records) > self.max_record_chars):
            raise ValueError("invalid bounded observation fixture")
        key = intent.key
        if self._active.get(key) != intent:
            return False  # forged/duplicate/superseded token cannot release a slot
        del self._active[key]
        root = self._roots.get(intent.enrollment)
        if (root is None or root.factory_id != intent.factory_id
                or root.epoch != intent.root_epoch
                or self._serials.get(key) != intent.serial
                or self._is_conflict(intent.enrollment)):
            return False
        # Unavailable/incompatible never overwrite the last good records.
        previous = root.snapshots.get(intent.kind)
        safe_records = (records if state == "current" else
                        previous.records if previous is not None else ())
        root.snapshots[intent.kind] = Observation(state, float(observed_at),
                                                   safe_records, intent.serial)
        return True

    def view(self, enrollment: str, kind: str, now: float,
             freshness_seconds: float = 10.0) -> tuple[str, tuple[str, ...]]:
        """Always label stale retained records; never claim persisted READY/current."""
        if kind not in KINDS:
            raise ValueError("unknown observation class")
        if (not isinstance(now, (int, float)) or not isfinite(now)
                or not isinstance(freshness_seconds, (int, float))
                or not isfinite(freshness_seconds) or freshness_seconds < 0):
            raise ValueError("invalid freshness clock/budget")
        root = self._roots[enrollment]
        if self._is_conflict(enrollment):
            return "conflict", ()
        observation = root.snapshots.get(kind)
        if observation is None:
            return "unknown", ()
        if observation.state != "current":
            return observation.state, observation.records
        age = now - observation.observed_at
        if age < 0 or age > freshness_seconds:
            return "stale", observation.records
        return "current", observation.records
