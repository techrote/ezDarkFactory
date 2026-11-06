"""Deterministic EDF-006 scene/theme/accessibility tests; not PHYSICAL-TUI."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_scene_spike import (Capabilities, Cell, COLOR_MODES, REQUIRED_ROLES,
                                Scene, logical_damage, plain_rows, sgr, status_text)


class SceneThemeTests(unittest.TestCase):
    def test_role_catalogue_matches_required_semantics(self):
        self.assertEqual(len(REQUIRED_ROLES), 19)
        for role in ("background", "text", "selection", "warning", "error",
                     "success", "stale", "unknown", "conflict", "destructive"):
            self.assertIn(role, REQUIRED_ROLES)

    def test_deterministic_color_degradation(self):
        expected = {
            "truecolor": "truecolor", "ansi256": "ansi256", "ansi16": "ansi16", "mono": "mono"
        }
        for maximum, result in expected.items():
            with self.subTest(maximum=maximum):
                self.assertEqual(Capabilities.negotiate(max_color=maximum).color, result)
        self.assertEqual(Capabilities.negotiate(preferred_color="ansi16", max_color="truecolor").color,
                         "ansi16")

    def test_unicode_ascii_and_motion_fallbacks(self):
        reduced = Capabilities.negotiate(unicode_supported=False, reduced_motion=True)
        self.assertFalse(reduced.unicode)
        self.assertEqual(reduced.motion, "reduced")
        self.assertEqual(Capabilities.negotiate(motion_supported=False).motion, "off")

    def test_all_color_modes_resolve_every_role(self):
        for mode in COLOR_MODES:
            caps = Capabilities(color=mode)
            for role in REQUIRED_ROLES:
                with self.subTest(mode=mode, role=role):
                    token = sgr(role, caps)
                    self.assertTrue(token.startswith("\x1b["))
                    self.assertTrue(token.endswith("m"))

    def test_high_contrast_is_explicit_and_deterministic(self):
        normal = sgr("warning", Capabilities(color="truecolor"))
        contrast = sgr("warning", Capabilities(color="truecolor", high_contrast=True))
        self.assertNotEqual(normal, contrast)
        self.assertEqual(contrast, sgr("warning", Capabilities(color="truecolor", high_contrast=True)))

    def test_status_meaning_is_never_color_only(self):
        for role, prefix in (("success", "SUCCESS"), ("warning", "WARNING"),
                             ("error", "ERROR"), ("stale", "STALE"),
                             ("unknown", "UNKNOWN"), ("conflict", "CONFLICT")):
            with self.subTest(role=role):
                self.assertEqual(status_text(role, "factory alpha"), f"{prefix}: factory alpha")
        self.assertEqual(status_text("error", "bad\x1btitle"), "ERROR: bad?title")

    def test_atomic_wide_glyph_clip(self):
        scene = Scene(4, 1)
        self.assertTrue(scene.put(0, 0, "界"))
        self.assertFalse(scene.put(3, 0, "界"))
        self.assertEqual(plain_rows(scene, Capabilities(unicode=True))[0], "界  ")
        self.assertEqual(plain_rows(scene, Capabilities(unicode=False))[0], "??  ")

    def test_known_unicode_glyphs_have_geometry_safe_ascii_fallback(self):
        scene = Scene(5, 1)
        scene.write(0, 0, "┌─✓")
        self.assertEqual(plain_rows(scene, Capabilities(unicode=True))[0], "┌─✓  ")
        self.assertEqual(plain_rows(scene, Capabilities(unicode=False))[0], "+-+  ")

    def test_decoration_cannot_cover_content_or_critical_cells(self):
        scene = Scene(5, 1)
        self.assertTrue(scene.put(1, 0, "C", role="text", protection="content"))
        self.assertTrue(scene.put(2, 0, "!", role="destructive", protection="critical"))
        self.assertFalse(scene.put(1, 0, "*", role="accent", protection="decoration"))
        self.assertFalse(scene.put(2, 0, "*", role="accent", protection="decoration"))
        self.assertFalse(scene.put(2, 0, "N", role="text", protection="content"))
        self.assertEqual((scene.cell(1, 0).char, scene.cell(2, 0).char), ("C", "!"))

    def test_critical_can_replace_lower_protection(self):
        scene = Scene(3, 1)
        scene.put(1, 0, ".", role="muted", protection="decoration")
        self.assertTrue(scene.put(1, 0, "!", role="error", protection="critical"))
        self.assertEqual(scene.cell(1, 0), Cell("!", "error", "critical"))

    def test_invalid_semantics_fail_closed(self):
        with self.assertRaises(ValueError):
            Capabilities(color="ansi8")
        with self.assertRaises(ValueError):
            Cell("x", "not-a-role")
        with self.assertRaises(ValueError):
            status_text("text", "not status")
        with self.assertRaises(ValueError):
            sgr("text", Capabilities(), frozenset({"mystery"}))

    def test_control_characters_are_not_replayed(self):
        scene = Scene(8, 1)
        scene.write(0, 0, "ok\x1b[31m")
        row = plain_rows(scene, Capabilities(unicode=True))[0]
        self.assertNotIn("\x1b", row)
        self.assertTrue(row.startswith("ok?[31m"))

    def test_unchanged_scene_has_zero_logical_damage(self):
        a, b = Scene(8, 2), Scene(8, 2)
        a.write(1, 0, "READY", role="success", protection="critical")
        b.write(1, 0, "READY", role="success", protection="critical")
        self.assertEqual(logical_damage(a, b), ())

    def test_local_focus_change_has_bounded_logical_damage(self):
        a, b = Scene(20, 2), Scene(20, 2)
        for scene in (a, b):
            scene.write(0, 0, "fleet", role="title", protection="content")
            scene.write(8, 0, "inspector", role="title", protection="content")
        a.put(0, 1, ">", role="selection", modifiers=frozenset({"focused"}))
        b.put(8, 1, ">", role="selection", modifiers=frozenset({"focused"}))
        self.assertEqual(set(logical_damage(a, b)), {(0, 1), (8, 1)})

    def test_resize_damage_is_explicit_not_silently_reused(self):
        self.assertEqual(len(logical_damage(Scene(2, 2), Scene(3, 2))), 6)


if __name__ == "__main__":
    unittest.main()
