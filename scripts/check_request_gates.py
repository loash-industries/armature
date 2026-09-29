#!/usr/bin/env python3
"""Fail if an armature_framework function that acts on an ExecutionRequest is ungated.

Every `public fun` or `public(package) fun` in
packages/armature_framework/sources that takes an `ExecutionRequest` must call
a permission gate (`assert_permitted` or `assert_controller`) or be listed in
ALLOWED with the reason it needs none. Every gated function must also have a
denial test in packages/armature_framework/tests/gate_tests.move (the bit is
necessary) and a grant test in grant_tests.move (the bit is sufficient), each
named with the function's name as its prefix. See ROAD-39 / ARMATURE-32.

Run from the repo root: python3 scripts/check_request_gates.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/armature_framework/sources"
GATE_TESTS = ROOT / "packages/armature_framework/tests/gate_tests.move"
GRANT_TESTS = ROOT / "packages/armature_framework/tests/grant_tests.move"
PROPOSALS_SOURCES = ROOT / "packages/armature_proposals/sources"
TYPE_PERMISSION_TESTS = ROOT / "packages/armature_proposals/tests/type_permission_tests.move"

# armature_proposals payload types whose `type_permissions` entry is 0.
NO_BITS = {"ConfigureMintAllowance"}

GATES = ("assert_permitted(", "assert_controller(")

# (module, function) -> why it needs no gate.
ALLOWED = {
    ("proposal", "req_ou_id"): "accessor",
    ("proposal", "req_proposal_id"): "accessor",
    ("proposal", "req_is_privileged"): "accessor",
    ("proposal", "req_permissions"): "accessor",
    ("proposal", "req_has_permission"): "the check itself",
    ("proposal", "assert_permitted"): "the check itself",
    ("proposal", "req_borrow_scope"): "accessor",
    ("proposal", "req_may_borrow"): "the check itself",
    ("proposal", "assert_may_borrow"): "the check itself",
    ("proposal", "with_borrow_scope_for_testing"): "test only",
    ("proposal", "consume_execution_request_for_testing"): "test only",
    ("ou", "is_permitted"): "the check itself",
    ("ou", "assert_permitted"): "the check itself",
    ("ou", "assert_controller"): "the check itself",
    ("ou", "init_type_state"): "type-state keyed by the request's own type P",
    ("ou", "borrow_type_state_mut"): "type-state keyed by the request's own type P",
    ("ou", "remove_type_state"): "type-state keyed by the request's own type P",
    ("controller", "privileged_consume"): "consumes the request",
    ("proposal", "consume"): "consumes the request",
    ("proposal", "new_ticket_standalone"): "wraps a freshly minted request in its ticket",
    ("proposal", "new_ticket_external"): "wraps a freshly minted request in its ticket",
    ("proposal", "new_external_execution_cap"): (
        "only caller execute_enable_bypass_type gates it with TYPE_ADMIN and VAULT_STORE"
    ),
    ("proposal", "destroy_external_execution_cap"): (
        "only caller execute_disable_bypass_type gates it with VAULT_EXTRACT"
    ),
}

# (module, function) that must take `Permit<P>`: the only ways to mint, spend
# or close a ticket. Without the permit, a ticket holder can hand the request
# to a mutator with arguments of their own choosing (ROAD-39 follow-up).
PERMIT_REQUIRED = {
    ("proposal", "ticket_request"),
    ("proposal", "discharge"),
    ("proposal", "discharge_returning_payload"),
    ("external_execution", "ticket_from_cap"),
    ("external_execution", "ticket_from_cap_readonly"),
}

FUN_RE = re.compile(r"^public(?:\(package\))? fun (\w+)(?:<[^>]*>)?\(([^)]*)\)[^{]*\{", re.M | re.S)


def strip_comments(src: str) -> str:
    return re.sub(r"//[^\n]*", "", src)


def snake(name: str) -> str:
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def check_proposal_types(errors: list) -> int:
    """Every handled armature_proposals payload type has grant and gate tests."""
    tests = TYPE_PERMISSION_TESTS.read_text()
    types = set()
    for path in sorted(PROPOSALS_SOURCES.rglob("*.move")):
        types |= set(re.findall(r"ExecutionTicket<(\w+)", strip_comments(path.read_text())))
    for t in sorted(types):
        prefix = snake(t)
        if not re.search(rf"^fun {prefix}_grant\(", tests, re.M):
            errors.append(f"armature_proposals {t} has no {prefix}_grant test")
        if t not in NO_BITS and not re.search(rf"^fun {prefix}_needs_\w+\(", tests, re.M):
            errors.append(f"armature_proposals {t} has no {prefix}_needs_* test")
    return len(types)


def main() -> int:
    tests = GATE_TESTS.read_text()
    grants = GRANT_TESTS.read_text()
    errors = []
    gated = 0
    permit_seen = set()
    for path in sorted(SOURCES.rglob("*.move")):
        src = strip_comments(path.read_text())
        module = re.search(r"^module armature::(\w+);", src, re.M).group(1)
        for m in FUN_RE.finditer(src):
            name, params = m.group(1), m.group(2)
            if (module, name) in PERMIT_REQUIRED:
                permit_seen.add((module, name))
                if "Permit<P>" not in params:
                    errors.append(f"{module}::{name} must take Permit<P>")
            if "ExecutionRequest" not in params:
                continue
            body_end = src.find("\n}\n", m.end())
            body = src[m.end():body_end]
            if (module, name) in ALLOWED:
                continue
            if not any(g in body for g in GATES):
                errors.append(f"{module}::{name} takes an ExecutionRequest but calls no gate")
                continue
            gated += 1
            if not re.search(rf"^fun {name}_\w*\(", tests, re.M):
                errors.append(f"{module}::{name} has no denial test in gate_tests.move")
            if not re.search(rf"^fun {name}_\w*\(", grants, re.M):
                errors.append(f"{module}::{name} has no grant test in grant_tests.move")
    for module, name in sorted(PERMIT_REQUIRED - permit_seen):
        errors.append(f"{module}::{name} not found; update PERMIT_REQUIRED")
    proposal_types = check_proposal_types(errors)
    for e in errors:
        print(f"error: {e}")
    if errors:
        return 1
    print(
        f"ok: {gated} gated functions, {len(ALLOWED)} allowed without a gate, "
        f"{len(PERMIT_REQUIRED)} Permit-gated ticket entry points, "
        f"{proposal_types} armature_proposals payload types covered"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
