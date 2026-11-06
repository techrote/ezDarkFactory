"""EDF-006 semantic scene/theme/accessibility and logical-damage spike.

Framework-neutral and deliberately inert: no terminal probing, filesystem I/O,
factory discovery, broker dispatch, subprocesses, or VM mutation.  It models
only the semantic cell/composition contract that a selected EDF-006 renderer
must preserve.
"""

from __future__ import annotations

from dataclasses import dataclass
import unicodedata

REQUIRED_ROLES = frozenset({
    "background", "text", "muted", "border", "title", "accent", "heading",
    "code", "link", "selection", "diagnostic", "status", "warning", "error",
    "success", "stale", "unknown", "conflict", "destructive",
})
STATE_MODIFIERS = frozenset({
    "focused", "hover", "pressed", "selected", "disabled", "busy", "caution",
    "destructive",
})
COLOR_MODES = ("mono", "ansi16", "ansi256", "truecolor")
MOTION_MODES = ("off", "reduced", "full")
PROTECTION = {"decoration": 0, "content": 1, "critical": 2}
WIDE_CONTINUATION = "\0"

# Fixed, embedded palettes: external theme execution/loading is intentionally out
# of scope for the EDF-006 spike.  Values are presentation data only.
SAFE_RGB = {
    "background": (11, 15, 20), "text": (215, 221, 232), "muted": (138, 147, 165),
    "border": (93, 107, 122), "title": (97, 218, 251), "accent": (97, 218, 251),
    "heading": (229, 192, 123), "code": (198, 120, 221), "link": (86, 182, 194),
    "selection": (11, 15, 20), "diagnostic": (171, 178, 191), "status": (152, 195, 121),
    "warning": (229, 192, 123), "error": (224, 108, 117), "success": (152, 195, 121),
    "stale": (209, 154, 102), "unknown": (171, 178, 191), "conflict": (224, 108, 117),
    "destructive": (255, 107, 107),
}
HIGH_CONTRAST_RGB = {
    role: ((0, 0, 0) if role in {"background", "selection"} else (255, 255, 255))
    for role in REQUIRED_ROLES
}
HIGH_CONTRAST_RGB.update({
    "warning": (255, 255, 0), "error": (255, 64, 64), "conflict": (255, 64, 64),
    "destructive": (255, 64, 64), "success": (64, 255, 64), "link": (64, 255, 255),
})

ANSI256 = {
    "background": 232, "text": 253, "muted": 246, "border": 244, "title": 81,
    "accent": 81, "heading": 180, "code": 176, "link": 73, "selection": 16,
    "diagnostic": 250, "status": 114, "warning": 180, "error": 168, "success": 114,
    "stale": 173, "unknown": 250, "conflict": 168, "destructive": 203,
}
ANSI16 = {
    "background": 30, "text": 97, "muted": 37, "border": 90, "title": 96,
    "accent": 96, "heading": 93, "code": 95, "link": 96, "selection": 30,
    "diagnostic": 37, "status": 92, "warning": 93, "error": 91, "success": 92,
    "stale": 33, "unknown": 37, "conflict": 91, "destructive": 91,
}
MONO_ATTR = {
    "title": "1", "accent": "1", "heading": "1", "code": "2", "link": "4",
    "selection": "7", "warning": "1", "error": "1;4", "success": "1",
    "stale": "2", "unknown": "2", "conflict": "1;4", "destructive": "1;4",
}
STATUS_PREFIX = {
    "status": "STATUS", "warning": "WARNING", "error": "ERROR", "success": "SUCCESS",
    "stale": "STALE", "unknown": "UNKNOWN", "conflict": "CONFLICT",
    "destructive": "DESTRUCTIVE",
}
ASCII_GLYPHS = {
    "─": "-", "│": "|", "┌": "+", "┐": "+", "└": "+", "┘": "+",
    "├": "+", "┤": "+", "┬": "+", "┴": "+", "┼": "+", "•": "*",
    "▶": ">", "◀": "<", "✓": "+", "✗": "x", "…": ".",
}


