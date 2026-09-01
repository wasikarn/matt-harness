#!/usr/bin/env bash
# 65. every disable-model-invocation: true carrier needs a dedicated CRIT guard (WARN).
# Checks 36/40/45/61/62/64 hardcode one CRIT check per KNOWN carrier — a
# deliberate design (see each of their own headers: matching that precedent
# keeps every check number mapped to exactly one skill). But a hardcoded
# per-skill check doesn't self-extend: a 7th disable-model-invocation
# carrier added after this check was written gets no dedicated guard until a
# human notices and writes the next one by hand — reopening, for that new
# skill, exactly the gap 58-64 originally closed for the 7 carriers that
# existed at audit-write-time (58/60/59/63 were later retired with their
# carrier skills, 2026-09-01 — the guard pattern's own self-extension logic
# below is unaffected: it re-derives the live set every run). Found by the
# 2026-08-30 deep-audit's advisor pass on the checks-58-64 commit itself —
# not hypothetical: this repo added wiki-ingest, idea-scan, and restored
# compliance-audit within the same few weeks.
#
# WARN (not CRIT): this check's job is to surface a coverage GAP in the audit
# system, not to assert the flag is currently missing on a live skill — the
# carrier it flags still has the flag present (that's how it was discovered:
# the frontmatter sweep below only visits `disable-model-invocation: true`
# skills). Check 30 still enforces the reason-presence requirement on it, and
# checks 05/47 still give an incidental (dodgeable-by-padding-the-description)
# backstop in the meantime. Whether to extend the pattern with a real CRIT
# check stays a human call, per CLAUDE.md's own disable-model-invocation
# selection criterion — this check only makes sure that call gets surfaced
# instead of silently missed.
#
# Deterministic, not semantic: this is a pure set-membership comparison (does
# some check file's `_f=` assignment name this exact SKILL.md path?), no LLM
# judgment involved — same discipline CLAUDE.md's Operating model requires of
# every gate (score, not feel). Assumes future dedicated guards keep the
# established `_f="$CLAUDE_DIR/skills/.../SKILL.md"` variable-assignment idiom
# all 6 current ones use; a guard written under a different variable name
# would go undetected by this check specifically (a soft miss on the META
# check, not a reopened safety gap — the underlying dedicated guard would
# still work).
# Guard the checks_dir existence before globbing: an unmatched multi-level
# glob stays literal (nullglob is off by default), so an unguarded grep on
# "$_checks_dir"/*.sh against a missing directory fails, and under this
# script's set -euo pipefail that failure aborts the whole audit mid-run —
# the exact regression class check 25's own comment already documents and
# fixes for its plugin-cache glob. Scoped nullglob (restored immediately)
# covers the case where the directory exists but is empty.
_checks_dir="$CLAUDE_DIR/skills/meta/harness-audit/scripts/checks"
_guarded_paths=""
if [ -d "$_checks_dir" ]; then
  shopt -s nullglob
  _check_files=("$_checks_dir"/*.sh)
  shopt -u nullglob
  if [ "${#_check_files[@]}" -gt 0 ]; then
    _guarded_paths=$(grep -hoE '^_f="\$CLAUDE_DIR/[^"]+"' "${_check_files[@]}" 2>/dev/null \
      | sed -E 's/^_f="\$CLAUDE_DIR\///; s/"$//')
  fi
fi
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  [ "$(fm_get "$f" disable-model-invocation)" = "true" ] || continue
  _rel="${f#"$CLAUDE_DIR"/}"
  if ! printf '%s\n' "$_guarded_paths" | grep -qxF "$_rel"; then
    _nm=$(basename "$(dirname "$f")")
    warn "'$_nm': disable-model-invocation: true with no dedicated CRIT-guard check file referencing '$_rel' — extend the checks-36/40/45/61/62/64 pattern (any of those is the template) so a future silent flag-drop on this skill is caught, not just relying on checks 05/47's dodgeable description-shape backstop"
  fi
done
