"""EDF-006 opt-in native Windows Console/Windows Terminal input-layout probe.

Not a selected/pinned production TUI runtime. Never imports factory code, reads
secrets, opens a VM, or writes a manager workspace. Physical evidence requires
manual execution in actual Windows Terminal; hosted unit tests are not that.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes

# Win32 records have fixed-width ABI fields even when tested on Linux, where
# ctypes.wintypes aliases may follow the host C long/wchar widths.
WIN_WORD = ctypes.c_uint16
WIN_DWORD = ctypes.c_uint32
WIN_BOOL = ctypes.c_int32
from dataclasses import dataclass, replace
import os
import sys
import time

from edf006_layout_spike import DividerDrag, OverlayStack, Rect, Split, solve
from edf006_probe_metrics import ProbeMetrics, write_receipt

KEY_EVENT = 0x0001
MOUSE_EVENT = 0x0002
WINDOW_BUFFER_SIZE_EVENT = 0x0004
FOCUS_EVENT = 0x0010
MOUSE_MOVED = 0x0001
MOUSE_WHEELED = 0x0004
MOUSE_HWHEELED = 0x0008
LEFT_BUTTON = 0x0001
# Ctrl/Alt-modified input is not an unmodified demo command. Production
# recovery bindings are owned by the future semantic command layer.
CTRL_ALT_MASK = 0x000F
# Win32 VK_PACKET represents Unicode-injected key input, including common
# paste/SendInput paths. It is not an interactive shortcut authority.
VK_PACKET = 0x00E7


class COORD(ctypes.Structure):
    _fields_ = [("X", ctypes.c_short), ("Y", ctypes.c_short)]


class SMALL_RECT(ctypes.Structure):
    _fields_ = [("Left", ctypes.c_short), ("Top", ctypes.c_short),
                ("Right", ctypes.c_short), ("Bottom", ctypes.c_short)]


class CONSOLE_SCREEN_BUFFER_INFO(ctypes.Structure):
    _fields_ = [("dwSize", COORD), ("dwCursorPosition", COORD),
                ("wAttributes", WIN_WORD), ("srWindow", SMALL_RECT),
                ("dwMaximumWindowSize", COORD)]


class KEY_EVENT_RECORD(ctypes.Structure):
    _fields_ = [("bKeyDown", WIN_BOOL), ("wRepeatCount", WIN_WORD),
                ("wVirtualKeyCode", WIN_WORD), ("wVirtualScanCode", WIN_WORD),
                ("UnicodeChar", WIN_WORD), ("dwControlKeyState", WIN_DWORD)]


class MOUSE_EVENT_RECORD(ctypes.Structure):
    _fields_ = [("dwMousePosition", COORD), ("dwButtonState", WIN_DWORD),
                ("dwControlKeyState", WIN_DWORD), ("dwEventFlags", WIN_DWORD)]


class FOCUS_EVENT_RECORD(ctypes.Structure):
    _fields_ = [("bSetFocus", WIN_BOOL)]


class EVENT_UNION(ctypes.Union):
    _fields_ = [("KeyEvent", KEY_EVENT_RECORD), ("MouseEvent", MOUSE_EVENT_RECORD),
                ("WindowBufferSizeEvent", COORD), ("FocusEvent", FOCUS_EVENT_RECORD)]


class INPUT_RECORD(ctypes.Structure):
    _fields_ = [("EventType", WIN_WORD), ("Event", EVENT_UNION)]


@dataclass(frozen=True)
class Event:
    kind: str
    x: int = 0
    y: int = 0
    value: int | str = 0


@dataclass(frozen=True)
class Viewport:
    """Visible console window, distinct from its underlying screen buffer."""
    left: int
    top: int
    width: int
    height: int

    @classmethod
    def from_buffer_info(cls, info: CONSOLE_SCREEN_BUFFER_INFO) -> Viewport:
        rect = info.srWindow
        width, height = rect.Right - rect.Left + 1, rect.Bottom - rect.Top + 1
        if width < 1 or height < 1:
            raise ValueError("invalid console visible-window geometry")
        return cls(rect.Left, rect.Top, width, height)


def require_physical_viewport(viewport: Viewport,
                              expected_width: int | None,
                              expected_height: int | None) -> tuple[int, int]:
    """CLI size flags assert actual native viewport; they never fabricate one."""
    if not 1 <= viewport.width <= 300 or not 1 <= viewport.height <= 100:
        raise ValueError("viewport outside supported diagnostic bounds")
    if ((expected_width is not None and expected_width != viewport.width)
            or (expected_height is not None and expected_height != viewport.height)):
        raise ValueError("expected viewport does not match actual console window")
    return viewport.width, viewport.height


def decode(record: INPUT_RECORD, previous_left: bool,
           viewport: Viewport | None = None) -> tuple[Event | None, bool]:
    """Translate native records; key-up is ignored, focus loss resets capture.

    Mouse wheel uses signed high word; never interprets wheel delta as button.
    """
    kind = record.EventType
    if kind == FOCUS_EVENT:
        return (Event("focus_gain") if record.Event.FocusEvent.bSetFocus
                else Event("focus_loss")), False if not record.Event.FocusEvent.bSetFocus else previous_left
    if kind == WINDOW_BUFFER_SIZE_EVENT:
        if viewport is not None:
            return Event("resize", viewport.width, viewport.height), previous_left
        # Synthetic ABI-only tests without a native console keep buffer dimensions.
        size = record.Event.WindowBufferSizeEvent
        return Event("resize", max(1, size.X), max(1, size.Y)), previous_left
    if kind == KEY_EVENT:
        key = record.Event.KeyEvent
        if not key.bKeyDown or key.dwControlKeyState & CTRL_ALT_MASK:
            return None, previous_left
        # Packet-marked Unicode input (often clipboard paste), unknown virtual
        # keys and inconsistent VK/Unicode pairs cannot become app shortcuts.
        # ReadConsoleInputW cannot identify *every* paste implementation.
        if key.wVirtualKeyCode in (0, VK_PACKET):
            return None, previous_left
        if key.wVirtualKeyCode == 0x1B:
            return (Event("key", value="Escape") if key.UnicodeChar in (0, 0x1B)
                    else None), previous_left
        value = chr(key.UnicodeChar)
        if (value.isprintable() and value.lower() in ("q", "m", "t")
                and key.wVirtualKeyCode == ord(value.upper())):
            return Event("key", value=value.lower()), previous_left
        return None, previous_left
    if kind != MOUSE_EVENT:
        return None, previous_left
    mouse = record.Event.MouseEvent
    x, y = mouse.dwMousePosition.X, mouse.dwMousePosition.Y
    if viewport is not None:
        # Win32 mouse positions are screen-buffer coordinates, not visible-window
        # offsets. Scrollback/viewport origin must not shift hit-test targets.
        x, y = x - viewport.left, y - viewport.top
    flags = mouse.dwEventFlags
    if flags in (MOUSE_WHEELED, MOUSE_HWHEELED):
        delta = ctypes.c_short((mouse.dwButtonState >> 16) & 0xFFFF).value
        return Event("wheel", x, y, delta), previous_left
    left = bool(mouse.dwButtonState & LEFT_BUTTON)
    if flags == MOUSE_MOVED:
        # A coalesced button-UP movement must end existing divider capture.
        # Never synthesize DOWN on movement: after focus loss, an already-held
        # button could otherwise reenter capture without a fresh press record.
        if previous_left and not left:
            return Event("release", x, y), left
        return Event("move", x, y), left
    if flags == 0:
        if left and not previous_left:
            return Event("press", x, y), left
        if previous_left and not left:
            return Event("release", x, y), left
    return None, left


class Demo:
    """Inert layout proof: no factory connection, dispatch or persistence."""
    def __init__(self, width: int, height: int):
        self.width, self.height = width, height
        self.split = Split("fleet", "inspector")
        self.frame = solve(width, height, self.split)
        self.drag: DividerDrag | None = None
        self.overlays = OverlayStack()
        self.focus = "fleet"
        self.last = "startup"
        self.count = 0
        self.wheel = 0
        self.running = True

    def apply(self, event: Event) -> None:
        self.count += 1
        self.last = event.kind
        if event.kind == "focus_loss":
            if self.drag and self.drag.active:
                self.split = replace(self.split, ratio=self.drag.finish("focus_loss"))
                self.drag = None
                self.frame = solve(self.width, self.height, self.split, self.focus)
        elif event.kind == "resize":
            if event.x > 300 or event.y > 100:
                self.running = False  # Refuse unbounded repaint, restore console.
                return
            # Any resize ends an in-progress transaction: its original
            # geometry is no longer valid even when both viewports are wide.
            if self.drag and self.drag.active:
                self.split = replace(self.split, ratio=self.drag.finish("focus_loss"))
                self.drag = None
            self.width, self.height = event.x, event.y
            self.frame = solve(self.width, self.height, self.split, self.focus)
        elif event.kind == "key":
            if event.value == "Escape":
                if self.drag and self.drag.active:
                    self.split = replace(self.split, ratio=self.drag.finish("escape"))
                    self.drag = None
                    self.frame = solve(self.width, self.height, self.split, self.focus)
                elif not self.overlays.escape():
                    self.running = False
            elif event.value == "q":
                self.running = False
            elif event.value == "m":
                self.overlays.push("menu", Rect(max(0, self.width // 4),
                                                max(1, self.height // 4),
                                                max(1, self.width // 2),
                                                max(1, self.height // 3)))
            elif event.value == "t":
                self.focus = "inspector" if self.focus == "fleet" else "fleet"
                self.frame = solve(self.width, self.height, self.split, self.focus)
        elif event.kind == "press":
            target = self.overlays.pointer(self.frame, event.x, event.y)
            if target == "divider":
                self.drag = DividerDrag.begin(self.split, self.frame, event.x, event.y)
            elif target in ("fleet", "inspector"):
                self.focus = target
                self.frame = solve(self.width, self.height, self.split, self.focus)
        elif event.kind == "move":
            if self.drag and self.drag.active:
                self.drag.move(self.frame, event.x, event.y)
                self.frame = solve(self.width, self.height,
                                   replace(self.split, ratio=self.drag.preview), self.focus)
        elif event.kind == "release":
            if self.drag and self.drag.active:
                self.split = replace(self.split, ratio=self.drag.finish("release"))
                self.drag = None
                self.frame = solve(self.width, self.height, self.split, self.focus)
        elif event.kind == "wheel":
            self.wheel += 1 if event.value > 0 else -1 if event.value < 0 else 0


def frame_text(demo: Demo) -> str:
    """Trusted ASCII-only fixture; never include untrusted factory/log text."""
    width, height = demo.width, demo.height
    grid = [[" " for _ in range(width)] for _ in range(height)]
    def put(x: int, y: int, message: str) -> None:
        if 0 <= y < height:
            for i, char in enumerate(message):
                if 0 <= x + i < width:
                    grid[y][x + i] = char
    for name, rect in demo.frame.tiles.items():
        put(rect.x, rect.y, "[" + name.upper() + (" *" if name == demo.focus else "") + "]")
    if demo.frame.divider:
        div = demo.frame.divider
        for n in range(div.height if div.width == 1 else div.width):
            put(div.x + (n if div.width > 1 else 0),
                div.y + (n if div.height > 1 else 0), "|")
    if demo.overlays.overlays:
        _, rect = demo.overlays.overlays[-1]
        put(rect.x, rect.y, "[MENU - ESC to dismiss]")
    put(0, height - 2, "m menu | t focus | drag divider | q quit | Esc cancel/quit")
    put(0, height - 1, f"event={demo.last} count={demo.count} wheel={demo.wheel} ")
    return "\x1b[H" + "\r\n".join("".join(row) for row in grid)


class WindowsConsole:
    """Restore both console modes and alternate-screen/cursor on every exit."""
    def __enter__(self):
        if os.name != "nt":
            raise RuntimeError("native console probe requires Windows")
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.GetStdHandle.argtypes = [wintypes.DWORD]
        kernel.GetStdHandle.restype = wintypes.HANDLE
        for function in ("GetConsoleMode", "SetConsoleMode"):
            getattr(kernel, function).argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)] if function == "GetConsoleMode" else [wintypes.HANDLE, wintypes.DWORD]
            getattr(kernel, function).restype = wintypes.BOOL
        kernel.ReadConsoleInputW.argtypes = [wintypes.HANDLE, ctypes.POINTER(INPUT_RECORD), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
        kernel.ReadConsoleInputW.restype = wintypes.BOOL
        kernel.GetConsoleScreenBufferInfo.argtypes = [
            wintypes.HANDLE, ctypes.POINTER(CONSOLE_SCREEN_BUFFER_INFO)]
        kernel.GetConsoleScreenBufferInfo.restype = wintypes.BOOL
        self.kernel = kernel
        self.input_handle = kernel.GetStdHandle(wintypes.DWORD(-10))
        self.output_handle = kernel.GetStdHandle(wintypes.DWORD(-11))
        self.input_mode, self.output_mode = wintypes.DWORD(), wintypes.DWORD()
        if not kernel.GetConsoleMode(self.input_handle, ctypes.byref(self.input_mode)) or not kernel.GetConsoleMode(self.output_handle, ctypes.byref(self.output_mode)):
            raise RuntimeError("requires interactive Windows console input/output")
        # Retain processed Ctrl+C; disable Quick Edit and VT input, enable mouse/resize.
        input_flags = (self.input_mode.value | 0x0080 | 0x0010 | 0x0008) & ~(0x0040 | 0x0200)
        output_flags = self.output_mode.value | 0x0001 | 0x0004
        if not kernel.SetConsoleMode(self.output_handle, output_flags):
            raise OSError(ctypes.get_last_error(), "cannot enable VT rendering")
        if not kernel.SetConsoleMode(self.input_handle, input_flags):
            kernel.SetConsoleMode(self.output_handle, self.output_mode.value)
            raise OSError(ctypes.get_last_error(), "cannot enable mouse/resize input")
        try:
            sys.stdout.write("\x1b[?1049h\x1b[?25l\x1b[2J")
            sys.stdout.flush()
        except BaseException:
            self.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *_):
        try:
            sys.stdout.write("\x1b[0m\x1b[?25h\x1b[?1049l")
            sys.stdout.flush()
        finally:
            self.kernel.SetConsoleMode(self.input_handle, self.input_mode.value)
            self.kernel.SetConsoleMode(self.output_handle, self.output_mode.value)

    def viewport(self) -> Viewport:
        info = CONSOLE_SCREEN_BUFFER_INFO()
        if not self.kernel.GetConsoleScreenBufferInfo(
                self.output_handle, ctypes.byref(info)):
            raise OSError(ctypes.get_last_error(), "GetConsoleScreenBufferInfo failed")
        return Viewport.from_buffer_info(info)

    def read(self) -> INPUT_RECORD:
        record, count = INPUT_RECORD(), wintypes.DWORD()
        if not self.kernel.ReadConsoleInputW(self.input_handle, ctypes.byref(record), 1, ctypes.byref(count)) or count.value != 1:
            raise OSError(ctypes.get_last_error(), "ReadConsoleInputW failed")
        return record


def main() -> int:
    parser = argparse.ArgumentParser(description="EDF-006 Windows Terminal non-production input probe")
    parser.add_argument("--width", type=int, default=None)
    parser.add_argument("--height", type=int, default=None)
    parser.add_argument("--receipt", metavar="ABSOLUTE_JSON_PATH", default=None,
                        help="opt-in create-only timing summary outside the repository")
    opts = parser.parse_args()
    previous_left = False
    metrics = ProbeMetrics()
    try:
        with WindowsConsole() as native:
            # The console buffer can be taller/wider than the visible viewport.
            # Native screen-buffer information is the geometry authority.
            width, height = require_physical_viewport(
                native.viewport(), opts.width, opts.height)
            demo = Demo(width, height)
            sys.stdout.write(frame_text(demo))
            sys.stdout.flush()
            while demo.running:
                record = native.read()
                read_return_ns = time.perf_counter_ns()
                current_view = (native.viewport() if record.EventType in
                                (MOUSE_EVENT, WINDOW_BUFFER_SIZE_EVENT) else None)
                # A mouse event may arrive before a buffer-size event; never
                # hit-test against geometry that no longer matches the viewport.
                if (current_view is not None and record.EventType == MOUSE_EVENT
                        and (current_view.width, current_view.height)
                        != (demo.width, demo.height)):
                    demo.apply(Event("resize", current_view.width, current_view.height))
                event, previous_left = decode(record, previous_left, current_view)
                if event is not None:
                    demo.apply(event)
                    if demo.running:
                        compose_start_ns = time.perf_counter_ns()
                        frame = frame_text(demo)
                        compose_end_ns = time.perf_counter_ns()
                        sys.stdout.write(frame)
                        sys.stdout.flush()
                        flush_end_ns = time.perf_counter_ns()
                        metrics.record(event.kind, read_return_ns, compose_start_ns,
                                       compose_end_ns, flush_end_ns)
                    else:
                        metrics.record(event.kind, read_return_ns)
    except KeyboardInterrupt:
        pass
    # Executed after native console restoration. No auto-persistence.
    if opts.receipt and any(metrics.kind_counts.values()):
        write_receipt(opts.receipt, metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
