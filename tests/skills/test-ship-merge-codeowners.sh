#!/usr/bin/env bash
# Regression test for the CODEOWNER check: the shared
# hooks/gates/lib/_codeowners_match.py (evaluate() + discover()) and
# skills/workflow/ship-merge/SKILL.md's Phase 1 step 7 wiring around it (moved from
# commands/ship-merge/COMMAND.md 2026-08-25, #103, commands→skills spec #101).
#
# MIGRATED 2026-08-15: the matcher and discovery loop used to be embedded
# in ship-merge.md's markdown and extracted via regex here. A
# mh:plan-reviewer pass on a plan to add CODEOWNERS awareness to
# hooks/gates/convergence-merge-gate.sh (needs-revision, High #2) flagged
# that leaving the discovery loop unshared -- reimplemented independently
# in the hook -- repeated the exact "same logic in 2+ files, no
# machine-check" pattern this repo has already been bitten by. Both the
# matcher and the discovery loop are now in _codeowners_match.py, imported
# directly here (no markdown-regex extraction needed for those), plus one
# small end-to-end check that ship-merge.md's own bash wiring around
# --discover's exit codes still does the right thing.
#
# Original build (a4204e1) claimed "verified against 16 fixture cases" --
# true when written, not reproducible; a later deep-audit pass (cdd3cbd)
# found and fixed 3 real bugs by executing the shipped logic, not just
# reading it, and built this file. That history is why every case below
# still exists even after the file's physical shape changed.
#
# Run standalone: bash tests/skills/test-ship-merge-codeowners.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHIP_MERGE_MD="$ROOT/skills/workflow/ship-merge/SKILL.md"
CM_LIB="$ROOT/hooks/gates/lib"

pass=0
fail=0

assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || true' EXIT

python3 -c "import ast; ast.parse(open('$CM_LIB/_codeowners_match.py').read())" 2>/dev/null
assert "_codeowners_match.py is syntactically valid python" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

