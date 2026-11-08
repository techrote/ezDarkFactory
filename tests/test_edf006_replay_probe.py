"""Bounded synthetic pipe protocol and native-reducer integration (not PHYSICAL-TUI)."""
import io
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_replay_probe import (
    MAX_EVENTS, MAX_LINE_BYTES, ReplayRefusal, parse_event, read_events, replay,
)


def stream(*events):
    return io.BytesIO(b"".join(json.dumps(e, separators=(",", ":")).encode() + b"\n" for e in events))


class ReplayProtocolTests(unittest.TestCase):
    def test_all_event_forms(self):
        cases = [
            ({"kind": "key", "value": "Escape"}, ("key", 0, 0, "Escape")),
            ({"kind": "focus_loss"}, ("focus_loss", 0, 0, 0)),
            ({"kind": "focus_gain"}, ("focus_gain", 0, 0, 0)),
            ({"kind": "resize", "x": 160, "y": 48}, ("resize", 160, 48, 0)),
            ({"kind": "press", "x": 80, "y": 7}, ("press", 80, 7, 0)),
            ({"kind": "move", "x": -1, "y": -1}, ("move", -1, -1, 0)),
            ({"kind": "release", "x": 99, "y": 7}, ("release", 99, 7, 0)),
            ({"kind": "wheel", "x": 90, "y": 7, "value": -120}, ("wheel", 90, 7, -120)),
        ]
        for case, expected in cases:
            with self.subTest(case=case):
                self.assertEqual(parse_event(json.dumps(case).encode()), expected)

    def test_unknown_or_mutating_fields_refused(self):
        for payload in [b'{"kind":"factory.stop"}',
                        b'{"kind":"press","x":1,"y":2,"command":"instance.reset"}',
                        b'{"kind":"focus_loss","x":1}',
                        b'{"kind":"key","value":"Ctrl+C"}',
                        b'{"kind":"key","value":"q","value":"m"}',
                        b'{"kind":"move","x":0,"y":0,"x":2}',
                        b'{"kind":"resize","x":true,"y":12}',
                        b'{"kind":"wheel","x":0,"y":0,"value":1e999}',
                        b'{"kind":"move","x":0,"y":0,"foo":"\\u001b[2J"}',
                        b'not-json', b'\xff']:
            with self.subTest(payload=payload):
                with self.assertRaises(ReplayRefusal):
                    parse_event(payload)

    def test_bounds_and_blank_lines(self):
        for payload in [b'\n', b' ' * (MAX_LINE_BYTES + 1) + b'\n',
                        stream(*([{"kind": "focus_loss"}] * (MAX_EVENTS + 1))).getvalue()]:
            with self.subTest(length=len(payload)):
                with self.assertRaises(ReplayRefusal):
                    list(read_events(io.BytesIO(payload)))

    def test_exact_budget_and_no_truncation(self):
        self.assertEqual(len(list(read_events(stream(*([{"kind": "focus_gain"}] * MAX_EVENTS))))), MAX_EVENTS)
        self.assertEqual(list(read_events(io.BytesIO(b""))), [])
        with self.assertRaises(ReplayRefusal):
            list(read_events(io.BytesIO(b'{"kind":"press","x":1,"y":2}\n' + b'x' * 513)))


class RealReducerReplayTests(unittest.TestCase):
    def test_viewport_matrix_is_deterministic(self):
        for width, height in [(40, 12), (80, 24), (120, 40), (160, 48), (200, 60)]:
            with self.subTest(viewport=(width, height)):
                value = stream({"kind": "key", "value": "m"},
                               {"kind": "key", "value": "Escape"},
                               {"kind": "wheel", "x": 3, "y": 3, "value": -120})
                result = replay(value, width, height)
                self.assertEqual(result, replay(stream({"kind": "key", "value": "m"},
                                                       {"kind": "key", "value": "Escape"},
                                                       {"kind": "wheel", "x": 3, "y": 3, "value": -120}), width, height))
                self.assertEqual(result["inputEvents"], 3)
                self.assertEqual(len(result["frames"]), 4)
                self.assertEqual(result["evidence"], "SYNTHETIC-PIPE-ONLY")
                self.assertEqual(result["frames"][-1]["width"], width)
                self.assertEqual(result["frames"][-1]["height"], height)
                self.assertEqual(result["frames"][0]["compact"], width < 120)

    def test_drag_commit_escape_focus_loss_and_resize(self):
        result = replay(stream({"kind": "press", "x": 80, "y": 4},
                               {"kind": "move", "x": 40, "y": 4},
                               {"kind": "focus_loss"},
                               {"kind": "press", "x": 80, "y": 4},
                               {"kind": "move", "x": 45, "y": 4},
                               {"kind": "resize", "x": 200, "y": 60},
                               {"kind": "press", "x": 100, "y": 4},
                               {"kind": "move", "x": 55, "y": 4},
                               {"kind": "release", "x": 55, "y": 4}), 160, 48)
        frames = result["frames"]
        self.assertTrue(frames[1]["dragActive"])
        self.assertEqual(frames[2]["dividerX"], 40)
        self.assertFalse(frames[3]["dragActive"])
        self.assertEqual(frames[3]["dividerX"], 80)
        self.assertEqual(frames[6]["dividerX"], 100)
        self.assertFalse(frames[6]["dragActive"])
        self.assertEqual(frames[-1]["dividerX"], 55)
        self.assertFalse(frames[-1]["dragActive"])

    def test_overlay_outside_click_is_consumed(self):
        result = replay(stream({"kind": "key", "value": "m"},
                               {"kind": "press", "x": 80, "y": 1},
                               {"kind": "press", "x": 80, "y": 1}), 160, 48)
        self.assertEqual(result["frames"][1]["overlayDepth"], 1)
        self.assertEqual(result["frames"][2]["overlayDepth"], 0)
        self.assertFalse(result["frames"][2]["dragActive"])
        self.assertTrue(result["frames"][3]["dragActive"])

    def test_exit_rejects_trailing_events(self):
        with self.assertRaises(ReplayRefusal):
            replay(stream({"kind": "key", "value": "q"},
                          {"kind": "key", "value": "m"}), 160, 48)

    def test_safe_termination_has_no_raw_input(self):
        result = replay(stream({"kind": "key", "value": "q"}), 40, 12)
        self.assertFalse(result["frames"][-1]["running"])
        data = json.dumps(result)
        self.assertNotIn("instance.reset", data)
        self.assertEqual(len(result["frames"][-1]["sha256"]), 64)

    def test_invalid_initial_viewport(self):
        for width, height in [(0, 12), (301, 12), (80, 101), (True, 24)]:
            with self.assertRaises(ReplayRefusal):
                replay(io.BytesIO(), width, height)


if __name__ == "__main__":
    unittest.main()
