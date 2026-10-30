#!/usr/bin/env python3
"""EDF source/provenance FAST-CI merge gate. No VM, provider or upstream script execution."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import unittest

import provenance as p


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    p.source_arguments(parser)
    args = parser.parse_args()
    try:
        repositories = p.resolve_sources(args)
        schema = p.load_json(p.PROVENANCE / "provenance.schema.json")
        selection = p.load_json(p.PROVENANCE / "selection.json")
        manifest_path = p.PROVENANCE / "manifest.json"
        manifest = p.verify_manifest(p.load_json(manifest_path), selection, repositories, schema)
        p.require(manifest_path.read_bytes() == p.canonical(manifest), "manifest is not canonical UTF-8/LF JSON")
        p.require(p.build_manifest(selection, repositories, schema) == manifest, "nondeterministic manifest regeneration")
        count = p.check_repository()
        print(f"SOURCE PASS: {len(manifest['files'])} authenticated records; {count} safe repository files", flush=True)
        os.environ["EDF_TEST_EZVM"] = str(repositories["techrote/ezvm"].path.resolve())
        os.environ["EDF_TEST_TUISYNTH"] = str(repositories["techrote/tuisynth"].path.resolve())
        sys.path.insert(0, str(p.ROOT))
        suite = unittest.defaultTestLoader.discover(str(p.ROOT / "tests"), pattern="test_*.py")
        p.require(suite.countTestCases() > 0, "zero tests discovered")
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        p.require(result.wasSuccessful() and not result.skipped, "tests failed or skipped; every EDF source/provenance test is required")
        p.run_git(p.ROOT, "diff", "--check")
        p.run_git(p.ROOT, "diff", "--cached", "--check")
        print(f"FAST-CI PASS: {result.testsRun} tests, 0 failures, 0 skips", flush=True)
        print("Evidence boundary: no TCG/WHPX runtime, physical Windows Terminal or human-usability execution.")
        return 0
    except (p.Invalid, OSError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
