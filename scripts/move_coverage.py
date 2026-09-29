#!/usr/bin/env python3
"""Measure Move test coverage for armature_framework and armature_proposals.

Runs `sui move test --coverage --trace` for both packages in a scratch copy of
packages/ (so the tracked .coverage_map.mvcov files and the traces/ dirs never
touch the working tree) and reports, per source file:

  lines      executable lines executed. Executable lines come from the
             compiler's source maps (each instruction's start line, plus each
             function's signature line); executed lines from the trace LCOV.
  functions  functions entered (trace LCOV)
  branches   branch arms taken (trace LCOV)
  bytecode   instructions executed (`sui move coverage summary`)

  own        from the package's own tests
  combined   from both packages' tests. armature_proposals tests drive
             armature_framework code (handlers/ and types/ especially), so
             framework coverage is higher here than from its own tests.

`#[test_only]` functions in sources/ are left out of every metric.

Writes to --out (default: coverage/):
  lcov.info               combined LCOV with repo-relative paths, for Coverage
                          Gutters, genhtml, Codecov
  <package>.lcov.info     LCOV from that package's own tests
  <package>.bytecode.csv  per-function bytecode coverage, as the CLI prints it
  summary.json            the numbers printed below
  html/                   genhtml report, if genhtml is on PATH

Needs a Sui CLI built with the `tracing` feature. The release binaries suiup
installs have it; a plain `cargo install` build does not. The first `sui` on
PATH that supports --coverage is used, or set SUI=/path/to/sui.

Run from anywhere: python3 scripts/move_coverage.py [--uncovered] [--min 90]
"""

import argparse
import bisect
import csv
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGES_DIR = ROOT / "packages"
# Both are always run: proposals depends on framework, and its tests count
# toward framework's combined coverage. Positional args pick what's reported.
PACKAGES = ("armature_framework", "armature_proposals")
COPY_IGNORE = shutil.ignore_patterns("build", "traces", "*.mvcov", "lcov.info")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
TEST_ONLY_FN = re.compile(r"#\[test_only\]\s*(?:#\[[^\]]*\]\s*|//[^\n]*\n\s*)*"
                          r"(?:public(?:\([a-z]+\))?\s+)?(?:entry\s+)?(?:macro\s+)?fun\s+(\w+)")


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def supports_coverage(sui):
    # The tracing check runs before the package path is resolved, so a missing
    # path answers the question without compiling anything.
    out = subprocess.run(
        [sui, "move", "test", "--coverage", "--path", "/nonexistent-armature-coverage"],
        capture_output=True, text=True,
    )
    return "tracing" not in out.stdout + out.stderr


def find_sui():
    if os.environ.get("SUI"):
        sui = os.environ["SUI"]
        if not supports_coverage(sui):
            fail(f"SUI={sui} was not built with the `tracing` feature")
        return sui
    seen = []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        cand = str(pathlib.Path(d) / "sui")
        if cand not in seen and os.path.isfile(cand) and os.access(cand, os.X_OK):
            seen.append(cand)
            if supports_coverage(cand):
                return cand
    fail(
        "no `sui` on PATH supports --coverage (checked: " + (", ".join(seen) or "none")
        + "). Install a release build with `suiup install sui@testnet`, or set SUI=/path/to/sui."
    )


def run(cmd, cwd):
    print(f"  $ sui {' '.join(cmd[1:])}", flush=True)
    out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return out.returncode, ANSI.sub("", out.stdout + out.stderr)


# ── Source maps (executable lines) ───────────────────────────────────────────


def source_map(debug_json):
    """Executable lines and test-only function info for one module.

    Returns (source path, executable lines, test-only function names,
    test-only line ranges)."""
    d = json.loads(debug_json.read_text())
    src = os.path.realpath(d["from_file_path"])
    data = pathlib.Path(src).read_bytes()
    starts = [0] + [i + 1 for i, b in enumerate(data) if b == 10]
    line = lambda off: bisect.bisect_right(starts, off)  # 1-based
    file_hash = d["definition_location"]["file_hash"]
    test_only = set(TEST_ONLY_FN.findall(data.decode()))

    executable, skipped = set(), []
    for fn in d["function_map"].values():
        name_loc = fn["definition_location"]
        name = data[name_loc["start"]:name_loc["end"]].decode()
        span = (line(fn["location"]["start"]), line(fn["location"]["end"]))
        if name in test_only:
            skipped.append(span)
            continue
        if fn.get("is_native"):
            continue
        executable.add(span[0])
        # Macro bodies inlined from other files carry that file's hash.
        executable.update(line(loc["start"]) for loc in fn["code_map"].values()
                          if loc["file_hash"] == file_hash)
    return src, executable, test_only, skipped


