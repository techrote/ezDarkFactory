"""EDF-006 synthetic semantic parity/refusal regression, not PHYSICAL-TUI."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from edf006_commands_spike import (CommandRefused, CommandRegistry, Context,
                                   DEFAULT, DEFINITIONS, RESERVED)

FID = "fct_" + "a" * 32
IID = "ins_" + "b" * 32
GEN = "c" * 32
CAP = frozenset(x[2] for x in DEFINITIONS if x[2])


class SemanticRegistryTests(unittest.TestCase):
    def setUp(self):
        self.ctx = Context(factory_id=FID, instance_id=IID, generation=GEN,
                           tile_id="fleet", path="C:/disposable", capabilities=CAP,
                           current=True)

    def test_all_minimum_commands_have_convergent_keyboard_and_pointer_intents(self):
        self.assertGreaterEqual(len(DEFAULT.entries), 33)
        for name, *_ in DEFINITIONS:
            with self.subTest(command=name):
                self.assertEqual(DEFAULT.resolve("keyboard", "palette:" + name, self.ctx),
                                 DEFAULT.resolve("pointer", "menu:" + name, self.ctx))

    def test_reserved_recovery_routes(self):
        DEFAULT.audit()
        for key, name in RESERVED.items():
            self.assertEqual(DEFAULT.resolve("keyboard", key, Context()).command_id, name)

    def test_conflicts_refuse_even_read_root_dispatch(self):
        ctx = Context(**{**vars(self.ctx), "conflict": True})
        for name in ("instance.start", "instance.diagnose", "instance.reset",
                     "factory.unregister"):
            with self.assertRaises(CommandRefused):
                DEFAULT.resolve("pointer", "menu:" + name, ctx)
        self.assertEqual(DEFAULT.resolve("pointer", "menu:factory.refresh", ctx).command_id,
                         "factory.refresh")

    def test_stale_root_cannot_start_but_can_refresh(self):
        ctx = Context(**{**vars(self.ctx), "current": False})
        with self.assertRaises(CommandRefused):
            DEFAULT.resolve("keyboard", "palette:instance.start", ctx)
        self.assertEqual(DEFAULT.resolve("keyboard", "palette:factory.refresh", ctx).command_id,
                         "factory.refresh")

    def test_exact_ids_and_capability_gate(self):
        for updates in ({"factory_id": ""}, {"instance_id": "by-name"},
                        {"generation": "A" * 32}, {"capabilities": frozenset()}):
            ctx = Context(**{**vars(self.ctx), **updates})
            with self.assertRaises(CommandRefused):
                DEFAULT.resolve("pointer", "menu:instance.reset", ctx)

    def test_no_implicit_shell_or_clone_capability(self):
        ctx = Context(**{**vars(self.ctx), "capabilities": frozenset({"instance.open_shell"})})
        with self.assertRaises(CommandRefused):
            DEFAULT.resolve("pointer", "menu:instance.open_shell", ctx)
        self.assertEqual(DEFAULT.resolve("pointer", "menu:instance.reset", self.ctx).retry,
                         "reconcile-only")
        self.assertEqual(DEFAULT.resolve("pointer", "menu:instance.reset", self.ctx).confirmation,
                         "target-and-consequence")

    def test_unregistered_path_and_tile_refuse(self):
        for name, ctx in (("factory.open_root", Context()),
                          ("tile.hide", Context())):
            with self.assertRaises(CommandRefused):
                DEFAULT.resolve("pointer", "menu:" + name, ctx)

    def test_manager_registry_uses_workspace_ownership(self):
        for name in ("factory.register", "factory.unregister", "factory.rename_alias"):
            self.assertEqual(DEFAULT.resolve("pointer", "menu:" + name, self.ctx).concurrency,
                             "workspace-write")

    def test_audit_rejects_dropped_recovery_or_parity(self):
        reg = CommandRegistry()
        del reg.routes[("keyboard", "Ctrl+P")]
        with self.assertRaises(ValueError):
            reg.audit()
        reg = CommandRegistry()
        del reg.routes[("pointer", "menu:instance.reset")]
        with self.assertRaises(ValueError):
            reg.audit()

    def test_duplicate_commands_and_invalid_surfaces(self):
        with self.assertRaises(ValueError):
            CommandRegistry(DEFINITIONS + (DEFINITIONS[0],))
        with self.assertRaises(ValueError):
            DEFAULT.resolve("serial", "Ctrl+P", Context())


if __name__ == "__main__":
    unittest.main()
