"""EDF-006 Textual integration probe.

This is a non-production qualification seam. It never discovers factories,
invokes the EDF-005 broker, or mutates VM/storage state. Textual owns terminal
I/O/event delivery only; ezDarkFactory retains semantic/layout/control authority.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import textual
from textual import events
from textual.app import App, ComposeResult
from textual.widgets import Static

from edf006_layout_spike import DividerDrag, Split, solve

EXPECTED_TEXTUAL = "8.2.8"
REQUIRED_WINDOWS_DRIVER_SEQUENCES = (
    "\\x1b[?1000h",  # button mouse
    "\\x1b[?1003h",  # any-event movement
    "\\x1b[?1006h",  # SGR mouse coordinates
    "\\x1b[?2004h",  # bracketed paste
    "\\033[?1004h",  # focus in/out
    "\\x1b[?1049h",  # alternate screen
    "\\x1b[?1000l",
    "\\x1b[?1003l",
    "\\x1b[?2004l",
    "\\033[?1004l",
)


class RuntimeProbe(App[None]):
    CSS = "#surface { width: 100%; height: 100%; }"
    BINDINGS = [("ctrl+t", "semantic_probe", "Semantic probe", False)]

    def __init__(self) -> None:
        super().__init__()
        self.split = Split("fleet", "inspector")
        self.frame = solve(80, 24, self.split)
        self.drag: DividerDrag | None = None
        self.events_seen: list[str] = []
        self.pastes: list[str] = []
        self.semantic_actions = 0

    def compose(self) -> ComposeResult:
        yield Static("EDF-006 TEXTUAL RUNTIME PROBE", id="surface")

    def action_semantic_probe(self) -> None:
        self.semantic_actions += 1

    def begin_synthetic_drag(self) -> None:
        frame = solve(160, 48, self.split)
        assert frame.divider is not None
        self.frame = frame
        self.drag = DividerDrag.begin(self.split, frame, frame.divider.x, frame.divider.y)
        self.drag.move(frame, frame.divider.x + 8, frame.divider.y)

    def _rollback_drag(self, reason: str) -> None:
        if self.drag is not None and self.drag.active:
            self.split = Split(
                self.split.first,
                self.split.second,
                self.split.axis,
                self.drag.finish(reason),
                self.split.min_first,
                self.split.min_second,
            )
            self.drag = None

    def on_app_blur(self, _event: events.AppBlur) -> None:
        self.events_seen.append("blur")
        self._rollback_drag("focus_loss")

    def on_app_focus(self, _event: events.AppFocus) -> None:
        self.events_seen.append("focus")

    def on_resize(self, event: events.Resize) -> None:
        self.events_seen.append("resize")
        self._rollback_drag("focus_loss")
        self.frame = solve(event.size.width, event.size.height, self.split)

    def on_paste(self, event: events.Paste) -> None:
        self.events_seen.append("paste")
        # A paste is data. It is deliberately not routed as a command.
        self.pastes.append(event.text[:256])

    def on_mouse_down(self, _event: events.MouseDown) -> None:
        self.events_seen.append("mouse_down")

    def on_mouse_up(self, _event: events.MouseUp) -> None:
        self.events_seen.append("mouse_up")

    def on_mouse_move(self, _event: events.MouseMove) -> None:
        self.events_seen.append("mouse_move")

    def on_mouse_scroll_up(self, _event: events.MouseScrollUp) -> None:
        self.events_seen.append("wheel_up")

    def on_mouse_scroll_down(self, _event: events.MouseScrollDown) -> None:
        self.events_seen.append("wheel_down")


def verify_installed_runtime_source() -> dict[str, object]:
    if textual.__version__ != EXPECTED_TEXTUAL:
        raise AssertionError(f"expected Textual {EXPECTED_TEXTUAL}, got {textual.__version__}")
    package = Path(textual.__file__).resolve().parent
    driver = package / "drivers" / "windows_driver.py"
    source = driver.read_text(encoding="utf-8")
    missing = [sequence for sequence in REQUIRED_WINDOWS_DRIVER_SEQUENCES if sequence not in source]
    if missing:
        raise AssertionError(f"pinned Windows driver is missing required terminal mode transitions: {missing}")
    event_source = (package / "events.py").read_text(encoding="utf-8")
    for symbol in ("class AppFocus", "class AppBlur", "class Paste", "class Resize", "class MouseMove"):
        if symbol not in event_source:
            raise AssertionError(f"pinned Textual event contract missing {symbol}")
    return {"textual": textual.__version__, "windows_driver": str(driver)}


async def run_headless_contract() -> dict[str, object]:
    app = RuntimeProbe()
    async with app.run_test(size=(80, 24)) as pilot:
        await pilot.press("ctrl+t")
        if app.semantic_actions != 1:
            raise AssertionError("Textual key binding did not route exactly once")

        app.begin_synthetic_drag()
        changed_preview = app.drag.preview if app.drag is not None else app.split.ratio
        if changed_preview == app.split.ratio:
            raise AssertionError("synthetic drag did not establish a preview")
        app.post_message(events.AppBlur())
        await pilot.pause()
        if app.drag is not None or app.split.ratio != 0.5 or "blur" not in app.events_seen:
            raise AssertionError("Textual AppBlur did not roll back first-party divider capture")

        app.post_message(events.Paste("q\nnot-a-command"))
        await pilot.pause()
        if app.pastes != ["q\nnot-a-command"] or app.semantic_actions != 1:
            raise AssertionError("paste was not isolated as data")

        await pilot.resize_terminal(160, 48)
        if (app.frame.root.width, app.frame.root.height) != (160, 48):
            raise AssertionError("Textual resize did not reach the first-party layout reducer")

        await pilot.hover("#surface", offset=(1, 1))
        await pilot.mouse_down("#surface", offset=(1, 1))
        await pilot.mouse_up("#surface", offset=(1, 1))
        await pilot.pause()
        for required in ("mouse_move", "mouse_down", "mouse_up"):
            if required not in app.events_seen:
                raise AssertionError(f"synthetic Textual pointer event missing {required}")

    return {
        "size": [160, 48],
        "semantic_actions": app.semantic_actions,
        "events": sorted(set(app.events_seen)),
        "paste_count": len(app.pastes),
    }


async def self_test() -> dict[str, object]:
    source = verify_installed_runtime_source()
    headless = await run_headless_contract()
    return {
        "evidence": "FAST-CI-HEADLESS",
        "physical_tui": False,
        "source": source,
        "headless": headless,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if not args.self_test:
        raise SystemExit("This EDF-006 qualification seam currently supports --self-test only.")
    print(json.dumps(asyncio.run(self_test()), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
