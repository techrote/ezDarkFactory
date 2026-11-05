"""EDF-006 framework-neutral, synthetic TUI layout/input spike.

This is not a terminal driver or production manager. It has no filesystem,
VM, broker, or subprocess access; Windows Terminal acceptance is separate.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from math import isfinite


@dataclass(frozen=True)
class Rect:
    x: int
    y: int
    width: int
    height: int

    def contains(self, x: int, y: int) -> bool:
        return self.x <= x < self.x + self.width and self.y <= y < self.y + self.height


@dataclass(frozen=True)
class Split:
    first: str
    second: str
    axis: str = "columns"  # columns = left/right; rows = top/bottom
    ratio: float = 0.5
    min_first: int = 24
    min_second: int = 24

    def __post_init__(self) -> None:
        if (self.first == self.second or not self.first or not self.second
                or self.axis not in {"columns", "rows"}
                or not isfinite(self.ratio) or not 0 <= self.ratio <= 1
                or self.min_first < 1 or self.min_second < 1):
            raise ValueError("invalid split configuration")


@dataclass(frozen=True)
class Frame:
    root: Rect
    tiles: dict[str, Rect]
    divider: Rect | None
    compact: bool

    def hit(self, x: int, y: int) -> str | None:
        # Hit testing exclusively uses the final solved geometry.
        if not self.root.contains(x, y):
            return None
        if self.divider is not None and self.divider.contains(x, y):
            return "divider"
        for tile_id, rect in self.tiles.items():
            if rect.contains(x, y):
                return tile_id
        return None


def solve(width: int, height: int, split: Split, focused: str | None = None) -> Frame:
    """Deterministically solve a single split with one-cell divider.

    40x12 and 80x24 are focused modes, not crushed split layouts.
    Invalid / insufficient geometry becomes a safe, selectable single tile.
    """
    if width < 1 or height < 1:
        raise ValueError("viewport must have positive dimensions")
    root = Rect(0, 0, width, height)
    focus = focused if focused in (split.first, split.second) else split.first
    axis_size = width if split.axis == "columns" else height
    usable = axis_size - 1
    compact = (width < 120 or height < 40
               or usable < split.min_first + split.min_second)
    if compact:
        return Frame(root, {focus: root}, None, True)
    first_size = max(split.min_first, min(usable - split.min_second,
                                         int(usable * split.ratio + 0.5)))
    second_size = usable - first_size
    if split.axis == "columns":
        first = Rect(0, 0, first_size, height)
        divider = Rect(first_size, 0, 1, height)
        second = Rect(first_size + 1, 0, second_size, height)
    else:
        first = Rect(0, 0, width, first_size)
        divider = Rect(0, first_size, width, 1)
        second = Rect(0, first_size + 1, width, second_size)
    return Frame(root, {split.first: first, split.second: second}, divider, False)


@dataclass
class DividerDrag:
    """Transactional divider capture; move previews but never commits."""

    split: Split
    initial: float
    preview: float
    active: bool = True

    @classmethod
    def begin(cls, split: Split, frame: Frame, x: int, y: int) -> DividerDrag:
        if frame.divider is None or not frame.divider.contains(x, y):
            raise ValueError("divider capture requires a hit on the solved divider")
        return cls(split, split.ratio, split.ratio)

    def move(self, frame: Frame, x: int, y: int) -> float:
        if not self.active:
            raise ValueError("capture has finished")
        if frame.compact or frame.divider is None:
            self.preview = self.initial
            self.active = False  # Resizing into compact mode cancels capture.
            return self.initial
        size = frame.root.width if self.split.axis == "columns" else frame.root.height
        available = size - 1
        position = x - frame.root.x if self.split.axis == "columns" else y - frame.root.y
        chosen = max(self.split.min_first,
                     min(available - self.split.min_second, position))
        self.preview = chosen / available
        return self.preview

    def finish(self, reason: str) -> float:
        if not self.active or reason not in {"release", "escape", "focus_loss"}:
            raise ValueError("invalid capture transition")
        self.active = False
        return self.preview if reason == "release" else self.initial


@dataclass
class OverlayStack:
    overlays: list[tuple[str, Rect]] = field(default_factory=list)

    def push(self, name: str, rect: Rect) -> None:
        if not name or rect.width < 1 or rect.height < 1:
            raise ValueError("invalid overlay")
        self.overlays.append((name, rect))

    def pointer(self, frame: Frame, x: int, y: int) -> str | None:
        if self.overlays:
            name, rect = self.overlays[-1]
            if rect.contains(x, y):
                return "overlay:" + name
            self.overlays.pop()
            return "dismiss-consumed"  # No click-through to tiles or dividers.
        return frame.hit(x, y)

    def escape(self) -> bool:
        if not self.overlays:
            return False
        self.overlays.pop()  # Exactly one logical level.
        return True


@dataclass
class TileWorkspace:
    """Retains tile-local state independently of visibility or layout mode."""

    tile_state: dict[str, dict[str, object]] = field(default_factory=dict)
    hidden: set[str] = field(default_factory=set)

    def hide(self, tile_id: str) -> None:
        if tile_id not in self.tile_state:
            raise KeyError(tile_id)
        self.hidden.add(tile_id)

    def restore_all(self) -> None:
        self.hidden.clear()

    def safe_session_load(self, value: object) -> bool:
        """Fail closed on corruption without destroying existing tile state."""
        if (not isinstance(value, dict) or type(value.get("schemaVersion")) is not int
                or value["schemaVersion"] != 1):
            return False
        hidden = value.get("hidden")
        if (not isinstance(hidden, list) or any(not isinstance(t, str) for t in hidden)
                or len(hidden) != len(set(hidden))
                or any(t not in self.tile_state for t in hidden)):
            return False
        self.hidden = set(hidden)
        return True
