"""Synthetic SOURCE/FAST-CI contract checks for EDF-006; not PHYSICAL-TUI."""

import math
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_layout_spike import DividerDrag, OverlayStack, Rect, Split, TileWorkspace, solve


class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.split = Split("fleet", "inspector", ratio=0.5)

    def test_required_viewports_and_no_gaps(self):
        for width, height in ((40, 12), (80, 24), (120, 40), (160, 48), (200, 60)):
            with self.subTest(viewport=(width, height)):
                frame = solve(width, height, self.split)
                self.assertEqual(frame.compact, width < 120 or height < 40)
                for y in range(height):
                    for x in range(width):
                        self.assertIsNotNone(frame.hit(x, y))
                self.assertIsNone(frame.hit(-1, 0))
                self.assertIsNone(frame.hit(width, 0))
                self.assertIsNone(frame.hit(0, height))

    def test_final_geometry_respects_min_and_single_divider(self):
        frame = solve(120, 40, Split("a", "b", ratio=0))
        self.assertEqual(frame.tiles["a"].width, 24)
        self.assertEqual(frame.tiles["b"].width, 95)
        self.assertEqual(frame.divider, Rect(24, 0, 1, 40))
        self.assertEqual(frame.hit(24, 5), "divider")
        self.assertEqual(frame.hit(25, 5), "b")
        self.assertEqual(solve(120, 40, Split("a", "b", ratio=1)).tiles["b"].width, 24)

    def test_rows_and_height_minima(self):
        frame = solve(120, 40, Split("a", "b", "rows", min_first=8, min_second=8))
        self.assertFalse(frame.compact)
        self.assertEqual(frame.divider.height, 1)
        self.assertEqual(frame.tiles["a"].height + frame.tiles["b"].height, 39)

    def test_unfeasible_split_falls_back_to_focused_tile(self):
        frame = solve(120, 40, Split("a", "b", min_first=70, min_second=70), "b")
        self.assertTrue(frame.compact)
        self.assertEqual(frame.tiles, {"b": Rect(0, 0, 120, 40)})
        self.assertIsNone(frame.divider)

    def test_invalid_geometry_and_config_refused(self):
        for ratio in (math.inf, math.nan, -0.1, 1.1):
            with self.assertRaises(ValueError):
                Split("a", "b", ratio=ratio)
        with self.assertRaises(ValueError):
            Split("a", "a")
        with self.assertRaises(ValueError):
            solve(0, 40, self.split)


class InputTests(unittest.TestCase):
    def setUp(self):
        self.split = Split("a", "b", ratio=0.5)
        self.frame = solve(160, 48, self.split)
        self.divider = self.frame.divider

    def test_drag_tracks_outside_original_divider_and_clamps(self):
        drag = DividerDrag.begin(self.split, self.frame, self.divider.x, 10)
        self.assertAlmostEqual(drag.move(self.frame, 999, 10), (159 - 24) / 159)
        self.assertAlmostEqual(drag.finish("release"), (159 - 24) / 159)
        with self.assertRaises(ValueError):
            drag.move(self.frame, 10, 10)

    def test_escape_and_focus_loss_rollback(self):
        for reason in ("escape", "focus_loss"):
            drag = DividerDrag.begin(self.split, self.frame, self.divider.x, 4)
            self.assertNotEqual(drag.move(self.frame, 24, 4), self.split.ratio)
            self.assertEqual(drag.finish(reason), self.split.ratio)

    def test_resize_to_compact_cancels_capture_without_division_by_zero(self):
        drag = DividerDrag.begin(self.split, self.frame, self.divider.x, 10)
        self.assertEqual(drag.move(solve(1, 12, self.split), 0, 0), self.split.ratio)
        self.assertFalse(drag.active)
        with self.assertRaises(ValueError):
            drag.finish("release")

    def test_non_divider_capture_refused(self):
        with self.assertRaises(ValueError):
            DividerDrag.begin(self.split, self.frame, 0, 0)

    def test_overlay_dismissal_does_not_click_through(self):
        overlays = OverlayStack()
        overlays.push("menu", Rect(10, 10, 20, 12))
        self.assertEqual(overlays.pointer(self.frame, 15, 12), "overlay:menu")
        self.assertEqual(overlays.pointer(self.frame, self.divider.x, 2), "dismiss-consumed")
        self.assertEqual(overlays.pointer(self.frame, self.divider.x, 2), "divider")

    def test_overlay_escape_exactly_one_level(self):
        overlays = OverlayStack()
        overlays.push("palette", Rect(1, 1, 50, 20))
        overlays.push("confirm", Rect(2, 2, 20, 10))
        self.assertTrue(overlays.escape())
        self.assertEqual(overlays.pointer(self.frame, 5, 5), "overlay:palette")
        self.assertTrue(overlays.escape())
        self.assertFalse(overlays.escape())


class PersistenceTests(unittest.TestCase):
    def test_tile_state_survives_hide_restore(self):
        workspace = TileWorkspace({"fleet": {"scroll": 53}, "logs": {"filter": "errors"}})
        workspace.hide("fleet")
        self.assertEqual(workspace.tile_state["fleet"]["scroll"], 53)
        workspace.restore_all()
        self.assertEqual(workspace.tile_state["logs"]["filter"], "errors")
        self.assertEqual(workspace.hidden, set())

    def test_corrupt_session_fails_closed_without_mutation(self):
        workspace = TileWorkspace({"fleet": {}}, {"fleet"})
        for session in (None, {}, {"schemaVersion": True, "hidden": []},
                        {"schemaVersion": 2, "hidden": []},
                        {"schemaVersion": 1, "hidden": ["unknown"]},
                        {"schemaVersion": 1, "hidden": ["fleet", "fleet"]}):
            with self.subTest(session=session):
                self.assertFalse(workspace.safe_session_load(session))
                self.assertEqual(workspace.hidden, {"fleet"})
        self.assertTrue(workspace.safe_session_load({"schemaVersion": 1, "hidden": []}))
        self.assertEqual(workspace.hidden, set())


if __name__ == "__main__":
    unittest.main()