@dataclass(frozen=True)
class Capabilities:
    color: str = "ansi16"
    unicode: bool = True
    motion: str = "full"
    high_contrast: bool = False

    def __post_init__(self) -> None:
        if self.color not in COLOR_MODES or self.motion not in MOTION_MODES:
            raise ValueError("invalid presentation capabilities")

    @classmethod
    def negotiate(cls, *, preferred_color: str = "truecolor", max_color: str = "truecolor",
                  unicode_preferred: bool = True, unicode_supported: bool = True,
                  preferred_motion: str = "full", reduced_motion: bool = False,
                  motion_supported: bool = True, high_contrast: bool = False) -> "Capabilities":
        if preferred_color not in COLOR_MODES or max_color not in COLOR_MODES:
            raise ValueError("invalid color capability")
        if preferred_motion not in MOTION_MODES:
            raise ValueError("invalid motion preference")
        color = COLOR_MODES[min(COLOR_MODES.index(preferred_color), COLOR_MODES.index(max_color))]
        unicode = bool(unicode_preferred and unicode_supported)
        if not motion_supported:
            motion = "off"
        elif reduced_motion and preferred_motion == "full":
            motion = "reduced"
        else:
            motion = preferred_motion
        return cls(color=color, unicode=unicode, motion=motion, high_contrast=high_contrast)


@dataclass(frozen=True)
class Cell:
    char: str = " "
    role: str = "text"
    protection: str = "content"
    modifiers: frozenset[str] = frozenset()

    def __post_init__(self) -> None:
        if self.role not in REQUIRED_ROLES or self.protection not in PROTECTION:
            raise ValueError("invalid semantic cell")
        if not self.modifiers <= STATE_MODIFIERS:
            raise ValueError("invalid state modifier")
        if not isinstance(self.char, str) or len(self.char) != 1:
            raise ValueError("cell requires one code point")


class Scene:
    """Fixed-size semantic scene with protection-aware writes."""

    def __init__(self, width: int, height: int) -> None:
        if type(width) is not int or type(height) is not int or width < 1 or height < 1:
            raise ValueError("positive integer scene dimensions required")
        self.width, self.height = width, height
        self._cells = [Cell(role="background", protection="decoration")
                       for _ in range(width * height)]

    def _index(self, x: int, y: int) -> int:
        if not (0 <= x < self.width and 0 <= y < self.height):
            raise IndexError("cell outside scene")
        return y * self.width + x

    def cell(self, x: int, y: int) -> Cell:
        return self._cells[self._index(x, y)]

    def _glyph_span(self, x: int, y: int) -> tuple[int, ...]:
        idx = self._index(x, y)
        cell = self._cells[idx]
        if cell.char == WIDE_CONTINUATION and x > 0:
            return (idx - 1, idx)
        if x + 1 < self.width and self._cells[idx + 1].char == WIDE_CONTINUATION:
            return (idx, idx + 1)
        return (idx,)

    def put(self, x: int, y: int, char: str, *, role: str = "text",
            protection: str = "content", modifiers: frozenset[str] = frozenset()) -> bool:
        if not isinstance(char, str) or len(char) != 1:
            raise ValueError("put expects one code point")
        if role not in REQUIRED_ROLES or protection not in PROTECTION or not modifiers <= STATE_MODIFIERS:
            raise ValueError("invalid semantic write")
        if _unsafe_control(char):
            char = "?"
        width = _display_width(char)
        if width == 0:
            char, width = "?", 1
        if width == 2 and x + 1 >= self.width:
            return False  # atomic clip: never place half a wide glyph
        targets = tuple(range(self._index(x, y), self._index(x, y) + width))
        old = set()
        for xx in range(x, x + width):
            old.update(self._glyph_span(xx, y))
        affected = old | set(targets)
        if any(PROTECTION[self._cells[i].protection] > PROTECTION[protection] for i in affected):
            return False
        background = Cell(role="background", protection="decoration")
        for i in affected:
            self._cells[i] = background
        self._cells[targets[0]] = Cell(char, role, protection, modifiers)
        if width == 2:
            self._cells[targets[1]] = Cell(WIDE_CONTINUATION, role, protection, modifiers)
        return True

    def write(self, x: int, y: int, text: str, *, role: str = "text",
              protection: str = "content", modifiers: frozenset[str] = frozenset()) -> int:
        if not isinstance(text, str):
            raise TypeError("text must be str")
        cursor = x
        for char in text:
            width = 1 if _unsafe_control(char) else max(1, _display_width(char))
            if cursor >= self.width or (width == 2 and cursor + 1 >= self.width):
                break
            if not self.put(cursor, y, char, role=role, protection=protection, modifiers=modifiers):
                break
            cursor += width
        return cursor - x

    def snapshot(self) -> tuple[Cell, ...]:
        return tuple(self._cells)


