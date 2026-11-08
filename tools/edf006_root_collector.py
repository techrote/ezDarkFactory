"""EDF-006 independently bounded static identity reads, one enrolled root per child.

This is a read-only adapter for ObservationPump, not a live instance inventory.
A 'current' summary proves only compatible static *factory identity* at the
observation instant; typed control must still revalidate fleet identity and
revision before any effect. No candidate executable/script is launched.
"""

from __future__ import annotations

from math import isfinite
import ntpath
from pathlib import Path
import subprocess
from typing import Callable

if __package__:
    from .edf006_bounded_process import BoundedCaptureError, run_bounded
    from .edf006_observation_spike import Request
    from .edf006_readonly_bridge import ENROLLMENT, FACTORY, StaticReadError, parse_static
    from .edf006_worker_pump import WorkerResult
else:
    from edf006_bounded_process import BoundedCaptureError, run_bounded
    from edf006_observation_spike import Request
    from edf006_readonly_bridge import ENROLLMENT, FACTORY, StaticReadError, parse_static
    from edf006_worker_pump import WorkerResult


def collect_root(workspace: Path, token: Request, timeout_seconds: float,
                 *, runner: Callable[..., object] = run_bounded) -> WorkerResult:
    """Collect only the token's enrolled root using trusted EDF-005 code.

    The registered root path comes from the trusted portable manager registry,
    never from the token or candidate code. The child is hard-deadline and
    output-bound by run_bounded. This function must run on a worker thread.
    Only 'summary' is supported; there is no inferred VM inventory/logs.
    """
    if (type(token) is not Request or not ENROLLMENT.fullmatch(token.enrollment)
            or not FACTORY.fullmatch(token.factory_id)
            or type(token.root_epoch) is not int or token.root_epoch < 1
            or type(token.serial) is not int or token.serial < 1
            or type(token.canonical_path) is not str
            or not 0 < len(token.canonical_path) <= 4096
            or not ntpath.isabs(token.canonical_path)
            or any(ord(c) < 32 or ord(c) == 127 for c in token.canonical_path)
            or token.kind not in {"summary", "instances", "logs"}
            or type(timeout_seconds) not in (int, float)
            or not isfinite(timeout_seconds) or not 0 < timeout_seconds <= 30):
        raise StaticReadError("invalid root observation request or deadline")
    # The accepted EDF-005 static bridge cannot establish live instances/logs.
    # Fail closed without even launching a process for unsupported classes.
    if token.kind != "summary":
        return WorkerResult("unreachable")
    try:
        workspace = Path(workspace)
    except (TypeError, ValueError) as exc:
        raise StaticReadError("invalid portable manager workspace") from exc
    trusted_script = (Path(__file__).resolve().parents[1] / "scripts" /
                      "Invoke-Edf006RootObservation.ps1")
    if (not workspace.is_absolute() or workspace.is_symlink()
            or not workspace.is_dir() or not trusted_script.is_file()
            or trusted_script.is_symlink()):
        raise StaticReadError("invalid workspace or trusted root adapter")
    argv = ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-File",
            str(trusted_script), "-Workspace", str(workspace),
            "-ExpectedCanonicalPath", token.canonical_path,
            "-EnrollmentId", token.enrollment]
    try:
        completed = runner(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout_seconds, check=False)
    except (OSError, subprocess.TimeoutExpired, BoundedCaptureError) as exc:
        raise StaticReadError("trusted root observation unavailable or timed out") from exc
    if completed.returncode != 0:
        raise StaticReadError("trusted root observation refused")
    records = parse_static(completed.stdout)
    if (len(records) != 1 or records[0].enrollment_id != token.enrollment
            or records[0].factory_id != token.factory_id
            or ntpath.normcase(ntpath.normpath(records[0].canonical_path))
            != ntpath.normcase(ntpath.normpath(token.canonical_path))):
        raise StaticReadError("root observation identity mismatch")
    root = records[0]
    if root.state == "current":
        return WorkerResult("current", (
            "Static factory identity: " + root.factory_id,
            "Instance inventory: unknown (not observed)",
        ))
    if root.state in {"conflict", "incompatible"}:
        return WorkerResult("incompatible")
    return WorkerResult("unreachable")
