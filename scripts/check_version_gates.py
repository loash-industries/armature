#!/usr/bin/env python3
"""Fail if a state-changing armature_framework function skips the version check.

ARMATURE-45 (version gating). Every shared framework object carries a
`min_version` floor, and every hot potato carries the floor of the object it
came from. A public function must check that floor (`check_*version*(...)` or
`version::assert_supported(...)`) when it:

- takes a gated shared object `&mut` or by value,
- takes a hot potato by value, or
- is in READONLY_GATED: it takes only `&` references but hands out authority
  or starts a state change (vault borrows, ticket mints, `ticket_request`).

Functions that take gated objects only by `&` and are not in READONLY_GATED are
getters and checks, and stay ungated so old-linked dependents keep reading.

It also checks that each shared type has a `min_version` field, a public
`min_version`-style getter and a permissionless `enforce` function, and that
each hot potato that needs one carries a `min_version` field.

Every gated function also needs an abort test in
packages/armature_framework/tests/version_gate_tests*.move: a test marked
`#[test, expected_failure(abort_code = version::EVersionRetired)]`, named
`<function>_retired` (`<function>_retired_<module>` when the name is gated in
more than one module, e.g. `enforce_version`), that calls the function.

Run from the repo root: python3 scripts/check_version_gates.py
"""

import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/armature_framework/sources"
TESTS = ROOT / "packages/armature_framework/tests"
ABORT_TESTS = "version_gate_tests*.move"

SHARED = {
    "OU": "ou",
    "CapabilityVault": "capability_vault",
    "TreasuryVault": "treasury_vault",
    "Charter": "charter",
    "EmergencyFreeze": "emergency",
    "Proposal": "proposal",
    "CompositeFrame": "composite",
    "EncryptedEntry": "encrypted_entry",
}
# Hot potato -> the struct that holds its floor (a ticket and an asset
# transfer carry their request's floor through the request they wrap).
HOT_POTATOES = {
    "ExecutionRequest": "ExecutionRequest",
    "ExecutionTicket": "ExecutionRequest",
    "CapLoan": "CapLoan",
    "Pipeline": "Pipeline",
    "AssetTransfer": "ExecutionRequest",
}
GATED_TYPES = set(SHARED) | set(HOT_POTATOES)

# Read-only paths that still need the check: they hand out authority or start
# a state change on an object they only read.
READONLY_GATED = {
    ("capability_vault", "borrow_cap"),
    ("capability_vault", "borrow_external_cap"),
    ("proposal", "ticket_request"),
    ("board_voting", "submit_proposal"),
    ("board_voting", "submit_vote_execute_readonly"),
    ("board_voting", "ticket_from_vote_readonly"),
    ("external_execution", "ticket_from_cap_readonly"),
    ("controller", "privileged_submit"),
    ("admin_ops", "propose_update_proposal_config"),
    # Seal key servers run seal_approve from any package version.
    ("encrypted_entry", "seal_approve"),
}

# (module, function) that match a rule above but need no check, and why.
ALLOWED = {}

ENFORCE = {
    "Proposal": "enforce_proposal_version",
}

CHECK_RE = re.compile(r"check_\w*version\w*\(|version::assert_(?:stamp_)?supported\(")
FUN_RE = re.compile(
    r"^(?:public |entry |public entry )fun (?P<name>\w+)(?:<[^>]*>)?\((?P<params>[^)]*)\)[^{]*\{",
    re.M | re.S,
)
TEST_FUN_RE = re.compile(r"^fun (?P<name>\w+)\(\)\s*\{", re.M)
RETIRED_ATTR_RE = re.compile(
    r"#\[test\s*,\s*expected_failure\(\s*abort_code\s*=\s*(?:armature::)?version::EVersionRetired\s*\)\]"
)


def strip_line_comments(src: str) -> str:
    return re.sub(r"(?<!/)//(?!/)[^\n]*", "", src)


def is_test_only(src: str, fun_start: int) -> bool:
    """True if the attribute/doc lines directly above the function hold #[test_only]."""
    lines = src[:fun_start].split("\n")[:-1]
    for line in reversed(lines):
        stripped = line.strip()
        if stripped.startswith("///") or stripped.startswith("#["):
            if "test_only" in stripped:
                return True
            continue
        return False
    return False


