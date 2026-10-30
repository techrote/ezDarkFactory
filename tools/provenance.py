#!/usr/bin/env python3
"""EDF-001 exact Git-object provenance. Never imports or executes upstream source."""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "docs" / "provenance"
PINS = {
    "ezvm-baseline": ("techrote/ezvm", "b6abdf8c3edd61695db30894da991f275b39a699", "78e5ce0db9c32972451add22d28c7d19983775ee", "historical-vm-baseline"),
    "ezvm-field-study": ("techrote/ezvm", "d692be6a79a0c6bd3c1d246ff74096bc523b23e1", "ab551beb502560fd065a8dfee1a9053bc3c17c00", "historical-field-reference"),
    "ezvm-field-replay": ("techrote/ezvm", "d5265c804d0d8494d8171482a85aca563b181e05", "9416befc914dafcdefbc5c9bcc605b1ddd53e082", "historical-field-reference"),
    "ezvm-keys-repair": ("techrote/ezvm", "7b829f8352a9fa30c965e57386965767c5969e0d", "2aa3170d8ba0a60ae98bb07803f63d9c04d41de0", "later-repair-candidate"),
    "ezvm-runtime-repair": ("techrote/ezvm", "8d4bacbe74e8c4d83d3cec9845e8a6026c62fd46", "ef550dcba1aa386500c50506d0af5aa3a8ac448f", "later-repair-candidate"),
    "tuisynth-programme": ("techrote/tuisynth", "e7060f6788421029ea9a1cb7cbee86a994c5b4d5", "0b5d96d1979ed150734ae95938395165bc40530a", "original-public-programme"),
}
FORBIDDEN_REPOSITORIES = ["techrote/tuisynth-claude", "techrote/tuisynth-codex"]
OBSERVATION_IDS = ["TRIO-FR-02", "TRIO-FR-05", "TRIO-FR-14", "TRIO-FR-15", "TRIO-FR-17", "TRIO-FR-19"]
FIELD_PREFIX = "docs/research/TRIO-2026-10/"
REQUIRED_REFERENCES = {
    "ezvm-field-study": {FIELD_PREFIX + p for p in ("README.md", "observations.json", "evidence-index.json")} | {"docs/design/VM-AI-DASHBOARD.md", "docs/design/VM-AI-DASHBOARD-CONTRACTS.md", "docs/design/VM-AI-DASHBOARD-DELIVERY.md"},
    "ezvm-field-replay": {FIELD_PREFIX + p for p in ("README.md", "observations.json", "evidence-index.json")},
    "ezvm-keys-repair": {"src/EzVm/Keys.ps1", "tests/PrivateAcl.Tests.ps1", "tests/PrivateAclHosted.Tests.ps1", "docs/research/CI-POC-001-PRIVATE-DACL.md"},
    "ezvm-runtime-repair": {"src/EzVm/Runtime.ps1", "src/EzVm/RuntimeProcess.cs", "tests/Dash08Lifecycle.Tests.ps1", FIELD_PREFIX + "DASH-08-LIFECYCLE.md"},
    "tuisynth-programme": {"trio/AGENTS.md", "trio/docs/programme/STATUS.md", "trio/docs/programme/IMPLEMENTATION-PROGRAMME.md", "trio/docs/rag/12-LOCAL-WORKFLOW-AND-MODELS.md"},
}
# Minimum guard policy is code-owned: removing a rule from selection cannot weaken it.
EXCLUDED_COMPONENTS = {
    ".git", "runtime", ".ezvm", ".ezdarkfactory", "cache", ".cache", "artifacts", ".provenance-cache",
    "testresults", "coverage", "__pycache__", ".venv", "venv", "node_modules",
    ".ssh", ".aws", ".codex", ".claude", ".opencode", ".lmstudio", "keys",
    "credentials", "model-cache", "models", "weights", "private-evidence", ".config",
}
EXCLUDED_GLOBS = (
    "*.qcow2", "*.qcow", "*.img", "*.iso", "*.vhd", "*.vhdx", "*.vmdk", "*.vdi",
    "*.raw", "*.ova", "*.ovf", "*.fd", "*.exe", "*.msi", "*.msix", "*.msp",
    "*.dll", "*.so", "*.so.*", "*.dylib", "*.bin", "*.zip", "*.7z", "*.rar",
    "*.tar", "*.tgz", "*.gz", "*.bz2", "*.xz", "*.zst", "*.pem", "*.key",
    "*.p12", "*.pfx", "*.ppk", "id_rsa*", "id_dsa*", "id_ecdsa*", "id_ed25519*",
    "ssh_host_*_key*", "*.pid", "*.sock", "*.token", ".env", ".env.*", "*.log",
    "*.tmp", "*.bak", "*.pyc", "*.pyo", "*.gguf", "*.safetensors", "*.pt", "*.pth",
    "*.onnx", "*.sqlite", "*.sqlite3", "*.db", "credentials.json", "auth.json",
    "known_hosts", "authorized_keys", "cookies.txt", "controller_ed25519*", "controller_rsa*", "controller-key*",
)
RESERVED_WINDOWS = {"con", "prn", "aux", "nul"} | {f"{p}{n}" for p in ("com", "lpt") for n in range(1, 10)}
SHA1 = re.compile(r"^[0-9a-f]{40}$")
SECRET_PATTERNS = (
    re.compile(rb"-----BEGIN (?:RSA |DSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(rb"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{40,}\b"),
)


class Invalid(ValueError):
    """A closed provenance or source-safety contract failed."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Invalid(message)


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json(data: bytes | str) -> object:
    def bad_constant(value: str) -> None:
        raise Invalid(f"non-JSON numeric constant: {value}")
    def finite_float(value: str) -> float:
        number = float(value)
        require(math.isfinite(number), "non-finite JSON number")
        return number
    try:
        return json.loads(data, object_pairs_hook=unique_object, parse_constant=bad_constant, parse_float=finite_float)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Invalid(f"invalid UTF-8 JSON: {exc}") from exc


def load_json(path: Path) -> object:
    return parse_json(path.read_bytes())


def canonical(data: object) -> bytes:
    return (json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def same_json(left: object, right: object) -> bool:
    """Exact JSON equality, including nested boolean/integer type distinctions."""
    return canonical(left) == canonical(right)


SCHEMA_KEYWORDS = {"$schema", "$id", "$defs", "$ref", "title", "description", "type", "properties", "required", "additionalProperties", "items", "minItems", "minLength", "minimum", "enum", "const", "pattern"}
SCHEMA_TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "integer": int, "null": type(None)}


def check_schema_definition(schema: dict, root: dict | None = None) -> None:
    """Check every node of our closed schema, including empty/unused definitions."""
    root = schema if root is None else root
    require(type(schema) is dict, "schema node must be an object")
    require(not (set(schema) - SCHEMA_KEYWORDS), f"unsupported schema keywords: {sorted(set(schema) - SCHEMA_KEYWORDS)}")
    if "$ref" in schema:
        ref = schema["$ref"]
        require(isinstance(ref, str) and ref.startswith("#/$defs/"), "only local $defs schema references are supported")
        require(ref[len("#/$defs/"):] in root.get("$defs", {}), "unknown schema reference")
        require(set(schema) <= {"$ref", "title", "description"}, "assertion siblings of $ref are not supported")
    if "type" in schema:
        kinds = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        require(bool(kinds) and all(isinstance(k, str) and k in SCHEMA_TYPES for k in kinds), "unsupported schema type")
    if "additionalProperties" in schema:
        require(schema["additionalProperties"] is False, "only closed additionalProperties:false is supported")
    for group in ("$defs", "properties"):
        if group in schema:
            require(type(schema[group]) is dict, f"schema {group} must be an object")
            for child in schema[group].values():
                check_schema_definition(child, root)
    if "required" in schema:
        required = schema["required"]
        require(isinstance(required, list) and all(isinstance(k, str) for k in required), "invalid required list")
        require(len(required) == len(set(required)) and set(required) <= set(schema.get("properties", {})), "invalid/missing required property definition")
    if "items" in schema:
        check_schema_definition(schema["items"], root)
    for key in ("minItems", "minLength", "minimum"):
        if key in schema:
            require(type(schema[key]) is int and schema[key] >= 0, f"invalid schema {key}")
    if "enum" in schema:
        require(isinstance(schema["enum"], list) and bool(schema["enum"]), "empty/invalid enum")
        require(len({canonical(x) for x in schema["enum"]}) == len(schema["enum"]), "duplicate enum member")
    if "pattern" in schema:
        require(isinstance(schema["pattern"], str), "schema pattern must be text")
        try:
            re.compile(schema["pattern"])
        except re.error as exc:
            raise Invalid(f"invalid schema pattern: {exc}") from exc


def validate_schema(value: object, schema: dict, root: dict | None = None, where: str = "$") -> None:
    """Validate the closed JSON Schema subset used here; unknown keywords fail closed.

    This is not a general JSON Schema engine. provenance.schema.json is also valid
    Draft 2020-12 for external validators; this small offline evaluator needs no pip.
    """
    if root is None:
        check_schema_definition(schema)
        root = schema
    require(not (set(schema) - SCHEMA_KEYWORDS), f"unsupported schema keywords at {where}: {sorted(set(schema) - SCHEMA_KEYWORDS)}")
    if "$ref" in schema:
        ref = schema["$ref"]
        require(ref.startswith("#/$defs/"), "only local $defs schema references are supported")
        name = ref[len("#/$defs/"):]
        require(name in root.get("$defs", {}), f"unknown schema reference: {ref}")
        validate_schema(value, root["$defs"][name], root, where)
        return
    if "type" in schema:
        kinds = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
        require(all(k in SCHEMA_TYPES for k in kinds), f"unsupported schema type at {where}")
        require(any(type(value) is SCHEMA_TYPES[k] for k in kinds), f"wrong type at {where}: expected {kinds}")
    if "const" in schema:
        require(same_json(value, schema["const"]), f"wrong constant at {where}")
    if "enum" in schema:
        require(any(same_json(value, v) for v in schema["enum"]), f"invalid enum at {where}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        require(set(schema.get("required", [])) <= set(value), f"missing required field at {where}")
        if schema.get("additionalProperties") is False:
            require(set(value) <= set(properties), f"unknown fields at {where}: {sorted(set(value) - set(properties))}")
        for name, child in value.items():
            if name in properties:
                validate_schema(child, properties[name], root, where + "." + name)
    elif isinstance(value, list):
        require(len(value) >= schema.get("minItems", 0), f"too few items at {where}")
        if "items" in schema:
            for index, child in enumerate(value):
                validate_schema(child, schema["items"], root, f"{where}[{index}]")
    elif isinstance(value, str):
        require(len(value) >= schema.get("minLength", 0), f"empty/short string at {where}")
        if "pattern" in schema:
            require(re.search(schema["pattern"], value) is not None, f"pattern mismatch at {where}")
    elif type(value) is int:
        require(value >= schema.get("minimum", value), f"number below minimum at {where}")


def safe_relative(path: str) -> str:
    require(isinstance(path, str) and bool(path), "path must be a nonempty string")
    require(not any(c in path for c in "\\:%$\x00"), f"nonportable path: {path!r}")
    require(all(ord(c) >= 32 and c not in '<>\"|?*' for c in path), f"unsafe path characters: {path!r}")
    parts = path.split("/")
    for part in parts:
        require(part not in ("", ".", ".."), f"path traversal or empty component: {path!r}")
        require(part == part.rstrip(" ."), f"Windows path alias: {path!r}")
        require(part.split(".")[0].casefold() not in RESERVED_WINDOWS, f"Windows device path: {path!r}")
    return unicodedata.normalize("NFC", path).casefold()


def excluded(path: str) -> bool:
    key = safe_relative(path)
    parts = key.split("/")
    return any(p in EXCLUDED_COMPONENTS for p in parts) or any(fnmatch.fnmatchcase(parts[-1], p) for p in EXCLUDED_GLOBS)


def inspect_text(path: str, data: bytes) -> None:
    require(not excluded(path), f"generated/private/payload path forbidden: {path}")
    require(b"\0" not in data, f"binary NUL in source: {path}")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise Invalid(f"non-text source: {path}") from exc
    require(not data.startswith((b"MZ", b"\x7fELF", b"PK\x03\x04", b"QFI\xfb")), f"binary payload signature: {path}")
    require(not data.startswith((b"version https://git-lfs.github.com/spec/v1\n", b"version https://git-lfs.github.com/spec/v1\r\n")), f"unresolved LFS payload: {path}")
    require(not any(p.search(data) for p in SECRET_PATTERNS), f"private key/token signature: {path}")


def run_git(path: Path, *args: str, input_data: bytes | None = None) -> bytes:
    environment = os.environ.copy()
    environment.update({"GIT_NO_REPLACE_OBJECTS": "1", "GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0"})
    # Do not let a caller's index/worktree overrides redirect source inspection.
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        environment.pop(key, None)
    result = subprocess.run(["git", "--no-replace-objects", "-C", str(path), *args], input=input_data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, env=environment, check=False)
    require(result.returncode == 0, f"git {args[0]} failed: {result.stderr.decode('utf-8', errors='replace').strip()}")
    return result.stdout


def git_id(kind: str, data: bytes) -> str:
    return hashlib.sha1(kind.encode("ascii") + b" " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


class GitRepository:
    """Read authenticated Git objects, never checkout bytes, filters or upstream code."""

    def __init__(self, path: Path):
        self.path = path
        self.objects: dict[tuple[str, str], bytes] = {}
        self.trees: dict[str, dict] = {}

    def object(self, kind: str, oid: str) -> bytes:
        require(bool(SHA1.fullmatch(oid)), "expected full lowercase Git SHA-1")
        key = (kind, oid)
        if key not in self.objects:
            data = run_git(self.path, "cat-file", kind, oid)
            require(git_id(kind, data) == oid, f"Git {kind} object identity mismatch: {oid}")
            self.objects[key] = data
        return self.objects[key]

    def tree(self, commit: str) -> dict:
        if commit not in self.trees:
            commit_bytes = self.object("commit", commit)
            root_tree = commit_bytes.splitlines()[0].decode("ascii").removeprefix("tree ")
            self.object("tree", root_tree)
            rows = {}
            case_keys = set()
            for line in run_git(self.path, "ls-tree", "-rtz", "--full-tree", commit).split(b"\0"):
                if not line:
                    continue
                metadata, raw_path = line.split(b"\t", 1)
                mode, kind, oid = metadata.decode("ascii").split(" ")
                path = raw_path.decode("utf-8")
                key = safe_relative(path)
                require(path not in rows and key not in case_keys, f"duplicate/Windows-colliding upstream path: {path}")
                case_keys.add(key)
                if kind == "tree":
                    require(mode == "040000", f"invalid tree mode: {path}")
                    self.object("tree", oid)
                    continue
                require(kind == "blob" and mode in ("100644", "100755"), f"symlink/gitlink/non-file refused: {path}")
                rows[path] = {"git_blob": oid, "mode": mode}
            self.trees[commit] = rows
        return self.trees[commit]

    def file(self, commit: str, path: str) -> bytes:
        require(path in self.tree(commit), f"missing upstream path: {path}")
        return self.object("blob", self.tree(commit)[path]["git_blob"])

    def identity(self, source: dict) -> dict:
        raw = self.object("commit", source["commit"])
        header, message = raw.split(b"\n\n", 1)
        tree = header.splitlines()[0].decode("ascii").removeprefix("tree ")
        require(tree == source["tree"], f"wrong pinned tree: {source['id']}")
        tree_bytes = self.object("tree", tree)
        committer = next(line for line in header.splitlines() if line.startswith(b"committer "))
        epoch = int(committer.rsplit(b" ", 2)[1])
        return dict(source, repository_url="https://github.com/" + source["repository"],
                    committed_at=datetime.fromtimestamp(epoch, timezone.utc).isoformat().replace("+00:00", "Z"),
                    subject=message.decode("utf-8").splitlines()[0],
                    commit_object_sha256=hashlib.sha256(raw).hexdigest(),
                    tree_object_sha256=hashlib.sha256(tree_bytes).hexdigest(),
                    tree_file_count=len(self.tree(source["commit"])))


def check_selection(selection: dict, schema: dict) -> None:
    check_schema_definition(schema)
    validate_schema(selection, schema["$defs"]["selection"], schema)
    sources = selection["sources"]
    require(len({s["id"] for s in sources}) == len(sources), "duplicate source ID")
    require({s["id"] for s in sources} == set(PINS), "missing/extra pinned source")
    for source in sources:
        require((source["repository"], source["commit"], source["tree"], source["role"]) == PINS[source["id"]], f"source authority/pin mismatch: {source['id']}")
    require(selection["non_authoritative_repositories"] == FORBIDDEN_REPOSITORIES, "comparison authority restrictions changed")
    require(selection["exclusions"]["components"] == sorted(EXCLUDED_COMPONENTS), "minimum excluded components changed")
    require(selection["exclusions"]["filename_globs"] == sorted(EXCLUDED_GLOBS), "minimum excluded filename patterns changed")
    seen = set()
    targets = set()
    per_source = {s: set() for s in PINS}
    for row in selection["files"]:
        sid, path = row["source_id"], row["source_path"]
        require(sid in PINS, f"unknown file source: {sid}")
        source_key = (sid, safe_relative(path))
        require(source_key not in seen, f"duplicate source path: {sid}:{path}")
        seen.add(source_key)
        per_source[sid].add(path)
        require(not excluded(path), f"excluded upstream file selected: {path}")
        active = row["classification"] in ("unchanged-import", "adapt-rebrand")
        require(row["edf002_import"] == active, f"classification/import flag mismatch: {path}")
        require(not active or sid == "ezvm-baseline", "only exact historical baseline may enter EDF-002")
        if sid.startswith("ezvm-field") or sid == "tuisynth-programme":
            require(row["classification"] == "historical-reference-only", "historical reference cannot become product authority")
        if sid.endswith("-repair"):
            require(row["classification"] == "later-repair-candidate", "later repair must remain candidate only")
        if not active:
            require(row["destination"] is None, f"reference/candidate has an import destination: {path}")
            continue
        require(row["destination"] is not None, f"selected import lacks destination: {path}")
        target = row["destination"]
        target_key = safe_relative(target)
        require(not excluded(target), f"excluded destination: {target}")
        require(target_key not in ("agents.md", "rag.md") and not target_key.startswith(("docs/rag/", "docs/programme/", "docs/provenance/")), "historical import may not overwrite current EDF authority")
        require(target_key not in targets, f"duplicate/Windows-colliding destination: {target}")
        require(not any(target_key.startswith(t + "/") or t.startswith(target_key + "/") for t in targets), f"file/directory destination collision: {target}")
        targets.add(target_key)
    for sid, paths in REQUIRED_REFERENCES.items():
        require(paths <= per_source[sid], f"missing required evidence paths: {sid}")
    require(same_json(selection["tuisynth_cutoff"], expected_cutoff()), "unsupported original local cutoff/authority assertion")
    require(same_json(selection["amendments"], expected_amendments()), "amendment equivalence or baseline boundary changed")
    new_paths = set()
    for row in selection["new_edf_source"]:
        key = safe_relative(row["path"])
        require(key not in new_paths and not excluded(row["path"]), "duplicate/unsafe new EDF source")
        new_paths.add(key)


def expected_cutoff() -> dict:
    return {
        "public_programme_source": "tuisynth-programme",
        "subsequent_implementation": "local-git-in-development-vm-by-design",
        "accepted_local_main": {"reported": "whole/TRIO-001..007", "verbatim_field_label": "whole001..007", "commit": None, "tree": None, "evidence": "TRIO-FR-02"},
        "partial_pause_checkpoint": {"existence_reported": True, "distinct_from_accepted_main": True, "commit": None, "tree": None, "evidence": "TRIO-FR-02"},
        "historical_canonical_checkout": {"distinct_from_accepted_and_partial": True, "commit": None, "tree": None},
        "recovered_original_local_records": [],
        "later_issue_acceptance_inferred": False,
    }


def expected_amendments() -> list[dict]:
    return [{"baseline_source": "ezvm-baseline", "source_path": f"src/EzVm/{name}.ps1",
             "candidate_source": sid, "disposition": "candidate-repair", "owner_patch_bytes_recovered": False,
             "demonstrated_equivalent": False, "implementation_issue": "EDF-003"}
            for name, sid in (("Keys", "ezvm-keys-repair"), ("Runtime", "ezvm-runtime-repair"))]


def acquisitions(repo: GitRepository) -> dict:
    commit = PINS["ezvm-baseline"][1]
    qemu = parse_json(repo.file(commit, "manifests/qemu-windows.json"))
    ubuntu = parse_json(repo.file(commit, "manifests/ubuntu-noble-amd64.json"))
    tooling = parse_json(repo.file(commit, "tests/tooling.json"))
    actions = []
    for path in sorted(repo.tree(commit)):
        if path.startswith(".github/workflows/"):
            for action in re.findall(r"uses:\s*([^\s#]+)", repo.file(commit, path).decode("utf-8")):
                require(re.fullmatch(r"[A-Za-z0-9_./-]+@[0-9a-f]{40}", action) is not None, "unpinned historical action")
                actions.append({"source_path": path, "uses": action})
    return {"evidence_class": "SOURCE", "payloads_downloaded_or_executed": False,
            "qemu_manifest": qemu, "ubuntu_manifest": ubuntu, "test_powershell": tooling["powerShell7"],
            "github_actions": actions,
            "guest_packages": parse_json(repo.file(commit, "guest/base-cloud-init/baseline.json"))["packages"],
            "guest_package_versions_pinned": False,
            "limitation": "Exact source/acquisition descriptors only. Ubuntu apt package names are unversioned and package_update is true; no byte-identical historical prepared guest or current download availability is established."}


def build_manifest(selection: dict, repositories: dict[str, GitRepository], schema: dict) -> dict:
    check_selection(selection, schema)
    result = copy.deepcopy(selection)
    sources = {s["id"]: s for s in selection["sources"]}
    result["sources"] = [repositories[s["repository"]].identity(s) for s in sorted(sources.values(), key=lambda s: s["id"])]
    baseline = repositories["techrote/ezvm"]
    baseline_paths = set(baseline.tree(PINS["ezvm-baseline"][1]))
    selected_paths = {r["source_path"] for r in selection["files"] if r["source_id"] == "ezvm-baseline"}
    require(baseline_paths == selected_paths, f"baseline inventory incomplete/extra: missing={sorted(baseline_paths-selected_paths)}, extra={sorted(selected_paths-baseline_paths)}")
    files = []
    for row in sorted(selection["files"], key=lambda r: (r["source_id"], r["source_path"])):
        source = sources[row["source_id"]]
        repo = repositories[source["repository"]]
        data = repo.file(source["commit"], row["source_path"])
        inspect_text(row["source_path"], data)
        files.append(dict(row, **repo.tree(source["commit"])[row["source_path"]], bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    result["files"] = files
    result["acquisition_pins"] = acquisitions(baseline)
    study = PINS["ezvm-field-study"][1]
    replay = PINS["ezvm-field-replay"][1]
    for filename in ("observations.json", "evidence-index.json"):
        require(baseline.file(study, FIELD_PREFIX + filename) == baseline.file(replay, FIELD_PREFIX + filename), "historical original/replay records changed")
    observations = parse_json(baseline.file(study, FIELD_PREFIX + "observations.json"))["observations"]
    result["historical_observations"] = [{k: row[k] for k in ("id", "observation", "evidence_ids", "scope", "confidence")} for row in observations if row["id"] in OBSERVATION_IDS]
    require([r["id"] for r in result["historical_observations"]] == OBSERVATION_IDS, "missing/duplicate field observation")
    local_records = parse_json(baseline.file(study, FIELD_PREFIX + "evidence-index.json"))["sources"]
    require(len({r["id"] for r in local_records}) == len(local_records), "duplicate local evidence index record")
    require(all(r["availability"] == "local-only" for r in local_records), "unexpected field evidence availability")
    result["published_local_only_metadata"] = [dict(row, content_recovered=False) for row in local_records]
    result["counts"] = {"baseline_files": len(baseline_paths), "all_recorded_files": len(files), "edf002_import_files": sum(r["edf002_import"] for r in files)}
    validate_schema(result, schema)
    return result


def verify_manifest(actual: dict, selection: dict, repositories: dict[str, GitRepository], schema: dict) -> dict:
    validate_schema(actual, schema)
    expected = build_manifest(selection, repositories, schema)
    require(same_json(actual, expected), "manifest differs from exact upstream objects/reviewed selection; regenerate and review")
    return expected


def check_repository(root: Path = ROOT) -> int:
    """Scan tracked/index content and candidate worktree files, including ignored tracked files."""
    staged = run_git(root, "ls-files", "--stage", "-z")
    paths = set()
    for row in staged.split(b"\0"):
        if not row:
            continue
        metadata, raw_path = row.split(b"\t", 1)
        mode, oid, stage = metadata.decode("ascii").split()
        path = raw_path.decode("utf-8")
        require(stage == "0" and mode in ("100644", "100755"), f"unmerged/link/gitlink index entry: {path}")
        inspect_text(path, run_git(root, "cat-file", "blob", oid))
        paths.add(path)
    candidates = run_git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    paths.update(p.decode("utf-8") for p in candidates.split(b"\0") if p)
    case_keys = set()
    for path in sorted(paths):
        key = safe_relative(path)
        require(key not in case_keys, f"Windows-colliding repository path: {path}")
        case_keys.add(key)
        candidate = root / path
        require(all(not parent.is_symlink() for parent in [candidate, *candidate.parents] if parent != root.parent), f"symlink worktree path: {path}")
        require(candidate.is_file(), f"missing repository source: {path}")
        inspect_text(path, candidate.read_bytes())
    return len(paths)


def fetch_sources(directory: Path) -> dict[str, GitRepository]:
    """Acquire public Git objects into an explicit disposable cache; no checkout or hooks."""
    directory.mkdir(parents=True, exist_ok=True)
    repositories = {}
    for name in ("ezvm", "tuisynth"):
        path = directory / name
        if not path.exists():
            path.mkdir()
            run_git(path, "init", "--bare")
        require(run_git(path, "rev-parse", "--is-bare-repository").strip() == b"true", "fetch destination must be a bare object cache")
        repository = "techrote/" + name
        for _, (repo, commit, _, _) in PINS.items():
            if repo == repository:
                run_git(path, "-c", "core.hooksPath=/dev/null", "fetch", "--no-tags", "--depth=1", "https://github.com/" + repository + ".git", commit)
        repositories[repository] = GitRepository(path)
    return repositories


def source_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--ezvm", type=Path, help="existing EzVM Git checkout/object cache (read-only)")
    parser.add_argument("--tuisynth", type=Path, help="existing original TUIsynth Git checkout/object cache (read-only)")
    parser.add_argument("--fetch", action="store_true", help="fetch pinned public Git objects; no VM payloads")
    parser.add_argument("--sources", type=Path, help="explicit disposable bare-cache folder, required with --fetch")


def resolve_sources(args: argparse.Namespace) -> dict[str, GitRepository]:
    if args.fetch:
        require(args.sources is not None and args.ezvm is None and args.tuisynth is None, "--fetch requires --sources, without --ezvm/--tuisynth")
        return fetch_sources(args.sources)
    require(args.ezvm is not None and args.tuisynth is not None and args.sources is None, "supply both --ezvm and --tuisynth, or --fetch --sources")
    return {"techrote/ezvm": GitRepository(args.ezvm), "techrote/tuisynth": GitRepository(args.tuisynth)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("generate", "verify", "import-plan"))
    source_arguments(parser)
    args = parser.parse_args()
    try:
        repositories = resolve_sources(args)
        schema = load_json(PROVENANCE / "provenance.schema.json")
        selection = load_json(PROVENANCE / "selection.json")
        manifest_path = PROVENANCE / "manifest.json"
        if args.command == "generate":
            result = build_manifest(selection, repositories, schema)
            manifest_path.write_bytes(canonical(result))
            print(f"SOURCE: generated {len(result['files'])} hashed source records")
        else:
            result = verify_manifest(load_json(manifest_path), selection, repositories, schema)
            require(manifest_path.read_bytes() == canonical(result), "manifest JSON is not canonical UTF-8/LF")
            if args.command == "import-plan":
                # A verified plan only. EDF-001 deliberately has no copy/import operation.
                sys.stdout.buffer.write(canonical([dict(row, repository=PINS[row["source_id"]][0], commit=PINS[row["source_id"]][1]) for row in result["files"] if row["edf002_import"]]))
            else:
                print(f"SOURCE PASS: {len(result['files'])} exact upstream blobs; {result['counts']['edf002_import_files']} planned EDF-002 imports")
        return 0
    except (Invalid, OSError, subprocess.SubprocessError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
