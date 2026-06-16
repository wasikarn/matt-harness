#!/bin/bash
# cleanup-bak-ttl — SessionStart TTL gate for stale *.bak residue in ~/.claude/.
#
# Background: G13 in the post-cutover deep-verify ledger flagged 3 pre-cutover
# .bak files (May 14/20/30) as housekeeping residue. Housekeeping has since
# cleared them, but the drift class is real — editors and ad-hoc `cp foo
# foo.bak` operations accumulate .bak over time. This hook fires on
# SessionStart and reports any .bak older than CLEANUP_BAK_TTL_DAYS (default
# 90) in the trust scopes most likely to collect residue.
#
# Behavior: detect-only by default — print a structured <bak-ttl-report> block
# listing stale files. NEVER trashs automatically (deny-blocked; rm -rf
# is refuse-everywhere; trash needs explicit per-file intent per
# feedback_use_trash_not_rm). The agent sees the report and decides per-file
# whether to `trash` or keep.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=cleanup-bak-ttl
#   export CLAUDE_BAK_TTL_PROFILE=off
#
# Failure mode: silent. Always exit 0; never block SessionStart.
#
# Trust scopes (deliberately narrow — see F11 in harness-audit audit.sh
# for the .bak skip rationale, and feedback_sibling_pattern_drift_post_cutover
# for the live test-fixture gotcha):
#   - ~/.claude/                        (user-scope; cutover residue)
#   - ~/.claude/plugins/cache/kobig/    (plugin cache; pre-cutover snapshots)
#
# Explicitly NOT scanned (would false-positive on live test fixtures):
#   - ~/.claude/plugins/cache/kobig/kbg/0.1.*/hooks/hooks.json.test.bak
#     (referenced by audit.sh:178,370; harness-audit F11 skip pattern)
#   - ~/kbg-cutover-backups/           (intentional snapshot dir)
#   - ~/.Trash/                         (trash bin, already recoverable)
#   - any path under harness-audit-managed test fixtures

HOOK_ID="cleanup-bak-ttl"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# Configurable TTL; 0 disables the check.
TTL_DAYS="${CLAUDE_BAK_TTL_DAYS:-90}"
if [ "$TTL_DAYS" -le 0 ] 2>/dev/null; then
  exit 0
fi

# Profile knob (distinct from CLAUDE_HOOK_PROFILE which gates the whole hook).
if [ "${CLAUDE_BAK_TTL_PROFILE:-standard}" = "off" ]; then
  exit 0
fi

# Find stale .bak in trust scopes. BSD find on macOS supports -mtime +N
# ("more than N days"), which matches the TTL semantics.
NOW=$(date +%s)
CUTOFF_SECONDS=$((TTL_DAYS * 86400))

# Temp file for the stale-list (use mktemp so parallel sessions don't collide;
# -t uses $TMPDIR which is per-user on macOS). Plain find loop below writes
# one TSV line per stale file; awk sorts + formats at emit time.
STALE_FILE=$(mktemp -t bak-ttl-XXXXXX.tsv) || exit 0
trap 'rm -f "$STALE_FILE"' EXIT

# Allowlist of path patterns that are TEST FIXTURES or INTENTIONAL SNAPSHOTS
# and must NOT trigger the report. (Glob anchored on the file basename
# because the test fixtures are regenerated every plugin cache rebuild and
# the snapshot dir is owned by the cutover ritual, not residue.)
FIXTURE_PATTERNS='hooks.json.test.bak|install.sh.bak|settings.json.test.bak'

# Build a newline-delimited list of stale files. Suppress find errors
# (e.g. cache dir missing before plugin is enabled) — empty list is fine.
# One find pass over the broadest scope; per-file filtering below.
# This avoids the overlap bug where scanning both ~/.claude and
# ~/.claude/plugins/cache/kobig reports the same file twice.
SCAN_ROOT="$HOME/.claude"
[ -d "$SCAN_ROOT" ] || exit 0

# -L follows symlinks (the plugin cache is real files, but harmless to
# follow). -mtime +N is BSD/GNU portable for "more than N days old".
# Convert TTL_DAYS to mtime arg: +N requires strict-greater, so subtract 1
# to make TTL_DAYS=90 catch exactly files older than 90 days.
# Actually +N is strict, so we want find's own cutoff, but mtime uses
# 24h-aligned days and we want second-precision. So do the comparison
# in awk after the find.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base=$(basename "$f")
  # bash case with literal "|" doesn't work for regex alternation (case uses
  # shell glob patterns, not regex). Use bash regex match instead.
  if [[ "$base" =~ ^($FIXTURE_PATTERNS)$ ]]; then
    continue  # live test fixture
  fi
  if [ "$(uname -s)" = "Darwin" ]; then
    MTIME=$(stat -f %m "$f" 2>/dev/null) || continue
  else
    MTIME=$(stat -c %Y "$f" 2>/dev/null) || continue
  fi
  AGE=$((NOW - MTIME))
  if [ "$AGE" -gt "$CUTOFF_SECONDS" ]; then
    AGE_DAYS=$((AGE / 86400))
    SIZE=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null)
    printf '%s\t%s\t%s\n' "$AGE_DAYS" "$SIZE" "$f" >> "$STALE_FILE"
  fi
done < <(find -L "$SCAN_ROOT" -name "*.bak" -type f 2>/dev/null)

# Nothing stale — silent. No additionalContext injection, no log entry.
[ ! -s "$STALE_FILE" ] && { rm -f "$STALE_FILE"; exit 0; }

# Stale entries exist — emit a structured report block Claude Code will
# inject as additionalContext. Sort by age descending (oldest first = most
# urgent to triage). Print to stdout (not stderr) per Claude Code spec.
COUNT=$(wc -l < "$STALE_FILE" | tr -d ' ')
printf '<bak-ttl-report ttl-days="%d" count="%d">\n' "$TTL_DAYS" "$COUNT"
printf 'Stale *.bak files in ~/.claude/ (older than %d days). Each is a housekeeping candidate.\n' "$TTL_DAYS"
printf 'Run `trash <path>` per file to remove; current sources must be verified first (per verify-before-asserting).\n'
printf 'Bypass: export CLAUDE_DISABLED_HOOKS=cleanup-bak-ttl or CLAUDE_BAK_TTL_PROFILE=off.\n'
sort -t$'\t' -k1,1 -nr "$STALE_FILE" | \
  awk -F'\t' '{ printf "- %s (%s days, %s bytes)\n", $3, $1, $2 }'
printf '</bak-ttl-report>\n'

rm -f "$STALE_FILE"
exit 0
