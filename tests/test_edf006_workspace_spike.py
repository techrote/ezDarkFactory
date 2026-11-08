"""SOURCE/FAST-CI portable workspace one-writer tests, not PHYSICAL-TUI."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_workspace_spike import (PortableWorkspace, WorkspaceBusy,
                                    WorkspaceInvalid, SESSION_MAX_BYTES)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.folder = Path(self.tmp.name) / "portable-manager"
        self.folder.mkdir()
        self.default = {"schemaVersion": 1, "hidden": []}

    def test_explicit_existing_absolute_folder_only(self):
        with self.assertRaises(WorkspaceInvalid):
            PortableWorkspace(Path("relative"))
        with self.assertRaises(WorkspaceInvalid):
            PortableWorkspace(self.folder / "missing")
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_read_only_never_creates_registry_or_session(self):
        with PortableWorkspace(self.folder) as workspace:
            self.assertEqual(workspace.read_session(), self.default)
            with self.assertRaises(PermissionError):
                workspace.save_session(self.default)
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_writer_is_exclusive_and_observer_remains_read_only(self):
        with PortableWorkspace(self.folder, writer=True) as owner:
            owner.save_session({"schemaVersion": 1, "hidden": ["logs"]})
            with self.assertRaises(WorkspaceBusy):
                PortableWorkspace(self.folder, writer=True)
            with PortableWorkspace(self.folder) as observer:
                self.assertEqual(observer.read_session()["hidden"], ["logs"])
                with self.assertRaises(PermissionError):
                    observer.save_session(self.default)
        with PortableWorkspace(self.folder, writer=True) as next_owner:
            self.assertEqual(next_owner.read_session()["hidden"], ["logs"])

    def test_cross_process_writer_conflict_and_release(self):
        src = str(Path(__file__).resolve().parents[1] / "tools")
        script = ("import sys;sys.path.insert(0,sys.argv[2]);"
                  "from edf006_workspace_spike import PortableWorkspace;"
                  "PortableWorkspace(__import__('pathlib').Path(sys.argv[1]),writer=True)")
        with PortableWorkspace(self.folder, writer=True):
            result = subprocess.run([sys.executable, "-c", script, str(self.folder), src],
                                    capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("WorkspaceBusy", result.stderr)
        result = subprocess.run([sys.executable, "-c", script, str(self.folder), src],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_abrupt_writer_exit_releases_os_lock(self):
        src = str(Path(__file__).resolve().parents[1] / "tools")
        script = ("import sys;sys.path.insert(0,sys.argv[2]);"
                  "from edf006_workspace_spike import PortableWorkspace;"
                  "w=PortableWorkspace(__import__('pathlib').Path(sys.argv[1]),writer=True);"
                  "print('locked',flush=True);sys.stdin.read()")
        child = subprocess.Popen([sys.executable, "-c", script, str(self.folder), src],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), "locked")
            with self.assertRaises(WorkspaceBusy):
                PortableWorkspace(self.folder, writer=True)
        finally:
            child.kill()
            child.communicate(timeout=10)
        with PortableWorkspace(self.folder, writer=True) as next_owner:
            self.assertTrue(next_owner.writer)

    def test_safe_start_ignores_good_session_without_changing_it(self):
        with PortableWorkspace(self.folder, writer=True) as owner:
            saved = {"schemaVersion": 1, "hidden": ["fleet", "logs"]}
            owner.save_session(saved)
            self.assertEqual(owner.read_session(), saved)
            self.assertEqual(owner.read_session(safe_start=True), self.default)
            self.assertEqual(owner.read_session(), saved)

    def test_corrupt_oversized_and_unknown_session_fails_to_safe_defaults(self):
        path = self.folder / "session.json"
        for raw in (b"{broken", b"\xff", b'{}', b'{"schemaVersion":true,"hidden":[]}',
                    b'{"schemaVersion":2,"hidden":[]}', b'{"schemaVersion":1,"hidden":["x","x"]}',
                    b'{"schemaVersion":1,"hidden":["escape\\u001b"]}',
                    b'{"schemaVersion":1,"hidden":[],"hidden":["logs"]}', b"x" * (SESSION_MAX_BYTES + 1)):
            with self.subTest(raw=raw[:25]):
                path.write_bytes(raw)
                with PortableWorkspace(self.folder) as observer:
                    self.assertEqual(observer.read_session(), self.default)
                self.assertEqual(path.read_bytes(), raw)

    def test_rejected_save_preserves_previous_bytes(self):
        with PortableWorkspace(self.folder, writer=True) as owner:
            owner.save_session({"schemaVersion": 1, "hidden": ["fleet"]})
            before = (self.folder / "session.json").read_bytes()
            for invalid in ({"schemaVersion": True, "hidden": []},
                            {"schemaVersion": 1, "hidden": ["x", "x"]},
                            {"schemaVersion": 1, "hidden": ["a/b"]},
                            {"schemaVersion": 1, "hidden": [], "factory_id": "fake"}):
                with self.subTest(invalid=invalid):
                    with self.assertRaises(ValueError):
                        owner.save_session(invalid)
                    self.assertEqual((self.folder / "session.json").read_bytes(), before)

    def test_all_manager_state_classes_remain_separate(self):
        (self.folder / "config.json").write_text('{"userTheme":"dark"}')
        (self.folder / "registry.json").write_text('{"registered":[]}')
        (self.folder / "journal.json").write_text('{"operations":[]}')
        before = {name: (self.folder / name).read_bytes()
                  for name in ("config.json", "registry.json", "journal.json")}
        with PortableWorkspace(self.folder, writer=True) as owner:
            owner.save_session(self.default)
        self.assertEqual(before, {name: (self.folder / name).read_bytes() for name in before})
        self.assertFalse((self.folder / "runtime").exists())

    def test_session_symlink_is_never_followed(self):
        outside = Path(self.tmp.name) / "other.json"
        outside.write_text('{"schemaVersion":1,"hidden":["secret"]}')
        try:
            (self.folder / "session.json").symlink_to(outside)
        except (OSError, NotImplementedError):
            self.assertFalse((self.folder / "session.json").is_symlink())
            return  # Native symlink creation unavailable; no skip in FAST-CI.
        with PortableWorkspace(self.folder, writer=True) as owner:
            self.assertEqual(owner.read_session(), self.default)
            with self.assertRaises(WorkspaceInvalid):
                owner.save_session(self.default)
        self.assertIn("secret", outside.read_text())


if __name__ == "__main__":
    unittest.main()
