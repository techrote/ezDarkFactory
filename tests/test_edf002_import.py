"""EDF-002 active-import provenance: source hashes, exact/default adaptations and safe destinations."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import provenance as p

REVIEWED_INTEGRATION_DESTINATIONS = frozenset({
    ".github/workflows/ci.yml",
    ".gitignore",
    "README.md",
    "THIRD-PARTY-NOTICES.md",
    "docs/CODING-GUEST.md",
    "docs/GETTING-STARTED.md",
    "docs/PORTABILITY.md",
    "docs/TROUBLESHOOTING.md",
    "docs/WHPX-QUALIFICATION.md",
    "scripts/New-EzDarkFactoryReleasePackage.ps1",
    "scripts/Publish-EzDarkFactoryGitHubRelease.ps1",
    "scripts/RepositoryContract.psm1",
    "src/EzDarkFactory/EzDarkFactory.psd1",
    "tests/Cli.Tests.ps1",
    "tests/README.md",
    "tests/Release.Tests.ps1",
    "tests/Repository.Tests.ps1",
})

EDF002_ACCEPTED_SOURCE = "978288496aa5d328f0d79712c74e69cf769689e4"
# The accepted import inventory is immutable historical evidence, NOT a claim
# that later explicitly reviewed repairs leave the live working file unchanged.
EDF003_SUPERSEDED_DESTINATIONS = frozenset({
    ".github/workflows/ci.yml",
    "src/EzDarkFactory/Keys.ps1",
    "src/EzDarkFactory/Runtime.ps1",
})

class ActiveImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = p.ROOT
        cls.manifest = p.load_json(p.PROVENANCE / "manifest.json")
        cls.active = p.load_json(p.PROVENANCE / "edf002-imports.json")
        cls.repo = p.GitRepository(Path(os.environ["EDF_TEST_EZVM"]))

    def test_import_set_is_exactly_reviewed_87_destinations(self):
        rows = [r for r in self.manifest["files"] if r["edf002_import"]]
        self.assertEqual(len(rows), 87)
        self.assertEqual(len(self.active["records"]), 87)
        self.assertEqual(self.active["baselineCommit"], "b6abdf8c3edd61695db30894da991f275b39a699")
        self.assertEqual(self.active["baselineTree"], "78e5ce0db9c32972451add22d28c7d19983775ee")
        actual = {(r["source_path"], r["destination"]) for r in self.active["records"]}
        self.assertEqual(len(actual), 87)
        self.assertEqual(actual, {(r["source_path"], r["destination"]) for r in rows})
        self.assertEqual(len({p.safe_relative(r["destination"]) for r in self.active["records"]}), 87)

    def test_each_active_file_has_hash_identified_original_blob_and_safe_root_relative_destination(self):
        baseline = {r["source_path"]: r for r in self.manifest["files"] if r["source_id"] == "ezvm-baseline"}
        for record in self.active["records"]:
            with self.subTest(path=record["destination"]):
                self.assertEqual(record["source_repository"], "techrote/ezvm")
                self.assertEqual(record["source_commit"], self.active["baselineCommit"])
                m = baseline[record["source_path"]]
                self.assertTrue(m["edf002_import"])
                self.assertEqual(record["source_blob"], m["git_blob"])
                self.assertEqual(record["source_sha256"], m["sha256"])
                self.assertEqual(record["source_mode"], m["mode"])
                self.assertEqual(record["classification"], m["classification"])
                destination = record["destination"]
                self.assertFalse(p.excluded(destination))
                self.assertEqual(p.safe_relative(destination), destination.casefold())
                original = self.repo.file(record["source_commit"], record["source_path"])
                self.assertEqual(hashlib.sha256(original).hexdigest(), record["source_sha256"])
                self.assertTrue((self.root / destination).is_file(), destination)
                # Read the exact accepted EDF-002 import commit, not current
                # HEAD: later issues explicitly supersede only scoped files.
                historical_blob = p.run_git(self.root, "rev-parse",
                    EDF002_ACCEPTED_SOURCE + ":" + destination).decode("ascii").strip()
                self.assertEqual(historical_blob, record["destination_blob"])
                historical_bytes = p.run_git(self.root, "cat-file", "blob", historical_blob)
                current_blob = p.run_git(self.root, "rev-parse", "HEAD:" + destination).decode("ascii").strip()
                self.assertEqual(p.run_git(self.root, "cat-file", "blob", current_blob),
                                 (self.root / destination).read_bytes())
                if destination not in EDF003_SUPERSEDED_DESTINATIONS:
                    self.assertEqual(current_blob, historical_blob)
                elif destination in {"src/EzDarkFactory/Keys.ps1", "src/EzDarkFactory/Runtime.ps1"}:
                    repairs = p.load_json(p.PROVENANCE / "edf003-repairs.json")
                    matches = [r for r in repairs["records"] if r["destination"] == destination]
                    self.assertEqual(len(matches), 1)
                    self.assertEqual(current_blob, matches[0]["destination_blob"])
                else:
                    workflow = (self.root / destination).read_text(encoding="utf-8")
                    self.assertIn("EDF-003 standard-user ACL", workflow)
                    self.assertIn("EDF-003 native process", workflow)

    def test_identity_and_default_rebrand_are_byte_reproducible_without_code_execution(self):
        for record in self.active["records"]:
            if record["transform"] == "reviewed-integration-v1":
                self.assertIn(record["destination"], REVIEWED_INTEGRATION_DESTINATIONS)
                self.assertIsInstance(record["review_note"], str)
                self.assertGreaterEqual(len(record["review_note"]), 35)
                continue
            with self.subTest(path=record["destination"]):
                original = self.repo.file(record["source_commit"], record["source_path"])
                if record["transform"] == "identity":
                    expected = original
                else:
                    self.assertEqual(record["transform"], "namespace-rebrand-v1")
                    expected = (original.decode("utf-8").replace("EzVm", "EzDarkFactory")
                        .replace("EZVM", "EDF").replace("ezvm", "ezdarkfactory")).encode("utf-8")
                accepted_blob = p.run_git(self.root, "cat-file", "blob", record["destination_blob"])
                self.assertEqual(accepted_blob, expected)
                if record["destination"] not in EDF003_SUPERSEDED_DESTINATIONS:
                    self.assertEqual((self.root / record["destination"]).read_bytes(), expected)

    def test_source_does_not_claim_stable_0_1_release_or_host_runtime_qualification(self):
        module = (self.root / "src/EzDarkFactory/EzDarkFactory.psd1").read_text(encoding="utf-8")
        self.assertIn("ModuleVersion = '0.0.0'", module)
        self.assertIn("EzDarkFactoryVersion = '0.0.0-dev'", module)
        self.assertNotIn("GUID = '2e0b7e67-36f3-4e77-96c8-8d40296b7abd'", module)
        self.assertFalse((self.root / ".github/workflows/release.yml").exists())
        publisher = (self.root / "scripts/Publish-EzDarkFactoryGitHubRelease.ps1").read_text(encoding="utf-8")
        self.assertIn("throw 'EDF-012 release qualification has not been completed.", publisher)
        self.assertEqual(self.active["evidence"], "SOURCE")
        self.assertFalse((self.root / "src/EzVm").exists())
        self.assertFalse((self.root / "ezvm.ps1").exists())

if __name__ == "__main__":
    unittest.main()
