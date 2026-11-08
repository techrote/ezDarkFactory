"""Actual selected-Textual operator fixture, not PHYSICAL-TUI PASS evidence.

Inert: no factories, credentials, QEMU, network, or raw input persisted.
A native Windows Terminal operator must separately witness presentation.
"""
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import dataclass, field, replace
import hashlib
import json
import os
from pathlib import Path
import sys

# Portable CPython runs with -I, which removes script-dir implicit imports.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from edf006_layout_spike import DividerDrag, OverlayStack, Rect, Split, solve


@dataclass
class Fixture:
    width: int = 80
    height: int = 24
    split: Split = field(default_factory=lambda: Split("fleet", "inspector"))
    focus: str = "fleet"
    drag: DividerDrag | None = None
    overlays: OverlayStack = field(default_factory=OverlayStack)
    input_armed: bool = False
    events: Counter = field(default_factory=Counter)
    actions: Counter = field(default_factory=Counter)
    pasted_chars: int = 0
    last: str = "startup"
    preview: float | None = None

    def __post_init__(self):
        self.frame = solve(self.width, self.height, self.split, self.focus)

    def _solve(self):
        self.frame = solve(self.width, self.height, self.split, self.focus)

    def cancel(self):
        if self.drag is None:
            return False
        if self.drag.active:
            self.split = replace(self.split, ratio=self.drag.finish("escape"))
        self.drag = None
        self.preview = None
        self.actions["divider_cancel"] += 1
        self.last = "divider_cancel"
        self._solve()
        return True

    def resize(self, width, height):
        if not (1 <= width <= 300 and 1 <= height <= 100):
            raise ValueError("unsafe viewport")
        if (width, height) != (self.width, self.height):
            self.events["resize"] += 1
            self.cancel()
            # Modal rectangles use viewport coordinates. Do not leave an
            # unreachable old-viewport overlay intercepting post-resize input.
            if self.overlays.overlays:
                self.overlays.overlays.clear()
                self.actions["overlay_resize_dismiss"] += 1
            self.width, self.height = width, height
            self._solve()
            self.last = "resize"

    def blur(self):
        self.events["blur"] += 1
        self.cancel()
        self.last = "blur"

    def press(self, x, y, button=1):
        self.events["mouse_down"] += 1
        # A capture owns the pointer transaction until release/cancellation.
        # Duplicate/nested down events must not replace its initial geometry,
        # refocus another tile or leak through a simultaneously opening overlay.
        if self.drag is not None:
            self.actions["captured_press_ignored"] += 1
            self.last = "captured_press_ignored"
            return
        if button == 3:
            self.events["right_click"] += 1
        if button not in (1, 3):
            return
        # Top overlay owns every pointer button. A right-click outside the
        # modal may dismiss it, but must not open a second menu underneath.
        target = self.overlays.pointer(self.frame, x, y)
        if target == "dismiss-consumed":
            self.actions["menu_dismiss_consumed"] += 1
        elif target is not None and target.startswith("overlay:"):
            self.actions["overlay_pointer_consumed"] += 1
        elif button == 3:
            if target in ("fleet", "inspector"):
                self.focus = target
                self._solve()
                self.menu(anchor=(x, y))
                self.actions["context_menu_open"] += 1
                self.last = "context_menu_open:" + target
            else:
                self.last = "context_ignored"
            return
        elif target == "divider":
            self.drag = DividerDrag.begin(self.split, self.frame, x, y)
            self.actions["divider_begin"] += 1
        elif target in ("fleet", "inspector"):
            self.focus = target
            self._solve()
            self.actions["tile_focus"] += 1
        self.last = str(target)

    def move(self, x, y):
        self.events["mouse_move"] += 1
        if self.drag and self.drag.active:
            self.preview = self.drag.move(self.frame, x, y)
            self.actions["divider_preview"] += 1
            self.last = "divider_preview"

    def release(self, button=1):
        self.events["mouse_up"] += 1
        if self.drag is not None and button == 1:
            if self.drag.active:
                self.split = replace(self.split, ratio=self.drag.finish("release"))
                self.actions["divider_commit"] += 1
            self.drag = None
            self.preview = None
            self._solve()
            self.last = "divider_commit"

    def menu(self, anchor=None):
        # A modal cancels any active divider transaction. Re-opening the same
        # menu must not create invisible stacked menus after one Escape.
        self.cancel()
        if self.overlays.overlays:
            self.actions["menu_duplicate_ignored"] += 1
            return
        width, height = max(1, self.width // 2), max(1, self.height // 3)
        if anchor is None:
            left, top = self.width // 4, max(1, self.height // 4)
        else:
            left = max(0, min(anchor[0], self.width - width))
            top = max(0, min(anchor[1], self.height - height))
        self.overlays.push("menu", Rect(left, top, width, height))
        self.actions["menu_open"] += 1
        self.last = "menu_open"

    def escape(self):
        if self.cancel():
            return
        if self.overlays.escape():
            self.actions["menu_escape"] += 1
        elif self.input_armed:
            self.input_armed = False
        self.last = "escape"

    def paste(self, data):
        # Never retain/display/log payload or treat a pasted command as an action.
        self.events["paste"] += 1
        if self.input_armed and not self.overlays.overlays:
            self.pasted_chars += min(len(data), 100000)
            self.actions["paste_allowed"] += 1
        else:
            self.actions["paste_refused"] += 1
        self.last = "paste"

    def handle_key(self, key):
        """Route key commands through the top-modal barrier; return quit intent.

        Only the explicit Ctrl+T recovery / Ctrl+X crash bindings are global.
        """
        self.events["key"] += 1
        if key == "escape":
            self.escape()
        elif self.overlays.overlays:
            self.actions["overlay_key_consumed"] += 1
            self.last = "overlay_key_consumed"
        elif key == "m" and not self.input_armed:
            self.menu()
        elif key == "i":
            self.input_armed = not self.input_armed
        elif key == "q" and not self.input_armed:
            self.actions["quit_requested"] += 1
            return True
        return False

    def recover(self):
        self.cancel()
        self.overlays.overlays.clear()
        self.input_armed = False
        self.focus = "fleet"
        self._solve()
        self.actions["recover"] += 1
        self.last = "recover"

    def summary(self):
        return {
            "schemaVersion": 1,
            "evidence": "UNVERIFIED_INTERACTIVE_DIAGNOSTIC",
            "physical_tui": False,
            "method": "in-process event counts only, no external frame measurement",
            "viewport_final": [self.width, self.height],
            "events": dict(self.events),
            "actions": dict(self.actions),
            "pasted_chars_count_only": self.pasted_chars,
            "ratio": round(self.split.ratio, 6),
            "input_to_visible_frame_p95_ms": None,
            "terminal_restoration_verified": False,
        }


def create_only_receipt(path, payload):
    dest = Path(path)
    if not dest.is_absolute() or not dest.parent.is_dir():
        raise ValueError("receipt must use new absolute path in existing directory")
    if dest.resolve().is_relative_to(Path(__file__).resolve().parent.parent):
        raise ValueError("receipt must be outside source checkout")
    if payload.get("evidence") != "UNVERIFIED_INTERACTIVE_DIAGNOSTIC" or payload.get("physical_tui") is not False:
        raise ValueError("cannot certify physical evidence from fixture")
    raw = (json.dumps(payload, sort_keys=True, ensure_ascii=True, allow_nan=False) + "\n").encode("utf-8")
    if len(raw) > 8192:
        raise ValueError("receipt exceeds cap")
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_BINARY", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(dest, flags, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def render(model, ascii_only=False):
    w, h = model.width, model.height
    cells = [[" "] * w for _ in range(h)]
    def put(x, y, value):
        if 0 <= y < h:
            for j, char in enumerate(value):
                if 0 <= x + j < w:
                    cells[y][x + j] = char if ord(char) < 128 or not ascii_only else "?"
    for name, rect in model.frame.tiles.items():
        put(rect.x + 1, rect.y + 3, name.upper() + (" [FOCUS]" if model.focus == name else ""))
    if model.frame.divider:
        d = model.frame.divider
        for y in range(d.y, d.y + d.height):
            for x in range(d.x, d.x + d.width):
                cells[y][x] = "|" if ascii_only else "│"
    put(0, 0, "EDF-006 TEXTUAL WINDOWS TERMINAL FIXTURE / NOT PHYSICAL PASS")
    put(0, 1, "m menu; i arm paste; Escape cancel; Ctrl+T recover; q quit; Ctrl+X crash")
    put(0, 2, f"{w}x{h} focus={model.focus} last={model.last} ratio={model.split.ratio:.3f}")
    put(0, 4, f"mouse down/up/move={model.events['mouse_down']}/{model.events['mouse_up']}/{model.events['mouse_move']}")
    put(0, 5, f"wheel up/down={model.events['wheel_up']}/{model.events['wheel_down']} blur={model.events['blur']} resize={model.events['resize']}")
    put(0, 6, f"divider begin/commit/cancel={model.actions['divider_begin']}/{model.actions['divider_commit']}/{model.actions['divider_cancel']}")
    put(0, 7, f"paste allowed/refused={model.actions['paste_allowed']}/{model.actions['paste_refused']} armed={model.input_armed}")
    put(0, 8, f"overlay outside-consumed={model.actions['menu_dismiss_consumed']} recover={model.actions['recover']}")
    if model.preview is not None:
        put(0, 9, f"drag preview={model.preview:.3f} (no commit until release)")
    if model.overlays.overlays:
        _, d = model.overlays.overlays[-1]
        for y in range(d.y, min(h, d.y + d.height)):
            for x in range(d.x, min(w, d.x + d.width)):
                cells[y][x] = "#"
        put(d.x + 1, d.y + 1, "MENU / outside click consumed")
    put(0, h - 1, "HUMAN OBSERVER MUST VERIFY VISIBLE FRAME, TERMINAL RESTORATION")
    return "\n".join("".join(line) for line in cells)


def make_app(ascii_only=False):
    from textual import events
    from textual.app import App, ComposeResult
    from textual.widgets import Static
    from edf006_textual_probe import verify_installed_runtime_source
    verify_installed_runtime_source()

    class PhysicalApp(App[None]):
        CSS = "#surface { width: 100%; height: 100%; overflow: hidden; }"
        BINDINGS = [("ctrl+t", "recover_fixture", "Recover"),
                    ("ctrl+x", "deliberate_crash", "Crash")]

        def __init__(self):
            super().__init__()
            self.model = Fixture()

        def compose(self) -> ComposeResult:
            yield Static("EDF-006 starting", id="surface", markup=False)

        def show(self):
            self.query_one("#surface", Static).update(render(self.model, ascii_only))

        def on_mount(self):
            self.model.resize(self.screen.size.width, self.screen.size.height)
            self.show()

        def on_resize(self, event: events.Resize):
            self.model.resize(event.size.width, event.size.height)
            self.show()

        def on_app_blur(self, event: events.AppBlur):
            self.model.blur()
            self.show()

        def on_app_focus(self, event: events.AppFocus):
            self.model.events["focus"] += 1

        def on_paste(self, event: events.Paste):
            self.model.paste(event.text)
            self.show()

        def on_mouse_down(self, event: events.MouseDown):
            self.model.press(event.screen_x, event.screen_y, event.button)
            self.show()

        def on_mouse_move(self, event: events.MouseMove):
            self.model.move(event.screen_x, event.screen_y)
            self.show()

        def on_mouse_up(self, event: events.MouseUp):
            self.model.release(event.button)
            self.show()

        def on_mouse_scroll_up(self, event: events.MouseScrollUp):
            self.model.events["wheel_up"] += 1
            self.show()

        def on_mouse_scroll_down(self, event: events.MouseScrollDown):
            self.model.events["wheel_down"] += 1
            self.show()

        def on_key(self, event: events.Key):
            if self.model.handle_key(event.key):
                self.exit()
                return
            self.show()

        def action_recover_fixture(self):
            self.model.recover()
            self.show()

        def action_deliberate_crash(self):
            raise RuntimeError("EDF-006 deliberate failure for native restoration check")
    return PhysicalApp


async def headless_smoke():
    """Exercise selected Textual's actual event routing, not just model methods.

    This is still FAST-CI-HEADLESS, never physical terminal evidence.
    """
    from textual import events
    app = make_app()()
    async with app.run_test(size=(160, 48)) as pilot:
        # Overlay dismissal must consume the pointer event rather than focus a tile.
        await pilot.press("m")
        if app.model.actions["menu_open"] != 1:
            raise AssertionError("menu key missing")
        await pilot.click("#surface", offset=(2, 12))
        if (app.model.actions["menu_dismiss_consumed"] != 1
                or app.model.actions["tile_focus"] != 0):
            raise AssertionError("outside overlay click leaked into a tile")
        await pilot.press("m")
        await pilot.press("escape")
        if app.model.actions["menu_escape"] != 1:
            raise AssertionError("Escape overlay dismissal missing")

        # Real Pilot pointer events must reach the divider reducer. A move
        # previews without mutation and a release is the sole commit point.
        divider = app.model.frame.divider
        if divider is None:
            raise AssertionError("160x48 expected a movable divider")
        await pilot.mouse_down("#surface", offset=(divider.x, 15))
        await pilot.hover("#surface", offset=(divider.x + 12, 15))
        if (app.model.drag is None or app.model.preview is None
                or app.model.split.ratio != 0.5):
            raise AssertionError("pointer drag preview committed before release")
        await pilot.mouse_up("#surface", offset=(divider.x + 12, 15))
        if (app.model.actions["divider_commit"] != 1
                or app.model.split.ratio <= 0.5 or app.model.drag is not None):
            raise AssertionError("pointer release did not commit divider")
        committed = app.model.split.ratio

        # Escape and focus loss must roll back an active preview. The late
        # mouse-up after cancellation must never resurrect the transaction.
        for cancel_kind in ("escape", "blur"):
            divider = app.model.frame.divider
            await pilot.mouse_down("#surface", offset=(divider.x, 15))
            await pilot.hover("#surface", offset=(divider.x - 9, 15))
            if cancel_kind == "escape":
                await pilot.press("escape")
            else:
                app.post_message(events.AppBlur())
                await pilot.pause()
            await pilot.mouse_up("#surface", offset=(divider.x - 9, 15))
            if app.model.drag is not None or app.model.split.ratio != committed:
                raise AssertionError(f"{cancel_kind} failed to roll back capture")
        if app.model.actions["divider_cancel"] != 2:
            raise AssertionError("Escape/blur cancellations not both recorded")

        # Shrinking from fleet layout into focused 80x24 also cancels capture.
        divider = app.model.frame.divider
        await pilot.mouse_down("#surface", offset=(divider.x, 15))
        await pilot.hover("#surface", offset=(divider.x - 7, 15))
        await pilot.resize_terminal(80, 24)
        if ((app.model.width, app.model.height) != (80, 24)
                or not app.model.frame.compact or app.model.drag is not None
                or app.model.split.ratio != committed
                or app.model.actions["divider_cancel"] != 3):
            raise AssertionError("resize did not safely cancel drag")

        # A paste with command-like text is data-only, whether armed or not.
        app.post_message(events.Paste("q\nCtrl+P\nSENSITIVE-FIXTURE"))
        await pilot.pause()
        if app.model.actions["paste_refused"] != 1:
            raise AssertionError("unarmed paste was not refused")
        await pilot.press("i")
        app.post_message(events.Paste("q\nCtrl+P\nSENSITIVE-FIXTURE"))
        await pilot.pause()
        if (app.model.actions["paste_allowed"] != 1
                or "SENSITIVE-FIXTURE" in render(app.model)
                or "SENSITIVE-FIXTURE" in str(app.model.summary())):
            raise AssertionError("paste data routed as command or leaked")
        await pilot.press("ctrl+t")
        if app.model.actions["recover"] != 1 or app.model.input_armed:
            raise AssertionError("recovery did not reset fixture")

        # Cross-event race: keyboard menu while button remains held must roll
        # back the preview. The late mouse-up may not commit the old capture.
        await pilot.resize_terminal(160, 48)
        divider = app.model.frame.divider
        if divider is None:
            raise AssertionError("fleet divider unavailable after recovery")
        before_menu = app.model.split.ratio
        await pilot.mouse_down("#surface", offset=(divider.x, 15))
        await pilot.hover("#surface", offset=(divider.x + 8, 15))
        await pilot.press("m")
        if (app.model.drag is not None
                or app.model.split.ratio != before_menu
                or app.model.actions["divider_cancel"] != 4):
            raise AssertionError("opening modal did not cancel active capture")
        await pilot.mouse_up("#surface", offset=(divider.x + 8, 15))
        if (app.model.split.ratio != before_menu
                or app.model.actions["divider_commit"] != 1):
            raise AssertionError("late mouse-up committed a pre-modal drag")
        await pilot.resize_terminal(80, 24)
        if app.model.overlays.overlays or app.model.actions["overlay_resize_dismiss"] != 1:
            raise AssertionError("resize retained stale modal hit geometry")

        # A visible overlay must swallow background commands and paste, even
        # when a field was previously armed. Exercise real Textual key/paste
        # routing, then use a context-menu right-click near the screen edge.
        await pilot.resize_terminal(160, 48)
        await pilot.press("m")
        for key in ("m", "i", "q"):
            await pilot.press(key)
        app.post_message(events.Paste("q;Ctrl+P;PRIVATE-MODAL-FIXTURE"))
        await pilot.pause()
        if (app.model.actions["menu_open"] != 4
                or app.model.actions["overlay_key_consumed"] != 3
                or app.model.actions["paste_refused"] != 2
                or app.model.input_armed
                or "PRIVATE-MODAL-FIXTURE" in render(app.model)
                or "PRIVATE-MODAL-FIXTURE" in str(app.model.summary())):
            raise AssertionError("modal leaked keyboard/paste into underlying tile")
        await pilot.press("escape")
        if app.model.actions["menu_escape"] != 2:
            raise AssertionError("modal Escape failed to dismiss one level")

        await pilot.click("#surface", offset=(155, 43), button=3)
        if (app.model.focus != "inspector"
                or app.model.actions["context_menu_open"] != 1
                or app.model.actions["menu_open"] != 5):
            raise AssertionError("right-click missed the pointed tile")
        menu_rect = app.model.overlays.overlays[-1][1]
        if not (menu_rect.contains(155, 43)
                and menu_rect.x + menu_rect.width <= app.model.width
                and menu_rect.y + menu_rect.height <= app.model.height):
            raise AssertionError("edge context menu escaped the viewport")
        await pilot.click("#surface", offset=(155, 43), button=3)
        if (app.model.actions["overlay_pointer_consumed"] != 1
                or app.model.actions["menu_open"] != 5):
            raise AssertionError("right-click inside modal leaked through")
        await pilot.click("#surface", offset=(2, 12), button=3)
        if (app.model.actions["menu_dismiss_consumed"] != 2
                or app.model.actions["context_menu_open"] != 1
                or app.model.focus != "inspector"):
            raise AssertionError("outside right-click clicked through the modal")

    return {"evidence": "FAST-CI-HEADLESS", "physical_tui": False,
            "actions": dict(app.model.actions),
            "events": dict(app.model.events),
            "input_to_visible_frame_p95_ms": None}


def main(argv=None):
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--interactive", action="store_true")
    modes.add_argument("--headless-smoke", action="store_true")
    parser.add_argument("--receipt")
    parser.add_argument("--ascii", action="store_true")
    args = parser.parse_args(argv)
    if args.headless_smoke:
        if args.receipt:
            parser.error("headless mode has no physical receipt")
        import asyncio
        print(json.dumps(asyncio.run(headless_smoke()), sort_keys=True))
        return 0
    if os.name != "nt" or not sys.stdin.isatty() or not os.environ.get("WT_SESSION"):
        parser.error("interactive mode requires actual Windows Terminal, TTY and WT_SESSION")
    App = make_app(ascii_only=args.ascii)
    app = App()
    app.run()
    if args.receipt:
        result = app.model.summary()
        result["lock_sha256"] = hashlib.sha256(
            (Path(__file__).resolve().parent.parent / "manifests" / "edf006-tui-runtime.json").read_bytes()
        ).hexdigest()
        result["textual"] = "8.2.8"
        create_only_receipt(args.receipt, result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