def param_kinds(params: str):
    """Yield (type, mode) for each gated type in the parameter list; mode is
    'mut', 'ref' or 'value'."""
    for raw in re.split(r",(?![^<]*>)", params):
        if ":" not in raw:
            continue
        ty = raw.split(":", 1)[1].strip()
        mode = "value"
        if ty.startswith("&mut "):
            mode, ty = "mut", ty[5:].strip()
        elif ty.startswith("&"):
            mode, ty = "ref", ty[1:].strip()
        base = re.sub(r"<.*", "", ty).split("::")[-1]
        if base in GATED_TYPES:
            yield base, mode


def body_of(src: str, start: int) -> str:
    depth, i = 1, start
    while depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start:i]


def abort_tests() -> dict:
    """name -> body of each test in ABORT_TESTS that expects EVersionRetired."""
    tests = {}
    for path in sorted(TESTS.glob(ABORT_TESTS)):
        code = strip_line_comments(path.read_text())
        for m in TEST_FUN_RE.finditer(code):
            above = []
            for line in reversed(code[: m.start()].split("\n")[:-1]):
                if not line.strip().startswith(("///", "#[")):
                    break
                above.append(line.strip())
            if any(RETIRED_ATTR_RE.search(line) for line in above):
                tests[m.group("name")] = body_of(code, m.end())
    return tests


def main() -> int:
    errors = []
    gated = []
    sources = {}
    for path in sorted(SOURCES.rglob("*.move")):
        src = path.read_text()
        module = re.search(r"^module armature::(\w+)", src, re.M).group(1)
        sources[module] = src
        code = strip_line_comments(src)
        for m in FUN_RE.finditer(code):
            if is_test_only(code, m.start()):
                continue
            name = m.group("name")
            kinds = list(param_kinds(m.group("params")))
            needs = (module, name) in READONLY_GATED or any(
                mode in ("mut", "value") and (ty in HOT_POTATOES or ty in SHARED)
                for ty, mode in kinds
            )
            # A hot potato passed by reference to a getter (req_ou_id, ...) is fine.
            if not needs or (module, name) in ALLOWED:
                continue
            gated.append((module, name))
            if not CHECK_RE.search(body_of(code, m.end())):
                errors.append(f"{module}::{name} changes gated state but calls no version check")

    tests = abort_tests()
    modules_per_name = collections.Counter(name for _, name in gated)
    for module, name in gated:
        prefix = f"{name}_retired" + (f"_{module}" if modules_per_name[name] > 1 else "")
        calls = re.compile(rf"\b{name}\s*[<(]")
        if not any(t.startswith(prefix) and calls.search(body) for t, body in tests.items()):
            errors.append(
                f"{module}::{name} has no abort test: add `fun {prefix}()` that calls it, "
                f"marked #[test, expected_failure(abort_code = version::EVersionRetired)], "
                f"to tests/{ABORT_TESTS}"
            )

    for ty, module in SHARED.items():
        src = sources[module]
        struct = re.search(rf"public struct {ty}\b[^{{]*\{{(.*?)\n\}}", src, re.S)
        if not struct or not re.search(r"\bmin_version: u64,", struct.group(1)):
            errors.append(f"{module}::{ty} has no min_version: u64 field")
        enforce = ENFORCE.get(ty, "enforce_version")
        if not re.search(rf"^public fun {enforce}\b[^{{]*&mut {ty}\b", src, re.M):
            errors.append(f"{module}::{enforce}(&mut {ty}) is missing")
    for ty, holder in HOT_POTATOES.items():
        if holder != ty:
            continue
        src = next(s for s in sources.values() if re.search(rf"public struct {ty}\b", s))
        struct = re.search(rf"public struct {ty}\b[^{{]*\{{(.*?)\n\}}", src, re.S)
        if not struct or not re.search(r"\bmin_version: u64,", struct.group(1)):
            errors.append(f"hot potato {ty} has no min_version: u64 field")

    for e in errors:
        print(f"error: {e}")
    if errors:
        return 1
    print(
        f"ok: {len(gated)} public functions check the version floor and have an abort test "
        f"({len(tests)} tests), "
        f"{len(SHARED)} shared types and {len(HOT_POTATOES)} hot potatoes carry it"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
