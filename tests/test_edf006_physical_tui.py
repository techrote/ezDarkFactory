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

    def test_menu_open_during_capture_cancels_and_late_release_is_inert(self):
        f = Fixture(160, 48)
        x = f.frame.divider.x
        f.press(x, 15)
        f.move(x + 12, 15)
        self.assertIsNotNone(f.preview)
        f.menu()
        self.assertIsNone(f.drag)
        self.assertEqual(f.split.ratio, .5)
        self.assertEqual(f.actions["divider_cancel"], 1)
        # The overlay's outside click is consumed; its paired release cannot
        # commit the old preview or redirect focus to the underlying tile.
        f.press(1, 12)
        f.release()
        self.assertEqual(f.actions["menu_dismiss_consumed"], 1)
        self.assertEqual(f.actions["divider_commit"], 0)
        self.assertEqual(f.actions["tile_focus"], 0)
        self.assertEqual(f.split.ratio, .5)

    def test_duplicate_down_cannot_replace_pointer_capture(self):
        f = Fixture(160, 48)
        x = f.frame.divider.x
        f.press(x, 15)
        f.move(x + 8, 15)
        expected_preview = f.preview
        f.press(x, 15)
        f.press(2, 15)
        self.assertEqual(f.actions["captured_press_ignored"], 2)
        self.assertEqual(f.actions["divider_begin"], 1)
        self.assertEqual(f.preview, expected_preview)
        f.release()
        self.assertEqual(f.actions["divider_commit"], 1)
        self.assertGreater(f.split.ratio, .5)

    def test_resize_discards_modal_from_old_viewport(self):
        f = Fixture(160, 48)
        f.menu()
        self.assertTrue(f.overlays.overlays)
        f.resize(80, 24)
        self.assertFalse(f.overlays.overlays)
        self.assertEqual(f.actions["overlay_resize_dismiss"], 1)
        f.press(1, 12)
        self.assertEqual(f.actions["menu_dismiss_consumed"], 0)
        self.assertEqual(f.actions["tile_focus"], 1)

    def test_modal_keyboard_and_paste_are_not_background_commands(self):
        f = Fixture(160, 48)
        f.input_armed = True
        f.menu()
        f.paste("q;Ctrl+P;PRIVATE-MODAL-FIXTURE")
        self.assertEqual(f.actions["paste_refused"], 1)
        self.assertEqual(f.pasted_chars, 0)
        for key in ("m", "i", "q"):
            self.assertFalse(f.handle_key(key))
        self.assertEqual(f.actions["overlay_key_consumed"], 3)
        self.assertEqual(f.actions["menu_open"], 1)
        self.assertTrue(f.input_armed)
        f.menu()
        self.assertEqual(f.actions["menu_duplicate_ignored"], 1)
        self.assertFalse(f.handle_key("escape"))
        self.assertFalse(f.overlays.overlays)
        f.paste("allowed")
        self.assertEqual(f.actions["paste_allowed"], 1)
        self.assertNotIn("PRIVATE-MODAL-FIXTURE", str(f.summary()))
        self.assertFalse(f.handle_key("i"))
        self.assertTrue(f.handle_key("q"))

    def test_right_click_context_is_clamped_and_overlay_is_first(self):
        f = Fixture(160, 48)
        f.press(158, 45, 3)
        self.assertEqual(f.focus, "inspector")
        self.assertEqual(f.actions["context_menu_open"], 1)
        name, rect = f.overlays.overlays[-1]
        self.assertEqual(name, "menu")
        self.assertTrue(rect.contains(158, 45))
        self.assertLessEqual(rect.x + rect.width, f.width)
        self.assertLessEqual(rect.y + rect.height, f.height)
        f.press(158, 45, 3)
        self.assertEqual(f.actions["overlay_pointer_consumed"], 1)
        self.assertEqual(f.actions["context_menu_open"], 1)
        f.press(1, 12, 3)
        self.assertEqual(f.actions["menu_dismiss_consumed"], 1)
        self.assertEqual(f.actions["context_menu_open"], 1)
        self.assertFalse(f.overlays.overlays)
        self.assertEqual(f.focus, "inspector")
        f.press(1, 12, 3)
        self.assertEqual(f.focus, "fleet")
        self.assertEqual(f.actions["context_menu_open"], 2)

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