# ── LCOV (executed lines, functions, branches) ───────────────────────────────


def new_record():
    return {"fn": {}, "fnda": {}, "da": {}, "brda": {}}


def parse_lcov(text):
    """Source path -> record. The CLI emits DA only for executed lines, so
    executable lines come from the source maps instead."""
    records, cur, path = {}, None, None
    for line in text.splitlines():
        if line.startswith("SF:"):
            path, cur = os.path.realpath(line[3:]), new_record()
        elif line == "end_of_record":
            records[path] = cur
            cur = None
        elif cur is None:
            continue
        elif line.startswith("DA:"):
            ln, hits = line[3:].split(",")[:2]
            cur["da"][int(ln)] = cur["da"].get(int(ln), 0) + int(hits)
        elif line.startswith("FN:"):
            ln, name = line[3:].split(",", 1)
            cur["fn"][name] = int(ln)
        elif line.startswith("FNDA:"):
            hits, name = line[5:].split(",", 1)
            cur["fnda"][name] = cur["fnda"].get(name, 0) + int(hits)
        elif line.startswith("BRDA:"):
            ln, block, branch, hits = line[5:].split(",")
            key = (int(ln), block, branch)
            cur["brda"][key] = cur["brda"].get(key, 0) + (0 if hits == "-" else int(hits))
    return records


def restrict(rec, executable, test_only, skipped):
    """Drop test-only functions and anything outside this file's own lines."""
    in_skipped = lambda ln: any(a <= ln <= b for a, b in skipped)
    return {
        "fn": {n: ln for n, ln in rec["fn"].items() if n not in test_only},
        "fnda": {n: h for n, h in rec["fnda"].items() if n not in test_only},
        "da": {ln: h for ln, h in rec["da"].items() if ln in executable},
        "brda": {k: h for k, h in rec["brda"].items() if k[0] in executable and not in_skipped(k[0])},
    }


def merge(records):
    out = new_record()
    for rec in records:
        for k in ("da", "fnda", "brda"):
            for key, hits in rec[k].items():
                out[k][key] = out[k].get(key, 0) + hits
        out["fn"].update(rec["fn"])
    return out


def hit_count(pairs):
    return (sum(1 for h in pairs.values() if h), len(pairs))


def write_lcov(files, path):
    """files: rel path -> (record, executable lines)."""
    buf = io.StringIO()
    for sf in sorted(files):
        rec, executable = files[sf]
        buf.write(f"SF:{sf}\n")
        for name, ln in sorted(rec["fn"].items(), key=lambda kv: kv[1]):
            buf.write(f"FN:{ln},{name}\n")
        for name in sorted(rec["fn"], key=rec["fn"].get):
            buf.write(f"FNDA:{rec['fnda'].get(name, 0)},{name}\n")
        buf.write(f"FNF:{len(rec['fn'])}\nFNH:{sum(1 for n in rec['fn'] if rec['fnda'].get(n))}\n")
        for (ln, block, branch), hits in sorted(rec["brda"].items()):
            buf.write(f"BRDA:{ln},{block},{branch},{hits or '-'}\n")
        bh, bt = hit_count(rec["brda"])
        buf.write(f"BRF:{bt}\nBRH:{bh}\n")
        for ln in sorted(executable):
            buf.write(f"DA:{ln},{rec['da'].get(ln, 0)}\n")
        lh = sum(1 for ln in executable if rec["da"].get(ln))
        buf.write(f"LF:{len(executable)}\nLH:{lh}\nend_of_record\n")
    path.write_text(buf.getvalue())


