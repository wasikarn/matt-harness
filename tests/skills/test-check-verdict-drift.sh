#!/usr/bin/env bash
# test-check-verdict-drift.sh — the three check-verdict.py scripts (idea-audit, deep-audit,
# compliance-audit) each keep their own copy of mask_json_spans, extract_object and
# extract_valid_candidates, and compliance-audit's and deep-audit's CITATION_RE are hand copies of
# idea-audit's check-citations.py one (it drifted once: 2026-09-20; deep-audit lacked it: #392). They stay copies on purpose (a cross-skill
# import would couple the skills' install layouts), so this fails when one copy's code diverges.
# Compared as AST with the docstring dropped: comments and docstrings may differ, code may not.
# The checker is run on planted edits too, so it cannot pass by comparing nothing.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."

echo "=== check-verdict.py copies have not drifted ==="
python3 - "$ROOT" <<'PY'
import ast, sys

ROOT = sys.argv[1]
VERDICTS = ["skills/workflow/idea-audit/scripts/check-verdict.py",
            "skills/review/deep-audit/scripts/check-verdict.py",
            "skills/review/compliance-audit/scripts/check-verdict.py"]
CITATIONS = "skills/workflow/idea-audit/scripts/check-citations.py"
CITATION_COPIES = (VERDICTS[1], VERDICTS[2])
FUNCS = ("mask_json_spans", "extract_object", "extract_valid_candidates")
passed = failed = 0


def check(desc, ok):
    global passed, failed
    if ok:
        passed += 1
        print("  PASS: " + desc)
    else:
        failed += 1
        print("  FAIL: " + desc, file=sys.stderr)


def defs(src):
    out = {}
    for n in ast.parse(src).body:
        if isinstance(n, ast.FunctionDef) and n.name in FUNCS:
            b = n.body
            if b and isinstance(b[0], ast.Expr) and isinstance(b[0].value, ast.Constant) \
                    and isinstance(b[0].value.value, str):
                n.body = b[1:]
            out[n.name] = ast.dump(n)
        elif isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "CITATION_RE" for t in n.targets):
            out["CITATION_RE"] = ast.dump(n.value)
    return out


def drift(srcs):
    d = [defs(srcs[p]) for p in VERDICTS]
    bad = []
    for f in FUNCS:
        vals = [x.get(f) for x in d]
        if None in vals or len(set(vals)) != 1:
            bad.append(f)
    c = defs(srcs[CITATIONS]).get("CITATION_RE")
    if c is None or any(c != defs(srcs[p]).get("CITATION_RE") for p in CITATION_COPIES):
        bad.append("CITATION_RE")
    return bad


srcs = {}
for p in VERDICTS + [CITATIONS]:
    with open(ROOT + "/" + p, encoding="utf-8") as fh:
        srcs[p] = fh.read()

real = drift(srcs)
check("the copies match: " + (", ".join(real) or "no drift"), not real)


def segment(src, name):
    for n in ast.parse(src).body:
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return n
    return None


def plant(path, name, how):
    """A copy of srcs with one edit in one function of one file, or None if the edit can't land."""
    lines = srcs[path].splitlines(True)
    fn = segment(srcs[path], name)
    if fn is None:
        return None
    if how == "op":  # first `i + 1` in the function body -> `i + 2`
        for k in range(fn.body[0].lineno - 1, fn.end_lineno):
            if "i + 1" in lines[k]:
                lines[k] = lines[k].replace("i + 1", "i + 2", 1)
                break
        else:
            return None
    else:  # one extra statement at the end of the body
        lines.insert(fn.end_lineno, " " * fn.body[-1].col_offset + "pass\n")
    out = dict(srcs)
    out[path] = "".join(lines)
    return out


probes = 0
for path in VERDICTS:
    for name in FUNCS:
        for how in ("op", "stmt"):
            m = plant(path, name, how)
            if m is None:
                check("planted %s edit lands in %s:%s" % (how, path, name), False)
                continue
            probes += 1
            check("planted %s edit in %s:%s is caught" % (how, path.split("/")[2], name), name in drift(m))

for path in (CITATIONS,) + CITATION_COPIES:
    m = dict(srcs)
    lines = srcs[path].splitlines(True)
    landed = False
    for k, line in enumerate(lines):
        if line.startswith("CITATION_RE = ") and "[A-Za-z]" in line:
            lines[k] = line.replace("[A-Za-z]", "[A-Z]", 1)
            landed = True
            break
    m[path] = "".join(lines)
    probes += landed
    check("planted CITATION_RE edit in %s is caught" % path,landed and "CITATION_RE" in drift(m))

for path in CITATION_COPIES:
    m = dict(srcs)
    m[path] = m[path].replace("CITATION_RE = ", "CITATION_RX = ", 1)
    check("a renamed-away CITATION_RE copy in %s is caught" % path.split("/")[2], "CITATION_RE" in drift(m))

check("%d planted edits ran (not vacuous)" % probes, probes == 3 * 3 * 2 + 1 + len(CITATION_COPIES))
print("=== Summary: %d passed, %d failed ===" % (passed, failed))
sys.exit(1 if failed else 0)
PY
