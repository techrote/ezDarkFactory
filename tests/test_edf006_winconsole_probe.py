"""Native record normalization and layout simulation; NOT physical TUI proof."""
import ctypes
import sys
import unittest
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_winconsole_probe import (
    Demo, Event, INPUT_RECORD, KEY_EVENT, MOUSE_EVENT,
    WINDOW_BUFFER_SIZE_EVENT, FOCUS_EVENT, MOUSE_MOVED,
    MOUSE_WHEELED, decode, frame_text, WindowsConsole, Viewport,
    CONSOLE_SCREEN_BUFFER_INFO, SMALL_RECT, require_physical_viewport,
)


def mouse(buttons, flags=0, x=60, y=7):
    record = INPUT_RECORD()
    record.EventType = MOUSE_EVENT
    record.Event.MouseEvent.dwButtonState = buttons
    record.Event.MouseEvent.dwEventFlags = flags
    record.Event.MouseEvent.dwMousePosition.X = x
    record.Event.MouseEvent.dwMousePosition.Y = y
    return record


class NativeInputTests(unittest.TestCase):
    def test_press_move_release(self):
        event, left = decode(mouse(1), False)
        self.assertEqual(event, Event("press", 60, 7))
        self.assertTrue(left)
        event, left = decode(mouse(1, MOUSE_MOVED, 80), left)
        self.assertEqual(event, Event("move", 80, 7))
        event, left = decode(mouse(0), left)
        self.assertEqual(event, Event("release", 60, 7))
        self.assertFalse(left)

    def test_duplicate_down_and_unrelated_records_do_not_fake_press(self):
        event, left = decode(mouse(1), True)
        self.assertIsNone(event)
        self.assertTrue(left)
        event, left = decode(mouse(0x2), False)
        self.assertIsNone(event)
        self.assertFalse(left)

    def test_printable_key_uses_fixed_width_utf16_code_unit(self):
        raw = INPUT_RECORD()
        raw.EventType = KEY_EVENT
        raw.Event.KeyEvent.bKeyDown = True
        raw.Event.KeyEvent.UnicodeChar = ord("Q")
        self.assertEqual(decode(raw, False)[0], Event("key", value="q"))

    def test_signed_wheel_does_not_mutate_button_capture(self):
        up, state = decode(mouse((120 & 0xFFFF) << 16, MOUSE_WHEELED), False)
        down, same_state = decode(mouse(((-120) & 0xFFFF) << 16, MOUSE_WHEELED), True)
        self.assertEqual(up.value, 120)
        self.assertEqual(down.value, -120)
        self.assertFalse(state)
        self.assertTrue(same_state)

    def test_focus_loss_resets_previous_button_and_fires_rollback(self):
        raw = INPUT_RECORD()
        raw.EventType = FOCUS_EVENT
        raw.Event.FocusEvent.bSetFocus = False
        event, state = decode(raw, True)
        self.assertEqual(event, Event("focus_loss"))
        self.assertFalse(state)

    def test_resize_is_bounded_to_positive_logical_dimensions(self):
        raw = INPUT_RECORD()
        raw.EventType = WINDOW_BUFFER_SIZE_EVENT
        raw.Event.WindowBufferSizeEvent.X = 0
        raw.Event.WindowBufferSizeEvent.Y = 80
        event, _ = decode(raw, False)
        self.assertEqual(event, Event("resize", 1, 80))

    def test_key_up_ignored_and_escape_keydown_normalized(self):
        raw = INPUT_RECORD()
        raw.EventType = KEY_EVENT
        raw.Event.KeyEvent.wVirtualKeyCode = 0x1B
        self.assertIsNone(decode(raw, False)[0])
        raw.Event.KeyEvent.bKeyDown = True
        self.assertEqual(decode(raw, False)[0], Event("key", value="Escape"))

    def test_win32_input_record_abi_is_portable_and_exact(self):
        self.assertEqual(ctypes.sizeof(INPUT_RECORD), 20)
        self.assertEqual(ctypes.sizeof(SMALL_RECT), 8)
        self.assertEqual(ctypes.sizeof(CONSOLE_SCREEN_BUFFER_INFO), 22)

    def test_visible_console_window_not_backing_buffer_is_authoritative(self):
        info = CONSOLE_SCREEN_BUFFER_INFO()
        info.dwSize.X, info.dwSize.Y = 512, 900
        info.srWindow.Left, info.srWindow.Top = 100, 300
        info.srWindow.Right, info.srWindow.Bottom = 259, 347
        self.assertEqual(Viewport.from_buffer_info(info), Viewport(100, 300, 160, 48))

    def test_native_mouse_coordinates_subtract_visible_window_origin(self):
        visible = Viewport(100, 300, 160, 48)
        event, left = decode(mouse(1, x=115, y=310), False, visible)
        self.assertEqual(event, Event("press", 15, 10))
        self.assertTrue(left)
        event, _ = decode(mouse(0, x=99, y=299), left, visible)
        self.assertEqual(event, Event("release", -1, -1))

    def test_native_resize_uses_viewport_not_buffer_dimensions(self):
        raw = INPUT_RECORD()
        raw.EventType = WINDOW_BUFFER_SIZE_EVENT
        raw.Event.WindowBufferSizeEvent.X = 300
        raw.Event.WindowBufferSizeEvent.Y = 900
        self.assertEqual(decode(raw, False, Viewport(40, 80, 80, 24))[0],
                         Event("resize", 80, 24))

    def test_physical_size_flags_are_assertions_not_software_override(self):
        visible = Viewport(100, 300, 160, 48)
        self.assertEqual(require_physical_viewport(visible, None, None), (160, 48))
        self.assertEqual(require_physical_viewport(visible, 160, 48), (160, 48))
        with self.assertRaises(ValueError):
            require_physical_viewport(visible, 80, 24)
        with self.assertRaises(ValueError):
            require_physical_viewport(Viewport(0, 0, 301, 48), None, None)

    def test_invalid_visible_window_fails_closed(self):
        info = CONSOLE_SCREEN_BUFFER_INFO()
        info.srWindow.Left, info.srWindow.Right = 20, 10
        with self.assertRaises(ValueError):
            Viewport.from_buffer_info(info)