# === Part 1: evaluate() -- matching engine + review-decision + owner-shape fixtures ===
run_matcher_suite() {
python3 - "$CM_LIB" <<'PYEOF'
import sys, json
sys.path.insert(0, sys.argv[1])
import _codeowners_match as cm

HEAD = "deadbeef"
STALE = "stale123"

cases = [
    ("exact path match, approved -> PASS", 'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("exact path match, not approved -> STOP", 'src/a.py @alice', ['src/a.py'], [], "STOP"),
    ("wildcard matches any depth", '*.md @bob', ['docs/deep/x.md'],
     [{"author":{"login":"bob"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("root-anchored directory pattern matches", '/docs/ @carol', ['docs/x.md'],
     [{"author":{"login":"carol"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("root-anchored directory does not match elsewhere", '/docs/ @carol', ['other/docs/x.md'], [], "PASS"),
    ("unanchored directory pattern matches at any depth", 'apps/ @dave', ['x/apps/y.py'],
     [{"author":{"login":"dave"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("single-level pattern does NOT match a nested file", 'docs/* @erin', ['docs/sub/deep.md'], [], "PASS"),
    ("single-level pattern matches a direct child", 'docs/* @erin', ['docs/deep.md'],
     [{"author":{"login":"erin"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("recursive globstar matches zero intervening segments", 'db/**/index.md @frank', ['db/index.md'],
     [{"author":{"login":"frank"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("recursive globstar matches one intervening segment", 'db/**/index.md @frank', ['db/sub/index.md'],
     [{"author":{"login":"frank"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("last-matching-line wins", '*.py @old\n*.py @new', ['a.py'],
     [{"author":{"login":"new"},"state":"APPROVED","commit":{"oid":HEAD}}], "PASS"),
    ("unparseable [bracket] pattern fails the whole check closed", '[abc].py @g', ['x.py'], [], "STOP"),
    ("@org/team owner defers instead of permanent STOP", '*.py @org/team', ['a.py'], [], "DEFERRED"),
    ("no owned files among changed files -> PASS", '*.md @h', ['src/a.py'], [], "PASS"),
    ("empty CODEOWNERS content parses to zero rules -> PASS", '', ['src/a.py'], [], "PASS"),
    ("comment-only CODEOWNERS content -> PASS", '# just a comment', ['src/a.py'], [], "PASS"),
    ("BUG FIX: a COMMENTED review after APPROVED must not revoke it",
     'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":HEAD}},
      {"author":{"login":"alice"},"state":"COMMENTED","commit":{"oid":HEAD}}],
     "PASS"),
    ("BUG FIX: a bare email-address owner defers instead of permanent STOP",
     'src/a.py docs@example.com', ['src/a.py'], [], "DEFERRED"),
    ("CHANGES_REQUESTED after an earlier APPROVED still blocks (decision states still override)",
     'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":HEAD}},
      {"author":{"login":"alice"},"state":"CHANGES_REQUESTED","commit":{"oid":HEAD}}],
     "STOP"),
    ("BUG FIX (#50): approval pinned to a stale SHA does not count -> STOP",
     'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":STALE}}],
     "STOP"),
    ("SANITY (not a #50 regression pin -- passes identically pre-fix, since a stale entry never outranks a fresh APPROVED under either dict-overwrite or SHA-filtered semantics): the SHA filter doesn't wrongly drop a fresh entry sitting next to a stale one -> PASS",
     'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":STALE}},
      {"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":HEAD}}],
     "PASS"),
    ("BUG FIX (#50): a review missing commit info entirely does not count -> STOP",
     'src/a.py @alice', ['src/a.py'],
     [{"author":{"login":"alice"},"state":"APPROVED"}],
     "STOP"),
]

fails = []
for desc, codeowners, changed, reviews, expected in cases:
    verdict, reason, detail = cm.evaluate(codeowners, changed, reviews, HEAD)
    ok = verdict == expected
    print("%s|%s (expected %s, got %s)" % ("1" if ok else "0", desc, expected, verdict))
    if not ok:
        fails.append(desc)
sys.exit(1 if fails else 0)
PYEOF
}
while IFS='|' read -r ok desc; do
  assert "$desc" "$ok"
done < <(run_matcher_suite)

# === Part 1b: evaluate() -- stale-approval detail-text regression ===
# 2026-08-15 deep-audit follow-up: the note guard that distinguishes "never
# reviewed" from "approved an earlier commit" only fires when the owner has
# NO current-head decision at all. Part 1's cases list above only asserts on
# verdict, never on detail-line text, so a broken guard here (note showing on
# a CHANGES_REQUESTED-on-head block, or missing on a genuine stale-only
# block) changes the message but not the STOP verdict -- invisible to Part 1.
run_detail_text_suite() {
python3 - "$CM_LIB" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import _codeowners_match as cm

HEAD, STALE = "deadbeef", "stale123"
NOTE = "approved an earlier commit"

detail_cases = [
    ("stale-only approval -> detail line carries the stale-approval note",
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":STALE}}],
     True),
    ("never reviewed at all -> detail line has no stale-approval note",
     [],
     False),
    ("CHANGES_REQUESTED on current head + an old stale APPROVED -> no stale-approval note (the real blocker is the current decision, not staleness)",
     [{"author":{"login":"alice"},"state":"APPROVED","commit":{"oid":STALE}},
      {"author":{"login":"alice"},"state":"CHANGES_REQUESTED","commit":{"oid":HEAD}}],
     False),
]

fails = []
for desc, reviews, expect_note in detail_cases:
    verdict, reason, detail = cm.evaluate('src/a.py @alice', ['src/a.py'], reviews, HEAD)
    has_note = any(NOTE in line for line in detail)
    ok = verdict == "STOP" and has_note == expect_note
    print("%s|%s (expected note=%s, got note=%s)" % ("1" if ok else "0", desc, expect_note, has_note))
    if not ok:
        fails.append(desc)
sys.exit(1 if fails else 0)
PYEOF
}
while IFS='|' read -r ok desc; do
  assert "$desc" "$ok"
done < <(run_detail_text_suite)

# === Part 2: discover() -- discovery-loop fixtures, no shelling out ===
run_discover_suite() {
python3 - "$CM_LIB" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import _codeowners_match as cm

def check(desc, run_gh, expected):
    got = cm.discover(run_gh)
    ok = got == expected
    print("%s|%s (expected %s, got %s)" % ("1" if ok else "0", desc, expected, got))
    return ok

fails = []

if not check(
    "found at first path with content",
    lambda p: (0, 'src/a.py @alice', '') if p == '.github/CODEOWNERS' else (1, '', 'gh: Not Found (HTTP 404)'),
    ('src/a.py @alice', True, ''),
):
    fails.append(1)

calls = []
def gh_empty_first(p):
    calls.append(p)
    if p == '.github/CODEOWNERS':
        return (0, '', '')
    return (0, 'src/a.py @alice', '')  # would be found if the bug incorrectly continued past .github

ok = check("BUG FIX: found-but-empty at first path short-circuits (does not try root)",
           gh_empty_first, ('', True, ''))
ok = ok and calls == ['.github/CODEOWNERS']
print("%s|discover() tried exactly 1 path for the found-but-empty case, tried: %s" % ("1" if calls == ['.github/CODEOWNERS'] else "0", calls))
if not ok:
    fails.append(2)

if not check("all three paths 404 -> verified absent", lambda p: (1, '', 'gh: Not Found (HTTP 404)'), ('', False, '')):
    fails.append(3)

calls2 = []
def gh_error(p):
    calls2.append(p)
    return (1, '', 'gh: authentication required')
ok = check("non-404 fetch error fails closed", gh_error, ('', False, 'gh: authentication required'))
print("%s|non-404 error stops after 1 path, tried: %s" % ("1" if calls2 == ['.github/CODEOWNERS'] else "0", calls2))
if not (ok and calls2 == ['.github/CODEOWNERS']):
    fails.append(4)

if not check(
    "falls through 404s to the third path",
    lambda p: (0, 'x @z', '') if p == 'docs/CODEOWNERS' else (1, '', 'gh: Not Found (HTTP 404)'),
    ('x @z', True, ''),
):
    fails.append(5)

sys.exit(1 if fails else 0)
PYEOF
}
while IFS='|' read -r ok desc; do
  assert "$desc" "$ok"
done < <(run_discover_suite)

# === Part 3: end-to-end -- ship-merge.md's own bash wiring around --discover's exit codes ===
python3 - "$SHIP_MERGE_MD" "$WORK/discovery.sh" <<'EXTRACT'
import re, sys, textwrap
content = open(sys.argv[1]).read()
blocks = re.findall(r"```bash\n(.*?)\n   ```", content, re.S)
loop = next((b for b in blocks if "DISCOVER_RC" in b), None)
if not loop:
    sys.exit("could not locate ship-merge.md's discovery wiring block")
open(sys.argv[2], "w").write(textwrap.dedent(loop))
EXTRACT
if [[ -s "$WORK/discovery.sh" ]]; then
  bash -n "$WORK/discovery.sh" 2>/dev/null
  assert "extracted ship-merge.md discovery wiring is syntactically valid bash" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

  mkdir -p "$WORK/fakebin"
  run_wiring() {
    # $1: fake gh script body
    printf '%s' "$1" > "$WORK/fakebin/gh"
    chmod +x "$WORK/fakebin/gh"
    sed "s|\${MH_PLUGIN_ROOT}|$ROOT|; s|\"<head_sha>\"|abc123|" "$WORK/discovery.sh" > "$WORK/discovery-runnable.sh"
    PATH="$WORK/fakebin:$PATH" bash -c "$(cat "$WORK/discovery-runnable.sh"); echo FOUND=\$CODEOWNERS_FOUND CONTENT=[\$CODEOWNERS_CONTENT] ERROR=[\$CODEOWNERS_ERROR]"
  }

  out=$(run_wiring '#!/bin/bash
if [[ "$*" == *"contents/.github/CODEOWNERS"* ]]; then exit 0; fi
echo "gh: Not Found (HTTP 404)" >&2; exit 1')
  assert "e2e: found-but-empty -> FOUND=1, empty content, no error ($out)" \
    "$([[ "$out" == *"FOUND=1"* && "$out" == *"CONTENT=[]"* && "$out" == *"ERROR=[]"* ]] && echo 1 || echo 0)"

  out=$(run_wiring '#!/bin/bash
echo "gh: Not Found (HTTP 404)" >&2; exit 1')
  assert "e2e: all-404 -> FOUND=0, no error (N/A) ($out)" \
    "$([[ "$out" == *"FOUND=0"* && "$out" == *"ERROR=[]"* ]] && echo 1 || echo 0)"

  out=$(run_wiring '#!/bin/bash
echo "gh: authentication required" >&2; exit 1')
  assert "e2e: fetch error -> FOUND=0, error captured ($out)" \
    "$([[ "$out" == *"FOUND=0"* && "$out" == *"ERROR=[gh: authentication required]"* ]] && echo 1 || echo 0)"
else
  assert "extracted ship-merge.md discovery wiring block" 0
fi

echo ""
total_t=$((pass + fail))
echo "=== $pass/$total_t passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
