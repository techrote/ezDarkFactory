"""EDF-006 EDF-005 static read bridge regression; not native terminal proof."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_readonly_bridge import (
    MAX_BYTES, MAX_ROOTS, StaticReadError, collect_static, parse_static,
)


def row(*, enrollment="a", factory="a", observed=None, state="current"):
    f = "fct_" + factory * 32
    return {
        "schemaVersion": 1,
        "enrollment_id": "enr_" + enrollment * 32,
        "alias": "Factory " + enrollment,
        "canonical_path": "C:/fixtures/" + enrollment,
        "factory_id": f,
        "observed_factory_id": f if observed is None else observed,
        "api": {"major": 1, "minor": 0},
        "state": state,
        "inventory_state": "unknown",
        "last_known": {
            "factory_id": f, "api_major": 1, "api_minor": 0,
            "verified_at": "2026-11-05T00:00:00Z", "freshness": "stale",
        },
        "observed_at": "2026-11-05T00:00:01Z",
        "reason": "Static identity only",
    }


def payload(*records):
    return json.dumps({
        "schemaVersion": 1, "kind": "edf005-static-roots", "records": records,
    }, separators=(",", ":")).encode("utf-8")


class StaticAdapterTests(unittest.TestCase):
    def test_exact_edf005_static_schema_is_read_only_not_vm_ready(self):
        roots = parse_static(payload(row()))
        self.assertEqual(len(roots), 1)
        self.assertEqual(roots[0].state, "current")
        self.assertEqual(roots[0].inventory_state, "unknown")
        self.assertFalse(hasattr(roots[0], "vm_ready"))
        self.assertFalse(hasattr(roots[0], "instance_id"))

    def test_empty_registry_is_valid_and_requires_no_candidate_execution(self):
        self.assertEqual(parse_static(payload()), ())

    def test_conflicting_reachable_factory_id_holds_both_registrations(self):
        a = row(enrollment="a")
        b = row(enrollment="b")
        b["observed_factory_id"] = a["factory_id"]
        b["factory_id"] = a["factory_id"]
        roots = parse_static(payload(a, b))
        self.assertEqual(tuple(x.state for x in roots), ("conflict", "conflict"))

    def test_current_plus_conflict_is_not_published_current(self):
        a, b = row(enrollment="a"), row(enrollment="b", state="conflict")
        b["observed_factory_id"] = a["factory_id"]
        roots = parse_static(payload(a, b))
        self.assertEqual(tuple(x.state for x in roots), ("conflict", "conflict"))

    def test_mismatched_current_identity_fails_closed(self):
        a = row()
        a["observed_factory_id"] = "fct_" + "b" * 32
        with self.assertRaises(StaticReadError):
            parse_static(payload(a))

    def test_bad_api_and_forged_inventory_refuse(self):
        for field, value in (
            ("api", {"major": 2, "minor": 0}),
            ("api", {"major": 1, "minor": 1}),
            ("inventory_state", "READY"),
            ("last_known", {"freshness": "current", "factory_id": "fct_" + "a" * 32,
                            "api_major": 1, "api_minor": 0, "verified_at": "now"}),
        ):
            with self.subTest(field=field, value=value):
                a = row()
                a[field] = value
                with self.assertRaises(StaticReadError):
                    parse_static(payload(a))

    def test_duplicate_enrollment_and_casefolded_path_refused(self):
        with self.assertRaises(StaticReadError):
            parse_static(payload(row(), row()))
        b = row(enrollment="b", factory="b")
        b["canonical_path"] = "c:\\FIXTURES\\A"
        with self.assertRaises(StaticReadError):
            parse_static(payload(row(), b))

    def test_unexpected_fields_schema_and_unknown_state_fail_closed(self):
        for bad in (
            {**row(), "ready": True},
            {**row(), "state": "READY"},
            {**row(), "state": []},
            {**row(), "schemaVersion": True},
            {**row(), "inventory_state": None},
        ):
            with self.subTest(bad=bad):
                with self.assertRaises(StaticReadError):
                    parse_static(payload(bad))
        with self.assertRaises(StaticReadError):
            parse_static(b'{"schemaVersion":2,"kind":"edf005-static-roots","records":[]}')

    def test_duplicate_json_keys_and_nonfinite_refused(self):
        with self.assertRaises(StaticReadError):
            parse_static(b'{"schemaVersion":1,"schemaVersion":1,"kind":"edf005-static-roots","records":[]}')
        with self.assertRaises(StaticReadError):
            parse_static(b'{"schemaVersion":1,"kind":"edf005-static-roots","records":NaN}')

    def test_corruption_size_and_count_limits(self):
        for bad in (b"", b"\xff", b"{", b" " * (MAX_BYTES + 1), "not bytes"):
            with self.subTest(bad=str(bad)[:15]):
                with self.assertRaises(StaticReadError):
                    parse_static(bad)
        with self.assertRaises(StaticReadError):
            parse_static(payload(*[row() for _ in range(MAX_ROOTS + 1)]))

    def test_control_sequences_never_survive_display_metadata(self):
        a = row()
        a["alias"] = "\x1b]52;c;unsafe\x07alias"
        a["reason"] = "\x1b[2Jerror\nnow"
        result = parse_static(payload(a))[0]
        for value in (result.alias, result.reason):
            self.assertNotIn("\x1b", value)
            self.assertNotIn("\x07", value)
            self.assertNotIn("\n", value)

    def test_unreachable_root_is_not_promoted_from_last_known(self):
        a = row(state="unreachable")
        a["observed_factory_id"] = None
        a["api"] = None
        result = parse_static(payload(a))[0]
        self.assertEqual(result.state, "unreachable")
        self.assertEqual(result.inventory_state, "unknown")

    def test_runner_uses_trusted_file_without_shell_or_profile(self):
        with tempfile.TemporaryDirectory(prefix="edf 006;root ") as workspace:
            seen = []
            def fake_run(argv, **kwargs):
                seen.append((argv, kwargs))
                return SimpleNamespace(returncode=0, stdout=payload(row()), stderr=b"")
            result = collect_static(Path(workspace), timeout=3.0, runner=fake_run)
            self.assertEqual(result[0].state, "current")
            argv, kwargs = seen[0]
            self.assertEqual(argv[:4], ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive"])
            self.assertEqual(argv[4], "-File")
            self.assertTrue(argv[5].endswith("Invoke-Edf006StaticObservation.ps1"))
            self.assertEqual(argv[-2:], ["-Workspace", workspace])
            self.assertNotIn("-Command", argv)
            self.assertEqual(kwargs["timeout"], 3.0)
            self.assertEqual(kwargs["check"], False)
            self.assertNotIn("shell", kwargs)

    def test_runner_failure_and_timeout_are_not_current(self):
        with tempfile.TemporaryDirectory() as workspace:
            with self.assertRaises(StaticReadError):
                collect_static(Path(workspace), runner=lambda *a, **k:
                               SimpleNamespace(returncode=2, stdout=payload(row()), stderr=b"secrets"))
            def timeout(*args, **kwargs):
                raise subprocess.TimeoutExpired(args[0], 3)
            with self.assertRaises(StaticReadError):
                collect_static(Path(workspace), runner=timeout)

    def test_invalid_workspace_and_timeout_execute_nothing(self):
        invoked = []
        def fake_run(*args, **kwargs):
            invoked.append(args)
            raise AssertionError("must not execute")
        with tempfile.TemporaryDirectory() as workspace:
            for path, timeout in ((Path("relative"), 1),
                                  (Path(workspace), 0),
                                  (Path(workspace), 31)):
                with self.assertRaises(StaticReadError):
                    collect_static(path, timeout=timeout, runner=fake_run)
            self.assertEqual(invoked, [])


    def test_path_and_timestamp_controls_refuse_but_unicode_labels_survive(self):
        a = row()
        a["alias"] = "Café"
        self.assertEqual(parse_static(payload(a))[0].alias, "Café")
        for key in ("canonical_path", "observed_at"):
            bad = row()
            bad[key] += "\x1b]52;clipboard\x07"
            with self.subTest(key=key):
                with self.assertRaises(StaticReadError):
                    parse_static(payload(bad))

    def test_actual_windows_powershell_static_endpoint_empty_registry(self):
        """Windows provenance CI runs the real checked-in EDF-005 module."""
        with tempfile.TemporaryDirectory(prefix="edf006-bridge-") as workspace:
            (Path(workspace) / "registry.json").write_text(
                '{"schemaVersion":1,"roots":[]}', encoding="utf-8")
            if sys.platform == "win32":
                self.assertEqual(collect_static(Path(workspace), timeout=15.0), ())
            else:
                # Linux exercises schema/bridge logic only. Never call this
                # physical Windows or PowerShell acceptance.
                self.assertEqual(parse_static(payload()), ())



if __name__ == "__main__":
    unittest.main()