def parse_bytecode_csv(text, test_only):
    """Module -> (covered, total) instructions. Despite its header, the CLI's
    `Uncovered` column is each function's total instruction count: covered
    never exceeds it, and summing covered/Uncovered reproduces the % the
    non-CSV summary prints."""
    out = {}
    for row in csv.DictReader(io.StringIO(text)):
        try:
            module = row["ModuleName"].split("::")[-1]
            covered, total = int(row["Covered"]), int(row["Uncovered"])
        except (KeyError, ValueError, TypeError, AttributeError):
            continue
        if row["FunctionName"] not in test_only.get(module, ()):
            out[module] = add(out.get(module, (0, 0)), (covered, total))
    return out


# ── Reporting ────────────────────────────────────────────────────────────────


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def pct(pair):
    return 100.0 * pair[0] / pair[1] if pair[1] else 100.0


def fmt(pair):
    return f"{pct(pair):5.1f}% {pair[0]:>4}/{pair[1]:<4}" if pair[1] else f"{'-':>6}"


def ranges(lines):
    out = []
    for ln in sorted(lines):
        if out and ln == out[-1][1] + 1:
            out[-1][1] = ln
        else:
            out.append([ln, ln])
    return ", ".join(str(a) if a == b else f"{a}-{b}" for a, b in out)


COLUMNS = ("lines_own", "lines_combined", "functions_own", "functions_combined",
           "branches_own", "branches_combined", "bytecode_own")
HEADINGS = ("lines own", "lines comb.", "fns own", "fns comb.", "branches own", "branches comb.",
            "bytecode own")


