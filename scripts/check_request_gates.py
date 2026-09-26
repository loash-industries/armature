#!/usr/bin/env python3
"""Fail if an armature_framework function that acts on an ExecutionRequest is ungated.

Every `public fun` in packages/armature_framework/sources that takes an
`ExecutionRequest` must call a permission gate (`assert_permitted` or
`assert_controller`) or be listed in ALLOWED with the reason it needs none.
Every gated function must also have a denial test in
packages/armature_framework/tests/gate_tests.move whose name starts with the
function's name. See ROAD-39 / ARMATURE-32.

Run from the repo root: python3 scripts/check_request_gates.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "packages/armature_framework/sources"
GATE_TESTS = ROOT / "packages/armature_framework/tests/gate_tests.move"

GATES = ("assert_permitted(", "assert_controller(")

# (module, function) -> why it needs no gate.
ALLOWED = {
    ("proposal", "req_dao_id"): "accessor",
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
    ("dao", "is_permitted"): "the check itself",
    ("dao", "assert_permitted"): "the check itself",
    ("dao", "assert_controller"): "the check itself",
    ("dao", "init_type_state"): "type-state keyed by the request's own type P",
    ("dao", "borrow_type_state_mut"): "type-state keyed by the request's own type P",
    ("dao", "remove_type_state"): "type-state keyed by the request's own type P",
    ("controller", "privileged_consume"): "consumes the request",
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

FUN_RE = re.compile(r"^public fun (\w+)(?:<[^>]*>)?\(([^)]*)\)[^{]*\{", re.M | re.S)


def strip_comments(src: str) -> str:
    return re.sub(r"//[^\n]*", "", src)


def main() -> int:
    tests = GATE_TESTS.read_text()
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
    for module, name in sorted(PERMIT_REQUIRED - permit_seen):
        errors.append(f"{module}::{name} not found; update PERMIT_REQUIRED")
    for e in errors:
        print(f"error: {e}")
    if errors:
        return 1
    print(
        f"ok: {gated} gated functions, {len(ALLOWED)} allowed without a gate, "
        f"{len(PERMIT_REQUIRED)} Permit-gated ticket entry points"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
