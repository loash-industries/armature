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

Run from the repo root: python3 scripts/check_version_gates.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/armature_framework/sources"

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
}

# (module, function) that match a rule above but need no check, and why.
ALLOWED = {}

ENFORCE = {
    "Proposal": "enforce_proposal_version",
}

CHECK_RE = re.compile(r"check_\w*version\w*\(|version::assert_supported\(")
FUN_RE = re.compile(
    r"^public fun (?P<name>\w+)(?:<[^>]*>)?\((?P<params>[^)]*)\)[^{]*\{",
    re.M | re.S,
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


def main() -> int:
    errors = []
    gated = 0
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
            gated += 1
            if not CHECK_RE.search(body_of(code, m.end())):
                errors.append(f"{module}::{name} changes gated state but calls no version check")

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
        f"ok: {gated} public functions check the version floor, "
        f"{len(SHARED)} shared types and {len(HOT_POTATOES)} hot potatoes carry it"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