def report_package(pkg, rows, show_uncovered):
    names = {rel: rel.split("/sources/", 1)[1] for rel in rows}
    width = max(map(len, names.values()), default=10)
    header = f"  {'file':<{width}}" + "".join(f"  {h:<16}" for h in HEADINGS)
    print(f"\n{pkg}\n{header}\n  {'-' * (len(header) - 2)}")
    total = {c: (0, 0) for c in COLUMNS}
    for rel in sorted(rows):
        row = rows[rel]
        print(f"  {names[rel]:<{width}}" + "".join(f"  {fmt(row[c]):<16}" for c in COLUMNS))
        if show_uncovered and row["uncovered_lines"]:
            print(f"      uncovered lines: {ranges(row['uncovered_lines'])}")
        if show_uncovered and row["uncovered_functions"]:
            print(f"      uncovered functions: {', '.join(row['uncovered_functions'])}")
        for c in COLUMNS:
            total[c] = add(total[c], row[c])
    print(f"  {'-' * (len(header) - 2)}")
    print(f"  {'TOTAL':<{width}}" + "".join(f"  {fmt(total[c]):<16}" for c in COLUMNS))
    return total


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("packages", nargs="*", default=list(PACKAGES),
                    help=f"packages to report (default: {' '.join(PACKAGES)})")
    ap.add_argument("--build-env", default="testnet", help="sui --build-env (default: testnet)")
    ap.add_argument("--out", default=str(ROOT / "coverage"), help="report directory (default: coverage/)")
    ap.add_argument("--min", type=float, metavar="PCT",
                    help="exit 1 if a reported package's combined line coverage is below PCT")
    ap.add_argument("--uncovered", action="store_true",
                    help="list uncovered lines and functions per file (combined)")
    ap.add_argument("--keep", action="store_true", help="keep the scratch build directory")
    args = ap.parse_args()
    for pkg in args.packages:
        if pkg not in PACKAGES:
            fail(f"unknown package {pkg!r}; expected one of: {', '.join(PACKAGES)}")

    sui = find_sui()
    print(f"using {sui}")

    scratch = pathlib.Path(tempfile.mkdtemp(prefix="armature-coverage-")).resolve()
    out_dir = pathlib.Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        for pkg in PACKAGES:
            shutil.copytree(PACKAGES_DIR / pkg, scratch / pkg, ignore=COPY_IGNORE)

        lcov, maps, csvs = {}, {}, {}
        for pkg in PACKAGES:
            path = scratch / pkg
            print(f"\n[{pkg}]")
            code, text = run([sui, "move", "test", "--path", str(path), "--build-env", args.build_env,
                              "--coverage", "--trace", "-i", "100000000"], scratch)
            result = [l for l in text.splitlines() if l.startswith("Test result:")]
            print("    " + (result[-1] if result else "(no test result line)"))
            if code != 0:
                failures = [l for l in text.splitlines() if l.startswith("[ FAIL")]
                print("\n".join(failures) or text[-4000:], file=sys.stderr)
                fail(f"{pkg} tests failed; coverage not measured")

            code, text = run([sui, "move", "coverage", "lcov", "--path", str(path),
                              "--build-env", args.build_env], path)
            if code != 0 or not (path / "lcov.info").exists():
                print(text[-4000:], file=sys.stderr)
                fail(f"{pkg}: `sui move coverage lcov` failed")
            lcov[pkg] = parse_lcov((path / "lcov.info").read_text())

            code, text = run([sui, "move", "coverage", "summary", "--path", str(path),
                              "--build-env", args.build_env, "--csv"], path)
            if code != 0 or "ModuleName," not in text:
                print(text[-4000:], file=sys.stderr)
                fail(f"{pkg}: `sui move coverage summary` failed")
            csvs[pkg] = text[text.find("ModuleName,"):]
            (out_dir / f"{pkg}.bytecode.csv").write_text(csvs[pkg])

            # The test build's source maps, restricted to this package's sources/.
            sources = f"{path}/sources/"
            for debug_json in (path / "build").glob("*/debug_info/*.json"):
                src, *info = source_map(debug_json)
                if src.startswith(sources):
                    maps[f"packages/{pkg}/sources/{src[len(sources):]}"] = (src, *info)

        summary, own_files, combined_files = {}, {}, {}
        for pkg in args.packages:
            test_only = {pathlib.Path(rel).stem: m[2] for rel, m in maps.items()}
            bytecode = parse_bytecode_csv(csvs[pkg], test_only)
            rows = {}
            for rel in sorted(r for r in maps if r.startswith(f"packages/{pkg}/")):
                src, executable, fn_test_only, skipped = maps[rel]
                own = restrict(lcov[pkg].get(src, new_record()), executable, fn_test_only, skipped)
                comb = merge(restrict(lcov[p].get(src, new_record()), executable, fn_test_only, skipped)
                             for p in PACKAGES)
                fns = comb["fn"]
                covered_own = {ln for ln, h in own["da"].items() if h}
                covered_comb = {ln for ln, h in comb["da"].items() if h}
                rows[rel] = {
                    "lines_own": (len(covered_own), len(executable)),
                    "lines_combined": (len(covered_comb), len(executable)),
                    "functions_own": (sum(1 for n in fns if own["fnda"].get(n)), len(fns)),
                    "functions_combined": (sum(1 for n in fns if comb["fnda"].get(n)), len(fns)),
                    "branches_own": (hit_count(own["brda"])[0], len(comb["brda"])),
                    "branches_combined": hit_count(comb["brda"]),
                    "bytecode_own": bytecode.get(pathlib.Path(rel).stem, (0, 0)),
                    "uncovered_lines": sorted(executable - covered_comb),
                    "uncovered_functions": sorted((n for n in fns if not comb["fnda"].get(n)), key=fns.get),
                }
                own_files[rel] = (own, executable)
                combined_files[rel] = (comb, executable)
            summary[pkg] = {"total": report_package(pkg, rows, args.uncovered), "files": rows}
            write_lcov({r: v for r, v in own_files.items() if r.startswith(f"packages/{pkg}/")},
                       out_dir / f"{pkg}.lcov.info")

        write_lcov(combined_files, out_dir / "lcov.info")
        (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        if shutil.which("genhtml"):
            out = subprocess.run(["genhtml", "--quiet", "--branch-coverage", "-o", str(out_dir / "html"),
                                  str(out_dir / "lcov.info")], cwd=ROOT, capture_output=True, text=True)
            print(f"\nhtml report: {out_dir / 'html/index.html'}" if out.returncode == 0
                  else (out.stdout + out.stderr)[-2000:])
        print(f"\nreports written to {out_dir}")
    finally:
        if args.keep:
            print(f"scratch build kept at {scratch}")
        else:
            shutil.rmtree(scratch, ignore_errors=True)

    if args.min is not None:
        low = [(p, pct(s["total"]["lines_combined"])) for p, s in summary.items()
               if pct(s["total"]["lines_combined"]) < args.min]
        for p, v in low:
            print(f"FAIL: {p} combined line coverage {v:.1f}% < {args.min}%", file=sys.stderr)
        if low:
            sys.exit(1)


if __name__ == "__main__":
    main()
