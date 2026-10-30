"""Pinned, narrowly scoped later source supersession; immutable EDF-002/003 records stay authenticated."""
from pathlib import Path
import provenance as p

# Accepted EDF-003/current preimages and CI-RUNTIME-001 proposed replacement blobs.
PINNED = {
    "src/EzDarkFactory/Runtime.ps1": (
        "f4e9af5f0058fd3b7176650a774aea355baaf1ff",
        "c36c073f00d9b5b98b75fa00c1ac85f0edd31f8f",
    ),
    "tests/Runtime.Tests.ps1": (
        "d298a546c1428b0c6d7d56c44d892eaf7b4eb43b",
        "d24e3f19de1af4372837026c6eecdf2df8433641",
    ),
}
BASE = "4ca42999081f6253e9701821f1c378f439fca9a9"

def verified_supersession(root: Path, destination: str, accepted_blob: str) -> bool:
    """Allow only exact reviewed replacement bytes, with intact accepted base history."""
    if destination not in PINNED:
        return False
    old, new = PINNED[destination]
    if accepted_blob != old:
        raise AssertionError("Supersession preimage differs from accepted provenance")
    base_blob = p.run_git(root, "rev-parse", BASE + ":" + destination).decode("ascii").strip()
    if base_blob != old:
        raise AssertionError("Accepted base no longer matches supersession preimage")
    actual_blob = p.run_git(root, "rev-parse", "HEAD:" + destination).decode("ascii").strip()
    if actual_blob != new:
        raise AssertionError("Actual superseded Git blob does not match reviewed replacement")
    if p.run_git(root, "cat-file", "blob", new) != (root / destination).read_bytes():
        raise AssertionError("Working tree does not match reviewed replacement")
    return True
