#!/usr/bin/env bash
# Regression test for commands/ship-merge.md's Phase 1 step 7 CODEOWNER check:
# the CODEOWNERS-discovery bash loop and the embedded python3 matcher/approval
# script. Extracts both the same way a user's shell would run them, no mocking
# of the matching logic itself.
#
# Built by a deep-audit pass (2026-08-15) that found this matcher had NEVER had
# a persisted test — only ephemeral /tmp fixture runs during the original build
# (a4204e1) and a compliance-audit's live spot-checks (dce81fe/60f368e, a
# different command). "Verified against 16 fixture cases" in a4204e1's own
# commit message was true when written; it just wasn't reproducible. This file
# makes it reproducible, and pins 3 real bugs the same audit found by executing
# (not just reading) the shipped logic:
#   1. The discovery loop judged "found" by non-empty stdout, not gh api's exit
#      code -- an existing-but-EMPTY .github/CODEOWNERS short-circuited after
#      one path with both CODEOWNERS_CONTENT and CODEOWNERS_ERROR empty, which
#      the file's own prose then read as "all three genuinely 404'd" -- true
#      only by coincidence, not by anything the code actually checked. Fixed to
#      branch on the real exit status.
#   2. latest_by_author tracked every review state including COMMENTED, so an
#      ordinary "approve, then leave a follow-up comment" sequence overwrote
#      APPROVED and produced a false STOP. GitHub's own review-decision model
#      only treats APPROVED/CHANGES_REQUESTED/DISMISSED as state-changing.
#   3. A bare email-address owner (GitHub CODEOWNERS syntax; no "@" prefix) had
#      no DEFERRED path -- it fell into the @username branch, could never
#      appear in the reviews API's login set, and permanently STOPped. Same
#      class of bug plan-reviewer already caught for @org/team before shipping;
#      this one used a narrower detection check that missed the email shape.
#
# Run standalone: bash tests/commands/test-ship-merge-codeowners.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHIP_MERGE_MD="$ROOT/commands/ship-merge.md"

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
trap 'rm -rf "$WORK"' EXIT

# --- Extract the embedded python3 matcher (the block invoked as
#     `python3 -c '...' "$CODEOWNERS_CONTENT" "$CHANGED_FILES" "$REVIEWS_JSON"`) ---
python3 - "$SHIP_MERGE_MD" "$WORK/matcher.py" <<'EXTRACT'
import re, sys
content = open(sys.argv[1]).read()
m = re.search(r"python3 -c '\n(.*?)\n' \"\$CODEOWNERS_CONTENT\"", content, re.S)
if not m:
    sys.exit("could not locate the embedded CODEOWNERS matcher block")
open(sys.argv[2], "w").write(m.group(1))
EXTRACT
if [[ ! -s "$WORK/matcher.py" ]]; then
  assert "extracted the embedded CODEOWNERS matcher script" 0
  echo "=== 0/1 passed (extraction failed, cannot run any fixture) ===" >&2
  exit 1
fi
python3 -c "import ast; ast.parse(open('$WORK/matcher.py').read())" 2>/dev/null
assert "extracted matcher is syntactically valid python" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

run_matcher() {
  # args: codeowners_text changed_files_text reviews_json
  python3 -c "$(cat "$WORK/matcher.py")" "$1" "$2" "$3" 2>/dev/null
}

check_verdict() {
  local desc="$1" codeowners="$2" changed="$3" reviews="$4" expected="$5"
  local out first_line
  out=$(run_matcher "$codeowners" "$changed" "$reviews")
  first_line=$(printf '%s\n' "$out" | head -1)
  assert "$desc (expected $expected, got '${first_line:-<empty>}')" "$([[ "$first_line" == "$expected" ]] && echo 1 || echo 0)"
}

# --- Core matching-engine fixtures (the 16 cases verified ephemerally at build time) ---
check_verdict "exact path match, approved -> PASS" \
  'src/a.py @alice' 'src/a.py' '[{"author":{"login":"alice"},"state":"APPROVED"}]' PASS
check_verdict "exact path match, not approved -> STOP" \
  'src/a.py @alice' 'src/a.py' '[]' STOP
check_verdict "wildcard matches any depth" \
  '*.md @bob' 'docs/deep/x.md' '[{"author":{"login":"bob"},"state":"APPROVED"}]' PASS
check_verdict "root-anchored directory pattern matches" \
  '/docs/ @carol' 'docs/x.md' '[{"author":{"login":"carol"},"state":"APPROVED"}]' PASS
check_verdict "root-anchored directory does not match elsewhere" \
  '/docs/ @carol' 'other/docs/x.md' '[]' PASS
check_verdict "unanchored directory pattern matches at any depth" \
  'apps/ @dave' 'x/apps/y.py' '[{"author":{"login":"dave"},"state":"APPROVED"}]' PASS
