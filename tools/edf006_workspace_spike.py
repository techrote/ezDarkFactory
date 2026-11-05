"""EDF-006 synthetic portable manager-workspace/one-writer pre-spike.

No factory control, discovery, terminal backend or VM mutation. This models
only optional manager convenience state; it is not EDF-006 native acceptance.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from typing import Any

SESSION_MAX_BYTES = 256 * 1024


class WorkspaceBusy(Exception):
    """An existing manager owns this optional workspace."""


class WorkspaceInvalid(Exception):
    """The chosen workspace cannot be safely used."""


def _lock(handle: Any) -> None:
    if os.name == "nt":
        import msvcrt
        handle.seek(0)
        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError as exc:
            raise WorkspaceBusy("manager workspace already has a writer") from exc
    else:
        import fcntl
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise WorkspaceBusy("manager workspace already has a writer") from exc


def _unlock(handle: Any) -> None:
    if os.name == "nt":
        import msvcrt
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _valid_session(document: Any) -> bool:
    return (isinstance(document, dict)
            and type(document.get("schemaVersion")) is int
            and document["schemaVersion"] == 1
            and set(document) == {"schemaVersion", "hidden"}
            and isinstance(document["hidden"], list)
            and len(document["hidden"]) <= 256
            and all(isinstance(x, str) and 0 < len(x) <= 128
                    and all(c.isascii() and (c.isalnum() or c in "_-.") for c in x)
                    for x in document["hidden"])
            and len(set(document["hidden"])) == len(document["hidden"]))


class PortableWorkspace:
    """Explicit path; cooperative OS-backed single writer; safe session fallback.

    Factory identity, VM state, operation receipts and authoritative manager
    registration belong to EDF-005 and are deliberately not written here.
    """

    def __init__(self, folder: Path, *, writer: bool = False):
        self.folder = Path(folder)
        self.writer = False
        self._handle: Any = None
        if not self.folder.is_absolute():
            raise WorkspaceInvalid("manager workspace needs an explicit absolute path")
        if self.folder.is_symlink() or not self.folder.is_dir():
            raise WorkspaceInvalid("manager workspace must be an existing ordinary directory")
        if writer:
            lock_path = self.folder / ".edf-manager-writer.lock"
            if lock_path.is_symlink():
                raise WorkspaceInvalid("writer lock cannot be a symlink")
            # The marker is permanent but the OS lock is released on process exit,
            # including abnormal termination. Lock contents are never authority.
            flags = os.O_RDWR | os.O_CREAT
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            fd = os.open(lock_path, flags, 0o600)
            handle = os.fdopen(fd, "r+b")
            try:
                _lock(handle)
            except BaseException:
                handle.close()
                raise
            self._handle = handle
            self.writer = True

    def close(self) -> None:
        if self._handle is not None:
            handle, self._handle = self._handle, None
            self.writer = False
            try:
                _unlock(handle)
            finally:
                handle.close()

    def __enter__(self) -> "PortableWorkspace":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def read_session(self, *, safe_start: bool = False) -> dict[str, Any]:
        """Corrupt/oversize/missing state gets safe defaults, not partial state.

        Safe start intentionally ignores any saved session. There is no factory
        registration or VM operation on this read path.
        """
        default: dict[str, Any] = {"schemaVersion": 1, "hidden": []}
        if safe_start:
            return default
        path = self.folder / "session.json"
        if path.is_symlink() or not path.is_file():
            return default
        try:
            if path.stat().st_size > SESSION_MAX_BYTES:
                return default
            with open(path, "rb") as source:
                content = source.read(SESSION_MAX_BYTES + 1)
            if len(content) > SESSION_MAX_BYTES:
                return default
            def distinct_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
                result: dict[str, Any] = {}
                for name, value in pairs:
                    if name in result:
                        raise ValueError("duplicate JSON member")
                    result[name] = value
                return result

            document = json.loads(content.decode("utf-8"),
                                  object_pairs_hook=distinct_pairs)
            if _valid_session(document):
                return document
        except (OSError, UnicodeError, ValueError):
            pass
        return default

    def save_session(self, document: dict[str, Any]) -> None:
        """Only an active writer can atomically replace a bounded session file."""
        if not self.writer or self._handle is None or self._handle.closed:
            raise PermissionError("manager session update requires workspace writer")
        if not _valid_session(document):
            raise ValueError("invalid session schema")
        payload = (json.dumps(document, sort_keys=True, ensure_ascii=True,
                              separators=(",", ":")) + "\n").encode("utf-8")
        if len(payload) > SESSION_MAX_BYTES:
            raise ValueError("session exceeds size cap")
        destination = self.folder / "session.json"
        if destination.is_symlink():
            raise WorkspaceInvalid("session destination cannot be a symlink")
        tmp: str | None = None
        try:
            with tempfile.NamedTemporaryFile(mode="wb", prefix=".session-",
                                             suffix=".tmp", dir=self.folder,
                                             delete=False) as stream:
                tmp = stream.name
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            if destination.is_symlink():
                raise WorkspaceInvalid("session destination changed to a symlink")
            os.replace(tmp, destination)
            tmp = None
        finally:
            if tmp is not None:
                os.unlink(tmp)
