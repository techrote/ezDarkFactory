"""Source-only checks for the EDF-006 production TUI runtime selection."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "edf006-tui-runtime.json"


class TuiRuntimeLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_exact_runtime_and_framework_identity(self):
        self.assertEqual(self.lock["schemaVersion"], 1)
        self.assertEqual(self.lock["python"]["version"], "3.12.10")
        self.assertEqual(self.lock["python"]["architecture"], "win-x64")
        self.assertEqual(self.lock["framework"]["name"], "textual")
        self.assertEqual(self.lock["framework"]["version"], "8.2.8")
        self.assertRegex(self.lock["framework"]["sourceCommit"], r"^[0-9a-f]{40}$")

    def test_acquisitions_are_hash_pinned_and_officially_scoped(self):
        py = self.lock["python"]
        self.assertEqual(py["url"], "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip")
        self.assertRegex(py["sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(py["officialMd5"], r"^[0-9a-f]{32}$")
        packages = self.lock["packages"]
        self.assertEqual(len(packages), 10)
        self.assertEqual(len({(x["name"], x["version"]) for x in packages}), len(packages))
        for package in packages:
            self.assertTrue(package["filename"].endswith("-py3-none-any.whl"))
            self.assertRegex(package["sha256"], r"^[0-9a-f]{64}$")
        self.assertFalse(self.lock["policy"]["allowSdist"])
        self.assertFalse(self.lock["policy"]["allowPipResolution"])
        self.assertFalse(self.lock["policy"]["syntaxExtras"])
        self.assertNotIn("tree-sitter", " ".join(x["name"] for x in packages).lower())

    def test_textual_wheel_identity_is_single_source_of_truth(self):
        framework = self.lock["framework"]
        textual = [x for x in self.lock["packages"] if x["name"] == "textual"]
        self.assertEqual(len(textual), 1)
        self.assertEqual(textual[0]["version"], framework["version"])
        self.assertEqual(textual[0]["filename"], framework["wheel"]["filename"])
        self.assertEqual(textual[0]["sha256"], framework["wheel"]["sha256"])

    def test_installer_is_portable_hash_verified_and_never_resolves_with_pip(self):
        source = (ROOT / "scripts" / "Install-Edf006TuiRuntime.ps1").read_text(encoding="utf-8")
        for required in ("Get-FileHash", "SHA256", "$lock.policy.wheelHost", "python312._pth", "Lib/site-packages"):
            self.assertIn(required, source)
        for forbidden in ("pip install", "Invoke-Expression", "$env:LOCALAPPDATA", "$env:APPDATA", "SetEnvironmentVariable"):
            self.assertNotIn(forbidden, source)

    def test_adr_retains_physical_gate_and_alternatives(self):
        adr = (ROOT / "docs" / "decisions" / "EDF-006-HOST-TUI-STACK.md").read_text(encoding="utf-8")
        for required in ("Textual 8.2.8", "prompt_toolkit 3.0.53", "Urwid 5.1.0", "PHYSICAL-TUI PENDING", "a38fd7d7a67f7039481868e3e5767c8b297fbdf6"):
            self.assertIn(required, adr)
        self.assertNotRegex(adr, re.compile(r"PHYSICAL-TUI\s+PASS"))


if __name__ == "__main__":
    unittest.main()