check_verdict "single-level pattern does NOT match a nested file" \
  'docs/* @erin' 'docs/sub/deep.md' '[]' PASS
check_verdict "single-level pattern matches a direct child" \
  'docs/* @erin' 'docs/deep.md' '[{"author":{"login":"erin"},"state":"APPROVED"}]' PASS
check_verdict "recursive globstar matches zero intervening segments" \
  'db/**/index.md @frank' 'db/index.md' '[{"author":{"login":"frank"},"state":"APPROVED"}]' PASS
check_verdict "recursive globstar matches one intervening segment" \
  'db/**/index.md @frank' 'db/sub/index.md' '[{"author":{"login":"frank"},"state":"APPROVED"}]' PASS
check_verdict "last-matching-line wins" \
  '*.py @old
*.py @new' 'a.py' '[{"author":{"login":"new"},"state":"APPROVED"}]' PASS
check_verdict "unparseable [bracket] pattern fails the whole check closed" \
  '[abc].py @g' 'x.py' '[]' STOP
check_verdict "@org/team owner defers instead of permanent STOP" \
  '*.py @org/team' 'a.py' '[]' DEFERRED
check_verdict "no owned files among changed files -> PASS" \
  '*.md @h' 'src/a.py' '[]' PASS
check_verdict "empty CODEOWNERS content parses to zero rules -> PASS" \
  '' 'src/a.py' '[]' PASS
check_verdict "comment-only CODEOWNERS content -> PASS" \
  '# just a comment' 'src/a.py' '[]' PASS

# --- Regressions for the 3 bugs this audit found and fixed ---
check_verdict "BUG FIX: a COMMENTED review after APPROVED must not revoke it" \
  'src/a.py @alice' 'src/a.py' \
  '[{"author":{"login":"alice"},"state":"APPROVED"},{"author":{"login":"alice"},"state":"COMMENTED"}]' \
  PASS
check_verdict "BUG FIX: a bare email-address owner defers instead of permanent STOP" \
  'src/a.py docs@example.com' 'src/a.py' '[]' DEFERRED
check_verdict "CHANGES_REQUESTED after an earlier APPROVED still blocks (decision states still override)" \
  'src/a.py @alice' 'src/a.py' \
  '[{"author":{"login":"alice"},"state":"APPROVED"},{"author":{"login":"alice"},"state":"CHANGES_REQUESTED"}]' \
  STOP

# --- Discovery-loop fixture: found-but-empty must not be mislabeled as absent ---
# Stubs gh api: .github/CODEOWNERS exists but is empty (exit 0, empty stdout);
# root CODEOWNERS (never reached once .github/CODEOWNERS is found, matching
# GitHub's own first-found-wins search order) carries a real rule.
python3 - "$SHIP_MERGE_MD" "$WORK/discovery.sh" <<'EXTRACT'
import re, sys, textwrap
content = open(sys.argv[1]).read()
blocks = re.findall(r"```bash\n(.*?)\n   ```", content, re.S)
loop = next((b for b in blocks if "CODEOWNERS_FOUND" in b), None)
if not loop:
    sys.exit("could not locate the CODEOWNERS discovery loop block")
open(sys.argv[2], "w").write(textwrap.dedent(loop))
EXTRACT
if [[ -s "$WORK/discovery.sh" ]]; then
  bash -n "$WORK/discovery.sh" 2>/dev/null
  assert "extracted discovery loop is syntactically valid bash" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

  run_discovery() {
    ( gh() {
        local args="$*"
        if [[ "$args" == *".github/CODEOWNERS?ref="* ]]; then
          return 0  # found, empty body (gh api succeeded, empty stdout)
        elif [[ "$args" == *"contents/CODEOWNERS?ref="* ]]; then
          echo "src/a.py @alice"; return 0  # never reached if the bug is fixed
        elif [[ "$args" == *"docs/CODEOWNERS?ref="* ]]; then
          echo "gh: Not Found (HTTP 404)" >&2; return 1
        fi
        return 1
      }
      export -f gh
      source "$WORK/discovery.sh"
      echo "FOUND=$CODEOWNERS_FOUND CONTENT=[$CODEOWNERS_CONTENT] ERROR=[$CODEOWNERS_ERROR]"
    )
  }

  out=$(run_discovery)
  assert "BUG FIX: found-but-empty .github/CODEOWNERS sets FOUND=1 (not misread as absent) — $out" \
    "$([[ "$out" == *"FOUND=1"* && "$out" == *"CONTENT=[]"* && "$out" == *"ERROR=[]"* ]] && echo 1 || echo 0)"
else
  assert "extracted the CODEOWNERS discovery loop" 0
fi

echo ""
total_t=$((pass + fail))
echo "=== $pass/$total_t passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
