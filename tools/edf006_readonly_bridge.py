"""EDF-006 bounded read-only bridge to EDF-005 *static* manager observations.

This does not observe live instance state, dispatch typed mutations, start VMs,
or render a terminal. Run collect_static() on a worker, NEVER on the UI thread.
A registered workspace is optional; direct factory-by-path remains EDF-005's job.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
import json
import ntpath
from pathlib import Path
import re
import subprocess
import unicodedata
from typing import Callable

MAX_BYTES = 256 * 1024
MAX_ROOTS = 128
ENROLLMENT = re.compile(r"enr_[a-f0-9]{32}\Z")
FACTORY = re.compile(r"fct_[a-f0-9]{32}\Z")
STATES = frozenset({"current", "stale", "unknown", "unreachable", "incompatible", "conflict"})
FIELDS = frozenset({
    "schemaVersion", "enrollment_id", "alias", "canonical_path", "factory_id",
    "observed_factory_id", "api", "state", "inventory_state", "last_known",
    "observed_at", "reason",
})


class StaticReadError(ValueError):
    """Malformed/unavailable snapshot; retain prior data as non-current."""


@dataclass(frozen=True)
class StaticRoot:
    enrollment_id: str
    factory_id: str
    observed_factory_id: str | None
    canonical_path: str
    alias: str
    state: str
    observed_at: str
    reason: str

    # There is intentionally no VM state/READY field here. EDF-005's static
    # reader always reports unknown instance inventory and stale last-known data.
    inventory_state: str = "unknown"


def _distinct(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise StaticReadError("duplicate snapshot JSON member")
        result[key] = value
    return result


def _invalid_number(_: str) -> None:
    raise StaticReadError("non-finite JSON number")


def _visible(value: str, maximum: int) -> str:
    """Strip terminal/OSC/C0/C1 controls from untrusted display metadata."""
    return "".join("\N{REPLACEMENT CHARACTER}" if unicodedata.category(char) in {"Cc", "Cf", "Cs"} else char
                   for char in value[:maximum])


def parse_static(payload: bytes) -> tuple[StaticRoot, ...]:
    """Validate the exact EDF-005 static-root envelope, never live VM inventory."""
    if not isinstance(payload, bytes) or not payload or len(payload) > MAX_BYTES:
        raise StaticReadError("missing or oversized static snapshot")
    try:
        data = json.loads(payload.decode("utf-8-sig"),
                          object_pairs_hook=_distinct, parse_constant=_invalid_number)
    except (UnicodeError, ValueError) as exc:
        raise StaticReadError("invalid static snapshot JSON") from exc
    if (type(data) is not dict or set(data) != {"schemaVersion", "kind", "records"}
            or type(data["schemaVersion"]) is not int or data["schemaVersion"] != 1
            or data["kind"] != "edf005-static-roots"
            or not isinstance(data["records"], list)
            or len(data["records"]) > MAX_ROOTS):
        raise StaticReadError("unsupported static snapshot envelope")

    roots: list[StaticRoot] = []
    enrollment_ids: set[str] = set()
    canonical_paths: set[str] = set()
    for record in data["records"]:
        if not isinstance(record, dict) or set(record) != FIELDS:
            raise StaticReadError("unrecognised static observation schema")
        enrollment = record["enrollment_id"]
        factory = record["factory_id"]
        observed = record["observed_factory_id"]
        path = record["canonical_path"]
        alias = record["alias"]
        state = record["state"]
        observed_at = record["observed_at"]
        reason = record["reason"]
        api = record["api"]
        previous = record["last_known"]
        if (not isinstance(enrollment, str) or not ENROLLMENT.fullmatch(enrollment)
                or not isinstance(factory, str) or not FACTORY.fullmatch(factory)
                or (observed is not None and
                    (not isinstance(observed, str) or not FACTORY.fullmatch(observed)))
                or not isinstance(path, str) or not 0 < len(path) <= 4096
                or any(unicodedata.category(c) in {"Cc", "Cf", "Cs"} for c in path)
                or not isinstance(alias, str) or len(alias) > 128
                or not isinstance(state, str) or state not in STATES
                or not isinstance(observed_at, str)
                or not 0 < len(observed_at) <= 128
                or any(unicodedata.category(c) in {"Cc", "Cf", "Cs"} for c in observed_at)
                or not isinstance(reason, str)
                or record["inventory_state"] != "unknown"
                or type(record["schemaVersion"]) is not int
                or record["schemaVersion"] != 1
                or not isinstance(previous, dict)
                or previous.get("factory_id") != factory
                or previous.get("freshness") != "stale"
                or type(previous.get("api_major")) is not int
                or type(previous.get("api_minor")) is not int
                or not isinstance(previous.get("verified_at"), str)
                or (api is not None and
                    (not isinstance(api, dict) or type(api.get("major")) is not int
                     or type(api.get("minor")) is not int))):
            raise StaticReadError("malformed static observation or false freshness")
        if state == "current" and (observed != factory or api is None
                                   or api["major"] != 1 or api["minor"] != 0):
            raise StaticReadError("unverified current identity or incompatible API")
        path_key = ntpath.normcase(ntpath.normpath(path))
        if enrollment in enrollment_ids or path_key in canonical_paths:
            raise StaticReadError("duplicate enrollment or canonical path")
        enrollment_ids.add(enrollment)
        canonical_paths.add(path_key)
        roots.append(StaticRoot(enrollment, factory, observed, path,
                                _visible(alias, 128), state, observed_at,
                                _visible(reason, 512)))

    # Defend against a truncated/malformed adapter conflict result. Both sides
    # are held even if one row incorrectly claims 'current'.
    counts: dict[str, int] = {}
    for root in roots:
        if root.observed_factory_id is not None and root.state in {"current", "conflict"}:
            key = root.observed_factory_id
            counts[key] = counts.get(key, 0) + 1
    return tuple(replace(root, state="conflict", reason="Duplicate reachable factory identity")
                 if root.observed_factory_id is not None
                 and counts.get(root.observed_factory_id, 0) > 1
                 and root.state == "current" else root
                 for root in roots)


def collect_static(workspace: Path, *, timeout: float = 10.0,
                   runner: Callable[..., object] = subprocess.run) -> tuple[StaticRoot, ...]:
    """Run the *trusted checkout's* EDF-005 read adapter, never candidate code.

    The OS subprocess is bounded by timeout; Python's run() kills and waits on
    timeout. It still buffers child output until exit: MAX_BYTES is an output
    validation cap, not a pre-allocation cap. Run this only on a worker.
    """
    workspace = Path(workspace)
    trusted_script = Path(__file__).resolve().parents[1] / "scripts" / "Invoke-Edf006StaticObservation.ps1"
    if (not workspace.is_absolute() or workspace.is_symlink()
            or not workspace.is_dir() or not trusted_script.is_file()
            or trusted_script.is_symlink() or not 0 < timeout <= 30):
        raise StaticReadError("invalid workspace, trusted adapter or deadline")
    command = ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
               "-File", str(trusted_script), "-Workspace", str(workspace)]
    try:
        completed = runner(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise StaticReadError("trusted static adapter unavailable or timed out") from exc
    if completed.returncode != 0:
        raise StaticReadError("trusted static adapter refused the observation")
    return parse_static(completed.stdout)
