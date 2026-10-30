"""EDF-003 immutable later-repair source provenance and software boundary tests."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import provenance as p
from edf_runtime_supersession import verified_supersession, PINNED

ADAPTED = frozenset({
    "scripts/Invoke-Edf003PrivateAclQualification.ps1",
    "scripts/Invoke-Edf003PrivateAclHosted.ps1",
    "tests/PrivateAclHosted.Tests.ps1",
    "scripts/Invoke-Edf003SoftwareQualification.ps1",
})

class Edf003RepairsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = p.ROOT
        cls.origin = p.GitRepository(Path(os.environ["EDF_TEST_EZVM"]))
        cls.edf001 = p.load_json(p.PROVENANCE / "manifest.json")
        cls.map = p.load_json(p.PROVENANCE / "edf003-repairs.json")

    def test_authenticated_source_set_and_actual_destination_git_blobs(self):
        records = self.map["records"]
        self.assertEqual(self.map["issue"], "EDF-003")
        self.assertEqual(self.map["evidence_class"], "SOURCE")
        self.assertFalse(self.map["original_historical_patch_bytes_recovered"])
        self.assertFalse(self.map["historical_patch_equivalence_claimed"])
        self.assertFalse(self.map["source_revisions"]["runtime_upstream_merged"])
        self.assertFalse(self.map["source_revisions"]["runtime_full_tcg_pass"])
        self.assertEqual(len(records), 13)
        source_names = {(row["source_id"], row["source_path"]) for row in records}
        self.assertEqual(len(source_names), 13)
        self.assertEqual(len({p.safe_relative(r["destination"]) for r in records}), 13)
        original = {(r["source_id"], r["source_path"]): r for r in self.edf001["files"]}
        permitted = {"ezvm-keys-repair", "ezvm-runtime-repair"}
        for row in records:
            with self.subTest(destination=row["destination"]):
                self.assertIn(row["source_id"], permitted)
                snapshot = original[(row["source_id"], row["source_path"])]
                self.assertEqual(snapshot["classification"], "later-repair-candidate")
                self.assertFalse(snapshot["edf002_import"])
                self.assertEqual(row["source_blob"], snapshot["git_blob"])
                self.assertEqual(row["source_sha256"], snapshot["sha256"])
                self.assertEqual(row["mode"], snapshot["mode"])
                source = next(s for s in self.edf001["sources"] if s["id"] == row["source_id"])
                self.assertEqual(row["source_commit"], source["commit"])
                self.assertEqual(row["source_tree"], source["tree"])
                raw = self.origin.file(row["source_commit"], row["source_path"])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row["source_sha256"])
                p.safe_relative(row["destination"])
                self.assertFalse(p.excluded(row["destination"]))
                actual = (self.root / row["destination"]).read_bytes()
                oid = p.run_git(self.root, "rev-parse", "HEAD:" + row["destination"]).decode("ascii").strip()
                if row["destination"] in PINNED:
                    self.assertTrue(verified_supersession(self.root, row["destination"], row["destination_blob"]))
                else:
                    self.assertEqual(oid, row["destination_blob"])
                self.assertEqual(p.run_git(self.root, "cat-file", "blob", oid), actual)

    def test_exact_namespace_rebrands_and_bounded_review_exceptions(self):
        records = self.map["records"]
        self.assertEqual({r["destination"] for r in records
                          if r["transformation"] == "reviewed-adaptation"}, ADAPTED)
        for row in records:
            if row["transformation"] == "reviewed-adaptation":
                continue
            with self.subTest(path=row["source_path"]):
                self.assertEqual(row["transformation"], "exact-rebrand")
                raw = self.origin.file(row["source_commit"], row["source_path"])
                expected = (raw.decode("utf-8").replace("EzVm", "EzDarkFactory")
                    .replace("EZVM", "EDF").replace("ezvm", "ezdarkfactory")).encode("utf-8")
                if row["destination"] in PINNED:
                    self.assertEqual(p.run_git(self.root, "cat-file", "blob", row["destination_blob"]), expected)
                    self.assertTrue(verified_supersession(self.root, row["destination"], row["destination_blob"]))
                else:
                    self.assertEqual((self.root / row["destination"]).read_bytes(), expected)

    def test_selected_runtime_has_no_legacy_capture_pipe_or_pid_kill(self):
        root = self.root
        source = (root / "src/EzDarkFactory/Runtime.ps1").read_text(encoding="utf-8")
        helper = (root / "src/EzDarkFactory/RuntimeProcess.cs").read_text(encoding="utf-8")
        acl = (root / "src/EzDarkFactory/Keys.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-EzDarkFactoryRuntimeProcessType", source)
        self.assertIn("StandardOutputPath", source)
        self.assertIn("Get-EzDarkFactoryRuntimeRemainingMilliseconds", source)
        self.assertIn("CreateProcessW", helper)
        self.assertIn("UpdateProcThreadAttribute", helper)
        self.assertIn('CreateFileW("NUL"', helper)
        self.assertIn("TerminateProcess(information.Process", helper)
        self.assertNotIn("GetProcessById(unknown", helper)
        self.assertNotIn("Set-Acl -LiteralPath $full", acl)
        self.assertIn("FileSystemAclExtensions", acl)
        self.assertIn("AccessControlSections]'Owner, Access'", acl)

    def test_standard_user_execution_refuses_untrusted_host_and_tcg_acceptance(self):
        hosted = (self.root / "scripts/Invoke-Edf003PrivateAclHosted.ps1").read_text(encoding="utf-8")
        qualification = (self.root / "scripts/Invoke-Edf003PrivateAclQualification.ps1").read_text(encoding="utf-8")
        native = (self.root / "scripts/Invoke-Edf003SoftwareQualification.ps1").read_text(encoding="utf-8")
        for expected in ("GITHUB_ACTIONS", "RUNNER_ENVIRONMENT", "New-LocalUser", "Remove-LocalUser", "Start-Process"):
            self.assertIn(expected, hosted)
        self.assertIn("7b829f8352a9fa30c965e57386965767c5969e0d", str(self.map["source_revisions"]["keys"]))
        self.assertIn("d49affee3624b81f952f68cb9c7ca5149d85e015", qualification)
        self.assertIn("SeSecurityPrivilege", qualification)
        self.assertIn("standardUserWhpxExecuted = $false", native)
        self.assertIn("originalIssueAcceptance = $false", native)
        self.assertIn("'DASH-08-*'", native)
        self.assertIn("sourceSha256", native)
        self.assertIn("sourceUnchanged = $true", qualification)

if __name__ == "__main__":
    unittest.main()
