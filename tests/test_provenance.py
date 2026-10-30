"""SOURCE / FAST-CI provenance tests; no VM, provider, or upstream code execution."""

from __future__ import annotations

import copy
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zlib
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools import provenance as p


class SourceProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        missing = [name for name in ("EDF_TEST_EZVM", "EDF_TEST_TUISYNTH") if not os.environ.get(name)]
        if missing:
            raise RuntimeError("Run tools/check.py with pinned sources; missing " + ", ".join(missing))
        cls.repositories = {
            "techrote/ezvm": p.GitRepository(Path(os.environ["EDF_TEST_EZVM"])),
            "techrote/tuisynth": p.GitRepository(Path(os.environ["EDF_TEST_TUISYNTH"])),
        }
        cls.schema = p.load_json(p.PROVENANCE / "provenance.schema.json")
        cls.selection = p.load_json(p.PROVENANCE / "selection.json")
        cls.manifest = p.load_json(p.PROVENANCE / "manifest.json")
        # Observe the entire cold verification without mocking its answers. Every
        # subprocess must be a read-only Git object operation, never upstream code.
        original_run = subprocess.run
        cls.process_commands = []

        def observe(command, *args, **kwargs):
            cls.process_commands.append(command)
            return original_run(command, *args, **kwargs)

        with mock.patch.object(p.subprocess, "run", side_effect=observe):
            cls.generated = p.build_manifest(cls.selection, cls.repositories, cls.schema)

    def selection_copy(self):
        return copy.deepcopy(self.selection)

    def manifest_copy(self):
        return copy.deepcopy(self.manifest)

    def reject_selection(self, selection):
        with self.assertRaises(p.Invalid):
            p.check_selection(selection, self.schema)

    def reject_manifest(self, manifest):
        with self.assertRaises(p.Invalid):
            p.verify_manifest(manifest, self.selection, self.repositories, self.schema)

    def test_checked_in_manifest_verifies_exact_sources(self):
        self.assertEqual(self.manifest, self.generated)
        p.verify_manifest(self.manifest, self.selection, self.repositories, self.schema)
        self.assertEqual((p.PROVENANCE / "manifest.json").read_bytes(), p.canonical(self.generated))

    def test_baseline_inventory_covers_every_tracked_file(self):
        rows = [r for r in self.manifest["files"] if r["source_id"] == "ezvm-baseline"]
        upstream = self.repositories["techrote/ezvm"].tree(p.PINS["ezvm-baseline"][1])
        self.assertEqual(len(rows), 110)
        self.assertEqual({r["source_path"] for r in rows}, set(upstream))
        self.assertEqual(self.manifest["counts"]["baseline_files"], len(upstream))

    def test_every_recorded_blob_hash_mode_and_size_matches_git(self):
        sources = {s["id"]: s for s in self.manifest["sources"]}
        for row in self.manifest["files"]:
            with self.subTest(source=row["source_id"], path=row["source_path"]):
                source = sources[row["source_id"]]
                repo = self.repositories[source["repository"]]
                data = repo.file(source["commit"], row["source_path"])
                self.assertEqual(row["git_blob"], p.git_id("blob", data))
                self.assertEqual(row["sha256"], hashlib.sha256(data).hexdigest())
                self.assertEqual(row["bytes"], len(data))
                self.assertEqual(row["mode"], repo.tree(source["commit"])[row["source_path"]]["mode"])

    def test_every_source_commit_and_tree_is_authenticated(self):
        for source in self.manifest["sources"]:
            with self.subTest(source=source["id"]):
                repo = self.repositories[source["repository"]]
                raw_commit = repo.object("commit", source["commit"])
                raw_tree = repo.object("tree", source["tree"])
                self.assertEqual(p.git_id("commit", raw_commit), source["commit"])
                self.assertEqual(p.git_id("tree", raw_tree), source["tree"])
                self.assertEqual(raw_commit.splitlines()[0], ("tree " + source["tree"]).encode("ascii"))
                self.assertEqual(hashlib.sha256(raw_commit).hexdigest(), source["commit_object_sha256"])
                self.assertEqual(hashlib.sha256(raw_tree).hexdigest(), source["tree_object_sha256"])

    def test_missing_duplicate_and_nonexistent_inventory_rows_fail(self):
        for mode in ("missing", "duplicate", "nonexistent"):
            selection = self.selection_copy()
            index = next(i for i, r in enumerate(selection["files"]) if r["source_id"] == "ezvm-baseline")
            if mode == "missing":
                selection["files"].pop(index)
            elif mode == "duplicate":
                selection["files"].append(copy.deepcopy(selection["files"][index]))
            else:
                selection["files"][index]["source_path"] = "not-present-in-baseline.txt"
            with self.subTest(mode=mode), self.assertRaises(p.Invalid):
                p.build_manifest(selection, self.repositories, self.schema)

    def test_required_historical_reference_cannot_be_omitted(self):
        for sid in p.REQUIRED_REFERENCES:
            selection = self.selection_copy()
            path = sorted(p.REQUIRED_REFERENCES[sid])[0]
            selection["files"] = [r for r in selection["files"] if (r["source_id"], r["source_path"]) != (sid, path)]
            with self.subTest(source=sid):
                self.reject_selection(selection)

    def test_schema_rejects_unknown_missing_and_wrongly_typed_fields(self):
        mutations = (
            lambda x: x.update(unreviewed=True),
            lambda x: x.pop("retrieved_at"),
            lambda x: x.update(schema_version=True),
            lambda x: x["files"][0].update(edf002_import=1),
            lambda x: x["files"][0].update(bytes=True),
            lambda x: x["files"][0].update(bytes=-1),
            lambda x: x["files"][0].update(extra="unreviewed"),
            lambda x: x["sources"][0].update(tree_file_count="110"),
        )
        for index, mutate in enumerate(mutations):
            manifest = self.manifest_copy()
            mutate(manifest)
            with self.subTest(mutation=index), self.assertRaises(p.Invalid):
                p.validate_schema(manifest, self.schema)

    def test_nested_boolean_contracts_reject_integer_lookalikes(self):
        for section, key, value in (
            ("portability", "hidden_host_appdata_authority", 0),
            ("portability", "relocation_preserves_identity", 1),
        ):
            selection = self.selection_copy()
            selection[section][key] = value
            with self.subTest(key=key):
                self.reject_selection(selection)
        manifest = self.manifest_copy()
        manifest["amendments"][0]["owner_patch_bytes_recovered"] = 0
        self.reject_manifest(manifest)

    def test_json_parser_rejects_duplicate_keys_and_nonfinite_values(self):
        for text in ('{"x": 1, "x": 2}', '{"nested": {"x": 1, "x": 2}}',
                     'NaN', 'Infinity', '-Infinity', '{"n": 1e999}'):
            with self.subTest(text=text), self.assertRaises(p.Invalid):
                p.parse_json(text)
        self.assertEqual(p.parse_json('{"zero": 0, "flag": false}'), {"zero": 0, "flag": False})

    def test_schema_rejects_unsupported_validation_keywords(self):
        with self.assertRaises(p.Invalid):
            p.validate_schema({}, {"type": "object", "unimplementedConstraint": True})

    def test_blob_digest_mode_size_commit_and_tree_tampering_fails(self):
        for field, value in (("git_blob", "0" * 40), ("sha256", "0" * 64),
                             ("mode", "100755"), ("bytes", 9999999)):
            manifest = self.manifest_copy()
            manifest["files"][0][field] = value
            with self.subTest(field=field):
                self.reject_manifest(manifest)
        for field in ("commit", "tree"):
            manifest = self.manifest_copy()
            manifest["sources"][0][field] = "0" * 40
            with self.subTest(field=field):
                self.reject_manifest(manifest)

    def test_comparison_repository_cannot_claim_original_pin(self):
        for repository in ("techrote/tuisynth-codex", "techrote/tuisynth-claude"):
            for source_id in ("tuisynth-programme", "ezvm-baseline"):
                selection = self.selection_copy()
                source = next(s for s in selection["sources"] if s["id"] == source_id)
                # Preserve the original commit/tree; changing only the repository
                # must still fail instead of laundering comparison-fork authority.
                source["repository"] = repository
                with self.subTest(repository=repository, source=source_id):
                    self.reject_selection(selection)

    def test_authority_restrictions_and_source_set_cannot_be_weakened(self):
        for mode in ("remove-comparison", "remove-source", "duplicate-source", "unknown-source"):
            selection = self.selection_copy()
            if mode == "remove-comparison":
                selection["non_authoritative_repositories"].pop()
            elif mode == "remove-source":
                selection["sources"].pop()
            elif mode == "duplicate-source":
                selection["sources"].append(copy.deepcopy(selection["sources"][0]))
            else:
                selection["files"][0]["source_id"] = "unreviewed-original"
            with self.subTest(mode=mode):
                self.reject_selection(selection)

    def test_later_repair_and_historical_reference_cannot_be_active_import(self):
        for source_id in ("ezvm-keys-repair", "ezvm-runtime-repair", "ezvm-field-study", "tuisynth-programme"):
            selection = self.selection_copy()
            row = next(r for r in selection["files"] if r["source_id"] == source_id)
            row.update(classification="adapt-rebrand", edf002_import=True, destination="candidate-import.txt")
            with self.subTest(source=source_id):
                self.reject_selection(selection)

    def test_owner_local_patch_recovery_and_equivalence_cannot_be_invented(self):
        for index in range(2):
            for field, value in (("owner_patch_bytes_recovered", True), ("demonstrated_equivalent", True),
                                 ("disposition", "proven-equivalent")):
                selection = self.selection_copy()
                selection["amendments"][index][field] = value
                with self.subTest(amendment=index, field=field):
                    self.reject_selection(selection)

    def test_local_accepted_partial_and_canonical_shas_cannot_be_inferred(self):
        for checkpoint in ("accepted_local_main", "partial_pause_checkpoint", "historical_canonical_checkout"):
            for field in ("commit", "tree"):
                selection = self.selection_copy()
                selection["tuisynth_cutoff"][checkpoint][field] = p.PINS["tuisynth-programme"][1]
                with self.subTest(checkpoint=checkpoint, field=field):
                    self.reject_selection(selection)
        selection = self.selection_copy()
        selection["tuisynth_cutoff"]["later_issue_acceptance_inferred"] = True
        self.reject_selection(selection)

    def test_local_only_evidence_remains_metadata_not_recovered_content(self):
        by_id = {r["id"]: r for r in self.manifest["published_local_only_metadata"]}
        for evidence_id in ("E01", "E04", "E17"):
            with self.subTest(evidence=evidence_id):
                self.assertEqual(by_id[evidence_id]["availability"], "local-only")
                self.assertIs(by_id[evidence_id]["content_recovered"], False)
        manifest = self.manifest_copy()
        manifest["published_local_only_metadata"][0]["content_recovered"] = True
        self.reject_manifest(manifest)

    def test_exclusion_policy_cannot_be_removed(self):
        for field in ("components", "filename_globs"):
            selection = self.selection_copy()
            selection["exclusions"][field].pop()
            with self.subTest(field=field):
                self.reject_selection(selection)

    def test_excluded_source_and_destination_patterns_ignore_case(self):
        forbidden = ("RunTime/notes.txt", "nested/CaChe/notes.txt", ".SsH/config", "notes/PRIVATE-EVIDENCE/source.md",
                     "docs/DISK.QcOw2", "docs/installer.ExE", "docs/model.GgUf", "docs/key.PpK",
                     "docs/Auth.JsOn", "docs/.EnV.production", "docs/Controller_Ed25519")
        for path in forbidden:
            with self.subTest(path=path):
                self.assertTrue(p.excluded(path))
                for field in ("source_path", "destination"):
                    selection = self.selection_copy()
                    row = next(r for r in selection["files"] if r["edf002_import"])
                    row[field] = path
                    self.reject_selection(selection)

    def test_nonportable_import_paths_are_rejected(self):
        forbidden = ("../outside", "a/../../outside", "/absolute", "C:/developer/source", "C:relative",
                     "//server/share", "\\\\server\\share", "file:stream", "dir//file", "./file",
                     "dir/CON.txt", "dir/LpT9", "dir/trailing.", "dir/trailing ", "dir/line\nfeed",
                     "%LOCALAPPDATA%/state", "$HOME/state", "dir/back\\slash")
        for path in forbidden:
            with self.subTest(path=path), self.assertRaises(p.Invalid):
                p.safe_relative(path)

    def test_destination_case_unicode_and_file_directory_collisions_fail(self):
        for first, second in (("src/Target.ps1", "SRC/target.ps1"), ("docs/caf\u00e9.txt", "docs/cafe\u0301.txt"),
                              ("src/container", "src/container/file.ps1")):
            selection = self.selection_copy()
            rows = [r for r in selection["files"] if r["edf002_import"]][:2]
            rows[0]["destination"], rows[1]["destination"] = first, second
            with self.subTest(first=first, second=second):
                self.reject_selection(selection)

    def test_source_case_collisions_fail(self):
        selection = self.selection_copy()
        row = copy.deepcopy(next(r for r in selection["files"] if r["source_id"] == "ezvm-baseline"))
        row["source_path"] = row["source_path"].upper()
        selection["files"].append(row)
        self.reject_selection(selection)

    def test_import_cannot_overwrite_current_authority_in_any_case(self):
        for path in ("AGENTS.md", "agents.MD", "RAG.md", "rag.MD", "Docs/RAG/02-ARCHITECTURE.md",
                     "DOCS/PROGRAMME/STATUS.md", "Docs/Provenance/manifest.json"):
            selection = self.selection_copy()
            next(r for r in selection["files"] if r["edf002_import"])["destination"] = path
            with self.subTest(path=path):
                self.reject_selection(selection)

    def test_generation_is_deterministic_and_selection_order_independent(self):
        first = p.canonical(p.build_manifest(self.selection, self.repositories, self.schema))
        reordered = self.selection_copy()
        reordered["files"].reverse()
        second = p.canonical(p.build_manifest(reordered, self.repositories, self.schema))
        self.assertEqual(first, second)
        self.assertEqual(first, p.canonical(self.manifest))

    def test_verification_never_executes_upstream_scripts_or_downloads_payloads(self):
        self.assertGreater(len(self.process_commands), 0)
        for command in self.process_commands:
            with self.subTest(command=command):
                self.assertEqual(command[0], "git")
                self.assertEqual(command[1], "--no-replace-objects")
                self.assertEqual(command[2], "-C")
                self.assertIn(command[4], ("cat-file", "ls-tree"))
        self.assertIs(self.manifest["acquisition_pins"]["payloads_downloaded_or_executed"], False)
        self.assertIs(self.manifest["acquisition_pins"]["guest_package_versions_pinned"], False)


class RepositoryBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="edf provenance fixture ")
        self.root = Path(self.temporary.name)
        p.run_git(self.root, "init", "--quiet")
        p.run_git(self.root, "config", "user.name", "EDF synthetic fixture")
        p.run_git(self.root, "config", "user.email", "fixture@example.invalid")
        p.run_git(self.root, "config", "core.autocrlf", "false")
        self.write("README.md", b"Synthetic source fixture.\n")
        p.run_git(self.root, "add", "--", "README.md")
        p.run_git(self.root, "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "synthetic fixture")

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, path, data):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return target

    def test_benign_source_repository_passes(self):
        self.write("source/example.txt", "Ordinary Unicode source: caf\u00e9\n".encode("utf-8"))
        self.assertEqual(p.check_repository(self.root), 2)

    def test_ignored_untracked_runtime_is_not_confused_with_committed_source(self):
        self.write(".gitignore", b"runtime/\n")
        self.write("runtime/disk.qcow2", b"synthetic ignored payload placeholder\n")
        self.assertEqual(p.check_repository(self.root), 2)
        p.run_git(self.root, "add", "--force", "--", "runtime/disk.qcow2")
        with self.assertRaises(p.Invalid):
            p.check_repository(self.root)

    def test_disguised_binary_payloads_are_rejected(self):
        for data in (b"MZsynthetic executable", b"\x7fELFsynthetic", b"PK\x03\x04synthetic",
                     b"QFI\xfbsynthetic", b"ordinary\0binary", b"\xffinvalid UTF-8"):
            with self.subTest(signature=data[:4]), self.assertRaises(p.Invalid):
                p.inspect_text("ordinary-document.md", data)

    def test_private_key_and_provider_token_markers_are_rejected(self):
        # Construct synthetic signatures at runtime so the tests contain no
        # complete credential-looking strings or usable key material themselves.
        samples = (
            b"-----BEGIN " + b"OPENSSH PRIVATE KEY-----\nsynthetic only\n",
            b"gh" + b"p_" + b"A" * 36,
            b"github_" + b"pat_" + b"B" * 48,
            b"AK" + b"IA" + b"C" * 16,
            b"sk-" + b"proj-" + b"D" * 48,
        )
        for data in samples:
            with self.subTest(kind=data[:8]), self.assertRaises(p.Invalid):
                p.inspect_text("innocent.md", data)

    def test_lfs_pointers_with_lf_or_crlf_are_rejected(self):
        pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:" + b"0" * 64 + b"\nsize 123\n"
        for data in (pointer, pointer.replace(b"\n", b"\r\n")):
            with self.subTest(crlf=b"\r\n" in data), self.assertRaises(p.Invalid):
                p.inspect_text("image-disguised.md", data)

    def test_staged_secret_cannot_be_hidden_by_clean_worktree(self):
        path = self.write("notes.md", b"-----BEGIN " + b"RSA PRIVATE KEY-----\nsynthetic only\n")
        p.run_git(self.root, "add", "--", "notes.md")
        path.write_bytes(b"Worktree is clean-looking, index must still be checked.\n")
        with self.assertRaises(p.Invalid):
            p.check_repository(self.root)

    def test_symlink_and_gitlink_index_entries_are_rejected_without_os_privileges(self):
        oid = p.run_git(self.root, "hash-object", "-w", "--stdin", input_data=b"README.md").decode().strip()
        p.run_git(self.root, "update-index", "--add", "--cacheinfo", f"120000,{oid},link.md")
        with self.assertRaises(p.Invalid):
            p.check_repository(self.root)
        p.run_git(self.root, "update-index", "--force-remove", "--", "link.md")
        commit = p.run_git(self.root, "rev-parse", "HEAD").decode().strip()
        p.run_git(self.root, "update-index", "--add", "--cacheinfo", f"160000,{commit},external-project")
        with self.assertRaises(p.Invalid):
            p.check_repository(self.root)

    def test_raw_git_blob_ignores_worktree_edits_and_autocrlf(self):
        original = b"line one\nline two\n"
        path = self.write("source.txt", original)
        p.run_git(self.root, "add", "--", "source.txt")
        p.run_git(self.root, "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "raw blob fixture")
        commit = p.run_git(self.root, "rev-parse", "HEAD").decode().strip()
        expected = p.GitRepository(self.root).file(commit, "source.txt")
        p.run_git(self.root, "config", "core.autocrlf", "true")
        path.write_bytes(b"modified checkout\r\nnot source authority\r\n")
        actual = p.GitRepository(self.root).file(commit, "source.txt")
        self.assertEqual(actual, original)
        self.assertEqual(actual, expected)

    def test_git_replacement_objects_do_not_rewrite_recorded_source(self):
        commit = p.run_git(self.root, "rev-parse", "HEAD").decode().strip()
        repo = p.GitRepository(self.root)
        original = repo.file(commit, "README.md")
        original_oid = repo.tree(commit)["README.md"]["git_blob"]
        replacement = p.run_git(self.root, "hash-object", "-w", "--stdin", input_data=b"replacement bytes\n").decode().strip()
        p.run_git(self.root, "replace", original_oid, replacement)
        self.assertEqual(p.GitRepository(self.root).file(commit, "README.md"), original)

    def test_corrupt_intermediate_tree_is_rejected_even_with_genuine_blob_and_root(self):
        self.write("nested/source.txt", b"original source bytes\n")
        p.run_git(self.root, "add", "--", "nested/source.txt")
        p.run_git(self.root, "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "nested tree fixture")
        commit = p.run_git(self.root, "rev-parse", "HEAD").decode().strip()
        root_tree = p.run_git(self.root, "rev-parse", "HEAD^{tree}").decode().strip()
        nested_tree = p.run_git(self.root, "rev-parse", "HEAD:nested").decode().strip()
        original_blob = p.run_git(self.root, "rev-parse", "HEAD:nested/source.txt").decode().strip()
        replacement_blob = p.run_git(self.root, "hash-object", "-w", "--stdin", input_data=b"different genuine blob\n").decode().strip()
        reader = p.GitRepository(self.root)
        reader.object("commit", commit)
        reader.object("tree", root_tree)
        reader.object("blob", replacement_blob)
        raw = p.run_git(self.root, "cat-file", "tree", nested_tree)
        corrupt = raw.replace(bytes.fromhex(original_blob), bytes.fromhex(replacement_blob), 1)
        self.assertNotEqual(raw, corrupt)
        self.assertEqual(len(raw), len(corrupt))
        loose_object = self.root / ".git" / "objects" / nested_tree[:2] / nested_tree[2:]
        self.assertTrue(loose_object.is_file())
        loose_object.chmod(0o600)
        loose_object.write_bytes(zlib.compress(b"tree " + str(len(corrupt)).encode("ascii") + b"\0" + corrupt))
        # Commit, root and replacement blob remain real objects. Only rehashing
        # the intervening tree catches this object-database corruption.
        with self.assertRaisesRegex(p.Invalid, "Git tree object identity mismatch"):
            p.GitRepository(self.root).tree(commit)

    def test_windows_colliding_upstream_tree_is_rejected_on_every_host(self):
        oid = p.run_git(self.root, "hash-object", "-w", "--stdin", input_data=b"synthetic\n").decode().strip()
        tree = p.run_git(self.root, "mktree", input_data=(f"100644 blob {oid}\tName.txt\n100644 blob {oid}\tname.txt\n").encode()).decode().strip()
        commit = p.run_git(self.root, "commit-tree", tree, "-m", "case collision fixture").decode().strip()
        with self.assertRaisesRegex(p.Invalid, "colliding upstream path"):
            p.GitRepository(self.root).tree(commit)


if __name__ == "__main__":
    unittest.main(verbosity=2)
