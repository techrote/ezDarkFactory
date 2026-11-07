"""EDF-006 physical fixture SOURCE tests, not native acceptance."""
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_physical_tui import Fixture, create_only_receipt, render


class PhysicalFixtureTests(unittest.TestCase):
    def test_commit_only_on_release(self):
        f = Fixture(160, 48)
        x = f.frame.divider.x
        f.press(x, 15)
        f.move(x + 10, 15)
        self.assertEqual(f.split.ratio, .5)
        f.release()
        self.assertGreater(f.split.ratio, .5)
        self.assertEqual(f.actions["divider_commit"], 1)

    def test_escape_blur_resize_cancel_drag(self):
        for action in ("escape", "blur", "resize"):
            with self.subTest(action=action):
                f = Fixture(160, 48)
                f.press(f.frame.divider.x, 15)
                f.move(f.frame.divider.x + 10, 15)
                if action == "resize":
                    f.resize(180, 48)
                else:
                    getattr(f, action)()
                self.assertEqual(f.split.ratio, .5)
                self.assertIsNone(f.drag)
                self.assertEqual(f.actions["divider_cancel"], 1)

    def test_overlay_outside_dismissal_is_consumed(self):
        f = Fixture(160, 48)
        f.menu()
        f.press(1, 12)
        self.assertEqual(f.actions["menu_dismiss_consumed"], 1)
        self.assertEqual(f.actions["tile_focus"], 0)
        f.menu()
        f.escape()
        self.assertEqual(f.actions["menu_escape"], 1)

    def test_inert_paste_without_payload_leak(self):
        f = Fixture()
        secret = "q\nCtrl+P\nSECRET-7392"
        f.paste(secret)
        f.input_armed = True
        f.paste(secret)
        self.assertEqual(f.actions["paste_refused"], 1)
        self.assertEqual(f.actions["paste_allowed"], 1)
        self.assertNotIn("SECRET-7392", str(f.summary()))
        self.assertNotIn("SECRET-7392", render(f))

    def test_receipts_create_only_and_cannot_claim_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "receipt.json")
            f = Fixture()
            f.paste("SECRET-7392")
            create_only_receipt(path, f.summary())
            content = Path(path).read_text()
            self.assertNotIn("SECRET-7392", content)
            self.assertFalse(json.loads(content)["physical_tui"])
            self.assertIsNone(json.loads(content)["input_to_visible_frame_p95_ms"])
            with self.assertRaises(FileExistsError):
                create_only_receipt(path, f.summary())
            with self.assertRaises(ValueError):
                create_only_receipt(str(Path(directory) / "fake.json"),
                                    {"evidence": "PHYSICAL-TUI", "physical_tui": True})
        with self.assertRaises(ValueError):
            create_only_receipt("relative.json", Fixture().summary())

    def test_ascii_responsive_layout_and_recovery(self):
        for w, h in ((40, 12), (80, 24), (160, 48)):
            f = Fixture(w, h)
            view = render(f, ascii_only=True)
            self.assertTrue(view.isascii())
            self.assertEqual([len(row) for row in view.splitlines()], [w]*h)
        f = Fixture(40, 12)
        self.assertTrue(f.frame.compact)
        f.resize(160, 48)
        f.recover()
        self.assertEqual(f.focus, "fleet")
        with self.assertRaises(ValueError):
            f.resize(2000, 500)


if __name__ == "__main__":
    unittest.main()