def _unsafe_control(char: str) -> bool:
    return unicodedata.category(char) in {"Cc", "Cs"}


def _display_width(char: str) -> int:
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in {"W", "F"} else 1


def _ascii_char(char: str) -> str:
    if char == WIDE_CONTINUATION:
        return ""
    if char.isascii() and not _unsafe_control(char):
        return char
    if char in ASCII_GLYPHS:
        return ASCII_GLYPHS[char]
    return "??" if _display_width(char) == 2 else "?"


def plain_rows(scene: Scene, capabilities: Capabilities) -> tuple[str, ...]:
    rows = []
    for y in range(scene.height):
        row = []
        for x in range(scene.width):
            char = scene.cell(x, y).char
            if char == WIDE_CONTINUATION:
                continue
            row.append(char if capabilities.unicode else _ascii_char(char))
        rows.append("".join(row))
    return tuple(rows)


def status_text(role: str, message: str) -> str:
    if role not in STATUS_PREFIX or not isinstance(message, str) or not message.strip():
        raise ValueError("status text requires a semantic status role and nonempty label")
    safe = "".join("?" if _unsafe_control(ch) else ch for ch in message.strip())
    return f"{STATUS_PREFIX[role]}: {safe}"


def sgr(role: str, capabilities: Capabilities, modifiers: frozenset[str] = frozenset()) -> str:
    """Return a deterministic SGR prefix for one semantic role."""
    if role not in REQUIRED_ROLES or not modifiers <= STATE_MODIFIERS:
        raise ValueError("invalid semantic style")
    attrs: list[str] = []
    if capabilities.color == "truecolor":
        rgb = (HIGH_CONTRAST_RGB if capabilities.high_contrast else SAFE_RGB)[role]
        attrs.append(f"38;2;{rgb[0]};{rgb[1]};{rgb[2]}")
    elif capabilities.color == "ansi256":
        attrs.append(f"38;5;{ANSI256[role]}")
    elif capabilities.color == "ansi16":
        attrs.append(str(ANSI16[role]))
    elif role in MONO_ATTR:
        attrs.extend(MONO_ATTR[role].split(";"))
    if role == "selection" or "selected" in modifiers:
        attrs.append("7")
    if "focused" in modifiers or role in {"title", "heading"}:
        attrs.append("1")
    if "disabled" in modifiers:
        attrs.append("2")
    if "destructive" in modifiers and "4" not in attrs:
        attrs.append("4")
    return "\x1b[" + ";".join(dict.fromkeys(attrs or ["0"])) + "m"


def logical_damage(previous: Scene, current: Scene) -> tuple[tuple[int, int], ...]:
    if (previous.width, previous.height) != (current.width, current.height):
        return tuple((x, y) for y in range(current.height) for x in range(current.width))
    a, b = previous.snapshot(), current.snapshot()
    return tuple((i % current.width, i // current.width) for i, pair in enumerate(zip(a, b))
                 if pair[0] != pair[1])
