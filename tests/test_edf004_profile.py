"""EDF-004 fresh-project provenance and source-contract tests."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import provenance as p

class Edf004ProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = p.ROOT
        cls.map = p.load_json(p.PROVENANCE / "edf004-fresh-profile.json")
        cls.upstream = p.GitRepository(Path(os.environ["EDF_TEST_EZVM"]))

    def test_exact_historical_sources_and_current_destinations_are_bound(self):
        self.assertEqual(self.map["issue"], "EDF-004")
        self.assertEqual(self.map["evidence_class"], "SOURCE")
        self.assertEqual(self.map["edf002_accepted_commit"], "978288496aa5d328f0d79712c74e69cf769689e4")
        self.assertEqual(len(self.map["records"]), 5)
        for row in self.map["records"]:
            with self.subTest(path=row["destination"]):
                raw = self.upstream.file(row["source_commit"], row["source_path"])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row["source_sha256"])
                self.assertEqual(
                    p.run_git(self.root, "rev-parse",
                              row["edf002_accepted_commit"] + ":" + row["edf002_accepted_destination"]).decode().strip(),
                    row["edf002_accepted_blob"])
                current = p.run_git(self.root, "rev-parse", "HEAD:" + row["destination"]).decode().strip()
                self.assertEqual(current, row["destination_blob"])
                self.assertEqual(p.run_git(self.root, "cat-file", "blob", current),
                                 (self.root / row["destination"]).read_bytes())
                self.assertFalse(p.excluded(row["destination"]))

    def test_fresh_profile_is_new_identity_not_mutated_historical_default(self):
        import json
        fresh = json.loads((self.root / "guest/profiles/fresh-project/v1/profile.json").read_text())
        legacy = json.loads((self.root / "guest/profiles/coding-default/v1/profile.json").read_text())
        self.assertEqual(fresh["name"], "fresh-project")
        self.assertEqual(fresh["version"], 1)
        self.assertEqual(fresh["workspacePolicy"], "empty-at-first-ready")
        self.assertEqual(fresh["historicalWorkloadPolicy"], "absent")
        self.assertEqual(fresh["referencePolicy"], "isolated-opt-in")
        self.assertEqual(fresh["requiredCommands"], legacy["requiredCommands"])
        self.assertEqual(legacy["name"], "coding-default")
        self.assertNotEqual(fresh, legacy)

    def test_managed_default_and_script_hold_freshness_boundary(self):
        registry = (self.root / "src/EzDarkFactory/Registry.ps1").read_text(encoding="utf-8")
        profiles = (self.root / "src/EzDarkFactory/Profiles.ps1").read_text(encoding="utf-8")
        script = (self.root / "guest/profiles/fresh-project/v1/provision.sh").read_text(encoding="utf-8")
        self.assertIn("Get-EzDarkFactoryCodingProfile -Root $Root -Name 'fresh-project' -Version 1", registry)
        self.assertIn("@('coding-default', 'fresh-project')", profiles)
        for token in ("fresh workspace is not empty", "historical workload state exists in coder home",
                      "provider, model, credential or autostart state exists in coder home",
                      "prior_ready=1", "rm -f -- /var/lib/ezdarkfactory/ready.json"):
            self.assertIn(token, script)
        self.assertNotRegex(script, r"(?i)rm\s+-rf\s+--?\s+/home/coder/workspace|chown\s+-R")

    def test_no_private_or_historical_payload_added(self):
        paths = [
            "guest/profiles/fresh-project/v1/profile.json",
            "guest/profiles/fresh-project/v1/provision.sh",
            "docs/provenance/edf004-fresh-profile.json",
        ]
        for relative in paths:
            data = (self.root / relative).read_text(encoding="utf-8")
            self.assertNotRegex(data, r"(?i)BEGIN [A-Z ]*PRIVATE KEY|github_pat_|ghp_[A-Za-z0-9]{20,}")
        for relative in self.map["new_edf_source"]:
            self.assertFalse(p.excluded(relative))

if __name__ == "__main__":
    unittest.main()
