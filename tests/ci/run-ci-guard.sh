#!/usr/bin/env bash
# tests/ci/run-ci-guard.sh — supply-chain guard for the shipped plugin.
# Two invariants, both tied to CLAUDE.md deliberate non-goals:
#
#   (1) Shipped scripts (hooks/, scripts/, skills/, git-hooks/) must not
#       fetch-and-execute remote code at runtime — no `curl ... | sh`,
#       `wget ... | bash`, or `eval "$(curl ...)"`. A plugin whose own scripts
#       pipe a remote payload to a shell is a supply-chain compromise waiting
#       to happen; this static scan catches it before push.
#   (2) .github/workflows/validate.yml stays a CONFORMANCE gate, not a release
#       train (CLAUDE.md: ".github/workflows/validate.yml is a conformance gate,
#       not a release train"). No publish/release/deploy steps may creep in.
#
# Vendored reference thinking-skills (docs/reference/) are excluded — they are
# not shipped runtime scripts. Exit 0 = clean; 1 = supply-chain risk detected.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

# (1) fetch-and-exec scan. grep -r recurses with --include; the pattern requires
# curl/wget piped to a shell OR eval of a curl/wget command substitution, so a
# benign `eval "$cmd"` (fixed literal, run-gauntlet.sh) does NOT match.
fetch_hits=$( /usr/bin/grep -rEn --include='*.sh' --include='*.py' \
  'curl[[:space:]]+[^|]*\|[[:space:]]*(sh|bash)|wget[[:space:]]+[^|]*\|[[:space:]]*(sh|bash)|eval[[:space:]]*"?\$\((curl|wget)' \
  "$ROOT/hooks" "$ROOT/scripts" "$ROOT/skills" "$ROOT/git-hooks" 2>/dev/null \
  | /usr/bin/grep -v '/reference/thinking-skills/' )
if [ -z "$fetch_hits" ]; then
  ok "no fetch-and-exec (curl|sh / wget|bash / eval curl) in shipped scripts"
else
  FAIL=$((FAIL+1))
  printf '  ❌ fetch-and-exec in shipped scripts:\n%s\n' "$fetch_hits"
fi

# (2) CI workflow is a conformance gate only — no publish/release/deploy steps
# (comment lines excluded). "release" is matched broadly to catch release-train
# scaffolding even if worded unusually; a false positive here is a flag to
# justify the step, not a silent pass.
CI="$ROOT/.github/workflows/validate.yml"
if [ ! -f "$CI" ]; then
  no "validate.yml missing (CI conformance gate absent)"
else
  rel=$( /usr/bin/grep -En 'npm publish|git push --tags|git tag|release|deploy|publish' "$CI" 2>/dev/null \
    | /usr/bin/grep -vE '^[[:space:]]*#|^[[:space:]]*name:' )
  if [ -z "$rel" ]; then
    ok "validate.yml is a conformance gate (no release/publish/deploy)"
  else
    FAIL=$((FAIL+1))
    printf '  ❌ validate.yml has release-train step(s):\n%s\n' "$rel"
  fi
fi

echo
echo "SUITE PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] && exit 0 || exit 1