"""EDF-006 inert semantic command registry (synthetic SOURCE/FAST-CI pre-spike).

Routes create immutable intents, NEVER dispatch or authorize operations.
The accepted EDF-005 typed control plane must reverify revisions, identities,
capabilities and locks on every subsequent real dispatch.
"""
from dataclasses import dataclass
import re

FACTORY = re.compile(r"fct_[0-9a-f]{32}\Z")
INSTANCE = re.compile(r"ins_[0-9a-f]{32}\Z")
GENERATION = re.compile(r"[0-9a-f]{32}\Z")
RESERVED = {"Ctrl+P": "command_palette.open", "Ctrl+T": "tile.restore_all",
            "Tab": "view.focus_next", "Shift+Tab": "view.focus_previous",
            "Escape": "overlay.cancel"}

# (semantic id, target scope, EDF-005 capability, safety class)
DEFINITIONS = (
    ("factory.register", "path", "", "ordinary"),
    ("factory.unregister", "factory", "", "ordinary"),
    ("factory.refresh", "factory", "", "read"),
    ("factory.rename_alias", "factory", "", "ordinary"),
    ("factory.open_root", "path", "", "read"),
    ("factory.resolve_identity_conflict", "factory", "", "read"),
    ("instance.create", "factory", "instance.create", "ordinary"),
    ("instance.start", "instance", "instance.start", "ordinary"),
    ("instance.stop", "instance", "instance.stop", "sensitive"),
    ("instance.open_shell", "instance", "instance.shell_descriptor", "ordinary"),
    ("instance.exec", "instance", "instance.exec", "ordinary"),
    ("instance.copy_to", "instance", "instance.copy_to", "ordinary"),
    ("instance.copy_from", "instance", "instance.copy_from", "ordinary"),
    ("instance.diagnose", "instance", "instance.diagnose", "read"),
    ("instance.reset", "instance", "instance.reset", "destructive"),
    ("instance.clone_fresh", "instance", "instance.clone", "sensitive"),
    ("instance.clone_stateful", "instance", "instance.clone", "sensitive"),
    ("instance.export", "instance", "instance.export", "sensitive"),
    ("instance.import", "factory", "instance.import", "sensitive"),
    ("factory.portability_check", "factory", "factory.portability", "read"),
    ("view.focus_next", "ui", "", "read"),
    ("view.focus_previous", "ui", "", "read"),
    ("tile.hide", "tile", "", "read"),
    ("tile.restore_all", "ui", "", "read"),
    ("tile.maximize_toggle", "tile", "", "read"),
    ("layout.preset_select", "ui", "", "read"),
    ("layout.reset", "ui", "", "read"),
    ("theme.select", "ui", "", "read"),
    ("filter.open", "ui", "", "read"),
    ("help.open", "ui", "", "read"),
    ("command_palette.open", "ui", "", "read"),
    ("app.quit_guarded", "ui", "", "sensitive"),
    ("overlay.cancel", "ui", "", "read"),
)


class CommandRefused(ValueError):
    """No intent emitted; no operation executed."""


@dataclass(frozen=True)
class Context:
    factory_id: str = ""
    instance_id: str = ""
    generation: str = ""
    tile_id: str = ""
    path: str = ""
    capabilities: frozenset[str] = frozenset()
    current: bool = False
    conflict: bool = False


@dataclass(frozen=True)
class Intent:
    command_id: str
    factory_id: str
    instance_id: str
    generation: str
    confirmation: str
    concurrency: str
    retry: str


class CommandRegistry:
    def __init__(self, definitions=DEFINITIONS, reserved=RESERVED):
        self.entries = {}
        self.routes = {}
        for name, scope, capability, safety in definitions:
            if (name in self.entries or not re.fullmatch(r"[a-z_]+\.[a-z_]+", name)
                    or scope not in {"ui", "tile", "path", "factory", "instance"}
                    or safety not in {"read", "ordinary", "sensitive", "destructive"}
                    or (safety == "destructive" and scope != "instance")):
                raise ValueError("invalid or duplicate semantic command")
            self.entries[name] = (scope, capability, safety)
            for surface, route in (("keyboard", "palette:" + name),
                                   ("pointer", "menu:" + name)):
                if (surface, route) in self.routes:
                    raise ValueError("ambiguous input route")
                self.routes[surface, route] = name
        for key, name in reserved.items():
            if name not in self.entries or ("keyboard", key) in self.routes:
                raise ValueError("missing or colliding recovery binding")
            self.routes["keyboard", key] = name
        self.reserved = dict(reserved)

    def audit(self):
        if set(dict((name, True) for name, *_ in DEFINITIONS)) - set(self.entries):
            raise ValueError("missing required semantic command")
        if any(self.routes.get(("keyboard", key)) != name
               for key, name in RESERVED.items()):
            raise ValueError("reserved recovery route changed")
        if any(("keyboard", "palette:" + name) not in self.routes
               or ("pointer", "menu:" + name) not in self.routes
               for name in self.entries):
            raise ValueError("missing keyboard/pointer parity")
        if any(re.search(r"\b(?:F(?:[1-9]|1\d|2[0-4])|Numpad\w*|PageUp|PageDown)\b",
                         route, re.I)
               for (surface, route) in self.routes if surface == "keyboard"):
            raise ValueError("unsupported keyboard-only control")

    def resolve(self, surface: str, route: str, ctx: Context) -> Intent | None:
        if surface not in {"keyboard", "pointer"}:
            raise ValueError("unsupported input surface")
        name = self.routes.get((surface, route))
        if name is None:
            return None
        scope, capability, safety = self.entries[name]
        if scope in {"factory", "instance"}:
            if not FACTORY.fullmatch(ctx.factory_id):
                raise CommandRefused("missing verified factory identity")
            if (ctx.conflict or not ctx.current) and name not in {
                    "factory.refresh", "factory.resolve_identity_conflict"}:
                raise CommandRefused("conflict/stale identity holds root dispatch")
        if scope == "instance" and (not INSTANCE.fullmatch(ctx.instance_id)
                                     or not GENERATION.fullmatch(ctx.generation)):
            raise CommandRefused("missing exact instance identity and generation")
        if scope == "tile" and not ctx.tile_id:
            raise CommandRefused("missing selected tile")
        if scope == "path" and not ctx.path.strip():
            raise CommandRefused("missing explicit path")
        if capability and capability not in ctx.capabilities:
            raise CommandRefused("capability was not advertised")
        confirm = ("target-and-consequence" if safety in {"sensitive", "destructive"}
                   else "target" if safety == "ordinary" else "none")
        concurrency = ("workspace-write" if name in {
            "factory.register", "factory.unregister", "factory.rename_alias"}
                       else "root-write" if safety != "read" and scope in {
                           "factory", "instance"}
                       else "root-read" if scope in {"factory", "instance"}
                       else "ui")
        retry = ("safe-read" if safety == "read" else
                 "reconcile-only" if concurrency in {"root-write", "workspace-write"}
                 else "explicit-new-intent")
        return Intent(name, ctx.factory_id if scope in {"factory", "instance"} else "",
                      ctx.instance_id if scope == "instance" else "",
                      ctx.generation if scope == "instance" else "",
                      confirm, concurrency, retry)


DEFAULT = CommandRegistry()
DEFAULT.audit()
