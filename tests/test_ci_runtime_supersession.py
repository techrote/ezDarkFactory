"""CI-RUNTIME-001: prove both historical import layers bind one exact replacement, never arbitrary bytes."""
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "tools"))
import provenance as p
from edf_runtime_supersession import PINNED, BASE, EDF002_ACCEPTED, verified_supersession

class RuntimeSupersessionChainTests(unittest.TestCase):
    def test_immutable_edf002_and_edf003_preimages_authenticate_same_replacement(self):
        for dest, (edf003_blob, replacement_blob) in PINNED.items():
            with self.subTest(path=dest):
                edf002_blob = p.run_git(p.ROOT, "rev-parse", EDF002_ACCEPTED + ":" + dest).decode().strip()
                accepted_edf003_blob = p.run_git(p.ROOT, "rev-parse", BASE + ":" + dest).decode().strip()
                # EDF-003 replaced Runtime.ps1, but did not modify the
                # imported Runtime.Tests.ps1 until this CI-RUNTIME issue.
                if dest == "src/EzDarkFactory/Runtime.ps1":
                    self.assertNotEqual(edf002_blob, edf003_blob)
                else:
                    self.assertEqual(edf002_blob, edf003_blob)
                self.assertEqual(accepted_edf003_blob, edf003_blob)
                self.assertTrue(verified_supersession(p.ROOT, dest, edf002_blob))
                self.assertTrue(verified_supersession(p.ROOT, dest, edf003_blob))
                self.assertEqual(p.run_git(p.ROOT, "rev-parse", "HEAD:" + dest).decode().strip(), replacement_blob)

    def test_unrecognized_source_preimage_and_path_are_rejected(self):
        for dest in PINNED:
            with self.subTest(path=dest):
                with self.assertRaisesRegex(AssertionError, "Supersession preimage"):
                    verified_supersession(p.ROOT, dest, "0"*40)
        self.assertFalse(verified_supersession(p.ROOT, "src/EzDarkFactory/Keys.ps1", "0"*40))

if __name__ == "__main__":
    unittest.main()