class InertDemoTests(unittest.TestCase):
    def setUp(self):
        self.demo = Demo(160, 48)

    def test_native_drag_preview_escape_and_release(self):
        self.demo.apply(Event("press", self.demo.frame.divider.x, 4))
        self.demo.apply(Event("move", 40, 4))
        self.assertNotEqual(self.demo.frame.divider.x, 80)
        self.demo.apply(Event("key", value="Escape"))
        self.assertEqual(self.demo.frame.divider.x, 80)
        self.assertTrue(self.demo.running)
        self.demo.apply(Event("press", self.demo.frame.divider.x, 4))
        self.demo.apply(Event("move", 40, 4))
        self.demo.apply(Event("release", 40, 4))
        self.assertEqual(self.demo.frame.divider.x, 40)

    def test_focus_loss_rolls_back_and_no_vm_is_touched(self):
        old = self.demo.split.ratio
        self.demo.apply(Event("press", self.demo.frame.divider.x, 5))
        self.demo.apply(Event("move", 50, 5))
        self.demo.apply(Event("focus_loss"))
        self.assertIsNone(self.demo.drag)
        self.assertEqual(self.demo.split.ratio, old)

    def test_noncompact_resize_cancels_drag_and_original_ratio_survives(self):
        start = self.demo.split.ratio
        self.demo.apply(Event("press", self.demo.frame.divider.x, 5))
        self.demo.apply(Event("move", 45, 5))
        self.demo.apply(Event("resize", 200, 60))
        self.assertIsNone(self.demo.drag)
        self.assertEqual(self.demo.split.ratio, start)
        self.assertFalse(self.demo.frame.compact)
        self.assertEqual((self.demo.width, self.demo.height), (200, 60))

    def test_resize_to_compact_cancels_drag(self):
        self.demo.apply(Event("press", self.demo.frame.divider.x, 5))
        self.demo.apply(Event("resize", 80, 24))
        self.assertIsNone(self.demo.drag)
        self.assertTrue(self.demo.frame.compact)

    def test_unbounded_resize_fails_closed(self):
        self.demo.apply(Event("resize", 320, 200))
        self.assertFalse(self.demo.running)
        self.assertEqual((self.demo.width, self.demo.height), (160, 48))

    def test_menu_dismiss_click_consumed_without_divider_capture(self):
        self.demo.apply(Event("key", value="m"))
        self.demo.apply(Event("press", self.demo.frame.divider.x, 1))
        self.assertFalse(self.demo.overlays.overlays)
        self.assertIsNone(self.demo.drag)
        self.demo.apply(Event("press", self.demo.frame.divider.x, 1))
        self.assertIsNotNone(self.demo.drag)

    def test_exit_and_ascii_safe_boundaries(self):
        self.demo.apply(Event("key", value="q"))
        self.assertFalse(self.demo.running)
        self.assertEqual(len(frame_text(self.demo).split("\r\n")), 48)
        self.assertTrue(all(ord(c) < 128 for c in frame_text(self.demo)))

    def test_interactive_probe_refuses_non_windows(self):
        with patch("edf006_winconsole_probe.os.name", "posix"):
            with self.assertRaises(RuntimeError):
                WindowsConsole().__enter__()


if __name__ == "__main__":
    unittest.main()
